import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../features/alira/data/alira_store_orders.dart';
import '../database/app_database.dart';
import '../floor/floor_store.dart';
import '../floor/floor_sync.dart';
import '../lan/lan_inbox.dart';
import '../lan/lan_sale_bridge.dart';
import '../../features/ecommerce/data/cloud_store_orders.dart';
import '../network/api_client.dart';
import 'connectivity_service.dart';
import 'store_catalog_publisher.dart';
import 'supplier_sheet_sink.dart';
import 'sync_failure.dart';
import 'sync_queue_repository.dart';
import 'sync_remote_gateway.dart';

class SyncService {
  final AppDatabase database;
  final SyncQueueRepository queueRepository;
  final ConnectivityService connectivityService;
  final SyncRemoteGateway? remoteGateway;
  final ApiClient? apiClient;

  StreamSubscription<bool>? _connectionSubscription;
  Timer? _periodicTimer;
  Timer? _floorTimer;

  bool _isSyncing = false;
  bool _started = false;
  bool _followUp = false;
  bool _followUpPull = false;
  bool _pullingImages = false;
  bool _pullingSheets = false;

  SyncService({
    required this.database,
    required this.queueRepository,
    required     this.connectivityService,
    this.remoteGateway,
    this.apiClient,
  });

  bool get isSyncing => _isSyncing;
  bool get isStarted => _started;

  // ===========================================================================
  // START
  // ===========================================================================

