import 'package:drift/drift.dart';

class SyncOutbox extends Table {
  TextColumn get id => text()();

  TextColumn get entityType => text()();

  TextColumn get entityId => text()();

  TextColumn get operation => text()();

  TextColumn get payloadJson => text()();

  TextColumn get idempotencyKey => text()();

  TextColumn get status => text().withDefault(
    const Constant('PENDING'),
  )();

  IntColumn get attempts => integer().withDefault(
    const Constant(0),
  )();

  TextColumn get lastError => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };
}