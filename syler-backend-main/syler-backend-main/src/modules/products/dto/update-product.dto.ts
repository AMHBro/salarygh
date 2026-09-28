import { ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { IsISO8601, IsOptional } from 'class-validator';
import { CreateProductDto } from './create-product.dto';

export class UpdateProductDto extends PartialType(CreateProductDto) {
    @ApiPropertyOptional({
        description: 'وقت النسخة التي عدّلها الجهاز. إذا كانت أقدم من الخادم يُرجع 409',
    })
    @IsOptional()
    @IsISO8601()
    base_updated_at?: string;
}
