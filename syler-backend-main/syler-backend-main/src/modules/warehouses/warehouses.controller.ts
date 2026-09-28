import {
    Controller,
    Get,
    Post,
    Patch,
    Put,
    Param,
    Body,
    Query,
    UseGuards,
    Req,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { WarehousesService } from './warehouses.service';
import { CreateWarehouseDto } from './dto/create-warehouse.dto';
import { RejectRequestDto } from '../branches/dto/reject-request.dto';
import { AssignKeepersDto } from './dto/assign-keepers.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Roles } from '../../common/decorators/roles.decorator';



@ApiTags('Warehouses (M02)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('warehouses')

export class WarehousesController {
    constructor(private readonly warehousesService: WarehousesService) { }

    @Post()
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'إنشاء مخزن' })
    async create(@Body() dto: CreateWarehouseDto, @Req() req: any) {
        const data = await this.warehousesService.create(dto, req.user?.id);
        return { success: true, data };
    }
    @Get()
    @ApiOperation({ summary: 'قائمة المخازن مع الفلترة بالفرع والنوع والحالة' })
    async findAll(@Query() query: any) {
        const result = await this.warehousesService.findAll(query);
        return { success: true, ...result };
    }

    @Get(':id')
    @ApiOperation({ summary: 'تفاصيل المخزن وأمنائه والمخازن التابعة' })
    async findOne(@Param('id') id: string) {
        const data = await this.warehousesService.findOne(id);
        return { success: true, data };
    }
    @Post(':id/submit')
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'إرسال المخزن للاعتماد' })
    async submit(@Param('id') id: string) {
        const data = await this.warehousesService.submitForApproval(id);
        return { success: true, data, message: 'تم إرسال المخزن للاعتماد' };
    }
    @Post(':id/approve')
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'اعتماد المخزن وتفعيله' })
    async approve(@Param('id') id: string, @Req() req: any) {
        const data = await this.warehousesService.approve(id, req.user?.id);
        return { success: true, data, message: 'تم اعتماد وتفعيل المخزن بنجاح' };
    }
    @Post(':id/reject')
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'رفض طلب المخزن مع السبب' })
    async reject(@Param('id') id: string, @Body() dto: RejectRequestDto) {
        const data = await this.warehousesService.reject(id, dto);
        return { success: true, data, message: 'تم رفض طلب المخزن' };
    }
    @Post(':id/disable')
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'تعطيل المخزن بعد فحص الرصيد' })
    async disable(@Param('id') id: string) {
        const data = await this.warehousesService.disable(id);
        return { success: true, data, message: 'تم تعطيل المخزن بنجاح' };
    }
    @Put(':id/keepers')
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'تعيين أمناء المخزن' })
    async assignKeepers(@Param('id') id: string, @Body() dto: AssignKeepersDto) {
        const data = await this.warehousesService.assignKeepers(id, dto);
        return { success: true, data, message: 'تم تحديث قائمة أمناء المخزن بنجاح' };
    }
}