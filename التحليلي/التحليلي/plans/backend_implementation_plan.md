# 📋 خطة تطوير نظام المبيعات (Sayler System) — Backend NestJS

> **دورك**: Backend Developer | **شريكك**: Frontend Developer  
> **التقنية**: NestJS + PostgreSQL + Redis + Offline Sync

---

## 🔍 نظرة عامة على المشروع

نظام متكامل للمبيعات والمخازن يعمل **Online & Offline** مع مزامنة تلقائية. يشمل:
- إدارة المبيعات (POS)، المخازن، المشتريات، الموردين، الزبائن، المندوبين
- دعم الديون والدفعات
- تقارير وإحصاءات
- متجر إلكتروني (E-commerce)

---

## 🏗️ القرارات المعمارية

### 1. هيكلية النظام: **Modular Monolith** ✅ (مع إمكانية التحول لـ Microservices لاحقاً)

> [!IMPORTANT]
> **لماذا Modular Monolith وليس Microservices؟**
> - المشروع في مرحلته الأولى وفريقه صغير (2 مطورين)
> - Microservices تضيف تعقيداً في الـ DevOps والـ Inter-service communication
> - Modular Monolith يعطي نفس التنظيم مع سهولة التطوير
> - يمكن استخراج services منفصلة لاحقاً بسهولة إذا احتجنا scaling

**البديل**: كل Module في NestJS معزول تماماً → `SalesModule`, `InventoryModule`, `PurchasesModule`...

---

### 2. التقنيات المختارة (Tech Stack)

| الطبقة | التقنية | السبب |
|--------|---------|--------|
| **Backend Framework** | NestJS (TypeScript) | طلب المستخدم + منظم ومثالي للـ modules |
| **Database** | PostgreSQL | علائقية + دعم JSON + قوية |
| **ORM** | TypeORM أو Prisma | Prisma مُوصى به لـ type safety أفضل |
| **Cache / Queue** | Redis | للـ sessions + job queues |
| **Offline Sync** | Custom Sync Engine (CRDTs مبسطة) | مثل Semantic Sync |
| **Auth** | JWT + Refresh Tokens | stateless auth |
| **API Style** | REST API (مع swagger) | واضح وشريكك يتكامل بسهولة |
| **Real-time** | Socket.IO / SSE | للإشعارات الفورية |
| **Validation** | class-validator + class-transformer | مع NestJS |
| **File Upload** | MinIO أو Cloudinary | لصور المنتجات |
| **Background Jobs** | BullMQ + Redis | للمزامنة والتقارير |
| **Logging** | Winston + correlation IDs | |
| **Testing** | Jest + Supertest | |
| **Documentation** | Swagger/OpenAPI | مع @nestjs/swagger |
| **Containerization** | Docker + Docker Compose | |

---

## 📦 الموديولات (Modules) — 14 وحدة

استناداً للملفات التحليلية:

| كود | الوحدة | الوصف |
|-----|--------|--------|
| **M01** | Users, Roles & Permissions | المستخدمين والصلاحيات |
| **M02** | Company, Branches & Warehouses | الشركة والفروع والمخازن |
| **M03** | Products & Categories | المنتجات والأصناف |
| **M04** | Suppliers & Purchasing | الموردون والمشتريات |
| **M05** | Inventory Management | إدارة المخزون |
| **M06** | Warehouse Transfers | التحويلات بين المخازن |
| **M07** | Stocktaking & Reconciliation | الجرد والتسوية |
| **M08** | Customers & Direct Sales POS | الزبائن ونقطة البيع |
| **M09** | Representatives & Custody | المندوبون والعهدة |
| **M10** | Accounts & Payments | الحسابات والدفعات |
| **M11** | Reports & Analytics | التقارير والإحصاءات |
| **M12** | Archive | الأرشيف |
| **M13** | E-commerce Store & Orders | المتجر الإلكتروني |
| **M14** | System Settings & Config | إعدادات النظام |

---

## 🗂️ هيكل المجلدات (Project Structure)

