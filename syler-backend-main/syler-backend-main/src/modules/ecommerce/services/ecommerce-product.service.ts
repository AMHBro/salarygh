import {
    BadRequestException,
    Injectable,
    NotFoundException,
} from '@nestjs/common';

import {
    Prisma,
    commission_type_enum,
    price_type_enum,
} from '@prisma/client';

import { PrismaService } from '../../../prisma/prisma.service';
import { EcommercePricingService } from './ecommerce-pricing.service';

import { UpdateEcommerceProductSettingDto } from '../dto/update-ecommerce-product-setting.dto';

@Injectable()
export class EcommerceProductService {
    constructor(
        private readonly prisma: PrismaService,
        private readonly pricingService: EcommercePricingService,
    ) { }

    /**
     * جلب إعداد المتجر لمنتج/Variant ووحدة محددة
     */
    async getSetting(
        variantId: string,
        unitId: string,
    ) {
        const setting =
            await this.prisma.ecommerce_product_settings.findUnique({
                where: {
                    variant_id_unit_id: {
                        variant_id: variantId,
                        unit_id: unitId,
                    },
                },
                include: {
                    variant: {
                        include: {
                            products: true,
                        },
                    },
                    unit: true,
                },
            });

        if (!setting) {
            throw new NotFoundException({
                code: 'ECOMMERCE_PRODUCT_SETTING_NOT_FOUND',
                message: 'إعدادات المنتج في المتجر غير موجودة',
            });
        }

        const retailPrice =
            await this.pricingService.getRetailPrice(
                variantId,
                unitId,
            );

        let repPrice: Prisma.Decimal | null = null;

        try {
            repPrice =
                await this.pricingService.getRepPrice(
                    variantId,
                    unitId,
                );
        } catch {
            repPrice = null;
        }

        return {
            id: setting.id,

            variant_id: setting.variant_id,
            unit_id: setting.unit_id,

            is_enabled: setting.is_enabled,

            commission_type: setting.commission_type,
            commission_value: setting.commission_value,

            sort_order: setting.sort_order,

            retail_price: retailPrice,
            rep_price: repPrice,

            product: {
                id: setting.variant.products.id,
                name_ar: setting.variant.products.name_ar,
                name_en: setting.variant.products.name_en,
            },

            variant: {
                id: setting.variant.id,
                sku: setting.variant.sku,
                barcode: setting.variant.barcode,
                attributes: setting.variant.attributes,
            },

            unit: {
                id: setting.unit.id,
                name_ar: setting.unit.name_ar,
                name_en: setting.unit.name_en,
                symbol: setting.unit.symbol,
            },
        };
    }

    /**
     * إنشاء أو تحديث إعدادات المنتج للمتجر
     */
    async upsertSetting(
        variantId: string,
        dto: UpdateEcommerceProductSettingDto,
    ) {
        const {
            unit_id,
            is_enabled = true,
            commission_type,
            commission_value,
            sort_order = 0,
        } = dto;

        /**
         * 1. التحقق من Variant
         */
        const variant =
            await this.prisma.product_variants.findUnique({
                where: {
                    id: variantId,
                },
                include: {
                    products: true,
                },
            });

        if (!variant) {
            throw new NotFoundException({
                code: 'PRODUCT_VARIANT_NOT_FOUND',
                message: 'المنتج أو الـ Variant غير موجود',
            });
        }

        if (!variant.is_active) {
            throw new BadRequestException({
                code: 'PRODUCT_VARIANT_INACTIVE',
                message: 'لا يمكن تفعيل Variant غير فعال في المتجر',
            });
        }

        if (!variant.products.is_active) {
            throw new BadRequestException({
                code: 'PRODUCT_INACTIVE',
                message: 'لا يمكن تفعيل منتج غير فعال في المتجر',
            });
        }

        /**
         * 2. التحقق من Unit
         */
        const unit =
            await this.prisma.units_of_measure.findUnique({
                where: {
                    id: unit_id,
                },
            });

        if (!unit) {
            throw new NotFoundException({
                code: 'UNIT_NOT_FOUND',
                message: 'وحدة القياس غير موجودة',
            });
        }

        if (!unit.is_active) {
            throw new BadRequestException({
                code: 'UNIT_INACTIVE',
                message: 'وحدة القياس غير فعالة',
            });
        }

        /**
         * 3. التحقق أن الوحدة مسموحة للمنتج في البيع
         */
        const allowedUnit =
            await this.prisma.product_allowed_units.findUnique({
                where: {
                    product_id_unit_id: {
                        product_id: variant.product_id,
                        unit_id,
                    },
                },
            });

        /**
         * في بعض المشاريع base_unit قد لا تكون مسجلة داخل
         * product_allowed_units، لذلك نسمح بها إذا كانت base unit.
         */
        const isBaseUnit =
            variant.products.base_unit_id === unit_id;

        if (!isBaseUnit && (!allowedUnit || !allowedUnit.can_sell)) {
            throw new BadRequestException({
                code: 'ECOMMERCE_UNIT_NOT_SELLABLE',
                message: 'وحدة القياس غير مسموحة للبيع لهذا المنتج',
            });
        }

        /**
         * 4. التأكد من وجود RETAIL price
         */
        await this.pricingService.getRetailPrice(
            variantId,
            unit_id,
        );

        /**
         * 5. Validation إضافي للعمولة
         */
        const commissionDecimal =
            new Prisma.Decimal(commission_value);

        if (commissionDecimal.isNegative()) {
            throw new BadRequestException({
                code: 'ECOMMERCE_INVALID_COMMISSION',
                message: 'قيمة العمولة لا يمكن أن تكون سالبة',
            });
        }

        if (
            commission_type === commission_type_enum.PERCENT &&
            commissionDecimal.gt(100)
        ) {
            throw new BadRequestException({
                code: 'ECOMMERCE_INVALID_COMMISSION_PERCENT',
                message: 'نسبة العمولة لا يمكن أن تتجاوز 100%',
            });
        }

        /**
         * 6. Transaction
         *
         * نحفظ Setting ثم نزامن REP price.
         */
        const result = await this.prisma.$transaction(
            async (tx) => {
                const setting =
                    await tx.ecommerce_product_settings.upsert({
                        where: {
                            variant_id_unit_id: {
                                variant_id: variantId,
                                unit_id,
                            },
                        },

                        update: {
                            is_enabled,
                            commission_type,
                            commission_value: commissionDecimal,
                            sort_order,
                            updated_at: new Date(),
                        },

                        create: {
                            variant_id: variantId,
                            unit_id,

                            is_enabled,

                            commission_type,
                            commission_value: commissionDecimal,

                            sort_order,
                        },
                    });

                return setting;
            },
        );

        /**
         * ملاحظة:
         * syncRepPrice حالياً تستخدم prisma الأساسي وليس tx.
         *
         * لاحقاً ممكن نطور EcommercePricingService لدعم Transaction Client.
         */
        const pricing =
            await this.pricingService.syncRepPrice(
                variantId,
                unit_id,
                commission_type,
                commissionDecimal,
            );

        return {
            setting: {
                id: result.id,

                variant_id: result.variant_id,
                unit_id: result.unit_id,

                is_enabled: result.is_enabled,

                commission_type: result.commission_type,
                commission_value: result.commission_value,

                sort_order: result.sort_order,
            },

            pricing: {
                retail_price: pricing.retailPrice,
                commission_amount: pricing.commissionAmount,
                rep_price: pricing.repPrice,
            },
        };
    }

