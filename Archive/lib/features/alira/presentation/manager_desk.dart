import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/network/server_endpoint.dart';
import 'alira_frame.dart';

class ManagerDeskPage extends StatefulWidget {
  const ManagerDeskPage({super.key});

  @override
  State<ManagerDeskPage> createState() => _ManagerDeskPageState();
}

class _Choice {
  final String id;
  final String label;
  final IconData icon;
  final bool Function(Map<String, dynamic> order) match;

  const _Choice({
    required this.id,
    required this.label,
    required this.icon,
    required this.match,
  });
}

class _ManagerDeskPageState extends State<ManagerDeskPage> {
  final _email = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _dio = Dio(
    BaseOptions(
      baseUrl: ServerEndpoint.defaultInternet,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
    ),
  );

  String? _token;
  String? _message;
  String? _choice;
  bool _busy = false;
  List<Map<String, dynamic>> _orders = [];

  static final _choices = <_Choice>[
    _Choice(id: 'all', label: 'الكل', icon: Icons.grid_view_rounded, match: _any),
    _Choice(id: 'store', label: 'المتجر', icon: Icons.storefront_rounded, match: _store),
    _Choice(id: 'rep', label: 'المندوب', icon: Icons.badge_rounded, match: _rep),
    _Choice(id: 'wait', label: 'بانتظار', icon: Icons.hourglass_top_rounded, match: _wait),
    _Choice(id: 'ok', label: 'مقبول', icon: Icons.check_rounded, match: _ok),
    _Choice(id: 'no', label: 'مرفوض', icon: Icons.close_rounded, match: _no),
    _Choice(id: 'off', label: 'ملغي', icon: Icons.block_rounded, match: _off),
  ];

  static bool _any(Map<String, dynamic> _) => true;

  static bool _store(Map<String, dynamic> order) =>
      '${order['source'] ?? ''}'.toUpperCase() == 'GUEST';

  static bool _rep(Map<String, dynamic> order) =>
      '${order['source'] ?? ''}'.toUpperCase() == 'REPRESENTATIVE';

  static bool _wait(Map<String, dynamic> order) =>
      '${order['status'] ?? ''}'.toUpperCase() == 'SUBMITTED';

  static bool _ok(Map<String, dynamic> order) =>
      '${order['status'] ?? ''}'.toUpperCase() == 'ACCEPTED';

  static bool _no(Map<String, dynamic> order) =>
      '${order['status'] ?? ''}'.toUpperCase() == 'REJECTED';

