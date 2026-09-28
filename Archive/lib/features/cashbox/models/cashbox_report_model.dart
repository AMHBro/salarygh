class CashboxDayReport {
  final String businessDate;

  final double totalSales;
  final double cashSales;
  final double creditSales;
  final double partialSales;
  final double cashReceived;
  final double remainingAmount;

  final int invoicesCount;

  final double expectedCash;

  final int unassignedInvoicesCount;

  final List<CashboxSessionReport> sessions;
  final List<CashboxInvoiceModel> invoices;
  final List<CashboxSoldItemModel> soldItems;

  const CashboxDayReport({
    required this.businessDate,
    required this.totalSales,
    required this.cashSales,
    required this.creditSales,
    required this.partialSales,
    required this.cashReceived,
    required this.remainingAmount,
    required this.invoicesCount,
    required this.expectedCash,
    required this.unassignedInvoicesCount,
    required this.sessions,
    required this.invoices,
    required this.soldItems,
  });

  CashboxSessionReport? get openSession {
    for (final session in sessions) {
      if (session.isOpen) {
        return session;
      }
    }

    return null;
  }

  bool get hasOpenSession =>
      openSession != null;

  int get sessionsCount =>
      sessions.length;

  bool get hasUnassignedSales =>
      unassignedInvoicesCount > 0;
}

class CashboxSessionReport {
  final String id;
  final String businessDate;

  final double openingBalance;

  final double totalSales;
  final double cashSales;
  final double creditSales;
  final double partialSales;
  final double cashReceived;
  final double remainingAmount;

  final int invoicesCount;

  final double expectedCash;

  final double? countedCash;
  final double? difference;

  final String status;
  final String? note;

  final DateTime openedAt;
  final DateTime? closedAt;

  final List<CashboxInvoiceModel> invoices;
  final List<CashboxSoldItemModel> soldItems;

  const CashboxSessionReport({
    required this.id,
    required this.businessDate,
    required this.openingBalance,
    required this.totalSales,
    required this.cashSales,
    required this.creditSales,
    required this.partialSales,
    required this.cashReceived,
    required this.remainingAmount,
    required this.invoicesCount,
    required this.expectedCash,
    required this.countedCash,
    required this.difference,
    required this.status,
    required this.note,
    required this.openedAt,
    required this.closedAt,
    required this.invoices,
    required this.soldItems,
  });

  bool get isOpen =>
      status.trim().toUpperCase() ==
          'OPEN';

  bool get isClosed =>
      status.trim().toUpperCase() ==
          'CLOSED';

  bool get isMatched =>
      difference != null &&
          difference!.abs() < 0.01;
}

class CashboxInvoiceModel {
  final String id;
  final String? serverId;

  final String invoiceNumber;

  final String? cashboxSessionId;

  final String customerName;

  final String warehouseId;
  final String warehouseName;

  final String paymentType;

  final double total;
  final double paidAmount;
  final double remainingAmount;

  final DateTime createdAt;

  const CashboxInvoiceModel({
    required this.id,
    required this.serverId,
    required this.invoiceNumber,
    required this.cashboxSessionId,
    required this.customerName,
    required this.warehouseId,
    required this.warehouseName,
    required this.paymentType,
    required this.total,
    required this.paidAmount,
    required this.remainingAmount,
    required this.createdAt,
  });

  bool get isSynced =>
      serverId != null &&
          serverId!.trim().isNotEmpty;
}

class CashboxSoldItemModel {
  final String productId;
  final String productName;
  final String? unitId;

  final double quantity;
  final double totalSales;

  final int linesCount;

  const CashboxSoldItemModel({
    required this.productId,
    required this.productName,
    required this.unitId,
    required this.quantity,
    required this.totalSales,
    required this.linesCount,
  });
}

class CashboxDayHistoryModel {
  final String businessDate;

  final double totalSales;
  final double cashReceived;

  final int invoicesCount;
  final int sessionsCount;

  final bool hasOpenSession;

  final double? difference;

  const CashboxDayHistoryModel({
    required this.businessDate,
    required this.totalSales,
    required this.cashReceived,
    required this.invoicesCount,
    required this.sessionsCount,
    required this.hasOpenSession,
    required this.difference,
  });

  bool get isClosed =>
      sessionsCount > 0 &&
          !hasOpenSession;
}