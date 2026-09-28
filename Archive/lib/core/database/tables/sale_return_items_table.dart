import 'package:drift/drift.dart';

class SaleReturnItems extends Table {
  TextColumn get id => text()();

  TextColumn get returnId => text()();

  TextColumn get saleItemId => text()();

  TextColumn get variantId => text()();

  /// عدد القطع الراجعة من أصل قطع السطر.
  RealColumn get quantity => real()();

  /// سعر القطعة بالدينار بعد خصم السطر.
  RealColumn get unitPrice => real()();

  RealColumn get total => real()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
