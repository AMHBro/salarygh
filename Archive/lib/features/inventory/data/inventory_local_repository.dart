import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../models/stock_movement_model.dart';

class InventoryLocalRepository {
  final AppDatabase database;
  final SyncQueueRepository syncQueue;

  static const Uuid _uuid = Uuid();

  InventoryLocalRepository({
    required this.database,
    required this.syncQueue,
  });

  // ===========================================================================
  // WATCH STOCK
  // ===========================================================================

  Stream<double> watchStock({
    required String variantId,
    required String warehouseId,
  }) {
    final query = database.select(
      database.stockBalances,
    )
      ..where(
            (table) =>
            table.variantId.equals(variantId) &
            table.warehouseId.equals(warehouseId),
      );

    return query.watchSingleOrNull().map(
          (row) => row?.quantity ?? 0,
    );
  }

  // ===========================================================================
  // GET STOCK
  // ===========================================================================

  Future<double> getStock({
    required String variantId,
    required String warehouseId,
  }) {
    return _getStockInternal(
      variantId: variantId,
      warehouseId: warehouseId,
    );
  }

  // ===========================================================================
  // WAREHOUSE STOCK MAP
  // ===========================================================================

  Future<Map<String, double>> getWarehouseStockMap(
      String warehouseId,
      ) async {
    final rows = await (database.select(
      database.stockBalances,
    )
      ..where(
            (table) => table.warehouseId.equals(
          warehouseId,
        ),
      ))
        .get();

    return {
      for (final row in rows)
        row.variantId: row.quantity,
    };
  }

  // ===========================================================================
  // TOTAL VARIANT STOCK
  // ===========================================================================

  Future<double> getTotalVariantStock(
      String variantId,
      ) async {
    final quantityExpression =
    database.stockBalances.quantity.sum();

    final query = database.selectOnly(
      database.stockBalances,
    )
      ..addColumns([
        quantityExpression,
      ])
      ..where(
        database.stockBalances.variantId.equals(
          variantId,
        ),
      );

    final row = await query.getSingle();

    return row.read(
      quantityExpression,
    ) ??
        0;
  }

  // ===========================================================================
  // TOTAL PRODUCT STOCK
  // ===========================================================================

  Future<double> getTotalProductStock(
      String productId,
      ) async {
    final variants = await (database.select(
      database.productVariants,
    )
      ..where(
            (table) =>
        table.productId.equals(
          productId,
        ) &
        table.deletedAt.isNull(),
      ))
        .get();

    if (variants.isEmpty) {
      return 0;
    }

    final variantIds = variants
        .map(
          (variant) => variant.id,
    )
        .toList();

    final quantityExpression =
    database.stockBalances.quantity.sum();

    final query = database.selectOnly(
      database.stockBalances,
    )
      ..addColumns([
        quantityExpression,
      ])
      ..where(
        database.stockBalances.variantId.isIn(
          variantIds,
        ),
      );

    final row = await query.getSingle();

    return row.read(
      quantityExpression,
    ) ??
        0;
  }

  // ===========================================================================
  // ADD MOVEMENT
  // ===========================================================================

