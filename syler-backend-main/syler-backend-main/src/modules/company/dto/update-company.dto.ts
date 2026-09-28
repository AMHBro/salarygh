import { ApiPropertyOptional } from "@nestjs/swagger";
import { IsOptional, IsString, IsEmpty, IsEmail, MinLength, MaxLength, ArrayNotContains, IsEnum }
    from 'class-validator';

export class UpdateCompanyDto {
    @ApiPropertyOptional({ example: 'شركة المسار للتجارة والتوزيع' })
    @IsOptional()
    @IsString()
    name?: string;

    @ApiPropertyOptional({ example: 'https://example.com/logo.png' })
    @IsOptional()
    @IsString()
    logo_url?: string;

    @ApiPropertyOptional({ example: 'بغداد - المنصور - شارع 14 رمضان' })
    @IsOptional()
    @IsString()
    address?: string;

    @ApiPropertyOptional({ example: '+9647700000000' })
    @IsOptional()
    @IsString()
    phone?: string;

    @ApiPropertyOptional({ example: 'info@sayler.app' })
    @IsOptional()
    @IsEmail()
    email?: string;

    @ApiPropertyOptional({ example: '123456789' })
    @IsOptional()
    @IsString()
    tax_number?: string;

    @ApiPropertyOptional({ example: { currency: 'IQD', decimal_places: 2 } })
    @IsOptional()
    settings?: any;
}