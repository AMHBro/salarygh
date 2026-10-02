import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/agent_location.dart';
import '../data/alira_agent_api.dart';
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
  final _usernameLive = ValueNotifier('');
  final _passwordLive = ValueNotifier('');
  bool _usernameEdited = false;
  bool _passwordEdited = false;
  final _officeName = TextEditingController();
  final _officePhone = TextEditingController();
  final _officeAddress = TextEditingController();
  final _search = TextEditingController();
  final _notes = TextEditingController();
  final _agentLocation = TextEditingController();
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
  final Map<String, AliraStatement> _statements = {};
  AliraAging? _serverAging;
  bool _rememberLogin = false;
  int _queuedCount = 0;
  static const _loginStorage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _signedIn = AliraCatalog.forceMock;
    _routes = AliraCatalog.forceMock ? _mock.getRoutes('2026-09-20') : _blankRoutes();
    AliraCatalog.load(agent: true).then((_) {
      if (mounted) setState(() {});
    }).catchError((Object error) {
      if (!mounted) return null;
      setState(() {
        _error = error is ServerConnectionException
            ? error.message
            : 'الكتالوج غير متصل بالسيرفر';
      });
      return null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += 1);
    });
    _loadRemembered();
    _refreshQueue();
  }

  Future<void> _loadRemembered() async {
    try {
      final remember = await _loginStorage.read(key: 'alira.agent.remember');
      if (remember != '1' || !mounted) return;
      final username = await _loginStorage.read(key: 'alira.agent.username') ?? '';
      final password = await _loginStorage.read(key: 'alira.agent.password') ?? '';
      setState(() {
        _rememberLogin = true;
        _username.text = username;
        _password.text = password;
        _usernameLive.value = username;
        _passwordLive.value = password;
      });
    } catch (_) {}
  }

  Future<void> _persistLogin(String username, String password) async {
    try {
      if (!_rememberLogin) {
        await _loginStorage.delete(key: 'alira.agent.remember');
        await _loginStorage.delete(key: 'alira.agent.username');
        await _loginStorage.delete(key: 'alira.agent.password');
        return;
      }
      await _loginStorage.write(key: 'alira.agent.remember', value: '1');
      await _loginStorage.write(key: 'alira.agent.username', value: username);
      await _loginStorage.write(key: 'alira.agent.password', value: password);
    } catch (_) {}
  }

  Future<void> _refreshQueue() async {
    final count = await AliraStoreOrders.pendingCount();
    if (!mounted) return;
    setState(() => _queuedCount = count);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _username.dispose();
    _password.dispose();
    _usernameLive.dispose();
    _passwordLive.dispose();
    _officeName.dispose();
    _officePhone.dispose();
    _officeAddress.dispose();
    _search.dispose();
    _notes.dispose();
    _agentLocation.dispose();
    _paid.dispose();
    _productSearch.dispose();
    AliraCatalog.cancelPending();
    super.dispose();
  }

  void _scheduleProducts() {
    AliraCatalog.scheduleLoad(
      agent: true,
      query: _productSearch.text,
      familyId: _productSearch.text.trim().isEmpty ? _familyId : null,
      onDone: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _loadMoreProducts() async {
    await AliraCatalog.load(agent: true, append: true);
    if (mounted) setState(() {});
  }

  void _push(_Page page) {
    setState(() => _stack.add(page));
    if (page == _Page.invoice) {
      _refreshCeiling();
      _refreshQueue();
    }
  }

  String? get _ceilingMessage {
    final message = _account?['debt_ceiling_message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
    return null;
  }

  int get _customerDebtTotal => _asInt(_account?['customer_debt_total']);

  int get _maxDebtLimit => _asInt(_account?['max_debt_limit']);

  bool get _alreadyOverLimit => _maxDebtLimit > 0 && _customerDebtTotal > _maxDebtLimit;

  int get _addedDebt {
    if (_payment == 'CASH') return 0;
    if (_payment == 'PARTIAL') {
      final paid = int.tryParse(_paid.text.trim()) ?? 0;
      if (paid > 0 && paid < _cartTotal) return _cartTotal - paid;
    }
    return _cartTotal;
  }

  bool get _projectedOverLimit {
    if (_maxDebtLimit <= 0) return false;
    return _customerDebtTotal + _addedDebt > _maxDebtLimit;
  }

  String? get _debtAlert {
    if (_maxDebtLimit <= 0) return _ceilingMessage;
    if (!_projectedOverLimit && !_alreadyOverLimit && _ceilingMessage == null) return null;
    final shown = _projectedOverLimit ? _customerDebtTotal + _addedDebt : _customerDebtTotal;
    final name = _repName.trim().isEmpty ? 'المندوب' : _repName.trim();
    return 'تنبيه: مجموع ديون زبائن المندوب $name بلغت (${aliraMoney(shown)}) وتجاوزت السقف المسموح (${aliraMoney(_maxDebtLimit)})';
  }

  bool get _blockSend {
    if (_alreadyOverLimit || _ceilingMessage != null) return true;
    if (_payment == 'CASH') return false;
    return _projectedOverLimit;
  }

  Widget _ceilingBanner() {
    final message = _debtAlert;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F0),
          borderRadius: BorderRadius.circular(AliraColors.radius),
          border: Border.all(color: AliraColors.red, width: 1.4),
        ),
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFF9B1C1C),
            fontWeight: FontWeight.w800,
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Widget _queueBar() {
    if (_queuedCount <= 0) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: const Color(0xFFE7EEF2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        'طلبات محفوظة محلياً: $_queuedCount · تُرفع عند رجوع الاتصال',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AliraColors.teal),
      ),
    );
  }

  Future<void> _refreshCeiling() async {
    final token = _api.token;
    if (token == null || token.isEmpty) return;
    try {
      final account = await _api.account();
      if (!mounted) return;
      setState(() => _account = account);
    } catch (_) {}
  }

  void _pop() {
    if (_stack.length == 1) return;
    setState(() => _stack.removeLast());
  }

  void _reload() {
    if (AliraCatalog.forceMock) {
      setState(() => _routes = _mock.getRoutes('2026-09-20'));
      return;
    }
    setState(() {});
  }

  AliraRoutes _blankRoutes() {
    final today = DateTime.now();
    final date =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return AliraRoutes(
      date: date,
      agentId: '',
      kpis: AliraKpis(
        visitsToday: 0,
        remaining: 0,
        completed: 0,
        postponed: 0,
        cooperating: 0,
        notCooperating: 0,
      ),
      activeVisit: null,
      customers: [],
    );
  }

  String _routeDateLabel(String iso) {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return '${parsed.day} ${months[parsed.month - 1]}';
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }

  AliraRoutes _routesFromAccounts(Map<String, dynamic> body) {
    final previous = _routes?.activeVisit;
    final raw = body['data'];
    final list = raw is List ? raw : const [];
    final customers = <AliraCustomer>[];
    _statements.clear();
    for (final item in list) {
      if (item is! Map) continue;
      final id = '${item['party_id'] ?? item['account_key'] ?? ''}';
      if (id.isEmpty) continue;
      final totals = item['representative_totals'];
      final sales = totals is Map ? _asInt(totals['total_sales']) : 0;
      final paid = totals is Map ? _asInt(totals['total_paid']) : 0;
      final due = totals is Map ? _asInt(totals['total_due']) : _asInt(item['current_balance']);
      final address = '${item['party_address'] ?? ''}'.trim();
      final parts = address.split(RegExp(r'\s*-\s*')).where((part) => part.isNotEmpty).toList();
      final customer = AliraCustomer(
        id: id,
        name: '${item['party_name'] ?? ''}',
        city: parts.isEmpty ? address : parts.first,
        area: parts.length > 1 ? parts.sublist(1).join(' - ') : '',
        phone: '${item['party_phone'] ?? ''}',
        balance: _asInt(item['current_balance']) != 0 ? _asInt(item['current_balance']) : due,
        creditLimit: _asInt(item['credit_limit']),
        allowedAmount: _asInt(item['available_credit']),
        agingDays: 0,
        cooperating: '${item['customer_status'] ?? 'ACTIVE'}' != 'INACTIVE',
      );
      customers.add(customer);
      final last = item['last_order'];
      final lastDate = last is Map ? '${last['submitted_at'] ?? ''}' : '';
      _statements[id] = AliraStatement(
        customerId: id,
        debit: sales,
        credit: paid,
        balance: due,
        lastMovementDate: lastDate.isEmpty ? null : lastDate,
        entries: [
          if (sales != 0)
            AliraStatementEntry(
              id: '$id-sales',
              date: lastDate,
              title: 'مبيعات المندوب',
              amount: sales,
            ),
          if (paid != 0)
            AliraStatementEntry(
              id: '$id-paid',
              date: lastDate,
              title: 'مقبوض',
              amount: -paid,
            ),
        ],
      );
    }
    final rep = body['representative'];
    final keptVisit = previous != null && customers.any((item) => item.id == previous.customerId)
        ? previous
        : null;
    return AliraRoutes(
      date: _blankRoutes().date,
      agentId: rep is Map ? '${rep['id'] ?? ''}' : '',
      kpis: AliraKpis(
        visitsToday: customers.length,
        remaining: customers.length,
        completed: 0,
        postponed: 0,
        cooperating: customers.where((item) => item.cooperating).length,
        notCooperating: customers.where((item) => !item.cooperating).length,
      ),
      activeVisit: keptVisit,
      customers: customers,
    );
  }

  Future<void> _refreshLiveRoutes() async {
    if (AliraCatalog.forceMock) {
      _reload();
      return;
    }
    final token = _api.token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() => _routes = _blankRoutes());
      return;
    }
    try {
      final body = await _api.accounts();
      if (!mounted) return;
      setState(() => _routes = _routesFromAccounts(body));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _routes ??= _blankRoutes();
        _error = AliraAgentApi.message(error);
      });
    }
  }

  Future<void> _openVisit(AliraCustomer customer) async {
    final active = _routes?.activeVisit;
    AliraVisit visit;
    if (active != null && active.customerId == customer.id && active.status == 'in_progress') {
      visit = active;
    } else if (AliraCatalog.forceMock) {
      visit = _mock.startVisit(customer.id);
    } else {
      try {
        final body = await _api.startVisit(customerId: customer.id);
        final id = '${body['id'] ?? ''}';
        if (id.isEmpty || id.startsWith('vis_')) {
          throw StateError('السيرفر لم يعِد معرّف زيارة');
        }
        visit = AliraVisit(
          id: id,
          customerId: customer.id,
          status: '${body['status'] ?? 'in_progress'}',
          startedAt: '${body['started_at'] ?? DateTime.now().toIso8601String()}',
        );
        _routes?.activeVisit = visit;
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = AliraAgentApi.message(error));
        return;
      }
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
    if (AliraCatalog.forceMock) {
      _mock.finishVisit(visit.id, action, _notes.text.trim());
    } else {
      try {
        if (action == 'postpone') {
          await _api.postponeVisit(
            visitId: visit.id,
            notes: _notes.text.trim(),
          );
        } else {
          await _api.endVisit(visitId: visit.id, notes: _notes.text.trim());
        }
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = AliraAgentApi.message(error));
        return;
      }
      visit.status = action == 'complete'
          ? 'completed'
          : action == 'postpone'
              ? 'postponed'
              : 'cancelled';
      visit.endedAt = DateTime.now().toIso8601String();
      visit.notes = _notes.text.trim();
      final routes = _routes;
      if (routes != null) {
        if (action == 'complete') {
          routes.kpis.completed += 1;
          if (routes.kpis.remaining > 0) routes.kpis.remaining -= 1;
        } else if (action == 'postpone') {
          routes.kpis.postponed += 1;
        }
        routes.activeVisit = null;
      }
    }
    _reload();
    setState(() {
      _stack
        ..clear()
        ..add(_Page.routes);
    });
  }

  AliraProduct? _shelfProduct(String id) => AliraCatalog.byId(id);

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

  Future<void> _captureLocation() async {
    final point = await currentAgentLocation();
    if (!mounted) return;
    setState(() {
      if (point != null && point.trim().isNotEmpty) {
        _agentLocation.text = point.trim();
        _error = null;
      } else {
        _error = 'تعذر قراءة الموقع. اكتب الإحداثيات أو رابط الخرائط.';
      }
    });
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
      final partialPaid = int.tryParse(_paid.text.trim()) ?? 0;
      if (_payment == 'PARTIAL' &&
          (partialPaid <= 0 || partialPaid >= _cartTotal)) {
        setState(() {
          _error = 'في البيع الجزئي يجب أن يكون المبلغ المدفوع أكبر من صفر وأقل من الإجمالي';
        });
        return;
      }
      if (_blockSend) {
        setState(() => _error = _debtAlert ?? _ceilingMessage);
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
        var location = _agentLocation.text.trim();
        if (location.isEmpty) {
          final point = await currentAgentLocation();
          if (point != null && point.trim().isNotEmpty) {
            location = point.trim();
            _agentLocation.text = location;
          }
        }
        final number = await AliraStoreOrders.representative(
          token: token,
          partyName: customer.name,
          partyPhone: customer.phone,
          partyAddress: '${customer.city} - ${customer.area}',
          paymentType: _payment,
          paidAmount: _payment == 'PARTIAL' ? partialPaid : null,
          partyId: customer.id,
          priceType: _apiPriceType,
          notes: location,
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
        _refreshQueue();
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
    if (!AliraCatalog.forceMock) {
      setState(() => _error = 'الكتالوج غير متصل بالسيرفر');
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

  String _liveText(
    TextEditingController controller,
    ValueNotifier<String> live,
  ) {
    final typed = live.value.trim();
    if (typed.isNotEmpty) {
      if (controller.text != live.value) {
        controller.value = TextEditingValue(
          text: live.value,
          selection: TextSelection.collapsed(offset: live.value.length),
        );
      }
      return typed;
    }
    return controller.text.trim();
  }

  Future<void> _login() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    final username = _usernameEdited
        ? _usernameLive.value.trim()
        : _liveText(_username, _usernameLive);
    final password = _passwordEdited
        ? _passwordLive.value
        : _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'أدخل اسم المستخدم وكلمة المرور');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = await _api.login(username, password);
      final representative = body['representative'];
      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _busy = false;
        _repName = representative is Map ? '${representative['name'] ?? ''}' : '';
        _applyAllowedPrices(representative);
      });
      await _persistLogin(username, password);
      await _refreshLiveRoutes();
      _refreshCeiling();
      _refreshQueue();
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
    if (!_rememberLogin) {
      _username.clear();
      _password.clear();
      _usernameLive.value = '';
      _passwordLive.value = '';
    }
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
      if (AliraCatalog.forceMock) {
        _mock.addOffice(name: name, phone: phone, address: address);
      } else {
        await _api.createOffice(name: name, phone: phone, address: address);
        final parts = address.split('-').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
        _routes?.customers.insert(
          0,
          AliraCustomer(
            id: 'office-${DateTime.now().microsecondsSinceEpoch}',
            name: name,
            city: parts.isEmpty ? address : parts.first,
            area: parts.length > 1 ? parts.sublist(1).join(' - ') : '',
            phone: phone,
            balance: 0,
            creditLimit: 0,
            allowedAmount: 0,
            agingDays: 0,
            cooperating: true,
          ),
        );
        final routes = _routes;
        if (routes != null) {
          routes.kpis.cooperating += 1;
          routes.kpis.visitsToday += 1;
          routes.kpis.remaining += 1;
        }
      }
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
            padding: const EdgeInsets.all(18),
            children: [
              const SizedBox(height: 12),
              AliraSoftCard(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('مرحباً بك', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text(
                      'يتصل بعنوان السيرفر المحفوظ في الإعدادات',
                      style: TextStyle(fontSize: 12, color: AliraColors.muted),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _username,
                      onChanged: (value) {
                        _usernameEdited = true;
                        _usernameLive.value = value;
                      },
                      decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      onChanged: (value) {
                        _passwordEdited = true;
                        _passwordLive.value = value;
                      },
                      onSubmitted: (_) {
                        if (!_busy) _login();
                      },
                      decoration: const InputDecoration(labelText: 'كلمة المرور'),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _rememberLogin,
                      activeColor: AliraColors.teal,
                      title: const Text('حفظ الدخول'),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) => setState(() => _rememberLogin = value ?? false),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!, style: const TextStyle(color: AliraColors.red, fontWeight: FontWeight.w700)),
                      ),
                    FilledButton(
                      onPressed: _busy ? null : _login,
                      child: Text(_busy ? 'جاري الدخول...' : 'تسجيل الدخول'),
                    ),
                  ],
                ),
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
        _queueBar(),
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
                    child: Text(_routeDateLabel(routes.date)),
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
                  OutlinedButton(onPressed: () => _openLedger(_Page.aging), child: const Text('أعمار الذمم')),
                  OutlinedButton(onPressed: () => _openLedger(_Page.statement), child: const Text('كشف حساب')),
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

  static const _priceOrder = ['wholesale', 'retail', 'representative', 'cost'];

  List<String> get _orderedPrices {
    return [
      for (final key in _priceOrder)
        if (_allowedPrices.contains(key)) key,
    ];
  }

  void _changeCart(String id, int delta) {
    if (delta > 0 && _apiPriceType == null) {
      setState(() => _error = 'حدد نوع سعر القائمة');
      return;
    }
    setState(() {
      final next = (_cart[id] ?? 0) + delta;
      if (next <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = next;
      }
      _error = null;
      _syncPaid();
    });
  }

  Widget _invoicePage() {
    final products = AliraCatalog.visible(
      familyId: _productSearch.text.trim().isEmpty ? _familyId : null,
      query: _productSearch.text,
    );
    return Column(
      children: [
        _invoiceTopBar(),
        _queueBar(),
        _orderHeader(),
        _ceilingBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _productSearch,
            onChanged: (value) {
              setState(() {
                if (value.trim().isNotEmpty) _familyId = null;
              });
              _scheduleProducts();
            },
            decoration: const InputDecoration(
              hintText: 'ابحث بالاسم',
              filled: true,
              fillColor: AliraColors.paper,
              prefixIcon: Icon(Icons.search, size: 20, color: AliraColors.teal),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            children: [
              AliraFilterChip(
                label: 'الكل',
                selected: _familyId == null,
                onTap: () {
                  setState(() => _familyId = null);
                  AliraCatalog.load(agent: true, query: _productSearch.text).then((_) {
                    if (mounted) setState(() {});
                  });
                },
              ),
              for (final family in AliraCatalog.families)
                AliraFilterChip(
                  label: family.name,
                  selected: _familyId == family.id,
                  onTap: () {
                    setState(() {
                      _familyId = _familyId == family.id ? null : family.id;
                      if (_familyId != null) _productSearch.clear();
                    });
                    AliraCatalog.load(
                      agent: true,
                      query: _productSearch.text,
                      familyId: _productSearch.text.trim().isEmpty ? _familyId : null,
                    ).then((_) {
                      if (mounted) setState(() {});
                    });
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? Center(
                  child: Text(
                    _productSearch.text.trim().isEmpty
                        ? 'لا توجد مواد في هذه العائلة'
                        : 'لا توجد مادة بهذا الاسم',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  children: [
                    for (final product in products) _agentProductCard(product),
                  ],
                ),
        ),
        if (AliraCatalog.hasNext)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: OutlinedButton(
              onPressed: AliraCatalog.loading ? null : _loadMoreProducts,
              child: Text(AliraCatalog.loading ? 'جارٍ التحميل...' : 'تحميل المزيد'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_cart.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('أضف مواد إلى السلة'),
                ),
              const Text('الدفع', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AliraColors.capsule,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    _payChip('نقداً', 'CASH'),
                    _payChip('آجل', 'CREDIT'),
                    _payChip('جزئي', 'PARTIAL'),
                  ],
                ),
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
              const SizedBox(height: 8),
              TextField(
                controller: _agentLocation,
                decoration: InputDecoration(
                  labelText: 'موقعك الآن',
                  hintText: 'يُرفق مع الطلب',
                  filled: true,
                  fillColor: AliraColors.paper,
                  suffixIcon: IconButton(
                    tooltip: 'موقعي الآن',
                    onPressed: _busy ? null : _captureLocation,
                    icon: const Icon(Icons.my_location_outlined),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: AliraColors.red)),
                ),
            ],
          ),
        ),
        _invoiceSendBar(),
      ],
    );
  }

  Widget _invoiceTopBar() {
    final hint = _invoiceOfficeHint();
    return Container(
      color: AliraColors.paper,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Row(
        children: [
          Material(
            color: const Color(0xFFF1F4F7),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _pop,
              borderRadius: BorderRadius.circular(14),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.arrow_forward_rounded, color: AliraColors.text),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'فاتورة جديدة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                if (hint.isNotEmpty)
                  Text(
                    hint,
                    style: const TextStyle(fontSize: 12, color: AliraColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _invoiceOfficeHint() {
    final link = _account?['link'];
    if (link is Map) {
      final office = '${link['office_name'] ?? ''}'.trim();
      if (office.isNotEmpty) return office;
    }
    final company = _account?['company'];
    if (company is Map) {
      final name = '${company['name'] ?? ''}'.trim();
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  Widget _agentProductCard(AliraProduct product) {
    final quantity = _cart[product.id] ?? 0;
    final wash = _cardWash(product.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AliraColors.paper,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 156,
            child: ColoredBox(
              color: wash,
              child: quantity > 0
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                        decoration: BoxDecoration(
                          color: AliraColors.teal,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '$quantity في السلة',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )
                  : aliraProductImage(
                      product.imageUrl,
                      fallback: const SizedBox.expand(),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  product.categoryName,
                  style: const TextStyle(fontSize: 12, color: AliraColors.muted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'IQD ${aliraMoney(_unitPrice(product))}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const Spacer(),
                    _agentQty(product.id, quantity),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _cardWash(String id) {
    const washes = [
      Color(0xFFE6D7C3),
      Color(0xFFF3C7B8),
      Color(0xFFD9E6DE),
      Color(0xFFF6E3C8),
      Color(0xFFE4D8C8),
    ];
    return washes[id.hashCode.abs() % washes.length];
  }

  Widget _agentQty(String id, int quantity) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _qtySquare(Icons.add, () => _changeCart(id, 1)),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              quantity == 0 ? '·' : '$quantity',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
          _qtySquare(
            Icons.remove,
            quantity == 0 ? null : () => _changeCart(id, -1),
          ),
        ],
      ),
    );
  }

  Widget _qtySquare(IconData icon, VoidCallback? onTap) {
    return Material(
      color: const Color(0xFFE7EEF2),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: onTap == null ? AliraColors.muted : AliraColors.teal),
        ),
      ),
    );
  }

  Widget _invoiceSendBar() {
    final count = _cart.values.fold<int>(0, (sum, quantity) => sum + quantity);
    return Container(
      color: AliraColors.paper,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'IQD ${aliraMoney(_cartTotal)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                Text(
                  '$count مواد',
                  style: const TextStyle(fontSize: 12, color: AliraColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy || _blockSend ? null : _sendSale,
            style: FilledButton.styleFrom(
              backgroundColor: AliraColors.teal,
              foregroundColor: Colors.white,
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('إرسال للمكتب', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _orderHeader() {
    final customers = _routes?.customers ?? const <AliraCustomer>[];
    final selectedId = customers.any((customer) => customer.id == _customer?.id) ? _customer?.id : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AliraSoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                hint: const Text('اختر الزبون'),
                value: selectedId,
                items: [
                  for (final customer in customers)
                    DropdownMenuItem(value: customer.id, child: Text(customer.name)),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  setState(() => _customer = customers.firstWhere((customer) => customer.id == id));
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final key in _orderedPrices)
                  AliraFilterChip(
                    label: _priceLabels[key] ?? key,
                    selected: _invoicePrice == key,
                    onTap: () => setState(() {
                      _invoicePrice = key;
                      _error = null;
                      _syncPaid();
                    }),
                  ),
              ],
            ),
          ),
          if (_apiPriceType == null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'حدد نوع السعر قبل فتح السلة',
                style: TextStyle(color: AliraColors.red, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _payChip(String label, String value) {
    final selected = _payment == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _payment = value;
          _syncPaid();
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AliraColors.teal : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : AliraColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openLedger(_Page page) async {
    final customer = _customer;
    if (customer == null) return;
    if (!AliraCatalog.forceMock) {
      try {
        final body = await _api.ledger(customer.id);
        if (!mounted) return;
        _serverAging = _agingFromLedger(customer, body);
        _statements[customer.id] = _statementFromLedger(customer, body);
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = AliraAgentApi.message(error));
        return;
      }
    }
    _push(page);
  }

  AliraAging _agingFromLedger(AliraCustomer customer, Map<String, dynamic> body) {
    final raw = body['invoices'];
    final invoices = <AliraInvoice>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final remaining = _asInt(item['remaining']);
        invoices.add(
          AliraInvoice(
            id: '${item['id']}',
            number: '${item['number'] ?? ''}',
            customerId: customer.id,
            type: '${item['bucket'] ?? 'BALANCE'}',
            date: '${item['date'] ?? ''}',
            amount: _asInt(item['amount']),
            remaining: remaining,
            ageDays: _asInt(item['age_days']),
            overdue: _asInt(item['age_days']) > 30 || remaining > 0,
          ),
        );
      }
    }
    return AliraAging(
      customer: customer,
      overdueCount: invoices.where((item) => item.overdue).length,
      allowedCount: 0,
      invoices: invoices,
    );
  }

  AliraStatement _statementFromLedger(AliraCustomer customer, Map<String, dynamic> body) {
    final report = _agingFromLedger(customer, body);
    final debit = report.invoices.fold<int>(0, (sum, item) => sum + item.remaining);
    return AliraStatement(
      customerId: customer.id,
      debit: debit,
      credit: 0,
      balance: debit,
      lastMovementDate: report.invoices.isEmpty ? null : report.invoices.last.date,
      entries: [
        for (final invoice in report.invoices)
          AliraStatementEntry(
            id: invoice.id,
            date: invoice.date,
            title: invoice.number,
            amount: invoice.remaining,
          ),
      ],
    );
  }

  Widget _agingPage() {
    final report = AliraCatalog.forceMock
        ? _mock.getAging(_customer!.id)
        : (_serverAging ??
            AliraAging(
              customer: _customer!,
              overdueCount: 0,
              allowedCount: 0,
              invoices: const [],
            ));
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
    final statement = AliraCatalog.forceMock
        ? _mock.getStatement(_customer!.id)
        : (_statements[_customer!.id] ??
            AliraStatement(
              customerId: _customer!.id,
              debit: 0,
              credit: 0,
              balance: _customer!.balance,
              lastMovementDate: null,
              entries: const [],
            ));
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
              _ceilingBanner(),
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
}
