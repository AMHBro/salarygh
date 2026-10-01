import 'dart:convert';

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
  return _isManagerRole(role);
}

bool canApproveWarehouseDelete(String? role) {
  return _isManagerRole(role);
}

bool _isManagerRole(String? role) {
  switch ((role ?? '').trim().toUpperCase()) {
    case 'ADMIN':
    case 'SUPER_ADMIN':
    case 'MANAGER':
      return true;
    default:
      return false;
  }
}

/// الدور المحفوظ، ثم الدور داخل رمز الدخول إذا كانت الجلسة القديمة بلا دور.
String resolveSessionRole({
  String? storedRole,
  String? accessToken,
}) {
  final stored = (storedRole ?? '').trim();
  if (stored.isNotEmpty) {
    return stored;
  }
  final token = (accessToken ?? '').trim();
  final parts = token.split('.');
  if (parts.length < 2) {
    return '';
  }
  try {
    final normalized = base64Url.normalize(parts[1]);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is Map) {
      return decoded['role']?.toString().trim() ?? '';
    }
  } catch (_) {}
  return '';
}