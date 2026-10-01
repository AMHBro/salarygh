import 'package:dio/dio.dart';
import 'package:sales_system/core/network/server_endpoint.dart';

class AliraAgentApi {
  AliraAgentApi({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ServerEndpoint.defaultLan,
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
              ),
            );

  final Dio _dio;
  String? token;

  Future<void> _useActiveServer() async {
    _dio.options.baseUrl = await ServerEndpoint.instance.publicBaseUrl();
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    await _useActiveServer();
    final response = await _dio.post<dynamic>(
      '/store/agent/login',
      data: {'username': username.trim(), 'password': password},
    );
    final body = response.data;
    if (body is! Map) {
      throw StateError('تعذر تسجيل الدخول');
    }
    token = '${body['accessToken'] ?? ''}';
    if (token == null || token!.isEmpty) {
      throw StateError('تعذر تسجيل الدخول');
    }
    return Map<String, dynamic>.from(body);
  }

  Future<Map<String, dynamic>> account() async {
    await _useActiveServer();
    final response = await _dio.get<dynamic>(
      '/store/agent/account',
      options: Options(headers: {'authorization': 'Bearer $token'}),
    );
    final body = response.data;
    if (body is! Map) {
      throw StateError('تعذر قراءة الحساب');
    }
    return Map<String, dynamic>.from(body);
  }

  Future<Map<String, dynamic>> createOffice({
    required String name,
    required String phone,
    required String address,
  }) async {
    await _useActiveServer();
    final response = await _dio.post<dynamic>(
      '/store/agent/offices',
      data: {'name': name, 'phone': phone, 'address': address},
      options: Options(headers: {'authorization': 'Bearer $token'}),
    );
    final body = response.data;
    if (body is! Map) {
      throw StateError('تعذر إضافة المكتب');
    }
    return Map<String, dynamic>.from(body);
  }

  Future<Map<String, dynamic>> accounts() async {
    await _useActiveServer();
    final response = await _dio.get<dynamic>(
      '/store/representative/accounts',
      queryParameters: const {'limit': 100},
      options: Options(headers: {'authorization': 'Bearer $token'}),
    );
    final body = response.data;
    if (body is! Map) {
      throw StateError('تعذر قراءة حسابات المندوب');
    }
    return Map<String, dynamic>.from(body);
  }

  static String message(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        final message = data['message'];
        if (message is List && message.isNotEmpty) return '${message.first}';
        return '$message';
      }
    }
    if (error is StateError) return error.message;
    return 'تعذر إكمال الطلب';
  }
}
