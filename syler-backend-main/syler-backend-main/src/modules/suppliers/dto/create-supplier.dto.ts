import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsEmail, IsNumber, Min } from 'class-validator';


export class CreateSupplierDto {
    @ApiProperty({ example: 'شركة النور للتجارة' })
    @IsNotEmpty({ message: 'اسم المورد مطلوب' })
    @IsString()
    name: string;

    @ApiPropertyOptional({ example: '07701234567' })
    @IsOptional()
    @IsString()
    phone?: string;

    @ApiPropertyOptional({ example: 'supplier@alnoor.com' })
    @IsOptional()
    @IsEmail({}, { message: 'البريد الإلكتروني غير صالح' })
    email?: string;

    @ApiPropertyOptional({ example: 'بغداد - الشورجة' })
    @IsOptional()
    @IsString()
    address?: string;

    @ApiPropertyOptional({ example: 'TAX-987654' })
    @IsOptional()
    @IsString()
    tax_number?: string;

    @ApiPropertyOptional({ example: 10000000, description: 'الحد الائتماني بالدينار العراقي' })
    @IsOptional()
    @IsNumber()
    @Min(0)
    credit_limit?: number;

    @ApiPropertyOptional({ example: 'مورد رئيسي للمواد الغذائية' })
    @IsOptional()
    @IsString()
    notes?: string;
}