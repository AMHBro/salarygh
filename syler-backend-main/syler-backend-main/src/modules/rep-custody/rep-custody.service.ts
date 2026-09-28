import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { pageWindow } from '../../common/paging';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateRepCustodyDto } from './dto/create-rep-custody.dto';
import { custody_status_enum, movement_type_enum } from '@prisma/client';

@Injectable()
export class RepCustodyService {
  constructor(private prisma: PrismaService) {}

  private async generateOrderNumber(): Promise<string> {
    const today = new Date();
    const prefix = `CUST-${today.getFullYear()}${String(today.getMonth() + 1).padStart(2, '0')}-`;
    const count = await this.prisma.rep_custody_orders.count();
    return `${prefix}${String(count + 1).padStart(4, '0')}`;
  }

  // ─── 1. إنشاء طلب عهدة لمندوب ─────────────────────────────────────────────
  async createOrder(dto: CreateRepCustodyDto, userId?: string) {
    if (!dto.items || dto.items.length === 0) {
      throw new BadRequestException('يجب تحديد مادة واحدة على الأقل في طلب العهدة');
    }

    const [rep, warehouse] = await Promise.all([
      this.prisma.representatives.findUnique({ where: { id: dto.rep_id } }),
      this.prisma.warehouses.findUnique({ where: { id: dto.warehouse_id } }),
    ]);
    if (!rep) throw new NotFoundException('المندوب غير موجود');
    if (!warehouse) throw new NotFoundException('المخزن غير موجود');

    const orderNumber = await this.generateOrderNumber();

    return this.prisma.rep_custody_orders.create({
      data: {
        order_number: orderNumber,
        rep_id: dto.rep_id,
        warehouse_id: dto.warehouse_id,
        status: custody_status_enum.PENDING,
        notes: dto.notes,
        created_by: userId,
        rep_custody_items: {
          create: dto.items.map((item) => ({
            variant_id: item.variant_id,
            quantity_sent: item.quantity,
          })),
        },
      },
      include: {
        representatives: { select: { id: true, name: true } },
        warehouses: { select: { id: true, name: true } },
        rep_custody_items: true,
      },
    });
  }

  // ─── 2. اعتماد وتجهيز وتسليم العهدة وخصم المخزن ذرياً ─────────────────────
  async dispatchOrder(id: string, userId?: string) {
    const order = await this.prisma.rep_custody_orders.findUnique({
      where: { id },
      include: { rep_custody_items: true, warehouses: true, representatives: true },
    });
    if (!order) throw new NotFoundException('طلب العهدة غير موجود');

    if (order.status === custody_status_enum.DISPATCHED) {
      throw new BadRequestException('تم تسليم وتجهيز هذه العهدة مسبقاً');
    }

    return this.prisma.$transaction(async (tx) => {
      // 1. فحص كفاية رصيد المخزن لكل مادة
      for (const item of order.rep_custody_items) {
        const stock = await tx.stock_levels.findUnique({
          where: {
            variant_id_warehouse_id: {
              variant_id: item.variant_id,
              warehouse_id: order.warehouse_id,
            },
          },
        });

        const available = stock ? Number(stock.quantity_on_hand) : 0;
        if (available < Number(item.quantity_sent)) {
          throw new BadRequestException(
            `الكمية غير كافية بالمخزن للعهدة! المتاح: ${available}، المطلوب تسليمه: ${item.quantity_sent}`,
          );
        }

        // خصم الرصيد من المخزن
        await tx.stock_levels.update({
          where: {
            variant_id_warehouse_id: {
              variant_id: item.variant_id,
              warehouse_id: order.warehouse_id,
            },
          },
          data: {
            quantity_on_hand: { decrement: item.quantity_sent },
            updated_at: new Date(),
          },
        });

        // تسجيل حركة خروج مخزني
        await tx.inventory_movements.create({
          data: {
            movement_type: movement_type_enum.OUT,
            variant_id: item.variant_id,
            warehouse_id: order.warehouse_id,
            quantity: item.quantity_sent,
            notes: `تسليم عهدة للمندوب: ${order.representatives.name}`,
            reference_type: 'REP_CUSTODY',
            reference_id: order.id,
            performed_by: userId,
          },
        });
      }

      // 2. تحديث حالة الطلب إلى DISPATCHED
      const updated = await tx.rep_custody_orders.update({
        where: { id },
        data: {
          status: custody_status_enum.DISPATCHED,
          dispatch_date: new Date(),
          updated_at: new Date(),
        },
      });

      return updated;
    });
  }

  // ─── 3. قائمة طلبات العهد ────────────────────────────────────────────────
  async findAll(query: { rep_id?: string; warehouse_id?: string; status?: custody_status_enum; page?: number; limit?: number }) {
    const { page, limit, skip } = pageWindow(query);

    const where: any = {};
    if (query.rep_id) where.rep_id = query.rep_id;
    if (query.warehouse_id) where.warehouse_id = query.warehouse_id;
    if (query.status) where.status = query.status;

    const [total, items] = await Promise.all([
      this.prisma.rep_custody_orders.count({ where }),
      this.prisma.rep_custody_orders.findMany({
        where,
        skip,
        take: limit,
        include: {
          representatives: { select: { id: true, name: true, phone: true } },
          warehouses: { select: { id: true, name: true } },
          _count: { select: { rep_custody_items: true } },
        },
        orderBy: { created_at: 'desc' },
      }),
    ]);

    return {
      data: items,
      meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
    };
  }

  // ─── 4. تفاصيل طلب عهدة واحد ─────────────────────────────────────────────
  async findOne(id: string) {
    const order = await this.prisma.rep_custody_orders.findUnique({
      where: { id },
      include: {
        representatives: true,
        warehouses: true,
        rep_custody_items: {
          include: {
            product_variants: {
              include: { products: true },
            },
          },
        },
      },
    });
    if (!order) throw new NotFoundException('طلب العهدة غير موجود');
    return order;
  }
}
