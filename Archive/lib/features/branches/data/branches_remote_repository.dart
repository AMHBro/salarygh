import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/auth_storage.dart';
import '../models/branch_model.dart';

class BranchesRemoteRepository {
  final ApiClient apiClient;
  final AuthStorage authStorage;

  BranchesRemoteRepository({
    required this.apiClient,
    required this.authStorage,
  });

  Future<List<BranchModel>>
  getBranches() async {
    try {
      final response =
      await apiClient.get(
        '/branches',
        requiresBranch: false,
      );

      final raw =
          response.data;

      if (raw is! Map) {
        throw StateError(
          'استجابة الفروع غير صالحة.',
        );
      }

      final body =
          Map<String, dynamic>.from(
        raw,
      );

      final data =
      body['data'];

      if (data is! List) {
        throw StateError(
          'قائمة الفروع غير صالحة.',
        );
      }

      return data
          .whereType<Map>()
          .map(
            (item) =>
                BranchModel.fromJson(
          Map<String, dynamic>.from(
            item,
          ),
        ),
      )
          .toList();
    } on DioException catch (error) {
      throw StateError(
        _messageFromDio(
          error,
        ),
      );
    }
  }

  Future<BranchModel?>
  initializeActiveBranch() async {
    final branches =
    await getBranches();

    if (branches.isEmpty) {
      await authStorage
          .clearBranchId();

      return null;
    }

    BranchModel? activeBranch;

    for (final branch in branches) {
      if (branch.isActive) {
        activeBranch = branch;
        break;
      }
    }

    activeBranch ??= branches.first;

    await authStorage.saveBranchId(
      activeBranch.id,
    );

    return activeBranch;
  }

  String _messageFromDio(
      DioException error,
      ) {
    final data =
        error.response?.data;

    if (data
    is Map<String, dynamic>) {
      final message =
      data['message'];

      if (message is String &&
          message.trim().isNotEmpty) {
        return message;
      }
    }

    switch (
    error.response?.statusCode) {
      case 401:
        return 'انتهت جلسة الدخول أو لا تملك صلاحية الوصول إلى الفروع.';

      case 403:
        return 'لا تملك صلاحية الوصول إلى الفروع.';

      case 500:
        return 'حدث خطأ في السيرفر أثناء تحميل الفروع.';
    }

    return 'تعذر تحميل الفروع من السيرفر.';
  }
}