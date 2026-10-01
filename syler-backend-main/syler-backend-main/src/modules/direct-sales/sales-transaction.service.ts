import {
    BadRequestException,
    ConflictException,
    Injectable,
    NotFoundException,
    Optional,
} from '@nestjs/common';

import { FloorService } from '../floor/floor.service';
import { assertRepDebtCeiling } from '../representatives/rep-debt';

import {
    movement_type_enum,
    price_type_enum,
    Prisma,
    sales_payment_enum,
    sales_status_enum,
} from '@prisma/client';

import { randomBytes } from 'crypto';

export interface SalesTransactionItem {
    variant_id: string;
    unit_id: string;

    /**
     * الكمية بالوحدة المختارة.
     *
     * مثال:
     * 3 كارتونات.
     */
    quantity: Prisma.Decimal.Value;

    /**
     * سعر الوحدة المختارة.
     *
     * مثال:
     * سعر الكارتون وليس سعر القطعة.
     */
    unit_price: Prisma.Decimal.Value;

    discount_percent?: Prisma.Decimal.Value;
}

export interface SalesTransactionPayload {
    customer_id?: string | null;

    /**
     * يستخدم لطلبات المندوب.
     */
    rep_id?: string | null;

    warehouse_id: string;

    price_type: price_type_enum;

    payment_type: sales_payment_enum;

    items: SalesTransactionItem[];

    discount_amount?: Prisma.Decimal.Value;

    /**
     * مطلوب فقط عند PARTIAL.
     */
    paid_amount?: Prisma.Decimal.Value;

    notes?: string | null;

    /**
     * يجب أن يأتي من Caller.
     *
     * POS:
     * POS-....
     *
     * Ecommerce:
     * ECOMMERCE-ORDER-{orderId}
     */
    idempotency_key: string;

    /**
     * مفاتيح الحجز التي أنشأتها الحاسبة قبل الحفظ.
     * تُحذف قبل فحص الكمية حتى لا يحجب الحجز بيعه نفسه.
     */
    hold_keys?: string[];

    /**
     * المستخدم الذي نفذ العملية.
     */
    created_by?: string | null;

    /**
     * مسار رفع طابور الأوفلاين. يعيد فحص سقف المندوب بالمبلغ الآجل المحسوب هنا.
     */
    sync_revalidate?: boolean;

    /** USD لا يُقاس على سقف الدينار. */
    currency?: string | null;
}

@Injectable()
export class SalesTransactionService {
    constructor(@Optional() private readonly floor?: FloorService) {}

