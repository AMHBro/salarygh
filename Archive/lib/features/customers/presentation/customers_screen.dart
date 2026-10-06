import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/money/party_balance.dart';
import '../../../core/theme/app_theme.dart';
import '../../representatives/models/representative_model.dart';
import '../models/customer_model.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({
    super.key,
  });

  @override
  State<CustomersScreen> createState() =>
      _CustomersScreenState();
}

class _CustomersScreenState
    extends State<CustomersScreen> {
  final _repository =
      AppServices.customersRepository;

  final TextEditingController
  _searchController =
  TextEditingController();

  List<CustomerModel> _customers = [];
  List<RepresentativeModel> _representatives = [];
  int _customerTotal = 0;
  int _customerPage = 1;
  ({int count, double purchases, double balance, int withDebt})? _stats;

  String _selectedFilter = 'الكل';

  bool _isLoading = true;
  bool _paging = false;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_onSearchChanged);

    _loadCustomers();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);

    _searchController.dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      _loadCustomers();
    });
  }

  Future<void> _loadCustomers({int? page}) async {
    final nextPage = page ?? 1;
    if (mounted) {
      setState(() {
        _paging = true;
        if (_customers.isEmpty) {
          _isLoading = true;
        }
      });
    }

    try {
      final query = _searchController.text.trim();
      if (query.isNotEmpty) {
        try {
          await AppServices.customersSyncRemoteGateway.importSearch(query);
        } catch (_) {}
      }
      final result = await _repository.pageCustomers(
        offset: (nextPage - 1) * kListPageSize,
        search: _searchController.text,
        filter: _selectedFilter,
      );
      final stats = page == null ? await _repository.customerDirectoryStats() : _stats;
      final customers = result.items;
      List<RepresentativeModel> representatives = [];
      try {
        representatives = await AppServices
            .representativesRepository
            .getRepresentatives();
      } catch (_) {}

      if (!mounted) {
        return;
      }

      setState(() {
        _customers = customers;
        _customerPage = nextPage;
        _customerTotal = result.total;
        _stats = stats ?? _stats;
        _representatives = representatives
            .where((item) => item.deletedAt == null)
            .toList();

        _isLoading = false;
        _paging = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _paging = false;
      });

      _showMessage(
        _errorMessage(error),
      );
    }
  }

  double get _totalPurchases => _stats?.purchases ?? 0;

  double get _totalBalance => _stats?.balance ?? 0;

  int get _customersWithDebt => _stats?.withDebt ?? 0;

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      AppTheme.backgroundColor,
      body: _isLoading
          ? const Center(
        child:
        CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: _loadCustomers,
        child: SingleChildScrollView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          padding:
          const EdgeInsets.fromLTRB(
            34,
            30,
            34,
            34,
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(
                height: 28,
              ),
              _buildStats(),
              const SizedBox(
                height: 22,
              ),
              _buildFilters(),
              const SizedBox(
                height: 18,
              ),
              _buildCustomersTable(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'الزبائن',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight:
                  FontWeight.w700,
                  letterSpacing: -0.6,
                  color: AppTheme
                      .primaryTextColor,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'إدارة الزبائن والمشتريات والذمم والحسابات.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme
                      .secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _loadCustomers,
          icon: const Icon(
            Icons.refresh_rounded,
            size: 18,
          ),
          label: const Text(
            'تحديث',
          ),
        ),
        const SizedBox(
          width: 10,
        ),
        ElevatedButton.icon(
          onPressed:
          _showAddCustomerDialog,
          icon: const Icon(
            Icons.add_rounded,
            size: 18,
          ),
          label: const Text(
            'إضافة زبون',
          ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: 'عدد الزبائن',
            value:
            '${_stats?.count ?? _customerTotal}',
            subtitle: 'زبون مسجل',
            icon: Icons
                .people_outline_rounded,
            highlighted: true,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title: 'إجمالي المبيعات',
            value: _formatPrice(
              _totalPurchases,
            ),
            subtitle:
            'إجمالي مشتريات الزبائن',
            icon:
            Icons.trending_up_rounded,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title: 'إجمالي الديون',
            value: _formatPrice(
              _totalBalance,
            ),
            subtitle:
            'مبالغ غير مسددة',
            icon: Icons
                .account_balance_wallet_outlined,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title:
            'زبائن عليهم رصيد',
            value:
            '$_customersWithDebt',
            subtitle:
            'حساب غير مسدد',
            icon:
            Icons.schedule_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      padding:
      const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(18),
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
              const InputDecoration(
                hintText:
                'ابحث باسم الزبون أو رقم الهاتف',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 19,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child:
            DropdownButtonFormField<
                String>(
              key: ValueKey(_selectedFilter),
              initialValue: _selectedFilter,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: 'الكل',
                  child: Text(
                    'كل الزبائن',
                  ),
                ),
                DropdownMenuItem(
                  value: 'عليه رصيد',
                  child: Text(
                    'عليه رصيد',
                  ),
                ),
                DropdownMenuItem(
                  value: 'مسدد',
                  child: Text(
                    'مسدد بالكامل',
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _selectedFilter =
                      value;
                });
                _loadCustomers();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomersTable() {
    final customers = _customers;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(18),
        border: Border.all(
          color:
          AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding:
            const EdgeInsets.all(20),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Text(
                        'قائمة الزبائن',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                          FontWeight
                              .w600,
                          color: AppTheme
                              .primaryTextColor,
                        ),
                      ),
                      SizedBox(
                        height: 4,
                      ),
                      Text(
                        'تفاصيل الحساب والمبيعات لكل زبون.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme
                              .secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$_customerTotal زبون',
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
          const _CustomersTableHeader(),
          if (customers.isEmpty)
            const Padding(
              padding:
              EdgeInsets.symmetric(
                vertical: 60,
              ),
              child: Column(
                children: [
                  Icon(
                    Icons
                        .people_outline_rounded,
                    size: 38,
                    color: AppTheme
                        .tertiaryTextColor,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'لا توجد نتائج مطابقة',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            ...customers.map(
              _buildCustomerRow,
            ),
          ListPagination(
            page: _customerPage,
            totalItems: _customerTotal,
            loading: _paging,
            onPageChanged: (page) => _loadCustomers(page: page),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerRow(
      CustomerModel customer,
      ) {
    return Container(
      height: 76,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 18,
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
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration:
                  BoxDecoration(
                    color: const Color(
                      0xFFF5F5F7,
                    ),
                    borderRadius:
                    BorderRadius
                        .circular(
                      11,
                    ),
                  ),
                  child: const Icon(
                    Icons
                        .person_outline_rounded,
                    size: 19,
                    color: AppTheme
                        .primaryTextColor,
                  ),
                ),
                const SizedBox(
                  width: 11,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment:
                    MainAxisAlignment
                        .center,
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Text(
                        customer.name,
                        overflow:
                        TextOverflow
                            .ellipsis,
                        style:
                        const TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                          FontWeight
                              .w600,
                          color: AppTheme
                              .primaryTextColor,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        _customerSubtitle(
                          customer,
                        ),
                        style:
                        const TextStyle(
                          fontSize: 10.5,
                          color: AppTheme
                              .secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              customer.address
                  .trim()
                  .isEmpty
                  ? '-'
                  : customer.address,
              overflow:
              TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme
                    .secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${customer.invoicesCount}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight:
                FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatPrice(
                customer
                    .totalPurchases,
              ),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight:
                FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatPrice(
                customer.totalPaid,
              ),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme
                    .secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _BalanceBadge(
              balance:
              customer.balance,
              balanceUsd: customer.balanceUsd,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              customer.lastPurchaseDate ==
                  null
                  ? '-'
                  : _formatDate(
                customer
                    .lastPurchaseDate!,
              ),
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme
                    .secondaryTextColor,
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child:
            PopupMenuButton<String>(
              tooltip: 'خيارات',
              icon: const Icon(
                Icons
                    .more_horiz_rounded,
                size: 19,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'details':
                    _showCustomerDetails(
                      customer,
                    );
                    break;

                  case 'edit':
                    _showEditCustomerDialog(
                      customer,
                    );
                    break;

                  case 'payment':
                    _showPaymentDialog(
                      customer,
                    );
                    break;
                }
              },
              itemBuilder: (context) {
                return const [
                  PopupMenuItem(
                    value: 'details',
                    child: Row(
                      children: [
                        Icon(
                          Icons
                              .visibility_outlined,
                          size: 17,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Text(
                          'عرض التفاصيل',
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'payment',
                    child: Row(
                      children: [
                        Icon(
                          Icons
                              .payments_outlined,
                          size: 17,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Text(
                          'تسجيل دفعة',
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(
                          Icons
                              .edit_outlined,
                          size: 17,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Text(
                          'تعديل',
                        ),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ),
        ],
      ),
    );
  }

  String _customerSubtitle(CustomerModel customer) {
    final parts = <String>[
      customer.phone.trim().isEmpty ? 'بدون رقم هاتف' : customer.phone,
    ];
    if (customer.groupName.trim().isNotEmpty) {
      parts.add(customer.groupName.trim());
    }
    final representativeName = _representativeName(customer.representativeId);
    if (representativeName != null) {
      parts.add(representativeName);
    }
    return parts.join(' · ');
  }

  String? _representativeName(String? id) {
    if (id == null || id.trim().isEmpty) {
      return null;
    }
    for (final representative in _representatives) {
      if (representative.id == id) {
        return representative.name;
      }
    }
    return null;
  }

  void _showAddCustomerDialog() {
    _showCustomerDialog();
  }

  void _showEditCustomerDialog(
      CustomerModel customer,
      ) {
    _showCustomerDialog(
      customer: customer,
    );
  }

  void _showCustomerDialog({
    CustomerModel? customer,
  }) {
    final nameController =
    TextEditingController(
      text: customer?.name ?? '',
    );

    final phoneController =
    TextEditingController(
      text: customer?.phone ?? '',
    );

    final addressController =
    TextEditingController(
      text: customer?.address ?? '',
    );

    final notesController =
    TextEditingController(
      text: customer?.notes ?? '',
    );

    final groupController =
    TextEditingController(
      text: customer?.groupName ?? '',
    );

    String? selectedRepresentativeId =
        customer?.representativeId;

    final knownGroups = _customers
        .map((item) => item.groupName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    bool isSaving = false;

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
              textDirection:
              TextDirection.rtl,
              child: AlertDialog(
                title: Text(
                  customer == null
                      ? 'إضافة زبون جديد'
                      : 'تعديل بيانات الزبون',
                ),
                content: SizedBox(
                  width: 580,
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    children: [
                      _DialogField(
                        title:
                        'اسم الزبون',
                        controller:
                        nameController,
                        hint:
                        'الاسم الكامل أو اسم الشركة',
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child:
                            _DialogField(
                              title:
                              'رقم الهاتف',
                              controller:
                              phoneController,
                              hint:
                              '07xxxxxxxxx',
                            ),
                          ),
                          const SizedBox(
                            width: 12,
                          ),
                          Expanded(
                            child:
                            _DialogField(
                              title:
                              'العنوان',
                              controller:
                              addressController,
                              hint:
                              'بغداد - ...',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      _DialogField(
                        title: 'العائلة أو التصنيف',
                        controller: groupController,
                        hint: 'مثال: عائلة أبو محمد',
                      ),
                      if (knownGroups.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final group in knownGroups)
                                ActionChip(
                                  label: Text(group),
                                  onPressed: () {
                                    setDialogState(() {
                                      groupController.text = group;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        key: ValueKey(selectedRepresentativeId ?? ''),
                        initialValue: selectedRepresentativeId ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'المندوب',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('بدون مندوب'),
                          ),
                          for (final representative in _representatives)
                            DropdownMenuItem(
                              value: representative.id,
                              child: Text(representative.name),
                            ),
                        ],
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setDialogState(() {
                                  selectedRepresentativeId =
                                      value == null || value.isEmpty
                                          ? null
                                          : value;
                                });
                              },
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      _DialogField(
                        title: 'ملاحظات',
                        controller:
                        notesController,
                        hint:
                        'ملاحظات اختيارية',
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                    isSaving
                        ? null
                        : () {
                      Navigator.pop(
                        dialogContext,
                      );
                    },
                    child:
                    const Text(
                      'إلغاء',
                    ),
                  ),
                  ElevatedButton(
                    onPressed:
                    isSaving
                        ? null
                        : () async {
                      final name =
                      nameController
                          .text
                          .trim();

                      if (name
                          .isEmpty) {
                        _showMessage(
                          'اسم الزبون مطلوب.',
                        );

                        return;
                      }

                      setDialogState(
                            () {
                          isSaving =
                          true;
                        },
                      );

                      try {
                        if (customer ==
                            null) {
                          await _repository
                              .createCustomer(
                            name:
                            name,
                            phone:
                            phoneController
                                .text,
                            address:
                            addressController
                                .text,
                            notes:
                            notesController
                                .text,
                            groupName:
                            groupController.text,
                            representativeId:
                            selectedRepresentativeId,
                          );
                        } else {
                          await _repository
                              .updateCustomer(
                            customer,
                            name:
                            name,
                            phone:
                            phoneController
                                .text,
                            address:
                            addressController
                                .text,
                            notes:
                            notesController
                                .text,
                            groupName:
                            groupController.text,
                            representativeId:
                            selectedRepresentativeId,
                          );
                        }

                        if (!dialogContext.mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                        );

                        await _loadCustomers();

                        _showMessage(
                          customer ==
                              null
                              ? 'تمت إضافة الزبون.'
                              : 'تم حفظ التعديلات.',
                        );
                      } catch (error) {
                        if (!mounted) {
                          return;
                        }

                        setDialogState(
                              () {
                            isSaving =
                            false;
                          },
                        );

                        _showMessage(
                          _errorMessage(
                            error,
                          ),
                        );
                      }
                    },
                    child: isSaving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                      CircularProgressIndicator(
                        strokeWidth:
                        2,
                        color:
                        Colors.white,
                      ),
                    )
                        : Text(
                      customer ==
                          null
                          ? 'إضافة الزبون'
                          : 'حفظ التعديلات',
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

  void _showCustomerDetails(
      CustomerModel customer,
      ) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection:
          TextDirection.rtl,
          child: Dialog(
            child: Container(
              width: 620,
              padding:
              const EdgeInsets.all(
                24,
              ),
              child: Column(
                mainAxisSize:
                MainAxisSize.min,
                crossAxisAlignment:
                CrossAxisAlignment
                    .start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration:
                        const BoxDecoration(
                          color: AppTheme
                              .primaryColor,
                          shape:
                          BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons
                              .person_rounded,
                          color:
                          Colors.white,
                        ),
                      ),
                      const SizedBox(
                        width: 14,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                          children: [
                            Text(
                              customer.name,
                              style:
                              const TextStyle(
                                fontSize: 20,
                                fontWeight:
                                FontWeight
                                    .w700,
                              ),
                            ),
                            const SizedBox(
                              height: 4,
                            ),
                            Text(
                              customer.phone
                                  .trim()
                                  .isEmpty
                                  ? 'بدون رقم هاتف'
                                  : customer
                                  .phone,
                              style:
                              const TextStyle(
                                fontSize: 12,
                                color: AppTheme
                                    .secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(
                            context,
                          );
                        },
                        icon: const Icon(
                          Icons
                              .close_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _DetailCard(
                          title:
                          'إجمالي المشتريات',
                          value:
                          _formatPrice(
                            customer
                                .totalPurchases,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      Expanded(
                        child: _DetailCard(
                          title:
                          'إجمالي المدفوع',
                          value:
                          _formatPrice(
                            customer
                                .totalPaid,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      Expanded(
                        child: _DetailCard(
                          title:
                          'الرصيد المتبقي',
                          value:
                          partyBalanceLabel(
                            customer.balance,
                            customer.balanceUsd,
                          ),
                          danger:
                          customer
                              .balance >
                              0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  _InfoRow(
                    title: 'العنوان',
                    value: customer.address
                        .trim()
                        .isEmpty
                        ? '-'
                        : customer.address,
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  _InfoRow(
                    title:
                    'عدد الفواتير',
                    value:
                    '${customer.invoicesCount} فاتورة',
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  _InfoRow(
                    title:
                    'آخر عملية شراء',
                    value: customer
                        .lastPurchaseDate ==
                        null
                        ? '-'
                        : _formatDate(
                      customer
                          .lastPurchaseDate!,
                    ),
                  ),
                  if ((customer.notes ??
                      '')
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(
                      height: 12,
                    ),
                    _InfoRow(
                      title: 'ملاحظات',
                      value:
                      customer.notes!,
                    ),
                  ],
                  const SizedBox(
                    height: 24,
                  ),
                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(
                          Icons
                              .folder_outlined,
                          size: 17,
                        ),
                        label:
                        const Text(
                          'الأرشيف',
                        ),
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      ElevatedButton.icon(
                        onPressed:
                        customer.balance <= 0 &&
                                customer.balanceUsd <= 0
                            ? null
                            : () {
                          Navigator.pop(
                            context,
                          );

                          _showPaymentDialog(
                            customer,
                          );
                        },
                        icon: const Icon(
                          Icons
                              .payments_outlined,
                          size: 17,
                        ),
                        label:
                        const Text(
                          'تسجيل دفعة',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPaymentDialog(
      CustomerModel customer,
      ) {
    final amountController =
    TextEditingController();

    final noteController =
    TextEditingController();

    String method = 'CASH';
    var currency = 'IQD';
    bool isSaving = false;

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
              textDirection:
              TextDirection.rtl,
              child: AlertDialog(
                title: const Text(
                  'تسجيل دفعة',
                ),
                content: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Container(
                        width:
                        double.infinity,
                        padding:
                        const EdgeInsets
                            .all(
                          16,
                        ),
                        decoration:
                        BoxDecoration(
                          color:
                          const Color(
                            0xFFF5F5F7,
                          ),
                          borderRadius:
                          BorderRadius
                              .circular(
                            14,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'الرصيد المستحق',
                                style:
                                TextStyle(
                                  color: AppTheme
                                      .secondaryTextColor,
                                ),
                              ),
                            ),
                            Text(
                              partyBalanceLabel(
                                customer.balance,
                                customer.balanceUsd,
                              ),
                              style:
                              const TextStyle(
                                fontSize: 17,
                                fontWeight:
                                FontWeight
                                    .w700,
                                color: AppTheme
                                    .dangerColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        height: 18,
                      ),
                      _DialogField(
                        title:
                        'المبلغ المدفوع',
                        controller:
                        amountController,
                        hint: '0',
                        numeric: true,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: currency,
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
                          if (value == null) return;
                          setDialogState(() {
                            currency = value;
                          });
                        },
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      const Text(
                        'طريقة الدفع',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                          FontWeight
                              .w500,
                          color: AppTheme
                              .secondaryTextColor,
                        ),
                      ),
                      const SizedBox(
                        height: 7,
                      ),
                      DropdownButtonFormField<
                          String>(
                        key: ValueKey(method),
                        initialValue: method,
                        items: const [
                          DropdownMenuItem(
                            value: 'CASH',
                            child: Text(
                              'نقدي',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'BANK',
                            child: Text(
                              'تحويل',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'OTHER',
                            child: Text(
                              'أخرى',
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value ==
                              null) {
                            return;
                          }

                          setDialogState(
                                () {
                              method =
                                  value;
                            },
                          );
                        },
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      _DialogField(
                        title: 'ملاحظة',
                        controller:
                        noteController,
                        hint:
                        'ملاحظة اختيارية',
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                    isSaving
                        ? null
                        : () {
                      Navigator.pop(
                        dialogContext,
                      );
                    },
                    child:
                    const Text(
                      'إلغاء',
                    ),
                  ),
                  ElevatedButton(
                    onPressed:
                    isSaving
                        ? null
                        : () async {
                      final amount =
                          double.tryParse(
                            amountController
                                .text
                                .trim()
                                .replaceAll(
                              ',',
                              '',
                            ),
                          ) ??
                              0;

                      if (amount <=
                          0) {
                        _showMessage(
                          'أدخل مبلغاً صحيحاً.',
                        );

                        return;
                      }

                      final due = currency == 'USD'
                          ? customer.balanceUsd
                          : customer.balance;

                      if (amount >
                          due) {
                        _showMessage(
                          'المبلغ أكبر من الرصيد المستحق.',
                        );

                        return;
                      }

                      setDialogState(
                            () {
                          isSaving =
                          true;
                        },
                      );

                      try {
                        await _repository
                            .registerReceipt(
                          customerId:
                          customer
                              .id,
                          amount:
                          amount,
                          method:
                          method,
                          currency: currency,
                          note:
                          noteController
                              .text,
                        );

                        if (!dialogContext.mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                        );

                        await _loadCustomers();

                        _showMessage(
                          'تم تسجيل سند القبض بنجاح.',
                        );
                      } catch (error) {
                        if (!mounted) {
                          return;
                        }

                        setDialogState(
                              () {
                            isSaving =
                            false;
                          },
                        );

                        _showMessage(
                          _errorMessage(
                            error,
                          ),
                        );
                      }
                    },
                    child: isSaving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                      CircularProgressIndicator(
                        strokeWidth:
                        2,
                        color:
                        Colors.white,
                      ),
                    )
                        : const Text(
                      'تسجيل الدفعة',
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

  void _showMessage(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
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
    final text =
    value.toStringAsFixed(0);

    final buffer =
    StringBuffer();

    for (int i = 0;
    i < text.length;
    i++) {
      if (i > 0 &&
          (text.length - i) % 3 ==
              0) {
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
}

class _CustomersTableHeader
    extends StatelessWidget {
  const _CustomersTableHeader();

  static const style = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w500,
    color:
    AppTheme.secondaryTextColor,
  );

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 42,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      color:
      const Color(0xFFF8F8FA),
      child: const Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'الزبون',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'العنوان',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الفواتير',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'المشتريات',
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
              'الرصيد',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'آخر شراء',
              style: style,
            ),
          ),
          SizedBox(width: 50),
        ],
      ),
    );
  }
}

class _BalanceBadge
    extends StatelessWidget {
  final double balance;
  final double balanceUsd;

  const _BalanceBadge({
    required this.balance,
    this.balanceUsd = 0,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final hasDebt =
        balance > 0 || balanceUsd > 0;
    final hasCredit =
        balance < 0 || balanceUsd < 0;

    return Align(
      alignment:
      Alignment.centerRight,
      child: Container(
        padding:
        const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: hasDebt
              ? const Color(
            0xFFFFECEC,
          )
              : hasCredit
              ? const Color(
            0xFFE8F0FE,
          )
              : const Color(
            0xFFEAF7EE,
          ),
          borderRadius:
          BorderRadius.circular(
            20,
          ),
        ),
        child: Text(
          partyBalanceLabel(balance, balanceUsd),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight:
            FontWeight.w600,
            color: hasDebt
                ? const Color(
              0xFFC92A2A,
            )
                : hasCredit
                ? const Color(
              0xFF1D4ED8,
            )
                : const Color(
              0xFF248A3D,
            ),
          ),
        ),
      ),
    );
  }

}

class _StatCard
    extends StatelessWidget {
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
      padding:
      const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(
          0xFF1D1D1F,
        )
            : Colors.white,
        borderRadius:
        BorderRadius.circular(
          17,
        ),
        border: highlighted
            ? null
            : Border.all(
          color: AppTheme
              .subtleBorderColor,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment
                  .center,
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: highlighted
                        ? const Color(
                      0xFFB8B8BD,
                    )
                        : AppTheme
                        .secondaryTextColor,
                  ),
                ),
                const SizedBox(
                  height: 7,
                ),
                Text(
                  value,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight:
                    FontWeight
                        .w700,
                    color: highlighted
                        ? Colors.white
                        : AppTheme
                        .primaryTextColor,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: highlighted
                        ? const Color(
                      0xFF8E8E93,
                    )
                        : AppTheme
                        .tertiaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration:
            BoxDecoration(
              color: highlighted
                  ? Colors.white
                  .withValues(
                alpha: 0.10,
              )
                  : const Color(
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
              color: highlighted
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

class _DialogField
    extends StatelessWidget {
  final String title;
  final TextEditingController
  controller;
  final String hint;
  final bool numeric;

  const _DialogField({
    required this.title,
    required this.controller,
    required this.hint,
    this.numeric = false,
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
            fontSize: 11.5,
            fontWeight:
            FontWeight.w500,
            color: AppTheme
                .secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 7,
        ),
        TextField(
          controller: controller,
          keyboardType: numeric
              ? const TextInputType
              .numberWithOptions(
            decimal: true,
          )
              : TextInputType.text,
          decoration:
          InputDecoration(
            hintText: hint,
          ),
        ),
      ],
    );
  }
}

class _DetailCard
    extends StatelessWidget {
  final String title;
  final String value;
  final bool danger;

  const _DetailCard({
    required this.title,
    required this.value,
    this.danger = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 94,
      padding:
      const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
        const Color(0xFFF8F8FA),
        borderRadius:
        BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color:
          AppTheme.subtleBorderColor,
        ),
      ),
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
              fontSize: 10.5,
              color: AppTheme
                  .secondaryTextColor,
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            value,
            overflow:
            TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight:
              FontWeight.w700,
              color: danger
                  ? AppTheme
                  .dangerColor
                  : AppTheme
                  .primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow
    extends StatelessWidget {
  final String title;
  final String value;

  const _InfoRow({
    required this.title,
    required this.value,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            title,
            style:
            const TextStyle(
              fontSize: 11.5,
              color: AppTheme
                  .secondaryTextColor,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style:
            const TextStyle(
              fontSize: 12.5,
              fontWeight:
              FontWeight.w500,
              color: AppTheme
                  .primaryTextColor,
            ),
          ),
        ),
      ],
    );
  }
}