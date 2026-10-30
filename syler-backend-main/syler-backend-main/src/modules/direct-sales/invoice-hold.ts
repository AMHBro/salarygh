import { ageDays } from '../ecommerce/services/representative-ledger';

const ignoredStatuses = new Set(['CANCELLED', 'RETURNED', 'DRAFT']);
const managerRoles = new Set(['ADMIN', 'SUPER_ADMIN', 'MANAGER']);

export const invoiceHoldPrefix = 'البيع معلق.';
export const managementReleaseMark = 'سُمح بالبيع بقرار الإدارة';

export interface HoldInvoice {
    number: string;
    invoiceDate: Date;
    remaining: number;
    status?: string | null;
}

export interface OverdueHold {
    number: string;
    ageDays: number;
}

export function invoiceBlockDays(settings: unknown): number {
    if (!settings || typeof settings !== 'object' || Array.isArray(settings)) {
        return 0;
    }
    const raw = (settings as Record<string, unknown>).invoice_block_days;
    const parsed = typeof raw === 'number'
        ? raw
        : Number(String(raw ?? '').replace(/,/g, '').trim());
    if (!Number.isFinite(parsed) || parsed <= 0) {
        return 0;
    }
    return Math.floor(parsed);
}

export function isHoldManager(role: string | null | undefined): boolean {
    return managerRoles.has((role ?? '').trim().toUpperCase());
}

/** أقدم فاتورة غير مسددة تجاوز عمرها الحد. العمر المساوي للحد ما زال مسموحاً. */
export function findOverdueHold(
    invoices: HoldInvoice[],
    blockDays: number,
    now = new Date(),
): OverdueHold | null {
    if (blockDays <= 0) {
        return null;
    }
    let oldest: OverdueHold | null = null;
    for (const invoice of invoices) {
        if (!(invoice.remaining > 0)) {
            continue;
        }
        const status = (invoice.status ?? '').trim().toUpperCase();
        if (ignoredStatuses.has(status)) {
            continue;
        }
        const days = ageDays(invoice.invoiceDate, now);
        if (days <= blockDays) {
            continue;
        }
        if (!oldest || days > oldest.ageDays) {
            oldest = { number: invoice.number, ageDays: days };
        }
    }
    return oldest;
}

export function invoiceHoldMessage(hold: OverdueHold): string {
    return `${invoiceHoldPrefix} فاتورة ${hold.number} غير مسددة وعمرها ${hold.ageDays} يوم. لا يُستأنف البيع إلا بقرار الإدارة.`;
}

export function withManagementRelease(notes: string | null | undefined, hold: OverdueHold): string {
    const line = `${managementReleaseMark} رغم فاتورة ${hold.number} غير مسددة عمرها ${hold.ageDays} يوم.`;
    const current = (notes ?? '').trim();
    if (current.includes(managementReleaseMark)) {
        return current;
    }
    if (!current) {
        return line;
    }
    return `${current}\n${line}`;
}
