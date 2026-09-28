import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';

class ProductDirectoryPage {
  final List<ProductModel> items;
  final int total;
  final int activeCount;
  final int syncedCount;
  final int variantCount;

  const ProductDirectoryPage({
    required this.items,
    required this.total,
    required this.activeCount,
    required this.syncedCount,
    required this.variantCount,
  });

  bool get hasMore => items.length < total;
}

class ProductsLocalRepository {
  final AppDatabase database;
  final SyncQueueRepository syncQueue;

  static const Uuid _uuid = Uuid();

  ProductsLocalRepository({
    required this.database,
    required this.syncQueue,
  });

  // ---------------------------------------------------------------------------
  // WATCH PRODUCTS
  // ---------------------------------------------------------------------------

  Stream<List<ProductModel>> watchProducts({
    String search = '',
  }) {
    final normalizedSearch = search.trim().toLowerCase();

    final query = database.select(database.products)
      ..where(
            (table) => table.deletedAt.isNull(),
      )
      ..orderBy([
            (table) => OrderingTerm.desc(
          table.createdAt,
        ),
      ]);

    return query.watch().asyncMap(
          (rows) async {
        final products = <ProductModel>[];

        for (final row in rows) {
          products.add(
            await _mapRowToModelWithVariants(row),
          );
        }

        if (normalizedSearch.isEmpty) {
          return products;
        }

        return products.where(
              (product) {
            if (product.name.toLowerCase().contains(normalizedSearch)) {
              return true;
            }

            if (product.nameEn.toLowerCase().contains(normalizedSearch)) {
              return true;
            }

            if (product.barcode.toLowerCase().contains(normalizedSearch)) {
              return true;
            }

            if ((product.sku ?? '')
                .toLowerCase()
                .contains(normalizedSearch)) {
              return true;
            }

            if (product.categoryName
                .toLowerCase()
                .contains(normalizedSearch)) {
              return true;
            }

            for (final variant in product.variants) {
              if (variant.barcode
                  .toLowerCase()
                  .contains(normalizedSearch)) {
                return true;
              }

              if ((variant.sku ?? '')
                  .toLowerCase()
                  .contains(normalizedSearch)) {
                return true;
              }

              if (variant.displayName
                  .toLowerCase()
                  .contains(normalizedSearch)) {
                return true;
              }

              for (final value in variant.attributes.values) {
                if (value.toLowerCase().contains(normalizedSearch)) {
                  return true;
                }
              }
            }

            return false;
          },
        ).toList();
      },
    );
  }

  Stream<ProductDirectoryPage> watchProductPage({
    String search = '',
    int limit = kListPageSize,
    int offset = 0,
    bool includeInactive = false,
  }) {
    final stamp = database.customSelect(
      'SELECT COUNT(*) AS n FROM products',
      readsFrom: {database.products, database.productVariants},
    ).watch();
    return stamp.asyncMap(
      (_) => loadProductPage(
        search: search,
        limit: limit,
        offset: offset,
        includeInactive: includeInactive,
      ),
    );
  }

  Future<List<ProductModel>> searchProducts(
    String query, {
    int limit = 10,
    int offset = 0,
  }) async {
    final page = await loadProductPage(
      search: query,
      limit: limit,
      offset: offset,
      includeInactive: false,
    );
    return page.items;
  }

  Future<ProductDirectoryPage> loadProductPage({
    String search = '',
    int limit = kListPageSize,
    int offset = 0,
    bool includeInactive = false,
  }) async {
    final query = search.trim();
    final like = '%$query%';
    const match = '''
(
  ? = ''
  OR p.name LIKE ?
  OR IFNULL(p.name_en, '') LIKE ?
  OR IFNULL(p.barcode, '') LIKE ?
  OR IFNULL(p.sku, '') LIKE ?
  OR IFNULL(p.category_name, '') LIKE ?
  OR IFNULL(v.barcode, '') LIKE ?
  OR IFNULL(v.sku, '') LIKE ?
  OR IFNULL(v.attributes_json, '') LIKE ?
)
''';
    final active = includeInactive ? '1 = 1' : 'p.is_active = 1';
    final variables = [
      Variable.withString(query),
      Variable.withString(like),
      Variable.withString(like),
      Variable.withString(like),
      Variable.withString(like),
      Variable.withString(like),
      Variable.withString(like),
      Variable.withString(like),
      Variable.withString(like),
    ];
    final from = '''
FROM products p
LEFT JOIN product_variants v
  ON v.product_id = p.id AND v.deleted_at IS NULL
WHERE p.deleted_at IS NULL AND $active AND $match
''';
    final summary = await database.customSelect(
      '''
SELECT
  COUNT(DISTINCT p.id) AS total,
  COUNT(DISTINCT CASE WHEN p.is_active = 1 THEN p.id END) AS active_count,
  COUNT(DISTINCT CASE
    WHEN p.server_id IS NOT NULL AND TRIM(p.server_id) != '' THEN p.id
  END) AS synced_count,
  COUNT(DISTINCT v.id) AS variant_count
$from
''',
      variables: variables,
    ).getSingle();
    final idRows = await database.customSelect(
      '''
SELECT DISTINCT p.id AS id, p.created_at AS created_at
$from
ORDER BY p.created_at DESC
LIMIT ? OFFSET ?
''',
      variables: [
        ...variables,
        Variable.withInt(limit),
        Variable.withInt(offset),
      ],
    ).get();
    final ids = [for (final row in idRows) row.read<String>('id')];
    final items = <ProductModel>[];
    for (final id in ids) {
      final product = await getProductById(id);
      if (product != null) {
        items.add(product);
      }
    }
    return ProductDirectoryPage(
      items: items,
      total: sqlInt(summary, 'total'),
      activeCount: sqlInt(summary, 'active_count'),
      syncedCount: sqlInt(summary, 'synced_count'),
      variantCount: sqlInt(summary, 'variant_count'),
    );
  }

