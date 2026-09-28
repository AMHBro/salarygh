import 'package:flutter/foundation.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/branches/data/branches_remote_repository.dart';
import '../../features/cashbox/data/cashbox_local_repository.dart';
import '../../features/customers/data/customer_payments_sync_remote_gateway.dart';
import '../../features/customers/data/customers_local_repository.dart';
import '../../features/customers/data/customers_sync_remote_gateway.dart';
import '../../features/ecommerce/data/ecommerce_orders_remote_repository.dart';
import '../../features/finance/data/finance_local_repository.dart';
import '../../features/inventory/data/inventory_local_repository.dart';
import '../../features/inventory/data/inventory_sync_remote_gateway.dart';
import '../../features/products/data/categories_repository.dart';
import '../../features/products/data/products_local_repository.dart';
import '../../features/products/data/products_sync_remote_gateway.dart';
import '../../features/products/data/units_repository.dart';
import '../../features/purchases/data/purchases_local_repository.dart';
import '../../features/purchases/data/purchases_sync_remote_gateway.dart';
import '../../features/representatives/data/representatives_local_repository.dart';
import '../../features/representatives/data/representatives_sync_remote_gateway.dart';
import '../../features/sales/data/direct_sales_sync_remote_gateway.dart';
import '../../features/sales/data/sales_local_repository.dart';
import '../../features/suppliers/data/supplier_payments_sync_remote_gateway.dart';
import '../../features/suppliers/data/suppliers_local_repository.dart';
import '../../features/suppliers/data/suppliers_sync_remote_gateway.dart';
import '../../features/warehouses/data/warehouse_approvals_remote_repository.dart';
import '../../features/warehouses/data/warehouses_local_repository.dart';
import '../../features/warehouses/data/warehouses_sync_remote_gateway.dart';

import '../database/app_database.dart';
import '../floor/floor_notice_gateway.dart';
import '../network/api_client.dart';
import '../storage/auth_storage.dart';
import '../sync/composite_sync_remote_gateway.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_queue_repository.dart';
import '../sync/sync_service.dart';

class AppServices {
  AppServices._();

  // ===========================================================================
  // CORE
  // ===========================================================================

  static final AppDatabase database =
  AppDatabase();

  static final AuthStorage authStorage =
  AuthStorage();

  static final ApiClient apiClient =
  ApiClient(
    authStorage: authStorage,
  );

  // ===========================================================================
  // AUTH / BRANCHES
  // ===========================================================================

  static final BranchesRemoteRepository
  branchesRemoteRepository =
  BranchesRemoteRepository(
    apiClient: apiClient,
    authStorage: authStorage,
  );

  static final AuthRepository
  authRepository =
  AuthRepository(
    apiClient: apiClient,
    authStorage: authStorage,
    branchesRepository:
    branchesRemoteRepository,
  );

  // ===========================================================================
  // ECOMMERCE ADMIN
  // ===========================================================================
  //
  // Direct remote repository.
  //
  // Ecommerce order acceptance/rejection must NOT go through the local Outbox
  // because the backend performs the acceptance transaction atomically.
  // ===========================================================================

  static final EcommerceOrdersRemoteRepository
  ecommerceOrdersRepository =
  EcommerceOrdersRemoteRepository(
    apiClient: apiClient,
  );

  // ===========================================================================
  // SYNC CORE
  // ===========================================================================

  static final SyncQueueRepository
  syncQueueRepository =
  SyncQueueRepository(
    database: database,
  );

  static final ConnectivityService
  connectivityService =
  ConnectivityService();

  // ===========================================================================
  // REFERENCE DATA
  // ===========================================================================

  static final UnitsRepository
  unitsRepository =
  UnitsRepository(
    database: database,
    apiClient: apiClient,
  );

  static final CategoriesRepository
  categoriesRepository =
  CategoriesRepository(
    database: database,
    apiClient: apiClient,
  );

  // ===========================================================================
  // PRODUCTS
  // ===========================================================================

