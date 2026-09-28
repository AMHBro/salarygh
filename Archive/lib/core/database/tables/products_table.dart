import 'package:drift/drift.dart';

class Products extends Table {
  /// UUID محلي ثابت.
  /// جميع العلاقات المحلية تعتمد عليه.
  TextColumn get id => text()();

  /// UUID الخاص بالمنتج داخل السيرفر.
  ///
  /// يبقى null إذا المنتج لم تتم مزامنته بعد.
  TextColumn get serverId =>
      text().nullable()();

  TextColumn get barcode =>
      text().nullable()();

  TextColumn get sku =>
      text().nullable()();

  /// الاسم العربي الأساسي.
  TextColumn get name => text()();

  /// الاسم الإنكليزي.
  TextColumn get nameEn =>
      text().nullable()();

  TextColumn get categoryId =>
      text().nullable()();

  /// Snapshot لدعم العرض Offline.
  TextColumn get categoryName =>
      text().nullable()();

  /// UUID لوحدة القياس الأساسية بالسيرفر.
  TextColumn get baseUnitId =>
      text().nullable()();

  /// Snapshot لدعم العرض Offline.
  TextColumn get unit =>
      text().withDefault(
        const Constant('قطعة'),
      )();

  TextColumn get description =>
      text().nullable()();

  /// كم قطعة داخل كارتون هذا المنتج. القطعة وحدها = 1.
  RealColumn get piecesPerCarton => real().withDefault(
    const Constant(1),
  )();

  BoolColumn get hasVariants =>
      boolean().withDefault(
        const Constant(false),
      )();

  BoolColumn get hasExpiry =>
      boolean().withDefault(
        const Constant(false),
      )();

  BoolColumn get hasSerial =>
      boolean().withDefault(
        const Constant(false),
      )();

  TextColumn get imageUrl =>
      text().nullable()();

  RealColumn get costPrice =>
      real().withDefault(
        const Constant(0),
      )();

  RealColumn get representativePrice =>
      real().withDefault(
        const Constant(0),
      )();

  RealColumn get wholesalePrice =>
      real().withDefault(
        const Constant(0),
      )();

  RealColumn get retailPrice =>
      real().withDefault(
        const Constant(0),
      )();

  RealColumn get minimumStock =>
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
}