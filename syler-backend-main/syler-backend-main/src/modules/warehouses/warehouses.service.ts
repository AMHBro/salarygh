import {
    Injectable,
    NotFoundException,
    BadRequestException,
    ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateWarehouseDto } from './dto/create-warehouse.dto';
import { UpdateWarehouseDto } from './dto/update-warehouse.dto';
import { RejectRequestDto } from '../branches/dto/reject-request.dto';
import { AssignKeepersDto } from './dto/assign-keepers.dto';
import { org_status_enum, warehouse_type_enum } from '@prisma/client';
import { pageWindow } from '../../common/paging';


@Injectable()
export class WarehousesService {
    constructor(private prisma: PrismaService) { }

    private async generateWarehouseCode(): Promise<string> {
        const count = await this.prisma.warehouses.count();
        return `WH-${String(count + 1).padStart(3, '0')}`;
    }
    async create(dto: CreateWarehouseDto, userId: string) {
        const branch = await this.prisma.branches.findUnique({ where: { id: dto.branch_id } })
        if (!branch) throw new NotFoundException('الفرع غير موجود');
        if (dto.type === warehouse_type_enum.SUB) {
            if (!dto.parent_warehouse_id) {
                throw new BadRequestException('يجب تحديد المخزن الرئيسي الأب للمخزن الفرعي');
            }
            const parent = await this.prisma.warehouses.findUnique({
                where: { id: dto.parent_warehouse_id },
            });
            if (!parent || parent.branch_id !== dto.branch_id || parent.type !== warehouse_type_enum.MAIN) {
                throw new BadRequestException('المخزن الأب يجب أن يكون مخزناً رئيسياً نشطاً ينتمي لنفس الفرع');
            }
        }

        const code = dto.code || (await this.generateWarehouseCode());
        return this.prisma.warehouses.create({
            data: {
                ...dto,
                code,
                status: org_status_enum.DRAFT,
                created_by: userId,
            },
            include: { branch: true, parent_warehouse: true },
        });

    }

    async findAll(query: any) {
        const { branch_id, _type, status, search } = query;
        const { page, limit, skip } = pageWindow(query);

        const where: any = {}

        if (branch_id) where.branch_id = branch_id;
        if (_type) where.type = _type;
        if (status) where.status = status;
        if (search) {
            where.OR = [
                { name: { contains: search, mode: 'insensitive' } },
                { code: { contains: search, mode: 'insensitive' } }
            ]
        }

        const [total, data] = await Promise.all([
            this.prisma.warehouses.count({ where }),
            this.prisma.warehouses.findMany({
                where,
                skip: Number(skip),
                take: Number(limit),
                include: {
                    branch: { select: { id: true, name: true, code: true } },
                    parent_warehouse: { select: { id: true, name: true, code: true } },
                    manager: { select: { id: true, username: true } },
                    _count: { select: { sub_warehouses: true, keepers: true } },
                },
                orderBy: { created_at: 'desc' }
            })
        ]);

        return { data, meta: { total, page: Number(page), limit: Number(limit) } }

    }

    async findOne(id: string) {
        const warehouse = await this.prisma.warehouses.findUnique({
            where: { id },
            include: {
                branch: true,
                parent_warehouse: true,
                sub_warehouses: true,
                manager: true,
                keepers: { include: { user: { select: { id: true, username: true, email: true } } } },
            },
        });
        if (!warehouse) throw new NotFoundException('المخزن غير موجود');
        return warehouse;
    }

    async updateDetails(id: string, dto: UpdateWarehouseDto) {
        await this.findOne(id);
        const name = dto.name?.trim();
        const code = dto.code?.trim();
        return this.prisma.warehouses.update({
            where: { id },
            data: {
                ...(name ? { name } : {}),
                ...(code ? { code } : {}),
                ...(dto.address !== undefined ? { address: dto.address } : {}),
                ...(dto.notes !== undefined ? { notes: dto.notes } : {}),
                ...(dto.capacity !== undefined ? { capacity: dto.capacity } : {}),
                updated_at: new Date(),
            },
        });
    }

