# 🗄️ هيكل قاعدة البيانات — نظام المبيعات Sayler

> **Database**: PostgreSQL  
> **ORM**: Prisma (مُوصى به)  
> **التاريخ**: أغسطس 2026

---

## 📐 مبادئ التصميم

- كل جدول يحتوي على `id UUID DEFAULT gen_random_uuid() PRIMARY KEY`
- كل جدول يحتوي على `created_at`, `updated_at`, `created_by UUID FK`
- الـ Soft Delete باستخدام `deleted_at TIMESTAMP NULL`
- كل عملية مالية حساسة تحتوي على `idempotency_key`
- دعم الـ Offline Sync: `version INT DEFAULT 1`, `device_id UUID NULL`

---

## 📋 الجداول الكاملة

---

### 🔐 M01 — المستخدمون والصلاحيات

#### `companies`
```sql
id          UUID PK
name        VARCHAR(200) NOT NULL
logo_url    TEXT
address     TEXT
phone       VARCHAR(20)
email       VARCHAR(100)
tax_number  VARCHAR(50)
settings    JSONB DEFAULT '{}'
created_at  TIMESTAMP DEFAULT NOW()
updated_at  TIMESTAMP DEFAULT NOW()
```

#### `roles`
```sql
id          UUID PK
name        VARCHAR(100) NOT NULL UNIQUE
description TEXT
is_system   BOOLEAN DEFAULT FALSE  -- لا يمكن حذف system roles
created_at  TIMESTAMP DEFAULT NOW()
```

#### `permissions`
```sql
id          UUID PK
resource    VARCHAR(100) NOT NULL   -- e.g. 'sales', 'inventory'
action      VARCHAR(50) NOT NULL    -- e.g. 'create', 'read', 'update', 'delete'
description TEXT
UNIQUE(resource, action)
```

#### `role_permissions`
```sql
role_id        UUID FK → roles.id
permission_id  UUID FK → permissions.id
PRIMARY KEY (role_id, permission_id)
```

#### `users`
```sql
id             UUID PK
username       VARCHAR(100) NOT NULL UNIQUE
email          VARCHAR(150) UNIQUE
password_hash  TEXT NOT NULL
full_name      VARCHAR(200)
phone          VARCHAR(20)
role_id        UUID FK → roles.id
branch_id      UUID FK → branches.id NULL
avatar_url     TEXT
is_active      BOOLEAN DEFAULT TRUE
last_login     TIMESTAMP
refresh_token  TEXT NULL
created_at     TIMESTAMP DEFAULT NOW()
updated_at     TIMESTAMP DEFAULT NOW()
created_by     UUID FK → users.id NULL
```

---

### 🏢 M02 — الشركة والفروع والمخازن

#### `branches`
```sql
id          UUID PK
company_id  UUID FK → companies.id
name        VARCHAR(200) NOT NULL
address     TEXT
phone       VARCHAR(20)
manager_id  UUID FK → users.id NULL
is_active   BOOLEAN DEFAULT TRUE
created_at  TIMESTAMP DEFAULT NOW()
updated_at  TIMESTAMP DEFAULT NOW()
```

#### `warehouses`
```sql
id          UUID PK
branch_id   UUID FK → branches.id
name        VARCHAR(200) NOT NULL
address     TEXT
type        ENUM('MAIN', 'SUB', 'VIRTUAL') DEFAULT 'SUB'
is_active   BOOLEAN DEFAULT TRUE
created_at  TIMESTAMP DEFAULT NOW()
updated_at  TIMESTAMP DEFAULT NOW()
```

---

### 📦 M03 — المنتجات والأصناف

#### `categories` ← Self-Join (تصنيفات هرمية)
```sql
id          UUID PK
name_ar     VARCHAR(200) NOT NULL
name_en     VARCHAR(200)
parent_id   UUID FK → categories.id NULL   -- Self-Join: NULL = تصنيف رئيسي
level       INT DEFAULT 0                   -- 0=رئيسي, 1=فرعي, 2=فرعي-فرعي
path        TEXT                            -- '550e8400/f29b41d4/...' للبحث السريع
image_url   TEXT
order_index INT DEFAULT 0                   -- ترتيب العرض
is_active   BOOLEAN DEFAULT TRUE
created_at  TIMESTAMP DEFAULT NOW()
updated_at  TIMESTAMP DEFAULT NOW()
```

