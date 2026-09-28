import 'package:drift/drift.dart';

class Customers extends Table {
  /// Local UUID
  TextColumn get id => text()();

  /// Backend UUID
  TextColumn get serverId =>
      text().nullable()();

  TextColumn get name => text()();

  TextColumn get phone =>
      text().withDefault(
        const Constant(''),
      )();

  TextColumn get email =>
      text().withDefault(
        const Constant(''),
      )();

  TextColumn get address =>
      text().withDefault(
        const Constant(''),
      )();

  /// RETAIL | WHOLESALE
  TextColumn get type =>
      text().withDefault(
        const Constant('RETAIL'),
      )();

  /// العائلة أو التصنيف الذي يُستخدم لكشف المجموعة.
  TextColumn get groupName =>
      text().withDefault(
        const Constant(''),
      )();

  /// المندوب المحلي المرتبط بالزبون.
  TextColumn get representativeId =>
      text().nullable()();

  RealColumn get creditLimit =>
      real().withDefault(
        const Constant(0),
      )();

  TextColumn get notes =>
      text().nullable()();

  BoolColumn get isActive =>
      boolean().withDefault(
        const Constant(true),
      )();

  IntColumn get serverVersion =>
      integer().withDefault(
        const Constant(0),
      )();

  DateTimeColumn get createdAt =>
      dateTime()();

  DateTimeColumn get updatedAt =>
      dateTime()();

  DateTimeColumn get deletedAt =>
      dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };
}