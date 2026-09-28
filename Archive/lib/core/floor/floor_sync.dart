import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../network/api_client.dart';
import '../sync/connectivity_service.dart';
import 'floor_store.dart';

class FloorSync {
  static const Uuid _uuid = Uuid();
  static bool _running = false;

  static Future<void> pull({
    required AppDatabase database,
    required ApiClient apiClient,
    required ConnectivityService connectivity,
  }) async {
    if (_running) {
      return;
    }
    _running = true;
    try {
      await FloorStore.ensureTables(database);
      await _retryPending(database);
      final online = await connectivity.hasConnection;
      if (!online) {
        return;
      }
      final after = await FloorStore.cursor(database);
      final response = await apiClient.get(
        '/floor/events',
        queryParameters: {'after': '$after'},
      );
      final raw = response.data;
      if (raw is! List) {
        return;
      }
      var cursor = after;
      for (final item in raw) {
        if (item is! Map) {
          continue;
        }
        final id = _asInt(item['id']);
        if (id <= cursor) {
          continue;
        }
        final applied = await _apply(database, item);
        if (!applied) {
          await FloorStore.savePending(
            database,
            id: id,
            eventType: '${item['event_type'] ?? ''}',
            entityId: '${item['entity_id'] ?? ''}',
            payload: jsonEncode(item['payload'] ?? {}),
            createdAt: '${item['created_at'] ?? ''}',
          );
        }
        cursor = id;
      }
      if (cursor != after) {
        await FloorStore.saveCursor(database, cursor);
      }
    } catch (error) {
      debugPrint('[FLOOR] poll skipped: $error');
    } finally {
      _running = false;
    }
  }

  static Future<void> _retryPending(AppDatabase database) async {
    final rows = await FloorStore.pending(database);
    for (final row in rows) {
      final payload = jsonDecode(row.read<String>('payload'));
      final applied = await _apply(database, {
        'id': row.read<int>('id'),
        'event_type': row.read<String>('event_type'),
        'entity_id': row.read<String>('entity_id'),
        'payload': payload,
        'created_at': row.read<String>('created_at'),
      });
      if (applied) {
        await FloorStore.dropPending(database, row.read<int>('id'));
      }
    }
  }

  static Future<bool> _apply(AppDatabase database, Map item) async {
    final type = '${item['event_type'] ?? ''}';
    final payload = item['payload'];
    final body = payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
    switch (type) {
      case 'stock_delta':
        return _applyStock(database, body, '${item['created_at'] ?? ''}');
      case 'stock_locked':
        return _applyLock(database, body);
      case 'stock_unlocked':
        return _applyUnlock(database, body);
      case 'customer_receipt':
        return _applyCustomerReceipt(database, body);
      case 'supplier_payment':
        return _applySupplierPayment(database, body);
      case 'sale_return_ledger':
        return _applyReturnLedger(database, body);
      case 'sale_return':
        return true;
      default:
        return true;
    }
  }

