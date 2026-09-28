import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_session.dart';
import 'auth_user.dart';
import '../storage/auth_storage.dart';

const Duration localLoginMaxAge = Duration(days: 14);

/// تجزئة آخر دخول ناجح على هذه الحاسبة، لكل موظف على حدة.
class LocalCredentials {
  static const _key = 'local_login_verifiers';

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _memory;
  final DateTime Function() _now;

  LocalCredentials({
    FlutterSecureStorage? storage,
    Map<String, String>? memory,
    DateTime Function()? now,
  })  : _storage = memory == null ? (storage ?? const FlutterSecureStorage()) : null,
        _memory = memory,
        _now = now ?? DateTime.now;

  Future<void> remember({
    required String login,
    required String password,
    required AuthUser user,
  }) async {
    final key = _loginKey(login);
    if (key.isEmpty || password.isEmpty || user.id.isEmpty) {
      return;
    }

    final records = await _read();
    records.removeWhere((row) => row['login'] == key);
    records.add({
      'login': key,
      'userId': user.id,
      'email': user.email,
      'name': user.name,
      'role': user.role,
      'passwordHash': BCrypt.hashpw(password, BCrypt.gensalt()),
      'verifiedAt': _now().toUtc().toIso8601String(),
    });
    await _write(records);
  }

  /// يعيد جلسة محلية إذا طابقت التجزئة وما زالت ضمن المهلة.
  Future<AuthSession?> openOffline({
    required String login,
    required String password,
  }) async {
    final key = _loginKey(login);
    final records = await _read();
    Map<String, String>? match;
    for (final row in records) {
      if (row['login'] == key) {
        match = row;
        break;
      }
    }
    if (match == null) {
      return null;
    }

    final verifiedAt = DateTime.tryParse(match['verifiedAt'] ?? '');
    if (verifiedAt == null || _now().toUtc().difference(verifiedAt.toUtc()) > localLoginMaxAge) {
      return null;
    }

    final hash = match['passwordHash'] ?? '';
    if (hash.isEmpty || !BCrypt.checkpw(password, hash)) {
      return null;
    }

    final session = AuthSession(
      accessToken: AuthStorage.offlineToken,
      refreshToken: AuthStorage.offlineToken,
      user: AuthUser(
        id: match['userId'] ?? '',
        email: match['email'] ?? key,
        name: (match['name'] ?? '').isEmpty ? key : match['name']!,
        role: match['role'] ?? '',
      ),
    );
    return session;
  }

  Future<List<Map<String, String>>> _read() async {
    final raw = _memory != null ? _memory[_key] : await _storage!.read(key: _key);
    if (raw == null || raw.trim().isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return [];
    }
    return [
      for (final row in decoded)
        if (row is Map)
          {
            for (final entry in row.entries)
              if (entry.key is String && entry.value != null) entry.key: '${entry.value}',
          },
    ];
  }

  Future<void> _write(List<Map<String, String>> records) async {
    final payload = jsonEncode(records);
    if (_memory != null) {
      _memory[_key] = payload;
      return;
    }
    await _storage!.write(key: _key, value: payload);
  }

  String _loginKey(String login) => login.trim().toLowerCase();
}