> **مثال هرمي:**
> ```
> إلكترونيات          (id=A, parent_id=NULL, level=0)
>   ├── هواتف          (id=B, parent_id=A,    level=1)
>   │     ├── سامسونج  (id=C, parent_id=B,    level=2)
>   │     └── آيفون    (id=D, parent_id=B,    level=2)
>   └── لابتوب         (id=E, parent_id=A,    level=1)
> مواد غذائية         (id=F, parent_id=NULL, level=0)
> ```

---

#### `units_of_measure` ← Self-Join (وحدات مع تحويل)
```sql
id               UUID PK
name_ar          VARCHAR(100) NOT NULL    -- قطعة، علبة، كرتون، كيلو...
name_en          VARCHAR(100)
symbol           VARCHAR(20)              -- pcs, box, ctn, kg
parent_unit_id   UUID FK → units_of_measure.id NULL  -- Self-Join
conversion_factor DECIMAL(15,6) DEFAULT 1  -- كم وحدة أساسية في هذه الوحدة
is_base_unit     BOOLEAN DEFAULT FALSE     -- الوحدة الأساسية للتخزين
is_active        BOOLEAN DEFAULT TRUE
created_at       TIMESTAMP DEFAULT NOW()
```

> **مثال تحويل:**
> ```
> قطعة   (id=1, parent=NULL, factor=1,   is_base=TRUE)   ← وحدة التخزين
>   ├── علبة    (id=2, parent=1,    factor=12,  is_base=FALSE)  ← 1 علبة = 12 قطعة
>   └── كرتون   (id=3, parent=2,    factor=10,  is_base=FALSE)  ← 1 كرتون = 10 علب = 120 قطعة
>
> كيلو   (id=4, parent=NULL, factor=1,   is_base=TRUE)
>   └── طن      (id=5, parent=4,    factor=1000, is_base=FALSE)
> ```
>
> **منطق التحويل** (يُحسب تلقائياً في الـ Backend):
> ```
> الكمية بالوحدة الأساسية = الكمية المدخلة × conversion_factor (تعاودي حتى الأساس)
> ```

---

#### `products`
```sql
id              UUID PK
sku             VARCHAR(100) UNIQUE
barcode         VARCHAR(100) UNIQUE
name_ar         VARCHAR(300) NOT NULL
name_en         VARCHAR(300)
category_id     UUID FK → categories.id
description     TEXT
base_unit_id    UUID FK → units_of_measure.id   -- وحدة التخزين الأساسية
has_variants    BOOLEAN DEFAULT FALSE
has_serial      BOOLEAN DEFAULT FALSE            -- منتجات بأرقام سيريال
has_expiry      BOOLEAN DEFAULT FALSE            -- منتجات بتاريخ صلاحية
image_url       TEXT
images          JSONB DEFAULT '[]'
min_stock_level DECIMAL(15,3) DEFAULT 0          -- بوحدة الأساس
is_active       BOOLEAN DEFAULT TRUE
created_at      TIMESTAMP DEFAULT NOW()
updated_at      TIMESTAMP DEFAULT NOW()
created_by      UUID FK → users.id
```

#### `product_variants` (الألوان/الأحجام)
```sql
id                    UUID PK
product_id            UUID FK → products.id
sku                   VARCHAR(100) UNIQUE
barcode               VARCHAR(100) UNIQUE
attributes            JSONB DEFAULT '{}'   -- {"color": "أحمر", "size": "XL"}
weighted_avg_cost     DECIMAL(15,4) DEFAULT 0   -- تكلفة متوسطة بوحدة الأساس (WAC)
last_purchase_price   DECIMAL(15,4) DEFAULT 0   -- آخر سعر شراء بوحدة الأساس
is_active             BOOLEAN DEFAULT TRUE
created_at            TIMESTAMP DEFAULT NOW()
updated_at            TIMESTAMP DEFAULT NOW()
```

---

