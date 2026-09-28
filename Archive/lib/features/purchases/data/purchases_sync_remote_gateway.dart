import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_remote_gateway.dart';

class PurchasesSyncRemoteGateway implements SyncRemoteGateway {
  final AppDatabase database;
  final ApiClient apiClient;

  static const int _pullPageLimit = 100;
  static const Uuid _uuid = Uuid();

  PurchasesSyncRemoteGateway({
    required this.database,
    required this.apiClient,
  });

  @override
  Set<String> get supportedEntityTypes => {
    'purchase',
  };

  // ===========================================================================
  // PUSH
  // ===========================================================================

  @override
  Future<void> pushOperation(
      SyncOutboxData operation,
      ) async {
    final operationName = operation.operation.trim().toUpperCase();

    if (operationName != 'CREATE') {
      throw StateError(
        'Unsupported purchase sync operation: ${operation.operation}',
      );
    }

    await _pushCreate(
      operation.entityId,
    );
  }

  // ===========================================================================
  // CREATE
  // ===========================================================================

  Future<void> _pushCreate(
      String localPurchaseId,
      ) async {
    final purchase = await (database.select(
      database.purchases,
    )..where(
            (table) => table.id.equals(
          localPurchaseId,
        )))
        .getSingleOrNull();

    if (purchase == null) {
      throw StateError(
        'فاتورة الشراء المحلية غير موجودة: $localPurchaseId',
      );
    }

    if (purchase.deletedAt != null) {
      throw StateError(
        'لا يمكن مزامنة فاتورة شراء محذوفة.',
      );
    }

    if (_clean(purchase.serverId) != null) {
      debugPrint(
        '[PURCHASE SYNC] CREATE skipped. '
            'Purchase already mapped: ${purchase.serverId}',
      );

      return;
    }

    // =========================================================================
    // SUPPLIER
    // =========================================================================

    final supplier = await (database.select(
      database.suppliers,
    )..where(
            (table) => table.id.equals(
          purchase.supplierId,
        )))
        .getSingleOrNull();

    if (supplier == null ||
        supplier.deletedAt != null ||
        !supplier.isActive) {
      throw StateError(
        'المورد المرتبط بفاتورة الشراء غير موجود أو غير فعال.',
      );
    }

    final supplierServerId = _clean(
      supplier.serverId,
    );

    if (supplierServerId == null) {
      throw StateError(
        'المورد "${supplier.name}" لم تتم مزامنته مع السيرفر بعد.',
      );
    }

    // =========================================================================
    // WAREHOUSE
    // =========================================================================

    final warehouse = await (database.select(
      database.warehouses,
    )..where(
            (table) => table.id.equals(
          purchase.warehouseId,
        )))
        .getSingleOrNull();

    if (warehouse == null ||
        warehouse.deletedAt != null ||
        !warehouse.isActive) {
      throw StateError(
        'المخزن المرتبط بفاتورة الشراء غير موجود أو غير فعال.',
      );
    }

    final warehouseServerId = _clean(
      warehouse.serverId,
    );

    if (warehouseServerId == null) {
      throw StateError(
        'المخزن "${warehouse.name}" لم تتم مزامنته مع السيرفر بعد.',
      );
    }

    if (warehouse.status.trim().toUpperCase() != 'ACTIVE') {
      throw StateError(
        'المخزن "${warehouse.name}" ليس ACTIVE في السيرفر.',
      );
    }

    // =========================================================================
    // ITEMS
    // =========================================================================

    final itemRows = await (database.select(
      database.purchaseItems,
    )..where(
            (table) => table.purchaseId.equals(
          localPurchaseId,
        )))
        .get();

    if (itemRows.isEmpty) {
      throw StateError(
        'فاتورة الشراء لا تحتوي على مواد.',
      );
    }

    final remoteItems = <Map<String, dynamic>>[];

    for (var index = 0; index < itemRows.length; index++) {
      final item = itemRows[index];

      final localVariantId = _clean(
        item.variantId,
      );

      if (localVariantId == null) {
        throw StateError(
          'إحدى مواد الفاتورة قديمة ولا تحتوي على variantId.',
        );
      }

      final variant = await (database.select(
        database.productVariants,
      )..where(
              (table) => table.id.equals(
            localVariantId,
          )))
          .getSingleOrNull();

      if (variant == null ||
          variant.deletedAt != null ||
          !variant.isActive) {
        throw StateError(
          'أحد خيارات المنتجات غير موجود أو غير فعال.',
        );
      }

      final variantServerId = _clean(
        variant.serverId,
      );

      if (variantServerId == null) {
        throw StateError(
          'أحد خيارات المنتجات لم تتم مزامنته مع السيرفر.',
        );
      }

      final unitId = _clean(
        item.unitId,
      );

      if (unitId == null) {
        throw StateError(
          'إحدى مواد الفاتورة غير مرتبطة بوحدة قياس.',
        );
      }

      final localUnit = await (database.select(
        database.units,
      )..where(
              (table) => table.id.equals(
            unitId,
          )))
          .getSingleOrNull();

      if (localUnit == null || !localUnit.isActive) {
        throw StateError(
          'وحدة القياس المرتبطة بإحدى مواد الفاتورة غير موجودة أو غير فعالة.',
        );
      }

      debugPrint(
        '[PURCHASE SYNC] ----------------------------------------',
      );
      debugPrint(
        '[PURCHASE SYNC] Item ${index + 1}/${itemRows.length}',
      );
      debugPrint(
        '[PURCHASE SYNC] Local product ID: ${item.productId}',
      );
      debugPrint(
        '[PURCHASE SYNC] Local variant ID: $localVariantId',
      );
      debugPrint(
        '[PURCHASE SYNC] Server variant ID: $variantServerId',
      );
      debugPrint(
        '[PURCHASE SYNC] Variant barcode: ${variant.barcode}',
      );
      debugPrint(
        '[PURCHASE SYNC] Variant SKU: ${variant.sku}',
      );
      debugPrint(
        '[PURCHASE SYNC] Variant attributes: ${variant.attributesJson}',
      );
      debugPrint(
        '[PURCHASE SYNC] Unit ID: $unitId',
      );
      debugPrint(
        '[PURCHASE SYNC] Unit name: ${localUnit.nameAr}',
      );
      debugPrint(
        '[PURCHASE SYNC] Quantity: ${item.quantity}',
      );
      debugPrint(
        '[PURCHASE SYNC] Unit cost: ${item.unitCost}',
      );
      debugPrint(
        '[PURCHASE SYNC] Discount percent: ${item.discountPercent}',
      );

      final remoteItem = <String, dynamic>{
        'variant_id': variantServerId,
        'unit_id': unitId,
        'quantity': item.quantity,
        'unit_cost': item.unitCost,
        'discount_percent': item.discountPercent,
      };

      debugPrint(
        '[PURCHASE SYNC] Remote item JSON: ${jsonEncode(remoteItem)}',
      );

      remoteItems.add(
        remoteItem,
      );
    }

    // =========================================================================
    // REQUEST BODY
    // =========================================================================

    final body = <String, dynamic>{
      'supplier_id': supplierServerId,
      'warehouse_id': warehouseServerId,
      'payment_type': purchase.paymentType,
      'discount_amount': purchase.discount,
      'paid_amount': purchase.paid,
      'items': remoteItems,
    };

    final notes = _clean(
      purchase.note,
    );

    if (notes != null) {
      body['notes'] = notes;
    }

    debugPrint(
      '[PURCHASE SYNC] ========================================',
    );
    debugPrint(
      '[PURCHASE SYNC] POST /purchases',
    );
    debugPrint(
      '[PURCHASE SYNC] Local purchase: $localPurchaseId',
    );
    debugPrint(
      '[PURCHASE SYNC] Invoice number: ${purchase.invoiceNumber}',
    );
    debugPrint(
      '[PURCHASE SYNC] Supplier: ${supplier.id} -> $supplierServerId',
    );
    debugPrint(
      '[PURCHASE SYNC] Supplier name: ${supplier.name}',
    );
    debugPrint(
      '[PURCHASE SYNC] Warehouse: ${warehouse.id} -> $warehouseServerId',
    );
    debugPrint(
      '[PURCHASE SYNC] Warehouse name: ${warehouse.name}',
    );
    debugPrint(
      '[PURCHASE SYNC] Warehouse status: ${warehouse.status}',
    );
    debugPrint(
      '[PURCHASE SYNC] Payment type: ${purchase.paymentType}',
    );
    debugPrint(
      '[PURCHASE SYNC] Subtotal: ${purchase.subtotal}',
    );
    debugPrint(
      '[PURCHASE SYNC] Discount: ${purchase.discount}',
    );
    debugPrint(
      '[PURCHASE SYNC] Total: ${purchase.total}',
    );
    debugPrint(
      '[PURCHASE SYNC] Paid: ${purchase.paid}',
    );
    debugPrint(
      '[PURCHASE SYNC] Remaining: ${purchase.remaining}',
    );
    debugPrint(
      '[PURCHASE SYNC] Items: ${remoteItems.length}',
    );
    debugPrint(
      '[PURCHASE SYNC] ----------------------------------------',
    );
    debugPrint(
      '[PURCHASE SYNC] REQUEST BODY:',
    );

    try {
      const encoder = JsonEncoder.withIndent('  ');

      debugPrint(
        encoder.convert(
          body,
        ),
      );
    } catch (_) {
      debugPrint(
        '[PURCHASE SYNC] $body',
      );
    }

    debugPrint(
      '[PURCHASE SYNC] ----------------------------------------',
    );

    // =========================================================================
    // POST
    // =========================================================================

    try {
      final response = await apiClient.post(
        '/purchases',
        data: body,
      );

      debugPrint(
        '[PURCHASE SYNC] HTTP ${response.statusCode}',
      );
      debugPrint(
        '[PURCHASE SYNC] RESPONSE BODY:',
      );

      try {
        const encoder = JsonEncoder.withIndent('  ');

        debugPrint(
          encoder.convert(
            response.data,
          ),
        );
      } catch (_) {
        debugPrint(
          '[PURCHASE SYNC] Response: ${response.data}',
        );
      }

      _ensureSuccess(
        response.data,
      );

      final serverId = _extractServerId(
        response.data,
      );

      final officialInvoiceNumber = _extractInvoiceNumber(
        response.data,
      );

      if (serverId != null) {
        await database.transaction(() async {
          final companion = PurchasesCompanion(
            serverId: Value(
              serverId,
            ),
            updatedAt: Value(
              DateTime.now(),
            ),
            invoiceNumber: officialInvoiceNumber != null
                ? Value(
              officialInvoiceNumber,
            )
                : const Value.absent(),
          );

          await (database.update(
            database.purchases,
          )..where(
                  (table) => table.id.equals(
                localPurchaseId,
              )))
              .write(
            companion,
          );
        });

        debugPrint(
          '[PURCHASE SYNC] Server ID saved: $serverId',
        );

        if (officialInvoiceNumber != null) {
          debugPrint(
            '[PURCHASE SYNC] Official invoice number saved: '
                '$officialInvoiceNumber',
          );
        }
      } else {
        debugPrint(
          '[PURCHASE SYNC] Server accepted purchase, '
              'but response did not expose purchase id.',
        );
      }

      debugPrint(
        '[PURCHASE SYNC] Purchase pushed successfully.',
      );
      debugPrint(
        '[PURCHASE SYNC] ========================================',
      );
    } on DioException catch (error) {
      debugPrint(
        '[PURCHASE SYNC] !!! REQUEST FAILED !!!',
      );
      debugPrint(
        '[PURCHASE SYNC] HTTP ${error.response?.statusCode}',
      );
      debugPrint(
        '[PURCHASE SYNC] Method: ${error.requestOptions.method}',
      );
      debugPrint(
        '[PURCHASE SYNC] Path: ${error.requestOptions.path}',
      );
      debugPrint(
        '[PURCHASE SYNC] Dio type: ${error.type}',
      );
      debugPrint(
        '[PURCHASE SYNC] Dio message: ${error.message}',
      );
      debugPrint(
        '[PURCHASE SYNC] ----------------------------------------',
      );
      debugPrint(
        '[PURCHASE SYNC] SENT BODY:',
      );

      try {
        const encoder = JsonEncoder.withIndent('  ');

        debugPrint(
          encoder.convert(
            error.requestOptions.data,
          ),
        );
      } catch (_) {
        debugPrint(
          '[PURCHASE SYNC] ${error.requestOptions.data}',
        );
      }

      debugPrint(
        '[PURCHASE SYNC] ----------------------------------------',
      );
      debugPrint(
        '[PURCHASE SYNC] SERVER RESPONSE:',
      );

      try {
        const encoder = JsonEncoder.withIndent('  ');

        debugPrint(
          encoder.convert(
            error.response?.data,
          ),
        );
      } catch (_) {
        debugPrint(
          '[PURCHASE SYNC] ${error.response?.data}',
        );
      }

      debugPrint(
        '[PURCHASE SYNC] ========================================',
      );

      rethrow;
    }
  }