  // ---------------------------------------------------------------------------
  // GET PRODUCTS
  // ---------------------------------------------------------------------------

  Future<List<ProductModel>> getProducts() async {
    final query = database.select(database.products)
      ..where(
            (table) => table.deletedAt.isNull(),
      )
      ..orderBy([
            (table) => OrderingTerm.desc(
          table.createdAt,
        ),
      ]);

    final rows = await query.get();

    final products = <ProductModel>[];

    for (final row in rows) {
      products.add(
        await _mapRowToModelWithVariants(row),
      );
    }

    return products;
  }

  // ---------------------------------------------------------------------------
  // GET PRODUCT BY ID
  // ---------------------------------------------------------------------------

  Future<ProductModel?> getProductById(
      String id,
      ) async {
    final query = database.select(database.products)
      ..where(
            (table) =>
        table.id.equals(id) &
        table.deletedAt.isNull(),
      );

    final row = await query.getSingleOrNull();

    if (row == null) {
      return null;
    }

    return _mapRowToModelWithVariants(row);
  }

  // ---------------------------------------------------------------------------
  // GET PRODUCT BY BARCODE
  // ---------------------------------------------------------------------------

  Future<ProductModel?> getProductByBarcode(
      String barcode,
      ) async {
    final normalized = barcode.trim();

    if (normalized.isEmpty) {
      return null;
    }

    // أولاً نبحث بباركود المنتج الرئيسي.
    final productQuery = database.select(database.products)
      ..where(
            (table) =>
        table.barcode.equals(normalized) &
        table.deletedAt.isNull(),
      );

    final productRow = await productQuery.getSingleOrNull();

    if (productRow != null) {
      return _mapRowToModelWithVariants(productRow);
    }

    // إذا المنتج يحتوي Variants،
    // نبحث بباركود الـ Variant.
    final variantQuery = database.select(database.productVariants)
      ..where(
            (table) =>
        table.barcode.equals(normalized) &
        table.deletedAt.isNull() &
        table.isActive.equals(true),
      );

    final variantRow = await variantQuery.getSingleOrNull();

    if (variantRow == null) {
      return null;
    }

    return getProductById(
      variantRow.productId,
    );
  }

  // ---------------------------------------------------------------------------
  // GET VARIANT BY BARCODE
  // ---------------------------------------------------------------------------

  Future<ProductVariantModel?> getVariantByBarcode(
      String barcode,
      ) async {
    final normalized = barcode.trim();

    if (normalized.isEmpty) {
      return null;
    }

    final query = database.select(database.productVariants)
      ..where(
            (table) =>
        table.barcode.equals(normalized) &
        table.deletedAt.isNull() &
        table.isActive.equals(true),
      );

    final row = await query.getSingleOrNull();

    if (row == null) {
      return null;
    }

    return _mapVariantRowToModel(row);
  }

  // ---------------------------------------------------------------------------
  // GET PRODUCT VARIANTS
  // ---------------------------------------------------------------------------

