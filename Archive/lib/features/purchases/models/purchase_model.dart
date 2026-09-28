class PurchaseItemModel {
  /// Local Product UUID.
  final String productId;

  /// Local Variant UUID.
  ///
  /// إذا فارغ والمنتج عنده Variant واحد،
  /// PurchasesLocalRepository يحله تلقائياً.
  final String variantId;

  /// Unit UUID.
  ///
  /// Units.id = Server UUID.
  /// إذا فارغ، نستخدم baseUnitId مال المنتج.
  final String unitId;

  final String productName;
  final String barcode;

  final int quantity;
  final double unitCost;

  /// كم قطعة داخل الكارتون. 1 يعني البيع أو الشراء بالقطعة.
  final double unitFactor;

  final double discountPercent;

  const PurchaseItemModel({
    this.productId = '',
    this.variantId = '',
    this.unitId = '',
    required this.productName,
    required this.barcode,
    required this.quantity,
    required this.unitCost,
    this.unitFactor = 1,
    this.discountPercent = 0,
  });

  double get pieceCost {
    if (unitFactor <= 1) {
      return unitCost;
    }
    return unitCost / unitFactor;
  }

  double get grossTotal =>
      quantity * unitCost;

  double get discountAmount =>
      grossTotal *
          (discountPercent / 100);

  double get total =>
      grossTotal - discountAmount;

  PurchaseItemModel copyWith({
    String? productId,
    String? variantId,
    String? unitId,
    String? productName,
    String? barcode,
    int? quantity,
    double? unitCost,
    double? unitFactor,
    double? discountPercent,
  }) {
    return PurchaseItemModel(
      productId:
      productId ?? this.productId,
      variantId:
      variantId ?? this.variantId,
      unitId:
      unitId ?? this.unitId,
      productName:
      productName ?? this.productName,
      barcode:
      barcode ?? this.barcode,
      quantity:
      quantity ?? this.quantity,
      unitCost:
      unitCost ?? this.unitCost,
      unitFactor:
      unitFactor ?? this.unitFactor,
      discountPercent:
      discountPercent ??
          this.discountPercent,
    );
  }

  Map<String, dynamic> toSyncJson() {
    return {
      'product_id': productId,
      'variant_id': variantId,
      'unit_id': unitId,
      'product_name': productName,
      'barcode': barcode,
      'quantity': quantity,
      'unit_cost': unitCost,
      'discount_percent':
      discountPercent,
      'total': total,
    };
  }
}

enum PurchasePaymentType {
  cash,
  credit,
  partial,
}

extension PurchasePaymentTypeExtension
on PurchasePaymentType {
  String get title {
    switch (this) {
      case PurchasePaymentType.cash:
        return 'نقدي';

      case PurchasePaymentType.credit:
        return 'آجل';

      case PurchasePaymentType.partial:
        return 'جزئي';
    }
  }

  String get databaseValue {
    switch (this) {
      case PurchasePaymentType.cash:
        return 'CASH';

      case PurchasePaymentType.credit:
        return 'CREDIT';

      case PurchasePaymentType.partial:
        return 'PARTIAL';
    }
  }

  static PurchasePaymentType fromDatabaseValue(
      String value,
      ) {
    switch (value.trim().toUpperCase()) {
      case 'CASH':
        return PurchasePaymentType.cash;

      case 'CREDIT':
        return PurchasePaymentType.credit;

      case 'PARTIAL':
        return PurchasePaymentType.partial;

      default:
        throw StateError(
          'نوع دفع غير معروف: $value',
        );
    }
  }
}

class PurchaseModel {
  final String id;

  final String? serverId;

  final String invoiceNumber;

  final String supplierId;
  final String supplierName;

  final String warehouseId;
  final String warehouseName;

  final List<PurchaseItemModel> items;

  final double subtotal;
  final double discount;
  final double porterage;
  final double total;
  final double paid;
  final double remaining;

  final PurchasePaymentType paymentType;

  final String currency;
  final double exchangeRate;
  final double totalUsd;

  final String? note;

  final DateTime createdAt;

  const PurchaseModel({
    required this.id,
    this.serverId,
    required this.invoiceNumber,
    this.supplierId = '',
    required this.supplierName,
    this.warehouseId = '',
    required this.warehouseName,
    required this.items,
    required this.subtotal,
    required this.discount,
    this.porterage = 0,
    required this.total,
    required this.paid,
    required this.remaining,
    required this.paymentType,
    this.currency = 'IQD',
    this.exchangeRate = 0,
    this.totalUsd = 0,
    this.note,
    required this.createdAt,
  });

  bool get isSynced =>
      serverId != null &&
          serverId!.trim().isNotEmpty;
}