  // ===========================================================================
  // PULL
  // ===========================================================================

  @override
  Future<SyncPullResult> pullChanges({
    String? cursor,
  }) async {
    debugPrint(
      '[PURCHASE PULL] ========================================',
    );
    debugPrint(
      '[PURCHASE PULL] Starting purchases pull...',
    );

    final purchaseIds = await _fetchAllPurchaseIds();

    debugPrint(
      '[PURCHASE PULL] ${purchaseIds.length} purchase(s) found.',
    );

    var successCount = 0;
    var failedCount = 0;

    for (var index = 0; index < purchaseIds.length; index++) {
      final serverPurchaseId = purchaseIds[index];

      debugPrint(
        '[PURCHASE PULL] ----------------------------------------',
      );
      debugPrint(
        '[PURCHASE PULL] Purchase ${index + 1}/${purchaseIds.length}',
      );
      debugPrint(
        '[PURCHASE PULL] GET /purchases/$serverPurchaseId',
      );

      try {
        final detailResponse = await apiClient.get(
          '/purchases/$serverPurchaseId',
        );

        final detail = _extractDetail(
          detailResponse.data,
        );

        await _saveRemotePurchase(
          detail,
        );

        successCount++;
      } on DioException catch (error) {
        failedCount++;

        debugPrint(
          '[PURCHASE PULL] Purchase request failed.',
        );
        debugPrint(
          '[PURCHASE PULL] Server ID: $serverPurchaseId',
        );
        debugPrint(
          '[PURCHASE PULL] HTTP: ${error.response?.statusCode}',
        );
        debugPrint(
          '[PURCHASE PULL] Response: ${error.response?.data}',
        );
        debugPrint(
          '[PURCHASE PULL] Continuing with next purchase.',
        );
      } catch (error, stackTrace) {
        failedCount++;

        debugPrint(
          '[PURCHASE PULL] Purchase could not be reconciled.',
        );
        debugPrint(
          '[PURCHASE PULL] Server ID: $serverPurchaseId',
        );
        debugPrint(
          '[PURCHASE PULL] Error: $error',
        );
        debugPrint(
          '[PURCHASE PULL] StackTrace: $stackTrace',
        );
        debugPrint(
          '[PURCHASE PULL] Continuing with next purchase.',
        );
      }
    }

    debugPrint(
      '[PURCHASE PULL] ----------------------------------------',
    );
    debugPrint(
      '[PURCHASE PULL] Pull finished.',
    );
    debugPrint(
      '[PURCHASE PULL] Success: $successCount',
    );
    debugPrint(
      '[PURCHASE PULL] Failed: $failedCount',
    );
    debugPrint(
      '[PURCHASE PULL] ========================================',
    );

    return const SyncPullResult(
      nextCursor: null,
      changes: [],
    );
  }

