import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/theme/app_theme.dart';

class OfficeActivityScreen extends StatefulWidget {
  const OfficeActivityScreen({super.key});

  @override
  State<OfficeActivityScreen> createState() => _OfficeActivityScreenState();
}

class _OfficeActivityScreenState extends State<OfficeActivityScreen> {
  Timer? _timer;
  bool _loading = true;
  String? _error;
  List<_Notice> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await AppServices.apiClient.get('/users/activity');
      final raw = response.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
      final items = <_Notice>[];
      for (final row in list) {
        if (row is Map) {
          items.add(_Notice.fromJson(Map<String, dynamic>.from(row)));
        }
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _openDetails(_Notice item) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _OperationPage(item: item),
      ),
    );
  }

  String _message(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 403) {
        return 'هذه الخانة للمسؤول على الحاسبة الأساسية.';
      }
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return '${data['message']}';
      }
    }
    return 'تعذر قراءة تغييرات الحاسبات الأخرى.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'خانة المسؤول',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'كل قائمة أو شراء أو تغيير مخزن أو زبون تسجّله حاسبة أخرى يظهر هنا. اضغط العملية لتفتح صفحتها بكل التفاصيل.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 16),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(child: Text(_error!, style: const TextStyle(color: AppTheme.dangerColor)));
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('لا توجد تغييرات من الحاسبات الأخرى بعد.'),
      );
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _items[index];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            title: Text(item.title),
            subtitle: Text('${item.actor} · ${item.detail}'),
            trailing: Text(item.amount ?? item.when),
            onTap: () => _openDetails(item),
          ),
        );
      },
    );
  }
}

class _Notice {
  final String id;
  final String kind;
  final String title;
  final String detail;
  final String actor;
  final String? amount;
  final String when;

  const _Notice({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.actor,
    required this.amount,
    required this.when,
  });

  factory _Notice.fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse('${json['at'] ?? ''}');
    final clock = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final amount = json['amount'];
    return _Notice(
      id: '${json['id'] ?? ''}',
      kind: '${json['kind'] ?? ''}',
      title: '${json['title'] ?? ''}',
      detail: '${json['detail'] ?? ''}',
      actor: '${json['actor'] ?? 'حاسبة أخرى'}',
      amount: amount == null || '$amount'.isEmpty ? null : '$amount',
      when: clock,
    );
  }
}

class _OperationPage extends StatefulWidget {
  final _Notice item;

  const _OperationPage({required this.item});

  @override
  State<_OperationPage> createState() => _OperationPageState();
}