#### `product_prices` ← جدول الأسعار المتعددة
```sql
id           UUID PK
variant_id   UUID FK → product_variants.id
price_type   ENUM('RETAIL', 'WHOLESALE', 'REP')   -- مفرد / جملة / مندوب
unit_id      UUID FK → units_of_measure.id         -- السعر لأي وحدة
price        DECIMAL(15,4) NOT NULL                -- السعر
is_active    BOOLEAN DEFAULT TRUE
updated_at   TIMESTAMP DEFAULT NOW()
UNIQUE(variant_id, price_type, unit_id)            -- سعر واحد لكل (منتج × نوع × وحدة)
```

> **مثال بيانات في `product_prices`:**
>
> | variant | price_type | unit | price |
> |---------|-----------|------|-------|
> | شامبو X | RETAIL | قطعة | 3,500 |
> | شامبو X | WHOLESALE | قطعة | 2,800 |
> | شامبو X | REP | قطعة | 2,500 |
> | شامبو X | RETAIL | كرتون (24 قطعة) | 82,000 |
> | شامبو X | WHOLESALE | كرتون | 65,000 |
> | شامبو X | REP | كرتون | 58,000 |
>
> **البديل الأبسط** (إذا لم يريد المستخدم تسعير لكل وحدة):
> - يُخزَّن سعر الوحدة الأساسية فقط
> - عند البيع بكرتون: `سعر_الكرتون = سعر_القطعة × 24`

---

> **كيف يُحدَّد السعر في الفاتورة؟**
> ```
> عند فتح POS:
> 1. المستخدم يختار نوع السعر (مفرد / جملة / مندوب)
> 2. يختار المنتج + الوحدة
> 3. Backend يجلب:
>    SELECT price FROM product_prices
>    WHERE variant_id = ? AND price_type = ? AND unit_id = ?
> 4. إذا لم يوجد سعر للوحدة المختارة:
>    → يحسبه تلقائياً: سعر_الوحدة_الأساسية × conversion_factor
> ```

---

#### `product_allowed_units` (الوحدات المسموحة لكل منتج)
```sql
id           UUID PK
product_id   UUID FK → products.id
unit_id      UUID FK → units_of_measure.id
can_buy      BOOLEAN DEFAULT TRUE   -- يُشترى بهذه الوحدة
can_sell     BOOLEAN DEFAULT TRUE   -- يُباع بهذه الوحدة
PRIMARY KEY (product_id, unit_id)
```

> **كيف يعمل في البيع/الشراء:**
> - المستخدم يختار: `2 كرتون` من `منتج X`
> - الـ Backend يحوّل: `2 × 10 × 12 = 240 قطعة` من المخزون
> - المخزون يُخزَّن دائماً **بالوحدة الأساسية**
> - الأسعار في الفاتورة **بالوحدة المختارة** (Backend يحسبها)

#### `serials` (الأرقام التسلسلية)
```sql
id          UUID PK
variant_id  UUID FK → product_variants.id
serial_no   VARCHAR(200) NOT NULL UNIQUE
status      ENUM('IN_STOCK', 'SOLD', 'IN_CUSTODY', 'RETURNED')
warehouse_id UUID FK → warehouses.id NULL
created_at  TIMESTAMP DEFAULT NOW()
updated_at  TIMESTAMP DEFAULT NOW()
```

---

### 🏭 M04 — الموردون والمشتريات

#### `suppliers`
```sql
id            UUID PK
name          VARCHAR(300) NOT NULL
phone         VARCHAR(20)
email         VARCHAR(150)
address       TEXT
tax_number    VARCHAR(50)
balance       DECIMAL(15,2) DEFAULT 0   -- ما علينا للمورد (موجب = مديونية)
credit_limit  DECIMAL(15,2) DEFAULT 0
notes         TEXT
is_active     BOOLEAN DEFAULT TRUE
created_at    TIMESTAMP DEFAULT NOW()
updated_at    TIMESTAMP DEFAULT NOW()
created_by    UUID FK → users.id
```

