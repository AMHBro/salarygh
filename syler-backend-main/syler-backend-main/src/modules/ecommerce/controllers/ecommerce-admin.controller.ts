import {
    Body,
    Controller,
    Get,
    Param,
    Patch,
    Post,
    Put,
    Query,
    Req,
    UnauthorizedException,
    UseGuards,
} from '@nestjs/common';

import {
    ApiBadRequestResponse,
    ApiBearerAuth,
    ApiConflictResponse,
    ApiNotFoundResponse,
    ApiOkResponse,
    ApiOperation,
    ApiParam,
    ApiQuery,
    ApiTags,
    ApiUnauthorizedResponse,
} from '@nestjs/swagger';

import {
    ecommerce_order_source_enum,
} from '@prisma/client';

import {
    JwtAuthGuard,
} from '../../auth/guards/jwt-auth.guard';

import { Roles } from '../../../common/decorators/roles.decorator';

import {
    EcommerceProductService,
} from '../services/ecommerce-product.service';

import {
    OrderApprovalService,
} from '../services/order-approval.service';

import {
    UpdateEcommerceProductSettingDto,
} from '../dto/update-ecommerce-product-setting.dto';

import {
    RejectOrderDto,
} from '../dto/reject-order.dto';

import {
    AcceptOrderDto,
} from '../dto/accept-order.dto';

@ApiTags('M08 - Ecommerce Central Admin')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Roles('ADMIN', 'MANAGER')
@Controller('admin/ecommerce')
export class EcommerceAdminController {
    constructor(
        private readonly ecommerceProductService:
            EcommerceProductService,

        private readonly orderApprovalService:
            OrderApprovalService,
    ) { }

    /**
     * ============================================================
     * PRODUCT SETTINGS
     * ============================================================
     */

    @Get('products/settings')
    @ApiOperation({
        summary:
            'عرض إعدادات منتجات المتجر الإلكتروني',

        description:
            'يعرض إعدادات المنتجات المفعلة أو غير المفعلة في المتجر مع دعم البحث والفلترة.',
    })
    @ApiQuery({
        name:
            'enabled',

        required:
            false,

        type:
            Boolean,

        description:
            'فلترة المنتجات حسب حالة التفعيل في المتجر',

        example:
            true,
    })
    @ApiQuery({
        name:
            'search',

        required:
            false,

        type:
            String,

        description:
            'بحث باسم المنتج أو SKU أو Barcode',

        example:
            'Pepsi',
    })
    @ApiOkResponse({
        description:
            'تم جلب إعدادات المنتجات بنجاح',
    })
    @ApiUnauthorizedResponse({
        description:
            'المستخدم غير مسجل الدخول',
    })
    async listSettings(
        @Query('enabled')
        enabled?: string,

        @Query('search')
        search?: string,
    ) {
        return this.ecommerceProductService.listSettings({
            enabled:
                enabled === undefined
                    ? undefined
                    : enabled === 'true',

            search,
        });
    }

    /**
     * ============================================================
     * GET PRODUCT SETTING
     * ============================================================
     */

    @Get(
        'products/:variantId/settings/:unitId',
    )
    @ApiOperation({
        summary:
            'عرض إعداد منتج محدد في المتجر',

        description:
            'يعرض إعداد Ecommerce لمنتج Variant ووحدة قياس محددة.',
    })
    @ApiParam({
        name:
            'variantId',

        description:
            'معرف Product Variant',

        example:
            '00000000-0000-0000-0000-000000000000',
    })
    @ApiParam({
        name:
            'unitId',

        description:
            'معرف وحدة القياس',

        example:
            '00000000-0000-0000-0000-000000000000',
    })
    @ApiOkResponse({
        description:
            'تم جلب إعداد المنتج بنجاح',
    })
    @ApiNotFoundResponse({
        description:
            'إعداد المنتج غير موجود',
    })
    async getSetting(
        @Param('variantId')
        variantId: string,

        @Param('unitId')
        unitId: string,
    ) {
        return this.ecommerceProductService.getSetting(
            variantId,
            unitId,
        );
    }

