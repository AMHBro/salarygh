import { Controller, Get, Patch, Body, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { CompanyService } from './company.service';
import { UpdateCompanyDto } from './dto/update-company.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Roles } from '../../common/decorators/roles.decorator';

@ApiTags('Company (M02)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('company')
export class CompanyController {
    constructor(private readonly companyService: CompanyService) { }

    @Get()
    @ApiOperation({ summary: 'عرض بيانات الشركة الأساسية' })
    async getCompany() {
        const data = await this.companyService.getCompany();
        return { success: true, data };
    }

    @Patch()
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'تحديث بيانات الشركة وإعداداتها' })
    async updateCompany(@Body() dto: UpdateCompanyDto) {
        const data = await this.companyService.updateCompany(dto);
        return { success: true, data };
    }
}