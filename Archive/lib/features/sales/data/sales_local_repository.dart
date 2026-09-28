import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/money/party_balance.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../../inventory/models/stock_movement_model.dart';
import '../models/cart_item_model.dart';
import '../models/held_sale_model.dart';
import '../../products/data/unit_quantity.dart';
import '../models/sale_model.dart';

class SalesLocalRepository {
  final AppDatabase database;
  final SyncQueueRepository syncQueue;

  static const Uuid _uuid = Uuid();

  SalesLocalRepository({
    required this.database,
    required this.syncQueue,
  });

  // ===========================================================================
  // CREATE SALE
  // ===========================================================================

  Future<SaleModel> createSale({
    required String warehouseId,
    required String warehouseName,
    String? customerId,
    required String customerName,
    String? representativeId,
    required List<CartItemModel> items,
    required double subtotal,
    required double discount,
    double porterage = 0,
    required double total,
    required double paidAmount,
    required double remainingAmount,
    required PaymentType paymentType,
    String currency = 'IQD',
    double exchangeRate = 0,
    double totalUsd = 0,
    String notes = '',
    String? userId,
  }) async {
    if (items.isEmpty) {
      throw StateError(
        'لا يمكن إنشاء فاتورة بدون منتجات.',
      );
    }

    if (warehouseId.trim().isEmpty) {
      throw StateError(
        'يجب اختيار المخزن.',
      );
    }

    if (subtotal <= 0) {
      throw StateError(
        'مجموع الفاتورة غير صحيح.',
      );
    }

    if (discount < 0 ||
        discount > subtotal) {
      throw StateError(
        'قيمة الخصم غير صحيحة.',
      );
    }

    if (total <= 0) {
      throw StateError(
        'إجمالي الفاتورة غير صحيح.',
      );
    }

    if (paidAmount < 0 ||
        paidAmount > total) {
      throw StateError(
        'المبلغ المدفوع غير صحيح.',
      );
    }

    if (remainingAmount < 0) {
      throw StateError(
        'المبلغ المتبقي غير صحيح.',
      );
    }

    final cleanCustomerId =
    _clean(
      customerId,
    );

    final cleanRepresentativeId =
    _clean(
      representativeId,
    );

    final cleanUserId =
    _clean(
      userId,
    );

    if (paymentType != PaymentType.cash &&
        cleanCustomerId == null) {
      throw StateError(
        'يجب اختيار زبون مسجل للبيع الآجل أو الجزئي.',
      );
    }

    if (paymentType == PaymentType.cash &&
        paidAmount != total) {
      throw StateError(
        'البيع النقدي يجب أن يكون مسدداً بالكامل.',
      );
    }

    if (paymentType == PaymentType.credit &&
        paidAmount != 0) {
      throw StateError(
        'البيع الآجل يجب أن يكون المبلغ المدفوع فيه صفراً.',
      );
    }

    if (paymentType == PaymentType.partial) {
      if (paidAmount <= 0 ||
          paidAmount >= total) {
        throw StateError(
          'في البيع الجزئي يجب أن يكون المبلغ المدفوع أكبر من صفر وأقل من الإجمالي.',
        );
      }
    }

    final now =
    DateTime.now();

    final saleId =
    _uuid.v4();

    final invoiceNumber =
    _invoiceNumber(
      saleId,
      now,
    );

    String? representativeName;
    double? commissionPercentage;
    double commissionAmount = 0.0;

    final resolvedItems =
    <_ResolvedSaleItem>[];

    await database.transaction(
          () async {
        // =====================================================================
        // WAREHOUSE
        // =====================================================================

        final warehouse =
        await (database.select(
          database.warehouses,
        )
          ..where(
                (table) =>
                table.id.equals(
                  warehouseId,
                ),
          ))
            .getSingleOrNull();

        if (warehouse == null ||
            warehouse.deletedAt != null) {
          throw StateError(
            'المخزن غير موجود.',
          );
        }

        if (!warehouse.isActive) {
          throw StateError(
            'المخزن المحدد غير فعال.',
          );
        }

        if (warehouse.status
            .trim()
            .toUpperCase() !=
            'ACTIVE') {
          throw StateError(
            'المخزن "${warehouse.name}" غير فعال في السيرفر.',
          );
        }

        // =====================================================================
        // CUSTOMER
        // =====================================================================

        if (cleanCustomerId != null) {
          final customer =
          await (database.select(
            database.customers,
          )
            ..where(
                  (table) =>
                  table.id.equals(
                    cleanCustomerId,
                  ),
            ))
              .getSingleOrNull();

          if (customer == null ||
              customer.deletedAt != null) {
            throw StateError(
              'الزبون المحدد غير موجود.',
            );
          }

          if (!customer.isActive) {
            throw StateError(
              'الزبون المحدد غير فعال.',
            );
          }
        }

        // =====================================================================
        // REPRESENTATIVE
        // =====================================================================

        if (cleanRepresentativeId != null) {
          final representative =
          await (database.select(
            database.representatives,
          )
            ..where(
                  (table) =>
                  table.id.equals(
                    cleanRepresentativeId,
                  ),
            ))
              .getSingleOrNull();

          if (representative == null ||
              representative.deletedAt != null) {
            throw StateError(
              'المندوب المحدد غير موجود.',
            );
          }

          if (!representative.isActive) {
            throw StateError(
              'المندوب المحدد غير فعال.',
            );
          }

          representativeName =
              representative.name;

          commissionPercentage =
              representative.commissionPercentage;

          commissionAmount =
              representative.commissionPercentage;
        }

        // =====================================================================
        // RESOLVE + VALIDATE ITEMS
        // =====================================================================

        for (final item in items) {
          final product =
          await (database.select(
            database.products,
          )
            ..where(
                  (table) =>
                  table.id.equals(
                    item.product.id,
                  ),
            ))
              .getSingleOrNull();

          if (product == null ||
              product.deletedAt != null) {
            throw StateError(
              'المنتج "${item.product.name}" غير موجود.',
            );
          }

          if (!product.isActive) {
            throw StateError(
              'المنتج "${item.product.name}" غير فعال.',
            );
          }

          if (item.quantity <= 0) {
            throw StateError(
              'كمية "${item.product.name}" غير صحيحة.',
            );
          }

          if (item.unitPrice < 0) {
            throw StateError(
              'سعر "${item.product.name}" غير صحيح.',
            );
          }

          if (item.discountPercent < 0 ||
              item.discountPercent > 100) {
            throw StateError(
              'خصم "${item.product.name}" يجب أن يكون بين 0 و100%.',
            );
          }

          final variant =
          await _resolveInventoryVariant(
            productId:
            product.id,
            productName:
            product.name,
            requestedVariantId:
            item.variantId,
          );

          final unitId =
          await _resolveUnitId(
            requestedUnitId:
            item.unitId,
            productBaseUnitId:
            product.baseUnitId,
            productName:
            product.name,
          );

          final balance =
          await _findStockBalance(
            variantId:
            variant.id,
            warehouseId:
            warehouseId,
          );

          final double currentStock =
              balance?.quantity ?? 0.0;

          if (item.billedPieces <= 0) {
            throw StateError(
              'اكتب عدد الكارتون أو عدد القطع لمادة "${product.name}".',
            );
          }

          if (currentStock <
              item.billedPieces) {
            throw StateError(
              'الكمية المتوفرة من "${item.product.name}" '
                  'هي ${_formatQuantity(currentStock)} فقط.',
            );
          }

          resolvedItems.add(
            _ResolvedSaleItem(
              cartItem:
              item,
              product:
              product,
              variant:
              variant,
              unitId:
              unitId,
            ),
          );
        }

        // =====================================================================
        // SALE HEADER
        // =====================================================================

        await database
            .into(
          database.sales,
        )
            .insert(
          SalesCompanion.insert(
            id:
            saleId,
            serverId:
            const Value.absent(),
            invoiceNumber:
            invoiceNumber,
            warehouseId:
            warehouseId,
            warehouseNameSnapshot:
            warehouseName,
            customerId:
            Value(
              cleanCustomerId,
            ),
            customerName:
            customerName,
            representativeId:
            Value(
              cleanRepresentativeId,
            ),
            representativeNameSnapshot:
            Value(
              representativeName,
            ),
            commissionPercentageSnapshot:
            Value(
              commissionPercentage,
            ),
            commissionAmount:
            Value(
              commissionAmount,
            ),
            subtotal:
            subtotal,
            discount:
            Value(
              discount,
            ),
            porterage: Value(porterage < 0 ? 0 : porterage),
            total:
            total,
            paidAmount:
            Value(
              paidAmount,
            ),
            remainingAmount:
            Value(
              remainingAmount,
            ),
            paymentType:
            _paymentTypeValue(
              paymentType,
            ),
            currency: Value(
              currency == 'USD' ? 'USD' : 'IQD',
            ),
            exchangeRate: Value(
              exchangeRate,
            ),
            totalUsd: Value(
              totalUsd < 0 ? 0 : totalUsd,
            ),
            notes: Value(
              notes.trim(),
            ),
            serverVersion:
            const Value(
              0,
            ),
            createdAt:
            now,
            updatedAt:
            now,
          ),
        );

        // =====================================================================
        // SALE ITEMS + LOCAL STOCK
        // =====================================================================

        for (final resolved in resolvedItems) {
          final item =
              resolved.cartItem;

          final product =
              resolved.product;

          final variant =
              resolved.variant;

          final saleItemId =
          _uuid.v4();

          final barcode =
              _clean(
                variant.barcode,
              ) ??
                  _clean(
                    item.product.barcode,
                  );

          await database
              .into(
            database.saleItems,
          )
              .insert(
            SaleItemsCompanion.insert(
              id:
              saleItemId,
              saleId:
              saleId,
              productId:
              product.id,
              variantId:
              Value(
                variant.id,
              ),
              unitId:
              Value(
                resolved.unitId,
              ),
              productNameSnapshot:
              product.name,
              barcodeSnapshot:
              Value(
                barcode,
              ),
              priceType:
              _priceTypeValue(
                item.priceType,
              ),
              quantity:
              item.quantity.toDouble(),
              unitFactor: Value(
                item.unitFactor <= 0 ? 1 : item.unitFactor,
              ),
              loosePieces: Value(
                item.loosePieces < 0 ? 0 : item.loosePieces,
              ),
              unitPrice:
              item.unitPrice,
              discountPercent:
              Value(
                item.discountPercent,
              ),
              total:
              item.total,
              createdAt:
              now,
            ),
          );

          final currentBalance =
          await _findStockBalance(
            variantId:
            variant.id,
            warehouseId:
            warehouseId,
          );

          final double currentStock =
              currentBalance?.quantity ?? 0.0;

          final stockQuantity = item.billedPieces;

          final double newStock =
              currentStock -
                  stockQuantity;

          if (newStock < 0.0) {
            throw StateError(
              'الكمية المتوفرة من "${product.name}" غير كافية.',
            );
          }

          if (currentBalance != null) {
            await (database.update(
              database.stockBalances,
            )
              ..where(
                    (table) =>
                    table.id.equals(
                      currentBalance.id,
                    ),
              ))
                .write(
              StockBalancesCompanion(
                quantity:
                Value(
                  newStock,
                ),
                updatedAt:
                Value(
                  now,
                ),
              ),
            );
          } else {
            await database
                .into(
              database.stockBalances,
            )
                .insert(
              StockBalancesCompanion.insert(
                id:
                _balanceId(
                  variant.id,
                  warehouseId,
                ),
                variantId:
                variant.id,
                warehouseId:
                warehouseId,
                quantity:
                Value(
                  newStock,
                ),
                updatedAt:
                now,
              ),
            );
          }

          final movement =
          StockMovementModel(
            id:
            _uuid.v4(),
            variantId:
            variant.id,
            warehouseId:
            warehouseId,
            type:
            StockMovementType.sale,
            quantity:
            stockQuantity,
            referenceType:
            'SALE',
            referenceId:
            saleId,
            userId:
            cleanUserId,
            serverVersion:
            0,
            createdAt:
            now,
          );

          await database
              .into(
            database.stockMovements,
          )
              .insert(
            StockMovementsCompanion.insert(
              id:
              movement.id,
              variantId:
              movement.variantId,
              warehouseId:
              movement.warehouseId,
              type:
              movement.type.databaseValue,
              quantity:
              movement.quantity,
              referenceType:
              Value(
                movement.referenceType,
              ),
              referenceId:
              Value(
                movement.referenceId,
              ),
              note:
              Value(
                movement.note,
              ),
              userId:
              Value(
                movement.userId,
              ),
              serverVersion:
              const Value(
                0,
              ),
              createdAt:
              movement.createdAt,
            ),
          );
        }

        // =====================================================================
        // LOCAL CUSTOMER LEDGER
        // =====================================================================

        if (cleanCustomerId != null) {
          final saleLedgerId =
          _uuid.v4();
          final saleLedger = nativeLedgerAmount(
            amount: total,
            currency: currency,
            exchangeRate: exchangeRate,
            amountIsIqd: true,
          );
          final paidLedger = nativeLedgerAmount(
            amount: paidAmount,
            currency: currency,
            exchangeRate: exchangeRate,
            amountIsIqd: true,
          );

          await database
              .into(
            database.customerLedgerEntries,
          )
              .insert(
            CustomerLedgerEntriesCompanion.insert(
              id:
              saleLedgerId,
              customerId:
              cleanCustomerId,
              type:
              'SALE',
              amount:
              saleLedger.amount,
              currency: Value(saleLedger.currency),
              referenceType:
              const Value(
                'SALE',
              ),
              referenceId:
              Value(
                saleId,
              ),
              userId:
              Value(
                cleanUserId,
              ),
              serverVersion:
              const Value(
                0,
              ),
              createdAt:
              now,
            ),
          );

          if (paidLedger.amount > 0) {
            final paymentId =
            _uuid.v4();

            final paymentLedgerId =
            _uuid.v4();

            final voucherNumber =
            _receiptNumber(
              paymentId,
              now,
            );

            await database
                .into(
              database.customerPayments,
            )
                .insert(
              CustomerPaymentsCompanion.insert(
                id:
                paymentId,
                voucherNumber:
                voucherNumber,
                customerId:
                cleanCustomerId,
                method:
                const Value(
                  'CASH',
                ),
                amount:
                paidLedger.amount,
                currency: Value(paidLedger.currency),
                referenceType:
                const Value(
                  'SALE',
                ),
                referenceId:
                Value(
                  saleId,
                ),
                userId:
                Value(
                  cleanUserId,
                ),
                serverVersion:
                const Value(
                  0,
                ),
                createdAt:
                now,
              ),
            );

            await database
                .into(
              database.customerLedgerEntries,
            )
                .insert(
              CustomerLedgerEntriesCompanion.insert(
                id:
                paymentLedgerId,
                customerId:
                cleanCustomerId,
                type:
                'RECEIPT',
                amount:
                paidLedger.amount,
                currency: Value(paidLedger.currency),
                referenceType:
                const Value(
                  'SALE_PAYMENT',
                ),
                referenceId:
                Value(
                  paymentId,
                ),
                userId:
                Value(
                  cleanUserId,
                ),
                serverVersion:
                const Value(
                  0,
                ),
                createdAt:
                now,
              ),
            );
          }
        }

        // =====================================================================
        // LOCAL REPRESENTATIVE COMMISSION
        // =====================================================================

        if (cleanRepresentativeId != null &&
            commissionAmount > 0 &&
            commissionPercentage != null) {
          final commissionEntryId =
          _uuid.v4();

          await database
              .into(
            database.representativeCommissionEntries,
          )
              .insert(
            RepresentativeCommissionEntriesCompanion.insert(
              id:
              commissionEntryId,
              representativeId:
              cleanRepresentativeId,
              type:
              'SALE_COMMISSION',
              amount:
              commissionAmount,
              commissionPercentage:
              commissionPercentage!,
              referenceType:
              const Value(
                'SALE',
              ),
              referenceId:
              Value(
                saleId,
              ),
              userId:
              Value(
                cleanUserId,
              ),
              serverVersion:
              const Value(
                0,
              ),
              createdAt:
              now,
            ),
          );
        }

        // =====================================================================
        // DIRECT SALE OUTBOX
        // =====================================================================

        await syncQueue.enqueue(
          entityType:
          'direct_sale',
          entityId:
          saleId,
          operation:
          SyncOperation.create,
          idempotencyKey:
          saleId,
          payload: {
            'local_sale_id':
            saleId,
            'invoice_number':
            invoiceNumber,
            'created_at':
            now
                .toUtc()
                .toIso8601String(),
          },
        );
      },
    );

    final normalizedCartItems =
    resolvedItems
        .map(
          (resolved) =>
          resolved.cartItem.copyWith(
            variantId:
            resolved.variant.id,
            unitId:
            resolved.unitId,
          ),
    )
        .toList();

    return SaleModel(
      id:
      saleId,
      serverId:
      null,
      invoiceNumber:
      invoiceNumber,
      customerId:
      cleanCustomerId,
      customerName:
      customerName,
      warehouseId:
      warehouseId,
      warehouseName:
      warehouseName,
      representativeId:
      cleanRepresentativeId,
      items:
      normalizedCartItems,
      subtotal:
      subtotal,
      discount:
      discount,
      porterage: porterage < 0 ? 0 : porterage,
      total:
      total,
      paidAmount:
      paidAmount,
      remainingAmount:
      remainingAmount,
      paymentType:
      paymentType,
      currency: currency == 'USD' ? 'USD' : 'IQD',
      exchangeRate: exchangeRate,
      totalUsd: totalUsd < 0 ? 0 : totalUsd,
      notes: notes.trim(),
      createdAt:
      now,
      updatedAt:
      now,
    );
  }

