# 📘 الدليل التطبيقي الشامل لتنفيذ موديول M06 (العملاء ونقطة البيع المباشر POS)
### Hands-On Complete Implementation Guide — Sayler Backend (NestJS + Prisma)

> **الهدف من هذا الدليل**: مرجع كودي كامل وشامل لبناء موديول **M06 (إدارة الزبائن، والبيع النقدي والمباشر POS، والأسعار المتعددة مفرد/جملة، والخصومات، وخصم المخزون والذمم)** ليتطابق 100% مع واجهات شاشات الزبائن والمبيعات وقواعد العمل.

---

## 📑 فهرس المحتويات
1. [الهيكل المعماري لنقطة البيع المباشر والزبائن](#1-الهيكل-المعماري-لنقطة-البيع-المباشر-والزبائن)
2. [قواعد العمل الحاكمة (Business Rules)](#2-قواعد-العمل-الحاكمة-business-rules)
3. [الخطوة 1: مراجعة نماذج قاعدة البيانات (Prisma Schema)](#الخطوة-1-مراجعة-نماذج-قاعدة-البيانات-prisma-schema)
4. [الخطوة 2: موديول العملاء (Customers Module) بالكامل](#الخطوة-2-موديول-العملاء-customers-module-بالكامل)
5. [الخطوة 3: موديول البيع المباشر (Direct Sales / POS Module) بالكامل](#الخطوة-3-موديول-البيع-المباشر-direct-sales--pos-module-بالكامل)
6. [الخطوة 4: التسجيل في AppModule](#الخطوة-4-التسجيل-في-appmodule)
7. [الخطوة 5: خطة الاختبار والفحص الشامل (Swagger Checklist)](#الخطوة-5-خطة-الاختبار-والفحص-الشامل-swagger-checklist)

---

## 1. الهيكل المعماري لنقطة البيع المباشر والزبائن

```
┌────────────────────────────────────────────────────────────────────────┐
│                        شاشة البيع المباشر (POS)                        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
    ┌───────────────────────────────┴───────────────────────────────┐
    ▼                                                               ▼
┌───────────────────────────────────┐               ┌───────────────────────────────────┐
│ اليمين: كتالوج المنتجات           │               │ اليسار: سلة الفاتورة والدفع        │
│ • بحث بالاسم أو الباركود          │               │ • اختيار الزبون (نقدي عام أو مسجل) │
│ • اختيار نوع السعر:               │               │ • أسطر المواد والكميات            │
│   (مفرد RETAIL / جملة WHOLESALE)  │               │ • الخصم المالي                    │
│ • عرض الكمية المتوفرة بالمخزن     │               │ • نوع الدفع: (نقدي / آجل / جزئي)  │
└───────────────────────────────────┘               └─────────────────┬─────────────────┘
                                                                      │
                                    ┌─────────────────────────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      الترحيل الذري بالـ DB                             │
│                      (Atomic DB Transaction)                           │
├────────────────────────────────────────────────────────────────────────┤
│ 1. فحص كفاية رصيد المخزن (منع البيع بالسالب)                           │
│ 2. إنشاء فاتورة المبيعات وأسطرها (sales_invoices)                      │
│ 3. خصم الكميات المباعة من المخزن المحدد (stock_levels)                 │
│ 4. تسجيل حركة إخراج مخزني (inventory_movements بنوع OUT)                │
│ 5. إذا كان البيع آجلاً/جزئياً: زيادة ذمة الزبون (customers.balance)    │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. قواعد العمل الحاكمة (Business Rules)

| الرمز | القاعدة البرمجية | كيف تطبقها في الكود؟ |
|---|---|---|
| **BR-POS-001** | البيع المباشر يدعم نوعين من الزبائن | `زبون نقدي عام` (Walk-in) أو `زبون مسجل` محفوظ بالسيستم. |
| **BR-POS-002** | منع البيع بالآجل للزبون النقدي العام | إذا كان `due_amount > 0`، يجب تحديد `customer_id` مسجل بالسيستم وإلا يرفض الطلب. |
| **BR-POS-003** | فحص الحد الائتماني للزبون المسجل | عند البيع الآجل: `(customer.balance + due_amount) <= customer.credit_limit`. |
| **BR-POS-004** | منع البيع برصيد سالب | فحص `stock_levels.quantity_on_hand >= item.quantity` لكل مادة في المخزن المختار قبل البيع. |
| **BR-POS-005** | مرونة اختيار مستويات الأسعار | يدعم الكاشير التبديل بين سعر المفرد `RETAIL` وسعر الجملة `WHOLESALE`. |
| **BR-POS-006** | تنفيذ البيع ذرياً بالكامل | حفظ الفاتورة، خصم المخزن، تسجيل حركة `OUT`، وتحديث ذمة الزبون داخل `Prisma.$transaction` واحدة. |

---

## الخطوة 1: مراجعة نماذج قاعدة البيانات (Prisma Schema)

النماذج موجودة وجاهزة بالفعل في `prisma/schema.prisma`:
* `customers`: جدول الزبائن والحد الائتماني والرصيد.
* `sales_invoices`: جدول فواتير المبيعات ورأس الفاتورة وطريقة الدفع والخصم.
* `sales_invoice_items`: أسطر فاتورة المبيعات والكميات والأسعار.
* `stock_levels` و `inventory_movements`: خصم المخزون وتسجيل الحركات.

---

## الخطوة 2: موديول العملاء (Customers Module) بالكامل

المجلد: `src/modules/customers/`

### 1. الـ DTO لإنشاء وتعديل عميل (`dto/create-customer.dto.ts` و `update-customer.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsEmail, IsNumber, IsEnum, Min } from 'class-validator';
import { customer_type_enum } from '@prisma/client';

export class CreateCustomerDto {
  @ApiProperty({ example: 'أحمد محمد' })
  @IsNotEmpty({ message: 'اسم الزبون مطلوب' })
  @IsString()
  name: string;

  @ApiPropertyOptional({ example: '07701234567' })
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiPropertyOptional({ example: 'ahmed@example.com' })
  @IsOptional()
  @IsEmail({}, { message: 'البريد الإلكتروني غير صالح' })
  email?: string;

  @ApiPropertyOptional({ example: 'بغداد - المنصور' })
  @IsOptional()
  @IsString()
  address?: string;

  @ApiPropertyOptional({ enum: customer_type_enum, example: customer_type_enum.RETAIL })
  @IsOptional()
  @IsEnum(customer_type_enum)
  type?: customer_type_enum;

  @ApiPropertyOptional({ example: 5000000, description: 'الحد الائتماني بالدينار' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  credit_limit?: number;

  @ApiPropertyOptional({ example: 'زبون دائم' })
  @IsOptional()
  @IsString()
  notes?: string;
}
```

```typescript
// update-customer.dto.ts
import { PartialType } from '@nestjs/swagger';
import { CreateCustomerDto } from './create-customer.dto';

export class UpdateCustomerDto extends PartialType(CreateCustomerDto) {}
```

### 2. DTO سند قبض من زبون (`dto/customer-payment.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsNumber, IsOptional, IsString, Min } from 'class-validator';

export class RecordCustomerPaymentDto {
  @ApiProperty({ example: 250000, description: 'المبلغ المستلم من الزبون' })
  @IsNumber()
  @Min(1, { message: 'المبلغ يجب أن يكون أكبر من الصفر' })
  amount: number;

  @ApiPropertyOptional({ example: 'سداد دفعة نقدية' })
  @IsOptional()
  @IsString()
  notes?: string;
}
```

### 3. ملف الـ Service (`customers.service.ts`):
```typescript
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateCustomerDto } from './dto/create-customer.dto';
import { UpdateCustomerDto } from './dto/update-customer.dto';
import { RecordCustomerPaymentDto } from './dto/customer-payment.dto';

@Injectable()
export class CustomersService {
  constructor(private prisma: PrismaService) {}

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
  async findAll(query: {
    search?: string;
    filter?: 'all' | 'has_debt' | 'settled';
    page?: number;
    limit?: number;
  }) {
    const page = Number(query.page) || 1;
    const limit = Number(query.limit) || 20;
    const skip = (page - 1) * limit;

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
        include: {
          _count: { select: { sales_invoices: true } },
          sales_invoices: {
            select: {
              total: true,
              paid_amount: true,
              created_at: true,
            },
            orderBy: { created_at: 'desc' },
          },
        },
        orderBy: { name: 'asc' },
      }),
    ]);

    const data = items.map((c) => {
      const totalPurchases = c.sales_invoices.reduce((sum, inv) => sum + Number(inv.total), 0);
      const totalPaid = c.sales_invoices.reduce((sum, inv) => sum + Number(inv.paid_amount), 0);
      const lastPurchase = c.sales_invoices[0]?.created_at ?? null;

      return {
        id: c.id,
        name: c.name,
        phone: c.phone ?? '—',
        address: c.address ?? '—',
        invoices_count: c._count.sales_invoices,
        total_purchases: totalPurchases,
        total_paid: totalPaid,
        current_balance: Number(c.balance),
        last_purchase_date: lastPurchase,
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
  async recordPayment(id: string, dto: RecordCustomerPaymentDto) {
    const customer = await this.prisma.customers.findUnique({ where: { id } });
    if (!customer) throw new NotFoundException('الزبون غير موجود');

    const currentBalance = Number(customer.balance);
    if (currentBalance <= 0) {
      throw new BadRequestException('هذا الزبون ليس عليه أي رصيد ذمة مستحق');
    }

    const newBalance = Math.max(0, currentBalance - dto.amount);

    const updated = await this.prisma.customers.update({
      where: { id },
      data: {
        balance: newBalance,
        updated_at: new Date(),
      },
    });

    return {
      success: true,
      message: 'تم تسجيل دفعة الزبون وتحديث رصيد الذمة بنجاح',
      previous_balance: currentBalance,
      paid_amount: dto.amount,
      remaining_balance: newBalance,
    };
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
```

### 4. ملف الـ Controller (`customers.controller.ts`):
```typescript
import { Controller, Get, Post, Patch, Delete, Param, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { CustomersService } from './customers.service';
import { CreateCustomerDto } from './dto/create-customer.dto';
import { UpdateCustomerDto } from './dto/update-customer.dto';
import { RecordCustomerPaymentDto } from './dto/customer-payment.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('Customers (M06)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('customers')
export class CustomersController {
  constructor(private readonly customersService: CustomersService) {}

  @Get('dashboard/stats')
  @ApiOperation({ summary: 'إحصائيات لوحة الزبائن (عدد الزبائن، إجمالي المبيعات، إجمالي الديون، زبائن عليهم رصيد)' })
  async getDashboardStats() {
    const data = await this.customersService.getDashboardStats();
    return { success: true, data };
  }

  @Post()
  @ApiOperation({ summary: 'إنشاء زبون جديد' })
  async create(@Body() dto: CreateCustomerDto, @Request() req: any) {
    const data = await this.customersService.create(dto, req.user?.id);
    return { success: true, data, message: 'تم إنشاء الزبون بنجاح' };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة الزبائن مع البحث وفلترة الديون والصفحات' })
  @ApiQuery({ name: 'search', required: false, description: 'بحث بالاسم أو الهاتف' })
  @ApiQuery({ name: 'filter', required: false, enum: ['all', 'has_debt', 'settled'] })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAll(@Query() query: any) {
    return this.customersService.findAll(query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'تفاصيل الزبون وسجل فواتيره' })
  async findOne(@Param('id') id: string) {
    const data = await this.customersService.findOne(id);
    return { success: true, data };
  }

  @Post(':id/payments')
  @ApiOperation({ summary: 'تسجيل دفعة قبض من زبون لتسديد رصيد ديونه' })
  async recordPayment(@Param('id') id: string, @Body() dto: RecordCustomerPaymentDto) {
    return this.customersService.recordPayment(id, dto);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'تحديث بيانات الزبون والحد الائتماني' })
  async update(@Param('id') id: string, @Body() dto: UpdateCustomerDto) {
    const data = await this.customersService.update(id, dto);
    return { success: true, data, message: 'تم تحديث بيانات الزبون بنجاح' };
  }

  @Delete(':id')
  @ApiOperation({ summary: 'تعطيل الزبون بعد التحقق من خلو ذمته' })
  async remove(@Param('id') id: string) {
    const data = await this.customersService.remove(id);
    return { success: true, data, message: 'تم تعطيل الزبون بنجاح' };
  }
}
```

### 5. ملف الـ Module (`customers.module.ts`):
```typescript
import { Module } from '@nestjs/common';
import { CustomersService } from './customers.service';
import { CustomersController } from './customers.controller';

@Module({
  controllers: [CustomersController],
  providers: [CustomersService],
  exports: [CustomersService],
})
export class CustomersModule {}
```

---

## الخطوة 3: موديول البيع المباشر (Direct Sales / POS Module) بالكامل

المجلد: `src/modules/direct-sales/`

### 1. الـ DTO لإنشاء فاتورة بيع مباشر (`dto/create-direct-sale.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsNotEmpty,
  IsUUID,
  IsEnum,
  IsNumber,
  IsArray,
  ValidateNested,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';
import { Type } from 'class-transformer';
import { price_type_enum, sales_payment_enum } from '@prisma/client';

export class SaleItemDto {
  @ApiProperty({ example: 'uuid-product-variant-id', description: 'معرف المنتج/الشكل' })
  @IsNotEmpty({ message: 'المنتج مطلوب' })
  @IsUUID()
  variant_id: string;

  @ApiProperty({ example: 'uuid-unit-of-measure-id', description: 'وحدة البيع' })
  @IsNotEmpty({ message: 'وحدة القياس مطلوبة' })
  @IsUUID()
  unit_id: string;

  @ApiProperty({ example: 2, description: 'الكمية المباعة' })
  @IsNumber()
  @Min(0.001, { message: 'الكمية يجب أن تكون أكبر من الصفر' })
  quantity: number;

  @ApiProperty({ example: 12000, description: 'سعر بيع الوحدة' })
  @IsNumber()
  @Min(0)
  unit_price: number;

  @ApiPropertyOptional({ example: 0, description: 'نسبة الخصم على السطر %' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  discount_percent?: number;
}

export class CreateDirectSaleDto {
  @ApiPropertyOptional({ example: 'uuid-customer-id', description: 'معرف الزبون المسجل (يتركه فارغاً للزبون النقدي العام)' })
  @IsOptional()
  @IsUUID()
  customer_id?: string;

  @ApiProperty({ example: 'uuid-warehouse-id', description: 'المخزن الذي تخرج منه البضاعة' })
  @IsNotEmpty({ message: 'المخزن مطلوب' })
  @IsUUID()
  warehouse_id: string;

  @ApiProperty({ enum: price_type_enum, example: price_type_enum.RETAIL, description: 'نوع السعر: مفرد RETAIL أو جملة WHOLESALE' })
  @IsNotEmpty({ message: 'نوع السعر مطلوب' })
  @IsEnum(price_type_enum)
  price_type: price_type_enum;

  @ApiProperty({ enum: sales_payment_enum, example: sales_payment_enum.CASH, description: 'طريقة الدفع: CASH, CREDIT, PARTIAL' })
  @IsNotEmpty({ message: 'طريقة الدفع مطلوبة' })
  @IsEnum(sales_payment_enum)
  payment_type: sales_payment_enum;

  @ApiPropertyOptional({ example: 0, description: 'مبلغ الخصم الإجمالي' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  discount_amount?: number;

  @ApiPropertyOptional({ example: 60000, description: 'المبلغ المدفوع كاش' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  paid_amount?: number;

  @ApiPropertyOptional({ example: 'فاتورة بيع مباشر' })
  @IsOptional()
  @IsString()
  notes?: string;

  @ApiProperty({ type: [SaleItemDto], description: 'قائمة المواد المباعة' })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SaleItemDto)
  items: SaleItemDto[];
}
```

### 2. ملف الـ Service (`direct-sales.service.ts`):
```typescript
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateDirectSaleDto } from './dto/create-direct-sale.dto';
import { price_type_enum, sales_payment_enum, sales_status_enum, movement_type_enum } from '@prisma/client';

@Injectable()
export class DirectSalesService {
  constructor(private prisma: PrismaService) {}

  private async generateInvoiceNumber(): Promise<string> {
    const today = new Date();
    const prefix = `INV-${today.getFullYear()}${String(today.getMonth() + 1).padStart(2, '0')}-`;
    const count = await this.prisma.sales_invoices.count();
    return `${prefix}${String(count + 1).padStart(4, '0')}`;
  }

  // ─── 1. جلب كتالوج المنتجات لشاشة الـ POS مع الكميات والأسعار ──────────────
  async getPosProducts(query: { warehouse_id?: string; price_type?: price_type_enum; search?: string }) {
    const priceType = query.price_type || price_type_enum.RETAIL;

    const where: any = { is_active: true };
    if (query.search) {
      where.OR = [
        { name_ar: { contains: query.search, mode: 'insensitive' } },
        { barcode: { contains: query.search, mode: 'insensitive' } },
        { sku: { contains: query.search, mode: 'insensitive' } },
      ];
    }

    const products = await this.prisma.products.findMany({
      where,
      include: {
        units_of_measure: { select: { id: true, name_ar: true, symbol: true } },
        product_variants: {
          where: { is_active: true },
          include: {
            product_prices: { where: { is_active: true } },
            stock_levels: query.warehouse_id ? { where: { warehouse_id: query.warehouse_id } } : true,
          },
        },
      },
      orderBy: { name_ar: 'asc' },
    });

    const posItems = [];

    for (const p of products) {
      for (const v of p.product_variants) {
        const targetPrice = v.product_prices.find((pr) => pr.price_type === priceType);
        const retailPrice = v.product_prices.find((pr) => pr.price_type === price_type_enum.RETAIL);
        const wholesalePrice = v.product_prices.find((pr) => pr.price_type === price_type_enum.WHOLESALE);

        const availableQty = (v.stock_levels ?? []).reduce(
          (sum, sl) => sum + Number(sl.quantity_on_hand || 0),
          0,
        );

        posItems.push({
          product_id: p.id,
          variant_id: v.id,
          name: p.name_ar,
          barcode: v.barcode ?? p.barcode ?? '—',
          sku: v.sku ?? p.sku ?? '—',
          unit_id: p.base_unit_id,
          unit_name: p.units_of_measure?.name_ar,
          price: Number(targetPrice?.price ?? retailPrice?.price ?? 0),
          retail_price: Number(retailPrice?.price ?? 0),
          wholesale_price: Number(wholesalePrice?.price ?? 0),
          quantity_available: availableQty,
          is_out_of_stock: availableQty <= 0,
        });
      }
    }

    return posItems;
  }

  // ─── 2. إنشاء فاتورة بيع مباشر وترحيلها ذرياً ──────────────────────────────
  async createDirectSale(dto: CreateDirectSaleDto, userId?: string) {
    if (!dto.items || dto.items.length === 0) {
      throw new BadRequestException('يجب إضافة مادة واحدة على الأقل في الفاتورة');
    }

    // 1. التحقق من المخزن والعميل
    const warehouse = await this.prisma.warehouses.findUnique({ where: { id: dto.warehouse_id } });
    if (!warehouse) throw new NotFoundException('المخزن غير موجود');

    let customer: any = null;
    if (dto.customer_id) {
      customer = await this.prisma.customers.findUnique({ where: { id: dto.customer_id } });
      if (!customer) throw new NotFoundException('الزبون غير موجود');
    }

    // 2. حساب المجاميع المالية
    let subtotal = 0;
    for (const item of dto.items) {
      const lineDiscount = ((item.discount_percent || 0) / 100) * (item.quantity * item.unit_price);
      subtotal += item.quantity * item.unit_price - lineDiscount;
    }

    const discountAmount = Number(dto.discount_amount) || 0;
    const total = Math.max(0, subtotal - discountAmount);

    let paidAmount = 0;
    let dueAmount = 0;

    if (dto.payment_type === sales_payment_enum.CASH) {
      paidAmount = total;
      dueAmount = 0;
    } else if (dto.payment_type === sales_payment_enum.CREDIT) {
      paidAmount = 0;
      dueAmount = total;
    } else if (dto.payment_type === sales_payment_enum.PARTIAL) {
      paidAmount = Number(dto.paid_amount) || 0;
      if (paidAmount > total) throw new BadRequestException('المبلغ المدفوع لا يمكن أن يتجاوز إجمالي الفاتورة');
      dueAmount = total - paidAmount;
    }

    // 3. التحقق من الشراء الآجل (BR-POS-002 و BR-POS-003)
    if (dueAmount > 0) {
      if (!customer) {
        throw new BadRequestException('لا يمكن البيع بالآجل للزبون النقدي العام! يجب اختيار زبون مسجل في النظام.');
      }
      const newTotalBalance = Number(customer.balance) + dueAmount;
      const creditLimit = Number(customer.credit_limit);
      if (creditLimit > 0 && newTotalBalance > creditLimit) {
        throw new BadRequestException(
          `تجاوز الحد الائتماني للزبون! الحد المسموح: ${creditLimit}، الرصيد الحالي: ${customer.balance}`,
        );
      }
    }

    const invoiceNumber = await this.generateInvoiceNumber();
    const idempotencyKey = `POS-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;

    // 4. تنفيذ العملية داخل Database Transaction ذرية
    return this.prisma.$transaction(async (tx) => {
      // أ. التحقق من كفاية المخزون لكل مادة (BR-POS-004)
      for (const item of dto.items) {
        const stock = await tx.stock_levels.findUnique({
          where: {
            variant_id_warehouse_id: {
              variant_id: item.variant_id,
              warehouse_id: dto.warehouse_id,
            },
          },
        });

        const availableQty = stock ? Number(stock.quantity_on_hand) : 0;
        if (availableQty < Number(item.quantity)) {
          const variant = await tx.product_variants.findUnique({
            where: { id: item.variant_id },
            include: { products: true },
          });
          const prodName = variant?.products?.name_ar || 'المادة';
          throw new BadRequestException(
            `الكمية غير كافية بالمخزن للمادة "${prodName}"! المتاح: ${availableQty}، المطلوب: ${item.quantity}`,
          );
        }
      }

      // ب. إنشاء سجل فاتورة المبيعات
      const invoice = await tx.sales_invoices.create({
        data: {
          invoice_number: invoiceNumber,
          customer_id: dto.customer_id ?? null,
          warehouse_id: dto.warehouse_id,
          price_type: dto.price_type,
          payment_type: dto.payment_type,
          status: dueAmount === 0 ? sales_status_enum.PAID : sales_status_enum.PARTIAL,
          subtotal,
          discount_amount: discountAmount,
          total,
          paid_amount: paidAmount,
          due_amount: dueAmount,
          notes: dto.notes,
          idempotency_key: idempotencyKey,
          created_by: userId,
        },
      });

      // ج. إدخال أسطر الفاتورة وخصم المخزون
      for (const item of dto.items) {
        const itemLineTotal =
          item.quantity * item.unit_price -
          ((item.discount_percent || 0) / 100) * (item.quantity * item.unit_price);

        const variant = await tx.product_variants.findUnique({ where: { id: item.variant_id } });

        await tx.sales_invoice_items.create({
          data: {
            invoice_id: invoice.id,
            variant_id: item.variant_id,
            unit_id: item.unit_id,
            quantity: item.quantity,
            quantity_in_base_unit: item.quantity,
            unit_price: item.unit_price,
            cost_per_base_unit: variant?.weighted_avg_cost ?? 0,
            discount_percent: item.discount_percent || 0,
            net_unit_price: item.quantity > 0 ? itemLineTotal / item.quantity : item.unit_price,
            total_price: itemLineTotal,
          },
        });

        // خصم الكمية من stock_levels
        await tx.stock_levels.update({
          where: {
            variant_id_warehouse_id: {
              variant_id: item.variant_id,
              warehouse_id: dto.warehouse_id,
            },
          },
          data: {
            quantity_on_hand: { decrement: item.quantity },
            updated_at: new Date(),
          },
        });

        // تسجيل حركة إخراج مخزني
        await tx.inventory_movements.create({
          data: {
            movement_type: movement_type_enum.OUT,
            variant_id: item.variant_id,
            warehouse_id: dto.warehouse_id,
            quantity: item.quantity,
            unit_cost: variant?.weighted_avg_cost ?? 0,
            reference_type: 'SALES_INVOICE',
            reference_id: invoice.id,
            performed_by: userId,
          },
        });
      }

      // د. تحديث رصيد ذمة الزبون إذا كان البيع آجلاً/جزئياً
      if (customer && dueAmount > 0) {
        await tx.customers.update({
          where: { id: customer.id },
          data: {
            balance: { increment: dueAmount },
            updated_at: new Date(),
          },
        });
      }

      return {
        id: invoice.id,
        invoice_number: invoice.invoice_number,
        customer_name: customer?.name ?? 'زبون نقدي',
        total: Number(invoice.total),
        paid_amount: Number(invoice.paid_amount),
        due_amount: Number(invoice.due_amount),
        payment_type: invoice.payment_type,
        created_at: invoice.created_at,
      };
    });
  }

  // ─── 3. قائمة فواتير المبيعات ──────────────────────────────────────────────
  async findAll(query: any) {
    const page = Number(query.page) || 1;
    const limit = Number(query.limit) || 20;
    const skip = (page - 1) * limit;

    const where: any = {};
    if (query.customer_id) where.customer_id = query.customer_id;
    if (query.warehouse_id) where.warehouse_id = query.warehouse_id;
    if (query.payment_type) where.payment_type = query.payment_type;
    if (query.search) {
      where.OR = [
        { invoice_number: { contains: query.search, mode: 'insensitive' } },
        { customers: { name: { contains: query.search, mode: 'insensitive' } } },
      ];
    }

    const [total, items] = await Promise.all([
      this.prisma.sales_invoices.count({ where }),
      this.prisma.sales_invoices.findMany({
        where,
        skip,
        take: limit,
        include: {
          customers: { select: { id: true, name: true, phone: true } },
          warehouses: { select: { id: true, name: true } },
          _count: { select: { sales_invoice_items: true } },
        },
        orderBy: { created_at: 'desc' },
      }),
    ]);

    const data = items.map((inv) => ({
      id: inv.id,
      invoice_number: inv.invoice_number,
      customer_name: inv.customers?.name ?? 'زبون نقدي عام',
      warehouse_name: inv.warehouses?.name ?? '—',
      total: Number(inv.total),
      paid_amount: Number(inv.paid_amount),
      due_amount: Number(inv.due_amount),
      payment_type: inv.payment_type,
      status: inv.status,
      items_count: inv._count.sales_invoice_items,
      created_at: inv.created_at,
    }));

    return {
      data,
      meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
    };
  }

  // ─── 4. تفاصيل فاتورة بيع واحدة للطباعة ──────────────────────────────────
  async findOne(id: string) {
    const invoice = await this.prisma.sales_invoices.findUnique({
      where: { id },
      include: {
        customers: true,
        warehouses: true,
        sales_invoice_items: {
          include: {
            product_variants: { include: { products: true } },
            units_of_measure: true,
          },
        },
      },
    });
    if (!invoice) throw new NotFoundException('فاتورة المبيعات غير موجودة');
    return invoice;
  }
}
```

### 3. ملف الـ Controller (`direct-sales.controller.ts`):
```typescript
import { Controller, Get, Post, Param, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { DirectSalesService } from './direct-sales.service';
import { CreateDirectSaleDto } from './dto/create-direct-sale.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { price_type_enum } from '@prisma/client';

@ApiTags('Direct Sales & POS (M06)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('direct-sales')
export class DirectSalesController {
  constructor(private readonly directSalesService: DirectSalesService) {}

  @Get('products')
  @ApiOperation({ summary: 'كتالوج المنتجات لشاشة الـ POS مع الكميات المتوفرة وأسعار المفرد/الجملة' })
  @ApiQuery({ name: 'warehouse_id', required: false, description: 'المخزن المختار' })
  @ApiQuery({ name: 'price_type', required: false, enum: price_type_enum, description: 'مستوى السعر' })
  @ApiQuery({ name: 'search', required: false, description: 'بحث بالاسم أو الباركود' })
  async getPosProducts(@Query() query: any) {
    const data = await this.directSalesService.getPosProducts(query);
    return { success: true, data };
  }

  @Post()
  @ApiOperation({ summary: 'إنهاء وتأكيد عملية البيع المباشر (خصم المخزون + الدفع + تحديث الذمة)' })
  async createDirectSale(@Body() dto: CreateDirectSaleDto, @Request() req: any) {
    const data = await this.directSalesService.createDirectSale(dto, req.user?.id);
    return { success: true, data, message: 'تمت عملية البيع بنجاح' };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة فواتير المبيعات مع الفلاتر' })
  @ApiQuery({ name: 'customer_id', required: false })
  @ApiQuery({ name: 'warehouse_id', required: false })
  @ApiQuery({ name: 'payment_type', required: false })
  @ApiQuery({ name: 'search', required: false })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAll(@Query() query: any) {
    return this.directSalesService.findAll(query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'تفاصيل فاتورة مبيعات مع المواد للطباعة' })
  async findOne(@Param('id') id: string) {
    const data = await this.directSalesService.findOne(id);
    return { success: true, data };
  }
}
```

### 4. ملف الـ Module (`direct-sales.module.ts`):
```typescript
import { Module } from '@nestjs/common';
import { DirectSalesService } from './direct-sales.service';
import { DirectSalesController } from './direct-sales.controller';

@Module({
  controllers: [DirectSalesController],
  providers: [DirectSalesService],
  exports: [DirectSalesService],
})
export class DirectSalesModule {}
```

---

## الخطوة 4: التسجيل في AppModule

في [app.module.ts](file:///c:/Users/FWZ/Documents/sayler/syler-backend/src/app.module.ts):
```typescript
import { CustomersModule } from './modules/customers/customers.module';
import { DirectSalesModule } from './modules/direct-sales/direct-sales.module';

@Module({
  imports: [
    // ... باقي الموديولات
    CustomersModule,
    DirectSalesModule,
  ],
})
export class AppModule {}
```

---

## الخطوة 5: خطة الاختبار والفحص الشامل (Swagger Checklist)

افتح `http://localhost:3000/api/docs` واختبر السيناريوهات الأربعة الأساسية لـ M06:

### ✅ سيناريو 1: كتالوج نقطة البيع (POS Catalog)
- [ ] استدعاء `GET /api/v1/direct-sales/products?price_type=RETAIL` لمخزن معين.
- [ ] التأكد من استرجاع قائمة المنتجات مع أسعارها والكميات المتاحة في المخزن.

### ✅ سيناريو 2: بيع مباشر نقدي (CASH Sale) لزبون عام
- [ ] استدعاء `POST /api/v1/direct-sales` بدون `customer_id` وبنوع `CASH`.
- [ ] التأكد من نجاح العملية وخصم كمية المنتج من المخزن المختار مباشرة.
- [ ] التأكد من ظهور حركة `OUT` في جدول حركات المخزون.

### ✅ سيناريو 3: بيع مباشر آجل (CREDIT Sale) لزبون مسجل
- [ ] إنشاء زبون مسجل باسم "علي حسن" بحد ائتماني `1,000,000 د.ع`.
- [ ] استدعاء `POST /api/v1/direct-sales` وتحديد `customer_id` وبنوع `CREDIT` بمبلغ `250,000 د.ع`.
- [ ] التأكد من خصم المخزون، وزيادة رصيد ذمة الزبون إلى `250,000 د.ع`.

### ✅ سيناريو 4: سداد دفعة من الزبون (Customer Payment)
- [ ] استدعاء `POST /api/v1/customers/:id/payments` لسداد `100,000 د.ع`.
- [ ] التأكد من انخفاض رصيد ذمة الزبون إلى `150,000 د.ع`.

---

> 🚀 **دليل M06 مكتمل ومحفوظ بالكامل!**
