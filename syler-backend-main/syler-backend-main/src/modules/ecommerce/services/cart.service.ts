import {
    BadRequestException,
    Injectable,
    NotFoundException,
} from '@nestjs/common';

import {
    ecommerce_order_source_enum,
    Prisma,
} from '@prisma/client';

import { randomUUID } from 'crypto';

import { PrismaService } from '../../../prisma/prisma.service';

import { EcommercePricingService } from './ecommerce-pricing.service';
import { EcommerceCatalogService } from './ecommerce-catalog.service';

import { AddCartItemDto } from '../dto/add-cart-item.dto';
import { UpdateCartItemDto } from '../dto/update-cart-item.dto';

export interface CartActor {
    userId?: string | null;
    cartToken?: string | null;
}

@Injectable()
export class CartService {
    constructor(
        private readonly prisma: PrismaService,
        private readonly pricingService: EcommercePricingService,
        private readonly catalogService: EcommerceCatalogService,
    ) { }

    /**
     * تحديد مصدر السلة.
     */
    private async resolveActorSource(
        actor: CartActor,
    ): Promise<ecommerce_order_source_enum> {
        return this.catalogService.resolveSource(
            actor.userId,
        );
    }

    /**
     * جلب أو إنشاء السلة.
     *
     * Representative -> user_id
     * Guest          -> session_token
     */
    async getOrCreateCart(
        actor: CartActor,
    ) {
        const source =
            await this.resolveActorSource(actor);

        /**
         * Representative
         */
        if (
            source ===
            ecommerce_order_source_enum.REPRESENTATIVE
        ) {
            if (!actor.userId) {
                throw new BadRequestException({
                    code: 'ECOMMERCE_REP_USER_REQUIRED',
                    message:
                        'معرف مستخدم المندوب مطلوب',
                });
            }

            let cart =
                await this.prisma.ecommerce_carts.findUnique({
                    where: {
                        user_id: actor.userId,
                    },
                });

            if (!cart) {
                cart =
                    await this.prisma.ecommerce_carts.create({
                        data: {
                            user_id:
                                actor.userId,

                            source:
                                ecommerce_order_source_enum.REPRESENTATIVE,
                        },
                    });
            }

            return cart;
        }

        /**
         * Guest
         */
        let cartToken =
            actor.cartToken?.trim();

        if (!cartToken) {
            cartToken =
                randomUUID();
        }

        let cart =
            await this.prisma.ecommerce_carts.findUnique({
                where: {
                    session_token:
                        cartToken,
                },
            });

        if (!cart) {
            cart =
                await this.prisma.ecommerce_carts.create({
                    data: {
                        session_token:
                            cartToken,

                        source:
                            ecommerce_order_source_enum.GUEST,
                    },
                });
        }

        return cart;
    }

    /**
     * قراءة السلة مع الأسعار الحالية.
     */
    async getCart(
        actor: CartActor,
    ) {
        const cart =
            await this.getOrCreateCart(
                actor,
            );

        const items =
            await this.prisma.ecommerce_cart_items.findMany({
                where: {
                    cart_id: cart.id,
                },

                include: {
                    variant: {
                        include: {
                            products: true,
                        },
                    },

                    unit: true,
                },

                orderBy: {
                    created_at: 'asc',
                },
            });

        const resolvedItems =
            await Promise.all(
                items.map(
                    async (item) => {
                        const pricing =
                            await this.pricingService.resolvePrice(
                                item.variant_id,
                                item.unit_id,
                                cart.source,
                            );

                        const lineTotal =
                            pricing.finalPrice.mul(
                                item.quantity,
                            );

                        return {
                            id: item.id,

                            product_id:
                                item.variant.product_id,

                            variant_id:
                                item.variant_id,

                            unit_id:
                                item.unit_id,

                            product: {
                                name_ar:
                                    item.variant
                                        .products
                                        .name_ar,

                                name_en:
                                    item.variant
                                        .products
                                        .name_en,

                                image_url:
                                    item.variant
                                        .products
                                        .image_url,
                            },

                            variant: {
                                sku:
                                    item.variant
                                        .sku,

                                barcode:
                                    item.variant
                                        .barcode,

                                attributes:
                                    item.variant
                                        .attributes,
                            },

                            unit: {
                                id:
                                    item.unit.id,

                                name_ar:
                                    item.unit
                                        .name_ar,

                                name_en:
                                    item.unit
                                        .name_en,

                                symbol:
                                    item.unit
                                        .symbol,
                            },

                            quantity:
                                item.quantity,

                            price_type:
                                pricing.priceType,

                            unit_price:
                                pricing.finalPrice,

                            line_total:
                                lineTotal,
                        };
                    },
                ),
            );

        const subtotal =
            resolvedItems.reduce(
                (
                    sum,
                    item,
                ) =>
                    sum.add(
                        item.line_total,
                    ),

                new Prisma.Decimal(0),
            );

        const totalQuantity =
            resolvedItems.reduce(
                (
                    sum,
                    item,
                ) =>
                    sum.add(
                        item.quantity,
                    ),

                new Prisma.Decimal(0),
            );

        return {
            id: cart.id,

            /**
             * Guest frontend يجب أن يحتفظ به.
             */
            cart_token:
                cart.session_token,

            source:
                cart.source,

            items:
                resolvedItems,

            summary: {
                items_count:
                    resolvedItems.length,

                quantity:
                    totalQuantity,

                subtotal,
                total: subtotal,
            },
        };
    }

