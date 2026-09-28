import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../models/category_model.dart';

class CategoriesRepository {
  final AppDatabase database;
  final ApiClient apiClient;

  CategoriesRepository({
    required this.database,
    required this.apiClient,
  });

  Stream<List<CategoryModel>>
  watchCategories({
    bool activeOnly = true,
  }) {
    final query =
    database.select(
      database.categories,
    );

    if (activeOnly) {
      query.where(
            (table) =>
            table.isActive.equals(true),
      );
    }

    query.orderBy([
          (table) => OrderingTerm.asc(
        table.orderIndex,
      ),
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

  Future<List<CategoryModel>>
  getCategories({
    bool activeOnly = true,
  }) async {
    final query =
    database.select(
      database.categories,
    );

    if (activeOnly) {
      query.where(
            (table) =>
            table.isActive.equals(true),
      );
    }

    query.orderBy([
          (table) => OrderingTerm.asc(
        table.orderIndex,
      ),
          (table) => OrderingTerm.asc(
        table.nameAr,
      ),
    ]);

    final rows =
    await query.get();

    return rows
        .map(_mapRowToModel)
        .toList();
  }

  Future<CategoryModel?>
  getCategoryById(
      String id,
      ) async {
    final query =
    database.select(
      database.categories,
    )
      ..where(
            (table) =>
            table.id.equals(id),
      );

    final row =
    await query.getSingleOrNull();

    if (row == null) {
      return null;
    }

    return _mapRowToModel(
      row,
    );
  }

  Future<List<CategoryModel>>
  refreshFromServer() async {
    try {
      final response =
      await apiClient.get(
        '/categories',
        requiresBranch: false,
      );

      final rawData =
          response.data;

      if (rawData
      is! Map<String, dynamic>) {
        throw StateError(
          'استجابة التصنيفات غير صالحة.',
        );
      }

      if (rawData['success'] != true) {
        throw StateError(
          'فشل تحميل التصنيفات من السيرفر.',
        );
      }

      final rawCategories =
      rawData['data'];

      if (rawCategories is! List) {
        throw StateError(
          'بيانات التصنيفات غير صالحة.',
        );
      }

      final categories =
      rawCategories
          .whereType<Map>()
          .map(
            (item) =>
            CategoryModel
                .fromApiJson(
              Map<String, dynamic>
                  .from(item),
            ),
      )
          .where(
            (category) =>
        category
            .id.isNotEmpty,
      )
          .toList();

      await database.transaction(
            () async {
          for (final category
          in categories) {
            await database
                .into(
              database.categories,
            )
                .insertOnConflictUpdate(
              _modelToCompanion(
                category,
              ),
            );
          }
        },
      );

      return getCategories();
    } on DioException catch (error) {
      throw StateError(
        _messageFromDio(error),
      );
    }
  }

  Future<CategoryModel> createCategory({
    required String nameAr,
  }) async {
    final cleanName = nameAr.trim();

    if (cleanName.isEmpty) {
      throw StateError('اسم الصنف مطلوب.');
    }

    try {
      final response = await apiClient.post(
        '/categories',
        data: {
          'name_ar': cleanName,
        },
      );

      final raw = response.data;
      if (raw is! Map || raw['data'] is! Map) {
        throw StateError('استجابة إنشاء الصنف غير صالحة.');
      }

      final category = CategoryModel.fromApiJson(
        Map<String, dynamic>.from(raw['data'] as Map),
      );

      await database.into(database.categories).insertOnConflictUpdate(
            _modelToCompanion(category),
          );

      return category;
    } on DioException {
      return _saveLocalCategory(cleanName);
    }
  }

  Future<CategoryModel> _saveLocalCategory(String name) async {
    final now = DateTime.now();
    final category = CategoryModel(
      id: const Uuid().v4(),
      nameAr: name,
      createdAt: now,
      updatedAt: now,
    );

    await database.into(database.categories).insertOnConflictUpdate(
          _modelToCompanion(category),
        );

    return category;
  }

  Future<List<CategoryModel>>
  refreshOrGetLocal() async {
    try {
      return await refreshFromServer();
    } catch (_) {
      return getCategories();
    }
  }

  CategoryModel _mapRowToModel(
      Category row,
      ) {
    return CategoryModel(
      id: row.id,
      nameAr:
      row.nameAr,
      nameEn:
      row.nameEn ?? '',
      parentId:
      row.parentId,
      level:
      row.level,
      path:
      row.path,
      imageUrl:
      row.imageUrl,
      orderIndex:
      row.orderIndex,
      isActive:
      row.isActive,
      createdAt:
      row.createdAt,
      updatedAt:
      row.updatedAt,
    );
  }

  CategoriesCompanion
  _modelToCompanion(
      CategoryModel category,
      ) {
    return CategoriesCompanion(
      id: Value(category.id),
      nameAr:
      Value(category.nameAr),
      nameEn: Value(
        category.nameEn
            .trim()
            .isEmpty
            ? null
            : category.nameEn.trim(),
      ),
      parentId:
      Value(category.parentId),
      level:
      Value(category.level),
      path:
      Value(category.path),
      imageUrl:
      Value(category.imageUrl),
      orderIndex:
      Value(category.orderIndex),
      isActive:
      Value(category.isActive),
      createdAt:
      Value(category.createdAt),
      updatedAt:
      Value(category.updatedAt),
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

    return 'تعذر تحميل التصنيفات.';
  }
}