    async submitForApproval(id: string) {
        const wh = await this.findOne(id);
        if (wh.status !== org_status_enum.DRAFT && wh.status !== org_status_enum.REJECTED) {
            throw new BadRequestException('يمكن فقط إرسال المسودة أو الطلب المرفوض للاعتماد');
        }
        return this.prisma.warehouses.update({
            where: { id },
            data: { status: org_status_enum.PENDING_APPROVAL, rejection_reason: null },
        });
    }

    async approve(id: string, approverId: string, approverRole?: string | null) {
        const wh = await this.findOne(id);
        if (wh.status !== org_status_enum.PENDING_APPROVAL) {
            throw new BadRequestException('المخزن ليس في حالة انتظار الاعتماد');
        }
        const isSystemAdmin = (approverRole ?? '').trim().toUpperCase() === 'ADMIN';
        if (!isSystemAdmin && wh.created_by === approverId) {
            throw new ForbiddenException('لا يمكنك اعتماد طلب قمت بإنشائه بنفسك');
        }

        return this.prisma.warehouses.update({
            where: { id },
            data: { status: org_status_enum.ACTIVE, updated_at: new Date() },
        });
    }
    async reject(id: string, dto: RejectRequestDto) {
        const wh = await this.findOne(id);
        if (wh.status !== org_status_enum.PENDING_APPROVAL) {
            throw new BadRequestException('المخزن ليس في حالة انتظار الاعتماد');
        }

        return this.prisma.warehouses.update({
            where: { id },
            data: {
                status: org_status_enum.REJECTED,
                rejection_reason: dto.rejection_reason,
                updated_at: new Date(),
            },
        });
    }

    async disable(id: string) {
        const wh = await this.findOne(id);

        // BR-ORG-014: فحص الرصيد في المخزن
        const stock = await this.prisma.stock_levels.findFirst({
            where: { warehouse_id: id, quantity_on_hand: { gt: 0 } },
        });
        if (stock) {
            throw new BadRequestException('لا يمكن تعطيل المخزن لأنه يحتوي على بضائع وأرصدة غير صفرية');
        }

        // BR-ORG-015: إذا كان رئيسياً، التأكد من عدم وجود مخازن فرعية نشطة تتبعه
        if (wh.type === warehouse_type_enum.MAIN) {
            const activeSubs = await this.prisma.warehouses.count({
                where: { parent_warehouse_id: id, status: org_status_enum.ACTIVE },
            });
            if (activeSubs > 0) {
                throw new BadRequestException(`لا يمكن تعطيل المخزن لوجود ${activeSubs} مخازن فرعية نشطة تتبعه`);
            }
        }

        return this.prisma.warehouses.update({
            where: { id },
            data: { status: org_status_enum.INACTIVE, updated_at: new Date() },
        });
    }

    async enable(id: string) {
        const wh = await this.findOne(id);

        if (wh.status === org_status_enum.ACTIVE) {
            const current = await this.prisma.warehouses.findUnique({ where: { id } });
            if (!current) throw new NotFoundException('المخزن غير موجود');
            return current;
        }

        if (wh.status !== org_status_enum.INACTIVE) {
            throw new BadRequestException(
                'يمكن فقط إعادة تفعيل المخزن الموقوف',
            );
        }

        if (wh.type === warehouse_type_enum.SUB) {
            const parent = wh.parent_warehouse;
            if (!parent || parent.status !== org_status_enum.ACTIVE) {
                throw new BadRequestException(
                    'لا يمكن تفعيل مخزن فرعي تابع لمخزن أب غير نشط',
                );
            }
        }

        return this.prisma.warehouses.update({
            where: { id },
            data: { status: org_status_enum.ACTIVE, updated_at: new Date() },
        });
    }

    async assignKeepers(id: string, dto: AssignKeepersDto) {
        await this.findOne(id);

        // استخدام Transaction لحذف التعيينات القديمة وإضافة الجديدة
        return this.prisma.$transaction(async (tx) => {
            await tx.warehouse_keepers.deleteMany({ where: { warehouse_id: id } });
            if (dto.keeper_ids.length > 0) {
                await tx.warehouse_keepers.createMany({
                    data: dto.keeper_ids.map((userId) => ({
                        warehouse_id: id,
                        user_id: userId,
                    })),
                });
            }
            return tx.warehouse_keepers.findMany({
                where: { warehouse_id: id },
                include: { user: true },
            });
        });
    }
}