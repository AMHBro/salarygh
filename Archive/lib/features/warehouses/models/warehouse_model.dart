enum WarehouseType {
  main,
  sub,
  virtual,
}

extension WarehouseTypeExtension on WarehouseType {
  String get databaseValue {
    switch (this) {
      case WarehouseType.main:
        return 'MAIN';

      case WarehouseType.sub:
        return 'SUB';

      case WarehouseType.virtual:
        return 'VIRTUAL';
    }
  }

  String get displayName {
    switch (this) {
      case WarehouseType.main:
        return 'رئيسي';

      case WarehouseType.sub:
        return 'فرعي';

      case WarehouseType.virtual:
        return 'افتراضي';
    }
  }

  static WarehouseType fromValue(
      String? value,
      ) {
    switch (
    value
        ?.trim()
        .toUpperCase()) {
      case 'MAIN':
        return WarehouseType.main;

      case 'VIRTUAL':
        return WarehouseType.virtual;

      case 'SUB':
      default:
        return WarehouseType.sub;
    }
  }
}

class WarehouseModel {
  /// Local UUID.
  final String id;

  /// Backend UUID.
  final String? serverId;

  final String name;

  final String? code;

  /// Backend Branch UUID.
  final String? branchId;

  /// Compatibility مؤقت مع الشاشة القديمة.
  final String branchName;

  final WarehouseType type;

  /// الحالة ترجع من السيرفر كنص.
  ///
  /// أمثلة مؤكدة:
  /// LOCAL
  /// DRAFT
  /// PENDING_APPROVAL
  /// ACTIVE
  final String status;

  /// Backend UUID للمخزن الأب.
  final String? parentWarehouseId;

  /// Backend UUID لمدير المخزن.
  final String? managerId;

  final String? address;

  /// Compatibility مؤقت مع الشاشة القديمة.
  final String location;

  final double? capacity;

  final String? notes;

  final String? rejectionReason;

  final int productsCount;

  final int totalQuantity;

  final int lowStockCount;

  /// Compatibility مع الكود القديم.
  final bool isMain;

  final bool isActive;

  final int serverVersion;

  final DateTime createdAt;

  final DateTime updatedAt;

  final DateTime? deletedAt;

  const WarehouseModel({
    required this.id,
    this.serverId,
    required this.name,
    this.code,
    this.branchId,
    this.branchName = '',
    this.type = WarehouseType.sub,
    this.status = 'LOCAL',
    this.parentWarehouseId,
    this.managerId,
    this.address,
    this.location = '',
    this.capacity,
    this.notes,
    this.rejectionReason,
    this.productsCount = 0,
    this.totalQuantity = 0,
    this.lowStockCount = 0,
    bool? isMain,
    required this.isActive,
    required this.serverVersion,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  }) : isMain =
      isMain ??
          type == WarehouseType.main;

  bool get isSynced =>
      serverId != null &&
          serverId!.trim().isNotEmpty;

  bool get isDraft =>
      status.toUpperCase() ==
          'DRAFT';

  bool get isPendingApproval =>
      status.toUpperCase() ==
          'PENDING_APPROVAL';

  bool get isServerActive =>
      status.toUpperCase() ==
          'ACTIVE';

  bool get canUseForRemoteInventory =>
      isSynced &&
          isServerActive;

  WarehouseModel copyWith({
    String? id,
    String? serverId,
    bool clearServerId = false,
    String? name,
    String? code,
    String? branchId,
    String? branchName,
    WarehouseType? type,
    String? status,
    String? parentWarehouseId,
    bool clearParentWarehouseId = false,
    String? managerId,
    bool clearManagerId = false,
    String? address,
    String? location,
    double? capacity,
    bool clearCapacity = false,
    String? notes,
    String? rejectionReason,
    bool clearRejectionReason = false,
    int? productsCount,
    int? totalQuantity,
    int? lowStockCount,
    bool? isMain,
    bool? isActive,
    int? serverVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    var resolvedType =
        type ?? this.type;

    if (isMain != null) {
      if (isMain) {
        resolvedType =
            WarehouseType.main;
      } else if (
      resolvedType ==
          WarehouseType.main) {
        resolvedType =
            WarehouseType.sub;
      }
    }

    return WarehouseModel(
      id:
      id ?? this.id,
      serverId:
      clearServerId
          ? null
          : serverId ??
          this.serverId,
      name:
      name ?? this.name,
      code:
      code ?? this.code,
      branchId:
      branchId ??
          this.branchId,
      branchName:
      branchName ??
          this.branchName,
      type:
      resolvedType,
      status:
      status ?? this.status,
      parentWarehouseId:
      clearParentWarehouseId
          ? null
          : parentWarehouseId ??
          this.parentWarehouseId,
      managerId:
      clearManagerId
          ? null
          : managerId ??
          this.managerId,
      address:
      address ??
          this.address,
      location:
      location ??
          this.location,
      capacity:
      clearCapacity
          ? null
          : capacity ??
          this.capacity,
      notes:
      notes ?? this.notes,
      rejectionReason:
      clearRejectionReason
          ? null
          : rejectionReason ??
          this.rejectionReason,
      productsCount:
      productsCount ??
          this.productsCount,
      totalQuantity:
      totalQuantity ??
          this.totalQuantity,
      lowStockCount:
      lowStockCount ??
          this.lowStockCount,
      isMain:
      resolvedType ==
          WarehouseType.main,
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
      clearDeletedAt
          ? null
          : deletedAt ??
          this.deletedAt,
    );
  }

  /// Payload خاص بالـOutbox المحلي.
  ///
  /// ليس Request Body مباشر للـBackend.
  Map<String, dynamic> toSyncJson() {
    return {
      'id': id,
      'server_id': serverId,
      'name': name,
      'code': code,
      'branch_id': branchId,
      'type': type.databaseValue,
      'status': status,
      'parent_warehouse_id':
      parentWarehouseId,
      'manager_id': managerId,
      'address': address,
      'capacity': capacity,
      'notes': notes,
      'rejection_reason':
      rejectionReason,
      'is_main':
      type ==
          WarehouseType.main,
      'is_active': isActive,
      'version': serverVersion,
      'created_at':
      createdAt
          .toUtc()
          .toIso8601String(),
      'updated_at':
      updatedAt
          .toUtc()
          .toIso8601String(),
      'deleted_at':
      deletedAt
          ?.toUtc()
          .toIso8601String(),
    };
  }
}