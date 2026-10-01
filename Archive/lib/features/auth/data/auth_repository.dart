import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/auth/auth_session.dart';
import '../../../core/auth/local_credentials.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/public_server_session.dart';
import '../../../core/storage/auth_storage.dart';
import '../../branches/data/branches_remote_repository.dart';

class AuthRepository {
  final ApiClient apiClient;
  final AuthStorage authStorage;
  final BranchesRemoteRepository branchesRepository;
  final LocalCredentials localCredentials;

  AuthRepository({
    required this.apiClient,
    required this.authStorage,
    required this.branchesRepository,
    LocalCredentials? localCredentials,
  }) : localCredentials = localCredentials ?? LocalCredentials();

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email
        .replaceAll('\u200E', '')
        .replaceAll('\u200F', '')
        .replaceAll('\u200B', '')
        .replaceAll('\u200C', '')
        .replaceAll('\u200D', '')
        .trim();

    final cleanPassword = password
        .replaceAll('\u200E', '')
        .replaceAll('\u200F', '')
        .replaceAll('\u200B', '')
        .replaceAll('\u200C', '')
        .replaceAll('\u200D', '')
        .trim();

    if (cleanEmail.isEmpty) {
      throw StateError(
        'أدخل اسم الدخول.',
      );
    }

    if (cleanPassword.isEmpty) {
      throw StateError(
        'أدخل كلمة المرور.',
      );
    }

    if (kDebugMode) {
      debugPrint(
        'LOGIN -> email="$cleanEmail", passwordLength=${cleanPassword.length}',
      );
    }

