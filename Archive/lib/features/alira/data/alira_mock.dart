class AliraProduct {
  final String id;
  final String sku;
  final String name;
  final String unit;
  final int price;
  final int? repPrice;
  final String currency;
  final bool inStock;
  final String? imageUrl;
  final String color;
  final String categoryId;
  final String categoryName;
  final String? variantId;
  final String? unitId;
  final Map<String, int> prices;
  final int stock;

  const AliraProduct({
    required this.id,
    required this.sku,
    required this.name,
    required this.unit,
    required this.price,
    this.repPrice,
    this.currency = 'IQD',
    this.inStock = true,
    this.imageUrl,
    required this.color,
    this.categoryId = 'fam_food',
    this.categoryName = 'مواد غذائية',
    this.variantId,
    this.unitId,
    this.prices = const {},
    this.stock = 0,
  });

  int get agentPrice => prices['representative'] ?? repPrice ?? price;

  int priceFor(String key) {
    final listed = prices[key];
    if (listed != null && listed > 0) return listed;
    if (key == 'representative') return agentPrice;
    return price;
  }

  String get priceText {
    const names = {
      'wholesale': 'جملة',
      'representative': 'مندوب',
      'retail': 'مفرد',
    };
    final parts = [
      for (final entry in prices.entries)
        if (entry.value > 0) '${names[entry.key] ?? entry.key} ${entry.value}',
    ];
    if (parts.length > 1) return parts.join(' · ');
    return 'IQD $price';
  }
}

class AliraCustomer {
  final String id;
  final String name;
  final String city;
  final String area;
  final String phone;
  int balance;
  final String currency;
  final int creditLimit;
  final int allowedAmount;
  final int agingDays;
  final bool cooperating;

  AliraCustomer({
    required this.id,
    required this.name,
    required this.city,
    required this.area,
    required this.phone,
    required this.balance,
    this.currency = 'IQD',
    required this.creditLimit,
    required this.allowedAmount,
    required this.agingDays,
    required this.cooperating,
  });
}

class AliraInvoice {
  final String id;
  final String number;
  final String customerId;
  final String type;
  final String date;
  final int amount;
  final int remaining;
  final int ageDays;
  final bool overdue;
  final String currency;

  const AliraInvoice({
    required this.id,
    required this.number,
    required this.customerId,
    required this.type,
    required this.date,
    required this.amount,
    required this.remaining,
    required this.ageDays,
    required this.overdue,
    this.currency = 'IQD',
  });
}

class AliraStatementEntry {
  final String id;
  final String date;
  final String title;
  final int amount;

  const AliraStatementEntry({
    required this.id,
    required this.date,
    required this.title,
    required this.amount,
  });
}

class AliraStatement {
  final String customerId;
  final int debit;
  final int credit;
  final int balance;
  final String? lastMovementDate;
  final String currency;
  final List<AliraStatementEntry> entries;

  const AliraStatement({
    required this.customerId,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.lastMovementDate,
    this.currency = 'IQD',
    required this.entries,
  });
}

class AliraAging {
  final AliraCustomer customer;
  final int overdueCount;
  final int allowedCount;
  final List<AliraInvoice> invoices;

  const AliraAging({
    required this.customer,
    required this.overdueCount,
    required this.allowedCount,
    required this.invoices,
  });
}

class AliraVisit {
  final String id;
  final String customerId;
  String status;
  final String startedAt;
  String? endedAt;
  String notes;
  int invoicesCount;
  int receiptsTotal;
  int activitiesCount;
  int pendingRequestsCount;

  AliraVisit({
    required this.id,
    required this.customerId,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.notes = '',
    this.invoicesCount = 0,
    this.receiptsTotal = 0,
    this.activitiesCount = 0,
    this.pendingRequestsCount = 0,
  });
}

class AliraKpis {
  int visitsToday;
  int remaining;
  int completed;
  int postponed;
  int cooperating;
  int notCooperating;

