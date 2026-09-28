import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../network/api_client.dart';
import '../sync/sync_remote_gateway.dart';

class FloorNoticeGateway implements SyncRemoteGateway {
  final AppDatabase database;
  final ApiClient apiClient;

  FloorNoticeGateway({
    required this.database,
    required this.apiClient,
  });

  @override
  Set<String> get supportedEntityTypes => {'floor_notice'};

  @override
  Future<void> pushOperation(SyncOutboxData operation) async {
    final kind = _kind(operation);
    switch (kind) {
      case 'sale_return':
        await _pushReturn(operation.entityId);
        return;
      case 'customer_receipt':
        await _pushReceipt(operation.entityId);
        return;
      case 'supplier_payment':
        await _pushSupplierPayment(operation.entityId);
        return;
      default:
        throw StateError('إشعار صالة غير معروف: $kind');
    }
  }

  @override
  Future<SyncPullResult> pullChanges({String? cursor}) async {
    return const SyncPullResult(nextCursor: null, changes: []);
  }

  Future<void> _pushReturn(String returnId) async {
    final header = await (database.select(database.saleReturns)
          ..where((table) => table.id.equals(returnId)))
        .getSingleOrNull();
    if (header == null) {
      throw StateError('المرتجع المحلي غير موجود.');
    }
    final warehouse = await (database.select(database.warehouses)
          ..where((table) => table.id.equals(header.warehouseId)))
        .getSingleOrNull();
    final warehouseServerId = warehouse?.serverId?.trim() ?? '';
    if (warehouseServerId.isEmpty) {
      throw StateError('SYNC_DEFER المخزن لم يصل إلى السيرفر بعد.');
    }

    final lines = await (database.select(database.saleReturnItems)
          ..where((table) => table.returnId.equals(returnId)))
        .get();
    final apiLines = <Map<String, dynamic>>[];
    for (final line in lines) {
      final variant = await (database.select(database.productVariants)
            ..where((table) => table.id.equals(line.variantId)))
          .getSingleOrNull();
      final serverId = variant?.serverId?.trim() ?? '';
      if (serverId.isEmpty) {
        throw StateError('SYNC_DEFER خيار المادة لم يصل إلى السيرفر بعد.');
      }
      apiLines.add({
        'variant_id': serverId,
        'quantity': line.quantity,
      });
    }

    String? customerServerId;
    final customerId = header.customerId?.trim() ?? '';
    if (customerId.isNotEmpty) {
      final customer = await (database.select(database.customers)
            ..where((table) => table.id.equals(customerId)))
          .getSingleOrNull();
      customerServerId = customer?.serverId?.trim();
      if (customerServerId == null || customerServerId.isEmpty) {
        throw StateError('SYNC_DEFER الزبون لم يصل إلى السيرفر بعد.');
      }
    }

    final currency = header.currency == 'USD' ? 'USD' : 'IQD';
    final amount = currency == 'USD' && header.exchangeRate > 0
        ? header.total / header.exchangeRate
        : header.total;

    await apiClient.post(
      '/floor/notices',
      data: {
        'kind': 'sale_return',
        'entity_id': returnId,
        'warehouse_id': warehouseServerId,
        'customer_id': customerServerId,
        'amount': amount,
        'currency': currency,
        'lines': apiLines,
      },
    );
    debugPrint('[FLOOR] return synced $returnId');
  }

  Future<void> _pushReceipt(String paymentId) async {
    final payment = await (database.select(database.customerPayments)
          ..where((table) => table.id.equals(paymentId)))
        .getSingleOrNull();
    if (payment == null) {
      throw StateError('سند القبض غير موجود.');
    }
    final customer = await (database.select(database.customers)
          ..where((table) => table.id.equals(payment.customerId)))
        .getSingleOrNull();
    final serverId = customer?.serverId?.trim() ?? '';
    if (serverId.isEmpty) {
      throw StateError('SYNC_DEFER الزبون لم يصل إلى السيرفر بعد.');
    }
    await apiClient.post(
      '/floor/notices',
      data: {
        'kind': 'customer_receipt',
        'entity_id': paymentId,
        'customer_id': serverId,
        'amount': payment.amount,
        'currency': payment.currency == 'USD' ? 'USD' : 'IQD',
      },
    );
  }

  Future<void> _pushSupplierPayment(String paymentId) async {
    final payment = await (database.select(database.supplierPayments)
          ..where((table) => table.id.equals(paymentId)))
        .getSingleOrNull();
    if (payment == null) {
      throw StateError('سند الدفع غير موجود.');
    }
    final supplier = await (database.select(database.suppliers)
          ..where((table) => table.id.equals(payment.supplierId)))
        .getSingleOrNull();
    final serverId = supplier?.serverId?.trim() ?? '';
    if (serverId.isEmpty) {
      throw StateError('SYNC_DEFER المورد لم يصل إلى السيرفر بعد.');
    }
    await apiClient.post(
      '/floor/notices',
      data: {
        'kind': 'supplier_payment',
        'entity_id': paymentId,
        'supplier_id': serverId,
        'amount': payment.amount,
        'currency': payment.currency == 'USD' ? 'USD' : 'IQD',
      },
    );
  }

  String _kind(SyncOutboxData operation) {
    final raw = operation.payloadJson;
    final decoded = raw.isEmpty ? null : _decode(raw);
    final kind = decoded?['kind'];
    return kind is String ? kind : '';
  }

  Map<String, dynamic>? _decode(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
    } catch (_) {}
    return null;
  }
}