  static bool _off(Map<String, dynamic> order) =>
      '${order['status'] ?? ''}'.toUpperCase() == 'CANCELLED';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {
          'email': _email.text.trim(),
          'password': _password.text,
        },
      );
      final token = response.data['accessToken']?.toString() ?? '';
      if (token.isEmpty) {
        throw StateError('تعذر الدخول.');
      }
      setState(() => _token = token);
      await _load();
    } catch (_) {
      setState(() => _message = 'بيانات الدخول غير صحيحة.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await _dio.get(
        '/admin/ecommerce/orders',
        queryParameters: {'page': 1, 'limit': 60},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final rows = response.data['data'];
      setState(() {
        _orders = [
          if (rows is List)
            for (final row in rows)
              if (row is Map) Map<String, dynamic>.from(row),
        ];
        _message = _orders.isEmpty ? 'لا توجد طلبات حالياً.' : null;
      });
    } catch (_) {
      setState(() => _message = 'تعذر جلب طلبات المتابعة.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AliraPhone(
      child: Column(
        children: [
          AliraStatusBar(
            title: 'متابعة مدير النظام',
            hint: _token == null ? 'دخول مختصر' : 'ملخص الطلبات',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          if (_busy)
            const LinearProgressIndicator(
              minHeight: 2,
              color: AliraColors.teal,
              backgroundColor: Color(0x220F4C45),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _token == null ? _loginBody() : _board(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
      children: [
        AliraSoftCard(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'دخول المدير',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'ملخص طلبات المتجر والمندوبين، والتفاصيل عند الاختيار.',
                style: TextStyle(fontSize: 12, color: AliraColors.muted, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'اسم الدخول'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                onSubmitted: (_) => _busy ? null : _login(),
                decoration: const InputDecoration(labelText: 'كلمة المرور'),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: const Text('دخول'),
              ),
            ],
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 14),
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AliraColors.red, fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
  }

  Widget _board() {
    final selected = _selectedChoice;
    final shown = selected == null
        ? const <Map<String, dynamic>>[]
        : _orders.where(selected.match).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_orders.length} طلباً',
                style: const TextStyle(fontSize: 13, color: AliraColors.muted, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh_rounded, color: AliraColors.teal),
            ),
          ],
        ),
        const Text(
          'اضغط أي اختيار لعرض التفاصيل',
          style: TextStyle(fontSize: 12, color: AliraColors.muted),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 640 ? 4 : 2;
            const gap = 10.0;
            final tile = (width - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final choice in _choices)
                  SizedBox(
                    width: tile,
                    child: _choiceTile(choice),
                  ),
              ],
            );
          },
        ),
        if (_message != null) ...[
          const SizedBox(height: 16),
          Text(_message!, style: const TextStyle(color: AliraColors.muted)),
        ],
        if (selected != null) ...[
          const SizedBox(height: 18),
          Text(
            selected.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const AliraSoftCard(
              child: Text(
                'لا توجد طلبات في هذا الاختيار.',
                style: TextStyle(color: AliraColors.muted),
              ),
            )
          else
            for (final order in shown) ...[
              _orderRow(order),
              const SizedBox(height: 8),
            ],
        ],
      ],
    );
  }

  _Choice? get _selectedChoice {
    for (final choice in _choices) {
      if (choice.id == _choice) return choice;
    }
    return null;
  }

  Widget _choiceTile(_Choice choice) {
    final count = _orders.where(choice.match).length;
    final selected = _choice == choice.id;
    return Material(
      color: selected ? AliraColors.teal : AliraColors.paper,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => setState(() => _choice = selected ? null : choice.id),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AliraColors.teal : AliraColors.line),
            boxShadow: const [
              BoxShadow(color: Color(0x100F4C45), blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Icon(
                choice.icon,
                size: 18,
                color: selected ? Colors.white : AliraColors.teal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  choice.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: selected ? Colors.white : AliraColors.text,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: selected ? Colors.white : AliraColors.teal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orderRow(Map<String, dynamic> order) {
    return Material(
      color: AliraColors.paper,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openDetails(order),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AliraColors.line),
          ),
          child: Row(
            children: [
              _statusDot(order),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _who(order),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_source(order)} · ${_shortNumber(order)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AliraColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _money(order['total']),
                style: const TextStyle(fontWeight: FontWeight.w800, color: AliraColors.teal),
              ),
              const Icon(Icons.chevron_left_rounded, color: AliraColors.muted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusDot(Map<String, dynamic> order) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: _statusColor(order), shape: BoxShape.circle),
    );
  }

  Future<void> _openDetails(Map<String, dynamic> order) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: _OrderDetails(order: order),
        );
      },
    );
  }
}

String _who(Map<String, dynamic> order) {
  final customer = order['customer'];
  if (customer is Map) {
    final name = '${customer['name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
  }
  final party = order['party'];
  if (party is Map) {
    final name = '${party['name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
  }
  final rep = order['representative'];
  if (rep is Map) {
    final name = '${rep['name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
  }
  return 'بدون اسم';
}

String _source(Map<String, dynamic> order) {
  switch ('${order['source'] ?? ''}'.toUpperCase()) {
    case 'GUEST':
      return 'متجر';
    case 'REPRESENTATIVE':
      return 'مندوب';
    default:
      return '${order['source'] ?? ''}';
  }
}

String _status(Map<String, dynamic> order) {
  switch ('${order['status'] ?? ''}'.toUpperCase()) {
    case 'SUBMITTED':
      return 'بانتظار المعالجة';
    case 'ACCEPTED':
      return 'مقبول';
    case 'REJECTED':
      return 'مرفوض';
    case 'CANCELLED':
      return 'ملغي';
    default:
      return '${order['status'] ?? ''}';
  }
}

