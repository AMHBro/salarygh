import { Controller, Get, Post, Param, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { PurchasesService } from './purchases.service';
import { CreatePurchaseInvoiceDto } from './dto/create-purchase.dto';
import { QuickAddProductDto } from './dto/quick-add-item.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Permissions } from '../../common/decorators/permissions.decorator';

@ApiTags('Purchases (M04)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('purchases')
export class PurchasesController {
    constructor(private readonly purchasesService: PurchasesService) { }

    @Post()
    @Permissions('PURCHASE_EDIT')
    @ApiOperation({ summary: 'إنشاء فاتورة شراء مباشرة وترحيلها للمخزن والذمم فوراً' })
    async createDirect(@Body() dto: CreatePurchaseInvoiceDto, @Request() req: any) {
        const data = await this.purchasesService.createDirectInvoice(dto, req.user?.id);
        return { success: true, data, message: 'تم حفظ فاتورة الشراء وترحيل المواد إلى المخزن بنجاح' };
    }

    @Post('quick-product')
    @Permissions('PRODUCT_EDIT')
    @ApiOperation({ summary: 'الإضافة السريعة لمادة جديدة من نافذة الفاتورة المنبثقة' })
    async quickAddProduct(@Body() dto: QuickAddProductDto, @Request() req: any) {
        const data = await this.purchasesService.quickAddProduct(dto, req.user?.id);
        return { success: true, data, message: 'تم إنشاء المادة بنجاح وإضافتها للفاتورة' };
    }

    @Get()
    @ApiOperation({ summary: 'قائمة فواتير الشراء مع الفلاتر' })
    @ApiQuery({ name: 'supplier_id', required: false })
    @ApiQuery({ name: 'warehouse_id', required: false })
    @ApiQuery({ name: 'payment_type', required: false })
    @ApiQuery({ name: 'search', required: false })
    @ApiQuery({ name: 'page', required: false, example: 1 })
    @ApiQuery({ name: 'limit', required: false, example: 20 })
    async findAll(@Query() query: any) {
        return this.purchasesService.findAll(query);
    }

    @Get(':id')
    @ApiOperation({ summary: 'تفاصيل فاتورة شراء مع كافة المواد' })
    async findOne(@Param('id') id: string) {
        const data = await this.purchasesService.findOne(id);
        return { success: true, data };
    }
}