  Future<StockMovementModel> addMovement({
    required String variantId,
    required String warehouseId,
    required StockMovementType type,
    required double quantity,
    String? referenceType,
    String? referenceId,
    String? note,
    String? userId,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError(
        'الكمية يجب أن تكون أكبر من صفر.',
      );
    }

    if (type == StockMovementType.transferIn ||
        type == StockMovementType.transferOut) {
      throw StateError(
        'حركات التحويل يجب تنفيذها عن طريق transferStock.',
      );
    }

    await _validateVariantExists(
      variantId,
    );

    await _validateWarehouseExists(
      warehouseId,
    );

    final now = DateTime.now();

    final movement = StockMovementModel(
      id: _uuid.v4(),
      variantId: variantId,
      warehouseId: warehouseId,
      type: type,
      quantity: quantity,
      referenceType: _clean(
        referenceType,
      ),
      referenceId: _clean(
        referenceId,
      ),
      note: _clean(
        note,
      ),
      userId: _clean(
        userId,
      ),
      serverVersion: 0,
      createdAt: now,
    );

    await database.transaction(
          () async {
        final currentStock = await _getStockInternal(
          variantId: variantId,
          warehouseId: warehouseId,
        );

        final delta = type.increasesStock
            ? quantity
            : -quantity;

        final newStock =
            currentStock + delta;

        if (newStock < 0) {
          throw StateError(
            'الكمية المتوفرة غير كافية.',
          );
        }

        // ---------------------------------------------------------------------
        // 1. IMMUTABLE LOCAL MOVEMENT
        // ---------------------------------------------------------------------

        await database
            .into(
          database.stockMovements,
        )
            .insert(
          _movementCompanion(
            movement,
          ),
        );

        // ---------------------------------------------------------------------
        // 2. LOCAL CURRENT BALANCE
        // ---------------------------------------------------------------------

        await _setStock(
          variantId: variantId,
          warehouseId: warehouseId,
          quantity: newStock,
          updatedAt: now,
        );

        // ---------------------------------------------------------------------
        // 3. OUTBOX
        //
        // IMPORTANT:
        // variant_id and warehouse_id here are LOCAL UUIDs.
        // InventorySyncRemoteGateway converts them to server UUIDs.
        // ---------------------------------------------------------------------

        await syncQueue.enqueue(
          entityType: 'stock_movement',
          entityId: movement.id,
          operation: SyncOperation.create,
          payload: movement.toSyncJson(),
          idempotencyKey: movement.id,
        );
      },
    );

    return movement;
  }

  // ===========================================================================
  // TRANSFER STOCK
  // ===========================================================================

  Future<void> transferStock({
    required String variantId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    String? note,
    String? userId,
  }) async {
    if (fromWarehouseId ==
        toWarehouseId) {
      throw StateError(
        'لا يمكن التحويل إلى نفس المخزن.',
      );
    }

    if (quantity <= 0) {
      throw ArgumentError(
        'الكمية يجب أن تكون أكبر من صفر.',
      );
    }

    await _validateVariantExists(
      variantId,
    );

    await _validateWarehouseExists(
      fromWarehouseId,
    );

    await _validateWarehouseExists(
      toWarehouseId,
    );

    final now = DateTime.now();

    final transferId = _uuid.v4();

    final outMovement =
    StockMovementModel(
      id: _uuid.v4(),
      variantId: variantId,
      warehouseId: fromWarehouseId,
      type: StockMovementType.transferOut,
      quantity: quantity,
      referenceType: 'TRANSFER',
      referenceId: transferId,
      note: _clean(
        note,
      ),
      userId: _clean(
        userId,
      ),
      serverVersion: 0,
      createdAt: now,
    );

    final inMovement =
    StockMovementModel(
      id: _uuid.v4(),
      variantId: variantId,
      warehouseId: toWarehouseId,
      type: StockMovementType.transferIn,
      quantity: quantity,
      referenceType: 'TRANSFER',
      referenceId: transferId,
      note: _clean(
        note,
      ),
      userId: _clean(
        userId,
      ),
      serverVersion: 0,
      createdAt: now,
    );

    await database.transaction(
          () async {
        final sourceStock =
        await _getStockInternal(
          variantId: variantId,
          warehouseId:
          fromWarehouseId,
        );

        if (sourceStock < quantity) {
          throw StateError(
            'الكمية المتوفرة في المخزن غير كافية.',
          );
        }

        final destinationStock =
        await _getStockInternal(
          variantId: variantId,
          warehouseId:
          toWarehouseId,
        );

        // ---------------------------------------------------------------------
        // 1. LOCAL TRANSFER OUT
        // ---------------------------------------------------------------------

        await database
            .into(
          database.stockMovements,
        )
            .insert(
          _movementCompanion(
            outMovement,
          ),
        );

        // ---------------------------------------------------------------------
        // 2. LOCAL TRANSFER IN
        // ---------------------------------------------------------------------

        await database
            .into(
          database.stockMovements,
        )
            .insert(
          _movementCompanion(
            inMovement,
          ),
        );

        // ---------------------------------------------------------------------
        // 3. SOURCE BALANCE
        // ---------------------------------------------------------------------

        await _setStock(
          variantId: variantId,
          warehouseId: fromWarehouseId,
          quantity: sourceStock - quantity,
          updatedAt: now,
        );

        // ---------------------------------------------------------------------
        // 4. DESTINATION BALANCE
        // ---------------------------------------------------------------------

        await _setStock(
          variantId: variantId,
          warehouseId: toWarehouseId,
          quantity: destinationStock + quantity,
          updatedAt: now,
        );

        // ---------------------------------------------------------------------
        // 5. ONE ATOMIC REMOTE TRANSFER OPERATION
        //
        // Do NOT queue TRANSFER_OUT and TRANSFER_IN separately.
        // Backend has:
        // POST /inventory/transfer
        // ---------------------------------------------------------------------

        await syncQueue.enqueue(
          entityType: 'inventory_transfer',
          entityId: transferId,
          operation: SyncOperation.create,
          payload: {
            'transfer_id': transferId,
            'variant_id': variantId,
            'source_warehouse_id':
            fromWarehouseId,
            'destination_warehouse_id':
            toWarehouseId,
            'quantity': quantity,
            'notes': _clean(
              note,
            ),
            'user_id': _clean(
              userId,
            ),
            'created_at':
            now.toUtc().toIso8601String(),
          },
          idempotencyKey: transferId,
        );
      },
    );
  }

