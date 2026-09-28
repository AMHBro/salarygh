import { ConflictException } from '@nestjs/common';
import { ConflictResolutionService } from './conflict-resolution.service';

describe('ConflictResolutionService', () => {
    const service = new ConflictResolutionService();

    it('يعيد الفاتورة الموجودة بنفس المعرّف دون إنشاء نسخة ثانية', () => {
        const decision = service.decide({
            kind: 'historical_document',
            operation: 'CREATE',
            serverExists: true,
        });

        expect(decision.outcome).toBe('idempotent');
    });

    it('يرفض تعديل فاتورة مزامنة ويطلب سند تسوية', () => {
        expect(() =>
            service.assertCanApply({
                kind: 'historical_document',
                operation: 'UPDATE',
                serverExists: true,
                client: { version: 2 },
                server: { version: 2 },
            }),
        ).toThrow(ConflictException);
    });

    it('يعتمد آخر تعديل للسعر عندما تكون نسخة الجهاز أحدث', () => {
        const decision = service.decide({
            kind: 'mutable_master',
            operation: 'UPDATE',
            serverExists: true,
            client: { updatedAt: '2026-09-26T12:00:00.000Z' },
            server: { updatedAt: '2026-09-26T11:00:00.000Z' },
        });

        expect(decision.outcome).toBe('apply');
    });

    it('يرجع تعارض 409 عندما تكون نسخة المخزون على الخادم أحدث', () => {
        try {
            service.assertCanApply({
                kind: 'mutable_master',
                operation: 'UPDATE',
                serverExists: true,
                client: { updatedAt: '2026-09-26T10:00:00.000Z', version: 1 },
                server: { updatedAt: '2026-09-26T11:00:00.000Z', version: 4 },
            });
            throw new Error('expected conflict');
        } catch (error) {
            expect(error).toBeInstanceOf(ConflictException);
            const response = (error as ConflictException).getResponse() as { code: string };
            expect(response.code).toBe('SYNC_CONFLICT');
        }
    });
});
