import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/public_server_session.dart';
import '../models/ecommerce_order_model.dart';

/// يجلب طلبات المتجر من السيرفر العام ويحفظها في sayler.sqlite.
class CloudStoreOrders {
  CloudStoreOrders(this.database);

  final AppDatabase database;

  Future<List<EcommerceOrderModel>> pull() async {
    try {
      await _pullPages();
    } catch (error) {
      debugPrint('[STORE] cloud orders pull skipped: $error');
    }
    return read();
  }

  Future<void> _pullPages() async {
    var page = 1;
    var totalPages = 1;
    while (page <= totalPages && page <= 50) {
      final response = await PublicServerSession.send(
        method: 'GET',
        path: '/admin/ecommerce/orders',
        query: {
          'page': page,
          'limit': 50,
        },
      );
      final body = response.data;
      final parsed = body is Map
          ? EcommerceOrdersPage.fromJson(
              Map<String, dynamic>.from(body),
            )
          : null;
      final raw = body is Map && body['data'] is List
          ? body['data'] as List
          : const [];
      for (final item in raw.whereType<Map>()) {
        final json = Map<String, dynamic>.from(item);
        final id = json['id']?.toString() ?? '';
        if (id.isEmpty) {
          continue;
        }
        await database.customStatement(
          '''
INSERT OR REPLACE INTO cloud_store_orders (
  id, order_number, payload_json, updated_at
) VALUES (?, ?, ?, ?)
''',
          [
            id,
            json['order_number']?.toString() ?? '',
            jsonEncode(json),
            DateTime.now().toIso8601String(),
          ],
        );
      }
      totalPages = parsed?.totalPages ?? 1;
      if (totalPages < 1) {
        totalPages = 1;
      }
      page += 1;
      if (raw.isEmpty) {
        break;
      }
    }
  }

  Future<List<EcommerceOrderModel>> read() async {
    final rows = await database.customSelect('''
SELECT payload_json
FROM cloud_store_orders
ORDER BY updated_at DESC
''').get();
    final orders = <EcommerceOrderModel>[];
    for (final row in rows) {
      final raw = row.data['payload_json']?.toString() ?? '';
      if (raw.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          orders.add(
            EcommerceOrderModel.fromJson(
              Map<String, dynamic>.from(decoded),
            ),
          );
        }
      } catch (error) {
        debugPrint('[STORE] cloud order row skipped: $error');
      }
    }
    return orders;
  }
}
