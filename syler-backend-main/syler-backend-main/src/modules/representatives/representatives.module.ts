import { Module } from '@nestjs/common';
import { RepresentativesService } from './representatives.service';
import { RepresentativesController } from './representatives.controller';

@Module({
  controllers: [RepresentativesController],
  providers: [RepresentativesService],
  exports: [RepresentativesService],
})
export class RepresentativesModule {}
