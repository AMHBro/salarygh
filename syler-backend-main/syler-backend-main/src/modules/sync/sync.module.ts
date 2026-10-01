import { Module } from '@nestjs/common';
import { DirectSalesModule } from '../direct-sales/direct-sales.module';
import { ConflictResolutionService } from './conflict-resolution.service';
import { SyncUploadController } from './sync-upload.controller';
import { SyncUploadService } from './sync-upload.service';

/**
 * محرك المزامنة المعتمد هو طابور NestJS مع حسم التعارض هنا.
 * جداول SymmetricDS تبقى في قاعدة البيانات كما هي، ولا يُشغَّل محركها.
 */
@Module({
    imports: [DirectSalesModule],
    controllers: [SyncUploadController],
    providers: [ConflictResolutionService, SyncUploadService],
    exports: [ConflictResolutionService],
})
export class SyncModule {}
