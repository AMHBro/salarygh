import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { pageWindow } from '../../common/paging';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateSupplierPaymentDto } from './dto/create-supplier-payment.dto';
import { payment_method_enum, Prisma, purchase_status_enum, voucher_type_enum } from '@prisma/client';
import { randomBytes } from 'crypto';

@Injectable()
export class SupplierPaymentsService {
    constructor(private prisma: PrismaService) { }

    // ─── تسجيل سند دفع للمورد وخفض رصيد الذمة ─────────────────────────────────
    async createPayment(dto: CreateSupplierPaymentDto, userId?: string) {
        if (!Number.isFinite(dto.amount) || dto.amount <= 0 || !new Prisma.Decimal(dto.amount).mul(100).isInteger()) {
            throw new BadRequestException('المبلغ غير صالح أو يحتوي أكثر من منزلتين عشريتين');
        }
        if (!dto.invoice_id) throw new BadRequestException('يجب تحديد فاتورة الشراء');
        if (dto.payment_method === payment_method_enum.CASH && !dto.cashbox_id) {
            throw new BadRequestException('يجب تحديد الصندوق للسداد النقدي');
        }
        const amount = new Prisma.Decimal(dto.amount);

        return this.prisma.$transaction(async (tx) => {
            const existing = await tx.payment_vouchers.findUnique({ where: { idempotency_key: dto.idempotency_key } });
            if (existing) {
                if (existing.voucher_type !== voucher_type_enum.PAYMENT ||
                    existing.supplier_id !== dto.supplier_id || existing.invoice_id !== dto.invoice_id ||
                    existing.cashbox_id !== (dto.cashbox_id ?? null) ||
                    existing.payment_method !== dto.payment_method || !existing.amount.equals(amount)) {
                    throw new BadRequestException('مفتاح العملية مستخدم لسند مختلف');
                }
                return existing;
            }
            const invoice = await tx.purchase_invoices.findUnique({
                where: { id: dto.invoice_id }, include: { warehouse: { select: { branch_id: true } } },
            });
            if (!invoice || invoice.supplier_id !== dto.supplier_id) {
                throw new BadRequestException('الفاتورة لا تتبع المورد المحدد');
            }
            if (invoice.status === purchase_status_enum.DRAFT || invoice.status === purchase_status_enum.CANCELLED) {
                throw new BadRequestException('لا يمكن تسديد فاتورة مسودة أو ملغاة');
            }
            if (!userId) throw new BadRequestException('المستخدم غير معروف');
            const user = await tx.users.findUnique({ where: { id: userId }, include: { roles: true } });
            if (!user?.is_active || (!['ADMIN', 'SUPER_ADMIN'].includes(user.roles?.name ?? '') &&
                user.branch_id !== invoice.warehouse.branch_id)) {
                throw new BadRequestException('فاتورة الشراء خارج نطاق فرعك');
            }
            if (dto.cashbox_id) {
                const cashbox = await tx.cashboxes.findUnique({ where: { id: dto.cashbox_id } });
                if (!cashbox) throw new NotFoundException('الصندوق غير موجود');
                if (cashbox.branch_id !== invoice.warehouse.branch_id) {
                    throw new BadRequestException('الصندوق وفاتورة الشراء يتبعان فرعين مختلفين');
                }
                if (!['ADMIN', 'SUPER_ADMIN'].includes(user.roles?.name ?? '') && user.branch_id !== cashbox.branch_id) {
                    throw new BadRequestException('الصندوق خارج نطاق فرعك');
                }
            }
            const invoiceUpdate = await tx.purchase_invoices.updateMany({
                where: { id: dto.invoice_id, due_amount: { gte: amount } },
                data: { paid_amount: { increment: amount }, updated_at: new Date() },
            });
            if (!invoiceUpdate.count) throw new BadRequestException('المبلغ يتجاوز المتبقي على الفاتورة');
            await tx.purchase_invoices.updateMany({
                where: { id: dto.invoice_id, due_amount: { lte: 0 } },
                data: { status: purchase_status_enum.PAID },
            });
            const supplierUpdate = await tx.suppliers.updateMany({
                where: { id: dto.supplier_id, balance: { gte: amount } },
                data: { balance: { decrement: amount }, updated_at: new Date() },
            });
            if (!supplierUpdate.count) throw new BadRequestException('المبلغ يتجاوز رصيد المورد');
            return tx.payment_vouchers.create({
                data: {
                    voucher_number: `PAY-${randomBytes(8).toString('hex').toUpperCase()}`,
                    voucher_type: voucher_type_enum.PAYMENT,
                    supplier_id: dto.supplier_id,
                    invoice_id: dto.invoice_id,
                    cashbox_id: dto.cashbox_id ?? null,
                    amount,
                    idempotency_key: dto.idempotency_key,
                    payment_method: dto.payment_method,
                    notes: dto.notes,
                    created_by: userId,
                },
            });
        });
    }

    async findAll(query: { supplier_id?: string; page?: number; limit?: number }) {
        const { page, limit, skip } = pageWindow(query);

        const where: any = { voucher_type: voucher_type_enum.PAYMENT, supplier_id: { not: null } };
        if (query.supplier_id) where.supplier_id = query.supplier_id;

        const [total, data] = await Promise.all([
            this.prisma.payment_vouchers.count({ where }),
            this.prisma.payment_vouchers.findMany({
                where,
                skip,
                take: limit,
                include: {
                    supplier: { select: { id: true, name: true } },
                    invoice: { select: { id: true, invoice_number: true } },
                },
                orderBy: { created_at: 'desc' },
            }),
        ]);

        return {
            data,
            meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
        };
    }
}
