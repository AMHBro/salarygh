class AuthUser {
  final String id;
  final String email;
  final String name;
  final String role;

  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    this.role = '',
  });

  factory AuthUser.fromJson(
      Map<String, dynamic> json,
      ) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      email:
      json['email']?.toString() ?? '',
      name:
      json['name']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
    };
  }
}

/// رأس المال وتقارير الخادم للمدير والمسؤول فقط.
bool canOpenFinanceReports(String? role) {
  switch ((role ?? '').trim().toUpperCase()) {
    case 'ADMIN':
    case 'SUPER_ADMIN':
    case 'MANAGER':
      return true;
    default:
      return false;
  }
}