```
sayler-backend/
├── src/
│   ├── common/                    # Shared utilities
│   │   ├── decorators/
│   │   ├── filters/               # Exception filters
│   │   ├── guards/                # Auth guards
│   │   ├── interceptors/          # Logging, transform
│   │   ├── pipes/                 # Validation pipes
│   │   └── utils/
│   │
│   ├── config/                    # App config (env vars)
│   │   ├── app.config.ts
│   │   ├── database.config.ts
│   │   └── redis.config.ts
│   │
│   ├── modules/
│   │   ├── auth/                  # M01 — JWT auth
│   │   ├── users/                 # M01 — Users & Roles
│   │   ├── permissions/           # M01 — RBAC
│   │   ├── company/               # M02 — Company info
│   │   ├── branches/              # M02 — Branches
│   │   ├── warehouses/            # M02 — Warehouses
│   │   ├── products/              # M03 — Products & Variants
│   │   ├── categories/            # M03 — Categories
│   │   ├── suppliers/             # M04 — Suppliers
│   │   ├── purchases/             # M04 — Purchase invoices
│   │   ├── inventory/             # M05 — Stock levels
│   │   ├── inventory-movements/   # M05 — Stock movements
│   │   ├── warehouse-transfers/   # M06 — Transfers
│   │   ├── stocktaking/           # M07 — Stocktaking sessions
│   │   ├── customers/             # M08 — Customers
│   │   ├── sales/                 # M08 — Sales invoices POS
│   │   ├── cashboxes/             # M08 — Cash registers
│   │   ├── representatives/       # M09 — Sales reps
│   │   ├── custody/               # M09 — Rep custody
│   │   ├── accounts/              # M10 — Accounts ledger
│   │   ├── payments/              # M10 — Payments
│   │   ├── reports/               # M11 — Reports engine
│   │   ├── archive/               # M12 — Archiving
│   │   ├── ecommerce/             # M13 — Online store
│   │   └── settings/              # M14 — System config
│   │
│   ├── sync/                      # Offline Sync Engine
│   │   ├── sync.module.ts
│   │   ├── sync.controller.ts
│   │   ├── sync.service.ts
│   │   ├── conflict-resolver.ts
│   │   └── sync-log.entity.ts
│   │
│   ├── database/
│   │   ├── migrations/
│   │   └── seeds/
│   │
│   ├── notifications/             # Real-time (Socket.IO)
│   ├── jobs/                      # BullMQ Background jobs
│   └── main.ts
│
├── test/
├── docker-compose.yml
├── Dockerfile
├── .env.example
└── package.json
```

---

## 🗄️ هيكل قاعدة البيانات (Database Schema)

### جدول: `users`
```sql
id UUID PK, username, email, password_hash, role_id FK,
branch_id FK, is_active, last_login, created_at, updated_at
```

### جدول: `roles` + `permissions` + `role_permissions`
```sql
roles: id, name, description
permissions: id, resource, action (e.g. sales:create)
role_permissions: role_id, permission_id
```

### جدول: `branches` + `warehouses`
```sql
branches: id, company_id, name, address, phone, is_active
warehouses: id, branch_id, name, address, type (MAIN/SUB), is_active
```

### جدول: `products`
```sql
id, sku, barcode, name_ar, name_en, category_id,
unit_of_measure, has_variants, is_active
```

### جدول: `product_variants` (اللون/الحجم)
```sql
id, product_id, attributes (JSONB), barcode, 
weighted_avg_cost, last_purchase_price
```

### جدول: `product_batches` (الدفعات + انتهاء الصلاحية FEFO)
```sql
id, variant_id, warehouse_id, batch_number, 
expiry_date, quantity, unit_cost, received_at
```

### جدول: `stock_levels`
```sql
id, variant_id, warehouse_id, quantity_on_hand, 
quantity_reserved, reorder_point, updated_at
```

### جدول: `inventory_movements` (سجل كل حركة)
```sql
id, movement_type (IN/OUT/TRANSFER/ADJUST), variant_id,
warehouse_id, quantity, unit_cost, reference_type, 
reference_id, batch_id, serial_id, performed_by, created_at
```

### جدول: `suppliers`
```sql
id, name, phone, email, address, tax_number, 
balance (الرصيد), credit_limit, notes
```

