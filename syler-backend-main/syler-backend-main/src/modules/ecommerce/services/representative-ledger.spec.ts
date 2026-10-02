import { buildAgingLedger } from './representative-ledger';

describe('أعمار الذمم من الفواتير غير المسددة', () => {
    const now = new Date('2026-10-02T00:00:00.000Z');

    it('يفصل الفواتير حسب عمرها ولا يجمعها في سطر واحد', () => {
        const ledger = buildAgingLedger(
            [
                {
                    id: 'a',
                    number: 'INV-1',
                    invoiceDate: new Date('2026-09-20T00:00:00.000Z'),
                    amount: 100,
                    remaining: 40,
                },
                {
                    id: 'b',
                    number: 'INV-2',
                    invoiceDate: new Date('2026-06-01T00:00:00.000Z'),
                    amount: 80,
                    remaining: 80,
                },
                {
                    id: 'c',
                    number: 'INV-3',
                    invoiceDate: new Date('2026-10-01T00:00:00.000Z'),
                    amount: 15,
                    remaining: 0,
                },
            ],
            now,
        );

        expect(ledger.invoices.map((item) => item.number)).toEqual(['INV-1', 'INV-2']);
        expect(ledger.invoices[0].bucket).toBe('current');
        expect(ledger.invoices[1].bucket).toBe('over_90');
        expect(ledger.aging.current).toBe(40);
        expect(ledger.aging.over_90).toBe(80);
        expect(ledger.aging.total).toBe(120);
    });
});
