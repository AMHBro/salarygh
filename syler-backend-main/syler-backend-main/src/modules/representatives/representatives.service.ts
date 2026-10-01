import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateRepresentativeDto } from './dto/create-representative.dto';
import { UpdateRepresentativeDto } from './dto/update-representative.dto';
import { PayCommissionDto } from './dto/pay-commission.dto';
import { writeAllowedPrices } from './allowed-prices';
import { listRepDebtSnapshots, repDebtCeilingMessage } from './rep-debt';
import { Prisma, rep_status_enum } from '@prisma/client';
import { pageWindow } from '../../common/paging';
import * as bcrypt from 'bcrypt';

@Injectable()
export class RepresentativesService {
  constructor(private prisma: PrismaService) {}

  // ─── 1. إحصائيات لوحة المندوبين (البطاقات الأربعة العلوية) ─────────────────
  async getDashboardStats() {
    const [activeRepsCount, reps] = await Promise.all([
      this.prisma.representatives.count({ where: { status: rep_status_enum.ACTIVE } }),
      this.prisma.representatives.findMany({
        include: {
          sales_invoices: {
            select: { total: true },
          },
        },
      }),
    ]);

    let totalRepSales = 0;
    let totalCommissions = 0;
    let totalPaidCommissions = 0;

    for (const rep of reps) {
      const repSales = rep.sales_invoices.reduce((sum, inv) => sum + Number(inv.total), 0);
      const repRate = Number(rep.commission_rate) || 0;
      const repCommission = (repRate / 100) * repSales;
      const repPaid = Number(rep.paid_commission) || 0;

      totalRepSales += repSales;
      totalCommissions += repCommission;
      totalPaidCommissions += repPaid;
    }

    const dueCommissions = Math.max(0, totalCommissions - totalPaidCommissions);

    return {
      active_reps: activeRepsCount,
      total_sales: totalRepSales,
      total_commissions: totalCommissions,
      due_commissions: dueCommissions,
    };
  }

  // ─── 2. إنشاء مندوب جديد مع حساب دخول ────────────────────────────────────
  async create(dto: CreateRepresentativeDto, userId?: string) {
    const existingUser = await this.prisma.users.findFirst({
      where: { username: dto.username },
    });
    if (existingUser) {
      throw new BadRequestException('اسم المستخدم مستخدم مسبقاً، يرجى اختيار اسم مستخدم آخر');
    }

    const passwordHash = await bcrypt.hash(dto.password || '123456', 10);

    return this.prisma.$transaction(async (tx) => {
      // 1. إنشاء حساب المستخدم
      const user = await tx.users.create({
        data: {
          username: dto.username,
          full_name: dto.name,
          phone: dto.phone,
          password_hash: passwordHash,
        },
      });

      // 2. إنشاء سجل المندوب
      const rep = await tx.representatives.create({
        data: {
          user_id: user.id,
          name: dto.name,
          phone: dto.phone,
          commission_rate: dto.commission_rate,
          office_name: dto.office_name,
          office_phone: dto.office_phone,
          office_address: dto.office_address,
          location_url: dto.location_url,
          max_debt_limit: dto.max_debt_limit ?? 0,
          status: rep_status_enum.ACTIVE,
        },
      });

      await writeAllowedPrices(tx, rep.id, dto.allowed_prices);

      return rep;
    });
  }

