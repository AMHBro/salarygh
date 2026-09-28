import { Injectable } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { org_status_enum, warehouse_type_enum } from '@prisma/client';


@Injectable()
export class OrganizationService {
    constructor(private prisma: PrismaService) { }

    async getTree() {
        const company = await this.prisma.companies.findFirst();
        if (!company) return null;

        const branches = await this.prisma.branches.findMany({
            where: { status: { not: org_status_enum.INACTIVE } },
            include: {
                manager: { select: { id: true, username: true } },
                warehouses: {
                    where: {
                        status: { not: org_status_enum.INACTIVE },
                        type: warehouse_type_enum.MAIN
                    },
                    include: {
                        manager: { select: { id: true, username: true } },
                        sub_warehouses: {
                            where: { status: { not: org_status_enum.INACTIVE } },
                            include: {
                                manager: { select: { id: true, username: true } },
                                keepers: { include: { user: { select: { id: true, username: true } } } },
                            }
                        }
                    }
                }
            }
        });
        return {
            company: {
                id: company.id,
                name: company.name,
                logo_url: company.logo_url
            },
            branches
        }
    }

    async getPendingApprovals() {
        const [pendingBranches, pendingWarehouses] = await Promise.all([
            this.prisma.branches.findMany({
                where: { status: org_status_enum.PENDING_APPROVAL },
                include: { creator: { select: { id: true, username: true } } },
                orderBy: { updated_at: 'desc' },
            }),
            this.prisma.warehouses.findMany({
                where: { status: org_status_enum.PENDING_APPROVAL },
                include: {
                    branch: { select: { id: true, name: true } },
                    creator: { select: { id: true, username: true } },
                },
                orderBy: { updated_at: 'desc' },
            }),
        ]);

        return {
            total_pending: pendingBranches.length + pendingWarehouses.length,
            branches: pendingBranches,
            warehouses: pendingWarehouses,
        };
    }
}

