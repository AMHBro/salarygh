import { Controller, Delete, Get, Post, Patch, Param, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { RepresentativesService } from './representatives.service';
import { CreateRepresentativeDto } from './dto/create-representative.dto';
import { UpdateRepresentativeDto } from './dto/update-representative.dto';
import { PayCommissionDto } from './dto/pay-commission.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { rep_status_enum } from '@prisma/client';

@ApiTags('Sales Representatives (M07)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('representatives')
export class RepresentativesController {
  constructor(private readonly repsService: RepresentativesService) {}

  @Get('dashboard/stats')
  @ApiOperation({ summary: 'إحصائيات لوحة المندوبين (النشطون، المبيعات، إجمالي العمولات، المستحقات)' })
  async getDashboardStats() {
    const data = await this.repsService.getDashboardStats();
    return { success: true, data };
  }

  @Post()
  @Roles('ADMIN', 'MANAGER')
  @ApiOperation({ summary: 'إضافة مندوب جديد وإنشاء حساب دخول له وبيانات المكتب' })
  async create(@Body() dto: CreateRepresentativeDto, @Request() req: any) {
    const data = await this.repsService.create(dto, req.user?.id);
    return { success: true, data, message: 'تم إضافة المندوب وإنشاء حسابه بنجاح' };
  }

  @Get('debt-ceilings')
  @ApiOperation({ summary: 'سقف ذمة كل مندوب ومجموع أرصدة زبائنه على السحابة' })
  async debtCeilings() {
    const data = await this.repsService.debtCeilings();
    return { success: true, data };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة المندوبين مع الفلاتر والبحث وتفاصيل العمولات' })
  @ApiQuery({ name: 'status', required: false, enum: rep_status_enum })
  @ApiQuery({ name: 'search', required: false, description: 'بحث بالاسم، المستخدم، أو الهاتف' })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAll(@Query() query: any) {
    return this.repsService.findAll(query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'تفاصيل المندوب مع إحصائيات مبيعاته وعمولاته وسجل فواتيره' })
  async findOne(@Param('id') id: string) {
    const data = await this.repsService.findOne(id);
    return { success: true, data };
  }

  @Post(':id/pay-commission')
  @Roles('ADMIN', 'MANAGER')
  @ApiOperation({ summary: 'صرف ودفع عمولة للمندوب وتخفيض رصيد المستحق' })
  async payCommission(@Param('id') id: string, @Body() dto: PayCommissionDto) {
    return this.repsService.payCommission(id, dto);
  }

  @Patch(':id')
  @Roles('ADMIN', 'MANAGER')
  @ApiOperation({ summary: 'تعديل بيانات المندوب ونسبة العمولة وبيانات المكتب' })
  async update(@Param('id') id: string, @Body() dto: UpdateRepresentativeDto) {
    const data = await this.repsService.update(id, dto);
    return { success: true, data, message: 'تم تعديل بيانات المندوب بنجاح' };
  }

  @Delete(':id')
  @Roles('ADMIN', 'MANAGER')
  @ApiOperation({ summary: 'إغلاق حساب المندوب وتحرير اسم الدخول' })
  async remove(@Param('id') id: string) {
    return this.repsService.remove(id);
  }

  @Patch(':id/toggle-status')
  @Roles('ADMIN', 'MANAGER')
  @ApiOperation({ summary: 'تفعيل أو إيقاف حساب المندوب' })
  async toggleStatus(@Param('id') id: string) {
    return this.repsService.toggleStatus(id);
  }
}
