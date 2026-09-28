enum StockMovementType {
  stockIn,
  stockOut,
  transfer,
  adjustment,
}

class StockMovementModel {
  final int id;
  final String productName;
  final String barcode;
  final String warehouseName;
  final String? targetWarehouseName;
  final StockMovementType type;
  final int quantity;
  final DateTime date;
  final String userName;
  final String? note;

  const StockMovementModel({
    required this.id,
    required this.productName,
    required this.barcode,
    required this.warehouseName,
    this.targetWarehouseName,
    required this.type,
    required this.quantity,
    required this.date,
    required this.userName,
    this.note,
  });

  String get typeTitle {
    switch (type) {
      case StockMovementType.stockIn:
        return 'إدخال';
      case StockMovementType.stockOut:
        return 'إخراج';
      case StockMovementType.transfer:
        return 'تحويل';
      case StockMovementType.adjustment:
        return 'تسوية';
    }
  }
}