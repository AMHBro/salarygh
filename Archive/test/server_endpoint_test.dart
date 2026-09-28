import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_system/core/network/server_endpoint.dart';
import 'package:sales_system/core/sync/sync_failure.dart';

void main() {
  test('عنوان الراوتر وعنوان الإنترنت يكتملان بمسار الواجهة', () {
    expect(
      normalizeServerBase('192.168.1.8'),
      'http://192.168.1.8/api/v1',
    );
    expect(
      normalizeServerBase('192.168.1.8:3000'),
      'http://192.168.1.8:3000/api/v1',
    );
    expect(
      normalizeServerBase('https://shop.example.com/api/v1'),
      'https://shop.example.com/api/v1',
    );
    expect(normalizeServerBase('  '), isNull);
  });

  test('انقطاع الشبكة يبقى قابلاً للإعادة والتعارض لا يُعاد تلقائياً', () {
    expect(
      isTransientSyncFailure(
        DioException(
          requestOptions: RequestOptions(path: '/sales'),
          type: DioExceptionType.connectionError,
        ),
      ),
      isTrue,
    );
    expect(
      isTransientSyncFailure(
        DioException(
          requestOptions: RequestOptions(path: '/sales'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/sales'),
            statusCode: 409,
          ),
        ),
      ),
      isFalse,
    );
  });
}
