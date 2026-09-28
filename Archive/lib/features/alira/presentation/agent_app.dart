import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/alira_agent_api.dart';
import '../../../core/paging/list_page.dart';
import '../data/alira_catalog.dart';
import '../data/alira_mock.dart';
import '../data/alira_store_orders.dart';
import 'alira_frame.dart';
import 'alira_product_image.dart';
import 'agent_sale_session.dart';

class AliraAgentApp extends StatefulWidget {
  const AliraAgentApp({super.key});

  @override
  State<AliraAgentApp> createState() => _AliraAgentAppState();
}

enum _Page { routes, visit, invoice, aging, statement, sent, company, office }

class _AliraAgentAppState extends State<AliraAgentApp> {
  final _mock = AliraMock.instance;
  final _api = AliraAgentApi();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _officeName = TextEditingController();
  final _officePhone = TextEditingController();
  final _officeAddress = TextEditingController();
  final _search = TextEditingController();
  final _notes = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _productSearch = TextEditingController();
  final List<_Page> _stack = [_Page.routes];
  final Map<String, int> _cart = {};

  AliraRoutes? _routes;
  AliraCustomer? _customer;
  String _payment = 'CREDIT';
  AliraAgentSale? _sale;
  int _elapsed = 9;
  String? _familyId;
  Timer? _timer;
  String? _error;
  bool _signedIn = false;
  bool _busy = false;
  String _repName = '';
  List<String> _allowedPrices = const ['representative'];
  String? _invoicePrice = 'representative';
  Map<String, dynamic>? _account;

