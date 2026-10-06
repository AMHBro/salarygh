import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/money/party_balance.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../../inventory/models/stock_movement_model.dart';
import '../../products/data/unit_quantity.dart';
import '../models/purchase_model.dart';

class PurchasesLocalRepository {
  final AppDatabase database;
  final SyncQueueRepository syncQueue;

  static const Uuid _uuid = Uuid();

  PurchasesLocalRepository({
    required this.database,
    required this.syncQueue,
  });

  // ===========================================================================
  // CREATE PURCHASE
  // ===========================================================================

  Future<PurchaseModel> createPurchase({
    required String supplierId,
    required String warehouseId,
    required List<PurchaseItemModel> items,
    required double discount,
    double porterage = 0,
    required PurchasePaymentType paymentType,
    double paid = 0,
    String? note,
    String? userId,
    String currency = 'IQD',
    double exchangeRate = 0,
  }) async {
    // =========================================================================
    // BASIC VALIDATION
    // =========================================================================

    if (items.isEmpty) {
      throw StateError(
        'يجب إضافة مادة واحدة على الأقل.',
      );
    }

    if (supplierId.trim().isEmpty) {
      throw StateError(
        'يجب اختيار المورد.',
      );
    }

    if (warehouseId.trim().isEmpty) {
      throw StateError(
        'يجب اختيار المخزن.',
      );
    }

    if (currency == 'USD') {
      if (exchangeRate <= 0) {
        throw StateError(
          'حدد سعر الدولار قبل الشراء بالدولار.',
        );
      }
      items = [
        for (final item in items)
          item.copyWith(
            unitCost: item.unitCost * exchangeRate,
          ),
      ];
    }

    for (final item in items) {
      if (item.productId.trim().isEmpty) {
        throw StateError(
          'إحدى المواد غير مرتبطة بمنتج.',
        );
      }

      if (item.quantity <= 0) {
        throw StateError(
          'كمية المادة يجب أن تكون أكبر من صفر.',
        );
      }

      if (item.unitCost < 0) {
        throw StateError(
          'سعر الكلفة غير صحيح.',
        );
      }

      if (item.discountPercent < 0 ||
          item.discountPercent > 100) {
        throw StateError(
          'نسبة خصم المادة يجب أن تكون بين 0 و100.',
        );
      }
    }

    // =========================================================================
    // TOTALS
    // =========================================================================

    final subtotal = items.fold<double>(
      0,
          (sum, item) => sum + item.total,
    );

    if (discount < 0) {
      throw StateError(
        'قيمة الخصم غير صحيحة.',
      );
    }

    if (discount > subtotal) {
      throw StateError(
        'الخصم أكبر من مجموع الفاتورة.',
      );
    }

    if (porterage < 0) {
      throw StateError(
        'قيمة الحمالية غير صحيحة.',
      );
    }

    final total =
        subtotal - discount + porterage;

    late double finalPaid;

    switch (paymentType) {
      case PurchasePaymentType.cash:
        finalPaid = total;
        break;

      case PurchasePaymentType.credit:
        finalPaid = 0;
        break;

      case PurchasePaymentType.partial:
        finalPaid = paid;

        if (finalPaid <= 0 ||
            finalPaid >= total) {
          throw StateError(
            'في الدفع الجزئي يجب أن يكون المدفوع أكبر من صفر وأقل من الإجمالي.',
          );
        }

        break;
    }

    final remaining =
        total - finalPaid;

    final now =
    DateTime.now();

    final purchaseId =
    _uuid.v4();

    final invoiceNumber =
    _invoiceNumber(
      purchaseId,
      now,
    );

    late String supplierName;
    late String warehouseName;

    final resolvedItems =
    <PurchaseItemModel>[];

    // =========================================================================
    // TRANSACTION
    // =========================================================================

    await database.transaction(
          () async {
        // =====================================================================
        // SUPPLIER
        // =====================================================================

        final supplier =
        await (database.select(
          database.suppliers,
        )
          ..where(
                (table) =>
                table.id.equals(
                  supplierId,
                ),
          ))
            .getSingleOrNull();

        if (supplier == null ||
            supplier.deletedAt != null ||
            !supplier.isActive) {
          throw StateError(
            'المورد غير موجود أو غير فعال.',
          );
        }

        /// المورد غير المزامن يجوز استخدامه Offline.
        ///
        /// PurchaseSyncGateway يتحقق من serverId
        /// وقت إرسال العملية للسيرفر.
        supplierName =
            supplier.name;

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
            warehouse.deletedAt != null ||
            !warehouse.isActive) {
          throw StateError(
            'المخزن غير موجود أو غير فعال.',
          );
        }

        warehouseName =
            warehouse.name;

        // =====================================================================
        // PURCHASE HEADER
        // =====================================================================

        await database
            .into(
          database.purchases,
        )
            .insert(
          PurchasesCompanion.insert(
            id:
            purchaseId,
            serverId:
            const Value(null),
            invoiceNumber:
            invoiceNumber,
            supplierId:
            supplierId,
            supplierNameSnapshot:
            supplierName,
            warehouseId:
            warehouseId,
            warehouseNameSnapshot:
            warehouseName,
            subtotal:
            subtotal,
            discount:
            Value(
              discount,
            ),
            porterage: Value(porterage),
            total:
            total,
            paid:
            Value(
              finalPaid,
            ),
            remaining:
            Value(
              remaining,
            ),
            paymentType:
            paymentType.databaseValue,
            currency: Value(
              currency == 'USD' ? 'USD' : 'IQD',
            ),
            exchangeRate: Value(
              currency == 'USD' ? exchangeRate : 0,
            ),
            totalUsd: Value(
              currency == 'USD' && exchangeRate > 0
                  ? total / exchangeRate
                  : 0,
            ),
            note:
            Value(
              _clean(
                note,
              ),
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
        // PURCHASE ITEMS + LOCAL OPTIMISTIC INVENTORY
        // =====================================================================

        for (final requestedItem in items) {
          // -------------------------------------------------------------------
          // PRODUCT
          // -------------------------------------------------------------------

          final product =
          await (database.select(
            database.products,
          )
            ..where(
                  (table) =>
                  table.id.equals(
                    requestedItem.productId,
                  ),
            ))
              .getSingleOrNull();

          if (product == null ||
              product.deletedAt != null ||
              !product.isActive) {
            throw StateError(
              'المنتج ${requestedItem.productName} غير موجود أو غير فعال.',
            );
          }

          // -------------------------------------------------------------------
          // VARIANT
          // -------------------------------------------------------------------

          final variant =
          await _resolveInventoryVariant(
            productId:
            product.id,
            productName:
            product.name,
            requestedVariantId:
            requestedItem.variantId,
          );

          // -------------------------------------------------------------------
          // UNIT
          // -------------------------------------------------------------------

          final unitId =
          _resolveUnitId(
            requestedUnitId:
            requestedItem.unitId,
            productBaseUnitId:
            product.baseUnitId,
            productName:
            product.name,
          );

          // -------------------------------------------------------------------
          // BARCODE
          // -------------------------------------------------------------------

          final variantBarcode =
          variant.barcode?.trim();

          final productBarcode =
          product.barcode?.trim();

          final barcode =
          variantBarcode != null &&
              variantBarcode.isNotEmpty
              ? variantBarcode
              : productBarcode;

          // -------------------------------------------------------------------
          // RESOLVED ITEM
          // -------------------------------------------------------------------

          final resolvedItem =
          requestedItem.copyWith(
            productId:
            product.id,
            variantId:
            variant.id,
            unitId:
            unitId,
            productName:
            product.name,
            barcode:
            barcode,
          );

          resolvedItems.add(
            resolvedItem,
          );

          final itemId =
          _uuid.v4();

          // -------------------------------------------------------------------
          // PURCHASE ITEM
          // -------------------------------------------------------------------

          await database
              .into(
            database.purchaseItems,
          )
              .insert(
            PurchaseItemsCompanion.insert(
              id:
              itemId,
              purchaseId:
              purchaseId,
              productId:
              product.id,
              variantId:
              Value(
                variant.id,
              ),
              unitId:
              Value(
                unitId,
              ),
              productNameSnapshot:
              product.name,
              barcodeSnapshot:
              Value(
                (barcode ?? '').trim(),
              ),
              quantity:
              resolvedItem.quantity,
              unitFactor: Value(
                resolvedItem.unitFactor <= 0 ? 1 : resolvedItem.unitFactor,
              ),
              unitCost:
              resolvedItem.unitCost,
              discountPercent:
              Value(
                resolvedItem.discountPercent,
              ),
              createdAt:
              now,
            ),
          );

          // ===================================================================
          // LOCAL STOCK BALANCE
          // ===================================================================
          //
          // IMPORTANT:
          //
          // لا نبحث بواسطة StockBalances.id.
          //
          // الـInventory Pull ممكن ينشئ الرصيد بـID مختلف عن:
          //
          // variantId::warehouseId
          //
          // المفتاح المنطقي الصحيح هو:
          //
          // variantId + warehouseId
          // ===================================================================

          final currentBalance =
          await _findStockBalance(
            variantId:
            variant.id,
            warehouseId:
            warehouseId,
          );

          final double currentStock =
              currentBalance?.quantity ?? 0.0;

          final stockQuantity = await quantityInBaseUnit(
            database: database,
            unitId: resolvedItem.unitId,
            quantity: resolvedItem.quantity.toDouble(),
            factor: resolvedItem.unitFactor,
          );

          if (stockQuantity > 0) {
            final pieceCost =
                resolvedItem.unitCost * resolvedItem.quantity / stockQuantity;
            final balances = await (database.select(database.stockBalances)
                  ..where((table) => table.variantId.equals(variant.id)))
                .get();
            final oldQty = balances.fold<double>(
              0,
              (sum, row) => sum + row.quantity,
            );
            final newQty = oldQty + stockQuantity;
            final average = newQty > 0
                ? ((oldQty * variant.costPrice) + (stockQuantity * pieceCost)) /
                    newQty
                : pieceCost;
            await (database.update(database.productVariants)
                  ..where((table) => table.id.equals(variant.id)))
                .write(
              ProductVariantsCompanion(
                costPrice: Value(average),
                lastPurchasePrice: Value(pieceCost),
                updatedAt: Value(now),
              ),
            );
          }

          final double newStock =
              currentStock +
                  stockQuantity;

          if (currentBalance != null) {
            // -----------------------------------------------------------------
            // UPDATE EXISTING BALANCE
            //
            // نستخدم الـID الحقيقي للصف الموجود.
            // -----------------------------------------------------------------

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
            // -----------------------------------------------------------------
            // INSERT NEW BALANCE
            //
            // فقط إذا فعلاً ماكو رصيد لنفس:
            //
            // variantId + warehouseId
            // -----------------------------------------------------------------

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

          // ===================================================================
          // LOCAL IMMUTABLE STOCK MOVEMENT
          // ===================================================================
          //
          // LOCAL AUDIT ONLY.
          //
          // لا Outbox للحركة.
          //
          // POST /purchases هو المسؤول عن زيادة المخزون
          // على السيرفر.
          // ===================================================================

          final movement =
          StockMovementModel(
            id:
            _uuid.v4(),
            variantId:
            variant.id,
            warehouseId:
            warehouseId,
            type:
            StockMovementType.purchase,
            quantity:
            stockQuantity,
            referenceType:
            'PURCHASE',
            referenceId:
            purchaseId,
            note:
            _clean(
              note,
            ),
            userId:
            _clean(
              userId,
            ),
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
              now,
            ),
          );
        }

        // =====================================================================
        // LOCAL SUPPLIER PURCHASE LEDGER
        // =====================================================================
        //
        // LOCAL OPTIMISTIC ONLY.
        //
        // لا Outbox مستقل.
        //
        // POST /purchases هو المسؤول عن liability
        // على السيرفر.
        // =====================================================================

        final purchaseLedgerId =
        _uuid.v4();
        final purchaseLedger = nativeLedgerAmount(
          amount: total,
          currency: currency,
          exchangeRate: exchangeRate,
          amountIsIqd: true,
        );
        final paidLedger = nativeLedgerAmount(
          amount: finalPaid,
          currency: currency,
          exchangeRate: exchangeRate,
          amountIsIqd: true,
        );

        await database
            .into(
          database.supplierLedgerEntries,
        )
            .insert(
          SupplierLedgerEntriesCompanion.insert(
            id:
            purchaseLedgerId,
            supplierId:
            supplierId,
            type:
            'PURCHASE',
            amount:
            purchaseLedger.amount,
            currency: Value(purchaseLedger.currency),
            referenceType:
            const Value(
              'PURCHASE',
            ),
            referenceId:
            Value(
              purchaseId,
            ),
            note:
            Value(
              _clean(
                note,
              ),
            ),
            userId:
            Value(
              _clean(
                userId,
              ),
            ),
            serverVersion:
            const Value(
              0,
            ),
            createdAt:
            now,
          ),
        );

        // =====================================================================
        // LOCAL SUPPLIER PAYMENT
        // =====================================================================
        //
        // لا Outbox مستقل.
        //
        // paid_amount الموجود في POST /purchases
        // مسؤول عن تسجيل أثر الدفع في السيرفر.
        // =====================================================================

        if (paidLedger.amount > 0) {
          final paymentId =
          _uuid.v4();

          final paymentLedgerId =
          _uuid.v4();

          final voucherNumber =
          _paymentVoucherNumber(
            paymentId,
            now,
          );

          await database
              .into(
            database.supplierPayments,
          )
              .insert(
            SupplierPaymentsCompanion.insert(
              id:
              paymentId,
              voucherNumber:
              voucherNumber,
              supplierId:
              supplierId,
              method:
              const Value(
                'CASH',
              ),
              amount:
              paidLedger.amount,
              currency: Value(paidLedger.currency),
              referenceType:
              const Value(
                'PURCHASE',
              ),
              referenceId:
              Value(
                purchaseId,
              ),
              note:
              Value(
                _clean(
                  note,
                ),
              ),
              userId:
              Value(
                _clean(
                  userId,
                ),
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
            database.supplierLedgerEntries,
          )
              .insert(
            SupplierLedgerEntriesCompanion.insert(
              id:
              paymentLedgerId,
              supplierId:
              supplierId,
              type:
              'PAYMENT',
              amount:
              paidLedger.amount,
              currency: Value(paidLedger.currency),
              referenceType:
              const Value(
                'SUPPLIER_PAYMENT',
              ),
              referenceId:
              Value(
                paymentId,
              ),
              note:
              Value(
                _clean(
                  note,
                ),
              ),
              userId:
              Value(
                _clean(
                  userId,
                ),
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
        // PURCHASE OUTBOX
        // =====================================================================
        //
        // هذه العملية الوحيدة التي تذهب للسيرفر.
        //
        // لا inventory movement outbox منفصل.
        // لا supplier payment outbox منفصل.
        // =====================================================================

        await syncQueue.enqueue(
          entityType:
          'purchase',
          entityId:
          purchaseId,
          operation:
          SyncOperation.create,
          idempotencyKey:
          purchaseId,
          payload: {
            'id':
            purchaseId,
            'invoice_number':
            invoiceNumber,
            'supplier_id':
            supplierId,
            'warehouse_id':
            warehouseId,
            'items':
            resolvedItems
                .map(
                  (item) =>
                  item.toSyncJson(),
            )
                .toList(),
            'discount_amount':
            discount,
            'paid_amount':
            finalPaid,
            'payment_type':
            paymentType.databaseValue,
            'notes':
            _clean(
              note,
            ),
            'created_at':
            now
                .toUtc()
                .toIso8601String(),
          },
        );
      },
    );

    // =========================================================================
    // RESULT
    // =========================================================================

    return PurchaseModel(
      id:
      purchaseId,
      serverId:
      null,
      invoiceNumber:
      invoiceNumber,
      supplierId:
      supplierId,
      supplierName:
      supplierName,
      warehouseId:
      warehouseId,
      warehouseName:
      warehouseName,
      items:
      List<PurchaseItemModel>.unmodifiable(
        resolvedItems,
      ),
      subtotal:
      subtotal,
      discount:
      discount,
      porterage: porterage,
      total:
      total,
      paid:
      finalPaid,
      remaining:
      remaining,
      paymentType:
      paymentType,
      currency: currency == 'USD' ? 'USD' : 'IQD',
      exchangeRate: currency == 'USD' ? exchangeRate : 0,
      totalUsd: currency == 'USD' && exchangeRate > 0
          ? total / exchangeRate
          : 0,
      note:
      _clean(
        note,
      ),
      createdAt:
      now,
    );
  }

  // ===========================================================================
  // PURCHASES
  // ===========================================================================

  Future<void> updatePurchaseDetails({
    required String purchaseId,
    required String supplierName,
    required String notes,
    required double paidAmount,
    required Map<String, ({int quantity, double unitCost})> items,
  }) async {
    final cleanName = supplierName.trim();
    if (cleanName.isEmpty) {
      throw StateError('اسم المورد مطلوب.');
    }

    final now = DateTime.now();

    await database.transaction(() async {
      final purchase = await (database.select(database.purchases)
            ..where((table) => table.id.equals(purchaseId)))
          .getSingle();
      if ((purchase.serverId ?? '').trim().isNotEmpty) {
        throw StateError(
          'قائمة الشراء وصلت إلى السيرفر. التعديل بعد المزامنة مغلق حتى لا تختلف البيانات بين الحاسبات.',
        );
      }
      final rows = await (database.select(database.purchaseItems)
            ..where((table) => table.purchaseId.equals(purchaseId)))
          .get();

      var subtotal = 0.0;

      for (final row in rows) {
        final edit = items[row.id];
        if (edit == null) {
          final gross = row.quantity * row.unitCost;
          subtotal += gross - gross * (row.discountPercent / 100);
          continue;
        }

        if (edit.quantity <= 0 || edit.unitCost < 0) {
          throw StateError('تفاصيل المادة غير صحيحة.');
        }

        final delta = await quantityInBaseUnit(
          database: database,
          unitId: row.unitId,
          quantity: (edit.quantity - row.quantity).toDouble(),
        );
        final variantId = row.variantId;
        if (delta != 0 && variantId != null && variantId.isNotEmpty) {
          final balance = await _findStockBalance(
            variantId: variantId,
            warehouseId: purchase.warehouseId,
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
          } else {
            await database.into(database.stockBalances).insert(
                  StockBalancesCompanion.insert(
                    id: _balanceId(variantId, purchase.warehouseId),
                    variantId: variantId,
                    warehouseId: purchase.warehouseId,
                    quantity: Value(nextStock),
                    updatedAt: now,
                  ),
                );
          }
        }

        final gross = edit.quantity * edit.unitCost;
        subtotal += gross - gross * (row.discountPercent / 100);
        await (database.update(database.purchaseItems)
              ..where((table) => table.id.equals(row.id)))
            .write(
          PurchaseItemsCompanion(
            quantity: Value(edit.quantity),
            unitCost: Value(edit.unitCost),
          ),
        );
      }

      final total = subtotal - purchase.discount;
      if (total < 0) {
        throw StateError('مجموع قائمة الشراء غير صحيح.');
      }
      if (paidAmount < 0 || paidAmount > total) {
        throw StateError('المبلغ الواصل غير صحيح.');
      }

      await (database.update(database.purchases)
            ..where((table) => table.id.equals(purchaseId)))
          .write(
        PurchasesCompanion(
          supplierNameSnapshot: Value(cleanName),
          note: Value(notes.trim().isEmpty ? null : notes.trim()),
          subtotal: Value(subtotal),
          total: Value(total),
          paid: Value(paidAmount),
          remaining: Value(total - paidAmount),
          totalUsd: Value(
            purchase.currency == 'USD' && purchase.exchangeRate > 0
                ? total / purchase.exchangeRate
                : 0,
          ),
          updatedAt: Value(now),
        ),
      );

      final purchaseLedger = nativeLedgerAmount(
        amount: total,
        currency: purchase.currency,
        exchangeRate: purchase.exchangeRate,
        amountIsIqd: true,
      );
      final paidLedger = nativeLedgerAmount(
        amount: paidAmount,
        currency: purchase.currency,
        exchangeRate: purchase.exchangeRate,
        amountIsIqd: true,
      );

      await (database.update(database.supplierLedgerEntries)
            ..where(
              (table) =>
                  table.referenceId.equals(purchaseId) &
                  table.type.equals('PURCHASE'),
            ))
          .write(
        SupplierLedgerEntriesCompanion(
          amount: Value(purchaseLedger.amount),
          currency: Value(purchaseLedger.currency),
        ),
      );

      final payments = await (database.select(database.supplierPayments)
            ..where((table) => table.referenceId.equals(purchaseId)))
          .get();
      if (payments.isNotEmpty) {
        final payment = payments.first;
        await (database.update(database.supplierPayments)
              ..where((table) => table.id.equals(payment.id)))
            .write(
          SupplierPaymentsCompanion(
            amount: Value(paidLedger.amount),
            currency: Value(paidLedger.currency),
          ),
        );
        await (database.update(database.supplierLedgerEntries)
              ..where((table) => table.referenceId.equals(payment.id)))
            .write(
          SupplierLedgerEntriesCompanion(
            amount: Value(paidLedger.amount),
            currency: Value(paidLedger.currency),
          ),
        );
      }
    });
  }

  Future<List<Purchase>> getPurchases() {
    final query =
    database.select(
      database.purchases,
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

  Future<ListPage<Purchase>> pagePurchases({
    int offset = 0,
    int limit = kListPageSize,
    String search = '',
    DateTime? from,
    DateTime? to,
  }) async {
    final queryText = search.trim();
    final like = '%$queryText%';
    Expression<bool> filter($PurchasesTable table) {
      var expression = table.deletedAt.isNull();
      if (from != null) {
        expression = expression & table.createdAt.isBiggerOrEqualValue(from);
      }
      if (to != null) {
        expression = expression & table.createdAt.isSmallerThanValue(to);
      }
      if (queryText.isNotEmpty) {
        expression = expression &
            (table.invoiceNumber.like(like) |
                table.supplierNameSnapshot.like(like));
      }
      return expression;
    }

    final items = await (database.select(database.purchases)
          ..where(filter)
          ..orderBy([(table) => OrderingTerm.desc(table.createdAt)])
          ..limit(limit, offset: offset))
        .get();
    final totalRow = await (database.selectOnly(database.purchases)
          ..addColumns([database.purchases.id.count()])
          ..where(filter(database.purchases)))
        .getSingle();
    return ListPage(
      items: items,
      total: totalRow.read(database.purchases.id.count()) ?? 0,
    );
  }

  // ===========================================================================
  // STOCK BALANCE
  // ===========================================================================

  /// البحث الصحيح عن رصيد Variant داخل مخزن.
  ///
  /// لا نعتمد على StockBalances.id.
  ///
  /// لأن Inventory Pull قد يستخدم ID مختلف.
  ///
  /// المفتاح المنطقي الحقيقي هو:
  ///
  /// variantId + warehouseId
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
  // RESOLVE INVENTORY VARIANT
  // ===========================================================================

  Future<ProductVariant>
  _resolveInventoryVariant({
    required String productId,
    required String productName,
    required String requestedVariantId,
  }) async {
    final cleanRequestedId =
    requestedVariantId.trim();

    // -------------------------------------------------------------------------
    // Explicit Variant
    // -------------------------------------------------------------------------

    if (cleanRequestedId.isNotEmpty) {
      final variant =
      await (database.select(
        database.productVariants,
      )
        ..where(
              (table) =>
          table.id.equals(
            cleanRequestedId,
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

    // -------------------------------------------------------------------------
    // Auto Resolve
    // -------------------------------------------------------------------------

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
            'يجب تحديد الخيار المطلوب في فاتورة الشراء.',
      );
    }

    return variants.first;
  }

  // ===========================================================================
  // UNIT
  // ===========================================================================

  String _resolveUnitId({
    required String requestedUnitId,
    required String? productBaseUnitId,
    required String productName,
  }) {
    final requested =
    requestedUnitId.trim();

    if (requested.isNotEmpty) {
      return requested;
    }

    final baseUnit =
    productBaseUnitId?.trim();

    if (baseUnit != null &&
        baseUnit.isNotEmpty) {
      return baseUnit;
    }

    throw StateError(
      'المنتج "$productName" غير مرتبط بوحدة قياس. '
          'قم بتحديد الوحدة الأساسية للمنتج أولاً.',
    );
  }

  // ===========================================================================
  // BALANCE ID
  // ===========================================================================

  /// يستخدم فقط عند إنشاء صف Balance جديد.
  ///
  /// لا يستخدم للبحث عن Balance موجود.
  String _balanceId(
      String variantId,
      String warehouseId,
      ) {
    return '$variantId::$warehouseId';
  }

  // ===========================================================================
  // NUMBERS
  // ===========================================================================

  String _invoiceNumber(
      String purchaseId,
      DateTime date,
      ) {
    final suffix =
    purchaseId
        .replaceAll(
      '-',
      '',
    )
        .substring(
      0,
      6,
    )
        .toUpperCase();

    return 'PUR-${date.millisecondsSinceEpoch}-$suffix';
  }

  String _paymentVoucherNumber(
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

    return 'PAY-${date.millisecondsSinceEpoch}-$suffix';
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

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