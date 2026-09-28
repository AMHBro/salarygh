import '../database/app_database.dart';

abstract class SyncRemoteGateway {
  /// أنواع الـEntities التي يستطيع هذا Gateway
  /// مزامنتها فعلياً.
  ///
  /// حالياً نبدأ بالـProduct فقط.
  Set<String> get supportedEntityTypes;

  Future<void> pushOperation(
      SyncOutboxData operation,
      );

  Future<SyncPullResult> pullChanges({
    String? cursor,
  });
}

class SyncPullResult {
  final String? nextCursor;

  final List<Map<String, dynamic>>
  changes;

  const SyncPullResult({
    required this.nextCursor,
    required this.changes,
  });
}