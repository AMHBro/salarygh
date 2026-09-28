import {
    Injectable,
    NotFoundException,
    BadRequestException,
} from '@nestjs/common';
import { pageWindow } from '../../common/paging';
import { PrismaService } from 'src/prisma/prisma.service';
import { ConflictResolutionService } from '../sync/conflict-resolution.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';
import { price_type_enum } from '@prisma/client';

@Injectable()
export class ProductsService {
    constructor(
        private prisma: PrismaService,
        private readonly conflicts: ConflictResolutionService,
    ) { }

    // ─── إنشاء منتج جديد (بسيط أو متعدد الأشكال) ────────────────────────────
    async create(dto: CreateProductDto, userId?: string) {
        // التحقق من وجود التصنيف ووحدة القياس
        const [category, unit] = await Promise.all([
            this.prisma.categories.findUnique({ where: { id: dto.category_id } }),
            this.prisma.units_of_measure.findUnique({ where: { id: dto.base_unit_id } }),
        ]);
        if (!category) throw new NotFoundException('التصنيف غير موجود');
        if (!unit) throw new NotFoundException('وحدة القياس الأساسية غير موجودة');

        // التحقق من تفرد الباركود قبل الإنشاء
        if (dto.barcode) {
            const existing = await this.prisma.products.findUnique({ where: { barcode: dto.barcode } });
            if (existing) throw new BadRequestException('الباركود مستخدم مسبقاً لمنتج آخر');
        }

        // إذا كان منتجاً متعدد الأشكال، يجب تمرير variants
        if (dto.has_variants && (!dto.variants || dto.variants.length === 0)) {
            throw new BadRequestException('المنتج المتعدد الأشكال يحتاج شكل واحد على الأقل');
        }

        // إذا كان منتجاً بسيطاً، يجب تمرير pricing
        if (!dto.has_variants && !dto.pricing) {
            throw new BadRequestException('المنتج البسيط يحتاج بيانات الأسعار');
        }

        return this.prisma.$transaction(async (tx) => {
            // ── إنشاء سجل المنتج الأساسي ──────────────────────────────────────
            const product = await tx.products.create({
                data: {
                    name_ar: dto.name_ar,
                    name_en: dto.name_en,
                    barcode: dto.barcode,
                    sku: dto.sku,
                    category_id: dto.category_id,
                    base_unit_id: dto.base_unit_id,
                    description: dto.description,
                    min_stock_level: dto.min_stock_level ?? 0,
                    has_variants: dto.has_variants ?? false,
                    has_expiry: dto.has_expiry ?? false,
                    has_serial: dto.has_serial ?? false,
                    image_url: dto.image_url,
                    created_by: userId,
                },
            });

            // ── منتج بسيط: ينشئ Variant افتراضي واحد مع الأسعار الأربعة ────────
            if (!dto.has_variants && dto.pricing) {
                this.validatePricing(dto.pricing);

                const variant = await tx.product_variants.create({
                    data: {
                        product_id: product.id,
                        barcode: dto.barcode,
                        sku: dto.sku,
                        weighted_avg_cost: dto.pricing.cost_price,
                        last_purchase_price: dto.pricing.cost_price,
                        attributes: {},
                    },
                });

                await this.savePrices(tx, variant.id, dto.base_unit_id, dto.pricing);
            }

            // ── منتج متعدد الأشكال: ينشئ Variant لكل شكل مع أسعاره ────────────
            if (dto.has_variants && dto.variants) {
                for (const vDto of dto.variants) {
                    this.validatePricing(vDto.pricing);

                    // التحقق من تفرد باركود كل شكل
                    if (vDto.barcode) {
                        const existingVariant = await tx.product_variants.findUnique({
                            where: { barcode: vDto.barcode },
                        });
                        if (existingVariant) {
                            throw new BadRequestException(`الباركود ${vDto.barcode} مستخدم مسبقاً`);
                        }
                    }

                    const variant = await tx.product_variants.create({
                        data: {
                            product_id: product.id,
                            barcode: vDto.barcode,
                            sku: vDto.sku,
                            attributes: vDto.attributes ?? {},
                            weighted_avg_cost: vDto.pricing.cost_price,
                            last_purchase_price: vDto.pricing.cost_price,
                        },
                    });

                    await this.savePrices(tx, variant.id, dto.base_unit_id, vDto.pricing);
                }
            }

            // إرجاع المنتج الكامل مع الأشكال والأسعار
            return tx.products.findUnique({
                where: { id: product.id },
                include: {
                    categories: { select: { id: true, name_ar: true } },
                    units_of_measure: { select: { id: true, name_ar: true, symbol: true } },
                    product_variants: { include: { product_prices: true } },
                },
            });
        });
    }

