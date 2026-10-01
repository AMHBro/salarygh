import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../models/print_settings.dart';

class PrintSettingsStore {
  PrintSettingsStore(this.database);

  final AppDatabase database;

  static const _id = 'office';

  Future<PrintSettings> read() async {
    final row = await database.customSelect(
      'SELECT payload_json FROM print_settings WHERE id = ?',
      variables: [Variable.withString(_id)],
    ).getSingleOrNull();
    final raw = row?.data['payload_json']?.toString() ?? '';
    if (raw.isEmpty) {
      return const PrintSettings();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return PrintSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return const PrintSettings();
  }

  Future<void> save(PrintSettings settings) {
    return database.customStatement(
      '''
INSERT INTO print_settings (id, payload_json, updated_at)
VALUES (?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  payload_json = excluded.payload_json,
  updated_at = excluded.updated_at
''',
      [
        _id,
        jsonEncode(settings.toJson()),
        DateTime.now().toIso8601String(),
      ],
    );
  }
}
