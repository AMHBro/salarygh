import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
    IsEmail,
    IsNotEmpty,
    IsOptional,
    IsString,
    MinLength,
    IsUUID,
} from 'class-validator';

export class CreateUserDto {
    @ApiProperty({ example: 'أحمد علي', description: 'الاسم الكامل للمستخدم' })
    @IsString({ message: 'الاسم الكامل يجب أن يكون نصاً' })
    @IsNotEmpty({ message: 'الاسم الكامل مطلوب' })
    full_name: string;

    @ApiProperty({ example: 'ahmed_ali', description: 'اسم المستخدم الفريد' })
    @IsString({ message: 'اسم المستخدم يجب أن يكون نصاً' })
    @IsNotEmpty({ message: 'اسم المستخدم مطلوب' })
    username: string;

    @ApiProperty({ example: '123456', description: 'كلمة المرور (6 أحرف على الأقل)' })
    @IsString()
    @MinLength(6, { message: 'كلمة المرور يجب ألا تقل عن 6 أحرف' })
    @IsNotEmpty({ message: 'كلمة المرور مطلوبة' })
    password: string;

    @ApiProperty({ example: 'ahmed@sayler.app', description: 'البريد الإلكتروني' })
    @IsEmail({}, { message: 'صيغة البريد الإلكتروني غير صحيحة' })
    @IsNotEmpty({ message: 'البريد الإلكتروني مطلوب' })
    email: string;

    @ApiPropertyOptional({ example: '+9647701234567', description: 'رقم الهاتف' })
    @IsOptional()
    @IsString({ message: 'رقم الهاتف يجب أن يكون نصاً' })
    phone?: string;

    @ApiPropertyOptional({ example: 'uuid-role-id', description: 'معرف الدور / الصلاحية' })
    @IsOptional()
    @IsUUID('4', { message: 'معرف الدور يجب أن يكون UUID صحيح' })
    role_id?: string;

    @ApiPropertyOptional({ example: 'uuid-branch-id', description: 'معرف الفرع التابع له' })
    @IsOptional()
    @IsUUID('4', { message: 'معرف الفرع يجب أن يكون UUID صحيح' })
    branch_id?: string;
}
