import { ApiProperty } from '@nestjs/swagger';
import { IsArray, IsUUID } from 'class-validator';

export class AssignKeepersDto {
    @ApiProperty({ example: ['uuid-user-1', 'uuid-user-2'] })
    @IsArray()
    @IsUUID('4', { each: true })
    keeper_ids: string[];
}