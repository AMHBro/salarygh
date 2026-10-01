-- Baseline of the schema already running on Railway.
-- Mark it applied with: prisma migrate resolve --applied 00000000000000_baseline
-- Do not execute this file against the live database.

-- CreateEnum
CREATE TYPE "account_type_enum" AS ENUM ('CUSTOMER', 'SUPPLIER', 'REPRESENTATIVE');

-- CreateEnum
CREATE TYPE "adjustment_type_enum" AS ENUM ('NONE', 'ADD', 'REDUCE');

-- CreateEnum
CREATE TYPE "cashbox_status_enum" AS ENUM ('OPEN', 'CLOSED');

-- CreateEnum
CREATE TYPE "commission_type_enum" AS ENUM ('PERCENT', 'FIXED');

-- CreateEnum
CREATE TYPE "custody_status_enum" AS ENUM ('PENDING', 'APPROVED', 'DISPATCHED', 'PARTIALLY_RETURNED', 'FULLY_RETURNED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "customer_type_enum" AS ENUM ('RETAIL', 'WHOLESALE');

-- CreateEnum
CREATE TYPE "movement_type_enum" AS ENUM ('IN', 'OUT', 'TRANSFER_OUT', 'TRANSFER_IN', 'ADJUST_ADD', 'ADJUST_REDUCE', 'RETURN_IN', 'RETURN_OUT');

-- CreateEnum
CREATE TYPE "payment_method_enum" AS ENUM ('CASH', 'BANK_TRANSFER', 'CHECK', 'POS_MACHINE');

-- CreateEnum
CREATE TYPE "price_type_enum" AS ENUM ('RETAIL', 'WHOLESALE', 'REP', 'COST');

-- CreateEnum
CREATE TYPE "purchase_payment_enum" AS ENUM ('CASH', 'CREDIT', 'PARTIAL');

-- CreateEnum
CREATE TYPE "purchase_status_enum" AS ENUM ('DRAFT', 'CONFIRMED', 'PARTIAL', 'PAID', 'CANCELLED');

-- CreateEnum
CREATE TYPE "rep_status_enum" AS ENUM ('ACTIVE', 'INACTIVE');

-- CreateEnum
CREATE TYPE "sales_payment_enum" AS ENUM ('CASH', 'CREDIT', 'PARTIAL', 'REP_CUSTODY');

-- CreateEnum
CREATE TYPE "sales_status_enum" AS ENUM ('DRAFT', 'PAID', 'PARTIAL', 'OVERDUE', 'CANCELLED', 'RETURNED');

-- CreateEnum
CREATE TYPE "serial_status_enum" AS ENUM ('IN_STOCK', 'SOLD', 'IN_CUSTODY', 'RETURNED');

-- CreateEnum
CREATE TYPE "stocktaking_status_enum" AS ENUM ('OPEN', 'COUNTING', 'PENDING_REVIEW', 'PENDING_VALUATION', 'APPROVED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "stocktaking_type_enum" AS ENUM ('BLIND', 'VISIBLE');

-- CreateEnum
CREATE TYPE "sync_operation_enum" AS ENUM ('CREATE', 'UPDATE', 'DELETE');

-- CreateEnum
CREATE TYPE "transfer_status_enum" AS ENUM ('PENDING', 'APPROVED', 'DISPATCHED', 'RECEIVED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "voucher_type_enum" AS ENUM ('RECEIPT', 'PAYMENT');

-- CreateEnum
CREATE TYPE "warehouse_type_enum" AS ENUM ('MAIN', 'SUB', 'VIRTUAL');

-- CreateEnum
CREATE TYPE "org_status_enum" AS ENUM ('DRAFT', 'PENDING_APPROVAL', 'ACTIVE', 'REJECTED', 'INACTIVE');

-- CreateEnum
CREATE TYPE "branch_type_enum" AS ENUM ('HEADQUARTERS', 'STANDARD');

-- CreateEnum
CREATE TYPE "ecommerce_order_source_enum" AS ENUM ('GUEST', 'REPRESENTATIVE');

-- CreateEnum
CREATE TYPE "ecommerce_order_status_enum" AS ENUM ('SUBMITTED', 'ACCEPTED', 'REJECTED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "ecommerce_party_type_enum" AS ENUM ('CUSTOMER', 'SUPPLIER', 'BRANCH', 'REPRESENTATIVE', 'OTHER');

-- CreateTable
CREATE TABLE "accounts_ledger" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "account_type" "account_type_enum" NOT NULL,
    "account_id" UUID NOT NULL,
    "total_debit" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "total_credit" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "balance" DECIMAL(15,2) DEFAULT (total_debit - total_credit),
    "last_transaction" TIMESTAMPTZ(6),

    CONSTRAINT "accounts_ledger_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "branches" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "company_id" UUID NOT NULL,
    "name" VARCHAR(200) NOT NULL,
    "address" TEXT,
    "phone" VARCHAR(20),
    "manager_id" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "code" VARCHAR(50) NOT NULL,
    "created_by" UUID,
    "notes" TEXT,
    "rejection_reason" TEXT,
    "status" "org_status_enum" NOT NULL DEFAULT 'DRAFT',
    "type" "branch_type_enum" NOT NULL DEFAULT 'STANDARD',

    CONSTRAINT "branches_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cashbox_sessions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "cashbox_id" UUID NOT NULL,
    "opened_by" UUID NOT NULL,
    "closed_by" UUID,
    "opened_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "closed_at" TIMESTAMPTZ(6),
    "opening_balance" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "closing_balance" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "total_sales" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "total_returns" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "status" "cashbox_status_enum" NOT NULL DEFAULT 'OPEN',

    CONSTRAINT "cashbox_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cashboxes" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "device_code" VARCHAR(100) NOT NULL,
    "cashbox_code" VARCHAR(100) NOT NULL,
    "name" VARCHAR(200),
    "branch_id" UUID,
    "assigned_user_id" UUID,
    "status" "cashbox_status_enum" NOT NULL DEFAULT 'CLOSED',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cashboxes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "categories" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name_ar" VARCHAR(200) NOT NULL,
    "name_en" VARCHAR(200),
    "parent_id" UUID,
    "level" INTEGER NOT NULL DEFAULT 0,
    "path" TEXT,
    "image_url" TEXT,
    "order_index" INTEGER NOT NULL DEFAULT 0,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "categories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "companies" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" VARCHAR(200) NOT NULL,
    "logo_url" TEXT,
    "address" TEXT,
    "phone" VARCHAR(20),
    "email" VARCHAR(100),
    "tax_number" VARCHAR(50),
    "settings" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "companies_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "customers" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" VARCHAR(300) NOT NULL,
    "phone" VARCHAR(20),
    "email" VARCHAR(150),
    "address" TEXT,
    "type" "customer_type_enum" NOT NULL DEFAULT 'RETAIL',
    "balance" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "credit_limit" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "assigned_rep_id" UUID,
    "notes" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_by" UUID,

    CONSTRAINT "customers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "device_sync_state" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "device_id" UUID NOT NULL,
    "user_id" UUID,
    "branch_id" UUID,
    "last_sync_at" TIMESTAMPTZ(6),
    "last_seq" BIGINT NOT NULL DEFAULT 0,
    "device_info" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "device_sync_state_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory_movements" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "movement_type" "movement_type_enum" NOT NULL,
    "variant_id" UUID NOT NULL,
    "warehouse_id" UUID NOT NULL,
    "quantity" DECIMAL(15,3) NOT NULL,
    "unit_cost" DECIMAL(15,4),
    "reference_type" VARCHAR(50),
    "reference_id" UUID,
    "batch_id" UUID,
    "serial_id" UUID,
    "notes" TEXT,
    "performed_by" UUID,
    "device_id" UUID,
    "version" INTEGER NOT NULL DEFAULT 1,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "inventory_movements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payment_vouchers" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "voucher_number" VARCHAR(50) NOT NULL,
    "amount" DECIMAL(15,2) NOT NULL,
    "payment_method" "payment_method_enum" NOT NULL DEFAULT 'CASH',
    "notes" TEXT,
    "voucher_date" DATE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_by" UUID,
    "invoice_id" UUID,
    "supplier_id" UUID,
    "customer_id" UUID,
    "cashbox_id" UUID,
    "sales_invoice_id" UUID,
    "voucher_type" "voucher_type_enum" NOT NULL DEFAULT 'PAYMENT',
    "idempotency_key" UUID,

    CONSTRAINT "payment_vouchers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "permissions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "resource" VARCHAR(100) NOT NULL,
    "action" VARCHAR(50) NOT NULL,
    "description" TEXT,

    CONSTRAINT "permissions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product_allowed_units" (
    "product_id" UUID NOT NULL,
    "unit_id" UUID NOT NULL,
    "can_buy" BOOLEAN NOT NULL DEFAULT true,
    "can_sell" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "product_allowed_units_pkey" PRIMARY KEY ("product_id","unit_id")
);

-- CreateTable
CREATE TABLE "product_batches" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "variant_id" UUID NOT NULL,
    "warehouse_id" UUID NOT NULL,
    "batch_number" VARCHAR(100),
    "expiry_date" DATE,
    "quantity" DECIMAL(15,3) NOT NULL DEFAULT 0,
    "unit_cost" DECIMAL(15,4) NOT NULL,
    "received_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "purchase_item_id" UUID,

    CONSTRAINT "product_batches_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product_prices" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "variant_id" UUID NOT NULL,
    "price_type" "price_type_enum" NOT NULL,
    "unit_id" UUID NOT NULL,
    "price" DECIMAL(15,4) NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "product_prices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product_variants" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "product_id" UUID NOT NULL,
    "sku" VARCHAR(100),
    "barcode" VARCHAR(100),
    "attributes" JSONB NOT NULL DEFAULT '{}',
    "weighted_avg_cost" DECIMAL(15,4) NOT NULL DEFAULT 0,
    "last_purchase_price" DECIMAL(15,4) NOT NULL DEFAULT 0,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "product_variants_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "products" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "sku" VARCHAR(100),
    "barcode" VARCHAR(100),
    "name_ar" VARCHAR(300) NOT NULL,
    "name_en" VARCHAR(300),
    "category_id" UUID,
    "description" TEXT,
    "base_unit_id" UUID NOT NULL,
    "has_variants" BOOLEAN NOT NULL DEFAULT false,
    "has_serial" BOOLEAN NOT NULL DEFAULT false,
    "has_expiry" BOOLEAN NOT NULL DEFAULT false,
    "image_url" TEXT,
    "images" JSONB NOT NULL DEFAULT '[]',
    "min_stock_level" DECIMAL(15,3) NOT NULL DEFAULT 0,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_by" UUID,

    CONSTRAINT "products_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "purchase_invoice_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "invoice_id" UUID NOT NULL,
    "variant_id" UUID NOT NULL,
    "unit_id" UUID NOT NULL,
    "batch_number" VARCHAR(100),
    "expiry_date" DATE,
    "quantity" DECIMAL(15,3) NOT NULL,
    "quantity_in_base_unit" DECIMAL(15,3) NOT NULL,
    "unit_cost" DECIMAL(15,4) NOT NULL,
    "cost_per_base_unit" DECIMAL(15,4) NOT NULL,
    "discount_percent" DECIMAL(5,2) NOT NULL DEFAULT 0,
    "total_price" DECIMAL(15,2) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "purchase_invoice_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "purchase_invoices" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "invoice_number" VARCHAR(50) NOT NULL,
    "supplier_id" UUID NOT NULL,
    "warehouse_id" UUID NOT NULL,
    "status" "purchase_status_enum" NOT NULL DEFAULT 'CONFIRMED',
    "payment_type" "purchase_payment_enum" NOT NULL DEFAULT 'CASH',
    "subtotal" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "discount_amount" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "tax_amount" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "total" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "paid_amount" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "due_amount" DECIMAL(15,2) DEFAULT (total - paid_amount),
    "notes" TEXT,
    "invoice_date" DATE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_by" UUID,

    CONSTRAINT "purchase_invoices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "rep_custody_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "custody_order_id" UUID NOT NULL,
    "variant_id" UUID NOT NULL,
    "serial_id" UUID,
    "quantity_sent" DECIMAL(15,3) NOT NULL,
    "quantity_sold" DECIMAL(15,3) NOT NULL DEFAULT 0,
    "quantity_returned" DECIMAL(15,3) NOT NULL DEFAULT 0,

    CONSTRAINT "rep_custody_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "rep_custody_orders" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "order_number" VARCHAR(50) NOT NULL,
    "rep_id" UUID NOT NULL,
    "warehouse_id" UUID NOT NULL,
    "status" "custody_status_enum" NOT NULL DEFAULT 'PENDING',
    "dispatch_date" TIMESTAMPTZ(6),
    "return_due_date" DATE,
    "notes" TEXT,
    "idempotency_key" VARCHAR(200),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_by" UUID,

    CONSTRAINT "rep_custody_orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "representatives" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "name" VARCHAR(300) NOT NULL,
    "phone" VARCHAR(20),
    "branch_id" UUID,
    "commission_rate" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "commission_type" "commission_type_enum" NOT NULL DEFAULT 'PERCENT',
    "status" "rep_status_enum" NOT NULL DEFAULT 'ACTIVE',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "location_url" TEXT,
    "office_address" TEXT,
    "office_name" VARCHAR(200),
    "office_phone" VARCHAR(50),
    "paid_commission" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "allowed_prices" VARCHAR(200) NOT NULL DEFAULT 'wholesale,representative,retail',
    "max_debt_limit" DECIMAL(15,2) NOT NULL DEFAULT 0,

    CONSTRAINT "representatives_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "role_permissions" (
    "role_id" UUID NOT NULL,
    "permission_id" UUID NOT NULL,

    CONSTRAINT "role_permissions_pkey" PRIMARY KEY ("role_id","permission_id")
);

-- CreateTable
CREATE TABLE "roles" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" VARCHAR(100) NOT NULL,
    "description" TEXT,
    "is_system" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "roles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sales_invoice_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "invoice_id" UUID NOT NULL,
    "variant_id" UUID NOT NULL,
    "batch_id" UUID,
    "serial_id" UUID,
    "unit_id" UUID NOT NULL,
    "quantity" DECIMAL(15,3) NOT NULL,
    "quantity_in_base_unit" DECIMAL(15,3) NOT NULL,
    "unit_price" DECIMAL(15,4) NOT NULL,
    "cost_per_base_unit" DECIMAL(15,4) NOT NULL,
    "discount_percent" DECIMAL(5,2) NOT NULL DEFAULT 0,
    "net_unit_price" DECIMAL(15,4) NOT NULL,
    "total_price" DECIMAL(15,2) NOT NULL,

    CONSTRAINT "sales_invoice_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sales_invoices" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "invoice_number" VARCHAR(50) NOT NULL,
    "cashbox_id" UUID,
    "session_id" UUID,
    "customer_id" UUID,
    "warehouse_id" UUID NOT NULL,
    "rep_id" UUID,
    "price_type" "price_type_enum" NOT NULL DEFAULT 'RETAIL',
    "payment_type" "sales_payment_enum" NOT NULL DEFAULT 'CASH',
    "status" "sales_status_enum" NOT NULL DEFAULT 'DRAFT',
    "subtotal" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "discount_amount" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "total" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "paid_amount" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "due_amount" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "notes" TEXT,
    "idempotency_key" VARCHAR(200) NOT NULL,
    "device_id" UUID,
    "version" INTEGER NOT NULL DEFAULT 1,
    "invoice_date" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "due_date" DATE,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_by" UUID,

    CONSTRAINT "sales_invoices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "serials" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "variant_id" UUID NOT NULL,
    "serial_no" VARCHAR(200) NOT NULL,
    "status" "serial_status_enum" NOT NULL DEFAULT 'IN_STOCK',
    "warehouse_id" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "serials_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stock_levels" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "variant_id" UUID NOT NULL,
    "warehouse_id" UUID NOT NULL,
    "quantity_on_hand" DECIMAL(15,3) NOT NULL DEFAULT 0,
    "quantity_reserved" DECIMAL(15,3) NOT NULL DEFAULT 0,
    "quantity_in_transit" DECIMAL(15,3) NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "stock_levels_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stocktaking_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "session_id" UUID NOT NULL,
    "variant_id" UUID NOT NULL,
    "batch_id" UUID,
    "serial_id" UUID,
    "system_quantity" DECIMAL(15,3) NOT NULL DEFAULT 0,
    "counted_quantity" DECIMAL(15,3) NOT NULL DEFAULT 0,
    "difference" DECIMAL(15,3) DEFAULT (counted_quantity - system_quantity),
    "unit_cost" DECIMAL(15,4),
    "adjustment_type" "adjustment_type_enum" NOT NULL DEFAULT 'NONE',

    CONSTRAINT "stocktaking_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stocktaking_sessions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "session_number" VARCHAR(50) NOT NULL,
    "warehouse_id" UUID NOT NULL,
    "type" "stocktaking_type_enum" NOT NULL DEFAULT 'BLIND',
    "status" "stocktaking_status_enum" NOT NULL DEFAULT 'OPEN',
    "snapshot_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "approved_at" TIMESTAMPTZ(6),
    "notes" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_by" UUID,
    "approved_by" UUID,

    CONSTRAINT "stocktaking_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "suppliers" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" VARCHAR(300) NOT NULL,
    "phone" VARCHAR(20),
    "email" VARCHAR(150),
    "address" TEXT,
    "tax_number" VARCHAR(50),
    "balance" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "credit_limit" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "notes" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_by" UUID,

    CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sym_channel" (
    "channel_id" VARCHAR(128) NOT NULL,
    "processing_order" INTEGER NOT NULL DEFAULT 1,
    "max_batch_size" INTEGER NOT NULL DEFAULT 1000,
    "max_batch_to_send" INTEGER NOT NULL DEFAULT 60,
    "max_data_to_route" INTEGER NOT NULL DEFAULT 100000,
    "extract_period_millis" INTEGER NOT NULL DEFAULT 0,
    "enabled" SMALLINT NOT NULL DEFAULT 1,
    "use_old_data_to_route" SMALLINT NOT NULL DEFAULT 1,
    "use_row_data_to_route" SMALLINT NOT NULL DEFAULT 1,
    "use_pk_data_to_route" SMALLINT NOT NULL DEFAULT 1,
    "reload_flag" SMALLINT NOT NULL DEFAULT 0,
    "file_sync_flag" SMALLINT NOT NULL DEFAULT 0,
    "contains_big_lob" SMALLINT NOT NULL DEFAULT 0,
    "batch_algorithm" VARCHAR(50) NOT NULL DEFAULT 'default',
    "data_loader_type" VARCHAR(50) NOT NULL DEFAULT 'default',
    "description" VARCHAR(255),
    "queue" VARCHAR(25) NOT NULL DEFAULT 'default',
    "max_network_kbps" DECIMAL(10,3) NOT NULL DEFAULT 0.000,
    "data_event_action" CHAR(1),
    "create_time" TIMESTAMP(6),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6),

    CONSTRAINT "sym_channel_pkey" PRIMARY KEY ("channel_id")
);

-- CreateTable
CREATE TABLE "sym_conflict" (
    "conflict_id" VARCHAR(50) NOT NULL,
    "source_node_group_id" VARCHAR(50) NOT NULL,
    "target_node_group_id" VARCHAR(50) NOT NULL,
    "target_channel_id" VARCHAR(128),
    "target_catalog_name" VARCHAR(255),
    "target_schema_name" VARCHAR(255),
    "target_table_name" VARCHAR(255),
    "detect_type" VARCHAR(128) NOT NULL,
    "detect_expression" TEXT,
    "resolve_type" VARCHAR(128) NOT NULL,
    "ping_back" VARCHAR(128) NOT NULL,
    "resolve_changes_only" SMALLINT DEFAULT 0,
    "resolve_row_only" SMALLINT DEFAULT 0,
    "create_time" TIMESTAMP(6) NOT NULL,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,

    CONSTRAINT "sym_conflict_pkey" PRIMARY KEY ("conflict_id")
);

-- CreateTable
CREATE TABLE "sym_context" (
    "name" VARCHAR(80) NOT NULL,
    "context_value" TEXT,
    "create_time" TIMESTAMP(6),
    "last_update_time" TIMESTAMP(6),

    CONSTRAINT "sym_context_pkey" PRIMARY KEY ("name")
);

-- CreateTable
CREATE TABLE "sym_data" (
    "data_id" BIGSERIAL NOT NULL,
    "table_name" VARCHAR(255) NOT NULL,
    "event_type" CHAR(1) NOT NULL,
    "row_data" TEXT,
    "pk_data" TEXT,
    "old_data" TEXT,
    "trigger_hist_id" INTEGER NOT NULL,
    "channel_id" VARCHAR(128),
    "transaction_id" VARCHAR(255),
    "source_node_id" VARCHAR(50),
    "external_data" VARCHAR(50),
    "node_list" VARCHAR(255),
    "is_prerouted" SMALLINT NOT NULL DEFAULT 0,
    "create_time" TIMESTAMP(6),

    CONSTRAINT "sym_data_pkey" PRIMARY KEY ("data_id")
);

-- CreateTable
CREATE TABLE "sym_data_event" (
    "data_id" BIGINT NOT NULL,
    "batch_id" BIGINT NOT NULL,
    "create_time" TIMESTAMP(6),

    CONSTRAINT "sym_data_event_pkey" PRIMARY KEY ("data_id","batch_id")
);

-- CreateTable
CREATE TABLE "sym_data_gap" (
    "start_id" BIGINT NOT NULL,
    "end_id" BIGINT NOT NULL,
    "is_expired" SMALLINT NOT NULL DEFAULT 0,
    "create_time" TIMESTAMP(6) NOT NULL,
    "last_update_hostname" VARCHAR(255),

    CONSTRAINT "sym_data_gap_pkey" PRIMARY KEY ("start_id","end_id")
);

-- CreateTable
CREATE TABLE "sym_extension" (
    "extension_id" VARCHAR(50) NOT NULL,
    "extension_type" VARCHAR(10) NOT NULL,
    "interface_name" VARCHAR(255),
    "node_group_id" VARCHAR(50) NOT NULL,
    "enabled" SMALLINT NOT NULL DEFAULT 1,
    "extension_order" INTEGER NOT NULL DEFAULT 1,
    "extension_text" TEXT,
    "create_time" TIMESTAMP(6),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6),

    CONSTRAINT "sym_extension_pkey" PRIMARY KEY ("extension_id")
);

