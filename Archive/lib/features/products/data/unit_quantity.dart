import '../../../core/database/app_database.dart';

/// المخزون يُحفظ بالوحدة الأساس.
///
/// إذا كانت وحدة السطر كارتوناً فيه 12 قطعة، فالكمية المخزنية = العدد × 12.
Future<double> quantityInBaseUnit({
  required AppDatabase database,
  required String? unitId,
  required double quantity,
  double? factor,
}) async {
  if (quantity == 0) {
    return 0;
  }

  if (factor != null && factor > 0) {
    return factor <= 1 ? quantity : quantity * factor;
  }

  final id = unitId?.trim() ?? '';
  if (id.isEmpty) {
    return quantity;
  }

  final unit = await (database.select(database.units)
        ..where((table) => table.id.equals(id)))
      .getSingleOrNull();
  final conversion = unit?.conversionFactor ?? 1;
  if (conversion <= 1) {
    return quantity;
  }

  return quantity * conversion;
}
