import 'package:dio/dio.dart';

import '../database/app_database.dart';
import '../di/app_services.dart';
import '../network/api_client.dart';
import 'floor_store.dart';

class FloorGuard {
  static const _cloudRequired =
      'آخر كمية تحتاج تأكيد السحابة. البيع متوقف حتى يتأكد الحجز.';

  static Future<String?> reserve({
    required String localVariantId,
    required String localWarehouseId,
    required double pieces,
    bool requireCloud = false,
  }) async {
    final database = AppServices.database;
    final apiClient = AppServices.apiClient;
    final connectivity = AppServices.connectivityService;
    if (await FloorStore.isLocked(database, localVariantId)) {
      return 'هذه المادة مقفلة بعد بيع متعارض. تنتظر مراجعة المدير.';
    }
    if (pieces <= 0) {
      await _release(database, apiClient, localVariantId);
      return null;
    }

    final online = await connectivity.hasConnection;
    if (!online) {
      return requireCloud ? _cloudRequired : null;
    }

    final serverVariantId = await _serverVariantId(database, localVariantId);
    final serverWarehouseId = await _serverWarehouseId(database, localWarehouseId);
    if (serverVariantId == null || serverWarehouseId == null) {
      return requireCloud ? _cloudRequired : null;
    }

    final deviceId = await FloorStore.deviceId(database);
    final key = FloorStore.holdKey(deviceId, serverVariantId);
    try {
      await apiClient.post(
        '/floor/holds',
        data: {
          'variant_id': serverVariantId,
          'warehouse_id': serverWarehouseId,
          'quantity': pieces,
          'hold_key': key,
        },
      );
      return null;
    } on DioException catch (error) {
      if (error.response == null) {
        return requireCloud ? _cloudRequired : null;
      }
      final data = error.response?.data;
      if (data is Map) {
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message;
        }
      }
      return 'السيرفر رفض الكمية. راجع توفر المادة.';
    } catch (_) {
      return requireCloud ? _cloudRequired : null;
    }
  }

  static Future<void> _release(
    AppDatabase database,
    ApiClient apiClient,
    String localVariantId,
  ) async {
    final serverVariantId = await _serverVariantId(database, localVariantId);
    if (serverVariantId == null) {
      return;
    }
    final deviceId = await FloorStore.deviceId(database);
    final key = FloorStore.holdKey(deviceId, serverVariantId);
    try {
      await apiClient.delete('/floor/holds/$key');
    } catch (_) {}
  }

  static Future<String?> _serverVariantId(
    AppDatabase database,
    String localId,
  ) async {
    final row = await (database.select(database.productVariants)
          ..where((table) => table.id.equals(localId)))
        .getSingleOrNull();
    final serverId = row?.serverId?.trim() ?? '';
    return serverId.isEmpty ? null : serverId;
  }

  static Future<String?> _serverWarehouseId(
    AppDatabase database,
    String localId,
  ) async {
    final row = await (database.select(database.warehouses)
          ..where((table) => table.id.equals(localId)))
        .getSingleOrNull();
    final serverId = row?.serverId?.trim() ?? '';
    return serverId.isEmpty ? null : serverId;
  }
}
