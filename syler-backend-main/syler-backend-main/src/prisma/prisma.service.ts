import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {

    async onModuleInit() {
        await this.$connect();
        await this.ensureOnHandConstraint();
        console.log("Database Connected Successfully ✅");
    }

    /**
     * يمنع خصم المخزون تحت الصفر حتى لو تغيّر مسار الكتابة لاحقاً.
     * NOT VALID يطبّق القيد على الصفوف الجديدة دون إيقاف التشغيل
     * إذا وُجد رصيد سالب قديم.
     */
    private async ensureOnHandConstraint() {
        try {
            await this.$executeRawUnsafe(`
                DO $$
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1
                        FROM pg_constraint
                        WHERE conname = 'stock_levels_on_hand_nonnegative'
                    ) THEN
                        ALTER TABLE stock_levels
                            ADD CONSTRAINT stock_levels_on_hand_nonnegative
                            CHECK (quantity_on_hand >= 0) NOT VALID;
                    END IF;
                END $$;
            `);
        } catch (error) {
            console.warn('تعذر تثبيت قيد المخزون غير السالب:', error);
        }
    }

    async onModuleDestroy() {
        await this.$disconnect();
        console.log("Database Disconnected ✅");
    }



}
