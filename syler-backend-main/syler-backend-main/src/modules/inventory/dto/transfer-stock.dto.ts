import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsUUID, IsNumber, IsOptional, IsString, Min } from 'class-validator';

export class TransferStockDto {
  @ApiProperty({ example: 'uuid-source-warehouse-id', description: 'المخزن المحول منه (المصدر)' })
  @IsNotEmpty({ message: 'المخزن المصدر مطلوب' })
  @IsUUID()
  source_warehouse_id: string;

  @ApiProperty({ example: 'uuid-destination-warehouse-id', description: 'المخزن المحول إليه (الهدف)' })
  @IsNotEmpty({ message: 'المخزن الهدف مطلوب' })
  @IsUUID()
  destination_warehouse_id: string;

  @ApiProperty({ example: 'uuid-product-variant-id', description: 'معرف المنتج المراد تحويله' })
  @IsNotEmpty({ message: 'المنتج مطلوب' })
  @IsUUID()
  variant_id: string;

  @ApiProperty({ example: 20, description: 'الكمية المراد تحويلها' })
  @IsNumber()
  @Min(0.001, { message: 'الكمية يجب أن تكون أكبر من الصفر' })
  quantity: number;

  @ApiPropertyOptional({ example: 'تغذية فرع المنصور' })
  @IsOptional()
  @IsString()
  notes?: string;
}