  // ===========================================================================
  // PULL - LIST
  // ===========================================================================

  Future<List<String>> _fetchAllPurchaseIds() async {
    final result = <String>[];

    var page = 1;
    var totalPages = 1;

    do {
      debugPrint(
        '[PURCHASE PULL] GET /purchases?page=$page&limit=$_pullPageLimit',
      );

      final response = await apiClient.get(
        '/purchases',
        queryParameters: {
          'page': page,
          'limit': _pullPageLimit,
        },
      );

      final root = _asMap(
        response.data,
        context: 'GET /purchases response',
      );

      final rawData = root['data'];

      if (rawData is! List) {
        throw StateError(
          'GET /purchases لم يرجع data من نوع List.',
        );
      }

      for (final rawPurchase in rawData) {
        final purchase = _asMap(
          rawPurchase,
          context: 'Purchase list item',
        );

        final id = _requiredString(
          purchase['id'],
          'purchase.id',
        );

        result.add(
          id,
        );
      }

      final metaRaw = root['meta'];

      if (metaRaw is Map) {
        final meta = Map<String, dynamic>.from(
          metaRaw,
        );

        final remotePage = _intValue(
          meta['page'],
        ) ??
            page;

        final remoteTotalPages = _intValue(
          meta['totalPages'],
        ) ??
            1;

        final total = _intValue(
          meta['total'],
        ) ??
            result.length;

        debugPrint(
          '[PURCHASE PULL] Page $remotePage/$remoteTotalPages '
              '- Total purchases: $total',
        );

        page = remotePage + 1;
        totalPages = remoteTotalPages;
      } else {
        debugPrint(
          '[PURCHASE PULL] No pagination meta found. '
              'Treating response as one page.',
        );

        totalPages = 1;
        page = 2;
      }
    } while (page <= totalPages);

    return result;
  }

