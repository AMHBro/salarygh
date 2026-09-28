import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { pageWindow } from '../../common/paging';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateCustomerDto } from './dto/create-customer.dto';
import { UpdateCustomerDto } from './dto/update-customer.dto';
import { RecordCustomerPaymentDto } from './dto/customer-payment.dto';
import { payment_method_enum, Prisma, sales_status_enum, voucher_type_enum } from '@prisma/client';
import { randomBytes } from 'crypto';

@Injectable()
export class CustomersService {
  constructor(private prisma: PrismaService) { }

  // ─── إحصائيات لوحة الزبائن (البطاقات الأربعة العلوية) ───────────────────
  async getDashboardStats() {
    const [totalCustomers, salesSum, debtCustomers] = await Promise.all([
      this.prisma.customers.count({ where: { is_active: true } }),
      this.prisma.sales_invoices.aggregate({
        _sum: { total: true },
      }),
      this.prisma.customers.findMany({
        where: { is_active: true, balance: { gt: 0 } },
        select: { balance: true },
      }),
    ]);

    const totalDebts = debtCustomers.reduce((acc, c) => acc + Number(c.balance), 0);

    return {
      total_customers: totalCustomers,
      total_sales: Number(salesSum._sum.total) || 0,
      total_debts: totalDebts,
      customers_with_debt: debtCustomers.length,
    };
  }

  // ─── إنشاء زبون جديد ─────────────────────────────────────────────────────
  async create(dto: CreateCustomerDto, userId?: string) {
    if (dto.phone) {
      const existing = await this.prisma.customers.findUnique({ where: { phone: dto.phone } });
      if (existing) throw new BadRequestException('رقم الهاتف مستخدم مسبقاً لزبون آخر');
    }

    return this.prisma.customers.create({
      data: {
        ...dto,
        balance: 0,
        credit_limit: dto.credit_limit || 0,
        created_by: userId,
      },
    });
  }

  // ─── قائمة الزبائن مع الفلترة والبحث والـ Pagination ──────────────────────
  async findAll(query: { search?: string; filter?: 'all' | 'has_debt' | 'settled'; page?: number; limit?: number }) {
    const { page, limit, skip } = pageWindow(query);

    const where: any = { is_active: true };

    if (query.filter === 'has_debt') {
      where.balance = { gt: 0 };
    } else if (query.filter === 'settled') {
      where.balance = { lte: 0 };
    }

    if (query.search) {
      where.OR = [
        { name: { contains: query.search, mode: 'insensitive' } },
        { phone: { contains: query.search, mode: 'insensitive' } },
      ];
    }

    const [total, items] = await Promise.all([
      this.prisma.customers.count({ where }),
      this.prisma.customers.findMany({
        where,
        skip,
        take: limit,
        orderBy: { name: 'asc' },
      }),
    ]);

    const ids = items.map((item) => item.id);
    const invoiceGroups = ids.length === 0
      ? []
      : await this.prisma.sales_invoices.groupBy({
        by: ['customer_id'],
        where: { customer_id: { in: ids } },
        _count: { id: true },
        _sum: { total: true, paid_amount: true },
        _max: { created_at: true },
      });
    const invoicesByCustomer = new Map(invoiceGroups.map((group) => [group.customer_id, group]));

    const data = items.map((c) => {
      const invoices = invoicesByCustomer.get(c.id);
      return {
        id: c.id,
        name: c.name,
        phone: c.phone ?? '—',
        address: c.address ?? '—',
        invoices_count: invoices?._count?.id ?? 0,
        total_purchases: Number(invoices?._sum?.total) || 0,
        total_paid: Number(invoices?._sum?.paid_amount) || 0,
        current_balance: Number(c.balance),
        last_purchase_date: invoices?._max?.created_at ?? null,
      };
    });

    return {
      data,
      meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
    };
  }

  // ─── تفاصيل زبون واحد ────────────────────────────────────────────────────
  async findOne(id: string) {
    const customer = await this.prisma.customers.findUnique({
      where: { id },
      include: {
        sales_invoices: {
          take: 20,
          orderBy: { created_at: 'desc' },
        },
      },
    });
    if (!customer) throw new NotFoundException('الزبون غير موجود');

    const totalPurchases = customer.sales_invoices.reduce((sum, inv) => sum + Number(inv.total), 0);
    const totalPaid = customer.sales_invoices.reduce((sum, inv) => sum + Number(inv.paid_amount), 0);

    return {
      customer,
      summary: {
        total_purchases: totalPurchases,
        total_paid: totalPaid,
        current_due: Number(customer.balance),
      },
    };
  }

