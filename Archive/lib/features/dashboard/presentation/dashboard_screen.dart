import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/dashboard_repository.dart';
import '../models/dashboard_data.dart';

class DashboardScreen extends StatelessWidget {
  final DashboardRepository repository;
  final VoidCallback? onViewAllSales;

  const DashboardScreen({
    super.key,
    required this.repository,
    this.onViewAllSales,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          34,
          30,
          34,
          34,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),

            const SizedBox(height: 34),

            StreamBuilder<DashboardSummary>(
              stream: repository.watchSummary(),
              initialData: DashboardSummary.empty(),
              builder: (
                  context,
                  snapshot,
                  ) {
                final summary =
                    snapshot.data ??
                        DashboardSummary.empty();

                return _buildMainOverview(
                  summary,
                );
              },
            ),

            const SizedBox(height: 24),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildRecentSales(),
                ),

                const SizedBox(width: 20),

                Expanded(
                  flex: 2,
                  child: _buildLowStock(),
                ),
              ],
            ),

            const SizedBox(height: 24),

            StreamBuilder<DashboardSummary>(
              stream: repository.watchSummary(),
              initialData: DashboardSummary.empty(),
              builder: (
                  context,
                  snapshot,
                  ) {
                final summary =
                    snapshot.data ??
                        DashboardSummary.empty();

                return _buildQuickOverview(
                  summary,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader() {
    final hour = DateTime.now().hour;

    final greeting =
    hour >= 5 && hour < 12
        ? 'صباح الخير'
        : hour >= 12 && hour < 18
        ? 'مساء الخير'
        : 'مساء الخير';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'لوحة التحكم',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: AppTheme.primaryTextColor,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'نظرة سريعة على أداء المبيعات والمخزون اليوم.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),

        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: AppTheme.borderColor,
            ),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: AppTheme.primaryTextColor,
              ),
              SizedBox(width: 8),
              Text(
                'اليوم',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.primaryTextColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // MAIN OVERVIEW
  // ===========================================================================

  Widget _buildMainOverview(
      DashboardSummary summary,
      ) {
    return Row(
      children: [
        Expanded(
          child: _OverviewCard(
            title: 'مبيعات اليوم',
            value: _formatNumber(
              summary.todaySales,
            ),
            unit: 'د.ع',
            subtitle: 'إجمالي مبيعات اليوم',
            icon: Icons.trending_up_rounded,
            highlighted: true,
          ),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: _OverviewCard(
            title: 'عدد الفواتير',
            value:
            summary.todayInvoicesCount.toString(),
            subtitle: 'فاتورة مسجلة اليوم',
            icon: Icons.receipt_long_outlined,
          ),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: _OverviewCard(
            title: 'ديون الزبائن',
            value: _formatNumber(
              summary.totalCustomerDebt,
            ),
            unit: 'د.ع',
            subtitle: summary.totalCustomerDebtUsd.abs() < 0.005
                ? 'الرصيد غير المسدد'
                : 'و ${summary.totalCustomerDebtUsd.toStringAsFixed(2)} \$',
            icon:
            Icons.account_balance_wallet_outlined,
          ),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: _OverviewCard(
            title: 'نقص المخزون',
            value:
            summary.lowStockCount.toString(),
            subtitle: 'منتج تحت الحد الأدنى',
            icon: Icons.inventory_2_outlined,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // RECENT SALES
  // ===========================================================================

  Widget _buildRecentSales() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'آخر المبيعات',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                        AppTheme.primaryTextColor,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'أحدث الفواتير المسجلة',
                      style: TextStyle(
                        fontSize: 11.5,
                        color:
                        AppTheme.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),

              TextButton(
                onPressed: onViewAllSales,
                child: const Text(
                  'عرض الكل',
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          const _SalesTableHeader(),

          const SizedBox(height: 4),

          StreamBuilder<
              List<DashboardRecentSale>>(
            stream:
            repository.watchRecentSales(),
            initialData: const [],
            builder: (
                context,
                snapshot,
                ) {
              if (snapshot.hasError) {
                return _InlineMessage(
                  icon:
                  Icons.error_outline_rounded,
                  message:
                  'تعذر تحميل آخر المبيعات',
                );
              }

              final sales =
                  snapshot.data ?? const [];

              if (sales.isEmpty) {
                return const _InlineMessage(
                  icon:
                  Icons.receipt_long_outlined,
                  message:
                  'لا توجد مبيعات مسجلة حالياً',
                );
              }

              return Column(
                children: sales.map(
                      (sale) {
                    return _SalesRow(
                      invoice:
                      sale.invoiceNumber,
                      customer:
                      sale.customerName
                          .trim()
                          .isEmpty
                          ? 'زبون نقدي'
                          : sale.customerName,
                      paymentType:
                      sale.paymentTypeLabel,
                      total:
                      '${_formatNumber(sale.total)} د.ع',
                      status:
                      sale.statusLabel,
                    );
                  },
                ).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LOW STOCK
  // ===========================================================================

  Widget _buildLowStock() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تنبيهات المخزون',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                        AppTheme.primaryTextColor,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'المواد التي تحتاج إلى تجهيز',
                      style: TextStyle(
                        fontSize: 11.5,
                        color:
                        AppTheme.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.notifications_none_rounded,
                size: 20,
                color:
                AppTheme.secondaryTextColor,
              ),
            ],
          ),

          const SizedBox(height: 20),

          StreamBuilder<
              List<DashboardLowStockItem>>(
            stream:
            repository.watchLowStock(),
            initialData: const [],
            builder: (
                context,
                snapshot,
                ) {
              if (snapshot.hasError) {
                return const _InlineMessage(
                  icon:
                  Icons.error_outline_rounded,
                  message:
                  'تعذر تحميل حالة المخزون',
                );
              }

              final items =
                  snapshot.data ?? const [];

              if (items.isEmpty) {
                return const _InlineMessage(
                  icon:
                  Icons.check_circle_outline_rounded,
                  message:
                  'المخزون بحالة جيدة',
                );
              }

              return Column(
                children: items.map(
                      (item) {
                    final quantityText =
                    item.isOutOfStock
                        ? 'نفد من المخزون'
                        : '${_formatQuantity(item.quantity)} ${item.unit} متبقية';

                    return _StockAlertItem(
                      product:
                      item.productName,
                      quantity:
                      quantityText,
                      critical:
                      item.isCritical,
                    );
                  },
                ).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // QUICK OVERVIEW
  // ===========================================================================

  Widget _buildQuickOverview(
      DashboardSummary summary,
      ) {
    return Row(
      children: [
        Expanded(
          child: _SmallInfoCard(
            title: 'المبيعات النقدية',
            value:
            '${_formatNumber(summary.todayCashSales)} د.ع',
            icon: Icons.payments_outlined,
          ),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: _SmallInfoCard(
            title: 'المبالغ الآجلة اليوم',
            value:
            '${_formatNumber(summary.todayCreditAmount)} د.ع',
            icon: Icons.schedule_rounded,
          ),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: _SmallInfoCard(
            title: 'مبيعات المندوبين',
            value:
            '${_formatNumber(summary.todayRepresentativeSales)} د.ع',
            icon: Icons.badge_outlined,
          ),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: _SmallInfoCard(
            title: 'عدد المنتجات',
            value:
            _formatInteger(
              summary.activeProductsCount,
            ),
            icon:
            Icons.inventory_2_outlined,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  static String _formatNumber(
      double value,
      ) {
    final rounded = value.round();

    return _formatInteger(
      rounded,
    );
  }

  static String _formatInteger(
      int value,
      ) {
    final text = value.toString();
    final buffer = StringBuffer();

    for (
    var index = 0;
    index < text.length;
    index++
    ) {
      final positionFromEnd =
          text.length - index;

      buffer.write(
        text[index],
      );

      if (positionFromEnd > 1 &&
          positionFromEnd % 3 == 1) {
        buffer.write(',');
      }
    }

    return buffer.toString();
  }

  static String _formatQuantity(
      double value,
      ) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value
        .toStringAsFixed(2)
        .replaceFirst(
      RegExp(r'\.?0+$'),
      '',
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius:
      BorderRadius.circular(18),
      border: Border.all(
        color:
        AppTheme.subtleBorderColor,
      ),
    );
  }
}

// =============================================================================
// OVERVIEW CARD
// =============================================================================

class _OverviewCard extends StatelessWidget {
  final String title;
  final String value;
  final String? unit;
  final String subtitle;
  final IconData icon;
  final bool highlighted;

  const _OverviewCard({
    required this.title,
    required this.value,
    this.unit,
    required this.subtitle,
    required this.icon,
    this.highlighted = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final backgroundColor =
    highlighted
        ? const Color(0xFF1D1D1F)
        : Colors.white;

    final titleColor =
    highlighted
        ? const Color(0xFFB8B8BD)
        : AppTheme.secondaryTextColor;

    final valueColor =
    highlighted
        ? Colors.white
        : AppTheme.primaryTextColor;

    final subtitleColor =
    highlighted
        ? const Color(0xFF8E8E93)
        : AppTheme.tertiaryTextColor;

    final iconBackgroundColor =
    highlighted
        ? Colors.white.withValues(
      alpha: 0.10,
    )
        : const Color(0xFFF5F5F7);

    final iconColor =
    highlighted
        ? Colors.white
        : AppTheme.primaryTextColor;

    return Container(
      height: 150,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius:
        BorderRadius.circular(18),
        border:
        highlighted
            ? null
            : Border.all(
          color:
          AppTheme
              .subtleBorderColor,
        ),
        boxShadow:
        highlighted
            ? [
          BoxShadow(
            color: Colors.black
                .withValues(
              alpha: 0.08,
            ),
            blurRadius: 24,
            offset:
            const Offset(
              0,
              8,
            ),
          ),
        ]
            : null,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                    highlighted
                        ? FontWeight.w500
                        : FontWeight.w400,
                    color: titleColor,
                  ),
                ),
              ),
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color:
                  iconBackgroundColor,
                  borderRadius:
                  BorderRadius.circular(
                    10,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: iconColor,
                ),
              ),
            ],
          ),

          const Spacer(),

          Row(
            crossAxisAlignment:
            CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  overflow:
                  TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize:
                    highlighted
                        ? 24
                        : 22,
                    fontWeight:
                    FontWeight.w700,
                    letterSpacing: -0.4,
                    color: valueColor,
                  ),
                ),
              ),

              if (unit != null) ...[
                const SizedBox(width: 5),
                Padding(
                  padding:
                  const EdgeInsets.only(
                    bottom: 2,
                  ),
                  child: Text(
                    unit!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                      FontWeight.w500,
                      color:
                      highlighted
                          ? const Color(
                        0xFFB8B8BD,
                      )
                          : AppTheme
                          .secondaryTextColor,
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 4),

          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10.5,
              color: subtitleColor,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SALES TABLE
// =============================================================================

class _SalesTableHeader
    extends StatelessWidget {
  const _SalesTableHeader();

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 35,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color:
        const Color(0xFFF8F8FA),
        borderRadius:
        BorderRadius.circular(9),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'الفاتورة',
              style: _headerStyle,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'الزبون',
              style: _headerStyle,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'نوع الدفع',
              style: _headerStyle,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الإجمالي',
              style: _headerStyle,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الحالة',
              style: _headerStyle,
            ),
          ),
        ],
      ),
    );
  }

  static const TextStyle
  _headerStyle = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w500,
    color:
    AppTheme.secondaryTextColor,
  );
}

class _SalesRow extends StatelessWidget {
  final String invoice;
  final String customer;
  final String paymentType;
  final String total;
  final String status;

  const _SalesRow({
    required this.invoice,
    required this.customer,
    required this.paymentType,
    required this.total,
    required this.status,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 52,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      decoration:
      const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color:
            AppTheme
                .subtleBorderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              invoice,
              overflow:
              TextOverflow.ellipsis,
              style:
              const TextStyle(
                fontSize: 12,
                fontWeight:
                FontWeight.w600,
                color:
                AppTheme
                    .primaryTextColor,
              ),
            ),
          ),

          Expanded(
            flex: 3,
            child: Text(
              customer,
              overflow:
              TextOverflow.ellipsis,
              style:
              const TextStyle(
                fontSize: 12,
                color:
                AppTheme
                    .primaryTextColor,
              ),
            ),
          ),

          Expanded(
            flex: 2,
            child: Text(
              paymentType,
              overflow:
              TextOverflow.ellipsis,
              style:
              const TextStyle(
                fontSize: 11.5,
                color:
                AppTheme
                    .secondaryTextColor,
              ),
            ),
          ),

          Expanded(
            flex: 2,
            child: Text(
              total,
              overflow:
              TextOverflow.ellipsis,
              style:
              const TextStyle(
                fontSize: 11.5,
                fontWeight:
                FontWeight.w500,
                color:
                AppTheme
                    .primaryTextColor,
              ),
            ),
          ),

          Expanded(
            flex: 2,
            child: Align(
              alignment:
              Alignment.centerRight,
              child: _StatusBadge(
                status: status,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// STATUS
// =============================================================================

class _StatusBadge
    extends StatelessWidget {
  final String status;

  const _StatusBadge({
    required this.status,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    Color background;
    Color foreground;

    switch (status) {
      case 'مدفوعة':
        background =
        const Color(0xFFEAF7EE);
        foreground =
        const Color(0xFF248A3D);
        break;

      case 'جزئي':
        background =
        const Color(0xFFFFF4E5);
        foreground =
        const Color(0xFFB26A00);
        break;

      default:
        background =
        const Color(0xFFFFECEC);
        foreground =
        const Color(0xFFC92A2A);
    }

    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius:
        BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight:
          FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

// =============================================================================
// STOCK ALERT
// =============================================================================

class _StockAlertItem
    extends StatelessWidget {
  final String product;
  final String quantity;
  final bool critical;

  const _StockAlertItem({
    required this.product,
    required this.quantity,
    this.critical = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 18,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color:
              const Color(
                0xFFF5F5F7,
              ),
              borderRadius:
              BorderRadius.circular(
                10,
              ),
            ),
            child: const Icon(
              Icons
                  .inventory_2_outlined,
              size: 17,
              color:
              AppTheme
                  .primaryTextColor,
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  product,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  const TextStyle(
                    fontSize: 12,
                    fontWeight:
                    FontWeight.w600,
                    color:
                    AppTheme
                        .primaryTextColor,
                  ),
                ),

                const SizedBox(
                  height: 3,
                ),

                Text(
                  quantity,
                  style:
                  const TextStyle(
                    fontSize: 10.5,
                    color:
                    AppTheme
                        .secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),

          Container(
            width: 7,
            height: 7,
            decoration:
            BoxDecoration(
              shape: BoxShape.circle,
              color:
              critical
                  ? const Color(
                0xFFD70015,
              )
                  : const Color(
                0xFFFF9F0A,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SMALL INFO CARD
// =============================================================================

class _SmallInfoCard
    extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _SmallInfoCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 92,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(16),
        border: Border.all(
          color:
          AppTheme
              .subtleBorderColor,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color:
              const Color(
                0xFFF5F5F7,
              ),
              borderRadius:
              BorderRadius.circular(
                11,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color:
              AppTheme
                  .primaryTextColor,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  title,
                  style:
                  const TextStyle(
                    fontSize: 10.5,
                    color:
                    AppTheme
                        .secondaryTextColor,
                  ),
                ),

                const SizedBox(
                  height: 4,
                ),

                Text(
                  value,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  const TextStyle(
                    fontSize: 14.5,
                    fontWeight:
                    FontWeight.w600,
                    color:
                    AppTheme
                        .primaryTextColor,
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

// =============================================================================
// INLINE MESSAGE
// =============================================================================

class _InlineMessage
    extends StatelessWidget {
  final IconData icon;
  final String message;

  const _InlineMessage({
    required this.icon,
    required this.message,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 25,
              color:
              AppTheme
                  .tertiaryTextColor,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style:
              const TextStyle(
                fontSize: 11.5,
                color:
                AppTheme
                    .secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}