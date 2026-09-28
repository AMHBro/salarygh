SYSTEM MODULE SPECIFICATION
M09
المندوبون والعُهد والمبيعات الميدانية
Sales Representatives & Custody
الغرض — مرجع موحد لطلبات المندوبين والعهد والذمم وقوائم الأسعار والمبيعات والتحصيلات والعمولات والتسويات.

المشروع: نظام إدارة المخزون والمبيعات والتوزيع
الإصدار: 1.0  |  التاريخ: 13 آب 2026
المخرجات: Word + BPMN Draw.io — دون واجهات Figma

1. المفاهيم والنطاق
M09 يدير البضاعة التي تسجل عهدة وذمة على المندوب، ثم يتابع بيعها للعملاء أو المكاتب وتسديد المندوب للشركة واستحقاق عمولته.
المفهوم
التعريف
المندوب
مستخدم ميداني له قائمة أسعار وعهد وذمة.
طلب العهدة
طلب بضاعة ينشئه المندوب أو الإدارة.
العهدة
مخزون فعلي تحت مسؤولية المندوب.
ذمة المندوب
قيمة مالية تسجل عند اعتماد الطلب وفق قرار العمل.
قائمة الأسعار
أسعار خاصة بالمندوب لكل منتج أو Variant.
البيع الميداني
فاتورة يوثقها المندوب لعميل أو مكتب.
التسديد
دفعة من المندوب للشركة نقدًا أو تحويلًا.
العمولة
مبلغ/نسبة حسب المنتج تستحق بعد التسديد.

قرار خاص — تسجل الذمة مباشرة عند اعتماد الطلب. إذا ألغي قبل التسليم، تعكس الذمة ويحرر الحجز بالكامل.

2. القرارات المعتمدة
المحور
القرار
إنشاء العهدة
طلب مندوب أو تسليم إداري حسب الصلاحية
توقيت الذمة
عند اعتماد طلب المندوب
قيمة الذمة
سعر المندوب الخاص
المدة
مدة قصوى لكل عهدة
عند انتهاء المدة
دفع كامل قيمة العهدة
أنواع العملاء
مسجلون، نقديون، مكاتب مرتبطة
البيع الآجل
الدين على المندوب وحده
قائمة الأسعار
خاصة بكل مندوب
العمولة
تختلف حسب المنتج وتستحق بعد التسديد
التسديد
نقدي أو تحويل، كامل أو جزئي
إرجاع البضاعة
بموافقة الإدارة قبل انتهاء العهدة
النقل بين المندوبين
بموافقة الإدارة
التتبع
اختيار التفاصيل مع الالتزام بسياسة المنتج

2.1 الاستحقاق النسبي للعمولة
عند التسديد الجزئي تخصص الدفعة على مبيعات/أسطر محددة.
تستحق العمولة بما يقابل الجزء المسدد فقط.
لا تستحق عمولة على بضاعة عهدة لم تبع أو لم تسدد.
عكس أو نقل عهدة غير مسددة ينقل أثر الذمة والعمولة بصورة متسقة.

3. العمليات BPMN
الرمز
العملية
الناتج
BPMN-REP-01
تعريف مندوب وقائمة أسعاره
مندوب نشط
BPMN-REP-02
طلب عهدة من المندوب
طلب DRAFT
BPMN-REP-03
إنشاء عهدة من الإدارة
طلب إداري
BPMN-REP-04
اعتماد الطلب وتسجيل الذمة
حجز وذمة
BPMN-REP-05
تجهيز وتسليم العهدة
مخزون لدى المندوب
BPMN-REP-06
تسجيل بيع ميداني
فاتورة وخصم من العهدة
BPMN-REP-07
تسجيل تحصيل وتسديد
خفض ذمة
BPMN-REP-08
احتساب عمولة مسددة
عمولة مستحقة
BPMN-REP-09
إرجاع عهدة قبل الانتهاء
إرجاع وذمة مخفضة
BPMN-REP-10
نقل عهدة بين مندوبين
نقل مخزون وذمة
BPMN-REP-11
معالجة انتهاء العهدة
مطالبة بكامل القيمة
BPMN-REP-12
إلغاء طلب قبل التسليم
عكس الذمة والحجز

