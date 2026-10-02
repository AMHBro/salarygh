import { buildAgingLedger, UnpaidInvoice } from '../ecommerce/services/representative-ledger';
import { SalesTransactionService } from './sales-transaction.service';
import { Prisma, price_type_enum, sales_payment_enum } from '@prisma/client';

describe('مسار البيع من الطلب حتى الذمة', () => {
    const warehouseId = '11111111-1111-1111-1111-111111111111';
    const customerId = '22222222-2222-2222-2222-222222222222';
    const variantId = '33333333-3333-3333-3333-333333333333';
    const unitId = '44444444-4444-4444-4444-444444444444';

    function world() {
        const customer = {
            id: customerId,
            name: 'مكتب النور',
            balance: new Prisma.Decimal(0),
            credit_limit: new Prisma.Decimal(0),
            is_active: true,
        };
        const stock = {
            quantity_on_hand: new Prisma.Decimal(10),
            quantity_reserved: new Prisma.Decimal(0),
        };
        const invoices = new Map<string, any>();
        const tx = {
            $queryRaw: async () => [{ id: 'stock-row' }],
            sales_invoices: {
                findUnique: async ({ where }: any) => invoices.get(where.idempotency_key) ?? null,
                create: async ({ data }: any) => {
                    const invoice = { id: '55555555-5555-5555-5555-555555555555', ...data, customers: { name: customer.name } };
                    invoices.set(data.idempotency_key, invoice);
                    return invoice;
                },
            },
            warehouses: {
                findUnique: async () => ({ id: warehouseId, name: 'الرئيسي', status: 'ACTIVE', branch_id: 'branch' }),
            },
            customers: {
                findUnique: async () => customer,
                update: async ({ data }: any) => {
                    customer.balance = customer.balance.add(data.balance.increment);
                    return customer;
                },
            },
            representatives: { findUnique: async () => null },
            product_variants: {
                findUnique: async () => ({
                    id: variantId,
                    product_id: 'product',
                    is_active: true,
                    weighted_avg_cost: new Prisma.Decimal(2),
                    products: { is_active: true, name_ar: 'شاي', base_unit_id: unitId },
                }),
            },
            units_of_measure: {
                findUnique: async () => ({ id: unitId, conversion_factor: new Prisma.Decimal(1), is_active: true }),
            },
            product_allowed_units: { findUnique: async () => null },
            stock_levels: {
                findUnique: async () => stock,
                update: async ({ data }: any) => {
                    stock.quantity_on_hand = stock.quantity_on_hand.sub(data.quantity_on_hand.decrement);
                    return stock;
                },
            },
            sales_invoice_items: { create: async ({ data }: any) => data },
            inventory_movements: { create: async ({ data }: any) => data },
        };
        return { tx, customer, stock, invoices };
    }

    it('طلب المتجر ينشئ فاتورة ويخصم المخزون ويظهر في أعمار الذمم', async () => {
        const service = new SalesTransactionService();
        const state = world();
        const orderedAt = new Date('2026-08-01T00:00:00.000Z');
        const result = await service.createSale(state.tx as any, {
            customer_id: customerId,
            warehouse_id: warehouseId,
            price_type: price_type_enum.RETAIL,
            payment_type: sales_payment_enum.CREDIT,
            idempotency_key: 'store-order-1',
            items: [{ variant_id: variantId, unit_id: unitId, quantity: 2, unit_price: 5 }],
        });

        const unpaid: UnpaidInvoice[] = [...state.invoices.values()].map((invoice) => ({
            id: invoice.id,
            number: invoice.invoice_number,
            invoiceDate: orderedAt,
            amount: Number(invoice.total),
            remaining: Number(invoice.due_amount),
        }));
        const ledger = buildAgingLedger(unpaid, new Date('2026-10-02T00:00:00.000Z'));

        expect(result.already_exists).toBe(false);
        expect(state.stock.quantity_on_hand.toString()).toBe('8');
        expect(state.customer.balance.toString()).toBe('10');
        expect(ledger.invoices).toHaveLength(1);
        expect(ledger.invoices[0].age_days).toBe(62);
        expect(ledger.aging.days_61_90).toBe(10);
        expect(ledger.aging.total).toBe(10);
    });
});
