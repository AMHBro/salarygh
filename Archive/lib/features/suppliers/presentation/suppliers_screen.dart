import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/money/party_balance.dart';
import '../../../core/theme/app_theme.dart';
import '../models/supplier_model.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({
    super.key,
  });

  @override
  State<SuppliersScreen> createState() =>
      _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _repository =
      AppServices.suppliersRepository;

  final TextEditingController _searchController =
  TextEditingController();

  List<SupplierModel> _suppliers = [];
  int _supplierTotal = 0;
  int _supplierPage = 1;
  ({int count, double purchases, double balance, int withBalance})? _stats;

  bool _isLoading = true;
  bool _paging = false;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_onSearchChanged);

    _loadSuppliers();
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
      _loadSuppliers();
    });
  }

  Future<void> _loadSuppliers({int? page}) async {
    final nextPage = page ?? 1;
    if (mounted) {
      setState(() {
        _paging = true;
        if (_suppliers.isEmpty) {
          _isLoading = true;
        }
      });
    }

    try {
      final result = await _repository.pageSuppliers(
        offset: (nextPage - 1) * kListPageSize,
        search: _searchController.text,
      );
      final stats = page == null ? await _repository.supplierDirectoryStats() : _stats;
      final suppliers = result.items;

      if (!mounted) {
        return;
      }

      setState(() {
        _suppliers = suppliers;
        _supplierPage = nextPage;
        _supplierTotal = result.total;
        _stats = stats ?? _stats;
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

  int get _suppliersWithBalance => _stats?.withBalance ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
      AppTheme.backgroundColor,
      body: _isLoading
          ? const Center(
        child:
        CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: _loadSuppliers,
        child:
        SingleChildScrollView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          padding:
          const EdgeInsets
              .fromLTRB(
            34,
            30,
            34,
            34,
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment
                .start,
            children: [
              _buildHeader(),
              const SizedBox(
                height: 28,
              ),
              _buildStats(),
              const SizedBox(
                height: 22,
              ),
              _buildSearch(),
              const SizedBox(
                height: 18,
              ),
              _buildTable(),
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
                'الموردون',
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
                'إدارة الشركات الموردة والحسابات والفواتير.',
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
          onPressed: _loadSuppliers,
          icon: const Icon(
            Icons.refresh_rounded,
            size: 18,
          ),
          label: const Text(
            'تحديث',
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed:
          _showAddSupplierDialog,
          icon: const Icon(
            Icons.add_rounded,
            size: 18,
          ),
          label: const Text(
            'إضافة مورد',
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
            title: 'عدد الموردين',
            value:
            '${_stats?.count ?? _supplierTotal}',
            icon:
            Icons.business_outlined,
            highlighted: true,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title:
            'إجمالي المشتريات',
            value: _formatPrice(
              _totalPurchases,
            ),
            icon: Icons
                .shopping_bag_outlined,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title:
            'المبالغ المستحقة',
            value: _formatPrice(
              _totalBalance,
            ),
            icon: Icons
                .account_balance_wallet_outlined,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title:
            'موردون عليهم مستحق',
            value:
            '$_suppliersWithBalance',
            icon:
            Icons.schedule_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildSearch() {
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
      child: TextField(
        controller:
        _searchController,
        decoration:
        const InputDecoration(
          hintText:
          'ابحث باسم المورد أو رقم الهاتف أو العنوان',
          prefixIcon: Icon(
            Icons.search_rounded,
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
    final suppliers = _suppliers;

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
            const EdgeInsets.all(
              20,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'قائمة الموردين',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                      FontWeight
                          .w600,
                      color: AppTheme
                          .primaryTextColor,
                    ),
                  ),
                ),
                Text(
                  '$_supplierTotal مورد',
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
          const _SupplierTableHeader(),
          if (suppliers.isEmpty)
            const Padding(
              padding:
              EdgeInsets.symmetric(
                vertical: 55,
              ),
              child: Text(
                'لا يوجد موردون.',
                style: TextStyle(
                  color: AppTheme
                      .secondaryTextColor,
                ),
              ),
            )
          else
            ...suppliers.map(
              _buildSupplierRow,
            ),
          ListPagination(
            page: _supplierPage,
            totalItems: _supplierTotal,
            loading: _paging,
            onPageChanged: (page) => _loadSuppliers(page: page),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierRow(
      SupplierModel supplier,
      ) {
    return Container(
      height: 72,
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
                  width: 38,
                  height: 38,
                  decoration:
                  BoxDecoration(
                    color: const Color(
                      0xFFF5F5F7,
                    ),
                    borderRadius:
                    BorderRadius
                        .circular(
                      10,
                    ),
                  ),
                  child: const Icon(
                    Icons
                        .business_outlined,
                    size: 18,
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
                        supplier.name,
                        overflow:
                        TextOverflow
                            .ellipsis,
                        style:
                        const TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                          FontWeight
                              .w600,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        supplier.phone
                            .trim()
                            .isEmpty
                            ? 'بدون رقم هاتف'
                            : supplier
                            .phone,
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
              supplier.address
                  .trim()
                  .isEmpty
                  ? '-'
                  : supplier.address,
              overflow:
              TextOverflow.ellipsis,
              style:
              const TextStyle(
                fontSize: 11.5,
                color: AppTheme
                    .secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${supplier.invoicesCount}',
              style:
              const TextStyle(
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatPrice(
                supplier
                    .totalPurchases,
              ),
              style:
              const TextStyle(
                fontSize: 11.5,
                fontWeight:
                FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _BalanceBadge(
              amount:
              supplier.balance,
              amountUsd: supplier.balanceUsd,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              supplier.lastPurchaseDate ==
                  null
                  ? '-'
                  : _formatDate(
                supplier
                    .lastPurchaseDate!,
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
            width: 50,
            child:
            PopupMenuButton<String>(
              icon: const Icon(
                Icons
                    .more_horiz_rounded,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'details':
                    _showSupplierDetails(
                      supplier,
                    );
                    break;

                  case 'edit':
                    _showEditSupplierDialog(
                      supplier,
                    );
                    break;

                  case 'payment':
                    _showPaymentDialog(
                      supplier,
                    );
                    break;
                }
              },
              itemBuilder: (context) {
                return [
                  const PopupMenuItem(
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
                  const PopupMenuItem(
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
                  if (supplier.balance > 0 ||
                      supplier.balanceUsd > 0)
                    const PopupMenuItem(
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
                ];
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddSupplierDialog() {
    _showSupplierFormDialog();
  }

  void _showEditSupplierDialog(
      SupplierModel supplier,
      ) {
    _showSupplierFormDialog(
      supplier: supplier,
    );
  }

  void _showSupplierFormDialog({
    SupplierModel? supplier,
  }) {
    final nameController =
    TextEditingController(
      text: supplier?.name ?? '',
    );

    final phoneController =
    TextEditingController(
      text: supplier?.phone ?? '',
    );

    final addressController =
    TextEditingController(
      text: supplier?.address ?? '',
    );

    final notesController =
    TextEditingController(
      text: supplier?.notes ?? '',
    );

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
              textDirection:
              TextDirection.rtl,
              child: AlertDialog(
                title: Text(
                  supplier == null
                      ? 'إضافة مورد جديد'
                      : 'تعديل المورد',
                ),
                content: SizedBox(
                  width: 560,
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    children: [
                      _DialogField(
                        title:
                        'اسم المورد / الشركة',
                        controller:
                        nameController,
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
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      _DialogField(
                        title:
                        'ملاحظات',
                        controller:
                        notesController,
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
                    child:
                    const Text(
                      'إلغاء',
                    ),
                  ),
                  ElevatedButton(
                    onPressed: saving
                        ? null
                        : () async {
                      final name =
                      nameController
                          .text
                          .trim();

                      if (name
                          .isEmpty) {
                        _showMessage(
                          'اسم المورد مطلوب.',
                        );

                        return;
                      }

                      setDialogState(
                            () {
                          saving =
                          true;
                        },
                      );

                      try {
                        if (supplier ==
                            null) {
                          await _repository
                              .createSupplier(
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
                          );
                        } else {
                          await _repository
                              .updateSupplier(
                            supplier,
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
                          );
                        }

                        if (!mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                        );

                        await _loadSuppliers();

                        _showMessage(
                          supplier == null
                              ? 'تمت إضافة المورد.'
                              : 'تم تعديل المورد.',
                        );
                      } catch (error) {
                        setDialogState(
                              () {
                            saving =
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
                    child: Text(
                      supplier == null
                          ? 'إضافة المورد'
                          : 'حفظ التعديل',
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

  void _showPaymentDialog(
      SupplierModel supplier,
      ) {
    final amountController =
    TextEditingController();

    final noteController =
    TextEditingController();

    String method = 'CASH';
    var currency = 'IQD';

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
              textDirection:
              TextDirection.rtl,
              child: AlertDialog(
                title:
                const Text(
                  'سند دفع للمورد',
                ),
                content: SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Text(
                        supplier.name,
                        style:
                        const TextStyle(
                          fontSize: 16,
                          fontWeight:
                          FontWeight
                              .w600,
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      Container(
                        padding:
                        const EdgeInsets
                            .all(
                          14,
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
                            12,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child:
                              Text(
                                'المستحق الحالي',
                              ),
                            ),
                            Text(
                              partyBalanceLabel(
                                supplier.balance,
                                supplier.balanceUsd,
                              ),
                              style:
                              const TextStyle(
                                fontWeight:
                                FontWeight
                                    .w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      _DialogField(
                        title:
                        'المبلغ',
                        controller:
                        amountController,
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
                        style:
                        TextStyle(
                          fontSize:
                          11.5,
                          color: AppTheme
                              .secondaryTextColor,
                        ),
                      ),
                      const SizedBox(
                        height: 7,
                      ),
                      Row(
                        children: [
                          _MethodButton(
                            title:
                            'نقدي',
                            selected:
                            method ==
                                'CASH',
                            onTap: () {
                              setDialogState(
                                    () {
                                  method =
                                  'CASH';
                                },
                              );
                            },
                          ),
                          const SizedBox(
                            width: 8,
                          ),
                          _MethodButton(
                            title:
                            'تحويل',
                            selected:
                            method ==
                                'BANK',
                            onTap: () {
                              setDialogState(
                                    () {
                                  method =
                                  'BANK';
                                },
                              );
                            },
                          ),
                          const SizedBox(
                            width: 8,
                          ),
                          _MethodButton(
                            title:
                            'أخرى',
                            selected:
                            method ==
                                'OTHER',
                            onTap: () {
                              setDialogState(
                                    () {
                                  method =
                                  'OTHER';
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      _DialogField(
                        title:
                        'ملاحظة',
                        controller:
                        noteController,
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
                    child:
                    const Text(
                      'إلغاء',
                    ),
                  ),
                  ElevatedButton(
                    onPressed: saving
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
                          ? supplier.balanceUsd
                          : supplier.balance;

                      if (amount >
                          due) {
                        _showMessage(
                          'المبلغ أكبر من المستحق.',
                        );

                        return;
                      }

                      setDialogState(
                            () {
                          saving =
                          true;
                        },
                      );

                      try {
                        await _repository
                            .registerPayment(
                          supplierId:
                          supplier.id,
                          amount:
                          amount,
                          method:
                          method,
                          currency: currency,
                          note:
                          noteController
                              .text,
                        );

                        if (!mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                        );

                        await _loadSuppliers();

                        _showMessage(
                          'تم تسجيل سند الدفع.',
                        );
                      } catch (error) {
                        setDialogState(
                              () {
                            saving =
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
                    child:
                    const Text(
                      'حفظ سند الدفع',
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

  void _showSupplierDetails(
      SupplierModel supplier,
      ) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection:
          TextDirection.rtl,
          child: Dialog(
            child: Container(
              width: 650,
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
                        child:
                        const Icon(
                          Icons
                              .business_outlined,
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
                              supplier.name,
                              style:
                              const TextStyle(
                                fontSize:
                                20,
                                fontWeight:
                                FontWeight
                                    .w700,
                              ),
                            ),
                            const SizedBox(
                              height: 4,
                            ),
                            Text(
                              supplier.phone
                                  .trim()
                                  .isEmpty
                                  ? 'بدون رقم هاتف'
                                  : supplier
                                  .phone,
                              style:
                              const TextStyle(
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
                        icon:
                        const Icon(
                          Icons
                              .close_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 22,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child:
                        _DetailCard(
                          title:
                          'إجمالي المشتريات',
                          value:
                          _formatPrice(
                            supplier
                                .totalPurchases,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      Expanded(
                        child:
                        _DetailCard(
                          title:
                          'المدفوع',
                          value:
                          _formatPrice(
                            supplier
                                .totalPaid,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      Expanded(
                        child:
                        _DetailCard(
                          title:
                          'المستحق',
                          value:
                          _formatPrice(
                            supplier
                                .balance,
                          ),
                          danger:
                          supplier
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
                    title:
                    'العنوان',
                    value: supplier
                        .address
                        .trim()
                        .isEmpty
                        ? '-'
                        : supplier
                        .address,
                  ),
                  _InfoRow(
                    title:
                    'عدد الفواتير',
                    value:
                    '${supplier.invoicesCount}',
                  ),
                  _InfoRow(
                    title:
                    'آخر شراء',
                    value: supplier
                        .lastPurchaseDate ==
                        null
                        ? '-'
                        : _formatDate(
                      supplier
                          .lastPurchaseDate!,
                    ),
                  ),
                  _InfoRow(
                    title:
                    'ملاحظات',
                    value: supplier
                        .notes
                        ?.trim()
                        .isNotEmpty ==
                        true
                        ? supplier.notes!
                        : '-',
                  ),
                ],
              ),
            ),
          ),
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
    final text =
    value.toStringAsFixed(0);

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

    return '${buffer.toString()} د.ع';
  }

  String _formatDate(
      DateTime date,
      ) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _SupplierTableHeader
    extends StatelessWidget {
  const _SupplierTableHeader();

  static const style =
  TextStyle(
    fontSize: 10.5,
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
              'المورد',
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
              'المستحق',
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
          SizedBox(
            width: 50,
          ),
        ],
      ),
    );
  }
}

class _StatCard
    extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final bool highlighted;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    this.highlighted = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 122,
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
                  height: 8,
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

class _BalanceBadge
    extends StatelessWidget {
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
    final settled =
        amount <= 0 && amountUsd <= 0;

    return Align(
      alignment:
      Alignment.centerRight,
      child: Container(
        padding:
        const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 6,
        ),
        decoration:
        BoxDecoration(
          color: settled
              ? const Color(
            0xFFEAF7EE,
          )
              : const Color(
            0xFFFFECEC,
          ),
          borderRadius:
          BorderRadius.circular(
            20,
          ),
        ),
        child: Text(
          partyBalanceLabel(amount, amountUsd),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight:
            FontWeight.w600,
            color: settled
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

class _DialogField
    extends StatelessWidget {
  final String title;

  final TextEditingController
  controller;

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
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
          const TextStyle(
            fontSize: 11.5,
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
        ),
      ],
    );
  }
}

class _MethodButton
    extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _MethodButton({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Expanded(
      child: OutlinedButton(
        style:
        OutlinedButton.styleFrom(
          backgroundColor: selected
              ? AppTheme.primaryColor
              : Colors.white,
          foregroundColor: selected
              ? Colors.white
              : AppTheme
              .primaryTextColor,
        ),
        onPressed: onTap,
        child: Text(title),
      ),
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
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 7,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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
                fontSize: 12,
                fontWeight:
                FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}