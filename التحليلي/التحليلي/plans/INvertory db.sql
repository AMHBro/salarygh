-- ============================================================
-- 🗄️ Sayler Sales System — Full Database Schema
-- Database: PostgreSQL (Supabase)
-- Version: 1.0 | Date: August 2026
-- ============================================================
-- Run this script in: Supabase Dashboard → SQL Editor
-- ============================================================

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 1: Extensions
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 2: ENUM Types
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TYPE warehouse_type_enum     AS ENUM ('MAIN', 'SUB', 'VIRTUAL');
CREATE TYPE price_type_enum         AS ENUM ('RETAIL', 'WHOLESALE', 'REP', 'COST');
CREATE TYPE purchase_payment_enum   AS ENUM ('CASH', 'CREDIT', 'PARTIAL');
CREATE TYPE purchase_status_enum    AS ENUM ('DRAFT', 'CONFIRMED', 'PARTIAL', 'PAID', 'CANCELLED');
CREATE TYPE movement_type_enum      AS ENUM ('IN', 'OUT', 'TRANSFER_OUT', 'TRANSFER_IN', 'ADJUST_ADD', 'ADJUST_REDUCE', 'RETURN_IN', 'RETURN_OUT');
CREATE TYPE transfer_status_enum    AS ENUM ('PENDING', 'APPROVED', 'DISPATCHED', 'RECEIVED', 'CANCELLED');
CREATE TYPE stocktaking_type_enum   AS ENUM ('BLIND', 'VISIBLE');
CREATE TYPE stocktaking_status_enum AS ENUM ('OPEN', 'COUNTING', 'PENDING_REVIEW', 'PENDING_VALUATION', 'APPROVED', 'CANCELLED');
CREATE TYPE adjustment_type_enum    AS ENUM ('NONE', 'ADD', 'REDUCE');
CREATE TYPE sales_payment_enum      AS ENUM ('CASH', 'CREDIT', 'PARTIAL', 'REP_CUSTODY');
CREATE TYPE sales_status_enum       AS ENUM ('DRAFT', 'PAID', 'PARTIAL', 'OVERDUE', 'CANCELLED', 'RETURNED');
CREATE TYPE cashbox_status_enum     AS ENUM ('OPEN', 'CLOSED');
CREATE TYPE customer_type_enum      AS ENUM ('RETAIL', 'WHOLESALE');
CREATE TYPE rep_status_enum         AS ENUM ('ACTIVE', 'INACTIVE');
CREATE TYPE commission_type_enum    AS ENUM ('PERCENT', 'FIXED');
CREATE TYPE custody_status_enum     AS ENUM ('PENDING', 'APPROVED', 'DISPATCHED', 'PARTIALLY_RETURNED', 'FULLY_RETURNED', 'CANCELLED');
CREATE TYPE account_type_enum       AS ENUM ('CUSTOMER', 'SUPPLIER', 'REPRESENTATIVE');
CREATE TYPE voucher_type_enum       AS ENUM ('RECEIPT', 'PAYMENT');
CREATE TYPE payment_method_enum     AS ENUM ('CASH', 'BANK_TRANSFER', 'CHECK', 'POS_MACHINE');
CREATE TYPE serial_status_enum      AS ENUM ('IN_STOCK', 'SOLD', 'IN_CUSTODY', 'RETURNED');
CREATE TYPE sync_operation_enum     AS ENUM ('CREATE', 'UPDATE', 'DELETE');

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 3: M01 — Company, Roles, Users
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE companies (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(200) NOT NULL,
    logo_url    TEXT,
    address     TEXT,
    phone       VARCHAR(20),
    email       VARCHAR(100),
    tax_number  VARCHAR(50),
    settings    JSONB NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE roles (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    is_system   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE permissions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource    VARCHAR(100) NOT NULL,
    action      VARCHAR(50)  NOT NULL,
    description TEXT,
    UNIQUE (resource, action)
);

CREATE TABLE role_permissions (
    role_id       UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- Users (branch_id FK added after branches table)
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username      VARCHAR(100) NOT NULL UNIQUE,
    email         VARCHAR(150) UNIQUE,
    password_hash TEXT NOT NULL,
    full_name     VARCHAR(200),
    phone         VARCHAR(20),
    role_id       UUID REFERENCES roles(id),
    branch_id     UUID,                          -- FK added later
    avatar_url    TEXT,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    last_login    TIMESTAMPTZ,
    refresh_token TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by    UUID REFERENCES users(id)
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 4: M02 — Branches & Warehouses
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE branches (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID NOT NULL REFERENCES companies(id),
    name        VARCHAR(200) NOT NULL,
    address     TEXT,
    phone       VARCHAR(20),
    manager_id  UUID REFERENCES users(id),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Now add the FK from users to branches
ALTER TABLE users ADD CONSTRAINT fk_users_branch
    FOREIGN KEY (branch_id) REFERENCES branches(id);

CREATE TABLE warehouses (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id   UUID NOT NULL REFERENCES branches(id),
    name        VARCHAR(200) NOT NULL,
    address     TEXT,
    type        warehouse_type_enum NOT NULL DEFAULT 'SUB',
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 5: M03 — Categories, Units, Products
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Categories — Self-Join (Hierarchical)
CREATE TABLE categories (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name_ar     VARCHAR(200) NOT NULL,
    name_en     VARCHAR(200),
    parent_id   UUID REFERENCES categories(id) ON DELETE SET NULL,  -- Self-Join
    level       INT NOT NULL DEFAULT 0,       -- 0=رئيسي, 1=فرعي, 2=فرعي-فرعي
    path        TEXT,                         -- 'uuid1/uuid2/uuid3' للبحث السريع
    image_url   TEXT,
    order_index INT NOT NULL DEFAULT 0,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Units of Measure — Self-Join (with Conversion)
CREATE TABLE units_of_measure (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name_ar           VARCHAR(100) NOT NULL,
    name_en           VARCHAR(100),
    symbol            VARCHAR(20),
    parent_unit_id    UUID REFERENCES units_of_measure(id) ON DELETE RESTRICT, -- Self-Join
    conversion_factor DECIMAL(15,6) NOT NULL DEFAULT 1,  -- كم وحدة أساسية في هذه الوحدة
    is_base_unit      BOOLEAN NOT NULL DEFAULT FALSE,    -- الوحدة الأساسية للتخزين
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Products
CREATE TABLE products (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku             VARCHAR(100) UNIQUE,
    barcode         VARCHAR(100) UNIQUE,
    name_ar         VARCHAR(300) NOT NULL,
    name_en         VARCHAR(300),
    category_id     UUID REFERENCES categories(id),
    description     TEXT,
    base_unit_id    UUID NOT NULL REFERENCES units_of_measure(id),  -- وحدة التخزين الأساسية
    has_variants    BOOLEAN NOT NULL DEFAULT FALSE,
    has_serial      BOOLEAN NOT NULL DEFAULT FALSE,
    has_expiry      BOOLEAN NOT NULL DEFAULT FALSE,
    image_url       TEXT,
    images          JSONB NOT NULL DEFAULT '[]',
    min_stock_level DECIMAL(15,3) NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID REFERENCES users(id)
);

-- Product Variants (Colors/Sizes)
CREATE TABLE product_variants (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id          UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    sku                 VARCHAR(100) UNIQUE,
    barcode             VARCHAR(100) UNIQUE,
    attributes          JSONB NOT NULL DEFAULT '{}',        -- {"color": "أحمر", "size": "XL"}
    weighted_avg_cost   DECIMAL(15,4) NOT NULL DEFAULT 0,  -- WAC بوحدة الأساس
    last_purchase_price DECIMAL(15,4) NOT NULL DEFAULT 0,  -- آخر سعر شراء بوحدة الأساس
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Product Prices (RETAIL / WHOLESALE / REP) per Unit
CREATE TABLE product_prices (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_id  UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    price_type  price_type_enum NOT NULL,
    unit_id     UUID NOT NULL REFERENCES units_of_measure(id),
    price       DECIMAL(15,4) NOT NULL CHECK (price >= 0),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (variant_id, price_type, unit_id)
);

-- Product Allowed Units (what units can be used for buying/selling)
CREATE TABLE product_allowed_units (
    product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    unit_id     UUID NOT NULL REFERENCES units_of_measure(id) ON DELETE CASCADE,
    can_buy     BOOLEAN NOT NULL DEFAULT TRUE,
    can_sell    BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (product_id, unit_id)
);

-- Serials (Serial Numbers per Variant)
CREATE TABLE serials (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_id   UUID NOT NULL REFERENCES product_variants(id),
    serial_no    VARCHAR(200) NOT NULL UNIQUE,
    status       serial_status_enum NOT NULL DEFAULT 'IN_STOCK',
    warehouse_id UUID REFERENCES warehouses(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 6: M04 — Suppliers & Purchases
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE suppliers (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(300) NOT NULL,
    phone        VARCHAR(20),
    email        VARCHAR(150),
    address      TEXT,
    tax_number   VARCHAR(50),
    balance      DECIMAL(15,2) NOT NULL DEFAULT 0,
    credit_limit DECIMAL(15,2) NOT NULL DEFAULT 0,
    notes        TEXT,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by   UUID REFERENCES users(id)
);

CREATE TABLE purchase_invoices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_number  VARCHAR(50) NOT NULL UNIQUE,
    supplier_id     UUID NOT NULL REFERENCES suppliers(id),
    warehouse_id    UUID NOT NULL REFERENCES warehouses(id),
    status          purchase_status_enum NOT NULL DEFAULT 'DRAFT',
    payment_type    purchase_payment_enum NOT NULL DEFAULT 'CASH',
    subtotal        DECIMAL(15,2) NOT NULL DEFAULT 0,
    discount_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    tax_amount      DECIMAL(15,2) NOT NULL DEFAULT 0,
    total           DECIMAL(15,2) NOT NULL DEFAULT 0,
    paid_amount     DECIMAL(15,2) NOT NULL DEFAULT 0,
    due_amount      DECIMAL(15,2) GENERATED ALWAYS AS (total - paid_amount) STORED,
    notes           TEXT,
    invoice_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date        DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID REFERENCES users(id)
);

CREATE TABLE purchase_invoice_items (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id            UUID NOT NULL REFERENCES purchase_invoices(id) ON DELETE CASCADE,
    variant_id            UUID NOT NULL REFERENCES product_variants(id),
    unit_id               UUID NOT NULL REFERENCES units_of_measure(id),  -- وحدة الشراء
    batch_number          VARCHAR(100),
    expiry_date           DATE,
    quantity              DECIMAL(15,3) NOT NULL CHECK (quantity > 0),
    quantity_in_base_unit DECIMAL(15,3) NOT NULL,   -- بعد التحويل → يدخل المخزن
    unit_cost             DECIMAL(15,4) NOT NULL,   -- سعر وحدة الشراء (سعر الكرتون)
    cost_per_base_unit    DECIMAL(15,4) NOT NULL,   -- سعر الوحدة الأساسية → لحساب WAC
    discount_percent      DECIMAL(5,2) NOT NULL DEFAULT 0,
    total_price           DECIMAL(15,2) NOT NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 7: M05 — Inventory
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE stock_levels (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_id           UUID NOT NULL REFERENCES product_variants(id),
    warehouse_id         UUID NOT NULL REFERENCES warehouses(id),
    quantity_on_hand     DECIMAL(15,3) NOT NULL DEFAULT 0,
    quantity_reserved    DECIMAL(15,3) NOT NULL DEFAULT 0,
    quantity_in_transit  DECIMAL(15,3) NOT NULL DEFAULT 0,
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (variant_id, warehouse_id)
);

CREATE TABLE product_batches (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_id        UUID NOT NULL REFERENCES product_variants(id),
    warehouse_id      UUID NOT NULL REFERENCES warehouses(id),
    batch_number      VARCHAR(100),
    expiry_date       DATE,
    quantity          DECIMAL(15,3) NOT NULL DEFAULT 0,
    unit_cost         DECIMAL(15,4) NOT NULL,           -- تكلفة بالوحدة الأساسية
    received_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    purchase_item_id  UUID REFERENCES purchase_invoice_items(id)
);

CREATE TABLE inventory_movements (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    movement_type  movement_type_enum NOT NULL,
    variant_id     UUID NOT NULL REFERENCES product_variants(id),
    warehouse_id   UUID NOT NULL REFERENCES warehouses(id),
    quantity       DECIMAL(15,3) NOT NULL,
    unit_cost      DECIMAL(15,4),
    reference_type VARCHAR(50),   -- 'purchase', 'sale', 'transfer', 'stocktaking'
    reference_id   UUID,
    batch_id       UUID REFERENCES product_batches(id),
    serial_id      UUID REFERENCES serials(id),
    notes          TEXT,
    performed_by   UUID REFERENCES users(id),
    device_id      UUID,
    version        INT NOT NULL DEFAULT 1,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 8: M06 — Warehouse Transfers
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE warehouse_transfers (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transfer_number          VARCHAR(50) NOT NULL UNIQUE,
    source_warehouse_id      UUID NOT NULL REFERENCES warehouses(id),
    destination_warehouse_id UUID NOT NULL REFERENCES warehouses(id),
    status                   transfer_status_enum NOT NULL DEFAULT 'PENDING',
    dispatch_date            TIMESTAMPTZ,
    receive_date             TIMESTAMPTZ,
    notes                    TEXT,
    idempotency_key          VARCHAR(200) UNIQUE,
    approved_by              UUID REFERENCES users(id),
    dispatched_by            UUID REFERENCES users(id),
    received_by              UUID REFERENCES users(id),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by               UUID REFERENCES users(id),
    CONSTRAINT chk_diff_warehouses CHECK (source_warehouse_id <> destination_warehouse_id)
);

CREATE TABLE warehouse_transfer_items (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transfer_id       UUID NOT NULL REFERENCES warehouse_transfers(id) ON DELETE CASCADE,
    variant_id        UUID NOT NULL REFERENCES product_variants(id),
    batch_id          UUID REFERENCES product_batches(id),
    serial_id         UUID REFERENCES serials(id),
    quantity_sent     DECIMAL(15,3) NOT NULL CHECK (quantity_sent > 0),
    quantity_received DECIMAL(15,3) NOT NULL DEFAULT 0,
    quantity_shortage DECIMAL(15,3) NOT NULL DEFAULT 0,
    quantity_damaged  DECIMAL(15,3) NOT NULL DEFAULT 0,
    CONSTRAINT chk_transfer_qty CHECK (
        quantity_received + quantity_shortage + quantity_damaged <= quantity_sent
    )
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 9: M07 — Stocktaking
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE stocktaking_sessions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_number VARCHAR(50) NOT NULL UNIQUE,
    warehouse_id   UUID NOT NULL REFERENCES warehouses(id),
    type           stocktaking_type_enum NOT NULL DEFAULT 'BLIND',
    status         stocktaking_status_enum NOT NULL DEFAULT 'OPEN',
    snapshot_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    approved_at    TIMESTAMPTZ,
    notes          TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by     UUID REFERENCES users(id),
    approved_by    UUID REFERENCES users(id)
);

CREATE TABLE stocktaking_items (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id       UUID NOT NULL REFERENCES stocktaking_sessions(id) ON DELETE CASCADE,
    variant_id       UUID NOT NULL REFERENCES product_variants(id),
    batch_id         UUID REFERENCES product_batches(id),
    serial_id        UUID REFERENCES serials(id),
    system_quantity  DECIMAL(15,3) NOT NULL DEFAULT 0,
    counted_quantity DECIMAL(15,3) NOT NULL DEFAULT 0,
    difference       DECIMAL(15,3) GENERATED ALWAYS AS (counted_quantity - system_quantity) STORED,
    unit_cost        DECIMAL(15,4),
    adjustment_type  adjustment_type_enum NOT NULL DEFAULT 'NONE',
    UNIQUE (session_id, variant_id, batch_id)
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 10: M09 — Representatives (before customers & sales)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE representatives (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL UNIQUE REFERENCES users(id),
    name            VARCHAR(300) NOT NULL,
    phone           VARCHAR(20),
    branch_id       UUID REFERENCES branches(id),
    commission_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
    commission_type commission_type_enum NOT NULL DEFAULT 'PERCENT',
    status          rep_status_enum NOT NULL DEFAULT 'ACTIVE',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 11: M08 — Customers, Cashboxes, Sales
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE customers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(300) NOT NULL,
    phone           VARCHAR(20) UNIQUE,
    email           VARCHAR(150),
    address         TEXT,
    type            customer_type_enum NOT NULL DEFAULT 'RETAIL',
    balance         DECIMAL(15,2) NOT NULL DEFAULT 0,
    credit_limit    DECIMAL(15,2) NOT NULL DEFAULT 0,
    assigned_rep_id UUID REFERENCES representatives(id),
    notes           TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID REFERENCES users(id)
);

CREATE TABLE cashboxes (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_code      VARCHAR(100) NOT NULL UNIQUE,
    cashbox_code     VARCHAR(100) NOT NULL UNIQUE,
    name             VARCHAR(200),
    branch_id        UUID REFERENCES branches(id),
    assigned_user_id UUID REFERENCES users(id),
    status           cashbox_status_enum NOT NULL DEFAULT 'CLOSED',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE cashbox_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cashbox_id      UUID NOT NULL REFERENCES cashboxes(id),
    opened_by       UUID NOT NULL REFERENCES users(id),
    closed_by       UUID REFERENCES users(id),
    opened_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at       TIMESTAMPTZ,
    opening_balance DECIMAL(15,2) NOT NULL DEFAULT 0,
    closing_balance DECIMAL(15,2) NOT NULL DEFAULT 0,
    total_sales     DECIMAL(15,2) NOT NULL DEFAULT 0,
    total_returns   DECIMAL(15,2) NOT NULL DEFAULT 0,
    status          cashbox_status_enum NOT NULL DEFAULT 'OPEN'
);

-- Unique: only one OPEN session per cashbox
CREATE UNIQUE INDEX uidx_cashbox_open_session
    ON cashbox_sessions (cashbox_id)
    WHERE status = 'OPEN';

CREATE TABLE sales_invoices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_number  VARCHAR(50) NOT NULL UNIQUE,
    cashbox_id      UUID REFERENCES cashboxes(id),
    session_id      UUID REFERENCES cashbox_sessions(id),
    customer_id     UUID REFERENCES customers(id),       -- NULL = زبون نقدي
    warehouse_id    UUID NOT NULL REFERENCES warehouses(id),
    rep_id          UUID REFERENCES representatives(id),
    price_type      price_type_enum NOT NULL DEFAULT 'RETAIL',
    payment_type    sales_payment_enum NOT NULL DEFAULT 'CASH',
    status          sales_status_enum NOT NULL DEFAULT 'DRAFT',
    subtotal        DECIMAL(15,2) NOT NULL DEFAULT 0,
    discount_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    total           DECIMAL(15,2) NOT NULL DEFAULT 0,
    paid_amount     DECIMAL(15,2) NOT NULL DEFAULT 0,
    due_amount      DECIMAL(15,2) NOT NULL DEFAULT 0,
    notes           TEXT,
    idempotency_key VARCHAR(200) NOT NULL UNIQUE,
    device_id       UUID,
    version         INT NOT NULL DEFAULT 1,
    invoice_date    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    due_date        DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID REFERENCES users(id)
);

CREATE TABLE sales_invoice_items (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id            UUID NOT NULL REFERENCES sales_invoices(id) ON DELETE CASCADE,
    variant_id            UUID NOT NULL REFERENCES product_variants(id),
    batch_id              UUID REFERENCES product_batches(id),
    serial_id             UUID REFERENCES serials(id),
    unit_id               UUID NOT NULL REFERENCES units_of_measure(id), -- وحدة البيع
    quantity              DECIMAL(15,3) NOT NULL CHECK (quantity > 0),
    quantity_in_base_unit DECIMAL(15,3) NOT NULL,   -- بعد التحويل → ينقص من المخزن
    unit_price            DECIMAL(15,4) NOT NULL,
    cost_per_base_unit    DECIMAL(15,4) NOT NULL,   -- WAC snapshot وقت البيع
    discount_percent      DECIMAL(5,2) NOT NULL DEFAULT 0,
    net_unit_price        DECIMAL(15,4) NOT NULL,
    total_price           DECIMAL(15,2) NOT NULL,
    CONSTRAINT chk_no_loss CHECK (net_unit_price >= 0)
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 12: M09 — Rep Custody
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE rep_custody_orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number    VARCHAR(50) NOT NULL UNIQUE,
    rep_id          UUID NOT NULL REFERENCES representatives(id),
    warehouse_id    UUID NOT NULL REFERENCES warehouses(id),
    status          custody_status_enum NOT NULL DEFAULT 'PENDING',
    dispatch_date   TIMESTAMPTZ,
    return_due_date DATE,
    notes           TEXT,
    idempotency_key VARCHAR(200) UNIQUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID REFERENCES users(id)
);

CREATE TABLE rep_custody_items (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    custody_order_id  UUID NOT NULL REFERENCES rep_custody_orders(id) ON DELETE CASCADE,
    variant_id        UUID NOT NULL REFERENCES product_variants(id),
    serial_id         UUID REFERENCES serials(id),
    quantity_sent     DECIMAL(15,3) NOT NULL CHECK (quantity_sent > 0),
    quantity_sold     DECIMAL(15,3) NOT NULL DEFAULT 0,
    quantity_returned DECIMAL(15,3) NOT NULL DEFAULT 0
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 13: M10 — Accounts & Payments
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE accounts_ledger (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_type     account_type_enum NOT NULL,
    account_id       UUID NOT NULL,
    total_debit      DECIMAL(15,2) NOT NULL DEFAULT 0,
    total_credit     DECIMAL(15,2) NOT NULL DEFAULT 0,
    balance          DECIMAL(15,2) GENERATED ALWAYS AS (total_debit - total_credit) STORED,
    last_transaction TIMESTAMPTZ,
    UNIQUE (account_type, account_id)
);

CREATE TABLE payment_vouchers (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    voucher_number   VARCHAR(50) NOT NULL UNIQUE,
    voucher_type     voucher_type_enum NOT NULL,
    account_type     account_type_enum NOT NULL,
    account_id       UUID NOT NULL,
    amount           DECIMAL(15,2) NOT NULL CHECK (amount > 0),
    payment_method   payment_method_enum NOT NULL DEFAULT 'CASH',
    bank_name        VARCHAR(100),
    reference_number VARCHAR(100),
    notes            TEXT,
    voucher_date     DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by       UUID REFERENCES users(id)
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 14: Sync Engine (Symatric DS support)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE sync_log (
    id                BIGSERIAL PRIMARY KEY,          -- BIGSERIAL للترتيب التسلسلي
    device_id         UUID NOT NULL,
    entity_type       VARCHAR(100) NOT NULL,
    entity_id         UUID NOT NULL,
    operation         sync_operation_enum NOT NULL,
    payload           JSONB NOT NULL,
    client_version    INT,
    server_seq        BIGINT,
    conflict_resolved BOOLEAN NOT NULL DEFAULT FALSE,
    conflict_notes    TEXT,
    synced_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE device_sync_state (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id    UUID NOT NULL UNIQUE,
    user_id      UUID REFERENCES users(id),
    branch_id    UUID REFERENCES branches(id),
    last_sync_at TIMESTAMPTZ,
    last_seq     BIGINT NOT NULL DEFAULT 0,
    device_info  JSONB NOT NULL DEFAULT '{}',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 15: Indexes
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Users
CREATE INDEX idx_users_role       ON users(role_id);
CREATE INDEX idx_users_branch     ON users(branch_id);
CREATE INDEX idx_users_username   ON users(username);

-- Categories
CREATE INDEX idx_categories_parent ON categories(parent_id);
CREATE INDEX idx_categories_path   ON categories(path);

-- Products
CREATE INDEX idx_products_category  ON products(category_id);
CREATE INDEX idx_products_barcode   ON products(barcode);
CREATE INDEX idx_products_sku       ON products(sku);
CREATE INDEX idx_products_active    ON products(is_active);

-- Product Variants
CREATE INDEX idx_variants_product ON product_variants(product_id);
CREATE INDEX idx_variants_barcode ON product_variants(barcode);

-- Product Prices
CREATE INDEX idx_prices_variant ON product_prices(variant_id, price_type);

-- Stock Levels
CREATE INDEX idx_stock_warehouse ON stock_levels(warehouse_id);
CREATE INDEX idx_stock_variant   ON stock_levels(variant_id);

-- Inventory Movements
CREATE INDEX idx_movements_variant   ON inventory_movements(variant_id, created_at DESC);
CREATE INDEX idx_movements_warehouse ON inventory_movements(warehouse_id, created_at DESC);
CREATE INDEX idx_movements_ref       ON inventory_movements(reference_type, reference_id);

-- Product Batches
CREATE INDEX idx_batches_variant  ON product_batches(variant_id, warehouse_id);
CREATE INDEX idx_batches_expiry   ON product_batches(expiry_date ASC)
    WHERE expiry_date IS NOT NULL;

-- Purchase Invoices
CREATE INDEX idx_purchase_supplier ON purchase_invoices(supplier_id);
CREATE INDEX idx_purchase_status   ON purchase_invoices(status);
CREATE INDEX idx_purchase_date     ON purchase_invoices(invoice_date DESC);

-- Sales Invoices
CREATE INDEX idx_sales_customer ON sales_invoices(customer_id);
CREATE INDEX idx_sales_status   ON sales_invoices(status);
CREATE INDEX idx_sales_date     ON sales_invoices(invoice_date DESC);
CREATE INDEX idx_sales_rep      ON sales_invoices(rep_id);
CREATE INDEX idx_sales_cashbox  ON sales_invoices(cashbox_id);
CREATE INDEX idx_sales_idem     ON sales_invoices(idempotency_key);

-- Customers
CREATE INDEX idx_customers_phone ON customers(phone);
CREATE INDEX idx_customers_rep   ON customers(assigned_rep_id);

-- Suppliers
CREATE INDEX idx_suppliers_name ON suppliers(name);

-- Warehouse Transfers
CREATE INDEX idx_transfers_source ON warehouse_transfers(source_warehouse_id);
CREATE INDEX idx_transfers_dest   ON warehouse_transfers(destination_warehouse_id);
CREATE INDEX idx_transfers_status ON warehouse_transfers(status);

-- Accounts & Payments
CREATE INDEX idx_accounts_entity   ON accounts_ledger(account_type, account_id);
CREATE INDEX idx_payments_account  ON payment_vouchers(account_type, account_id);
CREATE INDEX idx_payments_date     ON payment_vouchers(voucher_date DESC);

-- Sync
CREATE INDEX idx_sync_log_device   ON sync_log(device_id, synced_at DESC);
CREATE INDEX idx_sync_log_entity   ON sync_log(entity_type, entity_id);
CREATE INDEX idx_sync_log_seq      ON sync_log(server_seq ASC);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 16: Trigger — updated_at auto-update
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to all tables with updated_at
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'companies', 'users', 'branches', 'warehouses',
        'categories', 'products', 'product_variants', 'product_prices',
        'suppliers', 'purchase_invoices',
        'stock_levels', 'sales_invoices',
        'warehouse_transfers', 'stocktaking_sessions',
        'representatives', 'customers', 'cashboxes',
        'rep_custody_orders'
    ]
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%s_updated_at
             BEFORE UPDATE ON %s
             FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at()',
            t, t
        );
    END LOOP;
END;
$$;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- STEP 17: Seed — Default Data
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Default Roles
INSERT INTO roles (name, description, is_system) VALUES
    ('ADMIN',     'مدير النظام — صلاحيات كاملة',    TRUE),
    ('MANAGER',   'مدير الفرع',                      TRUE),
    ('CASHIER',   'كاشير — إدارة المبيعات فقط',      TRUE),
    ('REP',       'مندوب المبيعات',                  TRUE),
    ('WAREHOUSE', 'أمين المخزن',                      TRUE);

-- Default Units of Measure
INSERT INTO units_of_measure (name_ar, name_en, symbol, parent_unit_id, conversion_factor, is_base_unit) VALUES
    -- وحدات العدد
    ('قطعة',   'Piece',   'pcs',  NULL, 1,    TRUE),
    ('لتر',    'Liter',   'L',    NULL, 1,    TRUE),
    ('كيلو',   'Kilogram','kg',   NULL, 1,    TRUE),
    ('متر',    'Meter',   'm',    NULL, 1,    TRUE);

-- علبة = 12 قطعة
INSERT INTO units_of_measure (name_ar, name_en, symbol, parent_unit_id, conversion_factor, is_base_unit)
SELECT 'علبة', 'Box', 'box', id, 12, FALSE FROM units_of_measure WHERE symbol = 'pcs';

-- كرتون = 10 علب = 120 قطعة
INSERT INTO units_of_measure (name_ar, name_en, symbol, parent_unit_id, conversion_factor, is_base_unit)
SELECT 'كرتون', 'Carton', 'ctn', id, 10, FALSE FROM units_of_measure WHERE symbol = 'box';

-- طن = 1000 كيلو
INSERT INTO units_of_measure (name_ar, name_en, symbol, parent_unit_id, conversion_factor, is_base_unit)
SELECT 'طن', 'Ton', 'ton', id, 1000, FALSE FROM units_of_measure WHERE symbol = 'kg';

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ✅ Done! Database created successfully.
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
