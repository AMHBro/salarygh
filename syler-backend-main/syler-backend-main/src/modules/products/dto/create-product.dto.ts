import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
    IsNotEmpty,
    IsString,
    IsOptional,
    IsUUID,
    IsBoolean,
    IsNumber,
    Min,
    IsArray,
    ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';

// ─── مستويات أسعار الشكل الواحد ───────────────────────────────────────────────
export class ProductPricingDto {
    @ApiProperty({ example: 8500, description: 'سعر الكلفة' })
    @IsNumber()
    @Min(0)
    cost_price: number;

    @ApiProperty({ example: 9500, description: 'سعر المندوب' })
    @IsNumber()
    @Min(0)
    rep_price: number;

    @ApiProperty({ example: 10500, description: 'سعر الجملة' })
    @IsNumber()
    @Min(0)
    wholesale_price: number;

    @ApiProperty({ example: 12000, description: 'سعر المفرد' })
    @IsNumber()
    @Min(0)
    retail_price: number;
}

// ─── شكل/متغير واحد للمنتج المتعدد الأشكال ───────────────────────────────────
export class CreateProductVariantDto {
    @ApiPropertyOptional({ example: '625123456001', description: 'الباركود الخاص بهذا الشكل' })
    @IsOptional()
    @IsString()
    barcode?: string;

    @ApiPropertyOptional({ example: 'SKU-RED-XL', description: 'رمز الشكل الداخلي' })
    @IsOptional()
    @IsString()
    sku?: string;

    @ApiPropertyOptional({
        example: { color: 'أحمر', size: 'XL' },
        description: 'خصائص الشكل (لون، حجم، نكهة...)',
    })
    @IsOptional()
    attributes?: Record<string, any>;

    @ApiProperty({ type: ProductPricingDto, description: 'أسعار هذا الشكل' })
    @ValidateNested()
    @Type(() => ProductPricingDto)
    pricing: ProductPricingDto;
}

// ─── DTO الرئيسي لإنشاء منتج ─────────────────────────────────────────────────
export class CreateProductDto {
    @ApiProperty({ example: 'عصير برتقال طبيعي' })
    @IsNotEmpty({ message: 'اسم المنتج بالعربية مطلوب' })
    @IsString()
    name_ar: string;

    @ApiPropertyOptional({ example: 'Natural Orange Juice' })
    @IsOptional()
    @IsString()
    name_en?: string;

    @ApiPropertyOptional({ example: '625123456001' })
    @IsOptional()
    @IsString()
    barcode?: string;

    @ApiPropertyOptional({ example: 'PRD-001' })
    @IsOptional()
    @IsString()
    sku?: string;

    @ApiProperty({ example: 'uuid-of-category', description: 'معرف التصنيف' })
    @IsNotEmpty({ message: 'التصنيف مطلوب' })
    @IsUUID()
    category_id: string;

    @ApiProperty({ example: 'uuid-of-base-unit', description: 'وحدة القياس الأساسية (مثل قطعة)' })
    @IsNotEmpty({ message: 'وحدة القياس الأساسية مطلوبة' })
    @IsUUID()
    base_unit_id: string;

    @ApiPropertyOptional({ example: 'منتج ذو جودة عالية' })
    @IsOptional()
    @IsString()
    description?: string;

    @ApiPropertyOptional({ example: 5, description: 'الحد الأدنى للمخزون' })
    @IsOptional()
    @IsNumber()
    @Min(0)
    min_stock_level?: number;

    @ApiPropertyOptional({ default: false, description: 'هل للمنتج أشكال متعددة (ألوان، أحجام)؟' })
    @IsOptional()
    @IsBoolean()
    has_variants?: boolean;

    @ApiPropertyOptional({ default: false, description: 'هل يتتبع تاريخ الصلاحية؟' })
    @IsOptional()
    @IsBoolean()
    has_expiry?: boolean;

    @ApiPropertyOptional({ default: false, description: 'هل يتتبع الأرقام التسلسلية؟' })
    @IsOptional()
    @IsBoolean()
    has_serial?: boolean;

    @ApiPropertyOptional({ example: 'https://example.com/image.jpg' })
    @IsOptional()
    @IsString()
    image_url?: string;

    @ApiPropertyOptional({
        type: ProductPricingDto,
        description: 'الأسعار الأربعة — للمنتج البسيط (بدون has_variants)',
    })
    @IsOptional()
    @ValidateNested()
    @Type(() => ProductPricingDto)
    pricing?: ProductPricingDto;

    @ApiPropertyOptional({
        type: [CreateProductVariantDto],
        description: 'قائمة الأشكال — للمنتج المتعدد الأشكال (has_variants=true)',
    })
    @IsOptional()
    @IsArray()
    @ValidateNested({ each: true })
    @Type(() => CreateProductVariantDto)
    variants?: CreateProductVariantDto[];
}