-- CreateTable
CREATE TABLE "sym_extract_request" (
    "request_id" BIGINT NOT NULL,
    "source_node_id" VARCHAR(50) NOT NULL DEFAULT 'default',
    "node_id" VARCHAR(50) NOT NULL,
    "queue" VARCHAR(128),
    "status" CHAR(2),
    "start_batch_id" BIGINT NOT NULL,
    "end_batch_id" BIGINT NOT NULL,
    "trigger_id" VARCHAR(128) NOT NULL,
    "router_id" VARCHAR(50) NOT NULL,
    "load_id" BIGINT,
    "table_name" VARCHAR(255),
    "byte_count" BIGINT NOT NULL DEFAULT 0,
    "extracted_rows" BIGINT NOT NULL DEFAULT 0,
    "extracted_millis" BIGINT NOT NULL DEFAULT 0,
    "transferred_rows" BIGINT NOT NULL DEFAULT 0,
    "transferred_millis" BIGINT NOT NULL DEFAULT 0,
    "last_transferred_batch_id" BIGINT,
    "loaded_rows" BIGINT NOT NULL DEFAULT 0,
    "loaded_millis" BIGINT NOT NULL DEFAULT 0,
    "last_loaded_batch_id" BIGINT,
    "total_rows" BIGINT,
    "conflicted_rows" BIGINT NOT NULL DEFAULT 0,
    "loaded_time" TIMESTAMP(6),
    "parent_request_id" BIGINT NOT NULL DEFAULT 0,
    "extract_thread_id" INTEGER,
    "load_thread_id" INTEGER,
    "last_update_time" TIMESTAMP(6),
    "create_time" TIMESTAMP(6),
    "bulk_rows_loaded" BIGINT DEFAULT 0,

    CONSTRAINT "sym_extract_request_pkey" PRIMARY KEY ("request_id","source_node_id")
);

-- CreateTable
CREATE TABLE "sym_file_incoming" (
    "relative_dir" VARCHAR(255) NOT NULL,
    "file_name" VARCHAR(260) NOT NULL,
    "last_event_type" CHAR(1) NOT NULL,
    "node_id" VARCHAR(50) NOT NULL,
    "file_modified_time" BIGINT,

    CONSTRAINT "sym_file_incoming_pkey" PRIMARY KEY ("relative_dir","file_name")
);

