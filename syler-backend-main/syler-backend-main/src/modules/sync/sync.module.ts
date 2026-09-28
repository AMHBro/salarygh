import { Module } from '@nestjs/common';
import { ConflictResolutionService } from './conflict-resolution.service';

/**
 * محرك المزامنة المعتمد هو طابور NestJS مع حسم التعارض هنا.
 * جداول SymmetricDS تبقى في قاعدة البيانات كما هي، ولا يُشغَّل محركها.
 */
@Module({
    providers: [ConflictResolutionService],
    exports: [ConflictResolutionService],
})
export class SyncModule {}
