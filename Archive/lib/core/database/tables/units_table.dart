import 'package:drift/drift.dart';

class Units extends Table {
  TextColumn get id => text()();

  TextColumn get nameAr => text()();

  TextColumn get nameEn =>
      text().nullable()();

  TextColumn get symbol => text()();

  TextColumn get parentUnitId =>
      text().nullable()();

  RealColumn get conversionFactor =>
      real().withDefault(
        const Constant(1),
      )();

  BoolColumn get isBaseUnit =>
      boolean().withDefault(
        const Constant(false),
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