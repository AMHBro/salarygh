import {
    Body,
    Controller,
    Get,
    Post,
    Req,
    UseGuards,
} from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Request } from 'express';

import { JwtAuthGuard } from '../../auth/guards/jwt-auth.guard';
import { AgentPortalService } from '../services/agent-portal.service';
import { Public } from '../../../common/decorators/public.decorator';

interface AuthenticatedRequest extends Request {
    user?: { id?: string };
}

@ApiTags('Agent portal')
@Controller('store/agent')
export class AgentPortalController {
    constructor(private readonly agentPortal: AgentPortalService) {}

    @Public()
    @Post('login')
    login(@Body() body: { username?: string; password?: string }) {
        return this.agentPortal.login(
            body.username ?? '',
            body.password ?? '',
        );
    }

    @Get('account')
    @UseGuards(JwtAuthGuard)
    account(@Req() request: AuthenticatedRequest) {
        return this.agentPortal.account(request.user?.id ?? '');
    }

    @Post('offices')
    @UseGuards(JwtAuthGuard)
    createOffice(
        @Req() request: AuthenticatedRequest,
        @Body() body: { name?: string; phone?: string; address?: string },
    ) {
        return this.agentPortal.createOffice(request.user?.id ?? '', {
            name: body.name ?? '',
            phone: body.phone ?? '',
            address: body.address ?? '',
        });
    }
}
