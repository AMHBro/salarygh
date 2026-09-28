import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../customers/data/customers_local_repository.dart';
import '../../representatives/data/representatives_local_repository.dart';
import '../../suppliers/data/suppliers_local_repository.dart';
import '../models/financial_account_model.dart';
import '../models/payment_transaction_model.dart';

class FinanceLocalRepository {
  final AppDatabase database;

  final CustomersLocalRepository customersRepository;

  final SuppliersLocalRepository suppliersRepository;

  final RepresentativesLocalRepository representativesRepository;

  FinanceLocalRepository({
    required this.database,
    required this.customersRepository,
    required this.suppliersRepository,
    required this.representativesRepository,
  });

  Future<List<FinancialAccountModel>> getAccounts() async {
    final customers = await customersRepository.getCustomers();

    final suppliers = await suppliersRepository.getSuppliers();

    final representatives = await representativesRepository
        .getRepresentatives();

    final customerPayments = await database
        .select(database.customerPayments)
        .get();

    final supplierPayments = await database
        .select(database.supplierPayments)
        .get();

    final representativePayments = await database
        .select(database.representativePayments)
        .get();

    final customerLastPayment = <String, DateTime>{};

    final supplierLastPayment = <String, DateTime>{};

    final representativeLastPayment = <String, DateTime>{};

    for (final payment in customerPayments) {
      final current = customerLastPayment[payment.customerId];

      if (current == null || payment.createdAt.isAfter(current)) {
        customerLastPayment[payment.customerId] = payment.createdAt;
      }
    }

    for (final payment in supplierPayments) {
      final current = supplierLastPayment[payment.supplierId];

      if (current == null || payment.createdAt.isAfter(current)) {
        supplierLastPayment[payment.supplierId] = payment.createdAt;
      }
    }

    for (final payment in representativePayments) {
      final current = representativeLastPayment[payment.representativeId];

      if (current == null || payment.createdAt.isAfter(current)) {
        representativeLastPayment[payment.representativeId] = payment.createdAt;
      }
    }

    final accounts = <FinancialAccountModel>[];

    accounts.addAll(
      customers
          .where((customer) => customer.isActive && customer.deletedAt == null)
          .map(
            (customer) => FinancialAccountModel(
              id: customer.id,
              name: customer.name,
              phone: customer.phone,
              type: FinancialAccountType.customerDebt,
              totalAmount: customer.totalPurchases,
              paidAmount: customer.totalPaid,
              remainingAmount: customer.balance,
              remainingUsd: customer.balanceUsd,
              lastPaymentDate: customerLastPayment[customer.id],
            ),
          ),
    );

    accounts.addAll(
      suppliers
          .where((supplier) => supplier.isActive && supplier.deletedAt == null)
          .map(
            (supplier) => FinancialAccountModel(
              id: supplier.id,
              name: supplier.name,
              phone: supplier.phone,
              type: FinancialAccountType.supplierPayable,
              totalAmount: supplier.totalPurchases,
              paidAmount: supplier.totalPaid,
              remainingAmount: supplier.balance,
              remainingUsd: supplier.balanceUsd,
              lastPaymentDate: supplierLastPayment[supplier.id],
            ),
          ),
    );

    accounts.addAll(
      representatives
          .where((representative) => representative.deletedAt == null)
          .map(
            (representative) => FinancialAccountModel(
              id: representative.id,
              name: representative.name,
              phone: representative.phone,
              type: FinancialAccountType.representativeCommission,
              totalAmount: representative.totalCommission,
              paidAmount: representative.paidCommission,
              remainingAmount: representative.remainingCommission,
              lastPaymentDate: representativeLastPayment[representative.id],
            ),
          ),
    );

    accounts.sort((a, b) => b.remainingAmount.compareTo(a.remainingAmount));

    return accounts;
  }

