import {
    IsEnum,
    IsOptional,
    IsString,
    IsUUID,
    MaxLength,
} from 'class-validator';

import {
    ApiProperty,
    ApiPropertyOptional,
} from '@nestjs/swagger';

import {
    ecommerce_party_type_enum,
    price_type_enum,
    sales_payment_enum,
} from '@prisma/client';

export class RepresentativeCheckoutDto {
    @ApiProperty({
        enum: ecommerce_party_type_enum,
        example: ecommerce_party_type_enum.CUSTOMER,
    })
    @IsEnum(ecommerce_party_type_enum)
    party_type: ecommerce_party_type_enum;

    @ApiPropertyOptional({
        example: '00000000-0000-0000-0000-000000000000',
    })
    @IsOptional()
    @IsUUID()
    party_id?: string;

    /**
     * تستخدم أساساً عندما party_type = OTHER
     */
    @ApiPropertyOptional({
        example: 'مكتب النور',
    })
    @IsOptional()
    @IsString()
    @MaxLength(300)
    party_name?: string;

    @ApiPropertyOptional({
        example: '07701234567',
    })
    @IsOptional()
    @IsString()
    @MaxLength(50)
    party_phone?: string;

    @ApiPropertyOptional({
        example: 'بغداد',
    })
    @IsOptional()
    @IsString()
    party_address?: string;

    @ApiProperty({
        enum: [
            sales_payment_enum.CASH,
            sales_payment_enum.CREDIT,
            sales_payment_enum.PARTIAL,
        ],
        example: sales_payment_enum.CASH,
    })
    @IsEnum(sales_payment_enum)
    payment_type: sales_payment_enum;

    @ApiPropertyOptional({
        enum: price_type_enum,
        example: price_type_enum.REP,
        description: 'نوع سعر القائمة عندما يملك المندوب أكثر من سعر',
    })
    @IsOptional()
    @IsEnum(price_type_enum)
    price_type?: price_type_enum;

    @ApiPropertyOptional({
        example: 'ملاحظات الطلب',
    })
    @IsOptional()
    @IsString()
    notes?: string;
}