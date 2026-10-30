import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

const invoiceHoldPrefix = 'البيع معلق.';
const managementReleaseMark = 'سُمح بالبيع بقرار الإدارة';

class OverdueInvoiceHold {
  final String number;
  final int ageDays;

  const OverdueInvoiceHold({
    required this.number,
    required this.ageDays,
  });
}

class OpenInvoiceAge {
  final String number;
  final DateTime createdAt;
  final double remaining;

  const OpenInvoiceAge({
    required this.number,
    required this.createdAt,
    required this.remaining,
  });
}

int parseInvoiceBlockDays(Object? raw) {
  final parsed = raw is num
      ? raw.toDouble()
      : double.tryParse('${raw ?? ''}'.trim().replaceAll(',', '')) ?? 0;
  if (parsed <= 0 || !parsed.isFinite) {
    return 0;
  }
  return parsed.floor();
}

int invoiceAgeDays(DateTime invoiceDate, DateTime now) {
  final start = DateTime(invoiceDate.year, invoiceDate.month, invoiceDate.day);
  final end = DateTime(now.year, now.month, now.day);
  final days = end.difference(start).inDays;
  return days < 0 ? 0 : days;
}

OverdueInvoiceHold? findOverdueHold(
  List<OpenInvoiceAge> invoices,
  int blockDays, {
  DateTime? now,
}) {
  if (blockDays <= 0) {
    return null;
  }
  final today = now ?? DateTime.now();
  OverdueInvoiceHold? oldest;
  for (final invoice in invoices) {
    if (invoice.remaining <= 0.001) {
      continue;
    }
    final days = invoiceAgeDays(invoice.createdAt, today);
    if (days <= blockDays) {
      continue;
    }
    if (oldest == null || days > oldest.ageDays) {
      oldest = OverdueInvoiceHold(number: invoice.number, ageDays: days);
    }
  }
  return oldest;
}

String invoiceHoldMessage(OverdueInvoiceHold hold) {
  return '$invoiceHoldPrefix فاتورة ${hold.number} غير مسددة وعمرها ${hold.ageDays} يوم. لا يُستأنف البيع إلا بقرار الإدارة.';
}

String withManagementRelease(String notes, OverdueInvoiceHold hold) {
  final line =
      '$managementReleaseMark رغم فاتورة ${hold.number} غير مسددة عمرها ${hold.ageDays} يوم.';
  final current = notes.trim();
  if (current.contains(managementReleaseMark)) {
    return current;
  }
  if (current.isEmpty) {
    return line;
  }
  return '$current\n$line';
}

class InvoiceHoldStore {
  static const _key = 'invoice_block_days';

  static Future<int> read(AppDatabase database) async {
    try {
      final row = await database.customSelect(
        'SELECT value FROM office_prefs WHERE key = ?',
        variables: [Variable.withString(_key)],
      ).getSingleOrNull();
      return parseInvoiceBlockDays(row?.data['value']);
    } catch (_) {
      return 0;
    }
  }

  static Future<void> write(AppDatabase database, int days) async {
    await database.customStatement(
      '''
INSERT INTO office_prefs (key, value) VALUES (?, ?)
ON CONFLICT(key) DO UPDATE SET value = excluded.value
''',
      [_key, '${days < 0 ? 0 : days}'],
    );
  }
}
