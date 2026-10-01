import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/app_services.dart';
import '../../../core/printing/print_preview.dart';
import '../../../core/theme/app_theme.dart';
import '../../products/presentation/product_stock_panel.dart';

class StockItemScreen extends StatefulWidget {
  final String productId;
  final String productName;
  final String barcode;
  final String unit;
  final double quantity;

  const StockItemScreen({
    super.key,
    required this.productId,
    required this.productName,
    required this.barcode,
    required this.unit,
    required this.quantity,
  });

  @override
  State<StockItemScreen> createState() => _StockItemScreenState();
}

class _StockItemScreenState extends State<StockItemScreen> {
  bool _loading = true;
  List<_OutgoingLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final database = AppServices.database;
    final items = await (database.select(database.saleItems)
          ..where((table) => table.productId.equals(widget.productId)))
        .get();
    final sales = await database.select(database.sales).get();
    final byId = {for (final sale in sales) sale.id: sale};
    final lines = <_OutgoingLine>[];

    for (final item in items) {
      final sale = byId[item.saleId];
      if (sale == null) {
        continue;
      }
      lines.add(_OutgoingLine(sale: sale, item: item));
    }

    lines.sort((a, b) => b.sale.createdAt.compareTo(a.sale.createdAt));

    if (!mounted) {
      return;
    }

    setState(() {
      _lines = lines;
      _loading = false;
    });
  }

  String _day(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  PrintDocument get _document {
    return PrintDocument(
      kind: 'كشف مادة',
      title: widget.productName,
      lines: [
        'الباركود: ${widget.barcode.isEmpty ? '—' : widget.barcode}',
        'الموجود: ${widget.quantity.toStringAsFixed(0)} ${widget.unit}',
      ],
      columns: const ['القائمة', 'التاريخ', 'الزبون', 'الكمية', 'الإجمالي'],
      rows: [
        for (final line in _lines)
          [
            line.sale.invoiceNumber,
            _day(line.sale.createdAt),
            line.sale.customerName,
            line.item.quantity.toStringAsFixed(0),
            line.item.total.toStringAsFixed(0),
          ],
      ],
      totals: [
        'عدد القوائم: ${_lines.length}',
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: Text(widget.productName),
          actions: [
            IconButton(
              tooltip: 'طباعة الكشف',
              onPressed: _loading
                  ? null
                  : () => showPrintPreview(context, _document),
              icon: const Icon(Icons.print_outlined),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  ProductStockPanel(productId: widget.productId),
                  const SizedBox(height: 16),
                  const Text(
                    'القوائم التي خرجت بها هذه المادة',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_lines.isEmpty)
                    const Text(
                      'لا توجد قوائم بيع لهذه المادة.',
                      style: TextStyle(color: AppTheme.secondaryTextColor),
                    ),
                  for (final line in _lines)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Text(
                        '${line.sale.invoiceNumber} · ${_day(line.sale.createdAt)} · ${line.sale.customerName} · ${line.item.quantity.toStringAsFixed(0)}',
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _OutgoingLine {
  final Sale sale;
  final SaleItem item;

  const _OutgoingLine({
    required this.sale,
    required this.item,
  });
}
