import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../models/cashbox_report_model.dart';

class CashboxLocalRepository {
  final AppDatabase database;

  static const Uuid _uuid =
  Uuid();

  CashboxLocalRepository({
    required this.database,
  });

  // ===========================================================================
  // OPEN SESSION
  // ===========================================================================

  Future<CashboxSession> openSession({
    required double openingBalance,
    String? note,
  }) async {
    if (openingBalance < 0) {
      throw StateError(
        'رصيد بداية النقد لا يمكن أن يكون سالباً.',
      );
    }

    final existingOpen =
    await getOpenSession();

    if (existingOpen != null) {
      throw StateError(
        'توجد جلسة النقد مفتوحة حالياً.',
      );
    }

    final now =
    DateTime.now();

    final businessDate =
    _dateKey(
      now,
    );

    final sessionId =
    _uuid.v4();

    await database.transaction(
          () async {
        await database
            .into(
          database.cashboxSessions,
        )
            .insert(
          CashboxSessionsCompanion.insert(
            id:
            sessionId,
            businessDate:
            businessDate,
            openingBalance:
            Value(
              openingBalance,
            ),
            note:
            Value(
              _clean(
                note,
              ),
            ),
            status:
            const Value(
              'OPEN',
            ),
            openedAt:
            now,
            createdAt:
            now,
            updatedAt:
            now,
          ),
        );

        // ===============================================================
        // RECOVER ORPHAN SALES
        // ===============================================================
        //
        // هذا مهم لحالة الانتقال من V20 -> V21:
        //
        // إذا المستخدم أغلق النقد ثم أنشأ فاتورة قبل إضافة
        // نظام Sessions، تكون الفاتورة cashboxSessionId = NULL.
        //
        // عند فتح جلسة جديدة بنفس اليوم نربط هذه الفواتير بها.
        // ===============================================================

        final previousClosedSession =
        await (database.select(
          database.cashboxSessions,
        )
          ..where(
                (table) =>
            table.businessDate.equals(
              businessDate,
            ) &
            table.status.equals(
              'CLOSED',
            ),
          )
          ..orderBy([
                (table) =>
                OrderingTerm.desc(
                  table.closedAt,
                ),
          ]))
            .getSingleOrNull();

        final orphanSales =
        await (database.select(
          database.sales,
        )
          ..where(
                (table) =>
            table.cashboxSessionId.isNull() &
            table.deletedAt.isNull(),
          ))
            .get();

        for (final sale in orphanSales) {
          if (_dateKey(
            sale.createdAt,
          ) !=
              businessDate) {
            continue;
          }

          final lastClosedAt =
              previousClosedSession?.closedAt;

          if (lastClosedAt != null &&
              sale.createdAt.isBefore(
                lastClosedAt,
              )) {
            continue;
          }

          await (database.update(
            database.sales,
          )
            ..where(
                  (table) =>
                  table.id.equals(
                    sale.id,
                  ),
            ))
              .write(
            SalesCompanion(
              cashboxSessionId:
              Value(
                sessionId,
              ),
              updatedAt:
              Value(
                now,
              ),
            ),
          );
        }
      },
    );

    final created =
    await getSessionById(
      sessionId,
    );

    if (created == null) {
      throw StateError(
        'تعذر فتح جلسة النقد.',
      );
    }

    return created;
  }

  // ===========================================================================
  // OPEN SESSION QUERY
  // ===========================================================================

  Future<CashboxSession?>
  getOpenSession() {
    final query =
    database.select(
      database.cashboxSessions,
    )
      ..where(
            (table) =>
            table.status.equals(
              'OPEN',
            ),
      )
      ..orderBy([
            (table) =>
            OrderingTerm.desc(
              table.openedAt,
            ),
      ])
      ..limit(
        1,
      );

    return query.getSingleOrNull();
  }

  Future<CashboxSession?>
  getTodayOpenSession() async {
    final session =
    await getOpenSession();

    if (session == null) {
      return null;
    }

    if (session.businessDate !=
        _dateKey(
          DateTime.now(),
        )) {
      return null;
    }

    return session;
  }

  Future<CashboxSession?> getSessionById(
      String sessionId,
      ) {
    final id =
    sessionId.trim();

    if (id.isEmpty) {
      return Future.value(
        null,
      );
    }

    return (database.select(
      database.cashboxSessions,
    )
      ..where(
            (table) =>
            table.id.equals(
              id,
            ),
      ))
        .getSingleOrNull();
  }

  // ===========================================================================
  // UPDATE OPENING BALANCE
  // ===========================================================================

