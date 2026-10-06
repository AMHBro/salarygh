import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_remote_gateway.dart';

class SuppliersSyncRemoteGateway
    implements SyncRemoteGateway {
  final AppDatabase database;
  final ApiClient apiClient;

  static const Uuid _uuid = Uuid();

  SuppliersSyncRemoteGateway({
    required this.database,
    required this.apiClient,
  });

  // ===========================================================================
  // SUPPORTED ENTITIES
  // ===========================================================================

  @override
  Set<String> get supportedEntityTypes => {
    'supplier',
  };

  // ===========================================================================
  // PUSH
  // ===========================================================================

  @override
  Future<void> pushOperation(
      SyncOutboxData operation,
      ) async {
    final operationName =
    operation.operation
        .trim()
        .toUpperCase();

    switch (operationName) {
      case 'CREATE':
        await _pushCreate(
          operation,
        );
        return;

      case 'UPDATE':
        await _pushUpdate(
          operation,
        );
        return;

      default:
        throw StateError(
          'Unsupported supplier sync operation: '
              '${operation.operation}',
        );
    }
  }

  // ===========================================================================
  // CREATE
  // ===========================================================================

  Future<void> _pushCreate(
      SyncOutboxData operation,
      ) async {
    final supplier =
    await _getLocalSupplier(
      operation.entityId,
    );

    if (supplier == null) {
      throw StateError(
        'المورد المحلي غير موجود: '
            '${operation.entityId}',
      );
    }

    if (supplier.deletedAt != null) {
      throw StateError(
        'لا يمكن مزامنة مورد محذوف محلياً.',
      );
    }

    // إذا كان الـserverId موجوداً فهذا يعني أن CREATE
    // تم بنجاح سابقاً، ولا نكرر الإنشاء.
    if (_clean(supplier.serverId) != null) {
      debugPrint(
        '[SUPPLIER SYNC] CREATE skipped: '
            '${supplier.id} already mapped to '
            '${supplier.serverId}.',
      );

      return;
    }

    final body =
    _createBody(
      supplier,
    );

    try {
      final response =
      await apiClient.post(
        '/suppliers',
        data: body,
      );

      final data =
      _requireDataMap(
        response.data,
        action: 'إنشاء المورد',
      );

      final serverId =
      _requireString(
        data['id'],
        field: 'data.id',
      );

      await _applyRemoteSnapshot(
        localId: supplier.id,
        serverData: data,
        requiredServerId: serverId,
      );

      debugPrint(
        '[SUPPLIER SYNC] Supplier created: '
            'local=${supplier.id}, '
            'server=$serverId',
      );
    } on DioException catch (error) {
      _logDioError(
        'CREATE',
        error,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // UPDATE
  // ===========================================================================

  Future<void> _pushUpdate(
      SyncOutboxData operation,
      ) async {
    final supplier =
    await _getLocalSupplier(
      operation.entityId,
    );

    if (supplier == null) {
      throw StateError(
        'المورد المحلي غير موجود: '
            '${operation.entityId}',
      );
    }

    if (supplier.deletedAt != null) {
      throw StateError(
        'لا يمكن تحديث مورد محذوف محلياً.',
      );
    }

    final serverId =
    _clean(
      supplier.serverId,
    );

    // إذا UPDATE وصل قبل CREATE لأي سبب،
    // ننشئ المورد أولاً.
    if (serverId == null) {
      debugPrint(
        '[SUPPLIER SYNC] UPDATE has no serverId. '
            'Creating supplier first...',
      );

      await _pushCreate(
        operation,
      );

      return;
    }

    final body =
    _updateBody(
      supplier,
    );

    try {
      final response =
      await apiClient.patch(
        '/suppliers/$serverId',
        data: body,
      );

      final raw =
          response.data;

      if (raw is Map) {
        final map =
        Map<String, dynamic>.from(
          raw,
        );

        if (map['success'] == false) {
          throw StateError(
            _messageFromMap(map) ??
                'فشل تحديث المورد.',
          );
        }

        final remoteData =
        map['data'];

        if (remoteData is Map) {
          await _applyRemoteSnapshot(
            localId: supplier.id,
            serverData:
            Map<String, dynamic>.from(
              remoteData,
            ),
            requiredServerId:
            serverId,
          );
        }
      }

      debugPrint(
        '[SUPPLIER SYNC] Supplier updated: '
            'local=${supplier.id}, '
            'server=$serverId',
      );
    } on DioException catch (error) {
      _logDioError(
        'UPDATE',
        error,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // PULL
  // ===========================================================================

  @override
  Future<SyncPullResult> pullChanges({
    String? cursor,
  }) async {
    try {
      var page = 1;
      var seen = 0;
      var pulled = 0;
      while (page <= 40) {
        final response = await apiClient.get(
          '/suppliers',
          queryParameters: {
            'page': '$page',
            'limit': '100',
          },
        );
        final batch = _suppliersFromResponse(response.data);
        if (batch.isEmpty) {
          break;
        }
        seen += batch.length;
        for (final item in batch) {
          try {
            await _upsertRemoteSupplier(item);
            pulled++;
          } catch (error) {
            debugPrint('[SUPPLIER SYNC] Skip row: $error');
          }
        }
        final root = response.data;
        final total = root is Map
            ? int.tryParse(
                  '${(root['meta'] is Map ? root['meta']['total'] : '') ?? ''}',
                ) ??
                0
            : 0;
        if (batch.length < 100 || (total > 0 && seen >= total)) {
          break;
        }
        page++;
      }

      debugPrint(
        '[SUPPLIER SYNC] Pulled '
            '$pulled supplier(s).',
      );

      return const SyncPullResult(
        nextCursor: null,
        changes: [],
      );
    } on DioException catch (error) {
      _logDioError(
        'PULL',
        error,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // UPSERT REMOTE
  // ===========================================================================

  Future<void> _upsertRemoteSupplier(
      Map<String, dynamic> serverData,
      ) async {
    final serverId =
    _requireString(
      serverData['id'],
      field: 'supplier.id',
    );

    final existing =
    await _getLocalSupplierByServerId(
      serverId,
    );

    if (existing != null) {
      await _applyRemoteSnapshot(
        localId: existing.id,
        serverData: serverData,
        requiredServerId: serverId,
      );

      return;
    }

    final claimed = await _unsyncedByName(
      name: _stringOrEmpty(serverData['name']),
      phone: _stringOrEmpty(serverData['phone']),
    );
    if (claimed != null) {
      await _applyRemoteSnapshot(
        localId: claimed.id,
        serverData: serverData,
        requiredServerId: serverId,
      );
      debugPrint(
        '[SUPPLIER SYNC] Linked local supplier ${claimed.id} to $serverId',
      );
      return;
    }

    final now = DateTime.now();

    final createdAt =
        _parseDate(
          serverData['created_at'],
        ) ??
            now;

    final updatedAt =
        _parseDate(
          serverData['updated_at'],
        ) ??
            createdAt;

    await database
        .into(
      database.suppliers,
    )
        .insert(
      SuppliersCompanion.insert(
        id: _uuid.v4(),
        serverId:
        Value(serverId),
        name: _stringOrEmpty(
          serverData['name'],
        ),
        phone: Value(
          _stringOrEmpty(
            serverData['phone'],
          ),
        ),
        email: Value(
          _stringOrEmpty(
            serverData['email'],
          ),
        ),
        address: Value(
          _stringOrEmpty(
            serverData['address'],
          ),
        ),
        taxNumber: Value(
          _stringOrEmpty(
            serverData['tax_number'],
          ),
        ),
        creditLimit: Value(
          _doubleOrZero(
            serverData['credit_limit'],
          ),
        ),
        notes: Value(
          _nullableString(
            serverData['notes'],
          ),
        ),
        isActive: Value(
          _boolOrDefault(
            serverData['is_active'],
            defaultValue: true,
          ),
        ),
        serverVersion:
        const Value(0),
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
    );

    debugPrint(
      '[SUPPLIER SYNC] Inserted remote supplier: '
          '$serverId',
    );
  }

  // ===========================================================================
  // APPLY REMOTE SNAPSHOT
  // ===========================================================================

  Future<void> _applyRemoteSnapshot({
    required String localId,
    required Map<String, dynamic> serverData,
    required String requiredServerId,
  }) async {
    final existing =
    await _getLocalSupplier(
      localId,
    );

    if (existing == null) {
      throw StateError(
        'المورد المحلي غير موجود أثناء حفظ Snapshot.',
      );
    }

    final responseServerId =
        _clean(
          serverData['id']?.toString(),
        ) ??
            requiredServerId;

    if (responseServerId !=
        requiredServerId) {
      throw StateError(
        'Supplier serverId mismatch. '
            'Expected $requiredServerId '
            'but received $responseServerId.',
      );
    }

    final duplicate =
    await _getLocalSupplierByServerId(
      requiredServerId,
    );

    if (duplicate != null &&
        duplicate.id != localId) {
      throw StateError(
        'Server supplier UUID '
            '$requiredServerId '
            'is already mapped to another local supplier.',
      );
    }

    final updatedAt =
        _parseDate(
          serverData['updated_at'],
        ) ??
            DateTime.now();

    final createdAt =
        _parseDate(
          serverData['created_at'],
        ) ??
            existing.createdAt;

    await (
        database.update(
          database.suppliers,
        )
          ..where(
                (table) =>
                table.id.equals(
                  localId,
                ),
          )
    ).write(
      SuppliersCompanion(
        serverId:
        Value(
          requiredServerId,
        ),
        name: serverData.containsKey(
          'name',
        )
            ? Value(
          _stringOrEmpty(
            serverData['name'],
          ),
        )
            : const Value.absent(),
        phone: serverData.containsKey(
          'phone',
        )
            ? Value(
          _stringOrEmpty(
            serverData['phone'],
          ),
        )
            : const Value.absent(),
        email: serverData.containsKey(
          'email',
        )
            ? Value(
          _stringOrEmpty(
            serverData['email'],
          ),
        )
            : const Value.absent(),
        address: serverData.containsKey(
          'address',
        )
            ? Value(
          _stringOrEmpty(
            serverData['address'],
          ),
        )
            : const Value.absent(),
        taxNumber:
        serverData.containsKey(
          'tax_number',
        )
            ? Value(
          _stringOrEmpty(
            serverData[
            'tax_number'],
          ),
        )
            : const Value.absent(),
        creditLimit:
        serverData.containsKey(
          'credit_limit',
        )
            ? Value(
          _doubleOrZero(
            serverData[
            'credit_limit'],
          ),
        )
            : const Value.absent(),
        notes: serverData.containsKey(
          'notes',
        )
            ? Value(
          _nullableString(
            serverData['notes'],
          ),
        )
            : const Value.absent(),
        isActive:
        serverData.containsKey(
          'is_active',
        )
            ? Value(
          _boolOrDefault(
            serverData[
            'is_active'],
            defaultValue: true,
          ),
        )
            : const Value.absent(),
        createdAt:
        Value(createdAt),
        updatedAt:
        Value(updatedAt),
      ),
    );
  }

  // ===========================================================================
  // LOCAL LOOKUPS
  // ===========================================================================

  Future<Supplier?>
  _getLocalSupplier(
      String localId,
      ) {
    final query =
    database.select(
      database.suppliers,
    )
      ..where(
            (table) =>
            table.id.equals(
              localId,
            ),
      );

    return query.getSingleOrNull();
  }

  Future<Supplier?>
  _getLocalSupplierByServerId(
      String serverId,
      ) {
    final query =
    database.select(
      database.suppliers,
    )
      ..where(
            (table) =>
            table.serverId.equals(
              serverId,
            ),
      );

    return query.getSingleOrNull();
  }

  // ===========================================================================
  // REQUEST BODY
  // ===========================================================================

  Map<String, dynamic> _createBody(
      Supplier supplier,
      ) {
    final result =
    <String, dynamic>{
      'name': supplier.name.trim(),
      'credit_limit':
      supplier.creditLimit,
    };

    _putOptionalString(
      result,
      'phone',
      supplier.phone,
    );

    _putOptionalString(
      result,
      'email',
      supplier.email,
    );

    _putOptionalString(
      result,
      'address',
      supplier.address,
    );

    _putOptionalString(
      result,
      'tax_number',
      supplier.taxNumber,
    );

    _putOptionalString(
      result,
      'notes',
      supplier.notes,
    );

    return result;
  }

  Map<String, dynamic> _updateBody(
      Supplier supplier,
      ) {
    return {
      'name': supplier.name.trim(),
      'phone': supplier.phone.trim(),
      'email': supplier.email.trim(),
      'address':
      supplier.address.trim(),
      'tax_number':
      supplier.taxNumber.trim(),
      'credit_limit':
      supplier.creditLimit,
      'notes':
      supplier.notes?.trim() ?? '',
    };
  }

  // ===========================================================================
  // RESPONSE HELPERS
  // ===========================================================================

  Map<String, dynamic> _requireDataMap(
      dynamic raw, {
        required String action,
      }) {
    if (raw is! Map) {
      throw StateError(
        'استجابة $action غير صالحة.',
      );
    }

    final root =
    Map<String, dynamic>.from(
      raw,
    );

    if (root['success'] != true) {
      throw StateError(
        _messageFromMap(root) ??
            'فشل $action.',
      );
    }

    final data =
    root['data'];

    if (data is! Map) {
      throw StateError(
        'بيانات $action غير صالحة.',
      );
    }

    return Map<String, dynamic>.from(
      data,
    );
  }

  /// يجلب موردي السيرفر المطابقين للبحث حتى لا يُنشأ مورد مكرر.
  Future<void> importSearch(String query) async {
    final text = query.trim();
    if (text.length < 2) {
      return;
    }
    final response = await apiClient.get(
      '/suppliers',
      queryParameters: {
        'search': text,
        'page': '1',
        'limit': '100',
      },
    );
    for (final item in _suppliersFromResponse(response.data)) {
      try {
        await _upsertRemoteSupplier(item);
      } catch (error) {
        debugPrint('[SUPPLIER SEARCH] $error');
      }
    }
  }

  List<Map<String, dynamic>> _suppliersFromResponse(dynamic raw) {
    if (raw is! Map) {
      throw StateError('استجابة الموردين غير صالحة.');
    }
    final root = Map<String, dynamic>.from(raw);
    if (root['success'] == false) {
      throw StateError(
        _messageFromMap(root) ?? 'فشل تحميل الموردين.',
      );
    }
    return _extractSupplierList(root['data']);
  }

  Future<Supplier?> _unsyncedByName({
    required String name,
    required String phone,
  }) async {
    final wanted = name.trim();
    if (wanted.isEmpty) {
      return null;
    }
    final wantedPhone = phone.trim();
    final rows = await (database.select(database.suppliers)
          ..where(
            (table) => table.deletedAt.isNull() & table.serverId.isNull(),
          ))
        .get();
    final matches = rows.where((row) {
      if (row.name.trim() != wanted) {
        return false;
      }
      final localPhone = row.phone.trim();
      if (wantedPhone.isEmpty || localPhone.isEmpty) {
        return true;
      }
      return localPhone == wantedPhone;
    }).toList();
    if (matches.length != 1) {
      return null;
    }
    return matches.first;
  }

  List<Map<String, dynamic>>
  _extractSupplierList(
      dynamic rawData,
      ) {
    if (rawData is List) {
      return rawData
          .whereType<Map>()
          .map(
            (item) =>
        Map<String, dynamic>.from(
          item,
        ),
      )
          .toList();
    }

    if (rawData is Map) {
      final map =
      Map<String, dynamic>.from(
        rawData,
      );

      for (final key in [
        'items',
        'suppliers',
        'results',
        'data',
      ]) {
        final value = map[key];

        if (value is List) {
          return value
              .whereType<Map>()
              .map(
                (item) =>
            Map<String, dynamic>.from(
              item,
            ),
          )
              .toList();
        }
      }
    }

    throw StateError(
      'قائمة الموردين في استجابة السيرفر غير صالحة.',
    );
  }

  // ===========================================================================
  // PARSING
  // ===========================================================================

  String _requireString(
      dynamic value, {
        required String field,
      }) {
    final result =
        value?.toString().trim() ?? '';

    if (result.isEmpty) {
      throw StateError(
        'الحقل $field مفقود من استجابة السيرفر.',
      );
    }

    return result;
  }

  String _stringOrEmpty(
      dynamic value,
      ) {
    return value?.toString().trim() ??
        '';
  }

  String? _nullableString(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    final result =
    value.toString().trim();

    return result.isEmpty
        ? null
        : result;
  }

  double _doubleOrZero(
      dynamic value,
      ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
  }

  bool _boolOrDefault(
      dynamic value, {
        required bool defaultValue,
      }) {
    if (value is bool) {
      return value;
    }

    final text =
    value?.toString()
        .trim()
        .toLowerCase();

    if (text == 'true' ||
        text == '1') {
      return true;
    }

    if (text == 'false' ||
        text == '0') {
      return false;
    }

    return defaultValue;
  }

  DateTime? _parseDate(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    )?.toLocal();
  }

  String? _clean(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final clean =
    value.trim();

    return clean.isEmpty
        ? null
        : clean;
  }

  void _putOptionalString(
      Map<String, dynamic> body,
      String key,
      String? value,
      ) {
    final clean =
    _clean(value);

    if (clean != null) {
      body[key] = clean;
    }
  }

  String? _messageFromMap(
      Map<String, dynamic> map,
      ) {
    final message =
    map['message'];

    if (message is String &&
        message.trim().isNotEmpty) {
      return message.trim();
    }

    return null;
  }

  // ===========================================================================
  // ERROR LOG
  // ===========================================================================

  void _logDioError(
      String action,
      DioException error,
      ) {
    debugPrint(
      '[SUPPLIER SYNC][$action] '
          'HTTP ${error.response?.statusCode}',
    );

    debugPrint(
      '[SUPPLIER SYNC][$action] '
          '${error.response?.data}',
    );
  }
}