import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../models/cashbox_report_model.dart';

class CashboxDayDetailsScreen
    extends StatefulWidget {
  final DateTime date;

  const CashboxDayDetailsScreen({
    super.key,
    required this.date,
  });

  @override
  State<CashboxDayDetailsScreen>
  createState() {
    return _CashboxDayDetailsScreenState();
  }
}

class _CashboxDayDetailsScreenState
    extends State<CashboxDayDetailsScreen> {
  final _repository =
      AppServices.cashboxRepository;

  CashboxDayReport? _report;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final report =
      await _repository
          .getDayReport(
        widget.date,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            error
                .toString()
                .replaceFirst(
              'Bad state: ',
              '',
            ),
          ),
        ),
      );
    }
  }

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
        child: _loading
            ? const Center(
          child:
          CircularProgressIndicator(),
        )
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final report =
        _report;

    if (report == null) {
      return const Center(
        child: Text(
          'تعذر تحميل تقرير اليوم.',
        ),
      );
    }

    return Column(
      children: [
        _buildHeader(
          report,
        ),
        Expanded(
          child:
          SingleChildScrollView(
            padding:
            const EdgeInsets.fromLTRB(
              28,
              22,
              28,
              32,
            ),
            child: Column(
              children: [
                _buildSummary(
                  report,
                ),
                const SizedBox(
                  height: 14,
                ),
                _buildSessions(
                  report,
                ),
                const SizedBox(
                  height: 14,
                ),
                _buildSoldItems(
                  report,
                ),
                const SizedBox(
                  height: 14,
                ),
                _buildInvoices(
                  report,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader(
      CashboxDayReport report,
      ) {
    return Container(
      padding:
      const EdgeInsets.fromLTRB(
        28,
        20,
        28,
        18,
      ),
      decoration:
      const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppTheme
                .subtleBorderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              Navigator.pop(
                context,
              );
            },
            icon: const Icon(
              Icons
                  .arrow_forward_rounded,
            ),
          ),
          const SizedBox(
            width: 8,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'تقرير الصندوق - ${_formatDate(widget.date)}',
                  style:
                  const TextStyle(
                    fontSize: 25,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
                const SizedBox(
                  height: 4,
                ),
                Text(
                  '${report.sessionsCount} جلسة • ${report.invoicesCount} فاتورة',
                  style:
                  const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme
                        .secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          if (report.hasOpenSession)
            const _DayStatusBadge(
              title:
              'توجد جلسة مفتوحة',
              open: true,
            )
          else
            const _DayStatusBadge(
              title:
              'لا توجد جلسة مفتوحة',
              open: false,
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  Widget _buildSummary(
      CashboxDayReport report,
      ) {
    return _Card(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'ملخص اليوم',
            style: TextStyle(
              fontSize: 17,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          const SizedBox(
            height: 16,
          ),
          LayoutBuilder(
            builder: (
                context,
                constraints,
                ) {
              final width =
                  constraints.maxWidth;

              final itemWidth =
              width >= 1000
                  ? (width - 30) / 4
                  : width >= 650
                  ? (width - 10) / 2
                  : width;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child:
                    _Metric(
                      title:
                      'إجمالي المبيعات',
                      value:
                      _formatPrice(
                        report.totalSales,
                      ),
                      dark: true,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child:
                    _Metric(
                      title:
                      'النقد الداخل',
                      value:
                      _formatPrice(
                        report.cashReceived,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child:
                    _Metric(
                      title:
                      'المتبقي على الزبائن',
                      value:
                      _formatPrice(
                        report.remainingAmount,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child:
                    _Metric(
                      title:
                      'عدد الفواتير',
                      value:
                      '${report.invoicesCount}',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(
            height: 10,
          ),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  title:
                  'نقدي',
                  value:
                  _formatPrice(
                    report.cashSales,
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: _Metric(
                  title:
                  'جزئي',
                  value:
                  _formatPrice(
                    report.partialSales,
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: _Metric(
                  title:
                  'آجل',
                  value:
                  _formatPrice(
                    report.creditSales,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SESSIONS
  // ===========================================================================

  Widget _buildSessions(
      CashboxDayReport report,
      ) {
    return _Card(
      padding:
      EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding:
            const EdgeInsets.all(
              18,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'جلسات الصندوق',
                    style:
                    TextStyle(
                      fontSize: 17,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${report.sessions.length} جلسة',
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
            color: AppTheme
                .subtleBorderColor,
          ),
          if (report.sessions.isEmpty)
            const SizedBox(
              height: 150,
              child: Center(
                child: Text(
                  'لا توجد جلسات صندوق لهذا اليوم.',
                ),
              ),
            )
          else
            ...report.sessions
                .asMap()
                .entries
                .map(
                  (entry) {
                final number =
                    entry.key + 1;

                final session =
                    entry.value;

                return _buildSessionRow(
                  number,
                  session,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(
      int number,
      CashboxSessionReport session,
      ) {
    return Container(
      padding:
      const EdgeInsets.all(
        18,
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
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'جلسة #$number',
                style:
                const TextStyle(
                  fontSize: 13,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              _DayStatusBadge(
                title: session.isOpen
                    ? 'مفتوح'
                    : 'مغلق',
                open:
                session.isOpen,
              ),
              const Spacer(),
              Text(
                session.closedAt ==
                    null
                    ? '${_formatTime(session.openedAt)} → الآن'
                    : '${_formatTime(session.openedAt)} → ${_formatTime(session.closedAt!)}',
                style:
                const TextStyle(
                  fontSize: 11,
                  color: AppTheme
                      .secondaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 14,
          ),
          Row(
            children: [
              Expanded(
                child:
                _SmallMetric(
                  title:
                  'رصيد البداية',
                  value:
                  _formatPrice(
                    session.openingBalance,
                  ),
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child:
                _SmallMetric(
                  title:
                  'المبيعات',
                  value:
                  _formatPrice(
                    session.totalSales,
                  ),
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child:
                _SmallMetric(
                  title:
                  'النقد الداخل',
                  value:
                  _formatPrice(
                    session.cashReceived,
                  ),
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child:
                _SmallMetric(
                  title:
                  'المفروض',
                  value:
                  _formatPrice(
                    session.expectedCash,
                  ),
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child:
                _SmallMetric(
                  title:
                  'المعدود',
                  value:
                  session.countedCash ==
                      null
                      ? '-'
                      : _formatPrice(
                    session
                        .countedCash!,
                  ),
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child:
                _SmallMetric(
                  title:
                  'الفرق',
                  value:
                  session.difference ==
                      null
                      ? '-'
                      : _formatSignedPrice(
                    session
                        .difference!,
                  ),
                  valueColor:
                  session.difference ==
                      null
                      ? null
                      : session
                      .difference!
                      .abs() <
                      0.01
                      ? AppTheme
                      .successColor
                      : AppTheme
                      .dangerColor,
                ),
              ),
            ],
          ),
          if (session.note != null &&
              session.note!
                  .trim()
                  .isNotEmpty) ...[
            const SizedBox(
              height: 10,
            ),
            Align(
              alignment:
              Alignment.centerRight,
              child: Text(
                'ملاحظة: ${session.note}',
                style:
                const TextStyle(
                  fontSize: 10.5,
                  color: AppTheme
                      .secondaryTextColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // SOLD ITEMS
  // ===========================================================================

  Widget _buildSoldItems(
      CashboxDayReport report,
      ) {
    return _Card(
      padding:
      EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding:
            const EdgeInsets.all(
              18,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'المواد المباعة',
                    style:
                    TextStyle(
                      fontSize: 17,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${report.soldItems.length} مادة',
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
            color: AppTheme
                .subtleBorderColor,
          ),
          if (report.soldItems.isEmpty)
            const SizedBox(
              height: 150,
              child: Center(
                child: Text(
                  'لا توجد مواد مباعة.',
                ),
              ),
            )
          else
            ...report.soldItems.map(
                  (item) {
                return Container(
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  decoration:
                  const BoxDecoration(
                    border: Border(
                      bottom:
                      BorderSide(
                        color: AppTheme
                            .subtleBorderColor,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.productName,
                          style:
                          const TextStyle(
                            fontWeight:
                            FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child:
                        _InlineValue(
                          title:
                          'الكمية',
                          value:
                          _formatQuantity(
                            item.quantity,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child:
                        _InlineValue(
                          title:
                          'إجمالي البيع',
                          value:
                          _formatPrice(
                            item.totalSales,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child:
                        _InlineValue(
                          title:
                          'المرات',
                          value:
                          '${item.linesCount}',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // INVOICES
  // ===========================================================================

  Widget _buildInvoices(
      CashboxDayReport report,
      ) {
    return _Card(
      padding:
      EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding:
            const EdgeInsets.all(
              18,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'فواتير اليوم',
                    style:
                    TextStyle(
                      fontSize: 17,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${report.invoices.length} فاتورة',
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
            color: AppTheme
                .subtleBorderColor,
          ),
          if (report.invoices.isEmpty)
            const SizedBox(
              height: 150,
              child: Center(
                child: Text(
                  'لا توجد فواتير.',
                ),
              ),
            )
          else
            ...report.invoices.map(
                  (invoice) {
                return Container(
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  decoration:
                  const BoxDecoration(
                    border: Border(
                      bottom:
                      BorderSide(
                        color: AppTheme
                            .subtleBorderColor,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 180,
                        child: Text(
                          invoice
                              .invoiceNumber,
                          maxLines: 1,
                          overflow:
                          TextOverflow
                              .ellipsis,
                          style:
                          const TextStyle(
                            fontWeight:
                            FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          _formatTime(
                            invoice
                                .createdAt,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          invoice
                              .customerName,
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          _paymentTitle(
                            invoice
                                .paymentType,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: Text(
                          _formatPrice(
                            invoice.total,
                          ),
                          style:
                          const TextStyle(
                            fontWeight:
                            FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: Text(
                          invoice.cashboxSessionId ==
                              null
                              ? 'غير مرتبط'
                              : 'مرتبط بالصندوق',
                          style:
                          TextStyle(
                            fontSize: 10,
                            color: invoice.cashboxSessionId ==
                                null
                                ? AppTheme
                                .dangerColor
                                : AppTheme
                                .successColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
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

  static String _formatDate(
      DateTime date,
      ) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  static String _formatTime(
      DateTime value,
      ) {
    final local =
    value.toLocal();

    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static String _formatQuantity(
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

  static String _formatPrice(
      double value,
      ) {
    final negative =
        value < 0;

    final raw =
    value
        .abs()
        .toStringAsFixed(
      0,
    );

    final buffer =
    StringBuffer();

    for (int i = 0;
    i < raw.length;
    i++) {
      if (i > 0 &&
          (raw.length - i) %
              3 ==
              0) {
        buffer.write(',');
      }

      buffer.write(
        raw[i],
      );
    }

    return '${negative ? '-' : ''}${buffer.toString()} د.ع';
  }

  static String _formatSignedPrice(
      double value,
      ) {
    if (value.abs() < 0.01) {
      return '0 د.ع';
    }

    return value > 0
        ? '+${_formatPrice(value)}'
        : _formatPrice(value);
  }
}

// =============================================================================
// COMPONENTS
// =============================================================================

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Card({
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
      decoration:
      BoxDecoration(
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

class _Metric extends StatelessWidget {
  final String title;
  final String value;
  final bool dark;

  const _Metric({
    required this.title,
    required this.value,
    this.dark = false,
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
      decoration:
      BoxDecoration(
        color: dark
            ? const Color(
          0xFF111111,
        )
            : const Color(
          0xFFFAFAFB,
        ),
        borderRadius:
        BorderRadius.circular(
          13,
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
          Text(
            title,
            style:
            TextStyle(
              fontSize: 10,
              color: dark
                  ? Colors.white54
                  : AppTheme
                  .secondaryTextColor,
            ),
          ),
          const SizedBox(
            height: 7,
          ),
          Text(
            value,
            style:
            TextStyle(
              fontSize: 14,
              fontWeight:
              FontWeight.w700,
              color: dark
                  ? Colors.white
                  : AppTheme
                  .primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallMetric
    extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;

  const _SmallMetric({
    required this.title,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding:
      const EdgeInsets.all(
        12,
      ),
      decoration:
      BoxDecoration(
        color:
        const Color(
          0xFFFAFAFB,
        ),
        borderRadius:
        BorderRadius.circular(
          11,
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
            maxLines: 1,
            overflow:
            TextOverflow.ellipsis,
            style:
            TextStyle(
              fontSize: 11.5,
              fontWeight:
              FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineValue
    extends StatelessWidget {
  final String title;
  final String value;

  const _InlineValue({
    required this.title,
    required this.value,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
          const TextStyle(
            fontSize: 9,
            color: AppTheme
                .tertiaryTextColor,
          ),
        ),
        const SizedBox(
          height: 3,
        ),
        Text(
          value,
          style:
          const TextStyle(
            fontSize: 11,
            fontWeight:
            FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DayStatusBadge
    extends StatelessWidget {
  final String title;
  final bool open;

  const _DayStatusBadge({
    required this.title,
    required this.open,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration:
      BoxDecoration(
        color: open
            ? const Color(
          0xFFEAF7EF,
        )
            : const Color(
          0xFFF1F1F3,
        ),
        borderRadius:
        BorderRadius.circular(
          20,
        ),
      ),
      child: Text(
        title,
        style:
        TextStyle(
          fontSize: 10,
          fontWeight:
          FontWeight.w700,
          color: open
              ? AppTheme.successColor
              : AppTheme
              .secondaryTextColor,
        ),
      ),
    );
  }
}