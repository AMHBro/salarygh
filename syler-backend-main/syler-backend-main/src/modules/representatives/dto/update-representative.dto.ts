import { PartialType } from '@nestjs/swagger';
import { CreateRepresentativeDto } from './create-representative.dto';

export class UpdateRepresentativeDto extends PartialType(CreateRepresentativeDto) {}
