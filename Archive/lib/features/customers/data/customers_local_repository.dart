import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/money/party_balance.dart';
import '../../../core/paging/list_page.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../models/customer_model.dart';

class CustomersLocalRepository {
  final AppDatabase database;
  final SyncQueueRepository syncQueue;

  static const Uuid _uuid = Uuid();

  CustomersLocalRepository({
    required this.database,
    required this.syncQueue,
  });

  // ===========================================================================
  // GET CUSTOMERS
  // ===========================================================================

  Future<List<CustomerModel>>
  getCustomers() async {
    final customerRows =
    await (database.select(
      database.customers,
    )
      ..where(
            (table) =>
            table.deletedAt.isNull(),
      )
      ..orderBy([
            (table) =>
            OrderingTerm.asc(
              table.name,
            ),
      ]))
        .get();

    final ledgerRows =
    await (database.select(
      database.customerLedgerEntries,
    )
      ..orderBy([
            (table) =>
            OrderingTerm.asc(
              table.createdAt,
            ),
      ]))
        .get();

    final Map<
        String,
        List<CustomerLedgerEntry>
    >
    ledgerByCustomer = {};

    for (final ledger in ledgerRows) {
      ledgerByCustomer
          .putIfAbsent(
        ledger.customerId,
            () => [],
      )
          .add(ledger);
    }

    return customerRows.map(
          (row) => _toCustomerModel(
        row,
        ledgerByCustomer[row.id] ??
            const <CustomerLedgerEntry>[],
      ),
    ).toList();
  }