  // ===========================================================================
  // SALES HISTORY
  // ===========================================================================

  Future<List<Sale>> getSales() {
    final query =
    database.select(
      database.sales,
    )
      ..where(
            (table) =>
            table.deletedAt.isNull(),
      )
      ..orderBy([
            (table) =>
            OrderingTerm.desc(
              table.createdAt,
            ),
      ]);

    return query.get();
  }

  Future<ListPage<Sale>> pageSales({
    int offset = 0,
    int limit = kListPageSize,
    String search = '',
    DateTime? from,
    DateTime? to,
  }) async {
    final queryText = search.trim();
    final like = '%$queryText%';
    Expression<bool> filter($SalesTable table) {
      var expression = table.deletedAt.isNull();
      if (from != null) {
        expression = expression & table.createdAt.isBiggerOrEqualValue(from);
      }
      if (to != null) {
        expression = expression & table.createdAt.isSmallerThanValue(to);
      }
      if (queryText.isNotEmpty) {
        expression = expression &
            (table.invoiceNumber.like(like) | table.customerName.like(like));
      }
      return expression;
    }

    final items = await (database.select(database.sales)
          ..where(filter)
          ..orderBy([(table) => OrderingTerm.desc(table.createdAt)])
          ..limit(limit, offset: offset))
        .get();
    final totalRow = await (database.selectOnly(database.sales)
          ..addColumns([database.sales.id.count()])
          ..where(filter(database.sales)))
        .getSingle();
    return ListPage(
      items: items,
      total: totalRow.read(database.sales.id.count()) ?? 0,
    );
  }

