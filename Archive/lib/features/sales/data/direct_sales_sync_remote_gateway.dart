import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/floor/floor_store.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_remote_gateway.dart';

class DirectSalesSyncRemoteGateway
    implements SyncRemoteGateway {
  final AppDatabase database;
  final ApiClient apiClient;

  static const Uuid _uuid = Uuid();

  DirectSalesSyncRemoteGateway({
    required this.database,
    required this.apiClient,
  });

  @override
  Set<String> get supportedEntityTypes => {
    'direct_sale',
  };

  // ===========================================================================
  // PUSH
  // ===========================================================================

  @override
  Future<void> pushOperation(
      SyncOutboxData operation,
      ) async {
    if (operation.entityType !=
        'direct_sale') {
      throw UnsupportedError(
        'Unsupported Direct Sales entity type: '
            '${operation.entityType}',
      );
    }

    switch (operation.operation
        .trim()
        .toUpperCase()) {
      case 'CREATE':
        await _pushCreate(
          operation,
        );
        return;

      default:
        throw UnsupportedError(
          'Unsupported Direct Sale operation: '
              '${operation.operation}',
        );
    }
  }

  // ===========================================================================
  // CREATE DIRECT SALE
  // ===========================================================================

  Future<void> _pushCreate(
      SyncOutboxData operation,
      ) async {
    final saleId =
    operation.entityId.trim();

    if (saleId.isEmpty) {
      throw StateError(
        'Direct Sale local ID is missing.',
      );
    }

    // =========================================================================
    // SALE HEADER
    // =========================================================================

    final sale =
    await (database.select(
      database.sales,
    )
      ..where(
            (table) =>
        table.id.equals(
          saleId,
        ) &
        table.deletedAt.isNull(),
      ))
        .getSingleOrNull();

    if (sale == null) {
      throw StateError(
        'فاتورة البيع المحلية غير موجودة: $saleId',
      );
    }

    final existingServerId =
    _clean(
      sale.serverId,
    );

    if (existingServerId != null) {
      return;
    }

    // =========================================================================
    // WAREHOUSE
    // =========================================================================

    final warehouse =
    await (database.select(
      database.warehouses,
    )
      ..where(
            (table) =>
        table.id.equals(
          sale.warehouseId,
        ) &
        table.deletedAt.isNull(),
      ))
        .getSingleOrNull();

    if (warehouse == null) {
      throw StateError(
        'المخزن المرتبط بفاتورة '
            '"${sale.invoiceNumber}" غير موجود محلياً.',
      );
    }

    if (!warehouse.isActive) {
      throw StateError(
        'المخزن "${warehouse.name}" غير فعال.',
      );
    }

    final warehouseServerId =
    _clean(
      warehouse.serverId,
    );

    if (warehouseServerId == null) {
      throw StateError(
        'المخزن "${warehouse.name}" لم تتم مزامنته مع السيرفر بعد.',
      );
    }

    // =========================================================================
    // CUSTOMER
    // =========================================================================

    String? customerServerId;

    final customerLocalId =
    _clean(
      sale.customerId,
    );

    if (customerLocalId != null) {
      final customer =
      await (database.select(
        database.customers,
      )
        ..where(
              (table) =>
          table.id.equals(
            customerLocalId,
          ) &
          table.deletedAt.isNull(),
        ))
          .getSingleOrNull();

      if (customer == null) {
        throw StateError(
          'الزبون المرتبط بفاتورة '
              '"${sale.invoiceNumber}" غير موجود محلياً.',
        );
      }

      if (!customer.isActive) {
        throw StateError(
          'الزبون "${customer.name}" غير فعال.',
        );
      }

      customerServerId =
          _clean(
            customer.serverId,
          );

      if (customerServerId == null) {
        throw StateError(
          'الزبون "${customer.name}" لم تتم مزامنته مع السيرفر بعد.',
        );
      }
    }

    // =========================================================================
    // SALE ITEMS
    // =========================================================================

    final saleItems =
    await (database.select(
      database.saleItems,
    )
      ..where(
            (table) =>
            table.saleId.equals(
              saleId,
            ),
      ))
        .get();

    if (saleItems.isEmpty) {
      throw StateError(
        'فاتورة "${sale.invoiceNumber}" لا تحتوي على مواد.',
      );
    }

    // =========================================================================
    // PRICE TYPE
    // =========================================================================

    final priceTypes =
    saleItems
        .map(
          (item) =>
          item.priceType
              .trim()
              .toUpperCase(),
    )
        .where(
          (value) =>
      value.isNotEmpty,
    )
        .toSet();

    if (priceTypes.isEmpty) {
      throw StateError(
        'نوع سعر فاتورة "${sale.invoiceNumber}" غير محدد.',
      );
    }

    if (priceTypes.length > 1) {
      throw StateError(
        'فاتورة "${sale.invoiceNumber}" تحتوي على أكثر من مستوى سعر. '
            'Direct Sales API يتطلب مستوى سعر واحد للفاتورة بالكامل.',
      );
    }

    final priceType =
    _normalizePriceType(
      priceTypes.first,
    );

    // =========================================================================
    // API ITEMS
    // =========================================================================

    final apiItems =
    <Map<String, dynamic>>[];
    final holdKeys = <String>[];
    final deviceId = await FloorStore.deviceId(database);

    for (final item in saleItems) {
      final localVariantId =
      _clean(
        item.variantId,
      );

      if (localVariantId == null) {
        throw StateError(
          'المادة "${item.productNameSnapshot}" '
              'لا تحتوي على Variant محدد.',
        );
      }

      final unitId =
      _clean(
        item.unitId,
      );

      if (unitId == null) {
        throw StateError(
          'المادة "${item.productNameSnapshot}" '
              'لا تحتوي على Unit محددة.',
        );
      }

      // =======================================================================
      // VARIANT
      // =======================================================================

      final variant =
      await (database.select(
        database.productVariants,
      )
        ..where(
              (table) =>
          table.id.equals(
            localVariantId,
          ) &
          table.deletedAt.isNull(),
        ))
          .getSingleOrNull();

      if (variant == null) {
        throw StateError(
          'Variant المادة "${item.productNameSnapshot}" '
              'غير موجود محلياً.',
        );
      }

      if (!variant.isActive) {
        throw StateError(
          'Variant المادة "${item.productNameSnapshot}" غير فعال.',
        );
      }

      final variantServerId =
      _clean(
        variant.serverId,
      );

      if (variantServerId == null) {
        throw StateError(
          'Variant المادة "${item.productNameSnapshot}" '
              'لم تتم مزامنته مع السيرفر بعد.',
        );
      }
      holdKeys.add(FloorStore.holdKey(deviceId, variantServerId));

      // =======================================================================
      // UNIT
      // =======================================================================

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
          'وحدة المادة "${item.productNameSnapshot}" غير موجودة محلياً.',
        );
      }

      if (!unit.isActive) {
        throw StateError(
          'وحدة المادة "${item.productNameSnapshot}" غير فعالة.',
        );
      }

      if (item.quantity <= 0) {
        throw StateError(
          'كمية المادة "${item.productNameSnapshot}" غير صحيحة.',
        );
      }

      if (item.unitPrice < 0) {
        throw StateError(
          'سعر المادة "${item.productNameSnapshot}" غير صحيح.',
        );
      }

      if (item.discountPercent < 0 ||
          item.discountPercent > 100) {
        throw StateError(
          'نسبة خصم المادة "${item.productNameSnapshot}" غير صحيحة.',
        );
      }

      apiItems.add({
        'variant_id':
        variantServerId,
        'unit_id':
        unit.id,
        'quantity':
        item.quantity,
        'unit_price':
        item.unitPrice,
        'discount_percent':
        item.discountPercent,
      });
    }

    // =========================================================================
    // PAYMENT TYPE
    // =========================================================================

    final paymentType =
    _normalizePaymentType(
      sale.paymentType,
    );

    // =========================================================================
    // REQUEST
    // =========================================================================

    final payload =
    <String, dynamic>{
      'idempotency_key':
      saleId,
      'warehouse_id':
      warehouseServerId,
      'price_type':
      priceType,
      'payment_type':
      paymentType,
      'discount_amount':
      sale.discount,
      'paid_amount':
      sale.paidAmount,
      'items':
      apiItems,
      'hold_keys':
      holdKeys,
    };

    if (customerServerId != null) {
      payload['customer_id'] =
          customerServerId;
    }

    // =========================================================================
    // POST /direct-sales
    // =========================================================================

    final response =
    await apiClient.post(
      '/direct-sales',
      data: payload,
    );

    final responseData =
    _extractResponseMap(
      response.data,
    );

    final serverId =
    _extractString(
      responseData,
      const [
        'id',
        'sale_id',
      ],
    );

    if (serverId == null) {
      throw StateError(
        'تم إرسال فاتورة البيع إلى السيرفر لكن الاستجابة '
            'لم تحتوي على معرف الفاتورة.',
      );
    }

    final serverInvoiceNumber =
    _extractString(
      responseData,
      const [
        'invoice_number',
        'invoiceNumber',
        'number',
      ],
    );

    final serverVersion =
    _extractInt(
      responseData,
      const [
        'version',
        'server_version',
        'serverVersion',
      ],
    );

    // =========================================================================
    // SAVE SERVER MAPPING
    // =========================================================================

    await (database.update(
      database.sales,
    )
      ..where(
            (table) =>
            table.id.equals(
              saleId,
            ),
      ))
        .write(
      SalesCompanion(
        serverId:
        Value(
          serverId,
        ),
        invoiceNumber:
        serverInvoiceNumber != null
            ? Value(
          serverInvoiceNumber,
        )
            : const Value.absent(),
        serverVersion:
        serverVersion != null
            ? Value(
          serverVersion,
        )
            : const Value.absent(),
        updatedAt:
        Value(
          DateTime.now(),
        ),
      ),
    );

    debugPrint(
      '[DIRECT SALE PUSH] Sale created: '
          'local=$saleId server=$serverId '
          'invoice=${serverInvoiceNumber ?? sale.invoiceNumber}',
    );
  }

  // ===========================================================================
  // PULL
  // ===========================================================================

  @override
  Future<SyncPullResult> pullChanges({
    String? cursor,
  }) async {
    debugPrint(
      '[DIRECT SALE PULL] ========================================',
    );

    debugPrint(
      '[DIRECT SALE PULL] Starting direct sales pull...',
    );

    int page = 1;
    const int limit = 100;

    int totalPages = 1;
    int totalPulled = 0;

    do {
      debugPrint(
        '[DIRECT SALE PULL] GET /direct-sales?page=$page&limit=$limit',
      );

      final response =
      await apiClient.get(
        '/direct-sales?page=$page&limit=$limit',
      );

      final root =
      _asMap(
        response.data,
      );

      if (root == null) {
        throw StateError(
          'GET /direct-sales returned invalid response.',
        );
      }

      if (root['success'] == false) {
        throw StateError(
          'GET /direct-sales returned success=false.',
        );
      }

      final list =
      _extractList(
        root['data'],
      );

      final meta =
      _asMap(
        root['meta'],
      );

      totalPages =
          _readInt(
            meta?['totalPages'],
          ) ??
              1;

      debugPrint(
        '[DIRECT SALE PULL] Page $page/$totalPages - '
            '${list.length} sale(s).',
      );

      for (final summaryRaw in list) {
        final summary =
        _asMap(
          summaryRaw,
        );

        if (summary == null) {
          continue;
        }

        final serverId =
        _extractString(
          summary,
          const [
            'id',
          ],
        );

        if (serverId == null) {
          continue;
        }

        await _pullSaleDetail(
          serverId,
          summary: summary,
        );

        totalPulled++;
      }

      page++;
    } while (page <= totalPages);

    debugPrint(
      '[DIRECT SALE PULL] Pulled $totalPulled sale(s).',
    );

    debugPrint(
      '[DIRECT SALE PULL] ========================================',
    );

    return SyncPullResult(
      nextCursor:
      cursor,
      changes:
      const [],
    );
  }

  // ===========================================================================
  // PULL SINGLE SALE
  // ===========================================================================

  Future<void> _pullSaleDetail(
      String serverId, {
        required Map<String, dynamic> summary,
      }) async {
    debugPrint(
      '[DIRECT SALE PULL] GET /direct-sales/$serverId',
    );

    final response =
    await apiClient.get(
      '/direct-sales/$serverId',
    );

    final root =
    _asMap(
      response.data,
    );

    if (root == null) {
      throw StateError(
        'Invalid Direct Sale detail response: $serverId',
      );
    }

    if (root['success'] == false) {
      throw StateError(
        'Direct Sale detail returned success=false: $serverId',
      );
    }

    final data =
    _asMap(
      root['data'],
    );

    if (data == null) {
      throw StateError(
        'Direct Sale detail data is missing: $serverId',
      );
    }

    await database.transaction(
          () async {
        // =====================================================================
        // LOCAL SALE ID
        // =====================================================================

        final existingSale =
        await (database.select(
          database.sales,
        )
          ..where(
                (table) =>
                table.serverId.equals(
                  serverId,
                ),
          ))
            .getSingleOrNull();

        final localSaleId =
            existingSale?.id ??
                _uuid.v4();

        // =====================================================================
        // WAREHOUSE
        // =====================================================================

        final warehouseServerId =
        _extractString(
          data,
          const [
            'warehouse_id',
          ],
        );

        final warehouseMap =
        _asMap(
          data['warehouses'],
        );

        final warehouseName =
            _extractString(
              warehouseMap ??
                  const {},
              const [
                'name',
              ],
            ) ??
                _extractString(
                  summary,
                  const [
                    'warehouse_name',
                  ],
                ) ??
                'مخزن';

        String? localWarehouseId;

        if (warehouseServerId != null) {
          final warehouse =
          await (database.select(
            database.warehouses,
          )
            ..where(
                  (table) =>
                  table.serverId.equals(
                    warehouseServerId,
                  ),
            ))
              .getSingleOrNull();

          localWarehouseId =
              warehouse?.id;
        }

        if (localWarehouseId == null) {
          debugPrint(
            '[DIRECT SALE PULL] Skipped sale $serverId: '
                'warehouse mapping not found.',
          );

          return;
        }

        // =====================================================================
        // CUSTOMER
        // =====================================================================

        final customerServerId =
        _extractString(
          data,
          const [
            'customer_id',
          ],
        );

        String? localCustomerId;

        if (customerServerId != null) {
          final customer =
          await (database.select(
            database.customers,
          )
            ..where(
                  (table) =>
                  table.serverId.equals(
                    customerServerId,
                  ),
            ))
              .getSingleOrNull();

          localCustomerId =
              customer?.id;
        }

        final customersMap =
        _asMap(
          data['customers'],
        );

        final customerName =
            _extractString(
              customersMap ??
                  const {},
              const [
                'name',
                'customer_name',
              ],
            ) ??
                _extractString(
                  summary,
                  const [
                    'customer_name',
                  ],
                ) ??
                'زبون نقدي عام';

        // =====================================================================
        // HEADER VALUES
        // =====================================================================

        final invoiceNumber =
            _extractString(
              data,
              const [
                'invoice_number',
              ],
            ) ??
                _extractString(
                  summary,
                  const [
                    'invoice_number',
                  ],
                ) ??
                'INV-$serverId';

        final paymentType =
        _normalizePaymentType(
          _extractString(
            data,
            const [
              'payment_type',
            ],
          ) ??
              'CASH',
        );

        final subtotal =
            _readDouble(
              data['subtotal'],
            ) ??
                _readDouble(
                  summary['total'],
                ) ??
                0.0;

        final discount =
            _readDouble(
              data['discount_amount'],
            ) ??
                0.0;

        final total =
            _readDouble(
              data['total'],
            ) ??
                _readDouble(
                  summary['total'],
                ) ??
                0.0;

        final paidAmount =
            _readDouble(
              data['paid_amount'],
            ) ??
                _readDouble(
                  summary['paid_amount'],
                ) ??
                0.0;

        final remainingAmount =
            _readDouble(
              data['due_amount'],
            ) ??
                _readDouble(
                  summary['due_amount'],
                ) ??
                0.0;

        final serverVersion =
            _readInt(
              data['version'],
            ) ??
                0;

        final createdAt =
            _readDate(
              data['created_at'],
            ) ??
                _readDate(
                  data['invoice_date'],
                ) ??
                _readDate(
                  summary['created_at'],
                ) ??
                DateTime.now();

        final updatedAt =
            _readDate(
              data['updated_at'],
            ) ??
                createdAt;

        // =====================================================================
        // UPSERT SALE
        // =====================================================================

        if (existingSale == null) {
          await database
              .into(
            database.sales,
          )
              .insert(
            SalesCompanion.insert(
              id:
              localSaleId,
              serverId:
              Value(
                serverId,
              ),
              invoiceNumber:
              invoiceNumber,
              warehouseId:
              localWarehouseId,
              warehouseNameSnapshot:
              warehouseName,
              customerId:
              Value(
                localCustomerId,
              ),
              customerName:
              customerName,
              representativeId:
              const Value.absent(),
              representativeNameSnapshot:
              const Value.absent(),
              commissionPercentageSnapshot:
              const Value.absent(),
              commissionAmount:
              const Value(
                0.0,
              ),
              subtotal:
              subtotal,
              discount:
              Value(
                discount,
              ),
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
              paymentType,
              serverVersion:
              Value(
                serverVersion,
              ),
              createdAt:
              createdAt,
              updatedAt:
              updatedAt,
            ),
          );
        } else {
          await (database.update(
            database.sales,
          )
            ..where(
                  (table) =>
                  table.id.equals(
                    localSaleId,
                  ),
            ))
              .write(
            SalesCompanion(
              serverId:
              Value(
                serverId,
              ),
              invoiceNumber:
              Value(
                invoiceNumber,
              ),
              warehouseId:
              Value(
                localWarehouseId,
              ),
              warehouseNameSnapshot:
              Value(
                warehouseName,
              ),
              customerId:
              Value(
                localCustomerId,
              ),
              customerName:
              Value(
                customerName,
              ),
              subtotal:
              Value(
                subtotal,
              ),
              discount:
              Value(
                discount,
              ),
              total:
              Value(
                total,
              ),
              paidAmount:
              Value(
                paidAmount,
              ),
              remainingAmount:
              Value(
                remainingAmount,
              ),
              paymentType:
              Value(
                paymentType,
              ),
              serverVersion:
              Value(
                serverVersion,
              ),
              updatedAt:
              Value(
                updatedAt,
              ),
            ),
          );
        }

        // =====================================================================
        // ITEMS
        // =====================================================================

        final remoteItems =
        _extractList(
          data['sales_invoice_items'],
        );

        // بما أن detail هو snapshot رسمي للفاتورة،
        // نحذف المواد المحلية للفاتورة ونبنيها من السيرفر.
        await (database.delete(
          database.saleItems,
        )
          ..where(
                (table) =>
                table.saleId.equals(
                  localSaleId,
                ),
          ))
            .go();

        for (final itemRaw
        in remoteItems) {
          final item =
          _asMap(
            itemRaw,
          );

          if (item == null) {
            continue;
          }

          final variantServerId =
          _extractString(
            item,
            const [
              'variant_id',
            ],
          );

          if (variantServerId == null) {
            continue;
          }

          final variant =
          await (database.select(
            database.productVariants,
          )
            ..where(
                  (table) =>
                  table.serverId.equals(
                    variantServerId,
                  ),
            ))
              .getSingleOrNull();

          if (variant == null) {
            debugPrint(
              '[DIRECT SALE PULL] Item skipped: '
                  'variant mapping missing $variantServerId',
            );

            continue;
          }

          final product =
          await (database.select(
            database.products,
          )
            ..where(
                  (table) =>
                  table.id.equals(
                    variant.productId,
                  ),
            ))
              .getSingleOrNull();

          if (product == null) {
            continue;
          }

          final remoteVariantMap =
          _asMap(
            item['product_variants'],
          );

          final remoteProductMap =
          _asMap(
            remoteVariantMap?['products'],
          );

          final productName =
              _extractString(
                remoteProductMap ??
                    const {},
                const [
                  'name_ar',
                  'name',
                ],
              ) ??
                  product.name;

          final barcode =
              _extractString(
                remoteVariantMap ??
                    const {},
                const [
                  'barcode',
                ],
              ) ??
                  product.barcode;

          final unitId =
          _extractString(
            item,
            const [
              'unit_id',
            ],
          );

          final quantity =
              _readDouble(
                item['quantity'],
              ) ??
                  0.0;

          final unitPrice =
              _readDouble(
                item['unit_price'],
              ) ??
                  0.0;

          final discountPercent =
              _readDouble(
                item['discount_percent'],
              ) ??
                  0.0;

          final totalPrice =
              _readDouble(
                item['total_price'],
              ) ??
                  (quantity *
                      unitPrice *
                      (1 -
                          discountPercent /
                              100.0));

          final priceType =
          _normalizePriceType(
            _extractString(
              data,
              const [
                'price_type',
              ],
            ) ??
                'RETAIL',
          );

          final remoteItemId =
          _extractString(
            item,
            const [
              'id',
            ],
          );

          await database
              .into(
            database.saleItems,
          )
              .insert(
            SaleItemsCompanion.insert(
              id:
              remoteItemId ??
                  _uuid.v4(),
              saleId:
              localSaleId,
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
              productName,
              barcodeSnapshot:
              Value(
                barcode,
              ),
              priceType:
              priceType,
              quantity:
              quantity,
              unitPrice:
              unitPrice,
              discountPercent:
              Value(
                discountPercent,
              ),
              total:
              totalPrice,
              createdAt:
              createdAt,
            ),
          );
        }

        debugPrint(
          '[DIRECT SALE PULL] Reconciled: '
              'local=$localSaleId '
              'server=$serverId '
              'invoice=$invoiceNumber '
              'items=${remoteItems.length}',
        );
      },
    );
  }

  // ===========================================================================
  // ENUM NORMALIZATION
  // ===========================================================================

  String _normalizePriceType(
      String value,
      ) {
    switch (value
        .trim()
        .toUpperCase()) {
      case 'RETAIL':
        return 'RETAIL';

      case 'WHOLESALE':
        return 'WHOLESALE';

      case 'REP':
        return 'REP';

      case 'REPRESENTATIVE':
        return 'REP';

      case 'COST':
        return 'COST';

      default:
        throw StateError(
          'نوع السعر غير مدعوم في Direct Sales: $value',
        );
    }
  }

  String _normalizePaymentType(
      String value,
      ) {
    switch (value
        .trim()
        .toUpperCase()) {
      case 'CASH':
        return 'CASH';

      case 'CREDIT':
        return 'CREDIT';

      case 'PARTIAL':
        return 'PARTIAL';

      case 'REP_CUSTODY':
        return 'REP_CUSTODY';

      default:
        throw StateError(
          'نوع الدفع غير مدعوم في Direct Sales: $value',
        );
    }
  }

  // ===========================================================================
  // RESPONSE HELPERS
  // ===========================================================================

  Map<String, dynamic> _extractResponseMap(
      dynamic raw,
      ) {
    final map =
    _asMap(
      raw,
    );

    if (map == null) {
      return const {};
    }

    final nestedData =
    _asMap(
      map['data'],
    );

    if (nestedData != null) {
      return nestedData;
    }

    return map;
  }

  List<dynamic> _extractList(
      dynamic raw,
      ) {
    if (raw is List) {
      return raw;
    }

    final map =
    _asMap(
      raw,
    );

    if (map == null) {
      return const [];
    }

    const possibleKeys = [
      'items',
      'sales',
      'results',
      'data',
    ];

    for (final key in possibleKeys) {
      final value =
      map[key];

      if (value is List) {
        return value;
      }
    }

    return const [];
  }

  Map<String, dynamic>? _asMap(
      dynamic raw,
      ) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }

    if (raw is Map) {
      return Map<String, dynamic>.from(
        raw,
      );
    }

    return null;
  }

  String? _extractString(
      Map<String, dynamic> map,
      List<String> keys,
      ) {
    for (final key in keys) {
      final value =
      map[key];

      if (value == null) {
        continue;
      }

      final clean =
      value
          .toString()
          .trim();

      if (clean.isNotEmpty &&
          clean.toLowerCase() !=
              'null') {
        return clean;
      }
    }

    return null;
  }

  int? _extractInt(
      Map<String, dynamic> map,
      List<String> keys,
      ) {
    for (final key in keys) {
      final parsed =
      _readInt(
        map[key],
      );

      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  int? _readInt(
      dynamic value,
      ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value != null) {
      return int.tryParse(
        value.toString(),
      );
    }

    return null;
  }

  double? _readDouble(
      dynamic value,
      ) {
    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value != null) {
      return double.tryParse(
        value.toString(),
      );
    }

    return null;
  }

  DateTime? _readDate(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    )?.toLocal();
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