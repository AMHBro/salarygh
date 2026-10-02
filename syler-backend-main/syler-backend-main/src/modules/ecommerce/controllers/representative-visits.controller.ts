import { Body, Controller, Post, Req, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { RepresentativeVisitsService, VisitBody } from '../services/representative-visits.service';

@ApiTags('Representative visits')
@ApiBearerAuth()
@Controller('visits')
export class RepresentativeVisitsController {
    constructor(private readonly visits: RepresentativeVisitsService) {}

    @Post('start')
    start(@Req() request: { user?: { id?: string; userId?: string; sub?: string } }, @Body() body: VisitBody) {
        return this.visits.start(this.userId(request), body);
    }

    @Post('end')
    end(@Req() request: { user?: { id?: string; userId?: string; sub?: string } }, @Body() body: VisitBody) {
        return this.visits.end(this.userId(request), body);
    }

    @Post('postpone')
    postpone(@Req() request: { user?: { id?: string; userId?: string; sub?: string } }, @Body() body: VisitBody) {
        return this.visits.postpone(this.userId(request), body);
    }

    private userId(request: { user?: { id?: string; userId?: string; sub?: string } }) {
        const userId = request.user?.id ?? request.user?.userId ?? request.user?.sub;
        if (!userId) {
            throw new UnauthorizedException({
                code: 'AUTH_REQUIRED',
                message: 'تسجيل الدخول مطلوب',
            });
        }
        return userId;
    }
}
