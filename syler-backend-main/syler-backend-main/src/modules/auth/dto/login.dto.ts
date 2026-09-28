import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString, MinLength } from "class-validator";

export class LoginDto {

    @IsString()
    @IsNotEmpty()
    @ApiProperty({ example: 'admin', description: 'اسم المستخدم أو البريد الإلكتروني' })
    email: string

    @IsString()
    @MinLength(6)
    @ApiProperty({ example: '123456', description: 'كلمة المرور' })
    password: string
}
