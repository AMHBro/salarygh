import 'package:drift/drift.dart';

class HeldSaleItems extends Table {
  TextColumn get id => text()();

  /// HeldSales.id.
  TextColumn get heldSaleId => text()();

  /// Local Product UUID.
  TextColumn get productId => text()();

  /// Local Variant UUID.
  TextColumn get variantId => text()();

  /// Unit UUID.
  TextColumn get unitId => text()();

  TextColumn get productNameSnapshot => text()();

  TextColumn get barcodeSnapshot => text().nullable()();

  /// COST / REP / WHOLESALE / RETAIL.
  TextColumn get priceType => text()();

  IntColumn get quantity => integer()();

  RealColumn get unitFactor => real().withDefault(
    const Constant(1),
  )();

  IntColumn get loosePieces => integer().withDefault(
    const Constant(0),
  )();

  RealColumn get unitPrice => real()();

  RealColumn get discountPercent => real().withDefault(
    const Constant(0),
  )();

  RealColumn get total => real()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };
}