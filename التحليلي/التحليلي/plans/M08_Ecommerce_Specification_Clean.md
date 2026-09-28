SYSTEM MODULE SPECIFICATION
M13
المتجر الإلكتروني والطلبات
E-commerce Store & Online Orders
الغرض — مرجع موحد للمتجر والعملاء والسلة والتوفر وإسناد المخزن والحجز والتجهيز والتوصيل والدفع عند الاستلام والإرجاع.

المشروع: نظام إدارة المخزون والمبيعات والتوزيع
الإصدار: 1.0  |  التاريخ: 13 آب 2026
المخرجات: Word + BPMN Draw.io — دون واجهات Figma

1. المفاهيم والنطاق
M13 يعرض منتجات M03 وأسعار المفرد والمخزون المتاح، ويحوّل سلة العميل إلى طلب محجوز في أقرب مخزن قادر على تنفيذها كاملة.
المفهوم
التعريف
عميل مسجل
حساب محفوظ بعناوين وسجل طلبات.
ضيف
طلب دون حساب دائم.
OTP
تحقق رقم الهاتف للعميل أو الضيف.
السلة
اختيارات مؤقتة لا تحجز المخزون.
المخزن المرشح
أقرب مخزن نشط داخل نطاق التوصيل.
الطلب
Snapshot للأسعار والعنوان والكميات والأجور.
COD
تحصيل نقدي عند التسليم فقط.
الإرجاع
طلب بعد التسليم يحتاج موافقة الإدارة.

قاعدة الإسناد — يجب أن ينفذ مخزن واحد السلة كاملة. لا يقسم الطلب بين مخازن متعددة.

2. القرارات المعتمدة
المحور
القرار
الدخول والطلب
حساب، ضيف، أو هاتف وOTP
الدفع
عند الاستلام فقط
اختيار المخزن
الأقرب لموقع العميل والقادر على تنفيذ السلة كاملة
عرض المخزون
العدد المتاح بالضبط
الحجز
فور تأكيد العميل
قبول الطلب
المخزن يقبل قبل التجهيز
التوصيل
داخلي، شركة خارجية، أو استلام من الفرع
السعر
سعر المفرد
الإلغاء
قبل بدء التجهيز
الإرجاع
بعد التسليم وبموافقة الإدارة
رد المبلغ
نقدًا من الصندوق
رسوم التوصيل
حسب المنطقة وقيمة الطلب
رفض COD
إرجاع للمخزن وتسجيل الرفض
العروض والكوبونات
غير مطلوبة حاليًا

2.1 حساب التوفر
يعتمد العدد المعروض على موقع العميل والمخازن التي تخدم منطقته.
يعرض مجموعًا قابلًا للتنفيذ من مخزن واحد، وليس جمع كميات مخازن متعددة.
يعاد التحقق عند تأكيد الطلب داخل Transaction.
إذا لم يكف مخزن واحد، يمنع التأكيد ويطلب تعديل السلة.

3. العمليات BPMN
الرمز
العملية
الناتج
BPMN-ECO-01
تسجيل/OTP أو متابعة كضيف
هوية طلب صالحة
BPMN-ECO-02
تصفح وبحث المنتجات
قائمة متاحة
BPMN-ECO-03
إدارة السلة والتحقق من الكمية
سلة صالحة
BPMN-ECO-04
اختيار أقرب مخزن
مخزن مرشح
BPMN-ECO-05
تأكيد الطلب وحجز المخزون
طلب PENDING_STORE_ACCEPTANCE
BPMN-ECO-06
قبول أو رفض المخزن
طلب ACCEPTED أو إعادة إسناد
BPMN-ECO-07
تجهيز الطلب
طلب READY
BPMN-ECO-08
تسليم داخلي/خارجي/استلام فرع
طلب OUT_FOR_DELIVERY/PICKUP
BPMN-ECO-09
تحصيل COD والتسليم
طلب DELIVERED
BPMN-ECO-10
إلغاء قبل التجهيز
إلغاء وتحرير الحجز
BPMN-ECO-11
رفض العميل للاستلام
إرجاع وتسجيل رفض
BPMN-ECO-12
طلب إرجاع واعتماده
إرجاع ورد نقدي

