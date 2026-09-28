SYSTEM MODULE SPECIFICATION
M02
الشركة والفروع والمخازن
Company, Branches & Warehouses
الغرض — مرجع موحّد للمفاهيم، العمليات، الواجهات، المسؤوليات، الحالات، قواعد العمل، API، وقاعدة البيانات لموديول الهيكل التشغيلي.

المشروع: نظام إدارة المخزون والمبيعات والتوزيع
الإصدار: 1.0  |  التاريخ: 12 آب 2026
التصميم: الملف الحالي في Figma — Desktop وTablet — RTL

1. المفاهيم والنطاق
يمثل هذا الموديول الهيكل المكاني والإداري الذي تعمل داخله بقية وحدات النظام. النظام مخصص لشركة واحدة، ويعامل مقر الشركة كفرع رئيسي واحد، بينما يحتوي كل فرع على عدة مخازن رئيسية وفرعية.
قرار هيكلي — المخزن الفرعي يتبع مخزنًا رئيسيًا محددًا داخل الفرع نفسه؛ لذلك يمكن تتبع المسؤولية ومسار التزويد دون خلطه بالتحويل بين الفروع.

المفهوم
التعريف
الشركة
الكيان القانوني الوحيد الذي يملكه النظام.
الفرع الرئيسي
مقر الشركة، ويسجل كفرع من النوع HEADQUARTERS.
الفرع الاعتيادي
موقع تشغيلي تابع للشركة وله مدير واحد.
المخزن الرئيسي
مخزن مستقل داخل الفرع ويمكن أن تتبعه مخازن فرعية.
المخزن الفرعي
مخزن يتبع مخزنًا رئيسيًا واحدًا في الفرع نفسه.
مدير المخزن
المسؤول الإداري الوحيد عن المخزن.
أمين المخزن
مستخدم تشغيلي؛ يمكن تعيين عدة أمناء للمخزن.

1.1 القرارات المعتمدة
المحور
القرار
عدد الشركات
شركة واحدة
هيكل المواقع
شركة ← فروع ← مخازن
المقر
فرع رئيسي واحد
المخازن الرئيسية
عدة مخازن رئيسية لكل فرع
المخزن الفرعي
يتبع مخزنًا رئيسيًا محددًا
الاعتماد
مسودة ثم موافقة إدارة الشركة
الرموز
تلقائية مع السماح بالتعديل بصلاحية
التعطيل
ممنوع حتى تصفير الأرصدة ومعالجة الارتباطات

2. خريطة الموديول
العنصر
التغطية
العمليات BPMN
8 عمليات من الإنشاء إلى التعطيل.
الواجهات Screens
12 واجهة إدارية وتشغيلية.
الأدوار والصلاحيات
صلاحيات دقيقة ترتبط بـM01.
قواعد العمل
الهيكل، الاعتماد، المسؤوليات، الرموز والتعطيل.
الحالات
دورة اعتماد موحدة للفرع والمخزن.
API Endpoints
Company، Branches، Warehouses، Assignments، Approvals.
قاعدة البيانات
جداول الهيكل والمسؤوليات وطلبات الاعتماد والتاريخ.

2.1 العمليات BPMN
الرمز
العملية
الناتج
BPMN-ORG-01
إكمال بيانات الشركة
شركة جاهزة للاستخدام
BPMN-ORG-02
إنشاء فرع وإرساله للاعتماد
طلب فرع قيد المراجعة
BPMN-ORG-03
اعتماد أو رفض الفرع
فرع نشط أو مرفوض بسبب واضح
BPMN-ORG-04
إنشاء مخزن رئيسي أو فرعي واعتماده
مخزن نشط مرتبط بفرعه
BPMN-ORG-05
تعيين المدير والأمناء
مسؤوليات فعالة وغير متعارضة
BPMN-ORG-06
تعديل فرع أو مخزن وإعادة اعتماده
نسخة معتمدة جديدة مع حفظ التاريخ
BPMN-ORG-07
تعطيل مخزن
مخزن غير نشط بعد التحقق من الرصيد
BPMN-ORG-08
تعطيل فرع
فرع غير نشط بعد معالجة مخازنه

