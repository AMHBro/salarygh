import {
    BadRequestException,
    Injectable,
    NotFoundException,
} from '@nestjs/common';

import {
    ecommerce_order_source_enum,
    price_type_enum,
    Prisma,
    sales_payment_enum,
} from '@prisma/client';

import { randomBytes } from 'crypto';

import { PrismaService } from '../../../prisma/prisma.service';

import { EcommercePricingService } from './ecommerce-pricing.service';
import { EcommercePartyService } from './ecommerce-party.service';

import { GuestCheckoutDto } from '../dto/guest-checkout.dto';
import { RepresentativeCheckoutDto } from '../dto/representative-checkout.dto';
import {
    chooseInvoicePriceType,
    readAllowedPrices,
} from '../../representatives/allowed-prices';

@Injectable()
export class CheckoutService {
    constructor(
        private readonly prisma: PrismaService,
        private readonly pricingService: EcommercePricingService,
        private readonly partyService: EcommercePartyService,
    ) { }

    /**
     * ============================================================
     * GUEST CHECKOUT
     * ============================================================
     */
    async guestCheckout(
        cartToken: string,
        dto: GuestCheckoutDto,
        idempotencyKey?: string,
    ) {
        if (!cartToken?.trim()) {
            throw new BadRequestException({
                code: 'ECOMMERCE_CART_TOKEN_REQUIRED',
                message: 'رمز السلة مطلوب',
            });
        }

        /**
         * Idempotency
         */
        if (idempotencyKey?.trim()) {
            const existing =
                await this.prisma.ecommerce_orders.findUnique({
                    where: {
                        idempotency_key:
                            idempotencyKey.trim(),
                    },

                    include: {
                        items: true,
                    },
                });

            if (existing) {
                /**
                 * حماية من استخدام Idempotency Key
                 * خاص بطلب Representative.
                 */
                if (
                    existing.source !==
                    ecommerce_order_source_enum.GUEST
                ) {
                    throw new BadRequestException({
                        code: 'ECOMMERCE_IDEMPOTENCY_CONFLICT',
                        message:
                            'مفتاح Idempotency مستخدم لعملية أخرى',
                    });
                }

                return this.buildCheckoutResponse(
                    existing,
                );
            }
        }

        return this.prisma.$transaction(
            async (tx) => {
                /**
                 * 1. قراءة Cart الخاصة بالـGuest.
                 */
                const cart =
                    await tx.ecommerce_carts.findUnique({
                        where: {
                            session_token:
                                cartToken.trim(),
                        },

                        include: {
                            items: {
                                include: {
                                    variant: {
                                        include: {
                                            products: true,
                                        },
                                    },

                                    unit: true,
                                },
                            },
                        },
                    });

                if (
                    !cart ||
                    cart.source !==
                    ecommerce_order_source_enum.GUEST
                ) {
                    throw new NotFoundException({
                        code: 'ECOMMERCE_CART_NOT_FOUND',
                        message:
                            'سلة التسوق غير موجودة',
                    });
                }

                if (cart.items.length === 0) {
                    throw new BadRequestException({
                        code: 'ECOMMERCE_CART_EMPTY',
                        message:
                            'لا يمكن إرسال طلب من سلة فارغة',
                    });
                }

                /**
                 * 2. إعادة حساب الأسعار من قاعدة البيانات.
                 *
                 * السعر القادم من Frontend لا يعتمد عليه.
                 */
                const preparedItems: Array<{
                    cartItem:
                    typeof cart.items[number];

                    pricing:
                    Awaited<
                        ReturnType<
                            EcommercePricingService['resolvePrice']
                        >
                    >;

                    lineTotal:
                    Prisma.Decimal;
                }> = [];

                let subtotal =
                    new Prisma.Decimal(0);

                for (const item of cart.items) {
                    const pricing =
                        await this.pricingService.resolvePrice(
                            item.variant_id,
                            item.unit_id,
                            ecommerce_order_source_enum.GUEST,
                            tx,
                        );

                    const lineTotal =
                        pricing.finalPrice.mul(
                            item.quantity,
                        );

                    subtotal =
                        subtotal.add(
                            lineTotal,
                        );

                    preparedItems.push({
                        cartItem: item,
                        pricing,
                        lineTotal,
                    });
                }

                /**
                 * لا يوجد Discount Engine في M08 V1.
                 */
                const discountAmount =
                    new Prisma.Decimal(0);

                const total =
                    subtotal.sub(
                        discountAmount,
                    );

                /**
                 * 3. Public Token للضيف.
                 */
                const publicToken =
                    randomBytes(32)
                        .toString('hex');

                /**
                 * 4. Order Number.
                 */
                const orderNumber =
                    this.generateOrderNumber();

                /**
                 * 5. إنشاء Order.
                 */
                const order =
                    await tx.ecommerce_orders.create({
                        data: {
                            order_number:
                                orderNumber,

                            source:
                                ecommerce_order_source_enum.GUEST,

                            status:
                                'SUBMITTED',

                            /**
                             * Guest لا يملك User أو Rep.
                             */
                            user_id:
                                null,

                            rep_id:
                                null,

                            /**
                             * Guest ليس Party مسجلاً
                             * في هذه المرحلة.
                             */
                            party_type:
                                null,

                            party_id:
                                null,

                            party_name:
                                null,

                            party_phone:
                                null,

                            party_address:
                                null,

                            customer_name:
                                dto.customer_name.trim(),

                            customer_phone:
                                dto.customer_phone.trim(),

                            customer_email:
                                dto.customer_email?.trim() ||
                                null,

                            customer_address:
                                dto.customer_address.trim(),

                            payment_type:
                                sales_payment_enum.CASH,

                            notes:
                                dto.notes?.trim() ||
                                null,

                            subtotal,

                            discount_amount:
                                discountAmount,

                            total,

                            submitted_at:
                                new Date(),

                            public_token:
                                publicToken,

                            idempotency_key:
                                idempotencyKey?.trim() ||
                                null,

                            items: {
                                create:
                                    preparedItems.map(
                                        ({
                                            cartItem,
                                            pricing,
                                            lineTotal,
                                        }) => ({
                                            product_id:
                                                cartItem
                                                    .variant
                                                    .product_id,

                                            variant_id:
                                                cartItem
                                                    .variant_id,

                                            unit_id:
                                                cartItem
                                                    .unit_id,

                                            product_name:
                                                cartItem
                                                    .variant
                                                    .products
                                                    .name_ar,

                                            variant_snapshot:
                                                this.buildVariantSnapshot(
                                                    cartItem.variant,
                                                ),

                                            unit_name:
                                                cartItem
                                                    .unit
                                                    .name_ar,

                                            quantity:
                                                cartItem
                                                    .quantity,

                                            price_type:
                                                price_type_enum.RETAIL,

                                            base_price:
                                                pricing.basePrice,

                                            commission_type:
                                                null,

                                            commission_value:
                                                new Prisma.Decimal(
                                                    0,
                                                ),

                                            commission_amount:
                                                new Prisma.Decimal(
                                                    0,
                                                ),

                                            unit_price:
                                                pricing.finalPrice,

                                            line_total:
                                                lineTotal,
                                        }),
                                    ),
                            },
                        },

                        include: {
                            items: true,
                        },
                    });

                /**
                 * 6. تنظيف Cart Items.
                 *
                 * Cart نفسها تبقى.
                 */
                await tx.ecommerce_cart_items.deleteMany({
                    where: {
                        cart_id:
                            cart.id,
                    },
                });

                return this.buildCheckoutResponse(
                    order,
                );
            },
            {
                isolationLevel:
                    Prisma.TransactionIsolationLevel
                        .Serializable,
            },
        );
    }

