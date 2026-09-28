import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../customers/data/customers_local_repository.dart';
import '../../customers/models/customer_model.dart';
import '../../products/data/unit_quantity.dart';
import '../../sales/data/sales_local_repository.dart';

class LocalStatementsRepository {
  final CustomersLocalRepository customersRepository;
  final SalesLocalRepository salesRepository;
  final AppDatabase database;

  LocalStatementsRepository({
    required this.customersRepository,
    required this.salesRepository,
    required this.database,
  });

  Future<List<Map<String, dynamic>>> groupStatement({
    required String groupName,
    DateTime? from,
    DateTime? to,
  }) async {
    final customers = await _customers();
    final selected = customers.where((customer) {
      return customer.groupName.trim() == groupName.trim();
    }).toList();
    final names = await _representativeNames();
    final sales = await salesRepository.getSales();
    final payments = await database.select(database.customerPayments).get();
    final rows = <Map<String, dynamic>>[];

    for (final customer in selected) {
      final movements = <Map<String, dynamic>>[];

      for (final sale in sales) {
        if (sale.customerId != customer.id ||
            !_inRange(sale.createdAt, from, to)) {
          continue;
        }

        movements.add({
          ..._customerRow(customer, names),
          'operation_type': 'بيع',
          'entry_type': 'بيع',
          'reference_number': sale.invoiceNumber,
          'invoice_number': sale.invoiceNumber,
          'invoice_date': sale.createdAt.toIso8601String(),
          'amount_iqd': sale.total,
          'sales_iqd': sale.total,
          'currency': sale.currency,
          'total_usd': sale.totalUsd,
          'sales_iqd_usd': sale.currency == 'USD' ? sale.totalUsd : 0,
          '_sort': sale.createdAt,
        });
      }

      for (final payment in payments) {
        if (payment.customerId != customer.id ||
            !_inRange(payment.createdAt, from, to)) {
          continue;
        }

        final disbursement = payment.referenceType == 'PAYMENT';
        movements.add({
          ..._customerRow(customer, names),
          'operation_type': disbursement ? 'صرف' : 'قبض',
          'entry_type': disbursement ? 'صرف' : 'قبض',
          'reference_number': payment.voucherNumber,
          'invoice_number': payment.voucherNumber,
          'invoice_date': payment.createdAt.toIso8601String(),
          'amount_iqd': payment.amount,
          'sales_iqd': 0,
          'sales_iqd_usd': 0,
          '_sort': payment.createdAt,
        });
      }

      if (movements.isEmpty) {
        rows.add(_customerRow(customer, names));
        continue;
      }

      movements.sort((a, b) {
        final left = a['_sort'] as DateTime;
        final right = b['_sort'] as DateTime;
        return left.compareTo(right);
      });

      for (final movement in movements) {
        movement.remove('_sort');
        rows.add(movement);
      }
    }

    return rows;
  }

  Future<List<Map<String, dynamic>>> customersByRepresentative(
    String representativeId,
  ) async {
    final customers = await _customers();
    final names = await _representativeNames();

    return [
      for (final customer in customers)
        if (customer.representativeId == representativeId)
          {
            ..._customerRow(customer, names),
            'recorded_balance': customer.balance,
          },
    ];
  }

  Future<List<Map<String, dynamic>>> representativeStatement({
    required String representativeId,
    DateTime? from,
    DateTime? to,
  }) async {
    final sales = await (database.select(database.sales)
          ..where(
            (table) =>
                table.deletedAt.isNull() &
                table.representativeId.equals(representativeId),
          ))
        .get();

    return [
      for (final sale in sales)
        if (_inRange(sale.createdAt, from, to))
          {
            'operation_type': 'بيع',
            'entry_type': 'بيع',
            'reference_number': sale.invoiceNumber,
            'representative_name': sale.representativeNameSnapshot ?? '',
            'customer_name': sale.customerName,
            'invoice_number': sale.invoiceNumber,
            'invoice_date': sale.createdAt.toIso8601String(),
            'sales_iqd': sale.total,
            'currency': sale.currency,
            'total_usd': sale.totalUsd,
            'sales_iqd_usd': sale.currency == 'USD' ? sale.totalUsd : 0,
            'commission_iqd': sale.commissionAmount,
            'commission_iqd_usd': 0,
          },
    ];
  }