  CustomerModel _toCustomerModel(
    Customer row,
    List<CustomerLedgerEntry> entries,
  ) {
        var totalPurchases = Money.zero;
        var totalPaid = Money.zero;
        var purchasesUsd = Money.zero;
        var paidUsd = Money.zero;

        DateTime? lastPurchaseDate;

        final saleReferences =
        <String>{};

        for (final entry in entries) {
          final amount = Money.parse(entry.amount);
          final inDollars = entry.currency == 'USD';
          switch (entry.type) {
            case 'SALE':
              if (inDollars) {
                purchasesUsd += amount;
              } else {
                totalPurchases += amount;
              }

              final referenceId =
                  entry.referenceId;

              if (referenceId != null &&
                  referenceId.isNotEmpty) {
                saleReferences.add(
                  referenceId,
                );
              }

              if (lastPurchaseDate ==
                  null ||
                  entry.createdAt.isAfter(
                    lastPurchaseDate,
                  )) {
                lastPurchaseDate =
                    entry.createdAt;
              }

              break;

            case 'OPENING_BALANCE':
              if (inDollars) {
                purchasesUsd += amount;
              } else {
                totalPurchases += amount;
              }
              break;

            case 'RECEIPT':
              if (inDollars) {
                paidUsd += amount;
              } else {
                totalPaid += amount;
              }
              break;

            case 'PAYMENT':
              if (inDollars) {
                purchasesUsd += amount;
              } else {
                totalPurchases += amount;
              }
              break;

            case 'REVERSAL':
              if (inDollars) {
                paidUsd += amount;
              } else {
                totalPaid += amount;
              }
              break;
          }
        }

        final rawBalance = totalPurchases - totalPaid;
        final rawBalanceUsd = purchasesUsd - paidUsd;

        return CustomerModel(
          id: row.id,
          serverId: row.serverId,
          name: row.name,
          phone: row.phone,
          email: row.email,
          address: row.address,
          type: row.type,
          groupName: row.groupName,
          representativeId: row.representativeId,
          creditLimit:
          row.creditLimit,
          notes: row.notes,
          totalPurchases: totalPurchases.toDouble(),
          totalPaid: totalPaid.toDouble(),
          balance: rawBalance.toDouble(),
          balanceUsd: rawBalanceUsd.toDouble(),
          invoicesCount:
          saleReferences.length,
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

  Future<ListPage<CustomerModel>> pageCustomers({
    int offset = 0,
    int limit = kListPageSize,
    String search = '',
    String filter = 'الكل',
  }) async {
    final query = search.trim();
    final like = '%$query%';
    final filterKey = switch (filter) {
      'عليه رصيد' => 'debt',
      'مسدد' => 'settled',
      _ => 'all',
    };
    const balanceJoin = '''
LEFT JOIN (
  SELECT customer_id,
    SUM(CASE
      WHEN type IN ('SALE', 'OPENING_BALANCE', 'PAYMENT')
        AND IFNULL(currency, 'IQD') != 'USD' THEN ABS(amount)
      WHEN type IN ('RECEIPT', 'REVERSAL')
        AND IFNULL(currency, 'IQD') != 'USD' THEN -ABS(amount)
      ELSE 0 END) AS balance_iqd,
    SUM(CASE
      WHEN type IN ('SALE', 'OPENING_BALANCE', 'PAYMENT')
        AND currency = 'USD' THEN ABS(amount)
      WHEN type IN ('RECEIPT', 'REVERSAL')
        AND currency = 'USD' THEN -ABS(amount)
      ELSE 0 END) AS balance_usd
  FROM customer_ledger_entries
  GROUP BY customer_id
) b ON b.customer_id = c.id
''';
    const where = '''
c.deleted_at IS NULL AND c.is_active = 1
AND (? = '' OR c.name LIKE ? OR c.phone LIKE ? OR c.address LIKE ? OR IFNULL(c.group_name, '') LIKE ?)
AND (
  ? = 'all'
  OR (? = 'debt' AND (IFNULL(b.balance_iqd, 0) > 0 OR IFNULL(b.balance_usd, 0) > 0))
  OR (? = 'settled' AND IFNULL(b.balance_iqd, 0) <= 0 AND IFNULL(b.balance_usd, 0) <= 0)
)
''';
    final variables = [
      Variable.withString(query),
      Variable.withString(like),
      Variable.withString(like),
      Variable.withString(like),
      Variable.withString(like),
      Variable.withString(filterKey),
      Variable.withString(filterKey),
      Variable.withString(filterKey),
    ];
    final total = (await database.customSelect(
      'SELECT COUNT(*) AS n FROM customers c $balanceJoin WHERE $where',
      variables: variables,
    ).getSingle()).read<int>('n');
    final idRows = await database.customSelect(
      'SELECT c.id AS id FROM customers c $balanceJoin WHERE $where ORDER BY c.name LIMIT ? OFFSET ?',
      variables: [
        ...variables,
        Variable.withInt(limit),
        Variable.withInt(offset),
      ],
    ).get();
    final ids = [for (final row in idRows) row.read<String>('id')];
    if (ids.isEmpty) {
      return ListPage(items: const [], total: total);
    }
    final rows = await (database.select(database.customers)
          ..where((table) => table.id.isIn(ids)))
        .get();
    final byId = {for (final row in rows) row.id: row};
    final ledgerRows = await (database.select(database.customerLedgerEntries)
          ..where((table) => table.customerId.isIn(ids)))
        .get();
    final ledgerByCustomer = <String, List<CustomerLedgerEntry>>{};
    for (final entry in ledgerRows) {
      ledgerByCustomer.putIfAbsent(entry.customerId, () => []).add(entry);
    }
    return ListPage(
      items: [
        for (final id in ids)
          if (byId[id] != null)
            _toCustomerModel(byId[id]!, ledgerByCustomer[id] ?? const []),
      ],
      total: total,
    );
  }

  Future<({int count, double purchases, double balance, int withDebt})>
      customerDirectoryStats() async {
    final counts = await database.customSelect(
      '''
SELECT
  COUNT(*) AS customers,
  SUM(CASE WHEN IFNULL(b.balance_iqd, 0) > 0 OR IFNULL(b.balance_usd, 0) > 0 THEN 1 ELSE 0 END) AS with_debt,
  SUM(IFNULL(b.balance_iqd, 0)) AS balance,
  SUM(IFNULL(b.purchases, 0)) AS purchases
FROM customers c
LEFT JOIN (
  SELECT customer_id,
    SUM(CASE
      WHEN type IN ('SALE', 'OPENING_BALANCE', 'PAYMENT')
        AND IFNULL(currency, 'IQD') != 'USD' THEN ABS(amount)
      ELSE 0 END) AS purchases,
    SUM(CASE
      WHEN type IN ('SALE', 'OPENING_BALANCE', 'PAYMENT')
        AND IFNULL(currency, 'IQD') != 'USD' THEN ABS(amount)
      WHEN type IN ('RECEIPT', 'REVERSAL')
        AND IFNULL(currency, 'IQD') != 'USD' THEN -ABS(amount)
      ELSE 0 END) AS balance_iqd,
    SUM(CASE
      WHEN type IN ('SALE', 'OPENING_BALANCE', 'PAYMENT') AND currency = 'USD' THEN ABS(amount)
      WHEN type IN ('RECEIPT', 'REVERSAL') AND currency = 'USD' THEN -ABS(amount)
      ELSE 0 END) AS balance_usd
  FROM customer_ledger_entries
  GROUP BY customer_id
) b ON b.customer_id = c.id
WHERE c.deleted_at IS NULL AND c.is_active = 1
''',
    ).getSingle();
    return (
      count: sqlInt(counts, 'customers'),
      purchases: sqlDouble(counts, 'purchases'),
      balance: sqlDouble(counts, 'balance'),
      withDebt: sqlInt(counts, 'with_debt'),
    );
  }

  // ===========================================================================
  // GET CUSTOMER
  // ===========================================================================

  Future<CustomerModel?>
  getCustomerById(
      String id,
      ) async {
    final row = await (database.select(database.customers)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final entries = await (database.select(database.customerLedgerEntries)
          ..where((table) => table.customerId.equals(id)))
        .get();
    return _toCustomerModel(row, entries);
  }

  Future<CustomerModel?>
  getCustomerByServerId(
      String serverId,
      ) async {
    final cleanServerId =
    serverId.trim();

    if (cleanServerId.isEmpty) {
      return null;
    }

    final row =
    await (database.select(
      database.customers,
    )
      ..where(
            (table) =>
        table.serverId.equals(
          cleanServerId,
        ) &
        table.deletedAt.isNull(),
      ))
        .getSingleOrNull();

    if (row == null) {
      return null;
    }

    return getCustomerById(
      row.id,
    );
  }

  // ===========================================================================
  // CREATE CUSTOMER
  // ===========================================================================

  Future<CustomerModel> createCustomer({
    required String name,
    String phone = '',
    String email = '',
    String address = '',
    String type = 'RETAIL',
    String groupName = '',
    String? representativeId,
    double creditLimit = 0,
    String? notes,
  }) async {
    final cleanName =
    name.trim();

    if (cleanName.isEmpty) {
      throw StateError(
        'اسم الزبون مطلوب.',
      );
    }

    final cleanType =
    _normalizeCustomerType(
      type,
    );

    if (creditLimit < 0) {
      throw StateError(
        'الحد الائتماني لا يمكن أن يكون سالباً.',
      );
    }

    final now =
    DateTime.now();

    final customer =
    CustomerModel(
      id: _uuid.v4(),
      serverId: null,
      name: cleanName,
      phone: phone.trim(),
      email: email.trim(),
      address: address.trim(),
      type: cleanType,
      groupName: groupName.trim(),
      representativeId: _clean(representativeId),
      creditLimit: creditLimit,
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
          database.customers,
        )
            .insert(
          CustomersCompanion.insert(
            id: customer.id,
            serverId:
            const Value.absent(),
            name: customer.name,
            phone: Value(
              customer.phone,
            ),
            email: Value(
              customer.email,
            ),
            address: Value(
              customer.address,
            ),
            type: Value(
              customer.type,
            ),
            groupName: Value(
              customer.groupName,
            ),
            representativeId: Value(
              customer.representativeId,
            ),
            creditLimit: Value(
              customer.creditLimit,
            ),
            notes: Value(
              customer.notes,
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
          entityType: 'customer',
          entityId: customer.id,
          operation:
          SyncOperation.create,
          idempotencyKey:
          customer.id,
          payload:
          customer.toSyncJson(),
        );
      },
    );

    return customer;
  }

  // ===========================================================================
  // UPDATE CUSTOMER
  // ===========================================================================

  Future<CustomerModel> updateCustomer(
      CustomerModel customer, {
        required String name,
        String phone = '',
        String email = '',
        String address = '',
        String type = 'RETAIL',
        String groupName = '',
        String? representativeId,
        double creditLimit = 0,
        String? notes,
      }) async {
    final cleanName =
    name.trim();

    if (cleanName.isEmpty) {
      throw StateError(
        'اسم الزبون مطلوب.',
      );
    }

    if (creditLimit < 0) {
      throw StateError(
        'الحد الائتماني لا يمكن أن يكون سالباً.',
      );
    }

    final cleanType =
    _normalizeCustomerType(
      type,
    );

    final now =
    DateTime.now();

    final cleanNotes =
    _clean(
      notes,
    );

    final updated =
    customer.copyWith(
      name: cleanName,
      phone: phone.trim(),
      email: email.trim(),
      address: address.trim(),
      type: cleanType,
      groupName: groupName.trim(),
      representativeId: _clean(representativeId),
      clearRepresentativeId: _clean(representativeId) == null,
      creditLimit: creditLimit,
      notes: cleanNotes,
      clearNotes:
      cleanNotes == null,
      updatedAt: now,
    );

    await database.transaction(
          () async {
        final affected =
        await (database.update(
          database.customers,
        )
          ..where(
                (table) =>
                table.id.equals(
                  customer.id,
                ),
          ))
            .write(
          CustomersCompanion(
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
            type: Value(
              updated.type,
            ),
            groupName: Value(
              updated.groupName,
            ),
            representativeId: Value(
              updated.representativeId,
            ),
            creditLimit: Value(
              updated.creditLimit,
            ),
            notes: Value(
              updated.notes,
            ),
            updatedAt: Value(
              now,
            ),
          ),
        );

        if (affected == 0) {
          throw StateError(
            'الزبون غير موجود.',
          );
        }

        await syncQueue.enqueue(
          entityType: 'customer',
          entityId: customer.id,
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
  // REGISTER RECEIPT
  // ===========================================================================

  Future<String> registerReceipt({
    required String customerId,
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

    final customer =
    await getCustomerById(
      customerId,
    );

    if (customer == null) {
      throw StateError(
        'الزبون غير موجود.',
      );
    }

    if (!customer.isActive) {
      throw StateError(
        'الزبون غير فعال.',
      );
    }

    final cleanMethod =
    method
        .trim()
        .toUpperCase();

    final now =
    DateTime.now();

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
        await database
            .into(
          database.customerPayments,
        )
            .insert(
          CustomerPaymentsCompanion.insert(
            id: paymentId,
            voucherNumber:
            voucherNumber,
            customerId:
            customerId,
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

        await database
            .into(
          database
              .customerLedgerEntries,
        )
            .insert(
          CustomerLedgerEntriesCompanion
              .insert(
            id: ledgerId,
            customerId:
            customerId,
            type: 'RECEIPT',
            amount: amount,
            currency: Value(ledgerCurrency),
            referenceType:
            const Value(
              'CUSTOMER_PAYMENT',
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

        // فقط payment يطلع للسيرفر.
        // الـBackend endpoint مسؤول عن تحديث ذمة الزبون.
        await syncQueue.enqueue(
          entityType:
          'customer_payment',
          entityId:
          paymentId,
          operation:
          SyncOperation.create,
          idempotencyKey:
          paymentId,
          payload: {
            'local_customer_id':
            customerId,
            'voucher_number':
            voucherNumber,
            'method':
            cleanMethod,
            'amount':
            amount,
            'note':
            _clean(note),
            'user_id':
            _clean(userId),
            'created_at':
            now
                .toUtc()
                .toIso8601String(),
          },
        );
        await syncQueue.enqueue(
          entityType: 'floor_notice',
          entityId: paymentId,
          operation: SyncOperation.create,
          idempotencyKey: 'floor-receipt-$paymentId',
          payload: {'kind': 'customer_receipt'},
        );
      },
    );

    return voucherNumber;
  }

  Future<String> registerDisbursement({
    required String customerId,
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

    final customer = await getCustomerById(customerId);

    if (customer == null) {
      throw StateError('الزبون غير موجود.');
    }

    if (!customer.isActive) {
      throw StateError('الزبون غير فعال.');
    }

    final now = DateTime.now();
    final paymentId = _uuid.v4();
    final ledgerId = _uuid.v4();
    final voucherNumber = _voucherNumber(paymentId, now);

    await database.transaction(() async {
      await database.into(database.customerPayments).insert(
            CustomerPaymentsCompanion.insert(
              id: paymentId,
              voucherNumber: voucherNumber,
              customerId: customerId,
              method: Value(method.trim().toUpperCase()),
              amount: amount,
              currency: Value(ledgerCurrency),
              referenceType: const Value('PAYMENT'),
              note: Value(_clean(note)),
              userId: Value(_clean(userId)),
              serverVersion: const Value(0),
              createdAt: now,
            ),
          );

      await database.into(database.customerLedgerEntries).insert(
            CustomerLedgerEntriesCompanion.insert(
              id: ledgerId,
              customerId: customerId,
              type: 'PAYMENT',
              amount: amount,
              currency: Value(ledgerCurrency),
              referenceType: const Value('CUSTOMER_DISBURSEMENT'),
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

  Future<List<LedgerLine>> _ledgerLines(String customerId) async {
    final rows = await (database.select(database.customerLedgerEntries)
          ..where((table) => table.customerId.equals(customerId)))
        .get();
    return [
      for (final row in rows)
        LedgerLine(
          id: row.id,
          type: row.type,
          referenceId: row.referenceId,
          createdAt: row.createdAt,
          amount: Money.parse(row.amount),
          currency: row.currency,
        ),
    ];
  }

  /// رصيد الزبون قبل هذا السند وبعده، من دفتر الأستاذ لا من مجموع الواجهة.
  Future<VoucherSnapshot?> snapshotForPayment(String paymentId) async {
    final payment = await (database.select(database.customerPayments)
          ..where((table) => table.id.equals(paymentId)))
        .getSingleOrNull();
    if (payment == null) {
      return null;
    }
    final lines = await _ledgerLines(payment.customerId);
    return voucherSnapshot(
      lines: lines,
      referenceId: paymentId,
      effectOf: customerLedgerEffect,
    );
  }

  Future<SaleBalanceSnapshot?> balanceAroundSale({
    required String customerId,
    required String saleId,
    required num invoiceTotal,
    required num paidAmount,
  }) async {
    final lines = await _ledgerLines(customerId);
    return saleBalanceSnapshot(
      lines: lines,
      saleId: saleId,
      invoiceTotal: Money.parse(invoiceTotal),
      paid: Money.parse(paidAmount),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _normalizeCustomerType(
      String value,
      ) {
    switch (value
        .trim()
        .toUpperCase()) {
      case 'RETAIL':
        return 'RETAIL';

      case 'WHOLESALE':
        return 'WHOLESALE';

      default:
        throw StateError(
          'نوع الزبون يجب أن يكون RETAIL أو WHOLESALE.',
        );
    }
  }

  String _voucherNumber(
      String paymentId,
      DateTime date,
      ) {
    final suffix =
    paymentId
        .replaceAll('-', '')
        .substring(0, 6)
        .toUpperCase();

    return 'REC-${date.millisecondsSinceEpoch}-$suffix';
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