-- CreateTable
CREATE TABLE "sym_file_snapshot" (
    "trigger_id" VARCHAR(128) NOT NULL,
    "router_id" VARCHAR(50) NOT NULL,
    "relative_dir" VARCHAR(255) NOT NULL,
    "file_name" VARCHAR(260) NOT NULL,
    "channel_id" VARCHAR(128) NOT NULL DEFAULT 'filesync',
    "reload_channel_id" VARCHAR(128) NOT NULL DEFAULT 'filesync_reload',
    "last_event_type" CHAR(1) NOT NULL,
    "crc32_checksum" BIGINT,
    "file_size" BIGINT,
    "file_modified_time" BIGINT,
    "last_update_time" TIMESTAMP(6) NOT NULL,
    "last_update_by" VARCHAR(50),
    "create_time" TIMESTAMP(6) NOT NULL,
    "external_file_data" VARCHAR(50),

    CONSTRAINT "sym_file_snapshot_pkey" PRIMARY KEY ("trigger_id","router_id","relative_dir","file_name")
);

-- CreateTable
CREATE TABLE "sym_file_trigger" (
    "trigger_id" VARCHAR(128) NOT NULL,
    "channel_id" VARCHAR(128) NOT NULL DEFAULT 'filesync',
    "reload_channel_id" VARCHAR(128) NOT NULL DEFAULT 'filesync_reload',
    "base_dir" VARCHAR(255) NOT NULL,
    "recurse" SMALLINT NOT NULL DEFAULT 1,
    "includes_files" VARCHAR(255),
    "excludes_files" VARCHAR(255),
    "sync_on_create" SMALLINT NOT NULL DEFAULT 1,
    "sync_on_modified" SMALLINT NOT NULL DEFAULT 1,
    "sync_on_delete" SMALLINT NOT NULL DEFAULT 1,
    "sync_on_ctl_file" SMALLINT NOT NULL DEFAULT 0,
    "delete_after_sync" SMALLINT NOT NULL DEFAULT 0,
    "before_copy_script" TEXT,
    "after_copy_script" TEXT,
    "create_time" TIMESTAMP(6) NOT NULL,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,
    "description" TEXT,

    CONSTRAINT "sym_file_trigger_pkey" PRIMARY KEY ("trigger_id")
);

-- CreateTable
CREATE TABLE "sym_file_trigger_router" (
    "trigger_id" VARCHAR(128) NOT NULL,
    "router_id" VARCHAR(50) NOT NULL,
    "enabled" SMALLINT NOT NULL DEFAULT 1,
    "initial_load_enabled" SMALLINT NOT NULL DEFAULT 1,
    "target_base_dir" VARCHAR(255),
    "conflict_strategy" VARCHAR(128) NOT NULL DEFAULT 'source_wins',
    "create_time" TIMESTAMP(6) NOT NULL,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,
    "description" TEXT,

    CONSTRAINT "sym_file_trigger_router_pkey" PRIMARY KEY ("trigger_id","router_id")
);

-- CreateTable
CREATE TABLE "sym_grouplet" (
    "grouplet_id" VARCHAR(50) NOT NULL,
    "grouplet_link_policy" CHAR(1) NOT NULL DEFAULT 'I',
    "description" VARCHAR(255),
    "create_time" TIMESTAMP(6) NOT NULL,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,

    CONSTRAINT "sym_grouplet_pkey" PRIMARY KEY ("grouplet_id")
);

-- CreateTable
CREATE TABLE "sym_grouplet_link" (
    "grouplet_id" VARCHAR(50) NOT NULL,
    "external_id" VARCHAR(255) NOT NULL,
    "create_time" TIMESTAMP(6) NOT NULL,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,

    CONSTRAINT "sym_grouplet_link_pkey" PRIMARY KEY ("grouplet_id","external_id")
);

-- CreateTable
CREATE TABLE "sym_incoming_batch" (
    "batch_id" BIGINT NOT NULL,
    "node_id" VARCHAR(50) NOT NULL,
    "channel_id" VARCHAR(128),
    "status" CHAR(2),
    "error_flag" SMALLINT DEFAULT 0,
    "sql_state" VARCHAR(10),
    "sql_code" INTEGER NOT NULL DEFAULT 0,
    "sql_message" TEXT,
    "last_update_hostname" VARCHAR(255),
    "last_update_time" TIMESTAMP(6),
    "create_time" TIMESTAMP(6),
    "summary" VARCHAR(255),
    "ignore_count" INTEGER NOT NULL DEFAULT 0,
    "byte_count" BIGINT NOT NULL DEFAULT 0,
    "load_flag" SMALLINT DEFAULT 0,
    "extract_count" INTEGER NOT NULL DEFAULT 0,
    "sent_count" INTEGER NOT NULL DEFAULT 0,
    "load_count" INTEGER NOT NULL DEFAULT 0,
    "reload_row_count" INTEGER NOT NULL DEFAULT 0,
    "other_row_count" INTEGER NOT NULL DEFAULT 0,
    "data_row_count" INTEGER NOT NULL DEFAULT 0,
    "extract_row_count" INTEGER NOT NULL DEFAULT 0,
    "load_row_count" INTEGER NOT NULL DEFAULT 0,
    "data_insert_row_count" INTEGER NOT NULL DEFAULT 0,
    "data_update_row_count" INTEGER NOT NULL DEFAULT 0,
    "data_delete_row_count" INTEGER NOT NULL DEFAULT 0,
    "extract_insert_row_count" INTEGER NOT NULL DEFAULT 0,
    "extract_update_row_count" INTEGER NOT NULL DEFAULT 0,
    "extract_delete_row_count" INTEGER NOT NULL DEFAULT 0,
    "load_insert_row_count" INTEGER NOT NULL DEFAULT 0,
    "load_update_row_count" INTEGER NOT NULL DEFAULT 0,
    "load_delete_row_count" INTEGER NOT NULL DEFAULT 0,
    "network_millis" INTEGER NOT NULL DEFAULT 0,
    "filter_millis" INTEGER NOT NULL DEFAULT 0,
    "load_millis" INTEGER NOT NULL DEFAULT 0,
    "router_millis" INTEGER NOT NULL DEFAULT 0,
    "extract_millis" INTEGER NOT NULL DEFAULT 0,
    "transform_extract_millis" INTEGER NOT NULL DEFAULT 0,
    "transform_load_millis" INTEGER NOT NULL DEFAULT 0,
    "load_id" BIGINT,
    "common_flag" SMALLINT DEFAULT 0,
    "fallback_insert_count" INTEGER NOT NULL DEFAULT 0,
    "fallback_update_count" INTEGER NOT NULL DEFAULT 0,
    "conflict_win_count" INTEGER NOT NULL DEFAULT 0,
    "conflict_lose_count" INTEGER NOT NULL DEFAULT 0,
    "ignore_row_count" INTEGER NOT NULL DEFAULT 0,
    "missing_delete_count" INTEGER NOT NULL DEFAULT 0,
    "skip_count" INTEGER NOT NULL DEFAULT 0,
    "failed_row_number" INTEGER NOT NULL DEFAULT 0,
    "failed_line_number" INTEGER NOT NULL DEFAULT 0,
    "failed_data_id" BIGINT NOT NULL DEFAULT 0,
    "bulk_loader_flag" SMALLINT DEFAULT 0,

    CONSTRAINT "sym_incoming_batch_pkey" PRIMARY KEY ("batch_id","node_id")
);

-- CreateTable
CREATE TABLE "sym_incoming_error" (
    "batch_id" BIGINT NOT NULL,
    "node_id" VARCHAR(50) NOT NULL,
    "failed_row_number" BIGINT NOT NULL,
    "failed_line_number" BIGINT NOT NULL DEFAULT 0,
    "target_catalog_name" VARCHAR(255),
    "target_schema_name" VARCHAR(255),
    "target_table_name" VARCHAR(255) NOT NULL,
    "event_type" CHAR(1) NOT NULL,
    "binary_encoding" VARCHAR(10) NOT NULL DEFAULT 'HEX',
    "column_names" TEXT NOT NULL,
    "pk_column_names" TEXT NOT NULL,
    "row_data" TEXT,
    "old_data" TEXT,
    "cur_data" TEXT,
    "resolve_data" TEXT,
    "resolve_ignore" SMALLINT DEFAULT 0,
    "conflict_id" VARCHAR(50),
    "create_time" TIMESTAMP(6),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,

    CONSTRAINT "sym_incoming_error_pkey" PRIMARY KEY ("batch_id","node_id","failed_row_number")
);

-- CreateTable
CREATE TABLE "sym_job" (
    "job_name" VARCHAR(50) NOT NULL,
    "job_type" VARCHAR(10) NOT NULL,
    "requires_registration" SMALLINT NOT NULL DEFAULT 1,
    "job_expression" TEXT,
    "implementation" VARCHAR(255),
    "description" VARCHAR(255),
    "default_schedule" VARCHAR(50),
    "default_auto_start" SMALLINT NOT NULL DEFAULT 1,
    "node_group_id" VARCHAR(50) NOT NULL,
    "is_clustered" SMALLINT NOT NULL DEFAULT 0,
    "create_by" VARCHAR(50),
    "create_time" TIMESTAMP(6),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6),

    CONSTRAINT "sym_job_pkey" PRIMARY KEY ("job_name")
);

-- CreateTable
CREATE TABLE "sym_load_filter" (
    "load_filter_id" VARCHAR(50) NOT NULL,
    "load_filter_type" VARCHAR(10) NOT NULL,
    "source_node_group_id" VARCHAR(50) NOT NULL,
    "target_node_group_id" VARCHAR(50) NOT NULL,
    "target_catalog_name" VARCHAR(255),
    "target_schema_name" VARCHAR(255),
    "target_table_name" VARCHAR(255),
    "filter_on_update" SMALLINT NOT NULL DEFAULT 1,
    "filter_on_insert" SMALLINT NOT NULL DEFAULT 1,
    "filter_on_delete" SMALLINT NOT NULL DEFAULT 1,
    "before_write_script" TEXT,
    "after_write_script" TEXT,
    "batch_complete_script" TEXT,
    "batch_commit_script" TEXT,
    "batch_rollback_script" TEXT,
    "handle_error_script" TEXT,
    "create_time" TIMESTAMP(6) NOT NULL,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,
    "load_filter_order" INTEGER NOT NULL DEFAULT 1,
    "fail_on_error" SMALLINT NOT NULL DEFAULT 0,

    CONSTRAINT "sym_load_filter_pkey" PRIMARY KEY ("load_filter_id")
);

-- CreateTable
CREATE TABLE "sym_lock" (
    "lock_action" VARCHAR(50) NOT NULL,
    "lock_type" VARCHAR(50) NOT NULL,
    "locking_server_id" VARCHAR(255),
    "lock_time" TIMESTAMP(6),
    "shared_count" INTEGER NOT NULL DEFAULT 0,
    "shared_enable" INTEGER NOT NULL DEFAULT 0,
    "last_lock_time" TIMESTAMP(6),
    "last_locking_server_id" VARCHAR(255),

    CONSTRAINT "sym_lock_pkey" PRIMARY KEY ("lock_action")
);

-- CreateTable
CREATE TABLE "sym_node" (
    "node_id" VARCHAR(50) NOT NULL,
    "node_group_id" VARCHAR(50) NOT NULL,
    "external_id" VARCHAR(255) NOT NULL,
    "sync_enabled" SMALLINT DEFAULT 0,
    "sync_url" VARCHAR(255),
    "schema_version" VARCHAR(50),
    "symmetric_version" VARCHAR(50),
    "config_version" VARCHAR(50),
    "database_type" VARCHAR(50),
    "database_version" VARCHAR(50),
    "database_name" VARCHAR(50),
    "batch_to_send_count" INTEGER DEFAULT 0,
    "batch_in_error_count" INTEGER DEFAULT 0,
    "batch_last_successful" TIMESTAMP(6),
    "data_rows_to_send_count" INTEGER DEFAULT 0,
    "data_rows_loaded_count" INTEGER DEFAULT 0,
    "oldest_load_time" TIMESTAMP(6),
    "most_recent_active_table" VARCHAR(255),
    "purge_outgoing_last_run_ms" BIGINT DEFAULT 0,
    "purge_outgoing_last_finish" TIMESTAMP(6),
    "purge_outgoing_average_ms" BIGINT,
    "routing_last_run_ms" BIGINT,
    "routing_last_finish" TIMESTAMP(6),
    "routing_average_run_ms" BIGINT DEFAULT 0,
    "sym_data_size" BIGINT,
    "created_at_node_id" VARCHAR(50),
    "deployment_type" VARCHAR(50),
    "deployment_sub_type" VARCHAR(50),

    CONSTRAINT "sym_node_pkey" PRIMARY KEY ("node_id")
);