#### `purchase_invoices`
```sql
id               UUID PK
invoice_number   VARCHAR(50) UNIQUE NOT NULL
supplier_id      UUID FK → suppliers.id
warehouse_id     UUID FK → warehouses.id
status           ENUM('DRAFT', 'CONFIRMED', 'PARTIAL', 'PAID', 'CANCELLED')
payment_type     ENUM('CASH', 'CREDIT', 'PARTIAL')
subtotal         DECIMAL(15,2) DEFAULT 0
discount_amount  DECIMAL(15,2) DEFAULT 0
tax_amount       DECIMAL(15,2) DEFAULT 0
total            DECIMAL(15,2) DEFAULT 0
paid_amount      DECIMAL(15,2) DEFAULT 0
due_amount       DECIMAL(15,2) GENERATED ALWAYS AS (total - paid_amount) STORED
notes            TEXT
invoice_date     DATE DEFAULT CURRENT_DATE
due_date         DATE
created_at       TIMESTAMP DEFAULT NOW()
updated_at       TIMESTAMP DEFAULT NOW()
created_by       UUID FK → users.id
```

#### `purchase_invoice_items`
```sql
id                    UUID PK
invoice_id            UUID FK → purchase_invoices.id ON DELETE CASCADE
variant_id            UUID FK → product_variants.id
batch_number          VARCHAR(100) NULL
expiry_date           DATE NULL

-- وحدة الشراء
unit_id               UUID FK → units_of_measure.id  -- مثل: كرتون / تنكة 100لتر
quantity              DECIMAL(15,3) NOT NULL          -- بوحدة الشراء (5 كراتين)
quantity_in_base_unit DECIMAL(15,3) NOT NULL          -- بعد التحويل (600 قطعة) ← يدخل المخزن

-- السعر
unity_cost            DECIMAL(15,4) NOT NULL          -- تكلفة وحدة الشراء (سعر الكرتون)
cost_per_base_unit    DECIMAL(15,4) NOT NULL          -- تكلفة الوحدة الأساسية (تكلفة القطعة) ← لحساب WAC
discount_percent      DECIMAL(5,2) DEFAULT 0
total_price           DECIMAL(15,2) NOT NULL
created_at            TIMESTAMP DEFAULT NOW()
```

> **مثال شراء بكرتون:**
> ```
> المستخدم يدخل: 5 كرتون بسعر 60,000 للكرتون
> quantity              = 5
> unit_id               = كرتون (factor=120)
> quantity_in_base_unit = 5 × 120 = 600 قطعة  ← تضاف للمخزن
> unity_cost            = 60,000
> cost_per_base_unit    = 60,000 ÷ 120 = 500 للقطعة ← لحساب WAC
> total_price           = 5 × 60,000 = 300,000
> ```
>
> **مثال شراء زيت 100 لتر:**
> ```
> المستخدم يدخل: 2 تنكة بسعر 50,000 للتنكة
> quantity              = 2
> unit_id               = تنكة 100لتر (factor=100)
> quantity_in_base_unit = 2 × 100 = 200 لتر  ← تضاف للمخزن
> unity_cost            = 50,000
> cost_per_base_unit    = 50,000 ÷ 100 = 500 لللتر ← لحساب WAC
> total_price           = 100,000
> ```

---

### 📊 M05 — إدارة المخزون

#### `stock_levels` (الرصيد الحالي)
```sql
id                UUID PK
variant_id        UUID FK → product_variants.id
warehouse_id      UUID FK → warehouses.id
quantity_on_hand  DECIMAL(15,3) DEFAULT 0   -- المتاح الفعلي
quantity_reserved DECIMAL(15,3) DEFAULT 0   -- محجوز لطلبات
quantity_in_transit DECIMAL(15,3) DEFAULT 0 -- في الطريق
updated_at        TIMESTAMP DEFAULT NOW()
UNIQUE(variant_id, warehouse_id)
```

#### `product_batches` (الدفعات — FEFO)
```sql
id              UUID PK
variant_id      UUID FK → product_variants.id
warehouse_id    UUID FK → warehouses.id
batch_number    VARCHAR(100)
expiry_date     DATE NULL
quantity        DECIMAL(15,3) DEFAULT 0
unit_cost       DECIMAL(15,4) NOT NULL
received_at     TIMESTAMP DEFAULT NOW()
purchase_item_id UUID FK → purchase_invoice_items.id NULL
```

