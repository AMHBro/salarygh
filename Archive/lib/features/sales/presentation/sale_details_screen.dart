import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/app_services.dart';
import '../../../core/money/party_balance.dart';
import '../../../core/printing/print_preview.dart';
import '../../../core/theme/app_theme.dart';

class SaleDetailsScreen
    extends StatefulWidget {
  final Sale sale;

  const SaleDetailsScreen({
    super.key,
    required this.sale,
  });

  @override
  State<SaleDetailsScreen>
  createState() {
    return _SaleDetailsScreenState();
  }
}

class _SaleDetailsScreenState
    extends State<SaleDetailsScreen> {
  final _salesRepository =
      AppServices.salesRepository;

  StreamSubscription<List<SaleItem>>?
  _itemsSubscription;

  List<SaleItem> _items = [];
  List<SaleReturn> _returns = [];

  bool _isLoading = true;
  late Sale _sale;

  @override
  void initState() {
    super.initState();
    _sale = widget.sale;
    _listenToItems();
    _loadReturns();
  }

  @override
  void dispose() {
    _itemsSubscription?.cancel();

    super.dispose();
  }

  void _listenToItems() {
    _itemsSubscription =
        _salesRepository
            .watchSaleItems(
          _sale.id,
        )
            .listen(
              (items) {
            if (!mounted) {
              return;
            }

            setState(() {
              _items = items;
              _isLoading = false;
            });
          },
          onError: (Object error) {
            if (!mounted) {
              return;
            }

            setState(() {
              _isLoading = false;
            });

            _showMessage(
              _errorMessage(error),
            );
          },
        );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      AppTheme.backgroundColor,
      body: Directionality(
        textDirection:
        TextDirection.rtl,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isLoading
                    ? const Center(
                  child:
                  CircularProgressIndicator(),
                )
                    : SingleChildScrollView(
                  padding:
                  const EdgeInsets
                      .fromLTRB(
                    28,
                    22,
                    28,
                    32,
                  ),
                  child: Column(
                    children: [
                      _buildInvoiceOverview(),
                      const SizedBox(
                        height: 14,
                      ),
                      _buildItemsCard(),
                      const SizedBox(
                        height: 14,
                      ),
                      _buildPaymentSummary(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader() {
    final synced =
        _sale.serverId != null &&
            _sale.serverId!
                .trim()
                .isNotEmpty;

    return Container(
      padding:
      const EdgeInsets.fromLTRB(
        28,
        22,
        28,
        18,
      ),
      decoration:
      const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color:
            AppTheme.subtleBorderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'رجوع',
            onPressed: () {
              Navigator.pop(context);
            },
            icon: const Icon(
              Icons
                  .arrow_forward_rounded,
            ),
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const Text(
                  'تفاصيل الفاتورة',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight:
                    FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppTheme
                        .primaryTextColor,
                  ),
                ),
                const SizedBox(
                  height: 4,
                ),
                Text(
                  _sale
                      .invoiceNumber,
                  style:
                  const TextStyle(
                    fontSize: 12,
                    color: AppTheme
                        .secondaryTextColor,
                  ),
                ),
                if (_returns.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'مرتجعات: ${_returns.map((row) => row.voucherNumber).join('، ')}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration:
            BoxDecoration(
              color:
              const Color(
                0xFFF5F5F7,
              ),
              borderRadius:
              BorderRadius.circular(
                10,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  synced
                      ? Icons
                      .cloud_done_outlined
                      : Icons
                      .cloud_upload_outlined,
                  size: 16,
                  color: synced
                      ? AppTheme
                      .successColor
                      : AppTheme
                      .secondaryTextColor,
                ),
                const SizedBox(
                  width: 7,
                ),
                Text(
                  synced
                      ? 'متزامنة مع السيرفر'
                      : 'محفوظة محلياً',
                  style:
                  TextStyle(
                    fontSize: 10.5,
                    fontWeight:
                    FontWeight.w600,
                    color: synced
                        ? AppTheme
                        .successColor
                        : AppTheme
                        .secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            width: 9,
          ),
          if (synced)
            const Text(
              'التعديل مغلق بعد المزامنة',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryTextColor,
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: _editSale,
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('تعديل'),
            ),
          const SizedBox(width: 9),
          OutlinedButton.icon(
            onPressed: _items.isEmpty ? null : _showReturnDialog,
            icon: const Icon(Icons.undo_outlined, size: 17),
            label: const Text('مرتجع'),
          ),
          const SizedBox(width: 9),
          PopupMenuButton<String>(
            onSelected: (value) {
              _printSaved(value == 'receipt');
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'invoice', child: Text('طباعة القائمة')),
              PopupMenuItem(value: 'receipt', child: Text('طباعة الوصل')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.print_outlined, size: 17),
                  SizedBox(width: 6),
                  Text('طباعة'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printSaved(bool receipt) async {
    final sale = await _salesRepository.getSaleById(_sale.id) ?? _sale;
    final items = await _salesRepository.getSaleItems(sale.id);
    SaleBalanceSnapshot? snapshot;
    final customerId = sale.customerId?.trim() ?? '';
    if (customerId.isNotEmpty) {
      snapshot = await AppServices.customersRepository.balanceAroundSale(
        customerId: customerId,
        saleId: sale.id,
        invoiceTotal: sale.total,
        paidAmount: sale.paidAmount,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _sale = sale;
      _items = items;
    });
    showPrintPreview(
      context,
      receipt
          ? _receiptDocument(snapshot, sale)
          : _invoiceDocument(snapshot, sale, items),
    );
  }

  PrintMoneyFigures _savedFigures(Sale sale, SaleBalanceSnapshot? snapshot) {
    return printMoneyFigures(
      invoiceTotal: sale.total,
      paid: sale.paidAmount,
      previousBalance: snapshot?.previous.toDouble() ?? 0,
      ledgerFinalBalance: snapshot?.remaining.toDouble(),
    );
  }

  PrintDocument _invoiceDocument(
    SaleBalanceSnapshot? snapshot,
    Sale sale,
    List<SaleItem> items,
  ) {
    final figures = _savedFigures(sale, snapshot);
    return PrintDocument(
      kind: 'قائمة بيع',
      title: sale.invoiceNumber,
      party: sale.customerName,
      representative: sale.representativeNameSnapshot ?? '',
      itemCodes: [
        for (final item in items) item.barcodeSnapshot ?? '',
      ],
      printedDate: printDateText(sale.createdAt),
      printedTime: printTimeText(sale.createdAt),
      documentType: _paymentTitle(sale.paymentType),
      columns: kInvoiceColumns,
      rows: [
        for (var index = 0; index < items.length; index++)
          invoiceCells(
            index: index + 1,
            details: items[index].productNameSnapshot,
            quantity: items[index].quantity,
            unitPrice: items[index].unitPrice,
            factor: items[index].unitFactor <= 0 ? 1 : items[index].unitFactor,
            loose: items[index].loosePieces.toDouble(),
            priceIsPerPiece: true,
            amount: items[index].total,
          ),
      ],
      grandTotal: figures.invoiceTotal,
      discount: sale.discount,
      porterage: sale.porterage,
      previousIqd: figures.previousBalance,
      paidIqd: figures.paid,
      remainingIqd: figures.finalBalance,
      previousIqdLabel: 'الرصيد السابق',
      paidIqdLabel: 'المسدد',
      remainingIqdLabel: 'الرصيد النهائي',
      lines: [
        'المخزن: ${sale.warehouseNameSnapshot}',
        if (sale.notes.trim().isNotEmpty) 'ملاحظات: ${sale.notes}',
      ],
      paidUsd: sale.currency == 'USD' && sale.total > 0
          ? sale.totalUsd * figures.paid / sale.total
          : 0,
      remainingUsd: sale.currency == 'USD' && sale.total > 0
          ? sale.totalUsd * figures.finalBalance / sale.total
          : 0,
      totals: printMoneyLines(figures),
    );
  }

  PrintDocument _receiptDocument(SaleBalanceSnapshot? snapshot, Sale sale) {
    final figures = _savedFigures(sale, snapshot);
    return PrintDocument(
      kind: 'وصل',
      title: 'وصل قبض',
      party: sale.customerName,
      printedDate: printDateText(sale.createdAt),
      printedTime: printTimeText(sale.createdAt),
      documentTypeLabel: 'النوع',
      documentType: 'وصل قبض',
      lines: [
        'رقم القائمة: ${sale.invoiceNumber}',
        'نوع الدفع: ${_paymentTitle(sale.paymentType)}',
      ],
      grandTotal: figures.invoiceTotal,
      previousIqd: figures.previousBalance,
      paidIqd: figures.paid,
      remainingIqd: figures.finalBalance,
      previousIqdLabel: 'الرصيد السابق',
      paidIqdLabel: 'المسدد',
      remainingIqdLabel: 'الرصيد النهائي',
      totals: printMoneyLines(figures),
    );
  }

  Future<void> _loadReturns() async {
    final rows = await _salesRepository.getSaleReturns(_sale.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _returns = rows;
    });
  }

  double _soldPieces(SaleItem item) {
    final factor = item.unitFactor <= 0 ? 1.0 : item.unitFactor;
    final cartons = item.quantity < 0 ? 0.0 : item.quantity;
    final loose = item.loosePieces < 0 ? 0.0 : item.loosePieces.toDouble();
    return cartons * factor + loose;
  }

  String _returnMoney(double iqd) {
    if (_sale.currency == 'USD' && _sale.exchangeRate > 0) {
      return '${(iqd / _sale.exchangeRate).toStringAsFixed(2)} \$';
    }
    return '${iqd.toStringAsFixed(0)} د.ع';
  }

  Future<void> _showReturnDialog() async {
    final already = await _salesRepository.returnedPiecesByItem(_sale.id);
    if (!mounted) {
      return;
    }
    final controllers = <String, TextEditingController>{
      for (final item in _items) item.id: TextEditingController(),
    };
    final noteController = TextEditingController();
    var saving = false;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: AlertDialog(
                  title: const Text('سند مرتجع'),
                  content: SizedBox(
                    width: 560,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'القائمة ${_sale.invoiceNumber} تبقى كما هي. اكتب عدد القطع الراجعة.',
                            style: const TextStyle(
                              color: AppTheme.secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 14),
                          for (final item in _items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _returnLine(
                                item: item,
                                left: _soldPieces(item) - (already[item.id] ?? 0),
                                controller: controllers[item.id]!,
                              ),
                            ),
                          TextField(
                            controller: noteController,
                            decoration: const InputDecoration(
                              labelText: 'ملاحظة',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.pop(dialogContext),
                      child: const Text('إلغاء'),
                    ),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final pieces = <String, double>{};
                              for (final item in _items) {
                                final value = double.tryParse(
                                      controllers[item.id]!
                                          .text
                                          .trim()
                                          .replaceAll(',', ''),
                                    ) ??
                                    0;
                                if (value > 0) {
                                  pieces[item.id] = value;
                                }
                              }
                              setDialogState(() {
                                saving = true;
                              });
                              try {
                                final number =
                                    await _salesRepository.createSaleReturn(
                                  saleId: _sale.id,
                                  piecesByItem: pieces,
                                  note: noteController.text,
                                );
                                if (!dialogContext.mounted) {
                                  return;
                                }
                                Navigator.pop(dialogContext);
                                await _loadReturns();
                                if (!mounted) {
                                  return;
                                }
                                _showMessage('تم تسجيل المرتجع $number.');
                              } catch (error) {
                                if (dialogContext.mounted) {
                                  setDialogState(() {
                                    saving = false;
                                  });
                                }
                                _showMessage(_errorMessage(error));
                              }
                            },
                      child: const Text('حفظ المرتجع'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      noteController.dispose();
    }
  }

  Widget _returnLine({
    required SaleItem item,
    required double left,
    required TextEditingController controller,
  }) {
    final sold = _soldPieces(item);
    final piece = sold <= 0 ? 0.0 : item.total / sold;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.productNameSnapshot),
              Text(
                'المتبقي $left قطعة · ${_returnMoney(piece)} للقطعة',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: TextField(
            controller: controller,
            enabled: left > 0,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'القطع',
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editSale() async {
    final customerController = TextEditingController(text: _sale.customerName);
    final notesController = TextEditingController(text: _sale.notes);
    final paidController = TextEditingController(
      text: _sale.paidAmount.toStringAsFixed(0),
    );
    final quantityControllers = {
      for (final item in _items)
        item.id: TextEditingController(text: item.quantity.toStringAsFixed(0)),
    };
    final priceControllers = {
      for (final item in _items)
        item.id: TextEditingController(text: item.unitPrice.toStringAsFixed(0)),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تعديل القائمة'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: customerController,
                      decoration: const InputDecoration(labelText: 'الزبون'),
                    ),
                    TextField(
                      controller: notesController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'ملاحظات'),
                    ),
                    TextField(
                      controller: paidController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'الواصل'),
                    ),
                    const SizedBox(height: 12),
                    for (final item in _items) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(item.productNameSnapshot),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: quantityControllers[item.id],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'العدد'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: priceControllers[item.id],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'السعر'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );

    if (saved != true || !mounted) {
      return;
    }

    try {
      final items = <String, ({double quantity, double unitPrice})>{
        for (final item in _items)
          item.id: (
            quantity: double.tryParse(quantityControllers[item.id]!.text.trim()) ?? 0,
            unitPrice: double.tryParse(priceControllers[item.id]!.text.trim()) ?? -1,
          ),
      };
      await _salesRepository.updateSaleDetails(
        saleId: _sale.id,
        customerName: customerController.text,
        notes: notesController.text,
        paidAmount: double.tryParse(paidController.text.trim()) ?? -1,
        items: items,
      );
      final fresh = await (AppServices.database.select(AppServices.database.sales)
            ..where((table) => table.id.equals(_sale.id)))
          .getSingle();
      if (!mounted) return;
      setState(() => _sale = fresh);
      _showMessage('تم تعديل القائمة.');
    } catch (error) {
      _showMessage(_errorMessage(error));
    }
  }

  // ===========================================================================
  // OVERVIEW
  // ===========================================================================

  Widget _buildInvoiceOverview() {
    final sale =
        _sale;

    return _DetailsCard(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'معلومات الفاتورة',
            style: TextStyle(
              fontSize: 17,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          const SizedBox(
            height: 16,
          ),
          Row(
            children: [
              Expanded(
                child:
                _InformationBox(
                  title:
                  'رقم الفاتورة',
                  value:
                  sale.invoiceNumber,
                  icon:
                  Icons.tag_rounded,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                _InformationBox(
                  title: 'التاريخ',
                  value:
                  _formatDateTime(
                    sale.createdAt,
                  ),
                  icon: Icons
                      .calendar_today_outlined,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                _InformationBox(
                  title: 'الزبون',
                  value:
                  sale.customerName,
                  icon: Icons
                      .person_outline_rounded,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                _InformationBox(
                  title: 'المخزن',
                  value: sale
                      .warehouseNameSnapshot,
                  icon: Icons
                      .warehouse_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 10,
          ),
          Row(
            children: [
              Expanded(
                child:
                _InformationBox(
                  title: 'نوع الدفع',
                  value:
                  _paymentTitle(
                    sale.paymentType,
                  ),
                  icon: Icons
                      .payments_outlined,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                _InformationBox(
                  title: 'المندوب',
                  value: sale
                      .representativeNameSnapshot
                      ?.trim()
                      .isNotEmpty ==
                      true
                      ? sale
                      .representativeNameSnapshot!
                      : 'بدون مندوب',
                  icon: Icons
                      .badge_outlined,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                _InformationBox(
                  title:
                  'عدد المواد',
                  value:
                  '${_items.length}',
                  icon: Icons
                      .inventory_2_outlined,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                _InformationBox(
                  title:
                  'إصدار السيرفر',
                  value:
                  '${sale.serverVersion}',
                  icon: Icons
                      .cloud_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ITEMS
  // ===========================================================================

  Widget _buildItemsCard() {
    return _DetailsCard(
      padding:
      EdgeInsets.zero,
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
            const EdgeInsets
                .fromLTRB(
              18,
              16,
              18,
              14,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Text(
                        'مواد الفاتورة',
                        style:
                        TextStyle(
                          fontSize: 17,
                          fontWeight:
                          FontWeight
                              .w700,
                        ),
                      ),
                      SizedBox(
                        height: 3,
                      ),
                      Text(
                        'تفاصيل المواد والكميات والأسعار المسجلة وقت البيع.',
                        style:
                        TextStyle(
                          fontSize: 11,
                          color: AppTheme
                              .secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_items.length} مادة',
                  style:
                  const TextStyle(
                    fontSize: 11,
                    color: AppTheme
                        .secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            color:
            AppTheme.subtleBorderColor,
          ),
          if (_items.isEmpty)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text(
                  'لا توجد مواد محفوظة لهذه الفاتورة.',
                  style:
                  TextStyle(
                    fontSize: 12,
                    color: AppTheme
                        .secondaryTextColor,
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection:
              Axis.horizontal,
              child: SizedBox(
                width: 1252,
                child: Column(
                  children: [
                    _buildItemsHeader(),
                    ..._items.asMap().entries.map(
                          (entry) {
                        return _buildItemRow(
                          entry.value,
                          entry.key,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemsHeader() {
    return Container(
      height: 47,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      decoration:
      const BoxDecoration(
        color: Color(
          0xFFFAFAFB,
        ),
        border: Border(
          bottom: BorderSide(
            color:
            AppTheme.subtleBorderColor,
          ),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              '#',
              style:
              _detailsHeaderStyle,
            ),
          ),
          SizedBox(
            width: 280,
            child: Text(
              'المادة',
              style:
              _detailsHeaderStyle,
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              'الباركود',
              style:
              _detailsHeaderStyle,
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              'نوع السعر',
              style:
              _detailsHeaderStyle,
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              'الكمية',
              style:
              _detailsHeaderStyle,
            ),
          ),
          SizedBox(
            width: 160,
            child: Text(
              'سعر الوحدة',
              style:
              _detailsHeaderStyle,
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              'الخصم',
              style:
              _detailsHeaderStyle,
            ),
          ),
          SizedBox(
            width: 160,
            child: Text(
              'المجموع',
              style:
              _detailsHeaderStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(
      SaleItem item,
      int index,
      ) {
    return Container(
      constraints:
      const BoxConstraints(
        minHeight: 67,
      ),
      padding:
      const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 10,
      ),
      decoration:
      const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color:
            AppTheme.subtleBorderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              '${index + 1}',
              style:
              const TextStyle(
                fontSize: 11,
                color: AppTheme
                    .secondaryTextColor,
              ),
            ),
          ),
          SizedBox(
            width: 280,
            child: Row(
              children: [
                Container(
                  width: 37,
                  height: 37,
                  alignment:
                  Alignment.center,
                  decoration:
                  BoxDecoration(
                    color:
                    const Color(
                      0xFFF5F5F7,
                    ),
                    borderRadius:
                    BorderRadius
                        .circular(
                      9,
                    ),
                  ),
                  child:
                  const Icon(
                    Icons
                        .inventory_2_outlined,
                    size: 17,
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Text(
                    item
                        .productNameSnapshot,
                    maxLines: 2,
                    overflow:
                    TextOverflow
                        .ellipsis,
                    style:
                    const TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                      FontWeight
                          .w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              item.barcodeSnapshot
                  ?.trim()
                  .isNotEmpty ==
                  true
                  ? item
                  .barcodeSnapshot!
                  : '-',
              style:
              const TextStyle(
                fontSize: 10.5,
                color: AppTheme
                    .secondaryTextColor,
              ),
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              _priceTypeTitle(
                item.priceType,
              ),
              style:
              const TextStyle(
                fontSize: 11,
              ),
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              _formatQuantity(
                item.quantity,
              ),
              style:
              const TextStyle(
                fontSize: 11.5,
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 160,
            child: Text(
              _formatPrice(
                item.unitPrice,
              ),
              style:
              const TextStyle(
                fontSize: 11.5,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              '${_formatQuantity(item.discountPercent)}%',
              style:
              const TextStyle(
                fontSize: 11,
                color: AppTheme
                    .secondaryTextColor,
              ),
            ),
          ),
          SizedBox(
            width: 160,
            child: Text(
              _formatPrice(
                item.total,
              ),
              style:
              const TextStyle(
                fontSize: 12,
                fontWeight:
                FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PAYMENT SUMMARY
  // ===========================================================================

  Widget _buildPaymentSummary() {
    final sale =
        _sale;

    return _DetailsCard(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'ملخص الحساب',
            style: TextStyle(
              fontSize: 17,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          const SizedBox(
            height: 16,
          ),
          Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding:
                  const EdgeInsets
                      .all(
                    20,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    const Color(
                      0xFF111111,
                    ),
                    borderRadius:
                    BorderRadius
                        .circular(
                      16,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      const Text(
                        'إجمالي الفاتورة',
                        style:
                        TextStyle(
                          fontSize: 11,
                          color:
                          Colors.white60,
                        ),
                      ),
                      const SizedBox(
                        height: 9,
                      ),
                      Text(
                        _formatPrice(
                          sale.total,
                        ),
                        style:
                        const TextStyle(
                          fontSize: 26,
                          fontWeight:
                          FontWeight
                              .w700,
                          color:
                          Colors.white,
                        ),
                      ),
                      const SizedBox(
                        height: 7,
                      ),
                      Text(
                        'المجموع قبل الخصم ${_formatPrice(sale.subtotal)}',
                        style:
                        const TextStyle(
                          fontSize: 10,
                          color:
                          Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                flex: 7,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child:
                          _SummaryBox(
                            title:
                            'المجموع قبل الخصم',
                            value:
                            _formatPrice(
                              sale.subtotal,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        Expanded(
                          child:
                          _SummaryBox(
                            title:
                            'الخصم',
                            value:
                            _formatPrice(
                              sale.discount,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        Expanded(
                          child:
                          _SummaryBox(
                            title:
                            'المبلغ المدفوع',
                            value:
                            _formatPrice(
                              sale.paidAmount,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Container(
                      width:
                      double.infinity,
                      padding:
                      const EdgeInsets
                          .symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      decoration:
                      BoxDecoration(
                        color:
                        const Color(
                          0xFFFAFAFB,
                        ),
                        borderRadius:
                        BorderRadius
                            .circular(
                          13,
                        ),
                        border:
                        Border.all(
                          color: AppTheme
                              .subtleBorderColor,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'المبلغ المتبقي',
                              style:
                              TextStyle(
                                fontSize:
                                11.5,
                                color: AppTheme
                                    .secondaryTextColor,
                              ),
                            ),
                          ),
                          Text(
                            _formatPrice(
                              sale
                                  .remainingAmount,
                            ),
                            style:
                            TextStyle(
                              fontSize: 15,
                              fontWeight:
                              FontWeight
                                  .w700,
                              color: sale
                                  .remainingAmount >
                                  0
                                  ? AppTheme
                                  .dangerColor
                                  : AppTheme
                                  .successColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (sale.commissionAmount >
              0) ...[
            const SizedBox(
              height: 12,
            ),
            Container(
              width:
              double.infinity,
              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              decoration:
              BoxDecoration(
                color:
                const Color(
                  0xFFF7F7F8,
                ),
                borderRadius:
                BorderRadius
                    .circular(
                  11,
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    'عمولة المندوب:',
                    style:
                    TextStyle(
                      fontSize: 11,
                      color: AppTheme
                          .secondaryTextColor,
                    ),
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  Text(
                    _formatPrice(
                      sale
                          .commissionAmount,
                    ),
                    style:
                    const TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                      FontWeight
                          .w700,
                    ),
                  ),
                  if (sale
                      .commissionPercentageSnapshot !=
                      null) ...[
                    const SizedBox(
                      width: 6,
                    ),
                    Text(
                      '(${sale.commissionPercentageSnapshot!.toStringAsFixed(0)} د.ع)',
                      style:
                      const TextStyle(
                        fontSize: 10,
                        color: AppTheme
                            .tertiaryTextColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _paymentTitle(
      String value,
      ) {
    switch (value
        .trim()
        .toUpperCase()) {
      case 'CASH':
        return 'نقدي';

      case 'CREDIT':
        return 'آجل';

      case 'PARTIAL':
        return 'جزئي';

      case 'REP_CUSTODY':
        return 'عهدة مندوب';

      default:
        return value;
    }
  }

  String _priceTypeTitle(
      String value,
      ) {
    switch (value
        .trim()
        .toUpperCase()) {
      case 'COST':
        return 'الكلفة';

      case 'REP':
      case 'REPRESENTATIVE':
        return 'مندوب';

      case 'WHOLESALE':
        return 'جملة';

      case 'RETAIL':
        return 'مفرد';

      default:
        return value;
    }
  }

  String _formatQuantity(
      double value,
      ) {
    if (value ==
        value.roundToDouble()) {
      return value
          .toInt()
          .toString();
    }

    return value.toStringAsFixed(
      2,
    );
  }

  String _formatPrice(
      double value,
      ) {
    final negative =
        value < 0;

    final text = value
        .abs()
        .toStringAsFixed(0);

    final buffer =
    StringBuffer();

    for (int i = 0;
    i < text.length;
    i++) {
      if (i > 0 &&
          (text.length - i) %
              3 ==
              0) {
        buffer.write(',');
      }

      buffer.write(text[i]);
    }

    return '${negative ? '-' : ''}${buffer.toString()} د.ع';
  }

  String _formatDateTime(
      DateTime value,
      ) {
    final local =
    value.toLocal();

    final day = local.day
        .toString()
        .padLeft(
      2,
      '0',
    );

    final month = local.month
        .toString()
        .padLeft(
      2,
      '0',
    );

    final hour = local.hour
        .toString()
        .padLeft(
      2,
      '0',
    );

    final minute = local.minute
        .toString()
        .padLeft(
      2,
      '0',
    );

    return '$day/$month/${local.year}  $hour:$minute';
  }

  void _showMessage(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  String _errorMessage(
      Object error,
      ) {
    var message =
    error.toString();

    message = message.replaceFirst(
      'Bad state: ',
      '',
    );

    message = message.replaceFirst(
      'Invalid argument(s): ',
      '',
    );

    return message;
  }
}

const TextStyle _detailsHeaderStyle =
TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w600,
  color:
  AppTheme.secondaryTextColor,
);

// =============================================================================
// COMPONENTS
// =============================================================================

class _DetailsCard
    extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _DetailsCard({
    required this.child,
    this.padding =
    const EdgeInsets.all(
      18,
    ),
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color:
          AppTheme.subtleBorderColor,
        ),
      ),
      child: child,
    );
  }
}

class _InformationBox
    extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _InformationBox({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      constraints:
      const BoxConstraints(
        minHeight: 82,
      ),
      padding:
      const EdgeInsets.all(
        13,
      ),
      decoration: BoxDecoration(
        color:
        const Color(
          0xFFFAFAFB,
        ),
        borderRadius:
        BorderRadius.circular(
          12,
        ),
        border: Border.all(
          color:
          AppTheme.subtleBorderColor,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment:
            Alignment.center,
            decoration:
            BoxDecoration(
              color:
              const Color(
                0xFFF1F1F3,
              ),
              borderRadius:
              BorderRadius.circular(
                9,
              ),
            ),
            child: Icon(
              icon,
              size: 16,
              color: AppTheme
                  .secondaryTextColor,
            ),
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                  const TextStyle(
                    fontSize: 9.5,
                    color: AppTheme
                        .secondaryTextColor,
                  ),
                ),
                const SizedBox(
                  height: 5,
                ),
                Text(
                  value,
                  maxLines: 2,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  const TextStyle(
                    fontSize: 11.5,
                    fontWeight:
                    FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBox
    extends StatelessWidget {
  final String title;
  final String value;

  const _SummaryBox({
    required this.title,
    required this.value,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding:
      const EdgeInsets.all(
        15,
      ),
      decoration: BoxDecoration(
        color:
        const Color(
          0xFFFAFAFB,
        ),
        borderRadius:
        BorderRadius.circular(
          13,
        ),
        border: Border.all(
          color:
          AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
            const TextStyle(
              fontSize: 10,
              color: AppTheme
                  .secondaryTextColor,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            value,
            style:
            const TextStyle(
              fontSize: 14,
              fontWeight:
              FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}