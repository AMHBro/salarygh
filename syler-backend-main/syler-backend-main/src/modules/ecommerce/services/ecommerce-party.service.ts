import {
    BadRequestException,
    Injectable,
    NotFoundException,
} from '@nestjs/common';

import {
    ecommerce_party_type_enum,
    Prisma,
} from '@prisma/client';

import { PrismaService } from '../../../prisma/prisma.service';

export interface EcommercePartySnapshot {
    partyType: ecommerce_party_type_enum;
    partyId: string | null;

    partyName: string;
    partyPhone: string | null;
    partyAddress: string | null;
}

@Injectable()
export class EcommercePartyService {
    constructor(
        private readonly prisma: PrismaService,
    ) { }

    async resolveParty(
        type: ecommerce_party_type_enum,
        partyId?: string | null,
        fallback?: {
            name?: string;
            phone?: string;
            address?: string;
        },
        db: Prisma.TransactionClient | PrismaService = this.prisma,
    ): Promise<EcommercePartySnapshot> {
        switch (type) {
            case ecommerce_party_type_enum.CUSTOMER:
                return this.resolveCustomer(
                    partyId,
                    db,
                );

            case ecommerce_party_type_enum.SUPPLIER:
                return this.resolveSupplier(
                    partyId,
                    db,
                );

            case ecommerce_party_type_enum.BRANCH:
                return this.resolveBranch(
                    partyId,
                    db,
                );

            case ecommerce_party_type_enum.REPRESENTATIVE:
                return this.resolveRepresentative(
                    partyId,
                    db,
                );

            case ecommerce_party_type_enum.OTHER:
                return this.resolveOther(
                    fallback,
                );

            default:
                throw new BadRequestException({
                    code: 'ECOMMERCE_INVALID_PARTY_TYPE',
                    message: 'نوع الجهة غير صالح',
                });
        }
    }

    private async resolveCustomer(
        partyId: string | null | undefined,
        db: Prisma.TransactionClient | PrismaService,
    ): Promise<EcommercePartySnapshot> {
        if (!partyId) {
            throw new BadRequestException({
                code: 'ECOMMERCE_PARTY_ID_REQUIRED',
                message: 'معرف الزبون مطلوب',
            });
        }

        const customer =
            await db.customers.findUnique({
                where: {
                    id: partyId,
                },
            });

        if (!customer) {
            throw new NotFoundException({
                code: 'ECOMMERCE_CUSTOMER_NOT_FOUND',
                message: 'الزبون غير موجود',
            });
        }

        return {
            partyType:
                ecommerce_party_type_enum.CUSTOMER,

            partyId:
                customer.id,

            partyName:
                customer.name,

            partyPhone:
                customer.phone ?? null,

            partyAddress:
                customer.address ?? null,
        };
    }

    private async resolveSupplier(
        partyId: string | null | undefined,
        db: Prisma.TransactionClient | PrismaService,
    ): Promise<EcommercePartySnapshot> {
        if (!partyId) {
            throw new BadRequestException({
                code: 'ECOMMERCE_PARTY_ID_REQUIRED',
                message: 'معرف المجهز مطلوب',
            });
        }

        const supplier =
            await db.suppliers.findUnique({
                where: {
                    id: partyId,
                },
                select: {
                    id: true,
                    name: true,
                    phone: true,
                    address: true,
                    is_active: true,
                },
            });

        if (!supplier) {
            throw new NotFoundException({
                code: 'ECOMMERCE_SUPPLIER_NOT_FOUND',
                message: 'المجهز غير موجود',
            });
        }

        if (!supplier.is_active) {
            throw new BadRequestException({
                code: 'ECOMMERCE_SUPPLIER_INACTIVE',
                message: 'المجهز غير فعال',
            });
        }

        return {
            partyType:
                ecommerce_party_type_enum.SUPPLIER,

            partyId:
                supplier.id,

            partyName:
                supplier.name,

            partyPhone:
                supplier.phone ?? null,

            partyAddress:
                supplier.address ?? null,
        };
    }

    private async resolveBranch(
        partyId: string | null | undefined,
        db: Prisma.TransactionClient | PrismaService,
    ): Promise<EcommercePartySnapshot> {
        if (!partyId) {
            throw new BadRequestException({
                code: 'ECOMMERCE_PARTY_ID_REQUIRED',
                message: 'معرف الفرع مطلوب',
            });
        }

        const branch =
            await db.branches.findUnique({
                where: {
                    id: partyId,
                },
                select: {
                    id: true,
                    name: true,
                    phone: true,
                    address: true,
                    status: true,
                },
            });

        if (!branch) {
            throw new NotFoundException({
                code: 'ECOMMERCE_BRANCH_NOT_FOUND',
                message: 'الفرع غير موجود',
            });
        }

        return {
            partyType:
                ecommerce_party_type_enum.BRANCH,

            partyId:
                branch.id,

            partyName:
                branch.name,

            partyPhone:
                branch.phone ?? null,

            partyAddress:
                branch.address ?? null,
        };
    }

    private async resolveRepresentative(
        partyId: string | null | undefined,
        db: Prisma.TransactionClient | PrismaService,
    ): Promise<EcommercePartySnapshot> {
        if (!partyId) {
            throw new BadRequestException({
                code: 'ECOMMERCE_PARTY_ID_REQUIRED',
                message: 'معرف المندوب مطلوب',
            });
        }

        const representative =
            await db.representatives.findUnique({
                where: {
                    id: partyId,
                },
                select: {
                    id: true,
                    name: true,
                    phone: true,
                    office_name: true,
                    office_phone: true,
                    office_address: true,
                    status: true,
                },
            });

        if (!representative) {
            throw new NotFoundException({
                code: 'ECOMMERCE_REPRESENTATIVE_NOT_FOUND',
                message: 'المندوب غير موجود',
            });
        }

        if (representative.status !== 'ACTIVE') {
            throw new BadRequestException({
                code: 'ECOMMERCE_REPRESENTATIVE_INACTIVE',
                message: 'المندوب غير فعال',
            });
        }

        return {
            partyType:
                ecommerce_party_type_enum.REPRESENTATIVE,

            partyId:
                representative.id,

            partyName:
                representative.office_name ??
                representative.name,

            partyPhone:
                representative.office_phone ??
                representative.phone ??
                null,

            partyAddress:
                representative.office_address ??
                null,
        };
    }

    private resolveOther(
        fallback?: {
            name?: string;
            phone?: string;
            address?: string;
        },
    ): EcommercePartySnapshot {
        if (!fallback?.name?.trim()) {
            throw new BadRequestException({
                code: 'ECOMMERCE_PARTY_NAME_REQUIRED',
                message: 'اسم الجهة مطلوب',
            });
        }

        return {
            partyType:
                ecommerce_party_type_enum.OTHER,

            partyId:
                null,

            partyName:
                fallback.name.trim(),

            partyPhone:
                fallback.phone?.trim() || null,

            partyAddress:
                fallback.address?.trim() || null,
        };
    }
}