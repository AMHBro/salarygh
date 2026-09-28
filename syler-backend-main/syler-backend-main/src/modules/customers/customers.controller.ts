import { Controller, Get, Post, Patch, Delete, Param, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { CustomersService } from './customers.service';
import { CreateCustomerDto } from './dto/create-customer.dto';
import { UpdateCustomerDto } from './dto/update-customer.dto';
import { RecordCustomerPaymentDto } from './dto/customer-payment.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Permissions } from '../../common/decorators/permissions.decorator';

@ApiTags('Customers (M06)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('customers')
export class CustomersController {
  constructor(private readonly customersService: CustomersService) { }

  @Get('dashboard/stats')
  @ApiOperation({ summary: 'إحصائيات لوحة الزبائن (عدد الزبائن، إجمالي المبيعات، إجمالي الديون، زبائن عليهم رصيد)' })
  async getDashboardStats() {
    const data = await this.customersService.getDashboardStats();
    return { success: true, data };
  }

  @Post()
  @Permissions('CUSTOMER_EDIT')
  @ApiOperation({ summary: 'إنشاء زبون جديد' })
  async create(@Body() dto: CreateCustomerDto, @Request() req: any) {
    const data = await this.customersService.create(dto, req.user?.id);
    return { success: true, data, message: 'تم إنشاء الزبون بنجاح' };
  }

  @Get()
  @ApiOperation({ summary: 'قائمة الزبائن مع البحث وفلترة الديون والصفحات' })
  @ApiQuery({ name: 'search', required: false, description: 'بحث بالاسم أو الهاتف' })
  @ApiQuery({ name: 'filter', required: false, enum: ['all', 'has_debt', 'settled'] })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  async findAll(@Query() query: any) {
    return this.customersService.findAll(query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'تفاصيل الزبون وسجل فواتيره' })
  async findOne(@Param('id') id: string) {
    const data = await this.customersService.findOne(id);
    return { success: true, data };
  }

  @Post(':id/payments')
  @Permissions('CUSTOMER_EDIT')
  @ApiOperation({ summary: 'تسجيل دفعة قبض من زبون لتسديد رصيد ديونه' })
  async recordPayment(@Param('id') id: string, @Body() dto: RecordCustomerPaymentDto, @Request() req: any) {
    return this.customersService.recordPayment(id, dto, req.user?.id);
  }

  @Patch(':id')
  @Permissions('CUSTOMER_EDIT')
  @ApiOperation({ summary: 'تحديث بيانات الزبون والحد الائتماني' })
  async update(@Param('id') id: string, @Body() dto: UpdateCustomerDto) {
    const data = await this.customersService.update(id, dto);
    return { success: true, data, message: 'تم تحديث بيانات الزبون بنجاح' };
  }

  @Delete(':id')
  @Permissions('CUSTOMER_EDIT')
  @ApiOperation({ summary: 'تعطيل الزبون بعد التحقق من خلو ذمته' })
  async remove(@Param('id') id: string) {
    const data = await this.customersService.remove(id);
    return { success: true, data, message: 'تم تعطيل الزبون بنجاح' };
  }
}
