import 'dart:math';

import 'package:dio/dio.dart';
import 'package:sales_system/core/network/server_endpoint.dart';
import 'package:sales_system/core/sync/sync_failure.dart';

import 'store_outbox.dart';

class AliraStoreLine {
  final String variantId;
  final String unitId;
  final int quantity;

  const AliraStoreLine({
    required this.variantId,
    required this.unitId,
    required this.quantity,
  });
}

class AliraStoreOrders {
  static bool lastQueued = false;

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ServerEndpoint.defaultInternet,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  static Future<void> _useActiveServer() async {
    _dio.options.baseUrl = await ServerEndpoint.instance.publicBaseUrl();
  }

  static Future<String> guest({
    required String name,
    required String phone,
    required String address,
    required List<AliraStoreLine> lines,
  }) async {
    lastQueued = false;
    final payload = <String, dynamic>{
      'kind': 'guest',
      'key': _idempotencyKey(),
      'name': name,
      'phone': phone,
      'address': address,
      'lines': _lineMaps(lines),
    };
    try {
      await _useActiveServer();
      return await _sendGuest(payload);
    } on DioException catch (error) {
      if (!isTransientSyncFailure(error)) rethrow;
      await _enqueue(payload);
      lastQueued = true;
      return '${payload['key']}';
    }
  }

  static Future<String> representative({
    required String token,
    required String partyName,
    required String partyPhone,
    required String partyAddress,
    required String paymentType,
    int? paidAmount,
    String? partyId,
    String? priceType,
    required List<AliraStoreLine> lines,
  }) async {
    lastQueued = false;
    final payload = <String, dynamic>{
      'kind': 'representative',
      'key': _idempotencyKey(),
      'token': token,
      'partyName': partyName,
      'partyPhone': partyPhone,
      'partyAddress': partyAddress,
      'paymentType': paymentType,
      'paidAmount': ?paidAmount,
      'partyId': partyId,
      'priceType': priceType,
      'lines': _lineMaps(lines),
    };
    try {
      await _useActiveServer();
      return await _sendRepresentative(payload);
    } on DioException catch (error) {
      if (!isTransientSyncFailure(error)) rethrow;
      await _enqueue(payload);
      lastQueued = true;
      return '${payload['key']}';
    }
  }

