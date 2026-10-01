import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

class FloorStore {
  static const _deviceKey = 'office_device_id';
  static const _cursorKey = 'floor_event_cursor';
  static const Uuid _uuid = Uuid();

  static Future<void> ensureTables(AppDatabase database) async {
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS stock_sale_locks (
        variant_id TEXT PRIMARY KEY,
        server_variant_id TEXT,
        reason TEXT NOT NULL,
        sale_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS sale_conflicts (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        variant_id TEXT,
        server_variant_id TEXT,
        message TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS floor_pending_events (
        id INTEGER PRIMARY KEY,
        event_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  static String holdKey(String deviceId, String serverVariantId) {
    return 'hold:$deviceId:$serverVariantId';
  }

  static Future<String> deviceId(AppDatabase database) async {
    final row = await (database.select(database.syncState)
          ..where((table) => table.key.equals(_deviceKey)))
        .getSingleOrNull();
    final existing = row?.value?.trim() ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }
    final created = _uuid.v4();
    await database.into(database.syncState).insertOnConflictUpdate(
          SyncStateCompanion.insert(
            key: _deviceKey,
            value: Value(created),
            updatedAt: DateTime.now(),
          ),
        );
    return created;
  }

  static Future<int> cursor(AppDatabase database) async {
    final row = await (database.select(database.syncState)
          ..where((table) => table.key.equals(_cursorKey)))
        .getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  static Future<void> saveCursor(AppDatabase database, int value) async {
    await database.into(database.syncState).insertOnConflictUpdate(
          SyncStateCompanion.insert(
            key: _cursorKey,
            value: Value('$value'),
            updatedAt: DateTime.now(),
          ),
        );
  }

  static Future<bool> isLocked(AppDatabase database, String variantId) async {
    await ensureTables(database);
    final rows = await database.customSelect(
      'SELECT variant_id FROM stock_sale_locks WHERE variant_id = ?',
      variables: [Variable.withString(variantId)],
    ).get();
    return rows.isNotEmpty;
  }

  static Future<void> lockVariant(
    AppDatabase database, {
    required String variantId,
    String? serverVariantId,
    required String reason,
    String? saleId,
  }) async {
    await ensureTables(database);
    await database.customInsert(
      '''
      INSERT INTO stock_sale_locks (
        variant_id, server_variant_id, reason, sale_id, created_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(variant_id) DO NOTHING
      ''',
      variables: [
        Variable.withString(variantId),
        Variable.withString(serverVariantId ?? ''),
        Variable.withString(reason),
        Variable.withString(saleId ?? ''),
        Variable.withString(DateTime.now().toIso8601String()),
      ],
    );
  }

  static Future<void> unlockVariant(AppDatabase database, String variantId) async {
    await ensureTables(database);
    await database.customStatement(
      "DELETE FROM stock_sale_locks WHERE variant_id = '${variantId.replaceAll("'", '')}'",
    );
  }

  static Future<void> noteShortage(
    AppDatabase database, {
    required String saleId,
    required String message,
  }) async {
    await ensureTables(database);
    final items = await (database.select(database.saleItems)
          ..where((table) => table.saleId.equals(saleId)))
        .get();
    String? firstVariant;
    String? firstServer;
    for (final item in items) {
      final variantId = item.variantId?.trim() ?? '';
      if (variantId.isEmpty) {
        continue;
      }
      firstVariant ??= variantId;
      final variant = await (database.select(database.productVariants)
            ..where((table) => table.id.equals(variantId)))
          .getSingleOrNull();
      final serverId = variant?.serverId?.trim();
      firstServer ??= serverId;
      await lockVariant(
        database,
        variantId: variantId,
        serverVariantId: serverId,
        reason: message,
        saleId: saleId,
      );
    }
    await database.customInsert(
      '''
      INSERT INTO sale_conflicts (
        id, sale_id, variant_id, server_variant_id, message, status, created_at
      ) VALUES (?, ?, ?, ?, ?, 'OPEN', ?)
      ON CONFLICT(id) DO NOTHING
      ''',
      variables: [
        Variable.withString(saleId),
        Variable.withString(saleId),
        Variable.withString(firstVariant ?? ''),
        Variable.withString(firstServer ?? ''),
        Variable.withString(message),
        Variable.withString(DateTime.now().toIso8601String()),
      ],
    );
  }

  static Future<int> openConflictCount(AppDatabase database) async {
    await ensureTables(database);
    final rows = await database.customSelect(
      "SELECT COUNT(*) AS n FROM sale_conflicts WHERE status <> 'RELEASED'",
    ).get();
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first.read<int>('n');
  }

  static Future<List<SaleConflictRow>> conflicts(AppDatabase database) async {
    await ensureTables(database);
    final rows = await database.customSelect(
      '''
      SELECT id, sale_id, variant_id, server_variant_id, message, status, created_at
      FROM sale_conflicts
      WHERE status <> 'RELEASED'
      ORDER BY created_at DESC
      ''',
    ).get();
    return [
      for (final row in rows)
        SaleConflictRow(
          id: row.read<String>('id'),
          saleId: row.read<String>('sale_id'),
          variantId: row.read<String>('variant_id'),
          serverVariantId: row.read<String>('server_variant_id'),
          message: row.read<String>('message'),
          status: row.read<String>('status'),
        ),
    ];
  }

  static Future<void> acknowledge(AppDatabase database, String id) async {
    await database.customStatement(
      "UPDATE sale_conflicts SET status = 'ACK' WHERE id = '${id.replaceAll("'", '')}'",
    );
  }

  static Future<void> markReleased(AppDatabase database, String id) async {
    final rows = await database.customSelect(
      'SELECT variant_id FROM sale_conflicts WHERE id = ?',
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isNotEmpty) {
      final variantId = rows.first.read<String>('variant_id');
      if (variantId.isNotEmpty) {
        await unlockVariant(database, variantId);
      }
    }
    await database.customStatement(
      "UPDATE sale_conflicts SET status = 'RELEASED' WHERE id = '${id.replaceAll("'", '')}'",
    );
  }

  static Future<void> savePending(
    AppDatabase database, {
    required int id,
    required String eventType,
    required String entityId,
    required String payload,
    required String createdAt,
  }) async {
    await ensureTables(database);
    await database.customInsert(
      '''
      INSERT INTO floor_pending_events (
        id, event_type, entity_id, payload, created_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO NOTHING
      ''',
      variables: [
        Variable.withInt(id),
        Variable.withString(eventType),
        Variable.withString(entityId),
        Variable.withString(payload),
        Variable.withString(createdAt),
      ],
    );
  }

  static Future<List<QueryRow>> pending(AppDatabase database) {
    return database.customSelect(
      '''
      SELECT id, event_type, entity_id, payload, created_at
      FROM floor_pending_events
      ORDER BY id
      ''',
    ).get();
  }

  static Future<void> dropPending(AppDatabase database, int id) async {
    await database.customStatement(
      'DELETE FROM floor_pending_events WHERE id = $id',
    );
  }

  static Future<void> noteSyncRejection(
    AppDatabase database, {
    required String saleId,
    required String message,
  }) async {
    await ensureTables(database);
    final clean = message
        .replaceFirst('SYNC_REJECTED', '')
        .replaceAll('Exception:', '')
        .trim();
    await database.customInsert(
      '''
      INSERT INTO sale_conflicts (
        id, sale_id, variant_id, server_variant_id, message, status, created_at
      ) VALUES (?, ?, '', '', ?, 'SYNC_REJECTED', ?)
      ON CONFLICT(id) DO NOTHING
      ''',
      variables: [
        Variable.withString('sync-rejected-$saleId'),
        Variable.withString(saleId),
        Variable.withString(
          clean.isEmpty
              ? 'تم رفض الفاتورة لأن السقف الائتماني لم يعد يكفي. تحتاج موافقة المدير.'
              : clean,
        ),
        Variable.withString(DateTime.now().toIso8601String()),
      ],
    );
  }
}

class SaleConflictRow {
  final String id;
  final String saleId;
  final String variantId;
  final String serverVariantId;
  final String message;
  final String status;

  const SaleConflictRow({
    required this.id,
    required this.saleId,
    required this.variantId,
    required this.serverVariantId,
    required this.message,
    required this.status,
  });
}
