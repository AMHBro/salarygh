import 'package:flutter_test/flutter_test.dart';
import 'package:sales_system/core/lan/lan_sync_policy.dart';

void main() {
  test('دفعة الفواتير تتجاوز خمس فواتير وتقف عند الحد', () {
    final rows = [
      for (var index = 0; index < 60; index++)
        {'status': 'pending', 'kind': 'sale.submit', 'id': '$index'},
      {'status': 'pending', 'kind': 'warehouse.delete.request', 'id': 'other'},
    ];
    final batch = LanSyncPolicy.selectSales(rows);
    expect(batch, hasLength(LanSyncPolicy.saleBatchLimit));
    expect(LanSyncPolicy.saleBatchLimit, greaterThan(5));
    expect(batch.last['id'], '49');
  });

  test('إعادة نفس الفاتورة تُغلق، واختلاف الإجمالي تعارض', () {
    expect(
      LanSyncPolicy.decideSale(existing: null, payloadTotal: 10),
      'create',
    );
    expect(
      LanSyncPolicy.decideSale(
        existing: {'id': 'sale-1', 'total': 10},
        payloadTotal: 10,
      ),
      'already_applied',
    );
    expect(
      LanSyncPolicy.decideSale(
        existing: {'id': 'sale-1', 'total': 10},
        payloadTotal: 12,
      ),
      'conflict',
    );
  });

  test('سحب المخزون والكتالوج من الرئيسي يستبدل نسخة الفرع', () {
    final stock = LanSyncPolicy.mergeStock(
      [
        {'variant_id': 'v1', 'warehouse_id': 'w1', 'quantity': 4},
      ],
      [
        {'variant_id': 'v1', 'warehouse_id': 'w1', 'quantity': 9},
        {'variant_id': 'v2', 'warehouse_id': 'w1', 'quantity': 3},
      ],
    );
    expect(stock, hasLength(2));
    expect(
      stock.firstWhere((row) => row['variant_id'] == 'v1')['quantity'],
      9,
    );

    final catalog = LanSyncPolicy.mergeCatalog(
      [
        {'barcode': '100', 'name': 'شاي', 'retail_price': 1000},
      ],
      [
        {'barcode': '100', 'name': 'شاي', 'retail_price': 1500, 'wholesale_price': 1200},
      ],
    );
    expect(catalog.single['retail_price'], 1500);
    expect(catalog.single['wholesale_price'], 1200);
  });
}