  static final ProductsLocalRepository
  productsRepository =
  ProductsLocalRepository(
    database: database,
    syncQueue: syncQueueRepository,
  );

  // ===========================================================================
  // WAREHOUSES
  // ===========================================================================

  static final WarehousesLocalRepository
  warehousesRepository =
  WarehousesLocalRepository(
    database: database,
    syncQueue: syncQueueRepository,
    authStorage: authStorage,
  );

  static final WarehouseApprovalsRemoteRepository
  warehouseApprovalsRepository =
  WarehouseApprovalsRemoteRepository(
    apiClient: apiClient,
  );

  // ===========================================================================
  // INVENTORY LOCAL
  // ===========================================================================

  static final InventoryLocalRepository
  inventoryRepository =
  InventoryLocalRepository(
    database: database,
    syncQueue: syncQueueRepository,
  );

  // ===========================================================================
  // REMOTE SYNC GATEWAYS
  // ===========================================================================

  static final ProductsSyncRemoteGateway
  productsSyncRemoteGateway =
  ProductsSyncRemoteGateway(
    database: database,
    apiClient: apiClient,
  );

  static final WarehousesSyncRemoteGateway
  warehousesSyncRemoteGateway =
  WarehousesSyncRemoteGateway(
    database: database,
    apiClient: apiClient,
  );

  static final InventorySyncRemoteGateway
  inventorySyncRemoteGateway =
  InventorySyncRemoteGateway(
    database: database,
    apiClient: apiClient,
  );

  static final CustomersSyncRemoteGateway
  customersSyncRemoteGateway =
  CustomersSyncRemoteGateway(
    database: database,
    apiClient: apiClient,
  );

  static final CustomerPaymentsSyncRemoteGateway
  customerPaymentsSyncRemoteGateway =
  CustomerPaymentsSyncRemoteGateway(
    database: database,
    apiClient: apiClient,
  );

  static final SuppliersSyncRemoteGateway
  suppliersSyncRemoteGateway =
  SuppliersSyncRemoteGateway(
    database: database,
    apiClient: apiClient,
  );

  static final SupplierPaymentsSyncRemoteGateway
  supplierPaymentsSyncRemoteGateway =
  SupplierPaymentsSyncRemoteGateway(
    database: database,
    apiClient: apiClient,
  );

  static final PurchasesSyncRemoteGateway
  purchasesSyncRemoteGateway =
  PurchasesSyncRemoteGateway(
    database: database,
    apiClient: apiClient,
  );

  static final DirectSalesSyncRemoteGateway
  directSalesSyncRemoteGateway =
  DirectSalesSyncRemoteGateway(
    database: database,
    apiClient: apiClient,
  );

  static final RepresentativesSyncRemoteGateway
  representativesSyncRemoteGateway =
  RepresentativesSyncRemoteGateway(
    database: database,
    apiClient: apiClient,
  );

  // ===========================================================================
  // COMPOSITE SYNC
  // ===========================================================================

  static final CompositeSyncRemoteGateway
  compositeSyncRemoteGateway =
  CompositeSyncRemoteGateway(
    gateways: [
      productsSyncRemoteGateway,
      warehousesSyncRemoteGateway,
      inventorySyncRemoteGateway,

      // -----------------------------------------------------------------------
      // Customers
      // -----------------------------------------------------------------------

      customersSyncRemoteGateway,
      customerPaymentsSyncRemoteGateway,

      // -----------------------------------------------------------------------
      // Suppliers
      // -----------------------------------------------------------------------

      suppliersSyncRemoteGateway,
      supplierPaymentsSyncRemoteGateway,

      // -----------------------------------------------------------------------
      // Representatives
      // -----------------------------------------------------------------------

      representativesSyncRemoteGateway,

      // -----------------------------------------------------------------------
      // Purchases / Sales
      // -----------------------------------------------------------------------

      purchasesSyncRemoteGateway,
      directSalesSyncRemoteGateway,
      FloorNoticeGateway(
        database: database,
        apiClient: apiClient,
      ),
    ],
  );

