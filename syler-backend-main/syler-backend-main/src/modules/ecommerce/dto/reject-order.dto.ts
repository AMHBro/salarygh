import {
    IsNotEmpty,
    IsString,
    MaxLength,
} from 'class-validator';

import { ApiProperty } from '@nestjs/swagger';

export class RejectOrderDto {
    @ApiProperty({
        example: 'الطلب غير متوفر حالياً',
    })
    @IsString()
    @IsNotEmpty()
    @MaxLength(1000)
    reason: string;
}