  Future<void> updateOpeningBalance({
    required String sessionId,
    required double openingBalance,
  }) async {
    if (openingBalance < 0) {
      throw StateError(
        'رصيد بداية النقد لا يمكن أن يكون سالباً.',
      );
    }

    final session =
    await getSessionById(
      sessionId,
    );

    if (session == null) {
      throw StateError(
        'جلسة النقد غير موجودة.',
      );
    }

    if (session.status
        .trim()
        .toUpperCase() !=
        'OPEN') {
      throw StateError(
        'لا يمكن تعديل رصيد جلسة النقد مغلقة.',
      );
    }

    await (database.update(
      database.cashboxSessions,
    )
      ..where(
            (table) =>
            table.id.equals(
              session.id,
            ),
      ))
        .write(
      CashboxSessionsCompanion(
        openingBalance:
        Value(
          openingBalance,
        ),
        updatedAt:
        Value(
          DateTime.now(),
        ),
      ),
    );
  }

  // ===========================================================================
  // CLOSE SESSION
  // ===========================================================================

  Future<void> closeSession({
    required String sessionId,
    required double countedCash,
    String? note,
  }) async {
    if (countedCash < 0) {
      throw StateError(
        'المبلغ المعدود لا يمكن أن يكون سالباً.',
      );
    }

    final session =
    await getSessionById(
      sessionId,
    );

    if (session == null) {
      throw StateError(
        'جلسة النقد غير موجودة.',
      );
    }

    if (session.status
        .trim()
        .toUpperCase() !=
        'OPEN') {
      throw StateError(
        'جلسة النقد مغلقة مسبقاً.',
      );
    }

    final report =
    await _buildSessionReport(
      session,
      useSnapshotIfClosed: false,
    );

    final difference =
        countedCash -
            report.expectedCash;

    final now =
    DateTime.now();

    await (database.update(
      database.cashboxSessions,
    )
      ..where(
            (table) =>
            table.id.equals(
              session.id,
            ),
      ))
        .write(
      CashboxSessionsCompanion(
        totalSales:
        Value(
          report.totalSales,
        ),
        cashSales:
        Value(
          report.cashSales,
        ),
        creditSales:
        Value(
          report.creditSales,
        ),
        partialSales:
        Value(
          report.partialSales,
        ),
        cashReceived:
        Value(
          report.cashReceived,
        ),
        remainingAmount:
        Value(
          report.remainingAmount,
        ),
        invoicesCount:
        Value(
          report.invoicesCount,
        ),
        expectedCash:
        Value(
          report.expectedCash,
        ),
        countedCash:
        Value(
          countedCash,
        ),
        difference:
        Value(
          difference,
        ),
        status:
        const Value(
          'CLOSED',
        ),
        note:
        Value(
          _clean(
            note,
          ) ??
              session.note,
        ),
        closedAt:
        Value(
          now,
        ),
        updatedAt:
        Value(
          now,
        ),
      ),
    );
  }

  // ===========================================================================
  // TODAY
  // ===========================================================================

  Future<CashboxDayReport>
  getTodayReport() {
    return getDayReport(
      DateTime.now(),
    );
  }

  // ===========================================================================
  // DAY REPORT
  // ===========================================================================

