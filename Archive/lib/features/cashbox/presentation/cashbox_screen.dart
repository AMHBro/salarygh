import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../models/cashbox_report_model.dart';
import 'cashbox_day_details_screen.dart';

class CashboxScreen extends StatefulWidget {
  const CashboxScreen({
    super.key,
  });

  @override
  State<CashboxScreen> createState() {
    return _CashboxScreenState();
  }
}

class _CashboxScreenState extends State<CashboxScreen> {
  final _repository =
      AppServices.cashboxRepository;

  CashboxDayReport? _report;
  List<CashboxDayHistoryModel> _history = [];

  bool _loading = true;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ===========================================================================
  // LOAD
  // ===========================================================================

  Future<void> _load({
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final results = await Future.wait([
        _repository.getTodayReport(),
        _repository.getDailyHistory(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _report =
        results[0] as CashboxDayReport;

        _history =
        results[1]
        as List<CashboxDayHistoryModel>;

        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });

      _showError(error);
    }
  }

  Future<void> _refresh() async {
    await _load(
      showLoading: false,
    );
  }

  // ===========================================================================
  // OPEN CASHBOX
  // ===========================================================================

  Future<void> _openCashbox() async {
    final report = _report;

    if (report?.hasOpenSession == true) {
      _showMessage(
        'توجد جلسة النقد مفتوحة حالياً.',
      );
      return;
    }

    final openingController =
    TextEditingController(
      text: '0',
    );

    final noteController =
    TextEditingController();

    final result =
    await showDialog<_OpenSessionResult>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection:
          TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'فتح جلسة جديدة',
            ),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize:
                MainAxisSize.min,
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  const Text(
                    'أدخل المبلغ الموجود فعلياً في النقد عند بداية هذه الجلسة.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme
                          .secondaryTextColor,
                    ),
                  ),
                  const SizedBox(
                    height: 18,
                  ),
                  TextField(
                    controller:
                    openingController,
                    autofocus: true,
                    keyboardType:
                    const TextInputType
                        .numberWithOptions(
                      decimal: true,
                    ),
                    decoration:
                    const InputDecoration(
                      labelText:
                      'رصيد بداية النقد',
                      suffixText:
                      'د.ع',
                    ),
                  ),
                  const SizedBox(
                    height: 14,
                  ),
                  TextField(
                    controller:
                    noteController,
                    maxLines: 3,
                    decoration:
                    const InputDecoration(
                      labelText:
                      'ملاحظة',
                      hintText:
                      'اختياري',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
                child: const Text(
                  'إلغاء',
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final opening =
                  double.tryParse(
                    openingController.text
                        .trim()
                        .replaceAll(
                      ',',
                      '',
                    ),
                  );

                  if (opening == null ||
                      opening < 0) {
                    return;
                  }

                  Navigator.pop(
                    dialogContext,
                    _OpenSessionResult(
                      openingBalance:
                      opening,
                      note:
                      noteController.text
                          .trim(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons
                      .lock_open_rounded,
                  size: 17,
                ),
                label: const Text(
                  'فتح النقد',
                ),
              ),
            ],
          ),
        );
      },
    );

    openingController.dispose();
    noteController.dispose();

    if (result == null) {
      return;
    }

    setState(() {
      _actionLoading = true;
    });

    try {
      await _repository.openSession(
        openingBalance:
        result.openingBalance,
        note:
        result.note,
      );

      await _load(
        showLoading: false,
      );

      _showMessage(
        'تم فتح جلسة النقد بنجاح.',
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _actionLoading = false;
        });
      }
    }
  }

  // ===========================================================================
  // EDIT OPENING BALANCE
  // ===========================================================================

  Future<void> _editOpeningBalance(
      CashboxSessionReport session,
      ) async {
    if (!session.isOpen) {
      return;
    }

    final controller =
    TextEditingController(
      text:
      _plainNumber(
        session.openingBalance,
      ),
    );

    final value =
    await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection:
          TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'تعديل رصيد البداية',
            ),
            content: SizedBox(
              width: 380,
              child: TextField(
                controller:
                controller,
                autofocus: true,
                keyboardType:
                const TextInputType
                    .numberWithOptions(
                  decimal: true,
                ),
                decoration:
                const InputDecoration(
                  labelText:
                  'رصيد بداية الجلسة',
                  suffixText:
                  'د.ع',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
                child: const Text(
                  'إلغاء',
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  final parsed =
                  double.tryParse(
                    controller.text
                        .trim()
                        .replaceAll(
                      ',',
                      '',
                    ),
                  );

                  if (parsed == null ||
                      parsed < 0) {
                    return;
                  }

                  Navigator.pop(
                    dialogContext,
                    parsed,
                  );
                },
                child: const Text(
                  'حفظ',
                ),
              ),
            ],
          ),
        );
      },
    );

    controller.dispose();

    if (value == null) {
      return;
    }

    try {
      await _repository
          .updateOpeningBalance(
        sessionId:
        session.id,
        openingBalance:
        value,
      );

      await _load(
        showLoading: false,
      );
    } catch (error) {
      _showError(error);
    }
  }

  // ===========================================================================
  // CLOSE SESSION
  // ===========================================================================

  Future<void> _closeSession(
      CashboxSessionReport session,
      ) async {
    if (!session.isOpen) {
      return;
    }

    final countedController =
    TextEditingController();

    final noteController =
    TextEditingController(
      text:
      session.note ?? '',
    );

    final result =
    await showDialog<_CloseSessionResult>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection:
          TextDirection.rtl,
          child: StatefulBuilder(
            builder: (
                context,
                dialogSetState,
                ) {
              final counted =
              double.tryParse(
                countedController.text
                    .trim()
                    .replaceAll(
                  ',',
                  '',
                ),
              );

              final difference =
              counted == null
                  ? null
                  : counted -
                  session.expectedCash;

              return AlertDialog(
                title: const Text(
                  'مطابقة وإغلاق النقد',
                ),
                content: SizedBox(
                  width: 500,
                  child:
                  SingleChildScrollView(
                    child: Column(
                      mainAxisSize:
                      MainAxisSize.min,
                      children: [
                        _DialogValueRow(
                          title:
                          'رصيد البداية',
                          value:
                          _formatPrice(
                            session
                                .openingBalance,
                          ),
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        _DialogValueRow(
                          title:
                          'النقد الداخل',
                          value:
                          _formatPrice(
                            session
                                .cashReceived,
                          ),
                        ),
                        const Divider(
                          height: 28,
                        ),
                        _DialogValueRow(
                          title:
                          'المفروض في النقد',
                          value:
                          _formatPrice(
                            session
                                .expectedCash,
                          ),
                          strong: true,
                        ),
                        const SizedBox(
                          height: 18,
                        ),
                        TextField(
                          controller:
                          countedController,
                          autofocus: true,
                          keyboardType:
                          const TextInputType
                              .numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) {
                            dialogSetState(
                                  () {},
                            );
                          },
                          decoration:
                          const InputDecoration(
                            labelText:
                            'النقد المعدود فعلياً',
                            suffixText:
                            'د.ع',
                          ),
                        ),
                        if (difference !=
                            null) ...[
                          const SizedBox(
                            height: 14,
                          ),
                          Container(
                            width:
                            double.infinity,
                            padding:
                            const EdgeInsets.all(
                              14,
                            ),
                            decoration:
                            BoxDecoration(
                              color:
                              const Color(
                                0xFFFAFAFB,
                              ),
                              borderRadius:
                              BorderRadius.circular(
                                12,
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
                                    'فرق المطابقة',
                                  ),
                                ),
                                Text(
                                  _formatSignedPrice(
                                    difference,
                                  ),
                                  style:
                                  TextStyle(
                                    fontWeight:
                                    FontWeight.w700,
                                    color: difference.abs() <
                                        0.01
                                        ? AppTheme
                                        .successColor
                                        : AppTheme
                                        .dangerColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(
                          height: 14,
                        ),
                        TextField(
                          controller:
                          noteController,
                          maxLines: 3,
                          decoration:
                          const InputDecoration(
                            labelText:
                            'ملاحظة الإغلاق',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                      );
                    },
                    child: const Text(
                      'إلغاء',
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed:
                    counted == null ||
                        counted < 0
                        ? null
                        : () {
                      Navigator.pop(
                        dialogContext,
                        _CloseSessionResult(
                          countedCash:
                          counted,
                          note:
                          noteController
                              .text
                              .trim(),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.lock_rounded,
                      size: 17,
                    ),
                    label: const Text(
                      'إغلاق الجلسة',
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    countedController.dispose();
    noteController.dispose();

    if (result == null) {
      return;
    }

    setState(() {
      _actionLoading = true;
    });

    try {
      await _repository.closeSession(
        sessionId:
        session.id,
        countedCash:
        result.countedCash,
        note:
        result.note,
      );

      await _load(
        showLoading: false,
      );

      _showMessage(
        'تمت مطابقة وإغلاق جلسة النقد.',
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _actionLoading = false;
        });
      }
    }
  }

  // ===========================================================================
  // OPEN DAY DETAILS
  // ===========================================================================

  Future<void> _openDay(
      String businessDate,
      ) async {
    final date =
    _parseBusinessDate(
      businessDate,
    );

    if (date == null) {
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) {
          return CashboxDayDetailsScreen(
            date: date,
          );
        },
      ),
    );

    await _load(
      showLoading: false,
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
          'تعذر تحميل بيانات النقد.',
        ),
      );
    }

    final openSession =
        report.openSession;

    return RefreshIndicator(
      onRefresh:
      _refresh,
      child: SingleChildScrollView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding:
        const EdgeInsets.fromLTRB(
          28,
          24,
          28,
          32,
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            _buildHeader(
              report,
              openSession,
            ),
            const SizedBox(
              height: 18,
            ),

            if (report
                .hasUnassignedSales) ...[
              _buildUnassignedWarning(
                report,
              ),
              const SizedBox(
                height: 14,
              ),
            ],

            _buildStats(
              report,
            ),

            const SizedBox(
              height: 14,
            ),

            if (openSession != null)
              _buildOpenSession(
                openSession,
              )
            else
              _buildNoOpenSession(),

            const SizedBox(
              height: 14,
            ),

            _buildTodaySessions(
              report,
            ),

            const SizedBox(
              height: 14,
            ),

            _buildTodayInvoices(
              report,
            ),

            const SizedBox(
              height: 14,
            ),

            _buildHistory(),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader(
      CashboxDayReport report,
      CashboxSessionReport? openSession,
      ) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'النقد',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight:
                  FontWeight.w700,
                  color: AppTheme
                      .primaryTextColor,
                ),
              ),
              SizedBox(
                height: 5,
              ),
              Text(
                'جلسات النقد ومطابقة النقد اليومية.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme
                      .secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed:
          _actionLoading
              ? null
              : _refresh,
          icon: const Icon(
            Icons.refresh_rounded,
            size: 17,
          ),
          label: const Text(
            'تحديث',
          ),
        ),
        const SizedBox(
          width: 8,
        ),
        if (openSession == null)
          ElevatedButton.icon(
            onPressed:
            _actionLoading
                ? null
                : _openCashbox,
            icon: const Icon(
              Icons
                  .lock_open_rounded,
              size: 17,
            ),
            label: const Text(
              'فتح جلسة جديدة',
            ),
          )
        else
          ElevatedButton.icon(
            onPressed:
            _actionLoading
                ? null
                : () {
              _closeSession(
                openSession,
              );
            },
            icon: const Icon(
              Icons.fact_check_outlined,
              size: 17,
            ),
            label: const Text(
              'مطابقة وإغلاق',
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // UNASSIGNED WARNING
  // ===========================================================================

  Widget _buildUnassignedWarning(
      CashboxDayReport report,
      ) {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.all(
        14,
      ),
      decoration:
      BoxDecoration(
        color:
        const Color(
          0xFFFFF8E8,
        ),
        borderRadius:
        BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color:
          const Color(
            0xFFE9D7A4,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons
                .warning_amber_rounded,
            size: 20,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              'يوجد ${report.unassignedInvoicesCount} فاتورة اليوم غير مرتبطة بجلسة النقد. '
                  'عند فتح جلسة جديدة سيتم ربط الفواتير الحديثة غير المرتبطة بها حسب منطق الاسترجاع.',
              style:
              const TextStyle(
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // STATS
  // ===========================================================================

  Widget _buildStats(
      CashboxDayReport report,
      ) {
    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        final width =
            constraints.maxWidth;

        final itemWidth =
        width >= 1100
            ? (width - 36) / 4
            : width >= 700
            ? (width - 12) / 2
            : width;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: itemWidth,
              child: _StatCard(
                title:
                'مبيعات اليوم',
                value:
                _formatPrice(
                  report.totalSales,
                ),
                subtitle:
                '${report.invoicesCount} فاتورة',
                icon:
                Icons.trending_up_rounded,
                dark: true,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _StatCard(
                title:
                'النقد الداخل',
                value:
                _formatPrice(
                  report.cashReceived,
                ),
                subtitle:
                'من المبيعات',
                icon:
                Icons.payments_outlined,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _StatCard(
                title:
                'المبيعات الآجلة',
                value:
                _formatPrice(
                  report.creditSales,
                ),
                subtitle:
                'آجل بالكامل',
                icon:
                Icons.schedule_rounded,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _StatCard(
                title:
                'جلسات اليوم',
                value:
                '${report.sessionsCount}',
                subtitle:
                report.hasOpenSession
                    ? 'توجد جلسة مفتوحة'
                    : 'لا توجد جلسة مفتوحة',
                icon:
                Icons
                    .account_balance_wallet_outlined,
              ),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // OPEN SESSION
  // ===========================================================================

  Widget _buildOpenSession(
      CashboxSessionReport session,
      ) {
    return _Panel(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration:
                BoxDecoration(
                  color:
                  const Color(
                    0xFFEAF7EF,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    20,
                  ),
                ),
                child: const Text(
                  'جلسة مفتوحة',
                  style:
                  TextStyle(
                    fontSize: 10,
                    fontWeight:
                    FontWeight.w700,
                    color: AppTheme
                        .successColor,
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Text(
                'بدأت ${_formatTime(session.openedAt)}',
                style:
                const TextStyle(
                  fontSize: 11,
                  color: AppTheme
                      .secondaryTextColor,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  _editOpeningBalance(
                    session,
                  );
                },
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 15,
                ),
                label: const Text(
                  'تعديل رصيد البداية',
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 16,
          ),
          Row(
            children: [
              Expanded(
                child:
                _SessionMetric(
                  title:
                  'رصيد البداية',
                  value:
                  _formatPrice(
                    session.openingBalance,
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                _SessionMetric(
                  title:
                  'مبيعات الجلسة',
                  value:
                  _formatPrice(
                    session.totalSales,
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                _SessionMetric(
                  title:
                  'النقد الداخل',
                  value:
                  _formatPrice(
                    session.cashReceived,
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                _SessionMetric(
                  title:
                  'المفروض بالنقد',
                  value:
                  _formatPrice(
                    session.expectedCash,
                  ),
                  dark: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoOpenSession() {
    return _Panel(
      child: SizedBox(
        height: 150,
        child: Center(
          child: Column(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              const Icon(
                Icons
                    .lock_outline_rounded,
                size: 30,
                color: AppTheme
                    .secondaryTextColor,
              ),
              const SizedBox(
                height: 10,
              ),
              const Text(
                'لا توجد جلسة النقد مفتوحة',
                style:
                TextStyle(
                  fontSize: 15,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
              const SizedBox(
                height: 5,
              ),
              const Text(
                'يجب فتح جلسة جديدة قبل تسجيل عمليات بيع جديدة.',
                style:
                TextStyle(
                  fontSize: 11,
                  color: AppTheme
                      .secondaryTextColor,
                ),
              ),
              const SizedBox(
                height: 14,
              ),
              ElevatedButton.icon(
                onPressed:
                _actionLoading
                    ? null
                    : _openCashbox,
                icon: const Icon(
                  Icons
                      .lock_open_rounded,
                  size: 16,
                ),
                label: const Text(
                  'فتح جلسة جديدة',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TODAY SESSIONS
  // ===========================================================================

  Widget _buildTodaySessions(
      CashboxDayReport report,
      ) {
    return _Panel(
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
                    'جلسات اليوم',
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
              height: 130,
              child: Center(
                child: Text(
                  'لم يتم فتح أي جلسة النقد اليوم.',
                  style:
                  TextStyle(
                    color: AppTheme
                        .secondaryTextColor,
                  ),
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

                return Container(
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
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
                        width: 115,
                        child: Text(
                          'جلسة #$number',
                          style:
                          const TextStyle(
                            fontWeight:
                            FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child:
                        _MiniValue(
                          title:
                          'الوقت',
                          value: session
                              .closedAt ==
                              null
                              ? '${_formatTime(session.openedAt)} → الآن'
                              : '${_formatTime(session.openedAt)} → ${_formatTime(session.closedAt!)}',
                        ),
                      ),
                      Expanded(
                        child:
                        _MiniValue(
                          title:
                          'المبيعات',
                          value:
                          _formatPrice(
                            session.totalSales,
                          ),
                        ),
                      ),
                      Expanded(
                        child:
                        _MiniValue(
                          title:
                          'الفواتير',
                          value:
                          '${session.invoicesCount}',
                        ),
                      ),
                      Expanded(
                        child:
                        _MiniValue(
                          title:
                          'الفرق',
                          value: session
                              .difference ==
                              null
                              ? '-'
                              : _formatSignedPrice(
                            session
                                .difference!,
                          ),
                        ),
                      ),
                      _StatusBadge(
                        open:
                        session.isOpen,
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
  // TODAY INVOICES
  // ===========================================================================

  Widget _buildTodayInvoices(
      CashboxDayReport report,
      ) {
    return _Panel(
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
              height: 140,
              child: Center(
                child: Text(
                  'لا توجد مبيعات اليوم.',
                ),
              ),
            )
          else
            ...report.invoices
                .take(10)
                .map(
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
                        width: 170,
                        child: Text(
                          invoice
                              .invoiceNumber,
                          maxLines: 1,
                          overflow:
                          TextOverflow
                              .ellipsis,
                          style:
                          const TextStyle(
                            fontSize: 11,
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
                          style:
                          const TextStyle(
                            fontSize: 10.5,
                            color: AppTheme
                                .secondaryTextColor,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          invoice
                              .customerName,
                          maxLines: 1,
                          overflow:
                          TextOverflow
                              .ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 100,
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
                    ],
                  ),
                );
              },
            ),
          if (report.invoices.length >
              10)
            Padding(
              padding:
              const EdgeInsets.all(
                14,
              ),
              child: OutlinedButton(
                onPressed: () {
                  _openDay(
                    report.businessDate,
                  );
                },
                child: const Text(
                  'عرض التقرير الكامل',
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HISTORY
  // ===========================================================================

  Widget _buildHistory() {
    return _Panel(
      padding:
      EdgeInsets.zero,
      child: Column(
        children: [
          const Padding(
            padding:
            EdgeInsets.all(
              18,
            ),
            child: Align(
              alignment:
              Alignment.centerRight,
              child: Text(
                'سجل الأيام',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ),
          ),
          const Divider(
            height: 1,
            color: AppTheme
                .subtleBorderColor,
          ),
          if (_history.isEmpty)
            const SizedBox(
              height: 130,
              child: Center(
                child: Text(
                  'لا يوجد سجل.',
                ),
              ),
            )
          else
            ..._history
                .take(30)
                .map(
                  (day) {
                return Material(
                  color: Colors.white,
                  child: InkWell(
                    onTap: () {
                      _openDay(
                        day.businessDate,
                      );
                    },
                    child: Container(
                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration:
                      const BoxDecoration(
                        border:
                        Border(
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
                            width: 140,
                            child:
                            Text(
                              _displayDate(
                                day.businessDate,
                              ),
                              style:
                              const TextStyle(
                                fontWeight:
                                FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child:
                            _MiniValue(
                              title:
                              'المبيعات',
                              value:
                              _formatPrice(
                                day.totalSales,
                              ),
                            ),
                          ),
                          Expanded(
                            child:
                            _MiniValue(
                              title:
                              'النقد',
                              value:
                              _formatPrice(
                                day.cashReceived,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child:
                            _MiniValue(
                              title:
                              'الجلسات',
                              value:
                              '${day.sessionsCount}',
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child:
                            _MiniValue(
                              title:
                              'الفواتير',
                              value:
                              '${day.invoicesCount}',
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child:
                            _MiniValue(
                              title:
                              'الفرق',
                              value:
                              day.difference ==
                                  null
                                  ? '-'
                                  : _formatSignedPrice(
                                day.difference!,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons
                                .chevron_left_rounded,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
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
        return 'عهدة';
      default:
        return value;
    }
  }

  String _displayDate(
      String value,
      ) {
    final date =
    _parseBusinessDate(
      value,
    );

    if (date == null) {
      return value;
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  DateTime? _parseBusinessDate(
      String value,
      ) {
    final parts =
    value.split('-');

    if (parts.length != 3) {
      return null;
    }

    final year =
    int.tryParse(
      parts[0],
    );

    final month =
    int.tryParse(
      parts[1],
    );

    final day =
    int.tryParse(
      parts[2],
    );

    if (year == null ||
        month == null ||
        day == null) {
      return null;
    }

    return DateTime(
      year,
      month,
      day,
    );
  }

  static String _formatTime(
      DateTime value,
      ) {
    final local =
    value.toLocal();

    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static String _plainNumber(
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
          (raw.length - i) % 3 ==
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

  void _showMessage(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content:
        Text(message),
      ),
    );
  }

  void _showError(
      Object error,
      ) {
    _showMessage(
      error
          .toString()
          .replaceFirst(
        'Bad state: ',
        '',
      )
          .replaceFirst(
        'Invalid argument(s): ',
        '',
      ),
    );
  }
}

// =============================================================================
// UI COMPONENTS
// =============================================================================

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Panel({
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

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final bool dark;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.dark = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 128,
      padding:
      const EdgeInsets.all(
        17,
      ),
      decoration:
      BoxDecoration(
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
              Icon(
                icon,
                size: 18,
                color: dark
                    ? Colors.white70
                    : AppTheme
                    .secondaryTextColor,
              ),
              const Spacer(),
              Text(
                subtitle,
                style:
                TextStyle(
                  fontSize: 9.5,
                  color: dark
                      ? Colors.white54
                      : AppTheme
                      .tertiaryTextColor,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            style:
            TextStyle(
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
            style:
            TextStyle(
              fontSize: 20,
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

class _SessionMetric
    extends StatelessWidget {
  final String title;
  final String value;
  final bool dark;

  const _SessionMetric({
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
            maxLines: 1,
            overflow:
            TextOverflow.ellipsis,
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

class _MiniValue
    extends StatelessWidget {
  final String title;
  final String value;

  const _MiniValue({
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
            fontSize: 9.5,
            color: AppTheme
                .tertiaryTextColor,
          ),
        ),
        const SizedBox(
          height: 3,
        ),
        Text(
          value,
          maxLines: 1,
          overflow:
          TextOverflow.ellipsis,
          style:
          const TextStyle(
            fontSize: 11.5,
            fontWeight:
            FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge
    extends StatelessWidget {
  final bool open;

  const _StatusBadge({
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
        open
            ? 'مفتوح'
            : 'مغلق',
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

class _DialogValueRow
    extends StatelessWidget {
  final String title;
  final String value;
  final bool strong;

  const _DialogValueRow({
    required this.title,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style:
            TextStyle(
              fontWeight:
              strong
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style:
          TextStyle(
            fontSize:
            strong ? 15 : 12,
            fontWeight:
            FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _OpenSessionResult {
  final double openingBalance;
  final String note;

  const _OpenSessionResult({
    required this.openingBalance,
    required this.note,
  });
}

class _CloseSessionResult {
  final double countedCash;
  final String note;

  const _CloseSessionResult({
    required this.countedCash,
    required this.note,
  });
}