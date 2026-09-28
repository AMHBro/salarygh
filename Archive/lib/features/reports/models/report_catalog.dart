/// تعريف تقرير واحد كما يظهر في شاشة التقارير.
///
/// [path] يطابق مسار ReportsController تحت `/reports`.
class ReportDefinition {
  final String group;
  final String title;
  final String purpose;
  final String path;
  final bool dates;
  final bool customer;
  final bool variant;
  final bool expiryDays;
  final bool chart;
  final String? chartValueKey;

  /// group | customersByRepresentative | representative
  final String? localKind;

  const ReportDefinition({
    required this.group,
    required this.title,
    required this.purpose,
    required this.path,
    this.dates = false,
    this.customer = false,
    this.variant = false,
    this.expiryDays = false,
    this.chart = false,
    this.chartValueKey,
    this.localKind,
  });
}

const String reportGroupWarehouses = 'warehouses';
const String reportGroupCustomers = 'customers';
const String reportGroupMaterials = 'materials';
const String reportGroupCash = 'cash';
const String reportGroupProfits = 'profits';

const List<ReportDefinition> reportCatalog = [
  ReportDefinition(
    group: reportGroupWarehouses,
    title: 'حركة المخزن',
    purpose:
        'مبيعات ومشتريات ووصولات المخزن خلال الفترة. حاسبة المخزن ترى مخزنها فقط.',
    path: 'local:warehouse-movement',
    dates: true,
    localKind: 'warehouseMovement',
  ),
  ReportDefinition(
    group: reportGroupWarehouses,
    title: 'مجموع المخازن',
    purpose: 'مجموع المبيعات والمشتريات والوصولات لكل مخزن على الحاسبة الرئيسية.',
    path: 'local:warehouse-totals',
    localKind: 'warehouseTotals',
  ),
  ReportDefinition(
    group: reportGroupCustomers,
    title: 'كشف حساب زبون معين',
    purpose:
        'حركات البيع والقبض لزبون واحد خلال الفترة، مع المدين والدائن.',
    path: '/reports/customers/statement',
    dates: true,
    customer: true,
  ),
  ReportDefinition(
    group: reportGroupCustomers,
    title: 'كشف مجموعة زبائن',
    purpose:
        'حركات الشراء والقبض والصرف للزبائن المنتمين إلى عائلة أو تصنيف واحد.',
    path: 'local:customer-group',
    dates: true,
    localKind: 'group',
  ),
  ReportDefinition(
    group: reportGroupCustomers,
    title: 'كشف زبائن حسب المندوب',
    purpose: 'أسماء الزبائن المرتبطين بمندوب واحد وأرصدتهم.',
    path: 'local:customers-by-representative',
    localKind: 'customersByRepresentative',
  ),
  ReportDefinition(
    group: reportGroupCustomers,
    title: 'كشف مندوب',
    purpose: 'فواتير البيع والعمولة المسجلة لمندوب خلال الفترة.',
    path: 'local:representative',
    dates: true,
    localKind: 'representative',
  ),
  ReportDefinition(
    group: reportGroupCustomers,
    title: 'الرصيد الإجمالي للزبائن دائن ومدين',
    purpose:
        'مجموع أرصدة الزبائن المدينة والدائنة. متاح لحساب الإدارة فقط.',
    path: '/reports/customers/balances',
  ),
  ReportDefinition(
    group: reportGroupCustomers,
    title: 'تقرير أسماء جميع الزبائن',
    purpose: 'دليل أسماء الزبائن مع الهاتف والنوع والمندوب.',
    path: '/reports/customers/directory',
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'تقرير باكتفاء الصلاحية',
    purpose:
        'دفعات المواد المنتهية أو التي تنتهي خلال عدد الأيام المحدد.',
    path: '/reports/products/expiry',
    expiryDays: true,
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'تقرير بأسعار البيع',
    purpose: 'أسعار البيع الفعالة لكل مادة ووحدة.',
    path: '/reports/products/prices',
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'تقرير بخصومات البيع',
    purpose: 'فواتير البيع التي عليها خصم على الفاتورة أو على البنود.',
    path: '/reports/products/discounts',
    dates: true,
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'أرقام قوائم البيع المفقودة',
    purpose:
        'الفجوات في التسلسل الرقمي لأرقام فواتير البيع على مستوى النظام.',
    path: '/reports/products/missing-invoices',
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'مجموع المبيعات حسب المواد',
    purpose: 'كمية وقيمة المبيعات وعدد الفواتير لكل مادة.',
    path: '/reports/products/sales',
    dates: true,
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'كشف تحليل المشتريات',
    purpose: 'بنود فواتير الشراء: المورد والمخزن والكمية والكلفة.',
    path: '/reports/products/purchase-analysis',
    dates: true,
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'كشف مادة والقوائم التي خرجت بها',
    purpose: 'قوائم البيع المحلية التي خرجت فيها مادة واحدة.',
    path: 'local:product-invoices',
    localKind: 'productInvoices',
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'كشف تحليل المبيعات',
    purpose: 'بنود فواتير البيع: الزبون والمادة والسعر والإجمالي.',
    path: '/reports/products/sales-analysis',
    dates: true,
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'مخطط بياني للمشتريات حسب الأشهر',
    purpose: 'مجموع المشتريات وعدد الفواتير لكل شهر.',
    path: '/reports/products/monthly-purchases',
    dates: true,
    chart: true,
    chartValueKey: 'total_purchases_iqd',
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'مخطط بياني للمبيعات حسب الأشهر',
    purpose: 'مجموع المبيعات وعدد الفواتير لكل شهر.',
    path: '/reports/products/monthly-sales',
    dates: true,
    chart: true,
    chartValueKey: 'total_sales_iqd',
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'تقرير بأرصدة المواد الأولية',
    purpose:
        'أرصدة المواد التي تصنيفها يحتوي «أولي» أو «خام».',
    path: '/reports/products/raw-materials',
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'جرد بأرصدة المواد دون مستوى إعادة الطلب',
    purpose: 'المواد التي رصيدها المتاح أقل من حد إعادة الطلب.',
    path: '/reports/products/below-reorder',
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'جرد بأرصدة المواد',
    purpose: 'الرصيد الفعلي والمحجوز والمتاح وقيمة المخزون.',
    path: '/reports/products/stock',
  ),
  ReportDefinition(
    group: reportGroupMaterials,
    title: 'تقرير بحركة مادة معينة لفترة معينة',
    purpose: 'حركات مخزون خيار مادة واحد خلال الفترة.',
    path: '/reports/products/movements',
    dates: true,
    variant: true,
  ),
  ReportDefinition(
    group: reportGroupCash,
    title: 'التقرير اليومي',
    purpose: 'مقبوضات ومدفوعات وصافي حركة كل صندوق في كل يوم.',
    path: '/reports/cash/daily',
    dates: true,
  ),
  ReportDefinition(
    group: reportGroupCash,
    title: 'كشف رصيد الصندوق',
    purpose: 'رصيد الصناديق المحسوب من آخر جلسة والحركات المسجلة.',
    path: '/reports/cash/balances',
  ),
  ReportDefinition(
    group: reportGroupCash,
    title: 'تقرير رأس المال',
    purpose:
        'يبدأ من رأس المال في الإعدادات. البيع يضيف الربح أو يخصم الخسارة. الشراء والقبض والصرف تظهر ولا تغير رأس المال. الدولار يتحول للدينار.',
    path: 'local:capital',
    dates: true,
    localKind: 'capital',
  ),
  ReportDefinition(
    group: reportGroupCash,
    title: 'كشف البيع والشراء بالدولار',
    purpose: 'فواتير البيع والشراء المسجلة بالدولار، مع المبلغ بالدينار وما يقابله بالدولار.',
    path: 'local:currency-statement',
    dates: true,
    localKind: 'currencyStatement',
  ),
  ReportDefinition(
    group: reportGroupCash,
    title: 'تقرير أسعار صرف الدولار',
    purpose: 'سعر الدولار المحفوظ في إعدادات الشركة.',
    path: '/reports/cash/exchange-rate',
  ),
  ReportDefinition(
    group: reportGroupCash,
    title: 'كشف المقبوضات',
    purpose: 'حركات القبض النقدية مع الطرف والمبلغ.',
    path: '/reports/cash/receipts',
    dates: true,
  ),
  ReportDefinition(
    group: reportGroupCash,
    title: 'كشف المدفوعات',
    purpose: 'حركات الدفع النقدية مع الطرف والمبلغ.',
    path: '/reports/cash/payments',
    dates: true,
  ),
  ReportDefinition(
    group: reportGroupCash,
    title: 'تقرير بالسندات',
    purpose: 'سندات القبض والدفع مع طريقة الدفع والفاتورة المرتبطة.',
    path: '/reports/cash/vouchers',
    dates: true,
  ),
  ReportDefinition(
    group: reportGroupProfits,
    title: 'مجموع الأرباح حسب الزبائن',
    purpose: 'المبيعات والكلفة والربح الإجمالي لكل زبون.',
    path: '/reports/profits/by-customer',
    dates: true,
  ),
  ReportDefinition(
    group: reportGroupProfits,
    title: 'مجموع الأرباح حسب المواد',
    purpose: 'المبيعات والكلفة والربح الإجمالي لكل مادة.',
    path: '/reports/profits/by-product',
    dates: true,
  ),
  ReportDefinition(
    group: reportGroupProfits,
    title: 'كشف تحليل الأرباح',
    purpose: 'المبيعات والكلفة والربح الإجمالي لكل فاتورة.',
    path: '/reports/profits/analysis',
    dates: true,
  ),
];

