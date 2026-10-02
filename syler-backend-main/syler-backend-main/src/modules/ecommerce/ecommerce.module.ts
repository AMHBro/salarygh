import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule, ConfigService } from '@nestjs/config';

/**
 * ============================================================
 * External Modules
 * ============================================================
 */
import {
    DirectSalesModule,
} from '../direct-sales/direct-sales.module';
import { FloorModule } from '../floor/floor.module';

/**
 * ============================================================
 * Controllers
 * ============================================================
 */
import {
    CartController,
} from './controllers/cart.controller';

import {
    CheckoutController,
} from './controllers/checkout.controller';

import {
    EcommerceAdminController,
} from './controllers/ecommerce-admin.controller';

import {
    EcommerceHealthController,
} from './controllers/ecommerce-health.controller';

import {
    OrdersController,
} from './controllers/orders.controller';

import {
    StoreCatalogController,
} from './controllers/store-catalog.controller';

/**
 * ============================================================
 * Services
 * ============================================================
 */
import {
    CartService,
} from './services/cart.service';

import {
    CheckoutService,
} from './services/checkout.service';

import {
    EcommerceCatalogService,
} from './services/ecommerce-catalog.service';

import {
    EcommerceOrderService,
} from './services/ecommerce-order.service';

import {
    EcommercePartyService,
} from './services/ecommerce-party.service';

import {
    EcommercePricingService,
} from './services/ecommerce-pricing.service';

import {
    EcommerceProductService,
} from './services/ecommerce-product.service';

import {
    EcommerceStockService,
} from './services/ecommerce-stock.service';

import {
    OrderApprovalService,
} from './services/order-approval.service';

import {
    RepresentativeAccountsController,
} from './controllers/representative-accounts.controller';

import {
    RepresentativeVisitsController,
} from './controllers/representative-visits.controller';

import {
    RepresentativeAccountsService,
} from './services/representative-accounts.service';

import {
    RepresentativeLedgerService,
} from './services/representative-ledger.service';

import {
    RepresentativeVisitsService,
} from './services/representative-visits.service';

import {
    AgentPortalController,
} from './controllers/agent-portal.controller';

import {
    AgentPortalService,
} from './services/agent-portal.service';
@Module({
    /**
     * ============================================================
     * IMPORTS
     * ============================================================
     *
     * DirectSalesModule يوفر لنا:
     * SalesTransactionService
     *
     * والذي يستخدمه OrderApprovalService
     * عند قبول Ecommerce Order.
     */
    imports: [
        DirectSalesModule,
        FloorModule,
        JwtModule.registerAsync({
            imports: [ConfigModule],
            inject: [ConfigService],
            useFactory: (configService: ConfigService) => ({
                secret: configService.get<string>('JWT_SECRET'),
            }),
        }),
    ],

    /**
     * ============================================================
     * CONTROLLERS
     * ============================================================
     */
    controllers: [
        EcommerceHealthController,

        StoreCatalogController,

        CartController,

        CheckoutController,

        OrdersController,

        RepresentativeAccountsController,

        RepresentativeVisitsController,

        AgentPortalController,

        EcommerceAdminController,
    ],

    /**
     * ============================================================
     * PROVIDERS
     * ============================================================
     */
    providers: [
        EcommercePricingService,

        EcommerceStockService,

        EcommerceProductService,

        EcommerceCatalogService,

        CartService,

        EcommercePartyService,

        CheckoutService,

        EcommerceOrderService,

        RepresentativeAccountsService,

        RepresentativeLedgerService,

        RepresentativeVisitsService,

        AgentPortalService,

        OrderApprovalService,
    ],

    /**
     * ============================================================
     * EXPORTS
     * ============================================================
     *
     * ليس ضروري تصدير كل شيء،
     * لكن إبقاء الخدمات الرئيسية هنا مفيد
     * إذا احتاجها Module آخر لاحقاً.
     */
    exports: [
        EcommercePricingService,

        EcommerceStockService,

        EcommerceProductService,

        EcommerceCatalogService,

        CartService,

        EcommercePartyService,

        CheckoutService,

        EcommerceOrderService,

        RepresentativeAccountsService,

        OrderApprovalService,
    ],
})
export class EcommerceModule { }