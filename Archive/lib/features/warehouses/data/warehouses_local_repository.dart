import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../models/warehouse_model.dart';

class WarehousesLocalRepository {
  final AppDatabase database;
  final SyncQueueRepository syncQueue;
  final AuthStorage authStorage;

  static const Uuid _uuid = Uuid();

  WarehousesLocalRepository({
    required this.database,
    required this.syncQueue,
    required this.authStorage,
  });

  // ===========================================================================
  // WATCH
  // ===========================================================================

  Stream<List<WarehouseModel>> watchWarehouses() {
    final query = database.select(database.warehouses)
      ..where(
            (table) => table.deletedAt.isNull(),
      )
      ..orderBy([
            (table) => OrderingTerm.asc(
          table.name,
        ),
      ]);

    return query.watch().map(
          (rows) {
        return rows.map(_mapRowToModel).toList();
      },
    );
  }

  // ===========================================================================
  // GET
  // ===========================================================================

  Future<List<WarehouseModel>> getWarehouses() async {
    final query = database.select(database.warehouses)
      ..where(
            (table) => table.deletedAt.isNull(),
      )
      ..orderBy([
            (table) => OrderingTerm.asc(
          table.name,
        ),
      ]);

    final rows = await query.get();

    return rows.map(_mapRowToModel).toList();
  }

  Future<WarehouseModel?> getWarehouseById(
      String id,
      ) async {
    final cleanId = id.trim();

    if (cleanId.isEmpty) {
      return null;
    }

    final row = await (database.select(database.warehouses)
      ..where(
            (table) => table.id.equals(
          cleanId,
        ),
      ))
        .getSingleOrNull();

    if (row == null) {
      return null;
    }

    return _mapRowToModel(
      row,
    );
  }

  Future<WarehouseModel?> getWarehouseByServerId(
      String serverId,
      ) async {
    final cleanServerId = serverId.trim();

    if (cleanServerId.isEmpty) {
      return null;
    }

    final rows = await (database.select(database.warehouses)
      ..where(
            (table) => table.serverId.equals(
          cleanServerId,
        ),
      ))
        .get();

    if (rows.isEmpty) {
      return null;
    }

    if (rows.length > 1) {
      throw StateError(
        'يوجد أكثر من مخزن محلي مرتبط بنفس Server ID: '
            '$cleanServerId',
      );
    }

    return _mapRowToModel(
      rows.first,
    );
  }

  // ===========================================================================
  // ACTIVE BRANCH
  // ===========================================================================

  Future<String?> _resolveBranchId(
      String? branchId,
      ) async {
    final providedBranchId = _clean(
      branchId,
    );

    if (providedBranchId != null) {
      return providedBranchId;
    }

    final savedBranchId = _clean(
      await authStorage.readBranchId(),
    );

    return savedBranchId;
  }

  // ===========================================================================
  // REPAIR OLD WAREHOUSES
  // ===========================================================================

  Future<int> repairMissingBranchIds() async {
    final activeBranchId = _clean(
      await authStorage.readBranchId(),
    );

    if (activeBranchId == null) {
      return 0;
    }

    final rows = await (database.select(database.warehouses)
      ..where(
            (table) =>
        table.branchId.isNull() &
        table.deletedAt.isNull(),
      ))
        .get();

    if (rows.isEmpty) {
      return 0;
    }

    var repairedCount = 0;

    await database.transaction(
          () async {
        for (final row in rows) {
          final affected =
          await (database.update(database.warehouses)
            ..where(
                  (table) => table.id.equals(
                row.id,
              ),
            ))
              .write(
            WarehousesCompanion(
              branchId: Value(
                activeBranchId,
              ),
              updatedAt: Value(
                DateTime.now(),
              ),
            ),
          );

          if (affected > 0) {
            repairedCount++;
          }
        }
      },
    );

    return repairedCount;
  }

  // ===========================================================================
  // CREATE
  // ===========================================================================

