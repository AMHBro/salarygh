# 📘 الدليل التطبيقي الشامل لتنفيذ موديول M05 (إدارة المخازن، حركات المخزون والتحويلات)
### Hands-On Complete Implementation Guide — Sayler Backend (NestJS + Prisma)

> **الهدف من هذا الدليل**: مرجع كودي كامل وشامل لبناء موديول **M05 (إدارة المخزون، الحركات اليدوية، التحويل بين المخازن، التنبيهات، والبطاقات الإحصائية)** ليتطابق 100% مع واجهات شاشات المخازن وقواعد العمل.

---

## 📑 فهرس المحتويات
1. [الهيكل المعماري والوظائف الخاصة بموديول M05](#1-الهيكل-المعماري-والوظائف-الخاصة-بموديول-m05)
2. [قواعد العمل الحاكمة (Business Rules)](#2-قواعد-العمل-الحاكمة-business-rules)
3. [الخطوة 1: مراجعة نماذج قاعدة البيانات (Prisma Schema)](#الخطوة-1-مراجعة-نماذج-قاعدة-البيانات-prisma-schema)
4. [الخطوة 2: ملفات الـ DTOs الكاملة](#الخطوة-2-ملفات-الـ-dtos-الكاملة)
5. [الخطوة 3: ملف الـ Service (منطق العمليات والترانزاكشن)](#الخطوة-3-ملف-الـ-service-منطق-العمليات-والترانزاكشن)
6. [الخطوة 4: ملف الـ Controller مع Swagger](#الخطوة-4-ملف-الـ-controller-مع-swagger)
7. [الخطوة 5: ملف الـ Module والتسجيل في AppModule](#الخطوة-5-ملف-الـ-module-والتسجيل-في-appmodule)
8. [الخطوة 6: خطة الاختبار والفحص الشامل (Swagger Checklist)](#الخطوة-6-خطة-الاختبار-والفحص-الشامل-swagger-checklist)

---

## 1. الهيكل المعماري والوظائف الخاصة بموديول M05

```
┌────────────────────────────────────────────────────────────────────────┐
│                        شاشة المخازن الرئيسية                            │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
    ┌───────────────────────────────┼───────────────────────────────┐
    ▼                               ▼                               ▼
┌───────────────────────┐ ┌───────────────────────┐ ┌───────────────────────┐
│ 1. لوحة الإحصائيات    │ │ 2. حركة مخزون يدوية   │ │ 3. تحويل بين المخازن  │
│ • 4 بطاقات علوية      │ │ • إدخال IN            │ │ • من مخزن ➔ إلى مخزن  │
│ • بطاقات ملخص المخازن │ │ • إخراج OUT           │ │ • خفض المصدر + زيادة  │
│ • تنبيهات نقص المخزون │ │ • تسوية ADJUSTMENT    │ │   الهدف ذرياً بالـ DB   │
└───────────────────────┘ └───────────────────────┘ └───────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 4. سجل ودفتر حركات المخزون (Movements Ledger Table)                    │
│ • فلترة حسب المخزن + فلترة حسب نوع الحركة + فلترة التاريخ               │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. قواعد العمل الحاكمة (Business Rules)

| الرمز | القاعدة البرمجية | كيف تطبقها في الكود؟ |
|---|---|---|
| **BR-INV-001** | كل حركة مخزنية تسجل في دفتر غير قابل للحذف | أي زيادة أو نقص تنشئ سجلاً في `inventory_movements`. |
| **BR-INV-002** | منع الرصيد السالب تماماً | عند الإخراج أو التحويل، يفحص النظام: `(quantity_on_hand >= requested_qty)` وإلا يرفض بـ `400 Bad Request`. |
| **BR-INV-003** | التحويل بين المخازن ذري (Atomic Transfer) | داخل `Prisma.$transaction` واحدة: خفض من المصدر + زيادة في الهدف + إنشاء حركتي `TRANSFER_OUT` و `TRANSFER_IN`. |
| **BR-INV-004** | كشف تنبيهات نقص المخزون | جلب المواد التي كميتها الحالية `<= min_stock_level`. |

---

## الخطوة 1: مراجعة نماذج قاعدة البيانات (Prisma Schema)

النماذج المستخدمة في `prisma/schema.prisma` جاهزة بالفعل:
* `inventory_movements`: جدول حركات المخزون.
* `stock_levels`: جدول الأرصدة الحالية لكل شكل منتج في كل مخزن (`variant_id_warehouse_id`).
* `warehouse_transfers` و `warehouse_transfer_items`: جدول توثيق عمليات التحويل بين المخازن.
* `warehouses`: جدول المخازن.

---

## الخطوة 2: ملفات الـ DTOs الكاملة

المجلد: `src/modules/inventory/dto/`

### 1. الـ DTO لحركة المخزون اليدوية (`dto/create-inventory-movement.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsUUID, IsNumber, IsEnum, IsOptional, IsString, Min } from 'class-validator';

export enum ManualMovementTypeEnum {
  IN = 'IN',
  OUT = 'OUT',
  ADJUST_ADD = 'ADJUST_ADD',
  ADJUST_REDUCE = 'ADJUST_REDUCE',
}

export class CreateInventoryMovementDto {
  @ApiProperty({ example: 'uuid-warehouse-id', description: 'المخزن المستهدف' })
  @IsNotEmpty({ message: 'المخزن مطلوب' })
  @IsUUID()
  warehouse_id: string;

  @ApiProperty({ example: 'uuid-product-variant-id', description: 'معرف المنتج/الشكل' })
  @IsNotEmpty({ message: 'المنتج مطلوب' })
  @IsUUID()
  variant_id: string;

  @ApiProperty({ enum: ManualMovementTypeEnum, example: ManualMovementTypeEnum.IN, description: 'نوع الحركة: إدخال أو إخراج أو تسوية' })
  @IsNotEmpty({ message: 'نوع الحركة مطلوب' })
  @IsEnum(ManualMovementTypeEnum)
  movement_type: ManualMovementTypeEnum;

  @ApiProperty({ example: 50, description: 'الكمية' })
  @IsNumber()
  @Min(0.001, { message: 'الكمية يجب أن تكون أكبر من الصفر' })
  quantity: number;

  @ApiPropertyOptional({ example: 8500, description: 'سعر الكلفة التقديري في حال الإدخال' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  unit_cost?: number;

  @ApiPropertyOptional({ example: 'رصيد افتتاحي / تسوية جرد دوري' })
  @IsOptional()
  @IsString()
  notes?: string;
}
```

### 2. الـ DTO للتحويل بين المخازن (`dto/transfer-stock.dto.ts`):
```typescript
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsUUID, IsNumber, IsOptional, IsString, Min } from 'class-validator';

export class TransferStockDto {
  @ApiProperty({ example: 'uuid-source-warehouse-id', description: 'المخزن المحول منه (المصدر)' })
  @IsNotEmpty({ message: 'المخزن المصدر مطلوب' })
  @IsUUID()
  source_warehouse_id: string;

  @ApiProperty({ example: 'uuid-destination-warehouse-id', description: 'المخزن المحول إليه (الهدف)' })
  @IsNotEmpty({ message: 'المخزن الهدف مطلوب' })
  @IsUUID()
  destination_warehouse_id: string;

  @ApiProperty({ example: 'uuid-product-variant-id', description: 'معرف المنتج المراد تحويله' })
  @IsNotEmpty({ message: 'المنتج مطلوب' })
  @IsUUID()
  variant_id: string;

  @ApiProperty({ example: 20, description: 'الكمية المراد تحويلها' })
  @IsNumber()
  @Min(0.001, { message: 'الكمية يجب أن تكون أكبر من الصفر' })
  quantity: number;

  @ApiPropertyOptional({ example: 'تغذية فرع المنصور' })
  @IsOptional()
  @IsString()
  notes?: string;
}
```

---

## الخطوة 3: ملف الـ Service (منطق العمليات والترانزاكشن)

المسار: `src/modules/inventory/inventory.service.ts`

```typescript
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateInventoryMovementDto, ManualMovementTypeEnum } from './dto/create-inventory-movement.dto';
import { TransferStockDto } from './dto/transfer-stock.dto';
import { movement_type_enum, transfer_status_enum } from '@prisma/client';

@Injectable()
export class InventoryService {
  constructor(private prisma: PrismaService) {}

  // ─── 1. إحصائيات لوحة المخازن (البطاقات الأربعة + بطاقات الفروع) ───────────
  async getDashboardStats() {
    const warehouses = await this.prisma.warehouses.findMany({
      where: { is_active: true },
      include: {
        stock_levels: {
          include: {
            product_variants: {
              include: { products: true },
            },
          },
        },
      },
      orderBy: { created_at: 'asc' },
    });

    let totalQuantity = 0;
    let lowStockCount = 0;
    const distinctVariantIds = new Set<string>();

    const warehouseSummaries = warehouses.map((w) => {
      let wQty = 0;
      let wAlerts = 0;
      const wVariantSet = new Set<string>();

      for (const sl of w.stock_levels) {
        const qty = Number(sl.quantity_on_hand) || 0;
        wQty += qty;
        totalQuantity += qty;
        wVariantSet.add(sl.variant_id);
        distinctVariantIds.add(sl.variant_id);

        const minStock = Number(sl.product_variants?.products?.min_stock_level) || 0;
        if (qty <= minStock) {
          wAlerts++;
          lowStockCount++;
        }
      }

      return {
        id: w.id,
        code: w.code,
        name: w.name,
        type: w.type,
        is_main: w.type === 'MAIN',
        items_count: wVariantSet.size,
        total_quantity: wQty,
        alerts_count: wAlerts,
      };
    });

    return {
      top_cards: {
        total_warehouses: warehouses.length,
        total_items: distinctVariantIds.size,
        total_quantity: totalQuantity,
        low_stock_count: lowStockCount,
      },
      warehouses: warehouseSummaries,
    };
  }

  // ─── 2. تنفيذ حركة مخزون يدوية (إدخال / إخراج / تسوية) ─────────────────────
  async createManualMovement(dto: CreateInventoryMovementDto, userId?: string) {
    const [warehouse, variant] = await Promise.all([
      this.prisma.warehouses.findUnique({ where: { id: dto.warehouse_id } }),
      this.prisma.product_variants.findUnique({ where: { id: dto.variant_id } }),
    ]);
    if (!warehouse) throw new NotFoundException('المخزن غير موجود');
    if (!variant) throw new NotFoundException('المنتج غير موجود');

    return this.prisma.$transaction(async (tx) => {
      const stock = await tx.stock_levels.findUnique({
        where: {
          variant_id_warehouse_id: {
            variant_id: dto.variant_id,
            warehouse_id: dto.warehouse_id,
          },
        },
      });

      const currentQty = stock ? Number(stock.quantity_on_hand) : 0;
      let newQty = currentQty;
      let prismaMovementType: movement_type_enum;

      if (dto.movement_type === ManualMovementTypeEnum.IN || dto.movement_type === ManualMovementTypeEnum.ADJUST_ADD) {
        newQty = currentQty + Number(dto.quantity);
        prismaMovementType = dto.movement_type === ManualMovementTypeEnum.IN ? movement_type_enum.IN : movement_type_enum.ADJUST_ADD;
      } else {
        // إخراج أو تسوية بالنقصان (فحص كفاية الرصيد لمنع السالب)
        if (currentQty < Number(dto.quantity)) {
          throw new BadRequestException(`الرصيد غير كافٍ في المخزن! المتاح حالياً: ${currentQty}`);
        }
        newQty = currentQty - Number(dto.quantity);
        prismaMovementType = dto.movement_type === ManualMovementTypeEnum.OUT ? movement_type_enum.OUT : movement_type_enum.ADJUST_REDUCE;
      }

      // تحديث رصيد المخزن
      await tx.stock_levels.upsert({
        where: {
          variant_id_warehouse_id: {
            variant_id: dto.variant_id,
            warehouse_id: dto.warehouse_id,
          },
        },
        update: { quantity_on_hand: newQty, updated_at: new Date() },
        create: {
          variant_id: dto.variant_id,
          warehouse_id: dto.warehouse_id,
          quantity_on_hand: newQty,
        },
      });

      // تسجيل الحركة في سجل الحركات
      const movement = await tx.inventory_movements.create({
        data: {
          movement_type: prismaMovementType,
          variant_id: dto.variant_id,
          warehouse_id: dto.warehouse_id,
          quantity: dto.quantity,
          unit_cost: dto.unit_cost ?? variant.weighted_avg_cost,
          notes: dto.notes,
          performed_by: userId,
          reference_type: 'MANUAL_ADJUSTMENT',
        },
      });

      return {
        movement,
        current_stock: newQty,
      };
    });
  }

  // ─── 3. تحويل بضاعة بين مخزنين ذرياً (Inter-Warehouse Transfer) ────────────
  async transferStock(dto: TransferStockDto, userId?: string) {
    if (dto.source_warehouse_id === dto.destination_warehouse_id) {
      throw new BadRequestException('لا يمكن التحويل لنفس المخزن');
    }

    const [srcWh, destWh, variant] = await Promise.all([
      this.prisma.warehouses.findUnique({ where: { id: dto.source_warehouse_id } }),
      this.prisma.warehouses.findUnique({ where: { id: dto.destination_warehouse_id } }),
      this.prisma.product_variants.findUnique({ where: { id: dto.variant_id } }),
    ]);
    if (!srcWh) throw new NotFoundException('المخزن المصدر غير موجود');
    if (!destWh) throw new NotFoundException('المخزن الهدف غير موجود');
    if (!variant) throw new NotFoundException('المنتج غير موجود');

    return this.prisma.$transaction(async (tx) => {
      // 1. فحص كفاية رصيد المخزن المصدر
      const srcStock = await tx.stock_levels.findUnique({
        where: {
          variant_id_warehouse_id: {
            variant_id: dto.variant_id,
            warehouse_id: dto.source_warehouse_id,
          },
        },
      });

      const srcCurrentQty = srcStock ? Number(srcStock.quantity_on_hand) : 0;
      if (srcCurrentQty < Number(dto.quantity)) {
        throw new BadRequestException(`الكمية المطلوبة للتحويل (${dto.quantity}) غير متوفرة في مخزن "${srcWh.name}" (المتاح: ${srcCurrentQty})`);
      }

      // 2. خفض الرصيد في المخزن المصدر
      await tx.stock_levels.update({
        where: {
          variant_id_warehouse_id: {
            variant_id: dto.variant_id,
            warehouse_id: dto.source_warehouse_id,
          },
        },
        data: {
          quantity_on_hand: srcCurrentQty - Number(dto.quantity),
          updated_at: new Date(),
        },
      });

      // 3. زيادة الرصيد في المخزن الهدف
      const destStock = await tx.stock_levels.findUnique({
        where: {
          variant_id_warehouse_id: {
            variant_id: dto.variant_id,
            warehouse_id: dto.destination_warehouse_id,
          },
        },
      });

      const destCurrentQty = destStock ? Number(destStock.quantity_on_hand) : 0;
      await tx.stock_levels.upsert({
        where: {
          variant_id_warehouse_id: {
            variant_id: dto.variant_id,
            warehouse_id: dto.destination_warehouse_id,
          },
        },
        update: {
          quantity_on_hand: destCurrentQty + Number(dto.quantity),
          updated_at: new Date(),
        },
        create: {
          variant_id: dto.variant_id,
          warehouse_id: dto.destination_warehouse_id,
          quantity_on_hand: dto.quantity,
        },
      });

      // 4. توليد رقم تحويل وتسجيل في جدول warehouse_transfers
      const count = await tx.warehouse_transfers.count();
      const transferNumber = `TRF-${Date.now().toString().slice(-6)}-${String(count + 1).padStart(3, '0')}`;

      const transfer = await tx.warehouse_transfers.create({
        data: {
          transfer_number: transferNumber,
          source_warehouse_id: dto.source_warehouse_id,
          destination_warehouse_id: dto.destination_warehouse_id,
          status: transfer_status_enum.COMPLETED,
          receive_date: new Date(),
          notes: dto.notes,
          created_by: userId,
          warehouse_transfer_items: {
            create: {
              variant_id: dto.variant_id,
              quantity_sent: dto.quantity,
              quantity_received: dto.quantity,
            },
          },
        },
      });

      // 5. تسجيل حركتي الإخراج والوارد في inventory_movements
      await tx.inventory_movements.create({
        data: {
          movement_type: movement_type_enum.TRANSFER_OUT,
          variant_id: dto.variant_id,
          warehouse_id: dto.source_warehouse_id,
          quantity: dto.quantity,
          notes: `تحويل صادر إلى ${destWh.name} - ${dto.notes || ''}`,
          reference_type: 'WAREHOUSE_TRANSFER',
          reference_id: transfer.id,
          performed_by: userId,
        },
      });

      await tx.inventory_movements.create({
        data: {
          movement_type: movement_type_enum.TRANSFER_IN,
          variant_id: dto.variant_id,
          warehouse_id: dto.destination_warehouse_id,
          quantity: dto.quantity,
          notes: `تحويل وارد من ${srcWh.name} - ${dto.notes || ''}`,
          reference_type: 'WAREHOUSE_TRANSFER',
          reference_id: transfer.id,
          performed_by: userId,
        },
      });

      return transfer;
    });
  }

  // ─── 4. استرجاع جدول سجل حركات المخزون مع الفلاتر ─────────────────────────
  async findAllMovements(query: {
    warehouse_id?: string;
    movement_type?: string;
    search?: string;
    page?: number;
    limit?: number;
  }) {
    const page = Number(query.page) || 1;
    const limit = Number(query.limit) || 20;
    const skip = (page - 1) * limit;

    const where: any = {};
    if (query.warehouse_id) where.warehouse_id = query.warehouse_id;
    if (query.movement_type) where.movement_type = query.movement_type;
    if (query.search) {
      where.product_variants = {
        OR: [
          { barcode: { contains: query.search, mode: 'insensitive' } },
          { products: { name_ar: { contains: query.search, mode: 'insensitive' } } },
        ],
      };
    }

    const [total, items] = await Promise.all([
      this.prisma.inventory_movements.count({ where }),
      this.prisma.inventory_movements.findMany({
        where,
        skip,
        take: limit,
        include: {
          warehouses: { select: { id: true, name: true } },
          product_variants: {
            include: {
              products: { select: { id: true, name_ar: true, barcode: true } },
            },
          },
          users: { select: { id: true, full_name: true, username: true } },
        },
        orderBy: { created_at: 'desc' },
      }),
    ]);

    const formattedData = items.map((m) => ({
      id: m.id,
      movement_type: m.movement_type,
      product_name: m.product_variants?.products?.name_ar ?? '—',
      barcode: m.product_variants?.barcode ?? m.product_variants?.products?.barcode ?? '—',
      warehouse_name: m.warehouses?.name ?? '—',
      quantity: Number(m.quantity),
      notes: m.notes,
      reference_type: m.reference_type,
      performed_by_name: m.users?.full_name ?? m.users?.username ?? 'مدير النظام',
      created_at: m.created_at,
    }));

    return {
      data: formattedData,
      meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
    };
  }

  // ─── 5. تنبيهات نقص المخزون ───────────────────────────────────────────────
  async getLowStockAlerts(warehouse_id?: string) {
    const stockLevels = await this.prisma.stock_levels.findMany({
      where: warehouse_id ? { warehouse_id } : {},
      include: {
        warehouses: { select: { id: true, name: true } },
        product_variants: {
          include: {
            products: { select: { id: true, name_ar: true, barcode: true, min_stock_level: true } },
          },
        },
      },
    });

    const alerts = stockLevels
      .filter((sl) => {
        const qty = Number(sl.quantity_on_hand) || 0;
        const minLevel = Number(sl.product_variants?.products?.min_stock_level) || 0;
        return qty <= minLevel;
      })
      .map((sl) => ({
        variant_id: sl.variant_id,
        warehouse_id: sl.warehouse_id,
        warehouse_name: sl.warehouses?.name,
        product_name: sl.product_variants?.products?.name_ar,
        barcode: sl.product_variants?.barcode ?? sl.product_variants?.products?.barcode,
        current_quantity: Number(sl.quantity_on_hand),
        min_stock_level: Number(sl.product_variants?.products?.min_stock_level),
      }));

    return alerts;
  }
}
```

---

## الخطوة 4: ملف الـ Controller مع Swagger

المسار: `src/modules/inventory/inventory.controller.ts`

```typescript
import { Controller, Get, Post, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { InventoryService } from './inventory.service';
import { CreateInventoryMovementDto } from './dto/create-inventory-movement.dto';
import { TransferStockDto } from './dto/transfer-stock.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('Inventory & Movements (M05)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('inventory')
export class InventoryController {
  constructor(private readonly inventoryService: InventoryService) {}

  @Get('dashboard')
  @ApiOperation({ summary: 'لوحة المخازن (البطاقات الإحصائية الأربعة + ملخص كل مخزن)' })
  async getDashboardStats() {
    const data = await this.inventoryService.getDashboardStats();
    return { success: true, data };
  }

  @Post('movements')
  @ApiOperation({ summary: 'إجراء حركة مخزون يدوية (+ حركة مخزون: إدخال أو إخراج أو تسوية)' })
  async createManualMovement(@Body() dto: CreateInventoryMovementDto, @Request() req: any) {
    const data = await this.inventoryService.createManualMovement(dto, req.user?.id);
    return { success: true, data, message: 'تم حفظ حركة المخزون وتحديث الأرصدة بنجاح' };
  }

  @Post('transfer')
  @ApiOperation({ summary: 'تحويل بضاعة بين مخزنين ذرياً (⇄ تحويل بين المخازن)' })
  async transferStock(@Body() dto: TransferStockDto, @Request() req: any) {
    const data = await this.inventoryService.transferStock(dto, req.user?.id);
    return { success: true, data, message: 'تم تحويل البضاعة بين المخازن بنجاح' };
  }

  @Get('movements')
  @ApiOperation({ summary: 'جدول سجل حركات المخزون مع الفلاتر والبحث والصفحات' })
  @ApiQuery({ name: 'warehouse_id', required: false, description: 'فلترة حسب المخزن' })
  @ApiQuery({ name: 'movement_type', required: false, description: 'نوع الحركة: IN, OUT, TRANSFER_OUT, TRANSFER_IN, ADJUST_ADD, ADJUST_REDUCE' })
  @ApiQuery({ name: 'search', required: false, description: 'بحث باسم المنتج أو الباركود' })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAllMovements(@Query() query: any) {
    return this.inventoryService.findAllMovements(query);
  }

  @Get('alerts/low-stock')
  @ApiOperation({ summary: 'قائمة تنبيهات انخفاض المخزون تحت الحد الأدنى' })
  @ApiQuery({ name: 'warehouse_id', required: false })
  async getLowStockAlerts(@Query('warehouse_id') warehouseId?: string) {
    const data = await this.inventoryService.getLowStockAlerts(warehouseId);
    return { success: true, data };
  }
}
```

---

## الخطوة 5: ملف الـ Module والتسجيل في AppModule

### 1. `src/modules/inventory/inventory.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { InventoryService } from './inventory.service';
import { InventoryController } from './inventory.controller';

@Module({
  controllers: [InventoryController],
  providers: [InventoryService],
  exports: [InventoryService],
})
export class InventoryModule {}
```

### 2. إضافة `InventoryModule` إلى `app.module.ts`:
```typescript
import { InventoryModule } from './modules/inventory/inventory.module';

@Module({
  imports: [
    // ... الموديولات السابقة
    InventoryModule,
  ],
})
export class AppModule {}
```

---

## الخطوة 6: خطة الاختبار والفحص الشامل (Swagger Checklist)

افتح `http://localhost:3000/api/docs` واختبر السيناريوهات الأربعة الأساسية لـ M05:

### ✅ سيناريو 1: فحص لوحة المخازن
- [ ] استدعاء `GET /api/v1/inventory/dashboard`.
- [ ] التأكد من ظهور البطاقات العلوية (عدد المخازن، إجمالي الأصناف، إجمالي الكمية، النواقص) وبطاقات كل مخزن.

### ✅ سيناريو 2: حركة إدخال رصيد يدوي (`IN`)
- [ ] استدعاء `POST /api/v1/inventory/movements` لنوع `IN` بكمية `50 قطعة` لمخزن معين.
- [ ] التأكد من زيادة كمية المخزن فوراّ وتسجيل الحركة في السجل.

### ✅ سيناريو 3: تحويل بضاعة بين مخزنين (`⇄ Transfer`)
- [ ] استدعاء `POST /api/v1/inventory/transfer` لنقل `20 قطعة` من المخزن الرئيسي إلى مخزن المنصور.
- [ ] التأكد من خفض `20` من المخزن الرئيسي وزيادة `20` في مخزن المنصور.
- [ ] التأكد من ظهور حركتين `TRANSFER_OUT` و `TRANSFER_IN` في جدول الحركات.

### ✅ سيناريو 4: فحص منع الرصيد السالب
- [ ] محاولة إخراج كمية أكبر من المتوفرة في المخزن.
- [ ] التأكد من رفض الطلب بـ `400 Bad Request: الرصيد غير كافٍ`.

---

> 🚀 **دليل M05 مكتمل ومحفوظ بالكامل!** يمكنك البدء بتنفيذ ملفات `InventoryModule` خطوة بخطوة وأنا معك!
