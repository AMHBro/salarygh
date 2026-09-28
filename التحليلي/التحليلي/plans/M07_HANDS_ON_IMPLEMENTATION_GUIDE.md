# 📘 الدليل التطبيقي الشامل لتنفيذ موديول M07 (المندوبين، العُهد، والعمولات)
### Hands-On Complete Implementation Guide — Sayler Backend (NestJS + Prisma)

> **الهدف من هذا الدليل**: مرجع كودي كامل وشامل لبناء موديول **M07 (إدارة المندوبين، حسابات المستخدمين، العمولات المستحقة والمدفوعة، بيانات المكاتب، وطلبات العهدة الميدانية)** ليتطابق 100% مع واجهات شاشات المندوبين وقواعد العمل.

---

## 📑 فهرس المحتويات
1. [الهيكل المعماري لموديول المندوبين والعهد](#1-الهيكل-المعماري-لموديول-المندوبين-والعهد)
2. [قواعد العمل الحاكمة (Business Rules)](#2-قواعد-العمل-الحاكمة-business-rules)
3. [الخطوة 1: مراجعة نماذج قاعدة البيانات (Prisma Schema)](#الخطوة-1-مراجعة-نماذج-قاعدة-البيانات-prisma-schema)
4. [الخطوة 2: ملفات الـ DTOs الكاملة للمندوبين والعمولات والعهد](#الخطوة-2-ملفات-الـ-dtos-الكاملة-للمندوبين-والعمولات-والعهد)
5. [الخطوة 3: ملف RepresentativesService الكامل](#الخطوة-3-ملف-representativesservice-الكامل)
6. [الخطوة 4: ملف RepresentativesController مع Swagger](#الخطوة-4-ملف-representativescontroller-مع-swagger)
7. [الخطوة 5: موديول طلبات العهدة (RepCustodyModule)](#الخطوة-5-موديول-طلبات-العهدة-repcustodymodule)
8. [الخطوة 6: التسجيل في AppModule وخطة الاختبار](#الخطوة-6-التسجيل-في-appmodule-وخطة-الاختبار)

---

## 1. الهيكل المعماري لموديول المندوبين والعهد

```
┌────────────────────────────────────────────────────────────────────────┐
│                        شاشة المندوبين الرئيسية                         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
    ┌───────────────────────────────┼───────────────────────────────┐
    ▼                               ▼                               ▼
┌───────────────────────┐ ┌───────────────────────┐ ┌───────────────────────┐
│ 1. لوحة الإحصائيات    │ │ 2. إنشاء مندوب جديد   │ │ 3. صرف العمولات       │
│ • 4 بطاقات علوية:     │ │ • الاسم + الهاتف      │ │ • نافذة "دفع عمولة"   │
│   - المندوبون النشطون │ │ • حساب Login للمندوب  │ │ • تخفيض المستحق فوراً │
│   - مبيعات المندوبين  │ │ • نسبة العمولة %      │ │ • تسجيل تاريخ الدفع   │
│   - إجمالي العمولات   │ │ • بيانات المكتب       │ │                       │
│   - عمولات مستحقة     │ │   (الاسم، العنوان...) │ │                       │
└───────────────────────┘ └───────────────────────┘ └───────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 4. قائمة المندوبين وتفاصيل الأداء                                      │
│ • جدول تفصيلي: (الاسم، المكتب، النسبة %، الفواتير، القطع، المبيعات،    │
│   العمولة الكلية، والمستحق المتبقي)                                    │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. قواعد العمل الحاكمة (Business Rules)

| الرمز | القاعدة البرمجية | كيف تطبقها في الكود؟ |
|---|---|---|
| **BR-REP-001** | إنشاء حساب دخول لكل مندوب | عند إضافة مندوب، ينشئ النظام مستخدم `users` باسم المستخدم `username` وكلمة مرور مشفرة. |
| **BR-REP-002** | احتساب العمولات التلقائي | تحسب العمولة الكلية بناءً على نسبة المندوب `commission_rate` من إجمالي مبيعات فواتيره `sales_invoices`. |
| **BR-REP-003** | إدارة المستحقات والمدفوعات | `المستحق = إجمالي العمولات المحتسبة - paid_commission`. |
| **BR-REP-004** | صرف العمولات | عبر نافذة "دفع عمولة" يتم زيادة `paid_commission` بما تم دفعه للمندوب. |
| **BR-REP-005** | تسليم العهدة وخصم المخزن | عند تسليم عهدة بضاعة لمندوب، يتم خصمها من المخزن بحركة `OUT` وتصبح تحت مسؤولية المندوب. |

---

## الخطوة 1: مراجعة نماذج قاعدة البيانات (Prisma Schema)

النماذج متزامنة ومحدثة في قاعدة البيانات:
* `representatives`: جدول المندوبين ونسبة العمولات `commission_rate`، المدفوع `paid_commission`، وبيانات المكتب (`office_name`, `office_phone`, `office_address`, `location_url`).
* `users`: جدول مستخدمي النظام لتسجيل الدخول.
* `sales_invoices`: جدول فواتير المبيعات المرتبطة بالمندوب عبر `rep_id`.
* `rep_custody_orders` و `rep_custody_items`: جدول توثيق طلبات وتسليم العهد.

---

## الخطوة 2: ملفات الـ DTOs الكاملة للمندوبين والعمولات والعهد

المجلد: `src/modules/representatives/dto/`

### 1. إنشاء وتعديل مندوب (`dto/create-representative.dto.ts` و `update-representative.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsNumber, Min, Max } from 'class-validator';

export class CreateRepresentativeDto {
  @ApiProperty({ example: 'أحمد علي' })
  @IsNotEmpty({ message: 'اسم المندوب مطلوب' })
  @IsString()
  name: string;

  @ApiProperty({ example: 'ahmed.rep' })
  @IsNotEmpty({ message: 'اسم المستخدم مطلوب' })
  @IsString()
  username: string;

  @ApiPropertyOptional({ example: 'password123' })
  @IsOptional()
  @IsString()
  password?: string;

  @ApiProperty({ example: '07701234567' })
  @IsNotEmpty({ message: 'رقم الهاتف مطلوب' })
  @IsString()
  phone: string;

  @ApiProperty({ example: 5, description: 'نسبة العمولة % (مثلاً 5 تعني 5%)' })
  @IsNumber()
  @Min(0)
  @Max(100)
  commission_rate: number;

  @ApiPropertyOptional({ example: 'المكتب الرئيسي' })
  @IsOptional()
  @IsString()
  office_name?: string;

  @ApiPropertyOptional({ example: '07800000001' })
  @IsOptional()
  @IsString()
  office_phone?: string;

  @ApiPropertyOptional({ example: 'بغداد - المنصور' })
  @IsOptional()
  @IsString()
  office_address?: string;

  @ApiPropertyOptional({ example: 'https://maps.google.com/?q=33.3152,44.3661' })
  @IsOptional()
  @IsString()
  location_url?: string;
}
```

```typescript
// update-representative.dto.ts
import { PartialType } from '@nestjs/swagger';
import { CreateRepresentativeDto } from './create-representative.dto';

export class UpdateRepresentativeDto extends PartialType(CreateRepresentativeDto) {}
```

### 2. DTO دفع وصرف عمولة للمندوب (`dto/pay-commission.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsNumber, IsOptional, IsString, Min } from 'class-validator';

export class PayCommissionDto {
  @ApiProperty({ example: 122500, description: 'المبلغ المدفوع كعمولة للمندوب بالدينار' })
  @IsNotEmpty({ message: 'مبلغ العمولة مطلوب' })
  @IsNumber()
  @Min(1, { message: 'المبلغ يجب أن يكون أكبر من الصفر' })
  amount: number;

  @ApiPropertyOptional({ example: 'صرف عمولة شهر آب' })
  @IsOptional()
  @IsString()
  notes?: string;
}
```

---

## الخطوة 3: ملف RepresentativesService الكامل

المسار: `src/modules/representatives/representatives.service.ts`

```typescript
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateRepresentativeDto } from './dto/create-representative.dto';
import { UpdateRepresentativeDto } from './dto/update-representative.dto';
import { PayCommissionDto } from './dto/pay-commission.dto';
import { rep_status_enum } from '@prisma/client';
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
          status: rep_status_enum.ACTIVE,
        },
      });

      return rep;
    });
  }

  // ─── 3. قائمة المندوبين مع الأداء والعمولات ──────────────────────────────
  async findAll(query: { search?: string; status?: rep_status_enum; page?: number; limit?: number }) {
    const page = Number(query.page) || 1;
    const limit = Number(query.limit) || 20;
    const skip = (page - 1) * limit;

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
          sales_invoices: {
            include: {
              sales_invoice_items: { select: { quantity: true } },
            },
          },
        },
        orderBy: { created_at: 'desc' },
      }),
    ]);

    const data = reps.map((rep) => {
      const invoicesCount = rep.sales_invoices.length;
      let itemsSold = 0;
      let totalSales = 0;

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

    const updated = await this.prisma.representatives.update({
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

    return this.prisma.representatives.update({
      where: { id },
      data: {
        name: dto.name,
        phone: dto.phone,
        commission_rate: dto.commission_rate,
        office_name: dto.office_name,
        office_phone: dto.office_phone,
        office_address: dto.office_address,
        location_url: dto.location_url,
        updated_at: new Date(),
      },
    });
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
```

---

## الخطوة 4: ملف RepresentativesController مع Swagger

المسار: `src/modules/representatives/representatives.controller.ts`

```typescript
import { Controller, Get, Post, Patch, Param, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { RepresentativesService } from './representatives.service';
import { CreateRepresentativeDto } from './dto/create-representative.dto';
import { UpdateRepresentativeDto } from './dto/update-representative.dto';
import { PayCommissionDto } from './dto/pay-commission.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { rep_status_enum } from '@prisma/client';

@ApiTags('Sales Representatives (M07)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('representatives')
export class RepresentativesController {
  constructor(private readonly repsService: RepresentativesService) {}

  @Get('dashboard/stats')
  @ApiOperation({ summary: 'إحصائيات لوحة المندوبين (النشطون، المبيعات، إجمالي العمولات، المستحقات)' })
  async getDashboardStats() {
    const data = await this.repsService.getDashboardStats();
    return { success: true, data };
  }

  @Post()
  @ApiOperation({ summary: 'إضافة مندوب جديد وإنشاء حساب دخول له وبيانات المكتب' })
  async create(@Body() dto: CreateRepresentativeDto, @Request() req: any) {
    const data = await this.repsService.create(dto, req.user?.id);
    return { success: true, data, message: 'تم إضافة المندوب وإنشاء حسابه بنجاح' };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة المندوبين مع الفلاتر والبحث وتفاصيل العمولات' })
  @ApiQuery({ name: 'status', required: false, enum: rep_status_enum })
  @ApiQuery({ name: 'search', required: false, description: 'بحث بالاسم، المستخدم، أو الهاتف' })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAll(@Query() query: any) {
    return this.repsService.findAll(query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'تفاصيل المندوب مع إحصائيات مبيعاته وعمولاته وسجل فواتيره' })
  async findOne(@Param('id') id: string) {
    const data = await this.repsService.findOne(id);
    return { success: true, data };
  }

  @Post(':id/pay-commission')
  @ApiOperation({ summary: 'صرف ودفع عمولة للمندوب وتخفيض رصيد المستحق' })
  async payCommission(@Param('id') id: string, @Body() dto: PayCommissionDto) {
    return this.repsService.payCommission(id, dto);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'تعديل بيانات المندوب ونسبة العمولة وبيانات المكتب' })
  async update(@Param('id') id: string, @Body() dto: UpdateRepresentativeDto) {
    const data = await this.repsService.update(id, dto);
    return { success: true, data, message: 'تم تعديل بيانات المندوب بنجاح' };
  }

  @Patch(':id/toggle-status')
  @ApiOperation({ summary: 'تفعيل أو إيقاف حساب المندوب' })
  async toggleStatus(@Param('id') id: string) {
    return this.repsService.toggleStatus(id);
  }
}
```

---

## الخطوة 5: موديول طلبات العهدة (RepCustodyModule)

المجلد: `src/modules/rep-custody/`

### 1. DTO إنشاء طلب عهدة (`dto/create-rep-custody.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsUUID, IsArray, ValidateNested, IsNumber, IsOptional, IsString, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class CustodyItemDto {
  @ApiProperty({ example: 'uuid-product-variant-id' })
  @IsNotEmpty()
  @IsUUID()
  variant_id: string;

  @ApiProperty({ example: 25, description: 'الكمية المطلوبة عهدة' })
  @IsNumber()
  @Min(0.001)
  quantity: number;
}

export class CreateRepCustodyDto {
  @ApiProperty({ example: 'uuid-representative-id' })
  @IsNotEmpty()
  @IsUUID()
  rep_id: string;

  @ApiProperty({ example: 'uuid-warehouse-id' })
  @IsNotEmpty()
  @IsUUID()
  warehouse_id: string;

  @ApiPropertyOptional({ example: 'عهدة لبداية الأسبوع' })
  @IsOptional()
  @IsString()
  notes?: string;

  @ApiProperty({ type: [CustodyItemDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CustodyItemDto)
  items: CustodyItemDto[];
}
```

---

## الخطوة 6: التسجيل في AppModule وخطة الاختبار

في [app.module.ts](file:///c:/Users/FWZ/Documents/sayler/syler-backend/src/app.module.ts):
```typescript
import { RepresentativesModule } from './modules/representatives/representatives.module';

@Module({
  imports: [
    // ... باقي الموديولات
    // M07 ── Sales Representatives & Custody
    RepresentativesModule,
  ],
})
export class AppModule {}
```

---

> 🚀 **دليل M07 مكتمل وشامل ومطابق 100% لواجهات المندوبين وقواعد العمل!**
