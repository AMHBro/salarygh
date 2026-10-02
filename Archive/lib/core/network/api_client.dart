import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/auth_storage.dart';
import 'server_endpoint.dart';

class ApiClient {
  static const String baseUrl = ServerEndpoint.defaultInternet;

  final AuthStorage authStorage;

  late final Dio _dio;
  late final Dio _refreshDio;

  Future<bool>? _refreshFuture;

  ApiClient({
    required this.authStorage,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout:
        const Duration(
          seconds: 20,
        ),
        receiveTimeout:
        const Duration(
          seconds: 30,
        ),
        sendTimeout:
        const Duration(
          seconds: 30,
        ),
        contentType:
        Headers.jsonContentType,
        responseType:
        ResponseType.json,
      ),
    );

    _refreshDio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout:
        const Duration(
          seconds: 20,
        ),
        receiveTimeout:
        const Duration(
          seconds: 30,
        ),
        sendTimeout:
        const Duration(
          seconds: 30,
        ),
        contentType:
        Headers.jsonContentType,
        responseType:
        ResponseType.json,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (
            options,
            handler,
            ) async {
          final requiresAuth =
              options.extra['requiresAuth'] !=
                  false;

          final requiresBranch =
              options.extra['requiresBranch'] !=
                  false;

          if (requiresAuth) {
            final token =
            await authStorage
                .readAccessToken();

            if (token != null &&
                token.isNotEmpty) {
              options.headers[
              'Authorization'] =
              'Bearer $token';
            }
          }

          if (requiresBranch) {
            final branchId =
            await authStorage
                .readBranchId();

            if (branchId != null &&
                branchId.isNotEmpty) {
              options.headers[
              'X-Branch-ID'] =
                  branchId;
            }
          }

          options.baseUrl =
              await ServerEndpoint.instance.activeBaseUrl();

          handler.next(
            options,
          );
        },

        onError: (
            error,
            handler,
            ) async {
          final statusCode =
              error.response
                  ?.statusCode;

          final options =
              error.requestOptions;

          final requiresAuth =
              options.extra['requiresAuth'] !=
                  false;

          final alreadyRetried =
              options.extra['authRetry'] ==
                  true;

          final isAuthEndpoint =
          _isAuthEndpoint(
            options.path,
          );

          if (statusCode != 401 ||
              !requiresAuth ||
              alreadyRetried ||
              isAuthEndpoint) {
            handler.next(
              error,
            );

            return;
          }

          final refreshed =
          await _refreshToken();

          if (!refreshed) {
            handler.next(
              error,
            );

            return;
          }

          try {
            final newToken =
            await authStorage
                .readAccessToken();

            if (newToken == null ||
                newToken.isEmpty) {
              handler.next(
                error,
              );

              return;
            }

            options.headers[
            'Authorization'] =
            'Bearer $newToken';

            options.extra[
            'authRetry'] =
            true;

            final response =
            await _dio.fetch<dynamic>(
              options,
            );

            handler.resolve(
              response,
            );
          } on DioException catch (
          retryError
          ) {
          handler.next(
          retryError,
          );
          } catch (_) {
          handler.next(
          error,
          );
          }
        },
      ),
    );
  }

  Future<bool> _refreshToken() {
    final existing =
        _refreshFuture;

    if (existing != null) {
      return existing;
    }

    final future =
    _performRefresh();

    _refreshFuture =
        future;

    future.whenComplete(
          () {
        _refreshFuture =
        null;
      },
    );

    return future;
  }

  Future<bool>
  _performRefresh() async {
    final refreshToken =
    await authStorage
        .readRefreshToken();

    if (refreshToken == null ||
        refreshToken.isEmpty) {
      await authStorage.clear();

      return false;
    }

    try {
      _refreshDio.options.baseUrl =
          await ServerEndpoint.instance.activeBaseUrl();
      final response =
      await _refreshDio.post(
        '/auth/refresh',
        data: {
          'refreshToken':
          refreshToken,
        },
      );

      final data =
          response.data;

      if (data
      is! Map<String, dynamic>) {
        await authStorage.clear();

        return false;
      }

      final newAccessToken =
      data['accessToken']
          ?.toString();

      final newRefreshToken =
          data['refreshToken']
              ?.toString() ??
              refreshToken;

      if (newAccessToken == null ||
          newAccessToken.isEmpty) {
        await authStorage.clear();

        return false;
      }

      await authStorage.updateTokens(
        accessToken:
        newAccessToken,
        refreshToken:
        newRefreshToken,
      );

      return true;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        await authStorage.clear();
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  bool _isAuthEndpoint(
      String path,
      ) {
    return path.contains(
      '/auth/login',
    ) ||
        path.contains(
          '/auth/register',
        ) ||
        path.contains(
          '/auth/refresh',
        );
  }

  Future<Response<dynamic>> get(
      String path, {
        Map<String, dynamic>?
        queryParameters,
        bool requiresAuth = true,
        bool requiresBranch = true,
      }) {
    return _dio.get(
      path,
      queryParameters:
      queryParameters,
      options: Options(
        extra: {
          'requiresAuth':
          requiresAuth,
          'requiresBranch':
          requiresBranch,
        },
      ),
    );
  }

  Future<Response<dynamic>> post(
      String path, {
        Object? data,
        Map<String, dynamic>?
        queryParameters,
        bool requiresAuth = true,
        bool requiresBranch = true,
      }) {
    return _dio.post(
      path,
      data: data,
      queryParameters:
      queryParameters,
      options: Options(
        extra: {
          'requiresAuth':
          requiresAuth,
          'requiresBranch':
          requiresBranch,
        },
      ),
    );
  }

  Future<Response<dynamic>> patch(
      String path, {
        Object? data,
        Map<String, dynamic>?
        queryParameters,
        bool requiresAuth = true,
        bool requiresBranch = true,
      }) {
    return _dio.patch(
      path,
      data: data,
      queryParameters:
      queryParameters,
      options: Options(
        extra: {
          'requiresAuth':
          requiresAuth,
          'requiresBranch':
          requiresBranch,
        },
      ),
    );
  }

  Future<Response<dynamic>> put(
      String path, {
        Object? data,
        Map<String, dynamic>?
        queryParameters,
        bool requiresAuth = true,
        bool requiresBranch = true,
      }) {
    return _dio.put(
      path,
      data: data,
      queryParameters:
      queryParameters,
      options: Options(
        extra: {
          'requiresAuth':
          requiresAuth,
          'requiresBranch':
          requiresBranch,
        },
      ),
    );
  }

  Future<Response<dynamic>> delete(
      String path, {
        Object? data,
        Map<String, dynamic>?
        queryParameters,
        bool requiresAuth = true,
        bool requiresBranch = true,
      }) {
    return _dio.delete(
      path,
      data: data,
      queryParameters:
      queryParameters,
      options: Options(
        extra: {
          'requiresAuth':
          requiresAuth,
          'requiresBranch':
          requiresBranch,
        },
      ),
    );
  }
}