import { IsOptional, IsUUID, IsInt, Min, Max } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiPropertyOptional } from '@nestjs/swagger';

export class GetInventoryBalancesDto {
  @ApiPropertyOptional({ description: 'فلترة حسب المخزن المحدد (UUID)' })
  @IsOptional()
  @IsUUID('4', { message: 'يجب أن يكون warehouse_id بصيغة UUID صحيحة' })
  warehouse_id?: string;

  @ApiPropertyOptional({ description: 'فلترة حسب المنتج الأساسي لجلب كافة أشكاله (UUID)' })
  @IsOptional()
  @IsUUID('4', { message: 'يجب أن يكون product_id بصيغة UUID صحيحة' })
  product_id?: string;

  @ApiPropertyOptional({ description: 'فلترة حسب شكل محدد للمنتج (UUID)' })
  @IsOptional()
  @IsUUID('4', { message: 'يجب أن يكون variant_id بصيغة UUID صحيحة' })
  variant_id?: string;

  @ApiPropertyOptional({ description: 'رقم الصفحة', default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({ description: 'عدد السجلات في كل صفحة (الدفعة)', default: 100 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(1000)
  limit?: number = 100;
}
