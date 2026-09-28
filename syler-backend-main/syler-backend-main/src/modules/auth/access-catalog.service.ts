import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

const GRANTS: Array<{ resource: string; action: string; roles: string[] }> = [
    { resource: 'INVOICE', action: 'EDIT', roles: ['MANAGER', 'CASHIER', 'REP'] },
    { resource: 'CUSTOMER', action: 'EDIT', roles: ['MANAGER', 'CASHIER', 'REP'] },
    { resource: 'PRODUCT', action: 'EDIT', roles: ['MANAGER'] },
    { resource: 'PRICE', action: 'EDIT', roles: ['MANAGER'] },
    { resource: 'STOCK', action: 'EDIT', roles: ['MANAGER', 'WAREHOUSE'] },
    { resource: 'PURCHASE', action: 'EDIT', roles: ['MANAGER', 'WAREHOUSE'] },
    { resource: 'USER', action: 'MANAGE', roles: ['ADMIN'] },
];

@Injectable()
export class AccessCatalogService implements OnModuleInit {
    private readonly logger = new Logger(AccessCatalogService.name);

    constructor(private readonly prisma: PrismaService) {}

    async onModuleInit() {
        try {
            await this.ensure();
        } catch (error) {
            this.logger.warn(`تعذر تجهيز كتالوج الصلاحيات: ${error}`);
        }
    }

    async ensure() {
        for (const name of ['ADMIN', 'SUPER_ADMIN', 'MANAGER', 'CASHIER', 'WAREHOUSE', 'REP']) {
            await this.prisma.roles.upsert({
                where: { name },
                update: {},
                create: { name, is_system: true },
            });
        }

        for (const grant of GRANTS) {
            const permission = await this.prisma.permissions.upsert({
                where: {
                    resource_action: {
                        resource: grant.resource,
                        action: grant.action,
                    },
                },
                update: {},
                create: {
                    resource: grant.resource,
                    action: grant.action,
                    description: `${grant.resource}_${grant.action}`,
                },
            });

            for (const roleName of grant.roles) {
                const role = await this.prisma.roles.findUnique({
                    where: { name: roleName },
                });
                if (!role) {
                    continue;
                }

                await this.prisma.role_permissions.upsert({
                    where: {
                        role_id_permission_id: {
                            role_id: role.id,
                            permission_id: permission.id,
                        },
                    },
                    update: {},
                    create: {
                        role_id: role.id,
                        permission_id: permission.id,
                    },
                });
            }
        }
    }
}
