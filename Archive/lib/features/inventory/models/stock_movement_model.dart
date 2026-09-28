enum StockMovementType {
  purchase,
  sale,
  returnIn,
  returnOut,
  transferIn,
  transferOut,
  adjustmentIn,
  adjustmentOut,
}

extension StockMovementTypeExtension
on StockMovementType {
  String get databaseValue {
    switch (this) {
      case StockMovementType.purchase:
        return 'PURCHASE';

      case StockMovementType.sale:
        return 'SALE';

      case StockMovementType.returnIn:
        return 'RETURN_IN';

      case StockMovementType.returnOut:
        return 'RETURN_OUT';

      case StockMovementType.transferIn:
        return 'TRANSFER_IN';

      case StockMovementType.transferOut:
        return 'TRANSFER_OUT';

      case StockMovementType.adjustmentIn:
        return 'ADJUSTMENT_IN';

      case StockMovementType.adjustmentOut:
        return 'ADJUSTMENT_OUT';
    }
  }

  bool get increasesStock {
    switch (this) {
      case StockMovementType.purchase:
      case StockMovementType.returnIn:
      case StockMovementType.transferIn:
      case StockMovementType.adjustmentIn:
        return true;

      case StockMovementType.sale:
      case StockMovementType.returnOut:
      case StockMovementType.transferOut:
      case StockMovementType.adjustmentOut:
        return false;
    }
  }
}

class StockMovementModel {
  final String id;

  //
  // المخزون والحركات صارت Variant-first.
  //
  final String variantId;

  final String warehouseId;

  final StockMovementType type;

  final double quantity;

  final String? referenceType;
  final String? referenceId;

  final String? note;
  final String? userId;

  final int serverVersion;

  final DateTime createdAt;
  final DateTime? syncedAt;

  const StockMovementModel({
    required this.id,
    required this.variantId,
    required this.warehouseId,
    required this.type,
    required this.quantity,
    this.referenceType,
    this.referenceId,
    this.note,
    this.userId,
    required this.serverVersion,
    required this.createdAt,
    this.syncedAt,
  });

  Map<String, dynamic> toSyncJson() {
    return {
      'id': id,

      //
      // مهم:
      // لا نستخدم product_id بعد الآن.
      //
      'variant_id': variantId,

      'warehouse_id': warehouseId,
      'type': type.databaseValue,
      'quantity': quantity,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'note': note,
      'user_id': userId,
      'version': serverVersion,
      'created_at':
      createdAt.toUtc().toIso8601String(),
    };
  }
}