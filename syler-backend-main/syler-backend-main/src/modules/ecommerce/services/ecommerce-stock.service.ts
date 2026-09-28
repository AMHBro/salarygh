import {
    BadRequestException,
    Injectable,
} from '@nestjs/common';

import {
    Prisma,
} from '@prisma/client';

import {
    PrismaService,
} from 'src/prisma/prisma.service';

type DbClient =
    | PrismaService
    | Prisma.TransactionClient;

export interface EcommerceStockResult {
    variant_id: string;

    quantity_on_hand:
    Prisma.Decimal;

    quantity_reserved:
    Prisma.Decimal;

    available_quantity:
    Prisma.Decimal;
}

export interface EcommerceWarehouseStockResult {
    warehouse_id: string;

    warehouse_name:
    string;

    variant_id: string;

    quantity_on_hand:
    Prisma.Decimal;

    quantity_reserved:
    Prisma.Decimal;

    available_quantity:
    Prisma.Decimal;
}

@Injectable()
export class EcommerceStockService {
    constructor(
        private readonly prisma:
            PrismaService,
    ) { }

    /**
     * ============================================================
     * GET AVAILABLE STOCK FOR ONE VARIANT
     * ============================================================
     *
     * يجمع المخزون من جميع المخازن الفعالة:
     *
     * available =
     * SUM(quantity_on_hand - quantity_reserved)
     */
    async getAvailableStock(
        variantId: string,

        db?: DbClient,
    ): Promise<Prisma.Decimal> {
        const client =
            db ??
            this.prisma;

        const stocks =
            await client.stock_levels.findMany({
                where: {
                    variant_id:
                        variantId,

                    warehouses: {
                        status:
                            'ACTIVE',
                    },
                },

                select: {
                    quantity_on_hand:
                        true,

                    quantity_reserved:
                        true,
                },
            });

        let available =
            new Prisma.Decimal(
                0,
            );

        for (
            const stock of stocks
        ) {
            available =
                available.add(
                    stock.quantity_on_hand.sub(
                        stock.quantity_reserved,
                    ),
                );
        }

        return available;
    }

    /**
     * ============================================================
     * GET STOCK SUMMARY FOR ONE VARIANT
     * ============================================================
     */
    async getStockSummary(
        variantId: string,

        db?: DbClient,
    ): Promise<EcommerceStockResult> {
        const client =
            db ??
            this.prisma;

        const stocks =
            await client.stock_levels.findMany({
                where: {
                    variant_id:
                        variantId,

                    warehouses: {
                        status:
                            'ACTIVE',
                    },
                },

                select: {
                    quantity_on_hand:
                        true,

                    quantity_reserved:
                        true,
                },
            });

        let quantityOnHand =
            new Prisma.Decimal(
                0,
            );

        let quantityReserved =
            new Prisma.Decimal(
                0,
            );

        for (
            const stock of stocks
        ) {
            quantityOnHand =
                quantityOnHand.add(
                    stock.quantity_on_hand,
                );

            quantityReserved =
                quantityReserved.add(
                    stock.quantity_reserved,
                );
        }

        return {
            variant_id:
                variantId,

            quantity_on_hand:
                quantityOnHand,

            quantity_reserved:
                quantityReserved,

            available_quantity:
                quantityOnHand.sub(
                    quantityReserved,
                ),
        };
    }

