import 'package:drift/drift.dart';

class StockBalances extends Table {
  TextColumn get id => text()();

  //
  // المخزون صار Variant-first.
  //
  // حتى المنتج البسيط عنده Default Variant
  // لذلك ما نحتاج نخزن productId هنا.
  //
  TextColumn get variantId => text()();

  //
  // المخزن الذي يوجد داخله هذا الرصيد.
  //
  TextColumn get warehouseId => text()();

  //
  // الكمية الحالية لهذا الـVariant داخل هذا المخزن.
  //
  RealColumn get quantity => real().withDefault(
    const Constant(0),
  )();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };

  //
  // لا يجوز أن يكون عندنا أكثر من Stock Balance
  // لنفس Variant داخل نفس Warehouse.
  //
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {
      variantId,
      warehouseId,
    },
  ];
}