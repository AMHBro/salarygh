import 'package:drift/drift.dart';

class Suppliers extends Table {
  /// UUID محلي ثابت.
  ///
  /// جميع العلاقات المحلية مثل المشتريات والدفعات
  /// تعتمد على هذا الـID.
  TextColumn get id => text()();

  /// UUID الخاص بالمورد داخل السيرفر.
  ///
  /// يبقى null إذا المورد لم تتم مزامنته بعد.
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

  TextColumn get taxNumber =>
      text().withDefault(
        const Constant(''),
      )();

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