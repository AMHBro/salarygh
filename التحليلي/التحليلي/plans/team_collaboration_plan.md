# 🤝 خطة التعاون بين Backend & Frontend — نظام Sayler

> **أنت**: Backend Developer (NestJS)  
> **شريكك**: Frontend Developer  
> **الهدف**: إنجاز المشروع بأسرع وقت مع أقل تعارضات

---

## 🧠 المبدأ الأساسي: **API-First Development**

> قبل أن تكتب سطراً واحداً من الـ business logic،  
> **اتفق على عقد الـ API أولاً** ← هذا يجعل شريكك يبدأ الـ Frontend بالتوازي معك.

```
أنت تكتب:         شريكك يكتب:
Schema → DTO       Mock Data → UI
Controller Stub    Real UI connected to Mock
→ يتوافقان عند الربط الحقيقي
```

---

## 🛠️ الأدوات المطلوبة (كلاكما)

| الأداة | الغرض | الرابط |
|--------|--------|--------|
| **GitHub** | كود مشترك + PR + Code Review | github.com |
| **Notion / Jira** | إدارة المهام والسبرينتات | notion.so |
| **Postman (Shared Workspace)** | اختبار API + توثيقه | postman.com |
| **Swagger (auto)** | وثائق API تلقائية من NestJS | `/api/docs` |
| **Discord / Slack** | تواصل يومي سريع | — |
| **Figma** | الواجهات المصممة (شريكك يطلع عليها) | — |
| **draw.io** | رسم خرائط الـ API والـ DB | — |

---

## 📁 هيكل المستودعات (Repositories)

```
GitHub Organization: sayler-system/
├── sayler-backend/          ← أنت
├── sayler-frontend/         ← شريكك
├── sayler-docs/             ← مشترك (API contracts, DB schema, meeting notes)
└── sayler-deploy/           ← Docker Compose, CI/CD configs
```

### قواعد الـ Branches

```
main          ← production only (محمي، PR فقط)
develop       ← integration branch (كلاكما تدمجان هنا)
feature/xxx   ← كل مهمة في branch منفصل
fix/xxx       ← إصلاح bugs
```

---

## 📋 طريقة العمل اليومية (Sprint-Based)

### مدة السبرينت: **أسبوعان**

```
اليوم 1 (الاثنين) — Sprint Planning
├── مراجعة المهام المتبقية
├── كل واحد يأخذ مهامه للأسبوعين
├── تحديد "API Contract" للـ features الجديدة
└── توثيق الـ API في Postman/Swagger قبل البدء

أيام 2-9 — Development
├── كل واحد يشتغل بشكل مستقل
├── Daily standup (10 دقائق): "شو عملت؟ شو راح تعمل؟ في عوائق؟"
├── PR Reviews: كل PR يحتاج موافقة الثاني
└── Merge إلى develop يومياً أو عند اكتمال feature

اليوم 10 (الجمعة الثانية) — Sprint Review
├── عرض ما تم إنجازه
├── اختبار الـ Integration
├── تسوية الـ bugs
└── تخطيط السبرينت القادم
```

---

## 🔗 نظام الـ API Contract

### الخطوات قبل بدء أي Feature:

**1. أنت تكتب الـ Contract (Backend)**
```typescript
// في ملف: sayler-docs/api-contracts/M08_sales.md

// POST /sales/invoices
// Request:
{
  customer_id?: string,       // null = زبون نقدي
  warehouse_id: string,
  price_type: 'RETAIL' | 'WHOLESALE' | 'COST',
  payment_type: 'CASH' | 'CREDIT' | 'PARTIAL',
  items: [
    {
      variant_id: string,
      quantity: number,
      unit_price: number,
      discount_percent?: number
    }
  ],
  idempotency_key: string,
  notes?: string
}

// Response 201:
{
  id: string,
  invoice_number: string,
  total: number,
  status: 'PAID' | 'PARTIAL',
  ...
}

// Errors:
// 400: validation error
// 409: idempotency_key already exists
// 422: insufficient stock
```

**2. شريكك يبني الـ UI على المواصفة**  
ويستخدم Mock Server (مثل `json-server` أو `MSW`) حتى يجهز الـ Backend

**3. أنت تبني الـ Endpoint**  
عند انتهائك، شريكك يبدّل الـ Mock بالـ API الحقيقي

---

## 📊 لوحة المهام (Task Board)

### الأعمدة:
```
📋 Backlog → 🎯 Sprint → 🔄 In Progress → 👀 Review → ✅ Done
```

### نموذج بطاقة المهمة:
```
Title: [M08] Sales Invoice API
Type: Backend / Frontend / Both
Priority: High / Medium / Low
Assigned: @backend_dev / @frontend_dev
API Contract: Link to docs
Estimate: 3 days
Blocked by: M05 (Stock levels)
```

---

## 🚦 ترتيب التطوير المقترح (Parallel Tracks)

```
الأسبوع    Backend (أنت)              Frontend (شريكك)
─────────────────────────────────────────────────────────
1-2        Auth + DB Setup            Login UI + Layout
           M01 (Users/Roles)          Auth Flow + Guards

3-4        M02 (Branches/Warehouses)  Dashboard UI
           M03 (Products)             Products Management UI

5-6        M04 (Suppliers/Purchases)  Purchases UI
           M05 (Inventory)            Inventory UI + Stock View

7-8        M08 (Sales POS)            POS Interface (الأهم)
           M09 (Representatives)      Representatives UI

9-10       M10 (Payments/Accounts)    Payments & Debts UI
           M06 (Transfers)            Transfers UI

11-12      M07 (Stocktaking)          Stocktaking UI
           M11 (Reports API)          Reports & Charts UI

13-14      Sync Engine (Backend)      Sync Queue (Frontend)
           M13 (E-commerce API)       E-commerce UI

15-16      Integration Testing        Bug Fixes
           Performance Tuning         UI Polish
```

