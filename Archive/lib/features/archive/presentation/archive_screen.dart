import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/di/app_services.dart';
import '../../../core/printing/print_preview.dart';
import '../../../core/theme/app_theme.dart';
import '../../ecommerce/models/ecommerce_order_model.dart';
import '../../ecommerce/presentation/ecommerce_order_details_screen.dart';
import '../../sales/presentation/sale_details_screen.dart';
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchController = TextEditingController();

  List<Sale> _sales = [];
  List<Purchase> _purchases = [];
  List<EcommerceOrderModel> _storeOrders = [];
  int _salesTotal = 0;
  int _purchasesTotal = 0;
  int _salesPage = 1;
  int _purchasesPage = 1;
  int _storePage = 1;
  int _storeTotalPages = 1;
  bool _loading = true;
  bool _paging = false;
  bool _todayOnly = true;
  String? _error;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      _searchTimer?.cancel();
      _searchTimer = Timer(const Duration(milliseconds: 250), () {
        _load(salesPage: 1, purchasesPage: 1, storePage: 1, sync: false);
      });
    });
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  ({DateTime from, DateTime to})? _dayRange() {
    if (!_todayOnly) {
      return null;
    }
    final start = DateTime.now();
    final from = DateTime(start.year, start.month, start.day);
    return (from: from, to: from.add(const Duration(days: 1)));
  }

  Future<void> _load({
    int? salesPage,
    int? purchasesPage,
    int? storePage,
    bool sync = true,
  }) async {
    final nextSalesPage = salesPage ?? _salesPage;
    final nextPurchasesPage = purchasesPage ?? _purchasesPage;
    final nextStorePage = storePage ?? _storePage;
    setState(() {
      _paging = true;
      if (_sales.isEmpty && _purchases.isEmpty) {
        _loading = true;
      }
      _error = null;
    });

    try {
      if (sync) {
        try {
          await AppServices.syncNow();
        } catch (_) {}
      }

      final range = _dayRange();
      final sales = await AppServices.salesRepository.pageSales(
        offset: (nextSalesPage - 1) * kListPageSize,
        search: _searchController.text,
        from: range?.from,
        to: range?.to,
      );
      final purchases = await AppServices.purchasesRepository.pagePurchases(
        offset: (nextPurchasesPage - 1) * kListPageSize,
        search: _searchController.text,
        from: range?.from,
        to: range?.to,
      );
      final storeOrders = await _completedStoreOrders(nextStorePage);

      if (!mounted) {
        return;
      }

      setState(() {
        _sales = sales.items;
        _purchases = purchases.items;
        _salesPage = nextSalesPage;
        _purchasesPage = nextPurchasesPage;
        _salesTotal = sales.total;
        _purchasesTotal = purchases.total;
        _storeOrders = storeOrders;
        _loading = false;
        _paging = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _paging = false;
        _error = 'تعذر قراءة الأرشيف المحلي.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'الأرشيف',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'الأرشيف اليومي يعرض قوائم هذا اليوم، وطلبات المتجر بعد إتمامها. اضغط أي قائمة لمشاهدة تفاصيلها.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'بحث برقم الفاتورة أو الاسم',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'تحديث',
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(_todayOnly ? 'اليوم' : 'كل الأيام'),
                  selected: _todayOnly,
                  onSelected: (value) {
                    setState(() {
                      _todayOnly = value;
                    });
                    _load(
                      salesPage: 1,
                      purchasesPage: 1,
                      storePage: 1,
                      sync: false,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              labelColor: AppTheme.primaryTextColor,
              tabs: [
                Tab(text: 'المبيعات (${_sales.length})'),
                Tab(text: 'المشتريات (${_purchases.length})'),
                Tab(text: 'طلبات المتجر (${_storeOrders.length})'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: AppTheme.dangerColor),
        ),
      );
    }

    return TabBarView(
      controller: _tabs,
      children: [
        _dailyList<Sale>(
          empty: _todayOnly
              ? 'لا قوائم بيع لهذا اليوم.'
              : 'لا توجد فواتير مبيعات محفوظة.',
          items: _sales,
          page: _salesPage,
          totalItems: _salesTotal,
          onPage: (page) => _load(salesPage: page, sync: false),
          dateOf: (sale) => sale.createdAt,
          row: (sale) => _ArchiveRow(
            number: sale.invoiceNumber,
            party: sale.customerName,
            place: sale.warehouseNameSnapshot,
            total: sale.total,
            date: sale.createdAt,
            kind: sale.paymentType,
            onOpen: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SaleDetailsScreen(sale: sale),
                ),
              );
            },
          ),
        ),
        _dailyList<Purchase>(
          empty: _todayOnly
              ? 'لا قوائم شراء لهذا اليوم.'
              : 'لا توجد فواتير مشتريات محفوظة.',
          items: _purchases,
          page: _purchasesPage,
          totalItems: _purchasesTotal,
          onPage: (page) => _load(purchasesPage: page, sync: false),
          dateOf: (purchase) => purchase.createdAt,
          row: (purchase) => _ArchiveRow(
            number: purchase.invoiceNumber,
            party: purchase.supplierNameSnapshot,
            place: purchase.warehouseNameSnapshot,
            total: purchase.total,
            date: purchase.createdAt,
            kind: purchase.paymentType,
            onOpen: () => _openPurchase(purchase),
          ),
        ),
        _dailyList<EcommerceOrderModel>(
          empty: _todayOnly
              ? 'لا طلبات متجر مكتملة لهذا اليوم.'
              : 'لا طلبات متجر مكتملة.',
          items: [
            for (final order in _storeOrders)
              if (_matches(order.orderNumber, order.partyDisplayName) &&
                  _inRange(order.acceptedAt ?? order.submittedAt ?? DateTime.now()))
                order,
          ],
          page: _storePage,
          pageCount: _storeTotalPages,
          onPage: (page) => _load(storePage: page, sync: false),
          dateOf: (order) => order.acceptedAt ?? order.submittedAt ?? DateTime.now(),
          row: (order) => _ArchiveRow(
            number: order.orderNumber,
            party: order.partyDisplayName,
            place: order.sourceDisplayName,
            total: order.total,
            date: order.acceptedAt ?? order.submittedAt ?? DateTime.now(),
            kind: order.statusDisplayName,
            onOpen: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EcommerceOrderDetailsScreen(initialOrder: order),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<List<EcommerceOrderModel>> _completedStoreOrders(int pageNumber) async {
    try {
      final page = await AppServices.ecommerceOrdersRepository.getOrders(
        page: pageNumber,
        limit: kListPageSize,
        status: 'ACCEPTED',
      );
      _storePage = page.page;
      _storeTotalPages = page.totalPages;
      return [
        for (final order in page.orders)
          if (order.isAccepted) order,
      ];
    } catch (_) {
      return const [];
    }
  }

  bool _inRange(DateTime date) {
    if (!_todayOnly) {
      return true;
    }
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Future<void> _openPurchase(Purchase purchase) async {
    final items = await (AppServices.database.select(
      AppServices.database.purchaseItems,
    )..where((table) => table.purchaseId.equals(purchase.id)))
        .get();
    if (!mounted) {
      return;
    }
    final date = printDateText(purchase.createdAt);
    final figures = printMoneyFigures(
      invoiceTotal: purchase.total,
      paid: purchase.paid,
      previousBalance: 0,
    );
    final document = PrintDocument(
      kind: 'قائمة شراء',
      title: purchase.invoiceNumber,
      partyLabel: 'المورد',
      party: purchase.supplierNameSnapshot,
      printedDate: date,
      printedTime: printTimeText(purchase.createdAt),
      documentType: 'قائمة شراء',
      lines: [
        'المخزن: ${purchase.warehouseNameSnapshot}',
      ],
      columns: kInvoiceColumns,
      rows: [
        for (var index = 0; index < items.length; index++)
          invoiceCells(
            index: index + 1,
            details: items[index].productNameSnapshot,
            quantity: items[index].quantity.toDouble(),
            unitPrice: items[index].unitCost,
            factor: items[index].unitFactor <= 0
                ? 1
                : items[index].unitFactor,
            amount: items[index].quantity * items[index].unitCost,
          ),
      ],
      grandTotal: figures.invoiceTotal,
      discount: purchase.discount,
      porterage: purchase.porterage,
      paidIqd: figures.paid,
      remainingIqd: figures.invoiceRemaining,
      previousIqdLabel: 'الرصيد السابق',
      paidIqdLabel: 'المسدد',
      remainingIqdLabel: 'متبقي القائمة',
      paidUsd: purchase.currency == 'USD' ? purchase.totalUsd : 0,
      totals: [
        'إجمالي القائمة: ${moneyText(figures.invoiceTotal)}',
        'المسدد: ${moneyText(figures.paid)}',
        'متبقي القائمة: ${moneyText(figures.invoiceRemaining)}',
      ],
    );
    final receipt = PrintDocument(
      kind: 'وصل',
      title: 'وصل دفع',
      partyLabel: 'المورد',
      party: purchase.supplierNameSnapshot,
      printedDate: date,
      printedTime: printTimeText(purchase.createdAt),
      documentTypeLabel: 'النوع',
      documentType: 'وصل دفع',
      lines: [
        'رقم القائمة: ${purchase.invoiceNumber}',
      ],
      totals: [
        'الكلي: ${purchase.total.toStringAsFixed(0)}',
        'المبلغ: ${purchase.paid.toStringAsFixed(0)}',
        'المتبقي: ${purchase.remaining.toStringAsFixed(0)}',
      ],
    );
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(purchase.invoiceNumber),
            content: Text(
              '${purchase.supplierNameSnapshot}\n$date\nالمجموع ${purchase.total.toStringAsFixed(0)}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
              if ((purchase.serverId ?? '').trim().isEmpty)
                OutlinedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _editPurchase(purchase, items);
                  },
                  child: const Text('تعديل'),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('التعديل مغلق بعد المزامنة'),
                ),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  showPrintPreview(this.context, document);
                },
                child: const Text('طباعة القائمة'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  showPrintPreview(this.context, receipt);
                },
                child: const Text('طباعة الوصل'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editPurchase(
    Purchase purchase,
    List<PurchaseItem> items,
  ) async {
    final supplierController = TextEditingController(
      text: purchase.supplierNameSnapshot,
    );
    final notesController = TextEditingController(text: purchase.note ?? '');
    final paidController = TextEditingController(
      text: purchase.paid.toStringAsFixed(0),
    );
    final quantityControllers = {
      for (final item in items)
        item.id: TextEditingController(text: item.quantity.toString()),
    };
    final costControllers = {
      for (final item in items)
        item.id: TextEditingController(text: item.unitCost.toStringAsFixed(0)),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تعديل قائمة الشراء'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: supplierController,
                      decoration: const InputDecoration(labelText: 'المورد'),
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
                    for (final item in items) ...[
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
                              controller: costControllers[item.id],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'الكلفة'),
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
      final edits = <String, ({int quantity, double unitCost})>{
        for (final item in items)
          item.id: (
            quantity: int.tryParse(quantityControllers[item.id]!.text.trim()) ?? 0,
            unitCost: double.tryParse(costControllers[item.id]!.text.trim()) ?? -1,
          ),
      };
      await AppServices.purchasesRepository.updatePurchaseDetails(
        purchaseId: purchase.id,
        supplierName: supplierController.text,
        notes: notesController.text,
        paidAmount: double.tryParse(paidController.text.trim()) ?? -1,
        items: edits,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تعديل قائمة الشراء.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Bad state: ', ''),
          ),
        ),
      );
    }
  }

  bool _matches(String number, String name) {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return true;
    }
    return number.contains(query) || name.contains(query);
  }

  Widget _dailyList<T>({
    required String empty,
    required List<T> items,
    required DateTime Function(T item) dateOf,
    required Widget Function(T item) row,
    required int page,
    required ValueChanged<int> onPage,
    int totalItems = 0,
    int? pageCount,
  }) {
    final pager = ListPagination(
      page: page,
      totalItems: totalItems,
      pageCount: pageCount,
      loading: _paging,
      onPageChanged: onPage,
    );
    if (items.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: 48),
          Text(
            empty,
            style: const TextStyle(color: AppTheme.secondaryTextColor),
          ),
          pager,
        ],
      );
    }

    final sorted = [...items]
      ..sort((a, b) => dateOf(b).compareTo(dateOf(a)));
    final children = <Widget>[];
    String? lastDay;

    for (final item in sorted) {
      final date = dateOf(item);
      final day =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      if (day != lastDay) {
        lastDay = day;
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              day,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
      }
      children.add(row(item));
      children.add(const SizedBox(height: 8));
    }

    children.add(pager);

    return ListView(children: children);
  }
}

class _ArchiveRow extends StatelessWidget {
  final String number;
  final String party;
  final String place;
  final double total;
  final DateTime date;
  final String kind;
  final VoidCallback onOpen;

  const _ArchiveRow({
    required this.number,
    required this.party,
    required this.place,
    required this.total,
    required this.date,
    required this.kind,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  number,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '$party · $place',
                  style: const TextStyle(
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Text(kind),
          const SizedBox(width: 16),
          Text('${date.year}-$month-$day'),
          const SizedBox(width: 16),
          SizedBox(
            width: 110,
            child: Text(
              total.toStringAsFixed(0),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    ),
    );
  }
}
