import {
    Body,
    Controller,
    Post,
    Req,
    UnauthorizedException,
    UseGuards,
} from '@nestjs/common';

import {
    ApiBearerAuth,
    ApiHeader,
    ApiOperation,
    ApiTags,
} from '@nestjs/swagger';

import { Request } from 'express';

import { CheckoutService } from '../services/checkout.service';
import { GuestCheckoutDto } from '../dto/guest-checkout.dto';
import { RepresentativeCheckoutDto } from '../dto/representative-checkout.dto';
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

@ApiTags('Ecommerce — Checkout (M08)')
@Controller('store/checkout')
export class CheckoutController {
    constructor(
        private readonly checkoutService:
            CheckoutService,
    ) { }

    @Public()
    @Post('guest')
    @ApiOperation({
        summary: 'إرسال طلب شراء كزائر',
        description:
            'أرسل قيمة cart_token المُعادة من GET /store/cart في الهيدر x-cart-token. يجب أن تكون السلة من نوع GUEST وبها مواد.',
    })
    @ApiHeader({
        name: 'x-cart-token',
        required: true,
        description:
            'قيمة cart_token المُعادة من GET /store/cart',
    })
    @ApiHeader({
        name: 'x-idempotency-key',
        required: false,
        description:
            'مفتاح ثابت لمنع تكرار الطلب عند إعادة المحاولة',
    })
    async guestCheckout(
        @Req() req: EcommerceAuthenticatedRequest,
        @Body() dto: GuestCheckoutDto,
    ) {
        const cartToken =
            req.get('x-cart-token')?.trim() ??
            '';

        const idempotencyKey =
            req.get('x-idempotency-key')?.trim();

        return this.checkoutService
            .guestCheckout(
                cartToken,
                dto,
                idempotencyKey,
            );
    }

    @Post('representative')
    @UseGuards(OptionalJwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({
        summary:
            'إرسال طلب Ecommerce بواسطة المندوب',
    })
    @ApiHeader({
        name: 'x-idempotency-key',
        required: false,
        description:
            'مفتاح ثابت لمنع تكرار الطلب عند إعادة المحاولة',
    })
    async representativeCheckout(
        @Req() req: EcommerceAuthenticatedRequest,
        @Body() dto: RepresentativeCheckoutDto,
    ) {
        const userId =
            req.user?.id ??
            req.user?.userId ??
            req.user?.sub;

        if (!userId) {
            throw new UnauthorizedException({
                code: 'ECOMMERCE_REP_AUTH_REQUIRED',
                message:
                    'تسجيل دخول المندوب مطلوب',
            });
        }

        const idempotencyKey =
            req.get('x-idempotency-key')?.trim();

        return this.checkoutService
            .representativeCheckout(
                userId,
                dto,
                idempotencyKey,
            );
    }
}