import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
    IsNumber,
    IsPositive,
    IsUUID,
} from 'class-validator';

export class AddCartItemDto {
    @ApiProperty({
        example: 'uuid',
    })
    @IsUUID()
    variant_id: string;

    @ApiProperty({
        example: 'uuid',
    })
    @IsUUID()
    unit_id: string;

    @ApiProperty({
        example: 2,
        minimum: 0.001,
    })
    @Type(() => Number)
    @IsNumber()
    @IsPositive()
    quantity: number;
}