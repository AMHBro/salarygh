class ProductVariantModel {
  /// UUID محلي ثابت.
  final String id;

  /// UUID الخاص بالـ Variant داخل السيرفر.
  final String? serverId;

  /// UUID المنتج الرئيسي محلياً.
  final String productId;

  final String barcode;
  final String? sku;

  /// Attributes مرنة.
  ///
  /// أمثلة:
  ///
  /// flavor -> برتقال
  ///
  /// color -> أسود
  /// size -> XL
  final Map<String, String> attributes;

  final double costPrice;
  final double representativePrice;
  final double wholesalePrice;
  final double retailPrice;

  final double weightedAverageCost;
  final double lastPurchasePrice;

  final bool isActive;

  final int serverVersion;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  const ProductVariantModel({
    required this.id,
    this.serverId,
    required this.productId,
    this.barcode = '',
    this.sku,
    this.attributes = const {},
    required this.costPrice,
    required this.representativePrice,
    required this.wholesalePrice,
    required this.retailPrice,
    this.weightedAverageCost = 0,
    this.lastPurchasePrice = 0,
    this.isActive = true,
    this.serverVersion = 0,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  bool get isSynced {
    return serverId != null &&
        serverId!.trim().isNotEmpty;
  }

  String get displayName {
    if (attributes.isEmpty) {
      return 'الخيار الرئيسي';
    }

    return attributes.values
        .where(
          (value) => value.trim().isNotEmpty,
    )
        .join(' - ');
  }

  ProductVariantModel copyWith({
    String? id,
    String? serverId,
    String? productId,
    String? barcode,
    String? sku,
    Map<String, String>? attributes,
    double? costPrice,
    double? representativePrice,
    double? wholesalePrice,
    double? retailPrice,
    double? weightedAverageCost,
    double? lastPurchasePrice,
    bool? isActive,
    int? serverVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return ProductVariantModel(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      productId: productId ?? this.productId,
      barcode: barcode ?? this.barcode,
      sku: sku ?? this.sku,
      attributes: attributes ?? this.attributes,
      costPrice: costPrice ?? this.costPrice,
      representativePrice:
      representativePrice ??
          this.representativePrice,
      wholesalePrice:
      wholesalePrice ??
          this.wholesalePrice,
      retailPrice:
      retailPrice ??
          this.retailPrice,
      weightedAverageCost:
      weightedAverageCost ??
          this.weightedAverageCost,
      lastPurchasePrice:
      lastPurchasePrice ??
          this.lastPurchasePrice,
      isActive:
      isActive ??
          this.isActive,
      serverVersion:
      serverVersion ??
          this.serverVersion,
      createdAt:
      createdAt ??
          this.createdAt,
      updatedAt:
      updatedAt ??
          this.updatedAt,
      deletedAt:
      deletedAt ??
          this.deletedAt,
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'barcode':
      barcode.trim().isEmpty
          ? null
          : barcode.trim(),
      'sku':
      sku == null ||
          sku!.trim().isEmpty
          ? null
          : sku!.trim(),
      'attributes':
      Map<String, String>.from(
        attributes,
      ),
      'pricing': {
        'cost_price':
        costPrice,
        'rep_price':
        representativePrice,
        'wholesale_price':
        wholesalePrice,
        'retail_price':
        retailPrice,
      },
    };
  }

  Map<String, dynamic> toSyncJson() {
    return {
      'local_id':
      id,
      'server_id':
      serverId,
      'product_local_id':
      productId,
      ...toApiJson(),
      'weighted_average_cost':
      weightedAverageCost,
      'last_purchase_price':
      lastPurchasePrice,
      'is_active':
      isActive,
      'version':
      serverVersion,
      'created_at':
      createdAt
          ?.toUtc()
          .toIso8601String(),
      'updated_at':
      updatedAt
          ?.toUtc()
          .toIso8601String(),
      'deleted_at':
      deletedAt
          ?.toUtc()
          .toIso8601String(),
    };
  }
}