-- CreateTable
CREATE TABLE "sym_node_channel_ctl" (
    "node_id" VARCHAR(50) NOT NULL,
    "target_node_id" VARCHAR(50) NOT NULL,
    "channel_id" VARCHAR(128) NOT NULL,
    "suspend_enabled" SMALLINT DEFAULT 0,
    "ignore_enabled" SMALLINT DEFAULT 0,
    "last_extract_time" TIMESTAMP(6),

    CONSTRAINT "sym_node_channel_ctl_pkey" PRIMARY KEY ("node_id","target_node_id","channel_id")
);

-- CreateTable
CREATE TABLE "sym_node_communication" (
    "node_id" VARCHAR(50) NOT NULL,
    "queue" VARCHAR(25) NOT NULL DEFAULT 'default',
    "communication_type" VARCHAR(10) NOT NULL,
    "lock_time" TIMESTAMP(6),
    "locking_server_id" VARCHAR(255),
    "last_lock_time" TIMESTAMP(6),
    "last_lock_millis" BIGINT DEFAULT 0,
    "success_count" BIGINT DEFAULT 0,
    "fail_count" BIGINT DEFAULT 0,
    "skip_count" BIGINT DEFAULT 0,
    "total_success_count" BIGINT DEFAULT 0,
    "total_fail_count" BIGINT DEFAULT 0,
    "total_success_millis" BIGINT DEFAULT 0,
    "total_fail_millis" BIGINT DEFAULT 0,
    "batch_to_send_count" BIGINT DEFAULT 0,
    "node_priority" INTEGER DEFAULT 0,

    CONSTRAINT "sym_node_communication_pkey" PRIMARY KEY ("node_id","queue","communication_type")
);

-- CreateTable
CREATE TABLE "sym_node_group" (
    "node_group_id" VARCHAR(50) NOT NULL,
    "description" VARCHAR(255),
    "create_time" TIMESTAMP(6),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6),

    CONSTRAINT "sym_node_group_pkey" PRIMARY KEY ("node_group_id")
);

-- CreateTable
CREATE TABLE "sym_node_group_channel_wnd" (
    "node_group_id" VARCHAR(50) NOT NULL,
    "channel_id" VARCHAR(128) NOT NULL,
    "start_time" TIMESTAMP(2) NOT NULL,
    "end_time" TIMESTAMP(2) NOT NULL,
    "enabled" SMALLINT NOT NULL DEFAULT 0,

    CONSTRAINT "sym_node_group_channel_wnd_pkey" PRIMARY KEY ("node_group_id","channel_id","start_time","end_time")
);

-- CreateTable
CREATE TABLE "sym_node_group_link" (
    "source_node_group_id" VARCHAR(50) NOT NULL,
    "target_node_group_id" VARCHAR(50) NOT NULL,
    "data_event_action" CHAR(1) NOT NULL DEFAULT 'W',
    "sync_config_enabled" SMALLINT NOT NULL DEFAULT 1,
    "sync_sql_enabled" SMALLINT NOT NULL DEFAULT 1,
    "is_reversible" SMALLINT NOT NULL DEFAULT 0,
    "description" VARCHAR(255),
    "create_time" TIMESTAMP(6),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6),

    CONSTRAINT "sym_node_group_link_pkey" PRIMARY KEY ("source_node_group_id","target_node_group_id")
);

-- CreateTable
CREATE TABLE "sym_node_host" (
    "node_id" VARCHAR(50) NOT NULL,
    "host_name" VARCHAR(60) NOT NULL,
    "instance_id" VARCHAR(60),
    "ip_address" VARCHAR(50),
    "os_user" VARCHAR(50),
    "os_name" VARCHAR(50),
    "os_arch" VARCHAR(50),
    "os_version" VARCHAR(50),
    "available_processors" INTEGER DEFAULT 0,
    "free_memory_bytes" BIGINT DEFAULT 0,
    "total_memory_bytes" BIGINT DEFAULT 0,
    "max_memory_bytes" BIGINT DEFAULT 0,
    "java_version" VARCHAR(50),
    "java_vendor" VARCHAR(255),
    "jdbc_version" VARCHAR(255),
    "symmetric_version" VARCHAR(50),
    "timezone_offset" VARCHAR(6),
    "heartbeat_time" TIMESTAMP(6),
    "last_restart_time" TIMESTAMP(6) NOT NULL,
    "create_time" TIMESTAMP(6) NOT NULL,

    CONSTRAINT "sym_node_host_pkey" PRIMARY KEY ("node_id","host_name")
);

-- CreateTable
CREATE TABLE "sym_node_host_channel_stats" (
    "node_id" VARCHAR(50) NOT NULL,
    "host_name" VARCHAR(60) NOT NULL,
    "channel_id" VARCHAR(128) NOT NULL,
    "start_time" TIMESTAMP(2) NOT NULL,
    "end_time" TIMESTAMP(2) NOT NULL,
    "data_routed" BIGINT DEFAULT 0,
    "data_unrouted" BIGINT DEFAULT 0,
    "data_event_inserted" BIGINT DEFAULT 0,
    "data_extracted" BIGINT DEFAULT 0,
    "data_bytes_extracted" BIGINT DEFAULT 0,
    "data_extracted_errors" BIGINT DEFAULT 0,
    "data_bytes_sent" BIGINT DEFAULT 0,
    "data_sent" BIGINT DEFAULT 0,
    "data_sent_errors" BIGINT DEFAULT 0,
    "data_received" BIGINT DEFAULT 0,
    "data_bytes_received" BIGINT DEFAULT 0,
    "data_loaded" BIGINT DEFAULT 0,
    "data_bytes_loaded" BIGINT DEFAULT 0,
    "data_loaded_errors" BIGINT DEFAULT 0,
    "data_loaded_outgoing" BIGINT DEFAULT 0,
    "data_bytes_loaded_outgoing" BIGINT DEFAULT 0,
    "data_loaded_outgoing_errors" BIGINT DEFAULT 0,
    "data_min_create_time" TIMESTAMP(6),
    "data_max_create_time" TIMESTAMP(6),

    CONSTRAINT "sym_node_host_channel_stats_pkey" PRIMARY KEY ("node_id","host_name","channel_id","start_time","end_time")
);

-- CreateTable
CREATE TABLE "sym_node_host_job_stats" (
    "node_id" VARCHAR(50) NOT NULL,
    "host_name" VARCHAR(60) NOT NULL,
    "job_name" VARCHAR(50) NOT NULL,
    "start_time" TIMESTAMP(2) NOT NULL,
    "end_time" TIMESTAMP(2) NOT NULL,
    "processed_count" BIGINT DEFAULT 0,
    "error_flag" SMALLINT DEFAULT 0,
    "error_message" TEXT,
    "target_node_id" VARCHAR(50),
    "target_node_count" INTEGER DEFAULT 0,

    CONSTRAINT "sym_node_host_job_stats_pkey" PRIMARY KEY ("node_id","host_name","job_name","start_time","end_time")
);

-- CreateTable
CREATE TABLE "sym_node_host_stats" (
    "node_id" VARCHAR(50) NOT NULL,
    "host_name" VARCHAR(60) NOT NULL,
    "start_time" TIMESTAMP(2) NOT NULL,
    "end_time" TIMESTAMP(2) NOT NULL,
    "restarted" BIGINT NOT NULL DEFAULT 0,
    "nodes_pulled" BIGINT DEFAULT 0,
    "total_nodes_pull_time" BIGINT DEFAULT 0,
    "nodes_pushed" BIGINT DEFAULT 0,
    "total_nodes_push_time" BIGINT DEFAULT 0,
    "nodes_rejected" BIGINT DEFAULT 0,
    "nodes_registered" BIGINT DEFAULT 0,
    "nodes_loaded" BIGINT DEFAULT 0,
    "nodes_disabled" BIGINT DEFAULT 0,
    "purged_data_rows" BIGINT DEFAULT 0,
    "purged_data_event_rows" BIGINT DEFAULT 0,
    "purged_stranded_data_rows" BIGINT DEFAULT 0,
    "purged_stranded_event_rows" BIGINT DEFAULT 0,
    "purged_expired_data_rows" BIGINT DEFAULT 0,
    "purged_batch_outgoing_rows" BIGINT DEFAULT 0,
    "purged_batch_incoming_rows" BIGINT DEFAULT 0,
    "triggers_created_count" BIGINT,
    "triggers_rebuilt_count" BIGINT,
    "triggers_removed_count" BIGINT,
    "data_gap_count" BIGINT,
    "data_unrouted_count" BIGINT,

    CONSTRAINT "sym_node_host_stats_pkey" PRIMARY KEY ("node_id","host_name","start_time","end_time")
);

-- CreateTable
CREATE TABLE "sym_node_identity" (
    "node_id" VARCHAR(50) NOT NULL,

    CONSTRAINT "sym_node_identity_pkey" PRIMARY KEY ("node_id")
);

-- CreateTable
CREATE TABLE "sym_node_security" (
    "node_id" VARCHAR(50) NOT NULL,
    "node_password" VARCHAR(50) NOT NULL,
    "registration_enabled" SMALLINT DEFAULT 0,
    "registration_time" TIMESTAMP(6),
    "registration_not_before" TIMESTAMP(6),
    "registration_not_after" TIMESTAMP(6),
    "initial_load_enabled" SMALLINT DEFAULT 0,
    "initial_load_time" TIMESTAMP(6),
    "initial_load_end_time" TIMESTAMP(6),
    "initial_load_id" BIGINT,
    "initial_load_create_by" VARCHAR(255),
    "partial_load_time" TIMESTAMP(6),
    "partial_load_end_time" TIMESTAMP(6),
    "partial_load_id" BIGINT,
    "partial_load_create_by" VARCHAR(255),
    "rev_initial_load_enabled" SMALLINT DEFAULT 0,
    "rev_initial_load_time" TIMESTAMP(6),
    "rev_initial_load_id" BIGINT,
    "rev_initial_load_create_by" VARCHAR(255),
    "failed_logins" SMALLINT DEFAULT 0,
    "created_at_node_id" VARCHAR(50),

    CONSTRAINT "sym_node_security_pkey" PRIMARY KEY ("node_id")
);

-- CreateTable
CREATE TABLE "sym_outgoing_batch" (
    "batch_id" BIGINT NOT NULL,
    "node_id" VARCHAR(50) NOT NULL,
    "channel_id" VARCHAR(128),
    "status" CHAR(2),
    "error_flag" SMALLINT DEFAULT 0,
    "sql_state" VARCHAR(10),
    "sql_code" INTEGER NOT NULL DEFAULT 0,
    "sql_message" TEXT,
    "last_update_hostname" VARCHAR(255),
    "last_update_time" TIMESTAMP(6),
    "create_time" TIMESTAMP(6),
    "summary" VARCHAR(255),
    "ignore_count" INTEGER NOT NULL DEFAULT 0,
    "byte_count" BIGINT NOT NULL DEFAULT 0,
    "load_flag" SMALLINT DEFAULT 0,
    "extract_count" INTEGER NOT NULL DEFAULT 0,
    "sent_count" INTEGER NOT NULL DEFAULT 0,
    "load_count" INTEGER NOT NULL DEFAULT 0,
    "reload_row_count" INTEGER NOT NULL DEFAULT 0,
    "other_row_count" INTEGER NOT NULL DEFAULT 0,
    "data_row_count" INTEGER NOT NULL DEFAULT 0,
    "extract_row_count" INTEGER NOT NULL DEFAULT 0,
    "load_row_count" INTEGER NOT NULL DEFAULT 0,
    "data_insert_row_count" INTEGER NOT NULL DEFAULT 0,
    "data_update_row_count" INTEGER NOT NULL DEFAULT 0,
    "data_delete_row_count" INTEGER NOT NULL DEFAULT 0,
    "extract_insert_row_count" INTEGER NOT NULL DEFAULT 0,
    "extract_update_row_count" INTEGER NOT NULL DEFAULT 0,
    "extract_delete_row_count" INTEGER NOT NULL DEFAULT 0,
    "load_insert_row_count" INTEGER NOT NULL DEFAULT 0,
    "load_update_row_count" INTEGER NOT NULL DEFAULT 0,
    "load_delete_row_count" INTEGER NOT NULL DEFAULT 0,
    "network_millis" INTEGER NOT NULL DEFAULT 0,
    "filter_millis" INTEGER NOT NULL DEFAULT 0,
    "load_millis" INTEGER NOT NULL DEFAULT 0,
    "router_millis" INTEGER NOT NULL DEFAULT 0,
    "extract_millis" INTEGER NOT NULL DEFAULT 0,
    "transform_extract_millis" INTEGER NOT NULL DEFAULT 0,
    "transform_load_millis" INTEGER NOT NULL DEFAULT 0,
    "load_id" BIGINT,
    "thread_id" INTEGER,
    "common_flag" SMALLINT DEFAULT 0,
    "fallback_insert_count" INTEGER NOT NULL DEFAULT 0,
    "fallback_update_count" INTEGER NOT NULL DEFAULT 0,
    "conflict_win_count" INTEGER NOT NULL DEFAULT 0,
    "conflict_lose_count" INTEGER NOT NULL DEFAULT 0,
    "ignore_row_count" INTEGER NOT NULL DEFAULT 0,
    "missing_delete_count" INTEGER NOT NULL DEFAULT 0,
    "skip_count" INTEGER NOT NULL DEFAULT 0,
    "total_extract_millis" INTEGER NOT NULL DEFAULT 0,
    "total_load_millis" INTEGER NOT NULL DEFAULT 0,
    "extract_job_flag" SMALLINT DEFAULT 0,
    "extract_start_time" TIMESTAMP(6),
    "transfer_start_time" TIMESTAMP(6),
    "load_start_time" TIMESTAMP(6),
    "failed_data_id" BIGINT NOT NULL DEFAULT 0,
    "failed_line_number" BIGINT NOT NULL DEFAULT 0,
    "create_by" VARCHAR(255),
    "bulk_loader_flag" SMALLINT DEFAULT 0,
    "data_min_create_time" TIMESTAMP(6),
    "data_max_create_time" TIMESTAMP(6),

    CONSTRAINT "sym_outgoing_batch_pkey" PRIMARY KEY ("batch_id","node_id")
);

