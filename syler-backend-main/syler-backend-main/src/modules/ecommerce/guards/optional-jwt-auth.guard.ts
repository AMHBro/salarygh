import {
    ExecutionContext,
    Injectable,
    UnauthorizedException,
} from '@nestjs/common';

import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class OptionalJwtAuthGuard extends AuthGuard('jwt') {
    handleRequest(
        err: any,
        user: any,
        info: any,
        context: ExecutionContext,
    ) {
        if (err) {
            throw err;
        }

        /**
         * JWT موجود لكنه غير صالح.
         * لا نحوله بصمت إلى Guest.
         */
        if (
            info &&
            (
                info.name === 'JsonWebTokenError' ||
                info.name === 'TokenExpiredError'
            )
        ) {
            throw new UnauthorizedException({
                code: 'AUTH_INVALID_TOKEN',
                message: 'رمز تسجيل الدخول غير صالح أو منتهي الصلاحية',
            });
        }

        /**
         * لا يوجد JWT أصلاً -> Guest.
         */
        return user ?? null;
    }
}