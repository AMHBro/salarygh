# 🚀 خطة الإنجاز السريع — نظام Sayler
## المدة: 5 أسابيع (الحد الأقصى)

> ⚡ **وضع الطوارئ**: شهر واحد لكل شيء  
> **المبدأ**: نسلّم **Core MVP أولاً** ← ثم نضيف الـ Advanced Features

---

## 🎯 ما سنسلّمه في الشهر (MVP Scope)

### ✅ داخل الـ MVP (يجب الانتهاء منه)
| الوحدة | الأولوية |
|--------|----------|
| Auth + Roles + Permissions | 🔴 حرج |
| المنتجات + الباركود + الأصناف | 🔴 حرج |
| المخازن + الفروع | 🔴 حرج |
| المشتريات + إضافة مخزون | 🔴 حرج |
| **المبيعات POS** ← القلب | 🔴 حرج |
| الزبائن + الديون | 🔴 حرج |
| الموردون + ديونهم | 🔴 حرج |
| المندوبون + العهدة | 🟠 عالي |
| الدفعات (سند قبض/دفع) | 🟠 عالي |
| التحويل بين المخازن | 🟠 عالي |
| **المزامنة Symatric DS** | 🟠 عالي |
| **E-commerce مصغر** | 🟡 متوسط |
| لوحة التحكم (Dashboard) | 🟡 متوسط |
| تقارير أساسية | 🟡 متوسط |

### ❌ خارج الـ MVP (بعد التسليم)
| الوحدة | السبب |
|--------|--------|
| الجرد M07 | وقت لاحق |
| الأرشيف M12 | وقت لاحق |
| تقارير متقدمة | وقت لاحق |

---

## 📅 الخطة الأسبوعية التفصيلية

---

### ⚡ الأسبوع 1: الأساس + Auth + المنتجات
**الهدف**: نظام شغال + Login + إضافة منتجات

| اليوم | Backend (أنت) | Frontend (شريكك) |
|-------|--------------|-----------------|
| **السبت** | تهيئة NestJS + Docker + DB | تهيئة مشروع Frontend + Layout |
| **الأحد** | Auth Module كامل (Login/JWT/RBAC) | Login Page + Auth Guard |
| **الاثنين** | Users + Roles CRUD | Sidebar + Routing + لوحة التحكم Skeleton |
| **الثلاثاء** | Categories + Products CRUD | Products List + Add Product UI |
| **الأربعاء** | Product Variants + Barcode Search | Product Detail + Barcode Input |
| **الخميس** | Integration + Bug Fixes | Integration + Bug Fixes |

**✅ تسليم نهاية الأسبوع 1**: تسجيل دخول + إضافة منتجات

---

### ⚡ الأسبوع 2: المخازن + المشتريات + المخزون
**الهدف**: شراء بضاعة وإضافتها للمخزن

| اليوم | Backend (أنت) | Frontend (شريكك) |
|-------|--------------|-----------------|
| **السبت** | Branches + Warehouses CRUD | Warehouses UI + Stock View |
| **الأحد** | Stock Levels + Inventory Movements | Stock Levels Page |
| **الاثنين** | Suppliers CRUD | Suppliers List + Add |
| **الثلاثاء** | Purchase Invoices + Items | Purchase Invoice Form |
| **الأربعاء** | Stock Update on Purchase Confirm | Purchase History + View |
| **الخميس** | Integration + Low Stock Alerts | Integration + Testing |

**✅ تسليم نهاية الأسبوع 2**: شراء + مخزون يُحدَّث تلقائياً

---

### ⚡ الأسبوع 3: المبيعات POS ← الأهم
**الهدف**: بيع وطباعة فاتورة

| اليوم | Backend (أنت) | Frontend (شريكك) |
|-------|--------------|-----------------|
| **السبت** | Customers CRUD | Customers List + Add |
| **الأحد** | Cashboxes + Sessions API | Cashbox Open/Close UI |
| **الاثنين** | Sales Invoice API (كامل مع validations) | POS Screen — Cart + Search |
| **الثلاثاء** | Price Types (Retail/Wholesale/Rep) | POS — Customer Select + Price Type |
| **الأربعاء** | Payment Types (Cash/Credit/Partial) | POS — Checkout + Payment |
| **الخميس** | Print Invoice API + Integration | Invoice Print + Testing كامل |

**✅ تسليم نهاية الأسبوع 3**: POS كامل — بيع + دفع + طباعة ✅

---

### ⚡ الأسبوع 4: المندوبون + الديون + الدفعات
**الهدف**: إدارة مالية كاملة

