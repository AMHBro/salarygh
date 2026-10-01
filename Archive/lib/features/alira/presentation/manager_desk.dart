import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ManagerDeskPage extends StatefulWidget {
  const ManagerDeskPage({super.key});

  @override
  State<ManagerDeskPage> createState() => _ManagerDeskPageState();
}

class _ManagerDeskPageState extends State<ManagerDeskPage> {
  final _email = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _dio = Dio(
    BaseOptions(
      baseUrl: 'https://salarygh-production.up.railway.app/api/v1',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
    ),
  );

  String? _token;
  String? _message;
  bool _busy = false;
  List<Map<String, dynamic>> _orders = [];

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
        queryParameters: {'page': 1, 'limit': 40},
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
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('متابعة مدير النظام'),
        actions: [
          if (_token != null)
            IconButton(
              tooltip: 'تحديث',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_token == null) ...[
            const Text('ادخل بحساب المدير لمتابعة طلبات المتجر والمندوبين.'),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'اسم الدخول'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة المرور'),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: const Text('دخول المدير'),
            ),
          ] else ...[
            Text('الطلبات الظاهرة: ${_orders.length}'),
            const SizedBox(height: 12),
            for (final order in _orders)
              Card(
                child: ListTile(
                  title: Text('${order['order_number'] ?? ''}'),
                  subtitle: Text(
                    '${_who(order)}\n${_source(order)} · ${_status(order)} · ${_total(order)}',
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!),
          ],
        ],
      ),
    );
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

  String _total(Map<String, dynamic> order) {
    final total = order['total'];
    if (total == null) return '';
    return '$total';
  }
}
