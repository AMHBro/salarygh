import '../../products/models/product_model.dart';

enum PriceType {
  cost,
  representative,
  wholesale,
  retail,
}

extension PriceTypeExtension on PriceType {
  String get title {
    switch (this) {
      case PriceType.cost:
        return 'الكلفة';

      case PriceType.representative:
        return 'المندوب';

      case PriceType.wholesale:
        return 'الجملة';

      case PriceType.retail:
        return 'المفرد';
    }
  }

  String get apiValue {
    switch (this) {
      case PriceType.cost:
        return 'COST';

      case PriceType.representative:
        return 'REP';

      case PriceType.wholesale:
        return 'WHOLESALE';

      case PriceType.retail:
        return 'RETAIL';
    }
  }
}

class CartItemModel {
  final ProductModel product;

  /// Local ProductVariant UUID.
  final String? variantId;

  /// Unit UUID.
  ///
  /// Units.id عندنا هو نفسه UUID الخاص بالسيرفر.
  final String? unitId;

  /// كم وحدة أساس داخل وحدة السطر. القطعة = 1، والكرتون = عدد القطع.
  final double unitFactor;

  final int quantity;

  /// قطع مفردة على نفس السطر. تبقى صفراً إذا البيع كارتون فقط.
  final int loosePieces;

  /// نوع السعر الفعلي المستخدم في هذه القائمة.
  final PriceType priceType;

  /// السعر الفعلي المستخدم للحساب والحفظ.
  ///
  /// يبقى موجوداً للتوافق مع بقية النظام
  /// وHeld Sales وSales Repository.
  final double? unitPriceOverride;

  /// -------------------------------------------------------------------------
  /// الأسعار المؤقتة داخل سطر قائمة البيع.
  ///
  /// هذه القيم لا تعدل أسعار المنتج في قاعدة البيانات.
  /// هي فقط خاصة بالقائمة الحالية.
  /// -------------------------------------------------------------------------

  final double? costPriceOverride;

  final double? representativePriceOverride;

  final double? wholesalePriceOverride;

  final double? retailPriceOverride;

  /// نسبة خصم على مستوى السطر.
  final double discountPercent;

  /// ملاحظة خاصة بهذه المادة داخل القائمة الحالية.
  final String notes;

  const CartItemModel({
    required this.product,
    required this.quantity,
    required this.priceType,
    this.variantId,
    this.unitId,
    this.unitFactor = 1,
    this.loosePieces = 0,
    this.unitPriceOverride,
    this.costPriceOverride,
    this.representativePriceOverride,
    this.wholesalePriceOverride,
    this.retailPriceOverride,
    this.discountPercent = 0,
    this.notes = '',
  });

  // ===========================================================================
  // DEFAULT PRICES
  // ===========================================================================

  double get defaultCostPrice {
    return product.costPrice;
  }

  double get defaultRepresentativePrice {
    return product.repPrice;
  }

  double get defaultWholesalePrice {
    return product.wholesalePrice;
  }

  double get defaultRetailPrice {
    return product.retailPrice;
  }

  // ===========================================================================
  // EDITABLE CART PRICES
  // ===========================================================================

  double get costPrice {
    return costPriceOverride ??
        defaultCostPrice;
  }

  double get representativePrice {
    return representativePriceOverride ??
        defaultRepresentativePrice;
  }

  double get wholesalePrice {
    return wholesalePriceOverride ??
        defaultWholesalePrice;
  }

  double get retailPrice {
    return retailPriceOverride ??
        defaultRetailPrice;
  }

  // ===========================================================================
  // SELECTED PRICE
  // ===========================================================================

  double get selectedPrice {
    switch (priceType) {
      case PriceType.cost:
        return costPrice;

      case PriceType.representative:
        return representativePrice;

      case PriceType.wholesale:
        return wholesalePrice;

      case PriceType.retail:
        return retailPrice;
    }
  }

  /// يبقى هذا الـgetter حتى ما نكسر أي كود موجود
  /// حالياً يعتمد على defaultUnitPrice.
  double get defaultUnitPrice {
    return selectedPrice;
  }

  /// السعر الفعلي الذي يدخل في الفاتورة.
  ///
  /// unitPriceOverride له الأولوية للحفاظ على
  /// التوافق مع Held Sales والكود الحالي.
  double get unitPrice {
    return unitPriceOverride ??
        selectedPrice;
  }

  // ===========================================================================
  // TOTALS
  // ===========================================================================

  /// القطع التي تُخصم من المخزن: كارتون × قطع الكارتون + القطع المفردة.
  double get billedPieces {
    final factor = unitFactor <= 0 ? 1.0 : unitFactor;
    final cartons = quantity < 0 ? 0 : quantity;
    final loose = loosePieces < 0 ? 0 : loosePieces;
    return cartons * factor + loose;
  }

  double get grossTotal {
    return unitPrice * billedPieces;
  }

  double get discountAmount {
    if (discountPercent <= 0) {
      return 0;
    }

    return grossTotal *
        discountPercent /
        100;
  }

  double get total {
    final result =
        grossTotal - discountAmount;

    if (result < 0) {
      return 0;
    }

    return result;
  }

  // ===========================================================================
  // PRICE BY TYPE
  // ===========================================================================

  double priceForType(
      PriceType type,
      ) {
    switch (type) {
      case PriceType.cost:
        return costPrice;

      case PriceType.representative:
        return representativePrice;

      case PriceType.wholesale:
        return wholesalePrice;

      case PriceType.retail:
        return retailPrice;
    }
  }

  // ===========================================================================
  // COPY WITH
  // ===========================================================================

  CartItemModel copyWith({
    ProductModel? product,

    String? variantId,
    bool clearVariantId = false,

    String? unitId,
    bool clearUnitId = false,

    double? unitFactor,

    int? quantity,

    int? loosePieces,

    PriceType? priceType,

    double? unitPriceOverride,
    bool clearUnitPriceOverride = false,

    double? costPriceOverride,
    bool clearCostPriceOverride = false,

    double? representativePriceOverride,
    bool clearRepresentativePriceOverride =
    false,

    double? wholesalePriceOverride,
    bool clearWholesalePriceOverride = false,

    double? retailPriceOverride,
    bool clearRetailPriceOverride = false,

    double? discountPercent,

    String? notes,
  }) {
    return CartItemModel(
      product:
      product ?? this.product,

      variantId: clearVariantId
          ? null
          : variantId ?? this.variantId,

      unitId: clearUnitId
          ? null
          : unitId ?? this.unitId,

      unitFactor: unitFactor ?? this.unitFactor,

      quantity:
      quantity ?? this.quantity,

      loosePieces:
      loosePieces ?? this.loosePieces,

      priceType:
      priceType ?? this.priceType,

      unitPriceOverride:
      clearUnitPriceOverride
          ? null
          : unitPriceOverride ??
          this.unitPriceOverride,

      costPriceOverride:
      clearCostPriceOverride
          ? null
          : costPriceOverride ??
          this.costPriceOverride,

      representativePriceOverride:
      clearRepresentativePriceOverride
          ? null
          : representativePriceOverride ??
          this.representativePriceOverride,

      wholesalePriceOverride:
      clearWholesalePriceOverride
          ? null
          : wholesalePriceOverride ??
          this.wholesalePriceOverride,

      retailPriceOverride:
      clearRetailPriceOverride
          ? null
          : retailPriceOverride ??
          this.retailPriceOverride,

      discountPercent:
      discountPercent ??
          this.discountPercent,

      notes: notes ?? this.notes,
    );
  }
}