| اليوم | Backend (أنت) | Frontend (شريكك) |
|-------|--------------|-----------------|
| **السبت** | Representatives CRUD + Commission | Representatives List + Details |
| **الأحد** | Rep Custody Orders (إرسال + استلام) | Custody UI |
| **الاثنين** | Accounts Ledger + Balances | Accounts & Debts Page |
| **الثلاثاء** | Payment Vouchers (قبض + دفع) | Payment Voucher Form |
| **الأربعاء** | Warehouse Transfers | Transfers UI |
| **الخميس** | Integration + Testing | Integration + Testing |

**✅ تسليم نهاية الأسبوع 4**: الجانب المالي كامل

---

### ⚡ الأسبوع 5: Dashboard + تقارير + Polish
**الهدف**: نظام جاهز للتسليم

| اليوم | Backend (أنت) | Frontend (شريكك) |
|-------|--------------|-----------------|
| **السبت** | Dashboard Summary API | Dashboard Charts + KPIs |
| **الأحد** | Reports APIs (مبيعات، مخزون، ديون) | Reports Pages |
| **الاثنين** | Bug Fixes + Performance | Bug Fixes + UI Polish |
| **الثلاثاء** | Permissions Fine-tuning | Error Handling + Messages |
| **الأربعاء** | Deployment Setup | Responsive + Print Styles |
| **الخميس** | **🎉 Final Testing + Delivery** | **🎉 Final Testing + Delivery** |

**✅ تسليم نهاية الأسبوع 5**: نظام كامل جاهز للإنتاج 🚀

---

## ⚡ قواعد العمل السريع (Wartime Rules)

> في وضع الطوارئ نغيّر أسلوب العمل:

### ✅ افعل
- **API Contract في 30 دقيقة** لا ساعات — اكتب الـ shape الأساسي وابدأ
- **Dummy Data للـ Frontend** — شريكك لا ينتظرك، يشتغل على Mock
- **PR Merge بدون Review** إذا كان feature صغير < 100 سطر
- **يوم واحد لكل endpoint** — لا تمدد
- **Skip الـ unit tests** الآن ← اعمل integration tests فقط
- **اتصل بشريكك فوراً** عند أي blocking issue

### ❌ لا تفعل
- لا تعمل over-engineering — YAGNI (You Ain't Gonna Need It)
- لا تضيع وقت في Pagination قبل ما تكمل الـ CRUD
- لا تشتغل على M13 أو Offline Sync الآن
- لا تنتظر شريكك لتبدأ — اشتغلوا بالتوازي دائماً

---

## 📊 جدول توزيع الوقت اليومي

```
8:00  - 8:15  → Daily Standup (15 دقيقة مع شريكك)
8:15  - 12:00 → Deep Work — Backend Development
12:00 - 13:00 → استراحة
13:00 - 16:00 → Deep Work — مكمل
16:00 - 17:00 → Integration مع شريكك + Bug Fixes
17:00 - 17:30 → Code Review + Push + Update Task Board
```

---

## 🔴 خطة الطوارئ إذا تأخرنا

### إذا وصلنا للأسبوع 4 وتأخرنا:

**نحذف من الـ Scope:**
1. ❌ Warehouse Transfers (يمكن إضافتها لاحقاً)
2. ❌ Rep Custody (بيع المندوب بدون نظام عهدة)
3. ❌ Reports (نبقي Dashboard فقط)
4. ❌ Cashbox Sessions (نبيع بدون إدارة كاشير)

**نبقي فقط:**
- ✅ Login + Auth
- ✅ Products + Inventory
- ✅ Purchases
- ✅ Sales POS
- ✅ Customers + Basic Debts
- ✅ Payments

---

## 📋 Checklist يومية (كل يوم قبل النوم)

```
□ هل commit معمول ومرفوع على GitHub؟
□ هل شريكي عنده ما يحتاجه؟
□ هل الـ Task Board محدّث؟
□ هل في أي blocking سأخبره غداً؟
□ هل الـ endpoint الذي وعدته به جاهز؟
```

---

## 🏁 تعريف "جاهز للتسليم"

الـ feature تعتبر مكتملة عندما:
- [ ] الـ API يرجع البيانات الصحيحة
- [ ] الـ Frontend يعمل بشكل صحيح
- [ ] الأخطاء تظهر بشكل واضح للمستخدم
- [ ] لا يوجد crash عند الاستخدام العادي

> **لا نشترط**: tests كاملة، optimization، edge cases نادرة

---

## 🗓️ ملخص المراحل

```
الأسبوع 1 → Setup + Auth + Products
الأسبوع 2 → Warehouses + Purchases + Stock  
الأسبوع 3 → POS Sales ← النقطة الحرجة ⭐
الأسبوع 4 → Reps + Finance + Transfers
الأسبوع 5 → Dashboard + Reports + Delivery 🎉
```

**الخط الأحمر: الأسبوع 3 (POS) يجب أن ينجح**  
لأنه القلب الذي يبني عليه كل شيء.

