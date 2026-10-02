import {
    Controller,
    Get,
    Param,
    Query,
    Req,
    UnauthorizedException,
    UseGuards,
} from '@nestjs/common';

import {
    ApiBearerAuth,
    ApiOkResponse,
    ApiOperation,
    ApiQuery,
    ApiTags,
    ApiUnauthorizedResponse,
} from '@nestjs/swagger';

import {
    ecommerce_party_type_enum,
} from '@prisma/client';

import {
    JwtAuthGuard,
} from '../../auth/guards/jwt-auth.guard';

import {
    RepresentativeAccountsService,
} from '../services/representative-accounts.service';

import {
    RepresentativeLedgerService,
} from '../services/representative-ledger.service';

@ApiTags(
    'M08 - Representative Accounts',
)
@ApiBearerAuth()
@UseGuards(
    JwtAuthGuard,
)
@Controller(
    'store/representative/accounts',
)
export class RepresentativeAccountsController {
    constructor(
        private readonly representativeAccountsService:
            RepresentativeAccountsService,
        private readonly ledger: RepresentativeLedgerService,
    ) { }

    /**
     * ============================================================
     * REPRESENTATIVE ACCOUNTS
     * ============================================================
     */
    @Get()
    @ApiOperation({
        summary:
            'عرض الحسابات والمكاتب التي تعامل معها المندوب',

        description: `
يعرض جميع الجهات التي سبق أن استخدمها المندوب في طلبات Ecommerce.

لكل حساب يتم عرض:

- بيانات الجهة
- عدد الطلبات
- الطلبات المقبولة
- الطلبات المعلقة
- الطلبات المرفوضة
- الطلبات الملغاة
- إجمالي المبيعات المرحّلة
- إجمالي المبالغ المدفوعة
- الذمة الناتجة من مبيعات هذا المندوب

إذا كانت الجهة CUSTOMER يتم كذلك عرض:

- الرصيد المحاسبي الحالي
- الحد الائتماني
- المتبقي من الحد الائتماني

المندوب يرى حساباته فقط.
        `,
    })
    @ApiQuery({
        name:
            'search',

        required:
            false,

        type:
            String,

        description:
            'بحث باسم الحساب أو الهاتف أو العنوان',

        example:
            'مكتب النور',
    })
    @ApiQuery({
        name:
            'party_type',

        required:
            false,

        enum:
            ecommerce_party_type_enum,

        description:
            'فلترة حسب نوع الجهة',
    })
    @ApiQuery({
        name:
            'has_balance',

        required:
            false,

        type:
            Boolean,

        description:
            'true لعرض الحسابات التي عليها ذمة فقط',

        example:
            true,
    })
    @ApiQuery({
        name:
            'page',

        required:
            false,

        type:
            Number,

        example:
            1,
    })
    @ApiQuery({
        name:
            'limit',

        required:
            false,

        type:
            Number,

        example:
            20,
    })
    @ApiOkResponse({
        description:
            'تم جلب حسابات المندوب بنجاح',

        schema: {
            example: {
                representative: {
                    id:
                        'uuid',

                    name:
                        'أحمد محمد',

                    office_name:
                        'مكتب أحمد',
                },

                summary: {
                    accounts_count:
                        5,

                    total_sales:
                        2500000,

                    total_paid:
                        1800000,

                    total_due:
                        700000,

                    current_balances:
                        700000,
                },

                data: [
                    {
                        account_key:
                            'CUSTOMER:uuid',

                        party_type:
                            'CUSTOMER',

                        party_id:
                            'uuid',

                        party_name:
                            'مكتب النور',

                        party_phone:
                            '07701234567',

                        party_address:
                            'بغداد',

                        has_customer_account:
                            true,

                        customer_status:
                            'ACTIVE',

                        current_balance:
                            350000,

                        credit_limit:
                            1000000,

                        available_credit:
                            650000,

                        representative_totals: {
                            total_sales:
                                1250000,

                            total_paid:
                                900000,

                            total_due:
                                350000,
                        },

                        orders: {
                            total:
                                8,

                            submitted:
                                1,

                            accepted:
                                6,

                            rejected:
                                1,

                            cancelled:
                                0,

                            total_orders_value:
                                1450000,
                        },

                        last_order: {
                            order_number:
                                'ECO-20260924-A81F932B',

                            submitted_at:
                                '2026-09-24T18:00:00.000Z',

                            invoice_number:
                                'INV-202609-91F7A2C8',
                        },
                    },
                ],

                meta: {
                    page:
                        1,

                    limit:
                        20,

                    total:
                        5,

                    total_pages:
                        1,
                },
            },
        },
    })
    @ApiUnauthorizedResponse({
        description:
            'تسجيل الدخول مطلوب',
    })
    async getAccounts(
        @Req()
        req: any,

        @Query('search')
        search?: string,

        @Query('party_type')
        partyType?:
            ecommerce_party_type_enum,

        @Query('has_balance')
        hasBalance?: string,

        @Query('page')
        page?: string,

        @Query('limit')
        limit?: string,
    ) {
        const userId =
            req.user?.id ??
            req.user?.userId ??
            req.user?.sub;

        if (
            !userId
        ) {
            throw new UnauthorizedException({
                code:
                    'AUTH_REQUIRED',

                message:
                    'تسجيل الدخول مطلوب',
            });
        }

        return this.representativeAccountsService.getAccounts(
            userId,

            {
                search,

                party_type:
                    partyType,

                has_balance:
                    hasBalance ===
                        undefined
                        ? undefined
                        : hasBalance ===
                        'true',

                page:
                    page
                        ? Number(
                            page,
                        )
                        : 1,

                limit:
                    limit
                        ? Number(
                            limit,
                        )
                        : 20,
            },
        );
    }

    @Get(':id/ledger')
    @ApiOperation({
        summary: 'كشف فواتير الذمة وأعمارها لحساب المندوب',
    })
    ledgerForAccount(
        @Req() req: any,
        @Param('id') partyId: string,
    ) {
        const userId = req.user?.id ?? req.user?.userId ?? req.user?.sub;
        if (!userId) {
            throw new UnauthorizedException({
                code: 'AUTH_REQUIRED',
                message: 'تسجيل الدخول مطلوب',
            });
        }
        return this.ledger.getLedger(userId, partyId);
    }
}