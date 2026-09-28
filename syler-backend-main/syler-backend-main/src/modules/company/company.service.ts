
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { UpdateCompanyDto } from './dto/update-company.dto';
// import { CreateCompanyDto } from './dto/create-company.dto';

@Injectable()
export class CompanyService {
    constructor(private prisma: PrismaService) { }

    async getCompany() {
        const company = await this.prisma.companies.findFirst();
        if (!company) {
            throw new NotFoundException('لم يتم ضبط بيانات الشركة بعد، يرجى تهيئة الشركة أولاً');
        }
        return company;
    }


    async createInitialCompany(dto: UpdateCompanyDto) {
        const exists = await this.prisma.companies.findFirst();
        if (exists) {
            throw new BadRequestException('بيانات الشركة موجودة بالفعل ولا يمكن إنشاء شركة ثانية (BR-ORG-001)');
        }
        return this.prisma.companies.create({
            data: {
                name: dto.name || 'الشركة الرئيسية',
                logo_url: dto.logo_url,
                address: dto.address,
                phone: dto.phone,
                email: dto.email,
                tax_number: dto.tax_number,
                settings: dto.settings || {},
            },
        });
    }

    async updateCompany(dto: UpdateCompanyDto) {
        const current = await this.getCompany();
        return this.prisma.companies.update({
            where: { id: current.id },
            data: { ...dto, updated_at: new Date() },
        });
    }

}

