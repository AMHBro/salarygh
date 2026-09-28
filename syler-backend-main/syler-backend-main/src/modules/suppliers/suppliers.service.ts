import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { pageWindow } from '../../common/paging';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateSupplierDto } from './dto/create-supplier.dto';
import { UpdateSupplierDto } from './dto/update-supplier.dto';

@Injectable()
export class SuppliersService {
    constructor(private readonly prisma: PrismaService) { }

    async create(dto: CreateSupplierDto, userId?: string) {
        return this.prisma.suppliers.create({
            data: {
                ...dto,
                credit_limit: dto.credit_limit || 0,
                balance: 0,
                created_by: userId,
            },
        });
    }
    async findAll(query: { search?: string; page?: number; limit?: number }) {
        const { page, limit, skip } = pageWindow(query);

        const where: any = { is_active: true };
        if (query.search) {
            where.OR = [
                { name: { contains: query.search, mode: 'insensitive' } },
                { phone: { contains: query.search, mode: 'insensitive' } },
            ];
        }

        const [total, data] = await Promise.all([
            this.prisma.suppliers.count({ where }),
            this.prisma.suppliers.findMany({
                where,
                skip,
                take: limit,
                orderBy: { name: 'asc' },
                include: {
                    _count: { select: { purchase_invoices: true } },
                },
            }),
        ]);

        return {
            data,
            meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
        };
    }
    async findOne(id: string) {
        const supplier = await this.prisma.suppliers.findUnique({
            where: { id },
            include: {
                purchase_invoices: {
                    take: 10,
                    orderBy: { created_at: 'desc' },
                },
            },
        });
        if (!supplier) throw new NotFoundException('المورد غير موجود');
        return supplier;
    }
    async getStatement(id: string) {
        const supplier = await this.findOne(id);

        const [invoices, payments] = await Promise.all([
            this.prisma.purchase_invoices.findMany({
                where: { supplier_id: id },
                select: {
                    id: true,
                    invoice_number: true,
                    invoice_date: true,
                    total: true,
                    paid_amount: true,
                    due_amount: true,
                    payment_type: true,
                    created_at: true,
                },
                orderBy: { created_at: 'desc' },
            }),
            this.prisma.payment_vouchers.findMany({
                where: { supplier_id: id },
                select: {
                    id: true,
                    voucher_number: true,
                    voucher_date: true,
                    amount: true,
                    payment_method: true,
                    notes: true,
                    created_at: true,
                },
                orderBy: { created_at: 'desc' },
            }),
        ]);

        return {
            supplier: {
                id: supplier.id,
                name: supplier.name,
                phone: supplier.phone,
                current_balance: supplier.balance,
                credit_limit: supplier.credit_limit,
            },
            invoices,
            payments,
        };
    }
    async update(id: string, dto: UpdateSupplierDto) {
        await this.findOne(id);
        return this.prisma.suppliers.update({
            where: { id },
            data: { ...dto, updated_at: new Date() },
        });
    }
    async remove(id: string) {
        const supplier = await this.findOne(id);
        if (Number(supplier.balance) > 0) {
            throw new BadRequestException(`لا يمكن حذف مورد يمتلك رصيد ذمة مستحق (${supplier.balance} د.ع)`);
        }
        return this.prisma.suppliers.update({
            where: { id },
            data: { is_active: false },
        });
    }

}