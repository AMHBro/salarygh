# M12 — Ecommerce

## خطة التنفيذ الكاملة للـ Backend باستخدام NestJS + Prisma + PostgreSQL

**المشروع:** Sayler Sales System  
**الموديول:** M12 — Ecommerce  
**النطاق:** Backend فقط

## 1. القرارات المعمارية

### Guest Customer
- بدون تسجيل دخول.
- يشاهد سعر `RETAIL`.
- يستطيع تصفح المنتجات وإدارة السلة وإرسال الطلب ومتابعته عبر `public_token`.

### Representative
- تسجيل الدخول إجباري.
- يشاهد سعر `REP`.
- يختار الجهة/الحساب المرتبط بالطلب.
- يختار `CASH / CREDIT / PARTIAL`.
- يرسل الطلب ويتابع طلباته.

## 2. حالات الطلب

```text
SUBMITTED
ACCEPTED
REJECTED
CANCELLED
```

الحركات المسموحة:

```text
SUBMITTED -> ACCEPTED
SUBMITTED -> REJECTED
SUBMITTED -> CANCELLED
```

لا يتم حجز أو خصم المخزون عند `SUBMITTED`. الخصم وإنشاء الفاتورة يحصلان عند `ACCEPTED`.

## 3. التسعير

لا نضيف `customer_price` أو `representative_price` إلى `products`.

نستخدم جدول `product_prices` الحالي:

```text
Guest          -> RETAIL
Representative -> REP
```

سعر `REP` هو السعر النهائي بعد تحميل العمولة.

مثال:

```text
RETAIL = 25,000
Commission = 8%
REP = 27,000
```

نحتفظ بقاعدة العمولة في جدول مستقل، بينما يبقى `product_prices.REP` هو السعر النهائي المستخدم في النظام.

## 4. Prisma Enums الجديدة

```prisma
enum ecommerce_order_source_enum {
  GUEST
  REPRESENTATIVE
}

enum ecommerce_order_status_enum {
  SUBMITTED
  ACCEPTED
  REJECTED
  CANCELLED
}

enum ecommerce_party_type_enum {
  CUSTOMER
  SUPPLIER
  BRANCH
  REPRESENTATIVE
  OTHER
}
```

نستخدم `sales_payment_enum` و `commission_type_enum` الموجودين حالياً.

## 5. جدول إعدادات منتجات المتجر

```prisma
model ecommerce_product_settings {
  id               String               @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  variant_id       String               @db.Uuid
  unit_id          String               @db.Uuid
  is_enabled       Boolean              @default(true)
  commission_type  commission_type_enum @default(PERCENT)
  commission_value Decimal              @default(0) @db.Decimal(15, 4)
  sort_order       Int                  @default(0)
  created_at       DateTime             @default(now()) @db.Timestamptz(6)
  updated_at       DateTime             @default(now()) @updatedAt @db.Timestamptz(6)

  variant          product_variants     @relation(fields: [variant_id], references: [id], onDelete: Cascade)
  unit             units_of_measure     @relation(fields: [unit_id], references: [id], onDelete: Cascade)

  @@unique([variant_id, unit_id])
  @@index([is_enabled])
  @@index([variant_id])
}
```

حساب REP:

```text
PERCENT:
REP = RETAIL + (RETAIL * commission_value / 100)

FIXED:
REP = RETAIL + commission_value
```

بعد الحساب يعمل Backend `upsert` لسعر `REP` داخل `product_prices`.

## 6. ecommerce_carts

```prisma
model ecommerce_carts {
  id            String                       @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  user_id       String?                      @unique @db.Uuid
  session_token String?                      @unique @db.VarChar(150)
  source        ecommerce_order_source_enum
  created_at    DateTime                     @default(now()) @db.Timestamptz(6)
  updated_at    DateTime                     @default(now()) @updatedAt @db.Timestamptz(6)

  user          users?                       @relation(fields: [user_id], references: [id], onDelete: Cascade)
  items         ecommerce_cart_items[]

  @@index([source])
}
```

Guest:

```text
user_id = NULL
session_token = UUID
source = GUEST
```

