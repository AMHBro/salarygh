import { Controller, Get, Post, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { SupplierPaymentsService } from './supplier-payments.service';
import { CreateSupplierPaymentDto } from './dto/create-supplier-payment.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Permissions } from '../../common/decorators/permissions.decorator';

@ApiTags('Supplier Payments (M04)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('supplier-payments')
export class SupplierPaymentsController {
    constructor(private readonly paymentsService: SupplierPaymentsService) { }

    @Post()
    @Permissions('PURCHASE_EDIT')
    @ApiOperation({ summary: 'تسجيل سند دفع لمورد وخفض رصيد الذمة' })
    async createPayment(@Body() dto: CreateSupplierPaymentDto, @Request() req: any) {
        const data = await this.paymentsService.createPayment(dto, req.user?.id);
        return { success: true, data, message: 'تم تسجيل سند الدفع وخفض رصيد الذمة بنجاح' };
    }

    @Get()
    @ApiOperation({ summary: 'قائمة سندات الدفع مع إمكانية الفلترة بالمورد' })
    @ApiQuery({ name: 'supplier_id', required: false })
    @ApiQuery({ name: 'page', required: false, example: 1 })
    @ApiQuery({ name: 'limit', required: false, example: 20 })
    async findAll(@Query() query: any) {
        return this.paymentsService.findAll(query);
    }
}