    // ─── قائمة المنتجات مع الفلاتر والـ Pagination ───────────────────────────
    async findAll(query: {
        search?: string;
        category_id?: string;
        warehouse_id?: string;
        is_active?: string;
        page?: number;
        limit?: number;
    }) {
        const { page, limit, skip } = pageWindow(query);

        const where: any = {};

        if (query.is_active !== 'all') {
            where.is_active = query.is_active === 'false' ? false : true;
        }
        if (query.category_id) where.category_id = query.category_id;
        if (query.search) {
            where.OR = [
                { name_ar: { contains: query.search, mode: 'insensitive' } },
                { barcode: { contains: query.search, mode: 'insensitive' } },
                { sku: { contains: query.search, mode: 'insensitive' } },
            ];
        }

        const [total, items] = await Promise.all([
            this.prisma.products.count({ where }),
            this.prisma.products.findMany({
                where,
                skip,
                take: limit,
                include: {
                    categories: { select: { id: true, name_ar: true } },
                    units_of_measure: { select: { id: true, name_ar: true, symbol: true } },
                    product_variants: {
                        where: { is_active: true },
                        include: {
                            product_prices: { where: { is_active: true } },
                            stock_levels: query.warehouse_id
                                ? { where: { warehouse_id: query.warehouse_id } }
                                : true,
                        },
                    },
                },
                orderBy: { created_at: 'desc' },
            }),
        ]);

        const data = items.map((p) => this.formatProductRow(p));

        return {
            data,
            meta: {
                total,
                page,
                limit,
                totalPages: Math.ceil(total / limit),
            },
        };
    }

    // ─── تفاصيل منتج واحد ────────────────────────────────────────────────────
    async findOne(id: string) {
        const product = await this.prisma.products.findUnique({
            where: { id },
            include: {
                categories: { select: { id: true, name_ar: true } },
                units_of_measure: { select: { id: true, name_ar: true, symbol: true } },
                product_variants: {
                    include: {
                        product_prices: { where: { is_active: true } },
                        stock_levels: { include: { warehouses: { select: { id: true, name: true } } } },
                    },
                },
                product_allowed_units: {
                    include: {
                        units_of_measure: { select: { id: true, name_ar: true, symbol: true } },
                    },
                },
            },
        });
        if (!product) throw new NotFoundException('المنتج غير موجود');
        return product;
    }

    // ─── البحث السريع بالباركود (للكاشير وشاشات البيع) ──────────────────────
    async findByBarcode(barcode: string) {
        // البحث في باركود المنتج أولاً ثم باركود الأشكال
        const variant = await this.prisma.product_variants.findUnique({
            where: { barcode },
            include: {
                products: {
                    include: {
                        categories: { select: { id: true, name_ar: true } },
                        units_of_measure: { select: { id: true, name_ar: true, symbol: true } },
                    },
                },
                product_prices: { where: { is_active: true } },
                stock_levels: true,
            },
        });
        if (!variant) throw new NotFoundException('لا يوجد منتج بهذا الباركود');
        return variant;
    }

    // ─── تحديث بيانات المنتج الأساسية ────────────────────────────────────────
    async update(id: string, dto: UpdateProductDto) {
        const current = await this.findOne(id);

        if (dto.base_updated_at) {
            this.conflicts.assertCanApply({
                kind: 'mutable_master',
                operation: 'UPDATE',
                serverExists: true,
                client: { updatedAt: dto.base_updated_at },
                server: { updatedAt: current.updated_at },
            });
        }

        // التحقق من تفرد الباركود إذا تم تغييره
        if (dto.barcode) {
            const existing = await this.prisma.products.findFirst({
                where: { barcode: dto.barcode, NOT: { id } },
            });
            if (existing) throw new BadRequestException('الباركود مستخدم مسبقاً');
        }

        return this.prisma.products.update({
            where: { id },
            data: {
                name_ar: dto.name_ar,
                name_en: dto.name_en,
                barcode: dto.barcode,
                sku: dto.sku,
                category_id: dto.category_id,
                description: dto.description,
                min_stock_level: dto.min_stock_level,
                has_expiry: dto.has_expiry,
                has_serial: dto.has_serial,
                image_url: dto.image_url,
                updated_at: new Date(),
            },
            include: {
                categories: { select: { id: true, name_ar: true } },
                units_of_measure: { select: { id: true, name_ar: true, symbol: true } },
            },
        });
    }

