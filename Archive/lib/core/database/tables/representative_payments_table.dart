import 'package:drift/drift.dart';

class RepresentativePayments extends Table {
  TextColumn get id => text()();

  TextColumn get voucherNumber => text()();

  TextColumn get representativeId => text()();

  /// CASH / BANK / OTHER
  TextColumn get method =>
      text().withDefault(
        const Constant('CASH'),
      )();

  RealColumn get amount => real()();

  TextColumn get note =>
      text().nullable()();

  TextColumn get userId =>
      text().nullable()();

  IntColumn get serverVersion =>
      integer().withDefault(
        const Constant(0),
      )();

  DateTimeColumn get createdAt =>
      dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {
      voucherNumber,
    },
  ];
}