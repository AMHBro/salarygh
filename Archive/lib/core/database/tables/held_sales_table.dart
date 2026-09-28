import 'package:drift/drift.dart';

class HeldSales extends Table {
  /// Local UUID فقط.
  TextColumn get id => text()();

  /// Local Warehouse UUID.
  TextColumn get warehouseId => text()();

  TextColumn get warehouseNameSnapshot => text()();

  /// Local Customer UUID.
  ///
  /// null = زبون نقدي.
  TextColumn get customerId => text().nullable()();

  TextColumn get customerNameSnapshot => text()();

  /// Local Representative UUID.
  TextColumn get representativeId => text().nullable()();

  TextColumn get representativeNameSnapshot => text().nullable()();

  /// COST / REP / WHOLESALE / RETAIL.
  TextColumn get priceType => text()();

  /// CASH / CREDIT / PARTIAL.
  TextColumn get paymentType => text()();

  RealColumn get discount => real().withDefault(
    const Constant(0),
  )();

  RealColumn get paidAmount => real().withDefault(
    const Constant(0),
  )();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };
}