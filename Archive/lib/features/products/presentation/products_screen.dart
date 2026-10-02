import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/app_services.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/theme/app_theme.dart';
import 'product_details_screen.dart';
import '../data/products_local_repository.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';
import '../models/unit_model.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({
    super.key,
  });

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final ProductsLocalRepository _repository =
      AppServices.productsRepository;

  final TextEditingController _searchController =
  TextEditingController();

  static const Uuid _uuid = Uuid();

  List<CategoryModel> _categories = [];
  List<UnitModel> _units = [];

  bool _showInactive = true;
  bool _isLoadingReferenceData = true;
  bool _isSyncing = false;
  int _productPage = 1;
  Timer? _searchTimer;
  String _productStreamKey = '';
  Stream<ProductDirectoryPage>? _productStream;

  Future<void> _openProductDetails(
      ProductModel product,
      ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailsScreen(
          product: product,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_onProductSearch);

    _loadReferenceData();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.removeListener(_onProductSearch);

    _searchController.dispose();

    super.dispose();
  }

  Stream<ProductDirectoryPage> _currentProductStream() {
    final key = '${_searchController.text}|$_productPage|$_showInactive';
    if (_productStream == null || _productStreamKey != key) {
      _productStreamKey = key;
      _productStream = _repository.watchProductPage(
        search: _searchController.text,
        offset: (_productPage - 1) * kListPageSize,
        includeInactive: _showInactive,
      );
    }
    return _productStream!;
  }

  void _onProductSearch() {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _productPage = 1;
      });
    });
  }

  Future<void> _loadReferenceData() async {
    if (mounted) {
      setState(() {
        _isLoadingReferenceData = true;
      });
    }

    try {
      await AppServices.refreshReferenceDataSafe();

      final results = await Future.wait([
        AppServices.categoriesRepository.getCategories(),
        AppServices.unitsRepository.getUnits(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _categories = results[0] as List<CategoryModel>;
        _units = results[1] as List<UnitModel>;
        _isLoadingReferenceData = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingReferenceData = false;
      });

      _showMessage(
        _cleanError(error),
      );
    }
  }

  Future<void> _syncNow() async {
    if (_isSyncing) {
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      await AppServices.refreshReferenceDataSafe();

      final fixedCount =
      await _repository.backfillLegacyProductReferences();

      debugPrint(
        'PRODUCT BACKFILL -> fixed: $fixedCount',
      );

      await AppServices.syncNow();

      if (!mounted) {
        return;
      }

      if (fixedCount > 0) {
        _showMessage(
          'تم إصلاح $fixedCount منتج قديم وبدأت المزامنة.',
        );
      } else {
        _showMessage(
          'اكتملت محاولة المزامنة.',
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _cleanError(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Padding(
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
              height: 26,
            ),
            Expanded(
              child: StreamBuilder<ProductDirectoryPage>(
                stream: _currentProductStream(),
                builder: (
                    context,
                    snapshot,
                    ) {
                  if (snapshot.connectionState ==
                      ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return _buildErrorState(
                      snapshot.error.toString(),
                    );
                  }

                  final page = snapshot.data ??
                      const ProductDirectoryPage(
                        items: [],
                        total: 0,
                        activeCount: 0,
                        syncedCount: 0,
                        variantCount: 0,
                      );

                  return Column(
                    children: [
                      _buildStats(
                        page,
                      ),
                      const SizedBox(
                        height: 18,
                      ),
                      Expanded(
                        child: _buildProductsCard(
                          page,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
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
                'المنتجات',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: AppTheme.primaryTextColor,
                ),
              ),
              SizedBox(
                height: 5,
              ),
              Text(
                'إدارة المنتجات والخيارات والأسعار ومعلومات البيع.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _isSyncing ? null : _syncNow,
          icon: _isSyncing
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          )
              : const Icon(
            Icons.cloud_sync_outlined,
            size: 18,
          ),
          label: Text(
            _isSyncing
                ? 'جاري المزامنة...'
                : 'مزامنة الآن',
          ),
        ),
        const SizedBox(
          width: 10,
        ),
        OutlinedButton.icon(
          onPressed:
          _isLoadingReferenceData ? null : _loadReferenceData,
          icon: _isLoadingReferenceData
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          )
              : const Icon(
            Icons.refresh_rounded,
            size: 18,
          ),
          label: const Text(
            'تحديث البيانات',
          ),
        ),
        const SizedBox(
          width: 10,
        ),
        ElevatedButton.icon(
          onPressed:
          _isLoadingReferenceData ? null : _showProductDialog,
          icon: const Icon(
            Icons.add_rounded,
            size: 18,
          ),
          label: const Text(
            'إضافة منتج',
          ),
        ),
      ],
    );
  }

  Widget _buildStats(
      ProductDirectoryPage page,
      ) {
    final activeCount = page.activeCount;
    final syncedCount = page.syncedCount;
    final waitingCount = page.total - syncedCount;
    final variantsCount = page.variantCount;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: 'إجمالي المنتجات',
            value: page.total.toString(),
            subtitle: 'المنتجات المسجلة محلياً',
            icon: Icons.inventory_2_outlined,
            highlighted: true,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _StatCard(
            title: 'الخيارات',
            value: variantsCount.toString(),
            subtitle: 'Variants المسجلة',
            icon: Icons.account_tree_outlined,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _StatCard(
            title: 'على السيرفر',
            value: syncedCount.toString(),
            subtitle: 'تم استلام Server ID',
            icon: Icons.cloud_done_outlined,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _StatCard(
            title: 'بانتظار المزامنة',
            value: waitingCount.toString(),
            subtitle: 'محفوظة محلياً فقط',
            icon: Icons.cloud_upload_outlined,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _StatCard(
            title: 'المنتجات الفعالة',
            value: activeCount.toString(),
            subtitle: 'متاحة للبيع حالياً',
            icon: Icons.check_circle_outline,
          ),
        ),
      ],
    );
  }

  Widget _buildProductsCard(
      ProductDirectoryPage page,
      ) {
    final products = page.items;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(
              18,
            ),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText:
                        'بحث بالاسم، الباركود، SKU أو الخيار',
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                FilterChip(
                  label: const Text(
                    'إظهار الموقوفة',
                  ),
                  selected: _showInactive,
                  onSelected: (value) {
                    setState(() {
                      _showInactive = value;
                      _productPage = 1;
                    });
                  },
                ),
              ],
            ),
          ),
          const _ProductsHeader(),
          Expanded(
            child: products.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
              itemCount: products.length + 1,
              itemBuilder: (
                  context,
                  index,
                  ) {
                if (index >= products.length) {
                  return ListPagination(
                    page: _productPage,
                    totalItems: page.total,
                    onPageChanged: (next) {
                      setState(() {
                        _productPage = next;
                      });
                    },
                  );
                }
                final product = products[index];

                return _ProductRow(
                  product: product,
                  onOpen: () {
                    _openProductDetails(
                      product,
                    );
                  },
                  onEdit: () {
                    _showProductDialog(
                      product: product,
                    );
                  },
                  onToggleActive: () async {
                    try {
                      await _repository.setProductActive(
                        product: product,
                        isActive: !product.isActive,
                      );
                    } catch (error) {
                      _showMessage(
                        _cleanError(
                          error,
                        ),
                      );
                    }
                  },
                  onDelete: () {
                    _confirmDelete(
                      product,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(
                0xFFF5F5F7,
              ),
              borderRadius: BorderRadius.circular(
                18,
              ),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 28,
              color: AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(
            height: 14,
          ),
          const Text(
            'لا توجد منتجات',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          const Text(
            'أضف أول منتج حتى يظهر هنا.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
      String error,
      ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 36,
          ),
          const SizedBox(
            height: 12,
          ),
          const Text(
            'تعذر قراءة المنتجات.',
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            error,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showProductDialog({
    ProductModel? product,
  }) async {
    final isEdit = product != null;

    if (_categories.isEmpty || _units.isEmpty) {
      await _loadReferenceData();

      if (!mounted) {
        return;
      }
    }

    final nameController = TextEditingController(
      text: product?.name ?? '',
    );

    final nameEnController = TextEditingController(
      text: product?.nameEn ?? '',
    );

    final barcodeController = TextEditingController(
      text: product?.barcode ?? '',
    );

    final skuController = TextEditingController(
      text: product?.sku ?? '',
    );

    final descriptionController = TextEditingController(
      text: product?.description ?? '',
    );

    final costController = TextEditingController(
      text: product == null
          ? ''
          : product.costPrice.toStringAsFixed(0),
    );

    final representativeController = TextEditingController(
      text: product == null
          ? ''
          : product.representativePrice.toStringAsFixed(0),
    );

    final wholesaleController = TextEditingController(
      text: product == null
          ? ''
          : product.wholesalePrice.toStringAsFixed(0),
    );

    final retailController = TextEditingController(
      text: product == null
          ? ''
          : product.retailPrice.toStringAsFixed(0),
    );

    final minimumStockController = TextEditingController(
      text: product == null
          ? '0'
          : product.minimumStock.toStringAsFixed(0),
    );
    final cartonCountController = TextEditingController(text: '0');
    final piecesInsideController = TextEditingController(
      text: product == null || product.piecesPerCarton <= 0
          ? '1'
          : product.piecesPerCarton.toStringAsFixed(0),
    );

    final keptPhoto = (product?.imageUrl ?? '').startsWith('data:image')
        ? product!.imageUrl!
        : '';
    final imageUrlController = TextEditingController(
      text: keptPhoto.isEmpty ? (product?.imageUrl ?? '') : '',
    );

    String? selectedCategoryId = _resolveCategoryId(
      product,
    );

    String? selectedUnitId = _resolveUnitId(
      product,
    );

    bool hasExpiry = product?.hasExpiry ?? false;
    bool hasSerial = product?.hasSerial ?? false;
    bool hasVariants = product?.hasVariants ?? false;

    List<ProductVariantModel> variants = product == null
        ? []
        : List<ProductVariantModel>.from(
      product.variants,
    );

    bool saving = false;
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (
          dialogContext,
          ) {
        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            final selectedCategory = _findCategory(
              selectedCategoryId,
            );

            final selectedUnit = _findUnit(
              selectedUnitId,
            );

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEdit
                            ? 'تعديل المنتج'
                            : 'إضافة منتج',
                      ),
                    ),
                    if (hasVariants)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF1F1F4,
                          ),
                          borderRadius: BorderRadius.circular(
                            20,
                          ),
                        ),
                        child: Text(
                          '${variants.length} خيارات',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                content: SizedBox(
                  width: 900,
                  height: 680,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _DialogField(
                                label: 'اسم المنتج بالعربي *',
                                controller: nameController,
                              ),
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            Expanded(
                              child: _DialogField(
                                label: 'اسم المنتج بالإنكليزي',
                                controller: nameEnController,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 12,
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ProductImageBox(
                              imageUrl: imageUrlController.text.trim().isEmpty
                                  ? keptPhoto
                                  : imageUrlController.text.trim(),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DialogField(
                                label: 'رابط الصورة',
                                controller: imageUrlController,
                                hintText: 'https://...',
                                onChanged: (_) => setDialogState(() {
                                  dialogError = null;
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 12,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _categories.isEmpty
                                  ? const InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'التصنيف *',
                                      ),
                                      child: Text(
                                        'لا يوجد تصنيف بعد. اضغط إضافة صنف.',
                                      ),
                                    )
                                  : _DropdownField(
                                label: 'التصنيف *',
                                value: selectedCategoryId,
                                hint: 'اختر التصنيف',
                                items: _categories.map(
                                      (
                                      category,
                                      ) {
                                    return DropdownMenuItem<String>(
                                      value: category.id,
                                      child: Text(
                                        category.nameAr,
                                      ),
                                    );
                                  },
                                ).toList(),
                                onChanged: saving
                                    ? null
                                    : (
                                    value,
                                    ) {
                                  setDialogState(
                                        () {
                                      selectedCategoryId =
                                          value;
                                      dialogError = null;
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final created =
                                          await _askForCategoryName(
                                        dialogContext,
                                      );
                                      if (created == null || !mounted) {
                                        return;
                                      }
                                      setState(() {
                                        _categories = [
                                          ..._categories.where(
                                            (item) => item.id != created.id,
                                          ),
                                          created,
                                        ];
                                      });
                                      setDialogState(() {
                                        selectedCategoryId = created.id;
                                        dialogError = null;
                                      });
                                    },
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('إضافة صنف'),
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            Expanded(
                              child: _DropdownField(
                                label: 'وحدة القياس *',
                                value: selectedUnitId,
                                hint: 'اختر الوحدة',
                                items: _units.map(
                                      (
                                      unit,
                                      ) {
                                    return DropdownMenuItem<String>(
                                      value: unit.id,
                                      child: Text(
                                        '${unit.nameAr} (${unit.symbol})',
                                      ),
                                    );
                                  },
                                ).toList(),
                                onChanged: saving
                                    ? null
                                    : (
                                    value,
                                    ) {
                                  setDialogState(
                                        () {
                                      selectedUnitId = value;
                                      dialogError = null;
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final created = await _askForUnitName(
                                        dialogContext,
                                      );
                                      if (created == null || !mounted) {
                                        return;
                                      }
                                      setState(() {
                                        _units = [
                                          ..._units.where(
                                            (item) => item.id != created.id,
                                          ),
                                          created,
                                        ];
                                      });
                                      setDialogState(() {
                                        selectedUnitId = created.id;
                                        dialogError = null;
                                      });
                                    },
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('إضافة وحدة'),
                            ),
                          ],
                        ),
                        if (selectedCategory != null ||
                            selectedUnit != null) ...[
                          const SizedBox(
                            height: 8,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              [
                                if (selectedCategory != null)
                                  'التصنيف: ${selectedCategory.nameAr}',
                                if (selectedUnit != null)
                                  'الوحدة: ${selectedUnit.nameAr}',
                              ].join(
                                '   •   ',
                              ),
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppTheme.tertiaryTextColor,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(
                          height: 12,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _DialogField(
                                label: 'كم كارتون',
                                controller: cartonCountController,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DialogField(
                                label: 'كم قطعة داخل الكارتون',
                                controller: piecesInsideController,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'مثال: 10 كارتون، وكل كارتون فيه 24 قطعة. المخزون يُحسب قطعاً.',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppTheme.tertiaryTextColor,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 18,
                        ),
                        _buildProductTypeSelector(
                          hasVariants: hasVariants,
                          saving: saving,
                          onChanged: (value) {
                            setDialogState(
                                  () {
                                hasVariants = value;
                                dialogError = null;
                              },
                            );
                          },
                        ),
                        const SizedBox(
                          height: 18,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _DialogField(
                                label: hasVariants
                                    ? 'باركود المنتج الرئيسي (اختياري)'
                                    : 'الباركود',
                                controller: barcodeController,
                              ),
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            Expanded(
                              child: _DialogField(
                                label: hasVariants
                                    ? 'SKU المنتج الرئيسي (اختياري)'
                                    : 'رمز المنتج SKU',
                                controller: skuController,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 12,
                        ),
                        _DialogField(
                          label: 'الوصف',
                          controller: descriptionController,
                          maxLines: 2,
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: CheckboxListTile(
                                value: hasExpiry,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: const Text(
                                  'للمنتج تاريخ صلاحية',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                  ),
                                ),
                                controlAffinity:
                                ListTileControlAffinity.leading,
                                onChanged: saving
                                    ? null
                                    : (
                                    value,
                                    ) {
                                  setDialogState(
                                        () {
                                      hasExpiry =
                                          value ?? false;
                                    },
                                  );
                                },
                              ),
                            ),
                            Expanded(
                              child: CheckboxListTile(
                                value: hasSerial,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: const Text(
                                  'للمنتج رقم تسلسلي',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                  ),
                                ),
                                controlAffinity:
                                ListTileControlAffinity.leading,
                                onChanged: saving
                                    ? null
                                    : (
                                    value,
                                    ) {
                                  setDialogState(
                                        () {
                                      hasSerial =
                                          value ?? false;
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 18,
                        ),
                        _buildMainPricingSection(
                          costController: costController,
                          representativeController:
                          representativeController,
                          wholesaleController:
                          wholesaleController,
                          retailController: retailController,
                          minimumStockController:
                          minimumStockController,
                          hasVariants: hasVariants,
                        ),
                        if (hasVariants) ...[
                          const SizedBox(
                            height: 22,
                          ),
                          _buildVariantsSection(
                            variants: variants,
                            saving: saving,
                            onAdd: () async {
                              final variant =
                              await _showVariantDialog(
                                productId: product?.id ?? '',
                                defaultCost: _number(
                                  costController.text,
                                ),
                                defaultRepresentative: _number(
                                  representativeController.text,
                                ),
                                defaultWholesale: _number(
                                  wholesaleController.text,
                                ),
                                defaultRetail: _number(
                                  retailController.text,
                                ),
                              );

                              if (variant == null) {
                                return;
                              }

                              setDialogState(
                                    () {
                                  variants.add(
                                    variant,
                                  );
                                  dialogError = null;
                                },
                              );
                            },
                            onEdit: (
                                index,
                                ) async {
                              final edited =
                              await _showVariantDialog(
                                productId: product?.id ?? '',
                                variant: variants[index],
                                defaultCost: _number(
                                  costController.text,
                                ),
                                defaultRepresentative: _number(
                                  representativeController.text,
                                ),
                                defaultWholesale: _number(
                                  wholesaleController.text,
                                ),
                                defaultRetail: _number(
                                  retailController.text,
                                ),
                              );

                              if (edited == null) {
                                return;
                              }

                              setDialogState(
                                    () {
                                  variants[index] = edited;
                                },
                              );
                            },
                            onDelete: (
                                index,
                                ) {
                              setDialogState(
                                    () {
                                  variants.removeAt(
                                    index,
                                  );
                                },
                              );
                            },
                          ),
                        ],
                        if (dialogError != null) ...[
                          const SizedBox(
                            height: 16,
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(
                              12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFFECEC,
                              ),
                              borderRadius: BorderRadius.circular(
                                10,
                              ),
                            ),
                            child: Text(
                              dialogError!,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.dangerColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () {
                      Navigator.of(
                        dialogContext,
                      ).pop(
                        false,
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
                      final name =
                      nameController.text.trim();

                      if (name.isEmpty) {
                        setDialogState(
                              () {
                            dialogError =
                            'اسم المنتج مطلوب.';
                          },
                        );
                        return;
                      }

                      if (selectedCategoryId == null) {
                        setDialogState(
                              () {
                            dialogError =
                            'اختر تصنيف المنتج.';
                          },
                        );
                        return;
                      }

                      if (selectedUnitId == null) {
                        setDialogState(
                              () {
                            dialogError =
                            'اختر وحدة القياس.';
                          },
                        );
                        return;
                      }

                      if (hasVariants && variants.isEmpty) {
                        setDialogState(
                              () {
                            dialogError =
                            'أضف خيار واحد على الأقل للمنتج.';
                          },
                        );
                        return;
                      }

                      final imageUrl = imageUrlController.text.trim().isEmpty
                          ? keptPhoto
                          : imageUrlController.text.trim();
                      if (imageUrl.isNotEmpty &&
                          !imageUrl.startsWith('data:image/') &&
                          !_isHttpUrl(imageUrl)) {
                        setDialogState(() {
                          dialogError =
                              'رابط الصورة غير صالح. الصق رابطاً يبدأ بـ https://';
                        });
                        return;
                      }

                      final category = _findCategory(
                        selectedCategoryId,
                      );

                      final unit = _findUnit(
                        selectedUnitId,
                      );

                      if (category == null || unit == null) {
                        setDialogState(
                              () {
                            dialogError =
                            'تعذر تحديد التصنيف أو الوحدة.';
                          },
                        );
                        return;
                      }

                      setDialogState(
                            () {
                          saving = true;
                          dialogError = null;
                        },
                      );

                      try {
                        final piecesInside = _number(
                          piecesInsideController.text,
                        );
                        final cartonCount = _number(
                          cartonCountController.text,
                        ).round();
                        String? savedProductId = product?.id;
                        if (isEdit) {
                          await _repository.updateProduct(
                            product: product.copyWith(
                              name: name,
                              nameEn:
                              nameEnController.text.trim(),
                              barcode:
                              barcodeController.text,
                              sku: skuController.text,
                              categoryId: category.id,
                              categoryName: category.nameAr,
                              baseUnitId: unit.id,
                              unit: unit.nameAr,
                              description:
                              descriptionController.text
                                  .trim(),
                              hasExpiry: hasExpiry,
                              hasSerial: hasSerial,
                              hasVariants: hasVariants,
                              variants: hasVariants
                                  ? variants
                                  : const [],
                              costPrice: _number(
                                costController.text,
                              ),
                              representativePrice: _number(
                                representativeController.text,
                              ),
                              wholesalePrice: _number(
                                wholesaleController.text,
                              ),
                              retailPrice: _number(
                                retailController.text,
                              ),
                              minimumStock: _number(
                                minimumStockController.text,
                              ),
                              imageUrl: imageUrl,
                            ),
                          );
                        } else {
                          final created = await _repository.createProduct(
                            name: name,
                            nameEn:
                            nameEnController.text.trim(),
                            barcode: barcodeController.text,
                            sku: skuController.text,
                            categoryId: category.id,
                            categoryName: category.nameAr,
                            baseUnitId: unit.id,
                            unit: unit.nameAr,
                            description:
                            descriptionController.text
                                .trim(),
                            hasVariants: hasVariants,
                            variants: hasVariants
                                ? variants
                                : const [],
                            hasExpiry: hasExpiry,
                            hasSerial: hasSerial,
                            costPrice: _number(
                              costController.text,
                            ),
                            representativePrice: _number(
                              representativeController.text,
                            ),
                            wholesalePrice: _number(
                              wholesaleController.text,
                            ),
                            retailPrice: _number(
                              retailController.text,
                            ),
                            minimumStock: _number(
                              minimumStockController.text,
                            ),
                            imageUrl: imageUrl,
                          );
                          savedProductId = created.id;
                        }

                        if (savedProductId != null) {
                          await _repository.rememberCarton(
                            productId: savedProductId,
                            piecesPerCarton: piecesInside < 1
                                ? 1
                                : piecesInside,
                            cartons: isEdit
                                ? 0
                                : (cartonCount < 0 ? 0 : cartonCount),
                          );
                        }

                        if (!dialogContext.mounted) {
                          return;
                        }

                        Navigator.of(
                          dialogContext,
                        ).pop(
                          true,
                        );
                      } catch (error) {
                        if (!dialogContext.mounted) {
                          return;
                        }

                        setDialogState(
                              () {
                            saving = false;
                            dialogError =
                                _cleanError(error);
                          },
                        );
                      }
                    },
                    child: saving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : Text(
                      isEdit
                          ? 'حفظ التعديلات'
                          : 'إضافة المنتج',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      await Future<void>.delayed(
        const Duration(
          milliseconds: 250,
        ),
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        isEdit
            ? 'تم حفظ تعديلات المنتج محلياً.'
            : 'تم حفظ المنتج محلياً.',
      );

      await _syncNow();
    }
  }

  Widget _buildProductTypeSelector({
    required bool hasVariants,
    required bool saving,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(
        4,
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
          Expanded(
            child: _ProductTypeButton(
              selected: !hasVariants,
              icon: Icons.inventory_2_outlined,
              title: 'منتج عادي',
              subtitle: 'باركود وأسعار واحدة',
              onTap: saving
                  ? null
                  : () {
                onChanged(
                  false,
                );
              },
            ),
          ),
          const SizedBox(
            width: 6,
          ),
          Expanded(
            child: _ProductTypeButton(
              selected: hasVariants,
              icon: Icons.account_tree_outlined,
              title: 'يحتوي على خيارات',
              subtitle: 'نكهة، حجم، لون أو نوع',
              onTap: saving
                  ? null
                  : () {
                onChanged(
                  true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainPricingSection({
    required TextEditingController costController,
    required TextEditingController representativeController,
    required TextEditingController wholesaleController,
    required TextEditingController retailController,
    required TextEditingController minimumStockController,
    required bool hasVariants,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xFFFAFAFB,
        ),
        borderRadius: BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasVariants
                ? 'الأسعار الأساسية'
                : 'الأسعار',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasVariants) ...[
            const SizedBox(
              height: 3,
            ),
            const Text(
              'تستخدم كقيم افتراضية عند إضافة خيار جديد، ويمكن تغيير سعر كل خيار بشكل مستقل.',
              style: TextStyle(
                fontSize: 10.5,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ],
          const SizedBox(
            height: 12,
          ),
          Row(
            children: [
              Expanded(
                child: _DialogField(
                  label: 'سعر الكلفة',
                  controller: costController,
                  numeric: true,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: _DialogField(
                  label: 'سعر المندوب',
                  controller: representativeController,
                  numeric: true,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: _DialogField(
                  label: 'سعر الجملة',
                  controller: wholesaleController,
                  numeric: true,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: _DialogField(
                  label: 'سعر التجزئة',
                  controller: retailController,
                  numeric: true,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 12,
          ),
          SizedBox(
            width: 240,
            child: _DialogField(
              label: 'الحد الأدنى للمخزون',
              controller: minimumStockController,
              numeric: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantsSection({
    required List<ProductVariantModel> variants,
    required bool saving,
    required VoidCallback onAdd,
    required ValueChanged<int> onEdit,
    required ValueChanged<int> onDelete,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'خيارات المنتج',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(
                      height: 3,
                    ),
                    Text(
                      'كل خيار يمتلك باركود وSKU وأسعار خاصة به.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: saving ? null : onAdd,
                icon: const Icon(
                  Icons.add_rounded,
                  size: 17,
                ),
                label: const Text(
                  'إضافة خيار',
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 14,
          ),
          if (variants.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                vertical: 28,
              ),
              decoration: BoxDecoration(
                color: const Color(
                  0xFFF8F8FA,
                ),
                borderRadius: BorderRadius.circular(
                  12,
                ),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 26,
                    color: AppTheme.tertiaryTextColor,
                  ),
                  SizedBox(
                    height: 7,
                  ),
                  Text(
                    'لم تتم إضافة أي خيار بعد',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(
                    height: 3,
                  ),
                  Text(
                    'مثلاً: برتقال، خوخ، كاكاو أو موز',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            const _VariantsTableHeader(),
            ...List.generate(
              variants.length,
                  (
                  index,
                  ) {
                final variant = variants[index];

                return _VariantRow(
                  variant: variant,
                  onEdit: () {
                    onEdit(
                      index,
                    );
                  },
                  onDelete: () {
                    onDelete(
                      index,
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<ProductVariantModel?> _showVariantDialog({
    required String productId,
    ProductVariantModel? variant,
    required double defaultCost,
    required double defaultRepresentative,
    required double defaultWholesale,
    required double defaultRetail,
  }) async {
    final isEdit = variant != null;

    final barcodeController = TextEditingController(
      text: variant?.barcode ?? '',
    );

    final skuController = TextEditingController(
      text: variant?.sku ?? '',
    );

    final costController = TextEditingController(
      text: (variant?.costPrice ?? defaultCost)
          .toStringAsFixed(0),
    );

    final representativeController = TextEditingController(
      text: (variant?.representativePrice ??
          defaultRepresentative)
          .toStringAsFixed(0),
    );

    final wholesaleController = TextEditingController(
      text: (variant?.wholesalePrice ??
          defaultWholesale)
          .toStringAsFixed(0),
    );

    final retailController = TextEditingController(
      text: (variant?.retailPrice ?? defaultRetail)
          .toStringAsFixed(0),
    );

    final attributeDrafts = <_VariantAttributeDraft>[];

    if (variant != null && variant.attributes.isNotEmpty) {
      for (final entry in variant.attributes.entries) {
        attributeDrafts.add(
          _VariantAttributeDraft(
            key: entry.key,
            value: entry.value,
          ),
        );
      }
    } else {
      attributeDrafts.add(
        _VariantAttributeDraft(
          key: 'flavor',
          value: '',
        ),
      );
    }

    String? error;

    return showDialog<ProductVariantModel>(
      context: context,
      barrierDismissible: false,
      builder: (
          dialogContext,
          ) {
        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(
                  isEdit
                      ? 'تعديل الخيار'
                      : 'إضافة خيار',
                ),
                content: SizedBox(
                  width: 720,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'صفات الخيار',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(
                          height: 4,
                        ),
                        const Text(
                          'مثلاً: flavor = برتقال أو size = XL أو color = أسود.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color:
                            AppTheme.secondaryTextColor,
                          ),
                        ),
                        const SizedBox(
                          height: 12,
                        ),
                        ...List.generate(
                          attributeDrafts.length,
                              (
                              index,
                              ) {
                            final draft =
                            attributeDrafts[index];

                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: 10,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _DialogField(
                                      label: 'اسم الصفة',
                                      controller:
                                      draft.keyController,
                                      hintText:
                                      'مثلاً flavor',
                                    ),
                                  ),
                                  const SizedBox(
                                    width: 10,
                                  ),
                                  Expanded(
                                    child: _DialogField(
                                      label: 'القيمة',
                                      controller:
                                      draft.valueController,
                                      hintText:
                                      'مثلاً برتقال',
                                    ),
                                  ),
                                  const SizedBox(
                                    width: 8,
                                  ),
                                  Padding(
                                    padding:
                                    const EdgeInsets.only(
                                      top: 18,
                                    ),
                                    child: IconButton(
                                      tooltip: 'حذف الصفة',
                                      onPressed:
                                      attributeDrafts.length ==
                                          1
                                          ? null
                                          : () {
                                        setDialogState(
                                              () {
                                            attributeDrafts
                                                .removeAt(
                                              index,
                                            );
                                          },
                                        );
                                      },
                                      icon: const Icon(
                                        Icons
                                            .remove_circle_outline,
                                        size: 19,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(
                                  () {
                                attributeDrafts.add(
                                  _VariantAttributeDraft(
                                    key: '',
                                    value: '',
                                  ),
                                );
                              },
                            );
                          },
                          icon: const Icon(
                            Icons.add_rounded,
                            size: 17,
                          ),
                          label: const Text(
                            'إضافة صفة أخرى',
                          ),
                        ),
                        const SizedBox(
                          height: 18,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _DialogField(
                                label: 'باركود الخيار',
                                controller:
                                barcodeController,
                              ),
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            Expanded(
                              child: _DialogField(
                                label: 'SKU الخيار',
                                controller: skuController,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 18,
                        ),
                        const Text(
                          'أسعار الخيار',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _DialogField(
                                label: 'الكلفة',
                                controller: costController,
                                numeric: true,
                              ),
                            ),
                            const SizedBox(
                              width: 8,
                            ),
                            Expanded(
                              child: _DialogField(
                                label: 'المندوب',
                                controller:
                                representativeController,
                                numeric: true,
                              ),
                            ),
                            const SizedBox(
                              width: 8,
                            ),
                            Expanded(
                              child: _DialogField(
                                label: 'الجملة',
                                controller:
                                wholesaleController,
                                numeric: true,
                              ),
                            ),
                            const SizedBox(
                              width: 8,
                            ),
                            Expanded(
                              child: _DialogField(
                                label: 'التجزئة',
                                controller: retailController,
                                numeric: true,
                              ),
                            ),
                          ],
                        ),
                        if (error != null) ...[
                          const SizedBox(
                            height: 14,
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(
                              10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFFECEC,
                              ),
                              borderRadius:
                              BorderRadius.circular(
                                10,
                              ),
                            ),
                            child: Text(
                              error!,
                              style: const TextStyle(
                                fontSize: 11,
                                color:
                                AppTheme.dangerColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(
                        dialogContext,
                      ).pop();
                    },
                    child: const Text(
                      'إلغاء',
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final attributes =
                      <String, String>{};

                      for (final draft
                      in attributeDrafts) {
                        final key = draft.keyController.text
                            .trim();

                        final value = draft
                            .valueController.text
                            .trim();

                        if (key.isEmpty && value.isEmpty) {
                          continue;
                        }

                        if (key.isEmpty || value.isEmpty) {
                          setDialogState(
                                () {
                              error =
                              'أكمل اسم الصفة والقيمة.';
                            },
                          );
                          return;
                        }

                        if (attributes.containsKey(
                          key,
                        )) {
                          setDialogState(
                                () {
                              error =
                              'لا يمكن تكرار نفس الصفة.';
                            },
                          );
                          return;
                        }

                        attributes[key] = value;
                      }

                      if (attributes.isEmpty) {
                        setDialogState(
                              () {
                            error =
                            'أضف صفة واحدة على الأقل للخيار.';
                          },
                        );
                        return;
                      }

                      final result =
                      ProductVariantModel(
                        id: variant?.id ?? _uuid.v4(),
                        serverId: variant?.serverId,
                        productId:
                        variant?.productId ?? productId,
                        barcode:
                        barcodeController.text.trim(),
                        sku: skuController.text
                            .trim()
                            .isEmpty
                            ? null
                            : skuController.text.trim(),
                        attributes: attributes,
                        costPrice: _number(
                          costController.text,
                        ),
                        representativePrice: _number(
                          representativeController.text,
                        ),
                        wholesalePrice: _number(
                          wholesaleController.text,
                        ),
                        retailPrice: _number(
                          retailController.text,
                        ),
                        weightedAverageCost:
                        variant?.weightedAverageCost ??
                            0,
                        lastPurchasePrice:
                        variant?.lastPurchasePrice ??
                            0,
                        isActive:
                        variant?.isActive ?? true,
                        serverVersion:
                        variant?.serverVersion ?? 0,
                        createdAt: variant?.createdAt,
                        updatedAt: DateTime.now(),
                        deletedAt: null,
                      );

                      Navigator.of(
                        dialogContext,
                      ).pop(
                        result,
                      );
                    },
                    child: Text(
                      isEdit
                          ? 'حفظ التعديل'
                          : 'إضافة الخيار',
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

  String? _resolveCategoryId(
      ProductModel? product,
      ) {
    if (product == null) {
      return _categories.isNotEmpty
          ? _categories.first.id
          : null;
    }

    if (product.categoryId != null &&
        _categories.any(
              (category) =>
          category.id == product.categoryId,
        )) {
      return product.categoryId;
    }

    final name = product.categoryName.trim();

    if (name.isEmpty) {
      return _categories.isNotEmpty
          ? _categories.first.id
          : null;
    }

    for (final category in _categories) {
      if (category.nameAr.trim() == name) {
        return category.id;
      }
    }

    return _categories.isNotEmpty
        ? _categories.first.id
        : null;
  }

  String? _resolveUnitId(
      ProductModel? product,
      ) {
    if (product == null) {
      final piece = _units.where(
            (unit) => unit.nameAr.trim() == 'قطعة',
      );

      if (piece.isNotEmpty) {
        return piece.first.id;
      }

      return _units.isNotEmpty
          ? _units.first.id
          : null;
    }

    if (product.baseUnitId != null &&
        _units.any(
              (unit) => unit.id == product.baseUnitId,
        )) {
      return product.baseUnitId;
    }

    final name = product.unit.trim();

    for (final unit in _units) {
      if (unit.nameAr.trim() == name) {
        return unit.id;
      }
    }

    return _units.isNotEmpty
        ? _units.first.id
        : null;
  }

  Future<CategoryModel?> _askForCategoryName(
    BuildContext dialogContext,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: dialogContext,
      builder: (context) {
        return AlertDialog(
          title: const Text('صنف جديد'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'اسم الصنف',
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    final cleanName = name?.trim() ?? '';
    if (cleanName.isEmpty) {
      return null;
    }

    try {
      return await AppServices.categoriesRepository.createCategory(
        nameAr: cleanName,
      );
    } catch (error) {
      if (!mounted) {
        return null;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return null;
    }
  }

  Future<UnitModel?> _askForUnitName(
    BuildContext dialogContext,
  ) async {
    final nameController = TextEditingController();
    final symbolController = TextEditingController();
    final piecesController = TextEditingController(text: '1');
    String? parentId;
    final saved = await showDialog<bool>(
      context: dialogContext,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('وحدة قياس جديدة'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'اسم الوحدة',
                        hintText: 'مثلاً كارتون أو قطعة',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: symbolController,
                      decoration: const InputDecoration(
                        labelText: 'الرمز',
                        hintText: 'اختياري، مثل CTN',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      key: ValueKey(parentId),
                      initialValue: parentId,
                      decoration: const InputDecoration(
                        labelText: 'الوحدة الأصغر داخلها',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('هذه وحدة أساس'),
                        ),
                        for (final unit in _units.where((unit) => unit.isActive))
                          DropdownMenuItem<String?>(
                            value: unit.id,
                            child: Text(unit.nameAr),
                          ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          parentId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: piecesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'كم وحدة أصغر داخلها',
                        hintText: 'كارتون فيه 12 قطعة: اكتب 12',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'مثال: كيك، كارتون فيه 4 قطع. اختر قطعة واكتب 4. سعر القطعة في المنتج 5100، وسعر شراء الكارتون 20000 يُقسّم على 4 فيصير كلفة القطعة 5000.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
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
            );
          },
        );
      },
    );

    final name = nameController.text;
    final symbol = symbolController.text;
    final pieces = double.tryParse(piecesController.text.trim()) ?? 1;
    nameController.dispose();
    symbolController.dispose();
    piecesController.dispose();

    if (saved != true || name.trim().isEmpty) {
      return null;
    }

    try {
      return await AppServices.unitsRepository.createUnit(
        nameAr: name,
        symbol: symbol,
        parentUnitId: parentId,
        conversionFactor: pieces,
      );
    } catch (error) {
      if (!mounted) {
        return null;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
      return null;
    }
  }

  CategoryModel? _findCategory(
      String? id,
      ) {
    if (id == null) {
      return null;
    }

    for (final category in _categories) {
      if (category.id == id) {
        return category;
      }
    }

    return null;
  }

  UnitModel? _findUnit(
      String? id,
      ) {
    if (id == null) {
      return null;
    }

    for (final unit in _units) {
      if (unit.id == id) {
        return unit;
      }
    }

    return null;
  }

  Future<void> _confirmDelete(
      ProductModel product,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (
          dialogContext,
          ) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'حذف المنتج',
            ),
            content: Text(
              'هل تريد حذف "${product.name}"؟\n'
                  'سيتم تسجيل الحذف للمزامنة مع السيرفر.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop(
                    false,
                  );
                },
                child: const Text(
                  'إلغاء',
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop(
                    true,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  AppTheme.dangerColor,
                ),
                child: const Text(
                  'حذف',
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _repository.deleteProduct(
        product,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'تم حذف المنتج محلياً.',
      );

      await _syncNow();
    } catch (error) {
      _showMessage(
        _cleanError(
          error,
        ),
      );
    }
  }

  double _number(
      String value,
      ) {
    return double.tryParse(
      value
          .replaceAll(
        ',',
        '',
      )
          .trim(),
    ) ??
        0;
  }

  String _cleanError(
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

  void _showMessage(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
      ),
    );
  }
}

class _VariantAttributeDraft {
  final TextEditingController keyController;
  final TextEditingController valueController;

  _VariantAttributeDraft({
    required String key,
    required String value,
  })  : keyController = TextEditingController(
    text: key,
  ),
        valueController = TextEditingController(
          text: value,
        );
}

class _ProductTypeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ProductTypeButton({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        11,
      ),
      child: AnimatedContainer(
        duration: const Duration(
          milliseconds: 160,
        ),
        padding: const EdgeInsets.all(
          13,
        ),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white
              : Colors.transparent,
          borderRadius: BorderRadius.circular(
            11,
          ),
          border: selected
              ? Border.all(
            color: AppTheme.subtleBorderColor,
          )
              : null,
          boxShadow: selected
              ? [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: 0.035,
              ),
              blurRadius: 10,
              offset: const Offset(
                0,
                2,
              ),
            ),
          ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(
                  0xFF1D1D1F,
                )
                    : const Color(
                  0xFFEAEAED,
                ),
                borderRadius: BorderRadius.circular(
                  10,
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected
                    ? Colors.white
                    : AppTheme.secondaryTextColor,
              ),
            ),
            const SizedBox(
              width: 11,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppTheme.primaryTextColor
                          : AppTheme
                          .secondaryTextColor,
                    ),
                  ),
                  const SizedBox(
                    height: 2,
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color:
                      AppTheme.tertiaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

class _VariantsTableHeader extends StatelessWidget {
  const _VariantsTableHeader();

  @override
  Widget build(
      BuildContext context,
      ) {
    const style = TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w500,
      color: AppTheme.secondaryTextColor,
    );

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xFFF8F8FA,
        ),
        borderRadius: BorderRadius.circular(
          9,
        ),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'الخيار',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الباركود',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'SKU',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الكلفة',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'التجزئة',
              style: style,
            ),
          ),
          SizedBox(
            width: 80,
          ),
        ],
      ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  final ProductVariantModel variant;

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VariantRow({
    required this.variant,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
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
            flex: 3,
            child: Text(
              variant.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              variant.barcode.trim().isEmpty
                  ? '-'
                  : variant.barcode,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              variant.sku?.trim().isEmpty ?? true
                  ? '-'
                  : variant.sku!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatMoney(
                variant.costPrice,
              ),
              style: const TextStyle(
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatMoney(
                variant.retailPrice,
              ),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // FIX:
          // سابقاً كانت IconButton الافتراضية أكبر من عرض 75
          // وبالتالي كانت تسبب RenderFlex overflow.
          SizedBox(
            width: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    tooltip: 'تعديل',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onEdit,
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 17,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 4,
                ),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    tooltip: 'حذف',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 17,
                      color: AppTheme.dangerColor,
                    ),
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

class _ProductsHeader extends StatelessWidget {
  const _ProductsHeader();

  @override
  Widget build(
      BuildContext context,
      ) {
    const style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w500,
      color: AppTheme.secondaryTextColor,
    );

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
              'المنتج',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الباركود / الخيارات',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'التصنيف',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'سعر الكلفة',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'المندوب',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الجملة',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'التجزئة',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'المزامنة',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الحالة',
              style: style,
            ),
          ),
          SizedBox(
            width: 48,
          ),
        ],
      ),
    );
  }
}

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'https' || uri.scheme == 'http');
}

Widget _safeNetworkImage(
  String url, {
  required Widget fallback,
  double? width,
  double? height,
}) {
  if (url.startsWith('data:image/')) {
    final comma = url.indexOf(',');
    if (comma < 0) {
      return fallback;
    }
    try {
      return Image.memory(
        base64Decode(url.substring(comma + 1)),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } catch (_) {
      return fallback;
    }
  }
  if (!_isHttpUrl(url)) {
    return fallback;
  }
  return Image.network(
    url,
    width: width,
    height: height,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) => fallback,
  );
}

Widget _productThumb(ProductModel product, bool hasVariants) {
  final fallback = Icon(
    hasVariants ? Icons.account_tree_outlined : Icons.inventory_2_outlined,
    size: 17,
  );
  final url = product.imageUrl?.trim() ?? '';
  if (url.isEmpty) {
    return fallback;
  }
  return _safeNetworkImage(url, fallback: fallback, width: 38, height: 38);
}

class _ProductImageBox extends StatelessWidget {
  final String? imageUrl;

  const _ProductImageBox({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    final fallback = const Icon(Icons.image_outlined);
    final child = url.isEmpty
        ? fallback
        : _safeNetworkImage(url, fallback: fallback);
    return Container(
      width: 64,
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _ProductRow extends StatelessWidget {
  final ProductModel product;

  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _ProductRow({
    required this.product,
    required this.onOpen,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final synced =
        product.serverId != null &&
            product.serverId!.trim().isNotEmpty;

    final hasVariants =
        product.hasVariants &&
            product.variants.isNotEmpty;

    return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Container(
      height: 72,
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
                  child: _productThumb(product, hasVariants),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
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
                        hasVariants
                            ? '${product.variants.length} خيارات'
                            : (product.sku ?? '')
                            .trim()
                            .isNotEmpty
                            ? product.sku!
                            : product.unit,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: hasVariants
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: hasVariants
                              ? AppTheme.primaryTextColor
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
          Expanded(
            flex: 2,
            child: Text(
              hasVariants
                  ? '${product.variants.length} خيارات'
                  : product.barcode.trim().isEmpty
                  ? '-'
                  : product.barcode,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              product.categoryName.trim().isEmpty
                  ? '-'
                  : product.categoryName,
              style: const TextStyle(
                fontSize: 10.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatMoney(
                product.costPrice,
              ),
              style: const TextStyle(
                fontSize: 10.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatMoney(
                product.representativePrice,
              ),
              style: const TextStyle(
                fontSize: 10.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatMoney(
                product.wholesalePrice,
              ),
              style: const TextStyle(
                fontSize: 10.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatMoney(
                product.retailPrice,
              ),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: synced
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      synced
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_upload_outlined,
                      size: 13,
                      color: synced
                          ? const Color(
                        0xFF248A3D,
                      )
                          : const Color(
                        0xFFB26A00,
                      ),
                    ),
                    const SizedBox(
                      width: 5,
                    ),
                    Text(
                      synced
                          ? 'على السيرفر'
                          : 'بانتظار الرفع',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: synced
                            ? const Color(
                          0xFF248A3D,
                        )
                            : const Color(
                          0xFFB26A00,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: product.isActive
                      ? const Color(
                    0xFFEAF7EE,
                  )
                      : const Color(
                    0xFFF2F2F4,
                  ),
                  borderRadius: BorderRadius.circular(
                    20,
                  ),
                ),
                child: Text(
                  product.isActive
                      ? 'فعال'
                      : 'موقوف',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: product.isActive
                        ? const Color(
                      0xFF248A3D,
                    )
                        : AppTheme.secondaryTextColor,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: PopupMenuButton<String>(
              tooltip: 'خيارات',
              icon: const Icon(
                Icons.more_horiz_rounded,
                size: 19,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                    break;

                  case 'status':
                    onToggleActive();
                    break;

                  case 'delete':
                    onDelete();
                    break;
                }
              },
              itemBuilder: (
                  context,
                  ) {
                return [
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
                          product.isActive
                              ? Icons
                              .pause_circle_outline
                              : Icons
                              .play_circle_outline,
                          size: 17,
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Text(
                          product.isActive
                              ? 'إيقاف المنتج'
                              : 'تفعيل المنتج',
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 17,
                          color: AppTheme.dangerColor,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Text(
                          'حذف',
                          style: TextStyle(
                            color: AppTheme.dangerColor,
                          ),
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
        ),
        ),
    );////////////////////////////////////////////////////////////////
  }
}

class _DialogField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool numeric;
  final int maxLines;
  final String? hintText;
  final ValueChanged<String>? onChanged;

  const _DialogField({
    required this.label,
    required this.controller,
    this.numeric = false,
    this.maxLines = 1,
    this.hintText,
    this.onChanged,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 6,
        ),
        TextField(
          controller: controller,
          maxLines: maxLines,
          onChanged: onChanged,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(
            decimal: true,
          )
              : null,
          decoration: InputDecoration(
            hintText: hintText,
          ),
        ),
      ],
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final String hint;

  final List<DropdownMenuItem<String>> items;

  final ValueChanged<String?>? onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 6,
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(value),
          initialValue: value,
          isExpanded: true,
          items: items,
          hint: Text(
            hint,
          ),
          onChanged: onChanged,
        ),
      ],
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
      height: 125,
      padding: const EdgeInsets.all(
        17,
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
              mainAxisAlignment:
              MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: highlighted
                        ? const Color(
                      0xFFB8B8BD,
                    )
                        : AppTheme
                        .secondaryTextColor,
                  ),
                ),
                const SizedBox(
                  height: 6,
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
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

String _formatMoney(
    double value,
    ) {
  final text = value.toStringAsFixed(
    0,
  );

  final buffer = StringBuffer();

  for (var i = 0; i < text.length; i++) {
    if (i > 0 &&
        (text.length - i) % 3 == 0) {
      buffer.write(',');
    }

    buffer.write(
      text[i],
    );
  }

  return '${buffer.toString()} د.ع';
}