#### `inventory_movements` (كل حركة مخزنية)
```sql
id              UUID PK
movement_type   ENUM('IN', 'OUT', 'TRANSFER_OUT', 'TRANSFER_IN', 'ADJUST_ADD', 'ADJUST_REDUCE', 'RETURN_IN', 'RETURN_OUT')
variant_id      UUID FK → product_variants.id
warehouse_id    UUID FK → warehouses.id
quantity        DECIMAL(15,3) NOT NULL
unit_cost       DECIMAL(15,4)
reference_type  VARCHAR(50)   -- 'purchase', 'sale', 'transfer', 'stocktaking'
reference_id    UUID
batch_id        UUID FK → product_batches.id NULL
serial_id       UUID FK → serials.id NULL
notes           TEXT
performed_by    UUID FK → users.id
device_id       UUID NULL     -- للـ Offline Sync
version         INT DEFAULT 1
created_at      TIMESTAMP DEFAULT NOW()
```

---

### 🔄 M06 — التحويلات بين المخازن

#### `warehouse_transfers`
```sql
id                      UUID PK
transfer_number         VARCHAR(50) UNIQUE NOT NULL
source_warehouse_id     UUID FK → warehouses.id
destination_warehouse_id UUID FK → warehouses.id
status                  ENUM('PENDING', 'APPROVED', 'DISPATCHED', 'RECEIVED', 'CANCELLED')
dispatch_date           TIMESTAMP
receive_date            TIMESTAMP
notes                   TEXT
idempotency_key         VARCHAR(200) UNIQUE
approved_by             UUID FK → users.id NULL
dispatched_by           UUID FK → users.id NULL
received_by             UUID FK → users.id NULL
created_at              TIMESTAMP DEFAULT NOW()
updated_at              TIMESTAMP DEFAULT NOW()
created_by              UUID FK → users.id
CHECK (source_warehouse_id <> destination_warehouse_id)
```

#### `warehouse_transfer_items`
```sql
id                UUID PK
transfer_id       UUID FK → warehouse_transfers.id ON DELETE CASCADE
variant_id        UUID FK → product_variants.id
batch_id          UUID FK → product_batches.id NULL
serial_id         UUID FK → serials.id NULL
quantity_sent     DECIMAL(15,3) NOT NULL
quantity_received DECIMAL(15,3) DEFAULT 0
quantity_shortage DECIMAL(15,3) DEFAULT 0
quantity_damaged  DECIMAL(15,3) DEFAULT 0
CHECK (quantity_received + quantity_shortage + quantity_damaged = quantity_sent)
```

---

### 📋 M07 — الجرد والتسوية

#### `stocktaking_sessions`
```sql
id              UUID PK
session_number  VARCHAR(50) UNIQUE NOT NULL
warehouse_id    UUID FK → warehouses.id
type            ENUM('BLIND', 'VISIBLE')
status          ENUM('OPEN', 'COUNTING', 'PENDING_REVIEW', 'PENDING_VALUATION', 'APPROVED', 'CANCELLED')
snapshot_at     TIMESTAMP NOT NULL    -- snapshot عند البداية
approved_at     TIMESTAMP
notes           TEXT
created_at      TIMESTAMP DEFAULT NOW()
updated_at      TIMESTAMP DEFAULT NOW()
created_by      UUID FK → users.id
approved_by     UUID FK → users.id NULL
```

#### `stocktaking_items`
```sql
id                  UUID PK
session_id          UUID FK → stocktaking_sessions.id
variant_id          UUID FK → product_variants.id
batch_id            UUID FK → product_batches.id NULL
serial_id           UUID FK → serials.id NULL
system_quantity     DECIMAL(15,3)    -- من الـ snapshot
counted_quantity    DECIMAL(15,3)
difference          DECIMAL(15,3) GENERATED ALWAYS AS (counted_quantity - system_quantity) STORED
unit_cost           DECIMAL(15,4)
adjustment_type     ENUM('NONE', 'ADD', 'REDUCE') DEFAULT 'NONE'
UNIQUE(session_id, variant_id, batch_id)
```

---

