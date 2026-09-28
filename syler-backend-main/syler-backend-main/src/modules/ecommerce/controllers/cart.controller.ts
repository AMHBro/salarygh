import {
    Body,
    Controller,
    Delete,
    Get,
    Param,
    Patch,
    Post,
    Req,
    UseGuards,
} from '@nestjs/common';

import {
    ApiBearerAuth,
    ApiHeader,
    ApiOperation,
    ApiTags,
} from '@nestjs/swagger';

import { Request } from 'express';

import { CartService } from '../services/cart.service';
import { AddCartItemDto } from '../dto/add-cart-item.dto';
import { UpdateCartItemDto } from '../dto/update-cart-item.dto';
import { OptionalJwtAuthGuard } from '../guards/optional-jwt-auth.guard';
import { Public } from '../../../common/decorators/public.decorator';

interface EcommerceRequest extends Request {
    user?: {
        id?: string;
        userId?: string;
        sub?: string;
    };
}

@ApiTags('Ecommerce — Cart (M08)')
@Public()
@Controller('store/cart')
@UseGuards(OptionalJwtAuthGuard)
@ApiBearerAuth()
export class CartController {
    constructor(
        private readonly cartService: CartService,
    ) { }

    private actor(req: EcommerceRequest) {
        return {
            userId:
                req.user?.id ??
                req.user?.userId ??
                req.user?.sub ??
                null,

            cartToken:
                req.get('x-cart-token')?.trim() ||
                null,
        };
    }

    private async resolveActor(
        req: EcommerceRequest,
    ) {
        const actor = this.actor(req);

        const cart =
            await this.cartService.getOrCreateCart(
                actor,
            );

        return {
            userId: actor.userId,
            cartToken: cart.session_token,
        };
    }

    @Get()
    @ApiOperation({
        summary: 'عرض السلة أو إنشاء سلة جديدة',
        description:
            'للزائر: أرسل x-cart-token إذا كانت لديه سلة. احتفظ بقيمة cart_token من الاستجابة لإرسالها عند Guest Checkout. لا ترسل Bearer المندوب عند اختبار سلة Guest.',
    })
    @ApiHeader({
        name: 'x-cart-token',
        required: false,
        description: 'رمز سلة الزائر',
    })
    async getCart(
        @Req() req: EcommerceRequest,
    ) {
        const actor =
            await this.resolveActor(req);

        return this.cartService.getCart(
            actor,
        );
    }

    @Post('items')
    @ApiOperation({
        summary: 'إضافة منتج إلى السلة',
    })
    @ApiHeader({
        name: 'x-cart-token',
        required: false,
        description: 'رمز سلة الزائر',
    })
    async addItem(
        @Req() req: EcommerceRequest,
        @Body() dto: AddCartItemDto,
    ) {
        const actor =
            await this.resolveActor(req);

        await this.cartService.addItem(
            actor,
            dto,
        );

        return this.cartService.getCart(
            actor,
        );
    }

    @Patch('items/:itemId')
    @ApiOperation({
        summary: 'تعديل كمية عنصر في السلة',
    })
    @ApiHeader({
        name: 'x-cart-token',
        required: false,
        description: 'رمز سلة الزائر',
    })
    async updateItem(
        @Req() req: EcommerceRequest,
        @Param('itemId') itemId: string,
        @Body() dto: UpdateCartItemDto,
    ) {
        const actor = this.actor(req);

        await this.cartService.updateItem(
            actor,
            itemId,
            dto,
        );

        return this.cartService.getCart(
            actor,
        );
    }

    @Delete('items/:itemId')
    @ApiOperation({
        summary: 'حذف عنصر من السلة',
    })
    @ApiHeader({
        name: 'x-cart-token',
        required: false,
        description: 'رمز سلة الزائر',
    })
    async removeItem(
        @Req() req: EcommerceRequest,
        @Param('itemId') itemId: string,
    ) {
        const actor = this.actor(req);

        await this.cartService.removeItem(
            actor,
            itemId,
        );

        return this.cartService.getCart(
            actor,
        );
    }

    @Delete()
    @ApiOperation({
        summary: 'تفريغ السلة بالكامل',
    })
    @ApiHeader({
        name: 'x-cart-token',
        required: false,
        description: 'رمز سلة الزائر',
    })
    async clearCart(
        @Req() req: EcommerceRequest,
    ) {
        const actor = this.actor(req);

        await this.cartService.clearCart(
            actor,
        );

        return this.cartService.getCart(
            actor,
        );
    }
}