import 'package:drift/drift.dart';

class CustomerLedgerEntries extends Table {
  TextColumn get id => text()();

  TextColumn get customerId => text()();

  /// SALE
  /// RECEIPT
  /// OPENING_BALANCE
  /// REVERSAL
  TextColumn get type => text()();

  RealColumn get amount => real()();

  /// IQD أو USD. المبلغ يبقى بعملة الحركة ولا يُحوَّل.
  TextColumn get currency => text().withDefault(const Constant('IQD'))();

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