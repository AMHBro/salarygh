import '../database/app_database.dart';
import 'sync_remote_gateway.dart';

class CompositeSyncRemoteGateway
    implements SyncRemoteGateway {
  final List<SyncRemoteGateway> gateways;

  CompositeSyncRemoteGateway({
    required this.gateways,
  });

  // ===========================================================================
  // SUPPORTED ENTITIES
  // ===========================================================================

  @override
  Set<String> get supportedEntityTypes {
    final result =
    <String>{};

    for (final gateway in gateways) {
      result.addAll(
        gateway.supportedEntityTypes,
      );
    }

    return result;
  }

  // ===========================================================================
  // PUSH
  // ===========================================================================

  @override
  Future<void> pushOperation(
      SyncOutboxData operation,
      ) async {
    final entityType =
    operation.entityType
        .trim()
        .toLowerCase();

    for (final gateway in gateways) {
      final supports =
      gateway.supportedEntityTypes
          .map(
            (value) =>
            value
                .trim()
                .toLowerCase(),
      )
          .contains(
        entityType,
      );

      if (!supports) {
        continue;
      }

      await gateway.pushOperation(
        operation,
      );

      return;
    }

    throw StateError(
      'No sync gateway registered for entity: '
          '${operation.entityType}',
    );
  }

  // ===========================================================================
  // PULL
  // ===========================================================================

  @override
  Future<SyncPullResult> pullChanges({
    String? cursor,
  }) async {
    final changes =
    <Map<String, dynamic>>[];

    String? nextCursor =
        cursor;

    for (final gateway in gateways) {
      final result =
      await gateway.pullChanges(
        cursor: cursor,
      );

      changes.addAll(
        result.changes,
      );

      if (result.nextCursor != null) {
        nextCursor =
            result.nextCursor;
      }
    }

    return SyncPullResult(
      nextCursor: nextCursor,
      changes: changes,
    );
  }
}