SYSTEM MODULE SPECIFICATION
M05
إدارة المخزون
Inventory Management
الغرض — مرجع موحّد للأرصدة والحجوزات والدفعات والصلاحية والتسلسلات والتسويات والحدود والتنبيهات وتقييم المخزون.

المشروع: نظام إدارة المخزون والمبيعات والتوزيع
الإصدار: 1.0  |  التاريخ: 13 آب 2026
المخرجات: Word + BPMN Draw.io — دون واجهات Figma

1. المفاهيم والنطاق
M05 هو دفتر الكميات التشغيلي للنظام. لا يسمح بتعديل رقم الرصيد مباشرة في قاعدة البيانات؛ كل تغيير ينتج من حركة مخزنية موثقة، بما فيها التسوية التي ينفذها مدير المخزن.
المفهوم
التعريف
On Hand
الكمية الموجودة فعليًا داخل المخزن.
Reserved
جزء من الفعلي مخصص لعملية لم تكتمل.
Available
الكمية القابلة للاستخدام = الفعلي − المحجوز.
Inventory Movement
سجل غير قابل للحذف يفسر كل زيادة أو نقصان.
Batch
دفعة كمية لها رقم وتواريخ إنتاج وانتهاء.
Serial
رقم فريد لقطعة واحدة وحالتها وضمانها.
Adjustment
تسوية مباشرة من مدير المخزن مع سبب إلزامي.
Weighted Average
قيمة تكلفة الوحدة الناتجة من متوسط التكلفة المرجح.

معادلة الرصيد — Available = On Hand − Reserved. الحجز لا يخفض الموجود الفعلي؛ يخفض المتاح فقط.

2. القرارات المعتمدة
المحور
القرار
التسوية
مدير المخزن مباشرة مع سبب إلزامي
اختيار الدفعة
يختارها المستخدم
الحجز
يخفض المتاح ويبقي الفعلي
انتهاء الحجز
مدة مختلفة حسب نوع العملية
الرصيد السالب
ممنوع تمامًا
المنتهي
محظور تلقائيًا وممنوع من البيع
المواقع الداخلية
غير مطلوبة؛ مستوى المخزن فقط
حدود المخزون
لكل منتج ومخزن
تنبيه الصلاحية
يحدده مدير المخزن
التقييم
المتوسط المرجح فقط

2.1 خارج النطاق
التحويلات بين المخازن لها Module مستقل.
الجرد الدوري والمفاجئ والتسويات الناتجة عنه لها Module مستقل.
المشتريات والمبيعات تنشئ الحركات، لكن M05 يحفظ أثرها.
لا توجد إدارة رفوف أو مناطق أو Bin Locations.

3. العمليات BPMN
الرمز
العملية
الناتج
BPMN-INV-01
إدخال مخزون من مصدر معتمد
زيادة On Hand وتحديث التكلفة
BPMN-INV-02
حجز كمية
زيادة Reserved وخفض Available
BPMN-INV-03
تنفيذ الحجز وإخراج الكمية
خفض On Hand وتحرير Reserved
BPMN-INV-04
إلغاء أو انتهاء الحجز
تحرير Reserved
BPMN-INV-05
اختيار وإخراج دفعة
حركة من دفعة صالحة
BPMN-INV-06
إخراج منتج تسلسلي
تغيير حالة Serial وخفض الرصيد
BPMN-INV-07
تسوية مباشرة
حركة فرق بسبب موثق
BPMN-INV-08
حظر دفعة منتهية
BLOCKED_EXPIRED ومنع البيع
BPMN-INV-09
تشغيل تنبيه الحد الأدنى
إشعار إعادة الطلب
BPMN-INV-10
تشغيل تنبيه الصلاحية
إشعار حسب إعداد المخزن
BPMN-INV-11
إعادة احتساب المتوسط المرجح
تكلفة جديدة بعد الإدخال
BPMN-INV-12
استعلام بطاقة حركة المنتج
رصيد تراكمي قابل للتدقيق

