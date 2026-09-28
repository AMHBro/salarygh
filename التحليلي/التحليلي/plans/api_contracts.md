# 📡 API Contracts — نظام Sayler

> هذا الملف هو المرجع الرسمي بين Backend وFrontend  
> **أي تغيير في الـ API يجب أن يُحدَّث هنا أولاً**

---

## Base URL
```
Development:  http://localhost:3000/api/v1
Production:   https://api.sayler.app/v1
Swagger Docs: http://localhost:3000/api/docs
```

## Headers المطلوبة
```
Authorization: Bearer <jwt_token>
Content-Type: application/json
X-Device-ID: <uuid>          // للـ Offline Sync
X-Branch-ID: <uuid>          // الفرع الحالي
Accept-Language: ar
```

---

## 📐 صيغة الـ Response الموحدة

### ✅ نجاح
```json
{
  "success": true,
  "data": {},
  "meta": {
    "page": 1,
    "per_page": 20,
    "total": 150,
    "total_pages": 8
  }
}
```

### ❌ خطأ
```json
{
  "success": false,
  "error": {
    "code": "INSUFFICIENT_STOCK",
    "message": "الكمية المطلوبة غير متوفرة في المخزن",
    "field": "items[0].quantity",
    "details": {
      "available": 5,
      "requested": 10
    }
  }
}
```

---

## 🔐 M01 — Auth

### POST `/auth/login`
```json
// Request
{ "username": "admin", "password": "123456" }

// Response 200
{
  "data": {
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "expires_in": 3600,
    "user": {
      "id": "uuid",
      "username": "admin",
      "full_name": "مدير النظام",
      "role": "ADMIN",
      "branch_id": "uuid",
      "permissions": ["sales:create", "inventory:read", ...]
    }
  }
}
```

### POST `/auth/refresh`
```json
// Request
{ "refresh_token": "eyJ..." }

// Response 200
{ "data": { "access_token": "eyJ...", "expires_in": 3600 } }
```

### POST `/auth/logout`
```json
// Response 200
{ "success": true, "data": { "message": "تم تسجيل الخروج" } }
```

---

## 🏢 M02 — Branches & Warehouses

### GET `/branches`
```json
// Response
{
  "data": [
    { "id": "uuid", "name": "المكتب الرئيسي", "address": "بغداد - الكرادة" }
  ]
}
```

### GET `/warehouses?branch_id=<uuid>`
```json
{
  "data": [
    { "id": "uuid", "name": "المخزن الرئيسي", "branch_id": "uuid", "type": "MAIN" }
  ]
}
```

---

## 📦 M03 — Products

### GET `/products`
```
Query: ?page=1&limit=20&search=<text>&category_id=<uuid>&is_active=true
```
```json
{
  "data": [
    {
      "id": "uuid",
      "name_ar": "منتج تجريبي",
      "barcode": "625123456001",
      "category": { "id": "uuid", "name_ar": "إلكترونيات" },
      "variants": [
        {
          "id": "uuid",
          "attributes": {},
          "retail_price": 12000,
          "wholesale_price": 10000,
          "stock": { "warehouse_id": "uuid", "quantity_on_hand": 35 }
        }
      ]
    }
  ],
  "meta": { "total": 1248, "page": 1, "per_page": 20 }
}
```

### GET `/products/barcode/:barcode`
```json
// Response: نفس شكل المنتج + stock للمخزن الحالي
```

### POST `/products`
```json
// Request
{
  "name_ar": "اسم المنتج",
  "name_en": "Product Name",
  "barcode": "625123456001",
  "category_id": "uuid",
  "unit_of_measure": "قطعة",
  "has_variants": false,
  "has_expiry": false,
  "min_stock_level": 5,
  "retail_price": 15000,
  "wholesale_price": 13000
}
```

---

## 🏭 M04 — Suppliers & Purchases

### GET `/suppliers`
```
Query: ?page=1&limit=20&search=<text>
```

