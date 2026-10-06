import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_remote_gateway.dart';

class ProductsSyncRemoteGateway
    implements SyncRemoteGateway {
  final AppDatabase database;
  final ApiClient apiClient;

  static const Uuid _uuid = Uuid();

  ProductsSyncRemoteGateway({
    required this.database,
    required this.apiClient,
  });

  @override
  Set<String> get supportedEntityTypes => const {
    'product',
  };

  // ===========================================================================
  // PUSH OPERATION
  // ===========================================================================

  @override
  Future<void> pushOperation(
      SyncOutboxData operation,
      ) async {
    if (operation.entityType.toLowerCase() !=
        'product') {
      throw StateError(
        'Unsupported sync entity: ${operation.entityType}',
      );
    }

    final decoded = jsonDecode(
      operation.payloadJson,
    );

    if (decoded is! Map) {
      throw StateError(
        'Invalid product sync payload.',
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

    debugPrint(
      '[PRODUCT SYNC] ========================================',
    );
    debugPrint(
      '[PRODUCT SYNC] Local product ID: ${operation.entityId}',
    );
    debugPrint(
      '[PRODUCT SYNC] Operation: ${operation.operation}',
    );

    switch (syncOperation) {
      case SyncOperation.create:
        await _createProduct(
          localProductId:
          operation.entityId,
        );
        break;

      case SyncOperation.update:
        await _updateProduct(
          localProductId:
          operation.entityId,
          payload: payload,
        );
        break;

      case SyncOperation.delete:
        await _deleteProduct(
          localProductId:
          operation.entityId,
          payload: payload,
        );
        break;
    }

    debugPrint(
      '[PRODUCT SYNC] Operation completed.',
    );
    debugPrint(
      '[PRODUCT SYNC] ========================================',
    );
  }

  // ===========================================================================
  // CREATE
  // ===========================================================================

  Future<void> _createProduct({
    required String localProductId,
  }) async {
    final localProduct =
    await _getLocalProduct(
      localProductId,
    );

    if (localProduct == null) {
      throw StateError(
        'Local product not found: $localProductId',
      );
    }

    if ((localProduct.deletedAt != null || !localProduct.isActive) &&
        (localProduct.serverId ?? '').trim().isEmpty) {
      debugPrint(
        '[PRODUCT SYNC] CREATE skipped: inactive product has no server id.',
      );
      return;
    }

    final serverId =
        localProduct.serverId;

    final apiPayload =
    await _buildApiPayloadFromLocalProduct(
      localProduct,
    );

    debugPrint(
      '[PRODUCT SYNC] CREATE requested.',
    );
    debugPrint(
      '[PRODUCT SYNC] Local ID: $localProductId',
    );
    debugPrint(
      '[PRODUCT SYNC] Existing serverId: ${serverId ?? 'NULL'}',
    );
    debugPrint(
      '[PRODUCT SYNC] API payload:',
    );
    debugPrint(
      _prettyJson(
        apiPayload,
      ),
    );

    _validateApiPayload(
      apiPayload,
    );

    //
    // إذا الـPOST نجح سابقاً وتم حفظ serverId،
    // لا نعيد إنشاء المنتج مرة ثانية.
    //
    if (serverId != null &&
        serverId.trim().isNotEmpty) {
      final endpoint =
          '/products/$serverId';

      debugPrint(
        '[PRODUCT SYNC] Product already exists on server.',
      );
      debugPrint(
        '[PRODUCT SYNC] PATCH $endpoint',
      );

      try {
        final response =
        await apiClient.patch(
          endpoint,
          data: apiPayload,
        );

        _printSuccess(
          action: 'PATCH $endpoint',
          statusCode:
          response.statusCode,
          data: response.data,
        );

        await _saveVariantsFromServerResponse(
          localProductId:
          localProductId,
          responseData:
          response.data,
        );
      } on DioException catch (error) {
        _printDioError(
          action: 'PATCH $endpoint',
          error: error,
          requestBody: apiPayload,
        );

        rethrow;
      }

      return;
    }

    debugPrint(
      '[PRODUCT SYNC] POST /products',
    );

    try {
      final response =
      await apiClient.post(
        '/products',
        data: apiPayload,
      );

      _printSuccess(
        action: 'POST /products',
        statusCode:
        response.statusCode,
        data: response.data,
      );

      final createdServerId =
      _extractServerId(
        response.data,
      );

      debugPrint(
        '[PRODUCT SYNC] Server ID received: $createdServerId',
      );

      await database.transaction(
            () async {
          await _saveServerId(
            localProductId:
            localProductId,
            serverId:
            createdServerId,
          );

          await _saveVariantsFromServerResponse(
            localProductId:
            localProductId,
            responseData:
            response.data,
          );
        },
      );

      debugPrint(
        '[PRODUCT SYNC] Product and Variant Server IDs saved locally.',
      );
    } on DioException catch (error) {
      _printDioError(
        action: 'POST /products',
        error: error,
        requestBody: apiPayload,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // UPDATE
  // ===========================================================================

  Future<void> _updateProduct({
    required String localProductId,
    required Map<String, dynamic> payload,
  }) async {
    final action =
    payload['sync_action']
        ?.toString();

    debugPrint(
      '[PRODUCT SYNC] UPDATE requested.',
    );
    debugPrint(
      '[PRODUCT SYNC] sync_action: ${action ?? 'NULL'}',
    );

    if (action ==
        'toggle_active') {
      await _toggleProduct(
        localProductId:
        localProductId,
      );

      return;
    }

    final localProduct =
    await _getLocalProduct(
      localProductId,
    );

    if (localProduct == null) {
      throw StateError(
        'Local product not found: $localProductId',
      );
    }

    var serverId =
        localProduct.serverId;

    final apiPayload =
    await _buildApiPayloadFromLocalProduct(
      localProduct,
    );

    debugPrint(
      '[PRODUCT SYNC] Current local product payload:',
    );
    debugPrint(
      _prettyJson(
        apiPayload,
      ),
    );

    _validateApiPayload(
      apiPayload,
    );

    //
    // منتج محلي لم يرفع سابقاً.
    //
    if (serverId == null ||
        serverId.trim().isEmpty) {
      debugPrint(
        '[PRODUCT SYNC] Product has no serverId.',
      );
      debugPrint(
        '[PRODUCT SYNC] POST /products',
      );

      try {
        final response =
        await apiClient.post(
          '/products',
          data: apiPayload,
        );

        _printSuccess(
          action: 'POST /products',
          statusCode:
          response.statusCode,
          data: response.data,
        );

        serverId =
            _extractServerId(
              response.data,
            );

        debugPrint(
          '[PRODUCT SYNC] Server ID received: $serverId',
        );

        await database.transaction(
              () async {
            await _saveServerId(
              localProductId:
              localProductId,
              serverId:
              serverId!,
            );

            await _saveVariantsFromServerResponse(
              localProductId:
              localProductId,
              responseData:
              response.data,
            );
          },
        );

        debugPrint(
          '[PRODUCT SYNC] Product and Variant Server IDs saved locally.',
        );
      } on DioException catch (error) {
        _printDioError(
          action: 'POST /products',
          error: error,
          requestBody: apiPayload,
        );

        rethrow;
      }

      return;
    }

    final endpoint =
        '/products/$serverId';

    debugPrint(
      '[PRODUCT SYNC] PATCH $endpoint',
    );

    try {
      final response =
      await apiClient.patch(
        endpoint,
        data: apiPayload,
      );

      _printSuccess(
        action: 'PATCH $endpoint',
        statusCode:
        response.statusCode,
        data: response.data,
      );

      await _saveVariantsFromServerResponse(
        localProductId:
        localProductId,
        responseData:
        response.data,
      );
    } on DioException catch (error) {
      _printDioError(
        action: 'PATCH $endpoint',
        error: error,
        requestBody: apiPayload,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // DELETE
  // ===========================================================================

  Future<void> _deleteProduct({
    required String localProductId,
    required Map<String, dynamic> payload,
  }) async {
    final localProduct =
    await _getLocalProduct(
      localProductId,
    );

    if (localProduct == null) {
      debugPrint(
        '[PRODUCT SYNC] DELETE ignored: local product not found.',
      );

      return;
    }

    final serverId =
        localProduct.serverId;

    if (serverId == null ||
        serverId.trim().isEmpty) {
      debugPrint(
        '[PRODUCT SYNC] DELETE ignored: product was never uploaded.',
      );

      return;
    }

    final wasActive =
        payload['was_active'] ==
            true;

    //
    // Backend الحالي لا يحتوي DELETE Product.
    //
    if (!wasActive) {
      debugPrint(
        '[PRODUCT SYNC] DELETE ignored: product already inactive.',
      );

      return;
    }

    final endpoint =
        '/products/$serverId/toggle-active';

    debugPrint(
      '[PRODUCT SYNC] DELETE translated to toggle-active.',
    );
    debugPrint(
      '[PRODUCT SYNC] PATCH $endpoint',
    );

    try {
      final response =
      await apiClient.patch(
        endpoint,
      );

      _printSuccess(
        action: 'PATCH $endpoint',
        statusCode:
        response.statusCode,
        data: response.data,
      );
    } on DioException catch (error) {
      _printDioError(
        action: 'PATCH $endpoint',
        error: error,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // TOGGLE ACTIVE
  // ===========================================================================

  Future<void> _toggleProduct({
    required String localProductId,
  }) async {
    final localProduct =
    await _getLocalProduct(
      localProductId,
    );

    if (localProduct == null) {
      throw StateError(
        'Local product not found: $localProductId',
      );
    }

    final serverId =
        localProduct.serverId;

    if (serverId == null ||
        serverId.trim().isEmpty) {
      throw StateError(
        'Product has no serverId yet: $localProductId',
      );
    }

    final endpoint =
        '/products/$serverId/toggle-active';

    debugPrint(
      '[PRODUCT SYNC] PATCH $endpoint',
    );

    try {
      final response =
      await apiClient.patch(
        endpoint,
      );

      _printSuccess(
        action: 'PATCH $endpoint',
        statusCode:
        response.statusCode,
        data: response.data,
      );
    } on DioException catch (error) {
      _printDioError(
        action: 'PATCH $endpoint',
        error: error,
      );

      rethrow;
    }
  }

  Future<void> _publishLocalCatalog(Product product) async {
    final categoryId = product.categoryId?.trim() ?? '';
    if (categoryId.isNotEmpty) {
      final serverCategoryId = await _serverCategoryId(categoryId);
      if (serverCategoryId != categoryId) {
        await _replaceCategoryId(categoryId, serverCategoryId);
      }
    }

    final unitId = product.baseUnitId?.trim() ?? '';
    if (unitId.isNotEmpty) {
      final serverUnitId = await _serverUnitId(unitId);
      if (serverUnitId != unitId) {
        await _replaceUnitId(unitId, serverUnitId);
      }
    }
  }

  Future<String> _serverCategoryId(String localId) async {
    final remote = await _apiMaps('/categories');
    for (final row in remote) {
      if ('${row['id']}' == localId) {
        return localId;
      }
    }

    final local = await (database.select(database.categories)
          ..where((table) => table.id.equals(localId)))
        .getSingleOrNull();
    final name = local?.nameAr.trim() ?? '';
    if (name.isEmpty) {
      return localId;
    }

    for (final row in remote) {
      if ('${row['name_ar'] ?? ''}'.trim() == name) {
        return '${row['id']}';
      }
    }

    final response = await apiClient.post(
      '/categories',
      data: {'name_ar': name},
    );
    final created = await _apiMaps(response.data);
    if (created.isEmpty || '${created.first['id']}'.isEmpty) {
      throw StateError('تعذر رفع تصنيف "$name" قبل المادة.');
    }
    return '${created.first['id']}';
  }

  Future<String> _serverUnitId(String localId) async {
    final remote = await _apiMaps('/units');
    for (final row in remote) {
      if ('${row['id']}' == localId) {
        return localId;
      }
    }

    final local = await (database.select(database.units)
          ..where((table) => table.id.equals(localId)))
        .getSingleOrNull();
    final name = local?.nameAr.trim() ?? '';
    if (name.isEmpty) {
      return localId;
    }

    for (final row in remote) {
      if ('${row['name_ar'] ?? ''}'.trim() == name) {
        return '${row['id']}';
      }
    }

    final response = await apiClient.post(
      '/units',
      data: {
        'name_ar': name,
        'symbol': (local?.symbol.trim().isNotEmpty ?? false)
            ? local!.symbol.trim()
            : name,
        'is_base_unit': local?.isBaseUnit ?? true,
      },
    );
    final created = await _apiMaps(response.data);
    if (created.isEmpty || '${created.first['id']}'.isEmpty) {
      throw StateError('تعذر رفع وحدة "$name" قبل المادة.');
    }
    return '${created.first['id']}';
  }

  Future<List<Map<String, dynamic>>> _apiMaps(dynamic source) async {
    dynamic raw = source;
    if (source is String) {
      final response = await apiClient.get(source);
      raw = response.data;
    }
    if (raw is Map && raw['data'] != null) {
      raw = raw['data'];
    }
    if (raw is Map && raw['id'] != null) {
      return [Map<String, dynamic>.from(raw)];
    }
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
    return const [];
  }

  Future<void> _replaceCategoryId(String localId, String serverId) async {
    await (database.update(database.products)
          ..where((table) => table.categoryId.equals(localId)))
        .write(ProductsCompanion(categoryId: Value(serverId)));

    final local = await (database.select(database.categories)
          ..where((table) => table.id.equals(localId)))
        .getSingleOrNull();
    final server = await (database.select(database.categories)
          ..where((table) => table.id.equals(serverId)))
        .getSingleOrNull();
    if (local != null && server == null) {
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: serverId,
              nameAr: local.nameAr,
              nameEn: Value(local.nameEn),
              parentId: Value(local.parentId),
              level: Value(local.level),
              path: Value(local.path),
              imageUrl: Value(local.imageUrl),
              orderIndex: Value(local.orderIndex),
              isActive: Value(local.isActive),
              createdAt: Value(local.createdAt),
              updatedAt: Value(local.updatedAt),
            ),
          );
    }
    if (local != null) {
      await (database.delete(database.categories)
            ..where((table) => table.id.equals(localId)))
          .go();
    }
  }

  Future<void> _replaceUnitId(String localId, String serverId) async {
    await (database.update(database.products)
          ..where((table) => table.baseUnitId.equals(localId)))
        .write(ProductsCompanion(baseUnitId: Value(serverId)));
    await (database.update(database.saleItems)
          ..where((table) => table.unitId.equals(localId)))
        .write(SaleItemsCompanion(unitId: Value(serverId)));
    await (database.update(database.purchaseItems)
          ..where((table) => table.unitId.equals(localId)))
        .write(PurchaseItemsCompanion(unitId: Value(serverId)));
    await (database.update(database.heldSaleItems)
          ..where((table) => table.unitId.equals(localId)))
        .write(HeldSaleItemsCompanion(unitId: Value(serverId)));
    await (database.update(database.units)
          ..where((table) => table.parentUnitId.equals(localId)))
        .write(UnitsCompanion(parentUnitId: Value(serverId)));

    final local = await (database.select(database.units)
          ..where((table) => table.id.equals(localId)))
        .getSingleOrNull();
    final server = await (database.select(database.units)
          ..where((table) => table.id.equals(serverId)))
        .getSingleOrNull();
    if (local != null && server == null) {
      await database.into(database.units).insert(
            UnitsCompanion.insert(
              id: serverId,
              nameAr: local.nameAr,
              nameEn: Value(local.nameEn),
              symbol: local.symbol,
              parentUnitId: Value(local.parentUnitId),
              conversionFactor: Value(local.conversionFactor),
              isBaseUnit: Value(local.isBaseUnit),
              isActive: Value(local.isActive),
              createdAt: Value(local.createdAt),
              updatedAt: Value(local.updatedAt),
            ),
          );
    }
    if (local != null) {
      await (database.delete(database.units)
            ..where((table) => table.id.equals(localId)))
          .go();
    }
  }

  // ===========================================================================
  // BUILD API PAYLOAD
  // ===========================================================================

  Future<Map<String, dynamic>>
  _buildApiPayloadFromLocalProduct(
      Product product,
      ) async {
    await _publishLocalCatalog(product);
    product = await _getLocalProduct(product.id) ?? product;

    final localVariants =
    await _getLocalVariants(
      product.id,
    );

    final variantsPayload =
    <Map<String, dynamic>>[];

    if (product.hasVariants) {
      for (final variant
      in localVariants) {
        final attributes =
        _decodeAttributes(
          variant.attributesJson,
        );

        variantsPayload.add({
          'barcode':
          _nullableString(
            variant.barcode,
          ),
          'sku':
          _nullableString(
            variant.sku,
          ),
          'attributes':
          attributes,
          'pricing': {
            'cost_price':
            variant.costPrice,
            'rep_price':
            variant
                .representativePrice,
            'wholesale_price':
            variant
                .wholesalePrice,
            'retail_price':
            variant
                .retailPrice,
          },
        });
      }
    }

    final payload = {
      'name_ar':
      product.name.trim(),

      'name_en':
      _nullableString(
        product.nameEn,
      ),

      'barcode':
      _nullableString(
        product.barcode,
      ),

      'sku':
      _nullableString(
        product.sku,
      ),

      'category_id':
      _nullableString(
        product.categoryId,
      ),

      'base_unit_id':
      _nullableString(
        product.baseUnitId,
      ),

      'description':
      _nullableString(
        product.description,
      ),

      'min_stock_level':
      product.minimumStock,

      'has_variants':
      product.hasVariants,

      'has_expiry':
      product.hasExpiry,

      'has_serial':
      product.hasSerial,

      'image_url':
      _httpImageUrl(
        product.imageUrl,
      ),

      'pricing': {
        'cost_price':
        product.costPrice,
        'rep_price':
        product.representativePrice,
        'wholesale_price':
        product.wholesalePrice,
        'retail_price':
        product.retailPrice,
      },

      'variants':
      variantsPayload,
    };
    if (payload['image_url'] == null) {
      payload.remove('image_url');
    }
    return payload;
  }

  // ===========================================================================
  // VALIDATE PRODUCT PAYLOAD
  // ===========================================================================

  void _validateApiPayload(
      Map<String, dynamic> payload,
      ) {
    final nameAr =
    payload['name_ar']
        ?.toString()
        .trim();

    if (nameAr == null ||
        nameAr.isEmpty) {
      throw StateError(
        'Product cannot sync: Arabic name is missing.',
      );
    }

    final categoryId =
    payload['category_id']
        ?.toString()
        .trim();

    if (categoryId == null ||
        categoryId.isEmpty) {
      throw StateError(
        'Product cannot sync: categoryId is missing. '
            'Edit the product and select its category again.',
      );
    }

    final baseUnitId =
    payload['base_unit_id']
        ?.toString()
        .trim();

    if (baseUnitId == null ||
        baseUnitId.isEmpty) {
      throw StateError(
        'Product cannot sync: baseUnitId is missing. '
            'Edit the product and select its unit again.',
      );
    }

    _validatePricing(
      payload['pricing'],
      label: 'product',
    );

    final hasVariants =
        payload['has_variants'] ==
            true;

    final variants =
    payload['variants'];

    if (variants is! List) {
      throw StateError(
        'Product cannot sync: variants must be a list.',
      );
    }

    if (hasVariants &&
        variants.isEmpty) {
      throw StateError(
        'Product cannot sync: product is marked as having variants '
            'but no variants were found locally.',
      );
    }

    for (var index = 0;
    index < variants.length;
    index++) {
      final rawVariant =
      variants[index];

      if (rawVariant is! Map) {
        throw StateError(
          'Product cannot sync: invalid variant at index $index.',
        );
      }

      final variant =
      Map<String, dynamic>.from(
        rawVariant,
      );

      final attributes =
      variant['attributes'];

      if (attributes is! Map ||
          attributes.isEmpty) {
        throw StateError(
          'Product cannot sync: variant ${index + 1} has no attributes.',
        );
      }

      var validAttributeFound =
      false;

      for (final entry
      in attributes.entries) {
        final key =
        entry.key
            .toString()
            .trim();

        final value =
        entry.value
            ?.toString()
            .trim();

        if (key.isNotEmpty &&
            value != null &&
            value.isNotEmpty) {
          validAttributeFound =
          true;
          break;
        }
      }

      if (!validAttributeFound) {
        throw StateError(
          'Product cannot sync: variant ${index + 1} has invalid attributes.',
        );
      }

      _validatePricing(
        variant['pricing'],
        label:
        'variant ${index + 1}',
      );
    }
  }

  void _validatePricing(
      dynamic rawPricing, {
        required String label,
      }) {
    if (rawPricing is! Map) {
      throw StateError(
        'Product cannot sync: $label pricing is missing.',
      );
    }

    final pricing =
    Map<dynamic, dynamic>.from(
      rawPricing,
    );

    final cost =
    pricing['cost_price'];

    final rep =
    pricing['rep_price'];

    final wholesale =
    pricing['wholesale_price'];

    final retail =
    pricing['retail_price'];

    if (cost is! num ||
        rep is! num ||
        wholesale is! num ||
        retail is! num) {
      throw StateError(
        'Product cannot sync: invalid $label pricing.',
      );
    }

    if (cost < 0 ||
        rep < 0 ||
        wholesale < 0 ||
        retail < 0) {
      throw StateError(
        'Product cannot sync: $label prices cannot be negative.',
      );
    }
  }

  // ===========================================================================
  // SAVE VARIANTS FROM PUSH RESPONSE
  // ===========================================================================

  Future<void>
  _saveVariantsFromServerResponse({
    required String localProductId,
    required dynamic responseData,
  }) async {
    final serverVariants =
    _extractServerVariants(
      responseData,
    );

    if (serverVariants.isEmpty) {
      debugPrint(
        '[PRODUCT SYNC] No product_variants found in response.',
      );

      return;
    }

    final localProduct =
    await _getLocalProduct(
      localProductId,
    );

    if (localProduct == null) {
      return;
    }

    final localVariants =
    await _getLocalVariants(
      localProductId,
    );

    //
    // مهم:
    // المنتج البسيط أيضاً يرجع من السيرفر Default Variant.
    // إذا ما عدنا Variant محلي، ننشئه.
    //
    if (localVariants.isEmpty) {
      for (final serverVariant
      in serverVariants) {
        await _insertServerVariantLocally(
          localProductId:
          localProductId,
          serverVariant:
          serverVariant,
          fallbackProduct:
          localProduct,
        );
      }

      debugPrint(
        '[PRODUCT SYNC] Server/default variants created locally.',
      );

      return;
    }

    final usedServerIds =
    <String>{};

    for (final localVariant
    in localVariants) {
      Map<String, dynamic>?
      matchedServerVariant;

      // -----------------------------------------------------------------------
      // 1. Existing serverId
      // -----------------------------------------------------------------------

      final currentServerId =
      _nullableString(
        localVariant.serverId,
      );

      if (currentServerId != null) {
        for (final serverVariant
        in serverVariants) {
          final id =
          _nullableString(
            serverVariant['id'],
          );

          if (id == currentServerId) {
            matchedServerVariant =
                serverVariant;
            break;
          }
        }
      }

      // -----------------------------------------------------------------------
      // 2. Match by SKU
      // -----------------------------------------------------------------------

      if (matchedServerVariant ==
          null) {
        final localSku =
        _nullableString(
          localVariant.sku,
        );

        if (localSku != null) {
          for (final serverVariant
          in serverVariants) {
            final serverVariantId =
            _nullableString(
              serverVariant['id'],
            );

            if (serverVariantId ==
                null ||
                usedServerIds.contains(
                  serverVariantId,
                )) {
              continue;
            }

            final serverSku =
            _nullableString(
              serverVariant['sku'],
            );

            if (serverSku ==
                localSku) {
              matchedServerVariant =
                  serverVariant;
              break;
            }
          }
        }
      }

      // -----------------------------------------------------------------------
      // 3. Match by Barcode
      // -----------------------------------------------------------------------

      if (matchedServerVariant ==
          null) {
        final localBarcode =
        _nullableString(
          localVariant.barcode,
        );

        if (localBarcode != null) {
          for (final serverVariant
          in serverVariants) {
            final serverVariantId =
            _nullableString(
              serverVariant['id'],
            );

            if (serverVariantId ==
                null ||
                usedServerIds.contains(
                  serverVariantId,
                )) {
              continue;
            }

            final serverBarcode =
            _nullableString(
              serverVariant['barcode'],
            );

            if (serverBarcode ==
                localBarcode) {
              matchedServerVariant =
                  serverVariant;
              break;
            }
          }
        }
      }

      // -----------------------------------------------------------------------
      // 4. Match by Attributes
      // -----------------------------------------------------------------------

      if (matchedServerVariant ==
          null) {
        final localAttributes =
        _decodeAttributes(
          localVariant.attributesJson,
        );

        for (final serverVariant
        in serverVariants) {
          final serverVariantId =
          _nullableString(
            serverVariant['id'],
          );

          if (serverVariantId ==
              null ||
              usedServerIds.contains(
                serverVariantId,
              )) {
            continue;
          }

          final serverAttributes =
          _normalizeAttributes(
            serverVariant[
            'attributes'],
          );

          if (_attributesEqual(
            localAttributes,
            serverAttributes,
          )) {
            matchedServerVariant =
                serverVariant;
            break;
          }
        }
      }

      if (matchedServerVariant ==
          null) {
        debugPrint(
          '[PRODUCT SYNC] Could not map local variant ${localVariant.id}.',
        );

        continue;
      }

      final variantServerId =
      _nullableString(
        matchedServerVariant['id'],
      );

      if (variantServerId == null) {
        continue;
      }

      usedServerIds.add(
        variantServerId,
      );

      final pricing =
      _extractVariantPricing(
        matchedServerVariant,
      );

      await (database.update(
        database.productVariants,
      )
        ..where(
              (table) =>
              table.id.equals(
                localVariant.id,
              ),
        ))
          .write(
        ProductVariantsCompanion(
          serverId:
          Value(
            variantServerId,
          ),
          barcode:
          Value(
            _nullableString(
              matchedServerVariant[
              'barcode'],
            ),
          ),
          sku:
          Value(
            _nullableString(
              matchedServerVariant[
              'sku'],
            ),
          ),
          attributesJson:
          Value(
            jsonEncode(
              _normalizeAttributes(
                matchedServerVariant[
                'attributes'],
              ),
            ),
          ),
          costPrice:
          Value(
            pricing.cost,
          ),
          representativePrice:
          Value(
            pricing.rep,
          ),
          wholesalePrice:
          Value(
            pricing.wholesale,
          ),
          retailPrice:
          Value(
            pricing.retail,
          ),
          weightedAverageCost:
          Value(
            _toDouble(
              matchedServerVariant[
              'weighted_avg_cost'],
            ),
          ),
          lastPurchasePrice:
          Value(
            _toDouble(
              matchedServerVariant[
              'last_purchase_price'],
            ),
          ),
          isActive:
          Value(
            _toBool(
              matchedServerVariant[
              'is_active'],
              fallback: true,
            ),
          ),
          updatedAt:
          Value(
            _parseDateTime(
              matchedServerVariant[
              'updated_at'],
            ) ??
                DateTime.now(),
          ),
        ),
      );

      debugPrint(
        '[PRODUCT SYNC] Variant mapped:',
      );
      debugPrint(
        '[PRODUCT SYNC] local=${localVariant.id}',
      );
      debugPrint(
        '[PRODUCT SYNC] server=$variantServerId',
      );
    }

    //
    // إذا السيرفر عنده Variant غير موجود محلياً،
    // ننشئه محلياً.
    //
    for (final serverVariant
    in serverVariants) {
      final serverVariantId =
      _nullableString(
        serverVariant['id'],
      );

      if (serverVariantId == null) {
        continue;
      }

      final existing =
      await _getLocalVariantByServerId(
        serverVariantId,
      );

      if (existing != null) {
        continue;
      }

      await _insertServerVariantLocally(
        localProductId:
        localProductId,
        serverVariant:
        serverVariant,
        fallbackProduct:
        localProduct,
      );
    }
  }

  // ===========================================================================
  // PULL
  // ===========================================================================

  @override
  Future<SyncPullResult> pullChanges({
    String? cursor,
  }) async {
    debugPrint(
      '[PRODUCT PULL] ========================================',
    );
    debugPrint(
      '[PRODUCT PULL] Starting products pull...',
    );

    try {
      var page = 1;
      const limit = 20;
      var totalPages = 1;

      do {
        debugPrint(
          '[PRODUCT PULL] GET /products?page=$page&limit=$limit',
        );

        final response =
        await apiClient.get(
          '/products',
          queryParameters: {
            'page': page,
            'limit': limit,
          },
        );

        final root =
        _asStringMap(
          response.data,
        );

        final rawProducts =
        root['data'];

        if (rawProducts is! List) {
          throw StateError(
            'GET /products returned invalid data.',
          );
        }

        final meta =
        _asStringMap(
          root['meta'],
        );

        totalPages =
            _toInt(
              meta['totalPages'],
              fallback: 1,
            );

        debugPrint(
          '[PRODUCT PULL] Page $page/$totalPages - ${rawProducts.length} products.',
        );

        for (final rawProduct
        in rawProducts) {
          if (rawProduct is! Map) {
            continue;
          }

          final summary =
          Map<String, dynamic>.from(
            rawProduct,
          );

          final serverProductId =
          _nullableString(
            summary['id'],
          );

          if (serverProductId ==
              null) {
            continue;
          }

          await _pullSingleProduct(
            serverProductId,
          );
        }

        page++;
      } while (page <=
          totalPages);

      debugPrint(
        '[PRODUCT PULL] Pull completed successfully.',
      );
      debugPrint(
        '[PRODUCT PULL] ========================================',
      );

      //
      // حالياً SyncService يعتمد Side Effects داخل Gateway.
      // لا يوجد Incremental Change Feed من Backend.
      //
      return const SyncPullResult(
        nextCursor: null,
        changes: [],
      );
    } on DioException catch (error) {
      _printDioError(
        action: 'PULL PRODUCTS',
        error: error,
      );

      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
        '[PRODUCT PULL] ERROR: $error',
      );
      debugPrint(
        '[PRODUCT PULL] STACK: $stackTrace',
      );

      rethrow;
    }
  }

  Future<void> _pullSingleProduct(
      String serverProductId,
      ) async {
    final endpoint =
        '/products/$serverProductId';

    debugPrint(
      '[PRODUCT PULL] GET $endpoint',
    );

    final response =
    await apiClient.get(
      endpoint,
    );

    final root =
    _asStringMap(
      response.data,
    );

    dynamic rawData =
    root['data'];

    if (rawData is! Map) {
      rawData =
          response.data;
    }

    if (rawData is! Map) {
      throw StateError(
        'Invalid product details response for $serverProductId.',
      );
    }

    final serverProduct =
    Map<String, dynamic>.from(
      rawData,
    );

    await _upsertServerProduct(
      serverProduct,
    );
  }

  // ===========================================================================
  // UPSERT SERVER PRODUCT
  // ===========================================================================

  Future<void> _upsertServerProduct(
      Map<String, dynamic> serverProduct,
      ) async {
    final serverId =
    _nullableString(
      serverProduct['id'],
    );

    if (serverId == null) {
      throw StateError(
        'Server product has no id.',
      );
    }

    var localProduct =
    await _getLocalProductByServerId(
      serverId,
    );

    //
    // إذا عدنا منتج محلي مربوط بهذا serverId
    // وعليه عمليات محلية Pending/Failed/Syncing،
    // لا نخلي الـPull يكتب فوق التعديلات المحلية.
    //
    if (localProduct != null) {
      final hasPendingChanges =
      await _productHasUnsyncedChanges(
        localProduct.id,
      );

      if (hasPendingChanges) {
        debugPrint(
          '[PRODUCT PULL] Skipped $serverId because local changes are pending.',
        );
        await _writeProductImage(
          localProduct.id,
          serverProduct['image_url'],
        );
        return;
      }
    }

    if (localProduct == null) {
      final linked = await _findLocalProductForPhoto(
        serverId,
        serverProduct,
      );
      if (linked != null) {
        await _writeProductImage(
          linked.id,
          serverProduct['image_url'],
        );
        if (await _productHasUnsyncedChanges(linked.id)) {
          return;
        }
        if ((linked.serverId ?? '').trim().isEmpty) {
          await (database.update(database.products)
                ..where((table) => table.id.equals(linked.id)))
              .write(
            ProductsCompanion(
              serverId: Value(serverId),
            ),
          );
        }
        localProduct = linked;
      }
    }

    final category =
    _asStringMap(
      serverProduct['categories'],
    );

    final unit =
    _asStringMap(
      serverProduct[
      'units_of_measure'],
    );

    final serverVariants =
    _extractServerVariantsFromProduct(
      serverProduct,
    );

    final firstVariant =
    serverVariants.isEmpty
        ? null
        : serverVariants.first;

    final parentPricing =
    firstVariant == null
        ? const _VariantPricing()
        : _extractVariantPricing(
      firstVariant,
    );

    final localProductId =
        localProduct?.id ??
            _uuid.v4();

    final now =
    DateTime.now();

    final createdAt =
        _parseDateTime(
          serverProduct[
          'created_at'],
        ) ??
            localProduct
                ?.createdAt ??
            now;

    final updatedAt =
        _parseDateTime(
          serverProduct[
          'updated_at'],
        ) ??
            now;

    await database.transaction(
          () async {
        await database
            .into(
          database.products,
        )
            .insertOnConflictUpdate(
          ProductsCompanion(
            id:
            Value(
              localProductId,
            ),
            serverId:
            Value(
              serverId,
            ),
            barcode:
            Value(
              _nullableString(
                serverProduct[
                'barcode'],
              ),
            ),
            sku:
            Value(
              _nullableString(
                serverProduct[
                'sku'],
              ),
            ),
            name:
            Value(
              serverProduct[
              'name_ar']
                  ?.toString() ??
                  '',
            ),
            nameEn:
            Value(
              _nullableString(
                serverProduct[
                'name_en'],
              ),
            ),
            categoryId:
            Value(
              _nullableString(
                serverProduct[
                'category_id'],
              ),
            ),
            categoryName:
            Value(
              _nullableString(
                category[
                'name_ar'],
              ),
            ),
            baseUnitId:
            Value(
              _nullableString(
                serverProduct[
                'base_unit_id'],
              ),
            ),
            unit:
            Value(
              _nullableString(
                unit['name_ar'],
              ) ??
                  'قطعة',
            ),
            description:
            Value(
              _nullableString(
                serverProduct[
                'description'],
              ),
            ),
            hasVariants:
            Value(
              _toBool(
                serverProduct[
                'has_variants'],
              ),
            ),
            hasExpiry:
            Value(
              _toBool(
                serverProduct[
                'has_expiry'],
              ),
            ),
            hasSerial:
            Value(
              _toBool(
                serverProduct[
                'has_serial'],
              ),
            ),
            imageUrl:
            Value(
              _nullableString(
                serverProduct[
                'image_url'],
              ),
            ),
            costPrice:
            Value(
              parentPricing.cost,
            ),
            representativePrice:
            Value(
              parentPricing.rep,
            ),
            wholesalePrice:
            Value(
              parentPricing.wholesale,
            ),
            retailPrice:
            Value(
              parentPricing.retail,
            ),
            minimumStock:
            Value(
              _toDouble(
                serverProduct[
                'min_stock_level'],
              ),
            ),
            isActive:
            Value(
              _toBool(
                serverProduct[
                'is_active'],
                fallback: true,
              ),
            ),
            createdAt:
            Value(
              createdAt,
            ),
            updatedAt:
            Value(
              updatedAt,
            ),
            deletedAt:
            _toBool(
              serverProduct['is_active'],
              fallback: true,
            )
                ? const Value(null)
                : Value(DateTime.now()),
          ),
        );

        for (final serverVariant
        in serverVariants) {
          await _upsertServerVariant(
            localProductId:
            localProductId,
            serverVariant:
            serverVariant,
            fallbackProduct:
            await _getLocalProduct(
              localProductId,
            ) ??
                localProduct,
          );
        }
      },
    );

    localProduct =
    await _getLocalProduct(
      localProductId,
    );

    debugPrint(
      '[PRODUCT PULL] Product saved locally:',
    );
    debugPrint(
      '[PRODUCT PULL] local=$localProductId',
    );
    debugPrint(
      '[PRODUCT PULL] server=$serverId',
    );
    debugPrint(
      '[PRODUCT PULL] variants=${serverVariants.length}',
    );
  }

  // ===========================================================================
  // UPSERT SERVER VARIANT
  // ===========================================================================

  Future<void> _upsertServerVariant({
    required String localProductId,
    required Map<String, dynamic> serverVariant,
    Product? fallbackProduct,
  }) async {
    final serverVariantId =
    _nullableString(
      serverVariant['id'],
    );

    if (serverVariantId == null) {
      return;
    }

    var localVariant =
    await _getLocalVariantByServerId(
      serverVariantId,
    );

    //
    // إذا ما عندنا serverId سابقاً،
    // نحاول نطابق SKU ثم Barcode ثم Attributes.
    //
    localVariant ??=
    await _findMatchingLocalVariant(
      localProductId:
      localProductId,
      serverVariant:
      serverVariant,
    );

    final localVariantId =
        localVariant?.id ??
            _uuid.v4();

    final pricing =
    _extractVariantPricing(
      serverVariant,
    );

    final now =
    DateTime.now();

    await database
        .into(
      database.productVariants,
    )
        .insertOnConflictUpdate(
      ProductVariantsCompanion(
        id:
        Value(
          localVariantId,
        ),
        serverId:
        Value(
          serverVariantId,
        ),
        productId:
        Value(
          localProductId,
        ),
        barcode:
        Value(
          _nullableString(
            serverVariant[
            'barcode'],
          ),
        ),
        sku:
        Value(
          _nullableString(
            serverVariant[
            'sku'],
          ),
        ),
        attributesJson:
        Value(
          jsonEncode(
            _normalizeAttributes(
              serverVariant[
              'attributes'],
            ),
          ),
        ),
        costPrice:
        Value(
          pricing.cost,
        ),
        representativePrice:
        Value(
          pricing.rep,
        ),
        wholesalePrice:
        Value(
          pricing.wholesale,
        ),
        retailPrice:
        Value(
          pricing.retail,
        ),
        weightedAverageCost:
        Value(
          _toDouble(
            serverVariant[
            'weighted_avg_cost'],
            fallback:
            pricing.cost,
          ),
        ),
        lastPurchasePrice:
        Value(
          _toDouble(
            serverVariant[
            'last_purchase_price'],
            fallback:
            pricing.cost,
          ),
        ),
        isActive:
        Value(
          _toBool(
            serverVariant[
            'is_active'],
            fallback: true,
          ),
        ),
        serverVersion:
        Value(
          localVariant
              ?.serverVersion ??
              0,
        ),
        createdAt:
        Value(
          _parseDateTime(
            serverVariant[
            'created_at'],
          ) ??
              localVariant
                  ?.createdAt ??
              now,
        ),
        updatedAt:
        Value(
          _parseDateTime(
            serverVariant[
            'updated_at'],
          ) ??
              now,
        ),
        deletedAt:
        const Value(
          null,
        ),
      ),
    );

    debugPrint(
      '[PRODUCT PULL] Variant saved:',
    );
    debugPrint(
      '[PRODUCT PULL] local=$localVariantId',
    );
    debugPrint(
      '[PRODUCT PULL] server=$serverVariantId',
    );
  }

  Future<void>
  _insertServerVariantLocally({
    required String localProductId,
    required Map<String, dynamic> serverVariant,
    required Product fallbackProduct,
  }) async {
    await _upsertServerVariant(
      localProductId:
      localProductId,
      serverVariant:
      serverVariant,
      fallbackProduct:
      fallbackProduct,
    );
  }

  // ===========================================================================
  // VARIANT MATCHING
  // ===========================================================================

  Future<ProductVariant?>
  _findMatchingLocalVariant({
    required String localProductId,
    required Map<String, dynamic> serverVariant,
  }) async {
    final localVariants =
    await _getLocalVariants(
      localProductId,
    );

    final serverSku =
    _nullableString(
      serverVariant['sku'],
    );

    if (serverSku != null) {
      for (final variant
      in localVariants) {
        if (_nullableString(
          variant.sku,
        ) ==
            serverSku) {
          return variant;
        }
      }
    }

    final serverBarcode =
    _nullableString(
      serverVariant['barcode'],
    );

    if (serverBarcode != null) {
      for (final variant
      in localVariants) {
        if (_nullableString(
          variant.barcode,
        ) ==
            serverBarcode) {
          return variant;
        }
      }
    }

    final serverAttributes =
    _normalizeAttributes(
      serverVariant['attributes'],
    );

    for (final variant
    in localVariants) {
      final localAttributes =
      _decodeAttributes(
        variant.attributesJson,
      );

      if (_attributesEqual(
        localAttributes,
        serverAttributes,
      )) {
        return variant;
      }
    }

    return null;
  }

  // ===========================================================================
  // PENDING LOCAL CHANGES
  // ===========================================================================

  Future<bool>
  _productHasUnsyncedChanges(
      String localProductId,
      ) async {
    final query =
    database.select(
      database.syncOutbox,
    )
      ..where(
            (table) =>
        table.entityType.equals(
          'product',
        ) &
        table.entityId.equals(
          localProductId,
        ) &
        table.status.isIn(
          const [
            'PENDING',
            'SYNCING',
            'FAILED',
          ],
        ),
      );

    final result =
    await query.get();

    return result.isNotEmpty;
  }

  // ===========================================================================
  // EXTRACT VARIANTS
  // ===========================================================================

  List<Map<String, dynamic>>
  _extractServerVariants(
      dynamic responseData,
      ) {
    if (responseData is! Map) {
      return [];
    }

    final root =
    Map<String, dynamic>.from(
      responseData,
    );

    dynamic data =
    root['data'];

    if (data is! Map) {
      data =
          root;
    }

    return _extractServerVariantsFromProduct(
      Map<String, dynamic>.from(
        data,
      ),
    );
  }

  List<Map<String, dynamic>>
  _extractServerVariantsFromProduct(
      Map<String, dynamic> product,
      ) {
    final rawVariants =
        product['product_variants'] ??
            product['variants'];

    if (rawVariants is! List) {
      return [];
    }

    final result =
    <Map<String, dynamic>>[];

    for (final rawVariant
    in rawVariants) {
      if (rawVariant is Map) {
        result.add(
          Map<String, dynamic>.from(
            rawVariant,
          ),
        );
      }
    }

    return result;
  }

  // ===========================================================================
  // PRICING
  // ===========================================================================

  _VariantPricing _extractVariantPricing(
      Map<String, dynamic> variant,
      ) {
    double cost = 0;
    double rep = 0;
    double wholesale = 0;
    double retail = 0;

    final rawPrices =
    variant['product_prices'];

    if (rawPrices is List) {
      for (final rawPrice
      in rawPrices) {
        if (rawPrice is! Map) {
          continue;
        }

        final price =
        Map<String, dynamic>.from(
          rawPrice,
        );

        final priceType =
        price['price_type']
            ?.toString()
            .trim()
            .toUpperCase();

        final value =
        _toDouble(
          price['price'],
        );

        switch (priceType) {
          case 'COST':
            cost = value;
            break;

          case 'REP':
            rep = value;
            break;

          case 'WHOLESALE':
            wholesale = value;
            break;

          case 'RETAIL':
            retail = value;
            break;
        }
      }
    }

    //
    // احتياط إذا Endpoint رجع pricing object
    // بدلاً من product_prices.
    //
    final pricing =
    variant['pricing'];

    if (pricing is Map) {
      final map =
      Map<String, dynamic>.from(
        pricing,
      );

      if (cost == 0) {
        cost =
            _toDouble(
              map['cost_price'],
            );
      }

      if (rep == 0) {
        rep =
            _toDouble(
              map['rep_price'],
            );
      }

      if (wholesale == 0) {
        wholesale =
            _toDouble(
              map['wholesale_price'],
            );
      }

      if (retail == 0) {
        retail =
            _toDouble(
              map['retail_price'],
            );
      }
    }

    return _VariantPricing(
      cost: cost,
      rep: rep,
      wholesale: wholesale,
      retail: retail,
    );
  }

  // ===========================================================================
  // LOCAL DATABASE HELPERS
  // ===========================================================================

  Future<Product?> _getLocalProduct(
      String localProductId,
      ) {
    return (database.select(
      database.products,
    )
      ..where(
            (table) =>
            table.id.equals(
              localProductId,
            ),
      ))
        .getSingleOrNull();
  }

  Future<void> _writeProductImage(
    String localProductId,
    dynamic image,
  ) async {
    final url = _httpImageUrl(image);
    if (url == null) {
      return;
    }
    await (database.update(database.products)
          ..where((table) => table.id.equals(localProductId)))
        .write(
      ProductsCompanion(
        imageUrl: Value(url),
      ),
    );
  }

  Future<Product?> _findLocalProductForPhoto(
    String serverId,
    Map<String, dynamic> serverProduct,
  ) async {
    final link = await database.customSelect(
      '''
SELECT local_product_id
FROM store_catalog_links
WHERE remote_product_id = ?
''',
      variables: [Variable.withString(serverId)],
    ).getSingleOrNull();
    final linkedId = link?.data['local_product_id']?.toString().trim() ?? '';
    if (linkedId.isNotEmpty) {
      final row = await (database.select(database.products)
            ..where((table) => table.id.equals(linkedId)))
          .getSingleOrNull();
      if (row != null && row.deletedAt == null) {
        return row;
      }
    }

    final barcode = _nullableString(serverProduct['barcode']);
    if (barcode != null) {
      final rows = await (database.select(database.products)
            ..where(
              (table) =>
                  table.barcode.equals(barcode) & table.deletedAt.isNull(),
            ))
          .get();
      final open = rows.where((row) {
        final current = row.serverId?.trim() ?? '';
        return current.isEmpty || current == serverId;
      }).toList();
      if (open.length == 1) {
        return open.first;
      }
    }

    final sku = _nullableString(serverProduct['sku']);
    if (sku != null) {
      final rows = await (database.select(database.products)
            ..where(
              (table) => table.sku.equals(sku) & table.deletedAt.isNull(),
            ))
          .get();
      final open = rows.where((row) {
        final current = row.serverId?.trim() ?? '';
        return current.isEmpty || current == serverId;
      }).toList();
      if (open.length == 1) {
        return open.first;
      }
    }

    return null;
  }

  Future<Product?>
  _getLocalProductByServerId(
      String serverId,
      ) {
    return (database.select(
      database.products,
    )
      ..where(
            (table) =>
            table.serverId.equals(
              serverId,
            ),
      ))
        .getSingleOrNull();
  }

  Future<List<ProductVariant>>
  _getLocalVariants(
      String localProductId,
      ) {
    final query =
    database.select(
      database.productVariants,
    )
      ..where(
            (table) =>
        table.productId.equals(
          localProductId,
        ) &
        table.deletedAt.isNull(),
      )
      ..orderBy([
            (table) =>
            OrderingTerm.asc(
              table.createdAt,
            ),
      ]);

    return query.get();
  }

  Future<ProductVariant?>
  _getLocalVariantByServerId(
      String serverId,
      ) {
    return (database.select(
      database.productVariants,
    )
      ..where(
            (table) =>
            table.serverId.equals(
              serverId,
            ),
      ))
        .getSingleOrNull();
  }

  Future<void> _saveServerId({
    required String localProductId,
    required String serverId,
  }) async {
    await (database.update(
      database.products,
    )
      ..where(
            (table) =>
            table.id.equals(
              localProductId,
            ),
      ))
        .write(
      ProductsCompanion(
        serverId:
        Value(
          serverId,
        ),
        updatedAt:
        Value(
          DateTime.now(),
        ),
      ),
    );
  }

  // ===========================================================================
  // ATTRIBUTES
  // ===========================================================================

  Map<String, dynamic>
  _decodeAttributes(
      String value,
      ) {
    if (value.trim().isEmpty) {
      return {};
    }

    try {
      final decoded =
      jsonDecode(
        value,
      );

      return _normalizeAttributes(
        decoded,
      );
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic>
  _normalizeAttributes(
      dynamic value,
      ) {
    if (value is! Map) {
      return {};
    }

    final result =
    <String, dynamic>{};

    for (final entry
    in value.entries) {
      final key =
      entry.key
          .toString()
          .trim();

      if (key.isEmpty) {
        continue;
      }

      final rawValue =
          entry.value;

      if (rawValue == null) {
        continue;
      }

      final normalizedValue =
      rawValue
          .toString()
          .trim();

      if (normalizedValue.isEmpty) {
        continue;
      }

      result[key] =
          normalizedValue;
    }

    return result;
  }

  bool _attributesEqual(
      Map<String, dynamic> first,
      Map<String, dynamic> second,
      ) {
    if (first.length !=
        second.length) {
      return false;
    }

    for (final entry
    in first.entries) {
      if (!second.containsKey(
        entry.key,
      )) {
        return false;
      }

      if (second[entry.key]
          ?.toString()
          .trim() !=
          entry.value
              .toString()
              .trim()) {
        return false;
      }
    }

    return true;
  }

  // ===========================================================================
  // SERVER RESPONSE
  // ===========================================================================

  String _extractServerId(
      dynamic responseData,
      ) {
    if (responseData is! Map) {
      throw StateError(
        'Invalid create product response.',
      );
    }

    final root =
    Map<String, dynamic>.from(
      responseData,
    );

    final data =
    root['data'];

    if (data is! Map) {
      throw StateError(
        'Create product response does not contain data.',
      );
    }

    final dataMap =
    Map<String, dynamic>.from(
      data,
    );

    final id =
    dataMap['id']
        ?.toString()
        .trim();

    if (id == null ||
        id.isEmpty) {
      throw StateError(
        'Create product response does not contain product id.',
      );
    }

    return id;
  }

  // ===========================================================================
  // TYPE HELPERS
  // ===========================================================================

  Map<String, dynamic> _asStringMap(
      dynamic value,
      ) {
    if (value is! Map) {
      return <String, dynamic>{};
    }

    return Map<String, dynamic>.from(
      value,
    );
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

  String? _httpImageUrl(dynamic value) {
    final text = _nullableString(value);
    if (text == null) {
      return null;
    }
    if (text.startsWith('data:image/') && text.length <= 1500000) {
      return text;
    }
    if (text.startsWith('data:')) {
      return null;
    }
    final uri = Uri.tryParse(text);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return text;
  }

  double _toDouble(
      dynamic value, {
        double fallback = 0,
      }) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    ) ??
        fallback;
  }

  int _toInt(
      dynamic value, {
        int fallback = 0,
      }) {
    if (value == null) {
      return fallback;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    ) ??
        fallback;
  }

  bool _toBool(
      dynamic value, {
        bool fallback = false,
      }) {
    if (value == null) {
      return fallback;
    }

    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final text =
    value
        .toString()
        .trim()
        .toLowerCase();

    if (text == 'true' ||
        text == '1') {
      return true;
    }

    if (text == 'false' ||
        text == '0') {
      return false;
    }

    return fallback;
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
    required int? statusCode,
    required dynamic data,
  }) {
    debugPrint(
      '[PRODUCT SYNC] SUCCESS',
    );
    debugPrint(
      '[PRODUCT SYNC] Action: $action',
    );
    debugPrint(
      '[PRODUCT SYNC] Status: $statusCode',
    );
    debugPrint(
      '[PRODUCT SYNC] Response:',
    );
    debugPrint(
      _prettyJson(
        data,
      ),
    );
  }

  void _printDioError({
    required String action,
    required DioException error,
    Map<String, dynamic>? requestBody,
  }) {
    debugPrint(
      '[PRODUCT SYNC] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!',
    );
    debugPrint(
      '[PRODUCT SYNC] REQUEST FAILED',
    );
    debugPrint(
      '[PRODUCT SYNC] Action: $action',
    );
    debugPrint(
      '[PRODUCT SYNC] Dio type: ${error.type}',
    );
    debugPrint(
      '[PRODUCT SYNC] Status code: ${error.response?.statusCode}',
    );
    debugPrint(
      '[PRODUCT SYNC] Method: ${error.requestOptions.method}',
    );
    debugPrint(
      '[PRODUCT SYNC] URI: ${error.requestOptions.uri}',
    );

    if (requestBody != null) {
      debugPrint(
        '[PRODUCT SYNC] Request body:',
      );
      debugPrint(
        _prettyJson(
          requestBody,
        ),
      );
    }

    debugPrint(
      '[PRODUCT SYNC] Server response:',
    );
    debugPrint(
      _prettyJson(
        error.response?.data,
      ),
    );

    debugPrint(
      '[PRODUCT SYNC] Dio message: ${error.message}',
    );
    debugPrint(
      '[PRODUCT SYNC] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!',
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

// =============================================================================
// INTERNAL VARIANT PRICING
// =============================================================================

class _VariantPricing {
  final double cost;
  final double rep;
  final double wholesale;
  final double retail;

  const _VariantPricing({
    this.cost = 0,
    this.rep = 0,
    this.wholesale = 0,
    this.retail = 0,
  });
}