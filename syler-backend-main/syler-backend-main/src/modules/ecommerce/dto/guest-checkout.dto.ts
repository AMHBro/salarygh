import {
    IsEmail,
    IsNotEmpty,
    IsOptional,
    IsString,
    MaxLength,
} from 'class-validator';

import {
    ApiProperty,
    ApiPropertyOptional,
} from '@nestjs/swagger';

export class GuestCheckoutDto {
    @ApiProperty({
        example: 'علي محمد',
    })
    @IsString()
    @IsNotEmpty()
    @MaxLength(300)
    customer_name: string;

    @ApiProperty({
        example: '07701234567',
    })
    @IsString()
    @IsNotEmpty()
    @MaxLength(50)
    customer_phone: string;

    @ApiPropertyOptional({
        example: 'ali@example.com',
    })
    @IsOptional()
    @IsEmail()
    @MaxLength(150)
    customer_email?: string;

    @ApiProperty({
        example: 'بغداد - شارع فلسطين',
    })
    @IsString()
    @IsNotEmpty()
    customer_address: string;

    @ApiPropertyOptional({
        example: 'يرجى الاتصال قبل التوصيل',
    })
    @IsOptional()
    @IsString()
    notes?: string;
}