3. شرح العمليات
BPMN-ORG-01 — بيانات الشركة
يفتح مسؤول الشركة صفحة البيانات الأساسية.
يدخل الاسم القانوني والتجاري والرقم الضريبي ومعلومات الاتصال.
يتحقق النظام من الحقول ويحفظ النسخة ويسجل التعديل.
BPMN-ORG-02/03 — إنشاء واعتماد فرع
ينشئ موظف الهيكل مسودة الفرع ويعين مديرًا.
يتحقق النظام من الرمز، النوع، المدير، ووجود مقر رئيسي واحد فقط.
يرسل الموظف الطلب؛ فتنتقل الحالة إلى PENDING_APPROVAL.
تراجع إدارة الشركة البيانات وتوافق أو ترفض بسبب إلزامي.
عند الموافقة يصبح الفرع ACTIVE؛ وعند الرفض يعاد للتعديل.
BPMN-ORG-04 — إنشاء واعتماد مخزن
يختار الموظف فرعًا نشطًا ونوع المخزن.
للمخزن الفرعي يختار مخزنًا رئيسيًا نشطًا من الفرع نفسه.
يعين المدير والأمناء ثم يرسل الطلب.
تعتمد إدارة الشركة الطلب أو ترفضه مع السبب.
BPMN-ORG-05 — المسؤوليات
يختار المسؤول مدير الفرع أو مدير/أمناء المخزن من مستخدمي M01 النشطين.
يتحقق النظام من عدم تضارب التعيين ومن نطاق وصول المستخدم.
تحدد تواريخ البداية والنهاية ويسجل التغيير.
BPMN-ORG-06 — تعديل معتمد
ينشئ النظام نسخة تعديل دون تغيير النسخة التشغيلية الحالية.
ترسل النسخة للاعتماد.
عند الموافقة تحل محل النسخة السابقة ويحفظ Before/After.
BPMN-ORG-07/08 — التعطيل
يفحص النظام الأرصدة والحركات المفتوحة والارتباطات التابعة.
إذا وجد رصيد أو مخزن فرعي/نشط يمنع التعطيل ويعرض الأسباب.
بعد المعالجة تعتمد إدارة الشركة التعطيل وتبقى البيانات السابقة للقراءة.

4. الواجهات Screens
ID
الواجهة
Route
الصلاحية
SCR-ORG-01
بيانات الشركة
/organization/company
company.view
SCR-ORG-02
قائمة الفروع
/organization/branches
branches.view
SCR-ORG-03
إنشاء/تعديل فرع
/organization/branches/new
branches.create/update
SCR-ORG-04
تفاصيل الفرع ومخازنه
/organization/branches/:id
branches.view
SCR-ORG-05
اعتمادات الفروع
/organization/branches/approvals
branches.approve
SCR-ORG-06
قائمة المخازن
/organization/warehouses
warehouses.view
SCR-ORG-07
إنشاء/تعديل مخزن
/organization/warehouses/new
warehouses.create/update
SCR-ORG-08
تفاصيل المخزن
/organization/warehouses/:id
warehouses.view
SCR-ORG-09
اعتمادات المخازن
/organization/warehouses/approvals
warehouses.approve
SCR-ORG-10
تعيين مدير الفرع
/organization/branches/:id/manager
branches.assign_manager
SCR-ORG-11
فريق المخزن
/organization/warehouses/:id/team
warehouses.assign_staff
SCR-ORG-12
الهيكل التنظيمي
/organization/tree
organization.view_tree

4.1 تصميم الواجهات
عربية RTL بخط Cairo وهوية لوحة إدارية فاتحة متوافقة مع M01.
Sidebar على Desktop وتنقل مضغوط على Tablet.
بطاقات مؤشرات، جداول بفلاتر، حالات فارغة وتحميل وأخطاء واضحة.
شارات موحدة للحالات وأزرار الاعتماد والرفض بحسب الصلاحية.
عرض العلاقة الهرمية بصريًا: الشركة ← الفرع ← المخزن الرئيسي ← الفرعي.
تأكيد للرفض والتعطيل مع إظهار أثر القرار قبل تنفيذه.

5. مواصفات الواجهات الأساسية
الواجهة
المحتوى والإجراءات
لوحة الهيكل
إجمالي الفروع والمخازن، طلبات الاعتماد، خريطة هيكلية، إجراءات سريعة.
قائمة الفروع
بحث، نوع، حالة، مدير، عدد المخازن، إنشاء، عرض، تعديل، إرسال واعتماد.
نموذج الفرع
الأسماء، الرمز، النوع، المدير، العنوان، الاتصال، الموقع والملاحظات.
تفاصيل الفرع
البيانات، المدير، مؤشرات المخازن، المخازن التابعة، التاريخ والاعتمادات.
قائمة المخازن
بحث وفلترة بالفرع والنوع والحالة والمدير والمخزن الأب.
نموذج المخزن
الفرع، النوع، المخزن الرئيسي، الرمز، المدير، الأمناء، العنوان والسعة.
تفاصيل المخزن
الرصيد الإجمالي، المنتجات، الفريق، العلاقات، الحركات المفتوحة وسجل التغيير.
صندوق الاعتماد
بيانات قبل/بعد، مقدم الطلب، وقت الإرسال، اعتماد أو رفض بسبب.
الهيكل التنظيمي
شجرة قابلة للتوسيع مع عدادات وحالات وإجراءات سريعة.