### 🛒 M08 — الزبائن والمبيعات POS

#### `customers`
```sql
id              UUID PK
name            VARCHAR(300) NOT NULL
phone           VARCHAR(20) UNIQUE
email           VARCHAR(150)
address         TEXT
type            ENUM('RETAIL', 'WHOLESALE') DEFAULT 'RETAIL'
balance         DECIMAL(15,2) DEFAULT 0   -- ما عليه (موجب = مديونية)
credit_limit    DECIMAL(15,2) DEFAULT 0
assigned_rep_id UUID FK → representatives.id NULL
notes           TEXT
is_active       BOOLEAN DEFAULT TRUE
created_at      TIMESTAMP DEFAULT NOW()
updated_at      TIMESTAMP DEFAULT NOW()
created_by      UUID FK → users.id
```

#### `cashboxes` (صناديق الكاشير)
```sql
id               UUID PK
device_code      VARCHAR(100) NOT NULL UNIQUE
cashbox_code     VARCHAR(100) NOT NULL UNIQUE
name             VARCHAR(200)
branch_id        UUID FK → branches.id
assigned_user_id UUID FK → users.id NULL
status           ENUM('OPEN', 'CLOSED') DEFAULT 'CLOSED'
created_at       TIMESTAMP DEFAULT NOW()
updated_at       TIMESTAMP DEFAULT NOW()
```

#### `cashbox_sessions`
```sql
id               UUID PK
cashbox_id       UUID FK → cashboxes.id
opened_by        UUID FK → users.id
closed_by        UUID FK → users.id NULL
opened_at        TIMESTAMP DEFAULT NOW()
closed_at        TIMESTAMP NULL
opening_balance  DECIMAL(15,2) DEFAULT 0
closing_balance  DECIMAL(15,2) DEFAULT 0
total_sales      DECIMAL(15,2) DEFAULT 0
total_returns    DECIMAL(15,2) DEFAULT 0
status           ENUM('OPEN', 'CLOSED') DEFAULT 'OPEN'
UNIQUE PARTIAL (cashbox_id WHERE status = 'OPEN')  -- كاشير واحد مفتوح
```

#### `sales_invoices`
```sql
id               UUID PK
invoice_number   VARCHAR(50) UNIQUE NOT NULL
cashbox_id       UUID FK → cashboxes.id NULL
session_id       UUID FK → cashbox_sessions.id NULL
customer_id      UUID FK → customers.id NULL   -- NULL = زبون نقدي
warehouse_id     UUID FK → warehouses.id NOT NULL
rep_id           UUID FK → representatives.id NULL
price_type       ENUM('RETAIL', 'WHOLESALE', 'COST', 'REP') DEFAULT 'RETAIL'
payment_type     ENUM('CASH', 'CREDIT', 'PARTIAL', 'REP_CUSTODY')
status           ENUM('DRAFT', 'PAID', 'PARTIAL', 'OVERDUE', 'CANCELLED', 'RETURNED')
subtotal         DECIMAL(15,2) DEFAULT 0
discount_amount  DECIMAL(15,2) DEFAULT 0
total            DECIMAL(15,2) DEFAULT 0
paid_amount      DECIMAL(15,2) DEFAULT 0
due_amount       DECIMAL(15,2) DEFAULT 0
notes            TEXT
idempotency_key  VARCHAR(200) UNIQUE NOT NULL
device_id        UUID NULL
version          INT DEFAULT 1
invoice_date     TIMESTAMP DEFAULT NOW()
due_date         DATE NULL
created_at       TIMESTAMP DEFAULT NOW()
updated_at       TIMESTAMP DEFAULT NOW()
created_by       UUID FK → users.id
```

