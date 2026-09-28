import '../data/alira_mock.dart';
import '../data/alira_store_orders.dart';

class AgentSaleSession {
  static int unitPrice(AliraProduct product, String? invoicePrice) {
    return product.priceFor(invoicePrice ?? 'representative');
  }

  static String? apiPriceType(String? invoicePrice) {
    switch (invoicePrice) {
      case 'wholesale':
        return 'WHOLESALE';
      case 'retail':
        return 'RETAIL';
      case 'cost':
        return 'COST';
      case 'representative':
        return 'REP';
      default:
        return null;
    }
  }

  static int cartTotal({
    required Map<String, int> cart,
    required AliraProduct? Function(String id) productOf,
    required String? invoicePrice,
  }) {
    var total = 0;
    for (final entry in cart.entries) {
      final product = productOf(entry.key);
      if (product == null) continue;
      total += unitPrice(product, invoicePrice) * entry.value;
    }
    return total;
  }

  static String paidText({
    required String payment,
    required int total,
  }) {
    if (payment == 'CREDIT') return '0';
    if (payment == 'CASH') return '$total';
    return '';
  }

  static List<AliraStoreLine> storeLines({
    required Map<String, int> cart,
    required AliraProduct? Function(String id) productOf,
  }) {
    final lines = <AliraStoreLine>[];
    for (final entry in cart.entries) {
      final product = productOf(entry.key);
      final variantId = product?.variantId;
      final unitId = product?.unitId;
      if (product == null || variantId == null || unitId == null) {
        throw StateError('تعذر ربط إحدى المواد بطلبات المتجر');
      }
      lines.add(
        AliraStoreLine(
          variantId: variantId,
          unitId: unitId,
          quantity: entry.value,
        ),
      );
    }
    return lines;
  }
}
