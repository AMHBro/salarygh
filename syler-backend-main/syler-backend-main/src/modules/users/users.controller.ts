import {
    BadRequestException,
    Body,
    Controller,
    Delete,
    Get,
    Param,
    Patch,
    Post,
    Req,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Permissions } from '../../common/decorators/permissions.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { AssignStationDto } from './dto/assign-station.dto';
import { CreateUserDto } from './dto/create-user.dto';
import { UsersService } from './users.service';

@Controller('users')
export class UsersController {
    constructor(private readonly usersService: UsersService) {}

    @Get('activity')
    @Roles('ADMIN', 'MANAGER')
    activity(@Req() req: { user?: { id?: string } }) {
        const userId = req.user?.id ?? '';
        return this.usersService.activityFor(userId);
    }

    @Get('roles')
    @Permissions('USER_MANAGE')
    roles() {
        return this.usersService.listRoles();
    }

    @Get()
    @Permissions('USER_MANAGE')
    list() {
        return this.usersService.listStations();
    }

    @Post()
    @Permissions('USER_MANAGE')
    async create(
        @Body() dto: CreateUserDto,
        @Req() req: { user?: { id?: string } },
    ) {
        try {
            const created = await this.usersService.create(dto, req.user?.id);
            return this.usersService.findById(created.id).then((user) => ({
                id: user.id,
                full_name: user.full_name,
                username: user.username,
                email: user.email,
                is_active: user.is_active,
                role_id: user.role_id,
                role_name: user.roles?.name ?? null,
            }));
        } catch (error) {
            if (
                error instanceof Prisma.PrismaClientKnownRequestError &&
                error.code === 'P2002'
            ) {
                throw new BadRequestException('اسم الدخول أو البريد مستخدم لحاسبة أخرى.');
            }
            throw error;
        }
    }

    @Patch(':id')
    @Permissions('USER_MANAGE')
    assign(@Param('id') id: string, @Body() dto: AssignStationDto) {
        return this.usersService.assignStation(id, dto);
    }

    @Delete(':id')
    @Permissions('USER_MANAGE')
    async remove(
        @Param('id') id: string,
        @Req() req: { user?: { id?: string } },
    ) {
        if (req.user?.id && req.user.id === id) {
            throw new BadRequestException('لا يمكن حذف الحساب الذي دخلت به.');
        }
        try {
            await this.usersService.removeUser(id);
            return { success: true };
        } catch (error) {
            if (
                error instanceof Prisma.PrismaClientKnownRequestError &&
                (error.code === 'P2003' || error.code === 'P2014')
            ) {
                throw new BadRequestException(
                    'لا يمكن حذف حاسبة لها فواتير أو عمليات. أوقف الدخول بدل الحذف.',
                );
            }
            throw error;
        }
    }
}
