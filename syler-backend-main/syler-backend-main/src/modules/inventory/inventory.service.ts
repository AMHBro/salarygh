import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { pageWindow } from '../../common/paging';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateInventoryMovementDto, ManualMovementTypeEnum } from './dto/create-inventory-movement.dto';
import { TransferStockDto } from './dto/transfer-stock.dto';
import { GetInventoryBalancesDto } from './dto/get-inventory-balances.dto';
import { Prisma, movement_type_enum, transfer_status_enum, org_status_enum } from '@prisma/client';

@Injectable()
export class InventoryService {
  constructor(private prisma: PrismaService) {}

  // ─── 1. إحصائيات لوحة المخازن (البطاقات الأربعة + بطاقات الفروع) ───────────
  async getDashboardStats() {
    const warehouses = await this.prisma.warehouses.findMany({
      where: { status: org_status_enum.ACTIVE },
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
        prismaMovementType =
          dto.movement_type === ManualMovementTypeEnum.IN ? movement_type_enum.IN : movement_type_enum.ADJUST_ADD;
      } else {
        // إخراج أو تسوية بالنقصان (فحص كفاية الرصيد لمنع السالب)
        if (currentQty < Number(dto.quantity)) {
          throw new BadRequestException(`الرصيد غير كافٍ في المخزن! المتاح حالياً: ${currentQty}`);
        }
        newQty = currentQty - Number(dto.quantity);
        prismaMovementType =
          dto.movement_type === ManualMovementTypeEnum.OUT ? movement_type_enum.OUT : movement_type_enum.ADJUST_REDUCE;
      }

      // تحديث رصيد المخزن في stock_levels
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
        throw new BadRequestException(
          `الكمية المطلوبة للتحويل (${dto.quantity}) غير متوفرة في مخزن "${srcWh.name}" (المتاح: ${srcCurrentQty})`,
        );
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
          status: transfer_status_enum.RECEIVED,
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
    const { page, limit, skip } = pageWindow(query);

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
  async getLowStockAlerts(query: { warehouse_id?: string; page?: number | string; limit?: number | string } = {}) {
    const { page, limit, skip } = pageWindow(query, 50);
    const warehouseFilter = query.warehouse_id
      ? Prisma.sql`AND sl.warehouse_id = ${query.warehouse_id}::uuid`
      : Prisma.empty;
    const rows = await this.prisma.$queryRaw<Array<{
      variant_id: string;
      warehouse_id: string;
      warehouse_name: string | null;
      product_name: string | null;
      barcode: string | null;
      current_quantity: unknown;
      min_stock_level: unknown;
    }>>`
      SELECT
        sl.variant_id,
        sl.warehouse_id,
        w.name AS warehouse_name,
        p.name_ar AS product_name,
        COALESCE(pv.barcode, p.barcode) AS barcode,
        sl.quantity_on_hand AS current_quantity,
        p.min_stock_level
      FROM stock_levels sl
      JOIN product_variants pv ON pv.id = sl.variant_id
      JOIN products p ON p.id = pv.product_id
      LEFT JOIN warehouses w ON w.id = sl.warehouse_id
      WHERE sl.quantity_on_hand <= p.min_stock_level
      ${warehouseFilter}
      ORDER BY sl.warehouse_id, p.name_ar
      LIMIT ${limit} OFFSET ${skip}
    `;
    const totalRows = await this.prisma.$queryRaw<Array<{ total: number }>>`
      SELECT COUNT(*)::int AS total
      FROM stock_levels sl
      JOIN product_variants pv ON pv.id = sl.variant_id
      JOIN products p ON p.id = pv.product_id
      WHERE sl.quantity_on_hand <= p.min_stock_level
      ${warehouseFilter}
    `;
    return {
      data: rows.map((row) => ({
        variant_id: row.variant_id,
        warehouse_id: row.warehouse_id,
        warehouse_name: row.warehouse_name,
        product_name: row.product_name,
        barcode: row.barcode,
        current_quantity: Number(row.current_quantity) || 0,
        min_stock_level: Number(row.min_stock_level) || 0,
      })),
      meta: {
        page,
        limit,
        total: Number(totalRows[0]?.total ?? 0),
      },
    };
  }

  // ─── 6. سحب ومزامنة أرصدة المخزون للأجهزة (Inventory Pull) ────────────────
  async getInventoryBalances(query: GetInventoryBalancesDto) {
    const { page, limit, skip } = pageWindow(query, 100);
    const filters = [Prisma.sql`pv.product_id IS NOT NULL`];
    if (query.warehouse_id) {
      filters.push(Prisma.sql`sl.warehouse_id = ${query.warehouse_id}::uuid`);
    }
    if (query.variant_id) {
      filters.push(Prisma.sql`sl.variant_id = ${query.variant_id}::uuid`);
    }
    if (query.product_id) {
      filters.push(Prisma.sql`pv.product_id = ${query.product_id}::uuid`);
    }
    const whereSql = Prisma.join(filters, ' AND ');
    const totalRows = await this.prisma.$queryRaw<Array<{ total: number }>>`
      SELECT COUNT(*)::int AS total
      FROM (
        SELECT sl.warehouse_id, pv.product_id
        FROM stock_levels sl
        JOIN product_variants pv ON pv.id = sl.variant_id
        WHERE ${whereSql}
        GROUP BY sl.warehouse_id, pv.product_id
      ) groups
    `;
    const total = Number(totalRows[0]?.total ?? 0);
    const keys = await this.prisma.$queryRaw<Array<{ warehouse_id: string; product_id: string }>>`
      SELECT sl.warehouse_id, pv.product_id
      FROM stock_levels sl
      JOIN product_variants pv ON pv.id = sl.variant_id
      WHERE ${whereSql}
      GROUP BY sl.warehouse_id, pv.product_id
      ORDER BY sl.warehouse_id, pv.product_id
      LIMIT ${limit} OFFSET ${skip}
    `;
    const stockLevels = keys.length === 0
      ? []
      : await this.prisma.stock_levels.findMany({
          where: {
            OR: keys.map((key) => ({
              warehouse_id: key.warehouse_id,
              ...(query.variant_id ? { variant_id: query.variant_id } : {}),
              product_variants: { product_id: key.product_id },
            })),
          },
          include: {
            product_variants: {
              include: {
                products: {
                  select: {
                    id: true,
                    name_ar: true,
                    has_variants: true,
                  },
                },
              },
            },
          },
        });

    const groupsMap = new Map<
      string,
      {
        warehouse_id: string;
        product_id: string;
        product_name: string;
        has_variants: boolean;
        total_quantity: number;
        variants: Array<{
          variant_id: string;
          sku: string;
          quantity: number;
          updated_at: Date;
        }>;
      }
    >();

    for (const sl of stockLevels) {
      const product = sl.product_variants?.products;
      if (!product) continue;

      const warehouseId = sl.warehouse_id;
      const productId = product.id;
      const key = `${warehouseId}_${productId}`;

      if (!groupsMap.has(key)) {
        groupsMap.set(key, {
          warehouse_id: warehouseId,
          product_id: productId,
          product_name: product.name_ar,
          has_variants: Boolean(product.has_variants),
          total_quantity: 0,
          variants: [],
        });
      }

      const group = groupsMap.get(key)!;
      const qty = Number(sl.quantity_on_hand) || 0;
      group.total_quantity += qty;
      group.variants.push({
        variant_id: sl.variant_id,
        sku: sl.product_variants?.sku ?? '',
        quantity: qty,
        updated_at: sl.updated_at,
      });
    }

    const paginatedData = keys
      .map((key) => groupsMap.get(`${key.warehouse_id}_${key.product_id}`))
      .filter((group) => group != null);

    return {
      data: paginatedData,
      meta: {
        page,
        limit,
        total,
      },
    };
  }
}
