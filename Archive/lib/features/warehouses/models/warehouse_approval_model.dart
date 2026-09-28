class WarehouseApprovalsResult {
  final int totalPending;
  final List<WarehouseApprovalModel> warehouses;

  const WarehouseApprovalsResult({
    required this.totalPending,
    required this.warehouses,
  });

  factory WarehouseApprovalsResult.fromJson(
      Map<String, dynamic> json,
      ) {
    final rawWarehouses = json['warehouses'];

    return WarehouseApprovalsResult(
      totalPending: _toInt(
        json['total_pending'],
      ),
      warehouses: rawWarehouses is List
          ? rawWarehouses
          .whereType<Map>()
          .map(
            (item) => WarehouseApprovalModel.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
          .toList()
          : const [],
    );
  }

  static int _toInt(
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
}

class WarehouseApprovalModel {
  final String id;

  final String? code;
  final String name;

  final String type;
  final String status;

  final String branchId;
  final String? parentWarehouseId;

  final String? managerId;

  final String? address;
  final double? capacity;
  final String? notes;

  final String? rejectionReason;

  final String createdBy;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String branchName;

  final String creatorId;
  final String creatorUsername;

  const WarehouseApprovalModel({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.status,
    required this.branchId,
    required this.parentWarehouseId,
    required this.managerId,
    required this.address,
    required this.capacity,
    required this.notes,
    required this.rejectionReason,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.branchName,
    required this.creatorId,
    required this.creatorUsername,
  });

  factory WarehouseApprovalModel.fromJson(
      Map<String, dynamic> json,
      ) {
    final branch = _map(
      json['branch'],
    );

    final creator = _map(
      json['creator'],
    );

    return WarehouseApprovalModel(
      id: _string(
        json['id'],
      ),
      code: _nullableString(
        json['code'],
      ),
      name: _string(
        json['name'],
      ),
      type: _string(
        json['type'],
      ),
      status: _string(
        json['status'],
      ),
      branchId: _string(
        json['branch_id'],
      ),
      parentWarehouseId: _nullableString(
        json['parent_warehouse_id'],
      ),
      managerId: _nullableString(
        json['manager_id'],
      ),
      address: _nullableString(
        json['address'],
      ),
      capacity: _double(
        json['capacity'],
      ),
      notes: _nullableString(
        json['notes'],
      ),
      rejectionReason: _nullableString(
        json['rejection_reason'],
      ),
      createdBy: _string(
        json['created_by'],
      ),
      createdAt: _date(
        json['created_at'],
      ),
      updatedAt: _date(
        json['updated_at'],
      ),
      branchName: _string(
        branch['name'],
      ),
      creatorId: _string(
        creator['id'],
      ),
      creatorUsername: _string(
        creator['username'],
      ),
    );
  }

  bool get isPending {
    return status.trim().toUpperCase() ==
        'PENDING_APPROVAL';
  }

  String get typeDisplayName {
    switch (type.trim().toUpperCase()) {
      case 'MAIN':
        return 'مخزن رئيسي';

      case 'SUB':
        return 'مخزن فرعي';

      case 'VIRTUAL':
        return 'مخزن افتراضي';

      default:
        return type;
    }
  }

  static Map<String, dynamic> _map(
      dynamic value,
      ) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    return const {};
  }

  static String _string(
      dynamic value,
      ) {
    return value?.toString().trim() ?? '';
  }

  static String? _nullableString(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    return text.isEmpty
        ? null
        : text;
  }

  static double? _double(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    );
  }

  static DateTime? _date(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    )?.toLocal();
  }
}