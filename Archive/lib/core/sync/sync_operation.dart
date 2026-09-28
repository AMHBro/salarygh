enum SyncOperation {
  create,
  update,
  delete,
}

extension SyncOperationExtension on SyncOperation {
  String get databaseValue {
    switch (this) {
      case SyncOperation.create:
        return 'CREATE';

      case SyncOperation.update:
        return 'UPDATE';

      case SyncOperation.delete:
        return 'DELETE';
    }
  }

  static SyncOperation fromDatabaseValue(
      String value,
      ) {
    switch (value.toUpperCase()) {
      case 'CREATE':
        return SyncOperation.create;

      case 'UPDATE':
        return SyncOperation.update;

      case 'DELETE':
        return SyncOperation.delete;

      default:
        throw ArgumentError(
          'Unknown sync operation: $value',
        );
    }
  }
}

enum SyncQueueStatus {
  pending,
  syncing,
  synced,
  failed,
}

extension SyncQueueStatusExtension on SyncQueueStatus {
  String get databaseValue {
    switch (this) {
      case SyncQueueStatus.pending:
        return 'PENDING';

      case SyncQueueStatus.syncing:
        return 'SYNCING';

      case SyncQueueStatus.synced:
        return 'SYNCED';

      case SyncQueueStatus.failed:
        return 'FAILED';
    }
  }
}