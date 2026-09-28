import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_operation.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../models/representative_model.dart';

class RepresentativesLocalRepository {
  final AppDatabase database;
  final SyncQueueRepository syncQueue;

  static const Uuid _uuid = Uuid();

  RepresentativesLocalRepository({
    required this.database,
    required this.syncQueue,
  });

  Future<List<RepresentativeModel>>
  getRepresentatives() async {
    final representativeRows = await (database.select(
      database.representatives,
    )
      ..where(
            (table) =>
            table.deletedAt.isNull(),
      )
      ..orderBy([
            (table) => OrderingTerm.asc(
          table.name,
        ),
      ]))
        .get();

    final salesRows = await (database.select(
      database.sales,
    )..where(
          (table) =>
          table.deletedAt.isNull(),
    ))
        .get();

    final saleItemRows =
    await database
        .select(
      database.saleItems,
    )
        .get();

    final commissionRows =
    await database
        .select(
      database.representativeCommissionEntries,
    )
        .get();

    final paymentRows =
    await database
        .select(
      database.representativePayments,
    )
        .get();

    final salesByRepresentative =
    <String, List<Sale>>{};

    for (final sale in salesRows) {
      final representativeId =
          sale.representativeId;

      if (representativeId == null ||
          representativeId.isEmpty) {
        continue;
      }

      salesByRepresentative
          .putIfAbsent(
        representativeId,
            () => [],
      )
          .add(sale);
    }

    final itemsBySale =
    <String, List<SaleItem>>{};

    for (final item in saleItemRows) {
      itemsBySale
          .putIfAbsent(
        item.saleId,
            () => [],
      )
          .add(item);
    }

    final commissionsByRepresentative =
    <String,
        List<
            RepresentativeCommissionEntry>>{};

    for (final entry in commissionRows) {
      commissionsByRepresentative
          .putIfAbsent(
        entry.representativeId,
            () => [],
      )
          .add(entry);
    }

    final paymentsByRepresentative =
    <String,
        List<RepresentativePayment>>{};

    for (final payment in paymentRows) {
      paymentsByRepresentative
          .putIfAbsent(
        payment.representativeId,
            () => [],
      )
          .add(payment);
    }

    final result =
    <RepresentativeModel>[];

    for (final row
    in representativeRows) {
      final representativeSales =
          salesByRepresentative[row.id] ??
              const <Sale>[];

      final commissionEntries =
          commissionsByRepresentative[
          row.id] ??
              const <
                  RepresentativeCommissionEntry>[];

      final representativePayments =
          paymentsByRepresentative[
          row.id] ??
              const <
                  RepresentativePayment>[];

      double totalSales = 0;
      int soldPieces = 0;

      for (final sale
      in representativeSales) {
        totalSales += sale.total;

        final items =
            itemsBySale[sale.id] ??
                const <SaleItem>[];

        for (final item in items) {
          soldPieces +=
              item.quantity.round();
        }
      }

      final totalCommission =
      commissionEntries.fold<double>(
        0,
            (sum, entry) =>
        sum + entry.amount,
      );

      final paidCommission =
      representativePayments
          .fold<double>(
        0,
            (sum, payment) =>
        sum + payment.amount,
      );

      final remaining =
          totalCommission -
              paidCommission;

      result.add(
        RepresentativeModel(
          id: row.id,
          name: row.name,
          username: row.username,
          phone: row.phone,
          officeName: row.officeName,
          officeAddress:
          row.officeAddress,
          officePhone:
          row.officePhone,
          locationLink:
          row.locationLink,
          commissionPercentage:
          row.commissionPercentage,
          allowedPrices: row.allowedPrices,
          invoicesCount:
          representativeSales.length,
          soldPieces: soldPieces,
          totalSales: totalSales,
          totalCommission:
          totalCommission,
          paidCommission:
          paidCommission,
          remainingCommission:
          remaining < 0
              ? 0
              : remaining,
          isActive: row.isActive,
          serverVersion:
          row.serverVersion,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
        ),
      );
    }

    return result;
  }

  Future<RepresentativeModel?>
  getRepresentativeById(
      String id,
      ) async {
    final representatives =
    await getRepresentatives();

    try {
      return representatives.firstWhere(
            (representative) =>
        representative.id == id,
      );
    } catch (_) {
      return null;
    }
  }

  // ===========================================================================
  // CREATE
  // ===========================================================================

