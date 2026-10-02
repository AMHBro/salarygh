import 'dart:async';

import 'package:dio/dio.dart';
import 'package:sales_system/core/network/server_endpoint.dart';

import 'alira_mock.dart';

class AliraCatalog {
  static const int pageSize = 20;
  static bool forceMock = false;
  static bool fromServer = false;
  static bool hasNext = false;
  static bool loading = false;
  static int page = 1;
  static List<AliraProduct> products = const [];
  static String? connectionError;
  static List<AliraFamily> _serverFamilies = const [];
  static final Map<String, AliraProduct> _byId = {};
  static int _generation = 0;
  static bool _agent = false;
  static String _query = '';
  static String? _familyId;
  static Timer? _searchTimer;

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ServerEndpoint.defaultInternet,
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  static Future<void> _useActiveServer() async {
    _dio.options.baseUrl = await ServerEndpoint.instance.publicBaseUrl();
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
    _remember(products);
    _serverFamilies = const [];
    fromServer = false;
    hasNext = false;
    page = 1;
    connectionError = null;
  }

  static AliraProduct? byId(String id) => _byId[id];

  static void _remember(Iterable<AliraProduct> items) {
    for (final item in items) {
      _byId[item.id] = item;
    }
  }

  static List<AliraProduct> visible({
    String? familyId,
    String query = '',
  }) {
    if (fromServer) return products;
    final text = query.trim();
    return products.where((item) {
      if (text.isNotEmpty) {
        return item.name.contains(text) || item.sku.contains(text);
      }
      if (familyId != null && item.categoryId != familyId) return false;
      return true;
    }).toList();
  }

  static void cancelPending() {
    _searchTimer?.cancel();
    _searchTimer = null;
  }

  static void scheduleLoad({
    required bool agent,
    required String query,
    String? familyId,
    required void Function() onDone,
  }) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        await load(agent: agent, query: query, familyId: familyId);
      } on ServerConnectionException {
        // connectionError يحمل حالة الانقطاع للواجهة.
      }
      onDone();
    });
  }

  static Future<void> load({
    required bool agent,
    String query = '',
    String? familyId,
    bool append = false,
  }) async {
    if (forceMock) {
      applyMock();
      return;
    }
    if (append && (loading || !hasNext)) return;
    final generation = append ? _generation : ++_generation;
    if (!append) {
      _agent = agent;
      _query = query.trim();
      _familyId = familyId;
    }
    loading = true;
    try {
      await _useActiveServer();
      final nextPage = append ? page + 1 : 1;
      final batch = await _readPage(nextPage, agent: _agent);
      if (generation != _generation) return;
      _remember(batch.products);
      if (append) {
        final seen = products.map((item) => item.id).toSet();
        products = [
          ...products,
          for (final item in batch.products)
            if (seen.add(item.id)) item,
        ];
        page = nextPage;
      } else {
        products = batch.products;
        page = 1;
      }
      if (batch.families.isNotEmpty) {
        _serverFamilies = batch.families;
      }
      if (!append && batch.products.isEmpty) {
        products = const [];
        _serverFamilies = batch.families;
        fromServer = false;
        hasNext = false;
        page = 1;
        throw const ServerConnectionException();
      }
      fromServer = true;
      hasNext = batch.hasMore;
      connectionError = null;
    } catch (error) {
      if (generation != _generation) return;
      products = const [];
      fromServer = false;
      hasNext = false;
      connectionError = error is ServerConnectionException
          ? error.message
          : 'الكتالوج غير متصل بالسيرفر';
      if (error is ServerConnectionException) rethrow;
      throw ServerConnectionException(connectionError!);
    } finally {
      if (generation == _generation) loading = false;
    }
  }

  static Future<_CatalogBatch> _readPage(int nextPage, {required bool agent}) async {
    final response = await _dio.get<dynamic>(
      '/store/warehouse',
      queryParameters: {
        'audience': agent ? 'agent' : 'customer',
        'page': nextPage,
        'limit': pageSize,
        if (_query.isNotEmpty) 'search': _query,
        if (_familyId != null && _familyId!.isNotEmpty) 'category_id': _familyId,
      },
    );
    final body = response.data;
    final raw = body is Map && body['products'] is List ? body['products'] as List : const [];
    final parsed = <AliraProduct>[];
    for (final item in raw) {
      if (item is! Map) continue;
      parsed.add(_product(item));
    }
    final families = <AliraFamily>[];
    if (body is Map && body['families'] is List) {
      for (final family in body['families'] as List) {
        if (family is! Map) continue;
        families.add(
          AliraFamily(
            id: '${family['id']}',
            name: '${family['name'] ?? family['name_ar'] ?? ''}',
          ),
        );
      }
    }
    return _CatalogBatch(
      products: parsed,
      families: families,
      hasMore: body is Map && body['has_more'] == true,
    );
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
      stock: item['stock'] is num ? (item['stock'] as num).round() : int.tryParse('${item['stock']}') ?? 0,
    );
  }
}

String? _text(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text == 'null') return null;
  return text;
}

class ServerConnectionException implements Exception {
  final String message;

  const ServerConnectionException([
    this.message = 'الكتالوج غير متصل بالسيرفر',
  ]);

  @override
  String toString() => message;
}

class AliraFamily {
  final String id;
  final String name;

  const AliraFamily({required this.id, required this.name});
}

class _CatalogBatch {
  final List<AliraProduct> products;
  final List<AliraFamily> families;
  final bool hasMore;

  const _CatalogBatch({
    required this.products,
    required this.families,
    required this.hasMore,
  });
}