  static final SyncService
  syncService =
  SyncService(
    database: database,
    queueRepository:
    syncQueueRepository,
    connectivityService:
    connectivityService,
    remoteGateway:
    compositeSyncRemoteGateway,
    apiClient: apiClient,
  );

  // ===========================================================================
  // CUSTOMERS
  // ===========================================================================

  static final CustomersLocalRepository
  customersRepository =
  CustomersLocalRepository(
    database: database,
    syncQueue: syncQueueRepository,
  );

  // ===========================================================================
  // SUPPLIERS
  // ===========================================================================

  static final SuppliersLocalRepository
  suppliersRepository =
  SuppliersLocalRepository(
    database: database,
    syncQueue: syncQueueRepository,
  );

  // ===========================================================================
  // REPRESENTATIVES
  // ===========================================================================

  static final RepresentativesLocalRepository
  representativesRepository =
  RepresentativesLocalRepository(
    database: database,
    syncQueue: syncQueueRepository,
  );

  // ===========================================================================
  // SALES
  // ===========================================================================

  static final SalesLocalRepository
  salesRepository =
  SalesLocalRepository(
    database: database,
    syncQueue: syncQueueRepository,
  );

  // ===========================================================================
  // PURCHASES
  // ===========================================================================

  static final PurchasesLocalRepository
  purchasesRepository =
  PurchasesLocalRepository(
    database: database,
    syncQueue: syncQueueRepository,
  );

  // ===========================================================================
  // CASHBOX
  // ===========================================================================

  static final CashboxLocalRepository
  cashboxRepository =
  CashboxLocalRepository(
    database: database,
  );

  // ===========================================================================
  // FINANCE
  // ===========================================================================

  static final FinanceLocalRepository
  financeRepository =
  FinanceLocalRepository(
    database: database,
    customersRepository:
    customersRepository,
    suppliersRepository:
    suppliersRepository,
    representativesRepository:
    representativesRepository,
  );

  // ===========================================================================
  // START SYNC
  // ===========================================================================

  static Future<void> startSync() async {
    debugPrint(
      '[APP SERVICES] ========================================',
    );

    debugPrint(
      '[APP SERVICES] Preparing sync...',
    );

    final repairedWarehouses =
    await warehousesRepository
        .repairMissingBranchIds();

    if (repairedWarehouses > 0) {
      debugPrint(
        '[WAREHOUSE REPAIR] '
            '$repairedWarehouses warehouse(s) linked to active branch.',
      );
    } else {
      debugPrint(
        '[WAREHOUSE REPAIR] '
            'No missing warehouse branch IDs found.',
      );
    }

    debugPrint(
      '[APP SERVICES] Starting SyncService...',
    );

    await syncService.start();

    debugPrint(
      '[APP SERVICES] SyncService started.',
    );

    debugPrint(
      '[APP SERVICES] ========================================',
    );
  }

  // ===========================================================================
  // MANUAL SYNC
  // ===========================================================================

  static Future<void> syncNow() async {
    final repairedWarehouses =
    await warehousesRepository
        .repairMissingBranchIds();

    if (repairedWarehouses > 0) {
      debugPrint(
        '[WAREHOUSE REPAIR] '
            '$repairedWarehouses warehouse(s) linked to active branch '
            'before manual sync.',
      );
    }

    await syncService.synchronize(
      source: 'manual',
    );
  }

  // ===========================================================================
  // REFERENCE DATA
  // ===========================================================================

  static Future<void>
  refreshReferenceData() async {
    await Future.wait([
      unitsRepository.refreshFromServer(),
      categoriesRepository.refreshFromServer(),
    ]);
  }

  static Future<void>
  refreshReferenceDataSafe() async {
    await Future.wait([
      unitsRepository.refreshOrGetLocal(),
      categoriesRepository.refreshOrGetLocal(),
    ]);
  }
}