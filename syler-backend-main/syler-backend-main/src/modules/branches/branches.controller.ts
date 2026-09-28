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
import { BranchesService } from './branches.service';
import { CreateBranchDto } from './dto/create-branch.dto';
import { RejectRequestDto } from './dto/reject-request.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Roles } from '../../common/decorators/roles.decorator';

@ApiTags('Branches M02')
@Controller('branches')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
export class BranchesController {
    constructor(private readonly branchesService: BranchesService) { }
    @Post()
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: "أنشاء فرع جديد (Draft مسودة)" })
    async create(@Body() dto: CreateBranchDto, @Req() req: any) {
        const data = await this.branchesService.create(dto, req.user.userId);
        return { success: true, data }
    }
    @Get()
    @ApiOperation({ summary: 'قائمة الفروع مع البحث والفلترة' })
    async findAll(@Query() query: any) {
        const result = await this.branchesService.findAll(query);
        return { success: true, ...result };
    }

    @Get(':id')
    @ApiOperation({ summary: 'تفاصيل الفرع ومخازنه' })
    async findOne(@Param('id') id: string) {
        const data = await this.branchesService.findOne(id);
        return { success: true, data };
    }

    @Post(':id/submit')
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'إرسال الفرع للاعتماد' })
    async submit(@Param('id') id: string) {
        const data = await this.branchesService.submitForApproval(id);
        return { success: true, data, message: 'تم إرسال الفرع للاعتماد' };
    }

    @Post(':id/approve')
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'اعتماد الفرع وتفعيله' })
    async approve(@Param('id') id: string, @Req() req: any) {
        const data = await this.branchesService.approve(id, req.user?.id);
        return { success: true, data, message: 'تم اعتماد وتفعيل الفرع بنجاح' };
    }
    @Post(':id/reject')
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'رفض طلب الفرع مع السبب' })
    async reject(@Param('id') id: string, @Body() dto: RejectRequestDto) {
        const data = await this.branchesService.reject(id, dto);
        return { success: true, data, message: 'تم رفض الطلب' };
    }

    @Post(':id/disable')
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'تعطيل الفرع بعد فحص الشروط' })
    async disable(@Param('id') id: string) {
        const data = await this.branchesService.disable(id);
        return { success: true, data, message: 'تم تعطيل الفرع' };
    }


    @Put(':id/manager')
    @Roles('ADMIN', 'MANAGER')
    @ApiOperation({ summary: 'تعيين مدير الفرع' })
    async assignManager(@Param('id') id: string, @Body('manager_id') managerId: string) {
        const data = await this.branchesService.assignManager(id, managerId);
        return { success: true, data };
    }



}