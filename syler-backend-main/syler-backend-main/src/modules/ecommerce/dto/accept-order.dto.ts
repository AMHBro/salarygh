import {
    IsNumber,
    IsOptional,
    IsUUID,
    Min,
} from 'class-validator';

import {
    ApiProperty,
    ApiPropertyOptional,
} from '@nestjs/swagger';

import {
    Type,
} from 'class-transformer';

export class AcceptOrderDto {
    @ApiProperty({
        description:
            'المخزن الذي سيتم تنفيذ عملية البيع منه',
        example:
            '00000000-0000-0000-0000-000000000000',
    })
    @IsUUID()
    warehouse_id: string;

    /**
     * يستخدم فقط إذا كان:
     *
     * payment_type = PARTIAL
     *
     * لأن Checkout الحالي يخزن نوع الدفع
     * لكنه لا يخزن المبلغ المدفوع الجزئي.
     */
    @ApiPropertyOptional({
        description:
            'المبلغ المدفوع في حالة PARTIAL',
        example:
            50000,
    })
    @IsOptional()
    @Type(() => Number)
    @IsNumber()
    @Min(0)
    paid_amount?: number;
}