class _OperationPageState extends State<_OperationPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _payload;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final item = widget.item;
    if (item.id.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final payload = item.kind == 'stock'
          ? await _loadStock(item.id)
          : await _loadRecord(_path(item));
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  String? _path(_Notice item) {
    return switch (item.kind) {
      'sale' => '/direct-sales/${item.id}',
      'purchase' => '/purchases/${item.id}',
      'customer' => '/customers/${item.id}',
      _ => null,
    };
  }

  Future<Map<String, dynamic>?> _loadRecord(String? path) async {
    if (path == null) return null;
    final response = await AppServices.apiClient.get(path);
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>?> _loadStock(String id) async {
    final response = await AppServices.apiClient.get(
      '/inventory/movements',
      queryParameters: {'page': 1, 'limit': 100},
    );
    final root = _unwrap(response.data) ?? _asMap(response.data);
    final rows = root['data'];
    if (rows is! List) return null;
    for (final row in rows) {
      if (row is Map && '${row['id']}' == id) {
        return Map<String, dynamic>.from(row);
      }
    }
    return null;
  }

  Map<String, dynamic>? _unwrap(dynamic raw) {
    if (raw is! Map) return null;
    final root = Map<String, dynamic>.from(raw);
    final data = root['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return root;
  }

  String _message(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) return '${data['message']}';
    }
    return 'تعذر فتح تفاصيل العملية.';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('تفاصيل العملية'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  item.title,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${item.actor} · ${item.when}',
                  style: const TextStyle(color: AppTheme.secondaryTextColor),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppTheme.dangerColor)),
                ],
                const SizedBox(height: 16),
                ..._sections(item, _payload),
              ],
            ),
    );
  }

  List<Widget> _sections(_Notice item, Map<String, dynamic>? payload) {
    if (payload == null) {
      return [
        _card([
          _line('الوصف', item.detail),
          if (item.amount != null) _line('المبلغ', _money(item.amount)),
        ]),
      ];
    }
    return switch (item.kind) {
      'sale' => _invoiceSections(payload, sale: true),
      'purchase' => _invoiceSections(payload, sale: false),
      'customer' => _customerSections(payload),
      'stock' => _stockSections(payload, item),
      _ => [
          _card([
            _line('الوصف', item.detail),
            if (item.amount != null) _line('المبلغ', _money(item.amount)),
          ]),
        ],
    };
  }

  List<Widget> _invoiceSections(Map<String, dynamic> payload, {required bool sale}) {
    final party = sale
        ? _asMap(payload['customers'] ?? payload['customer'])
        : _asMap(payload['supplier']);
    final warehouse = _asMap(payload['warehouses'] ?? payload['warehouse']);
    final rep = _asMap(payload['representatives']);
    final items = payload[sale ? 'sales_invoice_items' : 'purchase_invoice_items'];
    return [
      _card([
        _line('الرقم', '${payload['invoice_number'] ?? ''}'),
        _line('الحالة', _status('${payload['status'] ?? ''}')),
        _line('الدفع', _payment('${payload['payment_type'] ?? ''}')),
        if (sale) _line('نوع السعر', _price('${payload['price_type'] ?? ''}')),
        _line('التاريخ', _clock(payload['invoice_date'] ?? payload['created_at'])),
        if ('${payload['due_date'] ?? ''}'.isNotEmpty)
          _line('الاستحقاق', _clock(payload['due_date'])),
        _line(sale ? 'الزبون' : 'المورد', _person(party)),
        if (_text(party['phone']).isNotEmpty) _line('الهاتف', _text(party['phone'])),
        if (_text(party['address']).isNotEmpty) _line('العنوان', _text(party['address'])),
        _line('المخزن', _text(warehouse['name'])),
        if (_text(rep['name']).isNotEmpty) _line('المندوب', _text(rep['name'])),
        if (_text(payload['notes']).isNotEmpty) _line('ملاحظات', _text(payload['notes'])),
      ]),
      const SizedBox(height: 12),
      _card([
        _line('المجموع', _money(payload['subtotal'])),
        _line('الخصم', _money(payload['discount_amount'])),
        if (!sale) _line('الضريبة', _money(payload['tax_amount'])),
        _line('الإجمالي', _money(payload['total'])),
        _line('المدفوع', _money(payload['paid_amount'])),
        _line('المتبقي', _money(payload['due_amount'])),
      ]),
      const SizedBox(height: 12),
      _card([
        const Text('المواد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (items is! List || items.isEmpty)
          const Text('لا توجد مواد في هذه العملية.')
        else
          for (final row in items)
            if (row is Map) _itemRow(Map<String, dynamic>.from(row), sale: sale),
      ]),
    ];
  }

  Widget _itemRow(Map<String, dynamic> row, {required bool sale}) {
    final variant = _asMap(row['product_variants']);
    final product = _asMap(variant['products']);
    final unit = _asMap(row['units_of_measure']);
    final name = _text(product['name_ar']).isNotEmpty
        ? _text(product['name_ar'])
        : (_text(product['name']).isNotEmpty ? _text(product['name']) : 'مادة');
    final unitName = _text(unit['name_ar']).isNotEmpty
        ? _text(unit['name_ar'])
        : _text(unit['name']);
    final price = sale ? row['unit_price'] : (row['unit_cost'] ?? row['unit_price']);
    final total = row['total_price'] ?? row['total'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            'الكمية ${_qty(row['quantity'])}'
            '${unitName.isEmpty ? '' : ' $unitName'}'
            ' · السعر ${_money(price)}'
            ' · المجموع ${_money(total)}',
            style: const TextStyle(color: AppTheme.secondaryTextColor),
          ),
        ],
      ),
    );
  }

  List<Widget> _customerSections(Map<String, dynamic> payload) {
    final nested = payload['customer'];
    final customer = nested is Map ? _asMap(nested) : payload;
    final summary = _asMap(payload['summary']);
    final invoices = customer['sales_invoices'];
    return [
      _card([
        _line('الاسم', _text(customer['name'])),
        _line('الهاتف', _text(customer['phone'])),
        if (_text(customer['email']).isNotEmpty) _line('البريد', _text(customer['email'])),
        if (_text(customer['address']).isNotEmpty) _line('العنوان', _text(customer['address'])),
        _line('النوع', _customerType('${customer['type'] ?? ''}')),
        _line('الحالة', customer['is_active'] == false ? 'موقوف' : 'نشط'),
        if (_text(customer['notes']).isNotEmpty) _line('ملاحظات', _text(customer['notes'])),
        _line('أُضيف', _clock(customer['created_at'])),
      ]),
      const SizedBox(height: 12),
      _card([
        _line('الذمة', _money(summary['current_due'] ?? customer['balance'])),
        _line('سقف الدين', _money(customer['credit_limit'])),
        _line('مجموع القوائم', _money(summary['total_purchases'])),
        _line('المدفوع', _money(summary['total_paid'])),
      ]),
      const SizedBox(height: 12),
      _card([
        const Text('القوائم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (invoices is! List || invoices.isEmpty)
          const Text('لا توجد قوائم لهذا الزبون.')
        else
          for (final row in invoices)
            if (row is Map)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${row['invoice_number'] ?? ''} · ${_money(row['total'])} · ${_status('${row['status'] ?? ''}')} · ${_clock(row['invoice_date'])}',
                ),
              ),
      ]),
    ];
  }

  List<Widget> _stockSections(Map<String, dynamic> payload, _Notice item) {
    return [
      _card([
        _line('المادة', _text(payload['product_name'])),
        _line('الباركود', _text(payload['barcode'])),
        _line('المخزن', _text(payload['warehouse_name']).isEmpty ? item.detail : _text(payload['warehouse_name'])),
        _line('نوع الحركة', _movement('${payload['movement_type'] ?? ''}')),
        _line('الكمية', _qty(payload['quantity'])),
        _line('المرجع', _reference('${payload['reference_type'] ?? ''}')),
        if (_text(payload['notes']).isNotEmpty) _line('ملاحظات', _text(payload['notes'])),
        _line('المنفّذ', _text(payload['performed_by_name']).isEmpty ? item.actor : _text(payload['performed_by_name'])),
        _line('الوقت', _clock(payload['created_at'])),
      ]),
    ];
  }

  Widget _card(List<Widget> children) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    final shown = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AppTheme.secondaryTextColor)),
          ),
          Expanded(
            child: Text(shown, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  String _text(dynamic value) {
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') return '';
    return text;
  }

  String _money(dynamic value) {
    final text = _text(value);
    if (text.isEmpty) return '';
    final number = num.tryParse(text);
    if (number == null) return text;
    if (number == number.roundToDouble()) return number.toStringAsFixed(0);
    return number.toStringAsFixed(2);
  }

  String _qty(dynamic value) {
    final text = _money(value);
    return text.isEmpty ? '—' : text;
  }

  String _clock(dynamic value) {
    final at = DateTime.tryParse(_text(value));
    if (at == null) return _text(value);
    final local = at.toLocal();
    final date = '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date  $time';
  }

  String _payment(String raw) {
    return switch (raw.toUpperCase()) {
      'CASH' => 'نقداً',
      'CREDIT' => 'آجل',
      'PARTIAL' => 'جزئي',
      'REP_CUSTODY' => 'عهدة مندوب',
      _ => raw,
    };
  }

  String _status(String raw) {
    return switch (raw.toUpperCase()) {
      'DRAFT' => 'مسودة',
      'PAID' => 'مدفوعة',
      'PARTIAL' => 'جزئية',
      'OVERDUE' => 'متأخرة',
      'CANCELLED' => 'ملغاة',
      'RETURNED' => 'مرتجعة',
      'CONFIRMED' => 'مؤكدة',
      _ => raw,
    };
  }

  String _price(String raw) {
    return switch (raw.toUpperCase()) {
      'RETAIL' => 'مفرد',
      'WHOLESALE' => 'جملة',
      'REP' => 'مندوب',
      'COST' => 'كلفة',
      _ => raw,
    };
  }

  String _customerType(String raw) {
    return switch (raw.toUpperCase()) {
      'RETAIL' => 'مفرد',
      'WHOLESALE' => 'جملة',
      _ => raw,
    };
  }

  String _movement(String raw) {
    return switch (raw.toUpperCase()) {
      'IN' => 'إدخال',
      'OUT' => 'إخراج',
      'TRANSFER_OUT' => 'تحويل خروج',
      'TRANSFER_IN' => 'تحويل دخول',
      'ADJUST_ADD' => 'زيادة تسوية',
      'ADJUST_REDUCE' => 'نقص تسوية',
      'RETURN_IN' => 'مرتجع دخول',
      'RETURN_OUT' => 'مرتجع خروج',
      _ => raw,
    };
  }

  String _reference(String raw) {
    return switch (raw.toUpperCase()) {
      'PURCHASE_INVOICE' => 'فاتورة شراء',
      'SALE' || 'SALES_INVOICE' => 'قائمة بيع',
      'WAREHOUSE_TRANSFER' => 'نقل بين مخازن',
      'MANUAL_ADJUSTMENT' => 'تعديل يدوي',
      'REP_CUSTODY' => 'عهدة مندوب',
      '' => '—',
      _ => raw,
    };
  }

  String _person(Map<String, dynamic> party) {
    final name = _text(party['name']);
    return name.isEmpty ? _text(party['full_name']) : name;
  }
}
