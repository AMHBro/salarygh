import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_remote_gateway.dart';

class RepresentativesSyncRemoteGateway
    implements SyncRemoteGateway {
  final AppDatabase database;
  final ApiClient apiClient;

  static const Uuid _uuid = Uuid();

  RepresentativesSyncRemoteGateway({
    required this.database,
    required this.apiClient,
  });

  // ===========================================================================
  // SUPPORTED ENTITIES
  // ===========================================================================

  @override
  Set<String> get supportedEntityTypes => {
    'representative',
  };

  // ===========================================================================
  // PUSH
  // ===========================================================================

  @override
  Future<void> pushOperation(
      SyncOutboxData operation,
      ) async {
    final operationName =
    operation.operation.trim().toUpperCase();

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

      case 'DELETE':
        await _pushDelete(operation);
        return;

      default:
        throw StateError(
          'Unsupported representative sync operation: '
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
    final representative =
    await _getLocalRepresentative(
      operation.entityId,
    );

    if (representative == null) {
      throw StateError(
        'المندوب المحلي غير موجود: ${operation.entityId}',
      );
    }

    if (representative.deletedAt != null) {
      throw StateError(
        'لا يمكن مزامنة مندوب محذوف محلياً.',
      );
    }

    if (_clean(representative.serverId) != null) {
      debugPrint(
        '[REPRESENTATIVE SYNC] CREATE skipped: '
            '${representative.id} already mapped to '
            '${representative.serverId}.',
      );

      return;
    }

    final payload =
    _decodePayload(
      operation.payloadJson,
    );

    final password = payload['password']?.toString().trim() ?? '';
    if (password.isEmpty) {
      debugPrint(
        '[REPRESENTATIVE SYNC] CREATE skipped: password was not stored with the record.',
      );
      return;
    }

    final body =
    _createBody(
      representative,
      password: password,
    );

    try {
      final response =
      await apiClient.post(
        '/representatives',
        data: body,
      );

      final data =
      _requireDataMap(
        response.data,
        action: 'إنشاء المندوب',
      );

      final serverId =
      _requireString(
        data['id'],
        field: 'data.id',
      );

      await _applyRemoteSnapshot(
        localId: representative.id,
        serverData: data,
        requiredServerId: serverId,
      );

      debugPrint(
        '[REPRESENTATIVE SYNC] Representative created: '
            'local=${representative.id}, '
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

  Future<void> _pushDelete(
    SyncOutboxData operation,
  ) async {
    final representative = await _getLocalRepresentative(operation.entityId);
    if (representative == null) {
      return;
    }
    final serverId = _clean(representative.serverId);
    if (serverId == null) {
      return;
    }
    try {
      await apiClient.delete('/representatives/$serverId');
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) {
        rethrow;
      }
      final current = await apiClient.get('/representatives/$serverId');
      final raw = current.data;
      final row = raw is Map && raw['data'] is Map ? raw['data'] : raw;
      final status = row is Map ? '${row['status'] ?? ''}' : '';
      if (status == 'ACTIVE') {
        await apiClient.patch('/representatives/$serverId/toggle-status');
      }
    }
  }

  Future<void> _pushUpdate(
      SyncOutboxData operation,
      ) async {
    final representative =
    await _getLocalRepresentative(
      operation.entityId,
    );

    if (representative == null) {
      throw StateError(
        'المندوب المحلي غير موجود: ${operation.entityId}',
      );
    }

    if (representative.deletedAt != null) {
      throw StateError(
        'لا يمكن تحديث مندوب محذوف محلياً.',
      );
    }

    final serverId =
    _clean(
      representative.serverId,
    );

    if (serverId == null) {
      throw StateError(
        'لا يمكن تحديث المندوب قبل اكتمال عملية الإنشاء على السيرفر.',
      );
    }

    final body =
    _updateBody(
      representative,
    );

    try {
      final response =
      await apiClient.patch(
        '/representatives/$serverId',
        data: body,
      );

      final raw = response.data;

      if (raw is Map) {
        final root =
        Map<String, dynamic>.from(
          raw,
        );

        if (root['success'] == false) {
          throw StateError(
            _messageFromMap(root) ??
                'فشل تحديث المندوب.',
          );
        }

        final rawData = root['data'];

        if (rawData is Map) {
          await _applyRemoteSnapshot(
            localId: representative.id,
            serverData:
            Map<String, dynamic>.from(
              rawData,
            ),
            requiredServerId: serverId,
          );
        }
      }

      debugPrint(
        '[REPRESENTATIVE SYNC] Representative updated: '
            'local=${representative.id}, '
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
      const limit = 100;

      var totalPages = 1;
      var pulledCount = 0;

      do {
        final response =
        await apiClient.get(
          '/representatives',
          queryParameters: {
            'page': page,
            'limit': limit,
          },
        );

        final raw = response.data;

        if (raw is! Map) {
          throw StateError(
            'استجابة المندوبين غير صالحة.',
          );
        }

        final root =
        Map<String, dynamic>.from(
          raw,
        );

        if (root['success'] == false) {
          throw StateError(
            _messageFromMap(root) ??
                'فشل تحميل المندوبين.',
          );
        }

        final rawRepresentatives =
        _extractRepresentativeList(
          root['data'],
        );

        for (final item
        in rawRepresentatives) {
          await _upsertRemoteRepresentative(
            item,
          );
        }

        pulledCount +=
            rawRepresentatives.length;

        final meta = root['meta'];

        if (meta is Map) {
          final metaMap =
          Map<String, dynamic>.from(
            meta,
          );

          totalPages =
              _intOrDefault(
                metaMap['totalPages'] ??
                    metaMap['total_pages'],
                defaultValue: 1,
              );
        } else {
          totalPages = 1;
        }

        page++;
      } while (page <= totalPages);

      debugPrint(
        '[REPRESENTATIVE SYNC] Pulled '
            '$pulledCount representative(s).',
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

  Future<void> _upsertRemoteRepresentative(
      Map<String, dynamic> serverData,
      ) async {
    final serverId =
    _requireString(
      serverData['id'],
      field: 'representative.id',
    );

    final existingByServerId =
    await _getLocalRepresentativeByServerId(
      serverId,
    );

    if (existingByServerId != null) {
      await _applyRemoteSnapshot(
        localId: existingByServerId.id,
        serverData: serverData,
        requiredServerId: serverId,
      );

      return;
    }

    final username =
    _requireString(
      serverData['username'],
      field: 'representative.username',
    );

    // مهم:
    // إذا عندنا مندوب Local بنفس username ولم يحصل بعد على serverId،
    // لا ننشئ نسخة ثانية منه.
    //
    // هذا يحمي من حالة:
    // CREATE نجح بالسيرفر لكن التطبيق انقطع قبل حفظ serverId محلياً.
    final existingByUsername =
    await _getLocalRepresentativeByUsername(
      username,
    );

    if (existingByUsername != null &&
        _clean(existingByUsername.serverId) ==
            null) {
      await _applyRemoteSnapshot(
        localId: existingByUsername.id,
        serverData: serverData,
        requiredServerId: serverId,
      );

      return;
    }

    if (existingByUsername != null) {
      throw StateError(
        'اسم المستخدم $username موجود محلياً '
            'ومرتبط بمندوب آخر.',
      );
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
      database.representatives,
    )
        .insert(
      RepresentativesCompanion.insert(
        id: _uuid.v4(),
        serverId: Value(
          serverId,
        ),
        name: _stringOrEmpty(
          serverData['name'],
        ),
        username: username,
        phone: Value(
          _stringOrEmpty(
            serverData['phone'],
          ),
        ),
        officeName: Value(
          _stringOrEmpty(
            serverData['office_name'],
          ),
        ),
        officeAddress: Value(
          _stringOrEmpty(
            serverData['office_address'],
          ),
        ),
        officePhone: Value(
          _stringOrEmpty(
            serverData['office_phone'],
          ),
        ),
        locationLink: Value(
          _nullableString(
            serverData['location_url'],
          ),
        ),
        commissionPercentage: Value(
          _doubleOrZero(
            serverData['commission_rate'],
          ),
        ),
        maxDebtLimit: Value(
          _doubleOrZero(
            serverData['max_debt_limit'],
          ),
        ),
        isActive: Value(
          _remoteIsActive(
            serverData,
          ),
        ),
        serverVersion:
        const Value(0),
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
    );

    debugPrint(
      '[REPRESENTATIVE SYNC] Inserted remote representative: '
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
    await _getLocalRepresentative(
      localId,
    );

    if (existing == null) {
      throw StateError(
        'المندوب المحلي غير موجود أثناء حفظ Snapshot.',
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
        'Representative serverId mismatch. '
            'Expected $requiredServerId '
            'but received $responseServerId.',
      );
    }

    final duplicate =
    await _getLocalRepresentativeByServerId(
      requiredServerId,
    );

    if (duplicate != null &&
        duplicate.id != localId) {
      throw StateError(
        'Server representative UUID '
            '$requiredServerId '
            'is already mapped to another local representative.',
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
      database.representatives,
    )..where(
          (table) =>
          table.id.equals(
            localId,
          ),
    ))
        .write(
      RepresentativesCompanion(
        serverId: Value(
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
        username: serverData.containsKey(
          'username',
        )
            ? Value(
          _stringOrEmpty(
            serverData['username'],
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
        officeName: serverData.containsKey(
          'office_name',
        )
            ? Value(
          _stringOrEmpty(
            serverData['office_name'],
          ),
        )
            : const Value.absent(),
        officeAddress:
        serverData.containsKey(
          'office_address',
        )
            ? Value(
          _stringOrEmpty(
            serverData[
            'office_address'],
          ),
        )
            : const Value.absent(),
        officePhone:
        serverData.containsKey(
          'office_phone',
        )
            ? Value(
          _stringOrEmpty(
            serverData[
            'office_phone'],
          ),
        )
            : const Value.absent(),
        locationLink:
        serverData.containsKey(
          'location_url',
        )
            ? Value(
          _nullableString(
            serverData[
            'location_url'],
          ),
        )
            : const Value.absent(),
        commissionPercentage:
        serverData.containsKey(
          'commission_rate',
        )
            ? Value(
          _doubleOrZero(
            serverData[
            'commission_rate'],
          ),
        )
            : const Value.absent(),
        allowedPrices:
        serverData.containsKey(
          'allowed_prices',
        )
            ? Value(
          _stringOrEmpty(
            serverData[
            'allowed_prices'],
          ),
        )
            : const Value.absent(),
        maxDebtLimit:
        serverData.containsKey(
          'max_debt_limit',
        )
            ? Value(
          _doubleOrZero(
            serverData[
            'max_debt_limit'],
          ),
        )
            : const Value.absent(),
        isActive:
        serverData.containsKey(
          'is_active',
        ) ||
            serverData.containsKey(
              'status',
            )
            ? Value(
          _remoteIsActive(
            serverData,
          ),
        )
            : const Value.absent(),
        createdAt: Value(
          createdAt,
        ),
        updatedAt: Value(
          updatedAt,
        ),
      ),
    );
  }

  // ===========================================================================
  // LOCAL LOOKUPS
  // ===========================================================================

  Future<Representative?>
  _getLocalRepresentative(
      String localId,
      ) {
    final query =
    database.select(
      database.representatives,
    )..where(
          (table) =>
          table.id.equals(
            localId,
          ),
    );

    return query.getSingleOrNull();
  }

  Future<Representative?>
  _getLocalRepresentativeByServerId(
      String serverId,
      ) {
    final query =
    database.select(
      database.representatives,
    )..where(
          (table) =>
          table.serverId.equals(
            serverId,
          ),
    );

    return query.getSingleOrNull();
  }

  Future<Representative?>
  _getLocalRepresentativeByUsername(
      String username,
      ) {
    final query =
    database.select(
      database.representatives,
    )..where(
          (table) =>
          table.username.equals(
            username,
          ),
    );

    return query.getSingleOrNull();
  }

  // ===========================================================================
  // REQUEST BODIES
  // ===========================================================================

  Map<String, dynamic> _createBody(
      Representative representative, {
        required String password,
      }) {
    final result =
    <String, dynamic>{
      'name': representative.name.trim(),
      'username':
      representative.username.trim(),
      'password': password,
      'phone': representative.phone.trim(),
      'commission_rate':
      representative.commissionPercentage,
      'allowed_prices':
      representative.allowedPrices,
      'max_debt_limit':
      representative.maxDebtLimit,
    };

    _putOptionalString(
      result,
      'office_name',
      representative.officeName,
    );

    _putOptionalString(
      result,
      'office_phone',
      representative.officePhone,
    );

    _putOptionalString(
      result,
      'office_address',
      representative.officeAddress,
    );

    _putOptionalString(
      result,
      'location_url',
      representative.locationLink,
    );

    return result;
  }

  Map<String, dynamic> _updateBody(
      Representative representative,
      ) {
    final result =
    <String, dynamic>{
      'name': representative.name.trim(),
      'username':
      representative.username.trim(),
      'phone': representative.phone.trim(),
      'commission_rate':
      representative.commissionPercentage,
      'allowed_prices':
      representative.allowedPrices,
      'max_debt_limit':
      representative.maxDebtLimit,
    };

    _putOptionalString(
      result,
      'office_name',
      representative.officeName,
    );

    _putOptionalString(
      result,
      'office_phone',
      representative.officePhone,
    );

    _putOptionalString(
      result,
      'office_address',
      representative.officeAddress,
    );

    _putOptionalString(
      result,
      'location_url',
      representative.locationLink,
    );

    return result;
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

    final data = root['data'];

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
  _extractRepresentativeList(
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
        'representatives',
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
      'قائمة المندوبين في استجابة السيرفر غير صالحة.',
    );
  }

  // ===========================================================================
  // PAYLOAD
  // ===========================================================================

  Map<String, dynamic> _decodePayload(
      String payloadJson,
      ) {
    try {
      final decoded =
      jsonDecode(
        payloadJson,
      );

      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded,
        );
      }
    } catch (error) {
      throw StateError(
        'تعذر قراءة بيانات مزامنة المندوب: $error',
      );
    }

    throw StateError(
      'بيانات مزامنة المندوب غير صالحة.',
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
        'الحقل $field مفقود.',
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

    if (result.isEmpty ||
        result == '—') {
      return null;
    }

    return result;
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

  int _intOrDefault(
      dynamic value, {
        required int defaultValue,
      }) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value?.toString() ?? '',
    ) ??
        defaultValue;
  }

  bool _remoteIsActive(
      Map<String, dynamic> data,
      ) {
    final isActive = data['is_active'];

    if (isActive is bool) {
      return isActive;
    }

    if (isActive != null) {
      final text =
      isActive
          .toString()
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
    }

    final status =
    data['status']
        ?.toString()
        .trim()
        .toUpperCase();

    if (status == 'ACTIVE') {
      return true;
    }

    if (status == 'INACTIVE') {
      return false;
    }

    return true;
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
    final message = map['message'];

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
      '[REPRESENTATIVE SYNC][$action] '
          'HTTP ${error.response?.statusCode}',
    );

    debugPrint(
      '[REPRESENTATIVE SYNC][$action] '
          '${error.response?.data}',
    );
  }
}