import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Permissions } from '../../common/decorators/permissions.decorator';
import { CreateDirectSaleDto } from '../direct-sales/dto/create-direct-sale.dto';
import { SyncUploadService } from './sync-upload.service';

@ApiTags('Sync')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('sync')
export class SyncUploadController {
    constructor(private readonly uploadService: SyncUploadService) {}

    @Post('upload')
    @Permissions('INVOICE_EDIT')
    @ApiOperation({
        summary: 'رفع فاتورة من طابور الأوفلاين مع إعادة فحص السقف الائتماني',
    })
    upload(@Body() dto: CreateDirectSaleDto, @Req() req: { user?: { id?: string } }) {
        return this.uploadService.upload(dto, req.user?.id);
    }
}