  Future<WarehouseModel> createWarehouse({
    required String name,
    String? code,
    String? branchId,
    WarehouseType type = WarehouseType.sub,
    String? parentWarehouseId,
    String? managerId,
    String? address,
    double? capacity,
    String? notes,
  }) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError(
        'اسم المخزن مطلوب.',
      );
    }

    final resolvedBranchId = await _resolveBranchId(
      branchId,
    );

    if (resolvedBranchId == null) {
      throw StateError(
        'لا يوجد فرع فعّال محفوظ على الجهاز. '
            'سجّل الدخول وحدد الفرع أولاً.',
      );
    }

    final cleanParentId = _clean(
      parentWarehouseId,
    );

    if (type == WarehouseType.sub && cleanParentId == null) {
      throw ArgumentError(
        'المخزن الفرعي يحتاج إلى مخزن أب.',
      );
    }

    if (capacity != null && capacity < 0) {
      throw ArgumentError(
        'سعة المخزن لا يمكن أن تكون سالبة.',
      );
    }

    if (type == WarehouseType.sub) {
      final parentWarehouse = await getWarehouseById(
        cleanParentId!,
      );

      if (parentWarehouse == null) {
        throw StateError(
          'المخزن الأب المحدد غير موجود.',
        );
      }

      if (parentWarehouse.deletedAt != null) {
        throw StateError(
          'المخزن الأب المحدد محذوف.',
        );
      }

      if (!parentWarehouse.isActive) {
        throw StateError(
          'لا يمكن ربط مخزن فرعي بمخزن أب موقوف.',
        );
      }
    }

    final now = DateTime.now();

    final warehouse = WarehouseModel(
      id: _uuid.v4(),
      serverId: null,
      name: cleanName,
      code: _clean(
        code,
      ),
      branchId: resolvedBranchId,
      type: type,
      status: 'LOCAL',
      parentWarehouseId:
      type == WarehouseType.sub
          ? cleanParentId
          : null,
      managerId: _clean(
        managerId,
      ),
      address: _clean(
        address,
      ),
      capacity: capacity,
      notes: _clean(
        notes,
      ),
      isMain: type == WarehouseType.main,
      isActive: true,
      serverVersion: 0,
      createdAt: now,
      updatedAt: now,
    );

    await database.transaction(
          () async {
        await database.into(database.warehouses).insert(
          WarehousesCompanion.insert(
            id: warehouse.id,
            serverId: const Value(
              null,
            ),
            name: warehouse.name,
            code: Value(
              warehouse.code,
            ),
            branchId: Value(
              warehouse.branchId,
            ),
            type: Value(
              warehouse.type.databaseValue,
            ),
            status: Value(
              warehouse.status,
            ),
            parentWarehouseId: Value(
              warehouse.parentWarehouseId,
            ),
            managerId: Value(
              warehouse.managerId,
            ),
            address: Value(
              warehouse.address,
            ),
            capacity: Value(
              warehouse.capacity,
            ),
            notes: Value(
              warehouse.notes,
            ),
            rejectionReason: const Value(
              null,
            ),
            isMain: Value(
              warehouse.isMain,
            ),
            isActive: Value(
              warehouse.isActive,
            ),
            serverVersion: Value(
              warehouse.serverVersion,
            ),
            createdAt: warehouse.createdAt,
            updatedAt: warehouse.updatedAt,
          ),
        );

        await syncQueue.enqueue(
          entityType: 'warehouse',
          entityId: warehouse.id,
          operation: SyncOperation.create,
          idempotencyKey: warehouse.id,
          payload: warehouse.toSyncJson(),
        );
      },
    );

    return warehouse;
  }

  // ===========================================================================
  // UPDATE LOCAL WAREHOUSE
  // ===========================================================================
  //
  // IMPORTANT:
  //
  // The current backend contract does NOT expose a confirmed general endpoint
  // for editing warehouse name, code, type, parent, address, capacity, etc.
  //
  // Therefore:
  //
  // - Local/unsynced warehouse: editing is allowed.
  // - Synced warehouse: editing is blocked.
  //
  // This prevents a local/server divergence and prevents unsupported UPDATE
  // operations from entering the Outbox.
  // ===========================================================================

  Future<WarehouseModel> updateWarehouse(
      WarehouseModel warehouse,
      ) async {
    final current = await getWarehouseById(
      warehouse.id,
    );

    if (current == null) {
      throw StateError(
        'المخزن غير موجود.',
      );
    }

    if (current.isSynced) {
      throw StateError(
        'لا يمكن تعديل بيانات هذا المخزن حالياً لأنه مرتبط بالسيرفر، '
            'وواجهة تعديل المخازن غير متوفرة في الـBackend حالياً.',
      );
    }

    final name = warehouse.name.trim();

    if (name.isEmpty) {
      throw ArgumentError(
        'اسم المخزن مطلوب.',
      );
    }

    if (warehouse.capacity != null &&
        warehouse.capacity! < 0) {
      throw ArgumentError(
        'سعة المخزن لا يمكن أن تكون سالبة.',
      );
    }

    final resolvedBranchId = await _resolveBranchId(
      warehouse.branchId,
    );

    if (resolvedBranchId == null) {
      throw StateError(
        'لا يوجد فرع فعّال محفوظ لهذا المخزن.',
      );
    }

    final cleanParentId = _clean(
      warehouse.parentWarehouseId,
    );

    if (warehouse.type == WarehouseType.sub &&
        cleanParentId == null) {
      throw ArgumentError(
        'المخزن الفرعي يحتاج إلى مخزن أب.',
      );
    }

    if (cleanParentId == warehouse.id) {
      throw ArgumentError(
        'لا يمكن أن يكون المخزن تابعاً لنفسه.',
      );
    }

    if (warehouse.type == WarehouseType.sub) {
      final parentWarehouse = await getWarehouseById(
        cleanParentId!,
      );

      if (parentWarehouse == null) {
        throw StateError(
          'المخزن الأب المحدد غير موجود.',
        );
      }

      if (parentWarehouse.deletedAt != null) {
        throw StateError(
          'المخزن الأب المحدد محذوف.',
        );
      }

      if (!parentWarehouse.isActive) {
        throw StateError(
          'لا يمكن ربط المخزن بمخزن أب موقوف.',
        );
      }
    }

    final updated = warehouse.copyWith(
      serverId: current.serverId,
      name: name,
      code: _clean(
        warehouse.code,
      ),
      branchId: resolvedBranchId,
      parentWarehouseId:
      warehouse.type == WarehouseType.sub
          ? cleanParentId
          : null,
      clearParentWarehouseId:
      warehouse.type != WarehouseType.sub,
      address: _clean(
        warehouse.address,
      ),
      notes: _clean(
        warehouse.notes,
      ),
      isMain:
      warehouse.type == WarehouseType.main,
      updatedAt: DateTime.now(),
    );

    await database.transaction(
          () async {
        final affected =
        await (database.update(database.warehouses)
          ..where(
                (table) => table.id.equals(
              updated.id,
            ),
          ))
            .write(
          WarehousesCompanion(
            name: Value(
              updated.name,
            ),
            code: Value(
              updated.code,
            ),
            branchId: Value(
              updated.branchId,
            ),
            type: Value(
              updated.type.databaseValue,
            ),
            parentWarehouseId: Value(
              updated.parentWarehouseId,
            ),
            managerId: Value(
              updated.managerId,
            ),
            address: Value(
              updated.address,
            ),
            capacity: Value(
              updated.capacity,
            ),
            notes: Value(
              updated.notes,
            ),
            isMain: Value(
              updated.isMain,
            ),
            updatedAt: Value(
              updated.updatedAt,
            ),
          ),
        );

        if (affected == 0) {
          throw StateError(
            'تعذر تحديث بيانات المخزن المحلي.',
          );
        }

        // ---------------------------------------------------------------------
        // The warehouse is still local/serverId=null.
        //
        // The gateway can safely process this UPDATE because it knows how to
        // handle pre-upload warehouse changes and will use the current local
        // warehouse snapshot.
        // ---------------------------------------------------------------------

        await syncQueue.enqueue(
          entityType: 'warehouse',
          entityId: updated.id,
          operation: SyncOperation.update,
          idempotencyKey: updated.id,
          payload: updated.toSyncJson(),
        );
      },
    );

    return updated;
  }

  // ===========================================================================
  // ACTIVE / DISABLE
  // ===========================================================================
  //
  // Confirmed backend endpoint:
  //
  // POST /warehouses/{id}/disable
  //
  // There is currently no confirmed endpoint for reactivation.
  // ===========================================================================

  Future<void> setActive({
    required WarehouseModel warehouse,
    required bool isActive,
  }) async {
    final current = await getWarehouseById(
      warehouse.id,
    );

    if (current == null) {
      throw StateError(
        'المخزن غير موجود.',
      );
    }

    if (current.isActive == isActive) {
      return;
    }

    // -------------------------------------------------------------------------
    // We only send warehouse lifecycle actions after the warehouse has a
    // confirmed server identity.
    // -------------------------------------------------------------------------

    if (!current.isSynced) {
      throw StateError(
        'انتظر اكتمال مزامنة المخزن مع السيرفر أولاً.',
      );
    }

    // -------------------------------------------------------------------------
    // Reactivation is not part of the confirmed backend contract.
    // -------------------------------------------------------------------------

    if (isActive) {
      throw StateError(
        'لا يمكن إعادة تفعيل المخزن حالياً لأن '
            'واجهة إعادة التفعيل غير متوفرة في الـBackend.',
      );
    }

    final updated = current.copyWith(
      isActive: false,
      updatedAt: DateTime.now(),
    );

    await database.transaction(
          () async {
        final affected =
        await (database.update(database.warehouses)
          ..where(
                (table) => table.id.equals(
              current.id,
            ),
          ))
            .write(
          WarehousesCompanion(
            isActive: const Value(
              false,
            ),
            updatedAt: Value(
              updated.updatedAt,
            ),
          ),
        );

        if (affected == 0) {
          throw StateError(
            'تعذر تحديث حالة المخزن.',
          );
        }

        // ---------------------------------------------------------------------
        // The warehouse gateway interprets:
        //
        // UPDATE + server_id != null + is_active == false
        //
        // as:
        //
        // POST /warehouses/{serverId}/disable
        // ---------------------------------------------------------------------

        await syncQueue.enqueue(
          entityType: 'warehouse',
          entityId: current.id,
          operation: SyncOperation.update,
          idempotencyKey: current.id,
          payload: updated.toSyncJson(),
        );
      },
    );
  }

  // ===========================================================================
  // SOFT DELETE
  // ===========================================================================
  //
  // There is no confirmed warehouse DELETE endpoint in the current backend
  // contract.
  //
  // Synced warehouses therefore cannot be deleted from this repository.
  // Use disable instead.
  //
  // Local unsynced warehouses are also protected here because deleting one
  // while a CREATE operation is still present in the Outbox could later create
  // the warehouse remotely.
  // ===========================================================================

  Future<void> deleteWarehouse(
      WarehouseModel warehouse,
      ) async {
    final current = await getWarehouseById(
      warehouse.id,
    );

    if (current == null) {
      throw StateError(
        'المخزن غير موجود.',
      );
    }

    if (current.isSynced) {
      throw StateError(
        'حذف المخزن غير مدعوم حالياً من السيرفر. '
            'استخدم إيقاف المخزن بدلاً من الحذف.',
      );
    }

    throw StateError(
      'لا يمكن حذف مخزن محلي بانتظار المزامنة حالياً، '
          'لأن عملية الإنشاء قد تكون موجودة في قائمة المزامنة.',
    );
  }

  // ===========================================================================
  // SERVER SNAPSHOT
  // ===========================================================================

  Future<void> saveServerSnapshot({
    required String localId,
    required String serverId,
    required String status,
    WarehouseType? type,
    String? parentWarehouseId,
    String? managerId,
    double? capacity,
    String? rejectionReason,
    DateTime? serverUpdatedAt,
  }) async {
    final cleanLocalId = localId.trim();
    final cleanServerId = serverId.trim();

    if (cleanLocalId.isEmpty ||
        cleanServerId.isEmpty) {
      throw ArgumentError(
        'Warehouse IDs are required.',
      );
    }

    final current = await getWarehouseById(
      cleanLocalId,
    );

    if (current == null) {
      throw StateError(
        'المخزن المحلي غير موجود.',
      );
    }

    // -------------------------------------------------------------------------
    // Do not allow one remote warehouse to be mapped to multiple local rows.
    // -------------------------------------------------------------------------

    final duplicateRows =
    await (database.select(database.warehouses)
      ..where(
            (table) =>
        table.serverId.equals(
          cleanServerId,
        ) &
        table.id.equals(
          cleanLocalId,
        ).not(),
      ))
        .get();

    if (duplicateRows.isNotEmpty) {
      throw StateError(
        'Server ID هذا مرتبط مسبقاً بمخزن محلي آخر: '
            '$cleanServerId',
      );
    }

    final resolvedType = type ?? current.type;

    final affected =
    await (database.update(database.warehouses)
      ..where(
            (table) => table.id.equals(
          cleanLocalId,
        ),
      ))
        .write(
      WarehousesCompanion(
        serverId: Value(
          cleanServerId,
        ),
        status: Value(
          status.trim(),
        ),
        type: Value(
          resolvedType.databaseValue,
        ),
        parentWarehouseId: Value(
          parentWarehouseId,
        ),
        managerId: Value(
          managerId,
        ),
        capacity: Value(
          capacity,
        ),
        rejectionReason: Value(
          rejectionReason,
        ),
        isMain: Value(
          resolvedType == WarehouseType.main,
        ),
        isActive: Value(
          _isServerWarehouseActive(
            status,
          ),
        ),
        updatedAt: Value(
          serverUpdatedAt ?? DateTime.now(),
        ),
      ),
    );

    if (affected == 0) {
      throw StateError(
        'تعذر تحديث بيانات المخزن المحلي.',
      );
    }
  }

  // ===========================================================================
  // MAP
  // ===========================================================================

  WarehouseModel _mapRowToModel(
      Warehouse row,
      ) {
    return WarehouseModel(
      id: row.id,
      serverId: row.serverId,
      name: row.name,
      code: row.code,
      branchId: row.branchId,
      type: WarehouseTypeExtension.fromValue(
        row.type,
      ),
      status: row.status,
      parentWarehouseId: row.parentWarehouseId,
      managerId: row.managerId,
      address: row.address,
      capacity: row.capacity,
      notes: row.notes,
      rejectionReason: row.rejectionReason,
      isMain: row.isMain,
      isActive: row.isActive,
      serverVersion: row.serverVersion,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }

  // ===========================================================================
  // SERVER STATUS
  // ===========================================================================

  bool _isServerWarehouseActive(
      String status,
      ) {
    switch (status.trim().toUpperCase()) {
      case 'INACTIVE':
      case 'DISABLED':
        return false;

      default:
        return true;
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String? _clean(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final result = value.trim();

    return result.isEmpty
        ? null
        : result;
  }
}