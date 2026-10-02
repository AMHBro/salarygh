import {
  BadRequestException,
  ConflictException,
  Injectable,
  OnModuleInit,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { randomUUID } from 'crypto';
import { PrismaService } from '../../prisma/prisma.service';

type SqlClient = Prisma.TransactionClient | PrismaService;

@Injectable()
export class FloorService implements OnModuleInit {
  constructor(private readonly prisma: PrismaService) {}

  async onModuleInit() {
    await this.ensureSchema();
  }

  async ensureSchema() {
    await this.prisma.$executeRawUnsafe(`
      CREATE TABLE IF NOT EXISTS stock_holds (
        id TEXT PRIMARY KEY,
        variant_id UUID NOT NULL,
        warehouse_id UUID NOT NULL,
        quantity NUMERIC NOT NULL,
        hold_key TEXT NOT NULL UNIQUE,
        expires_at TIMESTAMPTZ NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await this.prisma.$executeRawUnsafe(`
      CREATE TABLE IF NOT EXISTS floor_events (
        id BIGSERIAL PRIMARY KEY,
        event_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload JSONB NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await this.prisma.$executeRawUnsafe(`
      CREATE UNIQUE INDEX IF NOT EXISTS floor_events_type_entity_uq
      ON floor_events (event_type, entity_id)
    `);
    await this.prisma.$executeRawUnsafe(`
      CREATE TABLE IF NOT EXISTS stock_sale_locks (
        variant_id UUID PRIMARY KEY,
        warehouse_id UUID,
        sale_key TEXT,
        reason TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
  }

  async hold(input: {
    variantId: string;
    warehouseId: string;
    quantity: number;
    holdKey: string;
  }) {
    await this.ensureSchema();
    if (!Number.isFinite(input.quantity) || input.quantity <= 0) {
      throw new BadRequestException('كمية الحجز غير صالحة');
    }
    const key = input.holdKey.trim();
    if (key.length < 8 || key.length > 160) {
      throw new BadRequestException('مفتاح الحجز غير صالح');
    }

    return this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`DELETE FROM stock_holds WHERE expires_at <= NOW()`;

      const locked = await tx.$queryRaw<Array<{ variant_id: string }>>`
        SELECT variant_id::text
        FROM stock_sale_locks
        WHERE variant_id = CAST(${input.variantId} AS uuid)
      `;
      if (locked.length > 0) {
        throw new ConflictException({
          code: 'STOCK_LOCKED',
          message: 'المادة مقفلة بعد بيع متعارض، بانتظار مراجعة المدير',
        });
      }

      await tx.$queryRaw`
        SELECT id FROM stock_levels
        WHERE variant_id = CAST(${input.variantId} AS uuid)
          AND warehouse_id = CAST(${input.warehouseId} AS uuid)
        FOR UPDATE
      `;

      const stock = await tx.stock_levels.findUnique({
        where: {
          variant_id_warehouse_id: {
            variant_id: input.variantId,
            warehouse_id: input.warehouseId,
          },
        },
      });
      const onHand = stock?.quantity_on_hand ?? new Prisma.Decimal(0);
      const reserved = stock?.quantity_reserved ?? new Prisma.Decimal(0);
      const others = await tx.$queryRaw<Array<{ held: unknown }>>`
        SELECT COALESCE(SUM(quantity), 0) AS held
        FROM stock_holds
        WHERE variant_id = CAST(${input.variantId} AS uuid)
          AND warehouse_id = CAST(${input.warehouseId} AS uuid)
          AND hold_key <> ${key}
          AND expires_at > NOW()
      `;
      const held = new Prisma.Decimal(`${others[0]?.held ?? 0}`);
      const available = onHand.sub(reserved).sub(held);
      if (available.lt(input.quantity)) {
        throw new ConflictException({
          code: 'INSUFFICIENT_STOCK',
          message: 'الكمية محجوزة لحاسبة أخرى أو غير متوفرة على السيرفر',
          details: { available: Number(available) },
        });
      }

      const expires = new Date(Date.now() + 3 * 60 * 1000);
      await tx.$executeRaw`
        INSERT INTO stock_holds (id, variant_id, warehouse_id, quantity, hold_key, expires_at)
        VALUES (
          ${randomUUID()},
          CAST(${input.variantId} AS uuid),
          CAST(${input.warehouseId} AS uuid),
          ${input.quantity},
          ${key},
          ${expires}
        )
        ON CONFLICT (hold_key) DO UPDATE
        SET quantity = EXCLUDED.quantity,
            variant_id = EXCLUDED.variant_id,
            warehouse_id = EXCLUDED.warehouse_id,
            expires_at = EXCLUDED.expires_at
      `;

      return {
        accepted: true,
        available: Number(available.sub(input.quantity)),
        expires_at: expires.toISOString(),
      };
    });
  }

  /**
   * حجز طلب المتجر أو المندوب لحظة الإرسال. ينتهي بعد 15 دقيقة
   * أو عند القبول والرفض والإلغاء.
   */
  async reserveOrder(
    tx: SqlClient,
    orderId: string,
    lines: Array<{ variantId: string; baseQuantity: Prisma.Decimal }>,
  ) {
    await this.ensureSchema();
    await tx.$executeRaw`DELETE FROM stock_holds WHERE expires_at <= NOW()`;
    const expires = new Date(Date.now() + 15 * 60 * 1000);

    for (const line of lines) {
      if (line.baseQuantity.lte(0)) {
        continue;
      }

      const locked = await tx.$queryRaw<Array<{ variant_id: string }>>`
        SELECT variant_id::text
        FROM stock_sale_locks
        WHERE variant_id = CAST(${line.variantId} AS uuid)
      `;
      if (locked.length > 0) {
        throw new ConflictException({
          code: 'STOCK_LOCKED',
          message: 'المادة مقفلة بعد بيع متعارض، بانتظار مراجعة المدير',
        });
      }

      const candidates = await tx.$queryRaw<
        Array<{ warehouse_id: string }>
      >`
        SELECT s.warehouse_id::text AS warehouse_id
        FROM stock_levels s
        JOIN warehouses w ON w.id = s.warehouse_id
        WHERE s.variant_id = CAST(${line.variantId} AS uuid)
        ORDER BY CASE WHEN w.status = 'ACTIVE' THEN 0 ELSE 1 END,
                 (s.quantity_on_hand - s.quantity_reserved) DESC,
                 s.warehouse_id
      `;

      let placed = false;
      for (const candidate of candidates) {
        await tx.$queryRaw`
          SELECT id FROM stock_levels
          WHERE variant_id = CAST(${line.variantId} AS uuid)
            AND warehouse_id = CAST(${candidate.warehouse_id} AS uuid)
          FOR UPDATE
        `;
        const stock = await tx.stock_levels.findUnique({
          where: {
            variant_id_warehouse_id: {
              variant_id: line.variantId,
              warehouse_id: candidate.warehouse_id,
            },
          },
        });
        const heldRows = await tx.$queryRaw<Array<{ held: unknown }>>`
          SELECT COALESCE(SUM(quantity), 0) AS held
          FROM stock_holds
          WHERE variant_id = CAST(${line.variantId} AS uuid)
            AND warehouse_id = CAST(${candidate.warehouse_id} AS uuid)
            AND expires_at > NOW()
            AND hold_key <> ${`eco:${orderId}:${line.variantId}`}
        `;
        const available = (stock?.quantity_on_hand ?? new Prisma.Decimal(0))
          .sub(stock?.quantity_reserved ?? 0)
          .sub(new Prisma.Decimal(`${heldRows[0]?.held ?? 0}`));
        if (available.lt(line.baseQuantity)) {
          continue;
        }
        const key = `eco:${orderId}:${line.variantId}`;
        await tx.$executeRaw`
          INSERT INTO stock_holds (id, variant_id, warehouse_id, quantity, hold_key, expires_at)
          VALUES (
            ${randomUUID()},
            CAST(${line.variantId} AS uuid),
            CAST(${candidate.warehouse_id} AS uuid),
            CAST(${line.baseQuantity.toString()} AS NUMERIC),
            ${key},
            ${expires}
          )
          ON CONFLICT (hold_key) DO UPDATE
          SET quantity = EXCLUDED.quantity,
              warehouse_id = EXCLUDED.warehouse_id,
              expires_at = EXCLUDED.expires_at
        `;
        placed = true;
        break;
      }

      if (!placed) {
        throw new ConflictException({
          code: 'INSUFFICIENT_STOCK',
          message: 'الكمية محجوزة أو غير متوفرة على السيرفر',
        });
      }
    }
  }

  async releaseOrder(tx: SqlClient, orderId: string) {
    const prefix = `eco:${orderId}:%`;
    try {
      await tx.$executeRaw`DELETE FROM stock_holds WHERE hold_key LIKE ${prefix}`;
    } catch (error) {
      if (!this.isMissingRelation(error)) {
        throw error;
      }
    }
  }

  async releaseHold(holdKey: string) {
    await this.ensureSchema();
    await this.prisma.$executeRaw`
      DELETE FROM stock_holds WHERE hold_key = ${holdKey}
    `;
    return { released: true };
  }

  async releaseKeys(tx: SqlClient, keys: string[]) {
    for (const key of keys) {
      const clean = key?.trim();
      if (!clean || clean.length > 160) {
        continue;
      }
      await tx.$executeRaw`DELETE FROM stock_holds WHERE hold_key = ${clean}`;
    }
  }

  async heldQuantity(
    tx: SqlClient,
    variantId: string,
    warehouseId: string,
  ) {
    try {
      const rows = await tx.$queryRaw<Array<{ held: unknown }>>`
        SELECT COALESCE(SUM(quantity), 0) AS held
        FROM stock_holds
        WHERE variant_id = CAST(${variantId} AS uuid)
          AND warehouse_id = CAST(${warehouseId} AS uuid)
          AND expires_at > NOW()
      `;
      return new Prisma.Decimal(`${rows[0]?.held ?? 0}`);
    } catch (error) {
      if (this.isMissingRelation(error)) {
        return new Prisma.Decimal(0);
      }
      throw error;
    }
  }

  private isMissingRelation(error: unknown): boolean {
    const message = error instanceof Error ? error.message : `${error ?? ''}`;
    return message.includes('42P01') || message.includes('does not exist');
  }

  async append(
    tx: SqlClient,
    eventType: string,
    entityId: string,
    payload: Record<string, unknown>,
  ) {
    await tx.$executeRawUnsafe(
      `INSERT INTO floor_events (event_type, entity_id, payload)
       VALUES ($1, $2, $3::jsonb)
       ON CONFLICT (event_type, entity_id) DO NOTHING`,
      eventType,
      entityId,
      JSON.stringify(payload),
    );
  }

  async listEvents(after: number) {
    await this.ensureSchema();
    const cursor = Number.isFinite(after) && after > 0 ? Math.floor(after) : 0;
    const rows = await this.prisma.$queryRaw<
      Array<{
        id: bigint | number;
        event_type: string;
        entity_id: string;
        payload: unknown;
        created_at: Date;
      }>
    >`
      SELECT id, event_type, entity_id, payload, created_at
      FROM floor_events
      WHERE id > ${cursor}
      ORDER BY id
      LIMIT 100
    `;
    return rows.map((row) => ({
      id: Number(row.id),
      event_type: row.event_type,
      entity_id: row.entity_id,
      payload: row.payload,
      created_at: row.created_at,
    }));
  }

  async lockShortage(input: {
    variantId: string;
    warehouseId?: string;
    saleKey?: string;
    reason: string;
  }) {
    await this.ensureSchema();
    if (input.warehouseId) {
      await this.prisma.$executeRaw`
        INSERT INTO stock_sale_locks (variant_id, warehouse_id, sale_key, reason)
        VALUES (
          CAST(${input.variantId} AS uuid),
          CAST(${input.warehouseId} AS uuid),
          ${input.saleKey ?? null},
          ${input.reason}
        )
        ON CONFLICT (variant_id) DO NOTHING
      `;
    } else {
      await this.prisma.$executeRaw`
        INSERT INTO stock_sale_locks (variant_id, sale_key, reason)
        VALUES (
          CAST(${input.variantId} AS uuid),
          ${input.saleKey ?? null},
          ${input.reason}
        )
        ON CONFLICT (variant_id) DO NOTHING
      `;
    }
    await this.append(this.prisma, 'stock_locked', input.variantId, {
      variant_id: input.variantId,
      warehouse_id: input.warehouseId ?? null,
      sale_key: input.saleKey ?? null,
      reason: input.reason,
    });
  }

  async releaseLock(variantId: string) {
    await this.ensureSchema();
    await this.prisma.$executeRaw`
      DELETE FROM stock_sale_locks
      WHERE variant_id = CAST(${variantId} AS uuid)
    `;
    await this.append(this.prisma, 'stock_unlocked', variantId, {
      variant_id: variantId,
    });
    return { released: true };
  }

  async publishNotice(body: {
    kind?: string;
    entity_id?: string;
    warehouse_id?: string;
    customer_id?: string | null;
    supplier_id?: string | null;
    amount?: number;
    currency?: string;
    lines?: Array<{ variant_id?: string; quantity?: number }>;
  }) {
    await this.ensureSchema();
    const kind = body.kind?.trim();
    const entityId = body.entity_id?.trim();
    if (!kind || !entityId) {
      throw new BadRequestException('إشعار الصالة ناقص');
    }

    if (kind === 'sale_return') {
      return this.applyReturn({
        returnId: entityId,
        warehouseId: body.warehouse_id ?? '',
        customerId: body.customer_id ?? null,
        amount: Number(body.amount ?? 0),
        currency: body.currency === 'USD' ? 'USD' : 'IQD',
        lines: (body.lines ?? []).map((line) => ({
          variantId: line.variant_id ?? '',
          quantity: Number(line.quantity ?? 0),
        })),
      });
    }

    if (kind !== 'customer_receipt' && kind !== 'supplier_payment') {
      throw new BadRequestException('نوع الإشعار غير معروف');
    }

    const amount = Number(body.amount ?? 0);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new BadRequestException('مبلغ الإشعار غير صالح');
    }
    const currency = body.currency === 'USD' ? 'USD' : 'IQD';
    await this.append(this.prisma, kind, entityId, {
      amount,
      currency,
      customer_id: body.customer_id ?? null,
      supplier_id: body.supplier_id ?? null,
      payment_id: entityId,
    });
    return { accepted: true };
  }

  private async applyReturn(input: {
    returnId: string;
    warehouseId: string;
    customerId: string | null;
    amount: number;
    currency: string;
    lines: Array<{ variantId: string; quantity: number }>;
  }) {
    if (!input.warehouseId || input.lines.length === 0) {
      throw new BadRequestException('المرتجع بلا مخزن أو مواد');
    }
    for (const line of input.lines) {
      if (!line.variantId || !Number.isFinite(line.quantity) || line.quantity <= 0) {
        throw new BadRequestException('سطر المرتجع غير صالح');
      }
    }

    return this.prisma.$transaction(async (tx) => {
      const existing = await tx.$queryRaw<Array<{ id: bigint }>>`
        SELECT id FROM floor_events
        WHERE event_type = 'sale_return' AND entity_id = ${input.returnId}
      `;
      if (existing.length > 0) {
        return { accepted: true, already_exists: true };
      }

      for (const line of input.lines) {
        await tx.$executeRaw`
          INSERT INTO stock_levels (
            variant_id, warehouse_id, quantity_on_hand, updated_at
          )
          VALUES (
            CAST(${line.variantId} AS uuid),
            CAST(${input.warehouseId} AS uuid),
            ${line.quantity},
            NOW()
          )
          ON CONFLICT (variant_id, warehouse_id) DO UPDATE
          SET quantity_on_hand = stock_levels.quantity_on_hand + EXCLUDED.quantity_on_hand,
              updated_at = NOW()
        `;
        await this.append(tx, 'stock_delta', `${input.returnId}:${line.variantId}`, {
          variant_id: line.variantId,
          warehouse_id: input.warehouseId,
          delta: line.quantity,
          return_id: input.returnId,
        });
      }

      await this.append(tx, 'sale_return', input.returnId, {
        return_id: input.returnId,
        warehouse_id: input.warehouseId,
      });

      if (input.customerId && input.amount > 0) {
        await this.append(tx, 'sale_return_ledger', input.returnId, {
          return_id: input.returnId,
          customer_id: input.customerId,
          amount: input.amount,
          currency: input.currency,
        });
      }

      return { accepted: true };
    });
  }
}