3.1 المسار الطبيعي
إنشاء الطلب وتحديد المنتجات والأسعار والمدة.
اعتماد الإدارة: حجز المخزون وتسجيل الذمة فورًا.
تجهيز الدفعات والتسلسلات وتسليمها للمندوب.
تسجيل المبيعات للعملاء أو المكاتب وخصمها من مخزون العهدة.
تسديد المندوب للشركة كليًا أو جزئيًا.
احتساب العمولة للأسطر المسددة فقط.
عند انتهاء المدة يستحق كامل المتبقي على المندوب.

4. الواجهات Screens
ID
الواجهة
Route
SCR-REP-01
لوحة المندوبين
/representatives/dashboard
SCR-REP-02
قائمة المندوبين
/representatives
SCR-REP-03
تفاصيل المندوب
/representatives/:id
SCR-REP-04
قائمة أسعار المندوب
/representatives/:id/prices
SCR-REP-05
طلبات العهدة
/custody-requests
SCR-REP-06
إنشاء طلب عهدة
/custody-requests/new
SCR-REP-07
اعتماد الطلبات
/custody-requests/approvals
SCR-REP-08
تجهيز وتسليم العهدة
/custodies/:id/dispatch
SCR-REP-09
عهد المندوب
/representatives/:id/custodies
SCR-REP-10
تسجيل بيع ميداني
/field-sales/new
SCR-REP-11
المبيعات الميدانية
/field-sales
SCR-REP-12
تسديدات المندوب
/representative-payments
SCR-REP-13
عمولات المندوب
/representative-commissions
SCR-REP-14
إرجاع العهدة
/custody-returns
SCR-REP-15
نقل العهدة
/custody-transfers
SCR-REP-16
العهد المنتهية
/custodies/overdue
SCR-REP-17
كشف حساب المندوب
/representatives/:id/statement

4.1 كشف المندوب
رصيد الذمة الافتتاحي والحركات والتسديدات.
العهد الحالية وقيمتها وتواريخ انتهائها.
المبيعات النقدية والآجلة والعملاء والمكاتب.
العمولة المحتسبة والمعلقة والمستحقة والمدفوعة.
ربط كل حركة بالمستند والمستخدم والتاريخ.

5. الأدوار والصلاحيات
الدور
المسؤولية
REPRESENTATIVE
طلب عهدة وتسجيل البيع والتحصيل ومتابعة حسابه.
SALES_MANAGER
إدارة المندوبين والأسعار والعهد والمبيعات.
COMPANY_ADMIN
اعتماد العهد والإرجاع والنقل.
WAREHOUSE_MANAGER
تجهيز وتسليم واستلام البضاعة.
ACCOUNTANT
الذمم والتسديدات والعمولات.
AUDITOR
قراءة السجل والكميات والقيم.

Permission Key
الوصف
representatives.view/create/update
إدارة المندوبين
representatives.manage_prices
قوائم الأسعار
custody_requests.create
إنشاء طلب
custody_requests.create_direct
إنشاء إداري مباشر
custody_requests.approve/reject
اعتماد/رفض
custodies.prepare/dispatch
تجهيز وتسليم
field_sales.create/view
المبيعات الميدانية
representative_payments.create/approve
التسديدات
commissions.view/calculate/pay
العمولات
custody_returns.create/approve
الإرجاع
custody_transfers.create/approve
النقل
custodies.overdue.view
العهد المنتهية
representatives.statement.view
كشف الحساب

