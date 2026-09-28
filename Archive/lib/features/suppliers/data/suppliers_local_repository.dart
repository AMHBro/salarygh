import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/party_balance.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../models/supplier_model.dart';

class SuppliersLocalRepository {
  final AppDatabase database;
  final SyncQueueRepository syncQueue;

  static const Uuid _uuid = Uuid();

  SuppliersLocalRepository({
    required this.database,
    required this.syncQueue,
  });

  // ===========================================================================
  // GET SUPPLIERS
  // ===========================================================================

  Future<List<SupplierModel>> getSuppliers() async {
    final supplierRows = await (
        database.select(database.suppliers)
          ..where(
                (table) => table.deletedAt.isNull(),
          )
          ..orderBy([
                (table) => OrderingTerm.asc(
              table.name,
            ),
          ])
    ).get();

    final ledgerRows = await (
        database.select(
          database.supplierLedgerEntries,
        )
          ..orderBy([
                (table) => OrderingTerm.asc(
              table.createdAt,
            ),
          ])
    ).get();

    final Map<String, List<SupplierLedgerEntry>>
    ledgerBySupplier = {};

    for (final ledger in ledgerRows) {
      ledgerBySupplier
          .putIfAbsent(
        ledger.supplierId,
            () => [],
      )
          .add(ledger);
    }

    return supplierRows.map(
          (row) => _toSupplierModel(
        row,
        ledgerBySupplier[row.id] ?? const <SupplierLedgerEntry>[],
      ),
    ).toList();
  }

  SupplierModel _toSupplierModel(
    Supplier row,
    List<SupplierLedgerEntry> entries,
  ) {
        double totalPurchases = 0;
        double totalPaid = 0;
        double purchasesUsd = 0;
        double paidUsd = 0;

        DateTime? lastPurchaseDate;

        final purchaseReferences =
        <String>{};

        for (final entry in entries) {
          final inDollars = entry.currency == 'USD';
          switch (entry.type) {
            case 'PURCHASE':
              if (inDollars) {
                purchasesUsd += entry.amount;
              } else {
                totalPurchases += entry.amount;
              }

              final referenceId =
                  entry.referenceId;

              if (referenceId != null &&
                  referenceId.isNotEmpty) {
                purchaseReferences.add(
                  referenceId,
                );
              }

              if (lastPurchaseDate == null ||
                  entry.createdAt.isAfter(
                    lastPurchaseDate,
                  )) {
                lastPurchaseDate =
                    entry.createdAt;
              }

              break;

            case 'OPENING_BALANCE':
              if (inDollars) {
                purchasesUsd += entry.amount;
              } else {
                totalPurchases += entry.amount;
              }
              break;

            case 'PAYMENT':
            case 'RECEIPT':
              if (inDollars) {
                paidUsd += entry.amount;
              } else {
                totalPaid += entry.amount;
              }
              break;
          }
        }

        final balance =
            totalPurchases - totalPaid;
        final balanceUsd = purchasesUsd - paidUsd;

        return SupplierModel(
          id: row.id,
          serverId: row.serverId,
          name: row.name,
          phone: row.phone,
          email: row.email,
          address: row.address,
          taxNumber: row.taxNumber,
          creditLimit: row.creditLimit,
          notes: row.notes,
          totalPurchases:
          totalPurchases,
          totalPaid: totalPaid,
          balance:
          balance,
          balanceUsd: balanceUsd,
          invoicesCount:
          purchaseReferences.length,
          lastPurchaseDate:
          lastPurchaseDate,
          isActive: row.isActive,
          serverVersion:
          row.serverVersion,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
        );
  }

