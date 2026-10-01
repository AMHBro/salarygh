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
  IsBoolean,
  MaxLength,
  Min,
} from 'class-validator';
import { Type } from 'class-transformer';
import { price_type_enum, sales_payment_enum } from '@prisma/client';

export class SaleItemDto {
  @ApiProperty({ example: 'uuid-product-variant-id', description: 'معرف المنتج/الشكل' })
  @IsNotEmpty({ message: 'المنتج مطلوب' })
  @IsUUID()
  variant_id: string;

  @ApiProperty({ example: 'uuid-unit-of-measure-id', description: 'وحدة البيع' })
  @IsNotEmpty({ message: 'وحدة القياس مطلوبة' })
  @IsUUID()
  unit_id: string;

  @ApiProperty({ example: 2, description: 'الكمية المباعة' })
  @IsNumber()
  @Min(0.001, { message: 'الكمية يجب أن تكون أكبر من الصفر' })
  quantity: number;

  @ApiProperty({ example: 12000, description: 'سعر بيع الوحدة' })
  @IsNumber()
  @Min(0)
  unit_price: number;

  @ApiPropertyOptional({ example: 0, description: 'نسبة الخصم على السطر %' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  discount_percent?: number;
}

export class CreateDirectSaleDto {
  @ApiPropertyOptional({
    example: 'uuid-customer-id',
    description: 'معرف الزبون المسجل (يتركه فارغاً للزبون النقدي العام)',
  })
  @IsOptional()
  @IsUUID()
  customer_id?: string;

  @ApiProperty({ example: 'uuid-warehouse-id', description: 'المخزن الذي تخرج منه البضاعة' })
  @IsNotEmpty({ message: 'المخزن مطلوب' })
  @IsUUID()
  warehouse_id: string;

  @ApiProperty({
    enum: price_type_enum,
    example: price_type_enum.RETAIL,
    description: 'نوع السعر: مفرد RETAIL أو جملة WHOLESALE',
  })
  @IsNotEmpty({ message: 'نوع السعر مطلوب' })
  @IsEnum(price_type_enum)
  price_type: price_type_enum;

  @ApiProperty({
    enum: sales_payment_enum,
    example: sales_payment_enum.CASH,
    description: 'طريقة الدفع: CASH, CREDIT, PARTIAL',
  })
  @IsNotEmpty({ message: 'طريقة الدفع مطلوبة' })
  @IsEnum(sales_payment_enum)
  payment_type: sales_payment_enum;

  @ApiPropertyOptional({ example: 0, description: 'مبلغ الخصم الإجمالي' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  discount_amount?: number;

  @ApiPropertyOptional({ example: 60000, description: 'المبلغ المدفوع كاش' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  paid_amount?: number;

  @ApiPropertyOptional({ example: 'فاتورة بيع مباشر' })
  @IsOptional()
  @IsString()
  notes?: string;

  @ApiPropertyOptional({
    example: '8f3c2a1e-6b4d-4c9a-9e2f-1a2b3c4d5e6f',
    description:
      'معرّف الفاتورة على الحاسبة. إعادة الإرسال بنفس القيمة تُرجع الفاتورة القائمة ولا تخصم المخزون مرة ثانية.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  idempotency_key?: string;

  @ApiPropertyOptional({
    type: [String],
    description: 'مفاتيح حجز الصالة لهذه الفاتورة. تُحرَّر داخل نفس عملية البيع.',
  })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  hold_keys?: string[];

  @ApiPropertyOptional({ description: 'يفعّل إعادة فحص سقف المندوب عند رفع طابور الأوفلاين' })
  @IsOptional()
  @IsBoolean()
  sync_revalidate?: boolean;

  @ApiPropertyOptional({ example: 'IQD', description: 'عملة الفاتورة. USD لا يُقاس على سقف الدينار' })
  @IsOptional()
  @IsString()
  currency?: string;

  @ApiProperty({ type: [SaleItemDto], description: 'قائمة المواد المباعة' })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SaleItemDto)
  items: SaleItemDto[];
}
