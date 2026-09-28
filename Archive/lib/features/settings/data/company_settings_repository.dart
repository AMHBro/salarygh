import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

class CompanySettingsRepository {
  final ApiClient apiClient;

  CompanySettingsRepository({
    required this.apiClient,
  });

  Future<Map<String, dynamic>> getCompany() async {
    try {
      final response = await apiClient.get('/company');
      final data = response.data;

      if (data is Map && data['data'] is Map) {
        return Map<String, dynamic>.from(
          data['data'] as Map,
        );
      }

      throw StateError('استجابة بيانات الشركة غير متوقعة.');
    } on DioException catch (error) {
      throw StateError(_message(error));
    }
  }

  Future<void> updateCompany(
    Map<String, dynamic> body,
  ) async {
    try {
      await apiClient.patch(
        '/company',
        data: body,
      );
    } on DioException catch (error) {
      throw StateError(_message(error));
    }
  }

  Future<double> usdExchangeRate() async {
    try {
      final company = await getCompany();
      final settings = company['settings'];
      if (settings is! Map) {
        return 0;
      }
      return double.tryParse(
            '${settings['usd_exchange_rate'] ?? ''}'.trim().replaceAll(',', ''),
          ) ??
          0;
    } catch (_) {
      return 0;
    }
  }

  Future<double> readOpeningCapital() async {
    try {
      final company = await getCompany();
      final settings = company['settings'];
      if (settings is! Map) {
        return 0;
      }
      return double.tryParse(
            '${settings['opening_capital'] ?? ''}'.trim().replaceAll(',', ''),
          ) ??
          0;
    } catch (_) {
      return 0;
    }
  }

  String _message(DioException error) {
    final data = error.response?.data;

    if (data is Map && data['message'] != null) {
      final message = data['message'];

      if (message is List) {
        return message.join('\n');
      }

      return message.toString();
    }

    return 'تعذر حفظ إعدادات الشركة على السيرفر.';
  }
}
