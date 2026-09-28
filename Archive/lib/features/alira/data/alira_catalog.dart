import 'package:dio/dio.dart';
import 'package:sales_system/core/network/server_endpoint.dart';

import 'alira_mock.dart';

class AliraCatalog {
  static bool forceMock = false;
  static bool fromServer = false;
  static bool hasNext = false;
  static bool loading = false;
  static int page = 1;
  static List<AliraProduct> products = AliraMock.instance.products;
  static List<AliraFamily> _serverFamilies = const [];

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ServerEndpoint.defaultLan,
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  static Future<void> _useActiveServer() async {
    _dio.options.baseUrl = await ServerEndpoint.instance.activeBaseUrl();
  }

  static List<AliraFamily> get families {
    if (_serverFamilies.isNotEmpty) return _serverFamilies;
    final seen = <String, String>{};
    for (final product in products) {
      seen[product.categoryId] = product.categoryName;
    }
    return [
      for (final entry in seen.entries)
        AliraFamily(id: entry.key, name: entry.value),
    ];
  }

  static void applyMock() {
    products = AliraMock.instance.products;
    _serverFamilies = const [];
    fromServer = false;
    hasNext = false;
    page = 1;
  }

  static Future<void> load({required bool agent}) async {
    page = 1;
    hasNext = false;
    if (forceMock) {
      applyMock();
      return;
    }
    products = [];
    _serverFamilies = const [];
    await openPage(1, agent: agent);
  }

  static Future<void> openPage(int nextPage, {required bool agent}) async {
    if (forceMock || loading || nextPage < 1) return;
    loading = true;
    try {
      await _useActiveServer();
      final response = await _dio.get<dynamic>(
        '/store/warehouse',
        queryParameters: {
          'audience': agent ? 'agent' : 'customer',
          'page': nextPage,
          'limit': 20,
        },
      );
      final body = response.data;
      final raw = body is Map && body['products'] is List ? body['products'] as List : const [];
      final parsed = <AliraProduct>[];
      for (final item in raw) {
        if (item is! Map) continue;
        parsed.add(_product(item));
      }
      products = parsed;
      if (body is Map && body['families'] is List) {
        _serverFamilies = [
          for (final family in body['families'] as List)
            if (family is Map)
              AliraFamily(
                id: '${family['id']}',
                name: '${family['name'] ?? family['name_ar'] ?? ''}',
              ),
        ];
      }
      page = nextPage;
      hasNext = body is Map && body['has_more'] == true;
      fromServer = true;
    } catch (_) {
      if (products.isEmpty) applyMock();
    } finally {
      loading = false;
    }
  }

  static AliraProduct _product(Map item) {
    final image = item['image_url'];
    final rawPrices = item['prices'];
    final prices = <String, int>{};
    if (rawPrices is Map) {
      for (final entry in rawPrices.entries) {
        final value = entry.value;
        prices['${entry.key}'] = value is num ? value.round() : int.tryParse('$value') ?? 0;
      }
    }
    return AliraProduct(
      id: '${item['id']}',
      sku: '${item['sku'] ?? ''}',
      name: '${item['name'] ?? ''}',
      unit: '${item['unit'] ?? ''}',
      price: item['price'] is num ? (item['price'] as num).round() : int.tryParse('${item['price']}') ?? 0,
      imageUrl: image == null || '$image'.isEmpty ? null : '$image',
      color: '#6b7788',
      categoryId: '${item['category_id'] ?? 'none'}',
      categoryName: '${item['category_name'] ?? 'بدون عائلة'}',
      variantId: _text(item['variant_id']),
      unitId: _text(item['unit_id']),
      prices: prices,
    );
  }
}

String? _text(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text == 'null') return null;
  return text;
}

class AliraFamily {
  final String id;
  final String name;

  const AliraFamily({required this.id, required this.name});
}
