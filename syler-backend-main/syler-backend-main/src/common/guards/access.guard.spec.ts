import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { PERMISSIONS_KEY } from '../decorators/permissions.decorator';
import { ROLES_KEY } from '../decorators/roles.decorator';
import { PermissionsGuard } from './permissions.guard';
import { RolesGuard } from './roles.guard';

function contextFor(user: unknown): ExecutionContext {
    return {
        getHandler: () => ({}),
        getClass: () => ({}),
        switchToHttp: () => ({
            getRequest: () => ({ user }),
        }),
    } as ExecutionContext;
}

describe('حراس الصلاحيات', () => {
    it('يمنع الكاشير من تعديل منتج ويسمح له بتحرير فاتورة', () => {
        const reflector = {
            getAllAndOverride: (key: string) => {
                if (key === PERMISSIONS_KEY) {
                    return ['PRODUCT_EDIT'];
                }
                return undefined;
            },
        } as unknown as Reflector;

        const guard = new PermissionsGuard(reflector);
        const cashier = {
            role: 'CASHIER',
            permissions: ['INVOICE_EDIT', 'CUSTOMER_EDIT'],
        };

        expect(() => guard.canActivate(contextFor(cashier))).toThrow(ForbiddenException);

        const invoiceReflector = {
            getAllAndOverride: (key: string) => (key === PERMISSIONS_KEY ? ['INVOICE_EDIT'] : undefined),
        } as unknown as Reflector;
        const invoiceGuard = new PermissionsGuard(invoiceReflector);
        expect(invoiceGuard.canActivate(contextFor(cashier))).toBe(true);
    });

    it('يمرر المدير من حارس الأدوار ويمنع المندوب من إدارة الفروع', () => {
        const reflector = {
            getAllAndOverride: (key: string) => (key === ROLES_KEY ? ['ADMIN', 'MANAGER'] : undefined),
        } as unknown as Reflector;
        const guard = new RolesGuard(reflector);

        expect(guard.canActivate(contextFor({ role: 'MANAGER' }))).toBe(true);
        expect(() => guard.canActivate(contextFor({ role: 'REP' }))).toThrow(ForbiddenException);
    });

    it('يقرأ الصلاحية من جداول الدور عندما لا تكون داخل التوكن', () => {
        const reflector = {
            getAllAndOverride: () => ['STOCK_EDIT'],
        } as unknown as Reflector;
        const guard = new PermissionsGuard(reflector);
        const warehouse = {
            role: 'WAREHOUSE',
            roles: {
                name: 'WAREHOUSE',
                role_permissions: [
                    { permissions: { resource: 'STOCK', action: 'EDIT' } },
                ],
            },
        };

        expect(guard.canActivate(contextFor(warehouse))).toBe(true);
    });
});
