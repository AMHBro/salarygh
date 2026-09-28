import { Module } from '@nestjs/common';

import { FloorModule } from '../floor/floor.module';
import { DirectSalesController } from './direct-sales.controller';
import { DirectSalesService } from './direct-sales.service';
import { SalesTransactionService } from './sales-transaction.service';

@Module({
  imports: [FloorModule],

  controllers: [
    DirectSalesController,
  ],

  providers: [
    DirectSalesService,
    SalesTransactionService,
  ],

  exports: [
    DirectSalesService,
    SalesTransactionService,
  ],
})
export class DirectSalesModule { }