  Future<ListPage<SupplierModel>> pageSuppliers({
    int offset = 0,
    int limit = kListPageSize,
    String search = '',
  }) async {
    final query = search.trim();
    final like = '%$query%';
    const where = '''
s.deleted_at IS NULL AND s.is_active = 1
AND (? = '' OR s.name LIKE ? OR s.phone LIKE ? OR s.address LIKE ?)
''';
    final variables = [
      Variable.withString(query),
      Variable.withString(like),
      Variable.withString(like),
      Variable.withString(like),
    ];
    final reads = {database.suppliers};
    final total = (await database.customSelect(
      'SELECT COUNT(*) AS n FROM suppliers s WHERE $where',
      variables: variables,
      readsFrom: reads,
    ).getSingle()).read<int>('n');
    final idRows = await database.customSelect(
      'SELECT s.id AS id FROM suppliers s WHERE $where ORDER BY s.name LIMIT ? OFFSET ?',
      variables: [
        ...variables,
        Variable.withInt(limit),
        Variable.withInt(offset),
      ],
      readsFrom: reads,
    ).get();
    final ids = [for (final row in idRows) row.read<String>('id')];
    if (ids.isEmpty) {
      return ListPage(items: const [], total: total);
    }
    final rows = await (database.select(database.suppliers)
          ..where((table) => table.id.isIn(ids)))
        .get();
    final byId = {for (final row in rows) row.id: row};
    final ledgerRows = await (database.select(database.supplierLedgerEntries)
          ..where((table) => table.supplierId.isIn(ids)))
        .get();
    final ledgerBySupplier = <String, List<SupplierLedgerEntry>>{};
    for (final entry in ledgerRows) {
      ledgerBySupplier.putIfAbsent(entry.supplierId, () => []).add(entry);
    }
    return ListPage(
      items: [
        for (final id in ids)
          if (byId[id] != null)
            _toSupplierModel(byId[id]!, ledgerBySupplier[id] ?? const []),
      ],
      total: total,
    );
  }

  Future<({int count, double purchases, double balance, int withBalance})>
      supplierDirectoryStats() async {
    final row = await database.customSelect(
      '''
SELECT
  COUNT(*) AS suppliers,
  SUM(CASE WHEN IFNULL(b.balance, 0) > 0 OR IFNULL(b.balance_usd, 0) > 0 THEN 1 ELSE 0 END) AS with_balance,
  SUM(IFNULL(b.balance, 0)) AS balance,
  SUM(IFNULL(b.purchases, 0)) AS purchases
FROM suppliers s
LEFT JOIN (
  SELECT supplier_id,
    SUM(CASE
      WHEN type IN ('PURCHASE', 'OPENING_BALANCE')
        AND IFNULL(currency, 'IQD') != 'USD' THEN ABS(amount)
      ELSE 0 END) AS purchases,
    SUM(CASE
      WHEN type IN ('PURCHASE', 'OPENING_BALANCE')
        AND IFNULL(currency, 'IQD') != 'USD' THEN ABS(amount)
      WHEN type IN ('PAYMENT', 'RECEIPT')
        AND IFNULL(currency, 'IQD') != 'USD' THEN -ABS(amount)
      ELSE 0 END) AS balance,
    SUM(CASE
      WHEN type IN ('PURCHASE', 'OPENING_BALANCE') AND currency = 'USD' THEN ABS(amount)
      WHEN type IN ('PAYMENT', 'RECEIPT') AND currency = 'USD' THEN -ABS(amount)
      ELSE 0 END) AS balance_usd
  FROM supplier_ledger_entries
  GROUP BY supplier_id
) b ON b.supplier_id = s.id
WHERE s.deleted_at IS NULL AND s.is_active = 1
''',
      readsFrom: {database.suppliers, database.supplierLedgerEntries},
    ).getSingle();
    return (
      count: sqlInt(row, 'suppliers'),
      purchases: sqlDouble(row, 'purchases'),
      balance: sqlDouble(row, 'balance'),
      withBalance: sqlInt(row, 'with_balance'),
    );
  }

  // ===========================================================================
  // GET BY LOCAL ID
  // ===========================================================================

