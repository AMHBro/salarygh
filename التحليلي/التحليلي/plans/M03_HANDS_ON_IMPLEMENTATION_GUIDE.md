# 📘 الدليل التطبيقي الشامل لتنفيذ موديول M03 (المنتجات والبيانات الأساسية)
### Hands-On Implementation Guide — Sayler Backend (NestJS + Prisma)

> **الهدف من هذا الدليل**: تمكينك من بناء موديول **M03 (المنتجات والأصناف والبيانات الأساسية)** بيدك خطوة بخطوة، وفهم قواعد العمل، التصنيفات الهرمية، الأشكال والمتغيرات (Variants)، وحدات القياس، ومصفوفة الأسعار الأربعة.

---

## 📑 فهرس المحتويات
1. [نظرة عامة والقرارات المعمارية لـ M03](#1-نظرة-عامة-والقرارات-المعمارية-لـ-m03)
2. [قواعد العمل الحاكمة (Business Rules)](#2-قواعد-العمل-الحاكمة-business-rules)
3. [الخطوة 1: مراجعة وتجهيز قاعدة البيانات (Prisma Schema)](#الخطوة-1-مراجعة-وتجهيز-قاعدة-البيانات-prisma-schema)
4. [الخطوة 2: موديول وحدات القياس (Units of Measure Module)](#الخطوة-2-موديول-وحدات-القياس-units-of-measure-module)
5. [الخطوة 3: موديول التصنيفات الهرمية (Categories Module — Self Join)](#الخطوة-3-موديول-التصنيفات-الهرمية-categories-module--self-join)
6. [الخطوة 4: موديول المنتجات والأشكال (Products & Variants Module)](#الخطوة-4-موديول-المنتجات-والأشكال-products--variants-module)
7. [الخطوة 5: موديول الأسعار ومؤشرات لوحة التحكم (Pricing & KPI Dashboard)](#الخطوة-5-موديول-الأسعار-ومؤشرات-لوحة-التحكم-pricing--kpi-dashboard)
8. [الخطوة 6: التسجيل في AppModule](#الخطوة-6-التسجيل-في-appmodule)
9. [الخطوة 7: خطة الاختبار والفحص الشامل (Swagger Checklist)](#الخطوة-7-خطة-الاختبار-والفحص-الشامل-swagger-checklist)

---

## 1. نظرة عامة والقرارات المعمارية لـ M03

موديول **M03** هو المصدر المركزي لتعريف كل مادة تباع أو تشترى أو تخزن:

```
               ┌─────────────────────────────────────────┐
               │    شجرة التصنيفات (Categories Tree)    │ (Self-Join: رئيسي ➔ فرعي)
               └────────────────────┬────────────────────┘
                                    │
               ┌────────────────────▼────────────────────┐
               │         قالب المنتج (Product)          │ (اسم، تصنيف، وحدة أساسية)
               │         [SIMPLE أو VARIABLE]            │
               └────────────────────┬────────────────────┘
                                    │ 1:N
               ┌────────────────────▼────────────────────┐
               │      الأشكال والمتغيرات (Variants)      │ (ألوان، أحجام، باركود فريد)
               └──────┬───────────────────────────┬──────┘
                      │ 1:N                       │ 1:N
       ┌──────────────▼──────────────┐     ┌──────▼──────────────────────┐
       │   مصفوفة الأسعار (Prices)   │     │  وحدات القياس والتحويلات    │
       │ (مفرد، جملة، مندوب، كلفة)  │     │  (قطعة = 1، كارتون = 24)    │
       └─────────────────────────────┘     └─────────────────────────────┘
```

---

## 2. قواعد العمل الحاكمة (Business Rules)

| الرمز | القاعدة البرمجية | كيف تطبقها في الكود؟ |
|---|---|---|
| **BR-PRD-001** | كود وباركود فريد لكل منتج وشكل | الحقول `sku` و `barcode` فريدة (`@unique`) في قاعدة البيانات. |
| **BR-PRD-002** | المنتج إما بسيط (`SIMPLE`) أو متعدد الأشكال (`VARIABLE`) | في المنتج البسيط ينشئ النظام Variant افتراضي واحد تلقائياً؛ وفي المتغير ينشئ أشكالاً متعددة حسب الخصائص. |
| **BR-PRD-004** | منع الدورات الدائرية في شجرة التصنيفات | عند تعديل تصنيف لا يمكن اختيار التصنيف نفسه أو أحد أبنائه كـ `parent_id`. |
| **BR-PRD-005** | لكل منتج وحدة قياس أساسية (`base_unit_id`) | جميع كميات التخزين والحسابات تُخزن بالوحدة الأساسية (مثل قطعة). |
| **BR-PRD-006** | معاملات التحويل موجبة وأكبر من الصفر | التحقق من أن `conversion_factor > 0` (مثل: 1 كارتون = 12 قطعة). |
| **BR-PRD-007** | منع بيع أي منتج بسعر أقل من التكلفة | التحقق عند إدخال الأسعار أن `retail_price >= cost_price` و `wholesale_price >= cost_price`. |
| **BR-PRD-009** | المنتج الحساس (`is_sensitive`) يتطلب اعتماد الإدارة | إذا كان `is_sensitive = true` تبدأ حالته بـ `PENDING_APPROVAL` ولا يصبح `ACTIVE` إلا بموافقة الإدارة. |
| **BR-PRD-010** | صانع طلب الاعتماد لا يعتمده بنفسه | منع المستخدم المنشئ من تمرير `approve` لمنتجه الحساس. |
| **BR-PRD-020** | المنتجات غير النشطة لا تظهر في عمليات البيع والشراء | الفلترة الافتراضية في شاشات الكاشير والشراء تكون `is_active: true`. |

---

## الخطوة 1: مراجعة وتجهيز قاعدة البيانات (Prisma Schema)

تأكد من وجود النماذج التالية في `prisma/schema.prisma`:

### 1. جدول التصنيفات الهرمية (`categories`):
```prisma
model categories {
  id               String       @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  name_ar          String       @db.VarChar(200)
  name_en          String?      @db.VarChar(200)
  parent_id        String?      @db.Uuid
  level            Int          @default(0)
  path             String?
  image_url        String?
  order_index      Int          @default(0)
  is_active        Boolean      @default(true)
  created_at       DateTime     @default(now()) @db.Timestamptz(6)
  updated_at       DateTime     @default(now()) @db.Timestamptz(6)

  parent           categories?  @relation("CategoryHierarchy", fields: [parent_id], references: [id], onDelete: Restrict)
  children         categories[] @relation("CategoryHierarchy")
  products         products[]

  @@index([parent_id])
}
```

### 2. جدول وحدات القياس (`units_of_measure`):
```prisma
model units_of_measure {
  id                String             @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  name_ar           String             @db.VarChar(100)
  name_en           String?            @db.VarChar(100)
  symbol            String?            @db.VarChar(20)
  parent_unit_id    String?            @db.Uuid
  conversion_factor Decimal            @default(1) @db.Decimal(15, 6)
  is_base_unit      Boolean            @default(false)
  is_active         Boolean            @default(true)
  created_at        DateTime           @default(now()) @db.Timestamptz(6)

  parent_unit       units_of_measure?  @relation("UnitHierarchy", fields: [parent_unit_id], references: [id], onDelete: Restrict)
  sub_units         units_of_measure[] @relation("UnitHierarchy")
  products          products[]
  product_prices    product_prices[]
}
```

### 3. جدول المنتجات الأساسي (`products`):
```prisma
model products {
  id              String             @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  sku             String?            @unique @db.VarChar(100)
  barcode         String?            @unique @db.VarChar(100)
  name_ar         String             @db.VarChar(300)
  name_en         String?            @db.VarChar(300)
  category_id     String?            @db.Uuid
  description     String?
  base_unit_id    String             @db.Uuid
  has_variants    Boolean            @default(false)
  has_serial      Boolean            @default(false)
  has_expiry      Boolean            @default(false)
  is_sensitive    Boolean            @default(false)
  image_url       String?
  min_stock_level Decimal            @default(0) @db.Decimal(15, 3)
  is_active       Boolean            @default(true)
  status          org_status_enum    @default(ACTIVE)
  created_by      String?            @db.Uuid
  created_at      DateTime           @default(now()) @db.Timestamptz(6)
  updated_at      DateTime           @default(now()) @db.Timestamptz(6)

  category        categories?        @relation(fields: [category_id], references: [id], onDelete: SetNull)
  base_unit       units_of_measure   @relation(fields: [base_unit_id], references: [id], onDelete: Restrict)
  creator         users?             @relation(fields: [created_by], references: [id], onDelete: SetNull)
  variants        product_variants[]

  @@index([category_id])
  @@index([barcode])
  @@index([is_active])
}
```

### 4. جدول الأشكال والمتغيرات (`product_variants`):
```prisma
model product_variants {
  id                  String           @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  product_id          String           @db.Uuid
  sku                 String?          @unique @db.VarChar(100)
  barcode             String?          @unique @db.VarChar(100)
  attributes          Json             @default("{}")
  weighted_avg_cost   Decimal          @default(0) @db.Decimal(15, 4)
  last_purchase_price Decimal          @default(0) @db.Decimal(15, 4)
  is_active           Boolean          @default(true)
  created_at          DateTime         @default(now()) @db.Timestamptz(6)
  updated_at          DateTime         @default(now()) @db.Timestamptz(6)

  product             products         @relation(fields: [product_id], references: [id], onDelete: Cascade)
  prices              product_prices[]
  stock_levels        stock_levels[]

  @@index([product_id])
  @@index([barcode])
}
```

### 5. جدول مصفوفة الأسعار (`product_prices`):
```prisma
model product_prices {
  id         String           @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  variant_id String           @db.Uuid
  price_type price_type_enum
  unit_id    String           @db.Uuid
  price      Decimal          @db.Decimal(15, 4)
  is_active  Boolean          @default(true)
  updated_at DateTime         @default(now()) @db.Timestamptz(6)

  variant    product_variants @relation(fields: [variant_id], references: [id], onDelete: Cascade)
  unit       units_of_measure @relation(fields: [unit_id], references: [id], onDelete: Restrict)

  @@unique([variant_id, price_type, unit_id])
}
```

---

## الخطوة 2: موديول وحدات القياس (Units of Measure Module)

المسار: `src/modules/units/`

### 1. الـ DTO (`dto/create-unit.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsBoolean, IsNumber, IsUUID, Min } from 'class-validator';

export class CreateUnitDto {
  @ApiProperty({ example: 'قطعة' })
  @IsNotEmpty({ message: 'اسم الوحدة بالعربية مطلوب' })
  @IsString()
  name_ar: string;

  @ApiPropertyOptional({ example: 'Piece' })
  @IsOptional()
  @IsString()
  name_en?: string;

  @ApiPropertyOptional({ example: 'PCS' })
  @IsOptional()
  @IsString()
  symbol?: string;

  @ApiPropertyOptional({ example: 'uuid-of-base-unit' })
  @IsOptional()
  @IsUUID()
  parent_unit_id?: string;

  @ApiPropertyOptional({ example: 1, description: 'معامل التحويل مقابل الوحدة الأساسية' })
  @IsOptional()
  @IsNumber()
  @Min(0.000001, { message: 'معامل التحويل يجب أن يكون أكبر من الصفر' })
  conversion_factor?: number;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  is_base_unit?: boolean;
}
```

### 2. الـ Service (`units.service.ts`):
```typescript
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateUnitDto } from './dto/create-unit.dto';

@Injectable()
export class UnitsService {
  constructor(private prisma: PrismaService) {}

  async create(dto: CreateUnitDto) {
    return this.prisma.units_of_measure.create({ data: dto });
  }

  async findAll() {
    return this.prisma.units_of_measure.findMany({
      where: { is_active: true },
      include: { parent_unit: { select: { id: true, name_ar: true } } },
      orderBy: { name_ar: 'asc' },
    });
  }

  async findOne(id: string) {
    const unit = await this.prisma.units_of_measure.findUnique({
      where: { id },
      include: { sub_units: true },
    });
    if (!unit) throw new NotFoundException('وحدة القياس غير موجودة');
    return unit;
  }
}
```

---

## الخطوة 3: موديول التصنيفات الهرمية (Categories Module — Self Join)

المسار: `src/modules/categories/`

### 1. الـ DTO (`dto/create-category.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsUUID, IsNumber } from 'class-validator';

export class CreateCategoryDto {
  @ApiProperty({ example: 'مواد غذائية' })
  @IsNotEmpty({ message: 'اسم التصنيف مطلوب' })
  @IsString()
  name_ar: string;

  @ApiPropertyOptional({ example: 'Food & Beverages' })
  @IsOptional()
  @IsString()
  name_en?: string;

  @ApiPropertyOptional({ example: 'uuid-parent-category', description: 'التصنيف الأب (فارغ إذا كان رئيسياً)' })
  @IsOptional()
  @IsUUID()
  parent_id?: string;

  @ApiPropertyOptional({ example: 'https://example.com/cat.png' })
  @IsOptional()
  @IsString()
  image_url?: string;

  @ApiPropertyOptional({ example: 0 })
  @IsOptional()
  @IsNumber()
  order_index?: number;
}
```

### 2. الـ Service (`categories.service.ts`):
```typescript
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateCategoryDto } from './dto/create-category.dto';

@Injectable()
export class CategoriesService {
  constructor(private prisma: PrismaService) {}

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
}
```

---

## الخطوة 4: موديول المنتجات والأشكال (Products & Variants Module)

المسار: `src/modules/products/`

### 1. الـ DTO لإنشاء منتج كامل مع الأسعار والأشكال (`dto/create-product.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsNotEmpty,
  IsString,
  IsOptional,
  IsUUID,
  IsBoolean,
  IsNumber,
  IsArray,
  ValidateNested,
  Min,
} from 'class-validator';
import { Type } from 'class-transformer';

export class ProductPricingDto {
  @ApiProperty({ example: 8500, description: 'سعر الكلفة' })
  @IsNumber()
  @Min(0)
  cost_price: number;

  @ApiProperty({ example: 9500, description: 'سعر المندوب' })
  @IsNumber()
  @Min(0)
  rep_price: number;

  @ApiProperty({ example: 10500, description: 'سعر الجملة' })
  @IsNumber()
  @Min(0)
  wholesale_price: number;

  @ApiProperty({ example: 12000, description: 'سعر المفرد' })
  @IsNumber()
  @Min(0)
  retail_price: number;
}

export class CreateProductVariantDto {
  @ApiPropertyOptional({ example: '625123456001' })
  @IsOptional()
  @IsString()
  barcode?: string;

  @ApiPropertyOptional({ example: 'SKU-001' })
  @IsOptional()
  @IsString()
  sku?: string;

  @ApiPropertyOptional({ example: { color: 'أحمر', size: 'XL' } })
  @IsOptional()
  attributes?: any;

  @ApiProperty({ type: ProductPricingDto })
  @ValidateNested()
  @Type(() => ProductPricingDto)
  pricing: ProductPricingDto;
}

export class CreateProductDto {
  @ApiProperty({ example: 'منتج تجريبي 1' })
  @IsNotEmpty({ message: 'اسم المنتج مطلوب' })
  @IsString()
  name_ar: string;

  @ApiPropertyOptional({ example: 'Product 1' })
  @IsOptional()
  @IsString()
  name_en?: string;

  @ApiPropertyOptional({ example: '625123456001', description: 'الباركود الأساسي' })
  @IsOptional()
  @IsString()
  barcode?: string;

  @ApiProperty({ example: 'uuid-category-id' })
  @IsNotEmpty({ message: 'التصنيف مطلوب' })
  @IsUUID()
  category_id: string;

  @ApiProperty({ example: 'uuid-base-unit-id' })
  @IsNotEmpty({ message: 'وحدة القياس الأساسية مطلوبة' })
  @IsUUID()
  base_unit_id: string;

  @ApiPropertyOptional({ example: 5 })
  @IsOptional()
  @IsNumber()
  min_stock_level?: number;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  has_variants?: boolean;

  @ApiPropertyOptional({ type: ProductPricingDto, description: 'الأسعار في حال كان منتجاً بسيطاً بدون Variants' })
  @IsOptional()
  @ValidateNested()
  @Type(() => ProductPricingDto)
  pricing?: ProductPricingDto;

  @ApiPropertyOptional({ type: [CreateProductVariantDto], description: 'قائمة الأشكال إذا كان متعدد الأشكال' })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreateProductVariantDto)
  variants?: CreateProductVariantDto[];
}
```

### 2. الـ Service (`products.service.ts`):
```typescript
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateProductDto } from './dto/create-product.dto';
import { price_type_enum } from '@prisma/client';

@Injectable()
export class ProductsService {
  constructor(private prisma: PrismaService) {}

  async create(dto: CreateProductDto, userId?: string) {
    // 1. التحقق من وجود التصنيف ووحدة القياس
    const [category, unit] = await Promise.all([
      this.prisma.categories.findUnique({ where: { id: dto.category_id } }),
      this.prisma.units_of_measure.findUnique({ where: { id: dto.base_unit_id } }),
    ]);
    if (!category) throw new NotFoundException('التصنيف غير موجود');
    if (!unit) throw new NotFoundException('وحدة القياس غير موجودة');

    // 2. استخدام Transaction لحفظ المنتج والأشكال والأسعار معاً
    return this.prisma.$transaction(async (tx) => {
      // إنشاء سجل المنتج
      const product = await tx.products.create({
        data: {
          name_ar: dto.name_ar,
          name_en: dto.name_en,
          barcode: dto.barcode,
          category_id: dto.category_id,
          base_unit_id: dto.base_unit_id,
          min_stock_level: dto.min_stock_level || 0,
          has_variants: dto.has_variants || false,
          created_by: userId,
        },
      });

      // إذا كان منتجاً بسيطاً (Single Variant)
      if (!dto.has_variants && dto.pricing) {
        // التحقق من أن سعر البيع أعلى من الكلفة (BR-PRD-007)
        if (dto.pricing.retail_price < dto.pricing.cost_price) {
          throw new BadRequestException('سعر المفرد لا يمكن أن يكون أقل من سعر الكلفة');
        }

        const variant = await tx.product_variants.create({
          data: {
            product_id: product.id,
            barcode: dto.barcode,
            weighted_avg_cost: dto.pricing.cost_price,
            attributes: {},
          },
        });

        // إضافة مستويات الأسعار الأربعة
        await tx.product_prices.createMany({
          data: [
            { variant_id: variant.id, price_type: price_type_enum.COST, unit_id: dto.base_unit_id, price: dto.pricing.cost_price },
            { variant_id: variant.id, price_type: price_type_enum.REP, unit_id: dto.base_unit_id, price: dto.pricing.rep_price },
            { variant_id: variant.id, price_type: price_type_enum.WHOLESALE, unit_id: dto.base_unit_id, price: dto.pricing.wholesale_price },
            { variant_id: variant.id, price_type: price_type_enum.RETAIL, unit_id: dto.base_unit_id, price: dto.pricing.retail_price },
          ],
        });
      }

      // إذا كان المنتج يحتوي على أشكال متعددة (Multi-Variants)
      if (dto.has_variants && dto.variants && dto.variants.length > 0) {
        for (const vDto of dto.variants) {
          const variant = await tx.product_variants.create({
            data: {
              product_id: product.id,
              barcode: vDto.barcode,
              sku: vDto.sku,
              attributes: vDto.attributes || {},
              weighted_avg_cost: vDto.pricing.cost_price,
            },
          });

          await tx.product_prices.createMany({
            data: [
              { variant_id: variant.id, price_type: price_type_enum.COST, unit_id: dto.base_unit_id, price: vDto.pricing.cost_price },
              { variant_id: variant.id, price_type: price_type_enum.REP, unit_id: dto.base_unit_id, price: vDto.pricing.rep_price },
              { variant_id: variant.id, price_type: price_type_enum.WHOLESALE, unit_id: dto.base_unit_id, price: vDto.pricing.wholesale_price },
              { variant_id: variant.id, price_type: price_type_enum.RETAIL, unit_id: dto.base_unit_id, price: vDto.pricing.retail_price },
            ],
          });
        }
      }

      return product;
    });
  }

  // استرجاع قائمة المنتجات مع الفلاتر والبحث والمؤشرات للجدول
  async findAll(query: any) {
    const { search, category_id, warehouse_id, page = 1, limit = 20 } = query;
    const skip = (Number(page) - 1) * Number(limit);

    const where: any = { is_active: true };
    if (category_id) where.category_id = category_id;
    if (search) {
      where.OR = [
        { name_ar: { contains: search, mode: 'insensitive' } },
        { barcode: { contains: search, mode: 'insensitive' } },
      ];
    }

    const [total, items] = await Promise.all([
      this.prisma.products.count({ where }),
      this.prisma.products.findMany({
        where,
        skip,
        take: Number(limit),
        include: {
          category: { select: { id: true, name_ar: true } },
          base_unit: { select: { id: true, name_ar: true, symbol: true } },
          variants: {
            include: {
              prices: true,
              stock_levels: warehouse_id ? { where: { warehouse_id } } : true,
            },
          },
        },
        orderBy: { created_at: 'desc' },
      }),
    ]);

    // تحويل البيانات لتناسب الجدول المعروض في الواجهة
    const data = items.map((p) => {
      const mainVariant = p.variants[0] || ({} as any);
      const prices = mainVariant.prices || [];

      const getPrice = (type: price_type_enum) =>
        prices.find((pr: any) => pr.price_type === type)?.price || 0;

      const totalStock = (mainVariant.stock_levels || []).reduce(
        (sum: number, sl: any) => sum + Number(sl.quantity_on_hand || 0),
        0,
      );

      let stockStatus = 'متوفر';
      if (totalStock === 0) stockStatus = 'نافد';
      else if (totalStock <= Number(p.min_stock_level)) stockStatus = 'منخفض';

      return {
        id: p.id,
        name_ar: p.name_ar,
        barcode: p.barcode || mainVariant.barcode,
        category: p.category?.name_ar || 'عام',
        unit: p.base_unit?.name_ar,
        quantity: totalStock,
        status: stockStatus,
        cost_price: getPrice(price_type_enum.COST),
        rep_price: getPrice(price_type_enum.REP),
        wholesale_price: getPrice(price_type_enum.WHOLESALE),
        retail_price: getPrice(price_type_enum.RETAIL),
      };
    });

    return {
      data,
      meta: {
        total,
        page: Number(page),
        limit: Number(limit),
        totalPages: Math.ceil(total / Number(limit)),
      },
    };
  }

  // البحث السريع بالباركود للكاشير والـ POS
  async findByBarcode(barcode: string) {
    const variant = await this.prisma.product_variants.findUnique({
      where: { barcode },
      include: {
        product: { include: { category: true, base_unit: true } },
        prices: true,
        stock_levels: true,
      },
    });
    if (!variant) throw new NotFoundException('لم يتم العثور على منتج بهذا الباركود');
    return variant;
  }
}
```

---

## الخطوة 5: موديول الأسعار ومؤشرات لوحة التحكم (Pricing & KPI Dashboard)

المسار: `src/modules/products/products-dashboard.service.ts`

هذه الدالة تستخرج **البطاقات الإحصائية الأربعة** الموجودة أعلى الشاشة:

```typescript
import { Injectable } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';

@Injectable()
export class ProductsDashboardService {
  constructor(private prisma: PrismaService) {}

  async getKpiStats(warehouse_id?: string) {
    const products = await this.prisma.products.findMany({
      where: { is_active: true },
      include: {
        variants: {
          include: {
            stock_levels: warehouse_id ? { where: { warehouse_id } } : true,
          },
        },
      },
    });

    let totalProducts = products.length;
    let inStock = 0;
    let lowStock = 0;
    let outOfStock = 0;

    for (const p of products) {
      const stock = p.variants.reduce((acc, v) => {
        return acc + v.stock_levels.reduce((s, sl) => s + Number(sl.quantity_on_hand || 0), 0);
      }, 0);

      const minLevel = Number(p.min_stock_level);

      if (stock === 0) {
        outOfStock++;
      } else if (stock <= minLevel) {
        lowStock++;
      } else {
        inStock++;
      }
    }

    return {
      total_products: totalProducts,
      in_stock: inStock,
      low_stock: lowStock,
      out_of_stock: outOfStock,
    };
  }
}
```

---

## الخطوة 6: التسجيل في AppModule

افتح ملف [app.module.ts](file:///c:/Users/FWZ/Documents/sayler/syler-backend/src/app.module.ts) وتأكد من تسجيل الموديولات الجديدة:

```typescript
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { PrismaModule } from './prisma/prisma.module';
import { UsersModule } from './modules/users/users.module';
import { AuthModule } from './modules/auth/auth.module';
import { CompanyModule } from './modules/company/company.module';
import { BranchesModule } from './modules/branches/branches.module';
import { WarehousesModule } from './modules/warehouses/warehouses.module';
import { OrganizationModule } from './modules/organization/organization.module';
import { UnitsModule } from './modules/units/units.module';
import { CategoriesModule } from './modules/categories/categories.module';
import { ProductsModule } from './modules/products/products.module';

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
  ],
})
export class AppModule {}
```

---

## الخطوة 7: خطة الاختبار والفحص الشامل (Swagger Checklist)

افتح Swagger UI على `http://localhost:3000/api/docs` واختبر السيناريوهات التالية:

