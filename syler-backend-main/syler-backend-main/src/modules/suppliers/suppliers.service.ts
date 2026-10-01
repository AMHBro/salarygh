import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { pageWindow } from '../../common/paging';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateSupplierDto } from './dto/create-supplier.dto';
import { CreateSupplierSheetDto } from './dto/create-supplier-sheet.dto';
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
    async addSheet(id: string, dto: CreateSupplierSheetDto) {
        await this.findOne(id);
        const title = dto.title.trim();
        const image = dto.image_url.trim();
        if (!title) {
            throw new BadRequestException('اسم الصورة مطلوب');
        }
        if (!image.startsWith('data:image/')) {
            throw new BadRequestException('الصورة غير صالحة');
        }
        return this.prisma.supplier_sheets.create({
            data: {
                supplier_id: id,
                title,
                image_url: image,
            },
            include: { supplier: { select: { id: true, name: true } } },
        });
    }

    async listSheets(pageRaw?: string) {
        const page = Math.max(1, Number(pageRaw) || 1);
        const limit = 8;
        const skip = (page - 1) * limit;
        const [total, rows] = await Promise.all([
            this.prisma.supplier_sheets.count(),
            this.prisma.supplier_sheets.findMany({
                orderBy: { created_at: 'desc' },
                skip,
                take: limit,
                include: { supplier: { select: { name: true } } },
            }),
        ]);
        return {
            data: rows.map((row) => ({
                id: row.id,
                title: row.title,
                image_url: row.image_url,
                created_at: row.created_at,
                supplier_name: row.supplier.name,
            })),
            meta: {
                total,
                page,
                limit,
                totalPages: Math.max(1, Math.ceil(total / limit)),
            },
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