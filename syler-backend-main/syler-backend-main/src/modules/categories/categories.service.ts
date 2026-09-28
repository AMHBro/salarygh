import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateCategoryDto } from './dto/create-category.dto';
import { UpdateCategoryDto } from './dto/update-category.dto';

@Injectable()
export class CategoriesService {
    constructor(private prisma: PrismaService) { }

    async create(dto: CreateCategoryDto) {
        let level = 0;
        if (dto.parent_id) {
            const parent = await this.prisma.categories.findUnique({ where: { id: dto.parent_id } });
            if (!parent) throw new NotFoundException('التصنيف الأب غير موجود');
            level = parent.level + 1;
        }

        return this.prisma.categories.create({
            data: { ...dto, level },
        });
    }

    // استرجاع التصنيفات على شكل شجرة هرمية (Tree)
    async getTree() {
        return this.prisma.categories.findMany({
            where: { parent_id: null, is_active: true },
            include: {
                children: {
                    where: { is_active: true },
                    include: { children: true },
                },
                _count: { select: { products: true } },
            },
            orderBy: { order_index: 'asc' },
        });
    }

    async findAllFlat() {
        return this.prisma.categories.findMany({
            where: { is_active: true },
            include: { parent: { select: { id: true, name_ar: true } } },
            orderBy: { level: 'asc' },
        });
    }

    async update(id: string, dto: UpdateCategoryDto) {
        // التحقق من وجود التصنيف
        const existing = await this.prisma.categories.findUnique({ where: { id } });
        if (!existing) throw new NotFoundException('التصنيف غير موجود');

        // إذا تم تغيير الأب، نتحقق منه
        let newLevel = existing.level;
        if (dto.parent_id && dto.parent_id !== existing.parent_id) {
            const parent = await this.prisma.categories.findUnique({ where: { id: dto.parent_id } });
            if (!parent) throw new NotFoundException('التصنيف الأب الجديد غير موجود');
            // منع الدورة اللانهائية (Self-referencing loop)
            if (parent.id === id) throw new BadRequestException('لا يمكن أن يكون التصنيف أبًا لنفسه');
            newLevel = parent.level + 1;
        }

        return this.prisma.categories.update({
            where: { id },
            data: { ...dto, level: newLevel },
        });
    }

    async remove(id: string) {
        // التحقق من وجود التصنيف
        const existing = await this.prisma.categories.findUnique({ where: { id } });
        if (!existing) throw new NotFoundException('التصنيف غير موجود');

        // التحقق من وجود منتجات تابعة له
        const hasProducts = await this.prisma.products.count({ where: { category_id: id } });
        if (hasProducts > 0) {
            throw new BadRequestException('لا يمكن حذف تصنيف يحتوي على منتجات. يرجى نقل المنتجات أولاً.');
        }

        // تعطيل التصنيف بدلاً من الحذف الكامل
        return this.prisma.categories.update({
            where: { id },
            data: { is_active: false },
        });
    }

    // دالة مساعدة للعثور على تصنيف مع أجداده (Breadcrumbs)
    async getWithBreadcrumbs(id: string) {
        const category = await this.prisma.categories.findUnique({
            where: { id, is_active: true },
            include: {
                parent: { include: { parent: true } }
            }
        });

        if (!category) throw new NotFoundException('التصنيف غير موجود');

        // بناء مسار التصنيفات (Breadcrumbs)
        const breadcrumbs = [];
        let current: any = category;

        while (current) {
            breadcrumbs.unshift({
                id: current.id,
                name_ar: current.name_ar,
                level: current.level
            });
            current = current.parent;
        }

        return {
            category,
            breadcrumbs
        };
    }
}