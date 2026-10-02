class LanSyncPolicy {
  static const saleBatchLimit = 50;

  static List<Map<String, Object?>> selectSales(List<Map<String, Object?>> rows) {
    return rows
        .where((row) => row['status'] == 'pending' && row['kind'] == 'sale.submit')
        .take(saleBatchLimit)
        .toList();
  }

  static String decideSale({
    Map<String, Object?>? existing,
    required num payloadTotal,
  }) {
    if (existing == null) return 'create';
    final stored = existing['total'];
    if (stored is num && stored != payloadTotal) return 'conflict';
    return 'already_applied';
  }

  static List<Map<String, Object?>> mergeStock(
    List<Map<String, Object?>> local,
    List<Map<String, Object?>> remote,
  ) {
    final merged = <String, Map<String, Object?>>{};
    for (final row in local) {
      merged['${row['variant_id']}|${row['warehouse_id']}'] = Map<String, Object?>.of(row);
    }
    for (final row in remote) {
      final key = '${row['variant_id']}|${row['warehouse_id']}';
      final current = merged[key];
      merged[key] = {
        ...?current,
        ...row,
        'quantity': row['quantity'],
      };
    }
    return merged.values.toList();
  }

  static List<Map<String, Object?>> mergeCatalog(
    List<Map<String, Object?>> local,
    List<Map<String, Object?>> remote,
  ) {
    final merged = <String, Map<String, Object?>>{};
    for (final row in local) {
      final barcode = '${row['barcode'] ?? ''}';
      if (barcode.isEmpty) continue;
      merged[barcode] = Map<String, Object?>.of(row);
    }
    for (final row in remote) {
      final barcode = '${row['barcode'] ?? ''}';
      if (barcode.isEmpty) continue;
      final current = merged[barcode];
      merged[barcode] = {
        ...?current,
        ...row,
        'retail_price': row['retail_price'],
        'wholesale_price': row['wholesale_price'],
      };
    }
    return merged.values.toList();
  }
}
