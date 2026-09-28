import {
    BadRequestException,
    Injectable,
    NotFoundException,
} from '@nestjs/common';

import {
    commission_type_enum,
    ecommerce_order_source_enum,
    price_type_enum,
    Prisma,
} from '@prisma/client';

import { PrismaService } from '../../../prisma/prisma.service';

export interface EcommercePriceBreakdown {
    variantId: string;
    unitId: string;

    priceType: price_type_enum;

    basePrice: Prisma.Decimal;

    commissionType: commission_type_enum | null;
    commissionValue: Prisma.Decimal;
    commissionAmount: Prisma.Decimal;

    finalPrice: Prisma.Decimal;
}

@Injectable()
export class EcommercePricingService {
    constructor(
        private readonly prisma: PrismaService,
    ) { }

    /**
     * Guest          -> RETAIL
     * Representative -> REP
     */
    resolvePriceType(
        source: ecommerce_order_source_enum,
    ): price_type_enum {
        switch (source) {
            case ecommerce_order_source_enum.GUEST:
                return price_type_enum.RETAIL;

            case ecommerce_order_source_enum.REPRESENTATIVE:
                return price_type_enum.REP;

            default:
                throw new BadRequestException({
                    code: 'ECOMMERCE_INVALID_SOURCE',
                    message: 'نوع مستخدم المتجر غير صالح',
                });
        }
    }

    /**
     * قراءة سعر من product_prices.
     */
    async getPrice(
        variantId: string,
        unitId: string,
        priceType: price_type_enum,
        db: Prisma.TransactionClient | PrismaService = this.prisma,
    ): Promise<Prisma.Decimal> {
        const record = await db.product_prices.findUnique({
            where: {
                variant_id_price_type_unit_id: {
                    variant_id: variantId,
                    price_type: priceType,
                    unit_id: unitId,
                },
            },
            select: {
                price: true,
                is_active: true,
            },
        });

        if (!record || !record.is_active) {
            throw new NotFoundException({
                code: 'ECOMMERCE_PRICE_NOT_FOUND',
                message: 'لا يوجد سعر فعال لهذا المنتج',
            });
        }

        return record.price;
    }

    async getRetailPrice(
        variantId: string,
        unitId: string,
        db: Prisma.TransactionClient | PrismaService = this.prisma,
    ) {
        return this.getPrice(
            variantId,
            unitId,
            price_type_enum.RETAIL,
            db,
        );
    }

    async getRepPrice(
        variantId: string,
        unitId: string,
        db: Prisma.TransactionClient | PrismaService = this.prisma,
    ) {
        return this.getPrice(
            variantId,
            unitId,
            price_type_enum.REP,
            db,
        );
    }
    /**
     * حساب عمولة المندوب والسعر النهائي.
     */
    calculateRepPrice(
        retailPrice: Prisma.Decimal,
        commissionType: commission_type_enum,
        commissionValue: Prisma.Decimal,
    ): {
        commissionAmount: Prisma.Decimal;
        finalPrice: Prisma.Decimal;
    } {
        if (retailPrice.isNegative()) {
            throw new BadRequestException({
                code: 'ECOMMERCE_INVALID_RETAIL_PRICE',
                message: 'سعر المنتج لا يمكن أن يكون سالباً',
            });
        }

        if (commissionValue.isNegative()) {
            throw new BadRequestException({
                code: 'ECOMMERCE_INVALID_COMMISSION',
                message: 'قيمة العمولة لا يمكن أن تكون سالبة',
            });
        }

        let commissionAmount: Prisma.Decimal;

        switch (commissionType) {
            case commission_type_enum.PERCENT:
                if (commissionValue.gt(100)) {
                    throw new BadRequestException({
                        code: 'ECOMMERCE_INVALID_COMMISSION_PERCENT',
                        message: 'نسبة العمولة لا يمكن أن تتجاوز 100%',
                    });
                }

                commissionAmount = retailPrice
                    .mul(commissionValue)
                    .div(100);

                break;

            case commission_type_enum.FIXED:
                commissionAmount = commissionValue;
                break;

            default:
                throw new BadRequestException({
                    code: 'ECOMMERCE_INVALID_COMMISSION_TYPE',
                    message: 'نوع العمولة غير صالح',
                });
        }

        return {
            commissionAmount,
            finalPrice: retailPrice.add(commissionAmount),
        };
    }