  // ===========================================================================
  // PULL - DETAIL
  // ===========================================================================

  Map<String, dynamic> _extractDetail(
      dynamic raw,
      ) {
    final root = _asMap(
      raw,
      context: 'GET /purchases/{id} response',
    );

    if (root['success'] == false) {
      final message = root['message']?.toString().trim();

      throw StateError(
        message?.isNotEmpty == true
            ? message!
            : 'فشل تحميل تفاصيل فاتورة الشراء.',
      );
    }

    final data = root['data'];

    return _asMap(
      data,
      context: 'Purchase detail data',
    );
  }

  // ===========================================================================
  // PULL - SAVE
  // ===========================================================================

  Future<void> _saveRemotePurchase(
      Map<String, dynamic> remote,
      ) async {
    final serverPurchaseId = _requiredString(
      remote['id'],
      'purchase.id',
    );

    final invoiceNumber = _requiredString(
      remote['invoice_number'],
      'purchase.invoice_number',
    );

    final supplierServerId = _requiredString(
      remote['supplier_id'],
      'purchase.supplier_id',
    );

    final warehouseServerId = _requiredString(
      remote['warehouse_id'],
      'purchase.warehouse_id',
    );

    final paymentType = _requiredString(
      remote['payment_type'],
      'purchase.payment_type',
    ).toUpperCase();

    if (paymentType != 'CASH' &&
        paymentType != 'CREDIT' &&
        paymentType != 'PARTIAL') {
      throw StateError(
        'نوع دفع غير معروف في فاتورة الشراء '
            '$invoiceNumber: $paymentType',
      );
    }

    final subtotal = _requiredDouble(
      remote['subtotal'],
      'purchase.subtotal',
    );

    final discount = _doubleValue(
      remote['discount_amount'],
    ) ??
        0;

    final total = _requiredDouble(
      remote['total'],
      'purchase.total',
    );

    final paid = _doubleValue(
      remote['paid_amount'],
    ) ??
        0;

    final remaining = _doubleValue(
      remote['due_amount'],
    ) ??
        0;

    final note = _clean(
      remote['notes']?.toString(),
    );

    final createdAt = _dateValue(
      remote['created_at'],
    ) ??
        _dateValue(
          remote['invoice_date'],
        ) ??
        DateTime.now();

    final updatedAt = _dateValue(
      remote['updated_at'],
    ) ??
        createdAt;

    // =========================================================================
    // SUPPLIER MAPPING
    // =========================================================================

    final supplier = await (database.select(
      database.suppliers,
    )..where(
          (table) =>
      table.serverId.equals(
        supplierServerId,
      ) &
      table.deletedAt.isNull(),
    ))
        .getSingleOrNull();

    if (supplier == null) {
      throw StateError(
        'لا يمكن Pull لفاتورة $invoiceNumber لأن المورد '
            '$supplierServerId غير موجود محلياً.',
      );
    }

    // =========================================================================
    // WAREHOUSE MAPPING
    // =========================================================================

    final warehouse = await (database.select(
      database.warehouses,
    )..where(
          (table) =>
      table.serverId.equals(
        warehouseServerId,
      ) &
      table.deletedAt.isNull(),
    ))
        .getSingleOrNull();

    if (warehouse == null) {
      throw StateError(
        'لا يمكن Pull لفاتورة $invoiceNumber لأن المخزن '
            '$warehouseServerId غير موجود محلياً.',
      );
    }

    // =========================================================================
    // EXISTING PURCHASE BY SERVER ID
    // =========================================================================

    final existingByServerId = await (database.select(
      database.purchases,
    )..where(
            (table) => table.serverId.equals(
          serverPurchaseId,
        )))
        .getSingleOrNull();

    // =========================================================================
    // EXISTING PURCHASE BY INVOICE NUMBER
    //
    // This is also used to repair a stale serverId mapping.
    // =========================================================================

    final existingByInvoiceNumber = await (database.select(
      database.purchases,
    )..where(
            (table) => table.invoiceNumber.equals(
          invoiceNumber,
        )))
        .getSingleOrNull();

    // =========================================================================
    // DETERMINE LOCAL PURCHASE
    // =========================================================================

    String localPurchaseId;

    if (existingByServerId != null) {
      localPurchaseId = existingByServerId.id;

      if (existingByInvoiceNumber != null &&
          existingByInvoiceNumber.id != existingByServerId.id) {
        throw StateError(
          'يوجد تعارض محلي حقيقي في رقم فاتورة الشراء '
              '$invoiceNumber. '
              'Server mapped local ID: ${existingByServerId.id}, '
              'conflicting local ID: ${existingByInvoiceNumber.id}',
        );
      }
    } else if (existingByInvoiceNumber != null) {
      final localServerId = _clean(
        existingByInvoiceNumber.serverId,
      );

      final sameSupplier =
          existingByInvoiceNumber.supplierId == supplier.id;

      final sameWarehouse =
          existingByInvoiceNumber.warehouseId == warehouse.id;

      final sameTotal = _sameMoney(
        existingByInvoiceNumber.total,
        total,
      );

      // =======================================================================
      // STALE SERVER-ID REPAIR
      //
      // Example:
      //
      // Local:
      // invoice = PUR-202609-0007
      // serverId = OLD-ID
      //
      // Server:
      // OLD-ID -> 404
      // invoice = PUR-202609-0007
      // serverId = NEW-ID
      //
      // We NEVER replace the mapping merely because the invoice number matches.
      //
      // We first verify:
      // 1. old server ID really returns 404
      // 2. supplier matches
      // 3. warehouse matches
      // 4. total matches
      // =======================================================================

      if (localServerId != null &&
          localServerId != serverPurchaseId) {
        debugPrint(
          '[PURCHASE PULL] Possible stale server mapping detected.',
        );
        debugPrint(
          '[PURCHASE PULL] Invoice: $invoiceNumber',
        );
        debugPrint(
          '[PURCHASE PULL] Local ID: ${existingByInvoiceNumber.id}',
        );
        debugPrint(
          '[PURCHASE PULL] Old server ID: $localServerId',
        );
        debugPrint(
          '[PURCHASE PULL] Current server ID: $serverPurchaseId',
        );
        debugPrint(
          '[PURCHASE PULL] Verifying old server ID...',
        );

        final oldServerPurchaseStillExists =
        await _remotePurchaseExists(
          localServerId,
        );

        if (oldServerPurchaseStillExists) {
          throw StateError(
            'رقم الفاتورة $invoiceNumber مرتبط محلياً '
                'بالسيرفر $localServerId، وهذا السجل ما زال '
                'موجوداً على السيرفر، بينما يوجد أيضاً السجل '
                '$serverPurchaseId. '
                'لن يتم دمج الفاتورتين تلقائياً.',
          );
        }

        debugPrint(
          '[PURCHASE PULL] Old server ID returned 404.',
        );

        if (!sameSupplier || !sameWarehouse || !sameTotal) {
          throw StateError(
            'تم اكتشاف Server ID قديم لفاتورة '
                '$invoiceNumber، لكن بيانات الفاتورة المحلية '
                'لا تطابق السجل الحالي على السيرفر. '
                'Supplier match: $sameSupplier, '
                'Warehouse match: $sameWarehouse, '
                'Total match: $sameTotal, '
                'Local ID: ${existingByInvoiceNumber.id}',
          );
        }

        localPurchaseId = existingByInvoiceNumber.id;

        debugPrint(
          '[PURCHASE PULL] ========================================',
        );
        debugPrint(
          '[PURCHASE PULL] STALE SERVER MAPPING CONFIRMED',
        );
        debugPrint(
          '[PURCHASE PULL] Invoice: $invoiceNumber',
        );
        debugPrint(
          '[PURCHASE PULL] Local ID: $localPurchaseId',
        );
        debugPrint(
          '[PURCHASE PULL] Old server ID: $localServerId',
        );
        debugPrint(
          '[PURCHASE PULL] New server ID: $serverPurchaseId',
        );
        debugPrint(
          '[PURCHASE PULL] Supplier match: $sameSupplier',
        );
        debugPrint(
          '[PURCHASE PULL] Warehouse match: $sameWarehouse',
        );
        debugPrint(
          '[PURCHASE PULL] Total match: $sameTotal',
        );
        debugPrint(
          '[PURCHASE PULL] Safe reconciliation approved.',
        );
        debugPrint(
          '[PURCHASE PULL] ========================================',
        );
      } else {
        // =====================================================================
        // NORMAL INVOICE-NUMBER RECONCILIATION
        //
        // Local row exists with no serverId yet, or already points to the
        // current server purchase.
        // =====================================================================

        if (!sameSupplier || !sameWarehouse || !sameTotal) {
          throw StateError(
            'يوجد تعارض محلي في رقم فاتورة الشراء '
                '$invoiceNumber، لكن بيانات الفاتورة المحلية '
                'لا تطابق بيانات السيرفر. '
                'Local ID: ${existingByInvoiceNumber.id}',
          );
        }

        localPurchaseId = existingByInvoiceNumber.id;

        debugPrint(
          '[PURCHASE PULL] Reconciliation candidate found.',
        );
        debugPrint(
          '[PURCHASE PULL] Invoice: $invoiceNumber',
        );
        debugPrint(
          '[PURCHASE PULL] Local ID: $localPurchaseId',
        );
        debugPrint(
          '[PURCHASE PULL] Server ID: $serverPurchaseId',
        );
        debugPrint(
          '[PURCHASE PULL] Supplier match: $sameSupplier',
        );
        debugPrint(
          '[PURCHASE PULL] Warehouse match: $sameWarehouse',
        );
        debugPrint(
          '[PURCHASE PULL] Total match: $sameTotal',
        );
      }
    } else {
      localPurchaseId = _uuid.v4();
    }

    // =========================================================================
    // ITEMS PREPARATION
    // =========================================================================

    final rawItems = remote['purchase_invoice_items'];

    if (rawItems is! List) {
      throw StateError(
        'فاتورة $invoiceNumber لا تحتوي '
            'purchase_invoice_items بصيغة صحيحة.',
      );
    }

    final itemCompanions = <PurchaseItemsCompanion>[];

    for (final rawItem in rawItems) {
      final item = _asMap(
        rawItem,
        context: 'purchase_invoice_items item',
      );

      final serverItemId = _requiredString(
        item['id'],
        'purchase_item.id',
      );

      final variantServerId = _requiredString(
        item['variant_id'],
        'purchase_item.variant_id',
      );

      final unitId = _requiredString(
        item['unit_id'],
        'purchase_item.unit_id',
      );

      final quantityDouble = _requiredDouble(
        item['quantity'],
        'purchase_item.quantity',
      );

      if (quantityDouble <= 0) {
        throw StateError(
          'كمية غير صالحة في فاتورة $invoiceNumber.',
        );
      }

      if (quantityDouble % 1 != 0) {
        throw StateError(
          'فاتورة $invoiceNumber تحتوي كمية عشرية '
              '$quantityDouble بينما PurchaseItems.quantity '
              'محلياً من نوع int.',
        );
      }

      final quantity = quantityDouble.toInt();

      final unitCost = _requiredDouble(
        item['unit_cost'],
        'purchase_item.unit_cost',
      );

      final discountPercent = _doubleValue(
        item['discount_percent'],
      ) ??
          0;

      // ======================================================================
      // VARIANT MAPPING
      // ======================================================================

      final variant = await (database.select(
        database.productVariants,
      )..where(
            (table) =>
        table.serverId.equals(
          variantServerId,
        ) &
        table.deletedAt.isNull(),
      ))
          .getSingleOrNull();

      if (variant == null) {
        throw StateError(
          'لا يمكن Pull لفاتورة $invoiceNumber لأن '
              'Variant $variantServerId غير موجود محلياً.',
        );
      }

      // ======================================================================
      // PRODUCT
      // ======================================================================

      final product = await (database.select(
        database.products,
      )..where(
            (table) =>
        table.id.equals(
          variant.productId,
        ) &
        table.deletedAt.isNull(),
      ))
          .getSingleOrNull();

      if (product == null) {
        throw StateError(
          'المنتج المحلي المرتبط بالـVariant '
              '$variantServerId غير موجود.',
        );
      }

      // ======================================================================
      // UNIT
      // ======================================================================

      final unit = await (database.select(
        database.units,
      )..where(
              (table) => table.id.equals(
            unitId,
          )))
          .getSingleOrNull();

      if (unit == null) {
        throw StateError(
          'لا يمكن Pull لفاتورة $invoiceNumber لأن '
              'وحدة القياس $unitId غير موجودة محلياً.',
        );
      }

      final itemCreatedAt = _dateValue(
        item['created_at'],
      ) ??
          createdAt;

      itemCompanions.add(
        PurchaseItemsCompanion(
          id: Value(
            serverItemId,
          ),
          purchaseId: Value(
            localPurchaseId,
          ),
          productId: Value(
            product.id,
          ),
          variantId: Value(
            variant.id,
          ),
          unitId: Value(
            unit.id,
          ),
          productNameSnapshot: Value(
            product.name,
          ),
          barcodeSnapshot: Value(
            variant.barcode ?? '',
          ),
          quantity: Value(
            quantity,
          ),
          unitCost: Value(
            unitCost,
          ),
          discountPercent: Value(
            discountPercent,
          ),
          createdAt: Value(
            itemCreatedAt,
          ),
        ),
      );
    }

    // =========================================================================
    // DATABASE TRANSACTION
    // =========================================================================

    await database.transaction(() async {
      final purchaseCompanion = PurchasesCompanion(
        id: Value(
          localPurchaseId,
        ),
        serverId: Value(
          serverPurchaseId,
        ),
        invoiceNumber: Value(
          invoiceNumber,
        ),
        supplierId: Value(
          supplier.id,
        ),
        supplierNameSnapshot: Value(
          supplier.name,
        ),
        warehouseId: Value(
          warehouse.id,
        ),
        warehouseNameSnapshot: Value(
          warehouse.name,
        ),
        subtotal: Value(
          subtotal,
        ),
        discount: Value(
          discount,
        ),
        total: Value(
          total,
        ),
        paid: Value(
          paid,
        ),
        remaining: Value(
          remaining,
        ),
        paymentType: Value(
          paymentType,
        ),
        note: Value(
          note,
        ),
        serverVersion: const Value(
          0,
        ),
        createdAt: Value(
          createdAt,
        ),
        updatedAt: Value(
          updatedAt,
        ),
        deletedAt: const Value(
          null,
        ),
      );

      final localPurchaseExists =
          existingByServerId != null ||
              existingByInvoiceNumber != null;

      if (!localPurchaseExists) {
        await database.into(database.purchases).insert(
          purchaseCompanion,
        );

        debugPrint(
          '[PURCHASE PULL] Inserted remote purchase:',
        );
      } else {
        await (database.update(
          database.purchases,
        )..where(
                (table) => table.id.equals(
              localPurchaseId,
            )))
            .write(
          purchaseCompanion,
        );

        if (existingByServerId == null &&
            existingByInvoiceNumber != null) {
          debugPrint(
            '[PURCHASE PULL] Reconciled local purchase with server:',
          );
        } else {
          debugPrint(
            '[PURCHASE PULL] Updated local purchase:',
          );
        }
      }

      // -----------------------------------------------------------------------
      // Server detail is authoritative for purchase items.
      //
      // IMPORTANT:
      // This pull must NEVER create financial or inventory side effects.
      //
      // Do NOT:
      // - create StockMovement
      // - change StockBalances
      // - create SupplierLedgerEntry
      // - create SupplierPayment
      // - create Outbox
      // -----------------------------------------------------------------------

      await (database.delete(
        database.purchaseItems,
      )..where(
              (table) => table.purchaseId.equals(
            localPurchaseId,
          )))
          .go();

      for (final itemCompanion in itemCompanions) {
        await database.into(database.purchaseItems).insert(
          itemCompanion,
        );
      }
    });

    debugPrint(
      '[PURCHASE PULL] local=$localPurchaseId',
    );
    debugPrint(
      '[PURCHASE PULL] server=$serverPurchaseId',
    );
    debugPrint(
      '[PURCHASE PULL] invoice=$invoiceNumber',
    );
    debugPrint(
      '[PURCHASE PULL] supplier=${supplier.name}',
    );
    debugPrint(
      '[PURCHASE PULL] warehouse=${warehouse.name}',
    );
    debugPrint(
      '[PURCHASE PULL] items=${itemCompanions.length}',
    );
  }

