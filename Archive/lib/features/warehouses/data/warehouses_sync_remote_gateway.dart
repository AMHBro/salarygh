import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_remote_gateway.dart';

class WarehousesSyncRemoteGateway implements SyncRemoteGateway {
  final AppDatabase database;
  final ApiClient apiClient;

  static const Uuid _uuid = Uuid();

  WarehousesSyncRemoteGateway({
    required this.database,
    required this.apiClient,
  });

  @override
  Set<String> get supportedEntityTypes => const {
    'warehouse',
  };

  // ===========================================================================
  // PUSH
  // ===========================================================================

  @override
  Future<void> pushOperation(
      SyncOutboxData operation,
      ) async {
    if (operation.entityType.toLowerCase() != 'warehouse') {
      throw StateError(
        'Unsupported warehouse sync entity: '
            '${operation.entityType}',
      );
    }

    final decoded = jsonDecode(
      operation.payloadJson,
    );

    if (decoded is! Map) {
      throw StateError(
        'Invalid warehouse sync payload.',
      );
    }

    final payload = Map<String, dynamic>.from(
      decoded,
    );

    final syncOperation = SyncOperationExtension.fromDatabaseValue(
      operation.operation,
    );

    debugPrint(
      '[WAREHOUSE SYNC] ========================================',
    );

    debugPrint(
      '[WAREHOUSE SYNC] Local ID: ${operation.entityId}',
    );

    debugPrint(
      '[WAREHOUSE SYNC] Operation: ${operation.operation}',
    );

    switch (syncOperation) {
      case SyncOperation.create:
        await _handleCreate(
          localWarehouseId: operation.entityId,
        );
        break;

      case SyncOperation.update:
        await _handleUpdate(
          localWarehouseId: operation.entityId,
          originalPayload: payload,
        );
        break;

      case SyncOperation.delete:
        await _handleDelete(
          localWarehouseId: operation.entityId,
          originalPayload: payload,
        );
        break;
    }

    debugPrint(
      '[WAREHOUSE SYNC] Completed.',
    );

    debugPrint(
      '[WAREHOUSE SYNC] ========================================',
    );
  }

  // ===========================================================================
  // CREATE
  // ===========================================================================

  Future<void> _handleCreate({
    required String localWarehouseId,
  }) async {
    final warehouse = await _getWarehouse(
      localWarehouseId,
    );

    if (warehouse == null) {
      throw StateError(
        'Local warehouse not found: $localWarehouseId',
      );
    }

    if (warehouse.deletedAt != null &&
        _clean(warehouse.serverId) == null) {
      debugPrint(
        '[WAREHOUSE SYNC] CREATE skipped because warehouse '
            'was deleted before upload.',
      );

      return;
    }

    final existingServerId = _clean(
      warehouse.serverId,
    );

    if (existingServerId != null) {
      debugPrint(
        '[WAREHOUSE SYNC] Warehouse already has serverId: '
            '$existingServerId',
      );

      await _ensureSubmitted(
        localWarehouseId: localWarehouseId,
        serverId: existingServerId,
      );

      return;
    }

    final serverId = await _ensureWarehouseCreatedOnServer(
      localWarehouseId: localWarehouseId,
      visiting: <String>{},
      dependency: false,
    );

    if (serverId == null) {
      debugPrint(
        '[WAREHOUSE SYNC] Warehouse creation skipped.',
      );

      return;
    }

    await _ensureSubmitted(
      localWarehouseId: localWarehouseId,
      serverId: serverId,
    );
  }

  // ===========================================================================
  // ENSURE REMOTE WAREHOUSE
  // ===========================================================================

