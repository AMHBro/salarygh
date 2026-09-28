import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_remote_gateway.dart';

class InventorySyncRemoteGateway
    implements SyncRemoteGateway {
  final AppDatabase database;
  final ApiClient apiClient;

  InventorySyncRemoteGateway({
    required this.database,
    required this.apiClient,
  });

  // ===========================================================================
  // CONFIG
  // ===========================================================================

  static const int _pullPageLimit = 100;

  // ===========================================================================
  // SUPPORTED ENTITIES
  // ===========================================================================

  @override
  Set<String> get supportedEntityTypes => const {
    'stock_movement',
    'inventory_transfer',
  };

  // ===========================================================================
  // PUSH
  // ===========================================================================

  @override
  Future<void> pushOperation(
      SyncOutboxData operation,
      ) async {
    final entityType = operation.entityType
        .trim()
        .toLowerCase();

    final decoded = jsonDecode(
      operation.payloadJson,
    );

    if (decoded is! Map) {
      throw StateError(
        'Invalid inventory sync payload.',
      );
    }

    final payload =
    Map<String, dynamic>.from(
      decoded,
    );

    final syncOperation =
    SyncOperationExtension
        .fromDatabaseValue(
      operation.operation,
    );

    if (syncOperation !=
        SyncOperation.create) {
      throw StateError(
        'Inventory ledger operations are immutable. '
            'Only CREATE is supported.',
      );
    }

    debugPrint(
      '[INVENTORY SYNC] ========================================',
    );

    debugPrint(
      '[INVENTORY SYNC] Entity: ${operation.entityType}',
    );

    debugPrint(
      '[INVENTORY SYNC] Entity ID: ${operation.entityId}',
    );

    switch (entityType) {
      case 'stock_movement':
        await _pushStockMovement(
          operation: operation,
          payload: payload,
        );
        break;

      case 'inventory_transfer':
        await _pushTransfer(
          operation: operation,
          payload: payload,
        );
        break;

      default:
        throw StateError(
          'Unsupported inventory sync entity: '
              '${operation.entityType}',
        );
    }

    debugPrint(
      '[INVENTORY SYNC] Operation completed.',
    );

    debugPrint(
      '[INVENTORY SYNC] ========================================',
    );
  }

  // ===========================================================================
  // STOCK MOVEMENT
  // ===========================================================================

  Future<void> _pushStockMovement({
    required SyncOutboxData operation,
    required Map<String, dynamic> payload,
  }) async {
    final localWarehouseId =
    _requiredString(
      payload['warehouse_id'],
      field: 'warehouse_id',
    );

    final localVariantId =
    _requiredString(
      payload['variant_id'],
      field: 'variant_id',
    );

    final localMovementType =
    _requiredString(
      payload['type'],
      field: 'type',
    );

    final quantity =
    _requiredPositiveDouble(
      payload['quantity'],
      field: 'quantity',
    );

    final warehouse =
    await _getWarehouse(
      localWarehouseId,
    );

    final variant =
    await _getVariant(
      localVariantId,
    );

    final warehouseServerId =
    _requireWarehouseReady(
      warehouse,
    );

    final variantServerId =
    _requireVariantReady(
      variant,
    );

    final movementType =
    _mapMovementType(
      localMovementType,
    );

    final apiPayload =
    <String, dynamic>{
      'warehouse_id':
      warehouseServerId,
      'variant_id':
      variantServerId,
      'movement_type':
      movementType,
      'quantity':
      quantity,
    };

    final notes =
    _nullableString(
      payload['note'],
    );

    if (notes != null) {
      apiPayload['notes'] =
          notes;
    }

    debugPrint(
      '[INVENTORY SYNC] POST /inventory/movements',
    );

    debugPrint(
      '[INVENTORY SYNC] Local warehouse: $localWarehouseId',
    );

    debugPrint(
      '[INVENTORY SYNC] Server warehouse: $warehouseServerId',
    );

    debugPrint(
      '[INVENTORY SYNC] Local variant: $localVariantId',
    );

    debugPrint(
      '[INVENTORY SYNC] Server variant: $variantServerId',
    );

    debugPrint(
      '[INVENTORY SYNC] Movement type: '
          '$localMovementType -> $movementType',
    );

    debugPrint(
      '[INVENTORY SYNC] Quantity: $quantity',
    );

    try {
      final response =
      await apiClient.post(
        '/inventory/movements',
        data: apiPayload,
      );

      _ensureSuccess(
        response.data,
        fallback:
        'تعذر مزامنة حركة المخزون.',
      );

      debugPrint(
        '[INVENTORY SYNC] SUCCESS',
      );

      debugPrint(
        '[INVENTORY SYNC] Status: ${response.statusCode}',
      );
    } on DioException catch (error) {
      _printDioError(
        action:
        'POST /inventory/movements',
        error: error,
        requestBody:
        apiPayload,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // TRANSFER
  // ===========================================================================

  Future<void> _pushTransfer({
    required SyncOutboxData operation,
    required Map<String, dynamic> payload,
  }) async {
    final localSourceWarehouseId =
    _requiredString(
      payload['source_warehouse_id'],
      field:
      'source_warehouse_id',
    );

    final localDestinationWarehouseId =
    _requiredString(
      payload['destination_warehouse_id'],
      field:
      'destination_warehouse_id',
    );

    if (localSourceWarehouseId ==
        localDestinationWarehouseId) {
      throw StateError(
        'لا يمكن مزامنة تحويل إلى نفس المخزن.',
      );
    }

    final localVariantId =
    _requiredString(
      payload['variant_id'],
      field: 'variant_id',
    );

    final quantity =
    _requiredPositiveDouble(
      payload['quantity'],
      field: 'quantity',
    );

    final sourceWarehouse =
    await _getWarehouse(
      localSourceWarehouseId,
    );

    final destinationWarehouse =
    await _getWarehouse(
      localDestinationWarehouseId,
    );

    final variant =
    await _getVariant(
      localVariantId,
    );

    final sourceServerId =
    _requireWarehouseReady(
      sourceWarehouse,
    );

    final destinationServerId =
    _requireWarehouseReady(
      destinationWarehouse,
    );

    final variantServerId =
    _requireVariantReady(
      variant,
    );

    if (sourceServerId ==
        destinationServerId) {
      throw StateError(
        'المخزن المصدر والوجهة مرتبطان بنفس Server ID.',
      );
    }

    final apiPayload =
    <String, dynamic>{
      'source_warehouse_id':
      sourceServerId,
      'destination_warehouse_id':
      destinationServerId,
      'variant_id':
      variantServerId,
      'quantity':
      quantity,
    };

    final notes =
    _nullableString(
      payload['notes'],
    );

    if (notes != null) {
      apiPayload['notes'] =
          notes;
    }

    debugPrint(
      '[INVENTORY SYNC] POST /inventory/transfer',
    );

    debugPrint(
      '[INVENTORY SYNC] Source local: $localSourceWarehouseId',
    );

    debugPrint(
      '[INVENTORY SYNC] Source server: $sourceServerId',
    );

    debugPrint(
      '[INVENTORY SYNC] Destination local: '
          '$localDestinationWarehouseId',
    );

    debugPrint(
      '[INVENTORY SYNC] Destination server: '
          '$destinationServerId',
    );

    debugPrint(
      '[INVENTORY SYNC] Variant local: $localVariantId',
    );

    debugPrint(
      '[INVENTORY SYNC] Variant server: $variantServerId',
    );

    debugPrint(
      '[INVENTORY SYNC] Quantity: $quantity',
    );

    try {
      final response =
      await apiClient.post(
        '/inventory/transfer',
        data: apiPayload,
      );

      _ensureSuccess(
        response.data,
        fallback:
        'تعذر مزامنة تحويل المخزون.',
      );

      debugPrint(
        '[INVENTORY SYNC] TRANSFER SUCCESS',
      );

      debugPrint(
        '[INVENTORY SYNC] Status: ${response.statusCode}',
      );
    } on DioException catch (error) {
      _printDioError(
        action:
        'POST /inventory/transfer',
        error: error,
        requestBody:
        apiPayload,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // MOVEMENT TYPE MAPPING
  // ===========================================================================

  String _mapMovementType(
      String localType,
      ) {
    switch (
    localType.trim().toUpperCase()) {
      case 'PURCHASE':
      case 'RETURN_IN':
        return 'IN';

      case 'SALE':
      case 'RETURN_OUT':
        return 'OUT';

      case 'ADJUSTMENT_IN':
        return 'ADJUST_ADD';

      case 'ADJUSTMENT_OUT':
        return 'ADJUST_REDUCE';

      case 'TRANSFER_IN':
      case 'TRANSFER_OUT':
        throw StateError(
          'TRANSFER_IN و TRANSFER_OUT لا يجب إرسالها '
              'إلى /inventory/movements. '
              'استخدم inventory_transfer.',
        );

      default:
        throw StateError(
          'نوع حركة المخزون غير مدعوم: $localType',
        );
    }
  }

  // ===========================================================================
  // LOCAL WAREHOUSE
  // ===========================================================================

  Future<Warehouse> _getWarehouse(
      String localWarehouseId,
      ) async {
    final warehouse =
    await (database.select(
      database.warehouses,
    )
      ..where(
            (table) =>
        table.id.equals(
          localWarehouseId,
        ) &
        table.deletedAt.isNull(),
      ))
        .getSingleOrNull();

    if (warehouse == null) {
      throw StateError(
        'المخزن المحلي غير موجود: '
            '$localWarehouseId',
      );
    }

    return warehouse;
  }

  Future<Warehouse?>
  _getWarehouseByServerId(
      String serverWarehouseId,
      ) async {
    return (database.select(
      database.warehouses,
    )
      ..where(
            (table) =>
        table.serverId.equals(
          serverWarehouseId,
        ) &
        table.deletedAt.isNull(),
      ))
        .getSingleOrNull();
  }

  // ===========================================================================
  // LOCAL VARIANT
  // ===========================================================================

  Future<ProductVariant> _getVariant(
      String localVariantId,
      ) async {
    final variant =
    await (database.select(
      database.productVariants,
    )
      ..where(
            (table) =>
        table.id.equals(
          localVariantId,
        ) &
        table.deletedAt.isNull(),
      ))
        .getSingleOrNull();

    if (variant == null) {
      throw StateError(
        'خيار المنتج المحلي غير موجود: '
            '$localVariantId',
      );
    }

    return variant;
  }

  Future<ProductVariant?>
  _getVariantByServerId(
      String serverVariantId,
      ) async {
    return (database.select(
      database.productVariants,
    )
      ..where(
            (table) =>
        table.serverId.equals(
          serverVariantId,
        ) &
        table.deletedAt.isNull(),
      ))
        .getSingleOrNull();
  }

  // ===========================================================================
  // WAREHOUSE SERVER READINESS
  // ===========================================================================

  String _requireWarehouseReady(
      Warehouse warehouse,
      ) {
    final serverId =
    _nullableString(
      warehouse.serverId,
    );

    if (serverId == null) {
      throw StateError(
        'المخزن "${warehouse.name}" لم تتم مزامنته مع السيرفر بعد.',
      );
    }

    final status =
    warehouse.status
        .trim()
        .toUpperCase();

    if (status != 'ACTIVE') {
      throw StateError(
        'المخزن "${warehouse.name}" غير معتمد بعد. '
            'حالته الحالية: ${warehouse.status}. '
            'يجب اعتماد المخزن قبل إرسال حركات المخزون إلى السيرفر.',
      );
    }

    if (!warehouse.isActive) {
      throw StateError(
        'المخزن "${warehouse.name}" موقوف.',
      );
    }

    return serverId;
  }

  // ===========================================================================
  // VARIANT SERVER READINESS
  // ===========================================================================

  String _requireVariantReady(
      ProductVariant variant,
      ) {
    final serverId =
    _nullableString(
      variant.serverId,
    );

    if (serverId == null) {
      throw StateError(
        'خيار المنتج لم تتم مزامنته مع السيرفر بعد. '
            'Local Variant ID: ${variant.id}',
      );
    }

    if (!variant.isActive) {
      throw StateError(
        'خيار المنتج المحدد موقوف.',
      );
    }

    return serverId;
  }

  // ===========================================================================
  // PULL
  // ===========================================================================

  @override
  Future<SyncPullResult> pullChanges({
    String? cursor,
  }) async {
    debugPrint(
      '[INVENTORY PULL] ========================================',
    );

    debugPrint(
      '[INVENTORY PULL] Starting inventory balances pull...',
    );

    try {
      final remoteBalances =
      await _fetchAllRemoteBalances();

      debugPrint(
        '[INVENTORY PULL] Remote balance rows after variant expansion: '
            '${remoteBalances.length}',
      );

      //
      // قبل أن نلمس الـStockBalances المحلية،
      // نتحقق أن كل Server Warehouse / Server Variant
      // موجود عندنا محلياً.
      //
      // إذا فشل أي Mapping:
      // لا نمسح ولا نعدل أي رصيد محلي.
      //
      final mappedBalances =
      await _mapRemoteBalancesToLocal(
        remoteBalances,
      );

      // السيرفر يحدّث الأرصدة الأقدم فقط.
      // رصيد محلي أحدث (شراء لم يُزامَن بعد) يبقى حتى لا تختفي المادة من البيع.
      final localRows = await database.select(database.stockBalances).get();
      final localByKey = <String, StockBalance>{
        for (final row in localRows)
          '${row.variantId}::${row.warehouseId}': row,
      };

      await database.transaction(() async {
        for (final balance in mappedBalances) {
          final key = '${balance.localVariantId}::${balance.localWarehouseId}';
          final local = localByKey[key];
          final keepLocal = local != null &&
              !local.updatedAt.isBefore(balance.updatedAt);
          final quantity = keepLocal ? local.quantity : balance.quantity;
          final updatedAt = keepLocal ? local.updatedAt : balance.updatedAt;

          if (local != null) {
            await (database.update(database.stockBalances)
                  ..where((table) => table.id.equals(local.id)))
                .write(
              StockBalancesCompanion(
                quantity: Value(quantity),
                updatedAt: Value(updatedAt),
              ),
            );
            continue;
          }

          await database.into(database.stockBalances).insert(
                StockBalancesCompanion.insert(
                  id: balance.id,
                  variantId: balance.localVariantId,
                  warehouseId: balance.localWarehouseId,
                  quantity: Value(quantity),
                  updatedAt: updatedAt,
                ),
              );
        }
      });

      debugPrint(
        '[INVENTORY PULL] Local stock snapshot replaced successfully.',
      );

      debugPrint(
        '[INVENTORY PULL] Local balances count: ${mappedBalances.length}',
      );

      debugPrint(
        '[INVENTORY PULL] ========================================',
      );

      //
      // Inventory balances لا تستخدم Cursor حالياً.
      // الـPagination تتم بالكامل داخل هذا Gateway.
      //
      return const SyncPullResult(
        nextCursor: null,
        changes: [],
      );
    } on DioException catch (error) {
      _printDioError(
        action:
        'GET /inventory/balances',
        error: error,
      );

      rethrow;
    } catch (error) {
      debugPrint(
        '[INVENTORY PULL] FAILED: $error',
      );

      debugPrint(
        '[INVENTORY PULL] ========================================',
      );

      rethrow;
    }
  }

  // ===========================================================================
  // FETCH ALL INVENTORY BALANCE PAGES
  // ===========================================================================

  Future<List<_RemoteInventoryBalance>>
  _fetchAllRemoteBalances() async {
    final result =
    <_RemoteInventoryBalance>[];

    var page = 1;
    var totalGroups = 0;
    var fetchedGroups = 0;

    while (true) {
      debugPrint(
        '[INVENTORY PULL] GET /inventory/balances '
            'page=$page limit=$_pullPageLimit',
      );

      final response =
      await apiClient.get(
        '/inventory/balances'
            '?page=$page'
            '&limit=$_pullPageLimit',
      );

      _ensureSuccess(
        response.data,
        fallback:
        'تعذر سحب أرصدة المخزون.',
      );

      final body =
      _requiredMap(
        response.data,
        field:
        'inventory balances response',
      );

      final rawData =
      body['data'];

      if (rawData is! List) {
        throw StateError(
          'Inventory balances response has invalid data.',
        );
      }

      final rawMeta =
      body['meta'];

      if (rawMeta is! Map) {
        throw StateError(
          'Inventory balances response has invalid meta.',
        );
      }

      final meta =
      Map<String, dynamic>.from(
        rawMeta,
      );

      final currentPage =
      _requiredPositiveInt(
        meta['page'],
        field: 'meta.page',
      );

      final limit =
      _requiredPositiveInt(
        meta['limit'],
        field: 'meta.limit',
      );

      final total =
      _requiredNonNegativeInt(
        meta['total'],
        field: 'meta.total',
      );

      if (currentPage != page) {
        throw StateError(
          'Inventory pagination mismatch. '
              'Requested page $page but server returned $currentPage.',
        );
      }

      totalGroups = total;

      debugPrint(
        '[INVENTORY PULL] Page $currentPage received. '
            'Groups: ${rawData.length}, '
            'Total groups: $totalGroups',
      );

      if (rawData.isEmpty) {
        if (fetchedGroups < totalGroups) {
          throw StateError(
            'Inventory pagination ended before all balances were received. '
                'Fetched $fetchedGroups of $totalGroups groups.',
          );
        }

        break;
      }

      for (final rawItem
      in rawData) {
        final item =
        _requiredMap(
          rawItem,
          field:
          'inventory balance item',
        );

        final serverWarehouseId =
        _requiredString(
          item['warehouse_id'],
          field: 'warehouse_id',
        );

        final variants =
        item['variants'];

        if (variants is! List) {
          throw StateError(
            'Inventory balance item has invalid variants list. '
                'Warehouse: $serverWarehouseId',
          );
        }

        for (final rawVariant
        in variants) {
          final variant =
          _requiredMap(
            rawVariant,
            field:
            'inventory balance variant',
          );

          final serverVariantId =
          _requiredString(
            variant['variant_id'],
            field: 'variant_id',
          );

          final quantity =
          _requiredNonNegativeDouble(
            variant['quantity'],
            field: 'quantity',
          );

          final updatedAt =
          _requiredDateTime(
            variant['updated_at'],
            field: 'updated_at',
          );

          result.add(
            _RemoteInventoryBalance(
              serverWarehouseId:
              serverWarehouseId,
              serverVariantId:
              serverVariantId,
              quantity:
              quantity,
              updatedAt:
              updatedAt,
            ),
          );
        }
      }

      fetchedGroups +=
          rawData.length;

      if (fetchedGroups >=
          totalGroups) {
        break;
      }

      //
      // حماية إضافية إذا رجع السيرفر limit مختلف.
      //
      if (rawData.length < limit &&
          fetchedGroups < totalGroups) {
        throw StateError(
          'Inventory pagination is inconsistent. '
              'Page $page returned ${rawData.length} rows '
              'with limit $limit, but $totalGroups total rows were reported.',
        );
      }

      page++;
    }

    debugPrint(
      '[INVENTORY PULL] All pages downloaded.',
    );

    debugPrint(
      '[INVENTORY PULL] Product/Warehouse groups fetched: $fetchedGroups',
    );

    debugPrint(
      '[INVENTORY PULL] Variant balance rows fetched: ${result.length}',
    );

    return result;
  }

  // ===========================================================================
  // MAP SERVER IDS TO LOCAL IDS
  // ===========================================================================

  Future<List<_LocalInventoryBalance>>
  _mapRemoteBalancesToLocal(
      List<_RemoteInventoryBalance>
      remoteBalances,
      ) async {
    final result =
    <_LocalInventoryBalance>[];

    final warehouseCache =
    <String, Warehouse>{};

    final variantCache =
    <String, ProductVariant>{};

    final uniqueBalances =
    <String>{};

    for (final remote
    in remoteBalances) {
      var warehouse =
      warehouseCache[
      remote.serverWarehouseId];

      warehouse ??=
      await _getWarehouseByServerId(
        remote.serverWarehouseId,
      );

      if (warehouse == null) {
        throw StateError(
          'تعذر مزامنة رصيد المخزون لأن المخزن غير موجود محلياً. '
              'Server Warehouse ID: ${remote.serverWarehouseId}',
        );
      }

      warehouseCache[
      remote.serverWarehouseId] =
          warehouse;

      var variant =
      variantCache[
      remote.serverVariantId];

      variant ??=
      await _getVariantByServerId(
        remote.serverVariantId,
      );

      if (variant == null) {
        throw StateError(
          'تعذر مزامنة رصيد المخزون لأن الـVariant غير موجود محلياً. '
              'Server Variant ID: ${remote.serverVariantId}',
        );
      }

      variantCache[
      remote.serverVariantId] =
          variant;

      final uniqueKey =
          '${warehouse.id}::${variant.id}';

      if (!uniqueBalances.add(
        uniqueKey,
      )) {
        throw StateError(
          'السيرفر أعاد أكثر من رصيد لنفس Variant داخل نفس Warehouse. '
              'Warehouse: ${remote.serverWarehouseId}, '
              'Variant: ${remote.serverVariantId}',
        );
      }

      result.add(
        _LocalInventoryBalance(
          id: uniqueKey,
          localWarehouseId:
          warehouse.id,
          localVariantId:
          variant.id,
          quantity:
          remote.quantity,
          updatedAt:
          remote.updatedAt,
        ),
      );

      debugPrint(
        '[INVENTORY PULL] Mapped balance:',
      );

      debugPrint(
        '[INVENTORY PULL] Warehouse '
            '${remote.serverWarehouseId} -> ${warehouse.id}',
      );

      debugPrint(
        '[INVENTORY PULL] Variant '
            '${remote.serverVariantId} -> ${variant.id}',
      );

      debugPrint(
        '[INVENTORY PULL] Quantity: ${remote.quantity}',
      );
    }

    return result;
  }

  // ===========================================================================
  // RESPONSE
  // ===========================================================================

  void _ensureSuccess(
      dynamic data, {
        required String fallback,
      }) {
    if (data is! Map) {
      return;
    }

    final map =
    Map<String, dynamic>.from(
      data,
    );

    if (!map.containsKey('success')) {
      return;
    }

    if (map['success'] == true) {
      return;
    }

    final message =
    _extractMessage(
      data,
    );

    throw StateError(
      message ?? fallback,
    );
  }

  // ===========================================================================
  // VALUES
  // ===========================================================================

  Map<String, dynamic> _requiredMap(
      dynamic value, {
        required String field,
      }) {
    if (value is! Map) {
      throw StateError(
        'Invalid $field.',
      );
    }

    return Map<String, dynamic>.from(
      value,
    );
  }

  String _requiredString(
      dynamic value, {
        required String field,
      }) {
    final result =
    _nullableString(
      value,
    );

    if (result == null) {
      throw StateError(
        'Inventory sync payload is missing $field.',
      );
    }

    return result;
  }

  double _requiredPositiveDouble(
      dynamic value, {
        required String field,
      }) {
    final result =
    _toDouble(
      value,
    );

    if (result == null ||
        result <= 0) {
      throw StateError(
        'Inventory sync payload has invalid $field.',
      );
    }

    return result;
  }

  double _requiredNonNegativeDouble(
      dynamic value, {
        required String field,
      }) {
    final result =
    _toDouble(
      value,
    );

    if (result == null ||
        result < 0) {
      throw StateError(
        'Inventory balances response has invalid $field.',
      );
    }

    return result;
  }

  double? _toDouble(
      dynamic value,
      ) {
    if (value is num) {
      return value.toDouble();
    }

    if (value == null) {
      return null;
    }

    return double.tryParse(
      value.toString(),
    );
  }

  int _requiredPositiveInt(
      dynamic value, {
        required String field,
      }) {
    final result =
    _toInt(
      value,
    );

    if (result == null ||
        result <= 0) {
      throw StateError(
        'Inventory balances response has invalid $field.',
      );
    }

    return result;
  }

  int _requiredNonNegativeInt(
      dynamic value, {
        required String field,
      }) {
    final result =
    _toInt(
      value,
    );

    if (result == null ||
        result < 0) {
      throw StateError(
        'Inventory balances response has invalid $field.',
      );
    }

    return result;
  }

  int? _toInt(
      dynamic value,
      ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value == null) {
      return null;
    }

    return int.tryParse(
      value.toString(),
    );
  }

  DateTime _requiredDateTime(
      dynamic value, {
        required String field,
      }) {
    final text =
    _nullableString(
      value,
    );

    if (text == null) {
      throw StateError(
        'Inventory balances response is missing $field.',
      );
    }

    final parsed =
    DateTime.tryParse(
      text,
    );

    if (parsed == null) {
      throw StateError(
        'Inventory balances response has invalid $field: $text',
      );
    }

    return parsed;
  }

  String? _nullableString(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    final text =
    value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  // ===========================================================================
  // DIO ERROR
  // ===========================================================================

  void _printDioError({
    required String action,
    required DioException error,
    Map<String, dynamic>? requestBody,
  }) {
    debugPrint(
      '[INVENTORY SYNC] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!',
    );

    debugPrint(
      '[INVENTORY SYNC] REQUEST FAILED',
    );

    debugPrint(
      '[INVENTORY SYNC] Action: $action',
    );

    debugPrint(
      '[INVENTORY SYNC] Dio type: ${error.type}',
    );

    debugPrint(
      '[INVENTORY SYNC] Status: ${error.response?.statusCode}',
    );

    debugPrint(
      '[INVENTORY SYNC] Method: ${error.requestOptions.method}',
    );

    debugPrint(
      '[INVENTORY SYNC] URI: ${error.requestOptions.uri}',
    );

    if (requestBody != null) {
      debugPrint(
        '[INVENTORY SYNC] Request body:',
      );

      debugPrint(
        _prettyJson(
          requestBody,
        ),
      );
    }

    debugPrint(
      '[INVENTORY SYNC] Response:',
    );

    debugPrint(
      _prettyJson(
        error.response?.data,
      ),
    );

    final message =
    _extractMessage(
      error.response?.data,
    );

    if (message != null) {
      debugPrint(
        '[INVENTORY SYNC] Backend message: $message',
      );
    }

    debugPrint(
      '[INVENTORY SYNC] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!',
    );
  }

  String? _extractMessage(
      dynamic value,
      ) {
    if (value is! Map) {
      return null;
    }

    final map =
    Map<String, dynamic>.from(
      value,
    );

    final message =
    map['message'];

    if (message is String &&
        message.trim().isNotEmpty) {
      return message.trim();
    }

    if (message is List &&
        message.isNotEmpty) {
      return message
          .map(
            (item) => item.toString(),
      )
          .join('\n');
    }

    return null;
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

// =============================================================================
// REMOTE INVENTORY BALANCE
// =============================================================================

class _RemoteInventoryBalance {
  final String serverWarehouseId;
  final String serverVariantId;
  final double quantity;
  final DateTime updatedAt;

  const _RemoteInventoryBalance({
    required this.serverWarehouseId,
    required this.serverVariantId,
    required this.quantity,
    required this.updatedAt,
  });
}

// =============================================================================
// LOCAL INVENTORY BALANCE
// =============================================================================

class _LocalInventoryBalance {
  final String id;
  final String localWarehouseId;
  final String localVariantId;
  final double quantity;
  final DateTime updatedAt;

  const _LocalInventoryBalance({
    required this.id,
    required this.localWarehouseId,
    required this.localVariantId,
    required this.quantity,
    required this.updatedAt,
  });
}