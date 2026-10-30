import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

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
    final denied = await _postHold(
      apiClient,
      variantId: serverVariantId,
      warehouseId: serverWarehouseId,
      pieces: pieces,
      holdKey: key,
      requireCloud: requireCloud,
    );
    if (denied == null || !denied.canRelocate) {
      return denied?.message;
    }

    /// الرصيد وصل للسيرفر على مخزن غير مخزن البيع، فيُنقل ثم يُعاد الحجز.
    final localQty = await _localQuantity(
      database,
      localVariantId,
      localWarehouseId,
    );
    final moved = await _relocate(
      apiClient,
      database,
      variantId: serverVariantId,
      destinationWarehouseId: serverWarehouseId,
      pieces: localQty > pieces ? localQty : pieces,
      fallbackPieces: pieces,
    );
    if (!moved) {
      return 'ما قدرنا نحجز الكمية من مخزن البيع، ولا لقينا رصيد حر بمخزن ثاني على السيرفر.';
    }
    final again = await _postHold(
      apiClient,
      variantId: serverVariantId,
      warehouseId: serverWarehouseId,
      pieces: pieces,
      holdKey: key,
      requireCloud: requireCloud,
    );
    return again?.message;
  }

  static Future<_HoldDenial?> _postHold(
    ApiClient apiClient, {
    required String variantId,
    required String warehouseId,
    required double pieces,
    required String holdKey,
    required bool requireCloud,
  }) async {
    try {
      await apiClient.post(
        '/floor/holds',
        data: {
          'variant_id': variantId,
          'warehouse_id': warehouseId,
          'quantity': pieces,
          'hold_key': holdKey,
        },
      );
      return null;
    } on DioException catch (error) {
      if (error.response == null) {
        return requireCloud ? const _HoldDenial(_cloudRequired) : null;
      }
      final data = error.response?.data;
      if (data is Map) {
        final message = data['message'];
        final text = message is String ? message.trim() : '';
        final available = _availableOf(data['details']);
        if (text.isNotEmpty) {
          return _HoldDenial(
            text,
            available: available,
            canRelocate: _isWarehouseMiss(text, available),
          );
        }
      }
      return const _HoldDenial('السيرفر رفض الكمية. راجع توفر المادة.');
    } catch (_) {
      return requireCloud ? const _HoldDenial(_cloudRequired) : null;
    }
  }

  static bool _isWarehouseMiss(String message, double? available) {
    if (available != null) {
      return available <= 0.001;
    }
    return message.contains('غير متوفرة على السيرفر') ||
        message.contains('محجوزة لحاسبة');
  }

  static double? _availableOf(dynamic details) {
    if (details is! Map) {
      return null;
    }
    final value = details['available'];
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('${value ?? ''}');
  }

  static Future<double> _localQuantity(
    AppDatabase database,
    String variantId,
    String warehouseId,
  ) async {
    final row = await (database.select(database.stockBalances)
          ..where(
            (table) =>
                table.variantId.equals(variantId) &
                table.warehouseId.equals(warehouseId),
          ))
        .getSingleOrNull();
    return row?.quantity ?? 0;
  }

  static Future<bool> _relocate(
    ApiClient apiClient,
    AppDatabase database, {
    required String variantId,
    required String destinationWarehouseId,
    required double pieces,
    required double fallbackPieces,
  }) async {
    if (await _transfer(
      apiClient,
      database,
      variantId: variantId,
      destinationWarehouseId: destinationWarehouseId,
      pieces: pieces,
    )) {
      return true;
    }
    if ((pieces - fallbackPieces).abs() < 0.001) {
      return false;
    }
    return _transfer(
      apiClient,
      database,
      variantId: variantId,
      destinationWarehouseId: destinationWarehouseId,
      pieces: fallbackPieces,
    );
  }

  static Future<bool> _transfer(
    ApiClient apiClient,
    AppDatabase database, {
    required String variantId,
    required String destinationWarehouseId,
    required double pieces,
  }) async {
    if (pieces <= 0) {
      return false;
    }
    final rows = await database.select(database.warehouses).get();
    final sources = rows.where((row) {
      if (row.deletedAt != null) {
        return false;
      }
      final id = row.serverId?.trim() ?? '';
      return id.isNotEmpty && id != destinationWarehouseId;
    }).toList()
      ..sort((a, b) {
        if (a.isActive == b.isActive) {
          return 0;
        }
        return a.isActive ? -1 : 1;
      });

    for (final source in sources) {
      try {
        await apiClient.post(
          '/inventory/transfer',
          data: {
            'source_warehouse_id': source.serverId!.trim(),
            'destination_warehouse_id': destinationWarehouseId,
            'variant_id': variantId,
            'quantity': pieces,
            'notes': 'تجهيز مخزن البيع',
          },
        );
        return true;
      } on DioException {
        continue;
      } catch (_) {
        continue;
      }
    }
    return false;
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

class _HoldDenial {
  final String message;
  final double? available;
  final bool canRelocate;

  const _HoldDenial(
    this.message, {
    this.available,
    this.canRelocate = false,
  });
}
