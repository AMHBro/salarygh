import 'package:drift/drift.dart';

class SaleReturns extends Table {
  TextColumn get id => text()();

  TextColumn get voucherNumber => text()();

  TextColumn get saleId => text()();

  TextColumn get customerId => text().nullable()();

  TextColumn get warehouseId => text()();

  /// مجموع المرتجع بالدينار. أثر الذمة يُحوَّل لعملة القائمة عند التسجيل.
  RealColumn get total => real()();

  TextColumn get currency => text().withDefault(const Constant('IQD'))();

  RealColumn get exchangeRate => real().withDefault(const Constant(0))();

  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