  Stream<List<Sale>> watchSales() {
    final query =
    database.select(
      database.sales,
    )
      ..where(
            (table) =>
            table.deletedAt.isNull(),
      )
      ..orderBy([
            (table) =>
            OrderingTerm.desc(
              table.createdAt,
            ),
      ]);

    return query.watch();
  }

  Future<Sale?> getSaleById(
      String saleId,
      ) {
    final cleanSaleId =
    saleId.trim();

    if (cleanSaleId.isEmpty) {
      return Future.value(
        null,
      );
    }

    return (database.select(
      database.sales,
    )
      ..where(
            (table) =>
        table.id.equals(
          cleanSaleId,
        ) &
        table.deletedAt.isNull(),
      ))
        .getSingleOrNull();
  }

  Future<List<SaleItem>> getSaleItems(
      String saleId,
      ) {
    final cleanSaleId =
    saleId.trim();

    if (cleanSaleId.isEmpty) {
      return Future.value(
        const <SaleItem>[],
      );
    }

    final query =
    database.select(
      database.saleItems,
    )
      ..where(
            (table) =>
            table.saleId.equals(
              cleanSaleId,
            ),
      )
      ..orderBy([
            (table) =>
            OrderingTerm.asc(
              table.createdAt,
            ),
      ]);

    return query.get();
  }