  Future<List<ProductVariantModel>> getProductVariants(
      String productId,
      ) async {
    final query = database.select(database.productVariants)
      ..where(
            (table) =>
        table.productId.equals(productId) &
        table.deletedAt.isNull(),
      )
      ..orderBy([
            (table) => OrderingTerm.asc(
          table.createdAt,
        ),
      ]);

    final rows = await query.get();

    return rows
        .map(
      _mapVariantRowToModel,
    )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // LEGACY BACKFILL
  // ---------------------------------------------------------------------------

  Future<int> backfillLegacyProductReferences() async {
    final products = await database
        .select(
      database.products,
    )
        .get();

    final categories = await database
        .select(
      database.categories,
    )
        .get();

    final units = await database
        .select(
      database.units,
    )
        .get();

    if (products.isEmpty) {
      return 0;
    }

    if (categories.isEmpty || units.isEmpty) {
      return 0;
    }

    var updatedCount = 0;

    for (final product in products) {
      if (product.deletedAt != null) {
        continue;
      }

      String? resolvedCategoryId = product.categoryId;
      String? resolvedBaseUnitId = product.baseUnitId;

      final hasCategoryId =
          resolvedCategoryId != null &&
              resolvedCategoryId.trim().isNotEmpty;

      final hasBaseUnitId =
          resolvedBaseUnitId != null &&
              resolvedBaseUnitId.trim().isNotEmpty;

      if (hasCategoryId && hasBaseUnitId) {
        continue;
      }

      // -----------------------------------------------------------------------
      // CATEGORY
      // -----------------------------------------------------------------------

      if (!hasCategoryId) {
        final categoryName =
        (product.categoryName ?? '')
            .trim()
            .toLowerCase();

        if (categoryName.isNotEmpty) {
          // Exact match.
          for (final category in categories) {
            final apiCategoryName =
            category.nameAr.trim().toLowerCase();

            if (apiCategoryName == categoryName) {
              resolvedCategoryId = category.id;
              break;
            }
          }

          // Partial match.
          if (resolvedCategoryId == null ||
              resolvedCategoryId.trim().isEmpty) {
            for (final category in categories) {
              final apiCategoryName =
              category.nameAr.trim().toLowerCase();

              if (apiCategoryName.contains(categoryName) ||
                  categoryName.contains(apiCategoryName)) {
                resolvedCategoryId = category.id;
                break;
              }
            }
          }
        }

        // إذا يوجد تصنيف واحد فقط، نستخدمه للمنتجات القديمة.
        if ((resolvedCategoryId == null ||
            resolvedCategoryId.trim().isEmpty) &&
            categories.length == 1) {
          resolvedCategoryId = categories.first.id;
        }
      }

      // -----------------------------------------------------------------------
      // UNIT
      // -----------------------------------------------------------------------

      if (!hasBaseUnitId) {
        final unitName =
        product.unit.trim().toLowerCase();

        if (unitName.isNotEmpty) {
          for (final unit in units) {
            final apiUnitName =
            unit.nameAr.trim().toLowerCase();

            if (apiUnitName == unitName) {
              resolvedBaseUnitId = unit.id;
              break;
            }
          }
        }

        if (resolvedBaseUnitId == null ||
            resolvedBaseUnitId.trim().isEmpty) {
          for (final unit in units) {
            if (unit.nameAr.trim() == 'قطعة') {
              resolvedBaseUnitId = unit.id;
              break;
            }
          }
        }
      }

      final categoryChanged =
          !hasCategoryId &&
              resolvedCategoryId != null &&
              resolvedCategoryId.trim().isNotEmpty;

      final unitChanged =
          !hasBaseUnitId &&
              resolvedBaseUnitId != null &&
              resolvedBaseUnitId.trim().isNotEmpty;

      if (!categoryChanged && !unitChanged) {
        continue;
      }

      await (database.update(database.products)
        ..where(
              (table) => table.id.equals(product.id),
        ))
          .write(
        ProductsCompanion(
          categoryId: categoryChanged
              ? Value(resolvedCategoryId)
              : const Value.absent(),
          baseUnitId: unitChanged
              ? Value(resolvedBaseUnitId)
              : const Value.absent(),
          updatedAt: Value(
            DateTime.now(),
          ),
        ),
      );

      updatedCount++;
    }

    return updatedCount;
  }

  // ---------------------------------------------------------------------------
  // CREATE PRODUCT
  // ---------------------------------------------------------------------------

  Future<ProductModel> createProduct({
    String? barcode,
    String? sku,
    required String name,
    String? nameEn,
    String? categoryId,
    String? categoryName,
    String? baseUnitId,
    required String unit,
    String? description,
    bool hasVariants = false,
    bool hasExpiry = false,
    bool hasSerial = false,
    String? imageUrl,
    required double costPrice,
    required double representativePrice,
    required double wholesalePrice,
    required double retailPrice,
    required double minimumStock,
    List<ProductVariantModel> variants = const [],
  }) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError(
        'اسم المنتج مطلوب.',
      );
    }

    final cleanBarcode = _cleanOptionalText(
      barcode,
    );

    final cleanSku = _cleanOptionalText(
      sku,
    );

    final cleanCategoryId = _cleanOptionalText(
      categoryId,
    );

    final cleanCategoryName = _cleanOptionalText(
      categoryName,
    );

    final cleanBaseUnitId = _cleanOptionalText(
      baseUnitId,
    );

    if (cleanCategoryId == null) {
      throw ArgumentError(
        'التصنيف مطلوب.',
      );
    }

    if (cleanBaseUnitId == null) {
      throw ArgumentError(
        'وحدة القياس مطلوبة.',
      );
    }

    if (hasVariants && variants.isEmpty) {
      throw ArgumentError(
        'يجب إضافة خيار واحد على الأقل للمنتج.',
      );
    }