  Future<List<String>> groupNames() async {
    final customers = await _customers();
    final names = customers
        .map((customer) => customer.groupName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return names;
  }

  Future<List<CustomerModel>> _customers() async {
    final customers = await customersRepository.getCustomers();
    return customers
        .where((customer) => customer.isActive && customer.deletedAt == null)
        .toList();
  }

  Map<String, dynamic> _customerRow(
    CustomerModel customer,
    Map<String, String> names,
  ) {
    return {
      'customer_name': customer.name,
      'phone': customer.phone,
      'group_name': customer.groupName,
      'representative_name': names[customer.representativeId] ?? '',
      'recorded_balance': customer.balance,
      'operation_type': '',
      'invoice_number': '',
      'invoice_date': null,
      'sales_iqd': 0,
      'sales_iqd_usd': 0,
    };
  }

  Future<Map<String, String>> _representativeNames() async {
    final rows = await (database.select(database.representatives)
          ..where((table) => table.deletedAt.isNull()))
        .get();
    return {for (final row in rows) row.id: row.name};
  }

  Future<List<Map<String, dynamic>>> warehouseMovement({
    String? warehouseId,
    DateTime? from,
    DateTime? to,
  }) async {
    final sales = await database.select(database.sales).get();
    final purchases = await database.select(database.purchases).get();
    final customerPayments =
        await database.select(database.customerPayments).get();
    final supplierPayments =
        await database.select(database.supplierPayments).get();
    final customers = await database.select(database.customers).get();
    final suppliers = await database.select(database.suppliers).get();
    final customerNames = {for (final row in customers) row.id: row.name};
    final supplierNames = {for (final row in suppliers) row.id: row.name};
    final salesById = {for (final sale in sales) sale.id: sale};
    for (final sale in sales) {
      final serverId = sale.serverId?.trim() ?? '';
      if (serverId.isNotEmpty) {
        salesById[serverId] = sale;
      }
    }
    final purchasesById = {for (final purchase in purchases) purchase.id: purchase};
    for (final purchase in purchases) {
      final serverId = purchase.serverId?.trim() ?? '';
      if (serverId.isNotEmpty) {
        purchasesById[serverId] = purchase;
      }
    }
    final selected = warehouseId?.trim() ?? '';
    final rows = <Map<String, dynamic>>[];

    bool sameWarehouse(String id) {
      return selected.isEmpty || id == selected;
    }

    for (final sale in sales) {
      if (sale.deletedAt != null ||
          !sameWarehouse(sale.warehouseId) ||
          !_inRange(sale.createdAt, from, to)) {
        continue;
      }
      rows.add({
        'occurred_at': sale.createdAt.toIso8601String(),
        'warehouse_name': sale.warehouseNameSnapshot,
        'entry_type': 'بيع',
        'reference_number': sale.invoiceNumber,
        'party_name': sale.customerName,
        'amount_iqd': sale.total,
        'currency': sale.currency,
        'total_usd': sale.totalUsd,
        '_sort': sale.createdAt,
      });
    }

    for (final purchase in purchases) {
      if (purchase.deletedAt != null ||
          !sameWarehouse(purchase.warehouseId) ||
          !_inRange(purchase.createdAt, from, to)) {
        continue;
      }
      rows.add({
        'occurred_at': purchase.createdAt.toIso8601String(),
        'warehouse_name': purchase.warehouseNameSnapshot,
        'entry_type': 'شراء',
        'reference_number': purchase.invoiceNumber,
        'party_name': purchase.supplierNameSnapshot,
        'amount_iqd': purchase.total,
        'currency': purchase.currency,
        'total_usd': purchase.totalUsd,
        '_sort': purchase.createdAt,
      });
    }

    for (final payment in customerPayments) {
      if (!_inRange(payment.createdAt, from, to)) {
        continue;
      }
      final sale = salesById[payment.referenceId];
      final warehouseName = sale?.warehouseNameSnapshot ?? 'عام';
      final warehouse = sale?.warehouseId ?? '';
      if (selected.isNotEmpty && warehouse != selected) {
        continue;
      }
      final disbursement = payment.referenceType == 'PAYMENT';
      rows.add({
        'occurred_at': payment.createdAt.toIso8601String(),
        'warehouse_name': warehouseName,
        'entry_type': disbursement ? 'صرف' : 'قبض',
        'reference_number': payment.voucherNumber,
        'party_name': customerNames[payment.customerId] ?? '',
        'amount_iqd': payment.amount,
        '_sort': payment.createdAt,
      });
    }

    for (final payment in supplierPayments) {
      if (!_inRange(payment.createdAt, from, to)) {
        continue;
      }
      final purchase = purchasesById[payment.referenceId];
      final warehouseName = purchase?.warehouseNameSnapshot ?? 'عام';
      final warehouse = purchase?.warehouseId ?? '';
      if (selected.isNotEmpty && warehouse != selected) {
        continue;
      }
      final receipt = payment.referenceType == 'RECEIPT';
      rows.add({
        'occurred_at': payment.createdAt.toIso8601String(),
        'warehouse_name': warehouseName,
        'entry_type': receipt ? 'قبض' : 'صرف',
        'reference_number': payment.voucherNumber,
        'party_name': supplierNames[payment.supplierId] ?? '',
        'amount_iqd': payment.amount,
        '_sort': payment.createdAt,
      });
    }

    rows.sort((a, b) => (b['_sort'] as DateTime).compareTo(a['_sort'] as DateTime));
    for (final row in rows) {
      row.remove('_sort');
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> warehouseTotals({
    String? warehouseId,
  }) async {
    final warehouses = await database.select(database.warehouses).get();
    final sales = await database.select(database.sales).get();
    final purchases = await database.select(database.purchases).get();
    final customerPayments =
        await database.select(database.customerPayments).get();
    final supplierPayments =
        await database.select(database.supplierPayments).get();
    final salesById = {for (final sale in sales) sale.id: sale};
    for (final sale in sales) {
      final serverId = sale.serverId?.trim() ?? '';
      if (serverId.isNotEmpty) {
        salesById[serverId] = sale;
      }
    }
    final purchasesById = {for (final purchase in purchases) purchase.id: purchase};
    for (final purchase in purchases) {
      final serverId = purchase.serverId?.trim() ?? '';
      if (serverId.isNotEmpty) {
        purchasesById[serverId] = purchase;
      }
    }
    final selected = warehouseId?.trim() ?? '';
    final rows = <Map<String, dynamic>>[];

    for (final warehouse in warehouses) {
      if (warehouse.deletedAt != null) {
        continue;
      }
      if (selected.isNotEmpty && warehouse.id != selected) {
        continue;
      }
      var salesTotal = 0.0;
      var salesUsd = 0.0;
      var purchaseTotal = 0.0;
      var purchaseUsd = 0.0;
      var receipts = 0.0;
      var payments = 0.0;
      for (final sale in sales) {
        if (sale.deletedAt == null && sale.warehouseId == warehouse.id) {
          salesTotal += sale.total;
          salesUsd += sale.totalUsd;
        }
      }
      for (final purchase in purchases) {
        if (purchase.deletedAt == null && purchase.warehouseId == warehouse.id) {
          purchaseTotal += purchase.total;
          purchaseUsd += purchase.totalUsd;
        }
      }
      for (final payment in customerPayments) {
        final sale = salesById[payment.referenceId];
        if (sale?.warehouseId != warehouse.id) {
          continue;
        }
        if (payment.referenceType == 'PAYMENT') {
          payments += payment.amount;
        } else {
          receipts += payment.amount;
        }
      }
      for (final payment in supplierPayments) {
        final purchase = purchasesById[payment.referenceId];
        if (purchase?.warehouseId != warehouse.id) {
          continue;
        }
        if (payment.referenceType == 'RECEIPT') {
          receipts += payment.amount;
        } else {
          payments += payment.amount;
        }
      }
      rows.add({
        'warehouse_name': warehouse.name,
        'sales_iqd': salesTotal,
        'sales_iqd_usd': salesUsd,
        'total_purchases_iqd': purchaseTotal,
        'total_purchases_iqd_usd': purchaseUsd,
        'receipts_iqd': receipts,
        'payments_iqd': payments,
      });
    }

    rows.sort(
      (a, b) => '${a['warehouse_name']}'.compareTo('${b['warehouse_name']}'),
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> currencyStatement({
    DateTime? from,
    DateTime? to,
  }) async {
    final sales = await database.select(database.sales).get();
    final purchases = await database.select(database.purchases).get();
    final rows = <Map<String, dynamic>>[];

    for (final sale in sales) {
      if (sale.deletedAt != null ||
          sale.currency != 'USD' ||
          !_inRange(sale.createdAt, from, to)) {
        continue;
      }
      rows.add({
        'operation_type': 'بيع',
        'reference_number': sale.invoiceNumber,
        'party_name': sale.customerName,
        'invoice_date': sale.createdAt.toIso8601String(),
        'amount_iqd': sale.total,
        'currency': sale.currency,
        'total_usd': sale.totalUsd,
        '_sort': sale.createdAt,
      });
    }

    for (final purchase in purchases) {
      if (purchase.deletedAt != null ||
          purchase.currency != 'USD' ||
          !_inRange(purchase.createdAt, from, to)) {
        continue;
      }
      rows.add({
        'operation_type': 'شراء',
        'reference_number': purchase.invoiceNumber,
        'party_name': purchase.supplierNameSnapshot,
        'invoice_date': purchase.createdAt.toIso8601String(),
        'amount_iqd': purchase.total,
        'currency': purchase.currency,
        'total_usd': purchase.totalUsd,
        '_sort': purchase.createdAt,
      });
    }

    rows.sort((a, b) => (b['_sort'] as DateTime).compareTo(a['_sort'] as DateTime));
    for (final row in rows) {
      row.remove('_sort');
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> capitalStatement({
    double openingCapital = 0,
    DateTime? from,
    DateTime? to,
  }) async {
    final sales = await database.select(database.sales).get();
    final purchases = await database.select(database.purchases).get();
    final saleItems = await database.select(database.saleItems).get();
    final variants = await database.select(database.productVariants).get();
    final customerPayments =
        await database.select(database.customerPayments).get();
    final supplierPayments =
        await database.select(database.supplierPayments).get();
    final customers = await database.select(database.customers).get();
    final suppliers = await database.select(database.suppliers).get();
    final costs = {for (final variant in variants) variant.id: variant.costPrice};
    final customerNames = {for (final row in customers) row.id: row.name};
    final supplierNames = {for (final row in suppliers) row.id: row.name};
    final itemsBySale = <String, List<SaleItem>>{};
    for (final item in saleItems) {
      itemsBySale.putIfAbsent(item.saleId, () => []).add(item);
    }

    final movements = <Map<String, dynamic>>[];

    for (final sale in sales) {
      if (sale.deletedAt != null || !_inRange(sale.createdAt, from, to)) {
        continue;
      }
      var cost = 0.0;
      for (final item in itemsBySale[sale.id] ?? const <SaleItem>[]) {
        final pieces = await quantityInBaseUnit(
          database: database,
          unitId: item.unitId,
          quantity: item.quantity,
        );
        cost += pieces * (costs[item.variantId] ?? 0);
      }
      final profit = sale.total - cost;
      movements.add({
        'operation_type': 'بيع',
        'reference_number': sale.invoiceNumber,
        'party_name': sale.customerName,
        'invoice_date': sale.createdAt.toIso8601String(),
        'amount_iqd': sale.total,
        'cost_iqd': cost,
        'profit_iqd': profit,
        'currency': sale.currency,
        'total_usd': sale.totalUsd,
        'effect_note': 'يزيد رأس المال بمقدار الربح',
        '_sort': sale.createdAt,
      });
    }

    for (final purchase in purchases) {
      if (purchase.deletedAt != null ||
          !_inRange(purchase.createdAt, from, to)) {
        continue;
      }
      movements.add({
        'operation_type': 'شراء',
        'reference_number': purchase.invoiceNumber,
        'party_name': purchase.supplierNameSnapshot,
        'invoice_date': purchase.createdAt.toIso8601String(),
        'amount_iqd': purchase.total,
        'cost_iqd': purchase.total,
        'profit_iqd': 0,
        'currency': purchase.currency,
        'total_usd': purchase.totalUsd,
        'effect_note': 'لا يغير رأس المال: النقد صار بضاعة',
        '_sort': purchase.createdAt,
      });
    }

    for (final payment in customerPayments) {
      if (!_inRange(payment.createdAt, from, to)) {
        continue;
      }
      final disbursement = payment.referenceType == 'PAYMENT';
      movements.add({
        'operation_type': disbursement ? 'صرف' : 'قبض',
        'reference_number': payment.voucherNumber,
        'party_name': customerNames[payment.customerId] ?? '',
        'invoice_date': payment.createdAt.toIso8601String(),
        'amount_iqd': payment.amount,
        'cost_iqd': 0,
        'profit_iqd': 0,
        'currency': 'IQD',
        'total_usd': 0,
        'effect_note': 'لا يغير رأس المال: نقل بين النقد والذمة',
        '_sort': payment.createdAt,
      });
    }

    for (final payment in supplierPayments) {
      if (!_inRange(payment.createdAt, from, to)) {
        continue;
      }
      final receipt = payment.referenceType == 'RECEIPT';
      movements.add({
        'operation_type': receipt ? 'قبض' : 'صرف',
        'reference_number': payment.voucherNumber,
        'party_name': supplierNames[payment.supplierId] ?? '',
        'invoice_date': payment.createdAt.toIso8601String(),
        'amount_iqd': payment.amount,
        'cost_iqd': 0,
        'profit_iqd': 0,
        'currency': 'IQD',
        'total_usd': 0,
        'effect_note': 'لا يغير رأس المال: نقل بين النقد والذمة',
        '_sort': payment.createdAt,
      });
    }

    try {
      final exchanges = await database.customSelect(
        '''
        SELECT kind, usd_amount, iqd_amount, party_name, created_at
        FROM currency_exchanges
        ''',
      ).get();
      for (final row in exchanges) {
        final createdAt =
            DateTime.tryParse(row.read<String>('created_at')) ?? DateTime.now();
        if (!_inRange(createdAt, from, to)) {
          continue;
        }
        final buy = row.read<String>('kind') == 'BUY';
        movements.add({
          'operation_type': buy ? 'شراء دولار' : 'بيع دولار',
          'reference_number': '',
          'party_name': row.read<String?>('party_name') ?? '',
          'invoice_date': createdAt.toIso8601String(),
          'amount_iqd': row.read<double>('iqd_amount'),
          'cost_iqd': row.read<double>('iqd_amount'),
          'profit_iqd': 0,
          'currency': 'USD',
          'total_usd': row.read<double>('usd_amount'),
          'effect_note': 'لا يغير رأس المال: تحويل بين الدينار والدولار',
          '_sort': createdAt,
        });
      }
    } catch (_) {}

    movements.sort(
      (a, b) => (a['_sort'] as DateTime).compareTo(b['_sort'] as DateTime),
    );

    var running = openingCapital;
    final rows = <Map<String, dynamic>>[
      {
        'operation_type': 'رأس مال',
        'reference_number': '',
        'party_name': '',
        'invoice_date': null,
        'amount_iqd': openingCapital,
        'cost_iqd': 0,
        'profit_iqd': openingCapital,
        'currency': 'IQD',
        'total_usd': 0,
        'effect_note': 'المبلغ المسجل في الإعدادات',
        'capital_balance': openingCapital,
      },
    ];

    for (final movement in movements) {
      running += (movement['profit_iqd'] as num).toDouble();
      movement.remove('_sort');
      movement['capital_balance'] = running;
      rows.add(movement);
    }

    return rows;
  }

  bool _inRange(DateTime date, DateTime? from, DateTime? to) {
    final day = DateTime(date.year, date.month, date.day);
    if (from != null &&
        day.isBefore(DateTime(from.year, from.month, from.day))) {
      return false;
    }
    if (to != null && day.isAfter(DateTime(to.year, to.month, to.day))) {
      return false;
    }
    return true;
  }
}
