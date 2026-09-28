import 'package:drift/drift.dart';

class PurchaseItems extends Table {
  TextColumn get id => text()();

  TextColumn get purchaseId => text()();

  /// Local Product UUID.
  TextColumn get productId => text()();

  /// Local ProductVariant UUID.
  ///
  /// Nullable فقط لدعم البيانات القديمة قبل V15.
  /// كل فاتورة جديدة يجب أن تخزن variantId.
  TextColumn get variantId =>
      text().nullable()();

  /// Unit UUID.
  ///
  /// Units.id عندنا هو نفسه Server UUID.
  /// Nullable لدعم البيانات القديمة.
  TextColumn get unitId =>
      text().nullable()();

  TextColumn get productNameSnapshot =>
      text()();

  TextColumn get barcodeSnapshot =>
      text().withDefault(
        const Constant(''),
      )();

  IntColumn get quantity => integer()();

  /// كم قطعة داخل وحدة السطر. القطعة = 1، والكارتون = العدد الذي يحدده المستخدم.
  RealColumn get unitFactor => real().withDefault(
    const Constant(1),
  )();

  RealColumn get unitCost => real()();

  /// خصم على مستوى سطر الفاتورة بالنسبة المئوية.
  RealColumn get discountPercent =>
      real().withDefault(
        const Constant(0),
      )();

  DateTimeColumn get createdAt =>
      dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };
}