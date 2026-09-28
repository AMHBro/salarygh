import {
    IsNotEmpty,
    IsString,
    MaxLength,
} from 'class-validator';

import { ApiProperty } from '@nestjs/swagger';

export class CancelOrderDto {
    @ApiProperty({
        example: 'تم إدخال الطلب بالخطأ',
    })
    @IsString()
    @IsNotEmpty()
    @MaxLength(1000)
    reason: string;
}