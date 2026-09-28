import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../models/dashboard_data.dart';

class DashboardRepository {
  final AppDatabase database;

  const DashboardRepository({
    required this.database,
  });

  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  Stream<DashboardSummary> watchSummary() {
    final query = database.customSelect(
      '''
      SELECT
        (
          SELECT COALESCE(SUM(s.total), 0.0)
          FROM sales s
          WHERE s.deleted_at IS NULL
            AND date(
              s.created_at / 1000,
              'unixepoch',
              'localtime'
            ) = date(
              'now',
              'localtime'
            )
        ) AS today_sales,

        (
          SELECT COUNT(*)
          FROM sales s
          WHERE s.deleted_at IS NULL
            AND date(
              s.created_at / 1000,
              'unixepoch',
              'localtime'
            ) = date(
              'now',
              'localtime'
            )
        ) AS today_invoices_count,

        (
          SELECT COALESCE(
            SUM(
              CASE
                WHEN cle.type = 'SALE'
                  AND COALESCE(cle.currency, 'IQD') <> 'USD'
                  THEN cle.amount

                WHEN cle.type = 'OPENING_BALANCE'
                  AND COALESCE(cle.currency, 'IQD') <> 'USD'
                  THEN cle.amount

                WHEN cle.type = 'RECEIPT'
                  AND COALESCE(cle.currency, 'IQD') <> 'USD'
                  THEN -cle.amount

                WHEN cle.type = 'REVERSAL'
                  AND COALESCE(cle.currency, 'IQD') <> 'USD'
                  THEN -cle.amount

                WHEN cle.type = 'PAYMENT'
                  AND COALESCE(cle.currency, 'IQD') <> 'USD'
                  THEN cle.amount

                ELSE 0
              END
            ),
            0.0
          )
          FROM customer_ledger_entries cle
        ) AS customer_debt,

        (
          SELECT COALESCE(
            SUM(
              CASE
                WHEN cle.type = 'SALE'
                  AND cle.currency = 'USD'
                  THEN cle.amount

                WHEN cle.type = 'OPENING_BALANCE'
                  AND cle.currency = 'USD'
                  THEN cle.amount

                WHEN cle.type = 'RECEIPT'
                  AND cle.currency = 'USD'
                  THEN -cle.amount

                WHEN cle.type = 'REVERSAL'
                  AND cle.currency = 'USD'
                  THEN -cle.amount

                WHEN cle.type = 'PAYMENT'
                  AND cle.currency = 'USD'
                  THEN cle.amount

                ELSE 0
              END
            ),
            0.0
          )
          FROM customer_ledger_entries cle
        ) AS customer_debt_usd,

        (
          SELECT COUNT(*)
          FROM (
            SELECT
              p.id
            FROM products p

            LEFT JOIN product_variants pv
              ON pv.product_id = p.id
              AND pv.deleted_at IS NULL
              AND pv.is_active = 1

            LEFT JOIN stock_balances sb
              ON sb.variant_id = pv.id

            WHERE p.deleted_at IS NULL
              AND p.is_active = 1
              AND p.minimum_stock > 0

            GROUP BY
              p.id,
              p.minimum_stock

            HAVING
              COALESCE(
                SUM(sb.quantity),
                0.0
              ) < p.minimum_stock
          ) low_stock_products
        ) AS low_stock_count,

        (
          SELECT COALESCE(
            SUM(s.total),
            0.0
          )
          FROM sales s
          WHERE s.deleted_at IS NULL
            AND s.payment_type = 'CASH'
            AND date(
              s.created_at / 1000,
              'unixepoch',
              'localtime'
            ) = date(
              'now',
              'localtime'
            )
        ) AS today_cash_sales,

        (
          SELECT COALESCE(
            SUM(s.remaining_amount),
            0.0
          )
          FROM sales s
          WHERE s.deleted_at IS NULL
            AND s.remaining_amount > 0
            AND date(
              s.created_at / 1000,
              'unixepoch',
              'localtime'
            ) = date(
              'now',
              'localtime'
            )
        ) AS today_credit_amount,

        (
          SELECT COALESCE(
            SUM(s.total),
            0.0
          )
          FROM sales s
          WHERE s.deleted_at IS NULL
            AND s.representative_id IS NOT NULL
            AND date(
              s.created_at / 1000,
              'unixepoch',
              'localtime'
            ) = date(
              'now',
              'localtime'
            )
        ) AS today_representative_sales,

        (
          SELECT COUNT(*)
          FROM products p
          WHERE p.deleted_at IS NULL
            AND p.is_active = 1
        ) AS active_products_count
      ''',
      readsFrom: {
        database.sales,
        database.products,
        database.productVariants,
        database.stockBalances,
        database.customerLedgerEntries,
      },
    );

    return query.watchSingle().map(
          (row) {
        final rawDebt =
        row.read<double>('customer_debt');

        return DashboardSummary(
          todaySales:
          row.read<double>('today_sales'),
          todayInvoicesCount:
          row.read<int>('today_invoices_count'),
          totalCustomerDebt:
          rawDebt < 0 ? 0 : rawDebt,
          totalCustomerDebtUsd:
          row.read<double>('customer_debt_usd'),
          lowStockCount:
          row.read<int>('low_stock_count'),
          todayCashSales:
          row.read<double>('today_cash_sales'),
          todayCreditAmount:
          row.read<double>('today_credit_amount'),
          todayRepresentativeSales:
          row.read<double>(
            'today_representative_sales',
          ),
          activeProductsCount:
          row.read<int>('active_products_count'),
        );
      },
    );
  }

