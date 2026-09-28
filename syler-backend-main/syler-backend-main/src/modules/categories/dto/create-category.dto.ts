import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsUUID, IsNumber } from 'class-validator';

export class CreateCategoryDto {
    @ApiProperty({ example: 'مواد غذائية' })
    @IsNotEmpty({ message: 'اسم التصنيف مطلوب' })
    @IsString()
    name_ar: string;

    @ApiPropertyOptional({ example: 'Food & Beverages' })
    @IsOptional()
    @IsString()
    name_en?: string;

    @ApiPropertyOptional({ example: 'uuid-parent-category', description: 'التصنيف الأب (فارغ إذا كان رئيسياً)' })
    @IsOptional()
    @IsUUID()
    parent_id?: string;

    @ApiPropertyOptional({ example: 'https://example.com/cat.png' })
    @IsOptional()
    @IsString()
    image_url?: string;

    @ApiPropertyOptional({ example: 0 })
    @IsOptional()
    @IsNumber()
    order_index?: number;
}