    /**
     * ============================================================
     * REPRESENTATIVE CHECKOUT
     * ============================================================
     */
    async representativeCheckout(
        userId: string,
        dto: RepresentativeCheckoutDto,
        idempotencyKey?: string,
    ) {
        if (!userId) {
            throw new BadRequestException({
                code: 'ECOMMERCE_REP_USER_REQUIRED',
                message:
                    'معرف مستخدم المندوب مطلوب',
            });
        }

        /**
         * أنواع الدفع المسموحة للـEcommerce.
         *
         * REP_CUSTODY غير مستخدم هنا.
         */
        const allowedPaymentTypes: sales_payment_enum[] = [
            sales_payment_enum.CASH,
            sales_payment_enum.CREDIT,
            sales_payment_enum.PARTIAL,
        ];

        if (
            !allowedPaymentTypes.includes(
                dto.payment_type,
            )
        ) {
            throw new BadRequestException({
                code: 'ECOMMERCE_INVALID_PAYMENT_TYPE',
                message:
                    'طريقة الدفع غير مسموحة في طلب المتجر',
            });
        }

        /**
         * Idempotency
         */
        if (idempotencyKey?.trim()) {
            const existing =
                await this.prisma.ecommerce_orders.findUnique({
                    where: {
                        idempotency_key:
                            idempotencyKey.trim(),
                    },

                    include: {
                        items: true,
                    },
                });

            if (existing) {
                /**
                 * لا يجوز إعادة Order
                 * لمستخدم أو Source مختلف.
                 */
                if (
                    existing.user_id !== userId ||
                    existing.source !==
                    ecommerce_order_source_enum
                        .REPRESENTATIVE
                ) {
                    throw new BadRequestException({
                        code: 'ECOMMERCE_IDEMPOTENCY_CONFLICT',
                        message:
                            'مفتاح Idempotency مستخدم لعملية أخرى',
                    });
                }

                return this.buildCheckoutResponse(
                    existing,
                );
            }
        }

        return this.prisma.$transaction(
            async (tx) => {
                /**
                 * 1. الحصول على المندوب المرتبط
                 * بالمستخدم الحالي.
                 *
                 * representatives.user_id = UNIQUE
                 */
                const representative =
                    await tx.representatives.findUnique({
                        where: {
                            user_id:
                                userId,
                        },

                        select: {
                            id: true,
                            user_id: true,

                            name: true,
                            phone: true,

                            branch_id: true,

                            office_name: true,
                            office_phone: true,
                            office_address: true,

                            status: true,
                        },
                    });

                if (!representative) {
                    throw new NotFoundException({
                        code:
                            'ECOMMERCE_REPRESENTATIVE_NOT_FOUND',

                        message:
                            'المستخدم الحالي غير مرتبط بمندوب',
                    });
                }

                /**
                 * عندك rep_status_enum:
                 *
                 * ACTIVE
                 * INACTIVE
                 *
                 * نستخدم القيمة مباشرة حتى لا نحتاج
                 * import منفصل للـenum.
                 */
                if (
                    representative.status !==
                    'ACTIVE'
                ) {
                    throw new BadRequestException({
                        code:
                            'ECOMMERCE_REPRESENTATIVE_INACTIVE',

                        message:
                            'حساب المندوب غير فعال',
                    });
                }

                const invoicePriceType =
                    chooseInvoicePriceType(
                        await readAllowedPrices(
                            tx,
                            representative.id,
                        ),
                        dto.price_type,
                    );

                /**
                 * 2. Cart الخاصة بالمندوب.
                 */
                const cart =
                    await tx.ecommerce_carts.findUnique({
                        where: {
                            user_id:
                                userId,
                        },

                        include: {
                            items: {
                                include: {
                                    variant: {
                                        include: {
                                            products: true,
                                        },
                                    },

                                    unit: true,
                                },
                            },
                        },
                    });

                if (
                    !cart ||
                    cart.source !==
                    ecommerce_order_source_enum
                        .REPRESENTATIVE
                ) {
                    throw new NotFoundException({
                        code:
                            'ECOMMERCE_CART_NOT_FOUND',

                        message:
                            'سلة المندوب غير موجودة',
                    });
                }

                if (cart.items.length === 0) {
                    throw new BadRequestException({
                        code:
                            'ECOMMERCE_CART_EMPTY',

                        message:
                            'لا يمكن إرسال طلب من سلة فارغة',
                    });
                }

                /**
                 * 3. Resolve Party.
                 *
                 * CUSTOMER
                 * SUPPLIER
                 * BRANCH
                 * REPRESENTATIVE
                 * OTHER
                 */
                const party =
                    await this.partyService.resolveParty(
                        dto.party_type,

                        dto.party_id,

                        {
                            name:
                                dto.party_name,

                            phone:
                                dto.party_phone,

                            address:
                                dto.party_address,
                        },

                        tx,
                    );

                /**
                 * 4. إعادة حساب REP Prices.
                 */
                const preparedItems: Array<{
                    cartItem:
                    typeof cart.items[number];

                    pricing:
                    Awaited<
                        ReturnType<
                            EcommercePricingService['resolvePrice']
                        >
                    >;

                    lineTotal:
                    Prisma.Decimal;
                }> = [];

                let subtotal =
                    new Prisma.Decimal(0);

                for (const item of cart.items) {
                    const pricing =
                        await this.pricingService.resolveListedPrice(
                            item.variant_id,

                            item.unit_id,

                            invoicePriceType,

                            tx,
                        );

                    const lineTotal =
                        pricing.finalPrice.mul(
                            item.quantity,
                        );

                    subtotal =
                        subtotal.add(
                            lineTotal,
                        );

                    preparedItems.push({
                        cartItem:
                            item,

                        pricing,

                        lineTotal,
                    });
                }

                /**
                 * M08 V1
                 *
                 * لا يوجد Discount Engine.
                 */
                const discountAmount =
                    new Prisma.Decimal(0);

                const total =
                    subtotal.sub(
                        discountAmount,
                    );

                /**
                 * 5. إنشاء Order.
                 */
                const order =
                    await tx.ecommerce_orders.create({
                        data: {
                            order_number:
                                this.generateOrderNumber(),

                            source:
                                ecommerce_order_source_enum
                                    .REPRESENTATIVE,

                            /**
                             * حالة الطلب عند Checkout.
                             */
                            status:
                                'SUBMITTED',

                            /**
                             * صاحب الطلب.
                             */
                            user_id:
                                userId,

                            rep_id:
                                representative.id,

                            /**
                             * Party Snapshot
                             */
                            party_type:
                                party.partyType,

                            party_id:
                                party.partyId,

                            party_name:
                                party.partyName,

                            party_phone:
                                party.partyPhone,

                            party_address:
                                party.partyAddress,

                            /**
                             * هذه الحقول خاصة Guest،
                             * لذلك تبقى NULL للمندوب.
                             */
                            customer_name:
                                null,

                            customer_phone:
                                null,

                            customer_email:
                                null,

                            customer_address:
                                null,

                            payment_type:
                                dto.payment_type,

                            notes:
                                dto.notes?.trim() ||
                                null,

                            subtotal,

                            discount_amount:
                                discountAmount,

                            total,

                            submitted_at:
                                new Date(),

                            /**
                             * Representative يستخدم JWT،
                             * لذلك لا يحتاج Public Token.
                             */
                            public_token:
                                null,

                            idempotency_key:
                                idempotencyKey?.trim() ||
                                null,

                            items: {
                                create:
                                    preparedItems.map(
                                        ({
                                            cartItem,
                                            pricing,
                                            lineTotal,
                                        }) => ({
                                            product_id:
                                                cartItem
                                                    .variant
                                                    .product_id,

                                            variant_id:
                                                cartItem
                                                    .variant_id,

                                            unit_id:
                                                cartItem
                                                    .unit_id,

                                            product_name:
                                                cartItem
                                                    .variant
                                                    .products
                                                    .name_ar,

                                            variant_snapshot:
                                                this.buildVariantSnapshot(
                                                    cartItem.variant,
                                                ),

                                            unit_name:
                                                cartItem
                                                    .unit
                                                    .name_ar,

                                            quantity:
                                                cartItem
                                                    .quantity,

                                            price_type:
                                                pricing
                                                    .priceType,

                                            /**
                                             * RETAIL الأصلي.
                                             */
                                            base_price:
                                                pricing
                                                    .basePrice,

                                            commission_type:
                                                pricing
                                                    .commissionType,

                                            commission_value:
                                                pricing
                                                    .commissionValue,

                                            /**
                                             * عمولة الوحدة الواحدة.
                                             */
                                            commission_amount:
                                                pricing
                                                    .commissionAmount,

                                            /**
                                             * RETAIL + Commission.
                                             */
                                            unit_price:
                                                pricing
                                                    .finalPrice,

                                            line_total:
                                                lineTotal,
                                        }),
                                    ),
                            },
                        },

                        include: {
                            items: true,
                        },
                    });

                /**
                 * 6. تفريغ Cart Items.
                 *
                 * ecommerce_carts نفسها لا نحذفها.
                 */
                await tx.ecommerce_cart_items.deleteMany({
                    where: {
                        cart_id:
                            cart.id,
                    },
                });

                return this.buildCheckoutResponse(
                    order,
                );
            },
            {
                isolationLevel:
                    Prisma.TransactionIsolationLevel
                        .Serializable,
            },
        );
    }

