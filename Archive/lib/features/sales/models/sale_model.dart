import 'cart_item_model.dart';

enum PaymentType {
  cash,
  credit,
  partial,
}

extension PaymentTypeExtension on PaymentType {
  String get title {
    switch (this) {
      case PaymentType.cash:
        return 'نقدي';

      case PaymentType.credit:
        return 'آجل';

      case PaymentType.partial:
        return 'جزئي';
    }
  }

  String get apiValue {
    switch (this) {
      case PaymentType.cash:
        return 'CASH';

      case PaymentType.credit:
        return 'CREDIT';

      case PaymentType.partial:
        return 'PARTIAL';
    }
  }
}

class SaleModel {
  /// Local UUID.
  final String id;

  /// Server UUID.
  ///
  /// يكون null إلى أن تتم مزامنة الفاتورة مع السيرفر.
  final String? serverId;

  final String invoiceNumber;

  final String? customerId;

  final String customerName;

  final String warehouseId;

  final String warehouseName;

  final String? representativeId;

  final List<CartItemModel> items;

  final double subtotal;

  final double discount;

  final double porterage;

  final double total;

  final double paidAmount;

  final double remainingAmount;

  final PaymentType paymentType;

  /// IQD أو USD. [total] يبقى بالدينار.
  final String currency;

  final double exchangeRate;

  final double totalUsd;

  final String notes;

  final DateTime createdAt;

  final DateTime updatedAt;

  const SaleModel({
    required this.id,
    this.serverId,
    required this.invoiceNumber,
    this.customerId,
    required this.customerName,
    required this.warehouseId,
    required this.warehouseName,
    this.representativeId,
    required this.items,
    required this.subtotal,
    required this.discount,
    this.porterage = 0,
    required this.total,
    required this.paidAmount,
    required this.remainingAmount,
    required this.paymentType,
    this.currency = 'IQD',
    this.exchangeRate = 0,
    this.totalUsd = 0,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isSynced {
    return serverId != null &&
        serverId!.trim().isNotEmpty;
  }

  SaleModel copyWith({
    String? id,
    String? serverId,
    bool clearServerId = false,
    String? invoiceNumber,
    String? customerId,
    bool clearCustomerId = false,
    String? customerName,
    String? warehouseId,
    String? warehouseName,
    String? representativeId,
    bool clearRepresentativeId = false,
    List<CartItemModel>? items,
    double? subtotal,
    double? discount,
    double? porterage,
    double? total,
    double? paidAmount,
    double? remainingAmount,
    PaymentType? paymentType,
    String? currency,
    double? exchangeRate,
    double? totalUsd,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SaleModel(
      id: id ?? this.id,
      serverId:
      clearServerId
          ? null
          : serverId ?? this.serverId,
      invoiceNumber:
      invoiceNumber ?? this.invoiceNumber,
      customerId:
      clearCustomerId
          ? null
          : customerId ?? this.customerId,
      customerName:
      customerName ?? this.customerName,
      warehouseId:
      warehouseId ?? this.warehouseId,
      warehouseName:
      warehouseName ?? this.warehouseName,
      representativeId:
      clearRepresentativeId
          ? null
          : representativeId ??
          this.representativeId,
      items:
      items ?? this.items,
      subtotal:
      subtotal ?? this.subtotal,
      discount:
      discount ?? this.discount,
      porterage:
      porterage ?? this.porterage,
      total:
      total ?? this.total,
      paidAmount:
      paidAmount ?? this.paidAmount,
      remainingAmount:
      remainingAmount ??
          this.remainingAmount,
      paymentType:
      paymentType ?? this.paymentType,
      currency: currency ?? this.currency,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      totalUsd: totalUsd ?? this.totalUsd,
      notes: notes ?? this.notes,
      createdAt:
      createdAt ?? this.createdAt,
      updatedAt:
      updatedAt ?? this.updatedAt,
    );
  }
}