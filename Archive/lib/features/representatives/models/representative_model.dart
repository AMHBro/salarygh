class RepresentativeModel {
  final String id;

  final String name;
  final String username;
  final String phone;

  final String officeName;
  final String officeAddress;
  final String officePhone;
  final String? locationLink;

  final double commissionPercentage;

  final String allowedPrices;

  /// 0 يعني بدون سقف ذمة.
  final double maxDebtLimit;

  final int invoicesCount;
  final int soldPieces;

  final double totalSales;

  final double totalCommission;
  final double paidCommission;
  final double remainingCommission;

  final bool isActive;

  final int serverVersion;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  RepresentativeModel({
    required Object id,
    required this.name,
    required this.username,
    this.phone = '',
    this.officeName = '',
    this.officeAddress = '',
    this.officePhone = '',
    this.locationLink,
    this.commissionPercentage = 0,
    this.allowedPrices = 'wholesale,representative,retail',
    this.maxDebtLimit = 0,
    this.invoicesCount = 0,
    this.soldPieces = 0,
    this.totalSales = 0,
    this.totalCommission = 0,
    this.paidCommission = 0,
    this.remainingCommission = 0,
    this.isActive = true,
    this.serverVersion = 0,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  }) : id = id.toString();

  RepresentativeModel copyWith({
    Object? id,
    String? name,
    String? username,
    String? phone,
    String? officeName,
    String? officeAddress,
    String? officePhone,
    String? locationLink,
    double? commissionPercentage,
    String? allowedPrices,
    double? maxDebtLimit,
    int? invoicesCount,
    int? soldPieces,
    double? totalSales,
    double? totalCommission,
    double? paidCommission,
    double? remainingCommission,
    bool? isActive,
    int? serverVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return RepresentativeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      officeName: officeName ?? this.officeName,
      officeAddress:
      officeAddress ?? this.officeAddress,
      officePhone:
      officePhone ?? this.officePhone,
      locationLink:
      locationLink ?? this.locationLink,
      commissionPercentage:
      commissionPercentage ??
          this.commissionPercentage,
      allowedPrices: allowedPrices ?? this.allowedPrices,
      maxDebtLimit: maxDebtLimit ?? this.maxDebtLimit,
      invoicesCount:
      invoicesCount ?? this.invoicesCount,
      soldPieces:
      soldPieces ?? this.soldPieces,
      totalSales:
      totalSales ?? this.totalSales,
      totalCommission:
      totalCommission ?? this.totalCommission,
      paidCommission:
      paidCommission ?? this.paidCommission,
      remainingCommission:
      remainingCommission ??
          this.remainingCommission,
      isActive:
      isActive ?? this.isActive,
      serverVersion:
      serverVersion ?? this.serverVersion,
      createdAt:
      createdAt ?? this.createdAt,
      updatedAt:
      updatedAt ?? this.updatedAt,
      deletedAt:
      deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toSyncJson() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'phone': phone,
      'office_name': officeName,
      'office_address': officeAddress,
      'office_phone': officePhone,
      'location_link': locationLink,
      'commission_percentage':
      commissionPercentage,
      'allowed_prices': allowedPrices,
      'max_debt_limit': maxDebtLimit,
      'is_active': isActive,
      'version': serverVersion,
      'created_at':
      createdAt?.toUtc().toIso8601String(),
      'updated_at':
      updatedAt?.toUtc().toIso8601String(),
      'deleted_at':
      deletedAt?.toUtc().toIso8601String(),
    };
  }
}