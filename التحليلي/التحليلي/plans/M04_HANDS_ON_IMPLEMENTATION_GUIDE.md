# 📘 الدليل التطبيقي الشامل لتنفيذ موديول M04 (الموردون، المشتريات المباشرة، والذمم)
### Hands-On Complete Implementation Guide — Sayler Backend (NestJS + Prisma)

> **الهدف من هذا الدليل**: مرجع كودي كامل وشامل لبناء موديول **M04 (الموردون، فواتير الشراء المباشرة، الذمم وسندات الدفع)** بالتفصيل، شاملاً كافة ملفات الـ DTOs، Controllers، Services، Modules، وهيكل متابعة الذمم وكشف الحساب.

---

## 📑 فهرس المحتويات
1. [الهيكل المعماري وحركة الذمم المخزنية والمالية](#1-الهيكل-المعماري-وحركة-الذمم-المخزنية-والمالية)
2. [قواعد العمل الحاكمة (Business Rules)](#2-قواعد-العمل-الحاكمة-business-rules)
3. [الخطوة 1: مراجعة وتجهيز قاعدة البيانات (Prisma Schema) بما فيها الذمم](#الخطوة-1-مراجعة-وتجهيز-قاعدة-البيانات-prisma-schema-بما-فيها-الذمم)
4. [الخطوة 2: موديول الموردين (Suppliers Module) بالكامل](#الخطوة-2-موديول-الموردين-suppliers-module-بالكامل)
5. [الخطوة 3: موديول فواتير الشراء المباشرة (Purchases Module) بالكامل](#الخطوة-3-موديول-فواتير-الشراء-المباشرة-purchases-module-بالكامل)
6. [الخطوة 4: موديول دفعات الموردين وإدارة الذمم (Supplier Payments & Dues Module)](#الخطوة-4-موديول-دفعات-الموردين-وإدارة-الذمم-supplier-payments--dues-module)
7. [الخطوة 5: التسجيل الكامل في AppModule](#الخطوة-5-التسجيل-الكامل-في-appmodule)
8. [الخطوة 6: خطة الاختبار والفحص الشامل (Swagger Checklist)](#الخطوة-6-خطة-الاختبار-والفحص-الشامل-swagger-checklist)

---

## 1. الهيكل المعماري وحركة الذمم المخزنية والمالية

```
                               ┌────────────────────────────────┐
                               │       المورد (Supplier)        │
                               │  - رصيد الذمة (balance)        │
                               │  - الحد الائتماني (credit_limit)│
                               └───────────────┬────────────────┘
                                               │
                               ┌───────────────▼────────────────┐
                               │   فاتورة الشراء (Purchase Inv) │
                               │   المخزن + المواد + طريقة الدفع │
                               └───────────────┬────────────────┘
                                               │
              ┌────────────────────────────────┴────────────────────────────────┐
              │                                                                 │
    [حالة الدفع: نقدي CASH]                                          [حالة الدفع: آجل CREDIT أو جزئي PARTIAL]
              │                                                                 │
              ▼                                                                 ▼
 ┌───────────────────────────┐                                     ┌───────────────────────────┐
 │ • المدفوع = الإجمالي       │                                     │ • المتبقي = الإجمالي - المدفوع│
 │ • الذمة المضافة = 0       │                                     │ • يضاف المتبقي لذمة المورد │
 │ • زيادة المخزون فوراً     │                                     │ • زيادة المخزون فوراً     │
 └───────────────────────────┘                                     └─────────────┬─────────────┘
                                                                                 │
                                                                                 ▼
                                                                   ┌───────────────────────────┐
                                                                   │ سند صرف لاحق (Payment)    │
                                                                   │ • سداد دفعة للمورد        │
                                                                   │ • خصم المبلغ من رصيد الذمة│
                                                                   └───────────────────────────┘
```

---

## 2. قواعد العمل الحاكمة (Business Rules)

| الرمز | القاعدة البرمجية | كيف تطبقها في الكود؟ |
|---|---|---|
| **BR-PUR-001** | المورد يتفعل مباشرة بعد اكتمال بياناته | الحالة الافتراضية `is_active: true`. |
| **BR-PUR-002** | الحد الائتماني إلزامي للشراء الآجل | عند إنشاء فاتورة آجلة/جزئية، يتحقق النظام: `(balance + due_amount) <= credit_limit`. |
| **BR-PUR-006** | الفاتورة مباشرة ومستقلة | لا يشترط طلب شراء مسبق، يتم اختيار المورد والمخزن والمواد والحفظ مباشرة. |
| **BR-PUR-007** | الاستلام كامل ومباشر | تدخل جميع كميات الفاتورة فوراً إلى المخزن المحدد بدون تجزئة. |
| **BR-PUR-011** | الترحيل ذري داخل Transaction | حفظ الفاتورة، زيادة رصيد `stock_levels`، تسجيل حركة `inventory_movements`، وتحديث ذمة المورد تتم كعملية واحدة (Atomic). |
| **BR-PUR-017** | الإضافة السريعة للمنتج (Quick Add) | إمكانية إدخال مادة جديدة بالاسم والباركود والكلفة من داخل الفاتورة دون مغادرة الشاشة. |
| **BR-PUR-018** | احتساب متوسط التكلفة المرجح (WAC) | $NewCost = \frac{(CurrentStock \times CurrentCost) + (NewQty \times NewCost)}{CurrentStock + NewQty}$. |

---

## الخطوة 1: مراجعة وتجهيز قاعدة البيانات (Prisma Schema) بما فيها الذمم

تأكد من وجود النماذج التالية في `prisma/schema.prisma`:

### 1. جدول الموردين (`suppliers`):
```prisma
model suppliers {
  id                String              @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  name              String              @db.VarChar(300)
  phone             String?             @db.VarChar(20)
  email             String?             @db.VarChar(150)
  address           String?
  tax_number        String?             @db.VarChar(50)
  balance           Decimal             @default(0) @db.Decimal(15, 2)
  credit_limit      Decimal             @default(0) @db.Decimal(15, 2)
  notes             String?
  is_active         Boolean             @default(true)
  created_at        DateTime            @default(now()) @db.Timestamptz(6)
  updated_at        DateTime            @default(now()) @db.Timestamptz(6)
  created_by        String?             @db.Uuid

  purchase_invoices purchase_invoices[]
  payment_vouchers  payment_vouchers[]
  creator           users?              @relation(fields: [created_by], references: [id], onDelete: SetNull)

  @@index([name])
}
```

### 2. جدول فواتير الشراء (`purchase_invoices`):
```prisma
model purchase_invoices {
  id                     String                   @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  invoice_number         String                   @unique @db.VarChar(50)
  supplier_id            String                   @db.Uuid
  warehouse_id           String                   @db.Uuid
  status                 purchase_status_enum     @default(APPROVED)
  payment_type           purchase_payment_enum    @default(CASH)
  subtotal               Decimal                  @default(0) @db.Decimal(15, 2)
  discount_amount        Decimal                  @default(0) @db.Decimal(15, 2)
  tax_amount             Decimal                  @default(0) @db.Decimal(15, 2)
  total                  Decimal                  @default(0) @db.Decimal(15, 2)
  paid_amount            Decimal                  @default(0) @db.Decimal(15, 2)
  due_amount             Decimal                  @default(0) @db.Decimal(15, 2)
  notes                  String?
  invoice_date           DateTime                 @default(now()) @db.Date
  created_at             DateTime                 @default(now()) @db.Timestamptz(6)
  updated_at             DateTime                 @default(now()) @db.Timestamptz(6)
  created_by             String?                  @db.Uuid

  supplier               suppliers                @relation(fields: [supplier_id], references: [id], onDelete: Restrict)
  warehouse              warehouses               @relation(fields: [warehouse_id], references: [id], onDelete: Restrict)
  creator                users?                   @relation(fields: [created_by], references: [id], onDelete: SetNull)
  purchase_invoice_items purchase_invoice_items[]
  payment_vouchers       payment_vouchers[]

  @@index([supplier_id])
  @@index([warehouse_id])
}
```

### 3. جدول أسطر فاتورة الشراء (`purchase_invoice_items`):
```prisma
model purchase_invoice_items {
  id                    String            @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  invoice_id            String            @db.Uuid
  variant_id            String            @db.Uuid
  unit_id               String            @db.Uuid
  quantity              Decimal           @db.Decimal(15, 3)
  quantity_in_base_unit Decimal           @db.Decimal(15, 3)
  unit_cost             Decimal           @db.Decimal(15, 4)
  discount_percent      Decimal           @default(0) @db.Decimal(5, 2)
  total_price           Decimal           @db.Decimal(15, 2)
  created_at            DateTime          @default(now()) @db.Timestamptz(6)

  invoice               purchase_invoices @relation(fields: [invoice_id], references: [id], onDelete: Cascade)
  variant               product_variants  @relation(fields: [variant_id], references: [id], onDelete: Restrict)
  unit                  units_of_measure  @relation(fields: [unit_id], references: [id], onDelete: Restrict)
}
```

### 4. جدول سندات الدفع والذمم (`payment_vouchers`):
```prisma
model payment_vouchers {
  id             String              @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  voucher_number String              @unique @db.VarChar(50)
  supplier_id    String?             @db.Uuid
  invoice_id     String?             @db.Uuid
  amount         Decimal             @db.Decimal(15, 2)
  payment_method payment_method_enum @default(CASH)
  voucher_date   DateTime            @default(now()) @db.Date
  notes          String?
  created_by     String?             @db.Uuid
  created_at     DateTime            @default(now()) @db.Timestamptz(6)

  supplier       suppliers?          @relation(fields: [supplier_id], references: [id], onDelete: Restrict)
  invoice        purchase_invoices?  @relation(fields: [invoice_id], references: [id], onDelete: SetNull)
  creator        users?              @relation(fields: [created_by], references: [id], onDelete: SetNull)

  @@index([supplier_id])
}
```

---

## الخطوة 2: موديول الموردين (Suppliers Module) بالكامل

المجلد: `src/modules/suppliers/`

### 1. الـ DTO لإنشاء مورد (`dto/create-supplier.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsEmail, IsNumber, Min } from 'class-validator';

export class CreateSupplierDto {
  @ApiProperty({ example: 'شركة النور للتجارة' })
  @IsNotEmpty({ message: 'اسم المورد مطلوب' })
  @IsString()
  name: string;

  @ApiPropertyOptional({ example: '07701234567' })
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiPropertyOptional({ example: 'supplier@alnoor.com' })
  @IsOptional()
  @IsEmail({}, { message: 'البريد الإلكتروني غير صالح' })
  email?: string;

  @ApiPropertyOptional({ example: 'بغداد - الشورجة' })
  @IsOptional()
  @IsString()
  address?: string;

  @ApiPropertyOptional({ example: 'TAX-987654' })
  @IsOptional()
  @IsString()
  tax_number?: string;

  @ApiPropertyOptional({ example: 10000000, description: 'الحد الائتماني بالدينار العراقي' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  credit_limit?: number;

  @ApiPropertyOptional({ example: 'مورد رئيسي للمواد الغذائية' })
  @IsOptional()
  @IsString()
  notes?: string;
}
```

### 2. الـ DTO لتعديل مورد (`dto/update-supplier.dto.ts`):
```typescript
import { PartialType } from '@nestjs/swagger';
import { CreateSupplierDto } from './create-supplier.dto';

export class UpdateSupplierDto extends PartialType(CreateSupplierDto) {}
```

### 3. ملف الـ Service (`suppliers.service.ts`):
```typescript
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateSupplierDto } from './dto/create-supplier.dto';
import { UpdateSupplierDto } from './dto/update-supplier.dto';

@Injectable()
export class SuppliersService {
  constructor(private prisma: PrismaService) {}

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
    const page = Number(query.page) || 1;
    const limit = Number(query.limit) || 20;
    const skip = (page - 1) * limit;

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

  // كشف حساب المورد التفصيلي (حركات الفواتير وسندات الصرف)
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
```

### 4. ملف الـ Controller (`suppliers.controller.ts`):
```typescript
import { Controller, Get, Post, Patch, Delete, Param, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { SuppliersService } from './suppliers.service';
import { CreateSupplierDto } from './dto/create-supplier.dto';
import { UpdateSupplierDto } from './dto/update-supplier.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('Suppliers (M04)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('suppliers')
export class SuppliersController {
  constructor(private readonly suppliersService: SuppliersService) {}

  @Post()
  @ApiOperation({ summary: 'إنشاء مورد جديد' })
  async create(@Body() dto: CreateSupplierDto, @Request() req: any) {
    const data = await this.suppliersService.create(dto, req.user?.id);
    return { success: true, data, message: 'تم إنشاء المورد بنجاح' };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة الموردين مع البحث والصفحات' })
  @ApiQuery({ name: 'search', required: false })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAll(@Query() query: any) {
    return this.suppliersService.findAll(query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'تفاصيل المورد' })
  async findOne(@Param('id') id: string) {
    const data = await this.suppliersService.findOne(id);
    return { success: true, data };
  }

  @Get(':id/statement')
  @ApiOperation({ summary: 'كشف حساب المورد (فواتير وسندات صرف والذمة الحالية)' })
  async getStatement(@Param('id') id: string) {
    const data = await this.suppliersService.getStatement(id);
    return { success: true, data };
  }

  @Patch(':id')
  @ApiOperation({ summary: 'تحديث بيانات المورد والحد الائتماني' })
  async update(@Param('id') id: string, @Body() dto: UpdateSupplierDto) {
    const data = await this.suppliersService.update(id, dto);
    return { success: true, data, message: 'تم تحديث المورد بنجاح' };
  }

  @Delete(':id')
  @ApiOperation({ summary: 'تعطيل المورد بعد التحقق من خلو ذمته المالية' })
  async remove(@Param('id') id: string) {
    const data = await this.suppliersService.remove(id);
    return { success: true, data, message: 'تم تعطيل المورد بنجاح' };
  }
}
```

### 5. ملف الـ Module (`suppliers.module.ts`):
```typescript
import { Module } from '@nestjs/common';
import { SuppliersService } from './suppliers.service';
import { SuppliersController } from './suppliers.controller';

@Module({
  controllers: [SuppliersController],
  providers: [SuppliersService],
  exports: [SuppliersService],
})
export class SuppliersModule {}
```

---

## الخطوة 3: موديول فواتير الشراء المباشرة (Purchases Module) بالكامل

المجلد: `src/modules/purchases/`

### 1. الـ DTO لإنشاء فاتورة الشراء (`dto/create-purchase.dto.ts`):
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
import { purchase_payment_enum } from '@prisma/client';

export class PurchaseItemDto {
  @ApiProperty({ example: 'uuid-product-variant-id' })
  @IsNotEmpty({ message: 'معرف الشكل/المنتج مطلوب' })
  @IsUUID()
  variant_id: string;

  @ApiProperty({ example: 'uuid-unit-of-measure-id' })
  @IsNotEmpty({ message: 'وحدة القياس مطلوبة' })
  @IsUUID()
  unit_id: string;

  @ApiProperty({ example: 10, description: 'الكمية المشتراة' })
  @IsNumber()
  @Min(0.001, { message: 'الكمية يجب أن تكون أكبر من صفر' })
  quantity: number;

  @ApiProperty({ example: 8500, description: 'سعر كلفة الوحدة' })
  @IsNumber()
  @Min(0)
  unit_cost: number;

  @ApiPropertyOptional({ example: 0, description: 'نسبة الخصم على السطر %' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  discount_percent?: number;
}

export class CreatePurchaseInvoiceDto {
  @ApiProperty({ example: 'uuid-supplier-id', description: 'معرف المورد' })
  @IsNotEmpty({ message: 'المورد مطلوب' })
  @IsUUID()
  supplier_id: string;

  @ApiProperty({ example: 'uuid-warehouse-id', description: 'المخزن المستلم' })
  @IsNotEmpty({ message: 'المخزن مطلوب' })
  @IsUUID()
  warehouse_id: string;

  @ApiProperty({ enum: purchase_payment_enum, example: purchase_payment_enum.CASH })
  @IsNotEmpty({ message: 'طريقة الدفع مطلوبة' })
  @IsEnum(purchase_payment_enum)
  payment_type: purchase_payment_enum;

  @ApiPropertyOptional({ example: 0, description: 'مبلغ الخصم الإجمالي على الفاتورة' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  discount_amount?: number;

  @ApiPropertyOptional({ example: 85000, description: 'المبلغ المدفوع فعلياً (في حال الدفع الجزئي أو النقدي)' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  paid_amount?: number;

  @ApiPropertyOptional({ example: 'فاتورة توريد مواد غذائية' })
  @IsOptional()
  @IsString()
  notes?: string;

  @ApiProperty({ type: [PurchaseItemDto], description: 'قائمة المواد المشتراة' })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => PurchaseItemDto)
  items: PurchaseItemDto[];
}
```

### 2. الـ DTO للإضافة السريعة لمادة جديدة (`dto/quick-add-item.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsNumber, Min } from 'class-validator';

export class QuickAddProductDto {
  @ApiProperty({ example: 'عصير تفاح طبيعي' })
  @IsNotEmpty({ message: 'اسم المادة مطلوب' })
  @IsString()
  name_ar: string;

  @ApiPropertyOptional({ example: '625987654321' })
  @IsOptional()
  @IsString()
  barcode?: string;

  @ApiProperty({ example: 10, description: 'الكمية' })
  @IsNumber()
  @Min(0.001)
  quantity: number;

  @ApiProperty({ example: 5000, description: 'سعر الكلفة' })
  @IsNumber()
  @Min(0)
  unit_cost: number;
}
```

### 3. ملف الـ Service (`purchases.service.ts`):
```typescript
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreatePurchaseInvoiceDto } from './dto/create-purchase.dto';
import { QuickAddProductDto } from './dto/quick-add-item.dto';
import { purchase_status_enum, purchase_payment_enum, price_type_enum } from '@prisma/client';

@Injectable()
export class PurchasesService {
  constructor(private prisma: PrismaService) {}

  private async generateInvoiceNumber(): Promise<string> {
    const today = new Date();
    const prefix = `PUR-${today.getFullYear()}${String(today.getMonth() + 1).padStart(2, '0')}-`;
    const count = await this.prisma.purchase_invoices.count();
    return `${prefix}${String(count + 1).padStart(4, '0')}`;
  }

  // ─── إنشاء فاتورة الشراء المباشرة والترحيل الذري ───────────────────────────
  async createDirectInvoice(dto: CreatePurchaseInvoiceDto, userId?: string) {
    if (!dto.items || dto.items.length === 0) {
      throw new BadRequestException('يجب إضافة مادة واحدة على الأقل في الفاتورة');
    }

    // 1. التحقق من وجود المورد والمخزن
    const [supplier, warehouse] = await Promise.all([
      this.prisma.suppliers.findUnique({ where: { id: dto.supplier_id } }),
      this.prisma.warehouses.findUnique({ where: { id: dto.warehouse_id } }),
    ]);
    if (!supplier) throw new NotFoundException('المورد غير موجود');
    if (!warehouse) throw new NotFoundException('المخزن غير موجود');

    // 2. حساب المجاميع المالية
    let subtotal = 0;
    for (const item of dto.items) {
      const lineDiscount = ((item.discount_percent || 0) / 100) * (item.quantity * item.unit_cost);
      subtotal += (item.quantity * item.unit_cost) - lineDiscount;
    }

    const discountAmount = Number(dto.discount_amount) || 0;
    const total = Math.max(0, subtotal - discountAmount);

    let paidAmount = 0;
    let dueAmount = 0;

    if (dto.payment_type === purchase_payment_enum.CASH) {
      paidAmount = total;
      dueAmount = 0;
    } else if (dto.payment_type === purchase_payment_enum.CREDIT) {
      paidAmount = 0;
      dueAmount = total;
    } else if (dto.payment_type === purchase_payment_enum.PARTIAL) {
      paidAmount = Number(dto.paid_amount) || 0;
      if (paidAmount > total) throw new BadRequestException('المبلغ المدفوع لا يمكن أن يتجاوز إجمالي الفاتورة');
      dueAmount = total - paidAmount;
    }

    // 3. التحقق من الحد الائتماني للمورد (BR-PUR-002)
    if (dueAmount > 0) {
      const newTotalBalance = Number(supplier.balance) + dueAmount;
      const creditLimit = Number(supplier.credit_limit);
      if (creditLimit > 0 && newTotalBalance > creditLimit) {
        throw new BadRequestException(`تجاوز الحد الائتماني للمورد! الحد المسموح: ${creditLimit}، الرصيد الحالي: ${supplier.balance}`);
      }
    }

    const invoiceNumber = await this.generateInvoiceNumber();

    // 4. تنفيذ العملية داخل Database Transaction ذرية
    return this.prisma.$transaction(async (tx) => {
      // أ. إنشاء سجل الفاتورة
      const invoice = await tx.purchase_invoices.create({
        data: {
          invoice_number: invoiceNumber,
          supplier_id: dto.supplier_id,
          warehouse_id: dto.warehouse_id,
          status: purchase_status_enum.APPROVED,
          payment_type: dto.payment_type,
          subtotal,
          discount_amount: discountAmount,
          total,
          paid_amount: paidAmount,
          due_amount: dueAmount,
          notes: dto.notes,
          created_by: userId,
        },
      });

      // ب. إدخال أسطر المواد وتحديث المخزون والتكلفة
      for (const item of dto.items) {
        const itemLineTotal = (item.quantity * item.unit_cost) - (((item.discount_percent || 0) / 100) * (item.quantity * item.unit_cost));

        await tx.purchase_invoice_items.create({
          data: {
            invoice_id: invoice.id,
            variant_id: item.variant_id,
            unit_id: item.unit_id,
            quantity: item.quantity,
            quantity_in_base_unit: item.quantity,
            unit_cost: item.unit_cost,
            discount_percent: item.discount_percent || 0,
            total_price: itemLineTotal,
          },
        });

        // زيادة رصيد المخزن المحدد في stock_levels
        const stock = await tx.stock_levels.findUnique({
          where: {
            variant_id_warehouse_id: {
              variant_id: item.variant_id,
              warehouse_id: dto.warehouse_id,
            },
          },
        });

        const currentQty = stock ? Number(stock.quantity_on_hand) : 0;
        const newQty = currentQty + Number(item.quantity);

        await tx.stock_levels.upsert({
          where: {
            variant_id_warehouse_id: {
              variant_id: item.variant_id,
              warehouse_id: dto.warehouse_id,
            },
          },
          update: { quantity_on_hand: newQty, updated_at: new Date() },
          create: {
            variant_id: item.variant_id,
            warehouse_id: dto.warehouse_id,
            quantity_on_hand: item.quantity,
          },
        });

        // تسجيل حركة دخول مخزني
        await tx.inventory_movements.create({
          data: {
            movement_type: 'PURCHASE_IN' as any,
            variant_id: item.variant_id,
            to_warehouse_id: dto.warehouse_id,
            quantity: item.quantity,
            unit_cost: item.unit_cost,
            total_cost: itemLineTotal,
            reference_type: 'PURCHASE_INVOICE',
            reference_id: invoice.id,
            created_by: userId,
          },
        });

        // تحديث متوسط التكلفة المرجح (WAC)
        const variant = await tx.product_variants.findUnique({ where: { id: item.variant_id } });
        if (variant) {
          const oldCost = Number(variant.weighted_avg_cost) || 0;
          const weightedCost = newQty > 0
            ? ((currentQty * oldCost) + (Number(item.quantity) * Number(item.unit_cost))) / newQty
            : Number(item.unit_cost);

          await tx.product_variants.update({
            where: { id: item.variant_id },
            data: {
              weighted_avg_cost: weightedCost,
              last_purchase_price: item.unit_cost,
              updated_at: new Date(),
            },
          });
        }
      }

      // ج. تحديث رصيد ذمة المورد بالمبلغ المتبقي
      if (dueAmount > 0) {
        await tx.suppliers.update({
          where: { id: dto.supplier_id },
          data: {
            balance: { increment: dueAmount },
            updated_at: new Date(),
          },
        });
      }

      return invoice;
    });
  }

  // ─── الإضافة السريعة لمادة جديدة من داخل الفاتورة (Quick Add) ─────────────
  async quickAddProduct(dto: QuickAddProductDto, userId?: string) {
    // 1. فحص وجود وحدة قياس وتصنيف افتراضيين
    let [defaultUnit, defaultCategory] = await Promise.all([
      this.prisma.units_of_measure.findFirst({ where: { is_base_unit: true, is_active: true } }),
      this.prisma.categories.findFirst({ where: { is_active: true } }),
    ]);

    if (!defaultUnit) {
      defaultUnit = await this.prisma.units_of_measure.create({
        data: { name_ar: 'قطعة', is_base_unit: true },
      });
    }
    if (!defaultCategory) {
      defaultCategory = await this.prisma.categories.create({
        data: { name_ar: 'عام' },
      });
    }

    return this.prisma.$transaction(async (tx) => {
      // إنشاء المنتج
      const product = await tx.products.create({
        data: {
          name_ar: dto.name_ar,
          barcode: dto.barcode,
          category_id: defaultCategory.id,
          base_unit_id: defaultUnit.id,
          created_by: userId,
        },
      });

      // إنشاء الشكل Variant والأسعار التقديرية
      const variant = await tx.product_variants.create({
        data: {
          product_id: product.id,
          barcode: dto.barcode,
          weighted_avg_cost: dto.unit_cost,
          last_purchase_price: dto.unit_cost,
        },
      });

      // تسجيل سعر الكلفة
      await tx.product_prices.create({
        data: {
          variant_id: variant.id,
          unit_id: defaultUnit.id,
          price_type: price_type_enum.COST,
          price: dto.unit_cost,
        },
      });

      return {
        variant_id: variant.id,
        product_id: product.id,
        name_ar: product.name_ar,
        barcode: product.barcode,
        unit_id: defaultUnit.id,
        unit_name: defaultUnit.name_ar,
        unit_cost: dto.unit_cost,
        quantity: dto.quantity,
      };
    });
  }

  // ─── استرجاع قائمة فواتير الشراء ──────────────────────────────────────────
  async findAll(query: any) {
    const page = Number(query.page) || 1;
    const limit = Number(query.limit) || 20;
    const skip = (page - 1) * limit;

    const where: any = {};
    if (query.supplier_id) where.supplier_id = query.supplier_id;
    if (query.warehouse_id) where.warehouse_id = query.warehouse_id;
    if (query.payment_type) where.payment_type = query.payment_type;
    if (query.search) {
      where.OR = [
        { invoice_number: { contains: query.search, mode: 'insensitive' } },
        { supplier: { name: { contains: query.search, mode: 'insensitive' } } },
      ];
    }

    const [total, data] = await Promise.all([
      this.prisma.purchase_invoices.count({ where }),
      this.prisma.purchase_invoices.findMany({
        where,
        skip,
        take: limit,
        include: {
          supplier: { select: { id: true, name: true, phone: true } },
          warehouse: { select: { id: true, name: true } },
          _count: { select: { purchase_invoice_items: true } },
        },
        orderBy: { created_at: 'desc' },
      }),
    ]);

    return {
      data,
      meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
    };
  }

  // ─── تفاصيل فاتورة واحدة ──────────────────────────────────────────────────
  async findOne(id: string) {
    const invoice = await this.prisma.purchase_invoices.findUnique({
      where: { id },
      include: {
        supplier: true,
        warehouse: true,
        purchase_invoice_items: {
          include: {
            variant: { include: { products: true } },
            unit: true,
          },
        },
      },
    });
    if (!invoice) throw new NotFoundException('فاتورة الشراء غير موجودة');
    return invoice;
  }
}
```

### 4. ملف الـ Controller (`purchases.controller.ts`):
```typescript
import { Controller, Get, Post, Param, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { PurchasesService } from './purchases.service';
import { CreatePurchaseInvoiceDto } from './dto/create-purchase.dto';
import { QuickAddProductDto } from './dto/quick-add-item.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('Purchases (M04)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('purchases')
export class PurchasesController {
  constructor(private readonly purchasesService: PurchasesService) {}

  @Post()
  @ApiOperation({ summary: 'إنشاء فاتورة شراء مباشرة وترحيلها للمخزن والذمم فوراً' })
  async createDirect(@Body() dto: CreatePurchaseInvoiceDto, @Request() req: any) {
    const data = await this.purchasesService.createDirectInvoice(dto, req.user?.id);
    return { success: true, data, message: 'تم حفظ فاتورة الشراء وترحيل المواد إلى المخزن بنجاح' };
  }

  @Post('quick-product')
  @ApiOperation({ summary: 'الإضافة السريعة لمادة جديدة من نافذة الفاتورة المنبثقة' })
  async quickAddProduct(@Body() dto: QuickAddProductDto, @Request() req: any) {
    const data = await this.purchasesService.quickAddProduct(dto, req.user?.id);
    return { success: true, data, message: 'تم إنشاء المادة بنجاح وإضافتها للفاتورة' };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة فواتير الشراء مع الفلاتر' })
  @ApiQuery({ name: 'supplier_id', required: false })
  @ApiQuery({ name: 'warehouse_id', required: false })
  @ApiQuery({ name: 'payment_type', required: false })
  @ApiQuery({ name: 'search', required: false })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAll(@Query() query: any) {
    return this.purchasesService.findAll(query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'تفاصيل فاتورة شراء مع كافة المواد' })
  async findOne(@Param('id') id: string) {
    const data = await this.purchasesService.findOne(id);
    return { success: true, data };
  }
}
```

### 5. ملف الـ Module (`purchases.module.ts`):
```typescript
import { Module } from '@nestjs/common';
import { PurchasesService } from './purchases.service';
import { PurchasesController } from './purchases.controller';

@Module({
  controllers: [PurchasesController],
  providers: [PurchasesService],
  exports: [PurchasesService],
})
export class PurchasesModule {}
```

---

## الخطوة 4: موديول دفعات الموردين وإدارة الذمم (Supplier Payments & Dues Module)

المجلد: `src/modules/supplier-payments/`

### 1. الـ DTO لسند الدفع (`dto/create-supplier-payment.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsUUID, IsNumber, IsEnum, IsOptional, IsString, Min } from 'class-validator';
import { payment_method_enum } from '@prisma/client';

export class CreateSupplierPaymentDto {
  @ApiProperty({ example: 'uuid-supplier-id' })
  @IsNotEmpty({ message: 'المورد مطلوب' })
  @IsUUID()
  supplier_id: string;

  @ApiPropertyOptional({ example: 'uuid-purchase-invoice-id', description: 'إذا كان السند مخصصاً لفاتورة معينة' })
  @IsOptional()
  @IsUUID()
  invoice_id?: string;

  @ApiProperty({ example: 500000, description: 'المبلغ المسدد بالدينار' })
  @IsNumber()
  @Min(1, { message: 'المبلغ يجب أن يكون أكبر من الصفر' })
  amount: number;

  @ApiProperty({ enum: payment_method_enum, example: payment_method_enum.CASH })
  @IsNotEmpty()
  @IsEnum(payment_method_enum)
  payment_method: payment_method_enum;

  @ApiPropertyOptional({ example: 'دفعة سداد نقدية' })
  @IsOptional()
  @IsString()
  notes?: string;
}
```

### 2. ملف الـ Service (`supplier-payments.service.ts`):
```typescript
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateSupplierPaymentDto } from './dto/create-supplier-payment.dto';

@Injectable()
export class SupplierPaymentsService {
  constructor(private prisma: PrismaService) {}

  private async generateVoucherNumber(): Promise<string> {
    const today = new Date();
    const prefix = `PAY-${today.getFullYear()}${String(today.getMonth() + 1).padStart(2, '0')}-`;
    const count = await this.prisma.payment_vouchers.count();
    return `${prefix}${String(count + 1).padStart(4, '0')}`;
  }

  // ─── تسجيل سند دفع للمورد وخفض رصيد الذمة ─────────────────────────────────
  async createPayment(dto: CreateSupplierPaymentDto, userId?: string) {
    const supplier = await this.prisma.suppliers.findUnique({ where: { id: dto.supplier_id } });
    if (!supplier) throw new NotFoundException('المورد غير موجود');

    const currentBalance = Number(supplier.balance);
    if (currentBalance <= 0) {
      throw new BadRequestException('المورد لا يمتلك أي ذمة مالية مستحقة للسداد');
    }

    if (dto.amount > currentBalance) {
      throw new BadRequestException(`مبلغ الدفعة (${dto.amount}) أكبر من إجمالي ذمة المورد (${currentBalance})`);
    }

    const voucherNumber = await this.generateVoucherNumber();

    return this.prisma.$transaction(async (tx) => {
      // 1. إنشاء سند الصرف
      const voucher = await tx.payment_vouchers.create({
        data: {
          voucher_number: voucherNumber,
          supplier_id: dto.supplier_id,
          invoice_id: dto.invoice_id,
          amount: dto.amount,
          payment_method: dto.payment_method,
          notes: dto.notes,
          created_by: userId,
        },
      });

      // 2. خفض رصيد ذمة المورد الإجمالي
      await tx.suppliers.update({
        where: { id: dto.supplier_id },
        data: {
          balance: { decrement: dto.amount },
          updated_at: new Date(),
        },
      });

      // 3. إذا كان السداد مخصصاً لفاتورة معينة
      if (dto.invoice_id) {
        await tx.purchase_invoices.update({
          where: { id: dto.invoice_id },
          data: {
            paid_amount: { increment: dto.amount },
            due_amount: { decrement: dto.amount },
            updated_at: new Date(),
          },
        });
      }

      return voucher;
    });
  }

  async findAll(query: { supplier_id?: string; page?: number; limit?: number }) {
    const page = Number(query.page) || 1;
    const limit = Number(query.limit) || 20;
    const skip = (page - 1) * limit;

    const where: any = {};
    if (query.supplier_id) where.supplier_id = query.supplier_id;

    const [total, data] = await Promise.all([
      this.prisma.payment_vouchers.count({ where }),
      this.prisma.payment_vouchers.findMany({
        where,
        skip,
        take: limit,
        include: {
          supplier: { select: { id: true, name: true } },
          invoice: { select: { id: true, invoice_number: true } },
        },
        orderBy: { created_at: 'desc' },
      }),
    ]);

    return {
      data,
      meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
    };
  }
}
```

### 3. ملف الـ Controller (`supplier-payments.controller.ts`):
```typescript
import { Controller, Get, Post, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { SupplierPaymentsService } from './supplier-payments.service';
import { CreateSupplierPaymentDto } from './dto/create-supplier-payment.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('Supplier Payments (M04)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('supplier-payments')
export class SupplierPaymentsController {
  constructor(private readonly paymentsService: SupplierPaymentsService) {}

  @Post()
  @ApiOperation({ summary: 'تسجيل سند دفع لمورد وخفض رصيد الذمة' })
  async createPayment(@Body() dto: CreateSupplierPaymentDto, @Request() req: any) {
    const data = await this.paymentsService.createPayment(dto, req.user?.id);
    return { success: true, data, message: 'تم تسجيل سند الدفع وخفض رصيد الذمة بنجاح' };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة سندات الدفع مع إمكانية الفلترة بالمورد' })
  @ApiQuery({ name: 'supplier_id', required: false })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAll(@Query() query: any) {
    return this.paymentsService.findAll(query);
  }
}
```

### 4. ملف الـ Module (`supplier-payments.module.ts`):
```typescript
import { Module } from '@nestjs/common';
import { SupplierPaymentsService } from './supplier-payments.service';
import { SupplierPaymentsController } from './supplier-payments.controller';

@Module({
  controllers: [SupplierPaymentsController],
  providers: [SupplierPaymentsService],
  exports: [SupplierPaymentsService],
})
export class SupplierPaymentsModule {}
```

---

## الخطوة 5: التسجيل الكامل في AppModule

افتح [app.module.ts](file:///c:/Users/FWZ/Documents/sayler/syler-backend/src/app.module.ts) وسجل الموديولات الثلاثة:

```typescript
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { PrismaModule } from './prisma/prisma.module';
// M01
import { UsersModule } from './modules/users/users.module';
import { AuthModule } from './modules/auth/auth.module';
// M02
import { CompanyModule } from './modules/company/company.module';
import { BranchesModule } from './modules/branches/branches.module';
import { WarehousesModule } from './modules/warehouses/warehouses.module';
import { OrganizationModule } from './modules/organization/organization.module';
// M03
import { UnitsModule } from './modules/units/units.module';
import { CategoriesModule } from './modules/categories/categories.module';
import { ProductsModule } from './modules/products/products.module';
// M04 ── الموردون والمشتريات والذمم
import { SuppliersModule } from './modules/suppliers/suppliers.module';
import { PurchasesModule } from './modules/purchases/purchases.module';
import { SupplierPaymentsModule } from './modules/supplier-payments/supplier-payments.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    UsersModule,
    AuthModule,
    CompanyModule,
    BranchesModule,
    WarehousesModule,
    OrganizationModule,
    UnitsModule,
    CategoriesModule,
    ProductsModule,
    // M04
    SuppliersModule,
    PurchasesModule,
    SupplierPaymentsModule,
  ],
})
export class AppModule {}
```

---

## الخطوة 6: خطة الاختبار والفحص الشامل (Swagger Checklist)

افتح `http://localhost:3000/api/docs` واختبر السيناريوهات الأربعة الأساسية:

### ✅ سيناريو 1: إنشاء مورد مع حد ائتماني
- [ ] استدعاء `POST /api/v1/suppliers` لإنشاء مورد باسم "شركة النور للتجارة" بحد ائتماني `10,000,000 د.ع`.
- [ ] استدعاء `GET /api/v1/suppliers` والتأكد من ظهوره برصيد `0`.

### ✅ سيناريو 2: شراء مباشر نقدي (CASH)
- [ ] إنشاء فاتورة شراء نقدي عبر `POST /api/v1/purchases` بمبلغ `100,000 د.ع`.
- [ ] التأكد من أن `paid_amount = 100000` و `due_amount = 0`.
- [ ] التأكد من زيادة كمية المواد في المخزن المختار مباشرة.
- [ ] التأكد من بقاء رصيد ذمة المورد `0`.

### ✅ سيناريو 3: شراء مباشر آجل (CREDIT) ونشوء الذمة
- [ ] إنشاء فاتورة شراء آجل عبر `POST /api/v1/purchases` بمبلغ `1,500,000 د.ع`.
- [ ] التأكد من أن `paid_amount = 0` و `due_amount = 1500000`.
- [ ] التأكد من زيادة رصيد ذمة المورد ليصبح `1,500,000 د.ع`.
- [ ] التأكد من زيادة كميات المخزون وتحديث المتوسط المرجح للتكلفة `weighted_avg_cost`.

### ✅ سيناريو 4: سداد دفعة للمورد وخفض الذمة
- [ ] استدعاء `POST /api/v1/supplier-payments` لسداد مبلغ `500,000 د.ع` للمورد.
- [ ] استدعاء `GET /api/v1/suppliers/:id/statement` (كشف الحساب) والتأكد من انخفاض رصيد ذمة المورد إلى `1,000,000 د.ع`، وظهور الفواتير وسند الصرف بوضوح!

---

> 🚀 **الملف محدّث وجاهز بالكامل!** يمكنك الآن البدء بتنفيذ ملفات المهمة الأولى (`SuppliersModule`) وسأتابع معك خطوة بخطوة!
