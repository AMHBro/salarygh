import 'package:drift/drift.dart';

class ProductVariants extends Table {
  /// UUID محلي ثابت للـ Variant.
  TextColumn get id => text()();

  /// UUID الخاص بالـ Variant داخل السيرفر.
  ///
  /// يبقى null إذا لم تتم مزامنته بعد.
  TextColumn get serverId =>
      text().nullable()();

  /// المنتج الرئيسي محلياً.
  TextColumn get productId => text()();

  /// باركود خاص بهذا الـ Variant.
  TextColumn get barcode =>
      text().nullable()();

  /// SKU خاص بهذا الـ Variant.
  TextColumn get sku =>
      text().nullable()();

  /// نخزن الـ attributes كـ JSON.
  ///
  /// مثال:
  /// {
  ///   "flavor": "برتقال"
  /// }
  ///
  /// أو:
  /// {
  ///   "color": "أسود",
  ///   "size": "XL"
  /// }
  TextColumn get attributesJson =>
      text().withDefault(
        const Constant('{}'),
      )();

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

  /// متوسط تكلفة الشراء من السيرفر لاحقاً.
  RealColumn get weightedAverageCost =>
      real().withDefault(
        const Constant(0),
      )();

  /// آخر سعر شراء.
  RealColumn get lastPurchasePrice =>
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