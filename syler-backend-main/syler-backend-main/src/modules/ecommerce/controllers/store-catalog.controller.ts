import {
    Controller,
    Get,
    Param,
    Query,
    Req,
    UseGuards,
} from '@nestjs/common';

import {
    ApiBearerAuth,
    ApiOperation,
    ApiTags,
} from '@nestjs/swagger';

import { Request } from 'express';

import { CatalogQueryDto } from '../dto/catalog-query.dto';

import { EcommerceCatalogService } from '../services/ecommerce-catalog.service';

import { OptionalJwtAuthGuard } from '../guards/optional-jwt-auth.guard';
import { Public } from '../../../common/decorators/public.decorator';

interface AuthenticatedRequest extends Request {
    user?: {
        id?: string;
        userId?: string;
        sub?: string;
    };
}

@ApiTags('Ecommerce — Store Catalog (M08)')
@Public()
@Controller('store')
export class StoreCatalogController {
    constructor(
        private readonly catalogService:
            EcommerceCatalogService,
    ) { }

    @Get('products')
    @UseGuards(OptionalJwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({
        summary:
            'عرض منتجات المتجر بالسعر المناسب للضيف أو المندوب',
    })
    async getProducts(
        @Query() query: CatalogQueryDto,
        @Req() req: AuthenticatedRequest,
    ) {
        /**
         * عدل هذا حسب شكل JWT Payload الفعلي عندك.
         */
        const userId =
            req.user?.id ??
            req.user?.userId ??
            req.user?.sub ??
            null;

        return this.catalogService.getProducts(
            query,
            userId,
        );
    }
    @Get('warehouse')
    @ApiOperation({
        summary: 'عوائل المواد ومنتجات المخزن للزبون أو المندوب',
    })
    async getWarehouse(
        @Query('audience') audience?: string,
        @Query('page') page?: string,
        @Query('limit') limit?: string,
        @Query('search') search?: string,
        @Query('category_id') categoryId?: string,
    ) {
        return this.catalogService.getWarehouse(audience, page, limit, search, categoryId);
    }

    @Get('categories')
    @ApiOperation({
        summary: 'عرض تصنيفات المنتجات المتاحة في المتجر',
    })
    async getCategories() {
        return this.catalogService.getCategories();
    }

    @Get('products/:variantId')
    @UseGuards(OptionalJwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({
        summary: 'تفاصيل منتج في المتجر',
    })
    async getProduct(
        @Param('variantId') variantId: string,
        @Req() req: AuthenticatedRequest,
    ) {
        const userId =
            req.user?.id ??
            req.user?.userId ??
            req.user?.sub ??
            null;

        return this.catalogService.getProduct(
            variantId,
            userId,
        );
    }
}