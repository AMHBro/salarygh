import { Controller, Get, Post, Patch, Delete, Param, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { SuppliersService } from './suppliers.service';
import { CreateSupplierDto } from './dto/create-supplier.dto';
import { CreateSupplierSheetDto } from './dto/create-supplier-sheet.dto';
import { UpdateSupplierDto } from './dto/update-supplier.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Permissions } from '../../common/decorators/permissions.decorator';

@ApiTags('Suppliers (M04)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('suppliers')
export class SuppliersController {
    constructor(private readonly suppliersService: SuppliersService) { }

    @Post()
    @Permissions('PURCHASE_EDIT')
    @ApiOperation({ summary: "انشاء مورد جديد" })
    async create(@Body() dto: CreateSupplierDto, @Request() req: any) {
        const data = await this.suppliersService.create(dto, req.user?.id);
        return { success: true, data, message: 'تم اضافة مورد جديد بنجاح' }
    }

    @Get()
    @ApiOperation({ summary: 'قائمة الموردين مع البحث والصفحات' })
    @ApiQuery({ name: 'search', required: false })
    @ApiQuery({ name: 'page', required: false, example: 1 })
    @ApiQuery({ name: 'limit', required: false, example: 20 })
    async findAll(@Query() query: any) {
        const data = await this.suppliersService.findAll(query);
        return { success: true, data, message: 'تم الحصول على قائمة الموردين بنجاح' }
    }
    @Get('sheets')
    @ApiOperation({ summary: 'صور مجلدات الموردين لتنزيلها في النظام الأساسي' })
    async listSheets(@Query('page') page?: string) {
        return this.suppliersService.listSheets(page);
    }

    @Post(':id/sheets')
    @ApiOperation({ summary: 'إضافة صورة إلى مجلد المورد' })
    async addSheet(@Param('id') id: string, @Body() dto: CreateSupplierSheetDto) {
        const data = await this.suppliersService.addSheet(id, dto);
        return { success: true, data, message: 'تم حفظ صورة المورد' };
    }

    @Get(':id')
    @ApiOperation({ summary: 'تفاصيل المورد' })
    async findOne(@Param('id') id: string) {
        const data = await this.suppliersService.findOne(id);
        return { success: true, data };
    }
    @Get(':id/statement')
    @ApiOperation({ summary: 'كشف حساب المورد (فواتير وسندات صرف والذمة الحالية)' })
    async getStatement(@Param('id') id: string) {
        const data = await this.suppliersService.getStatement(id);
        return { success: true, data };
    }
    @Patch(':id')
    @Permissions('PURCHASE_EDIT')
    @ApiOperation({ summary: 'تحديث بيانات المورد والحد الائتماني' })
    async update(@Param('id') id: string, @Body() dto: UpdateSupplierDto) {
        const data = await this.suppliersService.update(id, dto);
        return { success: true, data, message: 'تم تحديث المورد بنجاح' };
    }
    @Delete(':id')
    @Permissions('PURCHASE_EDIT')
    @ApiOperation({ summary: 'تعطيل المورد بعد التحقق من خلو ذمته المالية' })
    async remove(@Param('id') id: string) {
        const data = await this.suppliersService.remove(id);
        return { success: true, data, message: 'تم تعطيل المورد بنجاح' };
    }
}
