import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsNumber, Min, MaxLength } from 'class-validator';

export class CreateRepresentativeDto {
  @ApiProperty({ example: 'أحمد علي' })
  @IsNotEmpty({ message: 'اسم المندوب مطلوب' })
  @IsString()
  name: string;

  @ApiProperty({ example: 'ahmed.rep' })
  @IsNotEmpty({ message: 'اسم المستخدم مطلوب' })
  @IsString()
  username: string;

  @ApiPropertyOptional({ example: 'password123' })
  @IsOptional()
  @IsString()
  password?: string;

  @ApiProperty({ example: '07701234567' })
  @IsNotEmpty({ message: 'رقم الهاتف مطلوب' })
  @IsString()
  phone: string;

  @ApiProperty({ example: 5, description: 'العمولة بالدينار لكل قائمة' })
  @IsNumber()
  @Min(0)
  commission_rate: number;

  @ApiPropertyOptional({
    example: 'wholesale,representative',
    description: 'أسعار البيع المسموحة للمندوب',
  })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  allowed_prices?: string;

  @ApiPropertyOptional({ example: 'المكتب الرئيسي' })
  @IsOptional()
  @IsString()
  office_name?: string;

  @ApiPropertyOptional({ example: '07800000001' })
  @IsOptional()
  @IsString()
  office_phone?: string;

  @ApiPropertyOptional({ example: 'بغداد - المنصور' })
  @IsOptional()
  @IsString()
  office_address?: string;

  @ApiPropertyOptional({ example: 'https://maps.google.com/?q=33.3152,44.3661' })
  @IsOptional()
  @IsString()
  location_url?: string;

  @ApiPropertyOptional({
    example: 0,
    description: 'سقف الذمة بالدينار. 0 يعني بدون سقف',
  })
  @IsOptional()
  @IsNumber()
  @Min(0)
  max_debt_limit?: number;
}
