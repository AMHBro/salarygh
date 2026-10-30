import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'fx_math.dart';

const _uuid = Uuid();

class FrozenLineCost {
  final int costIqd;
  final int usdMinor;
  final int usdBookIqd;

  const FrozenLineCost({
    required this.costIqd,
    required this.usdMinor,
    required this.usdBookIqd,
  });

  static const zero = FrozenLineCost(
    costIqd: 0,
    usdMinor: 0,
    usdBookIqd: 0,
  );

  int replacement(int rateMillis) {
    return replacementIqd(
      costIqd: costIqd,
      usdMinor: usdMinor,
      usdBookIqd: usdBookIqd,
      rateMillis: rateMillis,
    );
  }
}

class FxDaySettlement {
  final int differenceIqd;
  final String note;

  const FxDaySettlement({
    required this.differenceIqd,
    required this.note,
  });
}

/// كلفة البيع تُثبَّت وقت الفاتورة، وطبقة الدولار تُحفظ منفصلة عن متوسط الدينار.
class FxBooks {
  FxBooks(this.database);

  final AppDatabase database;

  Future<void> ensureTables() async {
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS sale_line_costs (
        sale_item_id TEXT PRIMARY KEY,
        cost_iqd INTEGER NOT NULL,
        usd_minor INTEGER NOT NULL,
        usd_book_iqd INTEGER NOT NULL
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS variant_usd_costs (
        variant_id TEXT PRIMARY KEY,
        cost_usd_minor INTEGER NOT NULL,
        pieces_minor INTEGER NOT NULL
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS ledger_fx (
        entry_id TEXT PRIMARY KEY,
        supplier_id TEXT NOT NULL,
        open_minor INTEGER NOT NULL,
        rate_millis INTEGER NOT NULL,
        booked_on TEXT NOT NULL
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS fx_results (
        id TEXT PRIMARY KEY,
        payment_entry_id TEXT NOT NULL,
        supplier_id TEXT NOT NULL,
        booked_on TEXT NOT NULL,
        usd_minor INTEGER NOT NULL,
        debt_rate_millis INTEGER NOT NULL,
        pay_rate_millis INTEGER NOT NULL,
        difference_iqd INTEGER NOT NULL,
        note TEXT NOT NULL
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS fx_meta (
        id TEXT PRIMARY KEY,
        rate_millis INTEGER NOT NULL
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS fx_payment_claims (
        entry_id TEXT PRIMARY KEY
      )
    ''');
  }

  Future<void> rememberRate(num rate) async {
    final millis = moneyMinor(rate);
    if (millis <= 0) {
      return;
    }
    await ensureTables();
    await database.customInsert(
      '''
      INSERT INTO fx_meta (id, rate_millis) VALUES ('usd', ?)
      ON CONFLICT(id) DO UPDATE SET rate_millis = excluded.rate_millis
      ''',
      variables: [Variable.withInt(millis)],
    );
  }

  Future<int> savedRateMillis() async {
    await ensureTables();
    final rows = await database.customSelect(
      "SELECT rate_millis FROM fx_meta WHERE id = 'usd'",
    ).get();
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first.read<int>('rate_millis');
  }

  Future<void> freezeSaleLine({
    required String saleItemId,
    required double pieces,
    required double pieceCostIqd,
  }) async {
    await ensureTables();
    if (await _line(saleItemId) != null) {
      return;
    }
    final piecesMinor = moneyMinor(pieces);
    final cost = lineCostIqd(piecesMinor, moneyMinor(pieceCostIqd));
    final variantId = await _variantOfItem(saleItemId);
    var usd = 0;
    var usdBook = 0;
    if (variantId != null && piecesMinor > 0) {
      final layer = await _layer(variantId);
      final taken = takeUsdPieces(
        layerPieces: layer.$1,
        onHandPieces: await _onHandMinor(variantId),
        soldPieces: piecesMinor,
      );
      if (taken > 0 && layer.$2 > 0) {
        usd = usdMinorForPieces(taken, layer.$2);
        final share = mulDivHalfUp(cost, taken, piecesMinor);
        usdBook = share > cost ? cost : share;
        final left = layer.$1 - taken;
        if (left <= 0) {
          await database.customUpdate(
            'DELETE FROM variant_usd_costs WHERE variant_id = ?',
            variables: [Variable.withString(variantId)],
          );
        } else {
          await _writeLayer(variantId, left, layer.$2);
        }
      }
    }
    await _insertLine(
      saleItemId,
      FrozenLineCost(costIqd: cost, usdMinor: usd, usdBookIqd: usdBook),
    );
  }

  Future<void> addUsdPurchase({
    required String variantId,
    required double addedPieces,
    required double usdPerPiece,
  }) async {
    await ensureTables();
    final addPieces = moneyMinor(addedPieces);
    final addCost = moneyMinor(usdPerPiece);
    if (addPieces <= 0 || addCost <= 0) {
      return;
    }
    final current = await _layer(variantId);
    final cost = blendAverage(
      oldPieces: current.$1,
      oldCost: current.$2,
      addPieces: addPieces,
      addCost: addCost,
    );
    await _writeLayer(variantId, current.$1 + addPieces, cost);
  }

  Future<void> restoreReturn({
    required String variantId,
    required String saleItemId,
    required double soldPieces,
    required double returnedPieces,
  }) async {
    await ensureTables();
    final line = await _line(saleItemId);
    if (line == null || line.usdMinor <= 0) {
      return;
    }
    final sold = moneyMinor(soldPieces);
    final returned = moneyMinor(returnedPieces);
    if (sold <= 0 || returned <= 0) {
      return;
    }
    final usd = mulDivHalfUp(line.usdMinor, returned, sold);
    if (usd <= 0) {
      return;
    }
    final perPiece = mulDivHalfUp(usd, 1000, returned);
    final current = await _layer(variantId);
    final cost = blendAverage(
      oldPieces: current.$1,
      oldCost: current.$2,
      addPieces: returned,
      addCost: perPiece,
    );
    await _writeLayer(variantId, current.$1 + returned, cost);
  }

  Future<void> openSupplierDebt({
    required String entryId,
    required String supplierId,
    required double usdAmount,
    required double rate,
    required DateTime bookedOn,
  }) async {
    await ensureTables();
    final amount = moneyMinor(usdAmount);
    final rateMillis = moneyMinor(rate);
    if (amount <= 0 || rateMillis <= 0) {
      return;
    }
    await rememberRate(rate);
    await database.customInsert(
      '''
      INSERT INTO ledger_fx (
        entry_id, supplier_id, open_minor, rate_millis, booked_on
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(entry_id) DO NOTHING
      ''',
      variables: [
        Variable.withString(entryId),
        Variable.withString(supplierId),
        Variable.withInt(amount),
        Variable.withInt(rateMillis),
        Variable.withString(bookedOn.toIso8601String()),
      ],
    );
  }

  Future<void> settleSupplierPayment({
    required String entryId,
    required String supplierId,
    required double usdAmount,
    required double rate,
    required DateTime bookedOn,
  }) async {
    await ensureTables();
    final claimed = await database.customSelect(
      'SELECT entry_id FROM fx_payment_claims WHERE entry_id = ?',
      variables: [Variable.withString(entryId)],
    ).get();
    if (claimed.isNotEmpty) {
      final done = await database.customSelect(
        'SELECT id FROM fx_results WHERE payment_entry_id = ? LIMIT 1',
        variables: [Variable.withString(entryId)],
      ).get();
      if (done.isNotEmpty) {
        return;
      }
    } else {
      await database.customInsert(
        'INSERT INTO fx_payment_claims (entry_id) VALUES (?)',
        variables: [Variable.withString(entryId)],
      );
    }
    await backfillOpenDebts();
    var left = moneyMinor(usdAmount);
    final payRate = moneyMinor(rate);
    if (left <= 0 || payRate <= 0) {
      return;
    }
    await rememberRate(rate);
    final debts = await database.customSelect(
      '''
      SELECT entry_id, open_minor, rate_millis
      FROM ledger_fx
      WHERE supplier_id = ? AND open_minor > 0
      ORDER BY booked_on, entry_id
      ''',
      variables: [Variable.withString(supplierId)],
    ).get();
    for (final debt in debts) {
      if (left <= 0) {
        break;
      }
      final open = debt.read<int>('open_minor');
      final take = left < open ? left : open;
      final debtRate = debt.read<int>('rate_millis');
      final difference = fxDifferenceIqd(
        usdMinor: take,
        debtRateMillis: debtRate,
        payRateMillis: payRate,
      );
      await database.customUpdate(
        'UPDATE ledger_fx SET open_minor = ? WHERE entry_id = ?',
        variables: [
          Variable.withInt(open - take),
          Variable.withString(debt.read<String>('entry_id')),
        ],
      );
      await database.customInsert(
        '''
        INSERT INTO fx_results (
          id, payment_entry_id, supplier_id, booked_on, usd_minor,
          debt_rate_millis, pay_rate_millis, difference_iqd, note
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: [
          Variable.withString(_uuid.v4()),
          Variable.withString(entryId),
          Variable.withString(supplierId),
          Variable.withString(bookedOn.toIso8601String()),
          Variable.withInt(take),
          Variable.withInt(debtRate),
          Variable.withInt(payRate),
          Variable.withInt(difference),
          Variable.withString(fxMovementNote(debtRate, payRate)),
        ],
      );
      left -= take;
    }
  }

  Future<void> backfillOpenDebts() async {
    await ensureTables();
    final purchases = await database.select(database.purchases).get();
    final purchaseById = {for (final row in purchases) row.id: row};
    final claimedRows = await database.customSelect(
      'SELECT entry_id FROM fx_payment_claims',
    ).get();
    final claimed = {
      for (final row in claimedRows) row.read<String>('entry_id'),
    };
    final entries = await database.select(database.supplierLedgerEntries).get();
    final debts = <SupplierLedgerEntry>[];
    final payments = <SupplierLedgerEntry>[];
    for (final entry in entries) {
      if (entry.currency != 'USD') {
        continue;
      }
      if (entry.type == 'PURCHASE') {
        debts.add(entry);
      } else if (entry.type == 'PAYMENT' && !claimed.contains(entry.id)) {
        payments.add(entry);
      }
    }
    final openByEntry = <String, int>{};
    final supplierIds = <String>{
      for (final debt in debts) debt.supplierId,
    };
    for (final supplierId in supplierIds) {
      final supplierDebts = [
        for (final debt in debts)
          if (debt.supplierId == supplierId) debt,
      ]..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
      final supplierPayments = [
        for (final row in payments)
          if (row.supplierId == supplierId) row,
      ]..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
      final paymentAmounts = [
        for (final row in supplierPayments) moneyMinor(row.amount),
      ];
      var payIndex = 0;
      var payRemain = paymentAmounts.isEmpty ? 0 : paymentAmounts.first;
      for (final debt in supplierDebts) {
        var open = moneyMinor(debt.amount);
        while (open > 0 && payIndex < paymentAmounts.length) {
          final take = open < payRemain ? open : payRemain;
          open -= take;
          payRemain -= take;
          if (payRemain <= 0) {
            payIndex++;
            payRemain = payIndex < paymentAmounts.length
                ? paymentAmounts[payIndex]
                : 0;
          }
        }
        openByEntry[debt.id] = open;
      }
    }
    for (final debt in debts) {
      final open = openByEntry[debt.id] ?? 0;
      if (open <= 0) {
        continue;
      }
      final purchase = purchaseById[debt.referenceId ?? ''];
      final rate = purchase?.exchangeRate ?? 0;
      if (rate <= 0) {
        continue;
      }
      await database.customInsert(
        '''
        INSERT INTO ledger_fx (
          entry_id, supplier_id, open_minor, rate_millis, booked_on
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(entry_id) DO NOTHING
        ''',
        variables: [
          Variable.withString(debt.id),
          Variable.withString(debt.supplierId),
          Variable.withInt(open),
          Variable.withInt(moneyMinor(rate)),
          Variable.withString(debt.createdAt.toIso8601String()),
        ],
      );
    }
  }

  Future<void> backfillSaleCosts() async {
    await ensureTables();
    final items = await database.select(database.saleItems).get();
    final known = await database.customSelect(
      'SELECT sale_item_id FROM sale_line_costs',
    ).get();
    final have = {for (final row in known) row.read<String>('sale_item_id')};
    final variants = await database.select(database.productVariants).get();
    final costByVariant = {
      for (final variant in variants) variant.id: variant.costPrice,
    };
    for (final item in items) {
      if (have.contains(item.id)) {
        continue;
      }
      final pieces = _pieces(item.quantity, item.unitFactor, item.loosePieces);
      final pieceCost = costByVariant[item.variantId] ?? 0;
      await _insertLine(
        item.id,
        FrozenLineCost(
          costIqd: lineCostIqd(moneyMinor(pieces), moneyMinor(pieceCost)),
          usdMinor: 0,
          usdBookIqd: 0,
        ),
      );
    }
  }

  Future<Map<String, FrozenLineCost>> lineCosts() async {
    await backfillSaleCosts();
    final rows = await database.customSelect(
      '''
      SELECT sale_item_id, cost_iqd, usd_minor, usd_book_iqd
      FROM sale_line_costs
      ''',
    ).get();
    return {
      for (final row in rows)
        row.read<String>('sale_item_id'): FrozenLineCost(
          costIqd: row.read<int>('cost_iqd'),
          usdMinor: row.read<int>('usd_minor'),
          usdBookIqd: row.read<int>('usd_book_iqd'),
        ),
    };
  }

  Future<Map<String, FxDaySettlement>> settlementsByDay({
    required String fromDay,
    required String toDay,
  }) async {
    await ensureTables();
    final rows = await database.customSelect(
      '''
      SELECT booked_on, difference_iqd, note
      FROM fx_results
      ''',
    ).get();
    final totals = <String, int>{};
    final notes = <String, List<String>>{};
    for (final row in rows) {
      final booked = DateTime.tryParse(row.read<String>('booked_on'));
      if (booked == null) {
        continue;
      }
      final day = _dayKey(booked);
      if (day.compareTo(fromDay) < 0 || day.compareTo(toDay) > 0) {
        continue;
      }
      totals[day] = (totals[day] ?? 0) + row.read<int>('difference_iqd');
      final note = row.read<String>('note');
      if (note.isNotEmpty) {
        notes.putIfAbsent(day, () => []).add(note);
      }
    }
    return {
      for (final day in totals.keys)
        day: FxDaySettlement(
          differenceIqd: totals[day] ?? 0,
          note: _joinNotes(notes[day] ?? const []),
        ),
    };
  }

  Future<List<Map<String, dynamic>>> stockValuation(int rateMillis) async {
    await ensureTables();
    final balances = await database.select(database.stockBalances).get();
    final variants = await database.select(database.productVariants).get();
    final products = await database.select(database.products).get();
    final warehouses = await database.select(database.warehouses).get();
    final layers = await database.customSelect(
      '''
      SELECT variant_id, cost_usd_minor, pieces_minor
      FROM variant_usd_costs
      ''',
    ).get();
    final variantById = {for (final row in variants) row.id: row};
    final productById = {for (final row in products) row.id: row};
    final warehouseById = {for (final row in warehouses) row.id: row};
    final layerById = {
      for (final row in layers)
        row.read<String>('variant_id'): (
          row.read<int>('pieces_minor'),
          row.read<int>('cost_usd_minor'),
        ),
    };
    final rows = <Map<String, dynamic>>[];
    var bookSum = 0;
    var replacementSum = 0;
    for (final balance in balances) {
      if (balance.quantity <= 0) {
        continue;
      }
      final variant = variantById[balance.variantId];
      if (variant == null) {
        continue;
      }
      final product = productById[variant.productId];
      final onHand = moneyMinor(balance.quantity);
      final pieceMinor = moneyMinor(variant.costPrice);
      final book = lineCostIqd(onHand, pieceMinor);
      final layer = layerById[balance.variantId];
      final usdPieces = layer == null
          ? 0
          : (layer.$1 < onHand ? layer.$1 : onHand);
      final rest = onHand - usdPieces;
      final restBook = lineCostIqd(rest, pieceMinor);
      final usd = layer == null ? 0 : usdMinorForPieces(usdPieces, layer.$2);
      final replacement = rateMillis <= 0
          ? book
          : restBook + iqdFromUsd(usd, rateMillis);
      bookSum += book;
      replacementSum += replacement;
      final name = product?.name ?? variant.productId;
      rows.add({
        'material_name': name,
        'warehouse_name': warehouseById[balance.warehouseId]?.name ?? '',
        'quantity': balance.quantity,
        'book_value_iqd': book,
        'replacement_value_iqd': replacement,
        'fx_effect_iqd': replacement - book,
        'rate_used': formatRateMillis(rateMillis),
      });
    }
    rows.sort((a, b) {
      final byName = '${a['material_name']}'.compareTo('${b['material_name']}');
      if (byName != 0) {
        return byName;
      }
      return '${a['warehouse_name']}'.compareTo('${b['warehouse_name']}');
    });
    if (rows.length > 1) {
      rows.add({
        'material_name': 'المجموع',
        'warehouse_name': '',
        'quantity': '',
        'book_value_iqd': bookSum,
        'replacement_value_iqd': replacementSum,
        'fx_effect_iqd': replacementSum - bookSum,
        'rate_used': formatRateMillis(rateMillis),
      });
    }
    return rows;
  }

  Future<FrozenLineCost?> _line(String saleItemId) async {
    final rows = await database.customSelect(
      '''
      SELECT cost_iqd, usd_minor, usd_book_iqd
      FROM sale_line_costs
      WHERE sale_item_id = ?
      ''',
      variables: [Variable.withString(saleItemId)],
    ).get();
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return FrozenLineCost(
      costIqd: row.read<int>('cost_iqd'),
      usdMinor: row.read<int>('usd_minor'),
      usdBookIqd: row.read<int>('usd_book_iqd'),
    );
  }

  Future<String?> _variantOfItem(String saleItemId) async {
    final item = await (database.select(database.saleItems)
          ..where((table) => table.id.equals(saleItemId)))
        .getSingleOrNull();
    final variantId = item?.variantId?.trim() ?? '';
    return variantId.isEmpty ? null : variantId;
  }

  Future<int> _onHandMinor(String variantId) async {
    final rows = await (database.select(database.stockBalances)
          ..where((table) => table.variantId.equals(variantId)))
        .get();
    var minor = 0;
    for (final row in rows) {
      minor += moneyMinor(row.quantity);
    }
    return minor;
  }

  Future<(int, int)> _layer(String variantId) async {
    final rows = await database.customSelect(
      '''
      SELECT pieces_minor, cost_usd_minor
      FROM variant_usd_costs
      WHERE variant_id = ?
      ''',
      variables: [Variable.withString(variantId)],
    ).get();
    if (rows.isEmpty) {
      return (0, 0);
    }
    return (
      rows.first.read<int>('pieces_minor'),
      rows.first.read<int>('cost_usd_minor'),
    );
  }

  Future<void> _writeLayer(String variantId, int pieces, int cost) async {
    await database.customInsert(
      '''
      INSERT INTO variant_usd_costs (variant_id, cost_usd_minor, pieces_minor)
      VALUES (?, ?, ?)
      ON CONFLICT(variant_id) DO UPDATE SET
        cost_usd_minor = excluded.cost_usd_minor,
        pieces_minor = excluded.pieces_minor
      ''',
      variables: [
        Variable.withString(variantId),
        Variable.withInt(cost),
        Variable.withInt(pieces),
      ],
    );
  }

  Future<void> _insertLine(String saleItemId, FrozenLineCost line) async {
    await database.customInsert(
      '''
      INSERT INTO sale_line_costs (
        sale_item_id, cost_iqd, usd_minor, usd_book_iqd
      ) VALUES (?, ?, ?, ?)
      ON CONFLICT(sale_item_id) DO NOTHING
      ''',
      variables: [
        Variable.withString(saleItemId),
        Variable.withInt(line.costIqd),
        Variable.withInt(line.usdMinor),
        Variable.withInt(line.usdBookIqd),
      ],
    );
  }

  double _pieces(double quantity, double factor, int loose) {
    final cartons = quantity < 0 ? 0.0 : quantity;
    final unit = factor <= 0 ? 1.0 : factor;
    final extra = loose < 0 ? 0 : loose;
    return cartons * unit + extra;
  }
}

String _dayKey(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _joinNotes(List<String> notes) {
  final unique = <String>[];
  for (final note in notes) {
    if (!unique.contains(note)) {
      unique.add(note);
    }
  }
  if (unique.isEmpty) {
    return '';
  }
  final text = unique.join(' · ');
  if (text.length <= 180) {
    return text;
  }
  return '${text.substring(0, 177)}...';
}
