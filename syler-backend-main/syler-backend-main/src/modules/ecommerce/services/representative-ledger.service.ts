import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, sales_status_enum } from '@prisma/client';
import { PrismaService } from 'src/prisma/prisma.service';
import { buildAgingLedger, UnpaidInvoice } from './representative-ledger';

@Injectable()
export class RepresentativeLedgerService {
    constructor(private readonly prisma: PrismaService) {}

    async getLedger(userId: string, partyId: string) {
        const representative = await this.prisma.representatives.findUnique({
            where: { user_id: userId },
            select: { id: true },
        });
        if (!representative) {
            throw new NotFoundException({
                code: 'REPRESENTATIVE_NOT_FOUND',
                message: 'المستخدم الحالي غير مرتبط بمندوب',
            });
        }

        const customer = await this.prisma.customers.findUnique({
            where: { id: partyId },
            select: { id: true, name: true, assigned_rep_id: true },
        });
        if (!customer) {
            throw new NotFoundException({
                code: 'ACCOUNT_NOT_FOUND',
                message: 'الحساب غير موجود',
            });
        }

        if (customer.assigned_rep_id !== representative.id) {
            const order = await this.prisma.ecommerce_orders.findFirst({
                where: { rep_id: representative.id, party_id: partyId },
                select: { id: true },
            });
            if (!order) {
                throw new NotFoundException({
                    code: 'ACCOUNT_NOT_FOUND',
                    message: 'الحساب غير مرتبط بهذا المندوب',
                });
            }
        }

        const rows = await this.prisma.sales_invoices.findMany({
            where: {
                customer_id: partyId,
                due_amount: { gt: 0 },
                status: {
                    notIn: [sales_status_enum.CANCELLED, sales_status_enum.RETURNED],
                },
            },
            orderBy: { invoice_date: 'asc' },
            select: {
                id: true,
                invoice_number: true,
                invoice_date: true,
                total: true,
                due_amount: true,
            },
        });

        const invoices: UnpaidInvoice[] = rows.map((row) => ({
            id: row.id,
            number: row.invoice_number,
            invoiceDate: row.invoice_date,
            amount: decimalToNumber(row.total),
            remaining: decimalToNumber(row.due_amount),
        }));
        const ledger = buildAgingLedger(invoices);
        return {
            party_id: customer.id,
            party_name: customer.name,
            ...ledger,
        };
    }
}

function decimalToNumber(value: Prisma.Decimal | number | string): number {
    if (typeof value === 'number') return value;
    return Number(value.toString());
}