Representative:

```text
user_id = logged user id
session_token = NULL
source = REPRESENTATIVE
```

## 7. ecommerce_cart_items

```prisma
model ecommerce_cart_items {
  id         String               @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  cart_id    String               @db.Uuid
  variant_id String               @db.Uuid
  unit_id    String               @db.Uuid
  quantity   Decimal              @db.Decimal(15, 3)
  created_at DateTime             @default(now()) @db.Timestamptz(6)
  updated_at DateTime             @default(now()) @updatedAt @db.Timestamptz(6)

  cart       ecommerce_carts      @relation(fields: [cart_id], references: [id], onDelete: Cascade)
  variant    product_variants     @relation(fields: [variant_id], references: [id], onDelete: Restrict)
  unit       units_of_measure     @relation(fields: [unit_id], references: [id], onDelete: Restrict)

  @@unique([cart_id, variant_id, unit_id])
  @@index([cart_id])
  @@index([variant_id])
}
```

## 8. ecommerce_orders

```prisma
model ecommerce_orders {
  id                  String                         @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  order_number        String                         @unique @db.VarChar(50)

  source              ecommerce_order_source_enum
  status              ecommerce_order_status_enum    @default(SUBMITTED)

  user_id             String?                        @db.Uuid
  rep_id              String?                        @db.Uuid

  party_type          ecommerce_party_type_enum?
  party_id            String?                        @db.Uuid
  party_name          String?                        @db.VarChar(300)
  party_phone         String?                        @db.VarChar(50)
  party_address       String?

  customer_name       String?                        @db.VarChar(300)
  customer_phone      String?                        @db.VarChar(50)
  customer_email      String?                        @db.VarChar(150)
  customer_address    String?

  payment_type        sales_payment_enum             @default(CASH)
  notes               String?

  subtotal            Decimal                        @default(0) @db.Decimal(15, 2)
  discount_amount     Decimal                        @default(0) @db.Decimal(15, 2)
  total               Decimal                        @default(0) @db.Decimal(15, 2)

  submitted_at        DateTime                       @default(now()) @db.Timestamptz(6)

  accepted_at         DateTime?                      @db.Timestamptz(6)
  accepted_by         String?                        @db.Uuid

  rejected_at         DateTime?                      @db.Timestamptz(6)
  rejected_by         String?                        @db.Uuid
  rejection_reason    String?

  cancelled_at        DateTime?                      @db.Timestamptz(6)
  cancelled_by        String?                        @db.Uuid
  cancellation_reason String?

  sales_invoice_id    String?                        @unique @db.Uuid

  public_token        String?                        @unique @db.VarChar(150)
  idempotency_key     String?                        @unique @db.VarChar(200)

  created_at          DateTime                       @default(now()) @db.Timestamptz(6)
  updated_at          DateTime                       @default(now()) @updatedAt @db.Timestamptz(6)

  items               ecommerce_order_items[]

  user                users?                         @relation("EcommerceOrderUser", fields: [user_id], references: [id], onDelete: SetNull)
  representative      representatives?               @relation(fields: [rep_id], references: [id], onDelete: SetNull)
  approver            users?                         @relation("EcommerceOrderApprover", fields: [accepted_by], references: [id], onDelete: SetNull)
  rejector            users?                         @relation("EcommerceOrderRejector", fields: [rejected_by], references: [id], onDelete: SetNull)
  canceller           users?                         @relation("EcommerceOrderCanceller", fields: [cancelled_by], references: [id], onDelete: SetNull)
  sales_invoice       sales_invoices?                @relation(fields: [sales_invoice_id], references: [id], onDelete: SetNull)

  @@index([status])
  @@index([source])
  @@index([user_id])
  @@index([rep_id])
  @@index([party_type, party_id])
  @@index([customer_phone])
  @@index([submitted_at])
}
```

`party_id` ليس Foreign Key لأن الجهة يمكن أن تكون CUSTOMER أو SUPPLIER أو BRANCH أو REPRESENTATIVE أو OTHER. التحقق يتم داخل Service، مع حفظ Snapshot للاسم والهاتف والعنوان.