-- CreateTable
CREATE TABLE "sym_outgoing_error" (
    "batch_id" BIGINT NOT NULL,
    "node_id" VARCHAR(50) NOT NULL,
    "failed_row_number" BIGINT NOT NULL,
    "failed_line_number" BIGINT NOT NULL DEFAULT 0,
    "target_catalog_name" VARCHAR(255),
    "target_schema_name" VARCHAR(255),
    "target_table_name" VARCHAR(255) NOT NULL,
    "event_type" CHAR(1) NOT NULL,
    "binary_encoding" VARCHAR(10) NOT NULL DEFAULT 'HEX',
    "column_names" TEXT NOT NULL,
    "pk_column_names" TEXT NOT NULL,
    "row_data" TEXT,
    "old_data" TEXT,
    "cur_data" TEXT,
    "resolve_data" TEXT,
    "resolve_ignore" SMALLINT DEFAULT 0,
    "conflict_id" VARCHAR(50),
    "create_time" TIMESTAMP(6),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,

    CONSTRAINT "sym_outgoing_error_pkey" PRIMARY KEY ("batch_id","node_id","failed_row_number")
);

-- CreateTable
CREATE TABLE "sym_parameter" (
    "external_id" VARCHAR(255) NOT NULL,
    "node_group_id" VARCHAR(50) NOT NULL,
    "param_key" VARCHAR(80) NOT NULL,
    "param_value" TEXT,
    "create_time" TIMESTAMP(6),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6),

    CONSTRAINT "sym_parameter_pkey" PRIMARY KEY ("external_id","node_group_id","param_key")
);

-- CreateTable
CREATE TABLE "sym_registration_redirect" (
    "registrant_external_id" VARCHAR(255) NOT NULL,
    "registration_node_id" VARCHAR(50) NOT NULL,

    CONSTRAINT "sym_registration_redirect_pkey" PRIMARY KEY ("registrant_external_id")
);

-- CreateTable
CREATE TABLE "sym_registration_request" (
    "node_group_id" VARCHAR(50) NOT NULL,
    "external_id" VARCHAR(255) NOT NULL,
    "status" CHAR(2) NOT NULL,
    "host_name" VARCHAR(60) NOT NULL,
    "ip_address" VARCHAR(50) NOT NULL,
    "attempt_count" INTEGER DEFAULT 0,
    "registered_node_id" VARCHAR(50),
    "error_message" TEXT,
    "create_time" TIMESTAMP(2) NOT NULL,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,

    CONSTRAINT "sym_registration_request_pkey" PRIMARY KEY ("node_group_id","external_id","create_time")
);

-- CreateTable
CREATE TABLE "sym_router" (
    "router_id" VARCHAR(50) NOT NULL,
    "target_catalog_name" VARCHAR(255),
    "target_schema_name" VARCHAR(255),
    "target_table_name" VARCHAR(255),
    "source_node_group_id" VARCHAR(50) NOT NULL,
    "target_node_group_id" VARCHAR(50) NOT NULL,
    "router_type" VARCHAR(50) NOT NULL DEFAULT 'default',
    "router_expression" TEXT,
    "sync_on_update" SMALLINT NOT NULL DEFAULT 1,
    "sync_on_insert" SMALLINT NOT NULL DEFAULT 1,
    "sync_on_delete" SMALLINT NOT NULL DEFAULT 1,
    "use_source_catalog_schema" SMALLINT NOT NULL DEFAULT 1,
    "create_time" TIMESTAMP(6) NOT NULL,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,
    "description" TEXT,

    CONSTRAINT "sym_router_pkey" PRIMARY KEY ("router_id")
);

-- CreateTable
CREATE TABLE "sym_sequence" (
    "sequence_name" VARCHAR(50) NOT NULL,
    "current_value" BIGINT NOT NULL DEFAULT 0,
    "increment_by" INTEGER NOT NULL DEFAULT 1,
    "min_value" BIGINT NOT NULL DEFAULT 1,
    "max_value" BIGINT NOT NULL DEFAULT 9999999999,
    "cycle_flag" SMALLINT DEFAULT 0,
    "cache_size" INTEGER NOT NULL DEFAULT 0,
    "create_time" TIMESTAMP(6),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,

    CONSTRAINT "sym_sequence_pkey" PRIMARY KEY ("sequence_name")
);

-- CreateTable
CREATE TABLE "sym_table_reload_request" (
    "target_node_id" VARCHAR(50) NOT NULL,
    "source_node_id" VARCHAR(50) NOT NULL,
    "trigger_id" VARCHAR(128) NOT NULL,
    "router_id" VARCHAR(50) NOT NULL,
    "create_time" TIMESTAMP(2) NOT NULL,
    "create_table" SMALLINT NOT NULL DEFAULT 0,
    "delete_first" SMALLINT NOT NULL DEFAULT 0,
    "reload_select" TEXT,
    "before_custom_sql" TEXT,
    "reload_time" TIMESTAMP(6),
    "load_id" BIGINT,
    "processed" SMALLINT NOT NULL DEFAULT 0,
    "channel_id" VARCHAR(128),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,

    CONSTRAINT "sym_table_reload_request_pkey" PRIMARY KEY ("target_node_id","source_node_id","trigger_id","router_id","create_time")
);

-- CreateTable
CREATE TABLE "sym_table_reload_status" (
    "load_id" BIGINT NOT NULL,
    "source_node_id" VARCHAR(50) NOT NULL,
    "target_node_id" VARCHAR(50) NOT NULL,
    "start_time" TIMESTAMP(6),
    "end_time" TIMESTAMP(6),
    "completed" SMALLINT NOT NULL DEFAULT 0,
    "cancelled" SMALLINT NOT NULL DEFAULT 0,
    "full_load" SMALLINT NOT NULL DEFAULT 0,
    "start_data_batch_id" BIGINT,
    "end_data_batch_id" BIGINT,
    "setup_batch_count" BIGINT NOT NULL DEFAULT 0,
    "data_batch_count" BIGINT NOT NULL DEFAULT 0,
    "finalize_batch_count" BIGINT NOT NULL DEFAULT 0,
    "setup_batch_loaded" BIGINT NOT NULL DEFAULT 0,
    "data_batch_loaded" BIGINT NOT NULL DEFAULT 0,
    "finalize_batch_loaded" BIGINT NOT NULL DEFAULT 0,
    "table_count" BIGINT NOT NULL DEFAULT 0,
    "rows_loaded" BIGINT NOT NULL DEFAULT 0,
    "rows_count" BIGINT NOT NULL DEFAULT 0,
    "error_flag" SMALLINT NOT NULL DEFAULT 0,
    "error_batch_id" BIGINT,
    "sql_state" VARCHAR(10),
    "sql_code" INTEGER NOT NULL DEFAULT 0,
    "sql_message" TEXT,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,
    "batch_bulk_load_count" BIGINT NOT NULL DEFAULT 0,
    "row_bulk_load_count" BIGINT NOT NULL DEFAULT 0,

    CONSTRAINT "sym_table_reload_status_pkey" PRIMARY KEY ("load_id","source_node_id")
);

-- CreateTable
CREATE TABLE "sym_transform_column" (
    "transform_id" VARCHAR(50) NOT NULL,
    "include_on" CHAR(1) NOT NULL DEFAULT '*',
    "target_column_name" VARCHAR(128) NOT NULL,
    "source_column_name" VARCHAR(128),
    "pk" SMALLINT DEFAULT 0,
    "transform_type" VARCHAR(50) DEFAULT 'copy',
    "transform_expression" TEXT,
    "transform_order" INTEGER NOT NULL DEFAULT 1,
    "create_time" TIMESTAMP(6),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6),
    "description" TEXT,

    CONSTRAINT "sym_transform_column_pkey" PRIMARY KEY ("transform_id","include_on","target_column_name")
);

-- CreateTable
CREATE TABLE "sym_transform_table" (
    "transform_id" VARCHAR(50) NOT NULL,
    "source_node_group_id" VARCHAR(50) NOT NULL,
    "target_node_group_id" VARCHAR(50) NOT NULL,
    "transform_point" VARCHAR(10) NOT NULL,
    "source_catalog_name" VARCHAR(255),
    "source_schema_name" VARCHAR(255),
    "source_table_name" VARCHAR(255) NOT NULL,
    "target_catalog_name" VARCHAR(255),
    "target_schema_name" VARCHAR(255),
    "target_table_name" VARCHAR(255),
    "update_first" SMALLINT DEFAULT 0,
    "update_action" VARCHAR(255) NOT NULL DEFAULT 'UPDATE_COL',
    "delete_action" VARCHAR(10) NOT NULL,
    "transform_order" INTEGER NOT NULL DEFAULT 1,
    "column_policy" VARCHAR(10) NOT NULL DEFAULT 'SPECIFIED',
    "create_time" TIMESTAMP(6),
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6),
    "description" TEXT,

    CONSTRAINT "sym_transform_table_pkey" PRIMARY KEY ("transform_id","source_node_group_id","target_node_group_id")
);

-- CreateTable
CREATE TABLE "sym_trigger" (
    "trigger_id" VARCHAR(128) NOT NULL,
    "source_catalog_name" VARCHAR(255),
    "source_schema_name" VARCHAR(255),
    "source_table_name" VARCHAR(255) NOT NULL,
    "channel_id" VARCHAR(128) NOT NULL,
    "reload_channel_id" VARCHAR(128) NOT NULL DEFAULT 'reload',
    "sync_on_update" SMALLINT NOT NULL DEFAULT 1,
    "sync_on_insert" SMALLINT NOT NULL DEFAULT 1,
    "sync_on_delete" SMALLINT NOT NULL DEFAULT 1,
    "sync_on_incoming_batch" SMALLINT NOT NULL DEFAULT 0,
    "name_for_update_trigger" VARCHAR(255),
    "name_for_insert_trigger" VARCHAR(255),
    "name_for_delete_trigger" VARCHAR(255),
    "sync_on_update_condition" TEXT,
    "sync_on_insert_condition" TEXT,
    "sync_on_delete_condition" TEXT,
    "custom_before_update_text" TEXT,
    "custom_before_insert_text" TEXT,
    "custom_before_delete_text" TEXT,
    "custom_on_update_text" TEXT,
    "custom_on_insert_text" TEXT,
    "custom_on_delete_text" TEXT,
    "external_select" TEXT,
    "tx_id_expression" TEXT,
    "channel_expression" TEXT,
    "excluded_column_names" TEXT,
    "included_column_names" TEXT,
    "sync_key_names" TEXT,
    "use_stream_lobs" SMALLINT NOT NULL DEFAULT 0,
    "use_capture_lobs" SMALLINT NOT NULL DEFAULT 0,
    "use_capture_old_data" SMALLINT NOT NULL DEFAULT 1,
    "use_handle_key_updates" SMALLINT NOT NULL DEFAULT 1,
    "stream_row" SMALLINT NOT NULL DEFAULT 0,
    "capture_changes_only" SMALLINT NOT NULL DEFAULT 0,
    "time_based_column_name" VARCHAR(255),
    "create_time" TIMESTAMP(6) NOT NULL,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,
    "description" TEXT,

    CONSTRAINT "sym_trigger_pkey" PRIMARY KEY ("trigger_id")
);

