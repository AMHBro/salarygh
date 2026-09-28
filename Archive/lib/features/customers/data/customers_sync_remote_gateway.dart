import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_remote_gateway.dart';

class CustomersSyncRemoteGateway
    implements SyncRemoteGateway {
  final AppDatabase database;
  final ApiClient apiClient;

  static const Uuid _uuid = Uuid();

  CustomersSyncRemoteGateway({
    required this.database,
    required this.apiClient,
  });

  // ===========================================================================
  // SUPPORTED ENTITIES
  // ===========================================================================

  @override
  Set<String> get supportedEntityTypes => {
    'customer',
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
          'Unsupported customer sync operation: '
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
    final customer =
    await _getLocalCustomer(
      operation.entityId,
    );

    if (customer == null) {
      throw StateError(
        'الزبون المحلي غير موجود: '
            '${operation.entityId}',
      );
    }

    if (customer.deletedAt != null) {
      throw StateError(
        'لا يمكن مزامنة زبون محذوف محلياً.',
      );
    }

    // إذا عنده serverId فهذا يعني أن CREATE نجح سابقاً.
    if (_clean(
      customer.serverId,
    ) !=
        null) {
      debugPrint(
        '[CUSTOMER SYNC] CREATE skipped: '
            '${customer.id} already mapped to '
            '${customer.serverId}.',
      );

      return;
    }

    final body =
    _createBody(
      customer,
    );

    try {
      final response =
      await apiClient.post(
        '/customers',
        data: body,
      );

      final data =
      _requireDataMap(
        response.data,
        action: 'إنشاء الزبون',
      );

      final serverId =
      _requireString(
        data['id'],
        field: 'data.id',
      );

      await _applyRemoteSnapshot(
        localId: customer.id,
        serverData: data,
        requiredServerId: serverId,
      );

      debugPrint(
        '[CUSTOMER SYNC] Customer created: '
            'local=${customer.id}, '
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
    final customer =
    await _getLocalCustomer(
      operation.entityId,
    );

    if (customer == null) {
      throw StateError(
        'الزبون المحلي غير موجود: '
            '${operation.entityId}',
      );
    }

    if (customer.deletedAt != null) {
      throw StateError(
        'لا يمكن تحديث زبون محذوف محلياً.',
      );
    }

    final serverId =
    _clean(
      customer.serverId,
    );

    // UPDATE وصل قبل CREATE.
    if (serverId == null) {
      debugPrint(
        '[CUSTOMER SYNC] UPDATE has no serverId. '
            'Creating customer first...',
      );

      await _pushCreate(
        operation,
      );

      return;
    }

    final body =
    _updateBody(
      customer,
    );

    try {
      final response =
      await apiClient.patch(
        '/customers/$serverId',
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
            _messageFromMap(
              map,
            ) ??
                'فشل تحديث الزبون.',
          );
        }

        final remoteData =
        map['data'];

        if (remoteData is Map) {
          await _applyRemoteSnapshot(
            localId: customer.id,
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
        '[CUSTOMER SYNC] Customer updated: '
            'local=${customer.id}, '
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
      final response =
      await apiClient.get(
        '/customers',
      );

      final raw =
          response.data;

      if (raw is! Map) {
        throw StateError(
          'استجابة الزبائن غير صالحة.',
        );
      }

      final root =
      Map<String, dynamic>.from(
        raw,
      );

      if (root['success'] == false) {
        throw StateError(
          _messageFromMap(
            root,
          ) ??
              'فشل تحميل الزبائن.',
        );
      }

      final rawCustomers =
      _extractCustomerList(
        root['data'],
      );

      for (final item
      in rawCustomers) {
        await _upsertRemoteCustomer(
          item,
        );
      }

      debugPrint(
        '[CUSTOMER SYNC] Pulled '
            '${rawCustomers.length} customer(s).',
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
  // UPSERT REMOTE CUSTOMER
  // ===========================================================================

  Future<void> _upsertRemoteCustomer(
      Map<String, dynamic> serverData,
      ) async {
    final serverId =
    _requireString(
      serverData['id'],
      field: 'customer.id',
    );

    final existing =
    await _getLocalCustomerByServerId(
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

    // لا نسوي matching بالاسم أو الهاتف.
    // serverId هو الهوية الوحيدة الموثوقة.
    final now =
    DateTime.now();

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
      database.customers,
    )
        .insert(
      CustomersCompanion.insert(
        id:
        _uuid.v4(),

        serverId:
        Value(
          serverId,
        ),

        name:
        _stringOrEmpty(
          serverData['name'],
        ),

        phone:
        Value(
          _stringOrEmpty(
            serverData['phone'],
          ),
        ),

        email:
        Value(
          _stringOrEmpty(
            serverData['email'],
          ),
        ),

        address:
        Value(
          _stringOrEmpty(
            serverData['address'],
          ),
        ),

        type:
        Value(
          _customerTypeOrDefault(
            serverData['type'],
          ),
        ),

        creditLimit:
        Value(
          _doubleOrZero(
            serverData[
            'credit_limit'],
          ),
        ),

        notes:
        Value(
          _nullableString(
            serverData['notes'],
          ),
        ),

        isActive:
        Value(
          _boolOrDefault(
            serverData['is_active'],
            defaultValue: true,
          ),
        ),

        serverVersion:
        const Value(
          0,
        ),

        createdAt:
        createdAt,

        updatedAt:
        updatedAt,
      ),
    );

    debugPrint(
      '[CUSTOMER SYNC] Inserted remote customer: '
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
    await _getLocalCustomer(
      localId,
    );

    if (existing == null) {
      throw StateError(
        'الزبون المحلي غير موجود أثناء حفظ Snapshot.',
      );
    }

    final responseServerId =
        _clean(
          serverData['id']
              ?.toString(),
        ) ??
            requiredServerId;

    if (responseServerId !=
        requiredServerId) {
      throw StateError(
        'Customer serverId mismatch. '
            'Expected $requiredServerId '
            'but received $responseServerId.',
      );
    }

    final duplicate =
    await _getLocalCustomerByServerId(
      requiredServerId,
    );

    if (duplicate != null &&
        duplicate.id != localId) {
      throw StateError(
        'Server customer UUID '
            '$requiredServerId '
            'is already mapped to another local customer.',
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

    await (database.update(
      database.customers,
    )
      ..where(
            (table) =>
            table.id.equals(
              localId,
            ),
      ))
        .write(
      CustomersCompanion(
        serverId:
        Value(
          requiredServerId,
        ),

        name:
        serverData.containsKey(
          'name',
        )
            ? Value(
          _stringOrEmpty(
            serverData['name'],
          ),
        )
            : const Value.absent(),

        phone:
        serverData.containsKey(
          'phone',
        )
            ? Value(
          _stringOrEmpty(
            serverData['phone'],
          ),
        )
            : const Value.absent(),

        email:
        serverData.containsKey(
          'email',
        )
            ? Value(
          _stringOrEmpty(
            serverData['email'],
          ),
        )
            : const Value.absent(),

        address:
        serverData.containsKey(
          'address',
        )
            ? Value(
          _stringOrEmpty(
            serverData['address'],
          ),
        )
            : const Value.absent(),

        type:
        serverData.containsKey(
          'type',
        )
            ? Value(
          _customerTypeOrDefault(
            serverData['type'],
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

        notes:
        serverData.containsKey(
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
            defaultValue:
            true,
          ),
        )
            : const Value.absent(),

        createdAt:
        Value(
          createdAt,
        ),

        updatedAt:
        Value(
          updatedAt,
        ),
      ),
    );
  }

  // ===========================================================================
  // LOCAL LOOKUPS
  // ===========================================================================

  Future<Customer?>
  _getLocalCustomer(
      String localId,
      ) {
    final query =
    database.select(
      database.customers,
    )
      ..where(
            (table) =>
            table.id.equals(
              localId,
            ),
      );

    return query.getSingleOrNull();
  }

  Future<Customer?>
  _getLocalCustomerByServerId(
      String serverId,
      ) {
    final query =
    database.select(
      database.customers,
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
  // CREATE BODY
  // ===========================================================================

  Map<String, dynamic> _createBody(
      Customer customer,
      ) {
    final body =
    <String, dynamic>{
      'name':
      customer.name.trim(),

      'type':
      _customerTypeOrDefault(
        customer.type,
      ),

      'credit_limit':
      customer.creditLimit,
    };

    _putOptionalString(
      body,
      'phone',
      customer.phone,
    );

    _putOptionalString(
      body,
      'email',
      customer.email,
    );

    _putOptionalString(
      body,
      'address',
      customer.address,
    );

    _putOptionalString(
      body,
      'notes',
      customer.notes,
    );

    return body;
  }

  // ===========================================================================
  // UPDATE BODY
  // ===========================================================================

  Map<String, dynamic> _updateBody(
      Customer customer,
      ) {
    return {
      'name':
      customer.name.trim(),

      'phone':
      customer.phone.trim(),

      'email':
      customer.email.trim(),

      'address':
      customer.address.trim(),

      'type':
      _customerTypeOrDefault(
        customer.type,
      ),

      'credit_limit':
      customer.creditLimit,

      'notes':
      customer.notes
          ?.trim() ??
          '',
    };
  }

  // ===========================================================================
  // RESPONSE
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
        _messageFromMap(
          root,
        ) ??
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

  List<Map<String, dynamic>>
  _extractCustomerList(
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
        'customers',
        'results',
        'data',
      ]) {
        final value =
        map[key];

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
      'قائمة الزبائن في استجابة السيرفر غير صالحة.',
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
        value
            ?.toString()
            .trim() ??
            '';

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
    return value
        ?.toString()
        .trim() ??
        '';
  }

  String? _nullableString(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    final result =
    value
        .toString()
        .trim();

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
      value
          ?.toString() ??
          '',
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
    value
        ?.toString()
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

  String _customerTypeOrDefault(
      dynamic value,
      ) {
    final text =
    value
        ?.toString()
        .trim()
        .toUpperCase();

    switch (text) {
      case 'WHOLESALE':
        return 'WHOLESALE';

      case 'RETAIL':
      default:
        return 'RETAIL';
    }
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
    _clean(
      value,
    );

    if (clean != null) {
      body[key] =
          clean;
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
      '[CUSTOMER SYNC][$action] '
          'HTTP ${error.response?.statusCode}',
    );

    debugPrint(
      '[CUSTOMER SYNC][$action] '
          '${error.response?.data}',
    );
  }
}