    try {
      return await _loginOnServer(
        email: cleanEmail,
        password: cleanPassword,
      );
    } on DioException catch (error) {
      if (_serverUnreachable(error)) {
        final offline = await _loginOffline(
          login: cleanEmail,
          password: cleanPassword,
        );
        if (offline != null) {
          return offline;
        }

        throw StateError(
          'السيرفر متوقف. الدخول المحلي متاح بعد دخول ناجح من هذه الحاسبة خلال آخر 14 يوماً.',
        );
      }

      throw StateError(
        _messageFromDio(
          error,
        ),
      );
    }
  }

  Future<AuthSession> enterLocalOffice() {
    throw StateError(
      'الدخول المحلي يحتاج كلمة المرور بعد دخول ناجح من هذه الحاسبة.',
    );
  }

  Future<bool> ensureOnlineSession() async {
    final token =
        await authStorage.readAccessToken();

    return token != null &&
        token.isNotEmpty &&
        token != AuthStorage.offlineToken;
  }

  Future<AuthSession> _loginOnServer({
    required String email,
    required String password,
  }) async {
    try {
      final response = await apiClient.post(
        '/auth/login',
        requiresAuth: false,
        requiresBranch: false,
        data: {
          'email': email,
          'password': password,
        },
      );

      if (kDebugMode) {
        debugPrint(
          'LOGIN -> status=${response.statusCode}',
        );
      }

      final rawData = response.data;

      if (rawData is! Map<String, dynamic>) {
        throw StateError(
          'استجابة تسجيل الدخول غير صالحة.',
        );
      }

      final session = AuthSession.fromJson(
        rawData,
      );

      if (session.accessToken.isEmpty ||
          session.refreshToken.isEmpty) {
        throw StateError(
          'لم يرسل السيرفر بيانات الجلسة بشكل صحيح.',
        );
      }

      //
      // أولاً نحفظ التوكن حتى GET /branches
      // يقدر يستخدم Authorization.
      //
      await authStorage.saveSession(
        session,
      );

      try {
        //
        // نجيب الفروع من السيرفر
        // ونختار أول فرع ACTIVE.
        //
        final activeBranch =
        await branchesRepository
            .initializeActiveBranch();

        if (activeBranch == null) {
          await authStorage.clear();

          throw StateError(
            'لا يوجد فرع فعال مرتبط بالنظام.',
          );
        }

        if (kDebugMode) {
          debugPrint(
            'BRANCH -> ${activeBranch.name}',
          );

          debugPrint(
            'BRANCH ID -> ${activeBranch.id}',
          );
        }
      } catch (error) {
        //
        // ما نريد نخلي Session ناقصة:
        // Login ناجح لكن بدون Branch.
        //
        await authStorage.clear();

        rethrow;
      }

      await localCredentials.remember(
        login: email,
        password: password,
        user: session.user,
      );

      try {
        await PublicServerSession.remember(
          email: email,
          password: password,
        );
      } catch (error) {
        debugPrint(
          '[STORE] public login skipped: $error',
        );
      }

      return session;
    } on DioException {
      rethrow;
    }
  }

  Future<AuthSession?> _loginOffline({
    required String login,
    required String password,
  }) async {
    final session = await localCredentials.openOffline(
      login: login,
      password: password,
    );
    if (session == null) {
      return null;
    }

    await authStorage.saveSession(
      session,
    );
    final branchId = await authStorage.readBranchId();
    if (branchId == null || branchId.trim().isEmpty) {
      await authStorage.saveBranchId(
        'local-branch',
      );
    }

    return session;
  }

  bool _serverUnreachable(
    DioException error,
  ) {
    return error.type ==
            DioExceptionType.connectionError ||
        error.type ==
            DioExceptionType.connectionTimeout ||
        error.type ==
            DioExceptionType.receiveTimeout ||
        error.type ==
            DioExceptionType.sendTimeout ||
        (error.type ==
                DioExceptionType.unknown &&
            error.response == null);
  }

  /// يتحقق أن الجلسة المحفوظة مقبولة على السيرفر الذي تتصل به الحاسبة الآن.
  Future<bool> activeServerAcceptsSession() async {
    final token = await authStorage.readAccessToken();
    if (token == null ||
        token.isEmpty ||
        token == AuthStorage.offlineToken) {
      if (token == AuthStorage.offlineToken) {
        await authStorage.clear();
      }
      return false;
    }

    try {
      await apiClient.get(
        '/branches',
        queryParameters: {
          'page': 1,
          'limit': 1,
        },
        requiresBranch: false,
      );
      final refresh = await authStorage.readRefreshToken() ?? '';
      await authStorage.savePublicSession(
        accessToken: token,
        refreshToken: refresh,
      );
      return true;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await authStorage.clear();
        return false;
      }
      return true;
    }
  }

  Future<AuthSession?> currentSession() {
    return authStorage.readSession();
  }

  Future<bool> isLoggedIn() async {
    final session =
    await currentSession();

    return session != null;
  }

  Future<void> logout() async {
    await authStorage.clear();
  }

  String _messageFromDio(
      DioException error,
      ) {
    final data =
        error.response?.data;

    if (data is Map<String, dynamic>) {
      final message =
      data['message'];

      if (message is String &&
          message.trim().isNotEmpty) {
        return message;
      }

      if (message is List) {
        return message
            .map(
              (item) =>
              item.toString(),
        )
            .join('\n');
      }
    }

    final statusCode =
        error.response?.statusCode;

    switch (statusCode) {
      case 400:
        return 'بيانات تسجيل الدخول غير صحيحة.';

      case 401:
        return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';

      case 403:
        return 'لا تملك صلاحية تسجيل الدخول.';

      case 404:
        return 'لا يوجد مستخدم بهذه البيانات.';

      case 500:
      case 502:
      case 503:
        return 'حدث خطأ في السيرفر، حاول مرة أخرى.';

      default:
        break;
    }

    if (error.type ==
        DioExceptionType.connectionTimeout ||
        error.type ==
            DioExceptionType.receiveTimeout ||
        error.type ==
            DioExceptionType.sendTimeout) {
      return 'انتهت مهلة الاتصال بالسيرفر.';
    }

    if (error.type ==
        DioExceptionType.connectionError) {
      return 'تعذر الاتصال بالسيرفر. تحقق من اتصال الإنترنت.';
    }

    return 'تعذر تسجيل الدخول.';
  }
}