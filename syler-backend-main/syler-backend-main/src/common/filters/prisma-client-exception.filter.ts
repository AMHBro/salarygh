import {
    ExceptionFilter,
    Catch,
    ArgumentsHost,
    HttpStatus,
    Logger,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Response } from 'express';

@Catch(Prisma.PrismaClientKnownRequestError)
export class PrismaClientExceptionFilter implements ExceptionFilter {
    private readonly logger = new Logger(PrismaClientExceptionFilter.name);

    catch(exception: Prisma.PrismaClientKnownRequestError, host: ArgumentsHost) {
        const ctx = host.switchToHttp();
        const response = ctx.getResponse<Response>();

        this.logger.error(
            `Prisma Error [${exception.code}]: ${exception.message}`,
            exception.stack,
        );

        switch (exception.code) {
            // Unique constraint violation
            case 'P2002': {
                const fields = (exception.meta?.target as string[]) ?? [];
                response.status(HttpStatus.CONFLICT).json({
                    statusCode: HttpStatus.CONFLICT,
                    error: 'Conflict',
                    message: `القيمة مكررة: الحقل (${fields.join(', ')}) يجب أن يكون فريداً`,
                    prisma_code: exception.code,
                    fields,
                });
                break;
            }

            // Foreign key constraint violation
            case 'P2003': {
                const field = (exception.meta?.field_name as string) ?? 'unknown';
                response.status(HttpStatus.BAD_REQUEST).json({
                    statusCode: HttpStatus.BAD_REQUEST,
                    error: 'Bad Request',
                    message: `معرف غير موجود في قاعدة البيانات للحقل: ${field}. تأكد من مزامنة المورد، المخزن، المادة، والوحدة مع السيرفر أولاً.`,
                    prisma_code: exception.code,
                    field,
                });
                break;
            }

            // Record not found
            case 'P2025': {
                const cause = (exception.meta?.cause as string) ?? 'Record not found';
                response.status(HttpStatus.NOT_FOUND).json({
                    statusCode: HttpStatus.NOT_FOUND,
                    error: 'Not Found',
                    message: `السجل غير موجود: ${cause}`,
                    prisma_code: exception.code,
                });
                break;
            }

            // Record required not found (upsert / update / delete)
            case 'P2016':
            case 'P2001': {
                response.status(HttpStatus.NOT_FOUND).json({
                    statusCode: HttpStatus.NOT_FOUND,
                    error: 'Not Found',
                    message: 'السجل المطلوب غير موجود',
                    prisma_code: exception.code,
                });
                break;
            }

            default: {
                this.logger.error(
                    `Unhandled Prisma error [${exception.code}]: ${exception.message}`,
                );
                response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
                    statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
                    error: 'Internal Server Error',
                    message: 'خطأ في قاعدة البيانات، يرجى التواصل مع الدعم الفني',
                    prisma_code: exception.code,
                });
            }
        }
    }
}
