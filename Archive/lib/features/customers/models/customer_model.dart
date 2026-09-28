class CustomerModel {
  /// Local UUID
  final String id;

  /// Backend UUID
  final String? serverId;

  final String name;
  final String phone;
  final String email;
  final String address;

  /// RETAIL | WHOLESALE
  final String type;

  /// العائلة أو التصنيف.
  final String groupName;

  /// معرف المندوب المحلي.
  final String? representativeId;

  final double creditLimit;

  final String? notes;

  final double totalPurchases;
  final double totalPaid;
  final double balance;
  final double balanceUsd;

  final int invoicesCount;

  final DateTime? lastPurchaseDate;

  final bool isActive;
  final int serverVersion;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  CustomerModel({
    required Object id,
    this.serverId,
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.type = 'RETAIL',
    this.groupName = '',
    this.representativeId,
    this.creditLimit = 0,
    this.notes,
    this.totalPurchases = 0,
    this.totalPaid = 0,
    this.balance = 0,
    this.balanceUsd = 0,
    this.invoicesCount = 0,
    this.lastPurchaseDate,
    this.isActive = true,
    this.serverVersion = 0,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  }) : id = id.toString();

  bool get isSynced =>
      serverId != null &&
          serverId!.trim().isNotEmpty;

  bool get isWholesale =>
      type.trim().toUpperCase() ==
          'WHOLESALE';

  bool get isRetail =>
      !isWholesale;

  CustomerModel copyWith({
    Object? id,
    String? serverId,
    bool clearServerId = false,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? type,
    String? groupName,
    String? representativeId,
    bool clearRepresentativeId = false,
    double? creditLimit,
    String? notes,
    bool clearNotes = false,
    double? totalPurchases,
    double? totalPaid,
    double? balance,
    double? balanceUsd,
    int? invoicesCount,
    DateTime? lastPurchaseDate,
    bool clearLastPurchaseDate = false,
    bool? isActive,
    int? serverVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      serverId: clearServerId
          ? null
          : serverId ?? this.serverId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      type: type ?? this.type,
      groupName: groupName ?? this.groupName,
      representativeId: clearRepresentativeId
          ? null
          : representativeId ?? this.representativeId,
      creditLimit:
      creditLimit ?? this.creditLimit,
      notes: clearNotes
          ? null
          : notes ?? this.notes,
      totalPurchases:
      totalPurchases ??
          this.totalPurchases,
      totalPaid:
      totalPaid ?? this.totalPaid,
      balance:
      balance ?? this.balance,
      balanceUsd:
      balanceUsd ?? this.balanceUsd,
      invoicesCount:
      invoicesCount ??
          this.invoicesCount,
      lastPurchaseDate:
      clearLastPurchaseDate
          ? null
          : lastPurchaseDate ??
          this.lastPurchaseDate,
      isActive:
      isActive ?? this.isActive,
      serverVersion:
      serverVersion ??
          this.serverVersion,
      createdAt:
      createdAt ?? this.createdAt,
      updatedAt:
      updatedAt ?? this.updatedAt,
      deletedAt:
      clearDeletedAt
          ? null
          : deletedAt ??
          this.deletedAt,
    );
  }

  Map<String, dynamic> toSyncJson() {
    return {
      'id': id,
      'server_id': serverId,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'type': type,
      'credit_limit': creditLimit,
      'notes': notes,
      'is_active': isActive,
      'version': serverVersion,
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