### GET `/purchases`
```
Query: ?page=1&limit=20&status=PAID&from=2026-01-01&to=2026-12-31&supplier_id=<uuid>
```

### POST `/purchases`
```json
// Request
{
  "supplier_id": "uuid",
  "warehouse_id": "uuid",
  "payment_type": "CASH",
  "invoice_date": "2026-08-22",
  "items": [
    {
      "variant_id": "uuid",
      "quantity": 100,
      "unit_price": 5000,
      "batch_number": "BATCH-001",
      "expiry_date": "2027-01-01"
    }
  ],
  "notes": "ملاحظة"
}

// Response 201
{
  "data": {
    "id": "uuid",
    "invoice_number": "PO-2026-0001",
    "total": 500000,
    "status": "CONFIRMED"
  }
}
```

---

## 📊 M05 — Inventory

### GET `/inventory/stock`
```
Query: ?warehouse_id=<uuid>&below_minimum=true
```
```json
{
  "data": [
    {
      "variant_id": "uuid",
      "product_name": "منتج تجريبي",
      "warehouse": "المخزن الرئيسي",
      "quantity_on_hand": 35,
      "quantity_reserved": 5,
      "quantity_available": 30,
      "min_stock_level": 10,
      "is_below_minimum": false
    }
  ]
}
```

### GET `/inventory/movements`
```
Query: ?variant_id=<uuid>&warehouse_id=<uuid>&from=<date>&to=<date>
```

---

## 🛒 M08 — Sales (POS)

### POST `/sales/invoices`
```json
// Request
{
  "customer_id": "uuid | null",
  "warehouse_id": "uuid",
  "price_type": "RETAIL",
  "payment_type": "CASH",
  "items": [
    {
      "variant_id": "uuid",
      "quantity": 2,
      "unit_price": 12000,
      "discount_percent": 0
    }
  ],
  "discount_amount": 0,
  "paid_amount": 24000,
  "idempotency_key": "uuid-v4",
  "notes": null
}

// Response 201
{
  "data": {
    "id": "uuid",
    "invoice_number": "INV-2026-1008",
    "total": 24000,
    "paid_amount": 24000,
    "due_amount": 0,
    "status": "PAID",
    "items": [...],
    "created_at": "2026-08-22T11:30:00Z"
  }
}

// Errors:
// 409: { code: "INVOICE_ALREADY_EXISTS", data: <existing_invoice> }
// 422: { code: "INSUFFICIENT_STOCK", details: { variant_id, available, requested } }
// 422: { code: "CREDIT_LIMIT_EXCEEDED", details: { limit, current_balance } }
```

### GET `/sales/invoices`
```
Query: ?page=1&limit=20&status=PAID&customer_id=<uuid>&from=<date>&to=<date>&search=<invoice_number>
```

### GET `/sales/invoices/:id`
```json
// Response: فاتورة كاملة مع items + customer + payments history
```

---

## 💰 M10 — Payments & Accounts

### GET `/accounts`
```
Query: ?type=CUSTOMER|SUPPLIER|REPRESENTATIVE&has_balance=true
```
```json
{
  "data": [
    {
      "id": "uuid",
      "account_type": "CUSTOMER",
      "name": "أحمد محمد",
      "phone": "07701234567",
      "total_amount": 3450000,
      "paid_amount": 2900000,
      "balance": 550000,
      "last_payment": "2026-08-17"
    }
  ]
}
```

### POST `/payments`
```json
// Request
{
  "voucher_type": "RECEIPT",
  "account_type": "CUSTOMER",
  "account_id": "uuid",
  "amount": 100000,
  "payment_method": "CASH",
  "notes": "دفعة جزئية"
}

// Response 201
{
  "data": {
    "id": "uuid",
    "voucher_number": "RV-2026-0042",
    "amount": 100000,
    "remaining_balance": 450000
  }
}
```