### جدول: `purchase_invoices`
```sql
id, supplier_id, warehouse_id, invoice_number, status,
payment_type (CASH/CREDIT/PARTIAL), subtotal, discount,
tax, total, paid_amount, due_amount, invoice_date
```

### جدول: `purchase_invoice_items`
```sql
id, invoice_id, variant_id, batch_id, quantity, 
unit_price, discount_percent, total_price
```

### جدول: `customers`
```sql
id, name, phone, email, address, type (RETAIL/WHOLESALE),
balance, credit_limit, assigned_rep_id
```

### جدول: `sales_invoices`
```sql
id, invoice_number, customer_id, cashbox_id, warehouse_id,
rep_id, payment_type (CASH/CREDIT/PARTIAL/REP),
price_type (SINGLE/WHOLESALE/COST/REP),
subtotal, discount, total, paid_amount, due_amount,
status (DRAFT/PAID/PARTIAL/OVERDUE), idempotency_key, created_by
```

### جدول: `sales_invoice_items`
```sql
id, invoice_id, variant_id, batch_id, serial_id, quantity,
unit_price, discount_percent, net_unit_price, total_price
```

### جدول: `cashboxes` (صناديق النقد)
```sql
id, device_code, cashbox_code, branch_id, 
assigned_user_id, status (OPEN/CLOSED)
```

### جدول: `cashbox_sessions`
```sql
id, cashbox_id, opened_at, closed_at, opening_balance,
closing_balance, total_sales, total_refunds, status
```

### جدول: `representatives` (المندوبون)
```sql
id, user_id, name, phone, branch_id, 
commission_rate, status (ACTIVE/INACTIVE)
```

### جدول: `rep_custody_orders` (عهدة المندوب)
```sql
id, rep_id, warehouse_id, status, dispatch_date,
return_date, notes
```

### جدول: `accounts_ledger` (دفتر الحسابات)
```sql
id, account_type (CUSTOMER/SUPPLIER/REP),
account_id, total_amount, paid_amount, 
due_amount, last_payment_date
```

### جدول: `payment_vouchers` (سندات القبض والدفع)
```sql
id, voucher_type (RECEIPT/PAYMENT), account_type,
account_id, amount, payment_method (CASH/BANK/TRANSFER),
reference_number, notes, created_by, created_at
```

### جدول: `warehouse_transfers`
```sql
id, source_warehouse_id, destination_warehouse_id,
status (PENDING/APPROVED/DISPATCHED/RECEIVED),
dispatch_date, receive_date, idempotency_key
```

### جدول: `stocktaking_sessions`
```sql
id, warehouse_id, type (BLIND/VISIBLE), status,
snapshot_at, created_by, approved_by
```

### جدول: `sync_log` (للـ Offline Sync)
```sql
id, device_id, entity_type, entity_id, operation (C/U/D),
payload (JSONB), synced_at, conflict_resolved, server_version
```

---

## 🔄 نظام المزامنة Offline/Online (Sync Engine)

> [!IMPORTANT]
> هذا هو أعقد جزء في المشروع

### الاستراتيجية المقترحة:

1. **كل سجل يحتوي على**: `version INT`, `updated_at TIMESTAMP`, `device_id UUID`
2. **العميل يحتفظ بـ Queue محلية** من العمليات المعلقة (IndexedDB في الفرونت)
3. **عند الاتصال**: يرسل كل العمليات المعلقة مع `device_id` و `client_version`
4. **الخادم يحل التعارض** (Last-Write-Wins مع منطق خاص للمبيعات)
5. **الخادم يرد بـ**: العمليات التي فاتت العميل (delta sync)

### Conflict Resolution Rules:
- المبيعات المؤكدة: لا تُلغى أبداً
- المخزون: يُجمع التغيير لا يُستبدل
- إعدادات المستخدم: آخر تعديل يفوز

---

## 👨‍💻 مهام Backend Developer (أنت)

### ✅ مسؤولياتك الكاملة:

**1. Infrastructure & Setup**
- [ ] تهيئة مشروع NestJS
- [ ] إعداد TypeORM/Prisma مع PostgreSQL
- [ ] Docker Compose (Postgres + Redis + App)
- [ ] إعداد Swagger/OpenAPI
- [ ] CI/CD pipeline أساسي

