import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/fx_books.dart';
import '../../../core/money/fx_math.dart';
import '../../products/data/products_local_repository.dart';

const _uuid = Uuid();

/// مبلغ دينار عراقي صحيح. الكسور تُرفض حتى لا يتحول المال إلى عدد عشري.
int? parseStaffDinars(String raw) {
  final text = raw.replaceAll(',', '').replaceAll(' ', '').trim();
  if (text.isEmpty || text.startsWith('-') || text.contains('.')) {
    return null;
  }
  final value = int.tryParse(text);
  if (value == null || value <= 0) {
    return null;
  }
  return value;
}

String staffDayKey(DateTime value) {
  final day = DateTime(value.year, value.month, value.day);
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$date';
}

class StaffEmployee {
  final String id;
  final String name;

  const StaffEmployee({
    required this.id,
    required this.name,
  });
}

class StaffExpense {
  final String id;
  final String employeeId;
  final String employeeName;
  final int amountIqd;
  final String note;
  final String spentOn;

  const StaffExpense({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.amountIqd,
    required this.note,
    required this.spentOn,
  });
}

class StaffLedger {
  StaffLedger(this.database);

  final AppDatabase database;

  Future<void> ensureTables() async {
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS staff_employees (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS staff_expenses (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        amount_iqd INTEGER NOT NULL CHECK (amount_iqd > 0),
        note TEXT NOT NULL DEFAULT '',
        spent_on TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS day_account_checks (
        day TEXT PRIMARY KEY,
        matched INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<List<StaffEmployee>> employees() async {
    await ensureTables();
    final rows = await database.customSelect('''
      SELECT id, name
      FROM staff_employees
      WHERE active = 1
      ORDER BY name
    ''').get();
    return [
      for (final row in rows)
        StaffEmployee(
          id: row.read<String>('id'),
          name: row.read<String>('name'),
        ),
    ];
  }

  Future<StaffEmployee> addEmployee(String name) async {
    await ensureTables();
    final clean = name.trim();
    if (clean.isEmpty) {
      throw StateError('اكتب اسم الموظف.');
    }
    final employee = StaffEmployee(id: _uuid.v4(), name: clean);
    await database.customInsert(
      '''
      INSERT INTO staff_employees (id, name, active, created_at)
      VALUES (?, ?, 1, ?)
      ''',
      variables: [
        Variable.withString(employee.id),
        Variable.withString(employee.name),
        Variable.withString(DateTime.now().toIso8601String()),
      ],
    );
    return employee;
  }

  Future<List<StaffExpense>> expensesFor(String employeeId) async {
    await ensureTables();
    final rows = await database.customSelect(
      '''
      SELECT e.id, e.employee_id, s.name AS employee_name,
             e.amount_iqd, e.note, e.spent_on
      FROM staff_expenses e
      JOIN staff_employees s ON s.id = e.employee_id
      WHERE e.employee_id = ?
      ORDER BY e.spent_on DESC, e.created_at DESC
      ''',
      variables: [Variable.withString(employeeId)],
    ).get();
    return rows.map(_expense).toList();
  }

  Future<void> addExpense({
    required String employeeId,
    required int amountIqd,
    required String spentOn,
    String note = '',
  }) async {
    await ensureTables();
    if (amountIqd <= 0) {
      throw StateError('مبلغ الصرف يجب أن يكون أكبر من صفر.');
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(spentOn)) {
      throw StateError('تاريخ الصرف غير صحيح.');
    }
    await database.customInsert(
      '''
      INSERT INTO staff_expenses (
        id, employee_id, amount_iqd, note, spent_on, created_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable.withString(_uuid.v4()),
        Variable.withString(employeeId),
        Variable.withInt(amountIqd),
        Variable.withString(note.trim()),
        Variable.withString(spentOn),
        Variable.withString(DateTime.now().toIso8601String()),
      ],
    );
  }

  Future<void> removeExpense(String id) async {
    await ensureTables();
    await database.customUpdate(
      'DELETE FROM staff_expenses WHERE id = ?',
      variables: [Variable.withString(id)],
    );
  }

  Future<void> setMatched(String day, bool matched) async {
    await ensureTables();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      throw StateError('اليوم غير صحيح.');
    }
    await database.customInsert(
      '''
      INSERT INTO day_account_checks (day, matched, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(day) DO UPDATE SET
        matched = excluded.matched,
        updated_at = excluded.updated_at
      ''',
      variables: [
        Variable.withString(day),
        Variable.withInt(matched ? 1 : 0),
        Variable.withString(DateTime.now().toIso8601String()),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> dailyProfit({
    DateTime? from,
    DateTime? to,
    int rateMillis = 0,
  }) async {
    await ensureTables();
    final bounds = _bounds(from, to);
    final books = FxBooks(database);
    final lineCosts = await books.lineCosts();
    final sales = await database.select(database.sales).get();
    final saleItems = await database.select(database.saleItems).get();
    final returns = await database.select(database.saleReturns).get();
    final returnItems = await database.select(database.saleReturnItems).get();
    final itemsBySale = <String, List<SaleItem>>{};
    final itemById = <String, SaleItem>{};
    for (final item in saleItems) {
      itemsBySale.putIfAbsent(item.saleId, () => []).add(item);
      itemById[item.id] = item;
    }
    final returnItemsByReturn = <String, List<SaleReturnItem>>{};
    for (final item in returnItems) {
      returnItemsByReturn.putIfAbsent(item.returnId, () => []).add(item);
    }

    final buckets = <String, _DayBucket>{
      for (final day in _days(bounds.$1, bounds.$2)) day: _DayBucket(),
    };

    for (final sale in sales) {
      if (sale.deletedAt != null || !_contains(sale.createdAt, bounds)) {
        continue;
      }
      var cost = 0;
      var replacement = 0;
      for (final item in itemsBySale[sale.id] ?? const <SaleItem>[]) {
        final frozen = lineCosts[item.id] ?? FrozenLineCost.zero;
        cost += frozen.costIqd;
        replacement += frozen.replacement(rateMillis);
      }
      final bucket = buckets.putIfAbsent(staffDayKey(sale.createdAt), _DayBucket.new);
      bucket.sales += sale.total;
      bucket.cost += cost;
      bucket.replacement += replacement;
    }

    for (final row in returns) {
      if (!_contains(row.createdAt, bounds)) {
        continue;
      }
      var cost = 0;
      var replacement = 0;
      for (final item in returnItemsByReturn[row.id] ?? const <SaleReturnItem>[]) {
        final sold = itemById[item.saleItemId];
        final frozen = lineCosts[item.saleItemId];
        if (sold == null || frozen == null) {
          continue;
        }
        final soldPieces = _pieces(sold.quantity, sold.unitFactor, sold.loosePieces);
        final share = _share(frozen, soldPieces, item.quantity);
        cost += share.costIqd;
        replacement += share.replacement(rateMillis);
      }
      final bucket = buckets.putIfAbsent(staffDayKey(row.createdAt), _DayBucket.new);
      bucket.sales -= row.total;
      bucket.cost -= cost;
      bucket.replacement -= replacement;
    }

    final settlements = await books.settlementsByDay(
      fromDay: staffDayKey(bounds.$1),
      toDay: staffDayKey(bounds.$2),
    );
    for (final entry in settlements.entries) {
      final bucket = buckets.putIfAbsent(entry.key, _DayBucket.new);
      bucket.fx = entry.value.differenceIqd;
      bucket.fxNote = entry.value.note;
    }

    final expenseRows = await database.customSelect(
      '''
      SELECT spent_on, SUM(amount_iqd) AS total
      FROM staff_expenses
      WHERE spent_on >= ? AND spent_on <= ?
      GROUP BY spent_on
      ''',
      variables: [
        Variable.withString(staffDayKey(bounds.$1)),
        Variable.withString(staffDayKey(bounds.$2)),
      ],
    ).get();
    for (final row in expenseRows) {
      final day = row.read<String>('spent_on');
      buckets.putIfAbsent(day, _DayBucket.new).expenses = row.read<int>('total');
    }

    final checks = await database.customSelect(
      '''
      SELECT day, matched
      FROM day_account_checks
      WHERE day >= ? AND day <= ?
      ''',
      variables: [
        Variable.withString(staffDayKey(bounds.$1)),
        Variable.withString(staffDayKey(bounds.$2)),
      ],
    ).get();
    final matchedByDay = {
      for (final row in checks)
        row.read<String>('day'): row.read<int>('matched') == 1,
    };

    final days = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    final rows = <Map<String, dynamic>>[];
    var salesSum = 0;
    var costSum = 0;
    var profitSum = 0;
    var replacementCostSum = 0;
    var replacementProfitSum = 0;
    var fxSum = 0;
    var expensesSum = 0;
    var netSum = 0;

    for (final day in days) {
      final bucket = buckets[day]!;
      final salesWhole = _whole(bucket.sales);
      final profitWhole = salesWhole - bucket.cost;
      final replacementProfit = salesWhole - bucket.replacement;
      final netWhole = profitWhole - bucket.expenses - bucket.fx;
      salesSum += salesWhole;
      costSum += bucket.cost;
      profitSum += profitWhole;
      replacementCostSum += bucket.replacement;
      replacementProfitSum += replacementProfit;
      fxSum += bucket.fx;
      expensesSum += bucket.expenses;
      netSum += netWhole;
      rows.add({
        'day': day,
        'sales_total': salesWhole,
        'cost_total': bucket.cost,
        'profit_total': profitWhole,
        'replacement_cost': bucket.replacement,
        'replacement_profit': replacementProfit,
        'fx_difference': bucket.fx,
        'fx_note': bucket.fxNote.isEmpty ? '—' : bucket.fxNote,
        'expenses_total': bucket.expenses,
        'net_total': netWhole,
        'profit_percent': marginLabel(profitWhole, bucket.cost),
        'account_status': _status(matchedByDay[day]),
      });
    }

    if (rows.length > 1) {
      rows.add({
        'day': 'المجموع',
        'sales_total': salesSum,
        'cost_total': costSum,
        'profit_total': profitSum,
        'replacement_cost': replacementCostSum,
        'replacement_profit': replacementProfitSum,
        'fx_difference': fxSum,
        'fx_note': '—',
        'expenses_total': expensesSum,
        'net_total': netSum,
        'profit_percent': marginLabel(profitSum, costSum),
        'account_status': '—',
      });
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> expensesReport({
    DateTime? from,
    DateTime? to,
  }) async {
    await ensureTables();
    final bounds = _bounds(from, to);
    final rows = await database.customSelect(
      '''
      SELECT e.spent_on, s.name AS employee_name, e.amount_iqd, e.note
      FROM staff_expenses e
      JOIN staff_employees s ON s.id = e.employee_id
      WHERE e.spent_on >= ? AND e.spent_on <= ?
      ORDER BY e.spent_on DESC, s.name
      ''',
      variables: [
        Variable.withString(staffDayKey(bounds.$1)),
        Variable.withString(staffDayKey(bounds.$2)),
      ],
    ).get();

    final report = <Map<String, dynamic>>[];
    var total = 0;
    for (final row in rows) {
      final amount = row.read<int>('amount_iqd');
      total += amount;
      report.add({
        'day': row.read<String>('spent_on'),
        'employee_name': row.read<String>('employee_name'),
        'expense_amount': amount,
        'expense_note': row.read<String>('note'),
      });
    }
    if (report.length > 1) {
      report.add({
        'day': 'المجموع',
        'employee_name': '',
        'expense_amount': total,
        'expense_note': '',
      });
    }
    return report;
  }

  StaffExpense _expense(QueryRow row) {
    return StaffExpense(
      id: row.read<String>('id'),
      employeeId: row.read<String>('employee_id'),
      employeeName: row.read<String>('employee_name'),
      amountIqd: row.read<int>('amount_iqd'),
      note: row.read<String>('note'),
      spentOn: row.read<String>('spent_on'),
    );
  }
}

class _DayBucket {
  double sales = 0;
  int cost = 0;
  int replacement = 0;
  int fx = 0;
  String fxNote = '';
  int expenses = 0;
}

double _pieces(double quantity, double factor, int loose) {
  final cartons = quantity < 0 ? 0.0 : quantity;
  final unit = factor <= 0 ? 1.0 : factor;
  final extra = loose < 0 ? 0 : loose;
  return cartons * unit + extra;
}

FrozenLineCost _share(FrozenLineCost line, double soldPieces, double returnedPieces) {
  final sold = moneyMinor(soldPieces);
  final returned = moneyMinor(returnedPieces);
  if (sold <= 0 || returned <= 0) {
    return FrozenLineCost.zero;
  }
  return FrozenLineCost(
    costIqd: mulDivHalfUp(line.costIqd, returned, sold),
    usdMinor: mulDivHalfUp(line.usdMinor, returned, sold),
    usdBookIqd: mulDivHalfUp(line.usdBookIqd, returned, sold),
  );
}

int _whole(double value) {
  if (value.isNaN || value.isInfinite) {
    return 0;
  }
  return value.round();
}

String _status(bool? matched) {
  if (matched == null) {
    return 'لم يُحدد';
  }
  return matched ? 'مطابق' : 'غير مطابق';
}

(DateTime, DateTime) _bounds(DateTime? from, DateTime? to) {
  final today = DateTime.now();
  final start = DateTime(
    (from ?? to ?? today).year,
    (from ?? to ?? today).month,
    (from ?? to ?? today).day,
  );
  final endSource = to ?? from ?? today;
  final end = DateTime(endSource.year, endSource.month, endSource.day);
  if (end.isBefore(start)) {
    return (end, start);
  }
  return (start, end);
}

List<String> _days(DateTime start, DateTime end) {
  final keys = <String>[];
  var cursor = start;
  while (!cursor.isAfter(end)) {
    keys.add(staffDayKey(cursor));
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
  return keys;
}

bool _contains(DateTime value, (DateTime, DateTime) bounds) {
  final day = DateTime(value.year, value.month, value.day);
  return !day.isBefore(bounds.$1) && !day.isAfter(bounds.$2);
}
