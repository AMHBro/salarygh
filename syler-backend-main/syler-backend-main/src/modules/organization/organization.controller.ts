import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { OrganizationService } from './organization.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('Organization Hub (M02)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('organization')
export class OrganizationController {
    constructor(private readonly orgService: OrganizationService) { }

    @Get('tree')
    @ApiOperation({ summary: 'عرض شجرة الهيكل التنظيمي الكاملة (شركة -> فروع -> مخازن)' })
    async getTree() {
        const data = await this.orgService.getTree();
        return { success: true, data };
    }

    @Get('approvals')
    @ApiOperation({ summary: 'صندوق طلبات الاعتماد المعلقة للفرع والمخازن' })
    async getApprovals() {
        const data = await this.orgService.getPendingApprovals();
        return { success: true, data };
    }
}