  // ===========================================================================
  // REMOTE PURCHASE EXISTENCE CHECK
  // ===========================================================================

  Future<bool> _remotePurchaseExists(
      String serverPurchaseId,
      ) async {
    debugPrint(
      '[PURCHASE PULL] Checking old server purchase:',
    );
    debugPrint(
      '[PURCHASE PULL] GET /purchases/$serverPurchaseId',
    );

    try {
      final response = await apiClient.get(
        '/purchases/$serverPurchaseId',
      );

      final statusCode = response.statusCode;

      debugPrint(
        '[PURCHASE PULL] Old server purchase check HTTP: $statusCode',
      );

      if (statusCode != null &&
          statusCode >= 200 &&
          statusCode < 300) {
        debugPrint(
          '[PURCHASE PULL] Old server purchase still exists.',
        );

        return true;
      }

      throw StateError(
        'تعذر التحقق من Server ID القديم '
            '$serverPurchaseId. HTTP: $statusCode',
      );
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;

      if (statusCode == 404) {
        debugPrint(
          '[PURCHASE PULL] Old server purchase does not exist (404).',
        );

        return false;
      }

      debugPrint(
        '[PURCHASE PULL] Could not verify old server purchase.',
      );
      debugPrint(
        '[PURCHASE PULL] Server ID: $serverPurchaseId',
      );
      debugPrint(
        '[PURCHASE PULL] HTTP: $statusCode',
      );
      debugPrint(
        '[PURCHASE PULL] Response: ${error.response?.data}',
      );

      rethrow;
    }
  }

