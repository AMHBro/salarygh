import {
    BadRequestException,
    ConflictException,
    Injectable,
    NotFoundException,
} from '@nestjs/common';

import {
    ecommerce_order_source_enum,
    price_type_enum,
    Prisma,
    sales_payment_enum,
} from '@prisma/client';

import {
    PrismaService,
} from '../../../prisma/prisma.service';

import {
    SalesTransactionService,
} from '../../direct-sales/sales-transaction.service';

@Injectable()
export class OrderApprovalService {
    constructor(
        private readonly prisma:
            PrismaService,

        private readonly salesTransactionService:
            SalesTransactionService,
    ) { }

    /**
     * ============================================================
     * ADMIN - ORDERS LIST
     * ============================================================
     */
    async getOrders(params?: {
        page?: number;
        limit?: number;
        status?: string;
        source?: ecommerce_order_source_enum;
        search?: string;
    }) {
        const page =
            params?.page &&
                params.page > 0
                ? params.page
                : 1;

        const limit =
            params?.limit &&
                params.limit > 0 &&
                params.limit <= 100
                ? params.limit
                : 20;

        const skip =
            (page - 1) *
            limit;

        const search =
            params?.search?.trim();

        const where:
            Prisma.ecommerce_ordersWhereInput =
            {};

        /**
         * Status filter
         */
        if (
            params?.status
        ) {
            where.status =
                params.status as any;
        }

        /**
         * Source filter
         */
        if (
            params?.source
        ) {
            where.source =
                params.source;
        }

        /**
         * Search
         */
        if (
            search
        ) {
            where.OR = [
                {
                    order_number: {
                        contains:
                            search,

                        mode:
                            'insensitive',
                    },
                },

                {
                    customer_name: {
                        contains:
                            search,

                        mode:
                            'insensitive',
                    },
                },

                {
                    customer_phone: {
                        contains:
                            search,

                        mode:
                            'insensitive',
                    },
                },

                {
                    party_name: {
                        contains:
                            search,

                        mode:
                            'insensitive',
                    },
                },

                {
                    party_phone: {
                        contains:
                            search,

                        mode:
                            'insensitive',
                    },
                },
            ];
        }

        const [
            orders,
            total,
        ] =
            await this.prisma.$transaction([
                this.prisma.ecommerce_orders.findMany({
                    where,

                    skip,

                    take:
                        limit,

                    include: {
                        items:
                            true,
                    },

                    orderBy: {
                        submitted_at:
                            'desc',
                    },
                }),

                this.prisma.ecommerce_orders.count({
                    where,
                }),
            ]);

        /**
         * Representatives batch loading.
         *
         * لا نعتمد على relation name داخل Prisma.
         */
        const repIds =
            [
                ...new Set(
                    orders
                        .map(
                            (order) =>
                                order.rep_id,
                        )
                        .filter(
                            (
                                id,
                            ): id is string =>
                                Boolean(
                                    id,
                                ),
                        ),
                ),
            ];

        const representatives =
            repIds.length
                ? await this.prisma.representatives.findMany({
                    where: {
                        id: {
                            in:
                                repIds,
                        },
                    },

                    select: {
                        id:
                            true,

                        name:
                            true,

                        phone:
                            true,

                        office_name:
                            true,

                        office_phone:
                            true,

                        office_address:
                            true,
                    },
                })
                : [];

        const representativeMap =
            new Map(
                representatives.map(
                    (
                        representative,
                    ) => [
                            representative.id,
                            representative,
                        ],
                ),
            );

        return {
            data:
                orders.map(
                    (
                        order,
                    ) =>
                        this.mapOrder(
                            order,

                            order.rep_id
                                ? representativeMap.get(
                                    order.rep_id,
                                ) ??
                                null
                                : null,
                        ),
                ),

            meta: {
                page,

                per_page:
                    limit,

                total,

                total_pages:
                    Math.ceil(
                        total /
                        limit,
                    ),
            },
        };
    }

