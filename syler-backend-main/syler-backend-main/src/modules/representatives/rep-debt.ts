import { BadRequestException, UnprocessableEntityException } from '@nestjs/common';
import { Prisma, sales_payment_enum } from '@prisma/client';

type DebtReader = {
    $queryRaw<T = unknown>(
        query: TemplateStringsArray | Prisma.Sql,
        ...values: unknown[]
    ): Prisma.PrismaPromise<T>;
};

export function formatRepDebtAmount(value: Prisma.Decimal): string {
    const rounded = value.toDecimalPlaces(0, Prisma.Decimal.ROUND_HALF_UP);
    return rounded.toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

export function repDebtCeilingMessage(
    name: string,
    total: Prisma.Decimal,
    limit: Prisma.Decimal,
): string {
    return `تنبيه: مجموع ديون زبائن المندوب ${name} بلغت (${formatRepDebtAmount(total)}) وتجاوزت السقف المسموح (${formatRepDebtAmount(limit)})`;
}

/**
 * مصدر الرفض الحي: customers.balance على السحابة بعد المزامنة وقبول الفاتورة.
 * الرصيد السالب لا يُحتسب. دفتر الحاسبة يُستخدم فقط عندما يتعذر قراءة السحابة.
 */
export async function listRepDebtSnapshots(
    db: DebtReader,
): Promise<Array<{ id: string; name: string; max_debt_limit: unknown; customer_debt_total: unknown }>> {
    return db.$queryRaw(Prisma.sql`
        SELECT r.id::text AS id,
               r.name,
               r.max_debt_limit::text AS max_debt_limit,
               COALESCE((
                   SELECT SUM(c.balance)
                   FROM customers c
                   WHERE c.assigned_rep_id = r.id
                     AND c.balance > 0
               ), 0)::text AS customer_debt_total
        FROM representatives r
    `);
}

/** مجموع أرصدة الزبائن المدينة المربوطين بالمندوب. الرصيد السالب لا يُحتسب ديناً. */
export async function calculateRepTotalDebt(
    db: DebtReader,
    repId: string,
): Promise<Prisma.Decimal> {
    const rows = await db.$queryRaw<Array<{ total: unknown }>>(Prisma.sql`
        SELECT COALESCE(SUM(balance), 0) AS total
        FROM customers
        WHERE assigned_rep_id = ${repId}::uuid
          AND balance > 0
    `);
    return new Prisma.Decimal(String(rows[0]?.total ?? 0));
}

/**
 * 0 يلغي السقف. otherwise يرفض إذا كان الدين الحالي، أو الدين بعد مبلغ الطلب الآجل، فوق السقف.
 * الطلب النقدي لا يضيف ديناً، ويُرفض فقط إذا كان السقف متجاوزاً أصلاً.
 */
export async function assertRepDebtCeiling(
    db: DebtReader,
    representative: {
        id: string;
        name: string;
        max_debt_limit: unknown;
    },
    addedDebt: Prisma.Decimal,
): Promise<void> {
    const limit = new Prisma.Decimal(String(representative.max_debt_limit ?? 0));
    if (limit.lte(0)) return;

    const current = await calculateRepTotalDebt(db, representative.id);
    const projected = current.add(addedDebt.gt(0) ? addedDebt : 0);
    if (projected.gt(limit)) {
        throw new UnprocessableEntityException(
            repDebtCeilingMessage(representative.name, projected, limit),
        );
    }
}

/** النقد يضيف صفراً، والآجل يضيف الإجمالي، والجزئي يضيف الإجمالي ناقص المدفوع. */
export function resolveCheckoutDebt(
    payment: sales_payment_enum,
    total: Prisma.Decimal,
    paidRaw?: number,
): { paid: Prisma.Decimal; addedDebt: Prisma.Decimal } {
    if (payment === sales_payment_enum.CASH) {
        if (paidRaw != null && !new Prisma.Decimal(paidRaw).eq(total)) {
            throw new BadRequestException('البيع النقدي يجب أن يكون مسدداً بالكامل');
        }
        return { paid: total, addedDebt: new Prisma.Decimal(0) };
    }

    if (payment === sales_payment_enum.CREDIT) {
        if (paidRaw != null && new Prisma.Decimal(paidRaw).gt(0)) {
            throw new BadRequestException('البيع الآجل يجب أن يكون المبلغ المدفوع فيه صفراً');
        }
        return { paid: new Prisma.Decimal(0), addedDebt: total };
    }

    if (payment !== sales_payment_enum.PARTIAL) {
        throw new BadRequestException('طريقة الدفع غير مدعومة');
    }

    if (paidRaw == null || Number.isNaN(Number(paidRaw))) {
        throw new BadRequestException('المبلغ المدفوع مطلوب عند الدفع الجزئي');
    }

    const paid = new Prisma.Decimal(paidRaw);
    if (paid.lte(0) || paid.gte(total)) {
        throw new BadRequestException(
            'في البيع الجزئي يجب أن يكون المبلغ المدفوع أكبر من صفر وأقل من الإجمالي',
        );
    }

    return { paid, addedDebt: total.sub(paid) };
}