3.1 قواعد الحركة الذرية
تقفل سجلات الرصيد المستهدفة داخل Transaction قبل الفحص والتغيير.
يعاد فحص Available داخل المعاملة لمنع Race Condition.
ينشأ movement ثم يحدث balance وbatch/serial والتكلفة في المعاملة نفسها.
يحمل كل أمر مفتاح Idempotency لمنع تكرار الحركة.

4. الواجهات Screens
ID
الواجهة
Route
SCR-INV-01
لوحة المخزون
/inventory/dashboard
SCR-INV-02
أرصدة المخازن
/inventory/balances
SCR-INV-03
تفاصيل رصيد المنتج
/inventory/balances/:id
SCR-INV-04
بطاقة حركة المنتج
/inventory/ledger
SCR-INV-05
الدفعات والصلاحيات
/inventory/batches
SCR-INV-06
تفاصيل الدفعة
/inventory/batches/:id
SCR-INV-07
الأرقام التسلسلية
/inventory/serials
SCR-INV-08
تفاصيل الرقم التسلسلي
/inventory/serials/:id
SCR-INV-09
الحجوزات
/inventory/reservations
SCR-INV-10
التسوية المباشرة
/inventory/adjustments/new
SCR-INV-11
سجل التسويات
/inventory/adjustments
SCR-INV-12
حدود المخزون
/inventory/stock-levels
SCR-INV-13
تنبيهات انخفاض المخزون
/inventory/alerts/low-stock
SCR-INV-14
تنبيهات الصلاحية
/inventory/alerts/expiry
SCR-INV-15
تقييم المخزون
/inventory/valuation
SCR-INV-16
إعداد مدد الحجز
/settings/reservation-policies

4.1 مواصفات شاشة الأرصدة
فلترة بالمخزن والمنتج والتصنيف والحالة.
عرض On Hand وReserved وAvailable ومتوسط التكلفة والقيمة.
توسيع السطر لعرض الدفعات أو التسلسلات.
منع إظهار زر التسوية إلا لمدير المخزن ضمن نطاقه.
تصدير تقرير الرصيد بتاريخ حالي، بينما التاريخ السابق يعتمد على Ledger.

5. الأدوار والصلاحيات
الدور
المسؤولية
WAREHOUSE_MANAGER
إدارة رصيد مخزنه والتسويات والحدود والتنبيهات.
WAREHOUSE_KEEPER
قراءة الرصيد وتنفيذ الحركات المصرح بها.
SALES_USER
إنشاء الحجز وقراءته ضمن عمليات البيع.
PURCHASES_USER
قراءة أثر الاستلام المعتمد.
INVENTORY_CONTROLLER
رقابة الحركات والتكلفة والتقارير.
ACCOUNTANT
قراءة تقييم المخزون والتكلفة.
AUDITOR
قراءة السجل الكامل دون تعديل.

Permission Key
الوصف
inventory.balances.view
عرض الأرصدة
inventory.movements.view
عرض بطاقة الحركة
inventory.reservations.create/release
إنشاء/تحرير الحجز
inventory.reservations.fulfill
تنفيذ الحجز
inventory.batches.view/select
عرض/اختيار الدفعات
inventory.serials.view/select
عرض/اختيار التسلسلات
inventory.adjustments.create
تسوية مدير المخزن
inventory.stock_levels.manage
إدارة الحدود
inventory.expiry_settings.manage
إعداد تنبيهات الصلاحية
inventory.valuation.view
عرض التقييم
inventory.valuation.export
تصدير التقييم
inventory.reservation_policies.manage
إدارة مدد الحجز

6. الحالات Statuses
الكيان
الحالات
الحجز
ACTIVE, FULFILLED, RELEASED, EXPIRED, CANCELLED
الدفعة
ACTIVE, BLOCKED_EXPIRED, BLOCKED_MANUAL, DEPLETED, RETURNED, DISPOSED
الرقم التسلسلي
IN_STOCK, RESERVED, SOLD, RETURNED, DEFECTIVE, UNDER_WARRANTY, DISPOSED
الحركة
POSTED, REVERSED
التنبيه
OPEN, ACKNOWLEDGED, RESOLVED, DISMISSED

