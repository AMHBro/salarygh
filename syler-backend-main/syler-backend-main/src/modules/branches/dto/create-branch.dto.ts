import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsEnum, IsUUID } from 'class-validator';
import { branch_type_enum } from '@prisma/client';

export class CreateBranchDto {
    @ApiPropertyOptional({ example: 'BR-001' })
    @IsOptional()
    @IsString()
    code?: string;

    @ApiProperty({ example: 'فرع الكرادة' })
    @IsNotEmpty({ message: 'اسم الفرع مطلوب' })
    @IsString()
    name: string;

    @ApiPropertyOptional({ enum: branch_type_enum, default: branch_type_enum.STANDARD })
    @IsOptional()
    @IsEnum(branch_type_enum)
    type?: branch_type_enum;

    @ApiPropertyOptional({ example: 'uuid-of-user' })
    @IsOptional()
    @IsUUID()
    manager_id?: string;

    @ApiPropertyOptional({ example: 'بغداد - الكرادة خارج' })
    @IsOptional()
    @IsString()
    address?: string;

    @ApiPropertyOptional({ example: '+9647712345678' })
    @IsOptional()
    @IsString()
    phone?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    notes?: string;
}