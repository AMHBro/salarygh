import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_system/core/database/app_database.dart';
import 'package:sales_system/core/sync/connectivity_service.dart';
import 'package:sales_system/core/sync/sync_operation.dart';
import 'package:sales_system/core/sync/sync_queue_repository.dart';
import 'package:sales_system/core/sync/sync_remote_gateway.dart';
import 'package:sales_system/core/sync/sync_service.dart';

class _Online extends ConnectivityService {
  @override
  Future<bool> get hasConnection async => true;
}

class _Gateway implements SyncRemoteGateway {
  final List<String> pushed = [];

  @override
  Set<String> get supportedEntityTypes => {'sale'};

  @override
  Future<void> pushOperation(SyncOutboxData operation) async {
    pushed.add(operation.entityId);
  }

  @override
  Future<SyncPullResult> pullChanges({String? cursor}) async {
    return const SyncPullResult(nextCursor: null, changes: []);
  }
}

void main() {
  test('فاتورة محلية تنتقل إلى SYNCED بعد نجاح الدفع', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final queue = SyncQueueRepository(database: database);
    final gateway = _Gateway();
    final sync = SyncService(
      database: database,
      queueRepository: queue,
      connectivityService: _Online(),
      remoteGateway: gateway,
    );

    await queue.enqueue(
      entityType: 'sale',
      entityId: 'local-sale-1',
      operation: SyncOperation.create,
      payload: {
        'total': 10,
        'lines': [
          {'variantId': 'v1', 'quantity': 2},
        ],
      },
      idempotencyKey: 'sale-offline-1',
    );

    await sync.synchronize(
      source: 'test',
      pullServerChanges: false,
    );

    final rows = await database.select(database.syncOutbox).get();
    expect(gateway.pushed, ['local-sale-1']);
    expect(rows, hasLength(1));
    expect(rows.single.status, 'SYNCED');
    expect(rows.single.entityId, 'local-sale-1');
  });

  test('طلب المزامنة أثناء دورة جارية يُنفَّذ بعدها ويسحب إن طُلب السحب', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final queue = SyncQueueRepository(database: database);
    final gateway = _PullGateway();
    final sync = SyncService(
      database: database,
      queueRepository: queue,
      connectivityService: _Online(),
      remoteGateway: gateway,
    );
    gateway.onFirstPush = () {
      return sync.synchronize(
        source: 'overlap',
        pullServerChanges: true,
      );
    };

    await queue.enqueue(
      entityType: 'sale',
      entityId: 'local-sale-2',
      operation: SyncOperation.create,
      payload: {'total': 1},
      idempotencyKey: 'sale-offline-2',
    );

    await sync.synchronize(
      source: 'test',
      pullServerChanges: false,
    );

    expect(gateway.pushes, 1);
    expect(gateway.pulls, 1);
  });
}

class _PullGateway implements SyncRemoteGateway {
  int pushes = 0;
  int pulls = 0;
  Future<void> Function()? onFirstPush;

  @override
  Set<String> get supportedEntityTypes => {'sale'};

  @override
  Future<void> pushOperation(SyncOutboxData operation) async {
    pushes += 1;
    if (pushes == 1 && onFirstPush != null) {
      await onFirstPush!();
    }
  }

  @override
  Future<SyncPullResult> pullChanges({String? cursor}) async {
    pulls += 1;
    return const SyncPullResult(nextCursor: null, changes: []);
  }
}
