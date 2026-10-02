import 'package:dio/dio.dart';

/// انقطاع الشبكة أو تعذّر الوصول للسيرفر. العملية تبقى معلّقة وتُعاد لاحقاً.
bool isTransientSyncFailure(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        return error.response == null;
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return false;
    }
  }

  final text = error.toString().toLowerCase();
  if (text.contains('sync_defer') ||
      text.contains('لم تتم مزامنته') ||
      text.contains('لم يصل إلى السيرفر')) {
    return true;
  }
  if (text.contains('sync_conflict') ||
      text.contains('status code of 409') ||
      text.contains('status code of 403') ||
      text.contains('status code of 400') ||
      text.contains('status code of 422')) {
    return false;
  }

  return text.contains('connection error') ||
      text.contains('connection timeout') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('send timeout') ||
      text.contains('receive timeout');
}