  Future<RepresentativeModel>
  createRepresentative({
    required String name,
    required String username,
    required String password,
    String phone = '',
    String officeName = '',
    String officeAddress = '',
    String officePhone = '',
    String? locationLink,
    required double commissionPercentage,
    String allowedPrices = 'wholesale,representative,retail',
  }) async {
    final cleanName =
    name.trim();

    final cleanUsername =
    username.trim();

    final cleanPassword =
    password.trim();

    final cleanPhone =
    phone.trim();

    if (cleanName.isEmpty) {
      throw StateError(
        'اسم المندوب مطلوب.',
      );
    }

    if (cleanUsername.isEmpty) {
      throw StateError(
        'اسم المستخدم مطلوب.',
      );
    }

    if (cleanPassword.isEmpty) {
      throw StateError(
        'كلمة المرور مطلوبة.',
      );
    }

    // الـAPI يعتبر الهاتف حقلاً مطلوباً.
    if (cleanPhone.isEmpty) {
      throw StateError(
        'رقم الهاتف مطلوب.',
      );
    }

    if (commissionPercentage < 0) {
      throw StateError(
        'العمولة بالدينار لا تكون سالبة.',
      );
    }

    final existing =
    await (database.select(
      database.representatives,
    )..where(
          (table) =>
          table.username.equals(
            cleanUsername,
          ),
    ))
        .getSingleOrNull();

    if (existing != null &&
        existing.deletedAt == null) {
      throw StateError(
        'اسم المستخدم مستخدم مسبقاً.',
      );
    }

    final now =
    DateTime.now();

    final representative =
    RepresentativeModel(
      id: _uuid.v4(),
      name: cleanName,
      username: cleanUsername,
      phone: cleanPhone,
      officeName:
      officeName.trim(),
      officeAddress:
      officeAddress.trim(),
      officePhone:
      officePhone.trim(),
      locationLink:
      _clean(locationLink),
      commissionPercentage:
      commissionPercentage,
      allowedPrices: allowedPrices,
      isActive: true,
      serverVersion: 0,
      createdAt: now,
      updatedAt: now,
    );

    await database.transaction(
          () async {
        await database
            .into(
          database.representatives,
        )
            .insert(
          RepresentativesCompanion.insert(
            id: representative.id,
            serverId:
            const Value(null),
            name: representative.name,
            username:
            representative.username,
            phone: Value(
              representative.phone,
            ),
            officeName: Value(
              representative.officeName,
            ),
            officeAddress: Value(
              representative
                  .officeAddress,
            ),
            officePhone: Value(
              representative.officePhone,
            ),
            locationLink: Value(
              representative.locationLink,
            ),
            commissionPercentage:
            Value(
              representative
                  .commissionPercentage,
            ),
            allowedPrices: Value(
              representative.allowedPrices,
            ),
            isActive:
            const Value(true),
            serverVersion:
            const Value(0),
            createdAt: now,
            updatedAt: now,
          ),
        );

        // كلمة المرور موجودة فقط داخل CREATE Outbox payload.
        // لا يتم تخزينها داخل جدول representatives.
        //
        // عند نجاح المزامنة يقوم SyncQueueRepository.markSynced()
        // بحذف سجل الـOutbox بالكامل.
        await syncQueue.enqueue(
          entityType:
          'representative',
          entityId:
          representative.id,
          operation:
          SyncOperation.create,
          idempotencyKey:
          representative.id,
          payload: {
            'name':
            representative.name,
            'username':
            representative.username,
            'password':
            cleanPassword,
            'phone':
            representative.phone,
            'commission_rate':
            representative
                .commissionPercentage,
            'office_name':
            representative.officeName,
            'office_phone':
            representative.officePhone,
            'office_address':
            representative
                .officeAddress,
            'location_url':
            representative.locationLink,
          },
        );
      },
    );

    return representative;
  }

  // ===========================================================================
  // UPDATE
  // ===========================================================================

  Future<RepresentativeModel>
  updateRepresentative(
      RepresentativeModel representative, {
        required String name,
        required String username,
        String phone = '',
        String officeName = '',
        String officeAddress = '',
        String officePhone = '',
        String? locationLink,
        required double commissionPercentage,
        String allowedPrices = 'wholesale,representative,retail',
      }) async {
    final cleanName =
    name.trim();

    final cleanUsername =
    username.trim();

    if (cleanName.isEmpty) {
      throw StateError(
        'اسم المندوب مطلوب.',
      );
    }

    if (cleanUsername.isEmpty) {
      throw StateError(
        'اسم المستخدم مطلوب.',
      );
    }

    if (commissionPercentage < 0) {
      throw StateError(
        'العمولة بالدينار لا تكون سالبة.',
      );
    }

    final duplicate =
    await (database.select(
      database.representatives,
    )..where(
          (table) =>
      table.username.equals(
        cleanUsername,
      ) &
      table.id
          .equals(
        representative.id,
      )
          .not(),
    ))
        .getSingleOrNull();

    if (duplicate != null &&
        duplicate.deletedAt == null) {
      throw StateError(
        'اسم المستخدم مستخدم مسبقاً.',
      );
    }

    final now =
    DateTime.now();

    final updated =
    representative.copyWith(
      name: cleanName,
      username: cleanUsername,
      phone: phone.trim(),
      officeName:
      officeName.trim(),
      officeAddress:
      officeAddress.trim(),
      officePhone:
      officePhone.trim(),
      locationLink:
      _clean(locationLink),
      commissionPercentage:
      commissionPercentage,
      allowedPrices: allowedPrices,
      updatedAt: now,
    );

    await database.transaction(
          () async {
        final affected =
        await (database.update(
          database.representatives,
        )..where(
              (table) =>
              table.id.equals(
                representative.id,
              ),
        ))
            .write(
          RepresentativesCompanion(
            name: Value(
              updated.name,
            ),
            username: Value(
              updated.username,
            ),
            phone: Value(
              updated.phone,
            ),
            officeName: Value(
              updated.officeName,
            ),
            officeAddress: Value(
              updated.officeAddress,
            ),
            officePhone: Value(
              updated.officePhone,
            ),
            locationLink: Value(
              updated.locationLink,
            ),
            commissionPercentage:
            Value(
              updated
                  .commissionPercentage,
            ),
            allowedPrices: Value(
              updated.allowedPrices,
            ),
            updatedAt:
            Value(now),
          ),
        );

        if (affected == 0) {
          throw StateError(
            'المندوب غير موجود.',
          );
        }

        await syncQueue.enqueue(
          entityType:
          'representative',
          entityId:
          representative.id,
          operation:
          SyncOperation.update,
          payload:
          updated.toSyncJson(),
        );
      },
    );

    return updated;
  }

