import { Controller, Get, Post, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { InventoryService } from './inventory.service';
import { CreateInventoryMovementDto } from './dto/create-inventory-movement.dto';
import { TransferStockDto } from './dto/transfer-stock.dto';
import { GetInventoryBalancesDto } from './dto/get-inventory-balances.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Permissions } from '../../common/decorators/permissions.decorator';

@ApiTags('Inventory & Movements (M05)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('inventory')
export class InventoryController {
  constructor(private readonly inventoryService: InventoryService) {}

  @Get('dashboard')
  @ApiOperation({ summary: 'لوحة المخازن (البطاقات الإحصائية الأربعة + ملخص كل مخزن)' })
  async getDashboardStats() {
    const data = await this.inventoryService.getDashboardStats();
    return { success: true, data };
  }

  @Post('movements')
  @Permissions('STOCK_EDIT')
  @ApiOperation({ summary: 'إجراء حركة مخزون يدوية (+ حركة مخزون: إدخال أو إخراج أو تسوية)' })
  async createManualMovement(@Body() dto: CreateInventoryMovementDto, @Request() req: any) {
    const data = await this.inventoryService.createManualMovement(dto, req.user?.id);
    return { success: true, data, message: 'تم حفظ حركة المخزون وتحديث الأرصدة بنجاح' };
  }

  @Post('transfer')
  @Permissions('STOCK_EDIT')
  @ApiOperation({ summary: 'تحويل بضاعة بين مخزنين ذرياً (⇄ تحويل بين المخازن)' })
  async transferStock(@Body() dto: TransferStockDto, @Request() req: any) {
    const data = await this.inventoryService.transferStock(dto, req.user?.id);
    return { success: true, data, message: 'تم تحويل البضاعة بين المخازن بنجاح' };
  }

  @Get('movements')
  @ApiOperation({ summary: 'جدول سجل حركات المخزون مع الفلاتر والبحث والصفحات' })
  @ApiQuery({ name: 'warehouse_id', required: false, description: 'فلترة حسب المخزن' })
  @ApiQuery({
    name: 'movement_type',
    required: false,
    description: 'نوع الحركة: IN, OUT, TRANSFER_OUT, TRANSFER_IN, ADJUST_ADD, ADJUST_REDUCE',
  })
  @ApiQuery({ name: 'search', required: false, description: 'بحث باسم المنتج أو الباركود' })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAllMovements(@Query() query: any) {
    return this.inventoryService.findAllMovements(query);
  }

  @Get('alerts/low-stock')
  @ApiOperation({ summary: 'قائمة تنبيهات انخفاض المخزون تحت الحد الأدنى' })
  @ApiQuery({ name: 'warehouse_id', required: false })
  async getLowStockAlerts(@Query() query: { warehouse_id?: string; page?: string; limit?: string }) {
    const result = await this.inventoryService.getLowStockAlerts(query);
    return { success: true, data: result.data, meta: result.meta };
  }

  @Get('balances')
  @ApiOperation({ summary: 'سحب ومزامنة أرصدة المخزون للأجهزة والأنظمة الطرفية (Inventory Pull)' })
  @ApiQuery({ name: 'warehouse_id', required: false, description: 'فلترة حسب المخزن (UUID)' })
  @ApiQuery({ name: 'product_id', required: false, description: 'فلترة حسب معرف المنتج لجلب كافة أشكاله (UUID)' })
  @ApiQuery({ name: 'variant_id', required: false, description: 'فلترة حسب شكل محدد للمنتج (UUID)' })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 100 })
  async getBalances(@Query() query: GetInventoryBalancesDto) {
    const result = await this.inventoryService.getInventoryBalances(query);
    return {
      success: true,
      data: result.data,
      meta: result.meta,
    };
  }
}
