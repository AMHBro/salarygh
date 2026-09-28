import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsUUID, IsNumber, IsEnum, IsOptional, IsString, Min } from 'class-validator';
import { payment_method_enum } from '@prisma/client';

export class CreateSupplierPaymentDto {
    @ApiPropertyOptional({ description: 'الصندوق الذي خرجت منه الدفعة النقدية' })
    @IsOptional()
    @IsUUID()
    cashbox_id?: string;
    @ApiProperty({ example: 'uuid-supplier-id' })
    @IsNotEmpty({ message: 'المورد مطلوب' })
    @IsUUID()
    supplier_id: string;

    @ApiProperty({ example: 'uuid-purchase-invoice-id', description: 'فاتورة الشراء المطلوب تسديدها' })
    @IsNotEmpty()
    @IsUUID()
    invoice_id: string;

    @ApiProperty({ example: 500000, description: 'المبلغ المسدد بالدينار' })
    @IsNumber()
    @Min(1, { message: 'المبلغ يجب أن يكون أكبر من الصفر' })
    amount: number;

    @ApiProperty({ description: 'UUID ثابت للعملية لمنع تكرار السند عند إعادة الطلب' })
    @IsNotEmpty()
    @IsUUID()
    idempotency_key: string;

    @ApiProperty({ enum: payment_method_enum, example: payment_method_enum.CASH })
    @IsNotEmpty()
    @IsEnum(payment_method_enum)
    payment_method: payment_method_enum;

    @ApiPropertyOptional({ example: 'دفعة سداد نقدية' })
    @IsOptional()
    @IsString()
    notes?: string;
}
