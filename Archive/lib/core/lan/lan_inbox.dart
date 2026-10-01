import 'dart:convert';

import 'package:drift/drift.dart';

import '../../features/products/models/product_model.dart';
import '../../features/sales/models/cart_item_model.dart';
import '../../features/sales/models/sale_model.dart';
import '../database/app_database.dart';
import '../di/app_services.dart';
import 'office_role.dart';

class LanInbox {
  static Future<void> drain(AppDatabase database) async {
    if (await OfficeRole.instance.isBranch()) {
      return;
    }
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS lan_inbox (
        id TEXT PRIMARY KEY,
        idempotency_key TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL,
        error TEXT,
        result_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    final rows = await database.customSelect(
      '''
      SELECT id, idempotency_key, kind, payload
      FROM lan_inbox
      WHERE status = 'pending' AND kind = 'sale.submit'
      ORDER BY created_at
      LIMIT 5
      ''',
    ).get();
    for (final row in rows) {
      final id = row.read<String>('id');
      final key = row.read<String>('idempotency_key');
      try {
        final existing = await database.customSelect(
          '''
          SELECT id, invoice_number
          FROM sales
          WHERE notes LIKE ?
          LIMIT 1
          ''',
          variables: [Variable.withString('%[lan:$key]%')],
        ).getSingleOrNull();
        if (existing != null) {
          await _mark(
            database,
            id,
            status: 'applied',
            result: {
              'saleId': existing.read<String>('id'),
              'invoiceNumber': existing.read<String>('invoice_number'),
            },
          );
          continue;
        }
        final payload = jsonDecode(row.read<String>('payload'));
        if (payload is! Map) {
          throw StateError('حمولة الفاتورة غير صالحة.');
        }
        final sale = await _apply(payload, key);
        await _mark(
          database,
          id,
          status: 'applied',
          result: {
            'saleId': sale.id,
            'invoiceNumber': sale.invoiceNumber,
          },
        );
      } catch (error) {
        await _mark(
          database,
          id,
          status: 'rejected',
          error: error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
    await _drainWarehouseDeletes(database);
  }

  static Future<void> _drainWarehouseDeletes(AppDatabase database) async {
    final rows = await database.customSelect(
      '''
      SELECT id, payload
      FROM lan_inbox
      WHERE status = 'pending' AND kind = 'warehouse.delete.request'
      ORDER BY created_at
      LIMIT 10
      ''',
    ).get();
    for (final row in rows) {
      final id = row.read<String>('id');
      try {
        final payload = jsonDecode(row.read<String>('payload'));
        if (payload is! Map) {
          throw StateError('طلب الحذف غير صالح.');
        }
        await AppServices.warehousesRepository.receiveBranchDeleteRequest(
          warehouseId: '${payload['warehouseId'] ?? ''}',
          warehouseName: '${payload['warehouseName'] ?? ''}',
          warehouseServerId: payload['warehouseServerId']?.toString(),
          requestedBy: '${payload['requestedBy'] ?? ''}',
        );
        await _mark(database, id, status: 'applied');
      } catch (error) {
        await _mark(
          database,
          id,
          status: 'rejected',
          error: error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  static Future<SaleModel> _apply(Map payload, String key) async {
    final items = <CartItemModel>[];
    final rawItems = payload['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw StateError('الفاتورة بلا مواد.');
    }
    for (final raw in rawItems) {
      if (raw is! Map) {
        continue;
      }
      final name = '${raw['productName'] ?? 'مادة'}';
      final variantId = await _localId(
        'product_variants',
        '${raw['variantId'] ?? ''}',
        raw['variantServerId']?.toString(),
      );
      items.add(
        CartItemModel(
          product: ProductModel(
            id: '${raw['productId'] ?? variantId}',
            barcode: '${raw['barcode'] ?? ''}',
            name: name,
            costPrice: 0,
            wholesalePrice: 0,
            retailPrice: _number(raw['unitPrice']),
          ),
          variantId: variantId.isEmpty ? null : variantId,
          unitId: raw['unitId']?.toString(),
          quantity: _number(raw['quantity']).round(),
          loosePieces: _number(raw['loosePieces']).round(),
          unitFactor: _number(raw['unitFactor']) == 0 ? 1 : _number(raw['unitFactor']),
          priceType: _price(raw['priceType']?.toString()),
          unitPriceOverride: _number(raw['unitPrice']),
          discountPercent: _number(raw['discountPercent']),
        ),
      );
    }
        final marker = '[lan:$key]';
    final notes = '${payload['notes'] ?? ''} $marker'.trim();
    final warehouseId = await _localId(
      'warehouses',
      '${payload['warehouseId'] ?? ''}',
      payload['warehouseServerId']?.toString(),
    );
    final customerId = await _localId(
      'customers',
      '${payload['customerId'] ?? ''}',
      payload['customerServerId']?.toString(),
    );
    return AppServices.salesRepository.createSale(
      warehouseId: warehouseId,
      warehouseName: '${payload['warehouseName'] ?? ''}',
      customerId: customerId.isEmpty ? null : customerId,
      customerName: '${payload['customerName'] ?? ''}',
      representativeId: payload['representativeId']?.toString(),
      items: items,
      subtotal: _number(payload['subtotal']),
      discount: _number(payload['discount']),
      porterage: _number(payload['porterage']),
      total: _number(payload['total']),
      paidAmount: _number(payload['paidAmount']),
      remainingAmount: _number(payload['remainingAmount']),
      paymentType: _payment('${payload['paymentType']}'),
      currency: '${payload['currency'] ?? 'IQD'}',
      exchangeRate: _number(payload['exchangeRate']),
      totalUsd: _number(payload['totalUsd']),
      notes: notes,
    );
  }

  static Future<void> _mark(
    AppDatabase database,
    String id, {
    required String status,
    String? error,
    Map<String, String>? result,
  }) {
    return database.customUpdate(
      '''
      UPDATE lan_inbox
      SET status = ?, error = ?, result_json = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(status),
        Variable.withString(error ?? ''),
        Variable.withString(result == null ? '' : jsonEncode(result)),
        Variable.withString(id),
      ],
    );
  }

  static Future<String> _localId(
    String table,
    String localId,
    String? serverId,
  ) async {
    if (table != 'warehouses' &&
        table != 'customers' &&
        table != 'product_variants') {
      return localId;
    }
    final database = AppServices.database;
    if (localId.trim().isNotEmpty) {
      final byId = await database.customSelect(
        'SELECT id FROM $table WHERE id = ?',
        variables: [Variable.withString(localId)],
      ).getSingleOrNull();
      if (byId != null) {
        return localId;
      }
    }
    final remote = serverId?.trim() ?? '';
    if (remote.isEmpty) {
      return localId;
    }
    final byServer = await database.customSelect(
      'SELECT id FROM $table WHERE server_id = ?',
      variables: [Variable.withString(remote)],
    ).getSingleOrNull();
    if (byServer == null) {
      throw StateError('العنصر غير مزامن على الحاسبة الأساسية.');
    }
    return byServer.read<String>('id');
  }

  static double _number(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }

  static PriceType _price(String? value) {
    switch (value) {
      case 'wholesale':
        return PriceType.wholesale;
      case 'representative':
        return PriceType.representative;
      case 'cost':
        return PriceType.cost;
      default:
        return PriceType.retail;
    }
  }

  static PaymentType _payment(String value) {
    switch (value.toUpperCase()) {
      case 'CREDIT':
        return PaymentType.credit;
      case 'PARTIAL':
        return PaymentType.partial;
      default:
        return PaymentType.cash;
    }
  }
}