#### `sales_invoice_items`
```sql
id                    UUID PK
invoice_id            UUID FK → sales_invoices.id ON DELETE CASCADE
variant_id            UUID FK → product_variants.id
batch_id              UUID FK → product_batches.id NULL
serial_id             UUID FK → serials.id NULL

-- وحدة البيع
unit_id               UUID FK → units_of_measure.id  -- مثل: قطعة / لتر
quantity              DECIMAL(15,3) NOT NULL          -- بوحدة البيع (10 قطع)
quantity_in_base_unit DECIMAL(15,3) NOT NULL          -- بعد التحويل (10 قطعة) ← ينقص من المخزن

-- السعر
unit_price            DECIMAL(15,4) NOT NULL          -- سعر وحدة البيع (500 للقطعة)
cost_per_base_unit    DECIMAL(15,4) NOT NULL          -- تكلفة الوحدة وقت البيع (WAC snapshot)
discount_percent      DECIMAL(5,2) DEFAULT 0
net_unit_price        DECIMAL(15,4) NOT NULL
total_price           DECIMAL(15,2) NOT NULL
CHECK (net_unit_price >= 0)
CHECK (net_unit_price * quantity_in_base_unit >= cost_per_base_unit * quantity_in_base_unit)  -- لا بيع بخسارة
```

> **مثال بيع بقطع:**
> ```
> اشترينا بكرتون (cost=500 للقطعة) ← WAC = 500
> المستخدم يبيع: 10 قطع بسعر 700
> unit_id               = قطعة (factor=1)
> quantity              = 10
> quantity_in_base_unit = 10 × 1 = 10  ← ينقص 10 من المخزن
> unit_price            = 700
> cost_per_base_unit    = 500 (WAC وقت البيع)
> total_price           = 7,000
> الربح               = (700-500) × 10 = 2,000 ✓
> ```
>
> **مثال بيع زيت باللتر:**
> ```
> اشترينا تنكة 100لتر (cost=500 لللتر) ← WAC = 500
> المستخدم يبيع: 5 لتر بسعر 800
> unit_id               = لتر (factor=1, هو الأساس)
> quantity              = 5
> quantity_in_base_unit = 5  ← ينقص 5 لتر من المخزن
> unit_price            = 800
> total_price           = 4,000
> المخزن بعد البيع    = 200 - 5 = 195 لتر ✓
> ```

---

### 👤 M09 — المندوبون والعهدة

#### `representatives`
```sql
id               UUID PK
user_id          UUID FK → users.id UNIQUE
name             VARCHAR(300) NOT NULL
phone            VARCHAR(20)
branch_id        UUID FK → branches.id
commission_rate  DECIMAL(5,2) DEFAULT 0    -- نسبة العمولة %
commission_type  ENUM('PERCENT', 'FIXED') DEFAULT 'PERCENT'
status           ENUM('ACTIVE', 'INACTIVE') DEFAULT 'ACTIVE'
created_at       TIMESTAMP DEFAULT NOW()
updated_at       TIMESTAMP DEFAULT NOW()
```

#### `rep_custody_orders` (أوامر تسليم العهدة)
```sql
id              UUID PK
order_number    VARCHAR(50) UNIQUE NOT NULL
rep_id          UUID FK → representatives.id
warehouse_id    UUID FK → warehouses.id
status          ENUM('PENDING', 'APPROVED', 'DISPATCHED', 'PARTIALLY_RETURNED', 'FULLY_RETURNED', 'CANCELLED')
dispatch_date   TIMESTAMP
return_due_date DATE
notes           TEXT
idempotency_key VARCHAR(200) UNIQUE
created_at      TIMESTAMP DEFAULT NOW()
updated_at      TIMESTAMP DEFAULT NOW()
created_by      UUID FK → users.id
```

#### `rep_custody_items`
```sql
id                  UUID PK
custody_order_id    UUID FK → rep_custody_orders.id
variant_id          UUID FK → product_variants.id
serial_id           UUID FK → serials.id NULL
quantity_sent       DECIMAL(15,3) NOT NULL
quantity_sold       DECIMAL(15,3) DEFAULT 0
quantity_returned   DECIMAL(15,3) DEFAULT 0
```

---

### 💰 M10 — الحسابات والدفعات

#### `accounts_ledger` (دفتر الحسابات)
```sql
id               UUID PK
account_type     ENUM('CUSTOMER', 'SUPPLIER', 'REPRESENTATIVE')
account_id       UUID NOT NULL     -- FK ديناميكي حسب account_type
total_debit      DECIMAL(15,2) DEFAULT 0   -- ما له علينا
total_credit     DECIMAL(15,2) DEFAULT 0   -- ما علينا له
balance          DECIMAL(15,2) GENERATED ALWAYS AS (total_debit - total_credit) STORED
last_transaction TIMESTAMP
UNIQUE(account_type, account_id)
```