---

## 👤 M09 — Representatives

### GET `/representatives`
```json
{
  "data": [
    {
      "id": "uuid",
      "name": "أحمد علي",
      "phone": "07705555555",
      "commission_rate": 5,
      "total_sales": 8450000,
      "commission_earned": 422500,
      "commission_paid": 300000,
      "commission_due": 122500,
      "status": "ACTIVE"
    }
  ]
}
```

---

## 🔄 Sync Engine

### POST `/sync/push`
```json
// Request
{
  "device_id": "uuid",
  "last_seq": 1520,
  "changes": [
    {
      "entity_type": "sales_invoices",
      "entity_id": "uuid",
      "operation": "CREATE",
      "payload": { ...invoice_data },
      "client_version": 1,
      "idempotency_key": "uuid",
      "client_timestamp": "2026-08-22T10:00:00Z"
    }
  ]
}

// Response
{
  "data": {
    "accepted": ["uuid1", "uuid2"],
    "rejected": [],
    "conflicts": [],
    "server_seq": 1530
  }
}
```

### GET `/sync/pull?last_seq=1520`
```json
{
  "data": {
    "changes": [
      {
        "entity_type": "stock_levels",
        "entity_id": "uuid",
        "operation": "UPDATE",
        "data": { "quantity_on_hand": 28 },
        "server_seq": 1521
      }
    ],
    "current_seq": 1530,
    "has_more": false
  }
}
```

---

## 📊 M11 — Dashboard

### GET `/dashboard/summary`
```
Query: ?date=today|week|month&branch_id=<uuid>
```
```json
{
  "data": {
    "sales_today": 2450000,
    "invoices_count": 38,
    "unpaid_debts": 820000,
    "low_stock_count": 12,
    "products_count": 1248,
    "cash_sales": 1320000,
    "credit_sales": 620000,
    "rep_sales": 510000,
    "recent_invoices": [...],
    "low_stock_items": [...]
  }
}
```

---

## 🔔 WebSocket Events (Socket.IO)

```typescript
// Client subscribes
socket.on('connect', () => {
  socket.emit('join_branch', { branch_id: 'uuid' });
});

// Server emits
socket.on('stock_alert',     (data) => { /* مخزون منخفض */ });
socket.on('new_invoice',     (data) => { /* فاتورة جديدة */ });
socket.on('payment_received',(data) => { /* دفعة واردة */ });
socket.on('sync_update',     (data) => { /* تحديث مزامنة */ });
```

---

## 📝 Error Codes الكاملة

```typescript
// Auth
AUTH_INVALID_CREDENTIALS    = 'بيانات الدخول غير صحيحة'
AUTH_TOKEN_EXPIRED           = 'انتهت صلاحية الجلسة'
AUTH_INSUFFICIENT_PERMISSIONS= 'لا تملك صلاحية هذا الإجراء'

// Stock
INSUFFICIENT_STOCK           = 'الكمية غير متوفرة في المخزن'
PRODUCT_NOT_FOUND            = 'المنتج غير موجود'

// Sales
INVOICE_ALREADY_EXISTS       = 'الفاتورة موجودة مسبقاً'
CREDIT_LIMIT_EXCEEDED        = 'تجاوز حد الائتمان'
CASHBOX_NOT_OPEN             = 'الكاشير غير مفتوح'
PRICE_BELOW_COST             = 'السعر أقل من التكلفة'

// Payments
PAYMENT_EXCEEDS_BALANCE      = 'المبلغ أكبر من الرصيد المستحق'

// Transfers
SAME_WAREHOUSE_TRANSFER      = 'لا يمكن التحويل لنفس المخزن'
TRANSFER_ALREADY_RECEIVED    = 'التحويل تم استلامه مسبقاً'
```

---

> **آخر تحديث**: أغسطس 2026  
> **يجب إشعار الفريق عند أي تعديل في هذا الملف**