  @override
  void initState() {
    super.initState();
    _signedIn = AliraCatalog.forceMock;
    _routes = _mock.getRoutes('2026-09-20');
    AliraCatalog.load(agent: true).then((_) {
      if (mounted) setState(() {});
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _username.dispose();
    _password.dispose();
    _officeName.dispose();
    _officePhone.dispose();
    _officeAddress.dispose();
    _search.dispose();
    _notes.dispose();
    _paid.dispose();
    _productSearch.dispose();
    super.dispose();
  }

  void _push(_Page page) => setState(() => _stack.add(page));

  void _pop() {
    if (_stack.length == 1) return;
    setState(() => _stack.removeLast());
  }

  void _reload() => setState(() => _routes = _mock.getRoutes('2026-09-20'));

  Future<void> _openVisit(AliraCustomer customer) async {
    final active = _routes?.activeVisit;
    AliraVisit visit;
    if (active != null && active.customerId == customer.id && active.status == 'in_progress') {
      visit = active;
    } else {
      visit = _mock.startVisit(customer.id);
    }
    _customer = customer;
    _notes.text = visit.notes;
    _elapsed = 9;
    _reload();
    _push(_Page.visit);
  }

  Future<void> _confirmFinish(String action, String title, String body) async {
    final visit = _routes?.activeVisit;
    if (visit == null) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(body),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('تأكيد'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || ok != true) return;
    _mock.finishVisit(visit.id, action, _notes.text.trim());
    _reload();
    setState(() {
      _stack
        ..clear()
        ..add(_Page.routes);
    });
  }

  AliraProduct? _shelfProduct(String id) {
    for (final product in AliraCatalog.products) {
      if (product.id == id) return product;
    }
    return null;
  }

  static const _priceLabels = {
    'wholesale': 'جملة',
    'representative': 'مندوب',
    'retail': 'مفرد',
    'cost': 'كلفة',
  };

  int _unitPrice(AliraProduct product) {
    return AgentSaleSession.unitPrice(product, _invoicePrice);
  }

  String? get _apiPriceType => AgentSaleSession.apiPriceType(_invoicePrice);

  void _applyAllowedPrices(Object? representative) {
    if (representative is! Map) return;
    final raw = '${representative['allowed_prices'] ?? ''}';
    final keys = [
      for (final part in raw.split(','))
        if (_priceLabels.containsKey(part.trim())) part.trim(),
    ];
    _allowedPrices = keys.isEmpty ? const ['representative'] : keys;
    if (_allowedPrices.length == 1) {
      _invoicePrice = _allowedPrices.first;
    } else if (_invoicePrice == null || !_allowedPrices.contains(_invoicePrice)) {
      _invoicePrice = null;
    }
  }

  int get _cartTotal {
    return AgentSaleSession.cartTotal(
      cart: _cart,
      productOf: _shelfProduct,
      invoicePrice: _invoicePrice,
    );
  }

  void _syncPaid() {
    final next = AgentSaleSession.paidText(
      payment: _payment,
      total: _cartTotal,
    );
    if (next.isNotEmpty) {
      _paid.text = next;
    }
  }

  Future<void> _sendSale() async {
    final visit = _routes?.activeVisit;
    final customer = _customer;
    if (_busy) return;
    if (visit == null || customer == null) return;
    if (_cart.isEmpty) {
      setState(() => _error = 'أضف مواد إلى السلة');
      return;
    }
    if (_apiPriceType == null) {
      setState(() => _error = 'حدد نوع سعر القائمة');
      return;
    }
    if (AliraCatalog.fromServer) {
      final token = _api.token;
      if (token == null || token.isEmpty) {
        setState(() => _error = 'سجل دخول المندوب قبل إرسال الطلب');
        return;
      }
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final lines = AgentSaleSession.storeLines(
          cart: _cart,
          productOf: _shelfProduct,
        );
        final number = await AliraStoreOrders.representative(
          token: token,
          partyName: customer.name,
          partyPhone: customer.phone,
          partyAddress: '${customer.city} - ${customer.area}',
          paymentType: _payment,
          partyId: customer.id,
          priceType: _apiPriceType,
          lines: lines,
        );
        final sale = _localSale(visit.id, customer);
        if (!mounted) return;
        setState(() {
          _cart.clear();
          _sale = AliraAgentSale(
            id: number,
            status: sale.status,
            customerId: sale.customerId,
            customerName: sale.customerName,
            items: sale.items,
            subtotal: sale.subtotal,
            total: sale.total,
            discount: sale.discount,
            paidAmount: sale.paidAmount,
            remainingAmount: sale.remainingAmount,
            paymentType: sale.paymentType,
            currency: sale.currency,
            createdAt: sale.createdAt,
            visitId: sale.visitId,
          );
          _busy = false;
          _error = null;
        });
        visit.pendingRequestsCount += 1;
        visit.invoicesCount += 1;
        _reload();
        _push(_Page.sent);
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = error is StateError ? error.message : AliraStoreOrders.message(error);
        });
      }
      return;
    }
    try {
      final sale = _mock.createAgentSale(
        visitId: visit.id,
        customerId: customer.id,
        items: [
          for (final entry in _cart.entries)
            {'productId': entry.key, 'quantity': entry.value},
        ],
        paymentType: _payment,
        paidAmount: int.tryParse(_paid.text.trim()) ?? 0,
        discount: 0,
      );
      _cart.clear();
      _sale = sale;
      _error = null;
      _reload();
      _push(_Page.sent);
    } on StateError catch (error) {
      setState(() => _error = _saleError(error.message));
    }
  }

  AliraAgentSale _localSale(String visitId, AliraCustomer customer) {
    final lines = <Map<String, dynamic>>[];
    var subtotal = 0;
    for (final entry in _cart.entries) {
      final product = _shelfProduct(entry.key);
      if (product == null) continue;
      final lineTotal = _unitPrice(product) * entry.value;
      subtotal += lineTotal;
      lines.add({
        'productId': product.id,
        'productName': product.name,
        'quantity': entry.value,
        'unitPrice': _unitPrice(product),
        'lineTotal': lineTotal,
      });
    }
    final paid = _payment == 'CASH'
        ? subtotal
        : _payment == 'CREDIT'
            ? 0
            : int.tryParse(_paid.text.trim()) ?? 0;
    return AliraAgentSale(
      id: 'asr_${DateTime.now().millisecondsSinceEpoch}',
      status: 'pending',
      customerId: customer.id,
      customerName: customer.name,
      items: lines,
      subtotal: subtotal,
      total: subtotal,
      discount: 0,
      paidAmount: paid,
      remainingAmount: subtotal - paid,
      paymentType: _payment,
      currency: 'IQD',
      createdAt: DateTime.now().toIso8601String(),
      visitId: visitId,
    );
  }

  String _saleError(String code) {
    switch (code) {
      case 'items_required':
        return 'أضف مواد إلى السلة';
      case 'unknown_product':
        return 'مادة غير معروفة';
      case 'invalid_quantity':
        return 'الكمية يجب أن تكون 1 أو أكثر';
      default:
        return code;
    }
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = await _api.login(_username.text, _password.text);
      final representative = body['representative'];
      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _busy = false;
        _repName = representative is Map ? '${representative['name'] ?? ''}' : '';
        _applyAllowedPrices(representative);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AliraAgentApi.message(error);
      });
    }
  }

  void _logout() {
    _api.token = null;
    _account = null;
    _password.clear();
    setState(() {
      _signedIn = false;
      _repName = '';
      _allowedPrices = const ['representative'];
      _invoicePrice = 'representative';
      _stack
        ..clear()
        ..add(_Page.routes);
    });
  }

  Future<void> _loadAccount() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await _api.account();
      if (!mounted) return;
      setState(() {
        _account = account;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AliraAgentApi.message(error);
      });
    }
  }

  Future<void> _saveOffice() async {
    final name = _officeName.text.trim();
    final phone = _officePhone.text.trim();
    final address = _officeAddress.text.trim();
    if (name.length < 2 || phone.length < 10 || address.length < 3) {
      setState(() => _error = 'أدخل اسم المكتب والعنوان ورقم هاتف مكتمل');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!AliraCatalog.forceMock) {
        await _api.createOffice(name: name, phone: phone, address: address);
      }
      _mock.addOffice(name: name, phone: phone, address: address);
      _officeName.clear();
      _officePhone.clear();
      _officeAddress.clear();
      _reload();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stack
          ..clear()
          ..add(_Page.routes);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AliraAgentApi.message(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AliraPhone(
      child: Column(
        children: [
          Expanded(child: _signedIn ? _body() : _loginPage()),
        ],
      ),
    );
  }

  Widget _loginPage() {
    return Column(
      children: [
        const AliraStatusBar(
          title: 'دخول المندوب',
          hint: 'حساب المندوب يتطلب تسجيل الدخول',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'يتصل بعنوان السيرفر المحفوظ في الإعدادات',
                style: TextStyle(fontSize: 12, color: AliraColors.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم',
                  filled: true,
                  fillColor: AliraColors.paper,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  filled: true,
                  fillColor: AliraColors.paper,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AliraColors.red)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: Text(_busy ? 'جاري الدخول...' : 'تسجيل الدخول'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body() {
    switch (_stack.last) {
      case _Page.routes:
        return _routesPage();
      case _Page.visit:
        return _visitPage();
      case _Page.invoice:
        return _invoicePage();
      case _Page.aging:
        return _agingPage();
      case _Page.statement:
        return _statementPage();
      case _Page.sent:
        return _sentPage();
      case _Page.company:
        return _companyPage();
      case _Page.office:
        return _officePage();
    }
  }

  Widget _routesPage() {
    final routes = _routes!;
    final query = _search.text.trim();
    final customers = routes.customers.where((customer) {
      if (query.isEmpty) return true;
      final haystack = '${customer.name} ${customer.city} ${customer.area} ${customer.phone}';
      return haystack.contains(query);
    }).toList();
    final active = routes.activeVisit;
    final activeCustomer = active == null
        ? null
        : routes.customers.where((item) => item.id == active.customerId).firstOrNull;

    return Column(
      children: [
          const AliraStatusBar(
          title: 'المسارات',
          hint: 'تطبيق المندوب · الزيارات والتحصيل',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                'يتصل بعنوان السيرفر المحفوظ في الإعدادات',
                style: TextStyle(fontSize: 12, color: AliraColors.muted),
              ),
              if (_repName.isNotEmpty)
                Text(_repName, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      _push(_Page.company);
                      _loadAccount();
                    },
                    child: const Text('حسابي مع الشركة'),
                  ),
                  FilledButton(
                    onPressed: () => _push(_Page.office),
                    child: const Text('إضافة مكتب'),
                  ),
                  TextButton(onPressed: _logout, child: const Text('خروج')),
                ],
              ),
              const SizedBox(height: 8),
              if (activeCustomer != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1E6),
                    borderRadius: BorderRadius.circular(14),
                    border: const Border.fromBorderSide(AliraColors.frame),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(activeCustomer.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                      TextButton(
                        onPressed: () => _openVisit(activeCustomer),
                        child: const Text('متابعة'),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AliraColors.paper,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AliraColors.line),
                    ),
                    child: const Text('20 سبتمبر'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'ابحث بالاسم أو المدينة أو المنطقة أو الهاتف',
                        isDense: true,
                        filled: true,
                        fillColor: AliraColors.paper,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _kpi('زيارات اليوم', '${routes.kpis.visitsToday}', AliraColors.text),
                  _kpi('المتبقية', '${routes.kpis.remaining}', AliraColors.orange),
                  _kpi('المنجزة', '${routes.kpis.completed}', AliraColors.green),
                  _kpi('المؤجلة', '${routes.kpis.postponed}', AliraColors.text),
                  _kpi('متعاونون', '${routes.kpis.cooperating}', AliraColors.green),
                  _kpi('غير متعاونين', '${routes.kpis.notCooperating}', AliraColors.red),
                ],
              ),
              const SizedBox(height: 10),
              for (final customer in customers) _customerCard(customer, active),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AliraColors.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AliraColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: AliraColors.muted)),
        ],
      ),
    );
  }

  Widget _customerCard(AliraCustomer customer, AliraVisit? active) {
    final open = active != null && active.customerId == customer.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AliraColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AliraColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '${customer.city} · ${customer.area} · ${customer.phone}',
            style: const TextStyle(fontSize: 12, color: AliraColors.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () {
                  _customer = customer;
                  _push(_Page.statement);
                },
                child: const Text('كشف حساب'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => _openVisit(customer),
                child: Text(open ? 'متابعة الزيارة' : 'فتح زيارة'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _visitPage() {
    final customer = _customer!;
    final visit = _routes?.activeVisit;
    final minutes = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsed % 60).toString().padLeft(2, '0');
    final pending = visit?.pendingRequestsCount ?? 0;
    return Column(
      children: [
        AliraStatusBar(title: 'الزيارة الحالية', onBack: _pop),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text('$minutes:$seconds', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
              Text(customer.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text('${customer.city} · ${customer.area}', style: const TextStyle(color: AliraColors.muted)),
              Text('الرصيد IQD ${aliraMoney(customer.balance)}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(onPressed: () => _push(_Page.invoice), child: const Text('فاتورة جديدة')),
                  const FilledButton(onPressed: null, child: Text('مقبوضات')),
                  const FilledButton(onPressed: null, child: Text('فعاليات')),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(onPressed: () => _push(_Page.aging), child: const Text('أعمار الذمم')),
                  OutlinedButton(onPressed: () => _push(_Page.statement), child: const Text('كشف حساب')),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                minLines: 3,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  filled: true,
                  fillColor: AliraColors.paper,
                ),
              ),
              const SizedBox(height: 12),
              if ((visit?.invoicesCount ?? 0) > 0 || pending > 0)
                const Text('تم تسجيل حركة / طلبات', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('فواتير ${visit?.invoicesCount ?? 0}'),
              Text('مقبوضات ${aliraMoney(visit?.receiptsTotal ?? 0)}'),
              Text('فعاليات ${visit?.activitiesCount ?? 0}'),
              if (pending > 0) Text('طلبات بانتظار: $pending'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => _confirmFinish(
                    'cancel',
                    'إلغاء',
                    'ستُغلق الزيارة الحالية دون حفظ أي حركة.',
                  ),
                  child: const Text('إلغاء', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => _confirmFinish(
                    'postpone',
                    'تأجيل',
                    'ستُنقل إلى المؤجلة ويمكن استئنافها لاحقاً من المسارات.',
                  ),
                  child: const Text('تأجيل', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => _confirmFinish(
                    'complete',
                    'إتمام الزيارة',
                    'سيتم إرسال حالة الإتمام إلى الباكند.',
                  ),
                  child: const Text('إتمام الزيارة', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _invoicePage() {
    final query = _productSearch.text.trim();
    final products = AliraCatalog.products.where((item) {
      if (_familyId != null && item.categoryId != _familyId) return false;
      return query.isEmpty || item.name.contains(query);
    });
    return Column(
      children: [
        AliraStatusBar(title: 'فاتورة جديدة', onBack: _pop),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              TextField(
                controller: _productSearch,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'بحث المواد',
                  filled: true,
                  fillColor: AliraColors.paper,
                ),
              ),
              const SizedBox(height: 8),
              if (_allowedPrices.length > 1) ...[
                const Text('سعر هذه القائمة', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final key in _allowedPrices)
                      ChoiceChip(
                        label: Text(_priceLabels[key] ?? key),
                        selected: _invoicePrice == key,
                        onSelected: (_) => setState(() {
                          _invoicePrice = key;
                          _syncPaid();
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final family in AliraCatalog.families)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(family.name),
                          selected: _familyId == family.id,
                          onSelected: (_) => setState(() => _familyId = family.id),
                        ),
                      ),
                  ],
                ),
              ),
              if (_familyId == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('اختر عائلة المواد'),
                ),
              if (_familyId != null) ...[
              for (final product in products)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: aliraProductImage(
                            product.imageUrl,
                            fallback: Container(
                              color: const Color(0xFF6B7788),
                              alignment: Alignment.center,
                              child: Text(
                                product.name.isEmpty ? '' : product.name.substring(0, 1),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              '${_unitPrice(product)} · ${product.unit}',
                              style: const TextStyle(fontSize: 12, color: AliraColors.muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() {
                            final next = (_cart[product.id] ?? 0) - 1;
                            if (next <= 0) {
                              _cart.remove(product.id);
                            } else {
                              _cart[product.id] = next;
                            }
                            _syncPaid();
                          });
                        },
                        icon: const Icon(Icons.remove, size: 18),
                      ),
                      Text('${_cart[product.id] ?? 0}'),
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() {
                            _cart[product.id] = (_cart[product.id] ?? 0) + 1;
                            _syncPaid();
                          });
                        },
                        icon: const Icon(Icons.add, size: 18),
                      ),
                    ],
                  ),
                ),
              ListPagination(
                page: AliraCatalog.page,
                hasNextPage: AliraCatalog.hasNext,
                pageSize: 20,
                loading: AliraCatalog.loading,
                onPageChanged: (page) async {
                  await AliraCatalog.openPage(page, agent: true);
                  if (mounted) setState(() {});
                },
              ),
              ],
              if (_cart.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('أضف مواد إلى السلة'),
                ),
              const SizedBox(height: 8),
              const Text('الدفع', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _payChip('آجل', 'CREDIT'),
                  _payChip('نقدي', 'CASH'),
                  _payChip('جزئي', 'PARTIAL'),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _paid,
                readOnly: _payment != 'PARTIAL',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'المدفوع',
                  filled: true,
                  fillColor: AliraColors.paper,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: AliraColors.red)),
                ),
              const SizedBox(height: 8),
              Text('المجموع IQD ${aliraMoney(_cartTotal)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _sendSale,
            child: const Text('إرسال للمكتب'),
          ),
        ),
      ],
    );
  }

  Widget _payChip(String label, String value) {
    final selected = _payment == value;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: selected ? AliraColors.green : AliraColors.line, width: selected ? 2 : 1),
          ),
          onPressed: () {
            setState(() {
              _payment = value;
              _syncPaid();
            });
          },
          child: Text(label),
        ),
      ),
    );
  }

  Widget _agingPage() {
    final report = _mock.getAging(_customer!.id);
    final total = report.invoices.fold<int>(0, (sum, item) => sum + item.remaining);
    return Column(
      children: [
        AliraStatusBar(title: 'أعمار الذمم', onBack: _pop),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(report.customer.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text('المبلغ المسموح IQD ${aliraMoney(report.customer.allowedAmount)}'),
              Text('حد الدين IQD ${aliraMoney(report.customer.creditLimit)}'),
              Text('عمر الذمة ${report.customer.agingDays} يوم'),
              Text('الرصيد IQD ${aliraMoney(report.customer.balance)}'),
              const SizedBox(height: 8),
              for (final invoice in report.invoices)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AliraColors.paper,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: invoice.overdue ? AliraColors.red : AliraColors.green),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('فاتورة ${invoice.number}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${invoice.date} · عمر ${invoice.ageDays} يوم'),
                      Text('قيمة الفاتورة IQD ${aliraMoney(invoice.amount)}'),
                      Text(
                        'المتبقي IQD ${aliraMoney(invoice.remaining)}',
                        style: TextStyle(color: invoice.overdue ? AliraColors.red : AliraColors.green),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Container(
          color: AliraColors.paper,
          padding: const EdgeInsets.all(12),
          child: Text('المجموع IQD ${aliraMoney(total)} · ${report.invoices.length} فواتير'),
        ),
      ],
    );
  }

  Widget _statementPage() {
    final statement = _mock.getStatement(_customer!.id);
    return Column(
      children: [
        AliraStatusBar(title: 'كشف حساب', onBack: _pop),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(_customer!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('مدين IQD ${aliraMoney(statement.debit)}'),
              Text('دائن IQD ${aliraMoney(statement.credit)}'),
              Text('رصيد IQD ${aliraMoney(statement.balance)}'),
              Text('آخر حركة ${statement.lastMovementDate ?? '—'}'),
              const SizedBox(height: 8),
              if (statement.entries.isEmpty) const Text('لا توجد حركات'),
              for (final entry in statement.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.title),
                  subtitle: Text(entry.date),
                  trailing: Text(
                    aliraSigned(entry.amount),
                    style: TextStyle(
                      color: entry.amount < 0 ? AliraColors.green : AliraColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sentPage() {
    final sale = _sale!;
    return Column(
      children: [
        const AliraStatusBar(title: 'تم الإرسال'),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sale.id, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  AliraStoreOrders.lastQueued
                      ? 'انقطع الاتصال. حُفظ الطلب وسيُرسل عند عودة الإنترنت.\nالإجمالي IQD ${aliraMoney(sale.total)}'
                      : 'الإجمالي IQD ${aliraMoney(sale.total)} · بانتظار موافقة المكتب',
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: () {
              setState(() {
                _stack.remove(_Page.sent);
                if (_stack.last == _Page.invoice) _stack.removeLast();
              });
            },
            child: const Text('العودة للزيارة'),
          ),
        ),
      ],
    );
  }

  Widget _companyPage() {
    final account = _account;
    final company = account?['company'] is Map ? Map<String, dynamic>.from(account!['company'] as Map) : null;
    final link = account?['link'] is Map ? Map<String, dynamic>.from(account!['link'] as Map) : null;
    final profit = account?['profit'] is Map ? Map<String, dynamic>.from(account!['profit'] as Map) : null;
    final statement = account?['statement'] is List ? account!['statement'] as List : const [];

    return Column(
      children: [
        AliraStatusBar(title: 'حسابي مع الشركة', onBack: _pop),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AliraColors.red)),
              if (company != null) ...[
                Text('${company['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text('${company['address']}'),
                Text('${company['phone']}', style: const TextStyle(color: AliraColors.muted)),
                const SizedBox(height: 12),
              ],
              if (link != null)
                _moneyCard(
                  'الربط مع الشركة',
                  '${link['name']} · ${link['office_name']}\nالعمولة ${link['commission_rate']} د.ع · ${link['status']}',
                ),
              if (account != null)
                _moneyCard('الذمة', 'IQD ${aliraMoney(_asInt(account['debt']))}'),
              if (profit != null)
                _moneyCard(
                  'أرباح العمولة',
                  'الإجمالي IQD ${aliraMoney(_asInt(profit['total']))}\nالمصروف IQD ${aliraMoney(_asInt(profit['paid']))}\nالمتبقي IQD ${aliraMoney(_asInt(profit['remaining']))}',
                ),
              const SizedBox(height: 8),
              const Text('كشف الحركة', style: TextStyle(fontWeight: FontWeight.w700)),
              if (statement.isEmpty && !_busy) const Text('لا توجد حركات مسجلة'),
              for (final raw in statement)
                if (raw is Map)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${raw['number']} · ${raw['customer']}'),
                    subtitle: Text('${raw['date']}'),
                    trailing: Text('IQD ${aliraMoney(_asInt(raw['remaining']))}'),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _officePage() {
    return Column(
      children: [
        AliraStatusBar(title: 'إضافة مكتب', onBack: _pop),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _officeName,
                decoration: const InputDecoration(labelText: 'اسم المكتب', filled: true, fillColor: AliraColors.paper),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _officePhone,
                decoration: const InputDecoration(labelText: 'الهاتف', filled: true, fillColor: AliraColors.paper),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _officeAddress,
                decoration: const InputDecoration(labelText: 'العنوان', filled: true, fillColor: AliraColors.paper),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AliraColors.red)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _saveOffice,
                child: Text(_busy ? 'جاري الحفظ...' : 'حفظ المكتب'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _moneyCard(String title, String body) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AliraColors.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AliraColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body),
        ],
      ),
    );
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}