  // ===========================================================================
  // MONEY COMPARISON
  // ===========================================================================

  bool _sameMoney(
      double a,
      double b,
      ) {
    return (a - b).abs() < 0.01;
  }

  // ===========================================================================
  // RESPONSE HELPERS
  // ===========================================================================

  void _ensureSuccess(
      dynamic raw,
      ) {
    if (raw == null) {
      return;
    }

    if (raw is Map) {
      final map = Map<String, dynamic>.from(
        raw,
      );

      if (map['success'] == false) {
        final message = map['message']?.toString().trim();

        throw StateError(
          message?.isNotEmpty == true
              ? message!
              : 'فشل إنشاء فاتورة الشراء.',
        );
      }

      return;
    }
  }

  String? _extractServerId(
      dynamic raw,
      ) {
    if (raw is! Map) {
      return null;
    }

    final root = Map<String, dynamic>.from(
      raw,
    );

    final directId = _clean(
      root['id']?.toString(),
    );

    if (directId != null) {
      return directId;
    }

    final data = root['data'];

    if (data is Map) {
      return _clean(
        data['id']?.toString(),
      );
    }

    return null;
  }

  String? _extractInvoiceNumber(
      dynamic raw,
      ) {
    if (raw is! Map) {
      return null;
    }

    final root = Map<String, dynamic>.from(
      raw,
    );

    final direct = _clean(
      root['invoice_number']?.toString(),
    );

    if (direct != null) {
      return direct;
    }

    final data = root['data'];

    if (data is Map) {
      return _clean(
        data['invoice_number']?.toString(),
      );
    }

    return null;
  }

