import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
    IsNumber,
    IsPositive,
} from 'class-validator';

export class UpdateCartItemDto {
    @ApiProperty({
        example: 5,
        minimum: 0.001,
    })
    @Type(() => Number)
    @IsNumber()
    @IsPositive()
    quantity: number;
}