    /**
     * ============================================================
     * UPSERT PRODUCT SETTING
     * ============================================================
     */

    @Put(
        'products/:variantId/settings',
    )
    @ApiOperation({
        summary:
            'إضافة أو تحديث إعداد منتج للمتجر',

        description:
            'ينشئ أو يحدث إعداد Ecommerce لمنتج معين، بما في ذلك التفعيل والعمولة وترتيب العرض.',
    })
    @ApiParam({
        name:
            'variantId',

        description:
            'معرف Product Variant',

        example:
            '00000000-0000-0000-0000-000000000000',
    })
    @ApiOkResponse({
        description:
            'تم حفظ إعداد المنتج بنجاح',
    })
    @ApiBadRequestResponse({
        description:
            'بيانات إعداد المنتج غير صالحة',
    })
    @ApiNotFoundResponse({
        description:
            'المنتج أو الوحدة غير موجودة',
    })
    async upsertSetting(
        @Param('variantId')
        variantId: string,

        @Body()
        dto:
            UpdateEcommerceProductSettingDto,
    ) {
        return this.ecommerceProductService.upsertSetting(
            variantId,
            dto,
        );
    }

    /**
     * ============================================================
     * ENABLE PRODUCT
     * ============================================================
     */

    @Patch(
        'products/:variantId/settings/:unitId/enable',
    )
    @ApiOperation({
        summary:
            'تفعيل المنتج في المتجر الإلكتروني',
    })
    @ApiParam({
        name:
            'variantId',

        description:
            'معرف Product Variant',
    })
    @ApiParam({
        name:
            'unitId',

        description:
            'معرف وحدة القياس',
    })
    @ApiOkResponse({
        description:
            'تم تفعيل المنتج بنجاح',
    })
    @ApiNotFoundResponse({
        description:
            'إعداد المنتج غير موجود',
    })
    async enable(
        @Param('variantId')
        variantId: string,

        @Param('unitId')
        unitId: string,
    ) {
        return this.ecommerceProductService.enable(
            variantId,
            unitId,
        );
    }

    /**
     * ============================================================
     * DISABLE PRODUCT
     * ============================================================
     */

    @Patch(
        'products/:variantId/settings/:unitId/disable',
    )
    @ApiOperation({
        summary:
            'تعطيل المنتج من المتجر الإلكتروني',
    })
    @ApiParam({
        name:
            'variantId',

        description:
            'معرف Product Variant',
    })
    @ApiParam({
        name:
            'unitId',

        description:
            'معرف وحدة القياس',
    })
    @ApiOkResponse({
        description:
            'تم تعطيل المنتج بنجاح',
    })
    @ApiNotFoundResponse({
        description:
            'إعداد المنتج غير موجود',
    })
    async disable(
        @Param('variantId')
        variantId: string,

        @Param('unitId')
        unitId: string,
    ) {
        return this.ecommerceProductService.disable(
            variantId,
            unitId,
        );
    }

    /**
     * ============================================================
     * ORDERS LIST
     * ============================================================
     */

