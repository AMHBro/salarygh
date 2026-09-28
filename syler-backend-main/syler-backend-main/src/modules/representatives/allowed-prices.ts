import { BadRequestException } from '@nestjs/common';
import { price_type_enum } from '@prisma/client';

const priceOrder = [
    'wholesale',
    'representative',
    'retail',
    'cost',
] as const;

const priceTypeByKey: Record<string, price_type_enum> = {
    wholesale: price_type_enum.WHOLESALE,
    representative: price_type_enum.REP,
    retail: price_type_enum.RETAIL,
    cost: price_type_enum.COST,
};

type SqlClient = {
    $queryRawUnsafe: <T = unknown>(
        query: string,
        ...values: unknown[]
    ) => Promise<T>;
    $executeRawUnsafe: (
        query: string,
        ...values: unknown[]
    ) => Promise<number>;
};

export function normalizeAllowedPrices(raw?: string | null): string {
    const selected = new Set(
        `${raw ?? ''}`
            .split(',')
            .map((part) => part.trim().toLowerCase())
            .filter((part) =>
                priceOrder.includes(part as (typeof priceOrder)[number]),
            ),
    );
    const ordered = priceOrder.filter((key) => selected.has(key));
    if (ordered.length === 0) {
        throw new BadRequestException('حدد سعراً واحداً على الأقل للمندوب');
    }
    return ordered.join(',');
}

export function allowedPriceKeys(raw?: string | null): string[] {
    const source = raw && raw.trim()
        ? raw
        : 'wholesale,representative,retail';
    try {
        return normalizeAllowedPrices(source).split(',');
    } catch {
        return ['wholesale', 'representative', 'retail'];
    }
}

export function chooseInvoicePriceType(
    allowedRaw: string | null | undefined,
    requested?: price_type_enum | null,
): price_type_enum {
    const allowed = allowedPriceKeys(allowedRaw).map(
        (key) => priceTypeByKey[key],
    );
    if (requested) {
        if (!allowed.includes(requested)) {
            throw new BadRequestException(
                'هذا السعر غير مسموح لهذا المندوب',
            );
        }
        return requested;
    }
    if (allowed.length > 1) {
        throw new BadRequestException('حدد نوع سعر القائمة');
    }
    return allowed[0];
}

export async function readAllowedPrices(
    db: SqlClient,
    representativeId: string,
): Promise<string> {
    try {
        const rows = await db.$queryRawUnsafe<
            Array<{ allowed_prices: string | null }>
        >(
            'SELECT allowed_prices FROM representatives WHERE id = $1::uuid',
            representativeId,
        );
        return rows[0]?.allowed_prices || 'wholesale,representative,retail';
    } catch {
        return 'wholesale,representative,retail';
    }
}

export async function writeAllowedPrices(
    db: SqlClient,
    representativeId: string,
    raw?: string | null,
): Promise<string> {
    const value = normalizeAllowedPrices(
        raw ?? 'wholesale,representative,retail',
    );
    await db.$executeRawUnsafe(
        'UPDATE representatives SET allowed_prices = $1 WHERE id = $2::uuid',
        value,
        representativeId,
    );
    return value;
}
