import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../features/alira/data/alira_store_orders.dart';
import '../database/app_database.dart';
import '../floor/floor_store.dart';
import '../floor/floor_sync.dart';
import '../network/api_client.dart';
import 'connectivity_service.dart';
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
        failedCount++;

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
          final conflict = message.contains('409') ||
              message.contains('SYNC_CONFLICT');
          if (!conflict && isTransientSyncFailure(error)) {
            await queueRepository.releaseToPending(
              queueId: operation.id,
              error: message,
            );
            debugPrint(
              '[SYNC] Server unreachable. Operation stays pending.',
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