  // ===========================================================================
  // ACTIVE STATUS
  // ===========================================================================

  Future<void> setRepresentativeActive({
    required RepresentativeModel representative,
    required bool isActive,
  }) async {
    final now =
    DateTime.now();

    await database.transaction(
          () async {
        final affected =
        await (database.update(
          database.representatives,
        )..where(
              (table) =>
              table.id.equals(
                representative.id,
              ),
        ))
            .write(
          RepresentativesCompanion(
            isActive:
            Value(isActive),
            updatedAt:
            Value(now),
          ),
        );

        if (affected == 0) {
          throw StateError(
            'المندوب غير موجود.',
          );
        }

        final updated =
        representative.copyWith(
          isActive: isActive,
          updatedAt: now,
        );

        await syncQueue.enqueue(
          entityType:
          'representative',
          entityId:
          representative.id,
          operation:
          SyncOperation.update,
          payload:
          updated.toSyncJson(),
        );
      },
    );
  }

  // ===========================================================================
  // COMMISSION PAYMENT
  // ===========================================================================

  Future<void> registerPayment({
    required String representativeId,
    required double amount,
    String method = 'CASH',
    String? note,
    String? userId,
  }) async {
    if (amount <= 0) {
      throw StateError(
        'مبلغ الدفع يجب أن يكون أكبر من صفر.',
      );
    }

    final now =
    DateTime.now();

    final paymentId =
    _uuid.v4();

    final voucherNumber =
    _paymentNumber(
      paymentId,
      now,
    );

    await database.transaction(
          () async {
        final representative =
        await (database.select(
          database.representatives,
        )..where(
              (table) =>
              table.id.equals(
                representativeId,
              ),
        ))
            .getSingleOrNull();

        if (representative == null ||
            representative.deletedAt !=
                null) {
          throw StateError(
            'المندوب غير موجود.',
          );
        }

        final commissionRows =
        await (database.select(
          database
              .representativeCommissionEntries,
        )..where(
              (table) =>
              table.representativeId
                  .equals(
                representativeId,
              ),
        ))
            .get();

        final paymentRows =
        await (database.select(
          database
              .representativePayments,
        )..where(
              (table) =>
              table.representativeId
                  .equals(
                representativeId,
              ),
        ))
            .get();

        final totalCommission =
        commissionRows.fold<double>(
          0,
              (sum, row) =>
          sum + row.amount,
        );

        final totalPaid =
        paymentRows.fold<double>(
          0,
              (sum, row) =>
          sum + row.amount,
        );

        final remaining =
            totalCommission -
                totalPaid;

        if (remaining <= 0) {
          throw StateError(
            'لا توجد عمولة مستحقة لهذا المندوب.',
          );
        }

        if (amount > remaining) {
          throw StateError(
            'المبلغ أكبر من العمولة المستحقة.',
          );
        }

        await database
            .into(
          database
              .representativePayments,
        )
            .insert(
          RepresentativePaymentsCompanion
              .insert(
            id: paymentId,
            voucherNumber:
            voucherNumber,
            representativeId:
            representativeId,
            method:
            Value(method),
            amount: amount,
            note: Value(
              _clean(note),
            ),
            userId: Value(
              _clean(userId),
            ),
            serverVersion:
            const Value(0),
            createdAt: now,
          ),
        );

        await syncQueue.enqueue(
          entityType:
          'representative_payment',
          entityId:
          paymentId,
          operation:
          SyncOperation.create,
          idempotencyKey:
          paymentId,
          payload: {
            'id': paymentId,
            'voucher_number':
            voucherNumber,
            'representative_id':
            representativeId,
            'method': method,
            'amount': amount,
            'note':
            _clean(note),
            'user_id':
            _clean(userId),
            'created_at': now
                .toUtc()
                .toIso8601String(),
            'version': 0,
          },
        );
      },
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _paymentNumber(
      String paymentId,
      DateTime date,
      ) {
    final suffix = paymentId
        .replaceAll(
      '-',
      '',
    )
        .substring(
      0,
      6,
    )
        .toUpperCase();

    return 'REP-PAY-${date.millisecondsSinceEpoch}-$suffix';
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
}