  AliraKpis({
    required this.visitsToday,
    required this.remaining,
    required this.completed,
    required this.postponed,
    required this.cooperating,
    required this.notCooperating,
  });
}

class AliraRoutes {
  final String date;
  final String agentId;
  final AliraKpis kpis;
  AliraVisit? activeVisit;
  final List<AliraCustomer> customers;

  AliraRoutes({
    required this.date,
    required this.agentId,
    required this.kpis,
    required this.activeVisit,
    required this.customers,
  });
}

class AliraOrder {
  final String id;
  final String status;
  final Map<String, String> customer;
  final List<Map<String, dynamic>> items;
  final String? notes;
  final int total;
  final String currency;
  final String createdAt;

  const AliraOrder({
    required this.id,
    required this.status,
    required this.customer,
    required this.items,
    required this.notes,
    required this.total,
    required this.currency,
    required this.createdAt,
  });
}

class AliraAgentSale {
  final String id;
  final String status;
  final String customerId;
  final String customerName;
  final List<Map<String, dynamic>> items;
  final int subtotal;
  final int total;
  final int discount;
  final int paidAmount;
  final int remainingAmount;
  final String paymentType;
  final String currency;
  final String createdAt;
  final String visitId;

  const AliraAgentSale({
    required this.id,
    required this.status,
    required this.customerId,
    required this.customerName,
    required this.items,
    required this.subtotal,
    required this.total,
    required this.discount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.paymentType,
    required this.currency,
    required this.createdAt,
    required this.visitId,
  });
}

class AliraMock {
  AliraMock._();

  static final AliraMock instance = AliraMock._();

  final List<AliraProduct> products = const [
    AliraProduct(
      id: 'prd_zahy',
      sku: 'ZAHY-800',
      name: 'زاهي كرمل 800 مل',
      unit: 'قنينة',
      price: 8000,
      color: '#8b5a2b',
    ),
    AliraProduct(
      id: 'prd_ahmad',
      sku: 'AHMAD-450',
      name: 'شاي أحمد 450 غم',
      unit: 'علبة',
      price: 12500,
      color: '#1f6b4a',
    ),
    AliraProduct(
      id: 'prd_diba',
      sku: 'DIBA-100',
      name: 'شاي ديبة 100 ظرف',
      unit: 'علبة',
      price: 9000,
      color: '#c45c26',
    ),
    AliraProduct(
      id: 'prd_oil',
      sku: 'OIL-1500',
      name: 'زيت نباتي 1.5 لتر',
      unit: 'قنينة',
      price: 14500,
      color: '#c4a35a',
    ),
    AliraProduct(
      id: 'prd_sugar',
      sku: 'SUGAR-1',
      name: 'سكر ناعم 1 كغم',
      unit: 'كيس',
      price: 2500,
      color: '#6b7788',
    ),
    AliraProduct(
      id: 'prd_milk',
      sku: 'MILK-400',
      name: 'حليب مجفف 400 غم',
      unit: 'علبة',
      price: 11000,
      color: '#3d7ea6',
    ),
  ];

  final List<AliraCustomer> customers = [
    AliraCustomer(
      id: 'cus_rusul',
      name: 'مكتب الرسل شارع الميزان',
      city: 'بغداد',
      area: 'الرصافة',
      phone: '9647709279536',
      balance: 0,
      creditLimit: 0,
      allowedAmount: 0,
      agingDays: 0,
      cooperating: true,
    ),
    AliraCustomer(
      id: 'cus_kamel',
      name: 'محلات الحاج كامل ابو محمد جميلة',
      city: 'بغداد',
      area: 'الرصافة',
      phone: '9647726747008',
      balance: 4540000,
      creditLimit: 0,
      allowedAmount: 0,
      agingDays: 30,
      cooperating: true,
    ),
    AliraCustomer(
      id: 'cus_sharjah',
      name: 'مكتب الشارقة جميلة',
      city: 'بغداد',
      area: 'الرصافة',
      phone: '9647714956571',
      balance: 0,
      creditLimit: 0,
      allowedAmount: 0,
      agingDays: 0,
      cooperating: false,
    ),
  ];