6.1 أنواع الحركة
النوع
الأثر
PURCHASE_RECEIPT
زيادة الفعلي والتكلفة
SALE_ISSUE
خفض الفعلي
RESERVATION_FULFILLMENT
خفض الفعلي وتحرير المحجوز
PURCHASE_RETURN
خفض الفعلي
SALE_RETURN
زيادة الفعلي
TRANSFER_IN / OUT
زيادة/خفض ضمن التحويل
ADJUSTMENT_IN / OUT
فرق تسوية مباشر
DISPOSAL
خفض بسبب إتلاف
REVERSAL
عكس حركة سابقة

7. قواعد العمل Business Rules
الرمز
القاعدة
BR-INV-001
Available = On Hand − Reserved دائمًا.
BR-INV-002
لا يسمح بأن تقل On Hand أو Reserved أو Available عن صفر.
BR-INV-003
الحجز يزيد Reserved ولا يغير On Hand.
BR-INV-004
مدة الحجز تحدد من policy حسب source_type.
BR-INV-005
الحجز المنتهي يحرر آليًا بصورة idempotent.
BR-INV-006
عند التنفيذ تخفض On Hand وتخفض Reserved بالقيمة نفسها.
BR-INV-007
المستخدم يختار الدفعة من الدفعات الصالحة فقط.
BR-INV-008
تعرض الدفعات افتراضيًا مرتبة بالأقرب انتهاءً.
BR-INV-009
الدفعة المنتهية تنتقل تلقائيًا إلى BLOCKED_EXPIRED.
BR-INV-010
المنتهي يبقى ضمن الفعلي لكنه يستبعد من المتاح للبيع.
BR-INV-011
الرقم التسلسلي فريد ولا تتحرك القطعة دون تغيير حالته.
BR-INV-012
مدير المخزن فقط ينفذ تسوية مباشرة ضمن مخزنه.
BR-INV-013
سبب التسوية إلزامي ويسجل قبل/بعد والفرق والتكلفة.
BR-INV-014
التسوية لا تسمح برصيد سالب.
BR-INV-015
الحدود تعرف لكل product_variant + warehouse.
BR-INV-016
تنبيه الانخفاض يعتمد على Available.
BR-INV-017
مدة تنبيه الصلاحية يحددها مدير المخزن.
BR-INV-018
تقييم المخزون يستخدم المتوسط المرجح فقط.
BR-INV-019
حركات الإخراج لا تغير المتوسط المرجح.
BR-INV-020
الحركة المرحلة لا تحذف أو تعدل؛ تعكس بحركة مقابلة.

8. API Endpoints
Method
Endpoint
الغرض
GET
/api/v1/inventory/balances
الأرصدة والفلاتر
GET
/api/v1/inventory/balances/:id
تفاصيل الرصيد
GET
/api/v1/inventory/ledger
بطاقة الحركة
GET
/api/v1/inventory/batches
الدفعات
GET
/api/v1/inventory/batches/:id
تفاصيل الدفعة
POST
/api/v1/inventory/batches/:id/block
حظر يدوي
GET
/api/v1/inventory/serials
التسلسلات
GET
/api/v1/inventory/serials/:id
تفاصيل التسلسل
GET/POST
/api/v1/inventory/reservations
قائمة/إنشاء حجز
POST
/api/v1/inventory/reservations/:id/fulfill
تنفيذ الحجز
POST
/api/v1/inventory/reservations/:id/release
تحرير الحجز
POST
/api/v1/inventory/adjustments
تنفيذ تسوية
GET
/api/v1/inventory/adjustments
سجل التسويات
GET/PUT
/api/v1/inventory/stock-levels
عرض/تحديث الحدود
GET
/api/v1/inventory/alerts/low-stock
تنبيهات الانخفاض
GET
/api/v1/inventory/alerts/expiry
تنبيهات الصلاحية
GET
/api/v1/inventory/valuation
تقييم المتوسط المرجح
GET/PUT
/api/v1/inventory/reservation-policies
مدد الحجز
POST
/api/v1/jobs/inventory/expire-reservations
مهمة انتهاء الحجوزات
POST
/api/v1/jobs/inventory/block-expired-batches
مهمة حظر المنتهي

