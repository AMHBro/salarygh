import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { UsersService } from '../users/users.service';
import { users } from '@prisma/client';
import { CreateUserDto } from '../users/dto/create-user.dto';
import { LoginDto } from './dto/login.dto';
import { ConfigService } from '@nestjs/config';
import { RefreshTokenDto } from './dto/refresh-token.dto';

@Injectable()
export class AuthService {
    constructor(
        private readonly usersService: UsersService,
        private readonly jwtService: JwtService,
        private readonly configService: ConfigService
    ) { }

    async validateUser(login: string, password: string): Promise<users | null> {
        const key = login.trim();
        let user: users | null = null;
        try {
            user = key.includes('@')
                ? await this.usersService.findByEmail(key)
                : await this.usersService.findByUsername(key);
        } catch {
            user = null;
        }

        if (!user?.is_active) {
            return null;
        }

        if (await this.usersService.comparePassword(password, user.password_hash)) {
            return user;
        }
        return null;
    }

    async login(loginDto: LoginDto) {
        const user = await this.validateUser(loginDto.email, loginDto.password);
        if (!user) {
            throw new UnauthorizedException('اسم الدخول أو كلمة المرور غير صحيحة.');
        }

        const payload = this.accessPayload(user);
        const accessToken = this.jwtService.sign(payload, {
            expiresIn: (this.configService.get<string>('JWT_ACCESS_TOKEN_EXPIRES_IN') || '15m') as any

        });
        const refreshToken = this.jwtService.sign(payload, {
            expiresIn: (this.configService.get<string>('JWT_REFRESH_TOKEN_EXPIRES_IN') || '7d') as any

        });

        await this.usersService.updateUserById(user.id, { last_login: new Date() } as any);

        const roleName = (user as users & { roles?: { name?: string | null } | null }).roles?.name ?? null;

        return {
            accessToken,
            refreshToken,
            user: { id: user.id, email: user.email, name: user.full_name, role: roleName }
        };
    }

    async register(createUserDto: CreateUserDto) {
        return this.usersService.create(createUserDto);
    }

    async refreshToken(refreshTokenDto: RefreshTokenDto) {
        try {
            const decoded = this.jwtService.verify(refreshTokenDto.refreshToken, {
                secret: this.configService.get<string>('JWT_SECRET')
            });

            const user = await this.usersService.findById(decoded.sub);
            if (!user) {
                throw new UnauthorizedException('User not found');
            }

            const payload = this.accessPayload(user);
            const accessToken = this.jwtService.sign(payload, {
                expiresIn: (this.configService.get<string>('JWT_ACCESS_TOKEN_EXPIRES_IN') || '15m') as any

            });

            return { accessToken };
        } catch (error) {
            throw new UnauthorizedException('Invalid refresh token');
        }
    }

    async logout(userId: string) {
        return this.usersService.updateUserById(userId, { last_login: null } as any);
    }

    private accessPayload(user: users & { roles?: any }) {
        const permissions = (user.roles?.role_permissions ?? [])
            .map((link: { permissions?: { resource?: string; action?: string } }) => {
                const resource = link.permissions?.resource;
                const action = link.permissions?.action;
                if (!resource || !action) {
                    return null;
                }
                return `${resource}_${action}`;
            })
            .filter((code: string | null): code is string => Boolean(code));

        return {
            sub: user.id,
            email: user.email,
            role: user.roles?.name || null,
            permissions,
        };
    }
}