  Future<List<PaymentTransactionModel>> getTransactions() async {
    final customerRows = await database.select(database.customers).get();

    final supplierRows = await database.select(database.suppliers).get();

    final representativeRows = await database
        .select(database.representatives)
        .get();

    final customerNames = {for (final row in customerRows) row.id: row.name};

    final supplierNames = {for (final row in supplierRows) row.id: row.name};

    final representativeNames = {
      for (final row in representativeRows) row.id: row.name,
    };

    final customerPaymentRows = await (database.select(
      database.customerPayments,
    )..orderBy([(table) => OrderingTerm.desc(table.createdAt)])).get();

    final supplierPaymentRows = await (database.select(
      database.supplierPayments,
    )..orderBy([(table) => OrderingTerm.desc(table.createdAt)])).get();

    final representativePaymentRows = await (database.select(
      database.representativePayments,
    )..orderBy([(table) => OrderingTerm.desc(table.createdAt)])).get();

    final transactions = <PaymentTransactionModel>[];

    transactions.addAll(
      customerPaymentRows.map(
        (payment) => PaymentTransactionModel(
          id: payment.id,
          voucherNumber: payment.voucherNumber,
          accountId: payment.customerId,
          accountName: customerNames[payment.customerId] ?? 'زبون غير معروف',
          type: payment.referenceType == 'PAYMENT'
              ? PaymentTransactionType.payment
              : PaymentTransactionType.receipt,
          method: PaymentMethodExtension.fromDatabase(payment.method),
          amount: payment.amount,
          createdAt: payment.createdAt,
          userName: payment.userId?.trim().isNotEmpty == true
              ? payment.userId!
              : 'مدير النظام',
          note: payment.note,
        ),
      ),
    );

    transactions.addAll(
      supplierPaymentRows.map(
        (payment) => PaymentTransactionModel(
          id: payment.id,
          voucherNumber: payment.voucherNumber,
          accountId: payment.supplierId,
          accountName: supplierNames[payment.supplierId] ?? 'شركة غير معروفة',
          type: payment.referenceType == 'RECEIPT'
              ? PaymentTransactionType.receipt
              : PaymentTransactionType.payment,
          method: PaymentMethodExtension.fromDatabase(payment.method),
          amount: payment.amount,
          createdAt: payment.createdAt,
          userName: payment.userId?.trim().isNotEmpty == true
              ? payment.userId!
              : 'مدير النظام',
          note: payment.note,
        ),
      ),
    );

    transactions.addAll(
      representativePaymentRows.map(
        (payment) => PaymentTransactionModel(
          id: payment.id,
          voucherNumber: payment.voucherNumber,
          accountId: payment.representativeId,
          accountName:
              representativeNames[payment.representativeId] ??
              'مندوب غير معروف',
          type: PaymentTransactionType.payment,
          method: PaymentMethodExtension.fromDatabase(payment.method),
          amount: payment.amount,
          createdAt: payment.createdAt,
          userName: payment.userId?.trim().isNotEmpty == true
              ? payment.userId!
              : 'مدير النظام',
          note: payment.note,
        ),
      ),
    );

    transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return transactions;
  }

  Future<String> registerCustomerReceipt({
    required String customerId,
    required double amount,
    required PaymentMethod method,
    String? note,
    String? userId,
    String currency = 'IQD',
    double exchangeRate = 0,
  }) {
    return customersRepository.registerReceipt(
      customerId: customerId,
      amount: amount,
      method: method.databaseValue,
      note: note,
      userId: userId,
      currency: currency,
      exchangeRate: exchangeRate,
    );
  }

  Future<String> registerCustomerDisbursement({
    required String customerId,
    required double amount,
    required PaymentMethod method,
    String? note,
    String? userId,
    String currency = 'IQD',
    double exchangeRate = 0,
  }) {
    return customersRepository.registerDisbursement(
      customerId: customerId,
      amount: amount,
      method: method.databaseValue,
      currency: currency,
      exchangeRate: exchangeRate,
      note: note,
      userId: userId,
    );
  }

  Future<String> registerSupplierReceipt({
    required String supplierId,
    required double amount,
    required PaymentMethod method,
    String? note,
    String? userId,
    String currency = 'IQD',
    double exchangeRate = 0,
  }) {
    return suppliersRepository.registerReceipt(
      supplierId: supplierId,
      amount: amount,
      method: method.databaseValue,
      note: note,
      userId: userId,
      currency: currency,
      exchangeRate: exchangeRate,
    );
  }

  Future<String> registerSupplierPayment({
    required String supplierId,
    required double amount,
    required PaymentMethod method,
    String? note,
    String? userId,
    String currency = 'IQD',
    double exchangeRate = 0,
  }) {
    return suppliersRepository.registerPayment(
      supplierId: supplierId,
      amount: amount,
      method: method.databaseValue,
      note: note,
      userId: userId,
      currency: currency,
      exchangeRate: exchangeRate,
    );
  }

  Future<void> registerRepresentativePayment({
    required String representativeId,
    required double amount,
    required PaymentMethod method,
    String? note,
    String? userId,
  }) {
    return representativesRepository.registerPayment(
      representativeId: representativeId,
      amount: amount,
      method: method.databaseValue,
      note: note,
      userId: userId,
    );
  }
}
