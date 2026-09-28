import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../models/unit_model.dart';

class UnitsRepository {
  final AppDatabase database;
  final ApiClient apiClient;

  UnitsRepository({
    required this.database,
    required this.apiClient,
  });

  Stream<List<UnitModel>> watchUnits({
    bool activeOnly = true,
  }) {
    final query =
    database.select(database.units);

    if (activeOnly) {
      query.where(
            (table) => table.isActive.equals(true),
      );
    }

    query.orderBy([
          (table) => OrderingTerm.asc(
        table.nameAr,
      ),
    ]);

    return query.watch().map(
          (rows) => rows
          .map(_mapRowToModel)
          .toList(),
    );
  }

  Future<List<UnitModel>> getUnits({
    bool activeOnly = true,
  }) async {
    final query =
    database.select(database.units);

    if (activeOnly) {
      query.where(
            (table) => table.isActive.equals(true),
      );
    }

    query.orderBy([
          (table) => OrderingTerm.asc(
        table.nameAr,
      ),
    ]);

    final rows = await query.get();

    return rows
        .map(_mapRowToModel)
        .toList();
  }

  Future<List<UnitModel>>
  getBaseUnits() async {
    final query =
    database.select(database.units)
      ..where(
            (table) =>
        table.isActive.equals(true) &
        table.isBaseUnit.equals(true),
      )
      ..orderBy([
            (table) => OrderingTerm.asc(
          table.nameAr,
        ),
      ]);

    final rows = await query.get();

    return rows
        .map(_mapRowToModel)
        .toList();
  }

  Future<UnitModel?> getUnitById(
      String id,
      ) async {
    final query =
    database.select(database.units)
      ..where(
            (table) => table.id.equals(id),
      );

    final row =
    await query.getSingleOrNull();

    if (row == null) {
      return null;
    }

    return _mapRowToModel(row);
  }

  Future<List<UnitModel>>
  refreshFromServer() async {
    try {
      final response = await apiClient.get(
        '/units',
        requiresBranch: false,
      );

      final rawData = response.data;

      if (rawData
      is! Map<String, dynamic>) {
        throw StateError(
          'استجابة وحدات القياس غير صالحة.',
        );
      }

      final success =
      rawData['success'];

      if (success != true) {
        throw StateError(
          'فشل تحميل وحدات القياس من السيرفر.',
        );
      }

      final rawUnits =
      rawData['data'];

      if (rawUnits is! List) {
        throw StateError(
          'بيانات وحدات القياس غير صالحة.',
        );
      }

      final units = rawUnits
          .whereType<Map>()
          .map(
            (item) =>
            UnitModel.fromApiJson(
              Map<String, dynamic>.from(
                item,
              ),
            ),
      )
          .where(
            (unit) => unit.id.isNotEmpty,
      )
          .toList();

      await database.transaction(
            () async {
          for (final unit in units) {
            await database
                .into(database.units)
                .insertOnConflictUpdate(
              _modelToCompanion(
                unit,
              ),
            );
          }
        },
      );

      return getUnits();
    } on DioException catch (error) {
      throw StateError(
        _messageFromDio(error),
      );
    }
  }

  /// يحاول التحديث، وإذا فشل الإنترنت
  /// يرجع البيانات المحلية الموجودة.
  Future<List<UnitModel>>
  refreshOrGetLocal() async {
    try {
      return await refreshFromServer();
    } catch (_) {
      return getUnits();
    }
  }