  // ─── تسجيل دفعة / سند قبض من زبون لتخفيض رصيد ذمته ───────────────────────
  async recordPayment(id: string, dto: RecordCustomerPaymentDto, userId?: string) {
    if (!Number.isFinite(dto.amount) || dto.amount <= 0 || !new Prisma.Decimal(dto.amount).mul(100).isInteger()) {
      throw new BadRequestException('المبلغ غير صالح أو يحتوي أكثر من منزلتين عشريتين');
    }
    if (!dto.cashbox_id) throw new BadRequestException('الصندوق مطلوب لتسجيل المقبوضات');
    const amount = new Prisma.Decimal(dto.amount);
    return this.prisma.$transaction(async tx => {
      const existing = await tx.payment_vouchers.findUnique({ where: { idempotency_key: dto.idempotency_key } });
      if (existing) {
        if (existing.voucher_type !== voucher_type_enum.RECEIPT || existing.customer_id !== id ||
          !existing.amount.equals(amount) || existing.cashbox_id !== dto.cashbox_id ||
          existing.sales_invoice_id !== (dto.invoice_id ?? null)) {
          throw new BadRequestException('مفتاح العملية مستخدم لسند مختلف');
        }
        return {
          success: true, voucher_number: existing.voucher_number,
          paid_amount: existing.amount, already_exists: true
        };
      }
      const [customer, cashbox] = await Promise.all([
        tx.customers.findUnique({ where: { id } }),
        tx.cashboxes.findUnique({ where: { id: dto.cashbox_id } }),
      ]);
      if (!customer) throw new NotFoundException('الزبون غير موجود');
      if (!cashbox) throw new NotFoundException('الصندوق غير موجود');
      if (!userId) throw new BadRequestException('المستخدم غير معروف');
      const user = await tx.users.findUnique({ where: { id: userId }, include: { roles: true } });
      if (!user?.is_active || (!['ADMIN', 'SUPER_ADMIN'].includes(user.roles?.name ?? '') && user.branch_id !== cashbox.branch_id)) {
        throw new BadRequestException('الصندوق خارج نطاق فرعك');
      }
      if (!dto.invoice_id && !['ADMIN', 'SUPER_ADMIN'].includes(user.roles?.name ?? '')) {
        const representative = customer.assigned_rep_id
          ? await tx.representatives.findUnique({ where: { id: customer.assigned_rep_id } }) : null;
        if (!representative || representative.branch_id !== cashbox.branch_id) {
          throw new BadRequestException('قبض الذمة العامة لهذا الزبون يتطلب صلاحية الإدارة');
        }
      }
      if (dto.invoice_id) {
        const invoice = await tx.sales_invoices.findUnique({
          where: { id: dto.invoice_id }, include: { warehouses: { select: { branch_id: true } } },
        });
        if (!invoice || invoice.customer_id !== id) throw new BadRequestException('الفاتورة لا تتبع هذا الزبون');
        if (invoice.status === sales_status_enum.DRAFT || invoice.status === sales_status_enum.CANCELLED || invoice.status === sales_status_enum.RETURNED) {
          throw new BadRequestException('لا يمكن قبض مبلغ على فاتورة مسودة أو ملغاة أو مرتجعة');
        }
        if (invoice.warehouses.branch_id !== cashbox.branch_id) {
          throw new BadRequestException('الصندوق والفاتورة يتبعان فرعين مختلفين');
        }
        const due = new Prisma.Decimal(invoice.due_amount);
        const applied = amount.lessThan(due) ? amount : due;
        if (applied.greaterThan(0)) {
          await tx.sales_invoices.update({
            where: { id: dto.invoice_id },
            data: {
              paid_amount: { increment: applied },
              due_amount: { decrement: applied },
              status: applied.greaterThanOrEqualTo(due)
                ? sales_status_enum.PAID
                : invoice.status,
              updated_at: new Date(),
            },
          });
        }
      }
      await tx.customers.update({
        where: { id },
        data: { balance: { decrement: amount }, updated_at: new Date() },
      });
      const voucher = await tx.payment_vouchers.create({
        data: {
          voucher_number: `RCPT-${randomBytes(8).toString('hex').toUpperCase()}`,
          voucher_type: voucher_type_enum.RECEIPT,
          payment_method: payment_method_enum.CASH,
          customer_id: id,
          cashbox_id: dto.cashbox_id,
          sales_invoice_id: dto.invoice_id ?? null,
          amount,
          idempotency_key: dto.idempotency_key,
          notes: dto.notes,
          created_by: userId,
        },
      });
      const current = await tx.customers.findUniqueOrThrow({ where: { id }, select: { balance: true } });
      return {
        success: true, voucher_number: voucher.voucher_number,
        paid_amount: amount, remaining_balance: current.balance
      };
    });
  }

  // ─── تحديث بيانات زبون ────────────────────────────────────────────────────
  async update(id: string, dto: UpdateCustomerDto) {
    await this.findOne(id);
    return this.prisma.customers.update({
      where: { id },
      data: { ...dto, updated_at: new Date() },
    });
  }

  // ─── تعطيل زبون ──────────────────────────────────────────────────────────
  async remove(id: string) {
    const res = await this.findOne(id);
    if (Number(res.customer.balance) > 0) {
      throw new BadRequestException(`لا يمكن حذف زبون يمتلك رصيد ديون مستحقة (${res.customer.balance} د.ع)`);
    }
    return this.prisma.customers.update({
      where: { id },
      data: { is_active: false },
    });
  }
}
