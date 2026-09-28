import 'product_variant_model.dart';

class ProductModel {
  /// Local UUID.
  final String id;

  /// UUID الموجود بالسيرفر.
  ///
  /// null = المنتج لم تتم مزامنته بعد.
  final String? serverId;

  final String barcode;
  final String? sku;

  final String name;
  final String nameEn;

  final String? categoryId;
  final String categoryName;

  final String? baseUnitId;

  /// Compatibility مؤقت.
  final String warehouse;

  /// Compatibility مؤقت.
  final int quantity;

  final String unit;

  final String description;

  final bool hasVariants;
  final bool hasExpiry;
  final bool hasSerial;

  final String? imageUrl;

  final double costPrice;
  final double representativePrice;
  final double wholesalePrice;
  final double retailPrice;

  final double minimumStock;

  /// كم قطعة داخل كارتون هذا المنتج.
  final double piecesPerCarton;

  final bool isActive;

  final int serverVersion;

  /// جميع Variants الخاصة بالمنتج.
  ///
  /// المنتج البسيط ممكن تبقى القائمة فارغة محلياً حالياً.
  ///
  /// المنتج متعدد الخيارات يحتوي أكثر من Variant.
  final List<ProductVariantModel> variants;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  const ProductModel({
    required this.id,
    this.serverId,
    this.barcode = '',
    this.sku,
    required this.name,
    this.nameEn = '',
    this.categoryId,
    String? categoryName,
    String? category,
    this.baseUnitId,
    this.warehouse = '',
    this.quantity = 0,
    this.unit = 'قطعة',
    this.description = '',
    this.hasVariants = false,
    this.hasExpiry = false,
    this.hasSerial = false,
    this.imageUrl,
    required this.costPrice,
    double? representativePrice,
    double? repPrice,
    required this.wholesalePrice,
    required this.retailPrice,
    this.minimumStock = 0,
    this.piecesPerCarton = 1,
    this.isActive = true,
    this.serverVersion = 0,
    this.variants = const [],
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  })  : categoryName =
      categoryName ??
          category ??
          '',
        representativePrice =
            representativePrice ??
                repPrice ??
                0;

  String get category {
    if (categoryName.trim().isEmpty) {
      return 'بدون تصنيف';
    }

    return categoryName;
  }

  double get repPrice {
    return representativePrice;
  }

  bool get isSynced {
    return serverId != null &&
        serverId!.trim().isNotEmpty;
  }

  bool get hasRealVariants {
    return hasVariants &&
        variants.isNotEmpty;
  }

  int get variantsCount {
    return variants.length;
  }

  ProductModel copyWith({
    String? id,
    String? serverId,
    String? barcode,
    String? sku,
    String? name,
    String? nameEn,
    String? categoryId,
    String? categoryName,
    String? baseUnitId,
    String? warehouse,
    int? quantity,
    String? unit,
    String? description,
    bool? hasVariants,
    bool? hasExpiry,
    bool? hasSerial,
    String? imageUrl,
    double? costPrice,
    double? representativePrice,
    double? wholesalePrice,
    double? retailPrice,
    double? minimumStock,
    double? piecesPerCarton,
    bool? isActive,
    int? serverVersion,
    List<ProductVariantModel>? variants,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return ProductModel(
      id:
      id ??
          this.id,
      serverId:
      serverId ??
          this.serverId,
      barcode:
      barcode ??
          this.barcode,
      sku:
      sku ??
          this.sku,
      name:
      name ??
          this.name,
      nameEn:
      nameEn ??
          this.nameEn,
      categoryId:
      categoryId ??
          this.categoryId,
      categoryName:
      categoryName ??
          this.categoryName,
      baseUnitId:
      baseUnitId ??
          this.baseUnitId,
      warehouse:
      warehouse ??
          this.warehouse,
      quantity:
      quantity ??
          this.quantity,
      unit:
      unit ??
          this.unit,
      description:
      description ??
          this.description,
      hasVariants:
      hasVariants ??
          this.hasVariants,
      hasExpiry:
      hasExpiry ??
          this.hasExpiry,
      hasSerial:
      hasSerial ??
          this.hasSerial,
      imageUrl:
      imageUrl ??
          this.imageUrl,
      costPrice:
      costPrice ??
          this.costPrice,
      representativePrice:
      representativePrice ??
          this.representativePrice,
      wholesalePrice:
      wholesalePrice ??
          this.wholesalePrice,
      retailPrice:
      retailPrice ??
          this.retailPrice,
      minimumStock:
      minimumStock ??
          this.minimumStock,
      piecesPerCarton:
      piecesPerCarton ??
          this.piecesPerCarton,
      isActive:
      isActive ??
          this.isActive,
      serverVersion:
      serverVersion ??
          this.serverVersion,
      variants:
      variants ??
          this.variants,
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

  /// Payload مطابق لعقد:
  ///
  /// POST /api/v1/products
  ///
  /// PATCH /api/v1/products/{id}
  Map<String, dynamic> toApiJson() {
    return {
      'name_ar':
      name.trim(),
      'name_en':
      nameEn.trim().isEmpty
          ? null
          : nameEn.trim(),
      'barcode':
      barcode.trim().isEmpty
          ? null
          : barcode.trim(),
      'sku':
      sku == null ||
          sku!.trim().isEmpty
          ? null
          : sku!.trim(),
      'category_id':
      categoryId,
      'base_unit_id':
      baseUnitId,
      'description':
      description.trim().isEmpty
          ? null
          : description.trim(),
      'min_stock_level':
      minimumStock,
      'has_variants':
      hasVariants,
      'has_expiry':
      hasExpiry,
      'has_serial':
      hasSerial,
      'image_url':
      imageUrl,
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
      'variants':
      hasVariants
          ? variants
          .where(
            (variant) =>
        variant.deletedAt ==
            null,
      )
          .map(
            (variant) =>
            variant.toApiJson(),
      )
          .toList()
          : <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> toCreateApiJson() {
    return toApiJson();
  }

  /// Payload المستخدم داخل Outbox.
  ///
  /// يحتوي معلومات محلية إضافية حتى نقدر
  /// نسترجع حالة المنتج كاملة Offline.
  Map<String, dynamic> toSyncJson() {
    return {
      'local_id':
      id,
      'server_id':
      serverId,
      ...toApiJson(),
      'category_name':
      categoryName.trim().isEmpty
          ? null
          : categoryName.trim(),
      'unit_name':
      unit,
      'is_active':
      isActive,
      'version':
      serverVersion,
      'local_variants':
      variants
          .map(
            (variant) =>
            variant.toSyncJson(),
      )
          .toList(),
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