    /**
     * ============================================================
     * CREATE SALE INSIDE EXISTING TRANSACTION
     * ============================================================
     *
     * مهم:
     * هذه الخدمة لا تنشئ $transaction جديدة.
     *
     * الـCaller هو المسؤول عن:
     *
     * prisma.$transaction(async (tx) => {
     *     await salesTransactionService.createSale(tx, payload);
     * });
     *
     * وهذا يسمح للـEcommerce أن يجعل:
     *
     * Invoice + Stock + Order ACCEPTED
     *
     * كلها داخل Transaction واحدة.
     */
    async createSale(
        tx: Prisma.TransactionClient,
        payload: SalesTransactionPayload,
    ) {
        /**
         * ========================================================
         * 1. BASIC VALIDATION
         * ========================================================
         */

        if (
            !payload.items ||
            payload.items.length === 0
        ) {
            throw new BadRequestException({
                code: 'SALE_ITEMS_REQUIRED',
                message:
                    'يجب إضافة مادة واحدة على الأقل في الفاتورة',
            });
        }

        if (
            !payload.idempotency_key?.trim()
        ) {
            throw new BadRequestException({
                code:
                    'SALE_IDEMPOTENCY_KEY_REQUIRED',

                message:
                    'مفتاح Idempotency مطلوب',
            });
        }

        if (
            !new Prisma.Decimal(payload.discount_amount ?? 0).isZero() ||
            payload.items.some(item => !new Prisma.Decimal(item.discount_percent ?? 0).isZero())
        ) {
            throw new BadRequestException({
                code: 'DISCOUNTS_NOT_SUPPORTED',
                message: 'الخصومات غير مفعلة في النظام',
            });
        }

        /**
         * ========================================================
         * 2. IDEMPOTENCY
         * ========================================================
         */

        const existingInvoice =
            await tx.sales_invoices.findUnique({
                where: {
                    idempotency_key:
                        payload.idempotency_key.trim(),
                },

                include: {
                    customers: {
                        select: {
                            name: true,
                        },
                    },
                },
            });

        if (existingInvoice) {
            return {
                invoice:
                    existingInvoice,

                already_exists:
                    true,

                customer_name:
                    existingInvoice.customers?.name ??
                    'زبون نقدي عام',

                totals: {
                    subtotal:
                        existingInvoice.subtotal,

                    discount_amount:
                        existingInvoice.discount_amount,

                    total:
                        existingInvoice.total,

                    paid_amount:
                        existingInvoice.paid_amount,

                    due_amount:
                        existingInvoice.due_amount,
                },
            };
        }

        /**
         * ========================================================
         * 3. WAREHOUSE
         * ========================================================
         */

        const warehouse =
            await tx.warehouses.findUnique({
                where: {
                    id:
                        payload.warehouse_id,
                },

                select: {
                    id:
                        true,

                    name:
                        true,

                    status:
                        true,

                    branch_id:
                        true,
                },
            });

        if (!warehouse) {
            throw new NotFoundException({
                code:
                    'WAREHOUSE_NOT_FOUND',

                message:
                    'المخزن غير موجود',
            });
        }

        if (
            warehouse.status !==
            'ACTIVE'
        ) {
            throw new BadRequestException({
                code:
                    'WAREHOUSE_NOT_ACTIVE',

                message:
                    'المخزن غير فعال',
            });
        }

        /**
         * ========================================================
         * 4. CUSTOMER
         * ========================================================
         */

        let customer:
            | {
                id: string;
                name: string;
                balance: Prisma.Decimal;
                credit_limit: Prisma.Decimal;
                is_active: boolean;
                assigned_rep_id: string | null;
            }
            | null =
            null;

        if (
            payload.customer_id
        ) {
            customer =
                await tx.customers.findUnique({
                    where: {
                        id:
                            payload.customer_id,
                    },

                    select: {
                        id:
                            true,

                        name:
                            true,

                        balance:
                            true,

                        credit_limit:
                            true,

                        is_active:
                            true,

                        assigned_rep_id:
                            true,
                    },
                });

            if (!customer) {
                throw new NotFoundException({
                    code:
                        'CUSTOMER_NOT_FOUND',

                    message:
                        'الزبون غير موجود',
                });
            }

            if (
                !customer.is_active
            ) {
                throw new BadRequestException({
                    code:
                        'CUSTOMER_INACTIVE',

                    message:
                        'الزبون غير فعال',
                });
            }
        }

        /**
         * ========================================================
         * 5. REPRESENTATIVE
         * ========================================================
         */

        if (payload.rep_id) {
            const representative =
                await tx.representatives.findUnique({
                    where: {
                        id:
                            payload.rep_id,
                    },

                    select: {
                        id:
                            true,

                        status:
                            true,
                    },
                });

            if (!representative) {
                throw new NotFoundException({
                    code:
                        'REPRESENTATIVE_NOT_FOUND',

                    message:
                        'المندوب غير موجود',
                });
            }

            if (
                representative.status !==
                'ACTIVE'
            ) {
                throw new BadRequestException({
                    code:
                        'REPRESENTATIVE_INACTIVE',

                    message:
                        'المندوب غير فعال',
                });
            }
        }

        /**
         * ========================================================
         * 6. PREPARE ITEMS
         * ========================================================
         */

        const preparedItems: Array<{
            variant_id: string;
            unit_id: string;

            quantity: Prisma.Decimal;

            conversion_factor:
            Prisma.Decimal;

            quantity_in_base_unit:
            Prisma.Decimal;

            unit_price:
            Prisma.Decimal;

            discount_percent:
            Prisma.Decimal;

            net_unit_price:
            Prisma.Decimal;

            total_price:
            Prisma.Decimal;

            weighted_avg_cost:
            Prisma.Decimal;

            product_name:
            string;
        }> = [];

        let subtotal =
            new Prisma.Decimal(
                0,
            );

        for (
            const item of payload.items
        ) {
            const quantity =
                new Prisma.Decimal(
                    item.quantity,
                );

            const unitPrice =
                new Prisma.Decimal(
                    item.unit_price,
                );

            const discountPercent =
                new Prisma.Decimal(
                    item.discount_percent ??
                    0,
                );

            if (
                quantity.lte(0)
            ) {
                throw new BadRequestException({
                    code:
                        'INVALID_SALE_QUANTITY',

                    message:
                        'كمية المادة يجب أن تكون أكبر من صفر',

                    details: {
                        variant_id:
                            item.variant_id,
                    },
                });
            }

            if (
                unitPrice.lt(0)
            ) {
                throw new BadRequestException({
                    code:
                        'INVALID_UNIT_PRICE',

                    message:
                        'سعر الوحدة غير صالح',

                    details: {
                        variant_id:
                            item.variant_id,
                    },
                });
            }

            if (
                discountPercent.lt(
                    0,
                ) ||
                discountPercent.gt(
                    100,
                )
            ) {
                throw new BadRequestException({
                    code:
                        'INVALID_DISCOUNT_PERCENT',

                    message:
                        'نسبة الخصم يجب أن تكون بين 0 و100',
                });
            }

            /**
             * Variant + Product
             */
            const variant =
                await tx.product_variants.findUnique({
                    where: {
                        id:
                            item.variant_id,
                    },

                    include: {
                        products:
                            true,
                    },
                });

            if (!variant) {
                throw new NotFoundException({
                    code:
                        'PRODUCT_VARIANT_NOT_FOUND',

                    message:
                        'الصنف غير موجود',
                });
            }

            if (
                !variant.is_active ||
                !variant.products.is_active
            ) {
                throw new BadRequestException({
                    code:
                        'PRODUCT_INACTIVE',

                    message:
                        `المادة "${variant.products.name_ar}" غير فعالة`,
                });
            }

            /**
             * Unit
             */
            const unit =
                await tx.units_of_measure.findUnique({
                    where: {
                        id:
                            item.unit_id,
                    },

                    select: {
                        id:
                            true,

                        conversion_factor:
                            true,

                        is_active:
                            true,
                    },
                });

            if (!unit) {
                throw new NotFoundException({
                    code:
                        'UNIT_NOT_FOUND',

                    message:
                        'وحدة القياس غير موجودة',
                });
            }

            if (
                !unit.is_active
            ) {
                throw new BadRequestException({
                    code:
                        'UNIT_INACTIVE',

                    message:
                        'وحدة القياس غير فعالة',
                });
            }

            const conversionFactor =
                unit.conversion_factor;

            if (
                conversionFactor.lte(
                    0,
                )
            ) {
                throw new BadRequestException({
                    code:
                        'INVALID_UNIT_CONVERSION',

                    message:
                        'معامل تحويل وحدة القياس غير صالح',
                });
            }

            /**
             * تحقق أن الوحدة مسموحة للمنتج.
             *
             * Base Unit مسموحة تلقائيًا.
             */
            if (
                item.unit_id !==
                variant.products
                    .base_unit_id
            ) {
                const allowedUnit =
                    await tx.product_allowed_units.findUnique({
                        where: {
                            product_id_unit_id: {
                                product_id:
                                    variant.product_id,

                                unit_id:
                                    item.unit_id,
                            },
                        },
                    });

                if (
                    !allowedUnit ||
                    !allowedUnit.can_sell
                ) {
                    throw new BadRequestException({
                        code:
                            'UNIT_NOT_ALLOWED_FOR_SALE',

                        message:
                            `وحدة القياس غير مسموحة للبيع للمادة "${variant.products.name_ar}"`,
                    });
                }
            }

            /**
             * Quantity selected unit -> base unit.
             *
             * مثال:
             *
             * quantity = 3 cartons
             * conversion = 12
             *
             * base = 36 pieces
             */
            const quantityInBaseUnit =
                quantity.mul(
                    conversionFactor,
                );

            /**
             * Line totals.
             */
            const gross =
                quantity.mul(
                    unitPrice,
                );

            const discountValue =
                gross
                    .mul(
                        discountPercent,
                    )
                    .div(
                        100,
                    );

            const lineTotal =
                gross.sub(
                    discountValue,
                );

            const netUnitPrice =
                quantity.gt(0)
                    ? lineTotal.div(
                        quantity,
                    )
                    : unitPrice;

            subtotal =
                subtotal.add(
                    lineTotal,
                );

            preparedItems.push({
                variant_id:
                    item.variant_id,

                unit_id:
                    item.unit_id,

                quantity,

                conversion_factor:
                    conversionFactor,

                quantity_in_base_unit:
                    quantityInBaseUnit,

                unit_price:
                    unitPrice,

                discount_percent:
                    discountPercent,

                net_unit_price:
                    netUnitPrice,

                total_price:
                    lineTotal,

                weighted_avg_cost:
                    variant.weighted_avg_cost,

                product_name:
                    variant.products.name_ar,
            });
        }

        /**
         * ========================================================
         * 7. INVOICE DISCOUNT
         * ========================================================
         */

        const discountAmount =
            new Prisma.Decimal(
                payload.discount_amount ??
                0,
            );

        if (
            discountAmount.lt(0)
        ) {
            throw new BadRequestException({
                code:
                    'INVALID_DISCOUNT_AMOUNT',

                message:
                    'قيمة الخصم غير صالحة',
            });
        }

        if (
            discountAmount.gt(
                subtotal,
            )
        ) {
            throw new BadRequestException({
                code:
                    'DISCOUNT_EXCEEDS_SUBTOTAL',

                message:
                    'قيمة الخصم أكبر من مجموع الفاتورة',
            });
        }

        const total =
            subtotal.sub(
                discountAmount,
            );

        /**
         * ========================================================
         * 8. PAYMENT
         * ========================================================
         */

        let paidAmount =
            new Prisma.Decimal(
                0,
            );

        let dueAmount =
            new Prisma.Decimal(
                0,
            );

        switch (
        payload.payment_type
        ) {
            case sales_payment_enum.CASH:
                paidAmount =
                    total;

                dueAmount =
                    new Prisma.Decimal(
                        0,
                    );

                break;

            case sales_payment_enum.CREDIT:
                paidAmount =
                    new Prisma.Decimal(
                        0,
                    );

                dueAmount =
                    total;

                break;

            case sales_payment_enum.PARTIAL:
                paidAmount =
                    new Prisma.Decimal(
                        payload.paid_amount ??
                        0,
                    );

                if (
                    paidAmount.lt(0)
                ) {
                    throw new BadRequestException({
                        code:
                            'INVALID_PAID_AMOUNT',

                        message:
                            'المبلغ المدفوع غير صالح',
                    });
                }

                if (
                    paidAmount.gt(
                        total,
                    )
                ) {
                    throw new BadRequestException({
                        code:
                            'PAID_AMOUNT_EXCEEDS_TOTAL',

                        message:
                            'المبلغ المدفوع لا يمكن أن يتجاوز إجمالي الفاتورة',
                    });
                }

                dueAmount =
                    total.sub(
                        paidAmount,
                    );

                break;

            default:
                throw new BadRequestException({
                    code:
                        'UNSUPPORTED_SALES_PAYMENT_TYPE',

                    message:
                        'طريقة الدفع غير مدعومة في عملية البيع الحالية',
                });
        }

        /**
         * ========================================================
         * 9. CREDIT VALIDATION
         * ========================================================
         */

        if (
            dueAmount.gt(0)
        ) {
            if (!customer) {
                throw new BadRequestException({
                    code:
                        'CUSTOMER_REQUIRED_FOR_CREDIT',

                    message:
                        'لا يمكن البيع بالآجل أو الجزئي بدون زبون مسجل',
                });
            }

            const newBalance =
                customer.balance.add(
                    dueAmount,
                );

            /**
             * credit_limit = 0
             * يعني لا يوجد Limit مطبق
             * حسب السلوك الحالي للنظام.
             */
            if (
                customer.credit_limit.gt(
                    0,
                ) &&
                newBalance.gt(
                    customer.credit_limit,
                )
            ) {
                throw new BadRequestException({
                    code:
                        'CREDIT_LIMIT_EXCEEDED',

                    message:
                        'تم تجاوز الحد الائتماني للزبون',

                    details: {
                        credit_limit:
                            customer.credit_limit.toString(),

                        current_balance:
                            customer.balance.toString(),

                        due_amount:
                            dueAmount.toString(),

                        new_balance:
                            newBalance.toString(),
                    },
                });
            }

            const currency = (payload.currency ?? 'IQD').trim().toUpperCase();
            if (
                payload.sync_revalidate &&
                currency !== 'USD' &&
                customer.assigned_rep_id
            ) {
                const representative = await tx.representatives.findUnique({
                    where: { id: customer.assigned_rep_id },
                    select: { id: true, name: true, max_debt_limit: true },
                });
                if (representative) {
                    await assertRepDebtCeiling(
                        tx,
                        representative,
                        dueAmount,
                    );
                }
            }
        }

        /**
         * ========================================================
         * 10. STOCK VALIDATION
         * ========================================================
         *
         * قفل الصفوف قبل القراءة حتى لا تمرّ بيعتان متزامنتان
         * على نفس الكمية. الترتيب الثابت يمنع التعارض بين الأقفال.
         */

        const lockedVariants = [
            ...new Set(
                preparedItems.map(
                    (item) => item.variant_id,
                ),
            ),
        ].sort();

        for (const variantId of lockedVariants) {
            await tx.$queryRaw`
                SELECT id
                FROM stock_levels
                WHERE variant_id = ${variantId}::uuid
                  AND warehouse_id = ${payload.warehouse_id}::uuid
                FOR UPDATE
            `;
        }

        if (this.floor && payload.hold_keys?.length) {
            await this.floor.releaseKeys(tx, payload.hold_keys);
        }

        for (
            const item of preparedItems
        ) {
            const stock =
                await tx.stock_levels.findUnique({
                    where: {
                        variant_id_warehouse_id: {
                            variant_id:
                                item.variant_id,

                            warehouse_id:
                                payload.warehouse_id,
                        },
                    },
                });

            const onHand =
                stock?.quantity_on_hand ??
                new Prisma.Decimal(
                    0,
                );

            const reserved =
                stock?.quantity_reserved ??
                new Prisma.Decimal(
                    0,
                );

            const held = this.floor
                ? await this.floor.heldQuantity(
                    tx,
                    item.variant_id,
                    payload.warehouse_id,
                )
                : new Prisma.Decimal(0);

            const available =
                onHand.sub(
                    reserved,
                ).sub(
                    held,
                );

            if (
                available.lt(
                    item.quantity_in_base_unit,
                )
            ) {
                throw new BadRequestException({
                    code:
                        'INSUFFICIENT_STOCK',

                    message:
                        `الكمية غير كافية بالمخزن للمادة "${item.product_name}"`,

                    details: {
                        variant_id:
                            item.variant_id,

                        warehouse_id:
                            payload.warehouse_id,

                        ordered_quantity:
                            item.quantity.toString(),

                        conversion_factor:
                            item.conversion_factor.toString(),

                        required_base_quantity:
                            item.quantity_in_base_unit.toString(),

                        available_base_quantity:
                            available.toString(),
                    },
                });
            }
        }

        /**
         * ========================================================
         * 11. INVOICE NUMBER
         * ========================================================
         */

        const invoiceNumber =
            this.generateInvoiceNumber();

        /**
         * ========================================================
         * 12. CREATE INVOICE
         * ========================================================
         */

        let invoice;

        try {
            invoice =
                await tx.sales_invoices.create({
                    data: {
                        invoice_number:
                            invoiceNumber,

                        customer_id:
                            payload.customer_id ??
                            null,

                        warehouse_id:
                            payload.warehouse_id,

                        rep_id:
                            payload.rep_id ??
                            null,

                        price_type:
                            payload.price_type,

                        payment_type:
                            payload.payment_type,

                        status:
                            dueAmount.eq(0)
                                ? sales_status_enum.PAID
                                : sales_status_enum.PARTIAL,

                        subtotal,

                        discount_amount:
                            discountAmount,

                        total,

                        paid_amount:
                            paidAmount,

                        due_amount:
                            dueAmount,

                        notes:
                            payload.notes ??
                            null,

                        idempotency_key:
                            payload.idempotency_key.trim(),

                        created_by:
                            payload.created_by ??
                            null,
                    },
                });
        } catch (error: any) {
            /**
             * حماية إضافية من Race Condition
             * على idempotency_key.
             */
            if (
                error?.code ===
                'P2002'
            ) {
                const existing =
                    await tx.sales_invoices.findUnique({
                        where: {
                            idempotency_key:
                                payload.idempotency_key.trim(),
                        },
                    });

                if (existing) {
                    return {
                        invoice:
                            existing,

                        already_exists:
                            true,
                    };
                }

                throw new ConflictException({
                    code:
                        'SALE_ALREADY_EXISTS',

                    message:
                        'تم إنشاء عملية البيع مسبقاً',
                });
            }

            throw error;
        }

        /**
         * ========================================================
         * 13. ITEMS + STOCK + MOVEMENTS
         * ========================================================
         */

        for (
            const item of preparedItems
        ) {
            await tx.sales_invoice_items.create({
                data: {
                    invoice_id:
                        invoice.id,

                    variant_id:
                        item.variant_id,

                    unit_id:
                        item.unit_id,

                    /**
                     * الكمية بوحدة البيع.
                     */
                    quantity:
                        item.quantity,

                    /**
                     * الكمية الفعلية التي ستخصم من المخزون.
                     */
                    quantity_in_base_unit:
                        item.quantity_in_base_unit,

                    unit_price:
                        item.unit_price,

                    cost_per_base_unit:
                        item.weighted_avg_cost,

                    discount_percent:
                        item.discount_percent,

                    net_unit_price:
                        item.net_unit_price,

                    total_price:
                        item.total_price,
                },
            });

            /**
             * المخزون مخزن بالـBase Unit.
             */
            await tx.stock_levels.update({
                where: {
                    variant_id_warehouse_id: {
                        variant_id:
                            item.variant_id,

                        warehouse_id:
                            payload.warehouse_id,
                    },
                },

                data: {
                    quantity_on_hand: {
                        decrement:
                            item.quantity_in_base_unit,
                    },

                    updated_at:
                        new Date(),
                },
            });

            /**
             * حركة المخزون أيضًا بالـBase Unit.
             */
            await tx.inventory_movements.create({
                data: {
                    movement_type:
                        movement_type_enum.OUT,

                    variant_id:
                        item.variant_id,

                    warehouse_id:
                        payload.warehouse_id,

                    quantity:
                        item.quantity_in_base_unit,

                    unit_cost:
                        item.weighted_avg_cost,

                    reference_type:
                        'SALES_INVOICE',

                    reference_id:
                        invoice.id,

                    performed_by:
                        payload.created_by ??
                        null,
                },
            });

            if (this.floor) {
                await this.floor.append(
                    tx,
                    'stock_delta',
                    `${invoice.id}:${item.variant_id}`,
                    {
                        variant_id: item.variant_id,
                        warehouse_id: payload.warehouse_id,
                        delta: -Number(item.quantity_in_base_unit),
                        invoice_id: invoice.id,
                    },
                );
            }
        }

        /**
         * ========================================================
         * 14. CUSTOMER BALANCE
         * ========================================================
         */

        if (
            customer &&
            dueAmount.gt(0)
        ) {
            await tx.customers.update({
                where: {
                    id:
                        customer.id,
                },

                data: {
                    balance: {
                        increment:
                            dueAmount,
                    },

                    updated_at:
                        new Date(),
                },
            });
        }

        /**
         * ========================================================
         * RESULT
         * ========================================================
         */

        return {
            invoice,

            already_exists:
                false,

            customer_name:
                customer?.name ??
                'زبون نقدي عام',

            totals: {
                subtotal,

                discount_amount:
                    discountAmount,

                total,

                paid_amount:
                    paidAmount,

                due_amount:
                    dueAmount,
            },
        };
    }

    /**
     * لا نستخدم count + 1 هنا لأنه عرضة للتصادم
     * عندما تدخل عمليتا بيع في نفس الوقت.
     */
    private generateInvoiceNumber(): string {
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

        const suffix =
            randomBytes(4)
                .toString('hex')
                .toUpperCase();

        return `INV-${year}${month}-${suffix}`;
    }
}