  final List<AliraInvoice> invoices = const [
    AliraInvoice(
      id: 'inv_27027',
      number: '27027',
      customerId: 'cus_kamel',
      type: 'SALE',
      date: '2026-07-15',
      amount: 2660000,
      remaining: 2090000,
      ageDays: 31,
      overdue: true,
    ),
    AliraInvoice(
      id: 'inv_28470',
      number: '28470',
      customerId: 'cus_kamel',
      type: 'SALE',
      date: '2026-07-22',
      amount: 2450000,
      remaining: 2450000,
      ageDays: 24,
      overdue: false,
    ),
  ];

  late AliraRoutes routes = AliraRoutes(
    date: '2026-09-20',
    agentId: 'agt_001',
    kpis: AliraKpis(
      visitsToday: 32,
      remaining: 18,
      completed: 14,
      postponed: 0,
      cooperating: 24,
      notCooperating: 8,
    ),
    activeVisit: AliraVisit(
      id: 'vis_open_kamel',
      customerId: 'cus_kamel',
      status: 'in_progress',
      startedAt: '2026-09-20T09:32:00',
    ),
    customers: customers,
  );

  int _seq = 1;

  AliraCustomer addOffice({
    required String name,
    required String phone,
    required String address,
  }) {
    final parts = address.split('-').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
    final customer = AliraCustomer(
      id: 'cus_${_seq++}',
      name: name.trim(),
      city: parts.isEmpty ? address.trim() : parts.first,
      area: parts.length > 1 ? parts.sublist(1).join(' - ') : '',
      phone: phone.trim(),
      balance: 0,
      creditLimit: 0,
      allowedAmount: 0,
      agingDays: 0,
      cooperating: true,
    );
    customers.insert(0, customer);
    routes.kpis.cooperating += 1;
    return customer;
  }

