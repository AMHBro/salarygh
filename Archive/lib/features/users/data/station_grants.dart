import '../../../core/auth/auth_user.dart';
import '../../../core/di/app_services.dart';
import '../../settings/data/company_settings_repository.dart';

/// المخزن الذي يسمح به المسؤول لكل حاسبة.
class StationGrants {
  static const unassigned = 'station-no-warehouse';
  static const _key = 'station_warehouses';

  static Future<Map<String, String>> read() async {
    final company = await CompanySettingsRepository(
      apiClient: AppServices.apiClient,
    ).getCompany();
    final settings = company['settings'];
    final raw = settings is Map ? settings[_key] : null;
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries)
        if ('${entry.key}'.trim().isNotEmpty && '${entry.value}'.trim().isNotEmpty)
          '${entry.key}': '${entry.value}'.trim(),
    };
  }

  static Future<void> save(String userId, String? warehouseServerId) async {
    final repository = CompanySettingsRepository(
      apiClient: AppServices.apiClient,
    );
    final company = await repository.getCompany();
    final settings = Map<String, dynamic>.from(
      company['settings'] is Map ? company['settings'] as Map : const {},
    );
    final grants = Map<String, dynamic>.from(
      settings[_key] is Map ? settings[_key] as Map : const {},
    );
    final serverId = warehouseServerId?.trim() ?? '';
    if (serverId.isEmpty) {
      grants.remove(userId);
    } else {
      grants[userId] = serverId;
    }
    settings[_key] = grants;
    await repository.updateCompany({'settings': settings});
  }

  /// المسؤول يبقى على كل المخازن. الحاسبة الأخرى تُقفل على المخزن المعيّن.
  static Future<void> applyForCurrentUser() async {
    final session = await AppServices.authStorage.readSession();
    final role = resolveSessionRole(
      storedRole: session?.user.role,
      accessToken: session?.accessToken,
    );
    final userId = session?.user.id.trim() ?? '';
    if (userId.isEmpty) return;
    Map<String, String> grants = const {};
    try {
      grants = await read();
    } catch (_) {
      return;
    }
    await _restoreGranted(grants.values);
    final serverId = grants[userId]?.trim() ?? '';
    if (serverId.isEmpty) {
      if (canApproveWarehouseDelete(role)) {
        await AppServices.authStorage.saveStationWarehouseId(null);
      } else {
        await AppServices.authStorage.saveStationWarehouseId(unassigned);
      }
      return;
    }
    await _restoreGranted(grants.values);
    var localId = await _localWarehouseId(serverId);
    if (localId == null) {
      try {
        await AppServices.warehousesSyncRemoteGateway.pullChanges();
      } catch (_) {}
      await _restoreGranted(grants.values);
      localId = await _localWarehouseId(serverId);
    }
    await AppServices.authStorage.saveStationWarehouseId(localId ?? unassigned);
    if (localId != null && localId != unassigned) {
      try {
        await AppServices.inventoryRepository.moveRecentOpeningStock(localId);
      } catch (_) {}
    }
  }

  /// مخزن الحاسبة الملحقة يبقى ظاهراً حتى لو أُوقف سابقاً.
  static Future<void> _restoreGranted(Iterable<String> serverIds) async {
    for (final raw in serverIds) {
      final serverId = raw.trim();
      if (serverId.isEmpty || serverId == unassigned) continue;
      final warehouse =
          await AppServices.warehousesRepository.getWarehouseByServerId(serverId);
      if (warehouse == null) continue;
      try {
        await AppServices.warehousesRepository.ensureListed(warehouse);
      } catch (_) {}
    }
  }

  /// الحاسبة الملحقة هي التي عُيّن لها مخزن. الحاسبة الأساسية تبقى بلا قفل.
  static Future<bool> isAttachedStation() async {
    final id =
        (await AppServices.authStorage.readStationWarehouseId())?.trim() ?? '';
    return id.isNotEmpty;
  }

  static Future<String?> _localWarehouseId(String serverId) async {
    final warehouses = await AppServices.warehousesRepository.getWarehouses();
    for (final warehouse in warehouses) {
      if ((warehouse.serverId ?? '').trim() == serverId &&
          warehouse.deletedAt == null) {
        return warehouse.id;
      }
    }
    return null;
  }
}
