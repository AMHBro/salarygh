import 'package:drift/drift.dart';

class Representatives extends Table {
  TextColumn get id => text()();

  // UUID الحقيقي للمندوب على السيرفر.
  // يبقى null إلى أن تنجح أول مزامنة CREATE.
  TextColumn get serverId =>
      text().nullable()();

  TextColumn get name => text()();

  TextColumn get username => text()();

  TextColumn get phone =>
      text().withDefault(
        const Constant(''),
      )();

  TextColumn get officeName =>
      text().withDefault(
        const Constant(''),
      )();

  TextColumn get officeAddress =>
      text().withDefault(
        const Constant(''),
      )();

  TextColumn get officePhone =>
      text().withDefault(
        const Constant(''),
      )();

  TextColumn get locationLink =>
      text().nullable()();

  RealColumn get commissionPercentage =>
      real().withDefault(
        const Constant(0),
      )();

  /// أسعار البيع المسموحة للمندوب، مفصولة بفاصلة.
  TextColumn get allowedPrices =>
      text().withDefault(
        const Constant('wholesale,representative,retail'),
      )();

  /// 0 يعني لا يوجد سقف. أي قيمة أكبر تُقارن بمجموع ديون زبائن المندوب.
  RealColumn get maxDebtLimit =>
      real().withDefault(
        const Constant(0),
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

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {
      username,
    },
  ];
}