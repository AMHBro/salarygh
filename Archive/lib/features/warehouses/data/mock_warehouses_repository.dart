import '../models/stock_movement_model.dart';
import '../models/warehouse_model.dart';

class MockWarehousesRepository {
  const MockWarehousesRepository();

  static final List<WarehouseModel> warehouses = [
    WarehouseModel(
      id: 'warehouse-main',
      name: 'المخزن الرئيسي',
      code: 'WH-001',
      branchId: 'branch-main',
      branchName: 'الفرع الرئيسي',
      address: 'بغداد',
      location: 'بغداد',
      notes: 'المخزن الرئيسي للنظام',
      productsCount: 126,
      totalQuantity: 2450,
      lowStockCount: 8,
      isMain: true,
      isActive: true,
      serverVersion: 0,
      createdAt: DateTime(
        2026,
        1,
        1,
      ),
      updatedAt: DateTime(
        2026,
        8,
        1,
      ),
    ),
    WarehouseModel(
      id: 'warehouse-mansour',
      name: 'مخزن المنصور',
      code: 'WH-002',
      branchId: 'branch-mansour',
      branchName: 'فرع المنصور',
      address: 'بغداد - المنصور',
      location: 'المنصور',
      notes: 'مخزن تابع لفرع المنصور',
      productsCount: 84,
      totalQuantity: 1320,
      lowStockCount: 5,
      isMain: false,
      isActive: true,
      serverVersion: 0,
      createdAt: DateTime(
        2026,
        2,
        1,
      ),
      updatedAt: DateTime(
        2026,
        8,
        1,
      ),
    ),
    WarehouseModel(
      id: 'warehouse-karrada',
      name: 'مخزن الكرادة',
      code: 'WH-003',
      branchId: 'branch-karrada',
      branchName: 'فرع الكرادة',
      address: 'بغداد - الكرادة',
      location: 'الكرادة',
      notes: 'مخزن تابع لفرع الكرادة',
      productsCount: 67,
      totalQuantity: 980,
      lowStockCount: 3,
      isMain: false,
      isActive: true,
      serverVersion: 0,
      createdAt: DateTime(
        2026,
        3,
        1,
      ),
      updatedAt: DateTime(
        2026,
        8,
        1,
      ),
    ),
  ];

  static final List<StockMovementModel> movements = [];

  List<WarehouseModel> getWarehouses() {
    return List<WarehouseModel>.from(
      warehouses,
    );
  }

  List<StockMovementModel> getMovements() {
    return List<StockMovementModel>.from(
      movements,
    );
  }

  WarehouseModel? getWarehouseById(
      String id,
      ) {
    try {
      return warehouses.firstWhere(
            (warehouse) => warehouse.id == id,
      );
    } catch (_) {
      return null;
    }
  }

  WarehouseModel? getMainWarehouse() {
    try {
      return warehouses.firstWhere(
            (warehouse) =>
        warehouse.isMain &&
            warehouse.isActive,
      );
    } catch (_) {
      return null;
    }
  }

  List<WarehouseModel> getActiveWarehouses() {
    return warehouses.where(
          (warehouse) => warehouse.isActive,
    ).toList();
  }

  List<WarehouseModel> searchWarehouses(
      String query,
      ) {
    final value = query.trim().toLowerCase();

    if (value.isEmpty) {
      return getWarehouses();
    }

    return warehouses.where(
          (warehouse) {
        return warehouse.name
            .toLowerCase()
            .contains(value) ||
            warehouse.branchName
                .toLowerCase()
                .contains(value) ||
            warehouse.location
                .toLowerCase()
                .contains(value) ||
            (warehouse.code ?? '')
                .toLowerCase()
                .contains(value);
      },
    ).toList();
  }

  void addWarehouse(
      WarehouseModel warehouse,
      ) {
    warehouses.add(
      warehouse,
    );
  }

  void updateWarehouse(
      WarehouseModel warehouse,
      ) {
    final index = warehouses.indexWhere(
          (item) => item.id == warehouse.id,
    );

    if (index < 0) {
      return;
    }

    warehouses[index] = warehouse;
  }

  void deleteWarehouse(
      String id,
      ) {
    warehouses.removeWhere(
          (warehouse) => warehouse.id == id,
    );
  }
}