    // ─── تعطيل/تفعيل المنتج (Soft Delete) ────────────────────────────────────
    async toggleActive(id: string) {
        const product = await this.findOne(id);
        return this.prisma.products.update({
            where: { id },
            data: { is_active: !product.is_active },
        });
    }

    // ─── إحصائيات لوحة التحكم (4 بطاقات علوية في الواجهة) ───────────────────
    async getDashboardStats(warehouse_id?: string) {
        const products = await this.prisma.products.findMany({
            where: { is_active: true },
            include: {
                product_variants: {
                    where: { is_active: true },
                    include: {
                        stock_levels: warehouse_id
                            ? { where: { warehouse_id } }
                            : true,
                    },
                },
            },
        });

        let inStock = 0, lowStock = 0, outOfStock = 0;

        for (const p of products) {
            const totalQty = p.product_variants.reduce((acc, v) =>
                acc + v.stock_levels.reduce((s, sl) => s + Number(sl.quantity_on_hand ?? 0), 0), 0
            );
            const minLevel = Number(p.min_stock_level);

            if (totalQty === 0) outOfStock++;
            else if (totalQty <= minLevel) lowStock++;
            else inStock++;
        }

        return {
            total_products: products.length,
            in_stock: inStock,
            low_stock: lowStock,
            out_of_stock: outOfStock,
        };
    }

    // ─── Helpers خاصة ────────────────────────────────────────────────────────

    // التحقق من قاعدة (BR-PRD-007): لا بيع بأقل من الكلفة
    private validatePricing(pricing: any) {
        if (pricing.retail_price < pricing.cost_price) {
            throw new BadRequestException('سعر المفرد لا يمكن أن يكون أقل من سعر الكلفة (BR-PRD-007)');
        }
        if (pricing.wholesale_price < pricing.cost_price) {
            throw new BadRequestException('سعر الجملة لا يمكن أن يكون أقل من سعر الكلفة (BR-PRD-007)');
        }
        if (pricing.rep_price < pricing.cost_price) {
            throw new BadRequestException('سعر المندوب لا يمكن أن يكون أقل من سعر الكلفة (BR-PRD-007)');
        }
    }

    // حفظ الأسعار الأربعة لشكل معين
    private async savePrices(tx: any, variantId: string, unitId: string, pricing: any) {
        await tx.product_prices.createMany({
            data: [
                { variant_id: variantId, price_type: price_type_enum.COST, unit_id: unitId, price: pricing.cost_price },
                { variant_id: variantId, price_type: price_type_enum.REP, unit_id: unitId, price: pricing.rep_price },
                { variant_id: variantId, price_type: price_type_enum.WHOLESALE, unit_id: unitId, price: pricing.wholesale_price },
                { variant_id: variantId, price_type: price_type_enum.RETAIL, unit_id: unitId, price: pricing.retail_price },
            ],
        });
    }

    // تحويل سجل المنتج لصيغة جدول الواجهة
    private formatProductRow(p: any) {
        const mainVariant = p.product_variants?.[0] ?? {};
        const prices = mainVariant.product_prices ?? [];

        const getPrice = (type: price_type_enum) =>
            Number(prices.find((pr: any) => pr.price_type === type)?.price ?? 0);

        const totalStock = (mainVariant.stock_levels ?? []).reduce(
            (sum: number, sl: any) => sum + Number(sl.quantity_on_hand ?? 0), 0
        );

        const minLevel = Number(p.min_stock_level);
        let stockStatus = 'متوفر';
        if (totalStock === 0) stockStatus = 'نافد';
        else if (totalStock <= minLevel) stockStatus = 'منخفض';

        return {
            id: p.id,
            name_ar: p.name_ar,
            name_en: p.name_en,
            barcode: p.barcode ?? mainVariant.barcode,
            sku: p.sku ?? mainVariant.sku,
            category: p.categories?.name_ar ?? '—',
            category_id: p.category_id,
            base_unit: p.units_of_measure?.name_ar,
            has_variants: p.has_variants,
            quantity: totalStock,
            min_stock_level: minLevel,
            stock_status: stockStatus,
            cost_price: getPrice(price_type_enum.COST),
            rep_price: getPrice(price_type_enum.REP),
            wholesale_price: getPrice(price_type_enum.WHOLESALE),
            retail_price: getPrice(price_type_enum.RETAIL),
            is_active: p.is_active,
            created_at: p.created_at,
        };
    }
}