  Stream<List<SaleItem>> watchSaleItems(
      String saleId,
      ) {
    final query =
    database.select(
      database.saleItems,
    )
      ..where(
            (table) =>
            table.saleId.equals(
              saleId.trim(),
            ),
      )
      ..orderBy([
            (table) =>
            OrderingTerm.asc(
              table.createdAt,
            ),
      ]);

    return query.watch();
  }

  // ===========================================================================
  // HELD SALES - LOCAL ONLY
  // ===========================================================================

  Future<String> holdSale({
    String? existingHeldSaleId,
    required String warehouseId,
    required String warehouseName,
    String? customerId,
    required String customerName,
    String? representativeId,
    String? representativeName,
    required PriceType priceType,
    required PaymentType paymentType,
    required double discount,
    required double paidAmount,
    required List<CartItemModel> items,
  }) async {
    if (items.isEmpty) {
      throw StateError(
        'لا يمكن وضع قائمة فارغة في الانتظار.',
      );
    }

    final cleanWarehouseId =
    warehouseId.trim();

    if (cleanWarehouseId.isEmpty) {
      throw StateError(
        'يجب اختيار المخزن.',
      );
    }

    if (discount < 0) {
      throw StateError(
        'قيمة الخصم غير صحيحة.',
      );
    }

    if (paidAmount < 0) {
      throw StateError(
        'المبلغ المدفوع غير صحيح.',
      );
    }

    for (final item in items) {
      if (item.variantId == null ||
          item.variantId!.trim().isEmpty) {
        throw StateError(
          'المادة "${item.product.name}" لا تحتوي على Variant صالح.',
        );
      }

      if (item.unitId == null ||
          item.unitId!.trim().isEmpty) {
        throw StateError(
          'المادة "${item.product.name}" لا تحتوي على Unit صالح.',
        );
      }

      if (item.quantity <= 0) {
        throw StateError(
          'كمية "${item.product.name}" غير صحيحة.',
        );
      }
    }

    final now =
    DateTime.now();

    final heldSaleId =
        _clean(
          existingHeldSaleId,
        ) ??
            _uuid.v4();

    await database.transaction(
          () async {
        final existing =
        await (database.select(
          database.heldSales,
        )
          ..where(
                (table) =>
                table.id.equals(
                  heldSaleId,
                ),
          ))
            .getSingleOrNull();

        final createdAt =
            existing?.createdAt ?? now;

        await (database.delete(
          database.heldSaleItems,
        )
          ..where(
                (table) =>
                table.heldSaleId.equals(
                  heldSaleId,
                ),
          ))
            .go();

        await (database.delete(
          database.heldSales,
        )
          ..where(
                (table) =>
                table.id.equals(
                  heldSaleId,
                ),
          ))
            .go();

        await database
            .into(
          database.heldSales,
        )
            .insert(
          HeldSalesCompanion.insert(
            id:
            heldSaleId,
            warehouseId:
            cleanWarehouseId,
            warehouseNameSnapshot:
            warehouseName,
            customerId:
            Value(
              _clean(
                customerId,
              ),
            ),
            customerNameSnapshot:
            customerName,
            representativeId:
            Value(
              _clean(
                representativeId,
              ),
            ),
            representativeNameSnapshot:
            Value(
              _clean(
                representativeName,
              ),
            ),
            priceType:
            _priceTypeValue(
              priceType,
            ),
            paymentType:
            _paymentTypeValue(
              paymentType,
            ),
            discount:
            Value(
              discount,
            ),
            paidAmount:
            Value(
              paidAmount,
            ),
            createdAt:
            createdAt,
            updatedAt:
            now,
          ),
        );

        for (final item in items) {
          final variantId =
          item.variantId!.trim();

          final unitId =
          item.unitId!.trim();

          String? barcode;

          for (final variant
          in item.product.variants) {
            if (variant.id ==
                variantId) {
              if (variant.barcode
                  .trim()
                  .isNotEmpty) {
                barcode =
                    variant.barcode.trim();
              } else if (variant.sku != null &&
                  variant.sku!
                      .trim()
                      .isNotEmpty) {
                barcode =
                    variant.sku!.trim();
              }

              break;
            }
          }

          barcode ??=
              _clean(
                item.product.barcode,
              );

          await database
              .into(
            database.heldSaleItems,
          )
              .insert(
            HeldSaleItemsCompanion.insert(
              id:
              _uuid.v4(),
              heldSaleId:
              heldSaleId,
              productId:
              item.product.id,
              variantId:
              variantId,
              unitId:
              unitId,
              productNameSnapshot:
              item.product.name,
              barcodeSnapshot:
              Value(
                barcode,
              ),
              priceType:
              _priceTypeValue(
                item.priceType,
              ),
              quantity:
              item.quantity,
              unitFactor: Value(
                item.unitFactor <= 0 ? 1 : item.unitFactor,
              ),
              loosePieces: Value(
                item.loosePieces < 0 ? 0 : item.loosePieces,
              ),
              unitPrice:
              item.unitPrice,
              discountPercent:
              Value(
                item.discountPercent,
              ),
              total:
              item.total,
              createdAt:
              now,
            ),
          );
        }
      },
    );

    return heldSaleId;
  }