3.1 دورة التنفيذ
العميل يحدد الموقع قبل عرض التوفر النهائي.
يؤكد السلة؛ فيختار النظام المخزن ويحجز الكميات.
المخزن يقبل ضمن المهلة أو يرفض؛ عند الرفض يحرر الحجز ويجرب المرشح التالي.
عند قبول المخزن يبدأ التجهيز ولا يعود الإلغاء متاحًا للعميل.
عند التسليم يحصل COD وتترحل حركة البيع والمخزون والصندوق.

4. الواجهات Screens
ID
الواجهة
Route
SCR-ECO-01
الصفحة الرئيسية
/
SCR-ECO-02
التصنيفات والبحث
/products
SCR-ECO-03
تفاصيل المنتج
/products/:slug
SCR-ECO-04
السلة
/cart
SCR-ECO-05
تسجيل/OTP
/auth
SCR-ECO-06
العناوين والموقع
/checkout/address
SCR-ECO-07
مراجعة الطلب
/checkout/review
SCR-ECO-08
تأكيد الطلب
/orders/:id/success
SCR-ECO-09
طلباتي
/account/orders
SCR-ECO-10
تتبع الطلب
/orders/:id/track
SCR-ECO-11
إلغاء الطلب
Dialog قبل التجهيز
SCR-ECO-12
طلب إرجاع
/orders/:id/return
SCR-ECO-13
صندوق طلبات المخزن
/admin/ecommerce/orders
SCR-ECO-14
قبول/رفض الطلب
/admin/ecommerce/orders/:id
SCR-ECO-15
تجهيز الطلب
/admin/ecommerce/orders/:id/prepare
SCR-ECO-16
إسناد التوصيل
/admin/ecommerce/orders/:id/delivery
SCR-ECO-17
إدارة مناطق التوصيل
/admin/ecommerce/delivery-zones
SCR-ECO-18
إدارة الإرجاعات
/admin/ecommerce/returns

4.1 تجربة العميل
إظهار العدد المتاح بالضبط بعد تحديد الموقع.
تحديث السلة عند تغير التوفر مع رسالة واضحة.
عرض رسوم التوصيل قبل التأكيد.
إظهار طريقة التنفيذ: توصيل داخلي/خارجي أو استلام فرع.
Timeline لحالات الطلب ورسائل سبب الرفض أو الإلغاء.

5. الأدوار والصلاحيات
الدور
المسؤولية
ECOMMERCE_ADMIN
إدارة المتجر والمناطق والطلبات.
STORE_CUSTOMER
السلة والطلبات والإلغاء والإرجاع.
WAREHOUSE_ORDER_AGENT
قبول وتجهيز الطلبات.
DELIVERY_COORDINATOR
إسناد التوصيل ومتابعته.
DELIVERY_DRIVER
تحديث الاستلام والتسليم والتحصيل.
CASHIER
استلام COD ورد المبلغ نقدًا.
COMPANY_ADMIN
اعتماد الإرجاع.
AUDITOR
قراءة المسار والسجلات.

Permission Key
الوصف
ecommerce.catalog.view/manage
الكتالوج
ecommerce.orders.view
عرض الطلبات
ecommerce.orders.accept/reject
قبول/رفض المخزن
ecommerce.orders.prepare
التجهيز
ecommerce.orders.assign_delivery
إسناد التوصيل
ecommerce.orders.mark_delivered
التسليم والتحصيل
ecommerce.orders.cancel
إلغاء قبل التجهيز
ecommerce.returns.create
طلب إرجاع
ecommerce.returns.approve/reject
اعتماد الإرجاع
ecommerce.refunds.cash
رد نقدي
delivery_zones.manage
مناطق ورسوم التوصيل
ecommerce.order_history.view
سجل الحالة

