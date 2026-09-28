import { Controller, Get, Post, Param, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { RepCustodyService } from './rep-custody.service';
import { CreateRepCustodyDto } from './dto/create-rep-custody.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { custody_status_enum } from '@prisma/client';

@ApiTags('Representative Custody Orders (M07)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('rep-custody')
export class RepCustodyController {
  constructor(private readonly custodyService: RepCustodyService) {}

  @Post()
  @Roles('ADMIN', 'MANAGER', 'WAREHOUSE')
  @ApiOperation({ summary: 'إنشاء طلب عهدة جديدة لمندوب' })
  async createOrder(@Body() dto: CreateRepCustodyDto, @Request() req: any) {
    const data = await this.custodyService.createOrder(dto, req.user?.id);
    return { success: true, data, message: 'تم إنشاء طلب العهدة بنجاح' };
  }

  @Post(':id/dispatch')
  @Roles('ADMIN', 'MANAGER', 'WAREHOUSE')
  @ApiOperation({ summary: 'تجهيز وتسليم العهدة للمندوب وخصم المواد من المخزن' })
  async dispatchOrder(@Param('id') id: string, @Request() req: any) {
    const data = await this.custodyService.dispatchOrder(id, req.user?.id);
    return { success: true, data, message: 'تم تجهيز وتسليم العهدة وخصم الكميات من المخزن بنجاح' };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة طلبات العهد مع الفلاتر' })
  @ApiQuery({ name: 'rep_id', required: false })
  @ApiQuery({ name: 'warehouse_id', required: false })
  @ApiQuery({ name: 'status', required: false, enum: custody_status_enum })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAll(@Query() query: any) {
    return this.custodyService.findAll(query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'تفاصيل طلب عهدة مع قائمة المواد' })
  async findOne(@Param('id') id: string) {
    const data = await this.custodyService.findOne(id);
    return { success: true, data };
  }
}