  Future<SupplierModel?>
  getSupplierById(
      String id,
      ) async {
    final row = await (database.select(database.suppliers)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final entries = await (database.select(database.supplierLedgerEntries)
          ..where((table) => table.supplierId.equals(id)))
        .get();
    return _toSupplierModel(row, entries);
  }

  // ===========================================================================
  // CREATE
  // ===========================================================================

  Future<SupplierModel>
  createSupplier({
    required String name,
    String phone = '',
    String email = '',
    String address = '',
    String taxNumber = '',
    double creditLimit = 0,
    String? notes,
  }) async {
    final cleanName =
    name.trim();

    if (cleanName.isEmpty) {
      throw StateError(
        'اسم المورد مطلوب.',
      );
    }

    if (creditLimit < 0) {
      throw StateError(
        'الحد الائتماني لا يمكن أن يكون سالباً.',
      );
    }

    final now = DateTime.now();

    final supplier =
    SupplierModel(
      id: _uuid.v4(),
      serverId: null,
      name: cleanName,
      phone: phone.trim(),
      email: email.trim(),
      address: address.trim(),
      taxNumber:
      taxNumber.trim(),
      creditLimit:
      creditLimit,
      notes: _clean(notes),
      isActive: true,
      serverVersion: 0,
      createdAt: now,
      updatedAt: now,
    );

    await database.transaction(
          () async {
        await database
            .into(
          database.suppliers,
        )
            .insert(
          SuppliersCompanion.insert(
            id: supplier.id,
            serverId:
            const Value(null),
            name: supplier.name,
            phone: Value(
              supplier.phone,
            ),
            email: Value(
              supplier.email,
            ),
            address: Value(
              supplier.address,
            ),
            taxNumber: Value(
              supplier.taxNumber,
            ),
            creditLimit: Value(
              supplier.creditLimit,
            ),
            notes: Value(
              supplier.notes,
            ),
            isActive:
            const Value(true),
            serverVersion:
            const Value(0),
            createdAt: now,
            updatedAt: now,
          ),
        );

        await syncQueue.enqueue(
          entityType: 'supplier',
          entityId: supplier.id,
          operation:
          SyncOperation.create,
          idempotencyKey:
          supplier.id,
          payload:
          supplier.toSyncJson(),
        );
      },
    );

    return supplier;
  }

  // ===========================================================================
  // UPDATE
  // ===========================================================================

  Future<SupplierModel>
  updateSupplier(
      SupplierModel supplier, {
        required String name,
        String phone = '',
        String? email,
        String address = '',
        String? taxNumber,
        double? creditLimit,
        String? notes,
      }) async {
    final cleanName =
    name.trim();

    if (cleanName.isEmpty) {
      throw StateError(
        'اسم المورد مطلوب.',
      );
    }

    final finalCreditLimit =
        creditLimit ??
            supplier.creditLimit;

    if (finalCreditLimit < 0) {
      throw StateError(
        'الحد الائتماني لا يمكن أن يكون سالباً.',
      );
    }

    final now = DateTime.now();

    final updated =
    supplier.copyWith(
      name: cleanName,
      phone: phone.trim(),
      email:
      email?.trim() ??
          supplier.email,
      address:
      address.trim(),
      taxNumber:
      taxNumber?.trim() ??
          supplier.taxNumber,
      creditLimit:
      finalCreditLimit,
      notes: _clean(notes),
      clearNotes:
      _clean(notes) == null,
      updatedAt: now,
    );

    await database.transaction(
          () async {
        final affected = await (
            database.update(
              database.suppliers,
            )
              ..where(
                    (table) =>
                    table.id.equals(
                      supplier.id,
                    ),
              )
        ).write(
          SuppliersCompanion(
            name: Value(
              updated.name,
            ),
            phone: Value(
              updated.phone,
            ),
            email: Value(
              updated.email,
            ),
            address: Value(
              updated.address,
            ),
            taxNumber: Value(
              updated.taxNumber,
            ),
            creditLimit: Value(
              updated.creditLimit,
            ),
            notes: Value(
              updated.notes,
            ),
            updatedAt:
            Value(now),
          ),
        );

        if (affected == 0) {
          throw StateError(
            'المورد غير موجود.',
          );
        }

        await syncQueue.enqueue(
          entityType: 'supplier',
          entityId: supplier.id,
          operation:
          SyncOperation.update,
          payload:
          updated.toSyncJson(),
        );
      },
    );

    return updated;
  }

  // ===========================================================================
  // REGISTER PAYMENT
  // ===========================================================================

  Future<String> registerPayment({
    required String supplierId,
    required double amount,
    String method = 'CASH',
    String? note,
    String? userId,
    String currency = 'IQD',
    double exchangeRate = 0,
  }) async {
    final posted = nativeLedgerAmount(
      amount: amount,
      currency: currency,
    );
    amount = posted.amount;
    final ledgerCurrency = posted.currency;
    if (amount <= 0) {
      throw StateError(
        'مبلغ الدفعة يجب أن يكون أكبر من صفر.',
      );
    }

    final cleanMethod =
    _normalizePaymentMethod(
      method,
    );

    final now = DateTime.now();

    final paymentId =
    _uuid.v4();

    final ledgerId =
    _uuid.v4();

    final voucherNumber =
    _voucherNumber(
      paymentId,
      now,
    );

    await database.transaction(
          () async {
        final supplier = await (
            database.select(
              database.suppliers,
            )
              ..where(
                    (table) =>
                    table.id.equals(
                      supplierId,
                    ),
              )
        ).getSingleOrNull();

        if (supplier == null ||
            supplier.deletedAt !=
                null) {
          throw StateError(
            'المورد غير موجود.',
          );
        }

        if (!supplier.isActive) {
          throw StateError(
            'المورد غير فعال.',
          );
        }

        // -------------------------------------------------------------------
        // 1. Local supplier payment
        // -------------------------------------------------------------------

        await database
            .into(
          database.supplierPayments,
        )
            .insert(
          SupplierPaymentsCompanion
              .insert(
            id: paymentId,
            voucherNumber:
            voucherNumber,
            supplierId:
            supplierId,
            method: Value(
              cleanMethod,
            ),
            amount: amount,
            currency: Value(ledgerCurrency),
            note: Value(
              _clean(note),
            ),
            userId: Value(
              _clean(userId),
            ),
            serverVersion:
            const Value(0),
            createdAt: now,
          ),
        );

        // -------------------------------------------------------------------
        // 2. Local ledger
        //
        // هذا السجل محلي حتى يتحدث رصيد المورد فوراً أثناء Offline.
        //
        // لا ننشئ له Outbox منفصل لأن endpoint:
        //
        // POST /supplier-payments
        //
        // هو المسؤول على السيرفر عن تسجيل السداد وتخفيض ذمة المورد.
        // -------------------------------------------------------------------

        await database
            .into(
          database
              .supplierLedgerEntries,
        )
            .insert(
          SupplierLedgerEntriesCompanion
              .insert(
            id: ledgerId,
            supplierId:
            supplierId,
            type: 'PAYMENT',
            amount: amount,
            currency: Value(ledgerCurrency),
            referenceType:
            const Value(
              'SUPPLIER_PAYMENT',
            ),
            referenceId:
            Value(paymentId),
            note: Value(
              _clean(note),
            ),
            userId: Value(
              _clean(userId),
            ),
            serverVersion:
            const Value(0),
            createdAt: now,
          ),
        );

        // -------------------------------------------------------------------
        // 3. Exactly one remote side-effect operation
        // -------------------------------------------------------------------

        await syncQueue.enqueue(
          entityType:
          'supplier_payment',
          entityId: paymentId,
          operation:
          SyncOperation.create,
          idempotencyKey:
          paymentId,
          payload: {
            'local_supplier_id':
            supplierId,
            'voucher_number':
            voucherNumber,
            'amount': amount,
            'payment_method':
            cleanMethod,
            'notes':
            _clean(note),
            'created_at': now
                .toUtc()
                .toIso8601String(),
          },
        );
        await syncQueue.enqueue(
          entityType: 'floor_notice',
          entityId: paymentId,
          operation: SyncOperation.create,
          idempotencyKey: 'floor-supplier-$paymentId',
          payload: {'kind': 'supplier_payment'},
        );
      },
    );

    return voucherNumber;
  }

  Future<String> registerReceipt({
    required String supplierId,
    required double amount,
    String method = 'CASH',
    String? note,
    String? userId,
    String currency = 'IQD',
    double exchangeRate = 0,
  }) {
    final posted = nativeLedgerAmount(
      amount: amount,
      currency: currency,
    );
    return _insertSupplierMovement(
      supplierId: supplierId,
      amount: posted.amount,
      movementCurrency: posted.currency,
      method: method,
      note: note,
      userId: userId,
      ledgerType: 'RECEIPT',
      referenceType: 'RECEIPT',
    );
  }

  Future<String> _insertSupplierMovement({
    required String supplierId,
    required double amount,
    required String method,
    required String ledgerType,
    required String referenceType,
    String movementCurrency = 'IQD',
    String? note,
    String? userId,
  }) async {
    if (amount <= 0) {
      throw StateError(
        'مبلغ الدفعة يجب أن يكون أكبر من صفر.',
      );
    }

    final cleanMethod = _normalizePaymentMethod(method);
    final now = DateTime.now();
    final paymentId = _uuid.v4();
    final ledgerId = _uuid.v4();
    final voucherNumber = _voucherNumber(paymentId, now);

    await database.transaction(() async {
      final supplier = await (database.select(database.suppliers)
            ..where((table) => table.id.equals(supplierId)))
          .getSingleOrNull();

      if (supplier == null || supplier.deletedAt != null) {
        throw StateError('الشركة غير موجودة.');
      }

      if (!supplier.isActive) {
        throw StateError('الشركة غير فعالة.');
      }

      await database.into(database.supplierPayments).insert(
            SupplierPaymentsCompanion.insert(
              id: paymentId,
              voucherNumber: voucherNumber,
              supplierId: supplierId,
              method: Value(cleanMethod),
              amount: amount,
              currency: Value(movementCurrency),
              referenceType: Value(referenceType),
              note: Value(_clean(note)),
              userId: Value(_clean(userId)),
              serverVersion: const Value(0),
              createdAt: now,
            ),
          );

      await database.into(database.supplierLedgerEntries).insert(
            SupplierLedgerEntriesCompanion.insert(
              id: ledgerId,
              supplierId: supplierId,
              type: ledgerType,
              amount: amount,
              currency: Value(movementCurrency),
              referenceType: Value(referenceType),
              referenceId: Value(paymentId),
              note: Value(_clean(note)),
              userId: Value(_clean(userId)),
              serverVersion: const Value(0),
              createdAt: now,
            ),
          );
    });

    return voucherNumber;
  }

  Future<VoucherSnapshot?> snapshotForPayment(String paymentId) async {
    final payment = await (database.select(database.supplierPayments)
          ..where((table) => table.id.equals(paymentId)))
        .getSingleOrNull();
    if (payment == null) {
      return null;
    }
    final rows = await (database.select(database.supplierLedgerEntries)
          ..where((table) => table.supplierId.equals(payment.supplierId)))
        .get();
    return voucherSnapshot(
      lines: [
        for (final row in rows)
          LedgerLine(
            id: row.id,
            type: row.type,
            referenceId: row.referenceId,
            createdAt: row.createdAt,
            amount: Money.parse(row.amount),
            currency: row.currency,
          ),
      ],
      referenceId: paymentId,
      effectOf: supplierLedgerEffect,
    );
  }

  // ===========================================================================
  // PAYMENT METHOD
  // ===========================================================================

  String _normalizePaymentMethod(
      String value,
      ) {
    switch (
    value.trim().toUpperCase()) {
      case 'CASH':
        return 'CASH';

      case 'BANK_TRANSFER':
      case 'BANK':
        return 'BANK_TRANSFER';

      case 'CHECK':
        return 'CHECK';

      case 'POS_MACHINE':
      case 'POS':
        return 'POS_MACHINE';

    // دعم البيانات القديمة التي كانت تستخدم OTHER.
    //
    // لا نرسل OTHER إلى الـBackend لأنه ليس ضمن الـenum
    // المسموح في CreateSupplierPaymentDto.
      case 'OTHER':
        return 'CASH';

      default:
        throw StateError(
          'طريقة الدفع غير مدعومة: $value',
        );
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _voucherNumber(
      String paymentId,
      DateTime date,
      ) {
    final suffix = paymentId
        .replaceAll('-', '')
        .substring(0, 6)
        .toUpperCase();

    return 'PAY-${date.millisecondsSinceEpoch}-$suffix';
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