  Future<String?> _ensureWarehouseCreatedOnServer({
    required String localWarehouseId,
    required Set<String> visiting,
    required bool dependency,
  }) async {
    final warehouse = await _getWarehouse(
      localWarehouseId,
    );

    if (warehouse == null) {
      throw StateError(
        'Local warehouse not found: $localWarehouseId',
      );
    }

    final existingServerId = _clean(
      warehouse.serverId,
    );

    if (existingServerId != null) {
      debugPrint(
        '[WAREHOUSE SYNC] Warehouse already exists remotely.',
      );

      debugPrint(
        '[WAREHOUSE SYNC] Local ID: $localWarehouseId',
      );

      debugPrint(
        '[WAREHOUSE SYNC] Server ID: $existingServerId',
      );

      return existingServerId;
    }

    if (warehouse.deletedAt != null) {
      if (dependency) {
        throw StateError(
          'Warehouse cannot sync: parent warehouse '
              'is deleted locally.',
        );
      }

      debugPrint(
        '[WAREHOUSE SYNC] CREATE skipped because warehouse '
            'was deleted before upload.',
      );

      return null;
    }

    if (visiting.contains(localWarehouseId)) {
      throw StateError(
        'Warehouse cannot sync: circular parent warehouse '
            'relationship detected.',
      );
    }

    visiting.add(
      localWarehouseId,
    );

    try {
      debugPrint(
        '[WAREHOUSE SYNC] Preparing remote warehouse.',
      );

      debugPrint(
        '[WAREHOUSE SYNC] Local ID: $localWarehouseId',
      );

      debugPrint(
        '[WAREHOUSE SYNC] Name: ${warehouse.name}',
      );

      debugPrint(
        '[WAREHOUSE SYNC] Type: ${warehouse.type}',
      );

      debugPrint(
        '[WAREHOUSE SYNC] Parent Local ID: '
            '${warehouse.parentWarehouseId}',
      );

      final remoteExisting = await _findRemoteMatchForLocal(
        warehouse,
      );

      if (remoteExisting != null) {
        final remoteId = _requiredString(
          remoteExisting['id'],
          label: 'warehouse id',
        );

        debugPrint(
          '[WAREHOUSE SYNC] Existing server warehouse found.',
        );

        debugPrint(
          '[WAREHOUSE SYNC] Local ID: $localWarehouseId',
        );

        debugPrint(
          '[WAREHOUSE SYNC] Remote ID: $remoteId',
        );

        await _saveServerSnapshot(
          localWarehouseId: localWarehouseId,
          data: remoteExisting,
        );

        return remoteId;
      }

      final apiPayload = await _buildCreatePayload(
        warehouse,
        visiting: visiting,
      );

      _validateCreatePayload(
        apiPayload,
      );

      debugPrint(
        '[WAREHOUSE SYNC] POST /warehouses',
      );

      debugPrint(
        _prettyJson(
          apiPayload,
        ),
      );

      try {
        final response = await apiClient.post(
          '/warehouses',
          data: apiPayload,
        );

        _printSuccess(
          action: 'POST /warehouses',
          response: response,
        );

        final data = _extractData(
          response.data,
        );

        final serverId = _requiredString(
          data['id'],
          label: 'warehouse id',
        );

        await _saveServerSnapshot(
          localWarehouseId: localWarehouseId,
          data: data,
        );

        debugPrint(
          '[WAREHOUSE SYNC] Remote warehouse created.',
        );

        debugPrint(
          '[WAREHOUSE SYNC] Local ID: $localWarehouseId',
        );

        debugPrint(
          '[WAREHOUSE SYNC] Server ID: $serverId',
        );

        if (dependency) {
          debugPrint(
            '[WAREHOUSE SYNC] Dependency created without submit.',
          );
        }

        return serverId;
      } on DioException catch (error) {
        _printDioError(
          action: dependency
              ? 'CREATE PARENT WAREHOUSE'
              : 'CREATE WAREHOUSE',
          error: error,
          requestBody: apiPayload,
        );

        rethrow;
      }
    } finally {
      visiting.remove(
        localWarehouseId,
      );
    }
  }

  // ===========================================================================
  // UPDATE
  // ===========================================================================

  Future<void> _handleUpdate({
    required String localWarehouseId,
    required Map<String, dynamic> originalPayload,
  }) async {
    final warehouse = await _getWarehouse(
      localWarehouseId,
    );

    if (warehouse == null) {
      throw StateError(
        'Local warehouse not found: $localWarehouseId',
      );
    }

    var serverId = _clean(
      warehouse.serverId,
    );

    final payloadServerId = _clean(
      originalPayload['server_id'],
    );

    debugPrint(
      '[WAREHOUSE SYNC] UPDATE current serverId=$serverId',
    );

    debugPrint(
      '[WAREHOUSE SYNC] UPDATE payload serverId=$payloadServerId',
    );

    // -------------------------------------------------------------------------
    // CASE 1
    // Warehouse currently has no remote record.
    //
    // هذا يصير إذا UPDATE موجود بالـOutbox قبل أول Upload.
    // -------------------------------------------------------------------------

    if (serverId == null) {
      debugPrint(
        '[WAREHOUSE SYNC] UPDATE target has no serverId.',
      );

      debugPrint(
        '[WAREHOUSE SYNC] Creating/reconciling warehouse first...',
      );

      serverId = await _ensureWarehouseCreatedOnServer(
        localWarehouseId: localWarehouseId,
        visiting: <String>{},
        dependency: false,
      );

      if (serverId == null) {
        debugPrint(
          '[WAREHOUSE SYNC] UPDATE skipped because warehouse '
              'could not be created remotely.',
        );

        return;
      }
    }

    // -------------------------------------------------------------------------
    // CASE 2
    // UPDATE was queued before initial CREATE completed.
    // -------------------------------------------------------------------------

    if (payloadServerId == null) {
      debugPrint(
        '[WAREHOUSE SYNC] UPDATE was queued before initial upload.',
      );

      await _ensureSubmitted(
        localWarehouseId: localWarehouseId,
        serverId: serverId,
      );

      return;
    }

    // -------------------------------------------------------------------------
    // CASE 3
    // STALE UPDATE
    //
    // الـOutbox يحتوي Server ID قديم بينما المخزن حالياً مربوط
    // بـServer ID مختلف وصحيح.
    //
    // ما نرسل هذا UPDATE إلى الـServer.
    // فقط نتأكد أن المخزن الحالي تم Submit.
    // -------------------------------------------------------------------------

    if (payloadServerId != serverId) {
      debugPrint(
        '[WAREHOUSE SYNC] Stale UPDATE detected.',
      );

      debugPrint(
        '[WAREHOUSE SYNC] Payload serverId=$payloadServerId',
      );

      debugPrint(
        '[WAREHOUSE SYNC] Current serverId=$serverId',
      );

      debugPrint(
        '[WAREHOUSE SYNC] Stale remote edit ignored.',
      );

      await _ensureSubmitted(
        localWarehouseId: localWarehouseId,
        serverId: serverId,
      );

      return;
    }

    // -------------------------------------------------------------------------
    // CASE 4
    // Disable
    // -------------------------------------------------------------------------

    final wantsActive =
        originalPayload['is_active'] != false;

    if (!wantsActive) {
      await _disableWarehouse(
        localWarehouseId: localWarehouseId,
        serverId: serverId,
      );

      return;
    }

    if (originalPayload['action']?.toString() == 'enable') {
      await _enableWarehouse(
        localWarehouseId: localWarehouseId,
        serverId: serverId,
      );

      return;
    }

    await _pushWarehouseDetails(
      localWarehouseId: localWarehouseId,
      serverId: serverId,
    );
  }