  Future<void> start() async {
    if (_started) {
      debugPrint(
        '[SYNC] start() ignored: service already started.',
      );
      return;
    }

    debugPrint('[SYNC] ========================================');
    debugPrint('[SYNC] Starting SyncService...');
    debugPrint('[SYNC] Remote gateway: ${remoteGateway.runtimeType}');

    _started = true;

    // =========================================================================
    // RESET INTERRUPTED OPERATIONS
    // =========================================================================

    try {
      debugPrint('[SYNC] Resetting stuck SYNCING operations...');

      await queueRepository.resetStuckOperations();

      debugPrint('[SYNC] Stuck operations reset completed.');
    } catch (error, stackTrace) {
      debugPrint('[SYNC] Failed to reset stuck operations.');
      debugPrint('[SYNC] Error: $error');
      debugPrint('[SYNC] StackTrace: $stackTrace');
    }

    // =========================================================================
    // CONNECTIVITY LISTENER
    // =========================================================================

    _connectionSubscription =
        connectivityService.connectionStream.listen(
              (connected) {
            debugPrint(
              '[SYNC] Connectivity changed. Connected: $connected',
            );

            if (connected) {
              unawaited(
                synchronize(
                  source: 'connectivity',
                  pullServerChanges: true,
                ),
              );
            }
          },
          onError: (Object error) {
            debugPrint(
              '[SYNC] Connectivity stream error: $error',
            );
          },
        );

    // =========================================================================
    // PERIODIC SYNC
    //
    // Periodic sync only pushes local pending changes.
    // It does not perform a full server pull.
    // =========================================================================

    final client = apiClient;
    if (client != null) {
      _floorTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) {
          unawaited(
            FloorSync.pull(
              database: database,
              apiClient: client,
              connectivity: connectivityService,
            ),
          );
          unawaited(
            LanInbox.drain(database),
          );
          unawaited(() async {
            try {
              await LanSaleBridge.pullMasterSnapshot(database);
            } catch (_) {}
          }());
        },
      );
    }

    _periodicTimer = Timer.periodic(
      const Duration(seconds: 45),
          (_) {
        debugPrint(
          '[SYNC] Periodic push triggered.',
        );

        unawaited(
          synchronize(
            source: 'timer',
            pullServerChanges: false,
          ),
        );
        unawaited(
          _pullProductImages(),
        );
        unawaited(
          _pullSupplierSheets(),
        );
      },
    );

    // =========================================================================
    // STARTUP SYNC
    // =========================================================================

    try {
      final connected =
      await connectivityService.hasConnection;

      debugPrint(
        '[SYNC] Initial connectivity: $connected',
      );

      if (connected) {
        await synchronize(
          source: 'startup',
          pullServerChanges: true,
        );
        unawaited(
          _pullProductImages(),
        );
        unawaited(
          _pullSupplierSheets(),
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[SYNC] Initial connectivity check failed.',
      );
      debugPrint(
        '[SYNC] Error: $error',
      );
      debugPrint(
        '[SYNC] StackTrace: $stackTrace',
      );
    }

    debugPrint('[SYNC] SyncService started.');
    debugPrint('[SYNC] ========================================');
  }

  Future<void> _pullProductImages() async {
    final client = apiClient;
    if (client == null || kIsWeb || _pullingImages) {
      return;
    }
    _pullingImages = true;
    try {
      var page = 1;
      var totalPages = 1;
      do {
        final response = await client.get(
          '/products/images',
          queryParameters: {
            'page': page,
          },
        );
        final root = response.data;
        if (root is! Map) {
          return;
        }
        final meta = root['meta'];
        if (meta is Map) {
          totalPages = int.tryParse('${meta['totalPages']}') ?? 1;
        }
        final rows = root['data'];
        if (rows is! List) {
          return;
        }
        for (final raw in rows) {
          if (raw is! Map) {
            continue;
          }
          final serverId = '${raw['id'] ?? ''}'.trim();
          final image = '${raw['image_url'] ?? ''}'.trim();
          if (serverId.isEmpty || !_usableProductImage(image)) {
            continue;
          }
          await _saveProductImage(
            serverId: serverId,
            image: image,
            barcode: '${raw['barcode'] ?? ''}'.trim(),
            sku: '${raw['sku'] ?? ''}'.trim(),
          );
        }
        page += 1;
      } while (page <= totalPages && page <= 20);
    } catch (error) {
      debugPrint('[SYNC] product images: $error');
    } finally {
      _pullingImages = false;
    }
  }

  Future<void> _pullSupplierSheets() async {
    final client = apiClient;
    if (client == null || kIsWeb || _pullingSheets) {
      return;
    }
    _pullingSheets = true;
    try {
      var page = 1;
      var totalPages = 1;
      do {
        final response = await client.get(
          '/suppliers/sheets',
          queryParameters: {
            'page': page,
          },
        );
        final root = response.data;
        if (root is! Map) {
          return;
        }
        final meta = root['meta'];
        if (meta is Map) {
          totalPages = int.tryParse('${meta['totalPages']}') ?? 1;
        }
        final rows = root['data'];
        if (rows is! List || rows.isEmpty) {
          return;
        }
        for (final raw in rows) {
          if (raw is! Map) {
            continue;
          }
          final sheetId = '${raw['id'] ?? ''}'.trim();
          final name = '${raw['supplier_name'] ?? ''}'.trim();
          final title = '${raw['title'] ?? ''}'.trim();
          final image = '${raw['image_url'] ?? ''}'.trim();
          if (sheetId.isEmpty || name.isEmpty || !_usableProductImage(image)) {
            continue;
          }
          final savedAt = DateTime.tryParse('${raw['created_at'] ?? ''}') ??
              DateTime.now();
          await saveSupplierSheet(
            sheetId: sheetId,
            supplierName: name,
            title: title.isEmpty ? 'صورة' : title,
            imageUrl: image,
            savedAt: savedAt.toLocal(),
          );
        }
        page += 1;
      } while (page <= totalPages && page <= 8);
    } catch (error) {
      debugPrint('[SYNC] supplier sheets: $error');
    } finally {
      _pullingSheets = false;
    }
  }

  bool _usableProductImage(String image) {
    if (image.startsWith('data:image/')) {
      return image.length <= 1500000;
    }
    final uri = Uri.tryParse(image);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _saveProductImage({
    required String serverId,
    required String image,
    required String barcode,
    required String sku,
  }) async {
    final byServer = await (database.select(database.products)
          ..where((table) => table.serverId.equals(serverId)))
        .getSingleOrNull();
    if (byServer != null) {
      await _writeImage(byServer.id, image);
      return;
    }

    final link = await database.customSelect(
      '''
SELECT local_product_id
FROM store_catalog_links
WHERE remote_product_id = ?
''',
      variables: [Variable.withString(serverId)],
    ).getSingleOrNull();
    final linkedId = link?.data['local_product_id']?.toString().trim() ?? '';
    if (linkedId.isNotEmpty) {
      await _writeImage(linkedId, image);
      return;
    }

    if (barcode.isNotEmpty) {
      final rows = await (database.select(database.products)
            ..where(
              (table) =>
                  table.barcode.equals(barcode) & table.deletedAt.isNull(),
            ))
          .get();
      if (rows.length == 1 && (rows.first.serverId ?? '').trim().isEmpty) {
        await _writeImage(rows.first.id, image);
        return;
      }
    }

    if (sku.isNotEmpty) {
      final rows = await (database.select(database.products)
            ..where(
              (table) => table.sku.equals(sku) & table.deletedAt.isNull(),
            ))
          .get();
      if (rows.length == 1 && (rows.first.serverId ?? '').trim().isEmpty) {
        await _writeImage(rows.first.id, image);
      }
    }
  }

  Future<void> _writeImage(String localId, String image) {
    return (database.update(database.products)
          ..where((table) => table.id.equals(localId)))
        .write(
      ProductsCompanion(
        imageUrl: Value(image),
      ),
    );
  }

  // ===========================================================================
  // SYNCHRONIZE
  // ===========================================================================

  Future<void> synchronize({
    String source = 'manual',
    bool pullServerChanges = true,
    bool nested = false,
  }) async {
    debugPrint('[SYNC] ----------------------------------------');
    debugPrint('[SYNC] synchronize() requested.');
    debugPrint('[SYNC] Source: $source');
    debugPrint(
      '[SYNC] Pull server changes: $pullServerChanges',
    );

    // =========================================================================
    // CONCURRENCY GUARD
    // =========================================================================

    if (_isSyncing && !nested) {
      _followUp = true;
      if (pullServerChanges) {
        _followUpPull = true;
      }
      debugPrint(
        '[SYNC] Sync coalesced: another sync is already running.',
      );
      debugPrint('[SYNC] ----------------------------------------');
      return;
    }

    final gateway = remoteGateway;

    // =========================================================================
    // GATEWAY CHECK
    // =========================================================================

    if (gateway == null) {
      debugPrint(
        '[SYNC] Sync stopped: remoteGateway is NULL.',
      );
      debugPrint('[SYNC] ----------------------------------------');
      return;
    }

    debugPrint(
      '[SYNC] Gateway: ${gateway.runtimeType}',
    );

    debugPrint(
      '[SYNC] Supported entity types: '
          '${gateway.supportedEntityTypes.join(', ')}',
    );

    // =========================================================================
    // CONNECTIVITY CHECK
    // =========================================================================

    bool connected;

    try {
      connected =
      await connectivityService.hasConnection;
    } catch (error, stackTrace) {
      debugPrint(
        '[SYNC] Connectivity check failed.',
      );
      debugPrint(
        '[SYNC] Error: $error',
      );
      debugPrint(
        '[SYNC] StackTrace: $stackTrace',
      );
      debugPrint('[SYNC] ----------------------------------------');
      return;
    }

    debugPrint(
      '[SYNC] Internet available: $connected',
    );

    if (!connected) {
      debugPrint(
        '[SYNC] Sync stopped: device is offline.',
      );
      debugPrint('[SYNC] ----------------------------------------');
      return;
    }

    // =========================================================================
    // RUN SYNC
    // =========================================================================

    if (!nested) {
      _isSyncing = true;
    }

    try {
      try {
        await AliraStoreOrders.flushQueued();
      } catch (error) {
        debugPrint('[SYNC] Store queue flush failed: $error');
      }

      try {
        final failed = await queueRepository.getFailedOperations(
          limit: 200,
        );
        for (final row in failed) {
          final error = row.lastError ?? '';
          if (error.contains('409') || error.contains('SYNC_CONFLICT')) {
            continue;
          }
          if (!isTransientSyncFailure(StateError(error))) {
            continue;
          }
          await queueRepository.retryFailedOperation(row.id);
        }
      } catch (error) {
        debugPrint('[SYNC] Could not resume network failures: $error');
      }

      // =======================================================================
      // PUSH
      // =======================================================================

      final pushResult =
      await _pushPendingOperations();

      debugPrint('[SYNC] Push finished.');
      debugPrint(
        '[SYNC] Pending found: ${pushResult.pendingCount}',
      );
      debugPrint(
        '[SYNC] Successfully pushed: ${pushResult.successCount}',
      );
      debugPrint(
        '[SYNC] Failed: ${pushResult.failedCount}',
      );

      // =======================================================================
      // IMPORTANT OFFLINE-FIRST SAFETY RULE
      //
      // إذا فشل أي Local Push فلا نسمح بعمل Full Pull في نفس الدورة.
      //
      // السبب:
      // بعض الـGateways مثل Inventory تستقبل Server Snapshot كامل.
      // لو سحبنا Snapshot بعد فشل Local Push، يمكن أن نستبدل الحالة
      // المحلية الصحيحة بحالة قديمة موجودة على السيرفر.
      //
      // مثال:
      // Local sale:
      // stock 10 -> 9
      //
      // Direct sale push fails.
      //
      // Server still has:
      // stock = 10
      //
      // Inventory pull would otherwise restore:
      // local stock = 10
      //
      // وهذا يكسر Offline-first.
      // =======================================================================

      final hasPushFailures =
          pushResult.failedCount > 0;

      if (pullServerChanges) {
        if (hasPushFailures) {
          debugPrint(
            '[SYNC] Pull SKIPPED because one or more '
                'local PUSH operations failed.',
          );

          debugPrint(
            '[SYNC] This protects unsynced local changes '
                'from being overwritten by server snapshots.',
          );
        } else {
          await _pullServerChanges();
        }
      } else {
        debugPrint(
          '[SYNC] Pull skipped for this sync source.',
        );
      }

      if (pullServerChanges) {
        await StoreCatalogPublisher(database).publish();
      }

      await CloudStoreOrders(database).pull();

      debugPrint(
        '[SYNC] Synchronization completed.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SYNC] Synchronization failed unexpectedly.',
      );
      debugPrint(
        '[SYNC] Error: $error',
      );
      debugPrint(
        '[SYNC] StackTrace: $stackTrace',
      );
    } finally {
      if (_followUp) {
        final pull = _followUpPull;
        _followUp = false;
        _followUpPull = false;
        debugPrint(
          '[SYNC] Running coalesced follow-up. Pull: $pull',
        );
        await synchronize(
          source: 'coalesced',
          pullServerChanges: pull,
          nested: true,
        );
      }

      if (!nested) {
        _isSyncing = false;
      }

      debugPrint(
        '[SYNC] synchronize() finished.',
      );
      debugPrint('[SYNC] ----------------------------------------');
    }
  }

  // ===========================================================================
  // PUSH PENDING OPERATIONS
  // ===========================================================================

  Future<_SyncPushResult>
  _pushPendingOperations() async {
    final gateway = remoteGateway;

    if (gateway == null) {
      debugPrint(
        '[SYNC] _pushPendingOperations(): gateway is NULL.',
      );

      return const _SyncPushResult();
    }

    debugPrint(
      '[SYNC] Reading NEW pending operations from Outbox...',
    );

    List<SyncOutboxData> operations;

    try {
      operations =
      await queueRepository.getPendingOperations(
        limit: 50,
        entityTypes:
        gateway.supportedEntityTypes,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SYNC] Failed to read Outbox.',
      );
      debugPrint(
        '[SYNC] Error: $error',
      );
      debugPrint(
        '[SYNC] StackTrace: $stackTrace',
      );

      rethrow;
    }

    debugPrint(
      '[SYNC] PENDING operations count: ${operations.length}',
    );

    if (operations.isEmpty) {
      debugPrint(
        '[SYNC] Nothing new to push.',
      );

      return const _SyncPushResult();
    }

    var successCount = 0;
    var failedCount = 0;

    // =========================================================================
    // PROCESS QUEUE
    // =========================================================================

    for (
    var index = 0;
    index < operations.length;
    index++
    ) {
      final operation =
      operations[index];

      debugPrint('[SYNC] ========================================');
      debugPrint(
        '[SYNC] Operation ${index + 1}/${operations.length}',
      );
      debugPrint(
        '[SYNC] Queue ID: ${operation.id}',
      );
      debugPrint(
        '[SYNC] Entity type: ${operation.entityType}',
      );
      debugPrint(
        '[SYNC] Entity ID: ${operation.entityId}',
      );
      debugPrint(
        '[SYNC] Operation: ${operation.operation}',
      );
      debugPrint(
        '[SYNC] Current status: ${operation.status}',
      );
      debugPrint(
        '[SYNC] Attempts: ${operation.attempts}',
      );
      debugPrint(
        '[SYNC] Idempotency key: ${operation.idempotencyKey}',
      );

      try {
        // =====================================================================
        // MARK SYNCING
        // =====================================================================

        debugPrint(
          '[SYNC] Marking operation as SYNCING...',
        );

        await queueRepository.markSyncing(
          operation.id,
        );

        // =====================================================================
        // PUSH
        // =====================================================================

        debugPrint(
          '[SYNC] Calling gateway.pushOperation()...',
        );

        await gateway.pushOperation(
          operation,
        );

        debugPrint(
          '[SYNC] Remote push SUCCESS.',
        );

        // =====================================================================
        // REMOVE SUCCESSFUL OPERATION
        // =====================================================================

        await queueRepository.markSynced(
          operation.id,
        );

        successCount++;

        debugPrint(
          '[SYNC] Operation synced and removed from Outbox.',
        );
      } catch (error, stackTrace) {
        final deferred = error.toString().toLowerCase().contains('sync_defer');
        if (!deferred) {
          failedCount++;
        }

        debugPrint(
          '[SYNC] !!! PUSH FAILED !!!',
        );
        debugPrint(
          '[SYNC] Queue ID: ${operation.id}',
        );
        debugPrint(
          '[SYNC] Entity: ${operation.entityType}',
        );
        debugPrint(
          '[SYNC] Entity ID: ${operation.entityId}',
        );
        debugPrint(
          '[SYNC] Operation: ${operation.operation}',
        );
        debugPrint(
          '[SYNC] Error type: ${error.runtimeType}',
        );
        debugPrint(
          '[SYNC] Error: $error',
        );
        debugPrint(
          '[SYNC] StackTrace:',
        );
        debugPrint(
          '$stackTrace',
        );

        // =====================================================================
        // MARK FAILED
        // =====================================================================

        try {
          final message = error.toString();
          if (message.contains('SYNC_REJECTED')) {
            await FloorStore.noteSyncRejection(
              database,
              saleId: operation.entityId,
              message: message,
            );
            await queueRepository.markFailed(
              queueId: operation.id,
              error: 'SYNC_REJECTED $message',
            );
            debugPrint(
              '[SYNC] Invoice rejected by credit revalidation.',
            );
            continue;
          }
          final conflict = message.contains('409') ||
              message.contains('SYNC_CONFLICT');
          if (!conflict && isTransientSyncFailure(error)) {
            await queueRepository.releaseToPending(
              queueId: operation.id,
              error: message,
            );
            debugPrint(
              deferred
                  ? '[SYNC] Deferred until its dependency reaches the server. Pull can continue.'
                  : '[SYNC] Server unreachable. Operation stays pending.',
            );
          } else {
            if (operation.entityType == 'direct_sale' &&
                message.contains('INSUFFICIENT_STOCK')) {
              await FloorStore.noteShortage(
                database,
                saleId: operation.entityId,
                message: message,
              );
            }
            await queueRepository.markFailed(
              queueId: operation.id,
              error: conflict || message.contains('INSUFFICIENT_STOCK')
                  ? 'CONFLICT $message'
                  : message,
            );

            debugPrint(
              '[SYNC] Operation marked FAILED.',
            );
          }
        } catch (
        markError,
        markStackTrace
        ) {
          debugPrint(
            '[SYNC] Failed to mark operation as FAILED.',
          );
          debugPrint(
            '[SYNC] Error: $markError',
          );
          debugPrint(
            '[SYNC] StackTrace: $markStackTrace',
          );
        }

        // =====================================================================
        // CONTINUE OTHER INDEPENDENT OPERATIONS
        // =====================================================================

        debugPrint(
          '[SYNC] Continuing with next queued operation.',
        );

        continue;
      }
    }

    return _SyncPushResult(
      pendingCount: operations.length,
      successCount: successCount,
      failedCount: failedCount,
    );
  }

  // ===========================================================================
  // PULL SERVER CHANGES
  // ===========================================================================

  Future<void> _pullServerChanges() async {
    final gateway = remoteGateway;

    if (gateway == null) {
      debugPrint(
        '[SYNC] Pull skipped: gateway is NULL.',
      );

      return;
    }

    debugPrint(
      '[SYNC] Starting server pull phase...',
    );

    try {
      final cursor =
      await _getCursor();

      debugPrint(
        '[SYNC] Current server cursor: ${cursor ?? 'NULL'}',
      );

      final result =
      await gateway.pullChanges(
        cursor: cursor,
      );

      debugPrint(
        '[SYNC] Pull returned ${result.changes.length} change(s).',
      );

      debugPrint(
        '[SYNC] Next cursor: ${result.nextCursor ?? 'NULL'}',
      );

      if (result.nextCursor != null) {
        await _saveCursor(
          result.nextCursor!,
        );

        debugPrint(
          '[SYNC] Cursor saved.',
        );
      }

      debugPrint(
        '[SYNC] Server pull phase completed.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SYNC] Pull phase failed.',
      );
      debugPrint(
        '[SYNC] Error: $error',
      );
      debugPrint(
        '[SYNC] StackTrace: $stackTrace',
      );

      rethrow;
    }
  }

  // ===========================================================================
  // MANUAL RETRY FAILED OPERATION
  // ===========================================================================

  Future<void> retryFailedOperation(
      String queueId,
      ) async {
    await queueRepository.retryFailedOperation(
      queueId,
    );

    await synchronize(
      source: 'manual_retry',
      pullServerChanges: false,
    );
  }

  // ===========================================================================
  // RETRY ALL FAILED OPERATIONS
  // ===========================================================================

  Future<void>
  retryAllFailedOperations() async {
    final changed =
    await queueRepository
        .retryAllFailedOperations();

    debugPrint(
      '[SYNC] $changed FAILED operation(s) returned to PENDING.',
    );

    if (changed <= 0) {
      return;
    }

    await synchronize(
      source: 'manual_retry_all',
      pullServerChanges: false,
    );
  }

  // ===========================================================================
  // GET CURSOR
  // ===========================================================================

  Future<String?> _getCursor() async {
    final result =
    await (database.select(
      database.syncState,
    )
      ..where(
            (table) =>
            table.key.equals(
              'server_cursor',
            ),
      ))
        .getSingleOrNull();

    return result?.value;
  }

  // ===========================================================================
  // SAVE CURSOR
  // ===========================================================================

  Future<void> _saveCursor(
      String cursor,
      ) async {
    await database
        .into(
      database.syncState,
    )
        .insertOnConflictUpdate(
      SyncStateCompanion.insert(
        key: 'server_cursor',
        value: Value(
          cursor,
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  void dispose() {
    debugPrint(
      '[SYNC] Disposing SyncService...',
    );

    _connectionSubscription?.cancel();
    _connectionSubscription = null;

    _periodicTimer?.cancel();
    _periodicTimer = null;
    _floorTimer?.cancel();
    _floorTimer = null;

    _started = false;

    debugPrint(
      '[SYNC] SyncService disposed.',
    );
  }
}

// =============================================================================
// PUSH RESULT
// =============================================================================

class _SyncPushResult {
  final int pendingCount;
  final int successCount;
  final int failedCount;

  const _SyncPushResult({
    this.pendingCount = 0,
    this.successCount = 0,
    this.failedCount = 0,
  });
}