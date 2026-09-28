import { Injectable, NotAcceptableException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import * as bcrypt from "bcrypt";
const userAccessInclude = {
    roles: {
        include: {
            role_permissions: {
                include: {
                    permissions: true,
                },
            },
        },
    },
} as const;

@Injectable()
export class UsersService {

    constructor(private prisma: PrismaService) { }

    async findByUsername(username: string) {
        const user = await this.prisma.users.findUnique({
            where: {
                username: username
            },
            include: userAccessInclude

        });
        if (!user) {
            throw new NotFoundException("لا يوجد مستخدم بهذا الاسم");
        }

        return user;
    }

    async findById(id: string) {
        const user = await this.prisma.users.findUnique({
            where: {
                id: id
            },
            include: userAccessInclude,
        });
        if (!user) {
            throw new NotFoundException("لا يوجد مستخدم بهذا الرقم");
        }
        return user;
    }

    async create(data: CreateUserDto, createdBy?: string) {
        const { password, ...rest } = data;
        const salt = await bcrypt.genSalt(10);
        const hashedpassword = await bcrypt.hash(password, salt);
        const user = await this.prisma.users.create({
            data: {
                ...rest,
                password_hash: hashedpassword,
                created_by: createdBy,
            }
        });
        return user;
    }

    async getAllUsers() {
        const users = await this.prisma.users.findMany();
        return users;
    }

    async removeUser(id: string) {
        const user = await this.prisma.users.delete({
            where: {
                id: id
            }
        });
        return user;
    }

    async findByEmail(email: string) {
        const user = await this.prisma.users.findUnique({
            where: {
                email: email
            },
            include: userAccessInclude
        });
        if (!user) {
            throw new NotFoundException("لا يوجد مستخدم بهذا الايميل");
        }
        return user;
    }

    async comparePassword(password: string, hash: string): Promise<boolean> {
        return await bcrypt.compare(password, hash);
    }

    async updateUserById(id: string, data: UpdateUserDto) {
        const user = await this.prisma.users.update({
            where: {
                id: id
            },
            data: {
                ...data
            }
        });
        return user;
    }

    async listStations() {
        const rows = await this.prisma.users.findMany({
            include: { roles: true },
            orderBy: { created_at: 'desc' },
        });
        return rows.map((row) => this.publicStation(row));
    }

    async listRoles() {
        const rows = await this.prisma.roles.findMany({
            orderBy: { name: 'asc' },
        });
        const titles: Record<string, { title: string; detail: string }> = {
            ADMIN: { title: 'مسؤول', detail: 'كل الصلاحيات وإدارة دخول الحاسبات' },
            MANAGER: { title: 'مدير', detail: 'القوائم والأسعار والمنتجات والمشتريات والمخزن' },
            CASHIER: { title: 'صندوق', detail: 'البيع والزبائن' },
            WAREHOUSE: { title: 'مخزن', detail: 'المخزون والمشتريات' },
            REP: { title: 'مندوب', detail: 'البيع والزبائن' },
            SUPER_ADMIN: { title: 'مسؤول أعلى', detail: 'كل الصلاحيات' },
        };
        return rows
            .filter((row) => row.name !== 'SUPER_ADMIN')
            .map((row) => ({
                id: row.id,
                name: row.name,
                title: titles[row.name]?.title ?? row.name,
                detail: titles[row.name]?.detail ?? row.description ?? '',
            }));
    }

    async assignStation(id: string, data: {
        role_id?: string;
        is_active?: boolean;
        password?: string;
        full_name?: string;
    }) {
        const current = await this.findById(id);
        const next: Prisma.usersUpdateInput = {};
        if (data.full_name?.trim()) {
            next.full_name = data.full_name.trim();
        }
        if (typeof data.is_active === 'boolean') {
            next.is_active = data.is_active;
        }
        if (data.role_id) {
            next.roles = { connect: { id: data.role_id } };
        }
        if (data.password) {
            const salt = await bcrypt.genSalt(10);
            next.password_hash = await bcrypt.hash(data.password, salt);
        }
        const updated = await this.prisma.users.update({
            where: { id: current.id },
            data: next,
            include: userAccessInclude,
        });
        return this.publicStation(updated);
    }

    async activityFor(userId: string) {
        const [sales, purchases, movements, customers] = await Promise.all([
            this.prisma.sales_invoices.findMany({
                where: { created_by: { not: userId } },
                orderBy: { created_at: 'desc' },
                take: 40,
                include: {
                    users: { select: { full_name: true, username: true } },
                    customers: { select: { name: true } },
                },
            }),
            this.prisma.purchase_invoices.findMany({
                where: { created_by: { not: userId } },
                orderBy: { created_at: 'desc' },
                take: 40,
                include: {
                    creator: { select: { full_name: true, username: true } },
                    supplier: { select: { name: true } },
                },
            }),
            this.prisma.inventory_movements.findMany({
                where: { performed_by: { not: userId } },
                orderBy: { created_at: 'desc' },
                take: 40,
                include: {
                    users: { select: { full_name: true, username: true } },
                    warehouses: { select: { name: true } },
                },
            }),
            this.prisma.customers.findMany({
                where: { created_by: { not: userId } },
                orderBy: { created_at: 'desc' },
                take: 40,
                include: {
                    users: { select: { full_name: true, username: true } },
                },
            }),
        ]);

        const items = [
            ...sales.map((row) => ({
                id: row.id,
                kind: 'sale',
                title: `قائمة بيع ${row.invoice_number}`,
                detail: row.customers?.name ? `الزبون: ${row.customers.name}` : 'قائمة بيع',
                amount: row.total.toString(),
                at: row.created_at.toISOString(),
                actor: this.actorName(row.users),
            })),
            ...purchases.map((row) => ({
                id: row.id,
                kind: 'purchase',
                title: `شراء ${row.invoice_number}`,
                detail: row.supplier?.name ? `المورد: ${row.supplier.name}` : 'فاتورة شراء',
                amount: row.total.toString(),
                at: row.created_at.toISOString(),
                actor: this.actorName(row.creator),
            })),
            ...movements.map((row) => ({
                id: row.id,
                kind: 'stock',
                title: 'تغيير مخزن',
                detail: `${row.warehouses?.name ?? 'مخزن'} · ${row.movement_type} · ${row.quantity.toString()}`,
                amount: null,
                at: row.created_at.toISOString(),
                actor: this.actorName(row.users),
            })),
            ...customers.map((row) => ({
                id: row.id,
                kind: 'customer',
                title: `زبون ${row.name}`,
                detail: row.phone ?? 'إضافة زبون',
                amount: null,
                at: row.created_at.toISOString(),
                actor: this.actorName(row.users),
            })),
        ];

        items.sort((left, right) => right.at.localeCompare(left.at));
        return items.slice(0, 80);
    }

    private actorName(user: { full_name: string | null; username: string } | null) {
        const name = user?.full_name?.trim();
        if (name) return name;
        return user?.username ?? 'حاسبة أخرى';
    }

    private publicStation(row: {
        id: string;
        full_name: string | null;
        username: string;
        email: string | null;
        is_active: boolean;
        role_id: string | null;
        last_login: Date | null;
        roles?: { name: string } | null;
    }) {
        return {
            id: row.id,
            full_name: row.full_name,
            username: row.username,
            email: row.email,
            is_active: row.is_active,
            role_id: row.role_id,
            role_name: row.roles?.name ?? null,
            last_login: row.last_login,
        };
    }
}