  Map<String, dynamic> _asMap(
      dynamic raw, {
        required String context,
      }) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }

    if (raw is Map) {
      return Map<String, dynamic>.from(
        raw,
      );
    }

    throw StateError(
      '$context ليس Map صالح.',
    );
  }

  String _requiredString(
      dynamic raw,
      String fieldName,
      ) {
    final value = _clean(
      raw?.toString(),
    );

    if (value == null) {
      throw StateError(
        'الحقل $fieldName مفقود أو فارغ.',
      );
    }

    return value;
  }

  double _requiredDouble(
      dynamic raw,
      String fieldName,
      ) {
    final value = _doubleValue(
      raw,
    );

    if (value == null) {
      throw StateError(
        'الحقل $fieldName ليس رقماً صالحاً.',
      );
    }

    return value;
  }

  double? _doubleValue(
      dynamic raw,
      ) {
    if (raw == null) {
      return null;
    }

    if (raw is num) {
      return raw.toDouble();
    }

    return double.tryParse(
      raw.toString().trim(),
    );
  }

  int? _intValue(
      dynamic raw,
      ) {
    if (raw == null) {
      return null;
    }

    if (raw is int) {
      return raw;
    }

    if (raw is num) {
      return raw.toInt();
    }

    return int.tryParse(
      raw.toString().trim(),
    );
  }

  DateTime? _dateValue(
      dynamic raw,
      ) {
    if (raw == null) {
      return null;
    }

    if (raw is DateTime) {
      return raw;
    }

    final value = raw.toString().trim();

    if (value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(
      value,
    );
  }

  String? _clean(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final clean = value.trim();

    return clean.isEmpty ? null : clean;
  }
}