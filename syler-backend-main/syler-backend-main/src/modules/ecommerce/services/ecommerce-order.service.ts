import {
    BadRequestException,
    Injectable,
    NotFoundException,
    UnauthorizedException,
} from '@nestjs/common';

import {
    ecommerce_order_source_enum,
    Prisma,
} from '@prisma/client';

import { PrismaService } from '../../../prisma/prisma.service';
import { FloorService } from '../../floor/floor.service';

@Injectable()
export class EcommerceOrderService {
    constructor(
        private readonly prisma: PrismaService,
        private readonly floor: FloorService,
    ) { }

    /**
     * ============================================================
     * REPRESENTATIVE ORDERS
     * ============================================================
     */

    async getRepresentativeOrders(
        userId: string,
        params?: {
            page?: number;
            limit?: number;
            status?: string;
        },
    ) {
        if (!userId) {
            throw new UnauthorizedException({
                code: 'ECOMMERCE_REP_AUTH_REQUIRED',
                message: 'تسجيل دخول المندوب مطلوب',
            });
        }

        const page =
            params?.page && params.page > 0
                ? params.page
                : 1;

        const limit =
            params?.limit &&
                params.limit > 0 &&
                params.limit <= 100
                ? params.limit
                : 20;

        const skip =
            (page - 1) * limit;

        /**
         * نتأكد أن المستخدم مرتبط بمندوب.
         */
        const representative =
            await this.prisma.representatives.findUnique({
                where: {
                    user_id: userId,
                },
                select: {
                    id: true,
                },
            });

        if (!representative) {
            throw new NotFoundException({
                code: 'ECOMMERCE_REPRESENTATIVE_NOT_FOUND',
                message: 'المستخدم الحالي غير مرتبط بمندوب',
            });
        }

        const where: Prisma.ecommerce_ordersWhereInput = {
            source:
                ecommerce_order_source_enum.REPRESENTATIVE,

            user_id:
                userId,

            rep_id:
                representative.id,
        };

        if (params?.status) {
            where.status =
                params.status as any;
        }

        const [orders, total] =
            await this.prisma.$transaction([
                this.prisma.ecommerce_orders.findMany({
                    where,

                    skip,
                    take: limit,

                    include: {
                        items: true,
                    },

                    orderBy: {
                        submitted_at: 'desc',
                    },
                }),

                this.prisma.ecommerce_orders.count({
                    where,
                }),
            ]);

        return {
            data:
                orders.map(
                    (order) =>
                        this.mapOrder(order),
                ),

            meta: {
                page,
                per_page: limit,
                total,
                total_pages:
                    Math.ceil(
                        total / limit,
                    ),
            },
        };
    }

    async getRepresentativeOrder(
        userId: string,
        orderId: string,
    ) {
        if (!userId) {
            throw new UnauthorizedException({
                code: 'ECOMMERCE_REP_AUTH_REQUIRED',
                message: 'تسجيل دخول المندوب مطلوب',
            });
        }

        const order =
            await this.prisma.ecommerce_orders.findFirst({
                where: {
                    id: orderId,

                    user_id:
                        userId,

                    source:
                        ecommerce_order_source_enum
                            .REPRESENTATIVE,
                },

                include: {
                    items: true,
                },
            });

        if (!order) {
            throw new NotFoundException({
                code: 'ECOMMERCE_ORDER_NOT_FOUND',
                message: 'الطلب غير موجود',
            });
        }

        return {
            data:
                this.mapOrder(order),
        };
    }

    async cancelRepresentativeOrder(
        userId: string,
        orderId: string,
        reason: string,
    ) {
        if (!userId) {
            throw new UnauthorizedException({
                code: 'ECOMMERCE_REP_AUTH_REQUIRED',
                message: 'تسجيل دخول المندوب مطلوب',
            });
        }

        return this.prisma.$transaction(
            async (tx) => {
                /**
                 * Ownership check.
                 */
                const order =
                    await tx.ecommerce_orders.findFirst({
                        where: {
                            id:
                                orderId,

                            user_id:
                                userId,

                            source:
                                ecommerce_order_source_enum
                                    .REPRESENTATIVE,
                        },
                    });

                if (!order) {
                    throw new NotFoundException({
                        code:
                            'ECOMMERCE_ORDER_NOT_FOUND',

                        message:
                            'الطلب غير موجود',
                    });
                }

                /**
                 * فقط SUBMITTED يمكن إلغاؤه.
                 */
                if (
                    order.status !==
                    'SUBMITTED'
                ) {
                    throw new BadRequestException({
                        code:
                            'ECOMMERCE_ORDER_CANNOT_BE_CANCELLED',

                        message:
                            'لا يمكن إلغاء الطلب في حالته الحالية',

                        details: {
                            current_status:
                                order.status,
                        },
                    });
                }

                const updated =
                    await tx.ecommerce_orders.update({
                        where: {
                            id:
                                order.id,
                        },

                        data: {
                            status:
                                'CANCELLED',

                            cancelled_at:
                                new Date(),

                            cancelled_by:
                                userId,

                            cancellation_reason:
                                reason.trim(),
                        },

                        include: {
                            items: true,
                        },
                    });

                await this.floor.releaseOrder(tx, order.id);

                return {
                    data:
                        this.mapOrder(
                            updated,
                        ),
                };
            },
        );
    }