6. الحالات Statuses
الكيان
الحالات
الطلب
PENDING_STORE_ACCEPTANCE, ACCEPTED, PREPARING, READY, OUT_FOR_DELIVERY, READY_FOR_PICKUP, DELIVERED, CANCELLED, REJECTED, DELIVERY_REFUSED, RETURNED
الحجز
ACTIVE, FULFILLED, RELEASED, EXPIRED
التوصيل
UNASSIGNED, ASSIGNED, PICKED_UP, DELIVERED, FAILED, RETURNED_TO_WAREHOUSE
الإرجاع
REQUESTED, PENDING_APPROVAL, APPROVED, REJECTED, RECEIVED, REFUNDED
COD
PENDING, COLLECTED, HANDED_OVER, VOIDED

6.1 انتقالات مهمة
من
إلى
الشرط
PENDING_STORE_ACCEPTANCE
ACCEPTED
قبول المخزن
PENDING_STORE_ACCEPTANCE
REJECTED
لا يوجد مخزن بديل
ACCEPTED
PREPARING
بدء التجهيز؛ يغلق الإلغاء
READY
OUT_FOR_DELIVERY
تسليم للناقل
OUT_FOR_DELIVERY
DELIVERED
تحصيل COD
OUT_FOR_DELIVERY
DELIVERY_REFUSED
رفض العميل
DELIVERED
RETURNED
إرجاع معتمد ومستلم

7. قواعد العمل Business Rules
الرمز
القاعدة
BR-ECO-001
يمكن الطلب بحساب أو ضيف أو هاتف OTP.
BR-ECO-002
الدفع COD فقط.
BR-ECO-003
السعر المستخدم هو RETAIL ويحفظ Snapshot.
BR-ECO-004
لا كوبونات أو عروض في الإصدار الحالي.
BR-ECO-005
يعرض العدد المتاح بالضبط بعد تحديد الموقع.
BR-ECO-006
لا تجمع كميات مخازن لتكوين طلب واحد.
BR-ECO-007
يجب أن يستطيع مخزن واحد تنفيذ السلة كاملة.
BR-ECO-008
الاختيار يرتب المخازن بالقرب ثم القدرة على التنفيذ.
BR-ECO-009
تأكيد الطلب ينشئ الحجز فورًا.
BR-ECO-010
المخزن يجب أن يقبل قبل التجهيز.
BR-ECO-011
رفض/انتهاء مهلة المخزن يحرر الحجز قبل تجربة بديل.
BR-ECO-012
العميل يلغي قبل PREPARING فقط.
BR-ECO-013
رسوم التوصيل حسب المنطقة وقيمة الطلب.
BR-ECO-014
يمكن تعريف حد توصيل مجاني لكل منطقة.
BR-ECO-015
تحصيل COD والتسليم وحركة المخزون ذرية.
BR-ECO-016
رفض الاستلام يعيد الطلب للمخزن ولا يعيد الكمية قبل تأكيد الوصول.
BR-ECO-017
يسجل رفض COD في سجل العميل دون حظر تلقائي.
BR-ECO-018
الإرجاع بعد التسليم يحتاج موافقة الإدارة.
BR-ECO-019
رد المبلغ نقدًا من صندوق مخول بعد استلام المرتجع.
BR-ECO-020
كل انتقال حالة وحجز وتحصيل وإرجاع يسجل.

8. API Endpoints
Method
Endpoint
الغرض
POST
/api/v1/store/auth/otp/request
طلب OTP
POST
/api/v1/store/auth/otp/verify
تحقق OTP
GET
/api/v1/store/catalog
الكتالوج والتوفر
GET
/api/v1/store/products/:slug
تفاصيل المنتج
POST
/api/v1/store/availability
التوفر حسب الموقع والسلة
GET/PUT
/api/v1/store/cart
قراءة/تحديث السلة
POST
/api/v1/store/orders
تأكيد وحجز
GET
/api/v1/store/orders/:id
تفاصيل وتتبع
POST
/api/v1/store/orders/:id/cancel
إلغاء قبل التجهيز
POST
/api/v1/store/orders/:id/return
طلب إرجاع
GET
/api/v1/ecommerce/orders
صندوق الإدارة
POST
/api/v1/ecommerce/orders/:id/accept
قبول المخزن
POST
/api/v1/ecommerce/orders/:id/reject
رفض وإعادة إسناد
POST
/api/v1/ecommerce/orders/:id/start-preparing
بدء التجهيز
POST
/api/v1/ecommerce/orders/:id/ready
جاهز
POST
/api/v1/ecommerce/orders/:id/assign-delivery
إسناد التوصيل
POST
/api/v1/ecommerce/orders/:id/deliver
COD وتسليم
POST
/api/v1/ecommerce/orders/:id/refuse-delivery
رفض الاستلام
POST
/api/v1/ecommerce/orders/:id/confirm-return
إعادة للمخزن
GET/PUT
/api/v1/ecommerce/delivery-zones
المناطق والرسوم
POST
/api/v1/ecommerce/returns/:id/approve
اعتماد الإرجاع
POST
/api/v1/ecommerce/returns/:id/refund-cash
رد نقدي

