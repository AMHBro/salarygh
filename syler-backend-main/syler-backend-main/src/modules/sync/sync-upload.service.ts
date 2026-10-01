import {
    HttpException,
    Injectable,
    UnprocessableEntityException,
} from '@nestjs/common';
import { DirectSalesService } from '../direct-sales/direct-sales.service';
import { CreateDirectSaleDto } from '../direct-sales/dto/create-direct-sale.dto';

@Injectable()
export class SyncUploadService {
    constructor(private readonly directSales: DirectSalesService) {}

    async upload(dto: CreateDirectSaleDto, userId?: string) {
        dto.sync_revalidate = true;
        try {
            const data = await this.directSales.createDirectSale(dto, userId);
            return {
                success: true,
                data,
                message: 'تمت عملية البيع بنجاح',
            };
        } catch (error) {
            if (!this.isCeilingRejection(error)) {
                throw error;
            }
            const message = this.readMessage(error);
            throw new UnprocessableEntityException({
                code: 'SYNC_REJECTED',
                status: 'SYNC_REJECTED',
                message,
            });
        }
    }

    private isCeilingRejection(error: unknown): boolean {
        if (!(error instanceof HttpException)) {
            return false;
        }
        const body = error.getResponse();
        const code = this.readCode(body);
        const message = this.readMessage(error);
        return code === 'CREDIT_LIMIT_EXCEEDED'
            || message.includes('الحد الائتماني')
            || message.includes('تجاوزت السقف');
    }

    private readCode(body: unknown): string {
        if (body && typeof body === 'object' && 'code' in body) {
            return String((body as { code?: unknown }).code ?? '');
        }
        return '';
    }

    private readMessage(error: HttpException): string {
        const body = error.getResponse();
        if (typeof body === 'string' && body.trim()) {
            return body;
        }
        if (body && typeof body === 'object' && 'message' in body) {
            const message = (body as { message?: unknown }).message;
            if (typeof message === 'string' && message.trim()) {
                return message;
            }
        }
        return 'تم رفض الفاتورة لأن السقف الائتماني لم يعد يكفي';
    }
}
