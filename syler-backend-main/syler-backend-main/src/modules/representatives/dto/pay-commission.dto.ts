import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsNumber, IsOptional, IsString, Min } from 'class-validator';

export class PayCommissionDto {
  @ApiProperty({ example: 122500, description: 'المبلغ المدفوع كعمولة للمندوب بالدينار' })
  @IsNotEmpty({ message: 'مبلغ العمولة مطلوب' })
  @IsNumber()
  @Min(1, { message: 'المبلغ يجب أن يكون أكبر من الصفر' })
  amount: number;

  @ApiPropertyOptional({ example: 'صرف عمولة شهر آب' })
  @IsOptional()
  @IsString()
  notes?: string;
}