  Future<List<HeldSaleModel>>
  getHeldSales() async {
    final headers =
    await (database.select(
      database.heldSales,
    )
      ..orderBy([
            (table) =>
            OrderingTerm.desc(
              table.updatedAt,
            ),
      ]))
        .get();

    if (headers.isEmpty) {
      return const <HeldSaleModel>[];
    }

    final allItems =
    await database
        .select(
      database.heldSaleItems,
    )
        .get();

    final result =
    <HeldSaleModel>[];

    for (final header in headers) {
      final items =
      allItems
          .where(
            (item) =>
        item.heldSaleId ==
            header.id,
      )
          .map(
            (item) =>
            HeldSaleItemModel(
              id:
              item.id,
              productId:
              item.productId,
              variantId:
              item.variantId,
              unitId:
              item.unitId,
              productName:
              item.productNameSnapshot,
              barcode:
              item.barcodeSnapshot,
              priceType:
              _priceTypeFromValue(
                item.priceType,
              ),
              quantity:
              item.quantity,
              unitPrice:
              item.unitPrice,
              discountPercent:
              item.discountPercent,
              total:
              item.total,
            ),
      )
          .toList();

      result.add(
        HeldSaleModel(
          id:
          header.id,
          warehouseId:
          header.warehouseId,
          warehouseName:
          header.warehouseNameSnapshot,
          customerId:
          header.customerId,
          customerName:
          header.customerNameSnapshot,
          representativeId:
          header.representativeId,
          representativeName:
          header.representativeNameSnapshot,
          priceType:
          _priceTypeFromValue(
            header.priceType,
          ),
          paymentType:
          _paymentTypeFromValue(
            header.paymentType,
          ),
          discount:
          header.discount,
          paidAmount:
          header.paidAmount,
          createdAt:
          header.createdAt,
          updatedAt:
          header.updatedAt,
          items:
          items,
        ),
      );
    }

    return result;
  }

  Future<HeldSaleModel?> getHeldSaleById(
      String heldSaleId,
      ) async {
    final id =
    heldSaleId.trim();

    if (id.isEmpty) {
      return null;
    }

    final header =
    await (database.select(
      database.heldSales,
    )
      ..where(
            (table) =>
            table.id.equals(
              id,
            ),
      ))
        .getSingleOrNull();

    if (header == null) {
      return null;
    }

    final rows =
    await (database.select(
      database.heldSaleItems,
    )
      ..where(
            (table) =>
            table.heldSaleId.equals(
              id,
            ),
      )
      ..orderBy([
            (table) =>
            OrderingTerm.asc(
              table.createdAt,
            ),
      ]))
        .get();

    final items =
    rows
        .map(
          (item) =>
          HeldSaleItemModel(
            id:
            item.id,
            productId:
            item.productId,
            variantId:
            item.variantId,
            unitId:
            item.unitId,
            productName:
            item.productNameSnapshot,
            barcode:
            item.barcodeSnapshot,
            priceType:
            _priceTypeFromValue(
              item.priceType,
            ),
            quantity:
            item.quantity,
            unitFactor: item.unitFactor <= 0 ? 1 : item.unitFactor,
            loosePieces: item.loosePieces < 0 ? 0 : item.loosePieces,
            unitPrice:
            item.unitPrice,
            discountPercent:
            item.discountPercent,
            total:
            item.total,
          ),
    )
        .toList();

    return HeldSaleModel(
      id:
      header.id,
      warehouseId:
      header.warehouseId,
      warehouseName:
      header.warehouseNameSnapshot,
      customerId:
      header.customerId,
      customerName:
      header.customerNameSnapshot,
      representativeId:
      header.representativeId,
      representativeName:
      header.representativeNameSnapshot,
      priceType:
      _priceTypeFromValue(
        header.priceType,
      ),
      paymentType:
      _paymentTypeFromValue(
        header.paymentType,
      ),
      discount:
      header.discount,
      paidAmount:
      header.paidAmount,
      createdAt:
      header.createdAt,
      updatedAt:
      header.updatedAt,
      items:
      items,
    );
  }

  Future<int> getHeldSalesCount() async {
    final rows =
    await database
        .select(
      database.heldSales,
    )
        .get();

    return rows.length;
  }

  Future<void> deleteHeldSale(
      String heldSaleId,
      ) async {
    final id =
    heldSaleId.trim();

    if (id.isEmpty) {
      return;
    }

    await database.transaction(
          () async {
        await (database.delete(
          database.heldSaleItems,
        )
          ..where(
                (table) =>
                table.heldSaleId.equals(
                  id,
                ),
          ))
            .go();

        await (database.delete(
          database.heldSales,
        )
          ..where(
                (table) =>
                table.id.equals(
                  id,
                ),
          ))
            .go();
      },
    );
  }

  // ===========================================================================
  // INVENTORY BALANCE
  // ===========================================================================

  Future<StockBalance?> _findStockBalance({
    required String variantId,
    required String warehouseId,
  }) {
    return (database.select(
      database.stockBalances,
    )
      ..where(
            (table) =>
        table.variantId.equals(
          variantId,
        ) &
        table.warehouseId.equals(
          warehouseId,
        ),
      ))
        .getSingleOrNull();
  }

