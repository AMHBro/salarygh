import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateUnitDto } from './dto/create-unit.dto';
import { UpdateUnitDto } from './dto/update-unit.dto';

@Injectable()
export class UnitsService {
    constructor(private prisma: PrismaService) { }

    async create(dto: CreateUnitDto) {
        if (dto.parent_unit_id) {
            const parent = await this.prisma.units_of_measure.findUnique({
                where: { id: dto.parent_unit_id }
            });
            if (!parent) throw new NotFoundException('الوحدة الاساسية الاب غير موجود');
        }

        return this.prisma.units_of_measure.create({ data: dto });
    }

    async findAll() {
        return this.prisma.units_of_measure.findMany({
            where: { is_active: true },
            include: {
                parent_unit: { select: { id: true, name_ar: true, symbol: true } },
            },
            orderBy: { name_ar: 'asc' },
        });
    }

    async findOne(id: string) {
        const unit = await this.prisma.units_of_measure.findUnique({
            where: { id },
            include: {
                parent_unit: true,
                sub_units: { where: { is_active: true } },
            },
        });
        if (!unit) throw new NotFoundException('وحدة القياس غير موجودة');
        return unit;
    }

    async update(id: string, dto: UpdateUnitDto) {
        await this.findOne(id);
        // منع ربط الوحدة بنفسها كأب
        if (dto.parent_unit_id && dto.parent_unit_id === id) {
            throw new BadRequestException('لا يمكن ربط الوحدة بنفسها كوحدة أب');
        }
        return this.prisma.units_of_measure.update({
            where: { id },
            data: dto,
        });
    }

    async remove(id: string) {
        await this.findOne(id);
        // التحقق من عدم وجود منتجات تستخدم هذه الوحدة
        const productsCount = await this.prisma.products.count({
            where: { base_unit_id: id },
        });
        if (productsCount > 0) {
            throw new BadRequestException(`لا يمكن حذف الوحدة لأنها مستخدمة كوحدة أساسية في ${productsCount} منتج`);
        }
        return this.prisma.units_of_measure.update({
            where: { id },
            data: { is_active: false },
        });
    }
}