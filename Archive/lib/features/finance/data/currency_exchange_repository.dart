import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

class CurrencyExchange {
  final String id;
  final String kind;
  final double usdAmount;
  final double rate;
  final double iqdAmount;
  final String partyName;
  final String note;
  final DateTime createdAt;

  const CurrencyExchange({
    required this.id,
    required this.kind,
    required this.usdAmount,
    required this.rate,
    required this.iqdAmount,
    required this.partyName,
    required this.note,
    required this.createdAt,
  });
}

class CurrencyExchangeRepository {
  final AppDatabase database;

  CurrencyExchangeRepository({required this.database});

  Future<void> ensureTable() {
    return database.customStatement(
      '''
      CREATE TABLE IF NOT EXISTS currency_exchanges (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        usd_amount REAL NOT NULL,
        rate REAL NOT NULL,
        iqd_amount REAL NOT NULL,
        party_name TEXT,
        note TEXT,
        created_at TEXT NOT NULL
      )
      ''',
    );
  }

  Future<CurrencyExchange> create({
    required String kind,
    required double usdAmount,
    required double rate,
    required String partyName,
    String note = '',
  }) async {
    await ensureTable();
    final id = const Uuid().v4();
    final createdAt = DateTime.now();
    final iqdAmount = usdAmount * rate;
    await database.customStatement(
      '''
      INSERT INTO currency_exchanges (
        id, kind, usd_amount, rate, iqd_amount, party_name, note, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        kind,
        usdAmount,
        rate,
        iqdAmount,
        partyName,
        note,
        createdAt.toIso8601String(),
      ],
    );
    return CurrencyExchange(
      id: id,
      kind: kind,
      usdAmount: usdAmount,
      rate: rate,
      iqdAmount: iqdAmount,
      partyName: partyName,
      note: note,
      createdAt: createdAt,
    );
  }

  Future<List<CurrencyExchange>> list() async {
    await ensureTable();
    final rows = await database.customSelect(
      '''
      SELECT id, kind, usd_amount, rate, iqd_amount, party_name, note, created_at
      FROM currency_exchanges
      ORDER BY created_at DESC
      ''',
    ).get();
    return [
      for (final row in rows)
        CurrencyExchange(
          id: row.read<String>('id'),
          kind: row.read<String>('kind'),
          usdAmount: row.read<double>('usd_amount'),
          rate: row.read<double>('rate'),
          iqdAmount: row.read<double>('iqd_amount'),
          partyName: row.read<String?>('party_name') ?? '',
          note: row.read<String?>('note') ?? '',
          createdAt: DateTime.tryParse(row.read<String>('created_at')) ??
              DateTime.now(),
        ),
    ];
  }
}
