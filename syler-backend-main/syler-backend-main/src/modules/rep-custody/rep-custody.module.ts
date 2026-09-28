import { Module } from '@nestjs/common';
import { RepCustodyService } from './rep-custody.service';
import { RepCustodyController } from './rep-custody.controller';

@Module({
  controllers: [RepCustodyController],
  providers: [RepCustodyService],
  exports: [RepCustodyService],
})
export class RepCustodyModule {}
