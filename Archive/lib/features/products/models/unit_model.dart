class UnitModel {
  final String id;

  final String nameAr;
  final String nameEn;
  final String symbol;

  final String? parentUnitId;

  final double conversionFactor;

  final bool isBaseUnit;
  final bool isActive;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UnitModel({
    required this.id,
    required this.nameAr,
    this.nameEn = '',
    required this.symbol,
    this.parentUnitId,
    this.conversionFactor = 1,
    this.isBaseUnit = false,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory UnitModel.fromApiJson(
      Map<String, dynamic> json,
      ) {
    return UnitModel(
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
      symbol:
      json['symbol']
          ?.toString() ??
          '',
      parentUnitId:
      json['parent_unit_id']
          ?.toString(),
      conversionFactor:
      double.tryParse(
        json['conversion_factor']
            ?.toString() ??
            '1',
      ) ??
          1,
      isBaseUnit:
      json['is_base_unit'] ==
          true,
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