    /**
     * تعطيل المنتج من المتجر بدون حذفه
     */
    async disable(
        variantId: string,
        unitId: string,
    ) {
        const setting =
            await this.prisma.ecommerce_product_settings.findUnique({
                where: {
                    variant_id_unit_id: {
                        variant_id: variantId,
                        unit_id: unitId,
                    },
                },
            });

        if (!setting) {
            throw new NotFoundException({
                code: 'ECOMMERCE_PRODUCT_SETTING_NOT_FOUND',
                message: 'إعدادات المنتج في المتجر غير موجودة',
            });
        }

        const updated =
            await this.prisma.ecommerce_product_settings.update({
                where: {
                    id: setting.id,
                },

                data: {
                    is_enabled: false,
                    updated_at: new Date(),
                },
            });

        return updated;
    }

    /**
     * إعادة تفعيل المنتج بدون تغيير العمولة
     */
    async enable(
        variantId: string,
        unitId: string,
    ) {
        const setting =
            await this.prisma.ecommerce_product_settings.findUnique({
                where: {
                    variant_id_unit_id: {
                        variant_id: variantId,
                        unit_id: unitId,
                    },
                },
            });

        if (!setting) {
            throw new NotFoundException({
                code: 'ECOMMERCE_PRODUCT_SETTING_NOT_FOUND',
                message: 'إعدادات المنتج في المتجر غير موجودة',
            });
        }

        /**
         * نتأكد أن REP price متزامن قبل التفعيل.
         */
        await this.pricingService.syncRepPrice(
            variantId,
            unitId,
            setting.commission_type,
            setting.commission_value,
        );

        return this.prisma.ecommerce_product_settings.update({
            where: {
                id: setting.id,
            },

            data: {
                is_enabled: true,
                updated_at: new Date(),
            },
        });
    }

    /**
     * List للمنتجات المفعلة للمتجر
     * سيستخدم لاحقاً في Admin.
     */
    async listSettings(params?: {
        enabled?: boolean;
        search?: string;
    }) {
        const where: Prisma.ecommerce_product_settingsWhereInput = {};

        if (typeof params?.enabled === 'boolean') {
            where.is_enabled = params.enabled;
        }

        if (params?.search) {
            where.variant = {
                products: {
                    OR: [
                        {
                            name_ar: {
                                contains: params.search,
                                mode: 'insensitive',
                            },
                        },
                        {
                            name_en: {
                                contains: params.search,
                                mode: 'insensitive',
                            },
                        },
                        {
                            sku: {
                                contains: params.search,
                                mode: 'insensitive',
                            },
                        },
                        {
                            barcode: {
                                contains: params.search,
                                mode: 'insensitive',
                            },
                        },
                    ],
                },
            };
        }

        return this.prisma.ecommerce_product_settings.findMany({
            where,

            include: {
                variant: {
                    include: {
                        products: true,
                    },
                },
                unit: true,
            },

            orderBy: [
                {
                    sort_order: 'asc',
                },
                {
                    created_at: 'desc',
                },
            ],
        });
    }
}