## 9. ecommerce_order_items

```prisma
model ecommerce_order_items {
  id                     String              @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  order_id               String              @db.Uuid
  product_id             String              @db.Uuid
  variant_id             String              @db.Uuid
  unit_id                String              @db.Uuid

  product_name           String              @db.VarChar(300)
  variant_snapshot       Json                @default("{}")
  unit_name              String?             @db.VarChar(100)

  quantity               Decimal             @db.Decimal(15, 3)
  price_type             price_type_enum
  base_price             Decimal             @db.Decimal(15, 4)

  commission_type        commission_type_enum?
  commission_value       Decimal             @default(0) @db.Decimal(15, 4)
  commission_amount      Decimal             @default(0) @db.Decimal(15, 4)

  unit_price             Decimal             @db.Decimal(15, 4)
  line_total             Decimal             @db.Decimal(15, 2)

  created_at             DateTime            @default(now()) @db.Timestamptz(6)

  order                  ecommerce_orders    @relation(fields: [order_id], references: [id], onDelete: Cascade)
  product                products            @relation(fields: [product_id], references: [id], onDelete: Restrict)
  variant                product_variants    @relation(fields: [variant_id], references: [id], onDelete: Restrict)
  unit                   units_of_measure    @relation(fields: [unit_id], references: [id], onDelete: Restrict)

  @@index([order_id])
  @@index([product_id])
  @@index([variant_id])
}
```

## 10. العلاقات العكسية المطلوبة

في `products`:

```prisma
ecommerce_order_items ecommerce_order_items[]
```

في `product_variants`:

```prisma
ecommerce_product_settings ecommerce_product_settings[]
ecommerce_cart_items       ecommerce_cart_items[]
ecommerce_order_items      ecommerce_order_items[]
```

في `units_of_measure`:

```prisma
ecommerce_product_settings ecommerce_product_settings[]
ecommerce_cart_items       ecommerce_cart_items[]
ecommerce_order_items      ecommerce_order_items[]
```

في `users`:

```prisma
ecommerce_carts            ecommerce_carts[]
ecommerce_orders_placed    ecommerce_orders[] @relation("EcommerceOrderUser")
ecommerce_orders_accepted  ecommerce_orders[] @relation("EcommerceOrderApprover")
ecommerce_orders_rejected  ecommerce_orders[] @relation("EcommerceOrderRejector")
ecommerce_orders_cancelled ecommerce_orders[] @relation("EcommerceOrderCanceller")
```

في `representatives`:

```prisma
ecommerce_orders ecommerce_orders[]
```

في `sales_invoices`:

```prisma
ecommerce_order ecommerce_orders?
```

## 11. أوامر Prisma

```bash
npx prisma format
npx prisma validate
npx prisma migrate dev --name m12_ecommerce
npx prisma generate
```

Production:

```bash
npx prisma migrate deploy
```

## 12. هيكل NestJS

```text
src/modules/ecommerce/
├── ecommerce.module.ts
├── controllers/
│   ├── store-catalog.controller.ts
│   ├── cart.controller.ts
│   ├── checkout.controller.ts
│   ├── orders.controller.ts
│   └── ecommerce-admin.controller.ts
├── services/
│   ├── ecommerce-product.service.ts
│   ├── ecommerce-pricing.service.ts
│   ├── ecommerce-stock.service.ts
│   ├── ecommerce-party.service.ts
│   ├── cart.service.ts
│   ├── checkout.service.ts
│   ├── ecommerce-order.service.ts
│   └── order-approval.service.ts
├── dto/
│   ├── catalog-query.dto.ts
│   ├── add-cart-item.dto.ts
│   ├── update-cart-item.dto.ts
│   ├── guest-checkout.dto.ts
│   ├── representative-checkout.dto.ts
│   ├── accept-order.dto.ts
│   ├── reject-order.dto.ts
│   └── cancel-order.dto.ts
└── guards/
    └── optional-jwt-auth.guard.ts
```

## 13. مراحل التنفيذ في NestJS

### Phase 1 — Database
- إضافة Enums والجداول الخمسة.
- إضافة العلاقات العكسية.
- تنفيذ Migration.

