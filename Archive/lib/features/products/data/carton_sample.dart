import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/app_services.dart';

/// يجهّز قطعة وكارتون فيه 4 قطع، ومنتج كيك حتى تُجرَّب المبيعات والمشتريات.
Future<void> ensureCartonSample() async {
  try {
    await _ensureCartonSample();
  } catch (error, stack) {
    debugPrint('تعذر تجهيز بيانات الكارتون: $error\n$stack');
  }
}

Future<void> _ensureCartonSample() async {
  final database = AppServices.database;
  final piece = await AppServices.unitsRepository.createUnit(
    nameAr: 'قطعة',
    symbol: 'قطعة',
  );
  final carton = await AppServices.unitsRepository.createUnit(
    nameAr: 'كارتون',
    symbol: 'كرتون',
    parentUnitId: piece.id,
    conversionFactor: 4,
  );

  if (carton.parentUnitId != piece.id || carton.conversionFactor != 4) {
    await (database.update(database.units)
          ..where((table) => table.id.equals(carton.id)))
        .write(
      UnitsCompanion(
        parentUnitId: Value(piece.id),
        conversionFactor: const Value(4),
        isBaseUnit: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  final categories = await AppServices.categoriesRepository.getCategories();
  final category = categories.isNotEmpty
      ? categories.first
      : await AppServices.categoriesRepository.createCategory(
          nameAr: 'حلويات',
        );

  final byBarcode = await (database.select(database.products)
        ..where(
          (table) =>
              table.barcode.equals('CAKE-4') & table.deletedAt.isNull(),
        )
        ..limit(1))
      .get();
  final byName = byBarcode.isNotEmpty
      ? byBarcode
      : await (database.select(database.products)
            ..where(
              (table) => table.name.equals('كيك') & table.deletedAt.isNull(),
            )
            ..limit(1))
          .get();

  final String productId;
  if (byName.isNotEmpty) {
    final existing = byName.first;
    productId = existing.id;
    if (existing.baseUnitId != piece.id) {
      await (database.update(database.products)
            ..where((table) => table.id.equals(existing.id)))
          .write(
        ProductsCompanion(
          baseUnitId: Value(piece.id),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  } else {
    final created = await AppServices.productsRepository.createProduct(
      name: 'كيك',
      barcode: 'CAKE-4',
      categoryId: category.id,
      categoryName: category.nameAr,
      baseUnitId: piece.id,
      unit: 'قطعة',
      description: 'كارتون فيه 4 قطع. سعر القطعة 5100، وشراء الكارتون 20000.',
      costPrice: 5000,
      representativePrice: 5050,
      wholesalePrice: 5080,
      retailPrice: 5100,
      minimumStock: 4,
    );
    productId = created.id;
  }

  final cake = await (database.select(database.products)
        ..where((table) => table.id.equals(productId)))
      .getSingleOrNull();
  if (cake != null && cake.piecesPerCarton <= 1) {
    await (database.update(database.products)
          ..where((table) => table.id.equals(productId)))
        .write(
      ProductsCompanion(
        piecesPerCarton: const Value(4),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  final variants = await (database.select(database.productVariants)
        ..where(
          (table) =>
              table.productId.equals(productId) & table.deletedAt.isNull(),
        )
        ..limit(1))
      .get();

  final String variantId;
  if (variants.isEmpty) {
    variantId = const Uuid().v4();
    final now = DateTime.now();
    await database.into(database.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: variantId,
            productId: productId,
            barcode: const Value('CAKE-4'),
            costPrice: const Value(5000),
            representativePrice: const Value(5050),
            wholesalePrice: const Value(5080),
            retailPrice: const Value(5100),
            lastPurchasePrice: const Value(5000),
            createdAt: now,
            updatedAt: now,
          ),
        );
  } else {
    variantId = variants.first.id;
    if (variants.first.retailPrice <= 0) {
      await (database.update(database.productVariants)
            ..where((table) => table.id.equals(variantId)))
          .write(
        ProductVariantsCompanion(
          costPrice: const Value(5000),
          representativePrice: const Value(5050),
          wholesalePrice: const Value(5080),
          retailPrice: const Value(5100),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  final warehouses = await (database.select(database.warehouses)
        ..where(
          (table) => table.deletedAt.isNull() & table.isActive.equals(true),
        ))
      .get();
  if (warehouses.isEmpty) {
    return;
  }

  final warehouse = warehouses.firstWhere(
    (row) => row.isMain,
    orElse: () => warehouses.first,
  );
  final balances = await (database.select(database.stockBalances)
        ..where(
          (table) =>
              table.variantId.equals(variantId) &
              table.warehouseId.equals(warehouse.id),
        )
        ..limit(1))
      .get();

  if (balances.isEmpty) {
    await database.into(database.stockBalances).insert(
          StockBalancesCompanion.insert(
            id: '$variantId::${warehouse.id}',
            variantId: variantId,
            warehouseId: warehouse.id,
            quantity: const Value(24),
            updatedAt: DateTime.now(),
          ),
        );
  } else if (balances.first.quantity < 4) {
    await (database.update(database.stockBalances)
          ..where((table) => table.id.equals(balances.first.id)))
        .write(
      StockBalancesCompanion(
        quantity: const Value(24),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