  // ─── 3. قائمة المندوبين مع الأداء والعمولات ──────────────────────────────
  async findAll(query: { search?: string; status?: rep_status_enum; page?: number; limit?: number }) {
    const { page, limit, skip } = pageWindow(query);

    const where: any = {};
    if (query.status) where.status = query.status;
    if (query.search) {
      where.OR = [
        { name: { contains: query.search, mode: 'insensitive' } },
        { phone: { contains: query.search, mode: 'insensitive' } },
        { users: { username: { contains: query.search, mode: 'insensitive' } } },
      ];
    }

    const [total, reps] = await Promise.all([
      this.prisma.representatives.count({ where }),
      this.prisma.representatives.findMany({
        where,
        skip,
        take: limit,
        include: {
          users: { select: { username: true } },
        },
        orderBy: { created_at: 'desc' },
      }),
    ]);

    const ids = reps.map((rep) => rep.id);
    const invoiceGroups = ids.length === 0
      ? []
      : await this.prisma.sales_invoices.groupBy({
        by: ['rep_id'],
        where: { rep_id: { in: ids } },
        _count: { id: true },
        _sum: { total: true },
      });
    const itemRows = ids.length === 0
      ? []
      : await this.prisma.$queryRaw<{ rep_id: string; items_sold: unknown }[]>(
        Prisma.sql`
          SELECT si.rep_id, COALESCE(SUM(sii.quantity), 0) AS items_sold
          FROM sales_invoices si
          LEFT JOIN sales_invoice_items sii ON sii.invoice_id = si.id
          WHERE si.rep_id IN (${Prisma.join(ids.map((id) => Prisma.sql`${id}::uuid`))})
          GROUP BY si.rep_id
        `,
      );
    const invoicesByRep = new Map(
      invoiceGroups
        .filter((group) => group.rep_id)
        .map((group) => [group.rep_id as string, group]),
    );
    const itemsByRep = new Map(itemRows.map((row) => [row.rep_id, Number(row.items_sold) || 0]));

    const data = reps.map((rep) => {
      const invoices = invoicesByRep.get(rep.id);
      const invoicesCount = invoices?._count?.id ?? 0;
      const itemsSold = itemsByRep.get(rep.id) ?? 0;
      const totalSales = Number(invoices?._sum?.total) || 0;
      const commissionRate = Number(rep.commission_rate) || 0;
      const totalCommission = (commissionRate / 100) * totalSales;
      const paidCommission = Number(rep.paid_commission) || 0;
      const dueCommission = Math.max(0, totalCommission - paidCommission);

      return {
        id: rep.id,
        name: rep.name,
        username: rep.users?.username ?? '—',
        phone: rep.phone ?? '—',
        status: rep.status,
        is_active: rep.status === rep_status_enum.ACTIVE,
        office_name: rep.office_name ?? 'المكتب الرئيسي',
        office_phone: rep.office_phone ?? '—',
        office_address: rep.office_address ?? '—',
        location_url: rep.location_url ?? null,
        commission_rate: commissionRate,
        max_debt_limit: Number(rep.max_debt_limit) || 0,
        invoices_count: invoicesCount,
        items_sold_count: itemsSold,
        total_sales: totalSales,
        total_commission: totalCommission,
        paid_commission: paidCommission,
        due_commission: dueCommission,
        is_settled: dueCommission <= 0,
      };
    });

    return {
      data,
      meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
    };
  }

  async debtCeilings() {
    const rows = await listRepDebtSnapshots(this.prisma);
    return rows.map((row) => {
      const limit = new Prisma.Decimal(String(row.max_debt_limit ?? 0));
      const total = new Prisma.Decimal(String(row.customer_debt_total ?? 0));
      const exceeded = limit.gt(0) && total.gt(limit);
      return {
        id: row.id,
        name: row.name,
        max_debt_limit: Number(limit),
        customer_debt_total: Number(total),
        debt_ceiling_exceeded: exceeded,
        debt_ceiling_message: exceeded
          ? repDebtCeilingMessage(row.name, total, limit)
          : null,
      };
    });
  }

