export interface UnpaidInvoice {
    id: string;
    number: string;
    invoiceDate: Date;
    amount: number;
    remaining: number;
}

export interface AgingBucketTotals {
    current: number;
    days_31_60: number;
    days_61_90: number;
    over_90: number;
    total: number;
}

export interface AgingLedgerLine {
    id: string;
    number: string;
    date: string;
    amount: number;
    remaining: number;
    age_days: number;
    bucket: 'current' | 'days_31_60' | 'days_61_90' | 'over_90';
}

export function ageDays(invoiceDate: Date, now: Date): number {
    const start = Date.UTC(
        invoiceDate.getUTCFullYear(),
        invoiceDate.getUTCMonth(),
        invoiceDate.getUTCDate(),
    );
    const end = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
    return Math.max(0, Math.round((end - start) / 86_400_000));
}

export function agingBucket(days: number): AgingLedgerLine['bucket'] {
    if (days <= 30) return 'current';
    if (days <= 60) return 'days_31_60';
    if (days <= 90) return 'days_61_90';
    return 'over_90';
}

export function buildAgingLedger(invoices: UnpaidInvoice[], now = new Date()) {
    const aging: AgingBucketTotals = {
        current: 0,
        days_31_60: 0,
        days_61_90: 0,
        over_90: 0,
        total: 0,
    };
    const lines: AgingLedgerLine[] = invoices
        .filter((invoice) => invoice.remaining > 0)
        .map((invoice) => {
            const days = ageDays(invoice.invoiceDate, now);
            const bucket = agingBucket(days);
            aging[bucket] += invoice.remaining;
            aging.total += invoice.remaining;
            return {
                id: invoice.id,
                number: invoice.number,
                date: invoice.invoiceDate.toISOString(),
                amount: invoice.amount,
                remaining: invoice.remaining,
                age_days: days,
                bucket,
            };
        });
    return { invoices: lines, aging };
}