---

## 📡 تعريفات مشتركة يجب الاتفاق عليها الآن

### 1. صيغة الـ Response الموحدة
```typescript
// Success
{
  success: true,
  data: { ... },
  meta: {
    page?: number,
    total?: number,
    per_page?: number
  }
}

// Error
{
  success: false,
  error: {
    code: 'INSUFFICIENT_STOCK',    // كود قابل للترجمة
    message: 'الكمية غير كافية',
    details?: { ... }
  }
}
```

### 2. الـ Pagination
```
GET /products?page=1&limit=20&search=قهوة&sort=name&order=asc
```

### 3. الـ Date Format
```
ISO 8601: "2026-08-22T11:30:00.000Z"
```

### 4. الـ Auth Header
```
Authorization: Bearer <jwt_token>
X-Device-ID: <uuid>        // للـ Offline Sync
X-Branch-ID: <uuid>        // الفرع النشط
```

### 5. أكواد الأخطاء الموحدة
```typescript
enum ErrorCodes {
  INSUFFICIENT_STOCK     = 'INSUFFICIENT_STOCK',
  INVOICE_ALREADY_EXISTS = 'INVOICE_ALREADY_EXISTS',
  CUSTOMER_CREDIT_LIMIT  = 'CUSTOMER_CREDIT_LIMIT',
  UNAUTHORIZED_ACTION    = 'UNAUTHORIZED_ACTION',
  PRODUCT_NOT_FOUND      = 'PRODUCT_NOT_FOUND',
  // ...
}
```

---

## 🔄 سير عمل الـ Feature (مثال عملي)

**السيناريو**: تطوير شاشة المبيعات POS

```
📅 يوم 1 — الاتفاق
├── [أنت] تكتب API Contract لـ POST /sales/invoices
├── [شريكك] يراجعه ويقترح تعديلات
└── [كلاكما] توافقان → يبدأ العمل

📅 يوم 2-3 — التطوير المتوازي
├── [أنت] تبني:
│   ├── SalesInvoice Entity
│   ├── CreateSaleDto (validation)
│   ├── SalesService.createInvoice()
│   └── SalesController POST /sales/invoices
│
└── [شريكك] يبني:
    ├── POS Screen UI
    ├── Cart Management
    ├── MSW Mock للـ API
    └── Sales flow كاملة مع Mock

📅 يوم 4 — الربط
├── [أنت] تعلن: "API جاهز على develop"
├── [شريكك] يحذف الـ Mock ويوصل الـ Real API
└── [كلاكما] تختبران معاً → PR → Merge

📅 يوم 5 — Edge Cases
└── معالجة الأخطاء، الـ offline، الـ validation messages
```

---

## 📝 نموذج Daily Standup (10 دقائق)

```
أنت:
 ✅ أمس: أكملت auth endpoints + JWT
 🔄 اليوم: أبدأ products CRUD
 🚧 عائق: لا يوجد

شريكك:
 ✅ أمس: أكملت login UI + token storage  
 🔄 اليوم: أبدأ dashboard layout
 🚧 عائق: محتاج API /dashboard/summary
 
→ [أنت] تعطيه promise date للـ API
```

---

## 🚨 قواعد لا تكسرها

1. **❌ لا تعدّل API response شكله بدون إخبار شريكك** — يكسر الـ Frontend
2. **❌ لا تمسح field من الـ Response** — استخدم deprecation أولاً
3. **✅ كل تغيير في الـ API → أضفه في Swagger + أخبر شريكك**
4. **✅ الـ develop branch يجب أن يكون deployable دائماً**
5. **✅ لا تدمج PR بدون review من الثاني** (إلا في emergency)
6. **✅ كل feature تنتهي منها → أكتب test واحد على الأقل**

---

## 🏃‍♂️ للبدء الآن (First Steps)

### أنت تفعل:
- [ ] أنشئ Organization على GitHub: `sayler-system`
- [ ] أنشئ repo: `sayler-backend` + `sayler-docs`
- [ ] أضف شريكك كـ Collaborator
- [ ] أنشئ مشروع NestJS واعمل له push
- [ ] شارك رابط Swagger مع شريكك حين يكون جاهزاً

### شريكك يفعل:
- [ ] أنشئ repo: `sayler-frontend`
- [ ] حدد الـ Framework (React/Vue/Next)
- [ ] ثبّت `msw` للـ Mock API
- [ ] ابدأ بالـ Layout والـ Auth UI

### معاً:
- [ ] أنشئوا Notion Workspace مشترك (أو Jira)
- [ ] اتفقوا على صيغة الـ Response الموحدة (أعلاه)
- [ ] اتفقوا على Error Codes
- [ ] حددوا وقت الـ Daily Standup (مثلاً: 10 صباحاً)
- [ ] اعملوا أول Sprint Planning

---

## 📈 مؤشرات النجاح (KPIs للفريق)

| المؤشر | الهدف |
|--------|-------|
| Features per sprint | 3-4 features مكتملة |
| PR Review time | < 24 ساعة |
| Integration bugs | < 2 بعد كل sprint |
| API contract violations | 0 |
| Daily standup attendance | 100% |

