import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class CreateSupplierSheetDto {
    @ApiProperty({ example: 'قائمة أيلول' })
    @IsString()
    @IsNotEmpty()
    @MaxLength(200)
    title: string;

    @ApiProperty({ description: 'صورة بصيغة data URL' })
    @IsString()
    @IsNotEmpty()
    @MaxLength(1500000)
    image_url: string;
}
