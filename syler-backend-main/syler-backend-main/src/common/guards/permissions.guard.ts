import { Injectable, CanActivate, ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { PERMISSIONS_KEY, RequiredPermission } from '../decorators/permissions.decorator';

@Injectable()
export class PermissionsGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredPermissions = this.reflector.getAllAndOverride<(string | RequiredPermission)[]>(
      PERMISSIONS_KEY,
      [context.getHandler(), context.getClass()],
    );

    if (!requiredPermissions || requiredPermissions.length === 0) {
      return true;
    }

    const { user } = context.switchToHttp().getRequest();
    if (!user) {
      throw new ForbiddenException('المستخدم غير مصرح له');
    }

    const userRole = user.roles?.name || user.role;

    // ADMIN / SUPER_ADMIN has full permissions on everything
    if (userRole === 'ADMIN' || userRole === 'SUPER_ADMIN') {
      return true;
    }

    const userPerms = this.readPermissions(user);

    const hasAll = requiredPermissions.every((req) => {
      const required = typeof req === 'string' ? req : `${req.resource}_${req.action}`;
      return userPerms.some((permission) => this.matches(permission, required));
    });

    if (!hasAll) {
      throw new ForbiddenException('ليس لديك الصلاحيات الكافية لتنفيذ هذا الإجراء');
    }

    return true;
  }

  private readPermissions(user: any): Array<{ resource: string; action: string }> {
    const fromRole =
      user.roles?.role_permissions?.map((rp: any) => ({
        resource: rp.permissions?.resource,
        action: rp.permissions?.action,
      })) ?? [];

    const fromToken = Array.isArray(user.permissions)
      ? user.permissions.map((code: string) => this.splitCode(code))
      : [];

    return [...fromRole, ...fromToken].filter(
      (permission) => permission.resource && permission.action,
    );
  }

  private matches(
    permission: { resource: string; action: string },
    required: string,
  ): boolean {
    const resource = permission.resource;
    const action = permission.action;
    if (resource === '*' || required === `${resource}_${action}` || required === `${resource}:${action}`) {
      return true;
    }

    const colon = required.split(':');
    if (colon.length === 2) {
      return (resource === colon[0] || resource === '*') &&
        (action === colon[1] || action === '*' || colon[1] === '*');
    }

    const split = this.splitCode(required);
    return (resource === split.resource || resource === '*') &&
      (action === split.action || action === '*' || split.action === '*');
  }

  private splitCode(code: string): { resource: string; action: string } {
    if (code.includes(':')) {
      const [resource, action] = code.split(':');
      return { resource, action: action || '*' };
    }
    const index = code.lastIndexOf('_');
    if (index <= 0) {
      return { resource: code, action: '*' };
    }
    return {
      resource: code.slice(0, index),
      action: code.slice(index + 1),
    };
  }
}
