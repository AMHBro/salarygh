import 'package:drift/drift.dart';

class SaleItems extends Table {
  TextColumn get id => text()();

  /// Local Sale UUID.
  TextColumn get saleId => text()();

  /// Local Product UUID.
  TextColumn get productId => text()();

  /// Local ProductVariant UUID.
  ///
  /// Nullable فقط لدعم البيانات القديمة.
  TextColumn get variantId =>
      text().nullable()();

  /// Unit UUID.
  ///
  /// Units.id عندنا هو نفسه Server UUID.
  TextColumn get unitId =>
      text().nullable()();

  TextColumn
  get productNameSnapshot =>
      text()();

  TextColumn get barcodeSnapshot =>
      text().nullable()();

  /// COST / REP / WHOLESALE / RETAIL.
  TextColumn get priceType =>
      text()();

  RealColumn get quantity => real()();

  /// كم قطعة داخل وحدة السطر. القطعة = 1، والكارتون = العدد الذي يحدده المستخدم.
  RealColumn get unitFactor => real().withDefault(
    const Constant(1),
  )();

  /// قطع مفردة تُباع مع الكارتون أو بدونه. الصفر مسموح.
  IntColumn get loosePieces => integer().withDefault(
    const Constant(0),
  )();

  RealColumn get unitPrice => real()();

  /// الخصم على مستوى السطر بالنسبة المئوية.
  RealColumn get discountPercent =>
      real().withDefault(
        const Constant(0),
      )();

  RealColumn get total => real()();

  DateTimeColumn get createdAt =>
      dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };
}