  Future<CashboxDayReport> getDayReport(
      DateTime date,
      ) async {
    final businessDate =
    _dateKey(
      date,
    );

    final sessions =
    await (database.select(
      database.cashboxSessions,
    )
      ..where(
            (table) =>
            table.businessDate.equals(
              businessDate,
            ),
      )
      ..orderBy([
            (table) =>
            OrderingTerm.asc(
              table.openedAt,
            ),
      ]))
        .get();

    final sessionReports =
    <CashboxSessionReport>[];

    for (final session in sessions) {
      sessionReports.add(
        await _buildSessionReport(
          session,
        ),
      );
    }

    final unassignedSales =
    await _getUnassignedSalesForDay(
      date,
    );

    final unassignedMetrics =
    await _calculateSalesMetrics(
      unassignedSales,
    );

    final allInvoices =
    <CashboxInvoiceModel>[];

    final allSoldItems =
    <CashboxSoldItemModel>[];

    double totalSales =
        unassignedMetrics.totalSales;

    double cashSales =
        unassignedMetrics.cashSales;

    double creditSales =
        unassignedMetrics.creditSales;

    double partialSales =
        unassignedMetrics.partialSales;

    double cashReceived =
        unassignedMetrics.cashReceived;

    double remainingAmount =
        unassignedMetrics.remainingAmount;

    double expectedCash =
        unassignedMetrics.cashReceived;

    int invoicesCount =
        unassignedMetrics.invoicesCount;

    for (final session
    in sessionReports) {
      totalSales +=
          session.totalSales;

      cashSales +=
          session.cashSales;

      creditSales +=
          session.creditSales;

      partialSales +=
          session.partialSales;

      cashReceived +=
          session.cashReceived;

      remainingAmount +=
          session.remainingAmount;

      expectedCash +=
          session.expectedCash;

      invoicesCount +=
          session.invoicesCount;

      allInvoices.addAll(
        session.invoices,
      );

      allSoldItems.addAll(
        session.soldItems,
      );
    }

    allInvoices.addAll(
      unassignedMetrics.invoices,
    );

    allSoldItems.addAll(
      unassignedMetrics.soldItems,
    );

    allInvoices.sort(
          (a, b) =>
          b.createdAt.compareTo(
            a.createdAt,
          ),
    );

    final mergedSoldItems =
    _mergeSoldItems(
      allSoldItems,
    );

    return CashboxDayReport(
      businessDate:
      businessDate,
      totalSales:
      totalSales,
      cashSales:
      cashSales,
      creditSales:
      creditSales,
      partialSales:
      partialSales,
      cashReceived:
      cashReceived,
      remainingAmount:
      remainingAmount,
      invoicesCount:
      invoicesCount,
      expectedCash:
      expectedCash,
      unassignedInvoicesCount:
      unassignedMetrics.invoicesCount,
      sessions:
      sessionReports,
      invoices:
      allInvoices,
      soldItems:
      mergedSoldItems,
    );
  }

  // ===========================================================================
  // SESSION REPORT
  // ===========================================================================

  Future<CashboxSessionReport>
  getSessionReport(
      String sessionId,
      ) async {
    final session =
    await getSessionById(
      sessionId,
    );

    if (session == null) {
      throw StateError(
        'جلسة النقد غير موجودة.',
      );
    }

    return _buildSessionReport(
      session,
    );
  }

  Future<CashboxSessionReport>
  _buildSessionReport(
      CashboxSession session, {
        bool useSnapshotIfClosed = true,
      }) async {
    final sales =
    await (database.select(
      database.sales,
    )
      ..where(
            (table) =>
        table.cashboxSessionId.equals(
          session.id,
        ) &
        table.deletedAt.isNull(),
      )
      ..orderBy([
            (table) =>
            OrderingTerm.desc(
              table.createdAt,
            ),
      ]))
        .get();

    final liveMetrics =
    await _calculateSalesMetrics(
      sales,
    );

    final closed =
        session.status
            .trim()
            .toUpperCase() ==
            'CLOSED';

    final shouldUseSnapshot =
        closed &&
            useSnapshotIfClosed;

    return CashboxSessionReport(
      id:
      session.id,
      businessDate:
      session.businessDate,
      openingBalance:
      session.openingBalance,
      totalSales:
      shouldUseSnapshot
          ? session.totalSales
          : liveMetrics.totalSales,
      cashSales:
      shouldUseSnapshot
          ? session.cashSales
          : liveMetrics.cashSales,
      creditSales:
      shouldUseSnapshot
          ? session.creditSales
          : liveMetrics.creditSales,
      partialSales:
      shouldUseSnapshot
          ? session.partialSales
          : liveMetrics.partialSales,
      cashReceived:
      shouldUseSnapshot
          ? session.cashReceived
          : liveMetrics.cashReceived,
      remainingAmount:
      shouldUseSnapshot
          ? session.remainingAmount
          : liveMetrics.remainingAmount,
      invoicesCount:
      shouldUseSnapshot
          ? session.invoicesCount
          : liveMetrics.invoicesCount,
      expectedCash:
      shouldUseSnapshot
          ? session.expectedCash
          : session.openingBalance +
          liveMetrics.cashReceived,
      countedCash:
      session.countedCash,
      difference:
      session.difference,
      status:
      session.status,
      note:
      session.note,
      openedAt:
      session.openedAt,
      closedAt:
      session.closedAt,
      invoices:
      liveMetrics.invoices,
      soldItems:
      liveMetrics.soldItems,
    );
  }

  // ===========================================================================
  // HISTORY
  // ===========================================================================