    /**
     * ============================================================
     * GET AVAILABLE STOCK FOR MULTIPLE VARIANTS
     * ============================================================
     *
     * مهم للـCatalog.
     *
     * بدل:
     *
     * Product 1 -> Query
     * Product 2 -> Query
     * Product 3 -> Query
     *
     * نعمل Query واحدة فقط.
     *
     * هذا يمنع N+1 Queries.
     */
    async getAvailableStockForVariants(
        variantIds: string[],

        db?: DbClient,
    ): Promise<
        Map<
            string,
            Prisma.Decimal
        >
    > {
        const result =
            new Map<
                string,
                Prisma.Decimal
            >();

        /**
         * حتى Variant بدون Stock يرجع 0.
         */
        for (
            const variantId of variantIds
        ) {
            result.set(
                variantId,
                new Prisma.Decimal(
                    0,
                ),
            );
        }

        if (
            variantIds.length ===
            0
        ) {
            return result;
        }

        const client =
            db ??
            this.prisma;

        const stocks =
            await client.stock_levels.findMany({
                where: {
                    variant_id: {
                        in:
                            variantIds,
                    },

                    warehouses: {
                        status:
                            'ACTIVE',
                    },
                },

                select: {
                    variant_id:
                        true,

                    quantity_on_hand:
                        true,

                    quantity_reserved:
                        true,
                },
            });

        for (
            const stock of stocks
        ) {
            const current =
                result.get(
                    stock.variant_id,
                ) ??
                new Prisma.Decimal(
                    0,
                );

            const available =
                stock.quantity_on_hand.sub(
                    stock.quantity_reserved,
                );

            result.set(
                stock.variant_id,

                current.add(
                    available,
                ),
            );
        }

        return result;
    }

    /**
     * ============================================================
     * GET FULL STOCK SUMMARY FOR MULTIPLE VARIANTS
     * ============================================================
     *
     * مفيد إذا Catalog يحتاج:
     *
     * quantity_on_hand
     * quantity_reserved
     * available_quantity
     */
    async getStockSummaryForVariants(
        variantIds: string[],

        db?: DbClient,
    ): Promise<
        Map<
            string,
            EcommerceStockResult
        >
    > {
        const result =
            new Map<
                string,
                EcommerceStockResult
            >();

        for (
            const variantId of variantIds
        ) {
            result.set(
                variantId,
                {
                    variant_id:
                        variantId,

                    quantity_on_hand:
                        new Prisma.Decimal(
                            0,
                        ),

                    quantity_reserved:
                        new Prisma.Decimal(
                            0,
                        ),

                    available_quantity:
                        new Prisma.Decimal(
                            0,
                        ),
                },
            );
        }

        if (
            variantIds.length ===
            0
        ) {
            return result;
        }

        const client =
            db ??
            this.prisma;

        const stocks =
            await client.stock_levels.findMany({
                where: {
                    variant_id: {
                        in:
                            variantIds,
                    },

                    warehouses: {
                        status:
                            'ACTIVE',
                    },
                },

                select: {
                    variant_id:
                        true,

                    quantity_on_hand:
                        true,

                    quantity_reserved:
                        true,
                },
            });

        for (
            const stock of stocks
        ) {
            const current =
                result.get(
                    stock.variant_id,
                );

            if (
                !current
            ) {
                continue;
            }

            current.quantity_on_hand =
                current.quantity_on_hand.add(
                    stock.quantity_on_hand,
                );

            current.quantity_reserved =
                current.quantity_reserved.add(
                    stock.quantity_reserved,
                );

            current.available_quantity =
                current.quantity_on_hand.sub(
                    current.quantity_reserved,
                );

            result.set(
                stock.variant_id,
                current,
            );
        }

        return result;
    }

