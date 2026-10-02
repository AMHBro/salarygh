import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/app_services.dart';
import '../../../core/theme/app_theme.dart';
import 'sale_details_screen.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({
    super.key,
  });

  @override
  State<SalesHistoryScreen> createState() {
    return _SalesHistoryScreenState();
  }
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final _salesRepository =
      AppServices.salesRepository;

  final TextEditingController
  _searchController =
  TextEditingController();

  StreamSubscription<List<Sale>>?
  _salesSubscription;

  List<Sale> _sales = [];

  bool _isLoading = true;
  bool _isSyncing = false;

  String _paymentFilter = 'ALL';

  @override
  void initState() {
    super.initState();

    _searchController.addListener(
      _refresh,
    );

    _listenToSales();
  }

  @override
  void dispose() {
    _salesSubscription?.cancel();

    _searchController.removeListener(
      _refresh,
    );

    _searchController.dispose();

    super.dispose();
  }

  void _refresh() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // ===========================================================================
  // DATA
  // ===========================================================================

  void _listenToSales() {
    _salesSubscription =
        _salesRepository
            .watchSales()
            .listen(
              (sales) {
            if (!mounted) {
              return;
            }

            setState(() {
              _sales = sales;
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

  Future<void> _synchronize() async {
    if (_isSyncing) {
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      await AppServices.syncNow();

      if (!mounted) {
        return;
      }

      _showMessage(
        'تم تحديث سجل المبيعات.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _errorMessage(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  // ===========================================================================
  // FILTERS
  // ===========================================================================

  List<Sale> get _filteredSales {
    final query =
    _searchController.text
        .trim()
        .toLowerCase();

    return _sales.where(
          (sale) {
        if (_paymentFilter != 'ALL' &&
            sale.paymentType
                .trim()
                .toUpperCase() !=
                _paymentFilter) {
          return false;
        }

        if (query.isEmpty) {
          return true;
        }

        final invoice =
        sale.invoiceNumber
            .toLowerCase();

        final customer =
        sale.customerName
            .toLowerCase();

        final warehouse =
        sale.warehouseNameSnapshot
            .toLowerCase();

        return invoice.contains(query) ||
            customer.contains(query) ||
            warehouse.contains(query);
      },
    ).toList();
  }

  // ===========================================================================
  // TOTALS
  // ===========================================================================

  double get _salesTotal {
    return _filteredSales.fold<double>(
      0,
          (sum, sale) =>
      sum + sale.total,
    );
  }

  double get _paidTotal {
    return _filteredSales.fold<double>(
      0,
          (sum, sale) =>
      sum + sale.paidAmount,
    );
  }

  double get _remainingTotal {
    return _filteredSales.fold<double>(
      0,
          (sum, sale) =>
      sum + sale.remainingAmount,
    );
  }

  int get _syncedCount {
    return _filteredSales
        .where(
          (sale) =>
      sale.serverId != null &&
          sale.serverId!
              .trim()
              .isNotEmpty,
    )
        .length;
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
                    : _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
          const Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'سجل القوائم',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight:
                    FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppTheme
                        .primaryTextColor,
                  ),
                ),
                SizedBox(
                  height: 4,
                ),
                Text(
                  'جميع فواتير البيع المحفوظة محلياً والمتزامنة مع السيرفر.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme
                        .secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed:
            _isSyncing
                ? null
                : _synchronize,
            icon: _isSyncing
                ? const SizedBox(
              width: 16,
              height: 16,
              child:
              CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
                : const Icon(
              Icons
                  .sync_rounded,
              size: 17,
            ),
            label: Text(
              _isSyncing
                  ? 'جاري التحديث...'
                  : 'تحديث',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding:
      const EdgeInsets.fromLTRB(
        28,
        22,
        28,
        32,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          _buildStats(),
          const SizedBox(
            height: 16,
          ),
          _buildFilters(),
          const SizedBox(
            height: 16,
          ),
          _buildSalesCard(),
        ],
      ),
    );
  }

  // ===========================================================================
  // STATS
  // ===========================================================================

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _HistoryStatCard(
            title:
            'إجمالي المبيعات',
            value:
            _formatPrice(
              _salesTotal,
            ),
            icon:
            Icons.trending_up_rounded,
            dark: true,
          ),
        ),
        const SizedBox(
          width: 12,
        ),
        Expanded(
          child: _HistoryStatCard(
            title:
            'المبلغ المسدد',
            value:
            _formatPrice(
              _paidTotal,
            ),
            icon: Icons
                .payments_outlined,
          ),
        ),
        const SizedBox(
          width: 12,
        ),
        Expanded(
          child: _HistoryStatCard(
            title:
            'المبلغ المتبقي',
            value:
            _formatPrice(
              _remainingTotal,
            ),
            icon: Icons
                .account_balance_wallet_outlined,
            danger:
            _remainingTotal > 0,
          ),
        ),
        const SizedBox(
          width: 12,
        ),
        Expanded(
          child: _HistoryStatCard(
            title:
            'عدد الفواتير',
            value:
            '${_filteredSales.length}',
            subtitle:
            '$_syncedCount متزامنة',
            icon:
            Icons.receipt_long_outlined,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // FILTERS
  // ===========================================================================

  Widget _buildFilters() {
    return Container(
      padding:
      const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(
          17,
        ),
        border: Border.all(
          color:
          AppTheme.subtleBorderColor,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller:
              _searchController,
              decoration:
              InputDecoration(
                hintText:
                'ابحث برقم الفاتورة أو الزبون أو المخزن...',
                prefixIcon:
                const Icon(
                  Icons.search_rounded,
                ),
                suffixIcon:
                _searchController
                    .text
                    .isEmpty
                    ? null
                    : IconButton(
                  onPressed: () {
                    _searchController
                        .clear();
                  },
                  icon:
                  const Icon(
                    Icons
                        .close_rounded,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          SizedBox(
            width: 190,
            child:
            DropdownButtonFormField<
                String>(
              key: ValueKey(_paymentFilter),
              initialValue:
              _paymentFilter,
              isExpanded: true,
              decoration:
              const InputDecoration(
                prefixIcon: Icon(
                  Icons
                      .filter_alt_outlined,
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'ALL',
                  child: Text(
                    'كل أنواع الدفع',
                  ),
                ),
                DropdownMenuItem(
                  value: 'CASH',
                  child: Text(
                    'نقدي',
                  ),
                ),
                DropdownMenuItem(
                  value: 'CREDIT',
                  child: Text(
                    'آجل',
                  ),
                ),
                DropdownMenuItem(
                  value: 'PARTIAL',
                  child: Text(
                    'جزئي',
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _paymentFilter =
                      value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TABLE
  // ===========================================================================

  Widget _buildSalesCard() {
    final sales =
        _filteredSales;

    return Container(
      width: double.infinity,
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
      clipBehavior:
      Clip.antiAlias,
      child: Column(
        children: [
          Container(
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
                        'فواتير البيع',
                        style:
                        TextStyle(
                          fontSize: 17,
                          fontWeight:
                          FontWeight
                              .w700,
                          color: AppTheme
                              .primaryTextColor,
                        ),
                      ),
                      SizedBox(
                        height: 3,
                      ),
                      Text(
                        'اضغط على أي فاتورة لعرض تفاصيلها.',
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
                  '${sales.length} فاتورة',
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
          if (sales.isEmpty)
            const SizedBox(
              height: 280,
              child: Center(
                child: Column(
                  mainAxisSize:
                  MainAxisSize.min,
                  children: [
                    Icon(
                      Icons
                          .receipt_long_outlined,
                      size: 42,
                      color: AppTheme
                          .tertiaryTextColor,
                    ),
                    SizedBox(
                      height: 12,
                    ),
                    Text(
                      'لا توجد فواتير',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                    SizedBox(
                      height: 5,
                    ),
                    Text(
                      'جرّب تغيير البحث أو نوع الدفع.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme
                            .secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection:
              Axis.horizontal,
              child: SizedBox(
                width: 1312,
                child: Column(
                  children: [
                    _buildTableHeader(),
                    ...sales.map(
                      _buildSaleRow,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
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
            width: 190,
            child: Text(
              'رقم الفاتورة',
              style:
              _historyHeaderStyle,
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              'التاريخ',
              style:
              _historyHeaderStyle,
            ),
          ),
          SizedBox(
            width: 190,
            child: Text(
              'الزبون',
              style:
              _historyHeaderStyle,
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              'المخزن',
              style:
              _historyHeaderStyle,
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              'نوع الدفع',
              style:
              _historyHeaderStyle,
            ),
          ),
          SizedBox(
            width: 145,
            child: Text(
              'الإجمالي',
              style:
              _historyHeaderStyle,
            ),
          ),
          SizedBox(
            width: 145,
            child: Text(
              'المتبقي',
              style:
              _historyHeaderStyle,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              'المزامنة',
              style:
              _historyHeaderStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleRow(
      Sale sale,
      ) {
    final synced =
        sale.serverId != null &&
            sale.serverId!
                .trim()
                .isNotEmpty;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          _openSaleDetails(
            sale,
          );
        },
        child: Container(
          constraints:
          const BoxConstraints(
            minHeight: 68,
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
                color: AppTheme
                    .subtleBorderColor,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 190,
                child: Text(
                  sale.invoiceNumber,
                  maxLines: 1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  const TextStyle(
                    fontSize: 11.5,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: Text(
                  _formatDateTime(
                    sale.createdAt,
                  ),
                  style:
                  const TextStyle(
                    fontSize: 11,
                    color: AppTheme
                        .secondaryTextColor,
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: Text(
                  sale.customerName,
                  maxLines: 1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  const TextStyle(
                    fontSize: 11.5,
                    fontWeight:
                    FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: Text(
                  sale
                      .warehouseNameSnapshot,
                  maxLines: 1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  const TextStyle(
                    fontSize: 11,
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child:
                _PaymentBadge(
                  paymentType:
                  sale.paymentType,
                ),
              ),
              SizedBox(
                width: 145,
                child: Text(
                  _formatPrice(
                    sale.total,
                  ),
                  style:
                  const TextStyle(
                    fontSize: 11.5,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 145,
                child: Text(
                  _formatPrice(
                    sale.remainingAmount,
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight:
                    FontWeight.w700,
                    color: sale
                        .remainingAmount >
                        0
                        ? AppTheme
                        .dangerColor
                        : AppTheme
                        .primaryTextColor,
                  ),
                ),
              ),
              SizedBox(
                width: 110,
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
                      width: 6,
                    ),
                    Text(
                      synced
                          ? 'متزامنة'
                          : 'محلية',
                      style:
                      TextStyle(
                        fontSize: 10.5,
                        fontWeight:
                        FontWeight
                            .w600,
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
            ],
          ),
        ),
      ),
    );
  }

  void _openSaleDetails(
      Sale sale,
      ) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) {
          return SaleDetailsScreen(
            sale: sale,
          );
        },
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

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
}

const TextStyle _historyHeaderStyle =
TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w600,
  color:
  AppTheme.secondaryTextColor,
);

// =============================================================================
// COMPONENTS
// =============================================================================

class _HistoryStatCard
    extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final bool dark;
  final bool danger;

  const _HistoryStatCard({
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
    this.dark = false,
    this.danger = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final foreground =
    dark
        ? Colors.white
        : AppTheme
        .primaryTextColor;

    return Container(
      constraints:
      const BoxConstraints(
        minHeight: 126,
      ),
      padding:
      const EdgeInsets.all(
        17,
      ),
      decoration: BoxDecoration(
        color: dark
            ? const Color(
          0xFF111111,
        )
            : Colors.white,
        borderRadius:
        BorderRadius.circular(
          17,
        ),
        border: dark
            ? null
            : Border.all(
          color: AppTheme
              .subtleBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment:
                Alignment.center,
                decoration:
                BoxDecoration(
                  color: dark
                      ? Colors.white
                      .withValues(
                    alpha: 0.10,
                  )
                      : const Color(
                    0xFFF5F5F7,
                  ),
                  borderRadius:
                  BorderRadius
                      .circular(
                    10,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color: dark
                      ? Colors.white
                      : AppTheme
                      .secondaryTextColor,
                ),
              ),
              const Spacer(),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style:
                  TextStyle(
                    fontSize: 10,
                    color: dark
                        ? Colors.white54
                        : AppTheme
                        .tertiaryTextColor,
                  ),
                ),
            ],
          ),
          const SizedBox(
            height: 15,
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 10.5,
              color: dark
                  ? Colors.white60
                  : AppTheme
                  .secondaryTextColor,
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            value,
            maxLines: 1,
            overflow:
            TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 19,
              fontWeight:
              FontWeight.w700,
              color: danger
                  ? AppTheme
                  .dangerColor
                  : foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentBadge
    extends StatelessWidget {
  final String paymentType;

  const _PaymentBadge({
    required this.paymentType,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final type =
    paymentType
        .trim()
        .toUpperCase();

    String title;

    switch (type) {
      case 'CASH':
        title = 'نقدي';
        break;

      case 'CREDIT':
        title = 'آجل';
        break;

      case 'PARTIAL':
        title = 'جزئي';
        break;

      case 'REP_CUSTODY':
        title = 'عهدة مندوب';
        break;

      default:
        title = paymentType;
    }

    return Align(
      alignment:
      Alignment.centerRight,
      child: Container(
        padding:
        const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color:
          const Color(
            0xFFF5F5F7,
          ),
          borderRadius:
          BorderRadius.circular(
            20,
          ),
        ),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight:
            FontWeight.w600,
          ),
        ),
      ),
    );
  }
}