9. جداول قاعدة البيانات
الجدول
المسؤولية
inventory_balances
On Hand وReserved والمتوسط لكل Variant ومخزن.
inventory_movements
دفتر الحركات غير القابل للحذف.
inventory_movement_lines
تفاصيل الدفعات والتسلسلات والتكلفة.
inventory_batches
الدفعات والصلاحية والحالة.
inventory_serials
التسلسلات والضمان والحالة.
inventory_reservations
رأس الحجز ومصدره وانتهاؤه.
inventory_reservation_lines
الكميات والدفعات/التسلسلات المحجوزة.
inventory_adjustments
سبب ومنفذ التسوية.
inventory_adjustment_lines
قبل وبعد والفرق.
warehouse_product_levels
Min/Reorder/Max وتنبيه الصلاحية.
reservation_policies
مدة الحجز حسب المصدر.
inventory_alerts
التنبيهات وحالتها.
inventory_cost_layers
تفاصيل احتساب المتوسط المرجح والتدقيق.
activity_logs
سجل النشاط.

9.1 القيود والفهارس
Unique على (warehouse_id, product_variant_id) في inventory_balances.
Check constraints تمنع القيم السالبة وتضمن reserved <= on_hand.
Unique على serial_number على مستوى الشركة.
Index على batch expiry_date/status وعلى reservation expires_at/status.
قفل Row-level أثناء الحجز والإخراج والتسوية.
Idempotency unique لكل حركة مصدر.

10. المتوسط المرجح
المعادلة — New Average = ((Old Qty × Old Average) + (Received Qty × Received Unit Cost)) ÷ New Qty

تعتمد Received Unit Cost على سعر الشراء بعد توزيع المصاريف الداخلة في التكلفة.
المرتجع إلى المورد يخفض الكمية بالقيمة المسجلة وفق السياسة المحاسبية، ولا يعاد حسابه كسعر شراء جديد.
تسوية الزيادة تحتاج قيمة تكلفة؛ الافتراضي المتوسط الحالي، وإن كان صفرًا يطلب النظام تكلفة موثقة.
تسوية النقص لا تغير متوسط الوحدة؛ تخفض قيمة المخزون بالمتوسط الحالي.
11. معايير القبول
الرمز
معيار القبول
AC-INV-01
يتطابق Available دائمًا مع On Hand − Reserved.
AC-INV-02
يمنع النظام أي حركة تؤدي إلى رصيد سالب.
AC-INV-03
ينتهي الحجز وفق سياسة مصدره ويحرر المتاح.
AC-INV-04
لا يسمح باختيار دفعة منتهية للبيع.
AC-INV-05
تنتقل الدفعات المنتهية تلقائيًا إلى الحظر.
AC-INV-06
تحتاج التسوية سببًا وتقتصر على مدير المخزن.
AC-INV-07
يصدر تنبيه الانخفاض حسب Available وحد المنتج/المخزن.
AC-INV-08
يصدر تنبيه الصلاحية وفق مدة مدير المخزن.
AC-INV-09
يحسب المتوسط المرجح بعد كل إدخال معتمد.
AC-INV-10
تفسر بطاقة الحركة الرصيد التراكمي دون فجوات.

12. حزمة التسليم
التكامل — تستخدم الوثيقة ومخططات BPMN الرموز نفسها لربط NestJS وPostgreSQL والمهام المجدولة والاختبارات.

M05_Inventory_Management_Specification_AR.docx
M05_Inventory_Management_BPMN.drawio — اثنا عشر مخططًا