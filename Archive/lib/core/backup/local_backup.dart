import 'dart:convert';

import '../database/app_database.dart';
import 'backup_channel.dart';

const _backupKind = 'sayler-local-backup';

class LocalBackup {
  final AppDatabase database;

  const LocalBackup({required this.database});

  Future<int> exportFile() async {
    final tables = <String, List<Map<String, Object?>>>{};
    var count = 0;

    for (final table in database.allTables) {
      final rows = await database
          .customSelect('SELECT * FROM ${table.actualTableName}')
          .get();
      tables[table.actualTableName] = [
        for (final row in rows) _plainRow(row.data),
      ];
      count += rows.length;
    }

    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final payload = jsonEncode({
      'kind': _backupKind,
      'schema': database.schemaVersion,
      'created_at': now.toIso8601String(),
      'tables': tables,
    });

    await saveBackupFile('sayler-backup-$stamp.json', payload);
    return count;
  }

  Future<int?> restoreFromFile() async {
    final text = await pickBackupText();
    if (text == null || text.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw StateError('ملف النسخة غير مفهوم.');
    }

    if (decoded['kind'] != _backupKind) {
      throw StateError('هذا الملف ليس نسخة احتياطية من النظام.');
    }

    final schema = decoded['schema'];
    if (schema != database.schemaVersion) {
      throw StateError(
        'النسخة من إصدار مختلف. هذه الحاسبة تعمل بالإصدار ${database.schemaVersion}.',
      );
    }

    final rawTables = decoded['tables'];
    if (rawTables is! Map) {
      throw StateError('ملف النسخة لا يحتوي على بيانات.');
    }

    final byName = {
      for (final table in database.allTables) table.actualTableName: table,
    };
    var count = 0;

    await database.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await database.transaction(() async {
        for (final table in byName.values) {
          await database.customStatement('DELETE FROM ${table.actualTableName}');
        }

        for (final entry in rawTables.entries) {
          final table = byName[entry.key];
          final rows = entry.value;
          if (table == null || rows is! List) {
            continue;
          }
          final allowed = {
            for (final column in table.$columns) column.name,
          };
          for (final row in rows) {
            if (row is! Map) {
              continue;
            }
            final columns = [
              for (final key in row.keys)
                if (key is String && allowed.contains(key) && _safeName(key)) key,
            ];
            if (columns.isEmpty) {
              continue;
            }
            final values = [for (final column in columns) row[column]];
            final marks = List.filled(columns.length, '?').join(', ');
            await database.customStatement(
              'INSERT INTO ${table.actualTableName} (${columns.join(', ')}) VALUES ($marks)',
              values,
            );
            count++;
          }
        }
      });
    } finally {
      await database.customStatement('PRAGMA foreign_keys = ON');
    }

    return count;
  }

  Map<String, Object?> _plainRow(Map<String, Object?> row) {
    return {
      for (final entry in row.entries) entry.key: _plainValue(entry.value),
    };
  }

  Object? _plainValue(Object? value) {
    if (value == null || value is num || value is String || value is bool) {
      return value;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    return value.toString();
  }

  bool _safeName(String name) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name);
  }
}