9. جداول قاعدة البيانات
الجدول
المسؤولية
store_customers / guest_identities
هوية العميل أو الضيف.
customer_addresses
العناوين والإحداثيات.
store_carts / items
السلة.
ecommerce_orders / items
الطلب وSnapshot الأسعار.
order_status_history
تاريخ الحالات.
order_warehouse_candidates
ترتيب المخازن ونتيجة المحاولة.
inventory_reservations
حجز الطلب.
delivery_zones / rules
المناطق والرسوم والحد المجاني.
order_deliveries
نوع التوصيل والناقل.
cod_collections
التحصيل والتسليم للصندوق.
delivery_refusals
رفض العميل والسبب.
ecommerce_returns / items
طلبات الإرجاع.
cash_refunds
الرد النقدي.
inventory_movements
SALE_ISSUE وRETURN_IN.
journal_entries / lines
القيود المحاسبية.
activity_logs
سجل التدقيق.

9.1 القيود والفهارس
Index جغرافي PostGIS على المخازن والعناوين/المناطق.
Unique idempotency_key على إنشاء الطلب والتسليم والرد.
Snapshot immutable للأسعار والرسوم بعد التأكيد.
قفل الأرصدة أثناء اختيار المخزن والحجز.
منع READY/DELIVERED قبل اكتمال كل الأسطر.
Transaction واحدة للتسليم والتحصيل والحركة والقيد.

10. الأثر المخزني والمحاسبي
الحدث
الأثر
تأكيد الطلب
حجز فقط دون قيد.
إلغاء/رفض نهائي
تحرير الحجز.
التسليم وCOD
خفض المخزون؛ مدين نقد لدى الناقل/الصندوق ودائن المبيعات.
تسليم COD للصندوق
نقل العهدة النقدية إلى الصندوق.
رفض الاستلام
إعادة البضاعة للمخزن بعد تأكيد الوصول.
إرجاع معتمد
زيادة المخزون الصالح ورد نقدي وعكس البيع/التكلفة حسب السياسة.

11. معايير القبول
الرمز
معيار القبول
AC-ECO-01
يعرض العدد القابل للتنفيذ من مخزن واحد بدقة.
AC-ECO-02
يمنع تأكيد سلة لا يستطيع مخزن واحد توفيرها.
AC-ECO-03
يختار أقرب مخزن نشط داخل نطاق التوصيل.
AC-ECO-04
يحجز المخزون فور التأكيد.
AC-ECO-05
يعيد الإسناد بأمان عند رفض المخزن.
AC-ECO-06
يمنع إلغاء العميل بعد بدء التجهيز.
AC-ECO-07
يحسب أجور التوصيل حسب المنطقة والقيمة.
AC-ECO-08
يرحل COD والتسليم والمخزون مرة واحدة.
AC-ECO-09
لا يعيد رفض COD للمخزون قبل تأكيد الوصول.
AC-ECO-10
لا ينفذ الرد النقدي قبل اعتماد واستلام المرتجع.

12. حزمة التسليم
التكامل — تستخدم الوثيقة وBPMN الرموز نفسها لتنفيذ المتجر وNestJS وPostGIS والحجز والتوصيل وCOD والإرجاع.

M13_Ecommerce_Store_Orders_Specification_AR.docx
M13_Ecommerce_Store_Orders_BPMN.drawio — اثنا عشر مخططًا