const Map<String, String> reportColumnLabels = {
  'customer_name': 'اسم الزبون',
  'group_name': 'العائلة أو التصنيف',
  'commission_iqd': 'العمولة',
  'phone': 'الهاتف',
  'email': 'البريد',
  'customer_type': 'النوع',
  'is_active': 'فعال',
  'representative_name': 'المندوب',
  'recorded_balance': 'الرصيد المسجل',
  'debit_total_iqd': 'إجمالي المدين',
  'credit_total_iqd': 'إجمالي الدائن',
  'customer_count': 'عدد الزبائن',
  'occurred_at': 'التاريخ',
  'reference_number': 'الرقم النهائي',
  'operation_type': 'نوع العملية',
  'entry_type': 'نوع العملية',
  'warehouse_name': 'المخزن',
  'debit_iqd': 'مدين',
  'credit_iqd': 'دائن',
  'product_name': 'المادة',
  'product_code': 'الرمز',
  'price_type': 'نوع السعر',
  'unit_name': 'الوحدة',
  'price': 'السعر',
  'updated_at': 'آخر تحديث',
  'batch_number': 'الدفعة',
  'expiry_date': 'الصلاحية',
  'quantity': 'الكمية',
  'days_remaining': 'الأيام المتبقية',
  'quantity_on_hand': 'الرصيد',
  'quantity_reserved': 'المحجوز',
  'quantity_in_transit': 'بالطريق',
  'quantity_available': 'المتاح',
  'min_stock_level': 'حد إعادة الطلب',
  'stock_value_iqd': 'قيمة المخزون',
  'sold_base_quantity': 'الكمية المباعة',
  'sales_total_iqd': 'إجمالي المبيعات',
  'invoice_count': 'عدد الفواتير',
  'invoice_number': 'رقم الفاتورة',
  'invoice_date': 'تاريخ الفاتورة',
  'supplier_name': 'المورد',
  'unit_cost_iqd': 'كلفة الوحدة',
  'line_total_iqd': 'إجمالي البند',
  'unit_price_iqd': 'سعر الوحدة',
  'month': 'الشهر',
  'total_purchases_iqd': 'مجموع المشتريات',
  'total_sales_iqd': 'مجموع المبيعات',
  'category_name': 'التصنيف',
  'movement_type': 'نوع الحركة',
  'created_at': 'وقت الحركة',
  'reference_type': 'مرجع الحركة',
  'notes': 'ملاحظات',
  'subtotal': 'المجموع',
  'invoice_discount_iqd': 'خصم الفاتورة',
  'item_discount_iqd': 'خصم البنود',
  'missing_invoice_number': 'الرقم المفقود',
  'report_date': 'اليوم',
  'branch_name': 'الفرع',
  'cashbox_name': 'الصندوق',
  'receipts_iqd': 'المقبوضات',
  'payments_iqd': 'المدفوعات',
  'net_movement_iqd': 'الصافي',
  'last_session_opened_at': 'فتح آخر جلسة',
  'last_opening_balance_iqd': 'رصيد الافتتاح',
  'recorded_receipts_iqd': 'مقبوضات مسجلة',
  'recorded_payments_iqd': 'مدفوعات مسجلة',
  'calculated_balance_iqd': 'الرصيد المحسوب',
  'party_name': 'الطرف',
  'movement_kind': 'نوع الحركة',
  'amount_iqd': 'المبلغ',
  'voucher_date': 'تاريخ السند',
  'voucher_number': 'رقم السند',
  'voucher_type': 'نوع السند',
  'payment_method': 'طريقة الدفع',
  'company_name': 'الشركة',
  'usd_exchange_rate': 'سعر الدولار',
  'inventory_value_iqd': 'قيمة المخزون',
  'customer_debit_iqd': 'ذمم الزبائن',
  'supplier_credit_iqd': 'ذمم الموردين',
  'cash_iqd': 'الصندوق',
  'capital_iqd': 'رأس المال التقديري',
  'capital_balance': 'رأس المال بعد الحركة',
  'effect_note': 'أثر الحركة',
  'profit_iqd': 'أثر على رأس المال',
  'sales_iqd': 'المبيعات',
  'cost_iqd': 'الكلفة',
  'gross_profit_iqd': 'الربح الإجمالي',
};

String reportColumnLabel(String key) {
  if (key.endsWith('_usd')) {
    final base = key.substring(0, key.length - 4);
    final name = reportColumnLabels[base] ?? base;
    return '$name (دولار)';
  }

  return reportColumnLabels[key] ?? key;
}
