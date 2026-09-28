import { Type } from 'class-transformer';
import {
    IsInt,
    IsOptional,
    IsString,
    IsUUID,
    Max,
    Min,
} from 'class-validator';

import { ApiPropertyOptional } from '@nestjs/swagger';

export class CatalogQueryDto {
    @ApiPropertyOptional({
        example: 1,
        default: 1,
    })
    @Type(() => Number)
    @IsInt()
    @Min(1)
    @IsOptional()
    page: number = 1;

    @ApiPropertyOptional({
        example: 20,
        default: 20,
        maximum: 100,
    })
    @Type(() => Number)
    @IsInt()
    @Min(1)
    @Max(100)
    @IsOptional()
    limit: number = 20;

    @ApiPropertyOptional({
        example: 'شامبو',
    })
    @IsString()
    @IsOptional()
    search?: string;

    @ApiPropertyOptional({
        example: 'uuid',
    })
    @IsUUID()
    @IsOptional()
    category_id?: string;
}