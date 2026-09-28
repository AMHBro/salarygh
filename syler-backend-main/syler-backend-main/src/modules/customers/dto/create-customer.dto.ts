import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsEmail, IsNumber, IsEnum, Min } from 'class-validator';
import { customer_type_enum } from '@prisma/client';

export class CreateCustomerDto {
  @ApiProperty({ example: 'أحمد محمد' })
  @IsNotEmpty({ message: 'اسم الزبون مطلوب' })
  @IsString()
  name: string;

  @ApiPropertyOptional({ example: '07701234567' })
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiPropertyOptional({ example: 'ahmed@example.com' })
  @IsOptional()
  @IsEmail({}, { message: 'البريد الإلكتروني غير صالح' })
  email?: string;

  @ApiPropertyOptional({ example: 'بغداد - المنصور' })
  @IsOptional()
  @IsString()
  address?: string;

  @ApiPropertyOptional({ enum: customer_type_enum, example: customer_type_enum.RETAIL })
  @IsOptional()
  @IsEnum(customer_type_enum)
  type?: customer_type_enum;

  @ApiPropertyOptional({ example: 5000000, description: 'الحد الائتماني بالدينار' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  credit_limit?: number;

  @ApiPropertyOptional({ example: 'زبون دائم' })
  @IsOptional()
  @IsString()
  notes?: string;
}
