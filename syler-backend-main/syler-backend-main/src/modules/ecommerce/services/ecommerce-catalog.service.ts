import {
    Injectable,
    NotFoundException,
} from '@nestjs/common';

import {
    ecommerce_order_source_enum,
    org_status_enum,
    price_type_enum,
    Prisma,
    rep_status_enum,

} from '@prisma/client';

import { PrismaService } from '../../../prisma/prisma.service';

import { CatalogQueryDto } from '../dto/catalog-query.dto';

@Injectable()
export class EcommerceCatalogService {
    constructor(
        private readonly prisma: PrismaService,
    ) { }

    /**
     * تحديد نوع مستخدم المتجر.
     *
     * بدون User -> Guest
     * Representative ACTIVE -> Representative
     * غير ذلك -> Guest
     */
    async resolveSource(
        userId?: string | null,
    ): Promise<ecommerce_order_source_enum> {
        if (!userId) {
            return ecommerce_order_source_enum.GUEST;
        }

        const representative =
            await this.prisma.representatives.findUnique({
                where: {
                    user_id: userId,
                },
                select: {
                    status: true,
                },
            });

        if (
            representative &&
            representative.status === rep_status_enum.ACTIVE
        ) {
            return ecommerce_order_source_enum.REPRESENTATIVE;
        }

        return ecommerce_order_source_enum.GUEST;
    }