#### `payment_vouchers` (سندات القبض والدفع)
```sql
id               UUID PK
voucher_number   VARCHAR(50) UNIQUE NOT NULL
voucher_type     ENUM('RECEIPT', 'PAYMENT')   -- قبض أو دفع
account_type     ENUM('CUSTOMER', 'SUPPLIER', 'REPRESENTATIVE')
account_id       UUID NOT NULL
amount           DECIMAL(15,2) NOT NULL
payment_method   ENUM('CASH', 'BANK_TRANSFER', 'CHECK', 'POS_MACHINE')
bank_name        VARCHAR(100) NULL
reference_number VARCHAR(100) NULL
notes            TEXT
voucher_date     DATE DEFAULT CURRENT_DATE
created_at       TIMESTAMP DEFAULT NOW()
created_by       UUID FK → users.id
```

---

### 🔄 Sync Engine

#### `sync_log`
```sql
id                UUID PK
device_id         UUID NOT NULL
entity_type       VARCHAR(100) NOT NULL   -- 'sales_invoices', 'stock_levels'...
entity_id         UUID NOT NULL
operation         ENUM('CREATE', 'UPDATE', 'DELETE')
payload           JSONB NOT NULL
client_version    INT
server_version    INT
conflict_resolved BOOLEAN DEFAULT FALSE
conflict_notes    TEXT
synced_at         TIMESTAMP DEFAULT NOW()
INDEX (device_id, entity_type, synced_at)
```

#### `device_sync_state`
```sql
id              UUID PK
device_id       UUID NOT NULL UNIQUE
user_id         UUID FK → users.id
branch_id       UUID FK → branches.id
last_sync_at    TIMESTAMP
last_seq        BIGINT DEFAULT 0
device_info     JSONB DEFAULT '{}'
created_at      TIMESTAMP DEFAULT NOW()
```

---

## 🔗 العلاقات الرئيسية (ERD Summary)

```
companies
  ├── branches (1:N)
  │     └── warehouses (1:N)
  │           ├── stock_levels (N:M via product_variants)
  │           ├── sales_invoices (1:N)
  │           └── warehouse_transfers (1:N source/destination)
  └── users (1:N)
        ├── representatives (1:1)
        └── cashboxes (1:N)

products
  └── product_variants (1:N)
        ├── stock_levels (1:N per warehouse)
        ├── product_batches (1:N per warehouse)
        ├── serials (1:N)
        ├── purchase_invoice_items (N:M)
        └── sales_invoice_items (N:M)

customers
  └── sales_invoices (1:N)
        └── sales_invoice_items (1:N)

suppliers
  └── purchase_invoices (1:N)
        └── purchase_invoice_items (1:N)

representatives
  ├── sales_invoices (1:N)
  └── rep_custody_orders (1:N)
        └── rep_custody_items (1:N)
```

---

## ⚡ Indexes المهمة

```sql
-- المبيعات
CREATE INDEX idx_sales_invoices_customer ON sales_invoices(customer_id);
CREATE INDEX idx_sales_invoices_status ON sales_invoices(status);
CREATE INDEX idx_sales_invoices_date ON sales_invoices(invoice_date DESC);
CREATE INDEX idx_sales_invoices_rep ON sales_invoices(rep_id);

-- المخزون
CREATE INDEX idx_stock_levels_warehouse ON stock_levels(warehouse_id);
CREATE INDEX idx_inventory_movements_variant ON inventory_movements(variant_id, created_at DESC);
CREATE INDEX idx_product_batches_expiry ON product_batches(expiry_date ASC) WHERE expiry_date IS NOT NULL;

-- الحسابات
CREATE INDEX idx_payment_vouchers_account ON payment_vouchers(account_type, account_id);

-- المزامنة
CREATE INDEX idx_sync_log_device ON sync_log(device_id, synced_at DESC);
CREATE INDEX idx_sync_log_entity ON sync_log(entity_type, entity_id);
```