### Phase 2 — Module Skeleton
- إنشاء `EcommerceModule`.
- تسجيل Controllers وServices.
- Import داخل `AppModule`.

### Phase 3 — Product Settings & Pricing
إنشاء:
- `EcommerceProductService`
- `EcommercePricingService`

Endpoints:

```text
GET /api/v1/admin/ecommerce/products/:variantId/settings
PUT /api/v1/admin/ecommerce/products/:variantId/settings
```

عند تحديث العمولة:
1. قراءة RETAIL.
2. حساب REP.
3. Upsert `ecommerce_product_settings`.
4. Upsert `product_prices` بسعر `REP`.

### Phase 4 — Catalog
Endpoints:

```text
GET /api/v1/store/products
GET /api/v1/store/products/:variantId
GET /api/v1/store/categories
```

Backend يحدد السعر:

```text
Guest -> RETAIL
Representative -> REP
```

ولا يقبل `price_type` من Frontend.

### Phase 5 — Stock
إنشاء `EcommerceStockService`.

Catalog:

```text
available_quantity =
SUM(quantity_on_hand - quantity_reserved)
```

لكل `variant_id` وعلى المخازن النشطة الداخلة ضمن نطاق المتجر.

عند Accept:
- اختيار مخزن واحد.
- التحقق من توفر كامل الكمية في ذلك المخزن.
- V1 لا يدعم Split Fulfillment.

### Phase 6 — Cart
Endpoints:

```text
GET    /api/v1/store/cart
POST   /api/v1/store/cart/items
PATCH  /api/v1/store/cart/items/:id
DELETE /api/v1/store/cart/items/:id
DELETE /api/v1/store/cart
```

Guest يستخدم:

```text
X-Cart-Token
```

Representative يستخدم `user_id` من JWT.

### Phase 7 — Guest Checkout
Endpoint:

```text
POST /api/v1/store/checkout/guest
```

Body:

```json
{
  "customer_name": "Ali",
  "customer_phone": "07700000000",
  "customer_email": null,
  "customer_address": "Baghdad",
  "notes": null,
  "idempotency_key": "uuid"
}
```

الـBackend يعيد حساب RETAIL من قاعدة البيانات، ينشئ Order + Snapshot، يولد `public_token`، ويفرغ السلة.

### Phase 8 — Representative Checkout
Endpoint:

```text
POST /api/v1/store/checkout/representative
```

Body لموجود مسبقاً:

```json
{
  "party_type": "CUSTOMER",
  "party_id": "uuid",
  "payment_type": "CREDIT",
  "notes": null,
  "idempotency_key": "uuid"
}
```

Body لجهة حرة:

```json
{
  "party_type": "OTHER",
  "party_name": "مكتب جبار",
  "party_phone": "077...",
  "party_address": "بغداد",
  "payment_type": "CASH",
  "idempotency_key": "uuid"
}
```

### Phase 9 — Orders
Representative:

```text
GET  /api/v1/store/orders
GET  /api/v1/store/orders/:id
POST /api/v1/store/orders/:id/cancel
```

Guest:

```text
GET  /api/v1/store/guest/orders/:orderNumber
POST /api/v1/store/guest/orders/:orderNumber/cancel
```

Guest يجب أن يرسل:

```text
X-Order-Token
```

### Phase 10 — Central Approval
Endpoints:

```text
GET  /api/v1/admin/ecommerce/orders
GET  /api/v1/admin/ecommerce/orders/:id
POST /api/v1/admin/ecommerce/orders/:id/accept
POST /api/v1/admin/ecommerce/orders/:id/reject
```

Accept Body:

```json
{
  "warehouse_id": "uuid"
}
```

### OrderApprovalService
داخل Transaction:

```text
Lock order
validate status == SUBMITTED
validate warehouse
validate stock
reuse M08 Sales Service
create invoice
create invoice items
stock OUT through existing sales logic
update order -> ACCEPTED
save sales_invoice_id
```

M12 لا يكرر منطق المخزون أو الفواتير أو الحسابات.

## 14. Party Resolution

