import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

class ReportsRepository {
  final ApiClient apiClient;

  ReportsRepository({
    required this.apiClient,
  });

  Future<List<Map<String, dynamic>>> fetch(
    String path, {
    Map<String, String> query = const {},
  }) async {
    try {
      final response = await apiClient.get(
        path,
        queryParameters: query.isEmpty ? null : query,
      );

      return _rows(response.data);
    } on DioException catch (error) {
      throw StateError(_message(error));
    }
  }

  List<Map<String, dynamic>> _rows(Object? data) {
    final raw = data is Map && data['data'] is List
        ? data['data']
        : data;

    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map>()
        .map(
          (row) => row.map(
            (key, value) => MapEntry(
              key.toString(),
              value,
            ),
          ),
        )
        .toList();
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

    return 'تعذر جلب التقرير من الخادم المحلي.';
  }
}
