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
      final items = <_Notice>[];
      if (raw is List) {
        for (final row in raw) {
          if (row is Map) {
            items.add(_Notice.fromJson(Map<String, dynamic>.from(row)));
          }
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
              'كل قائمة أو شراء أو تغيير مخزن أو زبون تسجّله حاسبة أخرى يظهر هنا حتى يبقى المسؤول على دراية.',
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
          ),
        );
      },
    );
  }
}

class _Notice {
  final String title;
  final String detail;
  final String actor;
  final String? amount;
  final String when;

  const _Notice({
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
      title: '${json['title'] ?? ''}',
      detail: '${json['detail'] ?? ''}',
      actor: '${json['actor'] ?? 'حاسبة أخرى'}',
      amount: amount == null || '$amount'.isEmpty ? null : '$amount',
      when: clock,
    );
  }
}
