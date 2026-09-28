# 📚 فهرس الخطط — نظام المبيعات Sayler

> **آخر تحديث**: أغسطس 2026  
> **المسؤول**: Backend Developer (NestJS)

---

## 📁 الملفات في هذا المجلد

| الملف | الوصف |
|-------|-------|
| [`backend_implementation_plan.md`](./backend_implementation_plan.md) | الخطة الشاملة للـ Backend (التقنيات، الموديولات، المهام، المراحل) |
| [`database_schema.md`](./database_schema.md) | هيكل قاعدة البيانات الكامل (جميع الجداول والعلاقات والـ Indexes) |
| [`sync_engine_plan.md`](./sync_engine_plan.md) | تصميم نظام المزامنة Offline/Online |

---

## ⚡ ملخص سريع

### التقنيات
- **Backend**: NestJS + TypeScript
- **Database**: PostgreSQL + Prisma ORM
- **Cache**: Redis
- **Auth**: JWT + Refresh Tokens
- **Sync**: Custom Sync Engine (Optimistic + Delta Pull)
- **Real-time**: Socket.IO
- **Jobs**: BullMQ

### الهيكلية
- **Modular Monolith** (وليس Microservices)
- 14 Module معزولة

### الموديولات
```
M01 → Auth & Users & Permissions
M02 → Company, Branches, Warehouses
M03 → Products & Categories
M04 → Suppliers & Purchases
M05 → Inventory Management
M06 → Warehouse Transfers
M07 → Stocktaking & Reconciliation
M08 → Customers & Sales POS
M09 → Representatives & Custody
M10 → Accounts & Payments
M11 → Reports & Analytics
M12 → Archive
M13 → E-commerce
M14 → System Settings
```

---

## 📋 أسئلة مفتوحة تحتاج قرار

- [ ] **ORM**: Prisma أم TypeORM؟
- [ ] **Frontend Framework** لدى الشريك؟
- [ ] **Deployment**: VPS أم Cloud؟
- [ ] **Multi-tenancy**: شركة واحدة أم متعددة؟
- [ ] **M13 E-commerce**: Web فقط أم + Mobile App؟

---

## 🗂️ الوثائق الأصلية

موجودة في المجلد الأب `التحليلي/`:
- `M01_Users_Roles_Permissions_Specification_AR.docx`
- `M02_Company_Branches_Warehouses_Specification_AR.docx`
- `M04_Suppliers_Purchasing_Specification_AR.docx`
- `M05_Inventory_Management_Specification_AR.docx`
- `M06_Warehouse_Transfers_Specification_AR.docx`
- `M07_Stocktaking_Reconciliation_Specification_AR.docx`
- `M08_Customers_Direct_Sales_POS_Specification_AR.docx`
- `M09_Representatives_Custody_Field_Sales_Specification_AR.docx`
- `M13_Ecommerce_Store_Orders_Specification_AR.docx`
