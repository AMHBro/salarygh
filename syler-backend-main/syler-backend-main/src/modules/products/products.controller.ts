import {
    Controller,
    Get,
    Post,
    Patch,
    Param,
    Body,
    Query,
    UseGuards,
    Request,
} from '@nestjs/common';
import {
    ApiTags,
    ApiOperation,
    ApiBearerAuth,
    ApiQuery,
} from '@nestjs/swagger';
import { ProductsService } from './products.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Permissions } from '../../common/decorators/permissions.decorator';

@ApiTags('Products (M03)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('products')
export class ProductsController {
    constructor(private readonly productsService: ProductsService) { }

    // ─── لوحة التحكم (4 بطاقات إحصائية) ─────────────────────────────────────
    @Get('dashboard/stats')
    @ApiOperation({ summary: 'إحصائيات المنتجات (إجمالي، متوفر، منخفض، نافد)' })
    @ApiQuery({ name: 'warehouse_id', required: false })
    async getDashboardStats(@Query('warehouse_id') warehouse_id?: string) {
        const data = await this.productsService.getDashboardStats(warehouse_id);
        return { success: true, data };
    }

    // ─── البحث بالباركود (للكاشير وشاشات البيع) ──────────────────────────────
    @Get('barcode/:barcode')
    @ApiOperation({ summary: 'البحث السريع عن منتج بالباركود (للكاشير/POS)' })
    async findByBarcode(@Param('barcode') barcode: string) {
        const data = await this.productsService.findByBarcode(barcode);
        return { success: true, data };
    }

    // ─── قائمة المنتجات مع الفلاتر والـ Pagination ───────────────────────────
    @Get()
    @ApiOperation({ summary: 'قائمة المنتجات مع فلترة وبحث وصفحات' })
    @ApiQuery({ name: 'search', required: false, description: 'بحث بالاسم أو الباركود' })
    @ApiQuery({ name: 'category_id', required: false })
    @ApiQuery({ name: 'warehouse_id', required: false })
    @ApiQuery({ name: 'is_active', required: false, enum: ['true', 'false', 'all'] })
    @ApiQuery({ name: 'page', required: false, example: 1 })
    @ApiQuery({ name: 'limit', required: false, example: 20 })
    async findAll(@Query() query: any) {
        return this.productsService.findAll(query);
    }

    // ─── تفاصيل منتج واحد ────────────────────────────────────────────────────
    @Get(':id')
    @ApiOperation({ summary: 'تفاصيل منتج مع جميع أشكاله وأسعاره وأرصدة مخازنه' })
    async findOne(@Param('id') id: string) {
        const data = await this.productsService.findOne(id);
        return { success: true, data };
    }

    // ─── إنشاء منتج جديد ─────────────────────────────────────────────────────
    @Post()
    @Permissions('PRODUCT_EDIT')
    @ApiOperation({ summary: 'إنشاء منتج جديد (بسيط أو متعدد الأشكال) مع الأسعار' })
    async create(@Body() dto: CreateProductDto, @Request() req: any) {
        const data = await this.productsService.create(dto, req.user?.id);
        return { success: true, data, message: 'تم إنشاء المنتج بنجاح' };
    }

    // ─── تحديث بيانات المنتج ─────────────────────────────────────────────────
    @Patch(':id')
    @Permissions('PRODUCT_EDIT')
    @ApiOperation({ summary: 'تحديث البيانات الأساسية للمنتج' })
    async update(@Param('id') id: string, @Body() dto: UpdateProductDto) {
        const data = await this.productsService.update(id, dto);
        return { success: true, data, message: 'تم تحديث المنتج بنجاح' };
    }

    // ─── تعطيل/تفعيل المنتج (Toggle) ─────────────────────────────────────────
    @Patch(':id/toggle-active')
    @Permissions('PRODUCT_EDIT')
    @ApiOperation({ summary: 'تعطيل أو تفعيل المنتج (Soft Delete)' })
    async toggleActive(@Param('id') id: string) {
        const data = await this.productsService.toggleActive(id);
        const message = data.is_active ? 'تم تفعيل المنتج بنجاح' : 'تم تعطيل المنتج بنجاح';
        return { success: true, data, message };
    }
}
