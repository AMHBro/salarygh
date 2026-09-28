enum PaymentTransactionType { receipt, payment }

extension PaymentTransactionTypeExtension on PaymentTransactionType {
  String get title {
    switch (this) {
      case PaymentTransactionType.receipt:
        return 'سند قبض';

      case PaymentTransactionType.payment:
        return 'سند دفع';
    }
  }
}

// ===========================================================================
// PAYMENT METHOD
// ===========================================================================
//
// القيم الأساسية مطابقة للـ Backend:
//
// CASH
// BANK_TRANSFER
// CHECK
// POS_MACHINE
//
// مع دعم القيم القديمة الموجودة محلياً مثل:
// BANK
// OTHER
//
// حتى لا تتأثر البيانات القديمة.
// ===========================================================================

enum PaymentMethod { cash, bankTransfer, check, posMachine }

extension PaymentMethodExtension on PaymentMethod {
  // =========================================================================
  // UI TITLE
  // =========================================================================

  String get title {
    switch (this) {
      case PaymentMethod.cash:
        return 'نقدي';

      case PaymentMethod.bankTransfer:
        return 'تحويل مصرفي';

      case PaymentMethod.check:
        return 'صك';

      case PaymentMethod.posMachine:
        return 'جهاز POS';
    }
  }

  // =========================================================================
  // DATABASE / API VALUE
  // =========================================================================

  String get databaseValue {
    switch (this) {
      case PaymentMethod.cash:
        return 'CASH';

      case PaymentMethod.bankTransfer:
        return 'BANK_TRANSFER';

      case PaymentMethod.check:
        return 'CHECK';

      case PaymentMethod.posMachine:
        return 'POS_MACHINE';
    }
  }

  // =========================================================================
  // FROM DATABASE
  // =========================================================================

  static PaymentMethod fromDatabase(String value) {
    switch (value.trim().toUpperCase()) {
      // ---------------------------------------------------------------------
      // Current backend values
      // ---------------------------------------------------------------------

      case 'BANK_TRANSFER':
        return PaymentMethod.bankTransfer;

      case 'CHECK':
        return PaymentMethod.check;

      case 'POS_MACHINE':
        return PaymentMethod.posMachine;

      case 'CASH':
        return PaymentMethod.cash;

      // ---------------------------------------------------------------------
      // Legacy local values
      // ---------------------------------------------------------------------

      case 'BANK':
        return PaymentMethod.bankTransfer;

      case 'OTHER':
        return PaymentMethod.cash;

      default:
        return PaymentMethod.cash;
    }
  }
}

// ===========================================================================
// PAYMENT TRANSACTION MODEL
// ===========================================================================

class PaymentTransactionModel {
  final String id;

  final String voucherNumber;

  final String accountId;
  final String accountName;

  final PaymentTransactionType type;
  final PaymentMethod method;

  final double amount;

  final DateTime createdAt;

  final String userName;
  final String? note;

  PaymentTransactionModel({
    required Object id,
    required this.voucherNumber,
    required Object accountId,
    required this.accountName,
    required this.type,
    required this.method,
    required this.amount,
    required this.createdAt,
    required this.userName,
    this.note,
  }) : id = id.toString(),
       accountId = accountId.toString();
}
