import 'auth_user.dart';

class AuthSession {
  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthSession.fromJson(
      Map<String, dynamic> json,
      ) {
    final userJson =
    json['user'];

    if (userJson
    is! Map<String, dynamic>) {
      throw const FormatException(
        'بيانات المستخدم غير صالحة.',
      );
    }

    return AuthSession(
      accessToken:
      json['accessToken']
          ?.toString() ??
          '',
      refreshToken:
      json['refreshToken']
          ?.toString() ??
          '',
      user:
      AuthUser.fromJson(
        userJson,
      ),
    );
  }
}