import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsNumber, IsOptional, IsString, MinLength } from 'class-validator';

export class UpdateWarehouseDto {
    @ApiPropertyOptional({ example: 'المخزن الرئيسي' })
    @IsOptional()
    @IsString()
    @MinLength(1)
    name?: string;

    @ApiPropertyOptional({ example: 'WH-001' })
    @IsOptional()
    @IsString()
    code?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    address?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    notes?: string;

    @ApiPropertyOptional({ example: 1000 })
    @IsOptional()
    @IsNumber()
    capacity?: number;
}
