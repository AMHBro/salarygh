enum FinancialAccountType {
  customerDebt,
  supplierPayable,
  representativeCommission,
}

extension FinancialAccountTypeExtension
on FinancialAccountType {
  String get title {
    switch (this) {
      case FinancialAccountType.customerDebt:
        return 'زبون';

      case FinancialAccountType.supplierPayable:
        return 'شركة';

      case FinancialAccountType.representativeCommission:
        return 'مندوب';
    }
  }
}

class FinancialAccountModel {
  final String id;

  final String name;
  final String phone;

  final FinancialAccountType type;

  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final double remainingUsd;

  final DateTime? lastPaymentDate;

  FinancialAccountModel({
    required Object id,
    required this.name,
    required this.phone,
    required this.type,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    this.remainingUsd = 0,
    this.lastPaymentDate,
  }) : id = id.toString();

  FinancialAccountModel copyWith({
    Object? id,
    String? name,
    String? phone,
    FinancialAccountType? type,
    double? totalAmount,
    double? paidAmount,
    double? remainingAmount,
    double? remainingUsd,
    DateTime? lastPaymentDate,
  }) {
    return FinancialAccountModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      type: type ?? this.type,
      totalAmount:
      totalAmount ?? this.totalAmount,
      paidAmount:
      paidAmount ?? this.paidAmount,
      remainingAmount:
      remainingAmount ??
          this.remainingAmount,
      remainingUsd:
      remainingUsd ?? this.remainingUsd,
      lastPaymentDate:
      lastPaymentDate ??
          this.lastPaymentDate,
    );
  }
}