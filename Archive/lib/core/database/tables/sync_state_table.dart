import 'package:drift/drift.dart';

class SyncState extends Table {
  TextColumn get key => text()();

  TextColumn get value => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    key,
  };
}