import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
    IsNotEmpty,
    IsUUID,
    IsEnum,
    IsNumber,
    IsArray,
    ValidateNested,
    IsOptional,
    IsString,
    IsIn,
    Min,
} from 'class-validator';
import { Type } from 'class-transformer';
import { purchase_payment_enum } from '@prisma/client';

export class PurchaseItemDto {
    @ApiProperty({ example: 'uuid-product-variant-id' })
    @IsNotEmpty({ message: 'معرف الشكل/المنتج مطلوب' })
    @IsUUID()
    variant_id: string;

    @ApiProperty({ example: 'uuid-unit-of-measure-id' })
    @IsNotEmpty({ message: 'وحدة القياس مطلوبة' })
    @IsUUID()
    unit_id: string;

    @ApiProperty({ example: 10, description: 'الكمية المشتراة' })
    @IsNumber()
    @Min(0.001, { message: 'الكمية يجب أن تكون أكبر من صفر' })
    quantity: number;

    @ApiProperty({ example: 8500, description: 'سعر كلفة الوحدة' })
    @IsNumber()
    @Min(0)
    unit_cost: number;

    @ApiPropertyOptional({ example: 0, description: 'نسبة الخصم على السطر %' })
    @IsOptional()
    @IsNumber()
    @Min(0)
    discount_percent?: number;
}

export class CreatePurchaseInvoiceDto {
    @ApiPropertyOptional({
        example: 'fd3ee431-2f10-4069-aff2-0bd0ab58f82e',
        description: 'المعرف المحلي للفاتورة (Offline-First) — اختياري، يُستخدم كـ id للفاتورة في السيرفر إن لم يكن مستخدماً مسبقاً',
    })
    @IsOptional()
    @IsUUID('4', { message: 'معرف الفاتورة يجب أن يكون بصيغة UUID v4 صالحة' })
    id?: string;

    @ApiProperty({ example: 'uuid-supplier-id', description: 'معرف المورد' })
    @IsNotEmpty({ message: 'المورد مطلوب' })
    @IsUUID()
    supplier_id: string;

    @ApiProperty({ example: 'uuid-warehouse-id', description: 'المخزن المستلم' })
    @IsNotEmpty({ message: 'المخزن مطلوب' })
    @IsUUID()
    warehouse_id: string;

    @ApiProperty({ enum: purchase_payment_enum, example: purchase_payment_enum.CASH })
    @IsNotEmpty({ message: 'طريقة الدفع مطلوبة' })
    @IsEnum(purchase_payment_enum)
    payment_type: purchase_payment_enum;

    @ApiPropertyOptional({ example: 0, description: 'مبلغ الخصم الإجمالي على الفاتورة' })
    @IsOptional()
    @IsNumber()
    @Min(0)
    discount_amount?: number;

    @ApiPropertyOptional({ example: 85000, description: 'المبلغ المدفوع فعلياً (في حال الدفع الجزئي أو النقدي)' })
    @IsOptional()
    @IsNumber()
    @Min(0)
    paid_amount?: number;

    @ApiPropertyOptional({ example: 'فاتورة توريد مواد غذائية' })
    @IsOptional()
    @IsString()
    notes?: string;

    @ApiPropertyOptional({
        enum: ['IQD', 'USD'],
        example: 'IQD',
        description: 'عملة الأرقام المرسلة. عند USD تُحوَّل الكلفة والخصم والمدفوع إلى الدينار مرة واحدة.',
    })
    @IsOptional()
    @IsIn(['IQD', 'USD'])
    currency?: 'IQD' | 'USD';

    @ApiPropertyOptional({
        example: 1500,
        description: 'دينار لكل دولار، مطلوب عندما تكون العملة USD',
    })
    @IsOptional()
    @IsNumber()
    @Min(0)
    exchange_rate?: number;

    @ApiProperty({ type: [PurchaseItemDto], description: 'قائمة المواد المشتراة' })
    @IsArray()
    @ValidateNested({ each: true })
    @Type(() => PurchaseItemDto)
    items: PurchaseItemDto[];
}