  Future<UnitModel> createUnit({
    required String nameAr,
    String? symbol,
    String? parentUnitId,
    double conversionFactor = 1,
  }) async {
    final cleanName = nameAr.trim();
    if (cleanName.isEmpty) {
      throw StateError('اسم وحدة القياس مطلوب.');
    }

    final existing = await getUnits(activeOnly: false);
    for (final unit in existing) {
      if (unit.nameAr.trim() == cleanName) {
        return unit;
      }
    }

    final cleanSymbol = (symbol ?? '').trim().isEmpty ? cleanName : symbol!.trim();
    final parent = parentUnitId?.trim() ?? '';
    final factor = conversionFactor <= 1 || parent.isEmpty ? 1.0 : conversionFactor;
    final isBase = factor <= 1;

    try {
      final response = await apiClient.post(
        '/units',
        data: {
          'name_ar': cleanName,
          'symbol': cleanSymbol,
          'is_base_unit': isBase,
          'conversion_factor': factor,
          if (!isBase) 'parent_unit_id': parent,
        },
      );

      final raw = response.data;
      Map<String, dynamic>? json;
      if (raw is Map && raw['data'] is Map) {
        json = Map<String, dynamic>.from(raw['data'] as Map);
      } else if (raw is Map && raw['id'] != null) {
        json = Map<String, dynamic>.from(raw);
      }

      if (json == null || '${json['id'] ?? ''}'.trim().isEmpty) {
        throw StateError('استجابة إنشاء الوحدة غير صالحة.');
      }

      final unit = UnitModel.fromApiJson(json);
      final saved = unit.conversionFactor == factor
          ? unit
          : UnitModel(
              id: unit.id,
              nameAr: unit.nameAr,
              nameEn: unit.nameEn,
              symbol: unit.symbol,
              parentUnitId: isBase ? null : parent,
              conversionFactor: factor,
              isBaseUnit: isBase,
              isActive: unit.isActive,
              createdAt: unit.createdAt,
              updatedAt: unit.updatedAt,
            );
      await database.into(database.units).insertOnConflictUpdate(
            _modelToCompanion(saved),
          );
      return saved;
    } on DioException {
      return _saveLocalUnit(
        cleanName,
        cleanSymbol,
        parentUnitId: isBase ? null : parent,
        conversionFactor: factor,
        isBaseUnit: isBase,
      );
    }
  }

  Future<UnitModel> _saveLocalUnit(
    String name,
    String symbol, {
    String? parentUnitId,
    double conversionFactor = 1,
    bool isBaseUnit = true,
  }) async {
    final now = DateTime.now();
    final unit = UnitModel(
      id: const Uuid().v4(),
      nameAr: name,
      symbol: symbol,
      parentUnitId: parentUnitId,
      conversionFactor: conversionFactor,
      isBaseUnit: isBaseUnit,
      createdAt: now,
      updatedAt: now,
    );

    await database.into(database.units).insertOnConflictUpdate(
          _modelToCompanion(unit),
        );

    return unit;
  }

  UnitModel _mapRowToModel(
      Unit row,
      ) {
    return UnitModel(
      id: row.id,
      nameAr: row.nameAr,
      nameEn: row.nameEn ?? '',
      symbol: row.symbol,
      parentUnitId:
      row.parentUnitId,
      conversionFactor:
      row.conversionFactor,
      isBaseUnit:
      row.isBaseUnit,
      isActive:
      row.isActive,
      createdAt:
      row.createdAt,
      updatedAt:
      row.updatedAt,
    );
  }

  UnitsCompanion _modelToCompanion(
      UnitModel unit,
      ) {
    return UnitsCompanion(
      id: Value(unit.id),
      nameAr:
      Value(unit.nameAr),
      nameEn: Value(
        unit.nameEn.trim().isEmpty
            ? null
            : unit.nameEn.trim(),
      ),
      symbol:
      Value(unit.symbol),
      parentUnitId:
      Value(unit.parentUnitId),
      conversionFactor:
      Value(
        unit.conversionFactor,
      ),
      isBaseUnit:
      Value(unit.isBaseUnit),
      isActive:
      Value(unit.isActive),
      createdAt:
      Value(unit.createdAt),
      updatedAt:
      Value(unit.updatedAt),
    );
  }

  String _messageFromDio(
      DioException error,
      ) {
    final data =
        error.response?.data;

    if (data is Map) {
      final message =
      data['message'];

      if (message is String &&
          message.trim().isNotEmpty) {
        return message;
      }
    }

    if (error.response?.statusCode ==
        401) {
      return 'انتهت جلسة تسجيل الدخول.';
    }

    if (error.type ==
        DioExceptionType
            .connectionError ||
        error.type ==
            DioExceptionType
                .connectionTimeout ||
        error.type ==
            DioExceptionType
                .receiveTimeout ||
        error.type ==
            DioExceptionType
                .sendTimeout) {
      return 'تعذر الاتصال بالسيرفر.';
    }

    return 'تعذر تحميل وحدات القياس.';
  }
}