    /**
     * ============================================================
     * GUEST ORDERS
     * ============================================================
     */

    async getGuestOrder(
        orderNumber: string,
        orderToken: string,
    ) {
        if (!orderToken?.trim()) {
            throw new UnauthorizedException({
                code:
                    'ECOMMERCE_ORDER_TOKEN_REQUIRED',

                message:
                    'رمز الطلب مطلوب',
            });
        }

        const order =
            await this.prisma.ecommerce_orders.findFirst({
                where: {
                    order_number:
                        orderNumber,

                    public_token:
                        orderToken.trim(),

                    source:
                        ecommerce_order_source_enum.GUEST,
                },

                include: {
                    items: true,
                },
            });

        if (!order) {
            throw new NotFoundException({
                code:
                    'ECOMMERCE_ORDER_NOT_FOUND',

                message:
                    'الطلب غير موجود أو رمز الطلب غير صحيح',
            });
        }

        return {
            data:
                this.mapOrder(order),
        };
    }

    async cancelGuestOrder(
        orderNumber: string,
        orderToken: string,
        reason: string,
    ) {
        if (!orderToken?.trim()) {
            throw new UnauthorizedException({
                code:
                    'ECOMMERCE_ORDER_TOKEN_REQUIRED',

                message:
                    'رمز الطلب مطلوب',
            });
        }

        return this.prisma.$transaction(
            async (tx) => {
                const order =
                    await tx.ecommerce_orders.findFirst({
                        where: {
                            order_number:
                                orderNumber,

                            public_token:
                                orderToken.trim(),

                            source:
                                ecommerce_order_source_enum.GUEST,
                        },
                    });

                if (!order) {
                    throw new NotFoundException({
                        code:
                            'ECOMMERCE_ORDER_NOT_FOUND',

                        message:
                            'الطلب غير موجود أو رمز الطلب غير صحيح',
                    });
                }

                if (
                    order.status !==
                    'SUBMITTED'
                ) {
                    throw new BadRequestException({
                        code:
                            'ECOMMERCE_ORDER_CANNOT_BE_CANCELLED',

                        message:
                            'لا يمكن إلغاء الطلب في حالته الحالية',

                        details: {
                            current_status:
                                order.status,
                        },
                    });
                }

                /**
                 * Guest لا يوجد user_id.
                 *
                 * لذلك cancelled_by = null.
                 */
                const updated =
                    await tx.ecommerce_orders.update({
                        where: {
                            id:
                                order.id,
                        },

                        data: {
                            status:
                                'CANCELLED',

                            cancelled_at:
                                new Date(),

                            cancelled_by:
                                null,

                            cancellation_reason:
                                reason.trim(),
                        },

                        include: {
                            items: true,
                        },
                    });

                await this.floor.releaseOrder(tx, order.id);

                return {
                    data:
                        this.mapOrder(
                            updated,
                        ),
                };
            },
        );
    }

    /**
     * ============================================================
     * RESPONSE MAPPER
     * ============================================================
     */

    private mapOrder(
        order: any,
    ) {
        return {
            id:
                order.id,

            order_number:
                order.order_number,

            source:
                order.source,

            status:
                order.status,

            /**
             * Representative
             */
            rep_id:
                order.rep_id,

            party: order.party_type
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

            /**
             * Guest
             */
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

            rejected_at:
                order.rejected_at,

            rejection_reason:
                order.rejection_reason,

            cancelled_at:
                order.cancelled_at,

            cancellation_reason:
                order.cancellation_reason,

            sales_invoice_id:
                order.sales_invoice_id,

            items:
                order.items,
        };
    }
}