import '../../../core/network/api_client.dart';
import '../models/ecommerce_order_model.dart';

class EcommerceOrdersRemoteRepository {
  final ApiClient apiClient;

  EcommerceOrdersRemoteRepository({
    required this.apiClient,
  });

  // ===========================================================================
  // ORDERS
  // ===========================================================================

  Future<EcommerceOrdersPage> getOrders({
    int page = 1,
    int limit = 20,
    String? status,
    String? source,
    String? search,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'limit': limit,
    };

    final cleanStatus = _clean(status);
    final cleanSource = _clean(source);
    final cleanSearch = _clean(search);

    if (cleanStatus != null) {
      query['status'] = cleanStatus;
    }

    if (cleanSource != null) {
      query['source'] = cleanSource;
    }

    if (cleanSearch != null) {
      query['search'] = cleanSearch;
    }

    final response = await apiClient.get(
      '/admin/ecommerce/orders',
      queryParameters: query,
    );

    final json = _asMap(
      response.data,
    );

    return EcommerceOrdersPage.fromJson(
      json,
    );
  }

  // ===========================================================================
  // DETAILS
  // ===========================================================================

  Future<EcommerceOrderModel> getOrder(
      String id,
      ) async {
    final cleanId = id.trim();

    if (cleanId.isEmpty) {
      throw ArgumentError(
        'معرف الطلب مطلوب.',
      );
    }

    final response = await apiClient.get(
      '/admin/ecommerce/orders/$cleanId',
    );

    final json = _asMap(
      response.data,
    );

    final rawData = json['data'];

    if (rawData is! Map) {
      throw StateError(
        'استجابة تفاصيل الطلب غير صالحة.',
      );
    }

    return EcommerceOrderModel.fromJson(
      Map<String, dynamic>.from(
        rawData,
      ),
    );
  }

  // ===========================================================================
  // ACCEPT
  // ===========================================================================

  Future<EcommerceAcceptResult> acceptOrder({
    required String orderId,
    required String warehouseId,
    double? paidAmount,
  }) async {
    final cleanOrderId = orderId.trim();
    final cleanWarehouseId = warehouseId.trim();

    if (cleanOrderId.isEmpty) {
      throw ArgumentError(
        'معرف الطلب مطلوب.',
      );
    }

    if (cleanWarehouseId.isEmpty) {
      throw ArgumentError(
        'معرف المخزن مطلوب.',
      );
    }

    final body = <String, dynamic>{
      'warehouse_id': cleanWarehouseId,
    };

    if (paidAmount != null) {
      body['paid_amount'] = paidAmount;
    }

    final response = await apiClient.post(
      '/admin/ecommerce/orders/$cleanOrderId/accept',
      data: body,
    );

    return EcommerceAcceptResult.fromJson(
      _asMap(response.data),
    );
  }

  // ===========================================================================
  // REJECT
  // ===========================================================================

  Future<EcommerceOrderModel> rejectOrder({
    required String orderId,
    required String reason,
  }) async {
    final cleanOrderId = orderId.trim();
    final cleanReason = reason.trim();

    if (cleanOrderId.isEmpty) {
      throw ArgumentError(
        'معرف الطلب مطلوب.',
      );
    }

    if (cleanReason.isEmpty) {
      throw ArgumentError(
        'سبب الرفض مطلوب.',
      );
    }

    final response = await apiClient.post(
      '/admin/ecommerce/orders/$cleanOrderId/reject',
      data: {
        'reason': cleanReason,
      },
    );

    final json = _asMap(
      response.data,
    );

    final rawData = json['data'];

    if (rawData is! Map) {
      throw StateError(
        'استجابة رفض الطلب غير صالحة.',
      );
    }

    return EcommerceOrderModel.fromJson(
      Map<String, dynamic>.from(
        rawData,
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  Map<String, dynamic> _asMap(
      dynamic value,
      ) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    throw StateError(
      'استجابة السيرفر غير صالحة.',
    );
  }

  String? _clean(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final result = value.trim();

    return result.isEmpty ? null : result;
  }
}