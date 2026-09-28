class CategoryModel {
  final String id;

  final String nameAr;
  final String nameEn;

  final String? parentId;

  final int level;

  final String? path;
  final String? imageUrl;

  final int orderIndex;

  final bool isActive;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CategoryModel({
    required this.id,
    required this.nameAr,
    this.nameEn = '',
    this.parentId,
    this.level = 0,
    this.path,
    this.imageUrl,
    this.orderIndex = 0,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory CategoryModel.fromApiJson(
      Map<String, dynamic> json,
      ) {
    return CategoryModel(
      id:
      json['id']?.toString() ??
          '',
      nameAr:
      json['name_ar']
          ?.toString() ??
          '',
      nameEn:
      json['name_en']
          ?.toString() ??
          '',
      parentId:
      json['parent_id']
          ?.toString(),
      level:
      _parseInt(
        json['level'],
      ),
      path:
      json['path']?.toString(),
      imageUrl:
      json['image_url']
          ?.toString(),
      orderIndex:
      _parseInt(
        json['order_index'],
      ),
      isActive:
      json['is_active'] !=
          false,
      createdAt:
      _parseDate(
        json['created_at'],
      ),
      updatedAt:
      _parseDate(
        json['updated_at'],
      ),
    );
  }

  static int _parseInt(
      dynamic value,
      ) {
    if (value is int) {
      return value;
    }

    return int.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
  }

  static DateTime? _parseDate(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    );
  }
}