-- CreateTable
CREATE TABLE "sym_trigger_hist" (
    "trigger_hist_id" INTEGER NOT NULL,
    "trigger_id" VARCHAR(128) NOT NULL,
    "source_table_name" VARCHAR(255) NOT NULL,
    "source_catalog_name" VARCHAR(255),
    "source_schema_name" VARCHAR(255),
    "name_for_update_trigger" VARCHAR(255),
    "name_for_insert_trigger" VARCHAR(255),
    "name_for_delete_trigger" VARCHAR(255),
    "table_hash" BIGINT NOT NULL DEFAULT 0,
    "trigger_row_hash" BIGINT NOT NULL DEFAULT 0,
    "trigger_template_hash" BIGINT NOT NULL DEFAULT 0,
    "column_names" TEXT NOT NULL,
    "pk_column_names" TEXT NOT NULL,
    "is_missing_pk" SMALLINT NOT NULL DEFAULT 0,
    "last_trigger_build_reason" CHAR(1) NOT NULL,
    "error_message" TEXT,
    "create_time" TIMESTAMP(6) NOT NULL,
    "inactive_time" TIMESTAMP(6),

    CONSTRAINT "sym_trigger_hist_pkey" PRIMARY KEY ("trigger_hist_id")
);

-- CreateTable
CREATE TABLE "sym_trigger_router" (
    "trigger_id" VARCHAR(128) NOT NULL,
    "router_id" VARCHAR(50) NOT NULL,
    "enabled" SMALLINT NOT NULL DEFAULT 1,
    "initial_load_order" INTEGER NOT NULL DEFAULT 1,
    "initial_load_select" TEXT,
    "initial_load_delete_stmt" TEXT,
    "ping_back_enabled" SMALLINT NOT NULL DEFAULT 0,
    "create_time" TIMESTAMP(6) NOT NULL,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,
    "description" TEXT,
    "data_refresh_type" VARCHAR(50),
    "data_refresh_job_name" VARCHAR(50) NOT NULL DEFAULT 'CDC',

    CONSTRAINT "sym_trigger_router_pkey" PRIMARY KEY ("trigger_id","router_id")
);

-- CreateTable
CREATE TABLE "sym_trigger_router_grouplet" (
    "grouplet_id" VARCHAR(50) NOT NULL,
    "trigger_id" VARCHAR(128) NOT NULL,
    "router_id" VARCHAR(50) NOT NULL,
    "applies_when" CHAR(1) NOT NULL,
    "create_time" TIMESTAMP(6) NOT NULL,
    "last_update_by" VARCHAR(50),
    "last_update_time" TIMESTAMP(6) NOT NULL,

    CONSTRAINT "sym_trigger_router_grouplet_pkey" PRIMARY KEY ("grouplet_id","trigger_id","router_id","applies_when")
);