6. الحالات Statuses
الكيان
الحالات
طلب العهدة
DRAFT, PENDING_APPROVAL, APPROVED, PREPARING, DISPATCHED, REJECTED, CANCELLED
العهدة
ACTIVE, PARTIALLY_SOLD, EXPIRED, RETURN_PENDING, TRANSFER_PENDING, SETTLED, CLOSED
البيع
DRAFT, POSTED, CANCELLED_BEFORE_POSTING
التسديد
DRAFT, POSTED, VOIDED
العمولة
PENDING_PAYMENT, PARTIALLY_EARNED, EARNED, PAID, REVERSED
الإرجاع/النقل
DRAFT, PENDING_APPROVAL, APPROVED, REJECTED, COMPLETED

6.1 حالات الذمة
الحركة
الأثر
اعتماد عهدة
زيادة الذمة بسعر المندوب
إلغاء قبل التسليم
عكس كامل الذمة
تسديد
خفض الذمة
إرجاع معتمد
خفض الذمة بقيمة المرجع
نقل لمندوب آخر
خفض الأول وزيادة الثاني
انتهاء المدة
استحقاق كامل الرصيد المتبقي

7. قواعد العمل Business Rules
الرمز
القاعدة
BR-REP-001
لكل مندوب قائمة أسعار فعالة بتاريخ صلاحية.
BR-REP-002
قيمة العهدة تعتمد سعر المندوب الخاص وقت الاعتماد.
BR-REP-003
اعتماد الطلب يسجل الذمة ويحجز المخزون.
BR-REP-004
إلغاء الطلب قبل التسليم يعكس الذمة والحجز ذريًا.
BR-REP-005
التسليم يحرر الحجز ويخفض المخزن ويزيد مخزون المندوب.
BR-REP-006
التتبع الإلزامي يتبع سياسة المنتج ولا يمكن تجاوزه.
BR-REP-007
يختار المندوب/المخول Batch وSerial من المتاح.
BR-REP-008
كل عهدة لها تاريخ انتهاء إلزامي.
BR-REP-009
بعد انتهاء المدة يستحق كامل رصيد العهدة.
BR-REP-010
البيع الآجل ينشئ دينًا على المندوب لا العميل.
BR-REP-011
لا يتجاوز البيع كمية العهدة المتاحة.
BR-REP-012
أسعار البيع مأخوذة من قائمة المندوب الفعالة.
BR-REP-013
التسديد يقبل النقد والتحويل والدفعات الجزئية.
BR-REP-014
العمولة تختلف حسب المنتج.
BR-REP-015
العمولة تستحق فقط بعد تسديد المندوب للشركة.
BR-REP-016
التسديد الجزئي يولد عمولة نسبية على المخصص.
BR-REP-017
الإرجاع قبل انتهاء العهدة يحتاج موافقة الإدارة.
BR-REP-018
النقل بين مندوبين يحتاج موافقة الإدارة وتأكيد الاستلام.
BR-REP-019
النقل يحول المخزون والذمة بالقيمة نفسها.
BR-REP-020
كل حركة تسجل في Audit Log وكشف المندوب.

8. API Endpoints
Method
Endpoint
الغرض
GET/POST
/api/v1/representatives
قائمة/إنشاء
GET/PATCH
/api/v1/representatives/:id
تفاصيل/تعديل
GET/PUT
/api/v1/representatives/:id/prices
قائمة الأسعار
GET/POST
/api/v1/custody-requests
قائمة/إنشاء طلب
POST
/api/v1/custody-requests/:id/approve
اعتماد وذمة وحجز
POST
/api/v1/custody-requests/:id/reject
رفض
POST
/api/v1/custody-requests/:id/cancel
إلغاء وعكس
POST
/api/v1/custodies/:id/prepare
تحديد Batch/Serial
POST
/api/v1/custodies/:id/dispatch
تسليم للمندوب
GET/POST
/api/v1/field-sales
قائمة/تسجيل بيع
GET/POST
/api/v1/representative-payments
قائمة/تسديد
GET
/api/v1/representatives/:id/commissions
العمولات
POST
/api/v1/commissions/calculate
احتساب المستحق
GET/POST
/api/v1/custody-returns
قائمة/إنشاء إرجاع
POST
/api/v1/custody-returns/:id/approve
اعتماد الإرجاع
GET/POST
/api/v1/custody-transfers
قائمة/إنشاء نقل
POST
/api/v1/custody-transfers/:id/approve
اعتماد النقل
POST
/api/v1/custody-transfers/:id/receive
تأكيد المندوب الثاني
GET
/api/v1/custodies/overdue
العهد المنتهية
GET
/api/v1/representatives/:id/statement
كشف الحساب

