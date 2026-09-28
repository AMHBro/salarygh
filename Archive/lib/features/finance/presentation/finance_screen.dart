import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/money/party_balance.dart';
import '../../../core/printing/print_preview.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/data/company_settings_repository.dart';
import '../data/currency_exchange_repository.dart';
import '../models/financial_account_model.dart';
import '../models/payment_transaction_model.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  final _repository = AppServices.financeRepository;

  final TextEditingController _searchController = TextEditingController();

  List<FinancialAccountModel> _accounts = [];
  List<PaymentTransactionModel> _transactions = [];

  String _selectedAccountType = 'الكل';

  bool _isLoading = true;
  bool _showVouchers = false;
  int _accountPage = 1;
  int _voucherPage = 1;

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_refresh);

    _loadData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_refresh);
    _searchController.dispose();

    super.dispose();
  }

  // ===========================================================================
  // DATA
  // ===========================================================================

  void _refresh() {
    if (!mounted) {
      return;
    }

    setState(() {
      _accountPage = 1;
      _voucherPage = 1;
    });
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final results = await Future.wait([
        _repository.getAccounts(),
        _repository.getTransactions(),
      ]);

      final accounts = results[0] as List<FinancialAccountModel>;

      final transactions = results[1] as List<PaymentTransactionModel>;

      if (!mounted) {
        return;
      }

      setState(() {
        _accounts = accounts;
        _transactions = transactions;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      _showMessage(
        _errorMessage(error),
      );
    }
  }

  // ===========================================================================
  // FILTERS
  // ===========================================================================

  List<FinancialAccountModel> get _filteredAccounts {
    final query = _searchController.text.trim().toLowerCase();

    return _accounts.where((account) {
      final matchesSearch =
          query.isEmpty ||
              account.name.toLowerCase().contains(query) ||
              account.phone.contains(query);

      final matchesType = switch (_selectedAccountType) {
        'الزبائن' => account.type == FinancialAccountType.customerDebt,
        'الموردون' => account.type == FinancialAccountType.supplierPayable,
        'المندوبون' =>
        account.type == FinancialAccountType.representativeCommission,
        _ => true,
      };

      return matchesSearch && matchesType;
    }).toList();
  }

  List<PaymentTransactionModel> get _filteredTransactions {
    final query = _searchController.text.trim().toLowerCase();
    final accountsById = {for (final account in _accounts) account.id: account};

    final transactions = _transactions.where((transaction) {
      final account = accountsById[transaction.accountId];
      final phone = account?.phone ?? '';
      final matchesSearch =
          query.isEmpty ||
          transaction.accountName.toLowerCase().contains(query) ||
          transaction.voucherNumber.toLowerCase().contains(query) ||
          phone.contains(query);

      final matchesType = switch (_selectedAccountType) {
        'الزبائن' => account?.type == FinancialAccountType.customerDebt,
        'الموردون' => account?.type == FinancialAccountType.supplierPayable,
        'المندوبون' =>
          account?.type == FinancialAccountType.representativeCommission,
        _ => true,
      };

      return matchesSearch && matchesType;
    }).toList();

    transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return transactions;
  }

  // ===========================================================================
  // TOTALS
  // ===========================================================================

  double get _customerDebts {
    return _accounts
        .where(
          (account) => account.type == FinancialAccountType.customerDebt,
    )
        .fold(
      0,
          (sum, account) =>
              sum + (account.remainingAmount > 0 ? account.remainingAmount : 0),
    );
  }

  double get _supplierPayables {
    return _accounts
        .where(
          (account) => account.type == FinancialAccountType.supplierPayable,
    )
        .fold(
      0,
          (sum, account) => sum + account.remainingAmount,
    );
  }

  double get _representativePayables {
    return _accounts
        .where(
          (account) =>
      account.type == FinancialAccountType.representativeCommission,
    )
        .fold(
      0,
          (sum, account) => sum + account.remainingAmount,
    );
  }

  double get _totalOpenBalances {
    return _customerDebts + _supplierPayables + _representativePayables;
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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
              const SizedBox(height: 28),
              _buildStats(),
              const SizedBox(height: 22),
              _buildLedgerSection(),
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
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الديون والدفعات',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: AppTheme.primaryTextColor,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'إدارة ديون الزبائن ومستحقات الموردين وعمولات المندوبين.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),

        OutlinedButton.icon(
          onPressed: _showDollarExchange,
          icon: const Icon(Icons.currency_exchange_rounded, size: 18),
          label: const Text('دولار'),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _loadData,
          icon: const Icon(
            Icons.refresh_rounded,
            size: 18,
          ),
          label: const Text(
            'تحديث',
          ),
        ),

        const SizedBox(width: 10),

        OutlinedButton.icon(
          onPressed: () => _showMoneyDialog(
            PaymentTransactionType.payment,
          ),
          icon: const Icon(
            Icons.arrow_upward_rounded,
            size: 18,
          ),
          label: const Text(
            'دفع',
          ),
        ),

        const SizedBox(width: 10),

        ElevatedButton.icon(
          onPressed: () => _showMoneyDialog(
            PaymentTransactionType.receipt,
          ),
          icon: const Icon(
            Icons.arrow_downward_rounded,
            size: 18,
          ),
          label: const Text(
            'قبض',
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // STATS
  // ===========================================================================

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: 'إجمالي الذمم',
            value: _formatPrice(
              _totalOpenBalances,
            ),
            subtitle: 'جميع المبالغ المفتوحة',
            icon: Icons.account_balance_wallet_outlined,
            highlighted: true,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title: 'ديون الزبائن',
            value: _formatPrice(
              _customerDebts,
            ),
            subtitle: 'مبالغ مستحقة من الزبائن',
            icon: Icons.people_outline_rounded,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title: 'مستحقات الموردين',
            value: _formatPrice(
              _supplierPayables,
            ),
            subtitle: 'مبالغ مستحقة للموردين',
            icon: Icons.business_outlined,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title: 'عمولات المندوبين',
            value: _formatPrice(
              _representativePayables,
            ),
            subtitle: 'عمولات غير مسددة',
            icon: Icons.badge_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildTableSwitch() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FinanceTableBadge(
          label: 'الحسابات المفتوحة',
          count: _filteredAccounts.length,
          selected: !_showVouchers,
          onTap: () {
            setState(() {
              _showVouchers = false;
            });
          },
        ),
        _FinanceTableBadge(
          label: 'آخر السندات',
          count: _filteredTransactions.length,
          selected: _showVouchers,
          onTap: () {
            setState(() {
              _showVouchers = true;
            });
          },
        ),
      ],
    );
  }

  // ===========================================================================
  // ACCOUNTS
  // ===========================================================================

  Widget _buildLedgerSection() {
    final accounts = _filteredAccounts;
    final transactions = _filteredTransactions;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _buildTableSwitch(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: _showVouchers
                          ? 'بحث بالاسم أو الهاتف أو رقم السند'
                          : 'بحث بالاسم أو الهاتف',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedAccountType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'الكل',
                        child: Text('كل الحسابات'),
                      ),
                      DropdownMenuItem(
                        value: 'الزبائن',
                        child: Text('الزبائن'),
                      ),
                      DropdownMenuItem(
                        value: 'الموردون',
                        child: Text('الشركات'),
                      ),
                      DropdownMenuItem(
                        value: 'المندوبون',
                        child: Text('المندوبون'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _selectedAccountType = value;
                        _accountPage = 1;
                        _voucherPage = 1;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_showVouchers) ...[
            const _TransactionsTableHeader(),
            if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 45),
                child: Text(
                  'لا توجد سندات مطابقة.',
                  style: TextStyle(color: AppTheme.secondaryTextColor),
                ),
              )
            else
              ...transactions
                  .skip((_voucherPage - 1) * kListPageSize)
                  .take(kListPageSize)
                  .map(_buildTransactionRow),
            ListPagination(
              page: _voucherPage,
              totalItems: transactions.length,
              onPageChanged: (page) {
                setState(() {
                  _voucherPage = page;
                });
              },
            ),
          ] else ...[
          const _AccountsTableHeader(),

          if (accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 55,
              ),
              child: Text(
                'لا توجد حسابات مطابقة.',
                style: TextStyle(
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            )
          else
            ...accounts
                .skip((_accountPage - 1) * kListPageSize)
                .take(kListPageSize)
                .map(
              _buildAccountRow,
            ),
          ListPagination(
            page: _accountPage,
            totalItems: accounts.length,
            onPageChanged: (page) {
              setState(() {
                _accountPage = page;
              });
            },
          ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountRow(
      FinancialAccountModel account,
      ) {
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.subtleBorderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFFF5F5F7,
                    ),
                    borderRadius: BorderRadius.circular(
                      10,
                    ),
                  ),
                  child: Icon(
                    _iconForAccountType(
                      account.type,
                    ),
                    size: 18,
                  ),
                ),

                const SizedBox(width: 11),

                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        account.phone.trim().isEmpty
                            ? 'بدون رقم هاتف'
                            : account.phone,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            flex: 2,
            child: _AccountTypeBadge(
              type: account.type,
            ),
          ),

          Expanded(
            flex: 3,
            child: Text(
              _formatPrice(
                account.totalAmount,
              ),
              style: const TextStyle(
                fontSize: 11.5,
              ),
            ),
          ),

          Expanded(
            flex: 3,
            child: Text(
              _formatPrice(
                account.paidAmount,
              ),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),

          Expanded(
            flex: 3,
            child: _BalanceBadge(
              amount: account.remainingAmount,
              amountUsd: account.remainingUsd,
            ),
          ),

          Expanded(
            flex: 3,
            child: Text(
              account.lastPaymentDate == null
                  ? '-'
                  : _formatDate(
                account.lastPaymentDate!,
              ),
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),

          SizedBox(
            width: 50,
            child: PopupMenuButton<String>(
              tooltip: 'خيارات',
              icon: const Icon(
                Icons.more_horiz_rounded,
              ),
              onSelected: (value) {
                if (value == 'commission') {
                  _showRepresentativePendingMessage();
                  return;
                }

                if (account.type ==
                    FinancialAccountType.representativeCommission) {
                  return;
                }

                _showTransactionDialog(
                  accounts: [account],
                  transactionType: value == 'payment'
                      ? PaymentTransactionType.payment
                      : PaymentTransactionType.receipt,
                  predefinedAccount: account,
                );
              },
              itemBuilder: (context) {
                if (account.type ==
                    FinancialAccountType.representativeCommission) {
                return [
                    const PopupMenuItem(
                      value: 'commission',
                      child: Text('دفع عمولة'),
                    ),
                  ];
                }

                return const [
                  PopupMenuItem(
                    value: 'receipt',
                    child: Text('سند قبض'),
                  ),
                  PopupMenuItem(
                    value: 'payment',
                    child: Text('سند دفع'),
                  ),
                ];
              },
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TRANSACTIONS
  // ===========================================================================

  Widget _buildTransactionRow(
      PaymentTransactionModel transaction,
      ) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.subtleBorderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              transaction.voucherNumber,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              transaction.accountName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: _TransactionTypeBadge(
              type: transaction.type,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              transaction.method.title,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatPrice(
                transaction.amount,
              ),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatDateTime(
                transaction.createdAt,
              ),
              style: const TextStyle(
                fontSize: 10.5,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              transaction.userName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
          IconButton(
            tooltip: 'طباعة السند',
            onPressed: () => _printVoucher(transaction),
            icon: const Icon(Icons.print_outlined, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _showDollarExchange() async {
    var kind = 'BUY';
    var rate = 0.0;
    try {
      final company = await CompanySettingsRepository(
        apiClient: AppServices.apiClient,
      ).getCompany();
      final settings = company['settings'];
      final raw = settings is Map ? settings['usd_exchange_rate'] : null;
      rate = double.tryParse('${raw ?? ''}'.replaceAll(',', '')) ?? 0;
    } catch (_) {}
    if (!mounted) {
      return;
    }
    final usdController = TextEditingController();
    final rateController = TextEditingController(
      text: rate > 0 ? rate.toStringAsFixed(0) : '',
    );
    final partyController = TextEditingController();
    final noteController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setLocal) {
              final usd = double.tryParse(usdController.text.replaceAll(',', '')) ?? 0;
              final usedRate = double.tryParse(rateController.text.replaceAll(',', '')) ?? 0;
              final iqd = usd * usedRate;
              return AlertDialog(
                title: const Text('شراء أو بيع دولار'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('أشتري دولار'),
                            selected: kind == 'BUY',
                            onSelected: (_) => setLocal(() => kind = 'BUY'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('أبيع دولار'),
                            selected: kind == 'SELL',
                            onSelected: (_) => setLocal(() => kind = 'SELL'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: partyController,
                        decoration: const InputDecoration(
                          labelText: 'الاسم',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: usdController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setLocal(() {}),
                        decoration: const InputDecoration(
                          labelText: 'مبلغ الدولار',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: rateController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setLocal(() {}),
                        decoration: const InputDecoration(
                          labelText: 'سعر الدولار',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('المقابل: ${iqd.toStringAsFixed(0)} دينار'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: noteController,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظة',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: usedRate <= 0 || usd <= 0
                        ? null
                        : () => Navigator.pop(dialogContext, true),
                    child: const Text('حفظ وطباعة'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    if (saved != true || !mounted) {
      usdController.dispose();
      rateController.dispose();
      partyController.dispose();
      noteController.dispose();
      return;
    }
    final usd = double.tryParse(usdController.text.replaceAll(',', '')) ?? 0;
    final usedRate = double.tryParse(rateController.text.replaceAll(',', '')) ?? 0;
    final party = partyController.text.trim();
    final note = noteController.text.trim();
    usdController.dispose();
    rateController.dispose();
    partyController.dispose();
    noteController.dispose();
    try {
      final exchange = await CurrencyExchangeRepository(
        database: AppServices.database,
      ).create(
        kind: kind,
        usdAmount: usd,
        rate: usedRate,
        partyName: party,
        note: note,
      );
      if (!mounted) {
        return;
      }
      final buy = exchange.kind == 'BUY';
      await showPrintPreview(
        context,
        PrintDocument(
          kind: 'وصل',
          title: buy ? 'شراء دولار' : 'بيع دولار',
          party: exchange.partyName,
          printedDate: printDateText(exchange.createdAt),
          printedTime: printTimeText(exchange.createdAt),
          documentType: buy ? 'شراء دولار' : 'بيع دولار',
          lines: [
            if (exchange.note.isNotEmpty) 'ملاحظة: ${exchange.note}',
            'سعر الدولار: ${exchange.rate.toStringAsFixed(0)}',
          ],
          grandTotal: exchange.iqdAmount,
          paidIqd: buy ? exchange.iqdAmount : 0,
          paidUsd: buy ? 0 : exchange.usdAmount,
          remainingIqd: buy ? 0 : exchange.iqdAmount,
          remainingUsd: buy ? exchange.usdAmount : 0,
          totals: [
            'الكلي: ${exchange.iqdAmount.toStringAsFixed(0)}',
          ],
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _printVoucher(PaymentTransactionModel transaction) async {
    final snapshot = await AppServices.customersRepository.snapshotForPayment(
          transaction.id,
        ) ??
        await AppServices.suppliersRepository.snapshotForPayment(
          transaction.id,
        );
    if (!mounted) {
      return;
    }
    if (snapshot == null) {
      _showMessage('تعذر قراءة رصيد هذا السند من السجل المحفوظ.');
      return;
    }
    FinancialAccountModel? account;
    for (final item in _accounts) {
      if (item.id == transaction.accountId) {
        account = item;
        break;
      }
    }
    final disbursement = snapshot.isDisbursement;
    final movement = groupedWhole(snapshot.amount.wholeDinars);
    showPrintPreview(
      context,
      PrintDocument(
        kind: transaction.type.title,
        title: transaction.voucherNumber,
        partyLabel: account?.type.title ?? 'الحساب',
        party: transaction.accountName,
        printedDate: printDateText(transaction.createdAt),
        printedTime: printTimeText(transaction.createdAt),
        documentTypeLabel: 'النوع',
        documentType: disbursement ? 'سند دفع' : 'سند قبض',
        lines: [
          'الرصيد السابق: ${balanceWords(snapshot.previous)}',
          disbursement
              ? 'صرف $movement يزيد ما على الطرف'
              : 'قبض $movement ينقص ما على الطرف',
          'الرصيد الحالي: ${balanceWords(snapshot.remaining)}',
          'طريقة الدفع: ${transaction.method.title}',
          if ((transaction.note ?? '').trim().isNotEmpty)
            'ملاحظة: ${transaction.note!.trim()}',
        ],
        grandTotal: snapshot.amount.toDouble(),
        previousIqd: snapshot.previous.toDouble(),
        paidIqd: snapshot.amount.toDouble(),
        remainingIqd: snapshot.remaining.toDouble(),
        previousIqdLabel: 'الرصيد السابق',
        paidIqdLabel: disbursement ? 'مبلغ الصرف' : 'مبلغ القبض',
        remainingIqdLabel: 'الرصيد الحالي',
        totals: [
          'المبلغ: ${groupedWhole(snapshot.amount.wholeDinars)}',
          'الرصيد السابق: ${groupedWhole(snapshot.previous.wholeDinars)}',
          'الرصيد الحالي: ${groupedWhole(snapshot.remaining.wholeDinars)}',
        ],
      ),
    );
  }

  Future<void> _showIssuedVoucher({
    required String voucherNumber,
    required FinancialAccountModel account,
    required PaymentTransactionType transactionType,
    required double amount,
    required PaymentMethod method,
    required String note,
  }) {
    final transaction = PaymentTransactionModel(
      id: voucherNumber,
      voucherNumber: voucherNumber,
      accountId: account.id,
      accountName: account.name,
      type: transactionType,
      method: method,
      amount: amount,
      createdAt: DateTime.now(),
      userName: 'مدير النظام',
      note: note.trim().isEmpty ? null : note.trim(),
    );
    final title = transactionType == PaymentTransactionType.receipt
        ? 'سند قبض'
        : 'سند دفع';

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'رقم السند',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                voucherNumber,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(account.name),
              const SizedBox(height: 4),
              Text(_formatPrice(amount)),
              const SizedBox(height: 10),
              Text(
                _savedMessage(transactionType, account, amount),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _printVoucher(transaction);
              },
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('طباعة السند'),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // GENERAL ACTIONS
  // ===========================================================================

  void _showMoneyDialog(PaymentTransactionType transactionType) {
    final accounts = _accounts
        .where(
          (account) =>
              account.type == FinancialAccountType.customerDebt ||
              account.type == FinancialAccountType.supplierPayable,
    )
        .toList();

    if (accounts.isEmpty) {
      _showMessage(
        'لا يوجد زبون أو شركة لتسجيل السند.',
      );
      return;
    }

    _showTransactionDialog(
      accounts: accounts,
      transactionType: transactionType,
    );
  }

  void _showRepresentativePendingMessage() {
    _showMessage(
      'دفع عمولات المندوبين سيُفعّل بعد تثبيت API المندوبين في الـBackend.',
    );
  }

  // ===========================================================================
  // TRANSACTION DIALOG
  // ===========================================================================

  void _showTransactionDialog({
    required List<FinancialAccountModel> accounts,
    required PaymentTransactionType transactionType,
    FinancialAccountModel? predefinedAccount,
  }) {
    final customers = accounts
        .where(
          (account) => account.type == FinancialAccountType.customerDebt,
        )
        .toList();
    final companies = accounts
        .where(
          (account) => account.type == FinancialAccountType.supplierPayable,
        )
        .toList();
    var party = predefinedAccount == null
        ? (customers.isNotEmpty ? 'customer' : 'company')
        : predefinedAccount.type == FinancialAccountType.customerDebt
            ? 'customer'
            : 'company';
    FinancialAccountModel selectedAccount = predefinedAccount ??
        (party == 'customer' ? customers.first : companies.first);

    PaymentMethod selectedMethod = PaymentMethod.cash;
    var voucherCurrency = 'IQD';

    final amountController = TextEditingController();
    final noteController = TextEditingController();

    bool saving = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(
                  _dialogTitle(
                    transactionType,
                    selectedAccount.type,
                  ),
                ),
                content: SizedBox(
                  width: 560,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (predefinedAccount == null) ...[
                        const Text(
                          'الطرف',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('زبون'),
                              selected: party == 'customer',
                              onSelected: customers.isEmpty || saving
                                  ? null
                                  : (_) {
                                      setDialogState(() {
                                        party = 'customer';
                                        selectedAccount = customers.first;
                                      });
                                    },
                            ),
                            ChoiceChip(
                              label: const Text('شركة'),
                              selected: party == 'company',
                              onSelected: companies.isEmpty || saving
                                  ? null
                                  : (_) {
                                      setDialogState(() {
                                        party = 'company';
                                        selectedAccount = companies.first;
                                      });
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                      const Text(
                        'الحساب',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),

                      const SizedBox(height: 7),

                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          '$party-${selectedAccount.id}',
                        ),
                        initialValue: selectedAccount.id,
                        isExpanded: true,
                        items: (party == 'customer' ? customers : companies).map(
                              (account) {
                            return DropdownMenuItem<String>(
                              value: account.id,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      account.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    account.type.title,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.secondaryTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ).toList(),
                        onChanged: predefinedAccount != null
                            ? null
                            : (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(() {
                            final visible = party == 'customer'
                                ? customers
                                : companies;
                            selectedAccount = visible.firstWhere(
                                  (account) => account.id == value,
                            );
                          });
                        },
                      ),

                      const SizedBox(height: 14),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF5F5F7,
                          ),
                          borderRadius: BorderRadius.circular(
                            13,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _balanceTitle(
                                  selectedAccount.type,
                                  selectedAccount.remainingAmount,
                                ),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.secondaryTextColor,
                                ),
                              ),
                            ),
                            Text(
                              partyBalanceLabel(
                                selectedAccount.remainingAmount,
                                selectedAccount.remainingUsd,
                              ),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      _DialogField(
                        title: 'المبلغ',
                        controller: amountController,
                        numeric: true,
                      ),

                      const SizedBox(height: 14),

                      DropdownButtonFormField<String>(
                        initialValue: voucherCurrency,
                        items: const [
                          DropdownMenuItem(
                            value: 'IQD',
                            child: Text('دينار'),
                          ),
                          DropdownMenuItem(
                            value: 'USD',
                            child: Text('دولار'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            voucherCurrency = value;
                          });
                        },
                      ),

                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _movementHint(
                            transactionType,
                            selectedAccount.type,
                          ),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.secondaryTextColor,
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      const Text(
                        'طريقة الدفع',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),

                      const SizedBox(height: 7),

                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: PaymentMethod.values.map(
                              (method) {
                            final selected = selectedMethod == method;

                            return OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: selected
                                    ? AppTheme.primaryColor
                                    : Colors.white,
                                foregroundColor: selected
                                    ? Colors.white
                                    : AppTheme.primaryTextColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 13,
                                ),
                              ),
                              onPressed: saving
                                  ? null
                                  : () {
                                setDialogState(() {
                                  selectedMethod = method;
                                });
                              },
                              child: Text(
                                method.title,
                              ),
                            );
                          },
                        ).toList(),
                      ),

                      const SizedBox(height: 14),

                      _DialogField(
                        title: 'ملاحظة',
                        controller: noteController,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () {
                      Navigator.pop(
                        dialogContext,
                      );
                    },
                    child: const Text(
                      'إلغاء',
                    ),
                  ),

                  ElevatedButton(
                    onPressed: saving
                        ? null
                        : () async {
                      final amount =
                          double.tryParse(
                            amountController.text
                                .trim()
                                .replaceAll(
                              ',',
                              '',
                            ),
                          ) ??
                              0;

                      if (amount <= 0) {
                        _showMessage(
                          'أدخل مبلغاً صحيحاً.',
                        );
                        return;
                      }

                      setDialogState(() {
                        saving = true;
                      });

                      try {
                        final voucherNumber = await _saveTransaction(
                          account: selectedAccount,
                          transactionType: transactionType,
                          amount: amount,
                          method: selectedMethod,
                          note: noteController.text,
                          currency: voucherCurrency,
                        );

                        if (!dialogContext.mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                        );

                        await _loadData();

                        if (!mounted) {
                          return;
                        }

                        await _showIssuedVoucher(
                          voucherNumber: voucherNumber,
                          account: selectedAccount,
                          transactionType: transactionType,
                          amount: amount,
                          method: selectedMethod,
                          note: noteController.text,
                        );
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                          });
                        }

                        _showMessage(
                          _errorMessage(error),
                        );
                      }
                    },
                    child: Text(
                      transactionType == PaymentTransactionType.receipt
                          ? 'حفظ سند القبض'
                          : 'حفظ سند الدفع',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // SAVE TRANSACTION
  // ===========================================================================

  Future<String> _saveTransaction({
    required FinancialAccountModel account,
    required PaymentTransactionType transactionType,
    required double amount,
    required PaymentMethod method,
    required String note,
    String currency = 'IQD',
  }) async {
    final isReceipt = transactionType == PaymentTransactionType.receipt;

    switch (account.type) {
      case FinancialAccountType.customerDebt:
        if (isReceipt) {
          return _repository.registerCustomerReceipt(
          customerId: account.id,
          amount: amount,
          method: method,
          note: note,
          currency: currency,
        );
        }
        return _repository.registerCustomerDisbursement(
          customerId: account.id,
          amount: amount,
          method: method,
          note: note,
          currency: currency,
        );

      case FinancialAccountType.supplierPayable:
        if (isReceipt) {
          return _repository.registerSupplierReceipt(
          supplierId: account.id,
          amount: amount,
          method: method,
          note: note,
          currency: currency,
        );
        }
        return _repository.registerSupplierPayment(
          supplierId: account.id,
          amount: amount,
          method: method,
          note: note,
          currency: currency,
        );

      case FinancialAccountType.representativeCommission:
        throw StateError(
          'دفع عمولات المندوبين غير مربوط بالـBackend حالياً.',
        );
    }
  }

  // ===========================================================================
  // LABELS
  // ===========================================================================

  String _dialogTitle(
      PaymentTransactionType type,
      FinancialAccountType accountType,
      ) {
    final receipt = type == PaymentTransactionType.receipt;

    switch (accountType) {
      case FinancialAccountType.customerDebt:
        return receipt ? 'سند قبض من زبون' : 'سند دفع لزبون';

      case FinancialAccountType.supplierPayable:
        return receipt ? 'سند قبض من شركة' : 'سند دفع لشركة';

      case FinancialAccountType.representativeCommission:
        return 'دفع عمولة مندوب';
    }
  }

  String _movementHint(
    PaymentTransactionType type,
    FinancialAccountType accountType,
  ) {
    final receipt = type == PaymentTransactionType.receipt;

    if (accountType == FinancialAccountType.customerDebt) {
      return receipt
          ? 'إذا دفع الزبون أكثر من المستحق، يُسجل المبلغ كاملاً والفرق يصبح رصيداً دائناً.'
          : 'يُسجل المبلغ مدفوعاً للزبون، فينقص رصيده الدائن أو يزيد ما عليه.';
    }

    if (accountType == FinancialAccountType.supplierPayable) {
      return receipt
          ? 'يُسجل المبلغ قبضاً من الشركة وينقص ما علينا لها. الزيادة تُسجل دائنة.'
          : 'إذا دُفع أكثر من المستحق، يُسجل المبلغ كاملاً والفرق يصبح رصيداً دائناً على الشركة.';
    }

    return '';
  }

  String _balanceTitle(
      FinancialAccountType type,
      double amount,
      ) {
    switch (type) {
      case FinancialAccountType.customerDebt:
        if (amount < 0) {
          return 'رصيد دائن على الزبون';
        }
        return 'الدين المتبقي';

      case FinancialAccountType.supplierPayable:
        if (amount < 0) {
          return 'رصيد دائن على الشركة';
        }
        return 'المستحق للشركة';

      case FinancialAccountType.representativeCommission:
        return 'العمولة المستحقة';
    }
  }

  String _savedMessage(
    PaymentTransactionType type,
    FinancialAccountModel account,
    double amount,
  ) {
    final receipt = type == PaymentTransactionType.receipt;
    final over = amount > account.remainingAmount &&
        amount > account.remainingUsd;

    if (receipt &&
        account.type == FinancialAccountType.customerDebt &&
        over) {
      return 'تم حفظ سند القبض، والفرق سُجل دائناً على الزبون.';
    }

    if (!receipt &&
        account.type == FinancialAccountType.supplierPayable &&
        over) {
      return 'تم حفظ سند الدفع، والفرق سُجل دائناً على الشركة.';
    }

    return receipt ? 'تم حفظ سند القبض.' : 'تم حفظ سند الدفع.';
  }

  IconData _iconForAccountType(
      FinancialAccountType type,
      ) {
    switch (type) {
      case FinancialAccountType.customerDebt:
        return Icons.person_outline_rounded;

      case FinancialAccountType.supplierPayable:
        return Icons.business_outlined;

      case FinancialAccountType.representativeCommission:
        return Icons.badge_outlined;
    }
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
      ),
    );
  }

  String _errorMessage(
      Object error,
      ) {
    return error
        .toString()
        .replaceFirst(
      'Bad state: ',
      '',
    )
        .replaceFirst(
      'Invalid argument(s): ',
      '',
    );
  }

  String _formatPrice(
      double value,
      ) {
    final text = value.toStringAsFixed(0);

    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) {
        buffer.write(',');
      }

      buffer.write(
        text[i],
      );
    }

    return '${buffer.toString()} د.ع';
  }

  String _formatDate(
      DateTime date,
      ) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(
      DateTime date,
      ) {
    final hour12 = date.hour > 12
        ? date.hour - 12
        : date.hour == 0
        ? 12
        : date.hour;

    final minute = date.minute.toString().padLeft(
      2,
      '0',
    );

    final period = date.hour >= 12 ? 'م' : 'ص';

    return '${_formatDate(date)} - $hour12:$minute $period';
  }
}

// =============================================================================
// ACCOUNTS TABLE HEADER
// =============================================================================

class _AccountsTableHeader extends StatelessWidget {
  const _AccountsTableHeader();

  static const style = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w500,
    color: AppTheme.secondaryTextColor,
  );

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      color: const Color(
        0xFFF8F8FA,
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'الحساب',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'النوع',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'الإجمالي',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'المدفوع',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'المتبقي',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'آخر دفعة',
              style: style,
            ),
          ),
          SizedBox(
            width: 50,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TRANSACTIONS TABLE HEADER
// =============================================================================

class _TransactionsTableHeader extends StatelessWidget {
  const _TransactionsTableHeader();

  static const style = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w500,
    color: AppTheme.secondaryTextColor,
  );

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      color: const Color(
        0xFFF8F8FA,
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'السند',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'الحساب',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'النوع',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الطريقة',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'المبلغ',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'التاريخ',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'المستخدم',
              style: style,
            ),
          ),
          SizedBox(width: 40),
        ],
      ),
    );
  }
}

// =============================================================================
// ACCOUNT TYPE BADGE
// =============================================================================

class _AccountTypeBadge extends StatelessWidget {
  final FinancialAccountType type;

  const _AccountTypeBadge({
    required this.type,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    late Color background;
    late Color foreground;

    switch (type) {
      case FinancialAccountType.customerDebt:
        background = const Color(
          0xFFEEF4FF,
        );
        foreground = const Color(
          0xFF3567C8,
        );
        break;

      case FinancialAccountType.supplierPayable:
        background = const Color(
          0xFFFFF4E5,
        );
        foreground = const Color(
          0xFFB26A00,
        );
        break;

      case FinancialAccountType.representativeCommission:
        background = const Color(
          0xFFF3EEFF,
        );
        foreground = const Color(
          0xFF7252B8,
        );
        break;
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(
            20,
          ),
        ),
        child: Text(
          type.title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TRANSACTION TYPE BADGE
// =============================================================================

class _FinanceTableBadge extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FinanceTableBadge({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppTheme.primaryTextColor;
    final badgeColor = selected ? Colors.white : AppTheme.primaryColor;
    final badgeText = selected ? AppTheme.primaryColor : Colors.white;

    return Material(
      color: selected ? AppTheme.primaryColor : const Color(0xFFF2F2F4),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 14,
            end: 8,
            top: 7,
            bottom: 7,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: badgeText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionTypeBadge extends StatelessWidget {
  final PaymentTransactionType type;

  const _TransactionTypeBadge({
    required this.type,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final receipt = type == PaymentTransactionType.receipt;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: receipt
              ? const Color(
            0xFFEAF7EE,
          )
              : const Color(
            0xFFFFECEC,
          ),
          borderRadius: BorderRadius.circular(
            20,
          ),
        ),
        child: Text(
          type.title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: receipt
                ? const Color(
              0xFF248A3D,
            )
                : const Color(
              0xFFC92A2A,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// BALANCE BADGE
// =============================================================================

class _BalanceBadge extends StatelessWidget {
  final double amount;
  final double amountUsd;

  const _BalanceBadge({
    required this.amount,
    this.amountUsd = 0,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final credit = amount < 0 || amountUsd < 0;
    final settled = amount == 0 && amountUsd == 0;
    final label = partyBalanceLabel(amount, amountUsd);
    final color = credit
        ? const Color(0xFF1D4ED8)
        : settled
            ? const Color(0xFF248A3D)
            : const Color(0xFFC92A2A);
    final background = credit
        ? const Color(0xFFE8F0FE)
        : settled
            ? const Color(0xFFEAF7EE)
            : const Color(0xFFFFECEC);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(
            20,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// STAT CARD
// =============================================================================

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final bool highlighted;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.highlighted = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 132,
      padding: const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(
          0xFF1D1D1F,
        )
            : Colors.white,
        borderRadius: BorderRadius.circular(
          17,
        ),
        border: highlighted
            ? null
            : Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: highlighted
                        ? const Color(
                      0xFFB8B8BD,
                    )
                        : AppTheme.secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: highlighted
                        ? Colors.white
                        : AppTheme.primaryTextColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: highlighted
                        ? const Color(
                      0xFF8E8E93,
                    )
                        : AppTheme.tertiaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: highlighted
                  ? Colors.white.withValues(
                alpha: 0.10,
              )
                  : const Color(
                0xFFF5F5F7,
              ),
              borderRadius: BorderRadius.circular(
                11,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: highlighted
                  ? Colors.white
                  : AppTheme.primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DIALOG FIELD
// =============================================================================

class _DialogField extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final bool numeric;

  const _DialogField({
    required this.title,
    required this.controller,
    this.numeric = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(
            decimal: true,
          )
              : TextInputType.text,
        ),
      ],
    );
  }
}