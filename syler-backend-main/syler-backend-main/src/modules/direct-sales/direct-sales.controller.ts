import { Controller, Get, Post, Param, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { DirectSalesService } from './direct-sales.service';
import { CreateDirectSaleDto } from './dto/create-direct-sale.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Permissions } from '../../common/decorators/permissions.decorator';
import { price_type_enum } from '@prisma/client';

@ApiTags('Direct Sales & POS (M06)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('direct-sales')
export class DirectSalesController {
  constructor(private readonly directSalesService: DirectSalesService) {}

  @Get('products')
  @ApiOperation({ summary: 'كتالوج المنتجات لشاشة الـ POS مع الكميات المتوفرة وأسعار المفرد/الجملة' })
  @ApiQuery({ name: 'warehouse_id', required: false, description: 'المخزن المختار' })
  @ApiQuery({ name: 'price_type', required: false, enum: price_type_enum, description: 'مستوى السعر' })
  @ApiQuery({ name: 'search', required: false, description: 'بحث بالاسم أو الباركود' })
  async getPosProducts(@Query() query: any) {
    const data = await this.directSalesService.getPosProducts(query);
    return { success: true, data };
  }

  @Post()
  @Permissions('INVOICE_EDIT')
  @ApiOperation({ summary: 'إنهاء وتأكيد عملية البيع المباشر (خصم المخزون + الدفع + تحديث الذمة)' })
  async createDirectSale(@Body() dto: CreateDirectSaleDto, @Request() req: any) {
    const data = await this.directSalesService.createDirectSale(dto, req.user?.id);
    return { success: true, data, message: 'تمت عملية البيع بنجاح' };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة فواتير المبيعات مع الفلاتر' })
  @ApiQuery({ name: 'customer_id', required: false })
  @ApiQuery({ name: 'warehouse_id', required: false })
  @ApiQuery({ name: 'payment_type', required: false })
  @ApiQuery({ name: 'search', required: false })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAll(@Query() query: any) {
    return this.directSalesService.findAll(query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'تفاصيل فاتورة مبيعات مع المواد للطباعة' })
  async findOne(@Param('id') id: string) {
    const data = await this.directSalesService.findOne(id);
    return { success: true, data };
  }
}
