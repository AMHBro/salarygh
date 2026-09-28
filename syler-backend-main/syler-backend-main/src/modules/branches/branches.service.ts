import {
    Injectable,
    NotFoundException,
    BadRequestException,
    ForbiddenException,
} from '@nestjs/common';
import { pageWindow } from '../../common/paging';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateBranchDto } from './dto/create-branch.dto';
// import { UpdateBranchDto } from './dto/update-branch.dto';
import { RejectRequestDto } from './dto/reject-request.dto';
import { org_status_enum, branch_type_enum } from '@prisma/client';


@Injectable()
export class BranchesService {
    constructor(private prisma: PrismaService) { }

    async generateBranchCode(): Promise<string> {
        const count = await this.prisma.branches.count();
        return `BR-${String(count + 1).padStart(3, '0')}`;
    }
    async create(dto: CreateBranchDto, userId: string) {
        const company = await this.prisma.companies.findFirst();
        if (!company) {
            throw new NotFoundException("لم يتم ضبط البيانات الشركة بعد")
        }
        if (dto.type === branch_type_enum.HEADQUARTERS) {
            const hqExists = await this.prisma.branches.findFirst({
                where: { type: branch_type_enum.HEADQUARTERS, status: { not: org_status_enum.INACTIVE } },
            });
            if (hqExists) {
                throw new BadRequestException("يوجد فرع رئيسي بالفعل")
            }
        }
        const code = dto.code || (await this.generateBranchCode());

        return this.prisma.branches.create({
            data: {
                ...dto,
                code,
                company_id: company.id,
                status: org_status_enum.DRAFT,
                created_by: userId,
            },
            include: { manager: true },
        });

    }

    async findAll(query: any) {
        const { search, status, type } = query;
        const { page, limit, skip } = pageWindow(query);

        const where: any = {};
        if (search) {
            where.OR = [
                { name: { contains: search, mode: 'insensitive' } },
                { code: { contains: search, mode: 'insensitive' } },
            ];
        }
        if (status) where.status = status;
        if (type) where.type = type;

        const [total, data] = await Promise.all([
            this.prisma.branches.count({ where }),
            this.prisma.branches.findMany({
                where,
                skip: Number(skip),
                take: Number(limit),
                include: {
                    manager: { select: { id: true, username: true } },
                    _count: { select: { warehouses: true } },
                },
                orderBy: { created_at: 'desc' },
            }),
        ]);

        return { data, meta: { total, page: Number(page), limit: Number(limit) } };
    }
    async findOne(id: string) {
        const branch = await this.prisma.branches.findUnique({
            where: { id },
            include: {
                manager: true,
                warehouses: {
                    include: { manager: true, _count: { select: { sub_warehouses: true } } },
                },
            },
        });
        if (!branch) throw new NotFoundException('الفرع غير موجود');
        return branch;
    }
    async submitForApproval(id: string) {
        const branch = await this.findOne(id);
        if (branch.status !== org_status_enum.DRAFT && branch.status !== org_status_enum.REJECTED) {
            throw new BadRequestException('يمكن فقط إرسال المسودة أو الطلب المرفوض للاعتماد');
        }
        return this.prisma.branches.update({
            where: { id },
            data: { status: org_status_enum.PENDING_APPROVAL, rejection_reason: null },
        });
    }
    async approve(id: string, approverId: string) {
        const branch = await this.findOne(id);
        if (branch.status !== org_status_enum.PENDING_APPROVAL) {
            throw new BadRequestException('الفرع ليس في حالة انتظار الاعتماد');
        }
        // BR-ORG-009: صانع الطلب لا يعتمد طلبه بنفسه
        if (branch.created_by === approverId) {
            throw new ForbiddenException('لا يمكنك اعتماد طلب قمت بإنشائه بنفسك');
        }

        return this.prisma.branches.update({
            where: { id },
            data: { status: org_status_enum.ACTIVE, updated_at: new Date() },
        });
    }

    async reject(id: string, dto: RejectRequestDto) {
        const branch = await this.findOne(id);
        if (branch.status !== org_status_enum.PENDING_APPROVAL) {
            throw new BadRequestException('الفرع ليس في حالة انتظار الاعتماد');
        }

        return this.prisma.branches.update({
            where: { id },
            data: {
                status: org_status_enum.REJECTED,
                rejection_reason: dto.rejection_reason,
                updated_at: new Date(),
            },
        });
    }
    async disable(id: string) {
        const branch = await this.findOne(id);
        // BR-ORG-016: فحص وجود مخازن نشطة
        const activeWarehouses = await this.prisma.warehouses.count({
            where: { branch_id: id, status: org_status_enum.ACTIVE },
        });
        if (activeWarehouses > 0) {
            throw new BadRequestException(`لا يمكن تعطيل الفرع لوجود ${activeWarehouses} مخزن نشط بداخله`);
        }

        return this.prisma.branches.update({
            where: { id },
            data: { status: org_status_enum.INACTIVE, updated_at: new Date() },
        });
    }

    async assignManager(id: string, managerId: string) {
        await this.findOne(id);
        return this.prisma.branches.update({
            where: { id },
            data: { manager_id: managerId },
            include: { manager: true },
        });
    }


}



