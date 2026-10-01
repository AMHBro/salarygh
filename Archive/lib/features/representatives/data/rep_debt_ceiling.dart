import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/app_services.dart';

class RepDebtWarning {
  final String representativeId;
  final String name;
  final double totalDebt;
  final double maxDebtLimit;

  const RepDebtWarning({
    required this.representativeId,
    required this.name,
    required this.totalDebt,
    required this.maxDebtLimit,
  });

  String get message =>
      'تنبيه: مجموع ديون زبائن المندوب $name بلغت (${formatRepDebt(totalDebt)}) وتجاوزت السقف المسموح (${formatRepDebt(maxDebtLimit)})';
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

String formatRepDebt(num value) {
  final rounded = value.round();
  final negative = rounded < 0;
  final text = rounded.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(text[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

class RepDebtCeiling {
  static const _sql = '''
SELECT r.id, r.name, r.max_debt_limit AS max_debt_limit,
  COALESCE(d.total_debt, 0) AS total_debt
FROM representatives r
LEFT JOIN (
  SELECT rep_id, SUM(CASE WHEN bal > 0 THEN bal ELSE 0 END) AS total_debt
  FROM (
    SELECT c.representative_id AS rep_id,
      SUM(CASE
        WHEN e.type IN ('SALE', 'OPENING_BALANCE', 'PAYMENT')
          AND IFNULL(e.currency, 'IQD') != 'USD' THEN ABS(e.amount)
        WHEN e.type IN ('RECEIPT', 'REVERSAL')
          AND IFNULL(e.currency, 'IQD') != 'USD' THEN -ABS(e.amount)
        ELSE 0 END) AS bal
    FROM customers c
    LEFT JOIN customer_ledger_entries e ON e.customer_id = c.id
    WHERE c.deleted_at IS NULL
      AND c.representative_id IS NOT NULL
    GROUP BY c.id
  ) customer_balances
  GROUP BY rep_id
) d ON d.rep_id = r.id
WHERE r.deleted_at IS NULL
  AND r.max_debt_limit > 0
  AND COALESCE(d.total_debt, 0) > r.max_debt_limit
''';

  /// السحابة هي مصدر الرفض. الدفتر المحلي يُستخدم فقط إذا تعذر قراءة السيرفر.
  static Future<List<RepDebtWarning>?> _cloudExceeded() async {
    try {
      final response = await AppServices.apiClient.get(
        '/representatives/debt-ceilings',
        requiresBranch: false,
      );
      final body = response.data;
      final raw = body is Map && body['data'] is List ? body['data'] as List : null;
      if (raw == null) return null;
      final warnings = <RepDebtWarning>[];
      for (final item in raw) {
        if (item is! Map) continue;
        if (item['debt_ceiling_exceeded'] != true) continue;
        final name = '${item['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        warnings.add(
          RepDebtWarning(
            representativeId: '${item['id'] ?? ''}',
            name: name,
            totalDebt: _asDouble(item['customer_debt_total']),
            maxDebtLimit: _asDouble(item['max_debt_limit']),
          ),
        );
      }
      return warnings;
    } catch (_) {
      return null;
    }
  }

  static Future<List<RepDebtWarning>> _localExceeded(AppDatabase database) async {
    final rows = await database.customSelect(
      _sql,
      readsFrom: {
        database.representatives,
        database.customers,
        database.customerLedgerEntries,
      },
    ).get();

    return [
      for (final row in rows)
        RepDebtWarning(
          representativeId: row.read<String>('id'),
          name: row.read<String>('name'),
          totalDebt: _asDouble(row.data['total_debt']),
          maxDebtLimit: _asDouble(row.data['max_debt_limit']),
        ),
    ];
  }

  static Future<List<RepDebtWarning>> exceeded(AppDatabase database) async {
    final cloud = await _cloudExceeded();
    if (cloud != null) return cloud;
    return _localExceeded(database);
  }

  static Future<RepDebtWarning?> forRepresentative(
    AppDatabase database,
    String representativeId,
  ) async {
    var name = '';
    String? serverId;
    final rows = await database.customSelect(
      '''
SELECT name, server_id
FROM representatives
WHERE id = ? AND deleted_at IS NULL
''',
      variables: [Variable.withString(representativeId)],
    ).get();
    if (rows.isNotEmpty) {
      name = rows.first.read<String>('name');
      serverId = rows.first.read<String?>('server_id');
    }
    final warnings = await exceeded(database);
    for (final warning in warnings) {
      if (warning.representativeId == representativeId) return warning;
      if (serverId != null &&
          serverId.isNotEmpty &&
          warning.representativeId == serverId) {
        return warning;
      }
      if (name.isNotEmpty && warning.name.trim() == name.trim()) {
        return warning;
      }
    }
    return null;
  }

  static Future<List<String>> messagesForNames(
    AppDatabase database,
    Set<String> names,
  ) async {
    if (names.isEmpty) return const [];
    final wanted = names.map((name) => name.trim()).where((name) => name.isNotEmpty).toSet();
    final warnings = await exceeded(database);
    return [
      for (final warning in warnings)
        if (wanted.contains(warning.name.trim())) warning.message,
    ];
  }
}

class RepDebtBanner extends StatelessWidget {
  final String message;

  const RepDebtBanner({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE6A23C)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF8A5A00),
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
      ),
    );
  }
}
