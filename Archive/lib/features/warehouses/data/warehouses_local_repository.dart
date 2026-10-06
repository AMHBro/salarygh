import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_user.dart';
import '../../../core/database/app_database.dart';
import '../../../core/lan/office_role.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../../users/data/station_grants.dart';
import '../models/warehouse_model.dart';

class WarehouseDeleteRequest {
  final String id;
  final String warehouseId;
  final String warehouseName;
  final String requestedBy;
  final String sourceName;

  const WarehouseDeleteRequest({
    required this.id,
    required this.warehouseId,
    required this.warehouseName,
    required this.requestedBy,
    required this.sourceName,
  });
}

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
    final session = await AuthStorage().readSession();
    final role = resolveSessionRole(
      storedRole: session?.user.role,
      accessToken: session?.accessToken,
    );
    if (!canApproveWarehouseDelete(role) ||
        await StationGrants.isAttachedStation()) {
      throw StateError(
        'إضافة المخزن للحاسبة الأساسية فقط. يعيّن المخزن من الحاسبات والصلاحيات.',
      );
    }

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
  // Name, code, address, capacity, and notes are pushed with
  // PATCH /warehouses/{serverId} after the warehouse is synced.
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
  // POST /warehouses/{id}/disable
  // POST /warehouses/{id}/enable
  // ===========================================================================

  /// يُظهر مخزن الحاسبة الملحقة من جديد ويرسل تفعيله للسيرفر.
  Future<void> ensureListed(WarehouseModel warehouse) async {
    final current = await getWarehouseById(warehouse.id);
    if (current == null) return;
    if (current.deletedAt == null &&
        current.isActive &&
        current.status.trim().toUpperCase() == 'ACTIVE') {
      return;
    }

    final now = DateTime.now();
    await (database.update(database.warehouses)
          ..where((table) => table.id.equals(current.id)))
        .write(
      WarehousesCompanion(
        deletedAt: const Value(null),
        isActive: const Value(true),
        status: const Value('ACTIVE'),
        updatedAt: Value(now),
      ),
    );

    if ((current.serverId ?? '').trim().isEmpty) return;
    final fresh = await getWarehouseById(current.id);
    if (fresh == null) return;
    final payload = fresh.toSyncJson();
    payload['action'] = 'enable';
    await syncQueue.enqueue(
      entityType: 'warehouse',
      entityId: current.id,
      operation: SyncOperation.update,
      idempotencyKey: '${current.id}:enable',
      payload: payload,
    );
  }

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

    if (isActive && current.type == WarehouseType.sub) {
      final parentId = _clean(
        current.parentWarehouseId,
      );

      if (parentId != null) {
        final parent = await getWarehouseById(
          parentId,
        );

        if (parent != null && !parent.isActive) {
          throw StateError(
            'لا يمكن تفعيل مخزن فرعي تابع لمخزن أب موقوف.',
          );
        }
      }
    }

    final updated = current.copyWith(
      isActive: isActive,
      status: isActive ? 'ACTIVE' : 'INACTIVE',
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
            isActive: Value(
              isActive,
            ),
            status: Value(
              updated.status,
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
        // UPDATE + action == enable  -> POST /warehouses/{serverId}/enable
        // UPDATE + is_active == false -> POST /warehouses/{serverId}/disable
        // ---------------------------------------------------------------------

        final payload = updated.toSyncJson();
        if (isActive) {
          payload['action'] = 'enable';
        }

        await syncQueue.enqueue(
          entityType: 'warehouse',
          entityId: current.id,
          operation: SyncOperation.update,
          idempotencyKey: isActive
              ? '${current.id}:enable'
              : current.id,
          payload: payload,
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
    await requestWarehouseDelete(warehouse);
  }

  Future<void> _ensureDeleteRequests() {
    return database.customStatement('''
      CREATE TABLE IF NOT EXISTS warehouse_delete_requests (
        id TEXT PRIMARY KEY,
        warehouse_id TEXT NOT NULL,
        warehouse_name TEXT NOT NULL,
        requested_by TEXT NOT NULL,
        source_name TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<List<WarehouseDeleteRequest>> listPendingWarehouseDeletes() async {
    await _ensureDeleteRequests();
    final rows = await database.customSelect('''
      SELECT id, warehouse_id, warehouse_name, requested_by, source_name
      FROM warehouse_delete_requests
      WHERE status = 'PENDING'
      ORDER BY created_at
    ''').get();
    return [
      for (final row in rows)
        WarehouseDeleteRequest(
          id: row.read<String>('id'),
          warehouseId: row.read<String>('warehouse_id'),
          warehouseName: row.read<String>('warehouse_name'),
          requestedBy: row.read<String>('requested_by'),
          sourceName: row.read<String>('source_name'),
        ),
    ];
  }

  Future<String> requestWarehouseDelete(
      WarehouseModel warehouse,
      ) async {
    final current = await getWarehouseById(warehouse.id);
    if (current == null || current.deletedAt != null) {
      throw StateError('المخزن غير موجود.');
    }
    await _assertWarehouseCanBeDeleted(current);
    await _ensureDeleteRequests();
    final existing = await database.customSelect(
      '''
      SELECT id FROM warehouse_delete_requests
      WHERE warehouse_id = ? AND status = 'PENDING'
      LIMIT 1
      ''',
      variables: [Variable.withString(current.id)],
    ).getSingleOrNull();
    final session = await authStorage.readSession();
    final requestedBy = session?.user.name.trim().isNotEmpty == true
        ? session!.user.name.trim()
        : 'مستخدم';
    final role = resolveSessionRole(
      storedRole: session?.user.role,
      accessToken: session?.accessToken,
    );
    final managerOnPrimary =
        !await OfficeRole.instance.isBranch() && canApproveWarehouseDelete(role);

    if (existing != null) {
      if (managerOnPrimary) {
        await approveWarehouseDelete(existing.read<String>('id'));
        return 'حُذف المخزن من هذه الحاسبة.';
      }
      throw StateError('طلب حذف هذا المخزن بانتظار موافقة المدير.');
    }

    if (await OfficeRole.instance.isBranch()) {
      await _sendBranchDeleteRequest(current, requestedBy);
      return 'أُرسل طلب الحذف إلى الحاسبة الأساسية، وبانتظار موافقة المدير.';
    }

    final requestId = await _insertDeleteRequest(
      warehouseId: current.id,
      warehouseName: current.name,
      requestedBy: requestedBy,
      sourceName: 'الحاسبة الأساسية',
    );
    if (managerOnPrimary) {
      await approveWarehouseDelete(requestId);
      return 'حُذف المخزن من هذه الحاسبة.';
    }
    return 'طلب الحذف بانتظار موافقة المدير على هذه الحاسبة.';
  }

  Future<void> receiveBranchDeleteRequest({
    required String warehouseId,
    required String warehouseName,
    String? warehouseServerId,
    required String requestedBy,
  }) async {
    WarehouseModel? warehouse = await getWarehouseById(warehouseId);
    final serverId = warehouseServerId?.trim() ?? '';
    if ((warehouse == null || warehouse.deletedAt != null) && serverId.isNotEmpty) {
      final row = await (database.select(database.warehouses)
            ..where((table) => table.serverId.equals(serverId)))
          .getSingleOrNull();
      warehouse = row == null ? null : _mapRowToModel(row);
    }
    if ((warehouse == null || warehouse.deletedAt != null) &&
        warehouseName.trim().isNotEmpty) {
      final row = await (database.select(database.warehouses)
            ..where(
              (table) =>
                  table.name.equals(warehouseName.trim()) &
                  table.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      warehouse = row == null ? warehouse : _mapRowToModel(row);
    }
    if (warehouse == null || warehouse.deletedAt != null) {
      throw StateError('المخزن غير موجود على الحاسبة الأساسية.');
    }
    await _assertWarehouseCanBeDeleted(warehouse);
    await _ensureDeleteRequests();
    final existing = await database.customSelect(
      '''
      SELECT id FROM warehouse_delete_requests
      WHERE warehouse_id = ? AND status = 'PENDING'
      LIMIT 1
      ''',
      variables: [Variable.withString(warehouse.id)],
    ).getSingleOrNull();
    if (existing != null) {
      return;
    }
    await _insertDeleteRequest(
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      requestedBy: requestedBy.trim().isEmpty ? 'حاسبة فرعية' : requestedBy.trim(),
      sourceName: 'حاسبة فرعية',
    );
  }

  Future<void> approveWarehouseDelete(String requestId) async {
    await _ensureDeleteRequests();
    final request = await _pendingRequest(requestId);
    final warehouse = await getWarehouseById(request.warehouseId);
    if (warehouse == null || warehouse.deletedAt != null) {
      throw StateError('المخزن غير موجود.');
    }
    await _assertWarehouseCanBeDeleted(warehouse);
    final now = DateTime.now();
    await database.transaction(() async {
      await (database.update(database.warehouses)
            ..where((table) => table.id.equals(warehouse.id)))
          .write(
        WarehousesCompanion(
          isActive: const Value(false),
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await database.customStatement(
        '''
        UPDATE warehouse_delete_requests
        SET status = 'APPROVED'
        WHERE id = ?
        ''',
        [requestId],
      );
    });
  }

  Future<void> rejectWarehouseDelete(String requestId) async {
    await _ensureDeleteRequests();
    await _pendingRequest(requestId);
    await database.customStatement(
      '''
      UPDATE warehouse_delete_requests
      SET status = 'REJECTED'
      WHERE id = ?
      ''',
      [requestId],
    );
  }

  Future<WarehouseDeleteRequest> _pendingRequest(String requestId) async {
    final row = await database.customSelect(
      '''
      SELECT id, warehouse_id, warehouse_name, requested_by, source_name, status
      FROM warehouse_delete_requests
      WHERE id = ?
      LIMIT 1
      ''',
      variables: [Variable.withString(requestId)],
    ).getSingleOrNull();
    if (row == null || row.read<String>('status') != 'PENDING') {
      throw StateError('طلب الحذف غير موجود.');
    }
    return WarehouseDeleteRequest(
      id: row.read<String>('id'),
      warehouseId: row.read<String>('warehouse_id'),
      warehouseName: row.read<String>('warehouse_name'),
      requestedBy: row.read<String>('requested_by'),
      sourceName: row.read<String>('source_name'),
    );
  }

  Future<void> _assertWarehouseCanBeDeleted(WarehouseModel warehouse) async {
    final stock = await database.customSelect(
      '''
      SELECT COALESCE(SUM(quantity), 0) AS qty
      FROM stock_balances
      WHERE warehouse_id = ?
      ''',
      variables: [Variable.withString(warehouse.id)],
    ).getSingle();
    final rawQty = stock.data['qty'];
    final qty = rawQty is num
        ? rawQty.toDouble()
        : double.tryParse('${rawQty ?? ''}') ?? 0;
    if (qty > 0) {
      throw StateError('انقل البضاعة من المخزن قبل طلب الحذف.');
    }
    final children = await (database.select(database.warehouses)
          ..where(
            (table) =>
                table.parentWarehouseId.equals(warehouse.id) &
                table.deletedAt.isNull(),
          ))
        .get();
    if (children.isNotEmpty) {
      throw StateError('احذف المخازن الفرعية أولاً.');
    }
  }

  Future<String> _insertDeleteRequest({
    required String warehouseId,
    required String warehouseName,
    required String requestedBy,
    required String sourceName,
  }) {
    final id = _uuid.v4();
    return database.customInsert(
      '''
      INSERT INTO warehouse_delete_requests (
        id, warehouse_id, warehouse_name, requested_by, source_name, status, created_at
      ) VALUES (?, ?, ?, ?, ?, 'PENDING', ?)
      ''',
      variables: [
        Variable.withString(id),
        Variable.withString(warehouseId),
        Variable.withString(warehouseName),
        Variable.withString(requestedBy),
        Variable.withString(sourceName),
        Variable.withString(DateTime.now().toUtc().toIso8601String()),
      ],
    ).then((_) => id);
  }

  Future<void> _sendBranchDeleteRequest(
    WarehouseModel warehouse,
    String requestedBy,
  ) async {
    final role = OfficeRole.instance;
    final base = await role.readBase();
    final token = await role.readToken();
    if (token.isEmpty) {
      throw StateError('رمز الشبكة المحلية مطلوب لإرسال طلب الحذف.');
    }
    final dio = Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    try {
      await dio.post(
        '/v1/queue',
        data: {
          'idempotencyKey': 'wh-del-${warehouse.id}-${DateTime.now().microsecondsSinceEpoch}',
          'kind': 'warehouse.delete.request',
          'payload': {
            'warehouseId': warehouse.id,
            'warehouseName': warehouse.name,
            'warehouseServerId': warehouse.serverId,
            'requestedBy': requestedBy,
          },
        },
      );
    } on DioException {
      throw StateError('تعذر الوصول إلى الحاسبة الأساسية لإرسال طلب الحذف.');
    }
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