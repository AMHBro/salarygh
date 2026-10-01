import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/warehouse_approval_model.dart';

class WarehouseApprovalsRemoteRepository {
  final ApiClient apiClient;

  WarehouseApprovalsRemoteRepository({
    required this.apiClient,
  });

  // ===========================================================================
  // GET APPROVALS
  // ===========================================================================

  Future<WarehouseApprovalsResult> getApprovals() async {
    try {
      final response = await apiClient.get(
        '/organization/approvals',
      );

      final root = _asMap(
        response.data,
      );

      if (root['success'] != true) {
        throw StateError(
          _extractMessage(
            response.data,
            fallback: 'تعذر تحميل طلبات الاعتماد.',
          ),
        );
      }

      final data = _asMap(
        root['data'],
      );

      return WarehouseApprovalsResult.fromJson(
        data,
      );
    } on DioException catch (error) {
      throw StateError(
        _dioMessage(
          error,
          fallback: 'تعذر تحميل طلبات الاعتماد.',
        ),
      );
    }
  }

  // ===========================================================================
  // APPROVE
  // ===========================================================================

  Future<void> approveWarehouse({
    required String warehouseServerId,
  }) async {
    final id = warehouseServerId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Server ID الخاص بالمخزن مطلوب.',
      );
    }

    try {
      final response = await apiClient.post(
        '/warehouses/$id/approve',
      );

      _ensureSuccess(
        response.data,
        fallback: 'تعذر اعتماد المخزن.',
      );
    } on DioException catch (error) {
      throw StateError(
        _dioMessage(
          error,
          fallback: 'تعذر اعتماد المخزن.',
        ),
      );
    }
  }

  /// يقرأ حالة المخزن من السيرفر ثم يرسل المسودة أو المرفوض ويعتمد حتى يصير ACTIVE.
  Future<String> activateWarehouse({
    required String warehouseServerId,
  }) async {
    final id = warehouseServerId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Server ID الخاص بالمخزن مطلوب.',
      );
    }

    final remoteStatus = await _readServerStatus(id);

    if (remoteStatus == 'ACTIVE') {
      return 'ACTIVE';
    }

    if (remoteStatus == 'INACTIVE' || remoteStatus == 'DISABLED') {
      await enableWarehouse(warehouseServerId: id);
      return 'ACTIVE';
    }

    if (remoteStatus == 'DRAFT' || remoteStatus == 'REJECTED') {
      await submitWarehouse(warehouseServerId: id);
    } else if (remoteStatus != 'PENDING_APPROVAL') {
      throw StateError(
        'المخزن على السيرفر حالته $remoteStatus ولا يمكن تفعيله من هنا.',
      );
    }

    await approveWarehouse(warehouseServerId: id);
    return 'ACTIVE';
  }

  Future<String> _readServerStatus(String id) async {
    try {
      final response = await apiClient.get(
        '/warehouses/$id',
      );
      final root = _asMap(response.data);
      final data = root['data'] is Map
          ? Map<String, dynamic>.from(root['data'] as Map)
          : root;
      final status = data['status']?.toString().trim().toUpperCase() ?? '';
      if (status.isEmpty) {
        throw StateError('تعذر قراءة حالة المخزن من السيرفر.');
      }
      return status;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        throw StateError(
          'رقم هذا المخزن غير مسجّل على السيرفر. استخدم مخزن المتجر المفعّل.',
        );
      }
      throw StateError(
        _dioMessage(
          error,
          fallback: 'تعذر قراءة حالة المخزن من السيرفر.',
        ),
      );
    }
  }

  Future<void> enableWarehouse({
    required String warehouseServerId,
  }) async {
    final id = warehouseServerId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Server ID الخاص بالمخزن مطلوب.',
      );
    }

    try {
      final response = await apiClient.post(
        '/warehouses/$id/enable',
      );

      _ensureSuccess(
        response.data,
        fallback: 'تعذر تفعيل المخزن.',
      );
    } on DioException catch (error) {
      throw StateError(
        _dioMessage(
          error,
          fallback: 'تعذر تفعيل المخزن.',
        ),
      );
    }
  }

  Future<void> submitWarehouse({
    required String warehouseServerId,
  }) async {
    final id = warehouseServerId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Server ID الخاص بالمخزن مطلوب.',
      );
    }

    try {
      final response = await apiClient.post(
        '/warehouses/$id/submit',
      );

      _ensureSuccess(
        response.data,
        fallback: 'تعذر إرسال المخزن للاعتماد.',
      );
    } on DioException catch (error) {
      throw StateError(
        _dioMessage(
          error,
          fallback: 'تعذر إرسال المخزن للاعتماد.',
        ),
      );
    }
  }

  // ===========================================================================
  // REJECT
  // ===========================================================================

  Future<void> rejectWarehouse({
    required String warehouseServerId,
    required String rejectionReason,
  }) async {
    final id = warehouseServerId.trim();

    final reason = rejectionReason.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Server ID الخاص بالمخزن مطلوب.',
      );
    }

    if (reason.isEmpty) {
      throw ArgumentError(
        'سبب الرفض مطلوب.',
      );
    }

    try {
      final response = await apiClient.post(
        '/warehouses/$id/reject',
        data: {
          'rejection_reason': reason,
        },
      );

      _ensureSuccess(
        response.data,
        fallback: 'تعذر رفض المخزن.',
      );
    } on DioException catch (error) {
      throw StateError(
        _dioMessage(
          error,
          fallback: 'تعذر رفض المخزن.',
        ),
      );
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  void _ensureSuccess(
      dynamic data, {
        required String fallback,
      }) {
    final map = _asMap(
      data,
    );

    if (map.isEmpty) {
      return;
    }

    if (map.containsKey('success') &&
        map['success'] != true) {
      throw StateError(
        _extractMessage(
          data,
          fallback: fallback,
        ),
      );
    }
  }

  Map<String, dynamic> _asMap(
      dynamic value,
      ) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    return const {};
  }

  String _dioMessage(
      DioException error, {
        required String fallback,
      }) {
    final responseData = error.response?.data;

    final message = _extractMessage(
      responseData,
      fallback: fallback,
    );

    if (error.response?.statusCode == 403) {
      return message;
    }

    return message;
  }

  String _extractMessage(
      dynamic data, {
        required String fallback,
      }) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(
        data,
      );

      final message = map['message'];

      if (message is String &&
          message.trim().isNotEmpty) {
        return message.trim();
      }

      if (message is List &&
          message.isNotEmpty) {
        return message
            .map(
              (item) => item.toString(),
        )
            .join('\n');
      }

      final nestedData = map['data'];

      if (nestedData is Map) {
        final nested = Map<String, dynamic>.from(
          nestedData,
        );

        final nestedMessage = nested['message'];

        if (nestedMessage != null &&
            nestedMessage.toString().trim().isNotEmpty) {
          return nestedMessage.toString().trim();
        }
      }
    }

    return fallback;
  }
}