    /**
     * إضافة منتج إلى السلة.
     */
    async addItem(
        actor: CartActor,
        dto: AddCartItemDto,
    ) {
        const cart =
            await this.getOrCreateCart(
                actor,
            );

        const quantity =
            new Prisma.Decimal(
                dto.quantity,
            );

        /**
         * تحقق من Variant والمنتج.
         */
        const variant =
            await this.prisma.product_variants.findUnique({
                where: {
                    id: dto.variant_id,
                },

                include: {
                    products: true,
                },
            });

        if (!variant) {
            throw new NotFoundException({
                code: 'PRODUCT_VARIANT_NOT_FOUND',
                message:
                    'المنتج غير موجود',
            });
        }

        if (
            !variant.is_active ||
            !variant.products.is_active
        ) {
            throw new BadRequestException({
                code: 'ECOMMERCE_PRODUCT_INACTIVE',
                message:
                    'المنتج غير فعال',
            });
        }

        /**
         * تحقق من إعداد Ecommerce.
         */
        let setting =
            await this.prisma.ecommerce_product_settings.findUnique({
                where: {
                    variant_id_unit_id: {
                        variant_id:
                            dto.variant_id,

                        unit_id:
                            dto.unit_id,
                    },
                },
            });

        if (!setting) {
            setting =
                await this.prisma.ecommerce_product_settings.create({
                    data: {
                        variant_id: dto.variant_id,
                        unit_id: dto.unit_id,
                        is_enabled: true,
                    },
                });
        }

        if (!setting.is_enabled) {
            throw new BadRequestException({
                code: 'ECOMMERCE_PRODUCT_DISABLED',
                message:
                    'هذا المنتج غير متاح في المتجر',
            });
        }

        /**
         * pricingService يتحقق أيضاً
         * من وجود RETAIL/REP الصحيح.
         */
        await this.pricingService.resolvePrice(
            dto.variant_id,
            dto.unit_id,
            cart.source,
        );

        /**
         * إذا العنصر موجود نزيد الكمية.
         */
        const existing =
            await this.prisma.ecommerce_cart_items.findUnique({
                where: {
                    cart_id_variant_id_unit_id: {
                        cart_id:
                            cart.id,

                        variant_id:
                            dto.variant_id,

                        unit_id:
                            dto.unit_id,
                    },
                },
            });

        if (existing) {
            return this.prisma.ecommerce_cart_items.update({
                where: {
                    id: existing.id,
                },

                data: {
                    quantity:
                        existing.quantity.add(
                            quantity,
                        ),

                    updated_at:
                        new Date(),
                },
            });
        }

        return this.prisma.ecommerce_cart_items.create({
            data: {
                cart_id:
                    cart.id,

                variant_id:
                    dto.variant_id,

                unit_id:
                    dto.unit_id,

                quantity,
            },
        });
    }

    /**
     * تعديل كمية عنصر.
     */
    async updateItem(
        actor: CartActor,
        itemId: string,
        dto: UpdateCartItemDto,
    ) {
        const cart =
            await this.getOrCreateCart(
                actor,
            );

        /**
         * مهم:
         * ownership validation.
         */
        const item =
            await this.prisma.ecommerce_cart_items.findFirst({
                where: {
                    id: itemId,
                    cart_id:
                        cart.id,
                },
            });

        if (!item) {
            throw new NotFoundException({
                code: 'ECOMMERCE_CART_ITEM_NOT_FOUND',
                message:
                    'عنصر السلة غير موجود',
            });
        }

        /**
         * نتأكد أن المنتج ما زال متاحاً.
         */
        await this.pricingService.resolvePrice(
            item.variant_id,
            item.unit_id,
            cart.source,
        );

        return this.prisma.ecommerce_cart_items.update({
            where: {
                id: item.id,
            },

            data: {
                quantity:
                    new Prisma.Decimal(
                        dto.quantity,
                    ),

                updated_at:
                    new Date(),
            },
        });
    }

    /**
     * حذف عنصر.
     */
    async removeItem(
        actor: CartActor,
        itemId: string,
    ) {
        const cart =
            await this.getOrCreateCart(
                actor,
            );

        const item =
            await this.prisma.ecommerce_cart_items.findFirst({
                where: {
                    id: itemId,
                    cart_id:
                        cart.id,
                },
            });

        if (!item) {
            throw new NotFoundException({
                code: 'ECOMMERCE_CART_ITEM_NOT_FOUND',
                message:
                    'عنصر السلة غير موجود',
            });
        }

        await this.prisma.ecommerce_cart_items.delete({
            where: {
                id: item.id,
            },
        });

        return {
            success: true,
        };
    }

    /**
     * تفريغ السلة.
     */
    async clearCart(
        actor: CartActor,
    ) {
        const cart =
            await this.getOrCreateCart(
                actor,
            );

        await this.prisma.ecommerce_cart_items.deleteMany({
            where: {
                cart_id:
                    cart.id,
            },
        });

        return {
            success: true,
        };
    }
}