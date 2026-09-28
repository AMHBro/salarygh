import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/cashbox_sessions_table.dart';
import 'tables/categories_table.dart';
import 'tables/customer_ledger_entries_table.dart';
import 'tables/customer_payments_table.dart';
import 'tables/customers_table.dart';
import 'tables/held_sale_items_table.dart';
import 'tables/held_sales_table.dart';
import 'tables/product_variants_table.dart';
import 'tables/products_table.dart';
import 'tables/purchase_items_table.dart';
import 'tables/purchases_table.dart';
import 'tables/representative_commission_entries_table.dart';
import 'tables/representative_payments_table.dart';
import 'tables/representatives_table.dart';
import 'tables/sale_items_table.dart';
import 'tables/sale_return_items_table.dart';
import 'tables/sale_returns_table.dart';
import 'tables/sales_table.dart';
import 'tables/stock_balances_table.dart';
import 'tables/stock_movements_table.dart';
import 'tables/supplier_ledger_entries_table.dart';
import 'tables/supplier_payments_table.dart';
import 'tables/suppliers_table.dart';
import 'tables/sync_outbox_table.dart';
import 'tables/sync_state_table.dart';
import 'tables/units_table.dart';
import 'tables/warehouses_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    SyncOutbox,
    SyncState,
    Units,
    Categories,
    Products,
    ProductVariants,
    Warehouses,
    StockBalances,
    StockMovements,
    Sales,
    SaleItems,
    SaleReturns,
    SaleReturnItems,
    Customers,
    CustomerLedgerEntries,
    CustomerPayments,
    Suppliers,
    SupplierLedgerEntries,
    SupplierPayments,
    Purchases,
    PurchaseItems,
    Representatives,
    RepresentativeCommissionEntries,
    RepresentativePayments,

    // Local-only held sales.
    HeldSales,
    HeldSaleItems,

    // Local-first cashbox sessions.
    CashboxSessions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase()
      : super(
    _openConnection(),
  );

  AppDatabase.forTesting(
      super.executor,
      );

  @override
  int get schemaVersion => 33;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
        await customStatement(
          '''
          CREATE TABLE IF NOT EXISTS currency_exchanges (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            usd_amount REAL NOT NULL,
            rate REAL NOT NULL,
            iqd_amount REAL NOT NULL,
            party_name TEXT,
            note TEXT,
            created_at TEXT NOT NULL
          )
          ''',
        );
      },

      onUpgrade: (
          migrator,
          from,
          to,
          ) async {
        // =====================================================================
        // VERSION 2
        // =====================================================================

        if (from < 2) {
          await migrator.createTable(
            products,
          );
        }

        // =====================================================================
        // VERSION 3
        // =====================================================================

        if (from < 3) {
          await migrator.createTable(
            warehouses,
          );

          await migrator.createTable(
            stockBalances,
          );

          await migrator.createTable(
            stockMovements,
          );
        }

        // =====================================================================
        // VERSION 4
        // =====================================================================

        if (from < 4) {
          await migrator.addColumn(
            warehouses,
            warehouses.isMain,
          );

          await migrator.createTable(
            sales,
          );

          await migrator.createTable(
            saleItems,
          );
        }

        // =====================================================================
        // VERSION 5
        // =====================================================================

        if (from < 5) {
          await migrator.createTable(
            customers,
          );

          await migrator.createTable(
            customerLedgerEntries,
          );

          await migrator.createTable(
            customerPayments,
          );

          await migrator.addColumn(
            sales,
            sales.customerId,
          );
        }

        // =====================================================================
        // VERSION 6
        // =====================================================================

        if (from < 6) {
          await migrator.createTable(
            suppliers,
          );

          await migrator.createTable(
            supplierLedgerEntries,
          );

          await migrator.createTable(
            supplierPayments,
          );

          await migrator.createTable(
            purchases,
          );

          await migrator.createTable(
            purchaseItems,
          );
        }

        // =====================================================================
        // VERSION 7
        // =====================================================================

        if (from < 7) {
          await migrator.createTable(
            representatives,
          );

          await migrator.createTable(
            representativeCommissionEntries,
          );

          await migrator.createTable(
            representativePayments,
          );

          await migrator.addColumn(
            sales,
            sales.representativeId,
          );

          await migrator.addColumn(
            sales,
            sales.representativeNameSnapshot,
          );

          await migrator.addColumn(
            sales,
            sales.commissionPercentageSnapshot,
          );

          await migrator.addColumn(
            sales,
            sales.commissionAmount,
          );
        }

        // =====================================================================
        // VERSION 8
        // =====================================================================

        if (from < 8) {
          await migrator.createTable(
            units,
          );

          await migrator.createTable(
            categories,
          );

          await migrator.addColumn(
            products,
            products.nameEn,
          );

          await migrator.addColumn(
            products,
            products.baseUnitId,
          );

          await migrator.addColumn(
            products,
            products.description,
          );

          await migrator.addColumn(
            products,
            products.hasVariants,
          );

          await migrator.addColumn(
            products,
            products.hasExpiry,
          );

          await migrator.addColumn(
            products,
            products.hasSerial,
          );

          await migrator.addColumn(
            products,
            products.imageUrl,
          );
        }

        // =====================================================================
        // VERSION 9
        // =====================================================================

        if (from < 9) {
          await migrator.addColumn(
            products,
            products.serverId,
          );
        }

        // =====================================================================
        // VERSION 10
        // =====================================================================

        if (from < 10) {
          await migrator.createTable(
            productVariants,
          );
        }

        // =====================================================================
        // VERSION 11
        // =====================================================================

        if (from < 11) {
          await _migrateInventoryToVariants(
            migrator,
          );
        }

        // =====================================================================
        // VERSION 12
        // =====================================================================

        if (from < 12) {
          await migrator.addColumn(
            warehouses,
            warehouses.serverId,
          );
        }

        // =====================================================================
        // VERSION 13
        // =====================================================================

        if (from < 13) {
          await migrator.addColumn(
            warehouses,
            warehouses.type,
          );

          await migrator.addColumn(
            warehouses,
            warehouses.status,
          );

          await migrator.addColumn(
            warehouses,
            warehouses.parentWarehouseId,
          );

          await migrator.addColumn(
            warehouses,
            warehouses.managerId,
          );

          await migrator.addColumn(
            warehouses,
            warehouses.capacity,
          );

          await migrator.addColumn(
            warehouses,
            warehouses.rejectionReason,
          );

          await customStatement(
            '''
            UPDATE warehouses
            SET type = 'MAIN'
            WHERE is_main = 1
            ''',
          );
        }

        // =====================================================================
        // VERSION 14
        // =====================================================================

        if (from < 14) {
          await migrator.addColumn(
            suppliers,
            suppliers.serverId,
          );

          await migrator.addColumn(
            suppliers,
            suppliers.email,
          );

          await migrator.addColumn(
            suppliers,
            suppliers.taxNumber,
          );

          await migrator.addColumn(
            suppliers,
            suppliers.creditLimit,
          );
        }

        // =====================================================================
        // VERSION 15
        // =====================================================================

        if (from < 15) {
          await migrator.addColumn(
            purchases,
            purchases.serverId,
          );

          await migrator.addColumn(
            purchaseItems,
            purchaseItems.variantId,
          );

          await migrator.addColumn(
            purchaseItems,
            purchaseItems.unitId,
          );

          await migrator.addColumn(
            purchaseItems,
            purchaseItems.discountPercent,
          );
        }

        // =====================================================================
        // VERSION 16
        // =====================================================================

        if (from < 16) {
          await migrator.addColumn(
            sales,
            sales.serverId,
          );

          await migrator.addColumn(
            saleItems,
            saleItems.variantId,
          );

          await migrator.addColumn(
            saleItems,
            saleItems.unitId,
          );

          await migrator.addColumn(
            saleItems,
            saleItems.discountPercent,
          );
        }

        // =====================================================================
        // VERSION 17
        // =====================================================================

        if (from < 17) {
          await migrator.addColumn(
            customers,
            customers.serverId,
          );
        }

        // =====================================================================
        // VERSION 18
        // =====================================================================

        if (from < 18) {
          await migrator.addColumn(
            customers,
            customers.email,
          );

          await migrator.addColumn(
            customers,
            customers.type,
          );

          await migrator.addColumn(
            customers,
            customers.creditLimit,
          );
        }

        // =====================================================================
        // VERSION 19
        // HELD SALES
        // =====================================================================

        if (from < 19) {
          await migrator.createTable(
            heldSales,
          );

          await migrator.createTable(
            heldSaleItems,
          );
        }

        // =====================================================================
        // VERSION 20
        // CASHBOX
        // =====================================================================

        if (from < 20) {
          await migrator.createTable(
            cashboxSessions,
          );
        }

        // =====================================================================
        // VERSION 21
        //
        // - Multiple cashbox sessions per business day.
        // - Link every new sale to its cashbox session.
        // =====================================================================

        if (from < 21) {
          await migrator.addColumn(
            sales,
            sales.cashboxSessionId,
          );

          if (from >= 20) {
            await customStatement(
              '''
              ALTER TABLE cashbox_sessions
              RENAME TO cashbox_sessions_v20
              ''',
            );

            await migrator.createTable(
              cashboxSessions,
            );

            await customStatement(
              '''
              INSERT INTO cashbox_sessions (
                id,
                business_date,
                opening_balance,
                total_sales,
                cash_sales,
                credit_sales,
                partial_sales,
                cash_received,
                remaining_amount,
                invoices_count,
                expected_cash,
                counted_cash,
                difference,
                status,
                note,
                opened_at,
                closed_at,
                created_at,
                updated_at
              )
              SELECT
                id,
                business_date,
                opening_balance,
                total_sales,
                cash_sales,
                credit_sales,
                partial_sales,
                cash_received,
                remaining_amount,
                invoices_count,
                expected_cash,
                counted_cash,
                difference,
                status,
                note,
                opened_at,
                closed_at,
                created_at,
                updated_at
              FROM cashbox_sessions_v20
              ''',
            );

            await customStatement(
              '''
              DROP TABLE cashbox_sessions_v20
              ''',
            );
          }

          await customStatement(
            '''
            UPDATE sales
            SET cashbox_session_id = (
              SELECT c.id
              FROM cashbox_sessions c
              WHERE c.business_date =
                    strftime(
                      '%Y-%m-%d',
                      sales.created_at / 1000,
                      'unixepoch',
                      'localtime'
                    )
                AND sales.created_at >= c.opened_at
                AND (
                  c.closed_at IS NULL
                  OR sales.created_at <= c.closed_at
                )
              ORDER BY c.opened_at DESC
              LIMIT 1
            )
            WHERE cashbox_session_id IS NULL
            ''',
          );
        }

        // =====================================================================
        // VERSION 22
        // REPRESENTATIVE SERVER MAPPING
        // =====================================================================

        if (from < 22) {
          await migrator.addColumn(
            representatives,
            representatives.serverId,
          );
        }

        // =====================================================================
        // VERSION 23
        // CUSTOMER GROUP AND REPRESENTATIVE
        // =====================================================================

        if (from < 23) {
          await migrator.addColumn(
            customers,
            customers.groupName,
          );

          await migrator.addColumn(
            customers,
            customers.representativeId,
          );
        }

        // =====================================================================
        // VERSION 24
        // SALE CURRENCY
        // =====================================================================

        if (from < 24) {
          await migrator.addColumn(
            sales,
            sales.currency,
          );

          await migrator.addColumn(
            sales,
            sales.exchangeRate,
          );

          await migrator.addColumn(
            sales,
            sales.totalUsd,
          );
        }

        if (from < 25) {
          await migrator.addColumn(
            sales,
            sales.notes,
          );
        }

        if (from < 26) {
          await migrator.addColumn(
            representatives,
            representatives.allowedPrices,
          );
        }

        if (from < 27) {
          await migrator.addColumn(
            purchases,
            purchases.currency,
          );
          await migrator.addColumn(
            purchases,
            purchases.exchangeRate,
          );
          await migrator.addColumn(
            purchases,
            purchases.totalUsd,
          );
        }

        if (from < 28) {
          await customStatement(
            '''
            CREATE TABLE IF NOT EXISTS currency_exchanges (
              id TEXT PRIMARY KEY,
              kind TEXT NOT NULL,
              usd_amount REAL NOT NULL,
              rate REAL NOT NULL,
              iqd_amount REAL NOT NULL,
              party_name TEXT,
              note TEXT,
              created_at TEXT NOT NULL
            )
            ''',
          );
        }

        if (from < 29) {
          await migrator.addColumn(sales, sales.porterage);
          await migrator.addColumn(purchases, purchases.porterage);
          await migrator.addColumn(saleItems, saleItems.unitFactor);
          await migrator.addColumn(purchaseItems, purchaseItems.unitFactor);
          await migrator.addColumn(heldSaleItems, heldSaleItems.unitFactor);
        }

        if (from < 30) {
          await migrator.addColumn(products, products.piecesPerCarton);
          await migrator.addColumn(saleItems, saleItems.loosePieces);
          await migrator.addColumn(heldSaleItems, heldSaleItems.loosePieces);
        }

        if (from < 31) {
          await migrator.addColumn(
            customerLedgerEntries,
            customerLedgerEntries.currency,
          );
          await migrator.addColumn(
            supplierLedgerEntries,
            supplierLedgerEntries.currency,
          );
          await migrator.addColumn(
            customerPayments,
            customerPayments.currency,
          );
          await migrator.addColumn(
            supplierPayments,
            supplierPayments.currency,
          );
          await customStatement(
            '''
            UPDATE customer_ledger_entries
            SET currency = 'USD',
                amount = (
                  SELECT s.total_usd FROM sales s
                  WHERE s.id = customer_ledger_entries.reference_id
                )
            WHERE type = 'SALE'
              AND EXISTS (
                SELECT 1 FROM sales s
                WHERE s.id = customer_ledger_entries.reference_id
                  AND s.currency = 'USD'
                  AND s.total_usd > 0
                  AND ABS(s.total - customer_ledger_entries.amount) < 1
              )
            ''',
          );
          await customStatement(
            '''
            UPDATE customer_payments
            SET currency = 'USD',
                amount = amount / (
                  SELECT s.exchange_rate FROM sales s
                  WHERE s.id = customer_payments.reference_id
                )
            WHERE COALESCE(currency, 'IQD') <> 'USD'
              AND EXISTS (
                SELECT 1 FROM sales s
                WHERE s.id = customer_payments.reference_id
                  AND s.currency = 'USD'
                  AND s.exchange_rate > 0
              )
            ''',
          );
          await customStatement(
            '''
            UPDATE customer_ledger_entries
            SET currency = 'USD',
                amount = (
                  SELECT p.amount FROM customer_payments p
                  WHERE p.id = customer_ledger_entries.reference_id
                )
            WHERE type = 'RECEIPT'
              AND reference_id IN (
                SELECT id FROM customer_payments WHERE currency = 'USD'
              )
            ''',
          );
          await customStatement(
            '''
            UPDATE supplier_ledger_entries
            SET currency = 'USD',
                amount = (
                  SELECT p.total_usd FROM purchases p
                  WHERE p.id = supplier_ledger_entries.reference_id
                )
            WHERE type = 'PURCHASE'
              AND EXISTS (
                SELECT 1 FROM purchases p
                WHERE p.id = supplier_ledger_entries.reference_id
                  AND p.currency = 'USD'
                  AND p.total_usd > 0
                  AND ABS(p.total - supplier_ledger_entries.amount) < 1
              )
            ''',
          );
          await customStatement(
            '''
            UPDATE supplier_payments
            SET currency = 'USD',
                amount = amount / (
                  SELECT p.exchange_rate FROM purchases p
                  WHERE p.id = supplier_payments.reference_id
                )
            WHERE COALESCE(currency, 'IQD') <> 'USD'
              AND EXISTS (
                SELECT 1 FROM purchases p
                WHERE p.id = supplier_payments.reference_id
                  AND p.currency = 'USD'
                  AND p.exchange_rate > 0
              )
            ''',
          );
          await customStatement(
            '''
            UPDATE supplier_ledger_entries
            SET currency = 'USD',
                amount = (
                  SELECT p.amount FROM supplier_payments p
                  WHERE p.id = supplier_ledger_entries.reference_id
                )
            WHERE type = 'PAYMENT'
              AND reference_id IN (
                SELECT id FROM supplier_payments WHERE currency = 'USD'
              )
            ''',
          );
        }

        if (from < 32) {
          await migrator.createTable(saleReturns);
          await migrator.createTable(saleReturnItems);
        }

        if (from < 33) {
          await _ensureFloorTables((sql) => customStatement(sql));
        }
      },

      beforeOpen: (details) async {
        await customStatement(
          'PRAGMA foreign_keys = ON',
        );
        await _ensureFloorTables((sql) => customStatement(sql));
      },
    );
  }

  Future<void> _ensureFloorTables(
    Future<void> Function(String sql) exec,
  ) async {
    await exec('''
      CREATE TABLE IF NOT EXISTS stock_sale_locks (
        variant_id TEXT PRIMARY KEY,
        server_variant_id TEXT,
        reason TEXT NOT NULL,
        sale_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await exec('''
      CREATE TABLE IF NOT EXISTS sale_conflicts (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        variant_id TEXT,
        server_variant_id TEXT,
        message TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await exec('''
      CREATE TABLE IF NOT EXISTS floor_pending_events (
        id INTEGER PRIMARY KEY,
        event_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  // ===========================================================================
  // V11 INVENTORY MIGRATION
  // ===========================================================================

  Future<void> _migrateInventoryToVariants(
      Migrator migrator,
      ) async {
    await customStatement(
      'PRAGMA foreign_keys = OFF',
    );

    await customStatement(
      '''
      ALTER TABLE stock_balances
      RENAME TO stock_balances_legacy_v10
      ''',
    );

    await migrator.createTable(
      stockBalances,
    );

    await customStatement(
      '''
      INSERT INTO stock_balances (
        id,
        variant_id,
        warehouse_id,
        quantity,
        updated_at
      )
      SELECT
        (
          SELECT pv.id
          FROM product_variants pv
          WHERE pv.product_id = old.product_id
            AND pv.deleted_at IS NULL
          LIMIT 1
        ) || '::' || old.warehouse_id,
        (
          SELECT pv.id
          FROM product_variants pv
          WHERE pv.product_id = old.product_id
            AND pv.deleted_at IS NULL
          LIMIT 1
        ),
        old.warehouse_id,
        old.quantity,
        old.updated_at
      FROM stock_balances_legacy_v10 old
      WHERE (
        SELECT COUNT(*)
        FROM product_variants pv
        WHERE pv.product_id = old.product_id
          AND pv.deleted_at IS NULL
      ) = 1
      ''',
    );

    await customStatement(
      '''
      ALTER TABLE stock_movements
      RENAME TO stock_movements_legacy_v10
      ''',
    );

    await migrator.createTable(
      stockMovements,
    );

    await customStatement(
      '''
      INSERT INTO stock_movements (
        id,
        variant_id,
        warehouse_id,
        type,
        quantity,
        reference_type,
        reference_id,
        note,
        user_id,
        server_version,
        created_at,
        synced_at
      )
      SELECT
        old.id,
        (
          SELECT pv.id
          FROM product_variants pv
          WHERE pv.product_id = old.product_id
            AND pv.deleted_at IS NULL
          LIMIT 1
        ),
        old.warehouse_id,
        old.quantity,
        old.type,
        old.quantity,
        old.reference_type,
        old.reference_id,
        old.note,
        old.user_id,
        old.server_version,
        old.created_at,
        old.synced_at
      FROM stock_movements_legacy_v10 old
      WHERE (
        SELECT COUNT(*)
        FROM product_variants pv
        WHERE pv.product_id = old.product_id
          AND pv.deleted_at IS NULL
      ) = 1
      ''',
    );

    await customStatement(
      'PRAGMA foreign_keys = ON',
    );
  }
}

// =============================================================================
// DATABASE CONNECTION
// =============================================================================

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'sayler',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}