**2. Auth Module (M01)**
- [ ] JWT Auth (Login/Logout/Refresh Token)
- [ ] RBAC (Role-Based Access Control)
- [ ] Permissions Guard
- [ ] تشفير كلمات المرور (bcrypt)

**3. Core Business Modules (M02-M09)**
- [ ] CRUD لكل entity
- [ ] Business logic (الحسابات، الـ validations)
- [ ] Stock management (الحجز، الاستهلاك)
- [ ] Idempotency keys للعمليات الحساسة
- [ ] Database transactions

**4. Financial Module (M10)**
- [ ] حسابات الديون والدفعات
- [ ] سندات القبض والدفع
- [ ] تتبع الأرصدة

**5. Sync Engine**
- [ ] Sync API endpoints
- [ ] Conflict resolver
- [ ] Delta sync

**6. Reports (M11)**
- [ ] APIs للتقارير
- [ ] تجميع البيانات (aggregations)

**7. Real-time Notifications**
- [ ] Socket.IO gateway
- [ ] أحداث: مخزون منخفض، فاتورة جديدة، إلخ

---

## 🤝 ما يحتاجه شريكك (Frontend Developer)

وضح له هذه النقاط:

1. **API Contract**: ستوفر Swagger docs على `/api/docs`
2. **Auth**: JWT في Authorization header
3. **Pagination**: `?page=1&limit=20`
4. **Filtering**: `?status=PAID&from=2026-01-01&to=2026-12-31`
5. **WebSocket**: للإشعارات الفورية
6. **Offline**: سيحتاج IndexedDB + sync queue في الـ frontend

---

## 📋 خطة التنفيذ (Phases)

### Phase 1 — Foundation (الأساس) — أسبوعان
- [ ] Setup مشروع NestJS
- [ ] Database schema + migrations
- [ ] Auth Module (M01)
- [ ] Company/Branches/Warehouses (M02)
- [ ] Swagger docs setup

### Phase 2 — Core Modules — 3 أسابيع
- [ ] Products & Categories (M03)
- [ ] Suppliers & Purchases (M04)
- [ ] Inventory Management (M05)
- [ ] Warehouse Transfers (M06)

### Phase 3 — Sales & Customers — أسبوعان
- [ ] Customers (M08)
- [ ] Sales POS (M08)
- [ ] Representatives & Custody (M09)

### Phase 4 — Finance & Reports — أسبوعان
- [ ] Accounts & Payments (M10)
- [ ] Reports (M11)
- [ ] Stocktaking (M07)

### Phase 5 — Advanced Features — أسبوعان
- [ ] Offline Sync Engine
- [ ] E-commerce (M13)
- [ ] Real-time Notifications
- [ ] Archive (M12)

---

## 🔐 Business Rules المهمة (من الوثائق)

1. **المبيعات**: `net_unit_price >= weighted_average_cost` (لا بيع بخسارة إلا بإذن)
2. **الجرد**: `received_good + shortage + damaged = dispatched`
3. **الفاتورة**: Unique `idempotency_key` لمنع التكرار
4. **المخزون**: FEFO (First Expired First Out) لبضائع الصلاحية
5. **الكاشير**: `PAID` invoices لا تُعدَّل أو تُحذف
6. **التحويل**: `source_warehouse_id ≠ destination_warehouse_id`

---

## ❓ أسئلة مفتوحة تحتاج تحديد

> [!IMPORTANT]
> قرر هذه النقاط قبل بدء التطوير:

1. **ORM**: Prisma أم TypeORM؟ (أنصح Prisma لـ type safety أفضل)
2. **الـ Frontend Framework**: ما الذي يستخدمه شريكك؟ (React/Vue/Angular) — يؤثر على CORS و auth strategy
3. **Deployment**: أين سيُنشر النظام؟ (VPS؟ Cloud؟) — يؤثر على Docker config
4. **المتجر الإلكتروني M13**: هل له mobile app أم web فقط؟
5. **Multi-tenancy**: هل النظام لشركة واحدة أم يدعم عدة شركات؟
6. **البيانات الأولية**: هل ستحتاج seeding للبيانات التجريبية؟