  static Future<bool> _applyStock(
    AppDatabase database,
    Map<String, dynamic> body,
    String createdAt,
  ) async {
    final invoiceId = '${body['invoice_id'] ?? ''}'.trim();
    if (invoiceId.isNotEmpty) {
      final own = await (database.select(database.sales)
            ..where((table) => table.serverId.equals(invoiceId)))
          .getSingleOrNull();
      if (own != null) {
        return true;
      }
    }
    final returnId = '${body['return_id'] ?? ''}'.trim();
    if (returnId.isNotEmpty) {
      final own = await (database.select(database.saleReturns)
            ..where((table) => table.id.equals(returnId)))
          .getSingleOrNull();
      if (own != null) {
        return true;
      }
    }

    final variant = await _localVariant(database, '${body['variant_id'] ?? ''}');
    final warehouse = await _localWarehouse(database, '${body['warehouse_id'] ?? ''}');
    if (variant == null || warehouse == null) {
      return false;
    }
    final delta = _asDouble(body['delta']);
    if (delta == 0) {
      return true;
    }
    final balance = await (database.select(database.stockBalances)
          ..where(
            (table) =>
                table.variantId.equals(variant.id) &
                table.warehouseId.equals(warehouse.id),
          ))
        .getSingleOrNull();
    final next = (balance?.quantity ?? 0) + delta;
    final quantity = next < 0 ? 0.0 : next;
    final eventTime = DateTime.tryParse(createdAt) ?? DateTime.now();
    final when = balance != null && balance.updatedAt.isAfter(eventTime)
        ? balance.updatedAt
        : eventTime;
    if (balance == null) {
      await database.into(database.stockBalances).insert(
            StockBalancesCompanion.insert(
              id: _uuid.v4(),
              variantId: variant.id,
              warehouseId: warehouse.id,
              quantity: Value(quantity),
              updatedAt: when,
            ),
          );
    } else {
      await (database.update(database.stockBalances)
            ..where((table) => table.id.equals(balance.id)))
          .write(
        StockBalancesCompanion(
          quantity: Value(quantity),
          updatedAt: Value(when),
        ),
      );
    }
    if (next < -0.0001) {
      await FloorStore.lockVariant(
        database,
        variantId: variant.id,
        serverVariantId: '${body['variant_id'] ?? ''}',
        reason: 'المخزون على السيرفر أقل من رصيد هذه الحاسبة',
      );
    }
    return true;
  }

  static Future<bool> _applyLock(AppDatabase database, Map<String, dynamic> body) async {
    final variant = await _localVariant(database, '${body['variant_id'] ?? ''}');
    if (variant == null) {
      return false;
    }
    await FloorStore.lockVariant(
      database,
      variantId: variant.id,
      serverVariantId: '${body['variant_id'] ?? ''}',
      reason: '${body['reason'] ?? 'المادة مقفلة'}',
      saleId: '${body['sale_key'] ?? ''}',
    );
    return true;
  }

  static Future<bool> _applyUnlock(AppDatabase database, Map<String, dynamic> body) async {
    final variant = await _localVariant(database, '${body['variant_id'] ?? ''}');
    if (variant == null) {
      return false;
    }
    await FloorStore.unlockVariant(database, variant.id);
    return true;
  }

  static Future<bool> _applyCustomerReceipt(
    AppDatabase database,
    Map<String, dynamic> body,
  ) async {
    final paymentId = '${body['payment_id'] ?? ''}'.trim();
    final customer = await _localCustomer(database, '${body['customer_id'] ?? ''}');
    if (paymentId.isEmpty || customer == null) {
      return false;
    }
    final existing = await (database.select(database.customerLedgerEntries)
          ..where((table) => table.referenceId.equals(paymentId)))
        .getSingleOrNull();
    if (existing != null) {
      return true;
    }
    final currency = body['currency'] == 'USD' ? 'USD' : 'IQD';
    await database.into(database.customerLedgerEntries).insert(
          CustomerLedgerEntriesCompanion.insert(
            id: _uuid.v4(),
            customerId: customer.id,
            type: 'RECEIPT',
            amount: _asDouble(body['amount']),
            currency: Value(currency),
            referenceType: const Value('CUSTOMER_RECEIPT'),
            referenceId: Value(paymentId),
            note: const Value('سند قبض وصل من حاسبة أخرى'),
            serverVersion: const Value(0),
            createdAt: DateTime.now(),
          ),
        );
    return true;
  }

