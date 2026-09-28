import {
    IsBoolean,
    IsEnum,
    IsNotEmpty,
    IsNumber,
    IsOptional,
    IsUUID,
    Min,
} from 'class-validator';

import {
    commission_type_enum,
} from '@prisma/client';

import {
    ApiProperty,
    ApiPropertyOptional,
} from '@nestjs/swagger';

export class UpdateEcommerceProductSettingDto {
    @ApiProperty({
        example: 'uuid',
        description: 'معرف وحدة القياس',
    })
    @IsUUID()
    @IsNotEmpty()
    unit_id: string;

    @ApiPropertyOptional({
        example: true,
        default: true,
    })
    @IsBoolean()
    @IsOptional()
    is_enabled?: boolean;

    @ApiProperty({
        enum: commission_type_enum,
        example: commission_type_enum.PERCENT,
    })
    @IsEnum(commission_type_enum)
    commission_type: commission_type_enum;

    @ApiProperty({
        example: 8,
        description: 'نسبة أو قيمة العمولة حسب commission_type',
    })
    @IsNumber()
    @Min(0)
    commission_value: number;

    @ApiPropertyOptional({
        example: 0,
        default: 0,
    })
    @IsNumber()
    @Min(0)
    @IsOptional()
    sort_order?: number;
}