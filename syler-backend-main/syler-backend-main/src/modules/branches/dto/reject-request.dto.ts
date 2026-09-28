import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString } from 'class-validator';

export class RejectRequestDto {
    @ApiProperty({ example: 'البيانات غير مكتملة أو الموقع الجغرافي غير محدد بدقة' })
    @IsNotEmpty({ message: 'سبب الرفض إلزامي' })
    @IsString()
    rejection_reason: string;
}