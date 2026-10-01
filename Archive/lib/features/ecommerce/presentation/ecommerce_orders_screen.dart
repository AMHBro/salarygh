import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/printing/print_preview.dart';
import '../../../core/theme/app_theme.dart';
import '../../representatives/data/rep_debt_ceiling.dart';
import '../data/cloud_store_orders.dart';
import '../models/ecommerce_order_model.dart';
import 'ecommerce_order_details_screen.dart';

class EcommerceOrdersScreen extends StatefulWidget {
  const EcommerceOrdersScreen({
    super.key,
  });

  @override
  State<EcommerceOrdersScreen> createState() =>
      _EcommerceOrdersScreenState();
}

class _EcommerceOrdersScreenState
    extends State<EcommerceOrdersScreen> {
  final TextEditingController _searchController =
  TextEditingController();

  Timer? _searchTimer;

  List<EcommerceOrderModel> _orders = const [];

  bool _loading = true;

  String? _error;

  List<String> _debtWarnings = const [];

  String? _status;
  String? _source;

  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  static const int _limit = 20;

  @override
  void initState() {
    super.initState();

    _loadOrders();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();

    super.dispose();
  }

  // ===========================================================================
  // LOAD
  // ===========================================================================

  Future<void> _loadOrders({
    bool resetPage = false,
  }) async {
    if (resetPage) {
      _page = 1;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final cloud = _filterCloud(
      await CloudStoreOrders(AppServices.database).pull(),
    );

    try {
      final result = await AppServices
          .ecommerceOrdersRepository
          .getOrders(
        page: _page,
        limit: _limit,
        status: _status,
        source: _source,
        search: _searchController.text,
      );

      if (!mounted) {
        return;
      }

      final seen = result.orders.map((order) => order.id).toSet();
      final extra = _page == 1
          ? cloud.where((order) => !seen.contains(order.id)).toList()
          : const <EcommerceOrderModel>[];

      final shown = [...extra, ...result.orders];
      final warnings = await _debtWarningsFor(shown);

      setState(() {
        _orders = shown;
        _debtWarnings = warnings;
        _page = result.page;
        _totalPages = result.totalPages;
        _total = result.total + extra.length;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final warnings = _page == 1 && cloud.isNotEmpty
          ? await _debtWarningsFor(cloud)
          : const <String>[];

      setState(() {
        if (_page == 1 && cloud.isNotEmpty) {
          _orders = cloud;
          _debtWarnings = warnings;
          _total = cloud.length;
          _totalPages = 1;
          _error = null;
        } else {
          _debtWarnings = const [];
          _error = _errorText(
            error,
          );
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<List<String>> _debtWarningsFor(
    List<EcommerceOrderModel> orders,
  ) {
    final names = <String>{
      for (final order in orders)
        if (order.isRepresentative &&
            (order.representative?.name.trim().isNotEmpty ?? false))
          order.representative!.name.trim(),
    };
    return RepDebtCeiling.messagesForNames(
      AppServices.database,
      names,
    );
  }

  List<EcommerceOrderModel> _filterCloud(
    List<EcommerceOrderModel> orders,
  ) {
    final query = _searchController.text.trim();
    return orders.where((order) {
      if (_status != null &&
          _status!.isNotEmpty &&
          order.status != _status) {
        return false;
      }
      if (_source != null &&
          _source!.isNotEmpty &&
          order.source != _source) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final haystack =
          '${order.orderNumber} ${order.customer?.name ?? ''} ${order.customer?.phone ?? ''} ${order.party?.name ?? ''}';
      return haystack.contains(query);
    }).toList();
  }

  void _onSearchChanged(
      String value,
      ) {
    _searchTimer?.cancel();

    _searchTimer = Timer(
      const Duration(
        milliseconds: 450,
      ),
          () {
        _loadOrders(
          resetPage: true,
        );
      },
    );
  }

  // ===========================================================================
  // DETAILS
  // ===========================================================================

  Future<void> _openOrder(
      EcommerceOrderModel order,
      ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EcommerceOrderDetailsScreen(
              initialOrder: order,
            ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadOrders();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  26,
                  0,
                  26,
                  24,
                ),
                child: Column(
                  children: [
                    _buildFilters(),
                    if (_debtWarnings.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final warning in _debtWarnings)
                        RepDebtBanner(message: warning),
                    ],
                    const SizedBox(height: 16),
                    Expanded(
                      child: _buildContent(),
                    ),
                    if (!_loading &&
                        _error == null &&
                        _totalPages > 1) ...[
                      const SizedBox(height: 14),
                      _buildPagination(),
                    ],
                  ],
                ),
              ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        28,
        26,
        28,
        20,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'طلبات المتجر',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'إدارة الطلبات الواردة من المتجر الإلكتروني',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.subtleBorderColor,
              ),
            ),
            child: Text(
              '$_total طلب',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'تحديث',
            onPressed:
            _loading ? null : () => _loadOrders(),
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FILTERS
  // ===========================================================================

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText:
                'بحث برقم الطلب أو اسم الزبون أو رقم الهاتف...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 20,
                ),
                suffixIcon:
                _searchController.text.isEmpty
                    ? null
                    : IconButton(
                  onPressed: () {
                    _searchController.clear();

                    setState(() {});

                    _loadOrders(
                      resetPage: true,
                    );
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                  ),
                ),
                filled: true,
                fillColor: const Color(
                  0xFFF8F8FA,
                ),
                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(11),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(11),
                  borderSide: const BorderSide(
                    color: AppTheme.subtleBorderColor,
                  ),
                ),
                contentPadding:
                const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String?>(
              initialValue: _status,
              decoration: _filterDecoration(
                'الحالة',
              ),
              items: const [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'جميع الحالات',
                  ),
                ),
                DropdownMenuItem<String?>(
                  value: 'SUBMITTED',
                  child: Text(
                    'بانتظار المعالجة',
                  ),
                ),
                DropdownMenuItem<String?>(
                  value: 'ACCEPTED',
                  child: Text(
                    'مقبول',
                  ),
                ),
                DropdownMenuItem<String?>(
                  value: 'REJECTED',
                  child: Text(
                    'مرفوض',
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _status = value;
                });

                _loadOrders(
                  resetPage: true,
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String?>(
              initialValue: _source,
              decoration: _filterDecoration(
                'المصدر',
              ),
              items: const [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'كل المصادر',
                  ),
                ),
                DropdownMenuItem<String?>(
                  value: 'GUEST',
                  child: Text(
                    'زبون متجر',
                  ),
                ),
                DropdownMenuItem<String?>(
                  value: 'REPRESENTATIVE',
                  child: Text(
                    'مندوب',
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _source = value;
                });

                _loadOrders(
                  resetPage: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _filterDecoration(
      String label,
      ) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF8F8FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 13,
      ),
    );
  }

  // ===========================================================================
  // CONTENT
  // ===========================================================================

  Widget _buildContent() {
    if (_loading && _orders.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 480,
          ),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: AppTheme.subtleBorderColor,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 38,
                color: AppTheme.secondaryTextColor,
              ),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadOrders,
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
                label: const Text(
                  'إعادة المحاولة',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_orders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 44,
              color: AppTheme.tertiaryTextColor,
            ),
            SizedBox(height: 12),
            Text(
              'لا توجد طلبات',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryTextColor,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'لم يتم العثور على طلبات مطابقة.',
              style: TextStyle(
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView.separated(
          itemCount: _orders.length,
          separatorBuilder: (_, __) =>
          const SizedBox(height: 10),
          itemBuilder: (
              context,
              index,
              ) {
            final order = _orders[index];

            return _OrderCard(
              order: order,
              onTap: () {
                _openOrder(
                  order,
                );
              },
              onPrint: () => _printOrder(order),
            );
          },
        ),
        if (_loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // PAGINATION
  // ===========================================================================

  Widget _buildPagination() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'السابق',
          onPressed: _page > 1
              ? () {
            setState(() {
              _page--;
            });

            _loadOrders();
          }
              : null,
          icon: const Icon(
            Icons.chevron_right_rounded,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.subtleBorderColor,
            ),
          ),
          child: Text(
            '$_page / $_totalPages',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip: 'التالي',
          onPressed: _page < _totalPages
              ? () {
            setState(() {
              _page++;
            });

            _loadOrders();
          }
              : null,
          icon: const Icon(
            Icons.chevron_left_rounded,
          ),
        ),
      ],
    );
  }

  Future<void> _printOrder(EcommerceOrderModel order) async {
    try {
      final full = order.items.isEmpty
          ? await AppServices.ecommerceOrdersRepository.getOrder(order.id)
          : order;
      if (!mounted) return;
      await showPrintPreview(context, storeOrderDocument(full));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(error))),
      );
    }
  }

  String _errorText(
      Object error,
      ) {
    return error
        .toString()
        .replaceFirst(
      'Bad state: ',
      '',
    )
        .replaceFirst(
      'Exception: ',
      '',
    );
  }
}

