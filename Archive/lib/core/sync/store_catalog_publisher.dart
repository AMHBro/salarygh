import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../network/public_server_session.dart';

/// يرفع عوائل المواد والمنتجات ذات الرصيد إلى سيرفر المتجر.
///
/// استعلام المتجر يعرض المنتج النشط الذي مجموع رصيده أكبر من صفر.
/// لذلك تُنشأ العائلة ثم المنتج بأسعاره ثم حركة إدخال في مخزن المتجر.
/// المعرّفات البعيدة تُحفظ في جداول الربط ولا تستبدل server_id المحلي.
class StoreCatalogPublisher {
  StoreCatalogPublisher(this.database);

  final AppDatabase database;

  static const _batchLimit = 150;

  Future<void> publish() async {
    try {
      await _publish();
    } catch (error, stackTrace) {
      debugPrint('[STORE] catalog publish stopped: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _publish() async {
    try {
      await PublicServerSession.send(
        method: 'GET',
        path: '/branches',
        query: {'page': 1, 'limit': 20},
      );
    } on StateError {
      debugPrint(
        '[STORE] catalog skipped until the office signs in online',
      );
      return;
    }

    final unitId = await _pieceUnitId();
    final branchId = await _branchId();
    if (unitId == null || branchId == null) {
      debugPrint('[STORE] catalog skipped: unit or branch missing');
      return;
    }
    final warehouseId = await _storeWarehouseId(branchId);
    if (warehouseId == null) {
      debugPrint('[STORE] catalog skipped: warehouse missing');
      return;
    }

    final remoteCategories = await _remoteCategoriesByName();
    final rows = await database.customSelect('''
SELECT
  p.id AS id,
  p.name AS name,
  p.sku AS sku,
  p.barcode AS barcode,
  COALESCE(p.category_id, '') AS category_id,
  COALESCE(p.category_name, '') AS category_name,
  p.cost_price AS cost_price,
  p.representative_price AS representative_price,
  p.wholesale_price AS wholesale_price,
  p.retail_price AS retail_price,
  COALESCE(SUM(sb.quantity), 0) AS qty
FROM products p
LEFT JOIN product_variants v
  ON v.product_id = p.id AND v.deleted_at IS NULL
LEFT JOIN stock_balances sb
  ON sb.variant_id = v.id
WHERE p.deleted_at IS NULL AND p.is_active = 1
GROUP BY p.id
HAVING COALESCE(SUM(sb.quantity), 0) > 0
ORDER BY p.name
LIMIT $_batchLimit
''').get();

    var published = 0;
    for (final row in rows) {
      final ok = await _publishProduct(
        row: row,
        unitId: unitId,
        warehouseId: warehouseId,
        remoteCategories: remoteCategories,
      );
      if (ok) {
        published += 1;
      }
    }
    debugPrint(
      '[STORE] catalog publish finished. products=$published',
    );
  }

  Future<bool> _publishProduct({
    required QueryRow row,
    required String unitId,
    required String warehouseId,
    required Map<String, String> remoteCategories,
  }) async {
    final localId = _text(row, 'id');
    final name = _text(row, 'name');
    if (localId.isEmpty || name.isEmpty) {
      return false;
    }
    final qty = _number(row, 'qty');
    if (qty <= 0) {
      return false;
    }

    final localCategoryId = _text(row, 'category_id');
    final categoryKey =
        localCategoryId.isEmpty ? 'general' : localCategoryId;
    final categoryName = _text(row, 'category_name').isEmpty
        ? 'عام'
        : _text(row, 'category_name');

    try {
      final existing = await database.customSelect(
        '''
SELECT remote_product_id, remote_variant_id, remote_category_id, stock_pushed
FROM store_catalog_links
WHERE local_product_id = ?
''',
        variables: [Variable.withString(localId)],
      ).getSingleOrNull();

      final categoryId = await _categoryId(
        localKey: categoryKey,
        name: categoryName,
        remoteCategories: remoteCategories,
      );
      if (categoryId == null) {
        return false;
      }

      var remoteProductId = existing == null
          ? ''
          : _text(existing, 'remote_product_id');
      var remoteVariantId = existing == null
          ? ''
          : _text(existing, 'remote_variant_id');
      final alreadyPushed =
          existing == null ? 0.0 : _number(existing, 'stock_pushed');

      if (remoteProductId.isEmpty || remoteVariantId.isEmpty) {
        final created = await _createProduct(
          localId: localId,
          name: name,
          sku: _text(row, 'sku'),
          barcode: _text(row, 'barcode'),
          categoryId: categoryId,
          unitId: unitId,
          cost: _number(row, 'cost_price'),
          representative: _number(row, 'representative_price'),
          wholesale: _number(row, 'wholesale_price'),
          retail: _number(row, 'retail_price'),
        );
        if (created == null) {
          return false;
        }
        remoteProductId = created.$1;
        remoteVariantId = created.$2;
      }

      await _saveLink(
        localId: localId,
        remoteProductId: remoteProductId,
        remoteVariantId: remoteVariantId,
        categoryId: categoryId,
        stockPushed: alreadyPushed,
      );
      await _stampLocalServerIds(
        localId: localId,
        remoteProductId: remoteProductId,
        remoteVariantId: remoteVariantId,
      );

      final delta = _round(qty - alreadyPushed);
      if (delta >= 0.001) {
        await PublicServerSession.send(
          method: 'POST',
          path: '/inventory/movements',
          data: {
            'warehouse_id': warehouseId,
            'variant_id': remoteVariantId,
            'movement_type': 'IN',
            'quantity': delta,
            'notes': 'متاح للمتجر',
          },
        );
        await _saveLink(
          localId: localId,
          remoteProductId: remoteProductId,
          remoteVariantId: remoteVariantId,
          categoryId: categoryId,
          stockPushed: alreadyPushed + delta,
        );
      }
      return true;
    } on DioException catch (error) {
      debugPrint(
        '[STORE] product "$name" skipped: '
        '${error.response?.statusCode} ${error.response?.data}',
      );
      return false;
    } catch (error) {
      debugPrint('[STORE] product "$name" skipped: $error');
      return false;
    }
  }

  Future<(String, String)?> _createProduct({
    required String localId,
    required String name,
    required String sku,
    required String barcode,
    required String categoryId,
    required String unitId,
    required double cost,
    required double representative,
    required double wholesale,
    required double retail,
  }) async {
    final safeCost = cost < 0 ? 0.0 : cost;
    final body = <String, dynamic>{
      'name_ar': name,
      'category_id': categoryId,
      'base_unit_id': unitId,
      'sku': sku.isEmpty ? _skuFrom(localId) : sku,
      'pricing': {
        'cost_price': safeCost,
        'rep_price': _atLeast(representative, safeCost),
        'wholesale_price': _atLeast(wholesale, safeCost),
        'retail_price': _atLeast(retail, safeCost),
      },
    };
    if (barcode.isNotEmpty) {
      body['barcode'] = barcode;
    }

    Response<dynamic> response;
    try {
      response = await PublicServerSession.send(
        method: 'POST',
        path: '/products',
        data: body,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 400 || barcode.isEmpty) {
        rethrow;
      }
      body.remove('barcode');
      body['sku'] = _skuFrom(localId);
      response = await PublicServerSession.send(
        method: 'POST',
        path: '/products',
        data: body,
      );
    }

    final data = _map(response.data)?['data'];
    final product = data is Map ? Map<String, dynamic>.from(data) : null;
    final productId = product?['id']?.toString() ?? '';
    final variants = product?['product_variants'];
    final variantId = variants is List && variants.isNotEmpty
        ? (variants.first as Map)['id']?.toString() ?? ''
        : '';
    if (productId.isEmpty || variantId.isEmpty) {
      debugPrint('[STORE] product "$name" created without a variant id');
      return null;
    }
    return (productId, variantId);
  }

  Future<String?> _categoryId({
    required String localKey,
    required String name,
    required Map<String, String> remoteCategories,
  }) async {
    final saved = await database.customSelect(
      '''
SELECT remote_category_id
FROM store_catalog_categories
WHERE local_category_id = ?
''',
      variables: [Variable.withString(localKey)],
    ).getSingleOrNull();
    final savedId = saved == null ? '' : _text(saved, 'remote_category_id');
    if (savedId.isNotEmpty) {
      return savedId;
    }

    final known = remoteCategories[name];
    if (known != null && known.isNotEmpty) {
      await _saveCategory(localKey, known);
      return known;
    }

    final response = await PublicServerSession.send(
      method: 'POST',
      path: '/categories',
      data: {
        'name_ar': name,
      },
    );
    final data = _map(response.data)?['data'];
    final id = data is Map ? data['id']?.toString() ?? '' : '';
    if (id.isEmpty) {
      return null;
    }
    remoteCategories[name] = id;
    await _saveCategory(localKey, id);
    return id;
  }

  Future<void> _saveLink({
    required String localId,
    required String remoteProductId,
    required String remoteVariantId,
    required String categoryId,
    required double stockPushed,
  }) {
    return database.customStatement(
      '''
INSERT OR REPLACE INTO store_catalog_links (
  local_product_id, remote_product_id, remote_variant_id,
  remote_category_id, stock_pushed
) VALUES (?, ?, ?, ?, ?)
''',
      [
        localId,
        remoteProductId,
        remoteVariantId,
        categoryId,
        stockPushed,
      ],
    );
  }

  Future<void> _stampLocalServerIds({
    required String localId,
    required String remoteProductId,
    required String remoteVariantId,
  }) async {
    await database.customStatement(
      'UPDATE products SET server_id = ? WHERE id = ?',
      [remoteProductId, localId],
    );
    await database.customStatement(
      '''
UPDATE product_variants
SET server_id = ?
WHERE id = (
  SELECT id FROM product_variants
  WHERE product_id = ? AND deleted_at IS NULL
  ORDER BY id
  LIMIT 1
)
''',
      [remoteVariantId, localId],
    );
  }

  Future<void> _saveCategory(String localKey, String remoteId) {
    return database.customStatement(
      '''
INSERT OR REPLACE INTO store_catalog_categories (
  local_category_id, remote_category_id
) VALUES (?, ?)
''',
      [localKey, remoteId],
    );
  }

  Future<String?> _pieceUnitId() async {
    final response = await PublicServerSession.send(
      method: 'GET',
      path: '/units',
    );
    for (final item in _list(response.data)) {
      final name = item['name_ar']?.toString() ?? '';
      final symbol = item['symbol']?.toString() ?? '';
      if (name == 'قطعة' || symbol == 'PCS') {
        return item['id']?.toString();
      }
    }
    final created = await PublicServerSession.send(
      method: 'POST',
      path: '/units',
      data: {
        'name_ar': 'قطعة',
        'name_en': 'Piece',
        'symbol': 'PCS',
        'is_base_unit': true,
        'conversion_factor': 1,
      },
    );
    final data = _map(created.data)?['data'] ?? created.data;
    if (data is Map) {
      return data['id']?.toString();
    }
    return null;
  }

  Future<String?> _branchId() async {
    final response = await PublicServerSession.send(
      method: 'GET',
      path: '/branches',
      query: {'page': 1, 'limit': 50},
    );
    final items = _list(response.data);
    for (final item in items) {
      if (item['code']?.toString() == 'HQ-001') {
        return item['id']?.toString();
      }
    }
    if (items.isEmpty) {
      return null;
    }
    return items.first['id']?.toString();
  }

  Future<String?> _storeWarehouseId(String branchId) async {
    final response = await PublicServerSession.send(
      method: 'GET',
      path: '/warehouses',
      query: {'page': 1, 'limit': 50, 'branch_id': branchId},
    );
    final items = _list(response.data);
    for (final item in items) {
      if (item['name']?.toString() == 'مخزن المتجر') {
        return item['id']?.toString();
      }
    }
    if (items.isNotEmpty) {
      return items.first['id']?.toString();
    }
    final created = await PublicServerSession.send(
      method: 'POST',
      path: '/warehouses',
      data: {
        'name': 'مخزن المتجر',
        'branch_id': branchId,
        'type': 'MAIN',
      },
    );
    final data = _map(created.data)?['data'];
    if (data is Map) {
      return data['id']?.toString();
    }
    return null;
  }

  Future<Map<String, String>> _remoteCategoriesByName() async {
    final response = await PublicServerSession.send(
      method: 'GET',
      path: '/categories',
    );
    final map = <String, String>{};
    for (final item in _list(response.data)) {
      final name = item['name_ar']?.toString() ?? '';
      final id = item['id']?.toString() ?? '';
      if (name.isNotEmpty && id.isNotEmpty) {
        map[name] = id;
      }
    }
    return map;
  }

  String _skuFrom(String localId) {
    final compact = localId.replaceAll('-', '');
    final slice = compact.length <= 10 ? compact : compact.substring(0, 10);
    return 'ST$slice';
  }

  double _round(double value) {
    return (value * 1000).round() / 1000;
  }

  double _atLeast(double value, double floor) {
    final safe = value < 0 ? 0.0 : value;
    return safe < floor ? floor : safe;
  }

  Map<String, dynamic>? _map(dynamic body) {
    if (body is Map<String, dynamic>) {
      return body;
    }
    if (body is Map) {
      return Map<String, dynamic>.from(body);
    }
    return null;
  }

  List<Map<String, dynamic>> _list(dynamic body) {
    final root = _map(body);
    final data = root?['data'] ?? body;
    if (data is List) {
      return data
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
    }
    return const [];
  }

  String _text(QueryRow row, String key) {
    final value = row.data[key];
    return value?.toString().trim() ?? '';
  }

  double _number(QueryRow row, String key) {
    final value = row.data[key];
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
