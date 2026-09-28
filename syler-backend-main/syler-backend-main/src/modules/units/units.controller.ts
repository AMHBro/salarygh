import { Controller, Get, Post, Patch, Delete, Param, Body, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { UnitsService } from './units.service';
import { CreateUnitDto } from './dto/create-unit.dto';
import { UpdateUnitDto } from './dto/update-unit.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Permissions } from '../../common/decorators/permissions.decorator';


@ApiTags('Units (M03)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('units')
export class UnitsController {
    constructor(private readonly unitsService: UnitsService) { }
    @Post()
    @Permissions('PRODUCT_EDIT')
    @ApiOperation({ summary: 'إنشاء وحدة قياس جديدة' })
    async create(@Body() dto: CreateUnitDto) {
        return this.unitsService.create(dto);
    }
    @Get()
    @ApiOperation({ summary: 'قائمة جميع وحدات القياس النشطة' })
    async findAll() {
        const data = await this.unitsService.findAll();
        return { success: true, data };
    }
    @Get(':id')
    @ApiOperation({ summary: 'تفاصيل وحدة القياس والوحدات التابعة' })
    async findOne(@Param('id') id: string) {
        const data = await this.unitsService.findOne(id);
        return { success: true, data };
    }
    @Patch(':id')
    @Permissions('PRODUCT_EDIT')
    @ApiOperation({ summary: 'تحديث بيانات وحدة القياس' })
    async update(@Param('id') id: string, @Body() dto: UpdateUnitDto) {
        const data = await this.unitsService.update(id, dto);
        return { success: true, data, message: 'تم تحديث وحدة القياس بنجاح' };
    }
    @Delete(':id')
    @Permissions('PRODUCT_EDIT')
    @ApiOperation({ summary: 'تعطيل/حذف وحدة القياس' })
    async remove(@Param('id') id: string) {
        const data = await this.unitsService.remove(id);
        return { success: true, data, message: 'تم تعطيل وحدة القياس بنجاح' };
    }
}
