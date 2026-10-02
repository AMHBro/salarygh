const test = require('node:test');
const assert = require('node:assert/strict');
const {
  SALE_BATCH_LIMIT,
  selectSales,
  decideSale,
  mergeStock,
  mergeCatalog,
} = require('./sync-policy');

test('sale.submit batch is larger than five and stops at the limit', () => {
  const rows = [];
  for (let index = 0; index < 60; index += 1) {
    rows.push({ status: 'pending', kind: 'sale.submit', id: String(index) });
  }
  rows.push({ status: 'pending', kind: 'warehouse.delete.request', id: 'other' });
  const batch = selectSales(rows);
  assert.equal(batch.length, SALE_BATCH_LIMIT);
  assert.ok(SALE_BATCH_LIMIT > 5);
  assert.equal(batch.at(-1).id, '49');
});

test('same invoice is already applied and a different total is a conflict', () => {
  assert.equal(decideSale(null, 10), 'create');
  assert.equal(decideSale({ id: 'sale-1', total: 10 }, 10), 'already_applied');
  assert.equal(decideSale({ id: 'sale-1', total: 10 }, 12), 'conflict');
});

test('HQ stock and catalog replace the branch copy', () => {
  const stock = mergeStock(
    [{ variant_id: 'v1', warehouse_id: 'w1', quantity: 4 }],
    [
      { variant_id: 'v1', warehouse_id: 'w1', quantity: 9 },
      { variant_id: 'v2', warehouse_id: 'w1', quantity: 3 },
    ],
  );
  assert.equal(stock.length, 2);
  assert.equal(stock.find((row) => row.variant_id === 'v1').quantity, 9);

  const catalog = mergeCatalog(
    [{ barcode: '100', name: 'شاي', retail_price: 1000 }],
    [{ barcode: '100', name: 'شاي', retail_price: 1500, wholesale_price: 1200 }],
  );
  assert.equal(catalog[0].retail_price, 1500);
  assert.equal(catalog[0].wholesale_price, 1200);
});
