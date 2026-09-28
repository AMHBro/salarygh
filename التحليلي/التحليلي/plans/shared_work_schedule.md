# 📅 جدول التعاون — نظام المبيعات Sayler
### Backend ↔ Frontend Sync Schedule

---

> **المدة الكلية**: 5 أسابيع  
> **Backend**: NestJS + PostgreSQL  
> **المزامنة**: Symatric DS (Online/Offline)  
> **E-commerce**: مصغر (مدمج في النظام)

---

## 🗂️ ما تم تأجيله (خارج الـ 5 أسابيع)
> - ❌ الجرد والتسوية (M07)  
> - ❌ التقارير المتقدمة  
> - ❌ الأرشيف  

---

## 📐 الاتفاقيات الأساسية (قبل أي شيء)

### Base URL
```
Local:  http://localhost:3000/api/v1
Swagger: http://localhost:3000/api/docs
```

### كل Response بهذا الشكل
```json
// نجاح
{ "success": true, "data": {}, "meta": { "page": 1, "total": 0 } }

// خطأ
{ "success": false, "error": { "code": "ERROR_CODE", "message": "رسالة للمستخدم" } }
```

### Auth Header (في كل request)
```
Authorization: Bearer <token>
X-Device-ID: <uuid>
X-Branch-ID: <uuid>
```