    await _validateUniqueIdentifiers(
      barcode: cleanBarcode,
      sku: cleanSku,
    );

    await _validateVariants(
      variants: variants,
      productBarcode: cleanBarcode,
      productSku: cleanSku,
    );

    final now = DateTime.now();
    final productId = _uuid.v4();

    final normalizedVariants = hasVariants
        ? variants.map(
          (variant) {
        return ProductVariantModel(
          id: variant.id.trim().isEmpty
              ? _uuid.v4()
              : variant.id,
          serverId: variant.serverId,
          productId: productId,
          barcode:
          _cleanOptionalText(variant.barcode) ?? '',
          sku: _cleanOptionalText(variant.sku),
          attributes:
          Map<String, String>.from(
            variant.attributes,
          ),
          costPrice: variant.costPrice,
          representativePrice:
          variant.representativePrice,
          wholesalePrice:
          variant.wholesalePrice,
          retailPrice:
          variant.retailPrice,
          weightedAverageCost:
          variant.weightedAverageCost,
          lastPurchasePrice:
          variant.lastPurchasePrice,
          isActive: variant.isActive,
          serverVersion:
          variant.serverVersion,
          createdAt:
          variant.createdAt ?? now,
          updatedAt:
          now,
          deletedAt:
          variant.deletedAt,
        );
      },
    ).toList()
        : <ProductVariantModel>[];

    final product = ProductModel(
      id: productId,
      serverId: null,
      barcode: cleanBarcode ?? '',
      sku: cleanSku,
      name: cleanName,
      nameEn: nameEn?.trim() ?? '',
      categoryId: cleanCategoryId,
      categoryName: cleanCategoryName ?? '',
      baseUnitId: cleanBaseUnitId,
      warehouse: '',
      quantity: 0,
      unit: unit.trim().isEmpty
          ? 'قطعة'
          : unit.trim(),
      description:
      description?.trim() ?? '',
      hasVariants: hasVariants,
      hasExpiry: hasExpiry,
      hasSerial: hasSerial,
      imageUrl: _cleanOptionalText(imageUrl),
      costPrice: costPrice,
      representativePrice:
      representativePrice,
      wholesalePrice: wholesalePrice,
      retailPrice: retailPrice,
      minimumStock: minimumStock,
      isActive: true,
      serverVersion: 0,
      variants: normalizedVariants,
      createdAt: now,
      updatedAt: now,
    );

    await database.transaction(
          () async {
        // Product
        await database
            .into(database.products)
            .insert(
          _modelToCompanion(product),
        );

        // Variants
        for (final variant in normalizedVariants) {
          await database
              .into(database.productVariants)
              .insert(
            _variantModelToCompanion(
              variant,
            ),
          );
        }

        // Outbox
        await syncQueue.enqueue(
          entityType: 'product',
          entityId: product.id,
          operation: SyncOperation.create,
          payload: product.toSyncJson(),
        );
      },
    );

