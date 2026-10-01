import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OfficeRole {
  static const master = 'master';
  static const branch = 'branch';

  static const _kindKey = 'office_role';
  static const _baseKey = 'office_lan_base';
  static const _tokenKey = 'office_lan_token';

  OfficeRole({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static final OfficeRole instance = OfficeRole();

  final FlutterSecureStorage _storage;

  Future<bool> isBranch() async {
    final kind = await _storage.read(key: _kindKey);
    return kind == branch;
  }

  Future<String> readBase() async {
    final value = (await _storage.read(key: _baseKey))?.trim() ?? '';
    if (value.isEmpty) {
      return 'http://127.0.0.1:3920';
    }
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  Future<String> readToken() async {
    return (await _storage.read(key: _tokenKey))?.trim() ?? '';
  }

  Future<void> save({
    required bool branchOffice,
    required String baseUrl,
    required String token,
  }) async {
    final base = baseUrl.trim();
    if (branchOffice && base.isEmpty) {
      throw StateError('عنوان الحاسبة الأساسية مطلوب للحاسبة الفرعية.');
    }
    if (branchOffice && token.trim().isEmpty) {
      throw StateError('رمز الشبكة المحلية مطلوب للحاسبة الفرعية.');
    }
    await _storage.write(
      key: _kindKey,
      value: branchOffice ? branch : master,
    );
    await _storage.write(key: _baseKey, value: base);
    await _storage.write(key: _tokenKey, value: token.trim());
  }
}