6. الأدوار والصلاحيات
الدور
المسؤولية
COMPANY_ADMIN
إدارة الشركة واعتماد الفروع والمخازن والتعطيل.
STRUCTURE_OFFICER
إنشاء المسودات وتعديلها وإرسالها للاعتماد.
BRANCH_MANAGER
عرض وإدارة بيانات فرعه التشغيلية دون اعتماد الهيكل.
WAREHOUSE_MANAGER
عرض مخزنه وفريقه والعمليات المرتبطة به.
WAREHOUSE_KEEPER
الوصول التشغيلي إلى المخازن المعينة له.
AUDITOR
قراءة الهيكل والسجل حسب نطاقه.

Permission Key
الوصف
company.view
عرض بيانات الشركة
company.update
تعديل بيانات الشركة
branches.view/create/update
عرض وإنشاء وتعديل الفروع
branches.submit/withdraw
إرسال أو سحب طلب الفرع
branches.approve/reject
اعتماد أو رفض الفرع
branches.disable
تعطيل الفرع
branches.assign_manager
تعيين مدير الفرع
warehouses.view/create/update
عرض وإنشاء وتعديل المخازن
warehouses.submit/withdraw
إرسال أو سحب طلب المخزن
warehouses.approve/reject
اعتماد أو رفض المخزن
warehouses.disable
تعطيل المخزن
warehouses.assign_staff
تعيين المدير والأمناء
organization.view_tree
عرض الشجرة التنظيمية
organization.view_history
عرض تاريخ التغييرات

7. الحالات Statuses
الحالة
الوصف
الاستخدام التشغيلي
DRAFT
مسودة قابلة للتعديل
لا
PENDING_APPROVAL
بانتظار إدارة الشركة
لا
REJECTED
مرفوضة مع السبب ويمكن تعديلها
لا
ACTIVE
معتمدة ونشطة
نعم
INACTIVE
معطلة مع حفظ التاريخ
قراءة فقط

7.1 الانتقالات
من
إلى
الشرط
DRAFT
PENDING_APPROVAL
اكتمال البيانات وإرسال الطلب
PENDING_APPROVAL
ACTIVE
موافقة إدارة الشركة
PENDING_APPROVAL
REJECTED
رفض مع سبب إلزامي
REJECTED
DRAFT
فتح الطلب للتعديل
ACTIVE
PENDING_APPROVAL
تعديل جوهري يحتاج اعتمادًا
ACTIVE
INACTIVE
نجاح فحوص التعطيل واعتماد الإدارة

8. قواعد العمل Business Rules
الرمز
القاعدة
BR-ORG-001
يوجد سجل شركة واحد فقط.
BR-ORG-002
يوجد فرع HEADQUARTERS واحد فقط.
BR-ORG-003
كل فرع يتبع الشركة وكل مخزن يتبع فرعًا واحدًا.
BR-ORG-004
المخزن الفرعي يتبع مخزنًا رئيسيًا نشطًا داخل الفرع نفسه.
BR-ORG-005
يمكن للفرع احتواء عدة مخازن رئيسية.
BR-ORG-006
لكل فرع مدير واحد نشط ولكل مخزن مدير واحد وعدة أمناء.
BR-ORG-007
الفرع أو المخزن غير ACTIVE لا يظهر في المعاملات.
BR-ORG-008
إدارة الشركة فقط تعتمد أو ترفض الطلبات.
BR-ORG-009
لا يعتمد منشئ الطلب طلبه بنفسه.
BR-ORG-010
الرفض يتطلب سببًا؛ وإعادة الإرسال تحفظ التاريخ.
BR-ORG-011
الرموز فريدة وتولد تلقائيًا ويمكن تعديلها بصلاحية.
BR-ORG-012
لا يعاد استخدام رمز سبق استعماله.
BR-ORG-013
لا يحذف كيان استخدم في معاملة؛ يعطل فقط.
BR-ORG-014
لا يعطل مخزن يحتوي رصيدًا أو حركات مفتوحة.
BR-ORG-015
لا يعطل مخزن رئيسي قبل معالجة مخازنه الفرعية.
BR-ORG-016
لا يعطل فرع قبل تصفير أرصدة جميع مخازنه وتعطيلها.
BR-ORG-017
التعديلات الجوهرية على كيان نشط تحتاج إعادة اعتماد.
BR-ORG-018
كل تغيير واعتماد ورفض وتعطيل يسجل في Audit Log.