    /**
     * ============================================================
     * ADMIN - ORDER DETAILS
     * ============================================================
     */
    async getOrder(
        orderId: string,
    ) {
        const order =
            await this.prisma.ecommerce_orders.findUnique({
                where: {
                    id:
                        orderId,
                },

                include: {
                    items:
                        true,
                },
            });

        if (
            !order
        ) {
            throw new NotFoundException({
                code:
                    'ECOMMERCE_ORDER_NOT_FOUND',

                message:
                    'الطلب غير موجود',
            });
        }

        const representative =
            order.rep_id
                ? await this.prisma.representatives.findUnique({
                    where: {
                        id:
                            order.rep_id,
                    },

                    select: {
                        id:
                            true,

                        user_id:
                            true,

                        name:
                            true,

                        phone:
                            true,

                        branch_id:
                            true,

                        office_name:
                            true,

                        office_phone:
                            true,

                        office_address:
                            true,

                        status:
                            true,
                    },
                })
                : null;

        return {
            data:
                this.mapOrder(
                    order,
                    representative,
                ),
        };
    }

    /**
     * ============================================================
     * ADMIN - REJECT
     * ============================================================
     */
    async rejectOrder(
        orderId: string,
        adminUserId: string,
        reason: string,
    ) {
        if (
            !reason?.trim()
        ) {
            throw new BadRequestException({
                code:
                    'ECOMMERCE_REJECTION_REASON_REQUIRED',

                message:
                    'سبب رفض الطلب مطلوب',
            });
        }

        return this.prisma.$transaction(
            async (
                tx,
            ) => {
                const order =
                    await tx.ecommerce_orders.findUnique({
                        where: {
                            id:
                                orderId,
                        },
                    });

                if (
                    !order
                ) {
                    throw new NotFoundException({
                        code:
                            'ECOMMERCE_ORDER_NOT_FOUND',

                        message:
                            'الطلب غير موجود',
                    });
                }

                if (
                    order.status !==
                    'SUBMITTED'
                ) {
                    throw new BadRequestException({
                        code:
                            'ECOMMERCE_ORDER_CANNOT_BE_REJECTED',

                        message:
                            'لا يمكن رفض الطلب في حالته الحالية',

                        details: {
                            current_status:
                                order.status,
                        },
                    });
                }

                if (
                    order.sales_invoice_id
                ) {
                    throw new BadRequestException({
                        code:
                            'ECOMMERCE_ORDER_ALREADY_INVOICED',

                        message:
                            'الطلب مرتبط بفاتورة بيع ولا يمكن رفضه',
                    });
                }

                const result =
                    await tx.ecommerce_orders.updateMany({
                        where: {
                            id:
                                order.id,

                            status:
                                'SUBMITTED',

                            sales_invoice_id:
                                null,
                        },

                        data: {
                            status:
                                'REJECTED',

                            rejected_at:
                                new Date(),

                            rejected_by:
                                adminUserId,

                            rejection_reason:
                                reason.trim(),
                        },
                    });

                /**
                 * Race protection.
                 */
                if (
                    result.count !==
                    1
                ) {
                    throw new ConflictException({
                        code:
                            'ECOMMERCE_ORDER_STATE_CHANGED',

                        message:
                            'تم تغيير حالة الطلب بواسطة عملية أخرى',
                    });
                }

                const updated =
                    await tx.ecommerce_orders.findUnique({
                        where: {
                            id:
                                order.id,
                        },

                        include: {
                            items:
                                true,
                        },
                    });

                return {
                    data:
                        this.mapOrder(
                            updated,
                        ),
                };
            },

            {
                isolationLevel:
                    Prisma
                        .TransactionIsolationLevel
                        .Serializable,
            },
        );
    }