    /**
     * السعر المستخدم من Catalog / Cart / Checkout.
     */
    async resolvePrice(
        variantId: string,
        unitId: string,
        source: ecommerce_order_source_enum,
        db: Prisma.TransactionClient | PrismaService = this.prisma,
    ): Promise<EcommercePriceBreakdown> {

        /**
         * أولاً:
         * المنتج يجب أن يكون مفعلاً في Ecommerce
         * سواء كان Guest أو Representative.
         */
        const setting =
            await db.ecommerce_product_settings.findUnique({
                where: {
                    variant_id_unit_id: {
                        variant_id: variantId,
                        unit_id: unitId,
                    },
                },
                select: {
                    is_enabled: true,
                    commission_type: true,
                    commission_value: true,
                },
            });

        if (!setting || !setting.is_enabled) {
            throw new NotFoundException({
                code: 'ECOMMERCE_PRODUCT_DISABLED',
                message: 'هذا المنتج غير متاح في المتجر',
            });
        }

        const retailPrice =
            await this.getRetailPrice(
                variantId,
                unitId,
                db,
            );

        /**
         * Guest -> RETAIL
         */
        if (
            source === ecommerce_order_source_enum.GUEST
        ) {
            return {
                variantId,
                unitId,

                priceType: price_type_enum.RETAIL,

                basePrice: retailPrice,

                commissionType: null,
                commissionValue: new Prisma.Decimal(0),
                commissionAmount: new Prisma.Decimal(0),

                finalPrice: retailPrice,
            };
        }

        /**
         * منع أي Source غير معروف.
         */
        if (
            source !==
            ecommerce_order_source_enum.REPRESENTATIVE
        ) {
            throw new BadRequestException({
                code: 'ECOMMERCE_INVALID_SOURCE',
                message: 'نوع مستخدم المتجر غير صالح',
            });
        }

        /**
         * Representative: السعر المحفوظ في قائمة المندوب.
         * عمولة المندوب مبلغ ثابت على القائمة وليست خصماً من سعر المفرد.
         */
        const repPrice =
            await this.getRepPrice(
                variantId,
                unitId,
                db,
            );

        return {
            variantId,
            unitId,

            priceType: price_type_enum.REP,

            basePrice: repPrice,

            commissionType: null,
            commissionValue: new Prisma.Decimal(0),
            commissionAmount: new Prisma.Decimal(0),

            finalPrice: repPrice,
        };
    }

    /**
     * سعر القائمة الذي يختاره المندوب:
     * جملة أو مندوب أو مفرد أو كلفة.
     */
    async resolveListedPrice(
        variantId: string,
        unitId: string,
        priceType: price_type_enum,
        db: Prisma.TransactionClient | PrismaService = this.prisma,
    ): Promise<EcommercePriceBreakdown> {
        if (priceType === price_type_enum.REP) {
            return this.resolvePrice(
                variantId,
                unitId,
                ecommerce_order_source_enum.REPRESENTATIVE,
                db,
            );
        }

        const setting =
            await db.ecommerce_product_settings.findUnique({
                where: {
                    variant_id_unit_id: {
                        variant_id: variantId,
                        unit_id: unitId,
                    },
                },
                select: {
                    is_enabled: true,
                },
            });

        if (!setting || !setting.is_enabled) {
            throw new NotFoundException({
                code: 'ECOMMERCE_PRODUCT_DISABLED',
                message: 'هذا المنتج غير متاح في المتجر',
            });
        }

        const listedPrice = await this.getPrice(
            variantId,
            unitId,
            priceType,
            db,
        );

        return {
            variantId,
            unitId,
            priceType,
            basePrice: listedPrice,
            commissionType: null,
            commissionValue: new Prisma.Decimal(0),
            commissionAmount: new Prisma.Decimal(0),
            finalPrice: listedPrice,
        };
    }

    /**
     * إنشاء أو تحديث REP في product_prices.
     *
     * db يسمح باستخدام PrismaService العادي
     * أو TransactionClient من ProductService.
     */
    async syncRepPrice(
        variantId: string,
        unitId: string,
        commissionType: commission_type_enum,
        commissionValue: Prisma.Decimal,
        db: Prisma.TransactionClient | PrismaService =
            this.prisma,
    ) {
        const retailRecord =
            await db.product_prices.findUnique({
                where: {
                    variant_id_price_type_unit_id: {
                        variant_id: variantId,
                        price_type:
                            price_type_enum.RETAIL,
                        unit_id: unitId,
                    },
                },
                select: {
                    price: true,
                    is_active: true,
                },
            });

        if (!retailRecord || !retailRecord.is_active) {
            throw new NotFoundException({
                code: 'ECOMMERCE_PRICE_NOT_FOUND',
                message:
                    'لا يوجد سعر RETAIL فعال لهذا المنتج',
                details: {
                    variant_id: variantId,
                    unit_id: unitId,
                },
            });
        }

        const retailPrice =
            retailRecord.price;

        const {
            commissionAmount,
            finalPrice,
        } = this.calculateRepPrice(
            retailPrice,
            commissionType,
            commissionValue,
        );

        const repPrice =
            await db.product_prices.upsert({
                where: {
                    variant_id_price_type_unit_id: {
                        variant_id: variantId,
                        price_type:
                            price_type_enum.REP,
                        unit_id: unitId,
                    },
                },

                update: {
                    price: finalPrice,
                    is_active: true,
                    updated_at: new Date(),
                },

                create: {
                    variant_id: variantId,
                    unit_id: unitId,
                    price_type:
                        price_type_enum.REP,
                    price: finalPrice,
                    is_active: true,
                },
            });

        return {
            variantId,
            unitId,

            retailPrice,

            commissionType,
            commissionValue,
            commissionAmount,

            repPrice: repPrice.price,
        };
    }
}