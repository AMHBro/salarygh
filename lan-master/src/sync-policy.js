const SALE_BATCH_LIMIT = 50;

function selectSales(rows) {
  return rows
    .filter((row) => row.status === 'pending' && row.kind === 'sale.submit')
    .slice(0, SALE_BATCH_LIMIT);
}

function decideSale(existing, payloadTotal) {
  if (!existing) return 'create';
  if (typeof existing.total === 'number' && existing.total !== payloadTotal) {
    return 'conflict';
  }
  return 'already_applied';
}

function mergeStock(local, remote) {
  const merged = new Map();
  for (const row of local) {
    merged.set(`${row.variant_id}|${row.warehouse_id}`, { ...row });
  }
  for (const row of remote) {
    const key = `${row.variant_id}|${row.warehouse_id}`;
    const current = merged.get(key) ?? {};
    merged.set(key, { ...current, ...row, quantity: row.quantity });
  }
  return [...merged.values()];
}

function mergeCatalog(local, remote) {
  const merged = new Map();
  for (const row of local) {
    if (!row.barcode) continue;
    merged.set(row.barcode, { ...row });
  }
  for (const row of remote) {
    if (!row.barcode) continue;
    const current = merged.get(row.barcode) ?? {};
    merged.set(row.barcode, {
      ...current,
      ...row,
      retail_price: row.retail_price,
      wholesale_price: row.wholesale_price,
    });
  }
  return [...merged.values()];
}

module.exports = {
  SALE_BATCH_LIMIT,
  selectSales,
  decideSale,
  mergeStock,
  mergeCatalog,
};