    /**
     * ============================================================
     * STOCK BREAKDOWN BY WAREHOUSE
     * ============================================================
     *
     * هذا مفيد للإدارة المركزية عندما تريد اختيار
     * المخزن الذي سيخرج منه الطلب.
     */
    async getWarehouseBreakdown(
        variantId: string,

        db?: DbClient,
    ): Promise<
        EcommerceWarehouseStockResult[]
    > {
        const client =
            db ??
            this.prisma;

        const stocks =
            await client.stock_levels.findMany({
                where: {
                    variant_id:
                        variantId,

                    warehouses: {
                        status:
                            'ACTIVE',
                    },
                },

                select: {
                    variant_id:
                        true,

                    warehouse_id:
                        true,

                    quantity_on_hand:
                        true,

                    quantity_reserved:
                        true,

                    warehouses: {
                        select: {
                            name:
                                true,
                        },
                    },
                },

                orderBy: {
                    warehouse_id:
                        'asc',
                },
            });

        return stocks.map(
            (
                stock,
            ) => ({
                warehouse_id:
                    stock.warehouse_id,

                warehouse_name:
                    stock.warehouses.name,

                variant_id:
                    stock.variant_id,

                quantity_on_hand:
                    stock.quantity_on_hand,

                quantity_reserved:
                    stock.quantity_reserved,

                available_quantity:
                    stock.quantity_on_hand.sub(
                        stock.quantity_reserved,
                    ),
            }),
        );
    }

    /**
     * ============================================================
     * GET STOCK FOR SPECIFIC WAREHOUSE
     * ============================================================
     *
     * يستخدم قبل Acceptance أو في شاشة الإدارة.
     */
    async getWarehouseStock(
        variantId: string,

        warehouseId: string,

        db?: DbClient,
    ): Promise<EcommerceStockResult> {
        const client =
            db ??
            this.prisma;

        const stock =
            await client.stock_levels.findUnique({
                where: {
                    variant_id_warehouse_id: {
                        variant_id:
                            variantId,

                        warehouse_id:
                            warehouseId,
                    },
                },

                select: {
                    variant_id:
                        true,

                    quantity_on_hand:
                        true,

                    quantity_reserved:
                        true,
                },
            });

        if (
            !stock
        ) {
            return {
                variant_id:
                    variantId,

                quantity_on_hand:
                    new Prisma.Decimal(
                        0,
                    ),

                quantity_reserved:
                    new Prisma.Decimal(
                        0,
                    ),

                available_quantity:
                    new Prisma.Decimal(
                        0,
                    ),
            };
        }

        return {
            variant_id:
                stock.variant_id,

            quantity_on_hand:
                stock.quantity_on_hand,

            quantity_reserved:
                stock.quantity_reserved,

            available_quantity:
                stock.quantity_on_hand.sub(
                    stock.quantity_reserved,
                ),
        };
    }

    /**
     * ============================================================
     * HAS AVAILABLE STOCK
     * ============================================================
     */
    async hasAvailableStock(
        variantId: string,

        requiredBaseQuantity:
            Prisma.Decimal.Value,

        db?: DbClient,
    ): Promise<boolean> {
        const required =
            new Prisma.Decimal(
                requiredBaseQuantity,
            );

        if (
            required.lte(
                0,
            )
        ) {
            return false;
        }

        const available =
            await this.getAvailableStock(
                variantId,
                db,
            );

        return available.gte(
            required,
        );
    }

    /**
     * ============================================================
     * ASSERT AVAILABLE STOCK
     * ============================================================
     *
     * مفيد إذا Service أخرى تريد Validation مباشر.
     */
    async assertAvailableStock(
        variantId: string,

        requiredBaseQuantity:
            Prisma.Decimal.Value,

        db?: DbClient,
    ): Promise<void> {
        const required =
            new Prisma.Decimal(
                requiredBaseQuantity,
            );

        if (
            required.lte(
                0,
            )
        ) {
            throw new BadRequestException({
                code:
                    'INVALID_STOCK_QUANTITY',

                message:
                    'الكمية المطلوبة يجب أن تكون أكبر من صفر',
            });
        }

        const available =
            await this.getAvailableStock(
                variantId,
                db,
            );

        if (
            available.lt(
                required,
            )
        ) {
            throw new BadRequestException({
                code:
                    'INSUFFICIENT_STOCK',

                message:
                    'الكمية المطلوبة غير متوفرة',

                details: {
                    variant_id:
                        variantId,

                    required_base_quantity:
                        required.toString(),

                    available_base_quantity:
                        available.toString(),
                },
            });
        }
    }
}