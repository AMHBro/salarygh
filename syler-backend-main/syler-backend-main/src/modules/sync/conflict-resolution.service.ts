import { ConflictException, Injectable } from '@nestjs/common';

export type SyncEntityKind = 'historical_document' | 'mutable_master';
export type SyncWriteOperation = 'CREATE' | 'UPDATE' | 'DELETE';

export interface VersionStamp {
    version?: number | null;
    updatedAt?: Date | string | null;
}

export interface ConflictInput {
    kind: SyncEntityKind;
    operation: SyncWriteOperation;
    serverExists: boolean;
    client?: VersionStamp;
    server?: VersionStamp;
}

export interface ConflictDecision {
    outcome: 'apply' | 'idempotent' | 'conflict';
    reason: string;
}

@Injectable()
export class ConflictResolutionService {
    decide(input: ConflictInput): ConflictDecision {
        if (input.kind === 'historical_document') {
            return this.decideHistorical(input);
        }

        return this.decideMutable(input);
    }

    assertCanApply(input: ConflictInput): ConflictDecision {
        const decision = this.decide(input);
        if (decision.outcome === 'conflict') {
            throw new ConflictException({
                code: 'SYNC_CONFLICT',
                message: decision.reason,
                server: input.server ?? null,
            });
        }
        return decision;
    }

    private decideHistorical(input: ConflictInput): ConflictDecision {
        if (input.operation === 'CREATE') {
            if (input.serverExists) {
                return {
                    outcome: 'idempotent',
                    reason: 'المستند موجود بنفس المعرّف ولن يُنشأ مرة ثانية',
                };
            }
            return {
                outcome: 'apply',
                reason: 'مستند جديد',
            };
        }

        if (input.operation === 'DELETE' && !input.serverExists) {
            return {
                outcome: 'idempotent',
                reason: 'المستند غير موجود',
            };
        }

        return {
            outcome: 'conflict',
            reason: 'الفواتير والحركات التاريخية لا تُعدَّل بعد المزامنة. التصحيح يكون بسند تسوية',
        };
    }

    private decideMutable(input: ConflictInput): ConflictDecision {
        if (!input.serverExists && input.operation !== 'UPDATE') {
            return { outcome: 'apply', reason: 'لا توجد نسخة على الخادم' };
        }

        const clientVersion = input.client?.version;
        const serverVersion = input.server?.version;
        if (
            typeof clientVersion === 'number' &&
            typeof serverVersion === 'number' &&
            clientVersion < serverVersion
        ) {
            return {
                outcome: 'conflict',
                reason: 'نسخة الخادم أحدث من نسخة الجهاز',
            };
        }

        const clientTime = this.time(input.client?.updatedAt);
        const serverTime = this.time(input.server?.updatedAt);
        if (clientTime !== null && serverTime !== null && clientTime < serverTime) {
            return {
                outcome: 'conflict',
                reason: 'آخر تعديل على الخادم أحدث من تعديل الجهاز',
            };
        }

        return {
            outcome: 'apply',
            reason: 'آخر تعديل يُعتمد',
        };
    }

    private time(value: Date | string | null | undefined): number | null {
        if (value == null) {
            return null;
        }
        const time = new Date(value).getTime();
        return Number.isNaN(time) ? null : time;
    }
}
