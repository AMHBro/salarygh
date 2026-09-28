import 'package:drift/drift.dart';

class Categories extends Table {
  TextColumn get id => text()();

  TextColumn get nameAr => text()();

  TextColumn get nameEn =>
      text().nullable()();

  TextColumn get parentId =>
      text().nullable()();

  IntColumn get level =>
      integer().withDefault(
        const Constant(0),
      )();

  TextColumn get path =>
      text().nullable()();

  TextColumn get imageUrl =>
      text().nullable()();

  IntColumn get orderIndex =>
      integer().withDefault(
        const Constant(0),
      )();

  BoolColumn get isActive =>
      boolean().withDefault(
        const Constant(true),
      )();

  DateTimeColumn get createdAt =>
      dateTime().nullable()();

  DateTimeColumn get updatedAt =>
      dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };
}