9. جداول قاعدة البيانات
الجدول
المسؤولية
representatives
بيانات المندوب والحالة.
representative_price_lists / items
قائمة الأسعار الخاصة.
representative_product_commissions
عمولة كل منتج.
custody_requests / items
طلبات العهدة.
custody_approvals
قرارات الإدارة.
representative_custodies / items
العهد الفعلية ومدتها.
custody_tracking_allocations
Batch/Serial.
representative_ledger
دفتر الذمة.
field_sales / items
المبيعات الميدانية.
representative_payments / allocations
التسديد وتخصيصه.
commission_accruals
العمولات المكتسبة.
custody_returns / items
الإرجاعات.
custody_transfers / items
النقل بين المندوبين.
inventory_movements
حركات المخزن والعهدة.
activity_logs
سجل التدقيق.

9.1 القيود والفهارس
Unique لقائمة أسعار فعالة لكل مندوب وفترة.
Check أن custody_due_date بعد تاريخ الاعتماد.
منع كمية عهدة سالبة أو بيع يتجاوز المتاح.
Unique serial allocation على العهد النشطة.
Idempotency على الاعتماد والتسليم والتسديد والنقل.
Transaction واحدة لتحويل الذمة والمخزون بين مندوبين.

10. الأثر المحاسبي والمخزني
الحدث
الأثر
اعتماد العهدة
زيادة ذمة المندوب وحجز المخزون.
التسليم
خفض مخزن الشركة وزيادة مخزون عهدة المندوب.
بيع ميداني
خفض مخزون العهدة؛ لا تنقل الذمة للعميل.
تسديد المندوب
خفض الذمة وزيادة الصندوق/البنك.
استحقاق العمولة
إثبات مصروف عمولة والتزام للمندوب حسب الجزء المسدد.
إرجاع
زيادة مخزن الشركة وخفض العهدة والذمة.
نقل عهدة
خفض عهدة وذمة الأول وزيادة الثاني.

11. معايير القبول
الرمز
معيار القبول
AC-REP-01
يسجل الاعتماد الذمة بسعر المندوب ويحجز الكمية.
AC-REP-02
يعكس الإلغاء قبل التسليم الذمة والحجز كاملًا.
AC-REP-03
يفرض التتبع المطلوب عند تسليم العهدة.
AC-REP-04
لا يسمح ببيع أكثر من مخزون العهدة.
AC-REP-05
يسجل دين البيع الآجل على المندوب وحده.
AC-REP-06
يدعم التسديد الجزئي والنقد والتحويل.
AC-REP-07
لا تستحق عمولة قبل تسديد المندوب.
AC-REP-08
ينقل الإرجاع المعتمد البضاعة ويخفض الذمة.
AC-REP-09
ينقل التحويل المعتمد المخزون والذمة بين المندوبين ذريًا.
AC-REP-10
يظهر كامل المسار في كشف المندوب.

12. حزمة التسليم
التكامل — تستخدم الوثيقة وBPMN الرموز نفسها لتنفيذ NestJS والمخزون والذمم والتسديد والعمولات.

M09_Representatives_Custody_Field_Sales_Specification_AR.docx
M09_Representatives_Custody_Field_Sales_BPMN.drawio — اثنا عشر مخططًا