  /// ينقل كل الرصيد الموجب من مخزن إلى آخر. كل مادة تُسجَّل تحويلاً مستقلاً.
  Future<int> transferAllStock({
    required String fromWarehouseId,
    required String toWarehouseId,
    String? note,
    String? userId,
  }) async {
    if (fromWarehouseId == toWarehouseId) {
      throw StateError(
        'لا يمكن التحويل إلى نفس المخزن.',
      );
    }

    await _validateWarehouseExists(fromWarehouseId);
    await _validateWarehouseExists(toWarehouseId);

    final balances = await (database.select(database.stockBalances)
          ..where((table) => table.warehouseId.equals(fromWarehouseId)))
        .get();
    final lines = balances.where((row) => row.quantity > 0).toList();
    if (lines.isEmpty) {
      throw StateError(
        'لا توجد كمية في المخزن المصدر.',
      );
    }

    var moved = 0;
    for (final row in lines) {
      final variant = await (database.select(database.productVariants)
            ..where(
              (table) =>
                  table.id.equals(row.variantId) & table.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      if (variant == null) continue;
      await transferStock(
        variantId: row.variantId,
        fromWarehouseId: fromWarehouseId,
        toWarehouseId: toWarehouseId,
        quantity: row.quantity,
        note: note,
        userId: userId,
      );
      moved++;
    }

    if (moved == 0) {
      throw StateError(
        'لا توجد كمية قابلة للنقل في هذا المخزن.',
      );
    }
    return moved;
  }

  // ===========================================================================
  // MOVEMENTS
  // ===========================================================================

  Future<List<StockMovement>> getMovements({
    String? variantId,
    String? warehouseId,
    int? limit,
    int offset = 0,
  }) {
    final query = database.select(
      database.stockMovements,
    );

    if (variantId != null) {
      query.where(
            (table) => table.variantId.equals(
          variantId,
        ),
      );
    }

    if (warehouseId != null) {
      query.where(
            (table) => table.warehouseId.equals(
          warehouseId,
        ),
      );
    }

    query.orderBy([
          (table) => OrderingTerm.desc(
        table.createdAt,
      ),
    ]);

    if (limit != null) {
      query.limit(limit, offset: offset);
    }

    return query.get();
  }

  /// كمية افتتاح كُتبت على المخزن الرئيسي تنتقل لمخزن الحاسبة الملحقة.
  Future<void> moveRecentOpeningStock(String stationWarehouseId) async {
    final stationId = stationWarehouseId.trim();
    if (stationId.isEmpty) return;
    await _validateWarehouseExists(stationId);
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    final balances = await database.select(database.stockBalances).get();
    for (final row in balances) {
      if (row.warehouseId == stationId || row.quantity <= 0) continue;
      if (row.updatedAt.isBefore(cutoff)) continue;
      final movements = await countMovements(
        variantId: row.variantId,
        warehouseId: row.warehouseId,
      );
      if (movements > 0) continue;
      await transferStock(
        variantId: row.variantId,
        fromWarehouseId: row.warehouseId,
        toWarehouseId: stationId,
        quantity: row.quantity,
        note: 'نقل رصيد الافتتاح إلى مخزن الحاسبة',
      );
    }
  }

  Future<int> countMovements({
    String? variantId,
    String? warehouseId,
  }) async {
    final query = database.selectOnly(database.stockMovements)
      ..addColumns([database.stockMovements.id.count()]);
    if (variantId != null) {
      query.where(database.stockMovements.variantId.equals(variantId));
    }
    if (warehouseId != null) {
      query.where(database.stockMovements.warehouseId.equals(warehouseId));
    }
    final row = await query.getSingle();
    return row.read(database.stockMovements.id.count()) ?? 0;
  }

  // ===========================================================================
  // INTERNAL STOCK
  // ===========================================================================

  Future<double> _getStockInternal({
    required String variantId,
    required String warehouseId,
  }) async {
    final row = await _balanceRow(
      variantId: variantId,
      warehouseId: warehouseId,
    );
    return row?.quantity ?? 0;
  }

  Future<StockBalance?> _balanceRow({
    required String variantId,
    required String warehouseId,
  }) {
    return (database.select(database.stockBalances)
          ..where(
            (table) =>
                table.variantId.equals(variantId) &
                table.warehouseId.equals(warehouseId),
          ))
        .getSingleOrNull();
  }

  Future<void> _setStock({
    required String variantId,
    required String warehouseId,
    required double quantity,
    required DateTime updatedAt,
  }) async {
    final existing = await _balanceRow(
      variantId: variantId,
      warehouseId: warehouseId,
    );
    if (existing != null) {
      await (database.update(database.stockBalances)
            ..where((table) => table.id.equals(existing.id)))
          .write(
        StockBalancesCompanion(
          quantity: Value(quantity),
          updatedAt: Value(updatedAt),
        ),
      );
      return;
    }
    await database.into(database.stockBalances).insert(
          StockBalancesCompanion.insert(
            id: _balanceId(variantId, warehouseId),
            variantId: variantId,
            warehouseId: warehouseId,
            quantity: Value(quantity),
            updatedAt: updatedAt,
          ),
        );
  }

  // ===========================================================================
  // MOVEMENT COMPANION
  // ===========================================================================

  StockMovementsCompanion _movementCompanion(
      StockMovementModel movement,
      ) {
    return StockMovementsCompanion.insert(
      id: movement.id,
      variantId:
      movement.variantId,
      warehouseId:
      movement.warehouseId,
      type:
      movement.type.databaseValue,
      quantity:
      movement.quantity,
      referenceType: Value(
        movement.referenceType,
      ),
      referenceId: Value(
        movement.referenceId,
      ),
      note: Value(
        movement.note,
      ),
      userId: Value(
        movement.userId,
      ),
      serverVersion: Value(
        movement.serverVersion,
      ),
      createdAt:
      movement.createdAt,
    );
  }

  // ===========================================================================
  // VALIDATE VARIANT
  // ===========================================================================

  Future<void> _validateVariantExists(
      String variantId,
      ) async {
    final variant = await (database.select(
      database.productVariants,
    )
      ..where(
            (table) =>
        table.id.equals(
          variantId,
        ) &
        table.deletedAt.isNull(),
      ))
        .getSingleOrNull();

    if (variant == null) {
      throw StateError(
        'الخيار المحدد للمنتج غير موجود.',
      );
    }
  }

  // ===========================================================================
  // VALIDATE WAREHOUSE
  // ===========================================================================

  Future<void> _validateWarehouseExists(
      String warehouseId,
      ) async {
    final warehouse = await (database.select(
      database.warehouses,
    )
      ..where(
            (table) =>
        table.id.equals(
          warehouseId,
        ) &
        table.deletedAt.isNull(),
      ))
        .getSingleOrNull();

    if (warehouse == null) {
      throw StateError(
        'المخزن المحدد غير موجود.',
      );
    }

    if (!warehouse.isActive) {
      throw StateError(
        'المخزن المحدد موقوف.',
      );
    }
  }

  // ===========================================================================
  // BALANCE ID
  // ===========================================================================

  String _balanceId(
      String variantId,
      String warehouseId,
      ) {
    return '$variantId::$warehouseId';
  }

  // ===========================================================================
  // STRING HELPERS
  // ===========================================================================

  String? _clean(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final clean = value.trim();

    return clean.isEmpty
        ? null
        : clean;
  }
}