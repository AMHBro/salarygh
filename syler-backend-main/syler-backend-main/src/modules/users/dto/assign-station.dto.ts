import { ApiPropertyOptional } from '@nestjs/swagger';
import {
    IsBoolean,
    IsOptional,
    IsString,
    IsUUID,
    MinLength,
} from 'class-validator';

export class AssignStationDto {
    @ApiPropertyOptional()
    @IsOptional()
    @IsUUID('4')
    role_id?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsBoolean()
    is_active?: boolean;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    @MinLength(6)
    password?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    full_name?: string;
}