    /**
     * ============================================================
     * HELPERS
     * ============================================================
     */

    /**
     * Snapshot للـVariant وقت إنشاء الطلب.
     */
    private buildVariantSnapshot(
        variant: {
            sku: string | null;
            barcode: string | null;
            attributes: Prisma.JsonValue;
        },
    ): Prisma.InputJsonValue {
        return {
            sku:
                variant.sku,

            barcode:
                variant.barcode,

            attributes:
                variant.attributes ??
                {},
        } as Prisma.InputJsonValue;
    }

    /**
     * إنشاء Order Number.
     *
     * مثال:
     * ECO-20260924-A81F932B
     */
    private generateOrderNumber(): string {
        const now =
            new Date();

        const year =
            now.getFullYear();

        const month =
            String(
                now.getMonth() + 1,
            ).padStart(
                2,
                '0',
            );

        const day =
            String(
                now.getDate(),
            ).padStart(
                2,
                '0',
            );

        const random =
            randomBytes(4)
                .toString('hex')
                .toUpperCase();

        return `ECO-${year}${month}${day}-${random}`;
    }

    /**
     * Unified Checkout Response.
     */
    private buildCheckoutResponse(
        order: any,
    ) {
        return {
            order: {
                id:
                    order.id,

                order_number:
                    order.order_number,

                source:
                    order.source,

                status:
                    order.status,

                /**
                 * Representative data
                 */
                rep_id:
                    order.rep_id,

                party_type:
                    order.party_type,

                party_id:
                    order.party_id,

                party_name:
                    order.party_name,

                party_phone:
                    order.party_phone,

                party_address:
                    order.party_address,

                /**
                 * Guest data
                 */
                customer_name:
                    order.customer_name,

                customer_phone:
                    order.customer_phone,

                customer_email:
                    order.customer_email,

                customer_address:
                    order.customer_address,

                payment_type:
                    order.payment_type,

                subtotal:
                    order.subtotal,

                discount_amount:
                    order.discount_amount,

                total:
                    order.total,

                submitted_at:
                    order.submitted_at,

                items:
                    order.items,
            },

            /**
             * Guest:
             * token موجود.
             *
             * Representative:
             * null.
             */
            order_token:
                order.public_token,
        };
    }
}