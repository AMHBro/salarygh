import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaModule } from './prisma/prisma.module';
import { UsersModule } from './modules/users/users.module';
import { AuthModule } from './modules/auth/auth.module';
import { ConfigModule } from '@nestjs/config';
import { CompanyModule } from './modules/company/company.module';
import { BranchesModule } from './modules/branches/branches.module';
import { WarehousesModule } from './modules/warehouses/warehouses.module';
import { OrganizationModule } from './modules/organization/organization.module';
import { UnitsModule } from './modules/units/units.module';
import { CategoriesModule } from './modules/categories/categories.module';
import { ProductsModule } from './modules/products/products.module';
import { SuppliersModule } from './modules/suppliers/suppliers.module';
import { PurchasesModule } from './modules/purchases/purchases.module';
import { SupplierPaymentsModule } from './modules/supplier-payments/supplier-payments.module';
import { InventoryModule } from './modules/inventory/inventory.module';
import { CustomersModule } from './modules/customers/customers.module';
import { DirectSalesModule } from './modules/direct-sales/direct-sales.module';
import { RepresentativesModule } from './modules/representatives/representatives.module';
import { RepCustodyModule } from './modules/rep-custody/rep-custody.module';
import { EcommerceModule } from './modules/ecommerce/ecommerce.module';
import { ReportsModule } from './modules/reports/reports.module';
import { SyncModule } from './modules/sync/sync.module';
import { FloorModule } from './modules/floor/floor.module';
import { JwtAuthGuard } from './modules/auth/guards/jwt-auth.guard';
import { RolesGuard } from './common/guards/roles.guard';
import { PermissionsGuard } from './common/guards/permissions.guard';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    // M01 ── Auth & Users
    UsersModule,
    AuthModule,
    // M02 ── Company, Branches & Warehouses
    CompanyModule,
    BranchesModule,
    WarehousesModule,
    OrganizationModule,
    // M03 ── Products & Master Data
    UnitsModule,
    CategoriesModule,
    ProductsModule,
    // M04 ── Suppliers & Purchasing
    SuppliersModule,
    PurchasesModule,
    SupplierPaymentsModule,
    // M05 ── Inventory & Movements
    InventoryModule,
    // M06 ── Customers & Direct Sales POS
    CustomersModule,
    DirectSalesModule,
    // M07 ── Sales Representatives & Custody
    RepresentativesModule,
    RepCustodyModule,
    // M08 ── Ecommerce
    EcommerceModule,
    // M09 ── Reports
    ReportsModule,
    SyncModule,
    FloorModule,
  ],
  controllers: [AppController],
  providers: [
    AppService,
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
    { provide: APP_GUARD, useClass: PermissionsGuard },
  ],
})
export class AppModule { }



