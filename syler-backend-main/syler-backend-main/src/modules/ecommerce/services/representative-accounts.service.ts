import {
    Injectable,
    NotFoundException,
} from '@nestjs/common';

import {
    ecommerce_order_source_enum,
    ecommerce_party_type_enum,
    Prisma,
} from '@prisma/client';

import {
    PrismaService,
} from 'src/prisma/prisma.service';

interface RepresentativeAccountsQuery {
    search?: string;

    party_type?:
    ecommerce_party_type_enum;

    has_balance?:
    boolean;

    page?:
    number;

    limit?:
    number;
}

@Injectable()
export class RepresentativeAccountsService {
    constructor(
        private readonly prisma:
            PrismaService,
    ) { }

    /**
     * ============================================================
     * GET REPRESENTATIVE ACCOUNTS
     * ============================================================
     *
     * يعرض جميع الجهات التي سبق أن تعامل معها المندوب
     * عن طريق Ecommerce Orders.
     *
     * كل Party تظهر مرة واحدة فقط.
     *
     * ويحسب:
     *
     * orders_count
     * accepted_orders
     * submitted_orders
     * rejected_orders
     * cancelled_orders
     *
     * total_sales
     * total_paid
     * representative_due
     *
     * وإذا كانت Party من نوع CUSTOMER:
     *
     * current_balance
     * credit_limit
     * available_credit
     */
    async getAccounts(
        userId: string,

        query:
            RepresentativeAccountsQuery =
            {},
    ) {
        /**
         * ========================================================
         * 1. Resolve Representative from JWT User
         * ========================================================
         */
        const representative =
            await this.prisma.representatives.findUnique({
                where: {
                    user_id:
                        userId,
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

                    status:
                        true,

                    office_name:
                        true,
                },
            });

        if (
            !representative
        ) {
            throw new NotFoundException({
                code:
                    'REPRESENTATIVE_NOT_FOUND',

                message:
                    'المستخدم الحالي غير مرتبط بمندوب',
            });
        }

        /**
         * ========================================================
         * 2. Representative Orders
         * ========================================================
         */

        const where:
            Prisma.ecommerce_ordersWhereInput =
        {
            source:
                ecommerce_order_source_enum
                    .REPRESENTATIVE,

            rep_id:
                representative.id,
        };

        if (
            query.party_type
        ) {
            where.party_type =
                query.party_type;
        }

        const search =
            query.search
                ?.trim();

        if (
            search
        ) {
            where.OR = [
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

                {
                    party_address: {
                        contains:
                            search,

                        mode:
                            'insensitive',
                    },
                },
            ];
        }

        const orders =
            await this.prisma.ecommerce_orders.findMany({
                where,

                select: {
                    id:
                        true,

                    order_number:
                        true,

                    party_type:
                        true,

                    party_id:
                        true,

                    party_name:
                        true,

                    party_phone:
                        true,

                    party_address:
                        true,

                    status:
                        true,

                    total:
                        true,

                    payment_type:
                        true,

                    sales_invoice_id:
                        true,

                    submitted_at:
                        true,

                    accepted_at:
                        true,

                    created_at:
                        true,
                },

                orderBy: {
                    submitted_at:
                        'desc',
                },
            });

        /**
         * ========================================================
         * 3. Load Sales Invoices
         * ========================================================
         */

        const invoiceIds =
            [
                ...new Set(
                    orders
                        .map(
                            (
                                order,
                            ) =>
                                order.sales_invoice_id,
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

        const invoices =
            invoiceIds.length >
                0
                ? await this.prisma.sales_invoices.findMany({
                    where: {
                        id: {
                            in:
                                invoiceIds,
                        },

                        /**
                         * حماية إضافية:
                         * الفاتورة يجب أن تكون للمندوب نفسه.
                         */
                        rep_id:
                            representative.id,
                    },

                    select: {
                        id:
                            true,

                        invoice_number:
                            true,

                        customer_id:
                            true,

                        total:
                            true,

                        paid_amount:
                            true,

                        due_amount:
                            true,

                        payment_type:
                            true,

                        status:
                            true,

                        invoice_date:
                            true,

                        created_at:
                            true,
                    },
                })
                : [];

        const invoiceMap =
            new Map(
                invoices.map(
                    (
                        invoice,
                    ) => [
                            invoice.id,
                            invoice,
                        ],
                ),
            );

        /**
         * ========================================================
         * 4. Group Orders By Party
         * ========================================================
         */

        const accountsMap =
            new Map<
                string,
                {
                    account_key:
                    string;

                    party_type:
                    ecommerce_party_type_enum | null;

                    party_id:
                    string | null;

                    party_name:
                    string;

                    party_phone:
                    string | null;

                    party_address:
                    string | null;

                    orders_count:
                    number;

                    submitted_orders:
                    number;

                    accepted_orders:
                    number;

                    rejected_orders:
                    number;

                    cancelled_orders:
                    number;

                    total_orders_value:
                    Prisma.Decimal;

                    total_sales:
                    Prisma.Decimal;

                    total_paid:
                    Prisma.Decimal;

                    representative_due:
                    Prisma.Decimal;

                    last_order_at:
                    Date | null;

                    last_order_number:
                    string | null;

                    last_invoice_number:
                    string | null;

                    recent_orders:
                    Array<{
                        id:
                        string;

                        order_number:
                        string;

                        status:
                        any;

                        total:
                        Prisma.Decimal;

                        invoice_number:
                        string | null;

                        paid_amount:
                        Prisma.Decimal;

                        due_amount:
                        Prisma.Decimal;

                        submitted_at:
                        Date;
                    }>;
                }
            >();

        for (
            const order of
            orders
        ) {
            /**
             * Party ID هو أفضل Identifier.
             *
             * OTHER قد لا يحتوي party_id،
             * فنستخدم phone/name لبناء Key مؤقت.
             */
            const accountKey =
                this.buildAccountKey(
                    order.party_type,

                    order.party_id,

                    order.party_phone,

                    order.party_name,
                );

            let account =
                accountsMap.get(
                    accountKey,
                );

            if (
                !account
            ) {
                account = {
                    account_key:
                        accountKey,

                    party_type:
                        order.party_type,

                    party_id:
                        order.party_id,

                    party_name:
                        order.party_name ??
                        'جهة غير مسماة',

                    party_phone:
                        order.party_phone,

                    party_address:
                        order.party_address,

                    orders_count:
                        0,

                    submitted_orders:
                        0,

                    accepted_orders:
                        0,

                    rejected_orders:
                        0,

                    cancelled_orders:
                        0,

                    total_orders_value:
                        new Prisma.Decimal(
                            0,
                        ),

                    total_sales:
                        new Prisma.Decimal(
                            0,
                        ),

                    total_paid:
                        new Prisma.Decimal(
                            0,
                        ),

                    representative_due:
                        new Prisma.Decimal(
                            0,
                        ),

                    last_order_at:
                        null,

                    last_order_number:
                        null,

                    last_invoice_number:
                        null,

                    recent_orders:
                        [],
                };
            }

            /**
             * Orders Count
             */
            account.orders_count++;

            account.total_orders_value =
                account.total_orders_value.add(
                    order.total,
                );

            /**
             * Status counters
             */
            switch (
            String(
                order.status,
            )
            ) {
                case 'SUBMITTED':
                    account.submitted_orders++;
                    break;

                case 'ACCEPTED':
                    account.accepted_orders++;
                    break;

                case 'REJECTED':
                    account.rejected_orders++;
                    break;

                case 'CANCELLED':
                    account.cancelled_orders++;
                    break;
            }

            /**
             * Last order
             *
             * orders جايين desc،
             * لذلك أول Order هو الأحدث.
             */
            if (
                !account.last_order_at
            ) {
                account.last_order_at =
                    order.submitted_at;

                account.last_order_number =
                    order.order_number;
            }

            /**
             * ====================================================
             * Accounting values only from Sales Invoice
             * ====================================================
             *
             * SUBMITTED Order لا نحسبه Sales.
             */

            const invoice =
                order.sales_invoice_id
                    ? invoiceMap.get(
                        order.sales_invoice_id,
                    )
                    : undefined;

            if (
                invoice
            ) {
                account.total_sales =
                    account.total_sales.add(
                        invoice.total,
                    );

                account.total_paid =
                    account.total_paid.add(
                        invoice.paid_amount,
                    );

                account.representative_due =
                    account.representative_due.add(
                        invoice.due_amount,
                    );

                if (
                    !account.last_invoice_number
                ) {
                    account.last_invoice_number =
                        invoice.invoice_number;
                }
            }

            /**
             * آخر 5 طلبات تظهر مع الحساب.
             */
            if (
                account.recent_orders.length <
                5
            ) {
                account.recent_orders.push({
                    id:
                        order.id,

                    order_number:
                        order.order_number,

                    status:
                        order.status,

                    total:
                        order.total,

                    invoice_number:
                        invoice?.invoice_number ??
                        null,

                    paid_amount:
                        invoice?.paid_amount ??
                        new Prisma.Decimal(
                            0,
                        ),

                    due_amount:
                        invoice?.due_amount ??
                        new Prisma.Decimal(
                            0,
                        ),

                    submitted_at:
                        order.submitted_at,
                });
            }

            accountsMap.set(
                accountKey,
                account,
            );
        }

        /**
         * ========================================================
         * 5. Load Customer Accounting Balances
         * ========================================================
         *
         * فقط Party Type = CUSTOMER.
         */

        const customerIds =
            [
                ...new Set(
                    Array.from(
                        accountsMap.values(),
                    )
                        .filter(
                            (
                                account,
                            ) =>
                                account.party_type ===
                                ecommerce_party_type_enum
                                    .CUSTOMER &&
                                Boolean(
                                    account.party_id,
                                ),
                        )
                        .map(
                            (
                                account,
                            ) =>
                                account.party_id!,
                        ),
                ),
            ];

        const customers =
            customerIds.length >
                0
                ? await this.prisma.customers.findMany({
                    where: {
                        id: {
                            in:
                                customerIds,
                        },
                    },

                    select: {
                        id:
                            true,

                        name:
                            true,

                        phone:
                            true,

                        address:
                            true,

                        balance:
                            true,

                        credit_limit:
                            true,

                        is_active:
                            true,
                    },
                })
                : [];

        const customerMap =
            new Map(
                customers.map(
                    (
                        customer,
                    ) => [
                            customer.id,
                            customer,
                        ],
                ),
            );

        /**
         * ========================================================
         * 6. Map Final Result
         * ========================================================
         */

        let accounts =
            Array.from(
                accountsMap.values(),
            ).map(
                (
                    account,
                ) => {
                    const customer =
                        account.party_type ===
                            ecommerce_party_type_enum
                                .CUSTOMER &&
                            account.party_id
                            ? customerMap.get(
                                account.party_id,
                            )
                            : undefined;

                    const currentBalance =
                        customer?.balance ??
                        new Prisma.Decimal(
                            0,
                        );

                    const creditLimit =
                        customer?.credit_limit ??
                        new Prisma.Decimal(
                            0,
                        );

                    /**
                     * credit_limit = 0
                     * يعني غير محدود حسب المنطق الحالي.
                     */
                    const availableCredit =
                        creditLimit.gt(
                            0,
                        )
                            ? Prisma.Decimal.max(
                                creditLimit.sub(
                                    currentBalance,
                                ),
                                new Prisma.Decimal(
                                    0,
                                ),
                            )
                            : null;

                    return {
                        account_key:
                            account.account_key,

                        party_type:
                            account.party_type,

                        party_id:
                            account.party_id,

                        party_name:
                            customer?.name ??
                            account.party_name,

                        party_phone:
                            customer?.phone ??
                            account.party_phone,

                        party_address:
                            customer?.address ??
                            account.party_address,

                        /**
                         * هل هذا الحساب مرتبط
                         * بحساب Customer محاسبي؟
                         */
                        has_customer_account:
                            Boolean(
                                customer,
                            ),

                        customer_status:
                            customer
                                ? customer.is_active
                                    ? 'ACTIVE'
                                    : 'INACTIVE'
                                : null,

                        /**
                         * Current Accounting Balance
                         *
                         * هذه ذمة الحساب الحالية
                         * في جدول customers.
                         *
                         * قد تتضمن مبيعات أخرى
                         * غير Ecommerce.
                         */
                        current_balance:
                            Number(
                                currentBalance,
                            ),

                        credit_limit:
                            Number(
                                creditLimit,
                            ),

                        available_credit:
                            availableCredit ===
                                null
                                ? null
                                : Number(
                                    availableCredit,
                                ),

                        /**
                         * فقط المبيعات التي تمت
                         * عن طريق هذا المندوب
                         * من Ecommerce.
                         */
                        representative_totals:
                        {
                            total_sales:
                                Number(
                                    account.total_sales,
                                ),

                            total_paid:
                                Number(
                                    account.total_paid,
                                ),

                            total_due:
                                Number(
                                    account.representative_due,
                                ),
                        },

                        orders: {
                            total:
                                account.orders_count,

                            submitted:
                                account.submitted_orders,

                            accepted:
                                account.accepted_orders,

                            rejected:
                                account.rejected_orders,

                            cancelled:
                                account.cancelled_orders,

                            total_orders_value:
                                Number(
                                    account.total_orders_value,
                                ),
                        },

                        last_order: {
                            order_number:
                                account.last_order_number,

                            submitted_at:
                                account.last_order_at,

                            invoice_number:
                                account.last_invoice_number,
                        },

                        recent_orders:
                            account.recent_orders.map(
                                (
                                    order,
                                ) => ({
                                    ...order,

                                    total:
                                        Number(
                                            order.total,
                                        ),

                                    paid_amount:
                                        Number(
                                            order.paid_amount,
                                        ),

                                    due_amount:
                                        Number(
                                            order.due_amount,
                                        ),
                                }),
                            ),
                    };
                },
            );

        /**
         * ========================================================
         * 7. has_balance Filter
         * ========================================================
         */

        if (
            query.has_balance !==
            undefined
        ) {
            accounts =
                accounts.filter(
                    (
                        account,
                    ) =>
                        query.has_balance
                            ? account.current_balance >
                            0 ||
                            account
                                .representative_totals
                                .total_due >
                            0
                            : account.current_balance <=
                            0 &&
                            account
                                .representative_totals
                                .total_due <=
                            0,
                );
        }

        /**
         * ========================================================
         * 8. Sort
         * ========================================================
         *
         * الأكبر ذمة أولاً،
         * ثم الأحدث.
         */

        accounts.sort(
            (
                a,
                b,
            ) => {
                const balanceCompare =
                    b.current_balance -
                    a.current_balance;

                if (
                    balanceCompare !==
                    0
                ) {
                    return balanceCompare;
                }

                const aDate =
                    a.last_order
                        .submitted_at
                        ? new Date(
                            a.last_order
                                .submitted_at,
                        ).getTime()
                        : 0;

                const bDate =
                    b.last_order
                        .submitted_at
                        ? new Date(
                            b.last_order
                                .submitted_at,
                        ).getTime()
                        : 0;

                return (
                    bDate -
                    aDate
                );
            },
        );

        /**
         * ========================================================
         * 9. Pagination
         * ========================================================
         */

        const page =
            Math.max(
                1,
                Number(
                    query.page,
                ) || 1,
            );

        const limit =
            Math.min(
                100,
                Math.max(
                    1,
                    Number(
                        query.limit,
                    ) || 20,
                ),
            );

        const total =
            accounts.length;

        const start =
            (page - 1) *
            limit;

        const data =
            accounts.slice(
                start,
                start +
                limit,
            );

        /**
         * ========================================================
         * 10. SUMMARY
         * ========================================================
         */

        const summary =
            accounts.reduce(
                (
                    result,
                    account,
                ) => {
                    result.total_sales +=
                        account
                            .representative_totals
                            .total_sales;

                    result.total_paid +=
                        account
                            .representative_totals
                            .total_paid;

                    result.total_due +=
                        account
                            .representative_totals
                            .total_due;

                    result.current_balances +=
                        account.current_balance;

                    return result;
                },

                {
                    total_sales:
                        0,

                    total_paid:
                        0,

                    total_due:
                        0,

                    current_balances:
                        0,
                },
            );

        return {
            representative: {
                id:
                    representative.id,

                name:
                    representative.name,

                office_name:
                    representative.office_name,
            },

            summary: {
                accounts_count:
                    total,

                ...summary,
            },

            data,

            meta: {
                page,

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
     * ACCOUNT KEY
     * ============================================================
     */
    private buildAccountKey(
        partyType:
            ecommerce_party_type_enum | null,

        partyId:
            string | null,

        phone:
            string | null,

        name:
            string | null,
    ): string {
        if (
            partyId
        ) {
            return `${partyType ?? 'UNKNOWN'}:${partyId}`;
        }

        /**
         * OTHER أو Party بدون ID.
         */
        const normalizedPhone =
            phone
                ?.trim()
                .toLowerCase() ??
            '';

        const normalizedName =
            name
                ?.trim()
                .toLowerCase() ??
            '';

        return `${partyType ?? 'OTHER'}:${normalizedPhone}:${normalizedName}`;
    }
}