  // ===========================================================================
  // INVENTORY VARIANT RESOLUTION
  // ===========================================================================

  Future<ProductVariant>
  _resolveInventoryVariant({
    required String productId,
    required String productName,
    String? requestedVariantId,
  }) async {
    final cleanRequestedVariantId =
    _clean(
      requestedVariantId,
    );

    if (cleanRequestedVariantId != null) {
      final variant =
      await (database.select(
        database.productVariants,
      )
        ..where(
              (table) =>
          table.id.equals(
            cleanRequestedVariantId,
          ) &
          table.productId.equals(
            productId,
          ) &
          table.deletedAt.isNull() &
          table.isActive.equals(
            true,
          ),
        ))
          .getSingleOrNull();

      if (variant == null) {
        throw StateError(
          'الخيار المحدد للمنتج "$productName" غير موجود أو غير فعال.',
        );
      }

      return variant;
    }

    final variants =
    await (database.select(
      database.productVariants,
    )
      ..where(
            (table) =>
        table.productId.equals(
          productId,
        ) &
        table.deletedAt.isNull() &
        table.isActive.equals(
          true,
        ),
      ))
        .get();

    if (variants.isEmpty) {
      throw StateError(
        'المنتج "$productName" لا يحتوي على خيار مخزون صالح. '
            'قم بمزامنة المنتجات أولاً.',
      );
    }

    if (variants.length > 1) {
      throw StateError(
        'المنتج "$productName" يحتوي على عدة خيارات. '
            'يجب تحديد الخيار المطلوب قبل إضافته إلى الفاتورة.',
      );
    }

    return variants.first;
  }

  // ===========================================================================
  // UNIT RESOLUTION
  // ===========================================================================

  Future<String> _resolveUnitId({
    String? requestedUnitId,
    String? productBaseUnitId,
    required String productName,
  }) async {
    final unitId =
        _clean(
          requestedUnitId,
        ) ??
            _clean(
              productBaseUnitId,
            );

    if (unitId == null) {
      throw StateError(
        'المنتج "$productName" لا يحتوي على وحدة قياس صالحة.',
      );
    }

    final unit =
    await (database.select(
      database.units,
    )
      ..where(
            (table) =>
            table.id.equals(
              unitId,
            ),
      ))
        .getSingleOrNull();

    if (unit == null) {
      throw StateError(
        'وحدة قياس المنتج "$productName" غير موجودة محلياً. '
            'قم بمزامنة الوحدات أولاً.',
      );
    }

    if (!unit.isActive) {
      throw StateError(
        'وحدة قياس المنتج "$productName" غير فعالة.',
      );
    }

    return unit.id;
  }

  // ===========================================================================
  // IDS
  // ===========================================================================

  Future<List<SaleReturn>> getSaleReturns(String saleId) {
    return (database.select(database.saleReturns)
          ..where((table) => table.saleId.equals(saleId))
          ..orderBy([
            (table) => OrderingTerm.desc(table.createdAt),
          ]))
        .get();
  }

  Future<Map<String, double>> returnedPiecesByItem(String saleId) async {
    final returns = await getSaleReturns(saleId);
    if (returns.isEmpty) {
      return {};
    }
    final ids = returns.map((row) => row.id).toList();
    final lines = await (database.select(database.saleReturnItems)
          ..where((table) => table.returnId.isIn(ids)))
        .get();
    final totals = <String, double>{};
    for (final line in lines) {
      totals[line.saleItemId] = (totals[line.saleItemId] ?? 0) + line.quantity;
    }
    return totals;
  }