  Future<List<CashboxDayHistoryModel>>
  getDailyHistory() async {
    final sessions =
    await database
        .select(
      database.cashboxSessions,
    )
        .get();

    final sales =
    await (database.select(
      database.sales,
    )
      ..where(
            (table) =>
            table.deletedAt.isNull(),
      ))
        .get();

    final dates =
    <String>{};

    for (final session in sessions) {
      dates.add(
        session.businessDate,
      );
    }

    for (final sale in sales) {
      dates.add(
        _dateKey(
          sale.createdAt,
        ),
      );
    }

    final sortedDates =
    dates.toList()
      ..sort(
            (a, b) =>
            b.compareTo(
              a,
            ),
      );

    final result =
    <CashboxDayHistoryModel>[];

    for (final dateKey
    in sortedDates) {
      final date =
      _parseDateKey(
        dateKey,
      );

      if (date == null) {
        continue;
      }

      final report =
      await getDayReport(
        date,
      );

      double? difference;

      final closedSessions =
      report.sessions
          .where(
            (session) =>
        session.isClosed &&
            session.difference !=
                null,
      )
          .toList();

      if (closedSessions.isNotEmpty) {
        difference =
            closedSessions.fold<double>(
              0,
                  (
                  total,
                  session,
                  ) =>
              total +
                  (session.difference ??
                      0),
            );
      }

      result.add(
        CashboxDayHistoryModel(
          businessDate:
          report.businessDate,
          totalSales:
          report.totalSales,
          cashReceived:
          report.cashReceived,
          invoicesCount:
          report.invoicesCount,
          sessionsCount:
          report.sessionsCount,
          hasOpenSession:
          report.hasOpenSession,
          difference:
          difference,
        ),
      );
    }

    return result;
  }

  // ===========================================================================
  // UNASSIGNED / LEGACY SALES
  // ===========================================================================

  Future<List<Sale>>
  _getUnassignedSalesForDay(
      DateTime date,
      ) async {
    final businessDate =
    _dateKey(
      date,
    );

    final rows =
    await (database.select(
      database.sales,
    )
      ..where(
            (table) =>
        table.cashboxSessionId.isNull() &
        table.deletedAt.isNull(),
      ))
        .get();

    return rows
        .where(
          (sale) =>
      _dateKey(
        sale.createdAt,
      ) ==
          businessDate,
    )
        .toList();
  }

  // ===========================================================================
  // SALES METRICS
  // ===========================================================================

  Future<_SalesMetrics>
  _calculateSalesMetrics(
      List<Sale> sales,
      ) async {
    double totalSales = 0;
    double cashSales = 0;
    double creditSales = 0;
    double partialSales = 0;
    double cashReceived = 0;
    double remainingAmount = 0;

    final invoices =
    <CashboxInvoiceModel>[];

    for (final sale in sales) {
      totalSales +=
          sale.total;

      cashReceived +=
          sale.paidAmount;

      remainingAmount +=
          sale.remainingAmount;

      switch (sale.paymentType
          .trim()
          .toUpperCase()) {
        case 'CASH':
          cashSales +=
              sale.total;
          break;

        case 'CREDIT':
          creditSales +=
              sale.total;
          break;

        case 'PARTIAL':
          partialSales +=
              sale.total;
          break;
      }

      invoices.add(
        CashboxInvoiceModel(
          id:
          sale.id,
          serverId:
          sale.serverId,
          invoiceNumber:
          sale.invoiceNumber,
          cashboxSessionId:
          sale.cashboxSessionId,
          customerName:
          sale.customerName,
          warehouseId:
          sale.warehouseId,
          warehouseName:
          sale.warehouseNameSnapshot,
          paymentType:
          sale.paymentType,
          total:
          sale.total,
          paidAmount:
          sale.paidAmount,
          remainingAmount:
          sale.remainingAmount,
          createdAt:
          sale.createdAt,
        ),
      );
    }

    invoices.sort(
          (a, b) =>
          b.createdAt.compareTo(
            a.createdAt,
          ),
    );

    final soldItems =
    await _buildSoldItems(
      sales,
    );

    return _SalesMetrics(
      totalSales:
      totalSales,
      cashSales:
      cashSales,
      creditSales:
      creditSales,
      partialSales:
      partialSales,
      cashReceived:
      cashReceived,
      remainingAmount:
      remainingAmount,
      invoicesCount:
      sales.length,
      invoices:
      invoices,
      soldItems:
      soldItems,
    );
  }

  // ===========================================================================
  // SOLD ITEMS
  // ===========================================================================

