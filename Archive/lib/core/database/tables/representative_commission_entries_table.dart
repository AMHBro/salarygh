import 'package:drift/drift.dart';

class RepresentativeCommissionEntries extends Table {
  TextColumn get id => text()();

  TextColumn get representativeId => text()();

  /// حالياً SALE_COMMISSION
  TextColumn get type => text()();

  RealColumn get amount => real()();

  RealColumn get commissionPercentage =>
      real()();

  TextColumn get referenceType =>
      text().nullable()();

  TextColumn get referenceId =>
      text().nullable()();

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
}