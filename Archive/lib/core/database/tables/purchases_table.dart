import 'package:drift/drift.dart';

class Purchases extends Table {

  /// Local UUID.

  TextColumn get id => text()();

  /// UUID الخاص بفاتورة الشراء في السيرفر.

  TextColumn get serverId =>

      text().nullable()();

  TextColumn get invoiceNumber => text()();

  /// Local supplier UUID.

  TextColumn get supplierId => text()();

  TextColumn get supplierNameSnapshot =>

      text()();

  /// Local warehouse UUID.

  TextColumn get warehouseId => text()();

  TextColumn get warehouseNameSnapshot =>

      text()();

  RealColumn get subtotal => real()();

  RealColumn get discount =>

      real().withDefault(

        const Constant(0),

      )();

  /// الحمالية على فاتورة الشراء. تُضاف إلى الإجمالي وتبقى محلية.
  RealColumn get porterage =>
      real().withDefault(const Constant(0))();

  RealColumn get total => real()();

  RealColumn get paid =>

      real().withDefault(

        const Constant(0),

      )();

  RealColumn get remaining =>

      real().withDefault(

        const Constant(0),

      )();

  TextColumn get paymentType => text()();

  /// IQD أو USD. المبلغ الأساسي يبقى بالدينار.
  TextColumn get currency =>
      text().withDefault(const Constant('IQD'))();

  RealColumn get exchangeRate =>
      real().withDefault(const Constant(0))();

  RealColumn get totalUsd =>
      real().withDefault(const Constant(0))();

  TextColumn get note => text().nullable()();

  IntColumn get serverVersion =>

      integer().withDefault(

        const Constant(0),

      )();

  DateTimeColumn get createdAt =>

      dateTime()();

  DateTimeColumn get updatedAt =>

      dateTime()();

  DateTimeColumn get deletedAt =>

      dateTime().nullable()();

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