### Pagination
```
GET /resource?page=1&limit=20&search=<text>&sort=created_at&order=desc
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━
## 🟥 الأسبوع الأول — الأساس + Auth + المنتجات
## ━━━━━━━━━━━━━━━━━━━━━━━━━

---

### 📌 السبت — يوم الإعداد

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | تهيئة NestJS + Docker + قاعدة البيانات | تهيئة مشروع + Layout الرئيسي |
| **الناتج** | Server يشتغل على port 3000 | Layout بالـ Sidebar والـ Router |
| **تنسيق مطلوب** | شارك رابط الـ repo | شارك رابط الـ repo |

---

### 📌 الأحد — Auth كامل

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Login API + JWT + Refresh Token + RBAC | Login Page + Token Storage + Auth Guard |
| **الـ API الجاهزة اليوم** | `POST /auth/login` `POST /auth/refresh` `POST /auth/logout` `GET /auth/me` | ـ |
| **ملاحظة** | Response يتضمن: token + user + permissions[] | خزّن الـ permissions في الـ store |

**📦 Response نموذجي `/auth/login`:**
```json
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
      "permissions": ["sales:create", "inventory:read"]
    }
  }
}
```

---

### 📌 الاثنين — المستخدمون + الأدوار

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Users CRUD + Roles CRUD + Permissions | Users Management Page + Roles |
| **الـ API الجاهزة اليوم** | `GET/POST /users` `GET/PUT/DELETE /users/:id` `GET /roles` | ـ |

---

### 📌 الثلاثاء — الأصناف + المنتجات

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Categories CRUD + Products CRUD | Products List + Add/Edit Form |
| **الـ API الجاهزة اليوم** | `GET/POST /categories` `GET/POST /products` `GET /products/:id` | ـ |

**📦 Response نموذجي `GET /products`:**
```json
{
  "data": [
    {
      "id": "uuid",
      "name_ar": "منتج تجريبي",
      "barcode": "625123456001",
      "category": { "id": "uuid", "name_ar": "إلكترونيات" },
      "unit_of_measure": "قطعة",
      "retail_price": 12000,
      "wholesale_price": 10000,
      "min_stock_level": 5,
      "is_active": true
    }
  ],
  "meta": { "total": 1248, "page": 1, "per_page": 20 }
}
```

---

### 📌 الأربعاء — متغيرات المنتج + البحث بالباركود

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Product Variants + Barcode Search API | Barcode Scanner Input + Variant Display |
| **الـ API الجاهزة اليوم** | `GET /products/barcode/:barcode` `GET/POST /products/:id/variants` | ـ |

---

### 📌 الخميس — Integration + Bug Fixes

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | إصلاح أي مشاكل + Swagger docs | ربط كل الصفحات بالـ API الحقيقي |
| **اجتماع** | ✅ **Review مشترك آخر اليوم** | ✅ **Review مشترك آخر اليوم** |

### 🏁 تسليم نهاية الأسبوع 1:
- ✅ Login يشتغل
- ✅ إضافة وتعديل وحذف المنتجات
- ✅ البحث بالباركود

---
---

## ━━━━━━━━━━━━━━━━━━━━━━━━━
## 🟧 الأسبوع الثاني — المخازن + المشتريات + المخزون
## ━━━━━━━━━━━━━━━━━━━━━━━━━

---

### 📌 السبت — الفروع والمخازن

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Branches + Warehouses CRUD | Warehouses Page + Branch Selector |
| **الـ API الجاهزة اليوم** | `GET/POST /branches` `GET/POST /warehouses` `GET /warehouses?branch_id=` | ـ |

---

### 📌 الأحد — المخزون الحالي

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Stock Levels API + Low Stock Alerts | Stock View Page + تنبيهات المخزون |
| **الـ API الجاهزة اليوم** | `GET /inventory/stock?warehouse_id=&below_minimum=` `GET /inventory/movements` | ـ |

**📦 Response نموذجي `GET /inventory/stock`:**
```json
{
  "data": [
    {
      "variant_id": "uuid",
      "product_name": "منتج تجريبي",
      "barcode": "625123456001",
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

---

### 📌 الاثنين — الموردون

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Suppliers CRUD + Balance Tracking | Suppliers List + Add/Edit |
| **الـ API الجاهزة اليوم** | `GET/POST /suppliers` `GET/PUT/DELETE /suppliers/:id` | ـ |

---

### 📌 الثلاثاء — فاتورة الشراء

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Purchase Invoices API + Items | Purchase Invoice Form |
| **الـ API الجاهزة اليوم** | `POST /purchases` `GET /purchases` `GET /purchases/:id` | ـ |

**📦 Request نموذجي `POST /purchases`:**
```json
{
  "supplier_id": "uuid",
  "warehouse_id": "uuid",
  "payment_type": "CASH",
  "invoice_date": "2026-08-22",
  "items": [
    { "variant_id": "uuid", "quantity": 100, "unit_price": 5000 }
  ]
}
```

---

### 📌 الأربعاء — تأكيد الشراء وتحديث المخزون

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | `POST /purchases/:id/confirm` يحدّث المخزون تلقائياً | Purchase History + Confirm Button |
| **الـ API الجاهزة اليوم** | `POST /purchases/:id/confirm` `GET /purchases/:id/items` | ـ |

---

### 📌 الخميس — Integration

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Testing + Fixes | ربط كامل |
| **اجتماع** | ✅ **Review مشترك** | ✅ **Review مشترك** |

### 🏁 تسليم نهاية الأسبوع 2:
- ✅ شراء بضاعة → يظهر في المخزون تلقائياً
- ✅ تنبيه عند نقص المخزون

---
---

## ━━━━━━━━━━━━━━━━━━━━━━━━━
## 🔴 الأسبوع الثالث — POS المبيعات ← الأهم
## ━━━━━━━━━━━━━━━━━━━━━━━━━

---

### 📌 السبت — الزبائن

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Customers CRUD + Balance | Customers List + Add |
| **الـ API الجاهزة اليوم** | `GET/POST /customers` `GET /customers/:id` (يتضمن الرصيد والفواتير) | ـ |

---

### 📌 الأحد — الكاشير

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Cashboxes + Sessions (فتح/إغلاق) | Cashbox Open/Close UI |
| **الـ API الجاهزة اليوم** | `GET /cashboxes` `POST /cashboxes/:id/open` `POST /cashboxes/:id/close` | ـ |

---

### 📌 الاثنين — فاتورة البيع (Core)

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Sales Invoice API الكامل | POS Screen — Cart + Product Search |
| **الـ API الجاهزة اليوم** | `POST /sales/invoices` `GET /sales/invoices` | ـ |

**📦 Request نموذجي `POST /sales/invoices`:**
```json
{
  "customer_id": "uuid | null",
  "warehouse_id": "uuid",
  "price_type": "RETAIL",
  "payment_type": "CASH",
  "paid_amount": 24000,
  "items": [
    {
      "variant_id": "uuid",
      "quantity": 2,
      "unit_price": 12000,
      "discount_percent": 0
    }
  ],
  "idempotency_key": "uuid-v4-generated-by-frontend",
  "notes": null
}
```

**📦 Response + أكواد الخطأ:**
```json
// نجاح 201
{ "data": { "id": "uuid", "invoice_number": "INV-2026-1008", "total": 24000, "status": "PAID" } }

// خطأ مخزون ناقص 422
{ "error": { "code": "INSUFFICIENT_STOCK", "details": { "available": 5, "requested": 10 } } }

// فاتورة موجودة مسبقاً 409
{ "error": { "code": "INVOICE_ALREADY_EXISTS", "data": { ...existing_invoice } } }
```

---

### 📌 الثلاثاء — أنواع السعر والدفع

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Price Types (مفرد/جملة/كلفة/مندوب) + دفع آجل | POS Tabs + Customer Picker |
| **الـ API** | نفس `/sales/invoices` مع `price_type` و `payment_type` | ـ |

---

### 📌 الأربعاء — الطباعة + المبيعات السابقة

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | `GET /sales/invoices/:id` كامل + Print Data | Invoice Detail + Print Template |
| **الـ API الجاهزة اليوم** | `GET /sales/invoices/:id` (مع items + customer + payments) | ـ |

---

### 📌 الخميس — Integration + Test مكثف

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | اختبار كل السيناريوهات | اختبار POS بالكامل |
| **اجتماع** | ✅ **Test مشترك لـ POS** | ✅ **Test مشترك لـ POS** |

### 🏁 تسليم نهاية الأسبوع 3:
- ✅ بيع كامل (نقدي + آجل + جزئي)
- ✅ المخزون ينقص تلقائياً
- ✅ طباعة الفاتورة

---
---

## ━━━━━━━━━━━━━━━━━━━━━━━━━
## 🟨 الأسبوع الرابع — المندوبون + الديون + التحويلات + E-commerce
## ━━━━━━━━━━━━━━━━━━━━━━━━━

---

### 📌 السبت — المندوبون

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Representatives CRUD + Commission Calc | Representatives List + Details |
| **الـ API الجاهزة اليوم** | `GET/POST /representatives` `GET /representatives/:id/summary` | ـ |

**📦 Response `GET /representatives/:id/summary`:**
```json
{
  "data": {
    "id": "uuid",
    "name": "أحمد علي",
    "commission_rate": 5,
    "total_sales": 8450000,
    "commission_earned": 422500,
    "commission_paid": 300000,
    "commission_due": 122500
  }
}
```

---

### 📌 الأحد — عهدة المندوب

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Custody Orders (إرسال + استلام + تسوية) | Custody UI + Status Tracking |
| **الـ API الجاهزة اليوم** | `POST /custody-orders` `POST /custody-orders/:id/dispatch` `POST /custody-orders/:id/settle` | ـ |

---

### 📌 الاثنين — الحسابات والديون

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Accounts Ledger (زبائن + موردون + مندوبون) | Accounts Page + Balances |
| **الـ API الجاهزة اليوم** | `GET /accounts?type=CUSTOMER\|SUPPLIER\|REPRESENTATIVE` | ـ |

---

### 📌 الثلاثاء — سندات القبض والدفع

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Payment Vouchers API | Payment Form + History |
| **الـ API الجاهزة اليوم** | `POST /payments` (RECEIPT/PAYMENT) `GET /payments?account_id=` | ـ |

**📦 Request `POST /payments`:**
```json
{
  "voucher_type": "RECEIPT",
  "account_type": "CUSTOMER",
  "account_id": "uuid",
  "amount": 100000,
  "payment_method": "CASH",
  "notes": "دفعة جزئية"
}
```

---

### 📌 الأربعاء — التحويل بين المخازن + E-commerce (بداية)

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Warehouse Transfers + E-commerce Products API | Transfers UI + E-commerce Store Setup |
| **الـ API الجاهزة اليوم** | `POST /transfers` `GET /ecommerce/products` `GET /ecommerce/products/:slug` | ـ |

---

### 📌 الخميس — E-commerce (طلبات) + Integration

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | E-commerce Orders API | Cart + Checkout + Order Status |
| **الـ API الجاهزة اليوم** | `POST /ecommerce/orders` `GET /ecommerce/orders/:id/track` | ـ |

**📦 E-commerce Order Status Flow:**
```
PENDING_REVIEW → ACCEPTED → READY → OUT_FOR_DELIVERY → DELIVERED
```

### 🏁 تسليم نهاية الأسبوع 4:
- ✅ المندوبون + العهدة
- ✅ الديون + الدفعات (قبض/دفع)
- ✅ التحويل بين المخازن
- ✅ متجر إلكتروني مصغر

---
---

## ━━━━━━━━━━━━━━━━━━━━━━━━━
## 🟩 الأسبوع الخامس — Dashboard + Sync + التسليم
## ━━━━━━━━━━━━━━━━━━━━━━━━━

---

### 📌 السبت — Dashboard API

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Dashboard Summary API | Dashboard Cards + Charts |
| **الـ API الجاهزة اليوم** | `GET /dashboard/summary?period=today\|week\|month` | ـ |

**📦 Response `GET /dashboard/summary`:**
```json
{
  "data": {
    "sales_total": 2450000,
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

### 📌 الأحد — Symatric DS Sync Integration

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | ربط Symatric DS للمزامنة + Sync Endpoints | إعداد الـ Offline Mode + Sync Queue |
| **الـ API الجاهزة اليوم** | `POST /sync/push` `GET /sync/pull?last_seq=` `GET /sync/status` | ـ |

---

### 📌 الاثنين — تقارير أساسية

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Sales Report + Inventory Report API | Reports Pages |
| **الـ API الجاهزة اليوم** | `GET /reports/sales?from=&to=` `GET /reports/inventory` `GET /reports/debts` | ـ |

---

### 📌 الثلاثاء — إشعارات Real-time

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Socket.IO Events | WebSocket Client + Toast Notifications |
| **Events** | `stock_alert` `new_invoice` `payment_received` | ـ |

---

### 📌 الأربعاء — Bug Fixes + Polish

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Performance + Error Handling | UI Polish + Arabic Messages |

---

### 📌 الخميس — **🎉 Final Delivery**

| | Backend | Frontend |
|--|---------|----------|
| **المهمة** | Deploy + Final Testing | Final Testing |
| **اجتماع** | ✅ **UAT مشترك كامل** | ✅ **UAT مشترك كامل** |

---

## 📊 ملخص الـ APIs الكاملة (للمرجعية)

| الوحدة | الـ APIs |
|--------|---------|
| Auth | login, refresh, logout, me |
| Users | CRUD |
| Roles | CRUD + permissions |
| Branches | CRUD |
| Warehouses | CRUD |
| Categories | CRUD |
| Products | CRUD + barcode search + variants |
| Suppliers | CRUD |
| Purchases | CRUD + confirm |
| Inventory | stock levels + movements |
| Transfers | CRUD + dispatch + receive |
| Customers | CRUD + balance |
| Cashboxes | CRUD + open + close |
| Sales | create + list + detail + print |
| Representatives | CRUD + summary + commission |
| Custody | CRUD + dispatch + settle |
| Accounts | ledger + summary |
| Payments | create + list |
| E-commerce | products + orders + tracking |
| Dashboard | summary |
| Reports | sales + inventory + debts |
| Sync | push + pull + status |

---

## 🚨 قواعد العمل المشترك

1. **Swagger docs** على `http://localhost:3000/api/docs` — مرجعك الأول
2. **لا تعدّل شكل الـ Response بدون إشعار** — يكسر الـ Frontend
3. **كل API تنتهي منها** → أخبر شريكك فوراً عبر Discord/Slack
4. **idempotency_key** في فواتير البيع — الـ Frontend يولّده (UUID v4)
5. **Daily Standup** الساعة 10:00 صباحاً — 10 دقائق فقط
6. **الـ develop branch** يجب أن يشتغل دائماً

---

> 📌 **للتواصل الفوري**: Discord/WhatsApp  
> 📌 **الـ Swagger**: يُحدَّث تلقائياً مع كل endpoint جديد  
> 📌 **الـ GitHub**: `sayler-system/sayler-backend` و `sayler-system/sayler-frontend`
