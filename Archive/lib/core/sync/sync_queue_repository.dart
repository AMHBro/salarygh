import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'sync_operation.dart';

class SyncQueueRepository {
  final AppDatabase database;

  static const Uuid _uuid = Uuid();

  SyncQueueRepository({
    required this.database,
  });

  // ===========================================================================
  // ENQUEUE
  // ===========================================================================

  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  }) async {
    final now = DateTime.now();

    await database.into(database.syncOutbox).insert(
      SyncOutboxCompanion.insert(
        id: _uuid.v4(),
        entityType: entityType,
        entityId: entityId,
        operation: operation.databaseValue,
        payloadJson: jsonEncode(payload),
        idempotencyKey: idempotencyKey ?? _uuid.v4(),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// يضع زبائن وموردين بلا رقم سيرفر في الطابور حتى تُرفع السندات بعدها.
  Future<int> enqueueUnsyncedParties() async {
    final queued = await (database.select(database.syncOutbox)..where(
      (table) =>
          table.entityType.isIn(['customer', 'supplier']) &
          table.operation.equals('CREATE') &
          table.status.isIn(['PENDING', 'SYNCING', 'FAILED']),
    ))
        .get();
    final blocked = {
      for (final row in queued) '${row.entityType}:${row.entityId}',
    };

    var added = 0;
    final customers = await (database.select(database.customers)
          ..where((table) => table.deletedAt.isNull()))
        .get();
    final suppliers = await (database.select(database.suppliers)
          ..where((table) => table.deletedAt.isNull()))
        .get();

    await database.transaction(() async {
      for (final row in customers) {
        if (!_needsServerId(row.serverId) || _skipPartyName(row.name)) {
          continue;
        }
        if (blocked.contains('customer:${row.id}')) continue;
        await enqueue(
          entityType: 'customer',
          entityId: row.id,
          operation: SyncOperation.create,
          payload: {'id': row.id},
          idempotencyKey: 'customer-create-${row.id}',
        );
        added++;
      }
      for (final row in suppliers) {
        if (!_needsServerId(row.serverId) || _skipPartyName(row.name)) {
          continue;
        }
        if (blocked.contains('supplier:${row.id}')) continue;
        await enqueue(
          entityType: 'supplier',
          entityId: row.id,
          operation: SyncOperation.create,
          payload: {'id': row.id},
          idempotencyKey: 'supplier-create-${row.id}',
        );
        added++;
      }
    });
    return added;
  }

  static bool _needsServerId(String? serverId) =>
      serverId == null || serverId.trim().isEmpty;

  static bool _skipPartyName(String name) {
    final text = name.trim();
    if (text.length < 2) return true;
    const labels = [
      'الإجمالي',
      'الاجمالي',
      'المجموع',
      'الإجمالي الكلي',
      'المجموع الإجمالي',
    ];
    return labels.any((label) => text == label);
  }

  // ===========================================================================
  // PENDING OPERATIONS
  //
  // IMPORTANT:
  //
  // Only PENDING operations are returned.
  //
  // FAILED operations remain stored in the Outbox for diagnosis/manual retry,
  // but they are never automatically POSTed again.
  // ===========================================================================

  Future<List<SyncOutboxData>> getPendingOperations({
    int limit = 50,
    Set<String>? entityTypes,
  }) async {
    await repairLegacyInventoryOutbox();

    await cleanupUnsupportedWarehouseUpdates();

    final query = database.select(
      database.syncOutbox,
    )
      ..where(
            (table) {
          Expression<bool> condition = table.status.equals(
            'PENDING',
          );

          if (entityTypes != null && entityTypes.isNotEmpty) {
            condition = condition &
            table.entityType.isIn(
              entityTypes.toList(),
            );
          }

          return condition;
        },
      )
      ..orderBy([
            (table) => OrderingTerm.asc(
          const CustomExpression<int>(
            "CASE entity_type "
            "WHEN 'customer' THEN 0 "
            "WHEN 'supplier' THEN 1 "
            "WHEN 'product' THEN 2 "
            "WHEN 'warehouse' THEN 2 "
            "ELSE 3 END",
          ),
        ),
            (table) => OrderingTerm.asc(
          table.createdAt,
        ),
      ])
      ..limit(limit);

    return query.get();
  }

  // ===========================================================================
  // FAILED OPERATIONS
  // ===========================================================================

  Future<List<SyncOutboxData>> getFailedOperations({
    int limit = 100,
    Set<String>? entityTypes,
  }) {
    final query = database.select(
      database.syncOutbox,
    )
      ..where(
            (table) {
          Expression<bool> condition = table.status.equals(
            'FAILED',
          );

          if (entityTypes != null && entityTypes.isNotEmpty) {
            condition = condition &
            table.entityType.isIn(
              entityTypes.toList(),
            );
          }

          return condition;
        },
      )
      ..orderBy([
            (table) => OrderingTerm.desc(
          table.updatedAt,
        ),
      ])
      ..limit(limit);

    return query.get();
  }

  // ===========================================================================
  // RETRY ONE FAILED OPERATION
  // ===========================================================================

  Future<void> retryFailedOperation(
      String queueId,
      ) async {
    final current = await (database.select(
      database.syncOutbox,
    )..where(
          (table) => table.id.equals(queueId),
    ))
        .getSingleOrNull();

    if (current == null) {
      throw StateError(
        'عملية المزامنة غير موجودة.',
      );
    }

    if (current.status != 'FAILED') {
      return;
    }

    await (database.update(
      database.syncOutbox,
    )..where(
          (table) => table.id.equals(queueId),
    ))
        .write(
      SyncOutboxCompanion(
        status: const Value(
          'PENDING',
        ),
        lastError: const Value(
          null,
        ),
        updatedAt: Value(
          DateTime.now(),
        ),
      ),
    );

    debugPrint(
      '[SYNC QUEUE] FAILED operation returned to PENDING manually.',
    );

    debugPrint(
      '[SYNC QUEUE] Queue ID: $queueId',
    );
  }

  // ===========================================================================
  // RETRY ALL FAILED OPERATIONS
  // ===========================================================================

  Future<int> retryAllFailedOperations() async {
    final failedRows = await (database.select(
      database.syncOutbox,
    )..where(
          (table) => table.status.equals(
        'FAILED',
      ),
    ))
        .get();

    if (failedRows.isEmpty) {
      return 0;
    }

    final ids = failedRows
        .map(
          (row) => row.id,
    )
        .toList();

    final changed = await (database.update(
      database.syncOutbox,
    )..where(
          (table) => table.id.isIn(ids),
    ))
        .write(
      SyncOutboxCompanion(
        status: const Value(
          'PENDING',
        ),
        lastError: const Value(
          null,
        ),
        updatedAt: Value(
          DateTime.now(),
        ),
      ),
    );

    debugPrint(
      '[SYNC QUEUE] $changed FAILED operation(s) returned to PENDING manually.',
    );

    return changed;
  }

  // ===========================================================================
  // REPAIR LEGACY INVENTORY OUTBOX
  // ===========================================================================

  Future<int> repairLegacyInventoryOutbox() async {
    final rows = await (database.select(
      database.syncOutbox,
    )
      ..where(
            (table) =>
        table.entityType.equals(
          'stock_movement',
        ) &
        (table.status.equals(
          'PENDING',
        ) |
        table.status.equals(
          'FAILED',
        )),
      )
      ..orderBy([
            (table) => OrderingTerm.asc(
          table.createdAt,
        ),
      ]))
        .get();

    if (rows.isEmpty) {
      return 0;
    }

    var repairedCount = 0;

    final processedQueueIds = <String>{};

    for (final queueRow in rows) {
      if (processedQueueIds.contains(queueRow.id)) {
        continue;
      }

      final payload = _decodePayload(
        queueRow.payloadJson,
      );

      final payloadVariantId = _clean(
        payload?['variant_id'],
      );

      final movement = await _getStockMovement(
        queueRow.entityId,
      );

      if (movement == null) {
        debugPrint(
          '[INVENTORY OUTBOX REPAIR] '
              'Movement not found for queue ${queueRow.id}.',
        );

        continue;
      }

      final movementType = movement.type.trim().toUpperCase();

      final isTransfer =
          movementType == 'TRANSFER_OUT' ||
              movementType == 'TRANSFER_IN';

      if (isTransfer) {
        final repaired = await _repairLegacyTransfer(
          queueRow: queueRow,
          movement: movement,
          allQueueRows: rows,
          processedQueueIds: processedQueueIds,
        );

        if (repaired) {
          repairedCount++;
        }

        continue;
      }

      if (payloadVariantId != null) {
        continue;
      }

      final repairedPayload = <String, dynamic>{
        'id': movement.id,
        'variant_id': movement.variantId,
        'warehouse_id': movement.warehouseId,
        'type': movement.type,
        'quantity': movement.quantity,
        'reference_type': _clean(
          movement.referenceType,
        ),
        'reference_id': _clean(
          movement.referenceId,
        ),
        'note': _clean(
          movement.note,
        ),
        'user_id': _clean(
          movement.userId,
        ),
        'version': movement.serverVersion,
        'created_at': movement.createdAt.toUtc().toIso8601String(),
      };

      await (database.update(
        database.syncOutbox,
      )..where(
            (table) => table.id.equals(
          queueRow.id,
        ),
      ))
          .write(
        SyncOutboxCompanion(
          payloadJson: Value(
            jsonEncode(
              repairedPayload,
            ),
          ),
          status: const Value(
            'PENDING',
          ),
          attempts: const Value(
            0,
          ),
          lastError: const Value(
            null,
          ),
          updatedAt: Value(
            DateTime.now(),
          ),
        ),
      );

      processedQueueIds.add(
        queueRow.id,
      );

      repairedCount++;

      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Legacy stock movement repaired.',
      );
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Queue ID: ${queueRow.id}',
      );
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Movement ID: ${movement.id}',
      );
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Variant ID: ${movement.variantId}',
      );
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Warehouse ID: ${movement.warehouseId}',
      );
    }

    if (repairedCount > 0) {
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] '
            '$repairedCount legacy inventory operation(s) repaired.',
      );
    }

    return repairedCount;
  }

  // ===========================================================================
  // REPAIR LEGACY TRANSFER
  // ===========================================================================

  Future<bool> _repairLegacyTransfer({
    required SyncOutboxData queueRow,
    required StockMovement movement,
    required List<SyncOutboxData> allQueueRows,
    required Set<String> processedQueueIds,
  }) async {
    final transferReferenceId = _clean(
      movement.referenceId,
    );

    if (transferReferenceId == null) {
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] '
            'Cannot repair transfer movement without referenceId.',
      );

      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Movement ID: ${movement.id}',
      );

      return false;
    }

    final transferMovements = await (database.select(
      database.stockMovements,
    )..where(
          (table) =>
      table.referenceType.equals(
        'TRANSFER',
      ) &
      table.referenceId.equals(
        transferReferenceId,
      ),
    ))
        .get();

    StockMovement? outMovement;
    StockMovement? inMovement;

    for (final item in transferMovements) {
      final type = item.type.trim().toUpperCase();

      if (type == 'TRANSFER_OUT') {
        outMovement = item;
      }

      if (type == 'TRANSFER_IN') {
        inMovement = item;
      }
    }

    if (outMovement == null || inMovement == null) {
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Incomplete local transfer ledger.',
      );
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Reference ID: $transferReferenceId',
      );

      return false;
    }

    if (outMovement.variantId != inMovement.variantId) {
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Transfer variant mismatch.',
      );
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Reference ID: $transferReferenceId',
      );

      return false;
    }

    if (outMovement.quantity != inMovement.quantity) {
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Transfer quantity mismatch.',
      );
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Reference ID: $transferReferenceId',
      );

      return false;
    }

    final relatedQueueRows = allQueueRows.where(
          (row) {
        return row.entityId == outMovement!.id ||
            row.entityId == inMovement!.id;
      },
    ).toList();

    if (relatedQueueRows.isEmpty) {
      return false;
    }

    relatedQueueRows.sort(
          (a, b) => a.createdAt.compareTo(
        b.createdAt,
      ),
    );

    final primaryQueueRow = relatedQueueRows.first;

    final transferPayload = <String, dynamic>{
      'transfer_id': transferReferenceId,
      'variant_id': outMovement.variantId,
      'source_warehouse_id': outMovement.warehouseId,
      'destination_warehouse_id': inMovement.warehouseId,
      'quantity': outMovement.quantity,
      'notes': _clean(
        outMovement.note,
      ) ??
          _clean(
            inMovement.note,
          ),
      'user_id': _clean(
        outMovement.userId,
      ) ??
          _clean(
            inMovement.userId,
          ),
      'created_at': outMovement.createdAt.toUtc().toIso8601String(),
    };

    await database.transaction(
          () async {
        await (database.update(
          database.syncOutbox,
        )..where(
              (table) => table.id.equals(
            primaryQueueRow.id,
          ),
        ))
            .write(
          SyncOutboxCompanion(
            entityType: const Value(
              'inventory_transfer',
            ),
            entityId: Value(
              transferReferenceId,
            ),
            operation: Value(
              SyncOperation.create.databaseValue,
            ),
            payloadJson: Value(
              jsonEncode(
                transferPayload,
              ),
            ),
            idempotencyKey: Value(
              transferReferenceId,
            ),
            status: const Value(
              'PENDING',
            ),
            attempts: const Value(
              0,
            ),
            lastError: const Value(
              null,
            ),
            updatedAt: Value(
              DateTime.now(),
            ),
          ),
        );

        final duplicateIds = relatedQueueRows
            .skip(1)
            .map(
              (row) => row.id,
        )
            .toList();

        if (duplicateIds.isNotEmpty) {
          await (database.delete(
            database.syncOutbox,
          )..where(
                (table) => table.id.isIn(
              duplicateIds,
            ),
          ))
              .go();
        }
      },
    );

    for (final row in relatedQueueRows) {
      processedQueueIds.add(
        row.id,
      );
    }

    debugPrint(
      '[INVENTORY OUTBOX REPAIR] '
          'Legacy transfer converted to atomic inventory_transfer.',
    );
    debugPrint(
      '[INVENTORY OUTBOX REPAIR] Transfer ID: $transferReferenceId',
    );
    debugPrint(
      '[INVENTORY OUTBOX REPAIR] Variant ID: ${outMovement.variantId}',
    );
    debugPrint(
      '[INVENTORY OUTBOX REPAIR] Source Warehouse: ${outMovement.warehouseId}',
    );
    debugPrint(
      '[INVENTORY OUTBOX REPAIR] Destination Warehouse: ${inMovement.warehouseId}',
    );
    debugPrint(
      '[INVENTORY OUTBOX REPAIR] Quantity: ${outMovement.quantity}',
    );
    debugPrint(
      '[INVENTORY OUTBOX REPAIR] Old queue rows: ${relatedQueueRows.length}',
    );

    return true;
  }

  // ===========================================================================
  // GET LOCAL STOCK MOVEMENT
  // ===========================================================================

  Future<StockMovement?> _getStockMovement(
      String movementId,
      ) {
    return (database.select(
      database.stockMovements,
    )..where(
          (table) => table.id.equals(
        movementId,
      ),
    ))
        .getSingleOrNull();
  }

  // ===========================================================================
  // DECODE PAYLOAD
  // ===========================================================================

  Map<String, dynamic>? _decodePayload(
      String payloadJson,
      ) {
    try {
      final decoded = jsonDecode(
        payloadJson,
      );

      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded,
        );
      }
    } catch (error) {
      debugPrint(
        '[INVENTORY OUTBOX REPAIR] Invalid payload JSON: $error',
      );
    }

    return null;
  }

  // ===========================================================================
  // CLEANUP UNSUPPORTED WAREHOUSE UPDATES
  // ===========================================================================

  Future<int> cleanupUnsupportedWarehouseUpdates() async {
    final rows = await (database.select(
      database.syncOutbox,
    )..where(
          (table) =>
      table.entityType.equals(
        'warehouse',
      ) &
      table.operation.equals(
        SyncOperation.update.databaseValue,
      ) &
      (table.status.equals(
        'PENDING',
      ) |
      table.status.equals(
        'FAILED',
      )),
    ))
        .get();

    if (rows.isEmpty) {
      return 0;
    }

    final queueIdsToDelete = <String>[];

    for (final row in rows) {
      Map<String, dynamic>? payload;

      try {
        final decoded = jsonDecode(
          row.payloadJson,
        );

        if (decoded is Map) {
          payload = Map<String, dynamic>.from(
            decoded,
          );
        }
      } catch (error) {
        debugPrint(
          '[SYNC QUEUE CLEANUP] '
              'Could not decode queue=${row.id}: $error',
        );

        continue;
      }

      if (payload == null) {
        continue;
      }

      final serverId = _clean(
        payload['server_id'],
      );

      if (serverId == null) {
        continue;
      }

      if (payload['is_active'] == false) {
        continue;
      }

      if (payload['action']?.toString() == 'enable') {
        continue;
      }

      if (_clean(payload['name']) != null) {
        continue;
      }

      queueIdsToDelete.add(
        row.id,
      );

      debugPrint(
        '[SYNC QUEUE CLEANUP] Removing unsupported warehouse UPDATE.',
      );
      debugPrint(
        '[SYNC QUEUE CLEANUP] Queue ID: ${row.id}',
      );
      debugPrint(
        '[SYNC QUEUE CLEANUP] Entity ID: ${row.entityId}',
      );
      debugPrint(
        '[SYNC QUEUE CLEANUP] Server ID: $serverId',
      );
    }

    if (queueIdsToDelete.isEmpty) {
      return 0;
    }

    final deleted = await (database.delete(
      database.syncOutbox,
    )..where(
          (table) => table.id.isIn(
        queueIdsToDelete,
      ),
    ))
        .go();

    debugPrint(
      '[SYNC QUEUE CLEANUP] '
          '$deleted unsupported warehouse UPDATE(s) removed.',
    );

    return deleted;
  }

  // ===========================================================================
  // WATCH PENDING COUNT
  //
  // We keep FAILED in the visible count so the UI can tell the user that
  // something still needs attention.
  // ===========================================================================

  Stream<int> watchPendingCount() {
    final countExpression = database.syncOutbox.id.count();

    final query = database.selectOnly(
      database.syncOutbox,
    )
      ..addColumns([
        countExpression,
      ])
      ..where(
        database.syncOutbox.status.equals(
          'PENDING',
        ) |
        database.syncOutbox.status.equals(
          'FAILED',
        ),
      );

    return query.watchSingle().map(
          (row) =>
      row.read(
        countExpression,
      ) ??
          0,
    );
  }

  // ===========================================================================
  // MARK SYNCING
  // ===========================================================================

  Future<void> markSyncing(
      String queueId,
      ) {
    return (database.update(
      database.syncOutbox,
    )..where(
          (table) => table.id.equals(
        queueId,
      ),
    ))
        .write(
      SyncOutboxCompanion(
        status: const Value(
          'SYNCING',
        ),
        updatedAt: Value(
          DateTime.now(),
        ),
      ),
    );
  }

  // ===========================================================================
  // MARK SYNCED
  // ===========================================================================

  Future<void> markSynced(
      String queueId,
      ) async {
    await (database.update(
      database.syncOutbox,
    )..where(
          (table) => table.id.equals(
        queueId,
      ),
    ))
        .write(
      SyncOutboxCompanion(
        status: const Value(
          'SYNCED',
        ),
        lastError: const Value(
          null,
        ),
        updatedAt: Value(
          DateTime.now(),
        ),
      ),
    );
  }

  // ===========================================================================
  // MARK FAILED
  // ===========================================================================

  Future<void> markFailed({
    required String queueId,
    required String error,
  }) async {
    final current = await (database.select(
      database.syncOutbox,
    )..where(
          (table) => table.id.equals(
        queueId,
      ),
    ))
        .getSingleOrNull();

    if (current == null) {
      return;
    }

    await (database.update(
      database.syncOutbox,
    )..where(
          (table) => table.id.equals(
        queueId,
      ),
    ))
        .write(
      SyncOutboxCompanion(
        status: const Value(
          'FAILED',
        ),
        attempts: Value(
          current.attempts + 1,
        ),
        lastError: Value(
          error,
        ),
        updatedAt: Value(
          DateTime.now(),
        ),
      ),
    );
  }

  // ===========================================================================
  // RELEASE BACK TO PENDING
  //
  // انقطاع الشبكة لا يُنهي العملية. تبقى في الطابور حتى يعود السيرفر.
  // ===========================================================================

  Future<void> releaseToPending({
    required String queueId,
    required String error,
  }) async {
    final current = await (database.select(
      database.syncOutbox,
    )..where(
          (table) => table.id.equals(
        queueId,
      ),
    ))
        .getSingleOrNull();

    if (current == null) {
      return;
    }

    await (database.update(
      database.syncOutbox,
    )..where(
          (table) => table.id.equals(
        queueId,
      ),
    ))
        .write(
      SyncOutboxCompanion(
        status: const Value(
          'PENDING',
        ),
        attempts: Value(
          current.attempts + 1,
        ),
        lastError: Value(
          error,
        ),
        updatedAt: Value(
          DateTime.now(),
        ),
      ),
    );
  }

  // ===========================================================================
  // RESET STUCK
  // ===========================================================================

  Future<void> resetStuckOperations() async {
    await (database.update(
      database.syncOutbox,
    )..where(
          (table) => table.status.equals(
        'SYNCING',
      ),
    ))
        .write(
      SyncOutboxCompanion(
        status: const Value(
          'PENDING',
        ),
        updatedAt: Value(
          DateTime.now(),
        ),
      ),
    );
  }

  // ===========================================================================
  // CLEAR ALL
  // ===========================================================================

  Future<void> clearAll() async {
    await database.delete(
      database.syncOutbox,
    ).go();
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String? _clean(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    return text.isEmpty ? null : text;
  }
}