  AliraProduct? _product(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  List<AliraProduct> getProducts() => products;

  AliraRoutes getRoutes(String date) => routes;

  AliraCustomer customerById(String id) {
    return customers.firstWhere((item) => item.id == id);
  }

  AliraAging getAging(String customerId) {
    final customer = customerById(customerId);
    final list = invoices.where((item) => item.customerId == customerId).toList();
    return AliraAging(
      customer: customer,
      overdueCount: list.where((item) => item.overdue).length,
      allowedCount: list.where((item) => !item.overdue).length,
      invoices: list,
    );
  }

  AliraStatement getStatement(String customerId) {
    if (customerId != 'cus_kamel') {
      return AliraStatement(
        customerId: customerId,
        debit: 0,
        credit: 0,
        balance: 0,
        lastMovementDate: null,
        entries: const [],
      );
    }

    return const AliraStatement(
      customerId: 'cus_kamel',
      debit: 6990000,
      credit: 2450000,
      balance: 4540000,
      lastMovementDate: '2026-07-22',
      entries: [
        AliraStatementEntry(
          id: 'st_1',
          date: '2026-07-22',
          title: 'قبض جزئي',
          amount: -570000,
        ),
        AliraStatementEntry(
          id: 'st_2',
          date: '2026-07-22',
          title: 'فاتورة 28470',
          amount: 2450000,
        ),
        AliraStatementEntry(
          id: 'st_3',
          date: '2026-07-15',
          title: 'فاتورة 27027',
          amount: 2660000,
        ),
      ],
    );
  }

  AliraVisit startVisit(String customerId) {
    customerById(customerId);
    final visit = AliraVisit(
      id: 'vis_${_seq++}',
      customerId: customerId,
      status: 'in_progress',
      startedAt: DateTime.now().toIso8601String(),
    );
    routes.activeVisit = visit;
    return visit;
  }

  AliraVisit finishVisit(String visitId, String action, String notes) {
    final visit = routes.activeVisit;
    if (visit == null || visit.id != visitId) {
      throw StateError('الزيارة غير موجودة');
    }
    if (action != 'complete' && action != 'postpone' && action != 'cancel') {
      throw StateError('إجراء الزيارة غير معروف');
    }
    visit.status = action == 'complete'
        ? 'completed'
        : action == 'postpone'
            ? 'postponed'
            : 'cancelled';
    visit.endedAt = DateTime.now().toIso8601String();
    visit.notes = notes;
    if (action == 'complete') {
      routes.kpis.completed += 1;
      if (routes.kpis.remaining > 0) routes.kpis.remaining -= 1;
    } else if (action == 'postpone') {
      routes.kpis.postponed += 1;
    }
    routes.activeVisit = null;
    return visit;
  }

  AliraAgentSale createAgentSale({
    required String visitId,
    required String customerId,
    required List<Map<String, dynamic>> items,
    required String paymentType,
    required int paidAmount,
    required int discount,
  }) {
    if (items.isEmpty) {
      throw StateError('items_required');
    }
    final customer = customerById(customerId);
    final lines = <Map<String, dynamic>>[];
    var subtotal = 0;
    for (final raw in items) {
      final productId = '${raw['productId']}';
      final quantity = raw['quantity'];
      final qty = quantity is int ? quantity : int.tryParse('$quantity') ?? 0;
      if (qty < 1) throw StateError('invalid_quantity');
      final product = _product(productId);
      if (product == null) throw StateError('unknown_product');
      final lineTotal = product.price * qty;
      subtotal += lineTotal;
      lines.add({
        'productId': product.id,
        'productName': product.name,
        'quantity': qty,
        'unitPrice': product.price,
        'lineTotal': lineTotal,
      });
    }
    final total = subtotal - discount;
    final int paid;
    if (paymentType == 'CASH') {
      paid = total;
    } else if (paymentType == 'CREDIT') {
      paid = 0;
    } else if (paymentType == 'PARTIAL') {
      paid = paidAmount;
    } else {
      throw StateError('طريقة الدفع غير معروفة');
    }
    final sale = AliraAgentSale(
      id: 'asr_${_seq++}',
      status: 'pending',
      customerId: customer.id,
      customerName: customer.name,
      items: lines,
      subtotal: subtotal,
      total: total,
      discount: discount,
      paidAmount: paid,
      remainingAmount: total - paid,
      paymentType: paymentType,
      currency: 'IQD',
      createdAt: DateTime.now().toIso8601String(),
      visitId: visitId,
    );
    final visit = routes.activeVisit;
    if (visit != null && visit.id == visitId) {
      visit.pendingRequestsCount += 1;
      visit.invoicesCount += 1;
    }
    return sale;
  }

  AliraOrder createOrder({
    required String name,
    required String address,
    required String phone,
    required List<Map<String, dynamic>> items,
    String? notes,
  }) {
    if (name.trim().isEmpty || address.trim().isEmpty || phone.trim().isEmpty) {
      throw StateError('customer_required');
    }
    if (items.isEmpty) throw StateError('items_required');
    var total = 0;
    final lines = <Map<String, dynamic>>[];
    for (final raw in items) {
      final productId = '${raw['productId']}';
      final quantity = raw['quantity'];
      final qty = quantity is int ? quantity : int.tryParse('$quantity') ?? 0;
      if (qty < 1) throw StateError('invalid_quantity');
      final product = _product(productId);
      if (product == null) throw StateError('unknown_product');
      total += product.price * qty;
      lines.add({
        'productId': product.id,
        'quantity': qty,
        'name': product.name,
        'unitPrice': product.price,
      });
    }
    return AliraOrder(
      id: 'ord_${_seq++}',
      status: 'pending',
      customer: {'name': name.trim(), 'address': address.trim(), 'phone': phone.trim()},
      items: lines,
      notes: notes,
      total: total,
      currency: 'IQD',
      createdAt: DateTime.now().toIso8601String(),
    );
  }
}

String aliraMoney(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

String aliraSigned(int value) {
  if (value > 0) return '+${aliraMoney(value)}';
  return aliraMoney(value);
}
