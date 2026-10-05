import {
    BadRequestException,
    ForbiddenException,
    Injectable,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

type Filters = Record<string, string | undefined>;

@Injectable()
export class ReportsService {
    constructor(private readonly db: PrismaService) { }

    private isUuid(value: string): boolean {
        return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
            value,
        );
    }

    private async scope(userId: string, q: Filters) {
        const user = await this.db.users.findUnique({
            where: { id: userId },
            select: {
                is_active: true,
                branch_id: true,
                roles: {
                    select: {
                        name: true,
                        role_permissions: {
                            select: {
                                permissions: {
                                    select: {
                                        resource: true,
                                        action: true,
                                    },
                                },
                            },
                        },
                    },
                },
            },
        });

        if (!user?.is_active) {
            throw new ForbiddenException('المستخدم غير فعال');
        }

        const roleName = (user.roles?.name ?? '').toUpperCase();
        const admin = ['ADMIN', 'SUPER_ADMIN'].includes(roleName);
        const branchLocked = !admin && !!user.branch_id;

        if (
            branchLocked &&
            q.branch_id &&
            q.branch_id !== user.branch_id
        ) {
            throw new ForbiddenException('التقرير خارج نطاق فرعك');
        }

        const branch = branchLocked ? user.branch_id : (q.branch_id ?? null);

        if (branch && !this.isUuid(branch)) {
            throw new BadRequestException('branch_id غير صالح');
        }

        if (q.warehouse_id && !this.isUuid(q.warehouse_id)) {
            throw new BadRequestException('warehouse_id غير صالح');
        }

        return {
            admin,
            branch,
            branchSql: (column: Prisma.Sql) =>
                branch
                    ? Prisma.sql`AND ${column} = ${branch}::uuid`
                    : Prisma.empty,
            warehouseSql: (column: Prisma.Sql) =>
                q.warehouse_id
                    ? Prisma.sql`AND ${column} = ${q.warehouse_id}::uuid`
                    : Prisma.empty,
        };
    }

    private dates(q: Filters) {
        for (const key of ['from', 'to'] as const) {
            const value = q[key];
            if (!value) continue;

            const date = new Date(`${value}T00:00:00Z`);

            if (
                !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
                Number.isNaN(date.getTime()) ||
                date.toISOString().slice(0, 10) !== value
            ) {
                throw new BadRequestException(`${key} يجب أن يكون YYYY-MM-DD`);
            }
        }

        if (q.from && q.to && q.from > q.to) {
            throw new BadRequestException('بداية الفترة بعد نهايتها');
        }

        return (column: Prisma.Sql) => Prisma.sql`
      ${q.from
                ? Prisma.sql`AND (${column} AT TIME ZONE 'Asia/Baghdad')::date >= ${q.from}::date`
                : Prisma.empty}
      ${q.to
                ? Prisma.sql`AND (${column} AT TIME ZONE 'Asia/Baghdad')::date <= ${q.to}::date`
                : Prisma.empty}
    `;
    }

    private page(q: Filters): Prisma.Sql {
        const page = Number(q.page ?? 1);
        const limit = Number(q.limit ?? 50);

        if (
            !Number.isInteger(page) ||
            page < 1 ||
            !Number.isInteger(limit) ||
            limit < 1 ||
            limit > 100
        ) {
            throw new BadRequestException(
                'page وlimit غير صالحين؛ الحد الأعلى 100',
            );
        }

        return Prisma.sql`LIMIT ${limit} OFFSET ${(page - 1) * limit}`;
    }

    private viewBranch(branchId: string | null): Prisma.Sql {
        if (!branchId) return Prisma.empty;

        // r.branch_code موجود في Views الصندوق.
        return Prisma.sql`
      AND EXISTS (
        SELECT 1
        FROM public.branches b
        WHERE b.id = ${branchId}::uuid
          AND b.code = r.branch_code
      )
    `;
    }

    // ─────────────── الزبائن ───────────────

    async customers(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        const search = q.search?.trim();

        if (search && search.length > 100) {
            throw new BadRequestException('نص البحث طويل');
        }

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        c.name AS customer_name,
        c.phone,
        c.email,
        c.type::text AS customer_type,
        c.is_active,
        r.name AS representative_name,
        ${s.admin
                ? Prisma.sql`c.balance`
                : Prisma.sql`NULL::numeric`} AS recorded_balance
      FROM public.customers c
      LEFT JOIN public.representatives r
        ON r.id = c.assigned_rep_id
      WHERE 1 = 1
        ${s.branch
                ? Prisma.sql`
              AND (
                r.branch_id = ${s.branch}::uuid
                OR EXISTS (
                  SELECT 1
                  FROM public.sales_invoices i
                  JOIN public.warehouses w
                    ON w.id = i.warehouse_id
                  WHERE i.customer_id = c.id
                    AND w.branch_id = ${s.branch}::uuid
                )
              )
            `
                : Prisma.empty}
        ${search
                ? Prisma.sql`
              AND (
                c.name ILIKE ${`%${search}%`}
                OR c.phone ILIKE ${`%${search}%`}
              )
            `
                : Prisma.empty}
      ORDER BY c.name, c.phone NULLS LAST
      ${this.page(q)}
    `);
    }

    async customerBalances(userId: string, q: Filters) {
        const s = await this.scope(userId, q);

        // customers.balance رصيد عالمي؛ لا يمكن تقسيمه بين الفروع بدقة.
        if (!s.admin) {
            throw new ForbiddenException(
                'إجمالي أرصدة الزبائن متاح للإدارة فقط',
            );
        }

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        coalesce(
          sum(c.balance) FILTER (WHERE c.balance > 0),
          0
        ) AS debit_total_iqd,
        coalesce(
          sum(-c.balance) FILTER (WHERE c.balance < 0),
          0
        ) AS credit_total_iqd,
        count(*)::integer AS customer_count
      FROM public.customers c
    `);
    }

    async customerStatement(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        this.dates(q);

        if (!q.customer_id || !this.isUuid(q.customer_id)) {
            throw new BadRequestException('customer_id مطلوب وصالح');
        }

        return this.db.$queryRaw(Prisma.sql`
      WITH allocated AS (
        SELECT
          sales_invoice_id,
          sum(amount) AS allocated_amount
        FROM public.payment_vouchers
        WHERE voucher_type = 'RECEIPT'
          AND sales_invoice_id IS NOT NULL
        GROUP BY sales_invoice_id
      ),
      entries AS (
        SELECT
          i.customer_id,
          c.name AS customer_name,
          i.invoice_date AS occurred_at,
          i.invoice_number AS reference_number,
          'SALE'::text AS entry_type,
          w.name AS warehouse_name,
          i.total AS debit_iqd,
          0::numeric AS credit_iqd,
          1 AS sort_order
        FROM public.sales_invoices i
        JOIN public.customers c ON c.id = i.customer_id
        JOIN public.warehouses w ON w.id = i.warehouse_id
        WHERE i.customer_id = ${q.customer_id}::uuid
          AND i.status IN ('PAID', 'PARTIAL', 'OVERDUE')
          ${s.branchSql(Prisma.sql`w.branch_id`)}

        UNION ALL

        SELECT
          i.customer_id,
          c.name,
          i.invoice_date,
          i.invoice_number,
          'PAYMENT_AT_SALE',
          w.name,
          0::numeric,
          greatest(
            i.paid_amount - coalesce(a.allocated_amount, 0),
            0
          ),
          2
        FROM public.sales_invoices i
        JOIN public.customers c ON c.id = i.customer_id
        JOIN public.warehouses w ON w.id = i.warehouse_id
        LEFT JOIN allocated a ON a.sales_invoice_id = i.id
        WHERE i.customer_id = ${q.customer_id}::uuid
          AND i.status IN ('PAID', 'PARTIAL', 'OVERDUE')
          AND i.paid_amount > coalesce(a.allocated_amount, 0)
          ${s.branchSql(Prisma.sql`w.branch_id`)}

        UNION ALL

        SELECT
          v.customer_id,
          c.name,
          v.created_at,
          v.voucher_number,
          'RECEIPT',
          w.name,
          0::numeric,
          v.amount,
          3
        FROM public.payment_vouchers v
        JOIN public.customers c ON c.id = v.customer_id
        LEFT JOIN public.cashboxes cb ON cb.id = v.cashbox_id
        LEFT JOIN public.sales_invoices i
          ON i.id = v.sales_invoice_id
        LEFT JOIN public.warehouses w
          ON w.id = i.warehouse_id
        WHERE v.customer_id = ${q.customer_id}::uuid
          AND v.voucher_type = 'RECEIPT'
          ${s.branch
                ? Prisma.sql`
                AND (
                  cb.branch_id = ${s.branch}::uuid
                  OR (
                    cb.id IS NULL
                    AND w.branch_id = ${s.branch}::uuid
                  )
                )
              `
                : Prisma.empty}
      ),
      running AS (
        SELECT
          customer_name,
          occurred_at,
          reference_number,
          entry_type,
          warehouse_name,
          debit_iqd,
          credit_iqd,
          sum(debit_iqd - credit_iqd) OVER (
            ORDER BY occurred_at, reference_number, sort_order
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          ) AS running_balance_iqd
        FROM entries
      )
      SELECT *
      FROM running
      WHERE 1 = 1
        ${q.from
                ? Prisma.sql`
              AND (
                occurred_at AT TIME ZONE 'Asia/Baghdad'
              )::date >= ${q.from}::date
            `
                : Prisma.empty}
        ${q.to
                ? Prisma.sql`
              AND (
                occurred_at AT TIME ZONE 'Asia/Baghdad'
              )::date <= ${q.to}::date
            `
                : Prisma.empty}
      ORDER BY occurred_at, reference_number
      ${this.page(q)}
    `);
    }

    // ─────────────── المواد ───────────────

    async prices(userId: string, q: Filters) {
        await this.scope(userId, q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        p.name_ar AS product_name,
        coalesce(v.sku, p.sku) AS product_code,
        u.name_ar AS unit_name,
        pp.price_type::text AS price_type,
        pp.price AS sale_price_iqd,
        pp.updated_at
      FROM public.product_prices pp
      JOIN public.product_variants v ON v.id = pp.variant_id
      JOIN public.products p ON p.id = v.product_id
      JOIN public.units_of_measure u ON u.id = pp.unit_id
      WHERE pp.is_active
        AND p.is_active
        AND v.is_active
      ORDER BY p.name_ar, pp.price_type, u.name_ar
      ${this.page(q)}
    `);
    }

    async expiry(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        const days = Number(q.days ?? 30);

        if (!Number.isInteger(days) || days < 0 || days > 3650) {
            throw new BadRequestException('days غير صالح');
        }

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        p.name_ar AS product_name,
        coalesce(v.sku, p.sku) AS product_code,
        w.name AS warehouse_name,
        b.batch_number,
        b.expiry_date,
        b.quantity,
        b.expiry_date -
          (now() AT TIME ZONE 'Asia/Baghdad')::date
          AS days_remaining
      FROM public.product_batches b
      JOIN public.product_variants v ON v.id = b.variant_id
      JOIN public.products p ON p.id = v.product_id
      JOIN public.warehouses w ON w.id = b.warehouse_id
      WHERE b.quantity > 0
        AND b.expiry_date IS NOT NULL
        AND b.expiry_date <=
          (now() AT TIME ZONE 'Asia/Baghdad')::date + ${days}
        ${s.branchSql(Prisma.sql`w.branch_id`)}
        ${s.warehouseSql(Prisma.sql`w.id`)}
      ORDER BY b.expiry_date, p.name_ar
      ${this.page(q)}
    `);
    }

    async stock(
        userId: string,
        q: Filters,
        belowReorder: boolean,
    ) {
        const s = await this.scope(userId, q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        p.name_ar AS product_name,
        coalesce(v.sku, p.sku) AS product_code,
        w.name AS warehouse_name,
        sl.quantity_on_hand,
        sl.quantity_reserved,
        sl.quantity_in_transit,
        sl.quantity_on_hand -
          sl.quantity_reserved AS quantity_available,
        p.min_stock_level,
        sl.quantity_on_hand * v.weighted_avg_cost
          AS stock_value_iqd
      FROM public.stock_levels sl
      JOIN public.product_variants v ON v.id = sl.variant_id
      JOIN public.products p ON p.id = v.product_id
      JOIN public.warehouses w ON w.id = sl.warehouse_id
      WHERE 1 = 1
        ${s.branchSql(Prisma.sql`w.branch_id`)}
        ${s.warehouseSql(Prisma.sql`w.id`)}
        ${belowReorder
                ? Prisma.sql`
              AND sl.quantity_on_hand -
                  sl.quantity_reserved < p.min_stock_level
            `
                : Prisma.empty}
      ORDER BY p.name_ar, w.name
      ${this.page(q)}
    `);
    }

    async productSales(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        const dates = this.dates(q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        p.name_ar AS product_name,
        coalesce(v.sku, p.sku) AS product_code,
        sum(it.quantity_in_base_unit) AS sold_base_quantity,
        sum(it.total_price) AS sales_total_iqd,
        count(DISTINCT i.id)::integer AS invoice_count
      FROM public.sales_invoice_items it
      JOIN public.sales_invoices i ON i.id = it.invoice_id
      JOIN public.product_variants v ON v.id = it.variant_id
      JOIN public.products p ON p.id = v.product_id
      JOIN public.warehouses w ON w.id = i.warehouse_id
      WHERE i.status IN ('PAID', 'PARTIAL', 'OVERDUE')
        ${s.branchSql(Prisma.sql`w.branch_id`)}
        ${s.warehouseSql(Prisma.sql`w.id`)}
        ${dates(Prisma.sql`i.invoice_date`)}
      GROUP BY p.id, p.name_ar, v.sku, p.sku
      ORDER BY sales_total_iqd DESC
      ${this.page(q)}
    `);
    }

    async purchaseAnalysis(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        this.dates(q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        i.invoice_number,
        i.invoice_date,
        sup.name AS supplier_name,
        w.name AS warehouse_name,
        p.name_ar AS product_name,
        coalesce(v.sku, p.sku) AS product_code,
        u.name_ar AS unit_name,
        it.quantity,
        it.unit_cost AS unit_cost_iqd,
        it.total_price AS line_total_iqd
      FROM public.purchase_invoice_items it
      JOIN public.purchase_invoices i ON i.id = it.invoice_id
      JOIN public.suppliers sup ON sup.id = i.supplier_id
      JOIN public.warehouses w ON w.id = i.warehouse_id
      JOIN public.product_variants v ON v.id = it.variant_id
      JOIN public.products p ON p.id = v.product_id
      JOIN public.units_of_measure u ON u.id = it.unit_id
      WHERE i.status IN ('CONFIRMED', 'PARTIAL', 'PAID')
        ${s.branchSql(Prisma.sql`w.branch_id`)}
        ${s.warehouseSql(Prisma.sql`w.id`)}
        ${q.from
                ? Prisma.sql`AND i.invoice_date >= ${q.from}::date`
                : Prisma.empty}
        ${q.to
                ? Prisma.sql`AND i.invoice_date <= ${q.to}::date`
                : Prisma.empty}
      ORDER BY i.invoice_date DESC, i.invoice_number
      ${this.page(q)}
    `);
    }

    async salesAnalysis(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        const dates = this.dates(q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        i.invoice_number,
        i.invoice_date,
        coalesce(c.name, 'زبون نقدي') AS customer_name,
        w.name AS warehouse_name,
        p.name_ar AS product_name,
        coalesce(v.sku, p.sku) AS product_code,
        u.name_ar AS unit_name,
        it.quantity,
        it.net_unit_price AS unit_price_iqd,
        it.total_price AS line_total_iqd
      FROM public.sales_invoice_items it
      JOIN public.sales_invoices i ON i.id = it.invoice_id
      LEFT JOIN public.customers c ON c.id = i.customer_id
      JOIN public.warehouses w ON w.id = i.warehouse_id
      JOIN public.product_variants v ON v.id = it.variant_id
      JOIN public.products p ON p.id = v.product_id
      JOIN public.units_of_measure u ON u.id = it.unit_id
      WHERE i.status IN ('PAID', 'PARTIAL', 'OVERDUE')
        ${s.branchSql(Prisma.sql`w.branch_id`)}
        ${s.warehouseSql(Prisma.sql`w.id`)}
        ${dates(Prisma.sql`i.invoice_date`)}
      ORDER BY i.invoice_date DESC, i.invoice_number
      ${this.page(q)}
    `);
    }

    async monthlyPurchases(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        this.dates(q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        date_trunc('month', i.invoice_date::timestamp)::date
          AS month,
        count(*)::integer AS invoice_count,
        sum(i.total) AS total_purchases_iqd
      FROM public.purchase_invoices i
      JOIN public.warehouses w ON w.id = i.warehouse_id
      WHERE i.status IN ('CONFIRMED', 'PARTIAL', 'PAID')
        ${s.branchSql(Prisma.sql`w.branch_id`)}
        ${s.warehouseSql(Prisma.sql`w.id`)}
        ${q.from
                ? Prisma.sql`AND i.invoice_date >= ${q.from}::date`
                : Prisma.empty}
        ${q.to
                ? Prisma.sql`AND i.invoice_date <= ${q.to}::date`
                : Prisma.empty}
      GROUP BY 1
      ORDER BY month
    `);
    }

    async monthlySales(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        const dates = this.dates(q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        date_trunc(
          'month',
          i.invoice_date AT TIME ZONE 'Asia/Baghdad'
        )::date AS month,
        count(*)::integer AS invoice_count,
        sum(i.total) AS total_sales_iqd
      FROM public.sales_invoices i
      JOIN public.warehouses w ON w.id = i.warehouse_id
      WHERE i.status IN ('PAID', 'PARTIAL', 'OVERDUE')
        ${s.branchSql(Prisma.sql`w.branch_id`)}
        ${s.warehouseSql(Prisma.sql`w.id`)}
        ${dates(Prisma.sql`i.invoice_date`)}
      GROUP BY 1
      ORDER BY month
    `);
    }

    async movements(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        const dates = this.dates(q);

        if (!q.variant_id || !this.isUuid(q.variant_id)) {
            throw new BadRequestException('variant_id مطلوب وصالح');
        }

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        p.name_ar AS product_name,
        coalesce(v.sku, p.sku) AS product_code,
        w.name AS warehouse_name,
        m.created_at,
        m.movement_type::text AS movement_type,
        m.quantity,
        m.unit_cost AS unit_cost_iqd,
        m.reference_type,
        m.notes
      FROM public.inventory_movements m
      JOIN public.product_variants v ON v.id = m.variant_id
      JOIN public.products p ON p.id = v.product_id
      JOIN public.warehouses w ON w.id = m.warehouse_id
      WHERE m.variant_id = ${q.variant_id}::uuid
        ${s.branchSql(Prisma.sql`w.branch_id`)}
        ${s.warehouseSql(Prisma.sql`w.id`)}
        ${dates(Prisma.sql`m.created_at`)}
      ORDER BY m.created_at, m.id
      ${this.page(q)}
    `);
    }

    // ─────────────── الصندوق ───────────────

    async cashDaily(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        this.dates(q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        (v.created_at AT TIME ZONE 'Asia/Baghdad')::date AS report_date,
        b.name AS branch_name,
        cb.name AS cashbox_name,
        coalesce(sum(v.amount) FILTER (
          WHERE v.voucher_type = 'RECEIPT'
        ), 0) AS receipts_iqd,
        coalesce(sum(v.amount) FILTER (
          WHERE v.voucher_type = 'PAYMENT'
        ), 0) AS payments_iqd,
        coalesce(sum(
          CASE
            WHEN v.voucher_type = 'RECEIPT' THEN v.amount
            ELSE -v.amount
          END
        ), 0) AS net_movement_iqd
      FROM public.payment_vouchers v
      LEFT JOIN public.cashboxes cb ON cb.id = v.cashbox_id
      LEFT JOIN public.branches b ON b.id = cb.branch_id
      WHERE 1 = 1
        ${s.branch
                ? Prisma.sql`AND cb.branch_id = ${s.branch}::uuid`
                : Prisma.empty}
        ${q.from
                ? Prisma.sql`AND (v.created_at AT TIME ZONE 'Asia/Baghdad')::date >= ${q.from}::date`
                : Prisma.empty}
        ${q.to
                ? Prisma.sql`AND (v.created_at AT TIME ZONE 'Asia/Baghdad')::date <= ${q.to}::date`
                : Prisma.empty}
      GROUP BY 1, b.name, cb.name
      ORDER BY report_date DESC, cb.name
      ${this.page(q)}
    `);
    }

    async cashBalances(userId: string, q: Filters) {
        const s = await this.scope(userId, q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        b.name AS branch_name,
        cb.name AS cashbox_name,
        latest.opened_at AS last_session_opened_at,
        latest.opening_balance AS last_opening_balance_iqd,
        latest.total_sales AS recorded_receipts_iqd,
        latest.total_returns AS recorded_payments_iqd,
        CASE
          WHEN latest.status = 'OPEN' THEN
            latest.opening_balance + latest.total_sales - latest.total_returns
          ELSE latest.closing_balance
        END AS calculated_balance_iqd
      FROM (
        SELECT DISTINCT ON (cs.cashbox_id)
          cs.cashbox_id,
          cs.opened_at,
          cs.opening_balance,
          cs.closing_balance,
          cs.total_sales,
          cs.total_returns,
          cs.status
        FROM public.cashbox_sessions cs
        ORDER BY cs.cashbox_id, cs.opened_at DESC
      ) latest
      JOIN public.cashboxes cb ON cb.id = latest.cashbox_id
      LEFT JOIN public.branches b ON b.id = cb.branch_id
      WHERE 1 = 1
        ${s.branch
                ? Prisma.sql`AND cb.branch_id = ${s.branch}::uuid`
                : Prisma.empty}
      ORDER BY b.name, cb.name
      ${this.page(q)}
    `);
    }

    async cashEntries(
        userId: string,
        q: Filters,
        type: 'receipts' | 'payments',
    ) {
        const s = await this.scope(userId, q);
        const dates = this.dates(q);

        const voucherType =
            type === 'receipts' ? 'RECEIPT' : 'PAYMENT';

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        v.created_at AS occurred_at,
        v.voucher_number AS reference_number,
        b.name AS branch_name,
        cb.name AS cashbox_name,
        coalesce(c.name, sup.name, 'غير محدد') AS party_name,
        v.voucher_type::text AS movement_kind,
        v.amount AS amount_iqd
      FROM public.payment_vouchers v
      LEFT JOIN public.customers c ON c.id = v.customer_id
      LEFT JOIN public.suppliers sup ON sup.id = v.supplier_id
      LEFT JOIN public.cashboxes cb ON cb.id = v.cashbox_id
      LEFT JOIN public.branches b ON b.id = cb.branch_id
      WHERE v.voucher_type = ${voucherType}::"voucher_type_enum"
        ${s.branch
                ? Prisma.sql`AND cb.branch_id = ${s.branch}::uuid`
                : Prisma.empty}
        ${dates(Prisma.sql`v.created_at`)}
      ORDER BY v.created_at DESC, v.voucher_number
      ${this.page(q)}
    `);
    }

    async vouchers(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        const dates = this.dates(q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        v.voucher_date,
        v.created_at,
        v.voucher_number,
        v.voucher_type::text AS voucher_type,
        v.payment_method::text AS payment_method,
        v.customer_id,
        v.supplier_id,
        coalesce(c.name, sup.name, 'غير محدد') AS party_name,
        cb.name AS cashbox_name,
        coalesce(
          si.invoice_number,
          pi.invoice_number
        ) AS invoice_number,
        v.amount AS amount_iqd,
        v.notes
      FROM public.payment_vouchers v
      LEFT JOIN public.customers c ON c.id = v.customer_id
      LEFT JOIN public.suppliers sup ON sup.id = v.supplier_id
      LEFT JOIN public.cashboxes cb ON cb.id = v.cashbox_id
      LEFT JOIN public.sales_invoices si
        ON si.id = v.sales_invoice_id
      LEFT JOIN public.purchase_invoices pi
        ON pi.id = v.invoice_id
      LEFT JOIN public.warehouses ws
        ON ws.id = si.warehouse_id
      LEFT JOIN public.warehouses wp
        ON wp.id = pi.warehouse_id
      WHERE 1 = 1
        ${s.branch
                ? Prisma.sql`
              AND coalesce(
                cb.branch_id,
                ws.branch_id,
                wp.branch_id
              ) = ${s.branch}::uuid
            `
                : Prisma.empty}
        ${dates(Prisma.sql`v.created_at`)}
      ORDER BY v.created_at DESC, v.voucher_number
      ${this.page(q)}
    `);
    }

    // ─────────────── الأرباح ───────────────

    async profits(
        userId: string,
        q: Filters,
        by: 'customer' | 'product' | 'invoice',
    ) {
        const s = await this.scope(userId, q);
        const dates = this.dates(q);

        const selection =
            by === 'customer'
                ? Prisma.sql`
            coalesce(c.name, 'زبون نقدي') AS customer_name
          `
                : by === 'product'
                    ? Prisma.sql`
              p.name_ar AS product_name,
              coalesce(v.sku, p.sku) AS product_code
            `
                    : Prisma.sql`
              i.invoice_number,
              i.invoice_date
            `;

        const grouping =
            by === 'customer'
                ? Prisma.sql`c.id, c.name`
                : by === 'product'
                    ? Prisma.sql`p.id, p.name_ar, v.sku, p.sku`
                    : Prisma.sql`
              i.id, i.invoice_number, i.invoice_date
            `;

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        ${selection},
        sum(it.total_price) AS sales_iqd,
        sum(
          it.quantity_in_base_unit *
          it.cost_per_base_unit
        ) AS cost_iqd,
        sum(
          it.total_price -
          it.quantity_in_base_unit *
          it.cost_per_base_unit
        ) AS gross_profit_iqd
      FROM public.sales_invoice_items it
      JOIN public.sales_invoices i ON i.id = it.invoice_id
      JOIN public.product_variants v ON v.id = it.variant_id
      JOIN public.products p ON p.id = v.product_id
      LEFT JOIN public.customers c ON c.id = i.customer_id
      JOIN public.warehouses w ON w.id = i.warehouse_id
      WHERE i.status IN ('PAID', 'PARTIAL', 'OVERDUE')
        ${s.branchSql(Prisma.sql`w.branch_id`)}
        ${s.warehouseSql(Prisma.sql`w.id`)}
        ${dates(Prisma.sql`i.invoice_date`)}
      GROUP BY ${grouping}
      ORDER BY gross_profit_iqd DESC
      ${this.page(q)}
    `);
    }

    async salesDiscounts(userId: string, q: Filters) {
        const s = await this.scope(userId, q);
        const dates = this.dates(q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        i.invoice_number,
        i.invoice_date,
        coalesce(c.name, 'زبون نقدي') AS customer_name,
        i.subtotal,
        i.discount_amount AS invoice_discount_iqd,
        coalesce(sum(
          CASE
            WHEN it.discount_percent > 0 THEN
              it.quantity * it.unit_price * it.discount_percent / 100
            ELSE 0
          END
        ), 0) AS item_discount_iqd
      FROM public.sales_invoices i
      JOIN public.sales_invoice_items it ON it.invoice_id = i.id
      LEFT JOIN public.customers c ON c.id = i.customer_id
      JOIN public.warehouses w ON w.id = i.warehouse_id
      WHERE i.status IN ('PAID', 'PARTIAL', 'OVERDUE')
        ${s.branchSql(Prisma.sql`w.branch_id`)}
        ${s.warehouseSql(Prisma.sql`w.id`)}
        ${dates(Prisma.sql`i.invoice_date`)}
      GROUP BY
        i.id,
        i.invoice_number,
        i.invoice_date,
        c.name,
        i.subtotal,
        i.discount_amount
      HAVING
        i.discount_amount > 0
        OR coalesce(sum(
          CASE
            WHEN it.discount_percent > 0 THEN
              it.quantity * it.unit_price * it.discount_percent / 100
            ELSE 0
          END
        ), 0) > 0
      ORDER BY i.invoice_date DESC, i.invoice_number
      ${this.page(q)}
    `);
    }

    async missingSalesInvoices(userId: string, q: Filters) {
        await this.scope(userId, q);

        const bounds = await this.db.$queryRaw<
            Array<{ lo: unknown; hi: unknown }>
        >(Prisma.sql`
      SELECT
        min(n) AS lo,
        max(n) AS hi
      FROM (
        SELECT DISTINCT
          (regexp_replace(invoice_number, '[^0-9]', '', 'g'))::bigint AS n
        FROM public.sales_invoices
        WHERE regexp_replace(invoice_number, '[^0-9]', '', 'g') ~ '^[0-9]+$'
          AND length(regexp_replace(invoice_number, '[^0-9]', '', 'g')) <= 12
      ) parsed
    `);

        const lo =
            bounds[0]?.lo == null
                ? null
                : Number(bounds[0]?.lo);
        const hi =
            bounds[0]?.hi == null
                ? null
                : Number(bounds[0]?.hi);

        if (lo == null || hi == null || !Number.isFinite(lo) || !Number.isFinite(hi)) {
            return [];
        }

        const span = hi - lo;

        if (!Number.isFinite(span) || span > 20000) {
            throw new BadRequestException(
                'نطاق أرقام الفواتير واسع جداً ولا يمكن استخراج الفجوات تلقائياً',
            );
        }

        return this.db.$queryRaw(Prisma.sql`
      WITH parsed AS (
        SELECT DISTINCT
          (regexp_replace(invoice_number, '[^0-9]', '', 'g'))::bigint AS n
        FROM public.sales_invoices
        WHERE regexp_replace(invoice_number, '[^0-9]', '', 'g') ~ '^[0-9]+$'
          AND length(regexp_replace(invoice_number, '[^0-9]', '', 'g')) <= 12
      )
      SELECT s.n::text AS missing_invoice_number
      FROM generate_series(${lo}::bigint, ${hi}::bigint) AS s(n)
      LEFT JOIN parsed p ON p.n = s.n
      WHERE p.n IS NULL
      ORDER BY s.n
      ${this.page(q)}
    `);
    }

    async rawMaterialBalances(userId: string, q: Filters) {
        const s = await this.scope(userId, q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        p.name_ar AS product_name,
        coalesce(v.sku, p.sku) AS product_code,
        cat.name_ar AS category_name,
        w.name AS warehouse_name,
        sl.quantity_on_hand,
        sl.quantity_on_hand - sl.quantity_reserved
          AS quantity_available,
        sl.quantity_on_hand * v.weighted_avg_cost
          AS stock_value_iqd
      FROM public.stock_levels sl
      JOIN public.product_variants v ON v.id = sl.variant_id
      JOIN public.products p ON p.id = v.product_id
      JOIN public.categories cat ON cat.id = p.category_id
      JOIN public.warehouses w ON w.id = sl.warehouse_id
      WHERE (
        cat.name_ar ILIKE '%أولي%'
        OR cat.name_ar ILIKE '%خام%'
        OR cat.name_ar ILIKE '%raw%'
      )
        ${s.branchSql(Prisma.sql`w.branch_id`)}
        ${s.warehouseSql(Prisma.sql`w.id`)}
      ORDER BY p.name_ar, w.name
      ${this.page(q)}
    `);
    }

    async exchangeRate(userId: string, q: Filters) {
        await this.scope(userId, q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        c.name AS company_name,
        nullif(c.settings->>'usd_exchange_rate', '') AS usd_exchange_rate,
        c.updated_at
      FROM public.companies c
      ORDER BY c.updated_at DESC
      LIMIT 1
    `);
    }

    async capital(userId: string, q: Filters) {
        const s = await this.scope(userId, q);

        return this.db.$queryRaw(Prisma.sql`
      SELECT
        inv.inventory_value_iqd,
        rec.customer_debit_iqd,
        pay.supplier_credit_iqd,
        cash.cash_iqd,
        inv.inventory_value_iqd
          + rec.customer_debit_iqd
          + cash.cash_iqd
          - pay.supplier_credit_iqd AS capital_iqd
      FROM (
        SELECT coalesce(
          sum(sl.quantity_on_hand * v.weighted_avg_cost),
          0
        ) AS inventory_value_iqd
        FROM public.stock_levels sl
        JOIN public.product_variants v ON v.id = sl.variant_id
        JOIN public.warehouses w ON w.id = sl.warehouse_id
        WHERE 1 = 1
          ${s.branchSql(Prisma.sql`w.branch_id`)}
          ${s.warehouseSql(Prisma.sql`w.id`)}
      ) inv
      CROSS JOIN (
        SELECT coalesce(
          sum(balance) FILTER (WHERE balance > 0),
          0
        ) AS customer_debit_iqd
        FROM public.customers
      ) rec
      CROSS JOIN (
        SELECT coalesce(
          sum(balance) FILTER (WHERE balance > 0),
          0
        ) AS supplier_credit_iqd
        FROM public.suppliers
      ) pay
      CROSS JOIN (
        SELECT coalesce(sum(
          CASE
            WHEN latest.status = 'OPEN' THEN
              latest.opening_balance + latest.total_sales - latest.total_returns
            ELSE latest.closing_balance
          END
        ), 0) AS cash_iqd
        FROM (
          SELECT DISTINCT ON (cs.cashbox_id)
            cs.opening_balance,
            cs.closing_balance,
            cs.total_sales,
            cs.total_returns,
            cs.status
          FROM public.cashbox_sessions cs
          JOIN public.cashboxes cb ON cb.id = cs.cashbox_id
          WHERE 1 = 1
            ${s.branch
                    ? Prisma.sql`AND cb.branch_id = ${s.branch}::uuid`
                    : Prisma.empty}
          ORDER BY cs.cashbox_id, cs.opened_at DESC
        ) latest
      ) cash
    `);
    }

    async availability(userId: string) {
        await this.scope(userId, {});

        return this.db.$queryRaw(Prisma.sql`
      SELECT report_name, status, reason
      FROM reports.availability
      ORDER BY report_name
    `);
    }
}