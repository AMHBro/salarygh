import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsUUID, IsNumber, IsEnum, IsOptional, IsString, Min } from 'class-validator';

export enum ManualMovementTypeEnum {
  IN = 'IN',
  OUT = 'OUT',
  ADJUST_ADD = 'ADJUST_ADD',
  ADJUST_REDUCE = 'ADJUST_REDUCE',
}

export class CreateInventoryMovementDto {
  @ApiProperty({ example: 'uuid-warehouse-id', description: 'المخزن المستهدف' })
  @IsNotEmpty({ message: 'المخزن مطلوب' })
  @IsUUID()
  warehouse_id: string;

  @ApiProperty({ example: 'uuid-product-variant-id', description: 'معرف المنتج/الشكل' })
  @IsNotEmpty({ message: 'المنتج مطلوب' })
  @IsUUID()
  variant_id: string;

  @ApiProperty({
    enum: ManualMovementTypeEnum,
    example: ManualMovementTypeEnum.IN,
    description: 'نوع الحركة: إدخال أو إخراج أو تسوية (بالزيادة/النقصان)',
  })
  @IsNotEmpty({ message: 'نوع الحركة مطلوب' })
  @IsEnum(ManualMovementTypeEnum)
  movement_type: ManualMovementTypeEnum;

  @ApiProperty({ example: 50, description: 'الكمية' })
  @IsNumber()
  @Min(0.001, { message: 'الكمية يجب أن تكون أكبر من الصفر' })
  quantity: number;

  @ApiPropertyOptional({ example: 8500, description: 'سعر الكلفة التقديري في حال الإدخال' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  unit_cost?: number;

  @ApiPropertyOptional({ example: 'رصيد افتتاحي / تسوية جرد دوري / إتلاف بضاعة' })
  @IsOptional()
  @IsString()
  notes?: string;
}
