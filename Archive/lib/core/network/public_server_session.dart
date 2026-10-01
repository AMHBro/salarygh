import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/auth_storage.dart';
import 'server_endpoint.dart';

/// جلسة السيرفر العام (Railway) منفصلة عن رمز الحاسبة المحلي.
class PublicServerSession {
  PublicServerSession._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 45),
      headers: {
        'Content-Type': 'application/json',
      },
    ),
  );

  static Future<void> remember({
    required String email,
    required String password,
  }) async {
    final base = await ServerEndpoint.instance.publicBaseUrl();
    final response = await _dio.post(
      '$base/auth/login',
      data: {
        'email': email.trim(),
        'password': password,
      },
    );
    final body = response.data;
    if (body is! Map) {
      return;
    }
    final access = body['accessToken']?.toString() ?? '';
    final refresh = body['refreshToken']?.toString() ?? '';
    if (access.isEmpty) {
      return;
    }
    await AuthStorage().savePublicSession(
      accessToken: access,
      refreshToken: refresh,
    );
    debugPrint('[STORE] public session saved');
  }

  static Future<Response<dynamic>> send({
    required String method,
    required String path,
    Object? data,
    Map<String, dynamic>? query,
    bool retried = false,
  }) async {
    final base = await ServerEndpoint.instance.publicBaseUrl();
    final access = await AuthStorage().readPublicAccessToken();
    if (access == null || access.isEmpty) {
      throw StateError('لا توجد جلسة للسيرفر العام');
    }

    try {
      return await _dio.request<dynamic>(
        '$base$path',
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {
            'Authorization': 'Bearer $access',
          },
        ),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 && !retried) {
        final refreshed = await _refresh();
        if (refreshed) {
          return send(
            method: method,
            path: path,
            data: data,
            query: query,
            retried: true,
          );
        }
      }
      rethrow;
    }
  }

  static Future<bool> _refresh() async {
    final refresh = await AuthStorage().readPublicRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      return false;
    }
    final base = await ServerEndpoint.instance.publicBaseUrl();
    try {
      final response = await _dio.post(
        '$base/auth/refresh',
        data: {
          'refreshToken': refresh,
        },
      );
      final body = response.data;
      if (body is! Map) {
        return false;
      }
      final access = body['accessToken']?.toString() ?? '';
      if (access.isEmpty) {
        return false;
      }
      await AuthStorage().savePublicSession(
        accessToken: access,
        refreshToken: refresh,
      );
      return true;
    } catch (error) {
      debugPrint('[STORE] public refresh failed: $error');
      return false;
    }
  }
}