    return product;
  }

  // ---------------------------------------------------------------------------
  // UPDATE PRODUCT
  // ---------------------------------------------------------------------------

  Future<ProductModel> updateProduct({
    required ProductModel product,
  }) async {
    final cleanName = product.name.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError(
        'اسم المنتج مطلوب.',
      );
    }

    final cleanBarcode =
    _cleanOptionalText(product.barcode);

    final cleanSku =
    _cleanOptionalText(product.sku);

    final cleanCategoryId =
    _cleanOptionalText(product.categoryId);

    final cleanBaseUnitId =
    _cleanOptionalText(product.baseUnitId);

    if (cleanCategoryId == null) {
      throw ArgumentError(
        'التصنيف مطلوب.',
      );
    }

    if (cleanBaseUnitId == null) {
      throw ArgumentError(
        'وحدة القياس مطلوبة.',
      );
    }

    if (product.hasVariants &&
        product.variants.isEmpty) {
      throw ArgumentError(
        'يجب إضافة خيار واحد على الأقل للمنتج.',
      );
    }

    await _validateUniqueIdentifiers(
      barcode: cleanBarcode,
      sku: cleanSku,
      excludingProductId: product.id,
    );

    await _validateVariants(
      variants: product.variants,
      productBarcode: cleanBarcode,
      productSku: cleanSku,
      excludingProductId: product.id,
    );

    final now = DateTime.now();

    final normalizedVariants =
    product.hasVariants
        ? product.variants.map(
          (variant) {
        return variant.copyWith(
          productId: product.id,
          updatedAt: now,
          createdAt:
          variant.createdAt ?? now,
        );
      },
    ).toList()
        : <ProductVariantModel>[];

    final updated = product.copyWith(
      barcode: cleanBarcode ?? '',
      sku: cleanSku,
      name: cleanName,
      nameEn: product.nameEn.trim(),
      categoryId: cleanCategoryId,
      baseUnitId: cleanBaseUnitId,
      unit: product.unit.trim().isEmpty
          ? 'قطعة'
          : product.unit.trim(),
      description:
      product.description.trim(),
      imageUrl:
      _cleanOptionalText(product.imageUrl),
      hasVariants:
      product.hasVariants,
      variants:
      normalizedVariants,
      updatedAt: now,
      createdAt:
      product.createdAt ?? now,
    );

    await database.transaction(
          () async {
        // ---------------------------------------------------------------------
        // UPDATE MAIN PRODUCT
        // ---------------------------------------------------------------------

        await (database.update(database.products)
          ..where(
                (table) =>
                table.id.equals(updated.id),
          ))
            .write(
          _modelToCompanion(updated),
        );

        // ---------------------------------------------------------------------
        // UPDATE VARIANTS
        // ---------------------------------------------------------------------

        final existingVariantRows =
        await (database.select(
          database.productVariants,
        )
          ..where(
                (table) =>
            table.productId.equals(
              updated.id,
            ) &
            table.deletedAt.isNull(),
          ))
            .get();

        final incomingVariantIds =
        normalizedVariants
            .map(
              (variant) => variant.id,
        )
            .toSet();

        // Variants التي حُذفت من الواجهة.
        for (final existingRow
        in existingVariantRows) {
          if (!incomingVariantIds.contains(
            existingRow.id,
          )) {
            await (database.update(
              database.productVariants,
            )
              ..where(
                    (table) =>
                    table.id.equals(
                      existingRow.id,
                    ),
              ))
                .write(
              ProductVariantsCompanion(
                isActive:
                const Value(false),
                deletedAt:
                Value(now),
                updatedAt:
                Value(now),
              ),
            );
          }
        }

        // Insert / Update variants الحالية.
        for (final variant
        in normalizedVariants) {
          final existing =
          await (database.select(
            database.productVariants,
          )
            ..where(
                  (table) =>
                  table.id.equals(
                    variant.id,
                  ),
            ))
              .getSingleOrNull();

          if (existing == null) {
            final newVariant =
            variant.copyWith(
              productId: updated.id,
              createdAt:
              variant.createdAt ?? now,
              updatedAt: now,
            );

            await database
                .into(
              database.productVariants,
            )
                .insert(
              _variantModelToCompanion(
                newVariant,
              ),
            );
          } else {
            final updatedVariant =
            variant.copyWith(
              productId: updated.id,
              createdAt:
              existing.createdAt,
              updatedAt: now,
              deletedAt: null,
            );

            await (database.update(
              database.productVariants,
            )
              ..where(
                    (table) =>
                    table.id.equals(
                      variant.id,
                    ),
              ))
                .write(
              _variantModelToCompanion(
                updatedVariant,
              ),
            );
          }
        }

        // ---------------------------------------------------------------------
        // OUTBOX
        // ---------------------------------------------------------------------

        await syncQueue.enqueue(
          entityType: 'product',
          entityId: updated.id,
          operation: SyncOperation.update,
          payload: updated.toSyncJson(),
        );
      },
    );

    return updated;
  }

  // ---------------------------------------------------------------------------
  // SET PRODUCT ACTIVE
  // ---------------------------------------------------------------------------

  Future<void> setProductActive({
    required ProductModel product,
    required bool isActive,
  }) async {
    final now = DateTime.now();

    await database.transaction(
          () async {
        await (database.update(database.products)
          ..where(
                (table) =>
                table.id.equals(product.id),
          ))
            .write(
          ProductsCompanion(
            isActive: Value(isActive),
            updatedAt: Value(now),
          ),
        );

        await syncQueue.enqueue(
          entityType: 'product',
          entityId: product.id,
          operation: SyncOperation.update,
          payload: {
            'sync_action': 'toggle_active',
            'local_id': product.id,
            'server_id': product.serverId,
            'is_active': isActive,
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // DELETE PRODUCT
  // ---------------------------------------------------------------------------

  Future<void> deleteProduct(
      ProductModel product,
      ) async {
    final now = DateTime.now();

    await database.transaction(
          () async {
        await (database.update(database.products)
          ..where(
                (table) =>
                table.id.equals(product.id),
          ))
            .write(
          ProductsCompanion(
            isActive:
            const Value(false),
            updatedAt:
            Value(now),
            deletedAt:
            Value(now),
          ),
        );

        // Soft-delete جميع Variants التابعة للمنتج.
        await (database.update(
          database.productVariants,
        )
          ..where(
                (table) =>
            table.productId.equals(
              product.id,
            ) &
            table.deletedAt.isNull(),
          ))
            .write(
          ProductVariantsCompanion(
            isActive:
            const Value(false),
            updatedAt:
            Value(now),
            deletedAt:
            Value(now),
          ),
        );

        await syncQueue.enqueue(
          entityType: 'product',
          entityId: product.id,
          operation: SyncOperation.delete,
          payload: {
            'sync_action':
            'delete_product',
            'local_id':
            product.id,
            'server_id':
            product.serverId,
            'was_active':
            product.isActive,
            'deleted_at':
            now
                .toUtc()
                .toIso8601String(),
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // VALIDATE PRODUCT IDENTIFIERS
  // ---------------------------------------------------------------------------

  Future<void> _validateUniqueIdentifiers({
    String? barcode,
    String? sku,
    String? excludingProductId,
  }) async {
    // -------------------------------------------------------------------------
    // PRODUCT BARCODE
    // -------------------------------------------------------------------------

    if (barcode != null) {
      final query =
      database.select(database.products)
        ..where(
              (table) {
            Expression<bool> condition =
            table.barcode.equals(
              barcode,
            ) &
            table.deletedAt.isNull();

            if (excludingProductId != null) {
              condition =
              condition &
              table.id
                  .equals(
                excludingProductId,
              )
                  .not();
            }

            return condition;
          },
        );

      final existing =
      await query.getSingleOrNull();

      if (existing != null) {
        throw StateError(
          'الباركود مستخدم لمنتج آخر.',
        );
      }

      // يجب أيضاً ألا يكون الباركود مستخدماً داخل Variant.
      final variantQuery =
      database.select(
        database.productVariants,
      )
        ..where(
              (table) =>
          table.barcode.equals(barcode) &
          table.deletedAt.isNull(),
        );

      final existingVariant =
      await variantQuery.get();

      for (final variant in existingVariant) {
        if (excludingProductId == null ||
            variant.productId !=
                excludingProductId) {
          throw StateError(
            'الباركود مستخدم في خيار لمنتج آخر.',
          );
        }
      }
    }

    // -------------------------------------------------------------------------
    // PRODUCT SKU
    // -------------------------------------------------------------------------

    if (sku != null) {
      final query =
      database.select(database.products)
        ..where(
              (table) {
            Expression<bool> condition =
            table.sku.equals(sku) &
            table.deletedAt.isNull();

            if (excludingProductId != null) {
              condition =
              condition &
              table.id
                  .equals(
                excludingProductId,
              )
                  .not();
            }

            return condition;
          },
        );

      final existing =
      await query.getSingleOrNull();

      if (existing != null) {
        throw StateError(
          'رمز المنتج مستخدم مسبقاً.',
        );
      }

      final variantQuery =
      database.select(
        database.productVariants,
      )
        ..where(
              (table) =>
          table.sku.equals(sku) &
          table.deletedAt.isNull(),
        );

      final existingVariants =
      await variantQuery.get();

      for (final variant in existingVariants) {
        if (excludingProductId == null ||
            variant.productId !=
                excludingProductId) {
          throw StateError(
            'SKU مستخدم في خيار لمنتج آخر.',
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // VALIDATE VARIANTS
  // ---------------------------------------------------------------------------

  Future<void> _validateVariants({
    required List<ProductVariantModel> variants,
    String? productBarcode,
    String? productSku,
    String? excludingProductId,
  }) async {
    final barcodes = <String>{};
    final skus = <String>{};

    for (final variant in variants) {
      if (variant.deletedAt != null) {
        continue;
      }

      if (variant.attributes.isEmpty) {
        throw ArgumentError(
          'يجب تحديد صفة واحدة على الأقل لكل خيار.',
        );
      }

      final hasValidAttribute =
      variant.attributes.entries.any(
            (entry) =>
        entry.key.trim().isNotEmpty &&
            entry.value.trim().isNotEmpty,
      );

      if (!hasValidAttribute) {
        throw ArgumentError(
          'بيانات أحد الخيارات غير مكتملة.',
        );
      }

      if (variant.costPrice < 0 ||
          variant.representativePrice < 0 ||
          variant.wholesalePrice < 0 ||
          variant.retailPrice < 0) {
        throw ArgumentError(
          'أسعار الخيارات لا يمكن أن تكون سالبة.',
        );
      }

      final barcode =
      _cleanOptionalText(
        variant.barcode,
      );

      final sku =
      _cleanOptionalText(
        variant.sku,
      );

      // -----------------------------------------------------------------------
      // LOCAL DUPLICATE BARCODE
      // -----------------------------------------------------------------------

      if (barcode != null) {
        if (barcode == productBarcode) {
          throw StateError(
            'باركود الخيار لا يمكن أن يكون نفس باركود المنتج الرئيسي.',
          );
        }

        if (!barcodes.add(barcode)) {
          throw StateError(
            'يوجد باركود مكرر بين خيارات المنتج.',
          );
        }

        // Check other main products.
        final productQuery =
        database.select(
          database.products,
        )
          ..where(
                (table) =>
            table.barcode.equals(barcode) &
            table.deletedAt.isNull(),
          );

        final matchedProducts =
        await productQuery.get();

        for (final product in matchedProducts) {
          if (excludingProductId == null ||
              product.id != excludingProductId) {
            throw StateError(
              'باركود الخيار مستخدم لمنتج آخر.',
            );
          }
        }

        // Check other variants.
        final variantQuery =
        database.select(
          database.productVariants,
        )
          ..where(
                (table) =>
            table.barcode.equals(barcode) &
            table.deletedAt.isNull(),
          );

        final matchedVariants =
        await variantQuery.get();

        for (final existing
        in matchedVariants) {
          if (excludingProductId == null ||
              existing.productId !=
                  excludingProductId) {
            throw StateError(
              'باركود الخيار مستخدم مسبقاً.',
            );
          }
        }
      }

      // -----------------------------------------------------------------------
      // LOCAL DUPLICATE SKU
      // -----------------------------------------------------------------------

      if (sku != null) {
        if (sku == productSku) {
          throw StateError(
            'SKU الخيار لا يمكن أن يكون نفس SKU المنتج الرئيسي.',
          );
        }

        if (!skus.add(sku)) {
          throw StateError(
            'يوجد SKU مكرر بين خيارات المنتج.',
          );
        }

        final productQuery =
        database.select(
          database.products,
        )
          ..where(
                (table) =>
            table.sku.equals(sku) &
            table.deletedAt.isNull(),
          );

        final matchedProducts =
        await productQuery.get();

        for (final product in matchedProducts) {
          if (excludingProductId == null ||
              product.id != excludingProductId) {
            throw StateError(
              'SKU الخيار مستخدم لمنتج آخر.',
            );
          }
        }

        final variantQuery =
        database.select(
          database.productVariants,
        )
          ..where(
                (table) =>
            table.sku.equals(sku) &
            table.deletedAt.isNull(),
          );

        final matchedVariants =
        await variantQuery.get();

        for (final existing
        in matchedVariants) {
          if (excludingProductId == null ||
              existing.productId !=
                  excludingProductId) {
            throw StateError(
              'SKU الخيار مستخدم مسبقاً.',
            );
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PRODUCT ROW -> MODEL WITH VARIANTS
  // ---------------------------------------------------------------------------

  Future<ProductModel> _mapRowToModelWithVariants(
      Product row,
      ) async {
    final variants =
    await getProductVariants(
      row.id,
    );

    return ProductModel(
      id: row.id,
      serverId: row.serverId,
      barcode: row.barcode ?? '',
      sku: row.sku,
      name: row.name,
      nameEn: row.nameEn ?? '',
      categoryId: row.categoryId,
      categoryName:
      row.categoryName ?? '',
      baseUnitId: row.baseUnitId,
      warehouse: '',
      quantity: 0,
      unit: row.unit,
      description:
      row.description ?? '',
      hasVariants:
      row.hasVariants,
      hasExpiry:
      row.hasExpiry,
      hasSerial:
      row.hasSerial,
      imageUrl:
      row.imageUrl,
      costPrice:
      row.costPrice,
      representativePrice:
      row.representativePrice,
      wholesalePrice:
      row.wholesalePrice,
      retailPrice:
      row.retailPrice,
      minimumStock:
      row.minimumStock,
      piecesPerCarton:
      row.piecesPerCarton <= 0
          ? 1
          : row.piecesPerCarton,
      isActive:
      row.isActive,
      serverVersion:
      row.serverVersion,
      variants:
      variants,
      createdAt:
      row.createdAt,
      updatedAt:
      row.updatedAt,
      deletedAt:
      row.deletedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // VARIANT ROW -> MODEL
  // ---------------------------------------------------------------------------

  ProductVariantModel _mapVariantRowToModel(
      ProductVariant row,
      ) {
    return ProductVariantModel(
      id:
      row.id,
      serverId:
      row.serverId,
      productId:
      row.productId,
      barcode:
      row.barcode ?? '',
      sku:
      row.sku,
      attributes:
      _decodeAttributes(
        row.attributesJson,
      ),
      costPrice:
      row.costPrice,
      representativePrice:
      row.representativePrice,
      wholesalePrice:
      row.wholesalePrice,
      retailPrice:
      row.retailPrice,
      weightedAverageCost:
      row.weightedAverageCost,
      lastPurchasePrice:
      row.lastPurchasePrice,
      isActive:
      row.isActive,
      serverVersion:
      row.serverVersion,
      createdAt:
      row.createdAt,
      updatedAt:
      row.updatedAt,
      deletedAt:
      row.deletedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // PRODUCT MODEL -> COMPANION
  // ---------------------------------------------------------------------------

  ProductsCompanion _modelToCompanion(
      ProductModel product,
      ) {
    return ProductsCompanion(
      id:
      Value(product.id),
      serverId:
      Value(product.serverId),
      barcode:
      Value(
        product.barcode.trim().isEmpty
            ? null
            : product.barcode.trim(),
      ),
      sku:
      Value(product.sku),
      name:
      Value(product.name),
      nameEn:
      Value(
        product.nameEn.trim().isEmpty
            ? null
            : product.nameEn.trim(),
      ),
      categoryId:
      Value(product.categoryId),
      categoryName:
      Value(
        product.categoryName.trim().isEmpty
            ? null
            : product.categoryName,
      ),
      baseUnitId:
      Value(product.baseUnitId),
      unit:
      Value(product.unit),
      description:
      Value(
        product.description.trim().isEmpty
            ? null
            : product.description,
      ),
      hasVariants:
      Value(product.hasVariants),
      hasExpiry:
      Value(product.hasExpiry),
      hasSerial:
      Value(product.hasSerial),
      imageUrl:
      Value(product.imageUrl),
      costPrice:
      Value(product.costPrice),
      representativePrice:
      Value(
        product.representativePrice,
      ),
      wholesalePrice:
      Value(product.wholesalePrice),
      retailPrice:
      Value(product.retailPrice),
      minimumStock:
      Value(product.minimumStock),
      isActive:
      Value(product.isActive),
      serverVersion:
      Value(product.serverVersion),
      createdAt:
      Value(
        product.createdAt ??
            DateTime.now(),
      ),
      updatedAt:
      Value(
        product.updatedAt ??
            DateTime.now(),
      ),
      deletedAt:
      Value(product.deletedAt),
    );
  }

  // ---------------------------------------------------------------------------
  // VARIANT MODEL -> COMPANION
  // ---------------------------------------------------------------------------

  ProductVariantsCompanion _variantModelToCompanion(
      ProductVariantModel variant,
      ) {
    return ProductVariantsCompanion(
      id:
      Value(variant.id),
      serverId:
      Value(variant.serverId),
      productId:
      Value(variant.productId),
      barcode:
      Value(
        variant.barcode.trim().isEmpty
            ? null
            : variant.barcode.trim(),
      ),
      sku:
      Value(
        _cleanOptionalText(
          variant.sku,
        ),
      ),
      attributesJson:
      Value(
        jsonEncode(
          variant.attributes,
        ),
      ),
      costPrice:
      Value(variant.costPrice),
      representativePrice:
      Value(
        variant.representativePrice,
      ),
      wholesalePrice:
      Value(variant.wholesalePrice),
      retailPrice:
      Value(variant.retailPrice),
      weightedAverageCost:
      Value(
        variant.weightedAverageCost,
      ),
      lastPurchasePrice:
      Value(
        variant.lastPurchasePrice,
      ),
      isActive:
      Value(variant.isActive),
      serverVersion:
      Value(variant.serverVersion),
      createdAt:
      Value(
        variant.createdAt ??
            DateTime.now(),
      ),
      updatedAt:
      Value(
        variant.updatedAt ??
            DateTime.now(),
      ),
      deletedAt:
      Value(variant.deletedAt),
    );
  }

  // ---------------------------------------------------------------------------
  // ATTRIBUTES JSON
  // ---------------------------------------------------------------------------

  Map<String, String> _decodeAttributes(
      String json,
      ) {
    if (json.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(json);

      if (decoded is! Map) {
        return {};
      }

      final result = <String, String>{};

      for (final entry in decoded.entries) {
        final key =
        entry.key.toString().trim();

        final value =
            entry.value?.toString().trim() ?? '';

        if (key.isEmpty || value.isEmpty) {
          continue;
        }

        result[key] = value;
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // CLEAN TEXT
  // ---------------------------------------------------------------------------

  String? _cleanOptionalText(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final cleaned = value.trim();

    if (cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  /// يحفظ عدد قطع الكارتون، ويضيف مخزون الفتح كقطع = كارتون × القطع.
  Future<void> rememberCarton({
    required String productId,
    required double piecesPerCarton,
    required int cartons,
  }) async {
    final factor = piecesPerCarton < 1 ? 1.0 : piecesPerCarton;
    final now = DateTime.now();

    await (database.update(database.products)
          ..where((table) => table.id.equals(productId)))
        .write(
      ProductsCompanion(
        piecesPerCarton: Value(factor),
        updatedAt: Value(now),
      ),
    );

    if (cartons <= 0) {
      return;
    }

    final product = await (database.select(database.products)
          ..where((table) => table.id.equals(productId)))
        .getSingleOrNull();
    if (product == null) {
      return;
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
      variantId = _uuid.v4();
      await database.into(database.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: variantId,
              productId: productId,
              barcode: Value(product.barcode),
              costPrice: Value(product.costPrice),
              representativePrice: Value(product.representativePrice),
              wholesalePrice: Value(product.wholesalePrice),
              retailPrice: Value(product.retailPrice),
              createdAt: now,
              updatedAt: now,
            ),
          );
    } else {
      variantId = variants.first.id;
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
    final addedPieces = cartons * factor;
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
              quantity: Value(addedPieces),
              updatedAt: now,
            ),
          );
      return;
    }

    await (database.update(database.stockBalances)
          ..where((table) => table.id.equals(balances.first.id)))
        .write(
      StockBalancesCompanion(
        quantity: Value(balances.first.quantity + addedPieces),
        updatedAt: Value(now),
      ),
    );
  }
}