  /// سند مرتجع. القائمة الأصلية تبقى كما هي.
  /// الكمية بالقطع، ولا تتجاوز ما تبقى من السطر.
  Future<String> createSaleReturn({
    required String saleId,
    required Map<String, double> piecesByItem,
    String? note,
  }) async {
    final requested = <String, double>{};
    for (final entry in piecesByItem.entries) {
      if (entry.value > 0) {
        requested[entry.key] = entry.value;
      }
    }
    if (requested.isEmpty) {
      throw StateError('حدد كمية مادة واحدة على الأقل.');
    }

    final now = DateTime.now();
    final returnId = _uuid.v4();
    final voucherNumber = _returnNumber(returnId, now);

    await database.transaction(() async {
      final sale = await (database.select(database.sales)
            ..where((table) => table.id.equals(saleId)))
          .getSingleOrNull();
      if (sale == null || sale.deletedAt != null) {
        throw StateError('القائمة غير موجودة.');
      }

      final items = await (database.select(database.saleItems)
            ..where((table) => table.saleId.equals(saleId)))
          .get();
      final byId = {for (final item in items) item.id: item};
      final already = await returnedPiecesByItem(saleId);

      var totalIqd = 0.0;
      final lines = <SaleReturnItemsCompanion>[];

      for (final entry in requested.entries) {
        final item = byId[entry.key];
        if (item == null) {
          throw StateError('أحد أسطر المرتجع لا يتبع هذه القائمة.');
        }
        final sold = _billedPieces(item);
        final left = sold - (already[item.id] ?? 0);
        if (entry.value - left > 0.0001) {
          throw StateError(
            'كمية ${item.productNameSnapshot} أكبر من المتبقي للرجعة.',
          );
        }
        final variantId = item.variantId?.trim() ?? '';
        if (variantId.isEmpty) {
          throw StateError(
            '${item.productNameSnapshot} بلا خيار مخزني، لا يمكن إرجاعها.',
          );
        }
        if (sold <= 0) {
          throw StateError('${item.productNameSnapshot} بلا كمية مباعة.');
        }
        final piecePrice = item.total / sold;
        final lineTotal = piecePrice * entry.value;
        totalIqd += lineTotal;
        lines.add(
          SaleReturnItemsCompanion.insert(
            id: _uuid.v4(),
            returnId: returnId,
            saleItemId: item.id,
            variantId: variantId,
            quantity: entry.value,
            unitPrice: piecePrice,
            total: lineTotal,
            createdAt: now,
          ),
        );

        final balance = await _findStockBalance(
          variantId: variantId,
          warehouseId: sale.warehouseId,
        );
        final nextQuantity = (balance?.quantity ?? 0) + entry.value;
        if (balance != null) {
          await (database.update(database.stockBalances)
                ..where((table) => table.id.equals(balance.id)))
              .write(
            StockBalancesCompanion(
              quantity: Value(nextQuantity),
              updatedAt: Value(now),
            ),
          );
        } else {
          await database.into(database.stockBalances).insert(
                StockBalancesCompanion.insert(
                  id: _balanceId(variantId, sale.warehouseId),
                  variantId: variantId,
                  warehouseId: sale.warehouseId,
                  quantity: Value(nextQuantity),
                  updatedAt: now,
                ),
              );
        }

        await database.into(database.stockMovements).insert(
              StockMovementsCompanion.insert(
                id: _uuid.v4(),
                variantId: variantId,
                warehouseId: sale.warehouseId,
                type: StockMovementType.returnIn.databaseValue,
                quantity: entry.value,
                referenceType: const Value('SALE_RETURN'),
                referenceId: Value(returnId),
                note: Value(_clean(note)),
                serverVersion: const Value(0),
                createdAt: now,
              ),
            );
      }

      await database.into(database.saleReturns).insert(
            SaleReturnsCompanion.insert(
              id: returnId,
              voucherNumber: voucherNumber,
              saleId: saleId,
              customerId: Value(_clean(sale.customerId)),
              warehouseId: sale.warehouseId,
              total: totalIqd,
              currency: Value(sale.currency == 'USD' ? 'USD' : 'IQD'),
              exchangeRate: Value(sale.exchangeRate),
              note: Value(_clean(note)),
              createdAt: now,
            ),
          );
      for (final line in lines) {
        await database.into(database.saleReturnItems).insert(line);
      }

      final customerId = _clean(sale.customerId);
      if (customerId != null && totalIqd > 0) {
        final ledger = nativeLedgerAmount(
          amount: totalIqd,
          currency: sale.currency,
          exchangeRate: sale.exchangeRate,
          amountIsIqd: true,
        );
        await database.into(database.customerLedgerEntries).insert(
              CustomerLedgerEntriesCompanion.insert(
                id: _uuid.v4(),
                customerId: customerId,
                type: 'REVERSAL',
                amount: ledger.amount,
                currency: Value(ledger.currency),
                referenceType: const Value('SALE_RETURN'),
                referenceId: Value(returnId),
                note: Value(
                  _clean(note) ?? 'مرتجع قائمة ${sale.invoiceNumber}',
                ),
                serverVersion: const Value(0),
                createdAt: now,
              ),
            );
      }
    });

    await syncQueue.enqueue(
      entityType: 'floor_notice',
      entityId: returnId,
      operation: SyncOperation.create,
      idempotencyKey: 'return-$returnId',
      payload: {'kind': 'sale_return'},
    );

    return voucherNumber;
  }

  double _billedPieces(SaleItem item) {
    final factor = item.unitFactor <= 0 ? 1.0 : item.unitFactor;
    final cartons = item.quantity < 0 ? 0.0 : item.quantity;
    final loose = item.loosePieces < 0 ? 0 : item.loosePieces;
    return cartons * factor + loose;
  }

  String _returnNumber(String returnId, DateTime date) {
    final suffix = returnId.replaceAll('-', '').substring(0, 6).toUpperCase();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return 'RET-${date.year}$month$day-$suffix';
  }

  Future<void> updateSaleDetails({
    required String saleId,
    required String customerName,
    required String notes,
    required double paidAmount,
    required Map<String, ({double quantity, double unitPrice})> items,
  }) async {
    final cleanName = customerName.trim();
    if (cleanName.isEmpty) {
      throw StateError('اسم الزبون مطلوب.');
    }

    final now = DateTime.now();

    await database.transaction(() async {
      final sale = await (database.select(database.sales)
            ..where((table) => table.id.equals(saleId)))
          .getSingle();
      if ((sale.serverId ?? '').trim().isNotEmpty) {
        throw StateError(
          'هذه القائمة وصلت إلى السيرفر. التعديل بعد المزامنة مغلق حتى لا تختلف البيانات بين الحاسبات.',
        );
      }
      final rows = await (database.select(database.saleItems)
            ..where((table) => table.saleId.equals(saleId)))
          .get();

      var subtotal = 0.0;

      for (final row in rows) {
        final edit = items[row.id];
        if (edit == null) {
          subtotal += row.total;
          continue;
        }

        if (edit.quantity <= 0 || edit.unitPrice < 0) {
          throw StateError('تفاصيل المادة غير صحيحة.');
        }

        final delta = await quantityInBaseUnit(
          database: database,
          unitId: row.unitId,
          quantity: row.quantity - edit.quantity,
          factor: row.unitFactor,
        );
        final variantId = row.variantId;
        if (delta != 0 && variantId != null && variantId.isNotEmpty) {
          final balance = await _findStockBalance(
            variantId: variantId,
            warehouseId: sale.warehouseId,
          );
          final nextStock = (balance?.quantity ?? 0) + delta;
          if (nextStock < 0) {
            throw StateError(
              'الكمية المتوفرة من "${row.productNameSnapshot}" غير كافية.',
            );
          }
          if (balance != null) {
            await (database.update(database.stockBalances)
                  ..where((table) => table.id.equals(balance.id)))
                .write(
              StockBalancesCompanion(
                quantity: Value(nextStock),
                updatedAt: Value(now),
              ),
            );
          }
        }

        final lineTotal = edit.quantity * edit.unitPrice;
        subtotal += lineTotal;
        await (database.update(database.saleItems)
              ..where((table) => table.id.equals(row.id)))
            .write(
          SaleItemsCompanion(
            quantity: Value(edit.quantity),
            unitPrice: Value(edit.unitPrice),
            total: Value(lineTotal),
          ),
        );
      }

      final total = subtotal - sale.discount + sale.porterage;
      if (total < 0) {
        throw StateError('مجموع القائمة غير صحيح.');
      }
      if (paidAmount < 0 || paidAmount > total) {
        throw StateError('المبلغ الواصل غير صحيح.');
      }

      await (database.update(database.sales)
            ..where((table) => table.id.equals(saleId)))
          .write(
        SalesCompanion(
          customerName: Value(cleanName),
          notes: Value(notes.trim()),
          subtotal: Value(subtotal),
          total: Value(total),
          paidAmount: Value(paidAmount),
          remainingAmount: Value(total - paidAmount),
          updatedAt: Value(now),
        ),
      );

      await _rewriteUnsyncedSaleLedger(
        saleId: saleId,
        customerId: sale.customerId,
        total: total,
        paidAmount: paidAmount,
        currency: sale.currency,
        exchangeRate: sale.exchangeRate,
        now: now,
      );
    });
  }

