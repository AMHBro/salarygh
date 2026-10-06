import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../data/rep_debt_ceiling.dart';
import '../models/representative_model.dart';

class RepresentativesScreen extends StatefulWidget {
  const RepresentativesScreen({
    super.key,
  });

  @override
  State<RepresentativesScreen> createState() =>
      _RepresentativesScreenState();
}

class _RepresentativesScreenState extends State<RepresentativesScreen> {
  final _repository = AppServices.representativesRepository;

  final TextEditingController _searchController = TextEditingController();

  List<RepresentativeModel> _representatives = [];

  String _statusFilter = 'الكل';

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(
      _refresh,
    );

    _loadRepresentatives();
  }

  @override
  void dispose() {
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

  Future<void> _loadRepresentatives() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final representatives = await _repository.getRepresentatives();

      if (!mounted) {
        return;
      }

      setState(() {
        _representatives = representatives;

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

  List<RepresentativeModel> get _filteredRepresentatives {
    final query = _searchController.text.trim().toLowerCase();

    return _representatives.where(
          (representative) {
        final matchesSearch =
            query.isEmpty ||
                representative.name.toLowerCase().contains(query) ||
                representative.username.toLowerCase().contains(query) ||
                representative.phone.contains(query);

        final matchesStatus = switch (_statusFilter) {
          'نشط' => representative.isActive,
          'متوقف' => !representative.isActive,
          _ => true,
        };

        return matchesSearch && matchesStatus;
      },
    ).toList();
  }

  double get _totalSales {
    return _representatives.fold(
      0,
          (sum, representative) => sum + representative.totalSales,
    );
  }

  double get _totalCommission {
    return _representatives.fold(
      0,
          (sum, representative) => sum + representative.totalCommission,
    );
  }

  double get _remainingCommission {
    return _representatives.fold(
      0,
          (sum, representative) => sum + representative.remainingCommission,
    );
  }

  int get _activeRepresentatives {
    return _representatives
        .where(
          (representative) => representative.isActive,
    )
        .length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: _loadRepresentatives,
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
              _buildRepresentativesTable(),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'المندوبون',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: AppTheme.primaryTextColor,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'إدارة المندوبين والمبيعات والعمولات والمستحقات.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _loadRepresentatives,
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
          onPressed: _showAddRepresentativeDialog,
          icon: const Icon(
            Icons.add_rounded,
            size: 18,
          ),
          label: const Text(
            'إضافة مندوب',
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
            title: 'المندوبون النشطون',
            value: '$_activeRepresentatives',
            subtitle: 'حساب مندوب فعال',
            icon: Icons.badge_outlined,
            highlighted: true,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title: 'مبيعات المندوبين',
            value: _formatPrice(_totalSales),
            subtitle: 'إجمالي المبيعات',
            icon: Icons.trending_up_rounded,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title: 'إجمالي العمولات',
            value: _formatPrice(
              _totalCommission,
            ),
            subtitle: 'العمولات المحتسبة',
            icon: Icons.percent_rounded,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            title: 'عمولات مستحقة',
            value: _formatPrice(
              _remainingCommission,
            ),
            subtitle: 'غير مدفوعة للمندوبين',
            icon: Icons.account_balance_wallet_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'ابحث باسم المندوب أو اسم المستخدم أو الهاتف',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 19,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              key: ValueKey(_statusFilter),
              initialValue: _statusFilter,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: 'الكل',
                  child: Text(
                    'كل الحالات',
                  ),
                ),
                DropdownMenuItem(
                  value: 'نشط',
                  child: Text(
                    'نشط',
                  ),
                ),
                DropdownMenuItem(
                  value: 'متوقف',
                  child: Text(
                    'متوقف',
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _statusFilter = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepresentativesTable() {
    final representatives = _filteredRepresentatives;

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
            padding: const EdgeInsets.all(
              20,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'قائمة المندوبين',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryTextColor,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'تفاصيل أداء المندوبين والعمولات.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${representatives.length} مندوب',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          const _RepresentativesTableHeader(),
          if (representatives.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 60,
              ),
              child: Text(
                'لا توجد نتائج مطابقة.',
                style: TextStyle(
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            )
          else
            ...representatives.map(
              _buildRepresentativeRow,
            ),
        ],
      ),
    );
  }

  Widget _buildRepresentativeRow(
      RepresentativeModel representative,
      ) {
    return Container(
      height: 78,
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
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFFF5F5F7,
                        ),
                        borderRadius: BorderRadius.circular(
                          11,
                        ),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        size: 19,
                      ),
                    ),
                    Positioned(
                      left: -2,
                      bottom: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: representative.isActive
                              ? AppTheme.successColor
                              : AppTheme.tertiaryTextColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  width: 11,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        representative.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        '@${representative.username}',
                        overflow: TextOverflow.ellipsis,
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
            flex: 3,
            child: Text(
              representative.officeName.trim().isEmpty
                  ? '-'
                  : representative.officeName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${representative.commissionPercentage.toStringAsFixed(0)} د.ع\n${_priceNames(representative.allowedPrices)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${representative.invoicesCount}',
              style: const TextStyle(
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${representative.soldPieces}',
              style: const TextStyle(
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatPrice(
                representative.totalSales,
              ),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatPrice(
                representative.totalCommission,
              ),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _CommissionBadge(
              value: representative.remainingCommission,
            ),
          ),
          SizedBox(
            width: 50,
            child: PopupMenuButton<String>(
              tooltip: 'خيارات',
              icon: const Icon(
                Icons.more_horiz_rounded,
                size: 19,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'details':
                    _showRepresentativeDetails(
                      representative,
                    );
                    break;

                  case 'commission':
                    _showCommissionPaymentDialog(
                      representative,
                    );
                    break;

                  case 'edit':
                    _showEditRepresentativeDialog(
                      representative,
                    );
                    break;

                  case 'status':
                    _toggleStatus(
                      representative,
                    );
                    break;

                  case 'delete':
                    _deleteRepresentative(representative);
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
                          Icons.visibility_outlined,
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
                    value: 'commission',
                    enabled: representative.remainingCommission > 0,
                    child: const Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 17,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Text(
                          'دفع عمولة',
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
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
                  PopupMenuItem(
                    value: 'status',
                    child: Row(
                      children: [
                        Icon(
                          representative.isActive
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                          size: 17,
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Text(
                          representative.isActive
                              ? 'إيقاف الحساب'
                              : 'تفعيل الحساب',
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

  void _showAddRepresentativeDialog() {
    _showRepresentativeDialog();
  }

  void _showEditRepresentativeDialog(
      RepresentativeModel representative,
      ) {
    _showRepresentativeDialog(
      representative: representative,
    );
  }

  void _showRepresentativeDialog({
    RepresentativeModel? representative,
  }) {
    final nameController = TextEditingController(
      text: representative?.name ?? '',
    );

    final usernameController = TextEditingController(
      text: representative?.username ?? '',
    );

    final passwordController = TextEditingController();

    final phoneController = TextEditingController(
      text: representative?.phone ?? '',
    );

    final commissionController = TextEditingController(
      text: representative?.commissionPercentage.toStringAsFixed(0) ?? '0',
    );
    final debtLimitController = TextEditingController(
      text: (representative?.maxDebtLimit ?? 0).toStringAsFixed(0),
    );
    final selectedPrices = <String>{
      for (final price in (representative?.allowedPrices ??
              'wholesale,representative,retail')
          .split(','))
        if (price.trim().isNotEmpty) price.trim(),
    };

    final officeController = TextEditingController(
      text: representative?.officeName ?? 'المكتب الرئيسي',
    );

    final addressController = TextEditingController(
      text: representative?.officeAddress ?? '',
    );

    final officePhoneController = TextEditingController(
      text: representative?.officePhone ?? '',
    );

    final locationController = TextEditingController(
      text: representative?.locationLink ?? '',
    );

    bool saving = false;
    bool passwordVisible = false;

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
              child: Dialog(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 680,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(
                      24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          representative == null
                              ? 'إضافة مندوب جديد'
                              : 'تعديل بيانات المندوب',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(
                          height: 22,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _DialogField(
                                title: 'اسم المندوب',
                                controller: nameController,
                                hint: 'الاسم الكامل',
                              ),
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            Expanded(
                              child: _DialogField(
                                title: 'اسم المستخدم',
                                controller: usernameController,
                                hint: 'username',
                              ),
                            ),
                          ],
                        ),

                        if (representative == null) ...[
                          const SizedBox(
                            height: 14,
                          ),
                          _DialogField(
                            title: 'كلمة المرور',
                            controller: passwordController,
                            hint: 'أدخل كلمة مرور المندوب',
                            obscureText: !passwordVisible,
                            suffixIcon: IconButton(
                              tooltip: passwordVisible
                                  ? 'إخفاء كلمة المرور'
                                  : 'إظهار كلمة المرور',
                              onPressed: () {
                                setDialogState(
                                      () {
                                    passwordVisible = !passwordVisible;
                                  },
                                );
                              },
                              icon: Icon(
                                passwordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 19,
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(
                          height: 14,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _DialogField(
                                title: 'رقم الهاتف',
                                controller: phoneController,
                                hint: '07xxxxxxxxx',
                              ),
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            Expanded(
                              child: _DialogField(
                                title: 'العمولة بالدينار',
                                controller: commissionController,
                                hint: '0',
                                numeric: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        _DialogField(
                          title: 'سقف الذمة المالي المسموح (دينار)',
                          controller: debtLimitController,
                          hint: '0 = بدون سقف',
                          numeric: true,
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        const Text(
                          'الأسعار التي يبيع بها',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final price in const [
                              ('wholesale', 'جملة'),
                              ('representative', 'مندوب'),
                              ('retail', 'مفرد'),
                              ('cost', 'كلفة'),
                            ])
                              FilterChip(
                                label: Text(price.$2),
                                selected: selectedPrices.contains(price.$1),
                                onSelected: (selected) {
                                  setDialogState(() {
                                    if (selected) {
                                      selectedPrices.add(price.$1);
                                    } else {
                                      selectedPrices.remove(price.$1);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(
                          height: 22,
                        ),
                        const Text(
                          'بيانات المكتب',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _DialogField(
                                title: 'اسم المكتب',
                                controller: officeController,
                                hint: 'المكتب الرئيسي',
                              ),
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            Expanded(
                              child: _DialogField(
                                title: 'هاتف المكتب',
                                controller: officePhoneController,
                                hint: 'رقم الهاتف',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        _DialogField(
                          title: 'عنوان المكتب',
                          controller: addressController,
                          hint: 'العنوان',
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        _DialogField(
                          title: 'رابط الموقع',
                          controller: locationController,
                          hint: 'Google Maps URL',
                        ),
                        const SizedBox(
                          height: 24,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
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
                            const SizedBox(
                              width: 10,
                            ),
                            ElevatedButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                final commission = double.tryParse(
                                  commissionController.text
                                      .trim()
                                      .replaceAll(
                                    ',',
                                    '',
                                  ),
                                ) ??
                                    -1;
                                final debtLimit = double.tryParse(
                                  debtLimitController.text
                                      .trim()
                                      .replaceAll(',', ''),
                                ) ??
                                    -1;

                                if (nameController.text.trim().isEmpty ||
                                    usernameController.text
                                        .trim()
                                        .isEmpty) {
                                  _showMessage(
                                    'اسم المندوب واسم المستخدم مطلوبان.',
                                  );

                                  return;
                                }

                                if (representative == null &&
                                    passwordController.text
                                        .trim()
                                        .isEmpty) {
                                  _showMessage(
                                    'كلمة المرور مطلوبة عند إنشاء المندوب.',
                                  );

                                  return;
                                }

                                if (commission < 0) {
                                  _showMessage(
                                    'العمولة بالدينار لا تكون سالبة.',
                                  );

                                  return;
                                }

                                if (debtLimit < 0) {
                                  _showMessage(
                                    'سقف الذمة لا يكون سالباً. اكتب 0 لإلغاء السقف.',
                                  );

                                  return;
                                }

                                if (selectedPrices.isEmpty) {
                                  _showMessage(
                                    'اختر سعراً واحداً على الأقل ليبيع به المندوب.',
                                  );

                                  return;
                                }

                                setDialogState(
                                      () {
                                    saving = true;
                                  },
                                );

                                try {
                                  if (representative == null) {
                                    await _repository
                                        .createRepresentative(
                                      name: nameController.text,
                                      username: usernameController.text,
                                      password: passwordController.text,
                                      phone: phoneController.text,
                                      officeName: officeController.text,
                                      officeAddress:
                                      addressController.text,
                                      officePhone:
                                      officePhoneController.text,
                                      locationLink:
                                      locationController.text,
                                      commissionPercentage: commission,
                                      allowedPrices: selectedPrices.join(','),
                                      maxDebtLimit: debtLimit,
                                    );
                                  } else {
                                    await _repository
                                        .updateRepresentative(
                                      representative,
                                      name: nameController.text,
                                      username: usernameController.text,
                                      phone: phoneController.text,
                                      officeName: officeController.text,
                                      officeAddress:
                                      addressController.text,
                                      officePhone:
                                      officePhoneController.text,
                                      locationLink:
                                      locationController.text,
                                      commissionPercentage: commission,
                                      allowedPrices: selectedPrices.join(','),
                                      maxDebtLimit: debtLimit,
                                    );
                                  }

                                  if (!dialogContext.mounted) {
                                    return;
                                  }

                                  Navigator.pop(
                                    dialogContext,
                                  );

                                  await _loadRepresentatives();

                                  _showMessage(
                                    representative == null
                                        ? 'تمت إضافة المندوب.'
                                        : 'تم حفظ التعديلات.',
                                  );
                                } catch (error) {
                                  setDialogState(
                                        () {
                                      saving = false;
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
                                representative == null
                                    ? 'إضافة المندوب'
                                    : 'حفظ التعديلات',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCommissionPaymentDialog(
      RepresentativeModel representative,
      ) {
    final amountController = TextEditingController();

    final noteController = TextEditingController();

    String method = 'CASH';

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
                title: const Text(
                  'دفع عمولة',
                ),
                content: SizedBox(
                  width: 470,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(
                          16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF5F5F7,
                          ),
                          borderRadius: BorderRadius.circular(
                            14,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'العمولة المستحقة',
                                style: TextStyle(
                                  color: AppTheme.secondaryTextColor,
                                ),
                              ),
                            ),
                            Text(
                              _formatPrice(
                                representative.remainingCommission,
                              ),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      _DialogField(
                        title: 'المبلغ',
                        controller: amountController,
                        hint: '0',
                        numeric: true,
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      Row(
                        children: [
                          _MethodButton(
                            title: 'نقدي',
                            selected: method == 'CASH',
                            onTap: () {
                              setDialogState(
                                    () {
                                  method = 'CASH';
                                },
                              );
                            },
                          ),
                          const SizedBox(
                            width: 8,
                          ),
                          _MethodButton(
                            title: 'تحويل',
                            selected: method == 'BANK',
                            onTap: () {
                              setDialogState(
                                    () {
                                  method = 'BANK';
                                },
                              );
                            },
                          ),
                          const SizedBox(
                            width: 8,
                          ),
                          _MethodButton(
                            title: 'أخرى',
                            selected: method == 'OTHER',
                            onTap: () {
                              setDialogState(
                                    () {
                                  method = 'OTHER';
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
                        title: 'ملاحظة',
                        controller: noteController,
                        hint: 'ملاحظة اختيارية',
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
                      final amount = double.tryParse(
                        amountController.text.trim().replaceAll(
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

                      if (amount > representative.remainingCommission) {
                        _showMessage(
                          'المبلغ أكبر من العمولة المستحقة.',
                        );

                        return;
                      }

                      setDialogState(
                            () {
                          saving = true;
                        },
                      );

                      try {
                        await _repository.registerPayment(
                          representativeId: representative.id,
                          amount: amount,
                          method: method,
                          note: noteController.text,
                        );

                        if (!dialogContext.mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                        );

                        await _loadRepresentatives();

                        _showMessage(
                          'تم تسجيل دفعة العمولة.',
                        );
                      } catch (error) {
                        setDialogState(
                              () {
                            saving = false;
                          },
                        );

                        _showMessage(
                          _errorMessage(
                            error,
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'تسجيل الدفع',
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

  Future<void> _toggleStatus(
      RepresentativeModel representative,
      ) async {
    try {
      await _repository.setRepresentativeActive(
        representative: representative,
        isActive: !representative.isActive,
      );

      await _loadRepresentatives();

      _showMessage(
        representative.isActive
            ? 'تم إيقاف حساب المندوب.'
            : 'تم تفعيل حساب المندوب.',
      );
    } catch (error) {
      _showMessage(
        _errorMessage(error),
      );
    }
  }

  Future<void> _deleteRepresentative(
    RepresentativeModel representative,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف حساب المندوب'),
        content: Text(
          'ينحذف دخول ${representative.name} وما يقدر يفتح حساب المندوب بعد المزامنة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteRepresentative(representative);
      await _loadRepresentatives();
      _showMessage('حُذف الحساب. اضغط مزامنة الآن حتى ينقفل دخوله من الهاتف.');
    } catch (error) {
      _showMessage(_errorMessage(error));
    }
  }

  void _showRepresentativeDetails(
      RepresentativeModel representative,
      ) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            child: Container(
              width: 680,
              padding: const EdgeInsets.all(
                24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<RepDebtWarning?>(
                    future: RepDebtCeiling.forRepresentative(
                      AppServices.database,
                      representative.id,
                    ),
                    builder: (context, snapshot) {
                      final warning = snapshot.data;
                      if (warning == null) return const SizedBox.shrink();
                      return RepDebtBanner(message: warning.message);
                    },
                  ),
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.badge_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(
                        width: 14,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              representative.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '@${representative.username}',
                              style: const TextStyle(
                                color: AppTheme.secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusBadge(
                        active: representative.isActive,
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
                          title: 'المبيعات',
                          value: _formatPrice(
                            representative.totalSales,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      Expanded(
                        child: _DetailCard(
                          title: 'العمولة',
                          value: _formatPrice(
                            representative.totalCommission,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      Expanded(
                        child: _DetailCard(
                          title: 'المستحق',
                          value: _formatPrice(
                            representative.remainingCommission,
                          ),
                          danger: representative.remainingCommission > 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 22,
                  ),
                  _InfoRow(
                    title: 'سقف الذمة',
                    value: representative.maxDebtLimit <= 0
                        ? 'بدون سقف'
                        : _formatPrice(representative.maxDebtLimit),
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  _InfoRow(
                    title: 'نسبة العمولة',
                    value:
                    '${representative.commissionPercentage.toStringAsFixed(2)}%',
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  _InfoRow(
                    title: 'عدد الفواتير',
                    value: '${representative.invoicesCount}',
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  _InfoRow(
                    title: 'القطع المباعة',
                    value: '${representative.soldPieces}',
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  _InfoRow(
                    title: 'رقم الهاتف',
                    value: representative.phone.trim().isEmpty
                        ? '-'
                        : representative.phone,
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  _InfoRow(
                    title: 'المكتب',
                    value: representative.officeName.trim().isEmpty
                        ? '-'
                        : representative.officeName,
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  _InfoRow(
                    title: 'عنوان المكتب',
                    value: representative.officeAddress.trim().isEmpty
                        ? '-'
                        : representative.officeAddress,
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: representative.remainingCommission <= 0
                            ? null
                            : () {
                          Navigator.pop(
                            context,
                          );

                          _showCommissionPaymentDialog(
                            representative,
                          );
                        },
                        icon: const Icon(
                          Icons.payments_outlined,
                          size: 17,
                        ),
                        label: const Text(
                          'دفع عمولة',
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

  void _showMessage(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
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

      buffer.write(text[i]);
    }

    return '${buffer.toString()} د.ع';
  }
}

class _RepresentativesTableHeader extends StatelessWidget {
  const _RepresentativesTableHeader();

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
      color: const Color(0xFFF8F8FA),
      child: const Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'المندوب',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'المكتب',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'العمولة',
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
            flex: 2,
            child: Text(
              'القطع',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'المبيعات',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'العمولة الكلية',
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
          SizedBox(width: 50),
        ],
      ),
    );
  }
}

class _CommissionBadge extends StatelessWidget {
  final double value;

  const _CommissionBadge({
    required this.value,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final paid = value <= 0;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: paid
              ? const Color(
            0xFFEAF7EE,
          )
              : const Color(
            0xFFFFF4E5,
          ),
          borderRadius: BorderRadius.circular(
            20,
          ),
        ),
        child: Text(
          paid ? 'مسدد' : '${value.toStringAsFixed(0)} د.ع',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: paid
                ? const Color(
              0xFF248A3D,
            )
                : const Color(
              0xFFB26A00,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;

  const _StatusBadge({
    required this.active,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: active
            ? const Color(
          0xFFEAF7EE,
        )
            : const Color(
          0xFFF2F2F4,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        active ? 'نشط' : 'متوقف',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: active
              ? AppTheme.successColor
              : AppTheme.secondaryTextColor,
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(
          0xFF1D1D1F,
        )
            : Colors.white,
        borderRadius: BorderRadius.circular(17),
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
                const SizedBox(
                  height: 7,
                ),
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
              color: highlighted ? Colors.white : AppTheme.primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final String hint;
  final bool numeric;
  final bool obscureText;
  final Widget? suffixIcon;

  const _DialogField({
    required this.title,
    required this.controller,
    required this.hint,
    this.numeric = false,
    this.obscureText = false,
    this.suffixIcon,
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
            fontWeight: FontWeight.w500,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 7,
        ),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(
            decimal: true,
          )
              : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}

class _MethodButton extends StatelessWidget {
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
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? AppTheme.primaryColor : Colors.white,
          foregroundColor:
          selected ? Colors.white : AppTheme.primaryTextColor,
        ),
        onPressed: onTap,
        child: Text(title),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color:
              danger ? AppTheme.dangerColor : AppTheme.primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
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
      children: [
        SizedBox(
          width: 130,
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.secondaryTextColor,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

String _priceNames(String raw) {
  const names = {
    'cost': 'كلفة',
    'wholesale': 'جملة',
    'representative': 'مندوب',
    'retail': 'مفرد',
  };
  final labels = [
    for (final part in raw.split(','))
      if (names.containsKey(part.trim())) names[part.trim()]!,
  ];
  return labels.isEmpty ? 'بدون سعر' : labels.join('، ');
}