  // ===========================================================================
  // DELETE
  // ===========================================================================

  Future<void> _handleDelete({
    required String localWarehouseId,
    required Map<String, dynamic> originalPayload,
  }) async {
    final warehouse = await _getWarehouse(
      localWarehouseId,
    );

    final serverId = _clean(
      warehouse?.serverId,
    ) ??
        _clean(
          originalPayload['server_id'],
        );

    if (serverId == null) {
      debugPrint(
        '[WAREHOUSE SYNC] DELETE skipped because warehouse '
            'never existed on server.',
      );

      return;
    }

    await _disableWarehouse(
      localWarehouseId: localWarehouseId,
      serverId: serverId,
    );
  }

  // ===========================================================================
  // SUBMIT
  // ===========================================================================

  Future<void> _ensureSubmitted({
    required String localWarehouseId,
    required String serverId,
  }) async {
    final current = await _getWarehouse(
      localWarehouseId,
    );

    final status =
    current?.status.trim().toUpperCase();

    if (status == 'PENDING_APPROVAL' ||
        status == 'ACTIVE') {
      debugPrint(
        '[WAREHOUSE SYNC] Submit not required. Status: $status',
      );

      return;
    }

    if (status != null &&
        status != 'LOCAL' &&
        status != 'DRAFT') {
      throw StateError(
        'Warehouse cannot be submitted from status: $status',
      );
    }

    final endpoint =
        '/warehouses/$serverId/submit';

    debugPrint(
      '[WAREHOUSE SYNC] POST $endpoint',
    );

    try {
      final response = await apiClient.post(
        endpoint,
      );

      _printSuccess(
        action: 'POST $endpoint',
        response: response,
      );

      final data = _extractData(
        response.data,
      );

      await _saveServerSnapshot(
        localWarehouseId: localWarehouseId,
        data: data,
      );
    } on DioException catch (error) {
      _printDioError(
        action: 'POST $endpoint',
        error: error,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // DISABLE
  // ===========================================================================

  Future<void> _disableWarehouse({
    required String localWarehouseId,
    required String serverId,
  }) async {
    final endpoint =
        '/warehouses/$serverId/disable';

    debugPrint(
      '[WAREHOUSE SYNC] POST $endpoint',
    );

    try {
      final response = await apiClient.post(
        endpoint,
      );

      _printSuccess(
        action: 'POST $endpoint',
        response: response,
      );

      final data = _extractData(
        response.data,
      );

      if (data.isNotEmpty) {
        await _saveServerSnapshot(
          localWarehouseId: localWarehouseId,
          data: data,
        );
      }

      await (database.update(
        database.warehouses,
      )..where(
            (table) => table.id.equals(
          localWarehouseId,
        ),
      ))
          .write(
        WarehousesCompanion(
          isActive: const Value(
            false,
          ),
          updatedAt: Value(
            DateTime.now(),
          ),
        ),
      );
    } on DioException catch (error) {
      _printDioError(
        action: 'POST $endpoint',
        error: error,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // ENABLE
  // ===========================================================================

  Future<void> _enableWarehouse({
    required String localWarehouseId,
    required String serverId,
  }) async {
    final endpoint =
        '/warehouses/$serverId/enable';

    debugPrint(
      '[WAREHOUSE SYNC] POST $endpoint',
    );

    try {
      final response = await apiClient.post(
        endpoint,
      );

      _printSuccess(
        action: 'POST $endpoint',
        response: response,
      );

      final data = _extractData(
        response.data,
      );

      if (data.isNotEmpty) {
        await _saveServerSnapshot(
          localWarehouseId: localWarehouseId,
          data: data,
        );
      }

      await (database.update(
        database.warehouses,
      )..where(
            (table) => table.id.equals(
          localWarehouseId,
        ),
      ))
          .write(
        WarehousesCompanion(
          isActive: const Value(
            true,
          ),
          status: const Value(
            'ACTIVE',
          ),
          updatedAt: Value(
            DateTime.now(),
          ),
        ),
      );
    } on DioException catch (error) {
      _printDioError(
        action: 'POST $endpoint',
        error: error,
      );

      rethrow;
    }
  }

  bool _statusMeansActive(String status) {
    switch (status.trim().toUpperCase()) {
      case 'INACTIVE':
      case 'DISABLED':
        return false;
      default:
        return true;
    }
  }

  // ===========================================================================
  // BUILD CREATE REQUEST
  // ===========================================================================

  Future<Map<String, dynamic>> _buildCreatePayload(
      Warehouse warehouse, {
        required Set<String> visiting,
      }) async {
    final type =
    warehouse.type.trim().toUpperCase();

    final payload = <String, dynamic>{
      'name': warehouse.name.trim(),
      'branch_id': _clean(
        warehouse.branchId,
      ),
      'type': type,
    };

    final code = _clean(
      warehouse.code,
    );

    if (code != null) {
      payload['code'] = code;
    }

    if (type == 'SUB') {
      final localParentId = _clean(
        warehouse.parentWarehouseId,
      );

      if (localParentId == null) {
        throw StateError(
          'Warehouse cannot sync: SUB warehouse requires '
              'a parent warehouse.',
        );
      }

      final parent = await _getWarehouse(
        localParentId,
      );

      if (parent == null) {
        throw StateError(
          'Warehouse cannot sync: parent warehouse '
              'does not exist locally.',
        );
      }

      if (parent.deletedAt != null) {
        throw StateError(
          'Warehouse cannot sync: parent warehouse '
              'is deleted locally.',
        );
      }

      var parentServerId = _clean(
        parent.serverId,
      );

      if (parentServerId == null) {
        debugPrint(
          '[WAREHOUSE SYNC] Parent is not synced yet.',
        );

        debugPrint(
          '[WAREHOUSE SYNC] Child: ${warehouse.name}',
        );

        debugPrint(
          '[WAREHOUSE SYNC] Parent: ${parent.name}',
        );

        debugPrint(
          '[WAREHOUSE SYNC] Parent Local ID: ${parent.id}',
        );

        debugPrint(
          '[WAREHOUSE SYNC] Creating / reconciling parent first...',
        );

        parentServerId =
        await _ensureWarehouseCreatedOnServer(
          localWarehouseId: parent.id,
          visiting: visiting,
          dependency: true,
        );

        if (parentServerId == null) {
          throw StateError(
            'Warehouse cannot sync: parent warehouse '
                'could not be created on server.',
          );
        }

        debugPrint(
          '[WAREHOUSE SYNC] Parent ready.',
        );

        debugPrint(
          '[WAREHOUSE SYNC] Parent Server ID: $parentServerId',
        );
      }

      payload['parent_warehouse_id'] =
          parentServerId;
    }

    final managerId = _clean(
      warehouse.managerId,
    );

    if (managerId != null) {
      payload['manager_id'] =
          managerId;
    }

    final address = _clean(
      warehouse.address,
    );

    if (address != null) {
      payload['address'] =
          address;
    }

    if (warehouse.capacity != null) {
      payload['capacity'] =
          warehouse.capacity;
    }

    return payload;
  }

  // ===========================================================================
  // VALIDATE CREATE
  // ===========================================================================

  void _validateCreatePayload(
      Map<String, dynamic> payload,
      ) {
    final name = _clean(
      payload['name'],
    );

    if (name == null) {
      throw StateError(
        'Warehouse cannot sync: name is missing.',
      );
    }

    final branchId = _clean(
      payload['branch_id'],
    );

    if (branchId == null) {
      throw StateError(
        'Warehouse cannot sync: branch_id is required by backend.',
      );
    }

    final type = _clean(
      payload['type'],
    )?.toUpperCase();

    const allowedTypes = {
      'MAIN',
      'SUB',
      'VIRTUAL',
    };

    if (type == null ||
        !allowedTypes.contains(type)) {
      throw StateError(
        'Warehouse cannot sync: invalid warehouse type.',
      );
    }

    if (type == 'SUB') {
      final parentId = _clean(
        payload['parent_warehouse_id'],
      );

      if (parentId == null) {
        throw StateError(
          'Warehouse cannot sync: SUB warehouse requires '
              'parent_warehouse_id.',
        );
      }
    }
  }

  // ===========================================================================
  // REMOTE LOOKUP / DUPLICATE PREVENTION
  // ===========================================================================

  Future<Map<String, dynamic>?> _findRemoteMatchForLocal(
      Warehouse warehouse,
      ) async {
    final remoteWarehouses =
    await _fetchAllRemoteWarehouses();

    final localServerId = _clean(
      warehouse.serverId,
    );

    if (localServerId != null) {
      for (final remote in remoteWarehouses) {
        if (_clean(remote['id']) ==
            localServerId) {
          return remote;
        }
      }

      return null;
    }

    // IMPORTANT:
    //
    // إذا ما عندنا serverId، ما نربط تلقائياً بـcode أو name.
    //
    // السبب:
    // هذا الربط هو اللي سبب سابقاً أن مخزن محلي أخذ serverId
    // مال مخزن مختلف.
    //
    // الـidentity الحقيقي بين Local وRemote هو serverId فقط.
    //
    // إذا نحتاج reconciliation يدوي مستقبلاً، نسويه من UI مستقلة.

    debugPrint(
      '[WAREHOUSE SYNC] Local warehouse has no serverId. '
          'Automatic code/name reconciliation disabled.',
    );

    return null;
  }

  // ===========================================================================
  // PULL
  // ===========================================================================

  @override
  Future<SyncPullResult> pullChanges({
    String? cursor,
  }) async {
    debugPrint(
      '[WAREHOUSE PULL] ========================================',
    );

    debugPrint(
      '[WAREHOUSE PULL] Starting warehouses pull...',
    );

    try {
      final remoteWarehouses =
      await _fetchAllRemoteWarehouses();

      debugPrint(
        '[WAREHOUSE PULL] '
            '${remoteWarehouses.length} warehouse(s) received.',
      );

      final serverToLocalId =
      <String, String>{};

      for (final remote in remoteWarehouses) {
        final serverId = _requiredString(
          remote['id'],
          label: 'warehouse id',
        );

        final local =
        await _findLocalMatchForRemote(
          remote,
        );

        if (local != null) {
          final office = !kIsWeb;
          if (office) {
            await _pushDesktopDetails(
              local: local,
              remote: remote,
            );
          }
          await _savePulledWarehouse(
            localWarehouseId: local.id,
            data: remote,
            updateParent: false,
            keepLocalDetails: office,
          );

          serverToLocalId[serverId] =
              local.id;

          debugPrint(
            '[WAREHOUSE PULL] Reconciled:',
          );

          debugPrint(
            '[WAREHOUSE PULL] local=${local.id}',
          );

          debugPrint(
            '[WAREHOUSE PULL] server=$serverId',
          );

          continue;
        }

        final localId =
        _uuid.v4();

        await _insertRemoteWarehouse(
          localWarehouseId: localId,
          data: remote,
        );

        serverToLocalId[serverId] =
            localId;

        debugPrint(
          '[WAREHOUSE PULL] Inserted remote warehouse locally:',
        );

        debugPrint(
          '[WAREHOUSE PULL] local=$localId',
        );

        debugPrint(
          '[WAREHOUSE PULL] server=$serverId',
        );
      }

      final allLocalWarehouses =
      await database
          .select(
        database.warehouses,
      )
          .get();

      for (final local
      in allLocalWarehouses) {
        final serverId = _clean(
          local.serverId,
        );

        if (serverId != null) {
          serverToLocalId[serverId] =
              local.id;
        }
      }

      for (final remote in remoteWarehouses) {
        final serverId = _requiredString(
          remote['id'],
          label: 'warehouse id',
        );

        final localId =
        serverToLocalId[serverId];

        if (localId == null) {
          continue;
        }

        final serverParentId = _clean(
          remote['parent_warehouse_id'],
        );

        String? localParentId;

        if (serverParentId != null) {
          localParentId =
          serverToLocalId[serverParentId];

          if (localParentId == null) {
            final localParent =
            await _getWarehouseByServerId(
              serverParentId,
            );

            localParentId =
                localParent?.id;
          }
        }

        await (database.update(
          database.warehouses,
        )..where(
              (table) => table.id.equals(
            localId,
          ),
        ))
            .write(
          WarehousesCompanion(
            parentWarehouseId: Value(
              localParentId,
            ),
          ),
        );
      }

      debugPrint(
        '[WAREHOUSE PULL] Pull completed successfully.',
      );

      debugPrint(
        '[WAREHOUSE PULL] ========================================',
      );

      return const SyncPullResult(
        nextCursor: null,
        changes: [],
      );
    } on DioException catch (error) {
      _printDioError(
        action: 'GET /warehouses',
        error: error,
      );

      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
        '[WAREHOUSE PULL] FAILED',
      );

      debugPrint(
        '[WAREHOUSE PULL] $error',
      );

      debugPrint(
        '$stackTrace',
      );

      rethrow;
    }
  }

  // ===========================================================================
  // FETCH ALL REMOTE WAREHOUSES
  // ===========================================================================

  Future<List<Map<String, dynamic>>>
  _fetchAllRemoteWarehouses() async {
    const limit = 100;

    var page = 1;
    var totalPages = 1;

    final result =
    <Map<String, dynamic>>[];

    do {
      final endpoint =
          '/warehouses?page=$page&limit=$limit';

      debugPrint(
        '[WAREHOUSE PULL] GET $endpoint',
      );

      final response = await apiClient.get(
        endpoint,
      );

      final pageData =
      _extractDataList(
        response.data,
      );

      result.addAll(
        pageData,
      );

      final meta =
      _extractMeta(
        response.data,
      );

      final total =
          _toInt(
            meta['total'],
          ) ??
              result.length;

      final serverLimit =
          _toInt(
            meta['limit'],
          ) ??
              limit;

      if (serverLimit > 0) {
        totalPages =
            (total / serverLimit).ceil();

        if (totalPages < 1) {
          totalPages = 1;
        }
      } else {
        totalPages = 1;
      }

      debugPrint(
        '[WAREHOUSE PULL] Page $page/$totalPages '
            '- ${pageData.length} warehouse(s).',
      );

      page++;
    } while (page <= totalPages);

    return result;
  }

  // ===========================================================================
  // FIND LOCAL MATCH FOR REMOTE
  // ===========================================================================

  Future<Warehouse?>
  _findLocalMatchForRemote(
      Map<String, dynamic> remote,
      ) async {
    final serverId = _clean(
      remote['id'],
    );

    if (serverId == null) {
      return null;
    }

    final matches =
    await (database.select(
      database.warehouses,
    )..where(
          (table) => table.serverId.equals(
        serverId,
      ),
    ))
        .get();

    if (matches.isEmpty) {
      return null;
    }

    if (matches.length > 1) {
      throw StateError(
        'Warehouse mapping conflict: serverId=$serverId '
            'is linked to ${matches.length} local warehouses.',
      );
    }

    return matches.first;
  }

  // ===========================================================================
  // INSERT PULLED WAREHOUSE
  // ===========================================================================

  Future<void> _insertRemoteWarehouse({
    required String localWarehouseId,
    required Map<String, dynamic> data,
  }) async {
    final serverId = _requiredString(
      data['id'],
      label: 'warehouse id',
    );

    final name = _requiredString(
      data['name'],
      label: 'warehouse name',
    );

    final type = _clean(
      data['type'],
    )?.toUpperCase() ??
        'SUB';

    final status = _clean(
      data['status'],
    ) ??
        'DRAFT';

    final createdAt =
        _parseDateTime(
          data['created_at'],
        ) ??
            DateTime.now();

    final updatedAt =
        _parseDateTime(
          data['updated_at'],
        ) ??
            createdAt;

    await database
        .into(
      database.warehouses,
    )
        .insert(
      WarehousesCompanion.insert(
        id: localWarehouseId,
        serverId: Value(
          serverId,
        ),
        name: name,
        code: Value(
          _clean(
            data['code'],
          ),
        ),
        branchId: Value(
          _clean(
            data['branch_id'],
          ),
        ),
        type: Value(
          type,
        ),
        status: Value(
          status,
        ),
        parentWarehouseId:
        const Value(
          null,
        ),
        managerId: Value(
          _clean(
            data['manager_id'],
          ),
        ),
        address: Value(
          _clean(
            data['address'],
          ),
        ),
        capacity: Value(
          _toDoubleNullable(
            data['capacity'],
          ),
        ),
        notes: Value(
          _clean(
            data['notes'],
          ),
        ),
        rejectionReason: Value(
          _clean(
            data['rejection_reason'],
          ),
        ),
        isMain: Value(
          type == 'MAIN',
        ),
        isActive: Value(
          _statusMeansActive(status),
        ),
        serverVersion:
        const Value(
          0,
        ),
        createdAt:
        createdAt,
        updatedAt:
        updatedAt,
      ),
    );
  }

  // ===========================================================================
  // PUSH DESKTOP DETAILS
  //
  // سطح المكتب هو مرجع الاسم والعنوان والرمز والسعة والملاحظات.
  // الويب يقرأ نفس الحقول من السيرفر بعد هذا الرفع.
  // ===========================================================================

  Future<void> _pushWarehouseDetails({
    required String localWarehouseId,
    required String serverId,
  }) async {
    final local = await _getWarehouse(
      localWarehouseId,
    );
    if (local == null) {
      return;
    }
    await _sendWarehouseDetails(
      serverId: serverId,
      name: local.name,
      code: local.code,
      address: local.address,
      notes: local.notes,
      capacity: local.capacity,
    );
  }

  Future<void> _pushDesktopDetails({
    required Warehouse local,
    required Map<String, dynamic> remote,
  }) async {
    final serverId = _clean(local.serverId) ?? _clean(remote['id']);
    if (serverId == null) {
      return;
    }
    final remoteName = _clean(remote['name']) ?? '';
    final remoteCode = _clean(remote['code']) ?? '';
    final remoteAddress = _clean(remote['address']) ?? '';
    final remoteNotes = _clean(remote['notes']) ?? '';
    final remoteCapacity = _toDoubleNullable(remote['capacity']);
    final localName = local.name.trim();
    final localCode = _clean(local.code) ?? '';
    final localAddress = _clean(local.address) ?? '';
    final localNotes = _clean(local.notes) ?? '';
    final sameCapacity = (local.capacity == null && remoteCapacity == null) ||
        (local.capacity != null &&
            remoteCapacity != null &&
            (local.capacity! - remoteCapacity).abs() < 0.001);
    if (localName == remoteName &&
        localCode == remoteCode &&
        localAddress == remoteAddress &&
        localNotes == remoteNotes &&
        sameCapacity) {
      return;
    }
    await _sendWarehouseDetails(
      serverId: serverId,
      name: local.name,
      code: local.code,
      address: local.address,
      notes: local.notes,
      capacity: local.capacity,
    );
  }

  Future<void> _sendWarehouseDetails({
    required String serverId,
    required String name,
    required String? code,
    required String? address,
    required String? notes,
    required double? capacity,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      return;
    }
    final body = <String, dynamic>{
      'name': cleanName,
      'address': address?.trim() ?? '',
      'notes': notes?.trim() ?? '',
    };
    final cleanCode = _clean(code);
    if (cleanCode != null) {
      body['code'] = cleanCode;
    }
    if (capacity != null) {
      body['capacity'] = capacity;
    }
    try {
      await apiClient.patch(
        '/warehouses/$serverId',
        data: body,
      );
    } on DioException catch (error) {
      if (body.containsKey('code')) {
        body.remove('code');
        try {
          await apiClient.patch(
            '/warehouses/$serverId',
            data: body,
          );
          return;
        } on DioException catch (retryError) {
          _printDioError(
            action: 'PATCH /warehouses/$serverId',
            error: retryError,
          );
          return;
        }
      }
      _printDioError(
        action: 'PATCH /warehouses/$serverId',
        error: error,
      );
    }
  }

  // ===========================================================================
  // SAVE PULLED WAREHOUSE
  // ===========================================================================

  Future<void> _savePulledWarehouse({
    required String localWarehouseId,
    required Map<String, dynamic> data,
    required bool updateParent,
    bool keepLocalDetails = false,
  }) async {
    final current = await _getWarehouse(
      localWarehouseId,
    );

    if (current == null) {
      throw StateError(
        'Local warehouse not found while saving pulled warehouse.',
      );
    }

    if (current.deletedAt != null) {
      return;
    }

    final serverId = _requiredString(
      data['id'],
      label: 'warehouse id',
    );

    final type = _clean(
      data['type'],
    )?.toUpperCase() ??
        current.type;

    final status = _clean(
      data['status'],
    ) ??
        current.status;

    final updatedAt =
        _parseDateTime(
          data['updated_at'],
        ) ??
            DateTime.now();

    String? localParentId =
        current.parentWarehouseId;

    if (updateParent) {
      final serverParentId = _clean(
        data['parent_warehouse_id'],
      );

      if (serverParentId == null) {
        localParentId = null;
      } else {
        final parent =
        await _getWarehouseByServerId(
          serverParentId,
        );

        localParentId =
            parent?.id;
      }
    }

    await (database.update(
      database.warehouses,
    )..where(
          (table) => table.id.equals(
        localWarehouseId,
      ),
    ))
        .write(
      WarehousesCompanion(
        serverId: Value(
          serverId,
        ),
        code: keepLocalDetails
            ? const Value.absent()
            : Value(
                _clean(
                      data['code'],
                    ) ??
                    current.code,
              ),
        name: keepLocalDetails
            ? const Value.absent()
            : Value(
                _clean(
                      data['name'],
                    ) ??
                    current.name,
              ),
        branchId: Value(
          _clean(
            data['branch_id'],
          ) ??
              current.branchId,
        ),
        type: Value(
          type,
        ),
        status: Value(
          status,
        ),
        parentWarehouseId: Value(
          localParentId,
        ),
        managerId: Value(
          _clean(
            data['manager_id'],
          ) ??
              current.managerId,
        ),
        address: keepLocalDetails
            ? const Value.absent()
            : Value(
                _clean(
                      data['address'],
                    ) ??
                    current.address,
              ),
        capacity: keepLocalDetails
            ? const Value.absent()
            : Value(
                _toDoubleNullable(
                      data['capacity'],
                    ) ??
                    current.capacity,
              ),
        notes: keepLocalDetails
            ? const Value.absent()
            : Value(
                _clean(
                      data['notes'],
                    ) ??
                    current.notes,
              ),
        rejectionReason: Value(
          _clean(
            data['rejection_reason'],
          ),
        ),
        isMain: Value(
          type == 'MAIN',
        ),
        isActive: Value(
          _statusMeansActive(status),
        ),
        updatedAt: Value(
          updatedAt,
        ),
      ),
    );
  }

  // ===========================================================================
  // SAVE SERVER SNAPSHOT
  // ===========================================================================

  Future<void> _saveServerSnapshot({
    required String localWarehouseId,
    required Map<String, dynamic> data,
  }) async {
    final current = await _getWarehouse(
      localWarehouseId,
    );

    if (current == null) {
      throw StateError(
        'Local warehouse not found while saving server snapshot.',
      );
    }

    final serverId = _requiredString(
      data['id'],
      label: 'warehouse id',
    );

    final duplicateRows =
    await (database.select(
      database.warehouses,
    )..where(
          (table) =>
      table.serverId.equals(
        serverId,
      ) &
      table.id
          .equals(localWarehouseId)
          .not(),
    ))
        .get();

    if (duplicateRows.isNotEmpty) {
      throw StateError(
        'Warehouse mapping conflict: serverId=$serverId '
            'is already linked to another local warehouse.',
      );
    }

    final status = _clean(
      data['status'],
    ) ??
        'DRAFT';

    final type = _clean(
      data['type'],
    )?.toUpperCase() ??
        current.type;

    final capacity =
    _toDoubleNullable(
      data['capacity'],
    );

    final updatedAt =
        _parseDateTime(
          data['updated_at'],
        ) ??
            DateTime.now();

    String? localParentId =
        current.parentWarehouseId;

    final serverParentId = _clean(
      data['parent_warehouse_id'],
    );

    if (serverParentId != null) {
      final parent =
      await _getWarehouseByServerId(
        serverParentId,
      );

      if (parent != null) {
        localParentId =
            parent.id;
      }
    }

    if (type != 'SUB' &&
        serverParentId == null) {
      localParentId = null;
    }

    await (database.update(
      database.warehouses,
    )..where(
          (table) => table.id.equals(
        localWarehouseId,
      ),
    ))
        .write(
      WarehousesCompanion(
        serverId: Value(
          serverId,
        ),
        code: Value(
          _clean(
            data['code'],
          ) ??
              current.code,
        ),
        name: Value(
          _clean(
            data['name'],
          ) ??
              current.name,
        ),
        branchId: Value(
          _clean(
            data['branch_id'],
          ) ??
              current.branchId,
        ),
        type: Value(
          type,
        ),
        status: Value(
          status,
        ),
        parentWarehouseId: Value(
          localParentId,
        ),
        managerId: Value(
          _clean(
            data['manager_id'],
          ) ??
              current.managerId,
        ),
        address: Value(
          _clean(
            data['address'],
          ) ??
              current.address,
        ),
        capacity: Value(
          capacity ??
              current.capacity,
        ),
        notes: Value(
          _clean(
            data['notes'],
          ) ??
              current.notes,
        ),
        rejectionReason: Value(
          _clean(
            data['rejection_reason'],
          ),
        ),
        isMain: Value(
          type == 'MAIN',
        ),
        isActive: Value(
          _statusMeansActive(status),
        ),
        updatedAt: Value(
          updatedAt,
        ),
      ),
    );

    debugPrint(
      '[WAREHOUSE SYNC] Server snapshot saved.',
    );

    debugPrint(
      '[WAREHOUSE SYNC] localId=$localWarehouseId',
    );

    debugPrint(
      '[WAREHOUSE SYNC] '
          'serverId=$serverId status=$status type=$type',
    );

    debugPrint(
      '[WAREHOUSE SYNC] localParentId=$localParentId',
    );
  }

  // ===========================================================================
  // LOCAL DATABASE
  // ===========================================================================

  Future<Warehouse?> _getWarehouse(
      String localId,
      ) {
    return (database.select(
      database.warehouses,
    )..where(
          (table) => table.id.equals(
        localId,
      ),
    ))
        .getSingleOrNull();
  }

  Future<Warehouse?> _getWarehouseByServerId(
      String serverId,
      ) async {
    final cleanServerId = _clean(
      serverId,
    );

    if (cleanServerId == null) {
      return null;
    }

    final rows =
    await (database.select(
      database.warehouses,
    )..where(
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
        'Warehouse mapping conflict: serverId=$cleanServerId '
            'is linked to ${rows.length} local warehouses.',
      );
    }

    return rows.first;
  }

  // ===========================================================================
  // RESPONSE HELPERS
  // ===========================================================================

  Map<String, dynamic> _extractData(
      dynamic responseData,
      ) {
    if (responseData is! Map) {
      return {};
    }

    final root =
    Map<String, dynamic>.from(
      responseData,
    );

    final rawData =
    root['data'];

    if (rawData is Map) {
      return Map<String, dynamic>.from(
        rawData,
      );
    }

    return {};
  }

  List<Map<String, dynamic>> _extractDataList(
      dynamic responseData,
      ) {
    if (responseData is! Map) {
      return [];
    }

    final root =
    Map<String, dynamic>.from(
      responseData,
    );

    final rawData =
    root['data'];

    if (rawData is! List) {
      return [];
    }

    return rawData
        .whereType<Map>()
        .map(
          (item) =>
      Map<String, dynamic>.from(
        item,
      ),
    )
        .toList();
  }

  Map<String, dynamic> _extractMeta(
      dynamic responseData,
      ) {
    if (responseData is! Map) {
      return {};
    }

    final root =
    Map<String, dynamic>.from(
      responseData,
    );

    final rawMeta =
    root['meta'];

    if (rawMeta is Map) {
      return Map<String, dynamic>.from(
        rawMeta,
      );
    }

    return {};
  }

  String _requiredString(
      dynamic value, {
        required String label,
      }) {
    final result = _clean(
      value,
    );

    if (result == null) {
      throw StateError(
        'Server response does not contain $label.',
      );
    }

    return result;
  }

  String? _clean(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    final text =
    value.toString().trim();

    return text.isEmpty
        ? null
        : text;
  }

  double? _toDoubleNullable(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    );
  }

  int? _toInt(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    );
  }

  DateTime? _parseDateTime(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    );
  }

  // ===========================================================================
  // DEBUG
  // ===========================================================================

  void _printSuccess({
    required String action,
    required Response<dynamic> response,
  }) {
    debugPrint(
      '[WAREHOUSE SYNC] SUCCESS',
    );

    debugPrint(
      '[WAREHOUSE SYNC] Action: $action',
    );

    debugPrint(
      '[WAREHOUSE SYNC] Status: ${response.statusCode}',
    );

    debugPrint(
      '[WAREHOUSE SYNC] Response:',
    );

    debugPrint(
      _prettyJson(
        response.data,
      ),
    );
  }

  void _printDioError({
    required String action,
    required DioException error,
    Map<String, dynamic>? requestBody,
  }) {
    debugPrint(
      '[WAREHOUSE SYNC] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!',
    );

    debugPrint(
      '[WAREHOUSE SYNC] REQUEST FAILED',
    );

    debugPrint(
      '[WAREHOUSE SYNC] Action: $action',
    );

    debugPrint(
      '[WAREHOUSE SYNC] Status: ${error.response?.statusCode}',
    );

    debugPrint(
      '[WAREHOUSE SYNC] URI: ${error.requestOptions.uri}',
    );

    if (requestBody != null) {
      debugPrint(
        '[WAREHOUSE SYNC] Request body:',
      );

      debugPrint(
        _prettyJson(
          requestBody,
        ),
      );
    }

    debugPrint(
      '[WAREHOUSE SYNC] Response:',
    );

    debugPrint(
      _prettyJson(
        error.response?.data,
      ),
    );

    debugPrint(
      '[WAREHOUSE SYNC] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!',
    );
  }

  String _prettyJson(
      dynamic value,
      ) {
    if (value == null) {
      return 'NULL';
    }

    try {
      return const JsonEncoder.withIndent(
        '  ',
      ).convert(
        value,
      );
    } catch (_) {
      return value.toString();
    }
  }
}