-- CreateTable
CREATE TABLE "sync_log" (
    "id" BIGSERIAL NOT NULL,
    "device_id" UUID NOT NULL,
    "entity_type" VARCHAR(100) NOT NULL,
    "entity_id" UUID NOT NULL,
    "operation" "sync_operation_enum" NOT NULL,
    "payload" JSONB NOT NULL,
    "client_version" INTEGER,
    "server_seq" BIGINT,
    "conflict_resolved" BOOLEAN NOT NULL DEFAULT false,
    "conflict_notes" TEXT,
    "synced_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sync_log_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "units_of_measure" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name_ar" VARCHAR(100) NOT NULL,
    "name_en" VARCHAR(100),
    "symbol" VARCHAR(20),
    "parent_unit_id" UUID,
    "conversion_factor" DECIMAL(15,6) NOT NULL DEFAULT 1,
    "is_base_unit" BOOLEAN NOT NULL DEFAULT false,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "units_of_measure_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "username" VARCHAR(100) NOT NULL,
    "email" VARCHAR(150),
    "password_hash" TEXT NOT NULL,
    "full_name" VARCHAR(200),
    "phone" VARCHAR(20),
    "role_id" UUID,
    "branch_id" UUID,
    "avatar_url" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "last_login" TIMESTAMPTZ(6),
    "refresh_token" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_by" UUID,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "warehouse_transfer_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "transfer_id" UUID NOT NULL,
    "variant_id" UUID NOT NULL,
    "batch_id" UUID,
    "serial_id" UUID,
    "quantity_sent" DECIMAL(15,3) NOT NULL,
    "quantity_received" DECIMAL(15,3) NOT NULL DEFAULT 0,
    "quantity_shortage" DECIMAL(15,3) NOT NULL DEFAULT 0,
    "quantity_damaged" DECIMAL(15,3) NOT NULL DEFAULT 0,

    CONSTRAINT "warehouse_transfer_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "warehouse_transfers" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "transfer_number" VARCHAR(50) NOT NULL,
    "source_warehouse_id" UUID NOT NULL,
    "destination_warehouse_id" UUID NOT NULL,
    "status" "transfer_status_enum" NOT NULL DEFAULT 'PENDING',
    "dispatch_date" TIMESTAMPTZ(6),
    "receive_date" TIMESTAMPTZ(6),
    "notes" TEXT,
    "idempotency_key" VARCHAR(200),
    "approved_by" UUID,
    "dispatched_by" UUID,
    "received_by" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_by" UUID,

    CONSTRAINT "warehouse_transfers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "warehouses" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "branch_id" UUID NOT NULL,
    "name" VARCHAR(200) NOT NULL,
    "address" TEXT,
    "type" "warehouse_type_enum" NOT NULL DEFAULT 'SUB',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "capacity" DECIMAL(10,2),
    "code" VARCHAR(50) NOT NULL,
    "created_by" UUID,
    "manager_id" UUID,
    "notes" TEXT,
    "parent_warehouse_id" UUID,
    "rejection_reason" TEXT,
    "status" "org_status_enum" NOT NULL DEFAULT 'DRAFT',

    CONSTRAINT "warehouses_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "warehouse_keepers" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "warehouse_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "assigned_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "warehouse_keepers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ecommerce_product_settings" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "variant_id" UUID NOT NULL,
    "unit_id" UUID NOT NULL,
    "is_enabled" BOOLEAN NOT NULL DEFAULT true,
    "commission_type" "commission_type_enum" NOT NULL DEFAULT 'PERCENT',
    "commission_value" DECIMAL(15,4) NOT NULL DEFAULT 0,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecommerce_product_settings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ecommerce_carts" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "session_token" VARCHAR(150),
    "source" "ecommerce_order_source_enum" NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecommerce_carts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ecommerce_cart_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "cart_id" UUID NOT NULL,
    "variant_id" UUID NOT NULL,
    "unit_id" UUID NOT NULL,
    "quantity" DECIMAL(15,3) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecommerce_cart_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ecommerce_orders" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "order_number" VARCHAR(50) NOT NULL,
    "source" "ecommerce_order_source_enum" NOT NULL,
    "status" "ecommerce_order_status_enum" NOT NULL DEFAULT 'SUBMITTED',
    "user_id" UUID,
    "rep_id" UUID,
    "party_type" "ecommerce_party_type_enum",
    "party_id" UUID,
    "party_name" VARCHAR(300),
    "party_phone" VARCHAR(50),
    "party_address" TEXT,
    "customer_name" VARCHAR(300),
    "customer_phone" VARCHAR(50),
    "customer_email" VARCHAR(150),
    "customer_address" TEXT,
    "payment_type" "sales_payment_enum" NOT NULL DEFAULT 'CASH',
    "notes" TEXT,
    "subtotal" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "discount_amount" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "total" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "submitted_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "accepted_at" TIMESTAMPTZ(6),
    "accepted_by" UUID,
    "rejected_at" TIMESTAMPTZ(6),
    "rejected_by" UUID,
    "rejection_reason" TEXT,
    "cancelled_at" TIMESTAMPTZ(6),
    "cancelled_by" UUID,
    "cancellation_reason" TEXT,
    "sales_invoice_id" UUID,
    "public_token" VARCHAR(150),
    "idempotency_key" VARCHAR(200),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecommerce_orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ecommerce_order_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "order_id" UUID NOT NULL,
    "product_id" UUID NOT NULL,
    "variant_id" UUID NOT NULL,
    "unit_id" UUID NOT NULL,
    "product_name" VARCHAR(300) NOT NULL,
    "variant_snapshot" JSONB NOT NULL DEFAULT '{}',
    "unit_name" VARCHAR(100),
    "quantity" DECIMAL(15,3) NOT NULL,
    "price_type" "price_type_enum" NOT NULL,
    "base_price" DECIMAL(15,4) NOT NULL,
    "commission_type" "commission_type_enum",
    "commission_value" DECIMAL(15,4) NOT NULL DEFAULT 0,
    "commission_amount" DECIMAL(15,4) NOT NULL DEFAULT 0,
    "unit_price" DECIMAL(15,4) NOT NULL,
    "line_total" DECIMAL(15,2) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecommerce_order_items_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "idx_accounts_entity" ON "accounts_ledger"("account_type", "account_id");

-- CreateIndex
CREATE UNIQUE INDEX "accounts_ledger_account_type_account_id_key" ON "accounts_ledger"("account_type", "account_id");

-- CreateIndex
CREATE UNIQUE INDEX "branches_code_key" ON "branches"("code");

-- CreateIndex
CREATE INDEX "branches_status_idx" ON "branches"("status");

-- CreateIndex
CREATE INDEX "branches_type_idx" ON "branches"("type");

-- CreateIndex
CREATE UNIQUE INDEX "cashboxes_device_code_key" ON "cashboxes"("device_code");

-- CreateIndex
CREATE UNIQUE INDEX "cashboxes_cashbox_code_key" ON "cashboxes"("cashbox_code");

-- CreateIndex
CREATE INDEX "idx_categories_parent" ON "categories"("parent_id");

-- CreateIndex
CREATE INDEX "idx_categories_path" ON "categories"("path");

-- CreateIndex
CREATE UNIQUE INDEX "customers_phone_key" ON "customers"("phone");

-- CreateIndex
CREATE INDEX "idx_customers_phone" ON "customers"("phone");

-- CreateIndex
CREATE INDEX "idx_customers_rep" ON "customers"("assigned_rep_id");

-- CreateIndex
CREATE UNIQUE INDEX "device_sync_state_device_id_key" ON "device_sync_state"("device_id");

-- CreateIndex
CREATE INDEX "idx_movements_ref" ON "inventory_movements"("reference_type", "reference_id");

-- CreateIndex
CREATE INDEX "idx_movements_variant" ON "inventory_movements"("variant_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "idx_movements_warehouse" ON "inventory_movements"("warehouse_id", "created_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "payment_vouchers_voucher_number_key" ON "payment_vouchers"("voucher_number");

-- CreateIndex
CREATE UNIQUE INDEX "payment_vouchers_idempotency_key_key" ON "payment_vouchers"("idempotency_key");

-- CreateIndex
CREATE INDEX "payment_vouchers_supplier_id_idx" ON "payment_vouchers"("supplier_id");

-- CreateIndex
CREATE INDEX "payment_vouchers_customer_id_voucher_date_idx" ON "payment_vouchers"("customer_id", "voucher_date");

-- CreateIndex
CREATE INDEX "payment_vouchers_cashbox_id_voucher_date_idx" ON "payment_vouchers"("cashbox_id", "voucher_date");

-- CreateIndex
CREATE INDEX "payment_vouchers_sales_invoice_id_idx" ON "payment_vouchers"("sales_invoice_id");

-- CreateIndex
CREATE UNIQUE INDEX "permissions_resource_action_key" ON "permissions"("resource", "action");

-- CreateIndex
CREATE INDEX "idx_batches_variant" ON "product_batches"("variant_id", "warehouse_id");

-- CreateIndex
CREATE INDEX "idx_prices_variant" ON "product_prices"("variant_id", "price_type");

-- CreateIndex
CREATE UNIQUE INDEX "product_prices_variant_id_price_type_unit_id_key" ON "product_prices"("variant_id", "price_type", "unit_id");

-- CreateIndex
CREATE UNIQUE INDEX "product_variants_sku_key" ON "product_variants"("sku");

-- CreateIndex
CREATE UNIQUE INDEX "product_variants_barcode_key" ON "product_variants"("barcode");

-- CreateIndex
CREATE INDEX "idx_variants_barcode" ON "product_variants"("barcode");

-- CreateIndex
CREATE INDEX "idx_variants_product" ON "product_variants"("product_id");

-- CreateIndex
CREATE UNIQUE INDEX "products_sku_key" ON "products"("sku");

-- CreateIndex
CREATE UNIQUE INDEX "products_barcode_key" ON "products"("barcode");

-- CreateIndex
CREATE INDEX "idx_products_active" ON "products"("is_active");

-- CreateIndex
CREATE INDEX "idx_products_barcode" ON "products"("barcode");

-- CreateIndex
CREATE INDEX "idx_products_category" ON "products"("category_id");

-- CreateIndex
CREATE INDEX "idx_products_sku" ON "products"("sku");

-- CreateIndex
CREATE UNIQUE INDEX "purchase_invoices_invoice_number_key" ON "purchase_invoices"("invoice_number");

-- CreateIndex
CREATE INDEX "purchase_invoices_supplier_id_idx" ON "purchase_invoices"("supplier_id");

-- CreateIndex
CREATE INDEX "purchase_invoices_warehouse_id_idx" ON "purchase_invoices"("warehouse_id");

-- CreateIndex
CREATE UNIQUE INDEX "rep_custody_orders_order_number_key" ON "rep_custody_orders"("order_number");

-- CreateIndex
CREATE UNIQUE INDEX "rep_custody_orders_idempotency_key_key" ON "rep_custody_orders"("idempotency_key");

-- CreateIndex
CREATE UNIQUE INDEX "representatives_user_id_key" ON "representatives"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "roles_name_key" ON "roles"("name");

-- CreateIndex
CREATE UNIQUE INDEX "sales_invoices_invoice_number_key" ON "sales_invoices"("invoice_number");

-- CreateIndex
CREATE UNIQUE INDEX "sales_invoices_idempotency_key_key" ON "sales_invoices"("idempotency_key");

-- CreateIndex
CREATE INDEX "idx_sales_cashbox" ON "sales_invoices"("cashbox_id");

-- CreateIndex
CREATE INDEX "idx_sales_customer" ON "sales_invoices"("customer_id");

-- CreateIndex
CREATE INDEX "idx_sales_date" ON "sales_invoices"("invoice_date" DESC);

-- CreateIndex
CREATE INDEX "idx_sales_idem" ON "sales_invoices"("idempotency_key");

-- CreateIndex
CREATE INDEX "idx_sales_rep" ON "sales_invoices"("rep_id");

-- CreateIndex
CREATE INDEX "idx_sales_status" ON "sales_invoices"("status");

-- CreateIndex
CREATE UNIQUE INDEX "serials_serial_no_key" ON "serials"("serial_no");

-- CreateIndex
CREATE INDEX "idx_stock_variant" ON "stock_levels"("variant_id");

-- CreateIndex
CREATE INDEX "idx_stock_warehouse" ON "stock_levels"("warehouse_id");

-- CreateIndex
CREATE UNIQUE INDEX "stock_levels_variant_id_warehouse_id_key" ON "stock_levels"("variant_id", "warehouse_id");

-- CreateIndex
CREATE UNIQUE INDEX "stocktaking_items_session_id_variant_id_batch_id_key" ON "stocktaking_items"("session_id", "variant_id", "batch_id");

-- CreateIndex
CREATE UNIQUE INDEX "stocktaking_sessions_session_number_key" ON "stocktaking_sessions"("session_number");

-- CreateIndex
CREATE INDEX "suppliers_name_idx" ON "suppliers"("name");

-- CreateIndex
CREATE UNIQUE INDEX "sym_idx_d_channel_id" ON "sym_data"("data_id", "channel_id");

-- CreateIndex
CREATE INDEX "sym_idx_de_batchid" ON "sym_data_event"("batch_id");

-- CreateIndex
CREATE INDEX "sym_idx_er_ld_src_nd" ON "sym_extract_request"("load_id", "source_node_id");

-- CreateIndex
CREATE INDEX "sym_idx_er_src_nd_st" ON "sym_extract_request"("source_node_id", "status");

-- CreateIndex
CREATE INDEX "sym_idx_f_snpsht_chid" ON "sym_file_snapshot"("reload_channel_id");

-- CreateIndex
CREATE INDEX "sym_idx_ib_in_error" ON "sym_incoming_batch"("error_flag");

-- CreateIndex
CREATE INDEX "sym_idx_ib_time_status" ON "sym_incoming_batch"("create_time", "status");

-- CreateIndex
CREATE INDEX "sym_idx_nd_hst_chnl_sts" ON "sym_node_host_channel_stats"("node_id", "start_time", "end_time");

-- CreateIndex
CREATE INDEX "sym_idx_nd_hst_job" ON "sym_node_host_job_stats"("node_id", "start_time", "end_time");

-- CreateIndex
CREATE INDEX "sym_idx_nd_hst_sts" ON "sym_node_host_stats"("node_id", "start_time", "end_time");

-- CreateIndex
CREATE INDEX "sym_idx_ob_in_error" ON "sym_outgoing_batch"("error_flag");

-- CreateIndex
CREATE INDEX "sym_idx_ob_load_id" ON "sym_outgoing_batch"("load_id");

-- CreateIndex
CREATE INDEX "sym_idx_ob_node_status" ON "sym_outgoing_batch"("node_id", "status", "channel_id");

-- CreateIndex
CREATE INDEX "sym_idx_ob_status" ON "sym_outgoing_batch"("status");

-- CreateIndex
CREATE INDEX "sym_idx_reg_req_1" ON "sym_registration_request"("node_group_id", "external_id", "status", "host_name", "ip_address");

-- CreateIndex
CREATE INDEX "sym_idx_reg_req_2" ON "sym_registration_request"("status");

-- CreateIndex
CREATE INDEX "sym_idx_tbl_rld_sts" ON "sym_table_reload_status"("target_node_id", "source_node_id", "completed", "cancelled");

-- CreateIndex
CREATE INDEX "sym_idx_trigg_hist_1" ON "sym_trigger_hist"("trigger_id", "inactive_time");

-- CreateIndex
CREATE INDEX "idx_sync_log_device" ON "sync_log"("device_id", "synced_at" DESC);

-- CreateIndex
CREATE INDEX "idx_sync_log_entity" ON "sync_log"("entity_type", "entity_id");

-- CreateIndex
CREATE INDEX "idx_sync_log_seq" ON "sync_log"("server_seq");

-- CreateIndex
CREATE UNIQUE INDEX "users_username_key" ON "users"("username");

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "idx_users_branch" ON "users"("branch_id");

-- CreateIndex
CREATE INDEX "idx_users_role" ON "users"("role_id");

-- CreateIndex
CREATE INDEX "idx_users_username" ON "users"("username");

-- CreateIndex
CREATE UNIQUE INDEX "warehouse_transfers_transfer_number_key" ON "warehouse_transfers"("transfer_number");

-- CreateIndex
CREATE UNIQUE INDEX "warehouse_transfers_idempotency_key_key" ON "warehouse_transfers"("idempotency_key");

-- CreateIndex
CREATE INDEX "idx_transfers_dest" ON "warehouse_transfers"("destination_warehouse_id");

-- CreateIndex
CREATE INDEX "idx_transfers_source" ON "warehouse_transfers"("source_warehouse_id");

-- CreateIndex
CREATE INDEX "idx_transfers_status" ON "warehouse_transfers"("status");

-- CreateIndex
CREATE UNIQUE INDEX "warehouses_code_key" ON "warehouses"("code");

-- CreateIndex
CREATE INDEX "warehouses_branch_id_status_idx" ON "warehouses"("branch_id", "status");

-- CreateIndex
CREATE INDEX "warehouses_parent_warehouse_id_idx" ON "warehouses"("parent_warehouse_id");

-- CreateIndex
CREATE UNIQUE INDEX "warehouse_keepers_warehouse_id_user_id_key" ON "warehouse_keepers"("warehouse_id", "user_id");

-- CreateIndex
CREATE INDEX "ecommerce_product_settings_variant_id_idx" ON "ecommerce_product_settings"("variant_id");

-- CreateIndex
CREATE INDEX "ecommerce_product_settings_is_enabled_idx" ON "ecommerce_product_settings"("is_enabled");

-- CreateIndex
CREATE UNIQUE INDEX "ecommerce_product_settings_variant_id_unit_id_key" ON "ecommerce_product_settings"("variant_id", "unit_id");

-- CreateIndex
CREATE UNIQUE INDEX "ecommerce_carts_user_id_key" ON "ecommerce_carts"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "ecommerce_carts_session_token_key" ON "ecommerce_carts"("session_token");

-- CreateIndex
CREATE INDEX "ecommerce_carts_source_idx" ON "ecommerce_carts"("source");

-- CreateIndex
CREATE INDEX "ecommerce_cart_items_cart_id_idx" ON "ecommerce_cart_items"("cart_id");

-- CreateIndex
CREATE INDEX "ecommerce_cart_items_variant_id_idx" ON "ecommerce_cart_items"("variant_id");

-- CreateIndex
CREATE INDEX "ecommerce_cart_items_unit_id_idx" ON "ecommerce_cart_items"("unit_id");

-- CreateIndex
CREATE UNIQUE INDEX "ecommerce_cart_items_cart_id_variant_id_unit_id_key" ON "ecommerce_cart_items"("cart_id", "variant_id", "unit_id");

-- CreateIndex
CREATE UNIQUE INDEX "ecommerce_orders_order_number_key" ON "ecommerce_orders"("order_number");

-- CreateIndex
CREATE UNIQUE INDEX "ecommerce_orders_sales_invoice_id_key" ON "ecommerce_orders"("sales_invoice_id");

-- CreateIndex
CREATE UNIQUE INDEX "ecommerce_orders_public_token_key" ON "ecommerce_orders"("public_token");

-- CreateIndex
CREATE UNIQUE INDEX "ecommerce_orders_idempotency_key_key" ON "ecommerce_orders"("idempotency_key");

-- CreateIndex
CREATE INDEX "ecommerce_orders_status_idx" ON "ecommerce_orders"("status");

-- CreateIndex
CREATE INDEX "ecommerce_orders_source_idx" ON "ecommerce_orders"("source");

-- CreateIndex
CREATE INDEX "ecommerce_orders_user_id_idx" ON "ecommerce_orders"("user_id");

-- CreateIndex
CREATE INDEX "ecommerce_orders_rep_id_idx" ON "ecommerce_orders"("rep_id");

-- CreateIndex
CREATE INDEX "ecommerce_orders_party_type_party_id_idx" ON "ecommerce_orders"("party_type", "party_id");

-- CreateIndex
CREATE INDEX "ecommerce_orders_customer_phone_idx" ON "ecommerce_orders"("customer_phone");

-- CreateIndex
CREATE INDEX "ecommerce_orders_submitted_at_idx" ON "ecommerce_orders"("submitted_at");

-- CreateIndex
CREATE INDEX "ecommerce_order_items_order_id_idx" ON "ecommerce_order_items"("order_id");

-- CreateIndex
CREATE INDEX "ecommerce_order_items_product_id_idx" ON "ecommerce_order_items"("product_id");

-- CreateIndex
CREATE INDEX "ecommerce_order_items_variant_id_idx" ON "ecommerce_order_items"("variant_id");

-- CreateIndex
CREATE INDEX "ecommerce_order_items_unit_id_idx" ON "ecommerce_order_items"("unit_id");

-- AddForeignKey
ALTER TABLE "branches" ADD CONSTRAINT "branches_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "branches" ADD CONSTRAINT "branches_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "branches" ADD CONSTRAINT "branches_manager_id_fkey" FOREIGN KEY ("manager_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cashbox_sessions" ADD CONSTRAINT "cashbox_sessions_cashbox_id_fkey" FOREIGN KEY ("cashbox_id") REFERENCES "cashboxes"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "cashbox_sessions" ADD CONSTRAINT "cashbox_sessions_closed_by_fkey" FOREIGN KEY ("closed_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "cashbox_sessions" ADD CONSTRAINT "cashbox_sessions_opened_by_fkey" FOREIGN KEY ("opened_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "cashboxes" ADD CONSTRAINT "cashboxes_assigned_user_id_fkey" FOREIGN KEY ("assigned_user_id") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "cashboxes" ADD CONSTRAINT "cashboxes_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "branches"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "categories" ADD CONSTRAINT "categories_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "categories"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "customers" ADD CONSTRAINT "customers_assigned_rep_id_fkey" FOREIGN KEY ("assigned_rep_id") REFERENCES "representatives"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "customers" ADD CONSTRAINT "customers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "device_sync_state" ADD CONSTRAINT "device_sync_state_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "branches"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "device_sync_state" ADD CONSTRAINT "device_sync_state_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "inventory_movements" ADD CONSTRAINT "inventory_movements_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "product_batches"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "inventory_movements" ADD CONSTRAINT "inventory_movements_performed_by_fkey" FOREIGN KEY ("performed_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "inventory_movements" ADD CONSTRAINT "inventory_movements_serial_id_fkey" FOREIGN KEY ("serial_id") REFERENCES "serials"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "inventory_movements" ADD CONSTRAINT "inventory_movements_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "inventory_movements" ADD CONSTRAINT "inventory_movements_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "warehouses"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "payment_vouchers" ADD CONSTRAINT "payment_vouchers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_vouchers" ADD CONSTRAINT "payment_vouchers_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "purchase_invoices"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_vouchers" ADD CONSTRAINT "payment_vouchers_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "suppliers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_vouchers" ADD CONSTRAINT "payment_vouchers_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "customers"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "payment_vouchers" ADD CONSTRAINT "payment_vouchers_cashbox_id_fkey" FOREIGN KEY ("cashbox_id") REFERENCES "cashboxes"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "payment_vouchers" ADD CONSTRAINT "payment_vouchers_sales_invoice_id_fkey" FOREIGN KEY ("sales_invoice_id") REFERENCES "sales_invoices"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "product_allowed_units" ADD CONSTRAINT "product_allowed_units_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "product_allowed_units" ADD CONSTRAINT "product_allowed_units_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "units_of_measure"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "product_batches" ADD CONSTRAINT "product_batches_purchase_item_id_fkey" FOREIGN KEY ("purchase_item_id") REFERENCES "purchase_invoice_items"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "product_batches" ADD CONSTRAINT "product_batches_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "product_batches" ADD CONSTRAINT "product_batches_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "warehouses"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "product_prices" ADD CONSTRAINT "product_prices_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "units_of_measure"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "product_prices" ADD CONSTRAINT "product_prices_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "product_variants" ADD CONSTRAINT "product_variants_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "products" ADD CONSTRAINT "products_base_unit_id_fkey" FOREIGN KEY ("base_unit_id") REFERENCES "units_of_measure"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "products" ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "categories"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "products" ADD CONSTRAINT "products_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "purchase_invoice_items" ADD CONSTRAINT "purchase_invoice_items_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "purchase_invoices"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "purchase_invoice_items" ADD CONSTRAINT "purchase_invoice_items_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "units_of_measure"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "purchase_invoice_items" ADD CONSTRAINT "purchase_invoice_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "purchase_invoices" ADD CONSTRAINT "purchase_invoices_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_invoices" ADD CONSTRAINT "purchase_invoices_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "suppliers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_invoices" ADD CONSTRAINT "purchase_invoices_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "warehouses"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "rep_custody_items" ADD CONSTRAINT "rep_custody_items_custody_order_id_fkey" FOREIGN KEY ("custody_order_id") REFERENCES "rep_custody_orders"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "rep_custody_items" ADD CONSTRAINT "rep_custody_items_serial_id_fkey" FOREIGN KEY ("serial_id") REFERENCES "serials"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "rep_custody_items" ADD CONSTRAINT "rep_custody_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "rep_custody_orders" ADD CONSTRAINT "rep_custody_orders_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "rep_custody_orders" ADD CONSTRAINT "rep_custody_orders_rep_id_fkey" FOREIGN KEY ("rep_id") REFERENCES "representatives"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "rep_custody_orders" ADD CONSTRAINT "rep_custody_orders_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "warehouses"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "representatives" ADD CONSTRAINT "representatives_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "branches"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "representatives" ADD CONSTRAINT "representatives_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "role_permissions" ADD CONSTRAINT "role_permissions_permission_id_fkey" FOREIGN KEY ("permission_id") REFERENCES "permissions"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "role_permissions" ADD CONSTRAINT "role_permissions_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "roles"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sales_invoice_items" ADD CONSTRAINT "sales_invoice_items_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "product_batches"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sales_invoice_items" ADD CONSTRAINT "sales_invoice_items_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "sales_invoices"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sales_invoice_items" ADD CONSTRAINT "sales_invoice_items_serial_id_fkey" FOREIGN KEY ("serial_id") REFERENCES "serials"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sales_invoice_items" ADD CONSTRAINT "sales_invoice_items_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "units_of_measure"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sales_invoice_items" ADD CONSTRAINT "sales_invoice_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sales_invoices" ADD CONSTRAINT "sales_invoices_cashbox_id_fkey" FOREIGN KEY ("cashbox_id") REFERENCES "cashboxes"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sales_invoices" ADD CONSTRAINT "sales_invoices_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sales_invoices" ADD CONSTRAINT "sales_invoices_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "customers"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sales_invoices" ADD CONSTRAINT "sales_invoices_rep_id_fkey" FOREIGN KEY ("rep_id") REFERENCES "representatives"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sales_invoices" ADD CONSTRAINT "sales_invoices_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "cashbox_sessions"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sales_invoices" ADD CONSTRAINT "sales_invoices_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "warehouses"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "serials" ADD CONSTRAINT "serials_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "serials" ADD CONSTRAINT "serials_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "warehouses"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "stock_levels" ADD CONSTRAINT "stock_levels_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "stock_levels" ADD CONSTRAINT "stock_levels_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "warehouses"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "stocktaking_items" ADD CONSTRAINT "stocktaking_items_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "product_batches"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "stocktaking_items" ADD CONSTRAINT "stocktaking_items_serial_id_fkey" FOREIGN KEY ("serial_id") REFERENCES "serials"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "stocktaking_items" ADD CONSTRAINT "stocktaking_items_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "stocktaking_sessions"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "stocktaking_items" ADD CONSTRAINT "stocktaking_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "stocktaking_sessions" ADD CONSTRAINT "stocktaking_sessions_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "stocktaking_sessions" ADD CONSTRAINT "stocktaking_sessions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "stocktaking_sessions" ADD CONSTRAINT "stocktaking_sessions_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "warehouses"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "suppliers" ADD CONSTRAINT "suppliers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sym_conflict" ADD CONSTRAINT "sym_fk_cf_2_grp_lnk" FOREIGN KEY ("source_node_group_id", "target_node_group_id") REFERENCES "sym_node_group_link"("source_node_group_id", "target_node_group_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_file_trigger_router" ADD CONSTRAINT "sym_fk_ftr_2_ftrg" FOREIGN KEY ("trigger_id") REFERENCES "sym_file_trigger"("trigger_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_file_trigger_router" ADD CONSTRAINT "sym_fk_ftr_2_rtr" FOREIGN KEY ("router_id") REFERENCES "sym_router"("router_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_grouplet_link" ADD CONSTRAINT "sym_fk_gpltlnk_2_gplt" FOREIGN KEY ("grouplet_id") REFERENCES "sym_grouplet"("grouplet_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_node_group_link" ADD CONSTRAINT "sym_fk_lnk_2_grp_src" FOREIGN KEY ("source_node_group_id") REFERENCES "sym_node_group"("node_group_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_node_group_link" ADD CONSTRAINT "sym_fk_lnk_2_grp_tgt" FOREIGN KEY ("target_node_group_id") REFERENCES "sym_node_group"("node_group_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_node_identity" ADD CONSTRAINT "sym_fk_ident_2_node" FOREIGN KEY ("node_id") REFERENCES "sym_node"("node_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_node_security" ADD CONSTRAINT "sym_fk_sec_2_node" FOREIGN KEY ("node_id") REFERENCES "sym_node"("node_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_router" ADD CONSTRAINT "sym_fk_rt_2_grp_lnk" FOREIGN KEY ("source_node_group_id", "target_node_group_id") REFERENCES "sym_node_group_link"("source_node_group_id", "target_node_group_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_transform_table" ADD CONSTRAINT "sym_fk_tt_2_grp_lnk" FOREIGN KEY ("source_node_group_id", "target_node_group_id") REFERENCES "sym_node_group_link"("source_node_group_id", "target_node_group_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_trigger" ADD CONSTRAINT "sym_fk_trg_2_chnl" FOREIGN KEY ("channel_id") REFERENCES "sym_channel"("channel_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_trigger" ADD CONSTRAINT "sym_fk_trg_2_rld_chnl" FOREIGN KEY ("reload_channel_id") REFERENCES "sym_channel"("channel_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_trigger_router" ADD CONSTRAINT "sym_fk_tr_2_rtr" FOREIGN KEY ("router_id") REFERENCES "sym_router"("router_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_trigger_router" ADD CONSTRAINT "sym_fk_tr_2_trg" FOREIGN KEY ("trigger_id") REFERENCES "sym_trigger"("trigger_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_trigger_router_grouplet" ADD CONSTRAINT "sym_fk_trgplt_2_gplt" FOREIGN KEY ("grouplet_id") REFERENCES "sym_grouplet"("grouplet_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sym_trigger_router_grouplet" ADD CONSTRAINT "sym_fk_trgplt_2_tr" FOREIGN KEY ("trigger_id", "router_id") REFERENCES "sym_trigger_router"("trigger_id", "router_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "units_of_measure" ADD CONSTRAINT "units_of_measure_parent_unit_id_fkey" FOREIGN KEY ("parent_unit_id") REFERENCES "units_of_measure"("id") ON DELETE RESTRICT ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "fk_users_branch" FOREIGN KEY ("branch_id") REFERENCES "branches"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "roles"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouse_transfer_items" ADD CONSTRAINT "warehouse_transfer_items_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "product_batches"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouse_transfer_items" ADD CONSTRAINT "warehouse_transfer_items_serial_id_fkey" FOREIGN KEY ("serial_id") REFERENCES "serials"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouse_transfer_items" ADD CONSTRAINT "warehouse_transfer_items_transfer_id_fkey" FOREIGN KEY ("transfer_id") REFERENCES "warehouse_transfers"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouse_transfer_items" ADD CONSTRAINT "warehouse_transfer_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouse_transfers" ADD CONSTRAINT "warehouse_transfers_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouse_transfers" ADD CONSTRAINT "warehouse_transfers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouse_transfers" ADD CONSTRAINT "warehouse_transfers_destination_warehouse_id_fkey" FOREIGN KEY ("destination_warehouse_id") REFERENCES "warehouses"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouse_transfers" ADD CONSTRAINT "warehouse_transfers_dispatched_by_fkey" FOREIGN KEY ("dispatched_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouse_transfers" ADD CONSTRAINT "warehouse_transfers_received_by_fkey" FOREIGN KEY ("received_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouse_transfers" ADD CONSTRAINT "warehouse_transfers_source_warehouse_id_fkey" FOREIGN KEY ("source_warehouse_id") REFERENCES "warehouses"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouses" ADD CONSTRAINT "warehouses_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "branches"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "warehouses" ADD CONSTRAINT "warehouses_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "warehouses" ADD CONSTRAINT "warehouses_manager_id_fkey" FOREIGN KEY ("manager_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "warehouses" ADD CONSTRAINT "warehouses_parent_warehouse_id_fkey" FOREIGN KEY ("parent_warehouse_id") REFERENCES "warehouses"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "warehouse_keepers" ADD CONSTRAINT "warehouse_keepers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "warehouse_keepers" ADD CONSTRAINT "warehouse_keepers_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "warehouses"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ecommerce_product_settings" ADD CONSTRAINT "ecommerce_product_settings_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "units_of_measure"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_product_settings" ADD CONSTRAINT "ecommerce_product_settings_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_carts" ADD CONSTRAINT "ecommerce_carts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_cart_items" ADD CONSTRAINT "ecommerce_cart_items_cart_id_fkey" FOREIGN KEY ("cart_id") REFERENCES "ecommerce_carts"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_cart_items" ADD CONSTRAINT "ecommerce_cart_items_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "units_of_measure"("id") ON DELETE RESTRICT ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_cart_items" ADD CONSTRAINT "ecommerce_cart_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE RESTRICT ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_orders" ADD CONSTRAINT "ecommerce_orders_accepted_by_fkey" FOREIGN KEY ("accepted_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_orders" ADD CONSTRAINT "ecommerce_orders_cancelled_by_fkey" FOREIGN KEY ("cancelled_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_orders" ADD CONSTRAINT "ecommerce_orders_rejected_by_fkey" FOREIGN KEY ("rejected_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_orders" ADD CONSTRAINT "ecommerce_orders_rep_id_fkey" FOREIGN KEY ("rep_id") REFERENCES "representatives"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_orders" ADD CONSTRAINT "ecommerce_orders_sales_invoice_id_fkey" FOREIGN KEY ("sales_invoice_id") REFERENCES "sales_invoices"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_orders" ADD CONSTRAINT "ecommerce_orders_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_order_items" ADD CONSTRAINT "ecommerce_order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "ecommerce_orders"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_order_items" ADD CONSTRAINT "ecommerce_order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_order_items" ADD CONSTRAINT "ecommerce_order_items_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "units_of_measure"("id") ON DELETE RESTRICT ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ecommerce_order_items" ADD CONSTRAINT "ecommerce_order_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE RESTRICT ON UPDATE NO ACTION;