Color _statusColor(Map<String, dynamic> order) {
  switch ('${order['status'] ?? ''}'.toUpperCase()) {
    case 'SUBMITTED':
      return AliraColors.orange;
    case 'ACCEPTED':
      return AliraColors.teal;
    case 'REJECTED':
      return AliraColors.red;
    default:
      return AliraColors.muted;
  }
}

String _shortNumber(Map<String, dynamic> order) {
  final number = '${order['order_number'] ?? ''}'.trim();
  if (number.length <= 12) return number;
  return number.substring(number.length - 8);
}

String _money(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  final digits = number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toStringAsFixed(0);
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class _OrderDetails extends StatelessWidget {
  final Map<String, dynamic> order;

  const _OrderDetails({required this.order});

  @override
  Widget build(BuildContext context) {
    final items = order['items'];
    final lines = items is List ? items.whereType<Map>().toList() : const <Map>[];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AliraColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AliraColors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _who(order),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(_source(order), AliraColors.teal),
                  _pill(_status(order), _statusColor(order)),
                  _pill(_payment(order), AliraColors.muted),
                ],
              ),
              const SizedBox(height: 14),
              AliraSoftCard(
                child: Column(
                  children: [
                    _line('رقم الطلب', '${order['order_number'] ?? ''}'),
                    _line('الهاتف', _phone(order)),
                    _line('العنوان', _address(order)),
                    _line('الوقت', _when(order['submitted_at'])),
                    if ('${order['notes'] ?? ''}'.trim().isNotEmpty)
                      _line('ملاحظة', '${order['notes']}'),
                    if ('${order['rejection_reason'] ?? ''}'.trim().isNotEmpty)
                      _line('سبب الرفض', '${order['rejection_reason']}'),
                    if ('${order['cancellation_reason'] ?? ''}'.trim().isNotEmpty)
                      _line('سبب الإلغاء', '${order['cancellation_reason']}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('المواد', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (lines.isEmpty)
                const AliraSoftCard(
                  child: Text('لا توجد مواد.', style: TextStyle(color: AliraColors.muted)),
                )
              else
                AliraSoftCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Column(
                    children: [
                      for (final item in lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item['product_name'] ?? ''}',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      '${_qty(item['quantity'])} ${item['unit_name'] ?? ''}'.trim(),
                                      style: const TextStyle(fontSize: 12, color: AliraColors.muted),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _money(item['line_total']),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              AliraSoftCard(
                child: Column(
                  children: [
                    _line('المجموع', _money(order['subtotal'])),
                    _line('الخصم', _money(order['discount_amount'])),
                    _line('الإجمالي', _money(order['total']), strong: true),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pill(String label, Color color) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

  Widget _line(String label, String value, {bool strong = false}) {
    final text = value.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: const TextStyle(color: AliraColors.muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _phone(Map<String, dynamic> order) {
    for (final key in ['customer', 'party', 'representative']) {
      final row = order[key];
      if (row is Map) {
        final phone = '${row['phone'] ?? ''}'.trim();
        if (phone.isNotEmpty) return phone;
      }
    }
    return '';
  }

  String _address(Map<String, dynamic> order) {
    final customer = order['customer'];
    if (customer is Map) {
      final address = '${customer['address'] ?? ''}'.trim();
      if (address.isNotEmpty) return address;
    }
    final party = order['party'];
    if (party is Map) {
      final address = '${party['address'] ?? ''}'.trim();
      if (address.isNotEmpty) return address;
    }
    final rep = order['representative'];
    if (rep is Map) {
      final address = '${rep['office_address'] ?? ''}'.trim();
      if (address.isNotEmpty) return address;
    }
    return '';
  }

  String _payment(Map<String, dynamic> order) {
    switch ('${order['payment_type'] ?? ''}'.toUpperCase()) {
      case 'CASH':
        return 'نقدي';
      case 'CREDIT':
        return 'آجل';
      case 'PARTIAL':
        return 'جزئي';
      default:
        return '${order['payment_type'] ?? ''}';
    }
  }

  String _when(dynamic value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return '';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.year}/${date.month}/${date.day}  $hour:$minute';
  }

  String _qty(dynamic value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toStringAsFixed(1);
  }
}
