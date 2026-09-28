import 'package:drift/drift.dart';

class Sales extends Table {
  /// Local UUID.
  TextColumn get id => text()();

  /// UUID الخاص بفاتورة Direct Sale في السيرفر.
  TextColumn get serverId => text().nullable()();

  TextColumn get invoiceNumber => text()();

  /// Local Cashbox Session UUID.
  ///
  /// Nullable للمبيعات القديمة القادمة من قبل نظام الجلسات
  /// أو المبيعات التاريخية القادمة من السيرفر.
  TextColumn get cashboxSessionId => text().nullable()();

  /// Local Warehouse UUID.
  TextColumn get warehouseId => text()();

  TextColumn get warehouseNameSnapshot => text()();

  /// Local Customer UUID.
  TextColumn get customerId => text().nullable()();

  TextColumn get customerName => text()();

  /// Local Representative UUID.
  ///
  /// حالياً Direct Sales API لا يحتوي representative_id،
  /// لذلك يبقى هذا الحقل محلياً لحين تأكيد عقد المندوب.
  TextColumn get representativeId => text().nullable()();

  TextColumn get representativeNameSnapshot => text().nullable()();

  RealColumn get commissionPercentageSnapshot => real().nullable()();

  RealColumn get commissionAmount => real().withDefault(
    const Constant(0),
  )();

  RealColumn get subtotal => real()();

  RealColumn get discount => real().withDefault(
    const Constant(0),
  )();

  /// الحمالية على القائمة. تُضاف إلى الإجمالي ولا تُرسل للسيرفر.
  RealColumn get porterage => real().withDefault(
    const Constant(0),
  )();

  RealColumn get total => real()();

  RealColumn get paidAmount => real().withDefault(
    const Constant(0),
  )();

  RealColumn get remainingAmount => real().withDefault(
    const Constant(0),
  )();

  /// CASH / CREDIT / PARTIAL.
  TextColumn get paymentType => text()();

  /// IQD أو USD. المبالغ الأساسية تبقى بالدينار.
  TextColumn get currency =>
      text().withDefault(const Constant('IQD'))();

  RealColumn get exchangeRate =>
      real().withDefault(const Constant(0))();

  RealColumn get totalUsd =>
      real().withDefault(const Constant(0))();

  TextColumn get notes =>
      text().withDefault(const Constant(''))();

  IntColumn get serverVersion => integer().withDefault(
    const Constant(0),
  )();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {
    id,
  };

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {
      invoiceNumber,
    },
  ];
}