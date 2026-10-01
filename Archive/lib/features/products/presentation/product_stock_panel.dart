import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/theme/app_theme.dart';

class ProductStockLine {
  final String warehouseName;
  final double quantity;

  const ProductStockLine({
    required this.warehouseName,
    required this.quantity,
  });
}

class ProductStockPanel extends StatefulWidget {
  final String productId;

  const ProductStockPanel({
    super.key,
    required this.productId,
  });

  @override
  State<ProductStockPanel> createState() => _ProductStockPanelState();
}

class _ProductStockPanelState extends State<ProductStockPanel> {
  bool _loading = true;
  List<ProductStockLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final product = await AppServices.productsRepository.getProductById(
      widget.productId,
    );
    final warehouses = await AppServices.warehousesRepository.getWarehouses();
    final names = {
      for (final warehouse in warehouses) warehouse.id: warehouse.name,
    };
    final variantIds = <String>[
      if (product != null)
        for (final variant in product.variants)
          if (variant.deletedAt == null) variant.id,
    ];
    final lines = <ProductStockLine>[];
    if (variantIds.isNotEmpty) {
      final balances = await (AppServices.database.select(
        AppServices.database.stockBalances,
      )..where((table) => table.variantId.isIn(variantIds)))
          .get();
      final totals = <String, double>{};
      for (final balance in balances) {
        if (balance.quantity <= 0) {
          continue;
        }
        final name = names[balance.warehouseId];
        if (name == null) {
          continue;
        }
        totals[name] = (totals[name] ?? 0) + balance.quantity;
      }
      final ordered = totals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      lines.addAll([
        for (final entry in ordered)
          ProductStockLine(
            warehouseName: entry.key,
            quantity: entry.value,
          ),
      ]);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _lines = lines;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _lines.fold<double>(0, (sum, line) => sum + line.quantity);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'المتوفر في المخازن',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Text(
              'جاري قراءة الكميات...',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            )
          else if (_lines.isEmpty)
            const Text(
              'غير متوفر في أي مخزن.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            )
          else ...[
            for (final line in _lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.warehouseName,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text(
                      _qty(line.quantity),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'المجموع',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  _qty(total),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _qty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}
