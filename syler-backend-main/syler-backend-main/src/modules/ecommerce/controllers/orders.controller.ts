import {
    Body,
    Controller,
    Get,
    Headers,
    Param,
    Post,
    Query,
    Req,
    UnauthorizedException,
    UseGuards,
} from '@nestjs/common';

import {
    ApiBearerAuth,
    ApiHeader,
    ApiOperation,
    ApiQuery,
    ApiTags,
} from '@nestjs/swagger';

import { Request } from 'express';

import { EcommerceOrderService } from '../services/ecommerce-order.service';

import { CancelOrderDto } from '../dto/cancel-order.dto';

import { OptionalJwtAuthGuard } from '../guards/optional-jwt-auth.guard';
import { Public } from '../../../common/decorators/public.decorator';

interface EcommerceAuthenticatedRequest
    extends Request {
    user?: {
        id?: string;
        userId?: string;
        sub?: string;
    };
}

@ApiTags('Ecommerce — Orders (M08)')
@Controller('store')
export class OrdersController {
    constructor(
        private readonly orderService:
            EcommerceOrderService,
    ) { }

    /**
     * ============================================================
     * REPRESENTATIVE
     * ============================================================
     */

    @Get('orders')
    @UseGuards(OptionalJwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({
        summary:
            'عرض طلبات المندوب الحالي',
    })
    @ApiQuery({
        name: 'page',
        required: false,
        example: 1,
    })
    @ApiQuery({
        name: 'limit',
        required: false,
        example: 20,
    })
    @ApiQuery({
        name: 'status',
        required: false,
        example: 'SUBMITTED',
    })
    async getRepresentativeOrders(
        @Req()
        req: EcommerceAuthenticatedRequest,

        @Query('page')
        page?: string,

        @Query('limit')
        limit?: string,

        @Query('status')
        status?: string,
    ) {
        const userId =
            this.getUserId(
                req,
            );

        return this.orderService
            .getRepresentativeOrders(
                userId,
                {
                    page:
                        page
                            ? Number(page)
                            : 1,

                    limit:
                        limit
                            ? Number(limit)
                            : 20,

                    status,
                },
            );
    }

    @Get('orders/:id')
    @UseGuards(OptionalJwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({
        summary:
            'عرض تفاصيل طلب للمندوب الحالي',
    })
    async getRepresentativeOrder(
        @Req()
        req: EcommerceAuthenticatedRequest,

        @Param('id')
        orderId: string,
    ) {
        const userId =
            this.getUserId(
                req,
            );

        return this.orderService
            .getRepresentativeOrder(
                userId,
                orderId,
            );
    }

    @Post('orders/:id/cancel')
    @UseGuards(OptionalJwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({
        summary:
            'إلغاء طلب مندوب بحالة SUBMITTED',
    })
    async cancelRepresentativeOrder(
        @Req()
        req: EcommerceAuthenticatedRequest,

        @Param('id')
        orderId: string,

        @Body()
        dto: CancelOrderDto,
    ) {
        const userId =
            this.getUserId(
                req,
            );

        return this.orderService
            .cancelRepresentativeOrder(
                userId,
                orderId,
                dto.reason,
            );
    }

    /**
     * ============================================================
     * GUEST
     * ============================================================
     */

    @Public()
    @Get('guest/orders/:orderNumber')
    @ApiHeader({
        name: 'X-Order-Token',
        required: true,
    })
    @ApiOperation({
        summary:
            'عرض طلب Guest باستخدام Order Token',
    })
    async getGuestOrder(
        @Param('orderNumber')
        orderNumber: string,

        @Headers('x-order-token')
        orderToken: string,
    ) {
        return this.orderService
            .getGuestOrder(
                orderNumber,
                orderToken,
            );
    }

    @Public()
    @Post('guest/orders/:orderNumber/cancel')
    @ApiHeader({
        name: 'X-Order-Token',
        required: true,
    })
    @ApiOperation({
        summary:
            'إلغاء طلب Guest بحالة SUBMITTED',
    })
    async cancelGuestOrder(
        @Param('orderNumber')
        orderNumber: string,

        @Headers('x-order-token')
        orderToken: string,

        @Body()
        dto: CancelOrderDto,
    ) {
        return this.orderService
            .cancelGuestOrder(
                orderNumber,
                orderToken,
                dto.reason,
            );
    }

    /**
     * ============================================================
     * HELPER
     * ============================================================
     */

    private getUserId(
        req: EcommerceAuthenticatedRequest,
    ): string {
        const userId =
            req.user?.id ??
            req.user?.userId ??
            req.user?.sub;

        if (!userId) {
            throw new UnauthorizedException({
                code:
                    'ECOMMERCE_REP_AUTH_REQUIRED',

                message:
                    'تسجيل دخول المندوب مطلوب',
            });
        }

        return userId;
    }
}