  Future<List<CashboxSoldItemModel>>
  _buildSoldItems(
      List<Sale> sales,
      ) async {
    if (sales.isEmpty) {
      return const [];
    }

    final saleIds =
    sales
        .map(
          (sale) =>
      sale.id,
    )
        .toList();

    final rows =
    await (database.select(
      database.saleItems,
    )
      ..where(
            (table) =>
            table.saleId.isIn(
              saleIds,
            ),
      ))
        .get();

    final map =
    <String, _MutableSoldItem>{};

    for (final row in rows) {
      final key =
          '${row.productId}::${row.unitId ?? ''}';

      final existing =
      map[key];

      if (existing == null) {
        map[key] =
            _MutableSoldItem(
              productId:
              row.productId,
              productName:
              row.productNameSnapshot,
              unitId:
              row.unitId,
              quantity:
              row.quantity,
              totalSales:
              row.total,
              linesCount:
              1,
            );
      } else {
        existing.quantity +=
            row.quantity;

        existing.totalSales +=
            row.total;

        existing.linesCount +=
        1;
      }
    }

    final result =
    map.values
        .map(
          (item) =>
          CashboxSoldItemModel(
            productId:
            item.productId,
            productName:
            item.productName,
            unitId:
            item.unitId,
            quantity:
            item.quantity,
            totalSales:
            item.totalSales,
            linesCount:
            item.linesCount,
          ),
    )
        .toList();

    result.sort(
          (a, b) =>
          b.totalSales.compareTo(
            a.totalSales,
          ),
    );

    return result;
  }

  List<CashboxSoldItemModel>
  _mergeSoldItems(
      List<CashboxSoldItemModel> items,
      ) {
    final map =
    <String, _MutableSoldItem>{};

    for (final item in items) {
      final key =
          '${item.productId}::${item.unitId ?? ''}';

      final existing =
      map[key];

      if (existing == null) {
        map[key] =
            _MutableSoldItem(
              productId:
              item.productId,
              productName:
              item.productName,
              unitId:
              item.unitId,
              quantity:
              item.quantity,
              totalSales:
              item.totalSales,
              linesCount:
              item.linesCount,
            );
      } else {
        existing.quantity +=
            item.quantity;

        existing.totalSales +=
            item.totalSales;

        existing.linesCount +=
            item.linesCount;
      }
    }

    final result =
    map.values
        .map(
          (item) =>
          CashboxSoldItemModel(
            productId:
            item.productId,
            productName:
            item.productName,
            unitId:
            item.unitId,
            quantity:
            item.quantity,
            totalSales:
            item.totalSales,
            linesCount:
            item.linesCount,
          ),
    )
        .toList();

    result.sort(
          (a, b) =>
          b.totalSales.compareTo(
            a.totalSales,
          ),
    );

    return result;
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _dateKey(
      DateTime value,
      ) {
    final local =
    value.toLocal();

    final year =
    local.year
        .toString()
        .padLeft(
      4,
      '0',
    );

    final month =
    local.month
        .toString()
        .padLeft(
      2,
      '0',
    );

    final day =
    local.day
        .toString()
        .padLeft(
      2,
      '0',
    );

    return '$year-$month-$day';
  }

  DateTime? _parseDateKey(
      String value,
      ) {
    final parts =
    value.split(
      '-',
    );

    if (parts.length != 3) {
      return null;
    }

    final year =
    int.tryParse(
      parts[0],
    );

    final month =
    int.tryParse(
      parts[1],
    );

    final day =
    int.tryParse(
      parts[2],
    );

    if (year == null ||
        month == null ||
        day == null) {
      return null;
    }

    return DateTime(
      year,
      month,
      day,
    );
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

// =============================================================================
// INTERNAL MODELS
// =============================================================================

class _SalesMetrics {
  final double totalSales;
  final double cashSales;
  final double creditSales;
  final double partialSales;
  final double cashReceived;
  final double remainingAmount;

  final int invoicesCount;

  final List<CashboxInvoiceModel> invoices;
  final List<CashboxSoldItemModel> soldItems;

  const _SalesMetrics({
    required this.totalSales,
    required this.cashSales,
    required this.creditSales,
    required this.partialSales,
    required this.cashReceived,
    required this.remainingAmount,
    required this.invoicesCount,
    required this.invoices,
    required this.soldItems,
  });
}

class _MutableSoldItem {
  final String productId;
  final String productName;
  final String? unitId;

  double quantity;
  double totalSales;
  int linesCount;

  _MutableSoldItem({
    required this.productId,
    required this.productName,
    required this.unitId,
    required this.quantity,
    required this.totalSales,
    required this.linesCount,
  });
}