  static Future<int> pendingCount() async {
    try {
      final items = await _readQueue();
      return items.where((item) => item['permanent'] != true).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> flushQueued() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final items = await _readQueue();
      if (items.isEmpty) return;
      await _useActiveServer();
      final remaining = <Map<String, dynamic>>[];
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        if (item['permanent'] == true) {
          remaining.add(item);
          continue;
        }
        try {
          if (item['kind'] == 'representative') {
            await _sendRepresentative(item);
          } else {
            await _sendGuest(item);
          }
        } on DioException catch (error) {
          if (isTransientSyncFailure(error)) {
            remaining.add(item);
            remaining.addAll(items.skip(index + 1));
            break;
          }
          remaining.add({
            ...item,
            'permanent': true,
            'lastError': message(error),
          });
        }
      }
      await _writeQueue(remaining);
    } finally {
      _flushing = false;
    }
  }

  static bool _flushing = false;

  static Future<String> _sendGuest(Map<String, dynamic> payload) async {
    final lines = _linesOf(payload);
    final cart = await _dio.get<dynamic>('/store/cart');
    final token = _cartToken(cart.data);
    final headers = {
      'x-cart-token': token,
      'x-idempotency-key': '${payload['key']}',
    };
    await _fill(headers, lines);
    final response = await _dio.post<dynamic>(
      '/store/checkout/guest',
      data: {
        'customer_name': payload['name'],
        'customer_phone': payload['phone'],
        'customer_address': payload['address'],
      },
      options: Options(headers: headers),
    );
    return _orderNumber(response.data);
  }

  static Future<String> _sendRepresentative(Map<String, dynamic> payload) async {
    final lines = _linesOf(payload);
    final headers = {
      'authorization': 'Bearer ${payload['token']}',
      'x-idempotency-key': '${payload['key']}',
    };
    await _fill(headers, lines);
    final partyId = '${payload['partyId'] ?? ''}';
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(partyId);
    final priceType = '${payload['priceType'] ?? ''}'.trim();
    final response = await _dio.post<dynamic>(
      '/store/checkout/representative',
      data: {
        'party_type': uuid ? 'CUSTOMER' : 'OTHER',
        if (uuid) 'party_id': partyId,
        'party_name': payload['partyName'],
        'party_phone': payload['partyPhone'],
        'party_address': payload['partyAddress'],
        'payment_type': payload['paymentType'],
        if (payload['paidAmount'] != null) 'paid_amount': payload['paidAmount'],
        if (priceType.isNotEmpty) 'price_type': priceType,
      },
      options: Options(headers: headers),
    );
    return _orderNumber(response.data);
  }

  static List<Map<String, dynamic>> _lineMaps(List<AliraStoreLine> lines) {
    return [
      for (final line in lines)
        {
          'variantId': line.variantId,
          'unitId': line.unitId,
          'quantity': line.quantity,
        },
    ];
  }

  static List<AliraStoreLine> _linesOf(Map<String, dynamic> payload) {
    final raw = payload['lines'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          AliraStoreLine(
            variantId: '${item['variantId']}',
            unitId: '${item['unitId']}',
            quantity: item['quantity'] is num
                ? (item['quantity'] as num).round()
                : int.tryParse('${item['quantity']}') ?? 0,
          ),
    ];
  }

  static Future<void> _fill(
    Map<String, String> headers,
    List<AliraStoreLine> lines,
  ) async {
    await _dio.delete<dynamic>(
      '/store/cart',
      options: Options(headers: headers),
    );
    for (final line in lines) {
      await _dio.post<dynamic>(
        '/store/cart/items',
        data: {
          'variant_id': line.variantId,
          'unit_id': line.unitId,
          'quantity': line.quantity,
        },
        options: Options(headers: headers),
      );
    }
  }

  static Future<List<Map<String, dynamic>>> _readQueue() => readStoreOutbox();

  static Future<void> _writeQueue(List<Map<String, dynamic>> items) =>
      writeStoreOutbox(items);

  static Future<void> _enqueue(Map<String, dynamic> payload) async {
    final items = await _readQueue();
    items.add(payload);
    await _writeQueue(items);
  }

  static String _idempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String _cartToken(Object? body) {
    if (body is Map) {
      final token = '${body['cart_token'] ?? ''}'.trim();
      if (token.isNotEmpty) return token;
    }
    throw StateError('تعذر فتح سلة المتجر');
  }

  static String _orderNumber(Object? body) {
    if (body is Map) {
      final nested = body['order'];
      final source = nested is Map ? nested : body;
      final number = '${source['order_number'] ?? source['orderNumber'] ?? source['id'] ?? ''}'.trim();
      if (number.isNotEmpty) return number;
    }
    return 'ord_${DateTime.now().millisecondsSinceEpoch}';
  }

  static String message(Object error) {
    if (error is DioException) {
      if (isTransientSyncFailure(error)) {
        return 'السيرفر غير متصل. حُفظ الطلب وسيُرسل عند عودة الشبكة.';
      }
      final data = error.response?.data;
      if (data is Map) {
        final nested = data['message'];
        if (nested is String && nested.trim().isNotEmpty) return nested;
        if (nested is List && nested.isNotEmpty) return '${nested.first}';
      }
      return 'تعذر إرسال الطلب إلى طلبات المتجر';
    }
    if (error is StateError && error.message.isNotEmpty) return error.message;
    return 'تعذر إرسال الطلب إلى طلبات المتجر';
  }
}
