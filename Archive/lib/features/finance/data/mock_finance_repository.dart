import '../models/financial_account_model.dart';
import '../models/payment_transaction_model.dart';

class MockFinanceRepository {
  const MockFinanceRepository();

  List<FinancialAccountModel> getAccounts() {
    return [
      FinancialAccountModel(
        id: 1,
        name: 'أحمد محمد',
        phone: '07701234567',
        type: FinancialAccountType.customerDebt,
        totalAmount: 3450000,
        paidAmount: 2900000,
        remainingAmount: 550000,
        lastPaymentDate: DateTime(2026, 8, 17),
      ),
      FinancialAccountModel(
        id: 2,
        name: 'شركة النور',
        phone: '07801234567',
        type: FinancialAccountType.customerDebt,
        totalAmount: 12650000,
        paidAmount: 11200000,
        remainingAmount: 1450000,
        lastPaymentDate: DateTime(2026, 8, 16),
      ),
      FinancialAccountModel(
        id: 3,
        name: 'شركة النور للتجارة',
        phone: '07709999999',
        type: FinancialAccountType.supplierPayable,
        totalAmount: 18450000,
        paidAmount: 16000000,
        remainingAmount: 2450000,
        lastPaymentDate: DateTime(2026, 8, 15),
      ),
      FinancialAccountModel(
        id: 4,
        name: 'مؤسسة بغداد للتجهيز',
        phone: '07509999999',
        type: FinancialAccountType.supplierPayable,
        totalAmount: 8650000,
        paidAmount: 7200000,
        remainingAmount: 1450000,
        lastPaymentDate: DateTime(2026, 8, 14),
      ),
      FinancialAccountModel(
        id: 5,
        name: 'أحمد علي',
        phone: '07705555555',
        type: FinancialAccountType.representativeCommission,
        totalAmount: 422500,
        paidAmount: 300000,
        remainingAmount: 122500,
        lastPaymentDate: DateTime(2026, 8, 13),
      ),
    ];
  }

  List<PaymentTransactionModel> getTransactions() {
    return [
      PaymentTransactionModel(
        id: 1,
        voucherNumber: 'REC-1001',
        accountId: 1,
        accountName: 'أحمد محمد',
        type: PaymentTransactionType.receipt,
        method: PaymentMethod.cash,
        amount: 250000,
        createdAt: DateTime(2026, 8, 18, 15, 20),
        userName: 'مدير النظام',
        note: 'تسديد جزء من الرصيد',
      ),
      PaymentTransactionModel(
        id: 2,
        voucherNumber: 'PAY-1002',
        accountId: 3,
        accountName: 'شركة النور للتجارة',
        type: PaymentTransactionType.payment,
        method: PaymentMethod.bankTransfer,
        amount: 1000000,
        createdAt: DateTime(2026, 8, 18, 13, 10),
        userName: 'مدير النظام',
        note: 'دفعة مورد',
      ),
      PaymentTransactionModel(
        id: 3,
        voucherNumber: 'PAY-1003',
        accountId: 5,
        accountName: 'أحمد علي',
        type: PaymentTransactionType.payment,
        method: PaymentMethod.cash,
        amount: 50000,
        createdAt: DateTime(2026, 8, 17, 17, 30),
        userName: 'مدير النظام',
        note: 'دفعة عمولة',
      ),
    ];
  }
}
