import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth_session.dart';
import '../auth/auth_user.dart';

class AuthStorage {
  static const offlineToken = 'local-offline';

  static const _storage =
  FlutterSecureStorage();

  static const _accessTokenKey =
      'auth_access_token';

  static const _refreshTokenKey =
      'auth_refresh_token';

  static const _userIdKey =
      'auth_user_id';

  static const _userEmailKey =
      'auth_user_email';

  static const _userNameKey =
      'auth_user_name';

  static const _userRoleKey =
      'auth_user_role';

  static const _branchIdKey =
      'auth_branch_id';

  static const _stationWarehouseKey =
      'station_warehouse_id';

  static const _publicAccessTokenKey =
      'public_access_token';

  static const _publicRefreshTokenKey =
      'public_refresh_token';

  Future<void> saveSession(
      AuthSession session,
      ) async {
    await Future.wait([
      _storage.write(
        key: _accessTokenKey,
        value: session.accessToken,
      ),
      _storage.write(
        key: _refreshTokenKey,
        value: session.refreshToken,
      ),
      _storage.write(
        key: _userIdKey,
        value: session.user.id,
      ),
      _storage.write(
        key: _userEmailKey,
        value: session.user.email,
      ),
      _storage.write(
        key: _userNameKey,
        value: session.user.name,
      ),
      _storage.write(
        key: _userRoleKey,
        value: session.user.role,
      ),
    ]);
  }

  Future<AuthSession?> readSession() async {
    final values =
    await Future.wait([
      _storage.read(
        key: _accessTokenKey,
      ),
      _storage.read(
        key: _refreshTokenKey,
      ),
      _storage.read(
        key: _userIdKey,
      ),
      _storage.read(
        key: _userEmailKey,
      ),
      _storage.read(
        key: _userNameKey,
      ),
      _storage.read(
        key: _userRoleKey,
      ),
    ]);

    final accessToken =
    values[0];

    final refreshToken =
    values[1];

    final userId =
    values[2];

    final userEmail =
    values[3];

    final userName =
    values[4];

    final userRole =
    values[5];

    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      return null;
    }

    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: AuthUser(
        id: userId,
        email: userEmail ?? '',
        name: userName ?? '',
        role: userRole ?? '',
      ),
    );
  }

  Future<String?> readAccessToken() {
    return _storage.read(
      key: _accessTokenKey,
    );
  }

  Future<String?> readRefreshToken() {
    return _storage.read(
      key: _refreshTokenKey,
    );
  }

  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(
        key: _accessTokenKey,
        value: accessToken,
      ),
      _storage.write(
        key: _refreshTokenKey,
        value: refreshToken,
      ),
    ]);
  }

  Future<void> saveBranchId(
      String branchId,
      ) async {
    final cleanBranchId =
    branchId.trim();

    if (cleanBranchId.isEmpty) {
      await clearBranchId();
      return;
    }

    await _storage.write(
      key: _branchIdKey,
      value: cleanBranchId,
    );
  }

  Future<String?> readBranchId() {
    return _storage.read(
      key: _branchIdKey,
    );
  }

  Future<String?> readStationWarehouseId() {
    return _storage.read(
      key: _stationWarehouseKey,
    );
  }

  Future<void> saveStationWarehouseId(String? warehouseId) async {
    final id = warehouseId?.trim() ?? '';
    if (id.isEmpty) {
      await _storage.delete(key: _stationWarehouseKey);
      return;
    }
    await _storage.write(
      key: _stationWarehouseKey,
      value: id,
    );
  }

  Future<void> savePublicSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(
      key: _publicAccessTokenKey,
      value: accessToken,
    );
    if (refreshToken.trim().isEmpty) {
      return;
    }
    await _storage.write(
      key: _publicRefreshTokenKey,
      value: refreshToken,
    );
  }

  Future<String?> readPublicAccessToken() {
    return _storage.read(
      key: _publicAccessTokenKey,
    );
  }

  Future<String?> readPublicRefreshToken() {
    return _storage.read(
      key: _publicRefreshTokenKey,
    );
  }

  Future<void> clearBranchId() async {
    await _storage.delete(
      key: _branchIdKey,
    );
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(
        key: _accessTokenKey,
      ),
      _storage.delete(
        key: _refreshTokenKey,
      ),
      _storage.delete(
        key: _userIdKey,
      ),
      _storage.delete(
        key: _userEmailKey,
      ),
      _storage.delete(
        key: _userNameKey,
      ),
      _storage.delete(
        key: _userRoleKey,
      ),
      _storage.delete(
        key: _branchIdKey,
      ),
      _storage.delete(
        key: _publicAccessTokenKey,
      ),
      _storage.delete(
        key: _publicRefreshTokenKey,
      ),
    ]);
  }
}