# 📘 الدليل التطبيقي الشامل لتنفيذ موديول M02 (الشركة والفروع والمخازن)
### Hands-On Implementation Guide — Sayler Backend (NestJS + Prisma)

> **الهدف من هذا الدليل**: تمكينك من بناء موديول **M02** خطوة بخطوة بيدك، وفهم المنطق البرمجي وقواعد العمل الحقيقية وطريقة تنظيم الكود باحترافية كـ Senior Backend Developer.

---

## 📑 فهرس المحتويات
1. [نظرة عامة والقرارات المعمارية](#1-نظرة-عامة-والقرارات-المعمارية)
2. [قواعد العمل الحاكمة (Business Rules)](#2-قواعد-العمل-الحاكمة-business-rules)
3. [الخطوة 1: تعديل وتجهيز قاعدة البيانات (Prisma Schema)](#الخطوة-1-تعديل-وتجهيز-قاعدة-البيانات-prisma-schema)
4. [الخطوة 2: بناء موديول الشركة (Company Module)](#الخطوة-2-بناء-موديول-الشركة-company-module)
5. [الخطوة 3: بناء موديول الفروع (Branches Module)](#الخطوة-3-بناء-موديول-الفروع-branches-module)
6. [الخطوة 4: بناء موديول المخازن (Warehouses Module)](#الخطوة-4-بناء-موديول-المخازن-warehouses-module)
7. [الخطوة 5: بناء موديول الهيكل والاعتمادات (Organization Module)](#الخطوة-5-بناء-موديول-الهيكل-والاعتمادات-organization-module)
8. [الخطوة 6: الربط والتسجيل في AppModule](#الخطوة-6-الربط-والتسجيل-في-appmodule)
9. [الخطوة 7: خطة الاختبار والفحص الشامل (Swagger Checklist)](#الخطوة-7-خطة-الاختبار-والفحص-الشامل-swagger-checklist)
10. [نصائح ذهبية لتطوير مهاراتك البرمجية](#10-نصائح-ذهبية-لتطوير-مهاراتك-البرمجية)

---

## 1. نظرة عامة والقرارات المعمارية

يمثل هذا الموديول **الهيكل المكاني والإداري** الذي ستبنى عليه كل العمليات القادمة (المشتريات، المبيعات، المخزون، التحويلات).

```
               ┌───────────────────────┐
               │    الشركة (Company)   │  (كيان واحد فقط في النظام)
               └───────────┬───────────┘
                           │ 1:N
               ┌───────────▼───────────┐
               │     الفرع (Branch)    │  (فرع رئيسي HQ واحد + فروع اعتيادية)
               └───────────┬───────────┘
                           │ 1:N
               ┌───────────▼───────────┐
               │ المخزن الرئيسي (MAIN) │  (يمكن وجود أكثر من مخزن رئيسي للفرع)
               └───────────┬───────────┘
                           │ 1:N (علاقة ذاتية داخل نفس الفرع)
               ┌───────────▼───────────┐
               │ المخزن الفرعي (SUB)  │  (يتبع مخزن رئيسي محدد في الفرع نفسه)
               └───────────────────────┘
```

---

## 2. قواعد العمل الحاكمة (Business Rules)
عليك تطبيق هذه القواعد في الـ Services:

| الرمز | القاعدة البرمجية | كيف تطبقها؟ |
|---|---|---|
| **BR-ORG-001** | شركة واحدة فقط في النظام | عند التحديث نتحقق من وجود السجل الوحيد، ونمنع إنشاء أكثر من شركة. |
| **BR-ORG-002** | فرع مقر رئيسي واحد فقط (`HEADQUARTERS`) | فحص عند الإنشاء أو التعديل: إذا كان النوع `HEADQUARTERS`، نتحقق أنه لا يوجد فرع آخر من نفس النوع بحالة نشطة. |
| **BR-ORG-004** | المخزن الفرعي يتبع مخزن رئيسي في نفس الفرع | التحقق من `parent_warehouse_id` أنه موجود، ونوعه `MAIN`، وينتمي لنفس الـ `branch_id`. |
| **BR-ORG-006** | مدير واحد نشط لكل فرع ومخزن | التحقق من أن المستخدم المختار نشط وله صلاحية الإدارة. |
| **BR-ORG-007** | الكيانات غير النشطة لا تستخدم تشغيلياً | فقط الكيانات بحالة `ACTIVE` تتاح في القوائم المنسدلة للعمليات. |
| **BR-ORG-009** | صانع الطلب لا يعتمده بنفسه | منع المستخدم الذي قام بـ `created_by` من الموافقة على `approve`. |
| **BR-ORG-010** | الرفض يتطلب سبباً إجبارياً | الـ DTO لعملية الـ Reject يحتوي على حقل `rejection_reason` إجباري. |
| **BR-ORG-011** | توليد تلقائي للرموز | توليد `BR-001`, `WH-001` تلقائياً إذا لم يتم إدخالها يدوياً. |
| **BR-ORG-014** | منع تعطيل المخزن إذا كان به رصيد | فحص جدول `stock_levels`؛ إذا كان `quantity_on_hand > 0` نرفض التعطيل فوراً. |
| **BR-ORG-015** | منع تعطيل المخزن الرئيسي إذا كانت تتبعه مخازن فرعية نشطة | فحص وجود أي مخزن فرعي بحالة `ACTIVE` يتبع هذا المخزن. |
| **BR-ORG-016** | منع تعطيل الفرع إذا وجدت به مخازن نشطة | فحص عدم وجود أي مخزن نشط في الفرع قبل السماح بتعطيله. |

---

## الخطوة 1: تعديل وتجهيز قاعدة البيانات (Prisma Schema)

افتح ملف `prisma/schema.prisma` وتأكد من إضافة وتحديث النماذج التالية:

### 1. الـ Enums المطلوبة:
```prisma
enum org_status_enum {
  DRAFT
  PENDING_APPROVAL
  ACTIVE
  REJECTED
  INACTIVE
}

enum branch_type_enum {
  HEADQUARTERS
  STANDARD
}

enum warehouse_type_enum {
  MAIN
  SUB
  VIRTUAL
}
```

### 2. جدول الفروع (`branches`):
```prisma
model branches {
  id               String            @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  code             String            @unique @db.VarChar(50)
  name             String            @db.VarChar(200)
  type             branch_type_enum  @default(STANDARD)
  status           org_status_enum   @default(DRAFT)
  company_id       String            @db.Uuid
  manager_id       String?           @db.Uuid
  address          String?
  phone            String?           @db.VarChar(20)
  notes            String?
  rejection_reason String?
  created_by       String?           @db.Uuid
  created_at       DateTime          @default(now()) @db.Timestamptz(6)
  updated_at       DateTime          @default(now()) @db.Timestamptz(6)

  company          companies         @relation(fields: [company_id], references: [id], onDelete: Restrict)
  manager          users?            @relation("BranchManager", fields: [manager_id], references: [id], onDelete: SetNull)
  creator          users?            @relation("BranchCreator", fields: [created_by], references: [id], onDelete: SetNull)
  warehouses       warehouses[]

  @@index([status])
  @@index([type])
}
```

### 3. جدول المخازن (`warehouses`):
```prisma
model warehouses {
  id                  String              @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  code                String              @unique @db.VarChar(50)
  name                String              @db.VarChar(200)
  type                warehouse_type_enum @default(SUB)
  status              org_status_enum     @default(DRAFT)
  branch_id           String              @db.Uuid
  parent_warehouse_id String?             @db.Uuid
  manager_id          String?             @db.Uuid
  address             String?
  capacity            Decimal?            @db.Decimal(10, 2)
  notes               String?
  rejection_reason    String?
  created_by          String?             @db.Uuid
  created_at          DateTime            @default(now()) @db.Timestamptz(6)
  updated_at          DateTime            @default(now()) @db.Timestamptz(6)

  branch              branches            @relation(fields: [branch_id], references: [id], onDelete: Restrict)
  parent_warehouse    warehouses?         @relation("WarehouseHierarchy", fields: [parent_warehouse_id], references: [id], onDelete: Restrict)
  sub_warehouses      warehouses[]        @relation("WarehouseHierarchy")
  manager             users?              @relation("WarehouseManager", fields: [manager_id], references: [id], onDelete: SetNull)
  creator             users?              @relation("WarehouseCreator", fields: [created_by], references: [id], onDelete: SetNull)
  keepers             warehouse_keepers[]
  stock_levels        stock_levels[]

  @@index([branch_id, status])
  @@index([parent_warehouse_id])
}
```

### 4. جدول أمناء المخازن (`warehouse_keepers`):
```prisma
model warehouse_keepers {
  id           String     @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  warehouse_id String     @db.Uuid
  user_id      String     @db.Uuid
  assigned_at  DateTime   @default(now()) @db.Timestamptz(6)

  warehouse    warehouses @relation(fields: [warehouse_id], references: [id], onDelete: Cascade)
  user         users      @relation(fields: [user_id], references: [id], onDelete: Cascade)

  @@unique([warehouse_id, user_id])
}
```

> ⚡ **أمر الترحيل بعد التعديل**:
> ```bash
> npx prisma db push
> # أو
> npx prisma migrate dev --name update_m02_schema
> npx prisma generate
> ```

---

## الخطوة 2: بناء موديول الشركة (Company Module)

المسار: `src/modules/company/`

### 1. الـ DTOs (`dto/update-company.dto.ts`):
```typescript
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsEmail } from 'class-validator';

export class UpdateCompanyDto {
  @ApiPropertyOptional({ example: 'شركة المسار للتجارة والتوزيع' })
  @IsOptional()
  @IsString()
  name?: string;

  @ApiPropertyOptional({ example: 'https://example.com/logo.png' })
  @IsOptional()
  @IsString()
  logo_url?: string;

  @ApiPropertyOptional({ example: 'بغداد - المنصور - شارع 14 رمضان' })
  @IsOptional()
  @IsString()
  address?: string;

  @ApiPropertyOptional({ example: '+9647700000000' })
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiPropertyOptional({ example: 'info@sayler.app' })
  @IsOptional()
  @IsEmail()
  email?: string;

  @ApiPropertyOptional({ example: '123456789' })
  @IsOptional()
  @IsString()
  tax_number?: string;

  @ApiPropertyOptional({ example: { currency: 'IQD', decimal_places: 2 } })
  @IsOptional()
  settings?: any;
}
```

### 2. الـ Service (`company.service.ts`):
```typescript
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { UpdateCompanyDto } from './dto/update-company.dto';

@Injectable()
export class CompanyService {
  constructor(private prisma: PrismaService) {}

  async getCompany() {
    let company = await this.prisma.companies.findFirst();
    if (!company) {
      // إنشاء سجل افتراضي إذا لم يوجد
      company = await this.prisma.companies.create({
        data: {
          name: 'الشركة الرئيسية',
          settings: {},
        },
      });
    }
    return company;
  }

  async updateCompany(dto: UpdateCompanyDto) {
    const current = await this.getCompany();
    return this.prisma.companies.update({
      where: { id: current.id },
      data: { ...dto, updated_at: new Date() },
    });
  }
}
```

### 3. الـ Controller (`company.controller.ts`):
```typescript
import { Controller, Get, Patch, Body, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { CompanyService } from './company.service';
import { UpdateCompanyDto } from './dto/update-company.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('Company (M02)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('company')
export class CompanyController {
  constructor(private readonly companyService: CompanyService) {}

  @Get()
  @ApiOperation({ summary: 'عرض بيانات الشركة الأساسية' })
  async getCompany() {
    const data = await this.companyService.getCompany();
    return { success: true, data };
  }

  @Patch()
  @ApiOperation({ summary: 'تحديث بيانات الشركة وإعداداتها' })
  async updateCompany(@Body() dto: UpdateCompanyDto) {
    const data = await this.companyService.updateCompany(dto);
    return { success: true, data };
  }
}
```

---

## الخطوة 3: بناء موديول الفروع (Branches Module)

المسار: `src/modules/branches/`

### 1. الـ DTOs:
- `dto/create-branch.dto.ts`:
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsEnum, IsUUID } from 'class-validator';
import { branch_type_enum } from '@prisma/client';

export class CreateBranchDto {
  @ApiPropertyOptional({ example: 'BR-001' })
  @IsOptional()
  @IsString()
  code?: string;

  @ApiProperty({ example: 'فرع الكرادة' })
  @IsNotEmpty({ message: 'اسم الفرع مطلوب' })
  @IsString()
  name: string;

  @ApiPropertyOptional({ enum: branch_type_enum, default: branch_type_enum.STANDARD })
  @IsOptional()
  @IsEnum(branch_type_enum)
  type?: branch_type_enum;

  @ApiPropertyOptional({ example: 'uuid-of-user' })
  @IsOptional()
  @IsUUID()
  manager_id?: string;

  @ApiPropertyOptional({ example: 'بغداد - الكرادة خارج' })
  @IsOptional()
  @IsString()
  address?: string;

  @ApiPropertyOptional({ example: '+9647712345678' })
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}
```

- `dto/reject-request.dto.ts`:
```typescript
import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString } from 'class-validator';

export class RejectRequestDto {
  @ApiProperty({ example: 'البيانات غير مكتملة أو الموقع الجغرافي غير محدد بدقة' })
  @IsNotEmpty({ message: 'سبب الرفض إلزامي' })
  @IsString()
  rejection_reason: string;
}
```

### 2. الـ Service (`branches.service.ts`):
تطبيق دورة الحياة والتحقق من القواعد:
```typescript
import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateBranchDto } from './dto/create-branch.dto';
import { UpdateBranchDto } from './dto/update-branch.dto';
import { RejectRequestDto } from './dto/reject-request.dto';
import { org_status_enum, branch_type_enum } from '@prisma/client';

@Injectable()
export class BranchesService {
  constructor(private prisma: PrismaService) {}

  // توليد كود فريد للفرع BR-001
  private async generateBranchCode(): Promise<string> {
    const count = await this.prisma.branches.count();
    return `BR-${String(count + 1).padStart(3, '0')}`;
  }

  async create(dto: CreateBranchDto, userId: string) {
    const company = await this.prisma.companies.findFirst();
    if (!company) throw new BadRequestException('لم يتم ضبط بيانات الشركة بعد');

    // BR-ORG-002: التأكد من وجود مقر رئيسي واحد فقط
    if (dto.type === branch_type_enum.HEADQUARTERS) {
      const hqExists = await this.prisma.branches.findFirst({
        where: { type: branch_type_enum.HEADQUARTERS, status: { not: org_status_enum.INACTIVE } },
      });
      if (hqExists) throw new BadRequestException('يوجد مقر رئيسي فعال بالفعل في النظام');
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
    const { search, status, type, page = 1, limit = 20 } = query;
    const skip = (page - 1) * limit;

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
```

### 3. الـ Controller (`branches.controller.ts`):
```typescript
import {
  Controller,
  Get,
  Post,
  Patch,
  Put,
  Param,
  Body,
  Query,
  UseGuards,
  Req,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { BranchesService } from './branches.service';
import { CreateBranchDto } from './dto/create-branch.dto';
import { UpdateBranchDto } from './dto/update-branch.dto';
import { RejectRequestDto } from './dto/reject-request.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('Branches (M02)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('branches')
export class BranchesController {
  constructor(private readonly branchesService: BranchesService) {}

  @Post()
  @ApiOperation({ summary: 'إنشاء فرع جديد (مسودة DRAFT)' })
  async create(@Body() dto: CreateBranchDto, @Req() req: any) {
    const data = await this.branchesService.create(dto, req.user?.id);
    return { success: true, data };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة الفروع مع البحث والفلترة' })
  async findAll(@Query() query: any) {
    const result = await this.branchesService.findAll(query);
    return { success: true, ...result };
  }

  @Get(':id')
  @ApiOperation({ summary: 'تفاصيل الفرع ومخازنه' })
  async findOne(@Param('id') id: string) {
    const data = await this.branchesService.findOne(id);
    return { success: true, data };
  }

  @Post(':id/submit')
  @ApiOperation({ summary: 'إرسال الفرع للاعتماد' })
  async submit(@Param('id') id: string) {
    const data = await this.branchesService.submitForApproval(id);
    return { success: true, data, message: 'تم إرسال الفرع للاعتماد' };
  }

  @Post(':id/approve')
  @ApiOperation({ summary: 'اعتماد الفرع وتفعيله' })
  async approve(@Param('id') id: string, @Req() req: any) {
    const data = await this.branchesService.approve(id, req.user?.id);
    return { success: true, data, message: 'تم اعتماد وتفعيل الفرع بنجاح' };
  }

  @Post(':id/reject')
  @ApiOperation({ summary: 'رفض طلب الفرع مع السبب' })
  async reject(@Param('id') id: string, @Body() dto: RejectRequestDto) {
    const data = await this.branchesService.reject(id, dto);
    return { success: true, data, message: 'تم رفض الطلب' };
  }

  @Post(':id/disable')
  @ApiOperation({ summary: 'تعطيل الفرع بعد فحص الشروط' })
  async disable(@Param('id') id: string) {
    const data = await this.branchesService.disable(id);
    return { success: true, data, message: 'تم تعطيل الفرع' };
  }

  @Put(':id/manager')
  @ApiOperation({ summary: 'تعيين مدير الفرع' })
  async assignManager(@Param('id') id: string, @Body('manager_id') managerId: string) {
    const data = await this.branchesService.assignManager(id, managerId);
    return { success: true, data };
  }
}
```

---

## الخطوة 4: بناء موديول المخازن (Warehouses Module)

المسار: `src/modules/warehouses/`

### 1. الـ DTOs:
- `dto/create-warehouse.dto.ts`:
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsEnum, IsUUID, IsNumber } from 'class-validator';
import { warehouse_type_enum } from '@prisma/client';

export class CreateWarehouseDto {
  @ApiPropertyOptional({ example: 'WH-001' })
  @IsOptional()
  @IsString()
  code?: string;

  @ApiProperty({ example: 'المخزن الرئيسي - الكرادة' })
  @IsNotEmpty({ message: 'اسم المخزن مطلوب' })
  @IsString()
  name: string;

  @ApiProperty({ example: 'uuid-of-branch' })
  @IsNotEmpty({ message: 'معرف الفرع مطلوب' })
  @IsUUID()
  branch_id: string;

  @ApiPropertyOptional({ enum: warehouse_type_enum, default: warehouse_type_enum.SUB })
  @IsOptional()
  @IsEnum(warehouse_type_enum)
  type?: warehouse_type_enum;

  @ApiPropertyOptional({ description: 'المخزن الرئيسي الأب (إلزامي إذا كان المخزن فرعياً SUB)' })
  @IsOptional()
  @IsUUID()
  parent_warehouse_id?: string;

  @ApiPropertyOptional({ example: 'uuid-of-manager' })
  @IsOptional()
  @IsUUID()
  manager_id?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  address?: string;

  @ApiPropertyOptional({ example: 1000.0 })
  @IsOptional()
  @IsNumber()
  capacity?: number;
}
```

- `dto/assign-keepers.dto.ts`:
```typescript
import { ApiProperty } from '@nestjs/swagger';
import { IsArray, IsUUID } from 'class-validator';

export class AssignKeepersDto {
  @ApiProperty({ example: ['uuid-user-1', 'uuid-user-2'] })
  @IsArray()
  @IsUUID('4', { each: true })
  keeper_ids: string[];
}
```

### 2. الـ Service (`warehouses.service.ts`):
تطبيق قواعد الربط بالفرع والأب، وفحص المخزون قبل التعطيل:
```typescript
import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateWarehouseDto } from './dto/create-warehouse.dto';
import { RejectRequestDto } from '../branches/dto/reject-request.dto';
import { AssignKeepersDto } from './dto/assign-keepers.dto';
import { org_status_enum, warehouse_type_enum } from '@prisma/client';

@Injectable()
export class WarehousesService {
  constructor(private prisma: PrismaService) {}

  private async generateWarehouseCode(): Promise<string> {
    const count = await this.prisma.warehouses.count();
    return `WH-${String(count + 1).padStart(3, '0')}`;
  }

  async create(dto: CreateWarehouseDto, userId: string) {
    // 1. التحقق من وجود الفرع وأنه نشط
    const branch = await this.prisma.branches.findUnique({ where: { id: dto.branch_id } });
    if (!branch) throw new NotFoundException('الفرع غير موجود');

    // 2. BR-ORG-004: المخزن الفرعي يتبع مخزن رئيسي نشط في نفس الفرع
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
    const { branch_id, type, status, search, page = 1, limit = 20 } = query;
    const skip = (page - 1) * limit;

    const where: any = {};
    if (branch_id) where.branch_id = branch_id;
    if (type) where.type = type;
    if (status) where.status = status;
    if (search) {
      where.OR = [
        { name: { contains: search, mode: 'insensitive' } },
        { code: { contains: search, mode: 'insensitive' } },
      ];
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
        orderBy: { created_at: 'desc' },
      }),
    ]);

    return { data, meta: { total, page: Number(page), limit: Number(limit) } };
  }

  async findOne(id: string) {
    const wh = await this.prisma.warehouses.findUnique({
      where: { id },
      include: {
        branch: true,
        parent_warehouse: true,
        sub_warehouses: true,
        manager: true,
        keepers: { include: { user: { select: { id: true, username: true, email: true } } } },
      },
    });
    if (!wh) throw new NotFoundException('المخزن غير موجود');
    return wh;
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

  async approve(id: string, approverId: string) {
    const wh = await this.findOne(id);
    if (wh.status !== org_status_enum.PENDING_APPROVAL) {
      throw new BadRequestException('المخزن ليس في حالة انتظار الاعتماد');
    }
    if (wh.created_by === approverId) {
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
```

### 3. الـ Controller (`warehouses.controller.ts`):
```typescript
import {
  Controller,
  Get,
  Post,
  Patch,
  Put,
  Param,
  Body,
  Query,
  UseGuards,
  Req,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { WarehousesService } from './warehouses.service';
import { CreateWarehouseDto } from './dto/create-warehouse.dto';
import { RejectRequestDto } from '../branches/dto/reject-request.dto';
import { AssignKeepersDto } from './dto/assign-keepers.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('Warehouses (M02)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('warehouses')
export class WarehousesController {
  constructor(private readonly warehousesService: WarehousesService) {}

  @Post()
  @ApiOperation({ summary: 'إنشاء مخزن جديد (مسودة DRAFT)' })
  async create(@Body() dto: CreateWarehouseDto, @Req() req: any) {
    const data = await this.warehousesService.create(dto, req.user?.id);
    return { success: true, data };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة المخازن مع الفلترة بالفرع والنوع والحالة' })
  async findAll(@Query() query: any) {
    const result = await this.warehousesService.findAll(query);
    return { success: true, ...result };
  }

  @Get(':id')
  @ApiOperation({ summary: 'تفاصيل المخزن وأمنائه والمخازن التابعة' })
  async findOne(@Param('id') id: string) {
    const data = await this.warehousesService.findOne(id);
    return { success: true, data };
  }

  @Post(':id/submit')
  @ApiOperation({ summary: 'إرسال المخزن للاعتماد' })
  async submit(@Param('id') id: string) {
    const data = await this.warehousesService.submitForApproval(id);
    return { success: true, data, message: 'تم إرسال المخزن للاعتماد' };
  }

  @Post(':id/approve')
  @ApiOperation({ summary: 'اعتماد المخزن وتفعيله' })
  async approve(@Param('id') id: string, @Req() req: any) {
    const data = await this.warehousesService.approve(id, req.user?.id);
    return { success: true, data, message: 'تم اعتماد وتفعيل المخزن بنجاح' };
  }

  @Post(':id/reject')
  @ApiOperation({ summary: 'رفض طلب المخزن مع السبب' })
  async reject(@Param('id') id: string, @Body() dto: RejectRequestDto) {
    const data = await this.warehousesService.reject(id, dto);
    return { success: true, data, message: 'تم رفض طلب المخزن' };
  }

  @Post(':id/disable')
  @ApiOperation({ summary: 'تعطيل المخزن بعد فحص الرصيد' })
  async disable(@Param('id') id: string) {
    const data = await this.warehousesService.disable(id);
    return { success: true, data, message: 'تم تعطيل المخزن بنجاح' };
  }

  @Put(':id/keepers')
  @ApiOperation({ summary: 'تعيين أمناء المخزن' })
  async assignKeepers(@Param('id') id: string, @Body() dto: AssignKeepersDto) {
    const data = await this.warehousesService.assignKeepers(id, dto);
    return { success: true, data, message: 'تم تحديث قائمة أمناء المخزن بنجاح' };
  }
}
```

---

## الخطوة 5: بناء موديول الهيكل والاعتمادات (Organization Module)

المسار: `src/modules/organization/`

هذا الموديول يجمع شجرة الهيكل التنظيمي كاملة للـ Frontend، وصندوق الاعتمادات الموحد:

### 1. الـ Service (`organization.service.ts`):
```typescript
import { Injectable } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { org_status_enum, warehouse_type_enum } from '@prisma/client';

@Injectable()
export class OrganizationService {
  constructor(private prisma: PrismaService) {}

  // 1. شجرة الهيكل التنظيمي الكاملة (Company -> Branches -> Main Warehouses -> Sub Warehouses)
  async getTree() {
    const company = await this.prisma.companies.findFirst();
    if (!company) return null;

    const branches = await this.prisma.branches.findMany({
      where: { status: { not: org_status_enum.INACTIVE } },
      include: {
        manager: { select: { id: true, username: true } },
        warehouses: {
          where: {
            status: { not: org_status_enum.INACTIVE },
            type: warehouse_type_enum.MAIN, // نبدأ بالمخازن الرئيسية
          },
          include: {
            manager: { select: { id: true, username: true } },
            sub_warehouses: {
              where: { status: { not: org_status_enum.INACTIVE } },
              include: {
                manager: { select: { id: true, username: true } },
                keepers: { include: { user: { select: { id: true, username: true } } } },
              },
            },
          },
        },
      },
    });

    return {
      company: {
        id: company.id,
        name: company.name,
        logo_url: company.logo_url,
      },
      branches,
    };
  }

  // 2. صندوق الاعتمادات الموحد (Pending Approvals Inbox)
  async getPendingApprovals() {
    const [pendingBranches, pendingWarehouses] = await Promise.all([
      this.prisma.branches.findMany({
        where: { status: org_status_enum.PENDING_APPROVAL },
        include: { creator: { select: { id: true, username: true } } },
        orderBy: { updated_at: 'desc' },
      }),
      this.prisma.warehouses.findMany({
        where: { status: org_status_enum.PENDING_APPROVAL },
        include: {
          branch: { select: { id: true, name: true } },
          creator: { select: { id: true, username: true } },
        },
        orderBy: { updated_at: 'desc' },
      }),
    ]);

    return {
      total_pending: pendingBranches.length + pendingWarehouses.length,
      branches: pendingBranches,
      warehouses: pendingWarehouses,
    };
  }
}
```

### 2. الـ Controller (`organization.controller.ts`):
```typescript
import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { OrganizationService } from './organization.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('Organization Hub (M02)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('organization')
export class OrganizationController {
  constructor(private readonly orgService: OrganizationService) {}

  @Get('tree')
  @ApiOperation({ summary: 'عرض شجرة الهيكل التنظيمي الكاملة (شركة -> فروع -> مخازن)' })
  async getTree() {
    const data = await this.orgService.getTree();
    return { success: true, data };
  }

  @Get('approvals')
  @ApiOperation({ summary: 'صندوق طلبات الاعتماد المعلقة للفرع والمخازن' })
  async getApprovals() {
    const data = await this.orgService.getPendingApprovals();
    return { success: true, data };
  }
}
```

---

## الخطوة 6: الربط والتسجيل في AppModule

افتح ملف `src/app.module.ts` وسجل الموديولات الجديدة:

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
  ],
})
export class AppModule {}
```

---

## الخطوة 7: خطة الاختبار والفحص الشامل (Swagger Checklist)

افتح المتصفح على `http://localhost:3000/api/docs` واختبر السيناريوهات التالية:

### ✅ سيناريو 1: الشركة
- [ ] استدعاء `GET /api/v1/company` وتأكد من استرجاع البيانات.
- [ ] تعديل البيانات بـ `PATCH /api/v1/company` وتأكد من الحفظ.

### ✅ سيناريو 2: الفروع ودورة الاعتماد
- [ ] إنشاء فرع جديد بـ `POST /api/v1/branches` وتأكد أن حالته `DRAFT` وله كود تلقائي `BR-001`.
- [ ] إرسال الفرع للاعتماد بـ `POST /api/v1/branches/{id}/submit` وتأكد من تحوله إلى `PENDING_APPROVAL`.
- [ ] محاولة اعتماده بنفس المستخدم صانع الطلب وتأكد من إرجاع خطأ `403 Forbidden` (`BR-ORG-009`).
- [ ] اعتماده بمستخدم إداري آخر بـ `POST /api/v1/branches/{id}/approve` وتأكد من تحوله إلى `ACTIVE`.

### ✅ سيناريو 3: المخازن والشجرة
- [ ] إنشاء مخزن رئيسي `MAIN` في الفرع المعتمد.
- [ ] إنشاء مخزن فرعي `SUB` وربطه بالمخزن الرئيسي.
- [ ] محاولة ربط مخزن فرعي بمخزن رئيسي من فرع مختلف وتأكد من الرفض.
- [ ] اعتماد المخازن.
- [ ] استدعاء `GET /api/v1/organization/tree` وتأكد من ظهور الشجرة الهرمية كاملة مع العدادات.

### ✅ سيناريو 4: فحوصات التعطيل الآمن
- [ ] محاولة تعطيل مخزن يحتوي على رصيد وتأكد من منع العملية (`BR-ORG-014`).
- [ ] محاولة تعطيل فرع يحتوي على مخازن نشطة وتأكد من منع العملية (`BR-ORG-016`).

---

## 10. نصائح ذهبية لتطوير مهاراتك البرمجية

1. **التعامل مع الـ Transactions (`prisma.$transaction`)**:
   استخدم المعاملات الذرية دائماً عندما تقوم بعمليات متعددة مرتبطة (مثل تعيين الأمناء، أو الاعتماد ونقل السجلات)، بحيث إذا فشلت خطوة يتم التراجع عن الكل (Rollback).

2. **Clean DTOs & Validation**:
   لا تعتمد أبداً على المدخلات القادمة من الـ Request دون تمريرها عبر `class-validator` و `whitelist: true`.

3. **Exception Filter الموحد**:
   احرص على أن تكون رسائل الخطأ واضحة باللغة العربية وموجهة للمستخدم، مع كود الخطأ البرمجي المناسب (e.g. `400 Bad Request`, `403 Forbidden`, `404 Not Found`).

4. **الالتزام بالـ Single Responsibility**:
   افصل منطق الفروع عن منطق المخازن عن منطق الشركة في موديولات مستقلة لسهولة صيانتها مستقبلاً.

---

> 🚀 **أنت الآن جاهز تماماً للبدء!** ابدأ بالخطوة الأولى (Prisma Schema)، وطبّق الموديولات واحداً تلو الآخر، وإذا واجهتك أي صعوبة أو استفسار في أي سطر كود، أنا معك خطوة بخطوة.