  // ===========================================================================
  // RECENT SALES
  // ===========================================================================

  Stream<List<DashboardRecentSale>>
  watchRecentSales({
    int limit = 4,
  }) {
    final query = database.customSelect(
      '''
      SELECT
        s.id,
        s.invoice_number,
        s.customer_name,
        s.payment_type,
        s.total,
        s.paid_amount,
        s.remaining_amount,
        s.created_at
      FROM sales s
      WHERE s.deleted_at IS NULL
      ORDER BY s.created_at DESC
      LIMIT ?
      ''',
      variables: [
        Variable<int>(limit),
      ],
      readsFrom: {
        database.sales,
      },
    );

    return query.watch().map(
          (rows) {
        return rows.map(
              (row) {
            return DashboardRecentSale(
              id: row.read<String>('id'),
              invoiceNumber:
              row.read<String>(
                'invoice_number',
              ),
              customerName:
              row.read<String>(
                'customer_name',
              ),
              paymentType:
              row.read<String>(
                'payment_type',
              ),
              total:
              row.read<double>('total'),
              paidAmount:
              row.read<double>(
                'paid_amount',
              ),
              remainingAmount:
              row.read<double>(
                'remaining_amount',
              ),
              createdAt:
              row.read<DateTime>(
                'created_at',
              ),
            );
          },
        ).toList();
      },
    );
  }

  // ===========================================================================
  // LOW STOCK
  // ===========================================================================

  Stream<List<DashboardLowStockItem>>
  watchLowStock({
    int limit = 4,
  }) {
    final query = database.customSelect(
      '''
      SELECT
        p.id AS product_id,
        p.name AS product_name,
        p.unit AS unit,
        p.minimum_stock AS minimum_stock,
        COALESCE(
          SUM(sb.quantity),
          0.0
        ) AS total_quantity
      FROM products p

      LEFT JOIN product_variants pv
        ON pv.product_id = p.id
        AND pv.deleted_at IS NULL
        AND pv.is_active = 1

      LEFT JOIN stock_balances sb
        ON sb.variant_id = pv.id

      WHERE p.deleted_at IS NULL
        AND p.is_active = 1
        AND p.minimum_stock > 0

      GROUP BY
        p.id,
        p.name,
        p.unit,
        p.minimum_stock

      HAVING
        COALESCE(
          SUM(sb.quantity),
          0.0
        ) < p.minimum_stock

      ORDER BY
        total_quantity ASC,
        p.name ASC

      LIMIT ?
      ''',
      variables: [
        Variable<int>(limit),
      ],
      readsFrom: {
        database.products,
        database.productVariants,
        database.stockBalances,
      },
    );

    return query.watch().map(
          (rows) {
        return rows.map(
              (row) {
            return DashboardLowStockItem(
              productId:
              row.read<String>(
                'product_id',
              ),
              productName:
              row.read<String>(
                'product_name',
              ),
              unit:
              row.read<String>('unit'),
              quantity:
              row.read<double>(
                'total_quantity',
              ),
              minimumStock:
              row.read<double>(
                'minimum_stock',
              ),
            );
          },
        ).toList();
      },
    );
  }
}