  Future<void> _rewriteUnsyncedSaleLedger({
    required String saleId,
    required String? customerId,
    required double total,
    required double paidAmount,
    required String currency,
    required double exchangeRate,
    required DateTime now,
  }) async {
    final cleanCustomerId = customerId?.trim();
    if (cleanCustomerId == null || cleanCustomerId.isEmpty) {
      return;
    }
    final saleLedger = nativeLedgerAmount(
      amount: total,
      currency: currency,
      exchangeRate: exchangeRate,
      amountIsIqd: true,
    );
    final paidLedger = nativeLedgerAmount(
      amount: paidAmount,
      currency: currency,
      exchangeRate: exchangeRate,
      amountIsIqd: true,
    );

    await (database.update(database.customerLedgerEntries)
          ..where(
            (table) =>
                table.referenceId.equals(saleId) & table.type.equals('SALE'),
          ))
        .write(
      CustomerLedgerEntriesCompanion(
        amount: Value(saleLedger.amount),
        currency: Value(saleLedger.currency),
      ),
    );

    final payments = await (database.select(database.customerPayments)
          ..where((table) => table.referenceId.equals(saleId)))
        .get();

    if (payments.isEmpty) {
      if (paidLedger.amount <= 0) {
        return;
      }

      final paymentId = _uuid.v4();
      await database.into(database.customerPayments).insert(
            CustomerPaymentsCompanion.insert(
              id: paymentId,
              voucherNumber: _receiptNumber(paymentId, now),
              customerId: cleanCustomerId,
              method: const Value('CASH'),
              amount: paidLedger.amount,
              currency: Value(paidLedger.currency),
              referenceType: const Value('SALE'),
              referenceId: Value(saleId),
              serverVersion: const Value(0),
              createdAt: now,
            ),
          );
      await database.into(database.customerLedgerEntries).insert(
            CustomerLedgerEntriesCompanion.insert(
              id: _uuid.v4(),
              customerId: cleanCustomerId,
              type: 'RECEIPT',
              amount: paidLedger.amount,
              currency: Value(paidLedger.currency),
              referenceType: const Value('SALE_PAYMENT'),
              referenceId: Value(paymentId),
              serverVersion: const Value(0),
              createdAt: now,
            ),
          );
      return;
    }

    for (var index = 0; index < payments.length; index++) {
      final payment = payments[index];
      final nextAmount = index == 0 ? paidLedger.amount : 0.0;
      await (database.update(database.customerPayments)
            ..where((table) => table.id.equals(payment.id)))
          .write(
        CustomerPaymentsCompanion(
          amount: Value(nextAmount),
          currency: Value(paidLedger.currency),
        ),
      );
      await (database.update(database.customerLedgerEntries)
            ..where((table) => table.referenceId.equals(payment.id)))
          .write(
        CustomerLedgerEntriesCompanion(
          amount: Value(nextAmount),
          currency: Value(paidLedger.currency),
        ),
      );
    }
  }

  String _invoiceNumber(
      String saleId,
      DateTime date,
      ) {
    final suffix =
    saleId
        .replaceAll(
      '-',
      '',
    )
        .substring(
      0,
      6,
    )
        .toUpperCase();

    return 'INV-${date.millisecondsSinceEpoch}-$suffix';
  }

  String _receiptNumber(
      String paymentId,
      DateTime date,
      ) {
    final suffix =
    paymentId
        .replaceAll(
      '-',
      '',
    )
        .substring(
      0,
      6,
    )
        .toUpperCase();

    return 'REC-${date.millisecondsSinceEpoch}-$suffix';
  }

  String _balanceId(
      String variantId,
      String warehouseId,
      ) {
    return '$variantId::$warehouseId';
  }

  // ===========================================================================
  // ENUMS
  // ===========================================================================

  String _paymentTypeValue(
      PaymentType type,
      ) {
    switch (type) {
      case PaymentType.cash:
        return 'CASH';

      case PaymentType.credit:
        return 'CREDIT';

      case PaymentType.partial:
        return 'PARTIAL';
    }
  }

  PaymentType _paymentTypeFromValue(
      String value,
      ) {
    switch (value
        .trim()
        .toUpperCase()) {
      case 'CREDIT':
        return PaymentType.credit;

      case 'PARTIAL':
        return PaymentType.partial;

      case 'CASH':
      default:
        return PaymentType.cash;
    }
  }

  String _priceTypeValue(
      PriceType type,
      ) {
    switch (type) {
      case PriceType.cost:
        return 'COST';

      case PriceType.representative:
        return 'REP';

      case PriceType.wholesale:
        return 'WHOLESALE';

      case PriceType.retail:
        return 'RETAIL';
    }
  }

  PriceType _priceTypeFromValue(
      String value,
      ) {
    switch (value
        .trim()
        .toUpperCase()) {
      case 'COST':
        return PriceType.cost;

      case 'REP':
      case 'REPRESENTATIVE':
        return PriceType.representative;

      case 'WHOLESALE':
        return PriceType.wholesale;

      case 'RETAIL':
      default:
        return PriceType.retail;
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _formatQuantity(
      double value,
      ) {
    if (value ==
        value.roundToDouble()) {
      return value
          .toInt()
          .toString();
    }

    return value.toStringAsFixed(
      2,
    );
  }

  String? _clean(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final clean =
    value.trim();

    return clean.isEmpty
        ? null
        : clean;
  }
}

class _ResolvedSaleItem {
  final CartItemModel cartItem;
  final Product product;
  final ProductVariant variant;
  final String unitId;

  const _ResolvedSaleItem({
    required this.cartItem,
    required this.product,
    required this.variant,
    required this.unitId,
  });
}