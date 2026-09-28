import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsNumber, Min } from 'class-validator';

export class QuickAddProductDto {
    @ApiProperty({ example: 'عصير تفاح طبيعي' })
    @IsNotEmpty({ message: 'اسم المادة مطلوب' })
    @IsString()
    name_ar: string;

    @ApiPropertyOptional({ example: '625987654321' })
    @IsOptional()
    @IsString()
    barcode?: string;

    @ApiProperty({ example: 10, description: 'الكمية' })
    @IsNumber()
    @Min(0.001)
    quantity: number;

    @ApiProperty({ example: 5000, description: 'سعر الكلفة' })
    @IsNumber()
    @Min(0)
    unit_cost: number;
}