    /**
     * Catalog الرئيسي.
     */
    async getProducts(
        query: CatalogQueryDto,
        userId?: string | null,
    ) {
        const source =
            await this.resolveSource(userId);

        const priceType =
            source === ecommerce_order_source_enum.REPRESENTATIVE
                ? price_type_enum.REP
                : price_type_enum.RETAIL;

        const page = query.page || 1;
        const limit = query.limit || 20;

        const skip =
            (page - 1) * limit;

        const search =
            query.search?.trim();

        const where: Prisma.ecommerce_product_settingsWhereInput = {
            is_enabled: true,

            variant: {
                is_active: true,

                products: {
                    is_active: true,

                    ...(query.category_id
                        ? {
                            category_id:
                                query.category_id,
                        }
                        : {}),
                },
            },
        };

        /**
         * البحث.
         */
        if (search) {
            where.AND = [
                {
                    OR: [
                        {
                            variant: {
                                sku: {
                                    contains: search,
                                    mode: 'insensitive',
                                },
                            },
                        },

                        {
                            variant: {
                                barcode: {
                                    contains: search,
                                    mode: 'insensitive',
                                },
                            },
                        },

                        {
                            variant: {
                                products: {
                                    name_ar: {
                                        contains: search,
                                        mode: 'insensitive',
                                    },
                                },
                            },
                        },

                        {
                            variant: {
                                products: {
                                    name_en: {
                                        contains: search,
                                        mode: 'insensitive',
                                    },
                                },
                            },
                        },

                        {
                            variant: {
                                products: {
                                    sku: {
                                        contains: search,
                                        mode: 'insensitive',
                                    },
                                },
                            },
                        },

                        {
                            variant: {
                                products: {
                                    barcode: {
                                        contains: search,
                                        mode: 'insensitive',
                                    },
                                },
                            },
                        },
                    ],
                },
            ];
        }

        /**
         * قراءة Settings الأساسية.
         *
         * لا نقرأ Price وStock لكل صف على حدة
         * حتى نتجنب N+1.
         */
        const [settings, total] =
            await this.prisma.$transaction([
                this.prisma.ecommerce_product_settings.findMany({
                    where,

                    skip,
                    take: limit,

                    include: {
                        variant: {
                            include: {
                                products: {
                                    include: {
                                        categories: true,
                                    },
                                },
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
                }),

                this.prisma.ecommerce_product_settings.count({
                    where,
                }),
            ]);

        if (settings.length === 0) {
            return {
                data: [],
                meta: {
                    page,
                    per_page: limit,
                    total,
                    total_pages: 0,
                },
            };
        }

        const variantIds = [
            ...new Set(
                settings.map(
                    (item) => item.variant_id,
                ),
            ),
        ];

        const unitIds = [
            ...new Set(
                settings.map(
                    (item) => item.unit_id,
                ),
            ),
        ];

        /**
         * جلب الأسعار المطلوبة دفعة واحدة.
         */
        const prices =
            await this.prisma.product_prices.findMany({
                where: {
                    variant_id: {
                        in: variantIds,
                    },

                    unit_id: {
                        in: unitIds,
                    },

                    price_type: priceType,

                    is_active: true,
                },

                select: {
                    variant_id: true,
                    unit_id: true,
                    price: true,
                    price_type: true,
                },
            });

        /**
         * Map سريع للأسعار.
         */
        const priceMap =
            new Map<string, Prisma.Decimal>();

        for (const price of prices) {
            priceMap.set(
                this.priceKey(
                    price.variant_id,
                    price.unit_id,
                ),
                price.price,
            );
        }

        /**
         * قراءة المخزون لكل Variants دفعة واحدة.
         */
        const stocks =
            await this.prisma.stock_levels.findMany({
                where: {
                    variant_id: {
                        in: variantIds,
                    },

                    warehouses: {
                        status: org_status_enum.ACTIVE,
                    },
                },

                select: {
                    variant_id: true,
                    quantity_on_hand: true,
                    quantity_reserved: true,
                },
            });

        /**
         * تجميع المخزون بالـBase Unit.
         */
        const stockMap =
            new Map<string, Prisma.Decimal>();

        for (const stock of stocks) {
            const available =
                stock.quantity_on_hand.sub(
                    stock.quantity_reserved,
                );

            const current =
                stockMap.get(stock.variant_id) ??
                new Prisma.Decimal(0);

            stockMap.set(
                stock.variant_id,
                current.add(
                    available.isNegative()
                        ? new Prisma.Decimal(0)
                        : available,
                ),
            );
        }

        /**
         * بناء Response.
         *
         * إذا لا يوجد السعر المطلوب:
         * لا نظهر المنتج أصلاً.
         */
        const data = settings
            .map((setting) => {
                const price =
                    priceMap.get(
                        this.priceKey(
                            setting.variant_id,
                            setting.unit_id,
                        ),
                    );

                if (!price) {
                    return null;
                }

                const availableBase =
                    stockMap.get(
                        setting.variant_id,
                    ) ??
                    new Prisma.Decimal(0);

                /**
                 * نفترض أن conversion_factor
                 * يمثل عدد الـBase Units داخل هذه الوحدة.
                 *
                 * مثال:
                 * carton = 12 pieces
                 *
                 * base stock = 120
                 * available carton = 10
                 */
                const conversionFactor =
                    setting.unit.conversion_factor;

                const availableQuantity =
                    conversionFactor.gt(0)
                        ? availableBase.div(
                            conversionFactor,
                        )
                        : availableBase;

                const product =
                    setting.variant.products;

                return {
                    product_id: product.id,
                    variant_id:
                        setting.variant.id,

                    name_ar:
                        product.name_ar,

                    name_en:
                        product.name_en,

                    description:
                        product.description,

                    sku:
                        setting.variant.sku ??
                        product.sku,

                    barcode:
                        setting.variant.barcode ??
                        product.barcode,

                    image_url:
                        this.storeImageRef(
                            product.id,
                            product.image_url,
                            product.updated_at,
                        ),

                    images:
                        product.images,

                    category:
                        product.categories
                            ? {
                                id:
                                    product.categories.id,

                                name_ar:
                                    product.categories.name_ar,

                                name_en:
                                    product.categories.name_en,
                            }
                            : null,

                    variant: {
                        id:
                            setting.variant.id,

                        attributes:
                            setting.variant.attributes,
                    },

                    unit: {
                        id:
                            setting.unit.id,

                        name_ar:
                            setting.unit.name_ar,

                        name_en:
                            setting.unit.name_en,

                        symbol:
                            setting.unit.symbol,

                        conversion_factor:
                            setting.unit.conversion_factor,
                    },

                    price_type:
                        priceType,

                    price,

                    available_quantity:
                        availableQuantity,

                    available_quantity_base:
                        availableBase,

                    in_stock:
                        availableBase.gt(0),
                };
            })
            .filter(
                (
                    item,
                ): item is NonNullable<
                    typeof item
                > => item !== null,
            );

        return {
            data,

            meta: {
                page,
                per_page: limit,
                total,
                total_pages:
                    Math.ceil(
                        total / limit,
                    ),
            },

            context: {
                source,
                price_type: priceType,
            },
        };
    }

    private priceKey(
        variantId: string,
        unitId: string,
    ): string {
        return `${variantId}:${unitId}`;
    }

    async getCategories() {
        const categories =
            await this.prisma.categories.findMany({
                where: {
                    is_active: true,

                    products: {
                        some: {
                            is_active: true,

                            product_variants: {
                                some: {
                                    is_active: true,

                                    ecommerce_product_settings: {
                                        some: {
                                            is_enabled: true,
                                        },
                                    },
                                },
                            },
                        },
                    },
                },

                select: {
                    id: true,
                    name_ar: true,
                    name_en: true,
                    image_url: true,
                    parent_id: true,
                    level: true,
                    order_index: true,
                },

                orderBy: [
                    {
                        order_index: 'asc',
                    },
                    {
                        name_ar: 'asc',
                    },
                ],
            });

        return {
            data: categories,
        };
    }
    async getProduct(
        variantId: string,
        userId?: string | null,
    ) {
        const source =
            await this.resolveSource(userId);

        const priceType =
            source ===
                ecommerce_order_source_enum.REPRESENTATIVE
                ? price_type_enum.REP
                : price_type_enum.RETAIL;

        const settings =
            await this.prisma.ecommerce_product_settings.findMany({
                where: {
                    variant_id: variantId,
                    is_enabled: true,

                    variant: {
                        is_active: true,

                        products: {
                            is_active: true,
                        },
                    },
                },

                include: {
                    variant: {
                        include: {
                            products: {
                                include: {
                                    categories: true,
                                },
                            },
                        },
                    },

                    unit: true,
                },

                orderBy: {
                    sort_order: 'asc',
                },
            });

        if (settings.length === 0) {
            throw new NotFoundException({
                code: 'ECOMMERCE_PRODUCT_NOT_FOUND',
                message:
                    'المنتج غير موجود أو غير متاح في المتجر',
            });
        }

        const prices =
            await this.prisma.product_prices.findMany({
                where: {
                    variant_id: variantId,

                    unit_id: {
                        in: settings.map(
                            (item) => item.unit_id,
                        ),
                    },

                    price_type: priceType,
                    is_active: true,
                },
            });

        const priceMap =
            new Map(
                prices.map(
                    (price) => [
                        price.unit_id,
                        price.price,
                    ],
                ),
            );

        const stock =
            await this.prisma.stock_levels.aggregate({
                where: {
                    variant_id: variantId,

                    warehouses: {
                        status:
                            org_status_enum.ACTIVE,
                    },
                },

                _sum: {
                    quantity_on_hand: true,
                    quantity_reserved: true,
                },
            });

        const onHand =
            stock._sum.quantity_on_hand ??
            new Prisma.Decimal(0);

        const reserved =
            stock._sum.quantity_reserved ??
            new Prisma.Decimal(0);

        let available =
            onHand.sub(reserved);

        if (available.isNegative()) {
            available =
                new Prisma.Decimal(0);
        }

        const first =
            settings[0];

        const product =
            first.variant.products;

        return {
            data: {
                product_id:
                    product.id,

                variant_id:
                    first.variant.id,

                name_ar:
                    product.name_ar,

                name_en:
                    product.name_en,

                description:
                    product.description,

                sku:
                    first.variant.sku ??
                    product.sku,

                barcode:
                    first.variant.barcode ??
                    product.barcode,

                image_url:
                    this.storeImageRef(
                        product.id,
                        product.image_url,
                        product.updated_at,
                    ),

                images:
                    product.images,

                category:
                    product.categories
                        ? {
                            id:
                                product.categories.id,

                            name_ar:
                                product.categories.name_ar,

                            name_en:
                                product.categories.name_en,
                        }
                        : null,

                attributes:
                    first.variant.attributes,

                available_quantity_base:
                    available,

                in_stock:
                    available.gt(0),

                units: settings
                    .map(
                        (setting) => {
                            const price =
                                priceMap.get(
                                    setting.unit_id,
                                );

                            if (!price) {
                                return null;
                            }

                            const factor =
                                setting.unit
                                    .conversion_factor;

                            const availableQuantity =
                                factor.gt(0)
                                    ? available.div(
                                        factor,
                                    )
                                    : available;

                            return {
                                id:
                                    setting.unit.id,

                                name_ar:
                                    setting.unit.name_ar,

                                name_en:
                                    setting.unit.name_en,

                                symbol:
                                    setting.unit.symbol,

                                conversion_factor:
                                    factor,

                                price_type:
                                    priceType,

                                price,

                                available_quantity:
                                    availableQuantity,
                            };
                        },
                    )
                    .filter(Boolean),
            },

            context: {
                source,
                price_type:
                    priceType,
            },
        };
    }

    async getWarehouse(
        audience?: string,
        pageRaw?: string,
        limitRaw?: string,
        searchRaw?: string,
        categoryRaw?: string,
    ) {
        const priceType =
            audience === 'agent'
                ? price_type_enum.REP
                : price_type_enum.RETAIL;
        const limit = Math.min(40, Math.max(1, Number(limitRaw) || 20));
        const page = Math.max(1, Number(pageRaw) || 1);
        const offset = (page - 1) * limit;
        const search = (searchRaw ?? '').trim().slice(0, 80);
        const like = search ? `%${search}%` : null;
        const categoryId = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(categoryRaw ?? '')
            ? categoryRaw
            : null;

        const idRows = await this.prisma.$queryRaw<{ id: string }[]>(Prisma.sql`
            SELECT p.id
            FROM public.products p
            WHERE p.is_active = true
              AND (${like}::text IS NULL OR p.name_ar ILIKE ${like} OR COALESCE(p.sku, '') ILIKE ${like} OR COALESCE(p.barcode, '') ILIKE ${like})
              AND (${categoryId}::uuid IS NULL OR p.category_id = ${categoryId}::uuid)
              AND EXISTS (
                SELECT 1
                FROM public.product_variants v
                JOIN public.stock_levels s ON s.variant_id = v.id
                WHERE v.product_id = p.id
                  AND v.is_active = true
                GROUP BY v.id
                HAVING SUM(s.quantity_on_hand - s.quantity_reserved)
                    - COALESCE((
                        SELECT SUM(h.quantity)
                        FROM public.stock_holds h
                        WHERE h.variant_id = v.id
                          AND h.expires_at > NOW()
                      ), 0) > 0
              )
            ORDER BY p.name_ar ASC
            LIMIT ${limit + 1}
            OFFSET ${offset}
        `);
        const hasMore = idRows.length > limit;
        const pageIds = idRows.slice(0, limit).map((row) => row.id);

        const familyRows = page === 1
            ? await this.prisma.$queryRaw<{ id: string; name: string }[]>(Prisma.sql`
            SELECT DISTINCT c.id, c.name_ar AS name
            FROM public.products p
            JOIN public.categories c ON c.id = p.category_id
            WHERE p.is_active = true
              AND EXISTS (
                SELECT 1
                FROM public.product_variants v
                JOIN public.stock_levels s ON s.variant_id = v.id
                WHERE v.product_id = p.id
                  AND v.is_active = true
                GROUP BY v.id
                HAVING SUM(s.quantity_on_hand - s.quantity_reserved)
                    - COALESCE((
                        SELECT SUM(h.quantity)
                        FROM public.stock_holds h
                        WHERE h.variant_id = v.id
                          AND h.expires_at > NOW()
                      ), 0) > 0
              )
            ORDER BY c.name_ar ASC
        `)
            : [];

        const rows = pageIds.length === 0
            ? []
            : await this.prisma.products.findMany({
            where: { id: { in: pageIds } },
            include: {
                categories: {
                    select: { id: true, name_ar: true },
                },
                units_of_measure: {
                    select: { name_ar: true },
                },
                product_variants: {
                    where: { is_active: true },
                    include: {
                        product_prices: {
                            where: {
                                is_active: true,
                                price_type: {
                                    in: [
                                        price_type_enum.RETAIL,
                                        price_type_enum.REP,
                                        price_type_enum.WHOLESALE,
                                    ],
                                },
                            },
                        },
                        stock_levels: true,
                    },
                },
            },
        });
        const order = new Map(pageIds.map((id, index) => [id, index]));
        rows.sort((left, right) => (order.get(left.id) ?? 0) - (order.get(right.id) ?? 0));

        const products = [];
        const heldByVariant = await this.activeHoldQuantities(
            rows.flatMap((product) => product.product_variants.map((variant) => variant.id)),
        );

        for (const product of rows) {
            let stock = 0;
            let variantId: string | null = null;
            const prices = {
                wholesale: 0,
                representative: 0,
                retail: 0,
            };

            for (const variant of product.product_variants) {
                variantId ??= variant.id;
                for (const level of variant.stock_levels) {
                    stock += Number(level.quantity_on_hand) - Number(level.quantity_reserved);
                }
                stock -= heldByVariant.get(variant.id) ?? 0;
                for (const item of variant.product_prices) {
                    if (item.unit_id !== product.base_unit_id) continue;
                    const amount = Math.round(Number(item.price));
                    if (item.price_type === price_type_enum.WHOLESALE) prices.wholesale = amount;
                    if (item.price_type === price_type_enum.REP) prices.representative = amount;
                    if (item.price_type === price_type_enum.RETAIL) prices.retail = amount;
                }
            }

            if (stock <= 0) {
                continue;
            }

            const categoryId = product.categories?.id ?? 'none';
            const categoryName = product.categories?.name_ar ?? 'بدون عائلة';
            const price = priceType === price_type_enum.REP
                ? prices.representative || prices.retail
                : prices.retail || prices.representative;
            products.push({
                id: product.id,
                variant_id: variantId,
                unit_id: product.base_unit_id,
                sku: product.sku,
                name: product.name_ar,
                unit: product.units_of_measure?.name_ar ?? '',
                price,
                prices,
                image_url: this.storeImageRef(
                    product.id,
                    product.image_url,
                    product.updated_at,
                ),
                category_id: categoryId,
                category_name: categoryName,
                stock,
                currency: 'IQD',
            });
        }

        return {
            families: familyRows,
            products,
            page,
            limit,
            has_more: hasMore,
            audience: audience === 'agent' ? 'agent' : 'customer',
        };
    }

    storeImageRef(
        productId: string,
        imageUrl: string | null | undefined,
        updatedAt?: Date | null,
    ) {
        const raw = (imageUrl ?? '').trim();
        if (!raw) return null;
        if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
        const stamp = updatedAt ? updatedAt.getTime() : 0;
        return `https://hajecamell.store/api/v1/store/products/${productId}/image?v=${stamp}`;
    }

    async readProductImage(id: string) {
        if (!/^[0-9a-f-]{36}$/i.test(id)) {
            throw new NotFoundException('الصورة غير موجودة');
        }
        const product = await this.prisma.products.findUnique({
            where: { id },
            select: { image_url: true },
        });
        const raw = (product?.image_url ?? '').trim();
        const match = raw.match(/^data:(image\/[a-zA-Z0-9.+-]+);base64,([A-Za-z0-9+/=\s]+)$/);
        if (!match) {
            throw new NotFoundException('الصورة غير موجودة');
        }
        return {
            contentType: match[1].toLowerCase(),
            body: Buffer.from(match[2].replace(/\s/g, ''), 'base64'),
        };
    }

    private async activeHoldQuantities(variantIds: string[]) {
        const unique = [...new Set(variantIds.filter(Boolean))];
        const held = new Map<string, number>();
        if (unique.length === 0) {
            return held;
        }
        const rows = await this.prisma.$queryRaw<Array<{ variant_id: string; held: unknown }>>(Prisma.sql`
            SELECT h.variant_id::text AS variant_id,
                   COALESCE(SUM(h.quantity), 0) AS held
            FROM public.stock_holds h
            WHERE h.expires_at > NOW()
              AND h.variant_id IN (${Prisma.join(unique.map((id) => Prisma.sql`${id}::uuid`))})
            GROUP BY h.variant_id
        `);
        for (const row of rows) {
            held.set(row.variant_id, Number(row.held) || 0);
        }
        return held;
    }
}