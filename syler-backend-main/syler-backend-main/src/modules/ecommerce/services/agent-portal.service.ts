import {
    Injectable,
    UnauthorizedException,
    BadRequestException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { rep_status_enum, sales_status_enum } from '@prisma/client';
import * as bcrypt from 'bcrypt';

import { PrismaService } from 'src/prisma/prisma.service';
import { readAllowedPrices } from '../../representatives/allowed-prices';

@Injectable()
export class AgentPortalService {
    constructor(
        private readonly prisma: PrismaService,
        private readonly jwtService: JwtService,
        private readonly configService: ConfigService,
    ) {}

    async login(username: string, password: string) {
        const cleanUsername = username.trim();
        const user = await this.prisma.users.findUnique({
            where: { username: cleanUsername },
        });
        if (!user) {
            throw new UnauthorizedException('اسم المستخدم أو كلمة المرور غير صحيحة');
        }

        const matches = await bcrypt.compare(password, user.password_hash);
        if (!matches) {
            throw new UnauthorizedException('اسم المستخدم أو كلمة المرور غير صحيحة');
        }

        const representative = await this.prisma.representatives.findUnique({
            where: { user_id: user.id },
        });
        if (!representative || representative.status !== rep_status_enum.ACTIVE) {
            throw new UnauthorizedException('هذا الحساب ليس حساب مندوب فعّال');
        }

        const payload = {
            sub: user.id,
            email: user.email,
            role: 'representative',
        };
        const accessToken = this.jwtService.sign(payload, {
            expiresIn: (this.configService.get<string>('JWT_ACCESS_TOKEN_EXPIRES_IN') || '15m') as any,
        });

        return {
            accessToken,
            representative: {
                ...this._profile(representative, user.username),
                allowed_prices: await readAllowedPrices(
                    this.prisma,
                    representative.id,
                ),
            },
        };
    }

    async account(userId: string) {
        const representative = await this._requireRep(userId);
        const company = await this.prisma.companies.findFirst({
            orderBy: { created_at: 'asc' },
        });
        const invoices = await this.prisma.sales_invoices.findMany({
            where: {
                rep_id: representative.id,
                status: { not: sales_status_enum.CANCELLED },
            },
            include: {
                customers: { select: { name: true } },
            },
            orderBy: { invoice_date: 'desc' },
            take: 40,
        });

        const totalSales = invoices.reduce((sum, invoice) => sum + Number(invoice.total), 0);
        const debt = invoices.reduce((sum, invoice) => sum + Number(invoice.due_amount), 0);
        const rate = Number(representative.commission_rate) || 0;
        const totalCommission = rate * invoices.length;
        const paidCommission = Number(representative.paid_commission) || 0;
        const remainingCommission = Math.max(0, totalCommission - paidCommission);

        return {
            company: {
                name: company?.name ?? '',
                phone: company?.phone ?? '',
                address: company?.address ?? '',
            },
            link: {
                ...this._profile(representative, representative.users?.username),
                allowed_prices: await readAllowedPrices(
                    this.prisma,
                    representative.id,
                ),
            },
            debt: Math.round(debt),
            profit: {
                rate,
                total: Math.round(totalCommission),
                paid: Math.round(paidCommission),
                remaining: Math.round(remainingCommission),
            },
            statement: invoices.map((invoice) => ({
                id: invoice.id,
                date: invoice.invoice_date,
                number: invoice.invoice_number,
                customer: invoice.customers?.name ?? '',
                total: Math.round(Number(invoice.total)),
                remaining: Math.round(Number(invoice.due_amount)),
            })),
        };
    }

    async createOffice(
        userId: string,
        input: { name: string; phone: string; address: string },
    ) {
        const representative = await this._requireRep(userId);
        const name = input.name.trim();
        const phone = input.phone.trim();
        const address = input.address.trim();
        if (name.length < 2 || phone.length < 10 || address.length < 3) {
            throw new BadRequestException('أدخل اسم المكتب والعنوان ورقم هاتف مكتمل');
        }

        const existing = await this.prisma.customers.findUnique({
            where: { phone },
        });
        if (existing) {
            throw new BadRequestException('رقم الهاتف مستخدم لمكتب آخر');
        }

        const customer = await this.prisma.customers.create({
            data: {
                name,
                phone,
                address,
                notes: 'مكتب أضافه المندوب',
                assigned_rep_id: representative.id,
                created_by: userId,
                balance: 0,
                credit_limit: 0,
            },
        });

        return {
            id: customer.id,
            name: customer.name,
            phone: customer.phone,
            address: customer.address,
        };
    }

    private async _requireRep(userId: string) {
        const representative = await this.prisma.representatives.findUnique({
            where: { user_id: userId },
            include: { users: { select: { username: true } } },
        });
        if (!representative || representative.status !== rep_status_enum.ACTIVE) {
            throw new UnauthorizedException('هذا الحساب ليس حساب مندوب فعّال');
        }
        return representative;
    }

    private _profile(
        representative: {
            id: string;
            name: string;
            phone: string | null;
            office_name: string | null;
            office_address: string | null;
            office_phone: string | null;
            commission_rate: unknown;
            status: string;
            users?: { username: string | null } | null;
        },
        username?: string | null,
    ) {
        return {
            id: representative.id,
            name: representative.name,
            username: username ?? representative.users?.username ?? '',
            phone: representative.phone ?? '',
            office_name: representative.office_name ?? '',
            office_address: representative.office_address ?? '',
            office_phone: representative.office_phone ?? '',
            commission_rate: Number(representative.commission_rate) || 0,
            status: representative.status,
        };
    }
}
