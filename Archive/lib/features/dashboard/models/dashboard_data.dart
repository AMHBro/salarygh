class DashboardSummary {
  final double todaySales;
  final int todayInvoicesCount;
  final double totalCustomerDebt;
  final double totalCustomerDebtUsd;
  final int lowStockCount;

  final double todayCashSales;
  final double todayCreditAmount;
  final double todayRepresentativeSales;

  final int activeProductsCount;

  const DashboardSummary({
    required this.todaySales,
    required this.todayInvoicesCount,
    required this.totalCustomerDebt,
    this.totalCustomerDebtUsd = 0,
    required this.lowStockCount,
    required this.todayCashSales,
    required this.todayCreditAmount,
    required this.todayRepresentativeSales,
    required this.activeProductsCount,
  });

  factory DashboardSummary.empty() {
    return const DashboardSummary(
      todaySales: 0,
      todayInvoicesCount: 0,
      totalCustomerDebt: 0,
      lowStockCount: 0,
      todayCashSales: 0,
      todayCreditAmount: 0,
      todayRepresentativeSales: 0,
      activeProductsCount: 0,
    );
  }
}

class DashboardRecentSale {
  final String id;
  final String invoiceNumber;
  final String customerName;
  final String paymentType;
  final double total;
  final double paidAmount;
  final double remainingAmount;
  final DateTime createdAt;

  const DashboardRecentSale({
    required this.id,
    required this.invoiceNumber,
    required this.customerName,
    required this.paymentType,
    required this.total,
    required this.paidAmount,
    required this.remainingAmount,
    required this.createdAt,
  });

  String get paymentTypeLabel {
    switch (paymentType.toUpperCase()) {
      case 'CASH':
        return 'نقدي';

      case 'CREDIT':
        return 'آجل';

      case 'PARTIAL':
        return 'جزئي';

      case 'REP_CUSTODY':
        return 'عهدة مندوب';

      default:
        return paymentType;
    }
  }

  String get statusLabel {
    if (remainingAmount <= 0.0001) {
      return 'مدفوعة';
    }

    if (paidAmount > 0) {
      return 'جزئي';
    }

    return 'آجل';
  }
}

class DashboardLowStockItem {
  final String productId;
  final String productName;
  final String unit;
  final double quantity;
  final double minimumStock;

  const DashboardLowStockItem({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.minimumStock,
  });

  bool get isOutOfStock => quantity <= 0;

  bool get isCritical {
    if (quantity <= 0) {
      return true;
    }

    if (minimumStock <= 0) {
      return false;
    }

    return quantity <= (minimumStock * 0.5);
  }
}