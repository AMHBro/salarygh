class BranchModel {
  final String id;
  final String code;
  final String name;
  final String type;
  final String status;
  final String companyId;
  final String? managerId;
  final String address;
  final String phone;
  final String notes;

  const BranchModel({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.status,
    required this.companyId,
    required this.managerId,
    required this.address,
    required this.phone,
    required this.notes,
  });

  bool get isActive =>
      status.toUpperCase() == 'ACTIVE';

  factory BranchModel.fromJson(
      Map<String, dynamic> json,
      ) {
    return BranchModel(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      status:
      json['status']?.toString() ?? '',
      companyId:
      json['company_id']?.toString() ?? '',
      managerId:
      json['manager_id']?.toString(),
      address:
      json['address']?.toString() ?? '',
      phone:
      json['phone']?.toString() ?? '',
      notes:
      json['notes']?.toString() ?? '',
    );
  }
}