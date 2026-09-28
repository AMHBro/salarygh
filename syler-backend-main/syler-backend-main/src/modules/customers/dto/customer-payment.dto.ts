import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class RecordCustomerPaymentDto {
  @ApiProperty({ example: 250000, description: 'المبلغ المستلم من الزبون بالدينار' })
  @IsNotEmpty({ message: 'المبلغ مطلوب' })
  @IsNumber()
  @Min(1, { message: 'المبلغ يجب أن يكون أكبر من الصفر' })
  amount: number;

  @ApiProperty({ description: 'UUID ثابت يرسله العميل لكل محاولة دفع ويعيد استخدامه عند إعادة المحاولة' })
  @IsNotEmpty()
  @IsUUID()
  idempotency_key: string;

  @ApiProperty({ description: 'الصندوق الذي استلم الدفعة' })
  @IsNotEmpty()
  @IsUUID()
  cashbox_id: string;

  @ApiPropertyOptional({ description: 'فاتورة البيع التي ستُسدد؛ يمكن تركه فارغاً لدفعة على الذمة العامة' })
  @IsOptional()
  @IsUUID()
  invoice_id?: string;

  @ApiPropertyOptional({ example: 'سداد دفعة نقدية' })
  @IsOptional()
  @IsString()
  notes?: string;
}