  // ─── 4. تفاصيل مندوب واحد ────────────────────────────────────────────────
  async findOne(id: string) {
    const rep = await this.prisma.representatives.findUnique({
      where: { id },
      include: {
        users: { select: { id: true, username: true, email: true } },
        sales_invoices: {
          include: {
            customers: { select: { id: true, name: true, phone: true } },
            sales_invoice_items: { select: { quantity: true } },
          },
          orderBy: { created_at: 'desc' },
        },
      },
    });
    if (!rep) throw new NotFoundException('المندوب غير موجود');

    let totalSales = 0;
    let itemsSold = 0;
    for (const inv of rep.sales_invoices) {
      totalSales += Number(inv.total);
      for (const item of inv.sales_invoice_items) {
        itemsSold += Number(item.quantity);
      }
    }

    const commissionRate = Number(rep.commission_rate) || 0;
    const totalCommission = (commissionRate / 100) * totalSales;
    const paidCommission = Number(rep.paid_commission) || 0;
    const dueCommission = Math.max(0, totalCommission - paidCommission);

    return {
      rep: {
        id: rep.id,
        name: rep.name,
        username: rep.users?.username,
        phone: rep.phone,
        status: rep.status,
        office_name: rep.office_name ?? 'المكتب الرئيسي',
        office_phone: rep.office_phone,
        office_address: rep.office_address,
        location_url: rep.location_url,
        commission_rate: commissionRate,
        max_debt_limit: Number(rep.max_debt_limit) || 0,
      },
      stats: {
        invoices_count: rep.sales_invoices.length,
        items_sold_count: itemsSold,
        total_sales: totalSales,
        total_commission: totalCommission,
        paid_commission: paidCommission,
        due_commission: dueCommission,
        is_settled: dueCommission <= 0,
      },
      recent_sales: rep.sales_invoices.slice(0, 15),
    };
  }

  // ─── 5. دفع وصرف عمولة للمندوب ──────────────────────────────────────────
  async payCommission(id: string, dto: PayCommissionDto) {
    const details = await this.findOne(id);
    const dueCommission = details.stats.due_commission;

    if (dueCommission <= 0) {
      throw new BadRequestException('لا توجد أي عمولات مستحقة غير مدفوعة لهذا المندوب');
    }

    if (dto.amount > dueCommission) {
      throw new BadRequestException(
        `المبلغ المراد دفعه (${dto.amount} د.ع) أكبر من إجمالي العمولة المستحقة (${dueCommission} د.ع)`,
      );
    }

    await this.prisma.representatives.update({
      where: { id },
      data: {
        paid_commission: { increment: dto.amount },
        updated_at: new Date(),
      },
    });

    const newDue = dueCommission - dto.amount;

    return {
      success: true,
      message: 'تم تسجيل صرف العمولة للمندوب بنجاح',
      paid_amount: dto.amount,
      remaining_due: newDue,
      is_settled: newDue <= 0,
    };
  }

  // ─── 6. تعديل بيانات المندوب ─────────────────────────────────────────────
  async update(id: string, dto: UpdateRepresentativeDto) {
    await this.findOne(id);

    const updated = await this.prisma.representatives.update({
      where: { id },
      data: {
        name: dto.name,
        phone: dto.phone,
        commission_rate: dto.commission_rate,
        office_name: dto.office_name,
        office_phone: dto.office_phone,
        office_address: dto.office_address,
        location_url: dto.location_url,
        max_debt_limit: dto.max_debt_limit,
        updated_at: new Date(),
      },
    });

    if (dto.allowed_prices !== undefined) {
      await writeAllowedPrices(this.prisma, id, dto.allowed_prices);
    }

    return updated;
  }

  // ─── 7. تفعيل أو إيقاف حساب المندوب ──────────────────────────────────────
  async toggleStatus(id: string) {
    const rep = await this.prisma.representatives.findUnique({ where: { id } });
    if (!rep) throw new NotFoundException('المندوب غير موجود');

    const nextStatus = rep.status === rep_status_enum.ACTIVE ? rep_status_enum.INACTIVE : rep_status_enum.ACTIVE;

    const updated = await this.prisma.representatives.update({
      where: { id },
      data: { status: nextStatus, updated_at: new Date() },
    });

    return {
      success: true,
      message: `تم ${nextStatus === rep_status_enum.ACTIVE ? 'تفعيل' : 'إيقاف'} حساب المندوب بنجاح`,
      status: updated.status,
    };
  }
}