إنشاء `EcommercePartyService`:

```text
CUSTOMER       -> customers
SUPPLIER       -> suppliers
BRANCH         -> branches
REPRESENTATIVE -> representatives
OTHER          -> snapshot only
```

يرجع:

```typescript
{
  type,
  id,
  name,
  phone,
  address
}
```

## 15. Guest عند Accept

عند قبول طلب Guest:

1. ابحث عن Customer بنفس الهاتف.
2. إذا موجود استخدمه.
3. إذا غير موجود أنشئ Customer محاسبي.
4. اربطه بـ `sales_invoice.customer_id`.

لا يتم إنشاء User Login للـGuest.

## 16. Permissions

```text
ecommerce:products_manage
ecommerce:store_use
ecommerce:orders_read
ecommerce:orders_accept
ecommerce:orders_reject
ecommerce:orders_cancel
```

## 17. Optional JWT

Catalog وCart يقبلان Guest أو Representative.

أنشئ:

```text
OptionalJwtAuthGuard
```

إذا Token موجود وصحيح يملأ `req.user`، وإذا لا يوجد يبقى Guest.

Checkout المندوب يبقى خلف `JwtAuthGuard`.

## 18. Error Codes

```text
ECOMMERCE_PRODUCT_DISABLED
ECOMMERCE_PRICE_NOT_FOUND
ECOMMERCE_CART_NOT_FOUND
ECOMMERCE_CART_EMPTY
ECOMMERCE_CART_ITEM_NOT_FOUND
ECOMMERCE_REP_REQUIRED
ECOMMERCE_REP_INACTIVE
ECOMMERCE_PARTY_NOT_FOUND
ECOMMERCE_INVALID_PARTY
ECOMMERCE_ORDER_NOT_FOUND
ECOMMERCE_ORDER_ALREADY_PROCESSED
ECOMMERCE_ORDER_NOT_CANCELLABLE
ECOMMERCE_INVALID_ORDER_TOKEN
ECOMMERCE_INSUFFICIENT_STOCK
ECOMMERCE_WAREHOUSE_REQUIRED
```

## 19. Concurrency & Idempotency

- لا تستخدم `count + 1` لتوليد رقم الطلب.
- استخدم PostgreSQL Sequence مثل:
  ```text
  EC-2026-000001
  ```
- Checkout يستخدم `idempotency_key`.
- Accept يجب أن يكون Idempotent.
- استخدم Row Lock أو آلية مكافئة داخل Transaction لمنع إنشاء فاتورتين لنفس الطلب.

## 20. الاختبارات

### Pricing
```text
Guest -> RETAIL
Representative -> REP
Frontend cannot choose price type
```

### Cart
```text
Guest by session token
Representative by user id
```

### Checkout
```text
empty cart rejected
inactive product rejected
missing price rejected
snapshot saved
idempotency works
```

### Stock
```text
catalog aggregated quantity
SUBMITTED does not reserve stock
ACCEPT validates selected warehouse
```

### Status
```text
SUBMITTED -> ACCEPTED
SUBMITTED -> REJECTED
SUBMITTED -> CANCELLED
```

### Concurrency
```text
two Accept requests -> one invoice only
```

## 21. ما لا يدخل في V1

```text
Online Payment
Delivery Tracking
Coupons
Wishlist
Reviews
Split Warehouse Fulfillment
Stock Reservation
OTP Login
Customer Accounts
Complex Promotions
```

## 22. اعتماد M12 على الموديولات الحالية

```text
M01 Auth
M02 Branches & Warehouses
M03 Products
M05 Inventory
M08 Sales
M09 Representatives
M10 Accounts
```

## 23. المعمارية النهائية

```text
M12 Ecommerce
   |
   +--> M03 Products / product_prices
   +--> M05 Inventory / stock_levels
   +--> M09 Representatives
   |
   +--> Ecommerce Order
             |
             v
       Central Approval
             |
             v
          M08 Sales
             |
        +----+----+
        v         v
     Invoice   Stock OUT
```

M12 هو طبقة طلبات فوق النظام الحالي، وليس نظام مبيعات ثانٍ.
