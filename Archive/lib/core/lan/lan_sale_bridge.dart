import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../features/sales/models/cart_item_model.dart';
import '../../features/sales/models/sale_model.dart';
import '../database/app_database.dart';
import '../di/app_services.dart';
import 'office_role.dart';

class LanSaleBridge {
  static Future<SaleModel> submit({
    required String warehouseId,
    required String warehouseName,
    String? customerId,
    required String customerName,
    String? representativeId,
    required List<CartItemModel> items,
    required double subtotal,
    required double discount,
    required double porterage,
    required double total,
    required double paidAmount,
    required double remainingAmount,
    required PaymentType paymentType,
    required String currency,
    required double exchangeRate,
    required double totalUsd,
    required String notes,
  }) async {
    final role = OfficeRole.instance;
    final base = await role.readBase();
    final token = await role.readToken();
    final idempotencyKey = 'lan-${DateTime.now().microsecondsSinceEpoch}';
    final dio = Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    final payload = {
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'customerId': customerId,
      'customerName': customerName,
      'representativeId': representativeId,
      'subtotal': subtotal,
      'discount': discount,
      'porterage': porterage,
      'total': total,
      'paidAmount': paidAmount,
      'remainingAmount': remainingAmount,
      'paymentType': paymentType.apiValue,
      'currency': currency,
      'exchangeRate': exchangeRate,
      'totalUsd': totalUsd,
      'notes': notes,
      'warehouseServerId': await _serverId(
        AppServices.database,
        'warehouses',
        warehouseId,
      ),
      'customerServerId': customerId == null
          ? null
          : await _serverId(AppServices.database, 'customers', customerId),
      'items': [
        for (final item in items)
          {
            'variantId': item.variantId,
            'variantServerId': await _serverId(
              AppServices.database,
              'product_variants',
              item.variantId ?? '',
            ),
            'unitId': item.unitId,
            'quantity': item.quantity,
            'loosePieces': item.loosePieces,
            'unitFactor': item.unitFactor,
            'priceType': item.priceType.name,
            'unitPrice': item.unitPrice,
            'discountPercent': item.discountPercent,
            'productId': item.product.id,
            'productName': item.product.name,
            'barcode': item.product.barcode,
          },
      ],
    };
    final queued = await dio.post<dynamic>(
      '/v1/queue',
      data: {
        'idempotencyKey': idempotencyKey,
        'kind': 'sale.submit',
        'payload': payload,
      },
    );
    final queuedId = '${(queued.data as Map)['id']}';
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final status = await dio.get<dynamic>('/v1/queue/$queuedId');
      final body = status.data as Map;
      final state = '${body['status']}';
      if (state == 'applied') {
        final result = body['result'];
        final resultMap = result is Map ? result : jsonDecode('$result');
        final now = DateTime.now();
        return SaleModel(
          id: '${resultMap['saleId'] ?? queuedId}',
          invoiceNumber: '${resultMap['invoiceNumber'] ?? queuedId}',
          customerId: customerId,
          customerName: customerName,
          warehouseId: warehouseId,
          warehouseName: warehouseName,
          representativeId: representativeId,
          items: items,
          subtotal: subtotal,
          discount: discount,
          porterage: porterage,
          total: total,
          paidAmount: paidAmount,
          remainingAmount: remainingAmount,
          paymentType: paymentType,
          currency: currency,
          exchangeRate: exchangeRate,
          totalUsd: totalUsd,
          notes: notes,
          createdAt: now,
          updatedAt: now,
        );
      }
      if (state == 'rejected') {
        throw StateError('${body['error'] ?? 'الحاسبة الأساسية رفضت الفاتورة.'}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    throw StateError(
      'الفاتورة دخلت طابور الحاسبة الأساسية ولم تُعالج بعد. أبقِ البرنامج مفتوحاً هناك.',
    );
  }

  static Future<String?> _serverId(
    AppDatabase database,
    String table,
    String localId,
  ) async {
    if (localId.trim().isEmpty) {
      return null;
    }
    if (table != 'warehouses' &&
        table != 'customers' &&
        table != 'product_variants') {
      return null;
    }
    final row = await database.customSelect(
      'SELECT server_id FROM $table WHERE id = ?',
      variables: [Variable.withString(localId)],
    ).getSingleOrNull();
    final serverId = row?.read<String?>('server_id')?.trim();
    if (serverId == null || serverId.isEmpty) {
      return null;
    }
    return serverId;
  }
}
