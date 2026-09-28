import { SetMetadata } from '@nestjs/common';

export const PERMISSIONS_KEY = 'permissions';
export interface RequiredPermission {
  resource: string;
  action: string;
}

export const RequirePermissions = (...permissions: (string | RequiredPermission)[]) =>
  SetMetadata(PERMISSIONS_KEY, permissions);

export const Permissions = RequirePermissions;
