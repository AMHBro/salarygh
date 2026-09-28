import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../reports/data/local_statements_repository.dart';
import '../../settings/data/company_settings_repository.dart';

class CapitalScreen extends StatefulWidget {
  const CapitalScreen({super.key});

  @override
  State<CapitalScreen> createState() => _CapitalScreenState();
}

class _CapitalScreenState extends State<CapitalScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final opening = await CompanySettingsRepository(
        apiClient: AppServices.apiClient,
      ).readOpeningCapital();
      final rows = await LocalStatementsRepository(
        customersRepository: AppServices.customersRepository,
        salesRepository: AppServices.salesRepository,
        database: AppServices.database,
      ).capitalStatement(openingCapital: opening);
      if (!mounted) {
        return;
      }
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _rows.isEmpty ? null : _rows.last;
    final capital = last == null ? 0.0 : _number(last['capital_balance']);
    final profit = _rows.fold<double>(
      0,
      (sum, row) {
        if (row['operation_type'] == 'رأس مال') {
          return sum;
        }
        return sum + _number(row['profit_iqd']);
      },
    );

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(30, 28, 30, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'رأس المال',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryTextColor,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'يبدأ من المبلغ في الإعدادات. البيع يضيف الربح أو يخصم الخسارة. الشراء والقبض والصرف تظهر ولا تغير رأس المال. الدولار يتحول للدينار بسعر الإعدادات.',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: AppTheme.secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('تحديث'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    )
                  else ...[
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _CapitalCard(
                          title: 'رأس المال الآن',
                          value: _money(capital),
                          emphasized: true,
                        ),
                        _CapitalCard(
                          title: 'الأرباح والخسائر',
                          value: _money(profit),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: _rows.isEmpty
                          ? const SizedBox.shrink()
                          : ListView.separated(
                              itemCount: _rows.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final row = _rows[index];
                                return ListTile(
                                  title: Text(
                                    '${row['operation_type']}  ${row['reference_number'] ?? ''}'
                                        .trim(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${row['party_name'] ?? ''}  ${row['effect_note'] ?? ''}'
                                        .trim(),
                                  ),
                                  trailing: Text(
                                    _money(row['capital_balance']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  double _number(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  String _money(Object? value) {
    return '${_number(value).toStringAsFixed(0)} د.ع';
  }
}

class _CapitalCard extends StatelessWidget {
  final String title;
  final String value;
  final bool emphasized;

  const _CapitalCard({
    required this.title,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: emphasized ? AppTheme.primaryColor : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: emphasized ? Colors.white70 : AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: emphasized ? Colors.white : AppTheme.primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}
