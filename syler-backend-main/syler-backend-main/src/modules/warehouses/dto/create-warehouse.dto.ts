import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString, IsOptional, IsEnum, IsUUID, IsNumber } from 'class-validator';
import { warehouse_type_enum } from '@prisma/client';


export class CreateWarehouseDto {
    @ApiPropertyOptional({ example: 'WH-001' })
    @IsOptional()
    @IsString()
    code?: string;

    @ApiProperty({ example: 'المخزن الرئيسي - الكرادة' })
    @IsNotEmpty({ message: 'اسم المخزن مطلوب' })
    @IsString()
    name: string;

    @ApiProperty({ example: 'uuid-of-branch' })
    @IsNotEmpty({ message: 'معرف الفرع مطلوب' })
    @IsUUID()
    branch_id: string;

    @ApiPropertyOptional({ enum: warehouse_type_enum, default: warehouse_type_enum.SUB })
    @IsOptional()
    @IsEnum(warehouse_type_enum)
    type?: warehouse_type_enum;

    @ApiPropertyOptional({ description: 'المخزن الرئيسي الأب (إلزامي إذا كان المخزن فرعياً SUB)' })
    @IsOptional()
    @IsUUID()
    parent_warehouse_id?: string;

    @ApiPropertyOptional({ example: 'uuid-of-manager' })
    @IsOptional()
    @IsUUID()
    manager_id?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    address?: string;

    @ApiPropertyOptional({ example: 1000.0 })
    @IsOptional()
    @IsNumber()
    capacity?: number;
}