    @Get('orders')
    @ApiOperation({
        summary:
            'عرض طلبات المتجر للمكتب المركزي',

        description:
            'يعرض طلبات Ecommerce مع Pagination وفلترة حسب الحالة والمصدر والبحث.',
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
    @ApiQuery({
        name:
            'status',

        required:
            false,

        type:
            String,

        description:
            'حالة الطلب',

        example:
            'SUBMITTED',
    })
    @ApiQuery({
        name:
            'source',

        required:
            false,

        enum:
            ecommerce_order_source_enum,

        description:
            'مصدر الطلب',

        example:
            ecommerce_order_source_enum.GUEST,
    })
    @ApiQuery({
        name:
            'search',

        required:
            false,

        type:
            String,

        description:
            'بحث برقم الطلب أو اسم/هاتف الزبون أو Party',
    })
    @ApiOkResponse({
        description:
            'تم جلب الطلبات بنجاح',

        schema: {
            example: {
                data: [
                    {
                        id:
                            '00000000-0000-0000-0000-000000000000',

                        order_number:
                            'ECO-20260924-A81F932B',

                        source:
                            'GUEST',

                        status:
                            'SUBMITTED',

                        payment_type:
                            'CASH',

                        subtotal:
                            '150000',

                        discount_amount:
                            '0',

                        total:
                            '150000',

                        submitted_at:
                            '2026-09-24T17:00:00.000Z',
                    },
                ],

                meta: {
                    page:
                        1,

                    per_page:
                        20,

                    total:
                        1,

                    total_pages:
                        1,
                },
            },
        },
    })
    async getOrders(
        @Query('page')
        page?: string,

        @Query('limit')
        limit?: string,

        @Query('status')
        status?: string,

        @Query('source')
        source?:
            ecommerce_order_source_enum,

        @Query('search')
        search?: string,
    ) {
        return this.orderApprovalService.getOrders({
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

            status,

            source,

            search,
        });
    }

    /**
     * ============================================================
     * ORDER DETAILS
     * ============================================================
     */

    @Get('orders/:id')
    @ApiOperation({
        summary:
            'عرض تفاصيل طلب Ecommerce',

        description:
            'يعرض بيانات الطلب كاملة، المواد، المندوب، Party، بيانات Guest، حالة الموافقة والفاتورة المرتبطة إن وجدت.',
    })
    @ApiParam({
        name:
            'id',

        description:
            'معرف طلب Ecommerce',

        example:
            '00000000-0000-0000-0000-000000000000',
    })
    @ApiOkResponse({
        description:
            'تم جلب تفاصيل الطلب بنجاح',
    })
    @ApiNotFoundResponse({
        description:
            'الطلب غير موجود',
    })
    async getOrder(
        @Param('id')
        orderId: string,
    ) {
        return this.orderApprovalService.getOrder(
            orderId,
        );
    }

    /**
     * ============================================================
     * REJECT ORDER
     * ============================================================
     */

    @Post(
        'orders/:id/reject',
    )
    @ApiOperation({
        summary:
            'رفض طلب Ecommerce',

        description:
            'يرفض الطلب إذا كان ما يزال في حالة SUBMITTED ولم يتم إنشاء فاتورة مبيعات له.',
    })
    @ApiParam({
        name:
            'id',

        description:
            'معرف طلب Ecommerce',

        example:
            '00000000-0000-0000-0000-000000000000',
    })
    @ApiOkResponse({
        description:
            'تم رفض الطلب بنجاح',

        schema: {
            example: {
                data: {
                    id:
                        '00000000-0000-0000-0000-000000000000',

                    order_number:
                        'ECO-20260924-A81F932B',

                    status:
                        'REJECTED',

                    rejection_reason:
                        'الكمية المطلوبة غير متوفرة',
                },
            },
        },
    })
    @ApiBadRequestResponse({
        description:
            'سبب الرفض غير موجود أو حالة الطلب لا تسمح بالرفض',
    })
    @ApiNotFoundResponse({
        description:
            'الطلب غير موجود',
    })
    @ApiConflictResponse({
        description:
            'تم تغيير حالة الطلب بواسطة عملية أخرى',
    })
    async rejectOrder(
        @Req()
        req: any,

        @Param('id')
        orderId: string,

        @Body()
        dto:
            RejectOrderDto,
    ) {
        const userId =
            this.getUserId(
                req,
            );

        return this.orderApprovalService.rejectOrder(
            orderId,
            userId,
            dto.reason,
        );
    }

    /**
     * ============================================================
     * ACCEPT ORDER
     * ============================================================
     */

    @Post(
        'orders/:id/accept',
    )
    @ApiOperation({
        summary:
            'قبول طلب Ecommerce وتحويله إلى فاتورة مبيعات',

        description:
            `
يقوم المكتب المركزي بتنفيذ العملية التالية بشكل ذري:

1. التحقق من أن الطلب ما يزال SUBMITTED.
2. التحقق من المخزن.
3. تحديد Customer عند الحاجة.
4. تحديد RETAIL أو REP حسب مصدر الطلب.
5. التحقق من الوحدات والكميات.
6. تحويل الكمية إلى Base Unit.
7. التحقق من المخزون.
8. التحقق من Credit Limit عند البيع الآجل أو الجزئي.
9. إنشاء sales_invoice.
10. إنشاء sales_invoice_items.
11. خصم المخزون.
12. تسجيل inventory_movements.
13. تحديث ذمة الزبون عند وجود مبلغ متبقي.
14. تحديث Ecommerce Order إلى ACCEPTED وربطه بالفاتورة.

في حالة PARTIAL يجب إرسال paid_amount.
            `,
    })
    @ApiParam({
        name:
            'id',

        description:
            'معرف طلب Ecommerce',

        example:
            '00000000-0000-0000-0000-000000000000',
    })
    @ApiOkResponse({
        description:
            'تم قبول الطلب وإنشاء فاتورة المبيعات بنجاح',

        schema: {
            example: {
                data: {
                    order_id:
                        '00000000-0000-0000-0000-000000000000',

                    order_number:
                        'ECO-20260924-A81F932B',

                    status:
                        'ACCEPTED',

                    sales_invoice_id:
                        '00000000-0000-0000-0000-000000000000',

                    invoice_number:
                        'INV-202609-91F7A2C8',

                    warehouse_id:
                        '00000000-0000-0000-0000-000000000000',

                    source:
                        'REPRESENTATIVE',

                    rep_id:
                        '00000000-0000-0000-0000-000000000000',

                    customer_id:
                        '00000000-0000-0000-0000-000000000000',

                    payment_type:
                        'CASH',

                    total:
                        150000,

                    paid_amount:
                        150000,

                    due_amount:
                        0,

                    accepted_at:
                        '2026-09-24T17:00:00.000Z',
                },

                message:
                    'تم قبول الطلب وإنشاء فاتورة المبيعات بنجاح',
            },
        },
    })
    @ApiBadRequestResponse({
        description:
            'الطلب لا يمكن قبوله أو المخزن غير فعال أو المخزون غير كافٍ أو بيانات الدفع غير صحيحة أو تم تجاوز الحد الائتماني',
    })
    @ApiNotFoundResponse({
        description:
            'الطلب أو المخزن أو الزبون أو المنتج غير موجود',
    })
    @ApiConflictResponse({
        description:
            'تمت معالجة الطلب مسبقًا أو حدث تعارض أثناء إنشاء الفاتورة أو قبول الطلب',
    })
    @ApiUnauthorizedResponse({
        description:
            'المستخدم غير مسجل الدخول',
    })
    async acceptOrder(
        @Req()
        req: any,

        @Param('id')
        orderId: string,

        @Body()
        dto:
            AcceptOrderDto,
    ) {
        const userId =
            this.getUserId(
                req,
            );

        return this.orderApprovalService.acceptOrder(
            orderId,
            userId,
            dto.warehouse_id,
            dto.paid_amount,
        );
    }

    /**
     * ============================================================
     * CURRENT USER ID
     * ============================================================
     */
    private getUserId(
        req: any,
    ): string {
        const userId =
            req.user?.id ??
            req.user?.userId ??
            req.user?.sub;

        if (!userId) {
            throw new UnauthorizedException({
                code:
                    'AUTH_REQUIRED',

                message:
                    'تسجيل الدخول مطلوب',
            });
        }

        return userId;
    }
}