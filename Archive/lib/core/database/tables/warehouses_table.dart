import 'package:drift/drift.dart';

class Warehouses extends Table {
  /// Local UUID.
  TextColumn get id => text()();

  /// UUID الخاص بالمخزن في الـBackend.
  TextColumn get serverId =>
      text().nullable()();

  TextColumn get name => text()();

  TextColumn get code =>
      text().nullable()();

  /// Backend Branch UUID.
  TextColumn get branchId =>
      text().nullable()();

  /// MAIN / SUB / VIRTUAL
  TextColumn get type =>
      text().withDefault(
        const Constant('SUB'),
      )();

  /// LOCAL / DRAFT / PENDING_APPROVAL / ACTIVE / ...
  TextColumn get status =>
      text().withDefault(
        const Constant('LOCAL'),
      )();

  /// Backend Warehouse UUID.
  /// يستخدم فقط إذا كان النوع SUB.
  TextColumn get parentWarehouseId =>
      text().nullable()();

  /// Backend User UUID.
  TextColumn get managerId =>
      text().nullable()();

  TextColumn get address =>
      text().nullable()();

  RealColumn get capacity =>
      real().nullable()();

  TextColumn get notes =>
      text().nullable()();

  TextColumn get rejectionReason =>
      text().nullable()();

  /// Compatibility مع الكود القديم.
  BoolColumn get isMain =>
      boolean().withDefault(
        const Constant(false),
      )();

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