    /**
     * ============================================================
     * VALIDATE BEFORE ACCEPT
     * ============================================================
     *
     * تستخدم مثلاً إذا أردنا Preview لفحص المخزون
     * قبل تنفيذ Accept الحقيقي.
     */
    async validateForAcceptance(
        orderId: string,
        warehouseId: string,
    ) {
        const order =
            await this.prisma.ecommerce_orders.findUnique({
                where: {
                    id:
                        orderId,
                },

                include: {
                    items: {
                        include: {
                            unit:
                                true,
                        },
                    },
                },
            });

        if (
            !order
        ) {
            throw new NotFoundException({
                code:
                    'ECOMMERCE_ORDER_NOT_FOUND',

                message:
                    'الطلب غير موجود',
            });
        }

        if (
            order.status !==
            'SUBMITTED'
        ) {
            throw new BadRequestException({
                code:
                    'ECOMMERCE_ORDER_CANNOT_BE_ACCEPTED',

                message:
                    'لا يمكن قبول الطلب في حالته الحالية',

                details: {
                    current_status:
                        order.status,
                },
            });
        }

        if (
            order.sales_invoice_id
        ) {
            throw new BadRequestException({
                code:
                    'ECOMMERCE_ORDER_ALREADY_INVOICED',

                message:
                    'الطلب مرتبط بفاتورة بيع مسبقاً',
            });
        }

        if (
            order.items.length ===
            0
        ) {
            throw new BadRequestException({
                code:
                    'ECOMMERCE_ORDER_EMPTY',

                message:
                    'الطلب لا يحتوي على منتجات',
            });
        }

        const warehouse =
            await this.prisma.warehouses.findUnique({
                where: {
                    id:
                        warehouseId,
                },

                select: {
                    id:
                        true,

                    code:
                        true,

                    name:
                        true,

                    status:
                        true,

                    branch_id:
                        true,
                },
            });

        if (
            !warehouse
        ) {
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

        const stockValidation: any[] =
            [];

        for (
            const item of
            order.items
        ) {
            if (
                !item.unit
            ) {
                throw new BadRequestException({
                    code:
                        'ORDER_UNIT_NOT_FOUND',

                    message:
                        'وحدة قياس المنتج غير موجودة',
                });
            }

            const conversionFactor =
                item.unit
                    .conversion_factor;

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

            const requiredBaseQuantity =
                item.quantity.mul(
                    conversionFactor,
                );

            const stock =
                await this.prisma.stock_levels.findUnique({
                    where: {
                        variant_id_warehouse_id: {
                            variant_id:
                                item.variant_id,

                            warehouse_id:
                                warehouseId,
                        },
                    },
                });

            const onHand =
                stock
                    ?.quantity_on_hand ??
                new Prisma.Decimal(
                    0,
                );

            const reserved =
                stock
                    ?.quantity_reserved ??
                new Prisma.Decimal(
                    0,
                );

            const available =
                onHand.sub(
                    reserved,
                );

            stockValidation.push({
                variant_id:
                    item.variant_id,

                unit_id:
                    item.unit_id,

                quantity:
                    item.quantity.toString(),

                conversion_factor:
                    conversionFactor.toString(),

                required_base_quantity:
                    requiredBaseQuantity.toString(),

                available_base_quantity:
                    available.toString(),
            });

            if (
                available.lt(
                    requiredBaseQuantity,
                )
            ) {
                throw new BadRequestException({
                    code:
                        'INSUFFICIENT_STOCK',

                    message:
                        'الكمية المطلوبة غير متوفرة في المخزن المحدد',

                    details: {
                        variant_id:
                            item.variant_id,

                        warehouse_id:
                            warehouseId,

                        required_base_quantity:
                            requiredBaseQuantity.toString(),

                        available_base_quantity:
                            available.toString(),
                    },
                });
            }
        }

        return {
            order,

            warehouse,

            stock_validation:
                stockValidation,
        };
    }

    /**
     * ============================================================
     * ADMIN - ACCEPT ORDER
     * ============================================================
     *
     * هذه هي نقطة الربط الرئيسية مع SalesTransactionService.
     */
    async acceptOrder(
        orderId: string,
        adminUserId: string,
        warehouseId: string,
        paidAmount?: number,
    ) {
        return this.prisma.$transaction(
            async (
                tx,
            ) => {
                /**
                 * =================================================
                 * 1. GET ORDER
                 * =================================================
                 */
                const order =
                    await tx.ecommerce_orders.findUnique({
                        where: {
                            id:
                                orderId,
                        },

                        include: {
                            items:
                                true,
                        },
                    });

                if (
                    !order
                ) {
                    throw new NotFoundException({
                        code:
                            'ECOMMERCE_ORDER_NOT_FOUND',

                        message:
                            'الطلب غير موجود',
                    });
                }

                /**
                 * =================================================
                 * 2. IDEMPOTENT ACCEPT
                 * =================================================
                 *
                 * إذا الطلب Accepted مسبقاً
                 * وله Invoice نرجع العملية الحالية.
                 */
                if (
                    order.status ===
                    'ACCEPTED' &&
                    order.sales_invoice_id
                ) {
                    const invoice =
                        await tx.sales_invoices.findUnique({
                            where: {
                                id:
                                    order.sales_invoice_id,
                            },
                        });

                    return {
                        data: {
                            order_id:
                                order.id,

                            order_number:
                                order.order_number,

                            status:
                                order.status,

                            sales_invoice_id:
                                order.sales_invoice_id,

                            invoice_number:
                                invoice
                                    ?.invoice_number ??
                                null,

                            already_accepted:
                                true,
                        },
                    };
                }

                /**
                 * فقط SUBMITTED.
                 */
                if (
                    order.status !==
                    'SUBMITTED'
                ) {
                    throw new BadRequestException({
                        code:
                            'ECOMMERCE_ORDER_CANNOT_BE_ACCEPTED',

                        message:
                            'لا يمكن قبول الطلب في حالته الحالية',

                        details: {
                            current_status:
                                order.status,
                        },
                    });
                }

                if (
                    order.sales_invoice_id
                ) {
                    throw new ConflictException({
                        code:
                            'ECOMMERCE_ORDER_ALREADY_INVOICED',

                        message:
                            'الطلب مرتبط بفاتورة بيع مسبقاً',
                    });
                }

                if (
                    order.items.length ===
                    0
                ) {
                    throw new BadRequestException({
                        code:
                            'ECOMMERCE_ORDER_EMPTY',

                        message:
                            'الطلب لا يحتوي على منتجات',
                    });
                }

                /**
                 * =================================================
                 * 3. WAREHOUSE
                 * =================================================
                 */

                const warehouse =
                    await tx.warehouses.findUnique({
                        where: {
                            id:
                                warehouseId,
                        },

                        select: {
                            id:
                                true,

                            status:
                                true,
                        },
                    });

                if (
                    !warehouse
                ) {
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
                 * =================================================
                 * 4. PAYMENT TYPE
                 * =================================================
                 */

                if (
                    !order.payment_type
                ) {
                    throw new BadRequestException({
                        code:
                            'ECOMMERCE_PAYMENT_TYPE_REQUIRED',

                        message:
                            'طريقة دفع الطلب غير محددة',
                    });
                }

                /**
                 * PARTIAL يحتاج Paid Amount.
                 */
                if (
                    order.payment_type ===
                    sales_payment_enum.PARTIAL &&
                    (
                        paidAmount ===
                        undefined ||
                        paidAmount ===
                        null
                    )
                ) {
                    throw new BadRequestException({
                        code:
                            'ECOMMERCE_PAID_AMOUNT_REQUIRED',

                        message:
                            'المبلغ المدفوع مطلوب عند قبول طلب بدفع جزئي',
                    });
                }

                /**
                 * =================================================
                 * 5. RESOLVE CUSTOMER
                 * =================================================
                 */

                const customerId =
                    await this.resolveCustomerForSale(
                        tx,
                        order,
                    );

                /**
                 * CREDIT / PARTIAL
                 * يجب أن يكون مرتبطاً بحساب Customer.
                 */
                if (
                    (
                        order.payment_type ===
                        sales_payment_enum.CREDIT ||
                        order.payment_type ===
                        sales_payment_enum.PARTIAL
                    ) &&
                    !customerId
                ) {
                    throw new BadRequestException({
                        code:
                            'ECOMMERCE_CUSTOMER_REQUIRED_FOR_CREDIT',

                        message:
                            'البيع بالآجل أو الجزئي يتطلب جهة مرتبطة بحساب زبون',
                    });
                }

                /**
                 * =================================================
                 * 6. PRICE TYPE
                 * =================================================
                 */

                const listedPriceType =
                    order.items[0]?.price_type;

                const priceType =
                    listedPriceType ??
                    (
                        order.source ===
                            ecommerce_order_source_enum.REPRESENTATIVE
                            ? price_type_enum.REP
                            : price_type_enum.RETAIL
                    );

                /**
                 * =================================================
                 * 7. SALES IDEMPOTENCY
                 * =================================================
                 *
                 * ثابت لكل Ecommerce Order.
                 */
                const salesIdempotencyKey =
                    `ECOMMERCE-ORDER-${order.id}`;

                /**
                 * =================================================
                 * 8. CREATE SALE
                 * =================================================
                 *
                 * هذه الدالة:
                 *
                 * - تتحقق من الوحدات
                 * - تحول Base Quantity
                 * - تتحقق من المخزون
                 * - تتحقق من Credit Limit
                 * - تنشئ Invoice
                 * - تنشئ Items
                 * - تخصم Stock
                 * - تنشئ Inventory Movements
                 * - تحدث Customer Balance
                 */

                const sale =
                    await this.salesTransactionService.createSale(
                        tx,

                        {
                            customer_id:
                                customerId,

                            rep_id:
                                order.source ===
                                    ecommerce_order_source_enum
                                        .REPRESENTATIVE
                                    ? order.rep_id
                                    : null,

                            warehouse_id:
                                warehouseId,

                            price_type:
                                priceType,

                            payment_type:
                                order.payment_type,

                            discount_amount:
                                order.discount_amount,

                            paid_amount:
                                order.payment_type ===
                                    sales_payment_enum.PARTIAL
                                    ? paidAmount ??
                                    0
                                    : 0,

                            notes:
                                this.buildSaleNotes(
                                    order,
                                ),

                            idempotency_key:
                                salesIdempotencyKey,

                            created_by:
                                adminUserId,

                            items:
                                order.items.map(
                                    (
                                        item,
                                    ) => ({
                                        variant_id:
                                            item.variant_id,

                                        unit_id:
                                            item.unit_id,

                                        quantity:
                                            item.quantity,

                                        /**
                                         * مهم:
                                         *
                                         * نستخدم Snapshot سعر الطلب.
                                         *
                                         * لا نعيد قراءة سعر المنتج
                                         * عند Acceptance.
                                         */
                                        unit_price:
                                            item.unit_price,

                                        discount_percent:
                                            0,
                                    }),
                                ),
                        },
                    );

                const invoice =
                    sale.invoice;

                /**
                 * =================================================
                 * 9. SAFETY TOTAL CHECK
                 * =================================================
                 *
                 * لأن السعر تم تثبيته عند Checkout،
                 * يجب أن تكون قيمة Invoice مطابقة للطلب.
                 */

                const orderTotal =
                    new Prisma.Decimal(
                        order.total,
                    );

                const invoiceTotal =
                    new Prisma.Decimal(
                        invoice.total,
                    );

                if (
                    !invoiceTotal.eq(
                        orderTotal,
                    )
                ) {
                    throw new ConflictException({
                        code:
                            'ECOMMERCE_ORDER_TOTAL_MISMATCH',

                        message:
                            'إجمالي فاتورة البيع لا يطابق إجمالي طلب المتجر',

                        details: {
                            order_total:
                                orderTotal.toString(),

                            invoice_total:
                                invoiceTotal.toString(),
                        },
                    });
                }

                /**
                 * =================================================
                 * 10. MARK ORDER ACCEPTED
                 * =================================================
                 *
                 * updateMany تستخدم كـOptimistic Guard.
                 */

                const updateResult =
                    await tx.ecommerce_orders.updateMany({
                        where: {
                            id:
                                order.id,

                            status:
                                'SUBMITTED',

                            sales_invoice_id:
                                null,
                        },

                        data: {
                            status:
                                'ACCEPTED',

                            accepted_at:
                                new Date(),

                            accepted_by:
                                adminUserId,

                            sales_invoice_id:
                                invoice.id,
                        },
                    });

                if (
                    updateResult.count !==
                    1
                ) {
                    /**
                     * throw = Rollback
                     *
                     * يعني Invoice + Stock أيضاً يرجعون.
                     */
                    throw new ConflictException({
                        code:
                            'ECOMMERCE_ORDER_ACCEPT_CONFLICT',

                        message:
                            'تمت معالجة الطلب بواسطة عملية أخرى',
                    });
                }

                /**
                 * =================================================
                 * 11. RESULT
                 * =================================================
                 */

                return {
                    data: {
                        order_id:
                            order.id,

                        order_number:
                            order.order_number,

                        status:
                            'ACCEPTED',

                        sales_invoice_id:
                            invoice.id,

                        invoice_number:
                            invoice.invoice_number,

                        warehouse_id:
                            warehouseId,

                        source:
                            order.source,

                        rep_id:
                            order.rep_id,

                        customer_id:
                            customerId,

                        payment_type:
                            invoice.payment_type,

                        total:
                            Number(
                                invoice.total,
                            ),

                        paid_amount:
                            Number(
                                invoice.paid_amount,
                            ),

                        due_amount:
                            Number(
                                invoice.due_amount,
                            ),

                        accepted_at:
                            new Date(),
                    },

                    message:
                        'تم قبول الطلب وإنشاء فاتورة المبيعات بنجاح',
                };
            },

            /**
             * مهم جداً للـAcceptance.
             */
            {
                isolationLevel:
                    Prisma
                        .TransactionIsolationLevel
                        .Serializable,

                maxWait:
                    5000,

                timeout:
                    15000,
            },
        );
    }

    /**
     * ============================================================
     * CUSTOMER RESOLUTION
     * ============================================================
     */
    private async resolveCustomerForSale(
        tx:
            Prisma.TransactionClient,

        order:
            any,
    ): Promise<
        string | null
    > {
        /**
         * ========================================================
         * REPRESENTATIVE ORDER
         * ========================================================
         *
         * إذا Party = CUSTOMER
         * فإن party_id هو customers.id.
         */
        if (
            order.source ===
            ecommerce_order_source_enum.REPRESENTATIVE
        ) {
            if (
                order.party_type ===
                'CUSTOMER' &&
                order.party_id
            ) {
                const customer =
                    await tx.customers.findUnique({
                        where: {
                            id:
                                order.party_id,
                        },

                        select: {
                            id:
                                true,

                            is_active:
                                true,
                        },
                    });

                if (
                    customer
                ) {
                    if (
                        !customer.is_active
                    ) {
                        throw new BadRequestException({
                            code:
                                'ECOMMERCE_PARTY_CUSTOMER_INACTIVE',

                            message:
                                'الزبون المرتبط بالطلب غير فعال',
                        });
                    }

                    return customer.id;
                }
            }

            /**
             * Cash يمكن أن يكون Party غير Customer.
             *
             * Invoice تبقى مرتبطة بالمندوب عن طريق rep_id.
             */
            if (
                order.payment_type ===
                sales_payment_enum.CASH
            ) {
                return null;
            }

            /**
             * قائمة المندوب الآجلة تسجّل باسم المكتب
             * حتى لو لم يُرسل رقم زبون من السيرفر.
             */
            const opensCustomerAccount =
                !order.party_type ||
                order.party_type ===
                'OTHER' ||
                order.party_type ===
                'CUSTOMER';

            if (
                opensCustomerAccount
            ) {
                return this.ensureNamedCustomer(
                    tx,
                    order,
                );
            }

            throw new BadRequestException({
                code:
                    'ECOMMERCE_CREDIT_REQUIRES_CUSTOMER_PARTY',

                message:
                    'البيع بالآجل أو الجزئي يتطلب أن تكون الجهة المختارة من نوع CUSTOMER',
            });
        }

        /**
         * ========================================================
         * GUEST ORDER
         * ========================================================
         */

        if (
            order.source ===
            ecommerce_order_source_enum.GUEST
        ) {
            /**
             * نحاول ربطه بزبون Accounting موجود
             * بنفس رقم الهاتف.
             */
            if (
                order.customer_phone
            ) {
                const existing =
                    await tx.customers.findFirst({
                        where: {
                            phone:
                                order.customer_phone,
                        },

                        select: {
                            id:
                                true,

                            is_active:
                                true,
                        },
                    });

                if (
                    existing
                ) {
                    if (
                        !existing.is_active
                    ) {
                        throw new BadRequestException({
                            code:
                                'CUSTOMER_INACTIVE',

                            message:
                                'حساب الزبون المرتبط برقم الهاتف غير فعال',
                        });
                    }

                    return existing.id;
                }
            }

            /**
             * Guest CASH:
             *
             * لا ننشئ Customer إجباري.
             */
            if (
                order.payment_type ===
                sales_payment_enum.CASH
            ) {
                return null;
            }

            /**
             * Guest CREDIT/PARTIAL:
             *
             * SalesTransactionService يحتاج Customer
             * حتى يسجل due_amount.
             */
            if (
                !order.customer_name ||
                !order.customer_phone
            ) {
                throw new BadRequestException({
                    code:
                        'GUEST_CUSTOMER_DATA_REQUIRED',

                    message:
                        'بيانات الزبون غير مكتملة لإنشاء حساب ذمة',
                });
            }

            const created =
                await tx.customers.create({
                    data: {
                        name:
                            order.customer_name,

                        phone:
                            order.customer_phone,

                        email:
                            order.customer_email ??
                            null,

                        address:
                            order.customer_address ??
                            null,

                        is_active:
                            true,
                    },

                    select: {
                        id:
                            true,
                    },
                });

            return created.id;
        }

        return null;
    }

    /**
     * يربط قائمة المندوب الآجلة بزبون موجود أو ينشئ حساباً باسم المكتب.
     */
    private async ensureNamedCustomer(
        tx:
            Prisma.TransactionClient,

        order:
            any,
    ): Promise<string> {
        const name =
            `${order.party_name ?? order.customer_name ?? ''}`
                .trim();

        const phone =
            `${order.party_phone ?? order.customer_phone ?? ''}`
                .trim();

        const storedPhone =
            phone.length > 0 &&
            phone.length <= 20
                ? phone
                : null;

        if (
            storedPhone
        ) {
            const byPhone =
                await tx.customers.findFirst({
                    where: {
                        phone:
                            storedPhone,
                    },

                    select: {
                        id:
                            true,

                        is_active:
                            true,
                    },
                });

            if (
                byPhone
            ) {
                if (
                    !byPhone.is_active
                ) {
                    throw new BadRequestException({
                        code:
                            'CUSTOMER_INACTIVE',

                        message:
                            'حساب الزبون المرتبط برقم الهاتف غير فعال',
                    });
                }

                return byPhone.id;
            }
        }

        if (
            name
        ) {
            const byName =
                await tx.customers.findFirst({
                    where: {
                        name,
                    },

                    select: {
                        id:
                            true,

                        is_active:
                            true,
                    },
                });

            if (
                byName
            ) {
                if (
                    !byName.is_active
                ) {
                    throw new BadRequestException({
                        code:
                            'CUSTOMER_INACTIVE',

                        message:
                            'الزبون المرتبط بالطلب غير فعال',
                    });
                }

                return byName.id;
            }
        }

        if (
            !name
        ) {
            throw new BadRequestException({
                code:
                    'ECOMMERCE_CUSTOMER_NAME_REQUIRED',

                message:
                    'اسم الزبون مطلوب لتسجيل قائمة المندوب الآجلة',
            });
        }

        const created =
            await tx.customers.create({
                data: {
                    name,

                    phone:
                        storedPhone,

                    address:
                        order.party_address ??
                        order.customer_address ??
                        null,

                    assigned_rep_id:
                        order.rep_id ??
                        null,

                    is_active:
                        true,
                },

                select: {
                    id:
                        true,
                },
            });

        return created.id;
    }

    /**
     * ============================================================
     * SALES NOTES
     * ============================================================
     */
    private buildSaleNotes(
        order:
            any,
    ): string {
        const notes: string[] =
            [
                `Ecommerce Order: ${order.order_number}`,
            ];

        if (
            order.party_name
        ) {
            notes.push(
                `Party: ${order.party_name}`,
            );
        }

        if (
            order.notes
        ) {
            notes.push(
                order.notes,
            );
        }

        return notes.join(
            ' | ',
        );
    }

    /**
     * ============================================================
     * RESPONSE MAPPER
     * ============================================================
     */
    private mapOrder(
        order:
            any,

        representative?:
            any,
    ) {
        if (
            !order
        ) {
            return null;
        }

        return {
            id:
                order.id,

            order_number:
                order.order_number,

            source:
                order.source,

            status:
                order.status,

            rep_id:
                order.rep_id,

            representative:
                representative
                    ? {
                        id:
                            representative.id,

                        name:
                            representative.name,

                        phone:
                            representative.phone,

                        office_name:
                            representative.office_name,

                        office_phone:
                            representative.office_phone,

                        office_address:
                            representative.office_address,
                    }
                    : null,

            party:
                order.party_type
                    ? {
                        type:
                            order.party_type,

                        id:
                            order.party_id,

                        name:
                            order.party_name,

                        phone:
                            order.party_phone,

                        address:
                            order.party_address,
                    }
                    : null,

            customer:
                order.source ===
                    ecommerce_order_source_enum.GUEST
                    ? {
                        name:
                            order.customer_name,

                        phone:
                            order.customer_phone,

                        email:
                            order.customer_email,

                        address:
                            order.customer_address,
                    }
                    : null,

            payment_type:
                order.payment_type,

            subtotal:
                order.subtotal,

            discount_amount:
                order.discount_amount,

            total:
                order.total,

            notes:
                order.notes,

            submitted_at:
                order.submitted_at,

            accepted_at:
                order.accepted_at,

            accepted_by:
                order.accepted_by,

            rejected_at:
                order.rejected_at,

            rejected_by:
                order.rejected_by,

            rejection_reason:
                order.rejection_reason,

            cancelled_at:
                order.cancelled_at,

            cancelled_by:
                order.cancelled_by,

            cancellation_reason:
                order.cancellation_reason,

            sales_invoice_id:
                order.sales_invoice_id,

            items:
                order.items,
        };
    }
}