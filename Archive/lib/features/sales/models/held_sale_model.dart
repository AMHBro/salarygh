import 'cart_item_model.dart';
import 'sale_model.dart';

class HeldSaleModel {
  final String id;

  final String warehouseId;
  final String warehouseName;

  final String? customerId;
  final String customerName;

  final String? representativeId;
  final String? representativeName;

  final PriceType priceType;
  final PaymentType paymentType;

  final double discount;
  final double paidAmount;

  final DateTime createdAt;
  final DateTime updatedAt;

  final List<HeldSaleItemModel> items;

  const HeldSaleModel({
    required this.id,
    required this.warehouseId,
    required this.warehouseName,
    required this.customerId,
    required this.customerName,
    required this.representativeId,
    required this.representativeName,
    required this.priceType,
    required this.paymentType,
    required this.discount,
    required this.paidAmount,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
  });

  int get itemsCount => items.length;

  double get subtotal {
    return items.fold<double>(
      0,
          (sum, item) => sum + item.total,
    );
  }

  double get total {
    final value = subtotal - discount;

    return value < 0 ? 0 : value;
  }
}

class HeldSaleItemModel {
  final String id;

  final String productId;
  final String variantId;
  final String unitId;

  final String productName;
  final String? barcode;

  final PriceType priceType;

  final int quantity;
  final double unitFactor;
  final int loosePieces;
  final double unitPrice;
  final double discountPercent;
  final double total;

  const HeldSaleItemModel({
    required this.id,
    required this.productId,
    required this.variantId,
    required this.unitId,
    required this.productName,
    required this.barcode,
    required this.priceType,
    required this.quantity,
    this.unitFactor = 1,
    this.loosePieces = 0,
    required this.unitPrice,
    required this.discountPercent,
    required this.total,
  });
}