9. API Endpoints
Method
Endpoint
الحماية
الغرض
GET/PATCH
/api/v1/company
company.view/update
عرض/تعديل الشركة
GET/POST
/api/v1/branches
branches.view/create
قائمة/إنشاء فرع
GET/PATCH
/api/v1/branches/:id
branches.view/update
تفاصيل/تعديل
POST
/api/v1/branches/:id/submit
branches.submit
إرسال للاعتماد
POST
/api/v1/branches/:id/withdraw
branches.withdraw
سحب الطلب
POST
/api/v1/branches/:id/approve
branches.approve
اعتماد الفرع
POST
/api/v1/branches/:id/reject
branches.reject
رفض الفرع
POST
/api/v1/branches/:id/disable
branches.disable
تعطيل الفرع
PUT
/api/v1/branches/:id/manager
branches.assign_manager
تعيين المدير
GET/POST
/api/v1/warehouses
warehouses.view/create
قائمة/إنشاء مخزن
GET/PATCH
/api/v1/warehouses/:id
warehouses.view/update
تفاصيل/تعديل
POST
/api/v1/warehouses/:id/submit
warehouses.submit
إرسال للاعتماد
POST
/api/v1/warehouses/:id/approve
warehouses.approve
اعتماد المخزن
POST
/api/v1/warehouses/:id/reject
warehouses.reject
رفض المخزن
POST
/api/v1/warehouses/:id/disable
warehouses.disable
تعطيل المخزن
PUT
/api/v1/warehouses/:id/manager
warehouses.assign_staff
تعيين المدير
PUT
/api/v1/warehouses/:id/keepers
warehouses.assign_staff
تعيين الأمناء
GET
/api/v1/organization/tree
organization.view_tree
عرض الهيكل
GET
/api/v1/organization/approvals
branches/warehouses.approve
صندوق الاعتماد
GET
/api/v1/organization/:type/:id/history
organization.view_history
سجل التغيير

10. جداول قاعدة البيانات
الجدول
المسؤولية
companies
بيانات الشركة الواحدة.
branches
الفروع ونوعها وحالتها ومديرها.
warehouses
المخازن ونوعها وفرعها والمخزن الأب.
branch_managers
تاريخ تعيين مدير الفرع.
warehouse_managers
تاريخ تعيين مدير المخزن.
warehouse_keepers
ربط عدة أمناء بالمخزن مع المدة.
organization_approval_requests
طلبات الإنشاء والتعديل والتعطيل وقراراتها.
organization_change_versions
نسخ Before/After للتعديلات المعتمدة.
activity_logs
سجل الأحداث والمنفذ والتوقيت.

10.1 العلاقات الأساسية
companies 1—N branches.
branches 1—N warehouses.
warehouses علاقة ذاتية: parent_warehouse_id للمخزن الفرعي.
users 1—N branch_managers وwarehouse_managers وwarehouse_keepers عبر سجلات تاريخية.
كل فرع أو مخزن يمكن أن يملك عدة approval_requests وchange_versions.
10.2 القيود والفهارس
Unique على company code وbranch code وwarehouse code.
Partial unique يضمن فرع HEADQUARTERS واحدًا فعالًا.
Check constraint: المخزن الفرعي يحتاج parent_warehouse_id، والرئيسي لا يحتاجه.
Composite index على warehouses(branch_id,status,type).
منع اختلاف branch_id بين المخزن الفرعي والمخزن الأب عبر Service validation/trigger.
Version column للتعامل مع التعديل المتزامن.

11. معايير القبول
الرمز
معيار القبول
AC-ORG-01
لا يمكن إنشاء شركة ثانية.
AC-ORG-02
لا يمكن اعتماد أكثر من مقر رئيسي.
AC-ORG-03
لا يظهر الفرع أو المخزن قبل ACTIVE في المعاملات.
AC-ORG-04
يرفض ربط مخزن فرعي بمخزن رئيسي من فرع آخر.
AC-ORG-05
لا يعتمد منشئ الطلب طلبه.
AC-ORG-06
يظهر سبب الرفض ويمكن إعادة الإرسال مع حفظ التاريخ.
AC-ORG-07
يمنع تعطيل المخزن إذا كان رصيده غير صفر.
AC-ORG-08
يمنع تعطيل الفرع إذا بقي مخزن نشط أو رصيد.
AC-ORG-09
تعرض الواجهات الهيكل بشكل صحيح على Desktop وTablet.
AC-ORG-10
يسجل Audit Log القيم القديمة والجديدة وقرار الاعتماد.

12. حزمة التسليم
التكامل — تستخدم وثيقة Word ومخططات Draw.io وشاشات Figma الرموز والمصطلحات نفسها، لربط التحليل والتنفيذ والاختبار.

M02_Company_Branches_Warehouses_Specification_AR.docx
M02_Company_Branches_Warehouses_BPMN.drawio — ثماني صفحات
Figma الحالي — شاشات Desktop وTablet لموديول M02