### ✅ سيناريو 1: وحدات القياس والتصنيفات
- [ ] إنشاء وحدة قياس أساسية (قطعة) عبر `POST /api/v1/units`.
- [ ] إنشاء وحدة قياس مجمعة (كارتون = 24 قطعة) مع ربطها بالأب.
- [ ] إنشاء تصنيف رئيسي (مواد غذائية) عبر `POST /api/v1/categories`.
- [ ] إنشاء تصنيف فرعي (مشروبات) وتعيين `parent_id`.
- [ ] استدعاء `GET /api/v1/categories/tree` والتأكد من بناء الشجرة الهرمية بشكل صحيح.

### ✅ سيناريو 2: المنتجات البسيطة والأسعار
- [ ] إنشاء منتج بسيط بـ `POST /api/v1/products` مع تمرير الأسعار الأربعة:
  - `cost_price: 8500`
  - `rep_price: 9500`
  - `wholesale_price: 10500`
  - `retail_price: 12000`
- [ ] محاولة إدخال `retail_price < cost_price` والتأكد من رفض السيرفر للطلب بـ `400 Bad Request`.

### ✅ سيناريو 3: المنتجات متعددة الأشكال (Variants)
- [ ] إنشاء منتج به `has_variants: true` وتمرير مصفوفتين من الأشكال (مثلاً: أبيض و أسود).
- [ ] التأكد من إنشاء باركود مستقل لكل شكل.

### ✅ سيناريو 4: فحص الجدول ولوحة التحكم
- [ ] استدعاء `GET /api/v1/products` والتأكد من استرجاع قائمة الجدول مطابقة تماماً لواجهة المبيعات المعروضة.
- [ ] استدعاء `GET /api/v1/products/dashboard/stats` والتأكد من حساب المؤشرات الأربعة (`total`, `in_stock`, `low_stock`, `out_of_stock`).
- [ ] استدعاء `GET /api/v1/products/barcode/:barcode` وتجربة المسح السريع للباركود.

---

> 🎯 **الملف جاهز الآن!** ابدأ بتنفيذ موديولات M03 بالتتابع، وإذا احتجت أي مساعدة أو مراجعة برمجية، أنا بجانبك دائماً!
