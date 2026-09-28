import { Prisma, price_type_enum, sales_payment_enum } from '@prisma/client';
import { SalesTransactionService } from './sales-transaction.service';

describe('SalesTransactionService posting', () => {
    const warehouseId = '11111111-1111-1111-1111-111111111111';
    const customerId = '22222222-2222-2222-2222-222222222222';
    const variantId = '33333333-3333-3333-3333-333333333333';
    const unitId = '44444444-4444-4444-4444-444444444444';

    function world() {
        const customer = {
            id: customerId,
            name: 'زبون الآجل',
            balance: new Prisma.Decimal(0),
            credit_limit: new Prisma.Decimal(0),
            is_active: true,
        };
        const stock = {
            quantity_on_hand: new Prisma.Decimal(10),
            quantity_reserved: new Prisma.Decimal(0),
        };
        const invoices = new Map<string, any>();
        const items: any[] = [];
        const movements: any[] = [];

        const tx = {
            $queryRaw: async () => [{ id: 'stock-row' }],
            sales_invoices: {
                findUnique: async ({ where }: any) => {
                    if (where.idempotency_key) {
                        return invoices.get(where.idempotency_key) ?? null;
                    }
                    return null;
                },
                create: async ({ data }: any) => {
                    const invoice = {
                        id: '55555555-5555-5555-5555-555555555555',
                        ...data,
                        customers: { name: customer.name },
                    };
                    invoices.set(data.idempotency_key, invoice);
                    return invoice;
                },
            },
            warehouses: {
                findUnique: async () => ({
                    id: warehouseId,
                    name: 'الرئيسي',
                    status: 'ACTIVE',
                    branch_id: 'branch',
                }),
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
                    products: {
                        is_active: true,
                        name_ar: 'شاي',
                        base_unit_id: unitId,
                    },
                }),
            },
            units_of_measure: {
                findUnique: async () => ({
                    id: unitId,
                    conversion_factor: new Prisma.Decimal(1),
                    is_active: true,
                }),
            },
            product_allowed_units: { findUnique: async () => null },
            stock_levels: {
                findUnique: async () => stock,
                update: async ({ data }: any) => {
                    stock.quantity_on_hand = stock.quantity_on_hand.sub(
                        data.quantity_on_hand.decrement,
                    );
                    return stock;
                },
            },
            sales_invoice_items: {
                create: async ({ data }: any) => {
                    items.push(data);
                    return data;
                },
            },
            inventory_movements: {
                create: async ({ data }: any) => {
                    movements.push(data);
                    return data;
                },
            },
        };

        return { tx, customer, stock, invoices, items, movements };
    }

    const payload = {
        customer_id: customerId,
        warehouse_id: warehouseId,
        price_type: price_type_enum.RETAIL,
        payment_type: sales_payment_enum.CREDIT,
        idempotency_key: 'sale-offline-1',
        items: [
            {
                variant_id: variantId,
                unit_id: unitId,
                quantity: 2,
                unit_price: 5,
            },
        ],
    };

    it('ينشئ فاتورة آجلة ويخصم المخزون ويزيد دين الزبون داخل نفس العملية', async () => {
        const service = new SalesTransactionService();
        const state = world();

        const result = await service.createSale(state.tx as any, payload);

        expect(result.already_exists).toBe(false);
        expect(result.invoice.total.toString()).toBe('10');
        expect(result.invoice.due_amount.toString()).toBe('10');
        expect(state.stock.quantity_on_hand.toString()).toBe('8');
        expect(state.customer.balance.toString()).toBe('10');
        expect(state.items).toHaveLength(1);
        expect(state.movements).toHaveLength(1);
        expect(state.movements[0].reference_type).toBe('SALES_INVOICE');
        expect(state.movements[0].quantity.toString()).toBe('2');
    });

    it('لا يكرر الفاتورة عند إعادة نفس مفتاح المزامنة', async () => {
        const service = new SalesTransactionService();
        const state = world();

        await service.createSale(state.tx as any, payload);
        const again = await service.createSale(state.tx as any, payload);

        expect(again.already_exists).toBe(true);
        expect(state.invoices.size).toBe(1);
        expect(state.stock.quantity_on_hand.toString()).toBe('8');
        expect(state.customer.balance.toString()).toBe('10');
    });
});
