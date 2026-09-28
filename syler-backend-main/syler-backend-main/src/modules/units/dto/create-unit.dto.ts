import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsBoolean, IsNumber, IsUUID, Min } from 'class-validator';

export class CreateUnitDto {
    @ApiProperty({ example: 'قطعة' })
    @IsNotEmpty({ message: 'اسم الوحدة بالعربية مطلوب' })
    @IsString()
    name_ar: string;

    @ApiPropertyOptional({ example: 'Piece' })
    @IsOptional()
    @IsString()
    name_en?: string;

    @ApiPropertyOptional({ example: 'PCS' })
    @IsOptional()
    @IsString()
    symbol?: string;

    @ApiPropertyOptional({ example: 'uuid-of-base-unit' })
    @IsOptional()
    @IsUUID()
    parent_unit_id?: string;

    @ApiPropertyOptional({ example: 1, description: 'معامل التحويل مقابل الوحدة الأساسية' })
    @IsOptional()
    @IsNumber()
    @Min(0.000001, { message: 'معامل التحويل يجب أن يكون أكبر من الصفر' })
    conversion_factor?: number;

    @ApiPropertyOptional({ default: false })
    @IsOptional()
    @IsBoolean()
    is_base_unit?: boolean;
}