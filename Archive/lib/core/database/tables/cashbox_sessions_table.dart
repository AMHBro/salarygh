import 'package:drift/drift.dart';

class CashboxSessions extends Table {
  /// Local UUID.
  TextColumn get id => text()();

  /// تاريخ العمل المحلي بصيغة YYYY-MM-DD.
  ///
  /// ملاحظة:
  /// لم يعد Unique لأن اليوم الواحد يمكن أن يحتوي
  /// على أكثر من جلسة صندوق.
  TextColumn get businessDate => text()();

  /// الرصيد النقدي الموجود عند فتح هذه الجلسة.
  RealColumn get openingBalance => real().withDefault(
    const Constant(0),
  )();

  // ===========================================================================
  // SNAPSHOT AT CLOSE
  // ===========================================================================

  RealColumn get totalSales => real().withDefault(
    const Constant(0),
  )();

  RealColumn get cashSales => real().withDefault(
    const Constant(0),
  )();

  RealColumn get creditSales => real().withDefault(
    const Constant(0),
  )();

  RealColumn get partialSales => real().withDefault(
    const Constant(0),
  )();

  /// النقد المستلم فعلياً من فواتير البيع المرتبطة بهذه الجلسة.
  RealColumn get cashReceived => real().withDefault(
    const Constant(0),
  )();

  RealColumn get remainingAmount => real().withDefault(
    const Constant(0),
  )();

  IntColumn get invoicesCount => integer().withDefault(
    const Constant(0),
  )();

  /// Opening Balance + Cash Received.
  ///
  /// لاحقاً يمكن توسيعها إلى:
  ///
  /// + Customer Receipts
  /// - Expenses
  /// - Supplier Payments
  /// - Refunds
  RealColumn get expectedCash => real().withDefault(
    const Constant(0),
  )();

  /// المبلغ الذي عده الموظف فعلياً عند الإغلاق.
  RealColumn get countedCash => real().nullable()();

  /// countedCash - expectedCash.
  RealColumn get difference => real().nullable()();

  /// OPEN / CLOSED.
  TextColumn get status => text().withDefault(
    const Constant('OPEN'),
  )();

  TextColumn get note => text().nullable()();

  DateTimeColumn get openedAt => dateTime()();

  DateTimeColumn get closedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };

/// لا يوجد Unique على businessDate.
///
/// اليوم الواحد يستطيع احتواء:
/// Session #1
/// Session #2
/// Session #3 ...
}