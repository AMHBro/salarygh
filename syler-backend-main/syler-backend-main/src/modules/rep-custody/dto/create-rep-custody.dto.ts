import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsUUID, IsArray, ValidateNested, IsNumber, IsOptional, IsString, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class CustodyItemDto {
  @ApiProperty({ example: 'uuid-product-variant-id' })
  @IsNotEmpty()
  @IsUUID()
  variant_id: string;

  @ApiProperty({ example: 25, description: 'الكمية المطلوبة عهدة' })
  @IsNumber()
  @Min(0.001)
  quantity: number;
}

export class CreateRepCustodyDto {
  @ApiProperty({ example: 'uuid-representative-id' })
  @IsNotEmpty()
  @IsUUID()
  rep_id: string;

  @ApiProperty({ example: 'uuid-warehouse-id' })
  @IsNotEmpty()
  @IsUUID()
  warehouse_id: string;

  @ApiPropertyOptional({ example: 'عهدة لبداية الأسبوع' })
  @IsOptional()
  @IsString()
  notes?: string;

  @ApiProperty({ type: [CustodyItemDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CustodyItemDto)
  items: CustodyItemDto[];
}
