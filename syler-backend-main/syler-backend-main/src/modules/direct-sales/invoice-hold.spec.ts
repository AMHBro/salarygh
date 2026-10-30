import { findOverdueHold, invoiceBlockDays, invoiceHoldMessage, isHoldManager } from './invoice-hold';

describe('تعليق البيع بسبب عمر الفاتورة', () => {
    const now = new Date('2026-10-20T00:00:00.000Z');

    it('يعتبر الإعداد الفارغ أو الصفري موقفاً للتعليق', () => {
        expect(invoiceBlockDays(null)).toBe(0);
        expect(invoiceBlockDays({})).toBe(0);
        expect(invoiceBlockDays({ invoice_block_days: 0 })).toBe(0);
        expect(invoiceBlockDays({ invoice_block_days: '30' })).toBe(30);
    });

    it('يعلق أقدم فاتورة تجاوزت العمر ويتجاوز الفاتورة المسددة والملغاة', () => {
        const hold = findOverdueHold([
            {
                number: 'S-PAID',
                invoiceDate: new Date('2026-01-01T00:00:00.000Z'),
                remaining: 0,
                status: 'PAID',
            },
            {
                number: 'S-CANCEL',
                invoiceDate: new Date('2026-01-01T00:00:00.000Z'),
                remaining: 40,
                status: 'CANCELLED',
            },
            {
                number: 'S-OLD',
                invoiceDate: new Date('2026-08-01T00:00:00.000Z'),
                remaining: 10,
                status: 'PARTIAL',
            },
            {
                number: 'S-NEW',
                invoiceDate: new Date('2026-10-01T00:00:00.000Z'),
                remaining: 5,
                status: 'PARTIAL',
            },
        ], 30, now);

        expect(hold).toEqual({ number: 'S-OLD', ageDays: 80 });
        expect(invoiceHoldMessage(hold!)).toContain('فاتورة S-OLD');
    });

    it('لا يعلق فاتورة عمرها ضمن الحد', () => {
        const hold = findOverdueHold([
            {
                number: 'S-30',
                invoiceDate: new Date('2026-09-20T00:00:00.000Z'),
                remaining: 8,
                status: 'PARTIAL',
            },
        ], 30, now);

        expect(hold).toBeNull();
    });

    it('يقصر قرار السماح على الإدارة', () => {
        expect(isHoldManager('MANAGER')).toBe(true);
        expect(isHoldManager('admin')).toBe(true);
        expect(isHoldManager('CASHIER')).toBe(false);
        expect(isHoldManager('REP')).toBe(false);
    });
});
