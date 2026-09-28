import 'package:drift/drift.dart';

class StockMovements extends Table {
  TextColumn get id => text()();

  //
  // كل حركة مخزون تخص Variant محدد.
  //
  // حتى المنتج البسيط عنده Default Variant،
  // لذلك ما نحتاج productId هنا.
  //
  TextColumn get variantId => text()();

  //
  // المخزن الذي حصلت داخله الحركة.
  //
  TextColumn get warehouseId => text()();

  //
  // نوع الحركة:
  // IN / OUT / TRANSFER_IN / TRANSFER_OUT
  // أو أي أنواع نعتمدها داخل النظام.
  //
  TextColumn get type => text()();

  //
  // كمية الحركة.
  //
  RealColumn get quantity => real()();

  //
  // نوع المرجع المرتبط بالحركة
  // مثل:
  // SALE / PURCHASE / TRANSFER / ADJUSTMENT
  //
  TextColumn get referenceType => text().nullable()();

  //
  // ID للسجل المسبب للحركة
  // مثل Sale ID أو Purchase ID.
  //
  TextColumn get referenceId => text().nullable()();

  TextColumn get note => text().nullable()();

  TextColumn get userId => text().nullable()();

  IntColumn get serverVersion => integer().withDefault(
    const Constant(0),
  )();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };
}