// =============================================================================
// ORDER CARD
// =============================================================================

class _OrderCard extends StatelessWidget {
  final EcommerceOrderModel order;
  final VoidCallback onTap;
  final VoidCallback onPrint;

  const _OrderCard({
    required this.order,
    required this.onTap,
    required this.onPrint,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Material(
      color: AppTheme.surfaceColor,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: AppTheme.subtleBorderColor,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  order.isRepresentative
                      ? Icons.badge_outlined
                      : Icons.shopping_bag_outlined,
                  size: 20,
                  color: AppTheme.primaryTextColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      order.orderNumber,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      order.partyDisplayName,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _SmallColumn(
                  title: 'المصدر',
                  value: order.sourceDisplayName,
                ),
              ),
              Expanded(
                child: _SmallColumn(
                  title: 'الدفع',
                  value: order.paymentTypeDisplayName,
                ),
              ),
              Expanded(
                child: _SmallColumn(
                  title: 'الإجمالي',
                  value: _money(
                    order.total,
                  ),
                  bold: true,
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _OrderStatusChip(
                    order: order,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'طباعة الطلب',
                onPressed: onPrint,
                icon: const Icon(Icons.print_outlined, size: 18),
              ),
              const Icon(
                Icons.chevron_left_rounded,
                color: AppTheme.tertiaryTextColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallColumn extends StatelessWidget {
  final String title;
  final String value;
  final bool bold;

  const _SmallColumn({
    required this.title,
    required this.value,
    this.bold = false,
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
          style: const TextStyle(
            fontSize: 10.5,
            color: AppTheme.tertiaryTextColor,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight:
            bold ? FontWeight.w700 : FontWeight.w500,
            color: AppTheme.primaryTextColor,
          ),
        ),
      ],
    );
  }
}

class _OrderStatusChip extends StatelessWidget {
  final EcommerceOrderModel order;

  const _OrderStatusChip({
    required this.order,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    Color background;
    Color foreground;

    switch (order.status.toUpperCase()) {
      case 'ACCEPTED':
        background = const Color(0xFFEAF7EF);
        foreground = const Color(0xFF217A45);
        break;

      case 'REJECTED':
      case 'CANCELLED':
        background = const Color(0xFFFDEEEE);
        foreground = AppTheme.dangerColor;
        break;

      default:
        background = const Color(0xFFFFF5DF);
        foreground = const Color(0xFF9B6B00);
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        order.statusDisplayName,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

String _money(
    double value,
    ) {
  final integer =
      value == value.roundToDouble();

  final text = integer
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  final parts = text.split('.');

  final digits = parts.first;

  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    final position = digits.length - i;

    buffer.write(
      digits[i],
    );

    if (position > 1 &&
        (position - 1) % 3 == 0) {
      buffer.write(',');
    }
  }

  if (parts.length > 1) {
    buffer
      ..write('.')
      ..write(parts[1]);
  }

  return '${buffer.toString()} د.ع';
}