  static Future<bool> _applySupplierPayment(
    AppDatabase database,
    Map<String, dynamic> body,
  ) async {
    final paymentId = '${body['payment_id'] ?? ''}'.trim();
    final supplier = await _localSupplier(database, '${body['supplier_id'] ?? ''}');
    if (paymentId.isEmpty || supplier == null) {
      return false;
    }
    final existing = await (database.select(database.supplierLedgerEntries)
          ..where((table) => table.referenceId.equals(paymentId)))
        .getSingleOrNull();
    if (existing != null) {
      return true;
    }
    final currency = body['currency'] == 'USD' ? 'USD' : 'IQD';
    await database.into(database.supplierLedgerEntries).insert(
          SupplierLedgerEntriesCompanion.insert(
            id: _uuid.v4(),
            supplierId: supplier.id,
            type: 'PAYMENT',
            amount: _asDouble(body['amount']),
            currency: Value(currency),
            referenceType: const Value('SUPPLIER_PAYMENT'),
            referenceId: Value(paymentId),
            note: const Value('سند دفع وصل من حاسبة أخرى'),
            serverVersion: const Value(0),
            createdAt: DateTime.now(),
          ),
        );
    return true;
  }

  static Future<bool> _applyReturnLedger(
    AppDatabase database,
    Map<String, dynamic> body,
  ) async {
    final returnId = '${body['return_id'] ?? ''}'.trim();
    final customer = await _localCustomer(database, '${body['customer_id'] ?? ''}');
    if (returnId.isEmpty || customer == null) {
      return false;
    }
    final own = await (database.select(database.saleReturns)
          ..where((table) => table.id.equals(returnId)))
        .getSingleOrNull();
    if (own != null) {
      return true;
    }
    final existing = await (database.select(database.customerLedgerEntries)
          ..where((table) => table.referenceId.equals(returnId)))
        .getSingleOrNull();
    if (existing != null) {
      return true;
    }
    final currency = body['currency'] == 'USD' ? 'USD' : 'IQD';
    await database.into(database.customerLedgerEntries).insert(
          CustomerLedgerEntriesCompanion.insert(
            id: _uuid.v4(),
            customerId: customer.id,
            type: 'REVERSAL',
            amount: _asDouble(body['amount']),
            currency: Value(currency),
            referenceType: const Value('SALE_RETURN'),
            referenceId: Value(returnId),
            note: const Value('مرتجع وصل من حاسبة أخرى'),
            serverVersion: const Value(0),
            createdAt: DateTime.now(),
          ),
        );
    return true;
  }

  static Future<ProductVariant?> _localVariant(AppDatabase database, String serverId) async {
    final clean = serverId.trim();
    if (clean.isEmpty) {
      return null;
    }
    final byServer = await (database.select(database.productVariants)
          ..where((table) => table.serverId.equals(clean)))
        .getSingleOrNull();
    if (byServer != null) {
      return byServer;
    }
    return (database.select(database.productVariants)
          ..where((table) => table.id.equals(clean)))
        .getSingleOrNull();
  }

  static Future<Warehouse?> _localWarehouse(AppDatabase database, String serverId) async {
    final clean = serverId.trim();
    if (clean.isEmpty) {
      return null;
    }
    final byServer = await (database.select(database.warehouses)
          ..where((table) => table.serverId.equals(clean)))
        .getSingleOrNull();
    if (byServer != null) {
      return byServer;
    }
    return (database.select(database.warehouses)
          ..where((table) => table.id.equals(clean)))
        .getSingleOrNull();
  }

  static Future<Customer?> _localCustomer(AppDatabase database, String serverId) async {
    final clean = serverId.trim();
    if (clean.isEmpty) {
      return null;
    }
    final byServer = await (database.select(database.customers)
          ..where((table) => table.serverId.equals(clean)))
        .getSingleOrNull();
    if (byServer != null) {
      return byServer;
    }
    return (database.select(database.customers)
          ..where((table) => table.id.equals(clean)))
        .getSingleOrNull();
  }

  static Future<Supplier?> _localSupplier(AppDatabase database, String serverId) async {
    final clean = serverId.trim();
    if (clean.isEmpty) {
      return null;
    }
    final byServer = await (database.select(database.suppliers)
          ..where((table) => table.serverId.equals(clean)))
        .getSingleOrNull();
    if (byServer != null) {
      return byServer;
    }
    return (database.select(database.suppliers)
          ..where((table) => table.id.equals(clean)))
        .getSingleOrNull();
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value') ?? 0;
  }

  static double _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }
}
