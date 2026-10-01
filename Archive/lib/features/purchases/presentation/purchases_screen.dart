import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/data/company_settings_repository.dart';
import '../../products/models/unit_model.dart';
import '../../suppliers/models/supplier_model.dart';
import '../../warehouses/models/warehouse_model.dart';
import '../data/supplier_folder.dart';
import '../models/purchase_model.dart';
import 'widgets/purchase_excel_grid.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({
    super.key,
  });

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final _repository = AppServices.purchasesRepository;
  final _productsRepository = AppServices.productsRepository;
  final _suppliersRepository = AppServices.suppliersRepository;
  final _warehousesRepository = AppServices.warehousesRepository;
  final _database = AppServices.database;

  final GlobalKey<PurchaseExcelGridState> _gridKey =
  GlobalKey<PurchaseExcelGridState>();

  List<UnitModel> _units = [];
  List<SupplierModel> _suppliers = [];
  int _supplierPage = 1;
  List<WarehouseModel> _warehouses = [];

  final List<PurchaseItemModel> _items = [];

  String? _selectedSupplierId;
  String? _selectedWarehouseId;
  final TextEditingController _supplierNameController = TextEditingController();
  final FocusNode _supplierFocus = FocusNode();
  final MenuController _supplierMenuController = MenuController();
  Timer? _supplierSearchTimer;
  bool _warehouseLocked = false;

  PurchasePaymentType _paymentType = PurchasePaymentType.cash;
  String _purchaseCurrency = 'IQD';
  double _usdRate = 0;

  final TextEditingController _discountController = TextEditingController(
    text: '0',
  );

  final TextEditingController _porterageController = TextEditingController(
    text: '0',
  );

  final TextEditingController _paidController = TextEditingController(
    text: '0',
  );

  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _discountController.addListener(_refreshSummary);
    _porterageController.addListener(_refreshSummary);
    _paidController.addListener(_refreshSummary);

    _loadData();
    _loadUsdRate();
    _loadUnits();
  }

  Future<void> _loadUsdRate() async {
    try {
      final company = await CompanySettingsRepository(
        apiClient: AppServices.apiClient,
      ).getCompany();
      final settings = company['settings'];
      final raw = settings is Map ? settings['usd_exchange_rate'] : null;
      final rate = double.tryParse(
            '${raw ?? ''}'.trim().replaceAll(',', ''),
          ) ??
          0;
      if (!mounted) {
        return;
      }
      setState(() {
        _usdRate = rate;
      });
    } catch (_) {}
  }

  double _typedToIqd(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '')) ?? 0;
    if (_purchaseCurrency == 'USD' && _usdRate > 0) {
      return value * _usdRate;
    }
    return value;
  }

  void _setPurchaseCurrency(String next) {
    if (next == 'USD' && _usdRate <= 0) {
      _showMessage('حدد سعر الدولار من الإعدادات أولاً.');
      return;
    }
    if (next == _purchaseCurrency) {
      return;
    }
    setState(() {
      _purchaseCurrency = next;
    });
  }

  @override
  void dispose() {
    _discountController.removeListener(_refreshSummary);
    _porterageController.removeListener(_refreshSummary);
    _paidController.removeListener(_refreshSummary);

    _discountController.dispose();
    _porterageController.dispose();
    _paidController.dispose();
    _notesController.dispose();
    _supplierSearchTimer?.cancel();
    _supplierFocus.dispose();
    _supplierNameController.dispose();

    super.dispose();
  }

  void _onSupplierTyped(String value) {
    if (_selectedSupplierId != null) {
      for (final supplier in _suppliers) {
        if (supplier.id == _selectedSupplierId && supplier.name == value) {
          return;
        }
      }
    }
    _selectedSupplierId = null;
    _supplierSearchTimer?.cancel();
    _supplierSearchTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _supplierPage = 1;
      });
      _loadSupplierPage();
    });
  }

  Future<String> _resolveSupplierId() async {
    final name = _supplierNameController.text.trim();
    if (name.isEmpty) {
      throw StateError('اكتب اسم المورد.');
    }
    if (_selectedSupplierId != null) {
      for (final supplier in _suppliers) {
        if (supplier.id == _selectedSupplierId && supplier.name.trim() == name) {
          return supplier.id;
        }
      }
    }
    final page = await _suppliersRepository.pageSuppliers(
      search: name,
      limit: 50,
    );
    for (final supplier in page.items) {
      if (supplier.name.trim() == name) {
        return supplier.id;
      }
    }
    final created = await _suppliersRepository.createSupplier(name: name);
    return created.id;
  }

  // ===========================================================================
  // DATA
  // ===========================================================================

  void _refreshSummary() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<PurchaseCatalogPage> _searchCatalog(
    String query,
    int limit,
    int offset,
  ) async {
    final products = await _productsRepository.searchProducts(
      query,
      limit: limit,
      offset: offset,
    );
    final ids = [for (final product in products) product.id];
    if (ids.isEmpty) {
      return const PurchaseCatalogPage(products: [], variants: []);
    }
    final variants = await (_database.select(_database.productVariants)
          ..where(
            (table) =>
                table.productId.isIn(ids) &
                table.deletedAt.isNull() &
                table.isActive.equals(true),
          ))
        .get();
    return PurchaseCatalogPage(products: products, variants: variants);
  }

  Future<void> _loadSupplierPage() async {
    try {
      final page = await _suppliersRepository.pageSuppliers(
        limit: kListPageSize,
        offset: (_supplierPage - 1) * kListPageSize,
        search: _supplierNameController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _suppliers = page.items
            .where((supplier) => supplier.isActive && supplier.deletedAt == null)
            .toList();
      });
      _reopenSupplierMenu();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(_errorMessage(error));
    }
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _suppliersRepository.pageSuppliers(
          limit: kListPageSize,
          offset: (_supplierPage - 1) * kListPageSize,
          search: _supplierNameController.text.trim(),
        ),
        _warehousesRepository.getWarehouses(),
      ]);

      final supplierPage = results[0] as ListPage<SupplierModel>;
      final suppliers = supplierPage.items;
      final warehouses = results[1] as List<WarehouseModel>;

      if (!mounted) {
        return;
      }

      final activeSuppliers = suppliers
          .where(
            (supplier) => supplier.isActive && supplier.deletedAt == null,
      )
          .toList();

      var activeWarehouses = warehouses
          .where(
            (warehouse) => warehouse.isActive && warehouse.deletedAt == null,
      )
          .toList();
      final stationWarehouseId =
          (await AuthStorage().readStationWarehouseId())?.trim() ?? '';
      final warehouseLocked = stationWarehouseId.isNotEmpty;
      if (warehouseLocked) {
        activeWarehouses = activeWarehouses
            .where((warehouse) => warehouse.id == stationWarehouseId)
            .toList();
      }

      setState(() {
        _suppliers = activeSuppliers;
        _warehouses = activeWarehouses;
        _warehouseLocked = warehouseLocked;

        if (_selectedWarehouseId == null ||
            !_warehouses.any(
                  (warehouse) => warehouse.id == _selectedWarehouseId,
            )) {
          if (_warehouses.isEmpty) {
            _selectedWarehouseId = null;
          } else {
            final mainWarehouses = _warehouses
                .where(
                  (warehouse) => warehouse.isMain,
            )
                .toList();

            _selectedWarehouseId = mainWarehouses.isNotEmpty
                ? mainWarehouses.first.id
                : _warehouses.first.id;
          }
        }

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
  // ITEMS
  // ===========================================================================

  void _addItem(
      PurchaseItemModel item,
      ) {
    final existingIndex = _items.indexWhere(
          (existing) =>
      existing.productId == item.productId &&
          existing.variantId == item.variantId,
    );

    setState(() {
      if (existingIndex >= 0) {
        final old = _items[existingIndex];

        _items[existingIndex] = old.copyWith(
          quantity: old.quantity + item.quantity,
        );
      } else {
        _items.add(item);
      }
    });
  }

  void _changeQuantity(
      int index,
      int quantity,
      ) {
    if (index < 0 || index >= _items.length || quantity < 0) {
      return;
    }

    final old = _items[index];

    setState(() {
      _items[index] = old.copyWith(
        quantity: quantity,
      );
    });
  }

  void _changeUnitCost(
      int index,
      double unitCost,
      ) {
    if (index < 0 || index >= _items.length || unitCost < 0) {
      return;
    }

    final old = _items[index];

    setState(() {
      _items[index] = old.copyWith(
        unitCost: unitCost,
      );
    });
  }

  void _changeItemDiscount(
      int index,
      double discountPercent,
      ) {
    if (index < 0 ||
        index >= _items.length ||
        discountPercent < 0 ||
        discountPercent > 100) {
      return;
    }

    final old = _items[index];

    setState(() {
      _items[index] = old.copyWith(
        discountPercent: discountPercent,
      );
    });
  }

  void _deleteItem(
      int index,
      ) {
    if (index < 0 || index >= _items.length) {
      return;
    }

    setState(() {
      _items.removeAt(index);
    });
  }

  Future<void> _loadUnits() async {
    try {
      final units = await AppServices.unitsRepository.getUnits();
      if (!mounted) {
        return;
      }
      setState(() {
        _units = units;
      });
    } catch (_) {}
  }

  Future<void> _cyclePurchaseUnit(int index) async {
    if (index < 0 || index >= _items.length) {
      return;
    }

    final item = _items[index];
    final product = await _productsRepository.getProductById(item.productId);
    if (!mounted || index >= _items.length) {
      return;
    }
    final baseId = product?.baseUnitId?.trim() ?? '';
    final related = _units.where((unit) {
      return unit.isActive &&
          (unit.id == baseId ||
              (baseId.isNotEmpty && unit.parentUnitId == baseId));
    }).toList();

    if (related.length < 2) {
      _showMessage(
        'أضف من المنتجات وحدة أكبر، مثل كارتون، وحدد كم قطعة داخلها.',
      );
      return;
    }

    final current = related.indexWhere((unit) => unit.id == item.unitId);
    final next = related[(current + 1) % related.length];
    final oldFactor = item.unitFactor <= 0 ? 1.0 : item.unitFactor;
    final newFactor =
        next.conversionFactor <= 1 ? 1.0 : next.conversionFactor;
    final ratio = newFactor / oldFactor;

    setState(() {
      _items[index] = item.copyWith(
        unitId: next.id,
        unitFactor: newFactor,
        unitCost: item.unitCost * ratio,
      );
    });
  }

  Future<void> _changePurchasePieces(int index, int pieces) async {
    if (index < 0 || index >= _items.length) {
      return;
    }

    final item = _items[index];
    final next = pieces < 1 ? 1.0 : pieces.toDouble();
    final old = item.unitFactor <= 0 ? 1.0 : item.unitFactor;
    if (next == old) {
      return;
    }

    final product = await _productsRepository.getProductById(item.productId);
    if (!mounted || index >= _items.length) {
      return;
    }
    final baseId = product?.baseUnitId?.trim() ?? '';
    String? cartonId;
    for (final unit in _units) {
      if (unit.isActive && baseId.isNotEmpty && unit.parentUnitId == baseId) {
        cartonId = unit.id;
        break;
      }
    }

    late PurchaseItemModel updated;
    if (old <= 1 && next > 1) {
      updated = item.copyWith(
        unitFactor: next,
        unitId: cartonId ?? item.unitId,
        unitCost: item.unitCost * next,
      );
    } else if (old > 1 && next <= 1) {
      updated = item.copyWith(
        unitFactor: 1,
        unitId: baseId.isEmpty ? item.unitId : baseId,
        unitCost: item.unitCost / old,
      );
    } else {
      updated = item.copyWith(
        unitFactor: next,
        unitId: cartonId ?? item.unitId,
      );
    }

    setState(() {
      _items[index] = updated;
    });
  }

  void _focusProductSearch() {
    _gridKey.currentState?.focusSearch();
  }

  // ===========================================================================
  // TOTALS
  // ===========================================================================

  double get _subtotal {
    final raw = _items.fold<double>(
      0,
          (sum, item) => sum + item.total,
    );
    if (_purchaseCurrency == 'USD' && _usdRate > 0) {
      return raw * _usdRate;
    }
    return raw;
  }

  double get _discount {
    return _typedToIqd(_discountController.text);
  }

  double get _porterage {
    final value = _typedToIqd(_porterageController.text);
    return value < 0 ? 0 : value;
  }

  double get _total {
    final value = _subtotal - _discount + _porterage;

    return value < 0 ? 0 : value;
  }

  double get _paid {
    switch (_paymentType) {
      case PurchasePaymentType.cash:
        return _total;

      case PurchasePaymentType.credit:
        return 0;

      case PurchasePaymentType.partial:
        return _typedToIqd(_paidController.text);
    }
  }

  double get _remaining {
    final value = _total - _paid;

    return value < 0 ? 0 : value;
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
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : Padding(
        padding: const EdgeInsets.fromLTRB(
          30,
          28,
          30,
          30,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(
              height: 20,
            ),

            // ===========================================================
            // بيانات الفاتورة بالأعلى
            // ===========================================================

            _buildInvoiceDataSection(),

            const SizedBox(
              height: 16,
            ),

            // ===========================================================
            // مواد الفاتورة بالأسفل
            // ===========================================================

            Expanded(
              child: _buildItemsSection(),
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
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'المشتريات',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryTextColor,
                ),
              ),
              SizedBox(
                height: 6,
              ),
              Text(
                'إنشاء فاتورة شراء وإضافة البضاعة إلى المخزن وتحديث حساب المورد.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _saving ? null : _loadData,
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
          _saving ? null : _focusProductSearch,
          icon: const Icon(
            Icons.add_rounded,
          ),
          label: const Text(
            'إضافة مادة',
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // INVOICE DATA - TOP SECTION
  // ===========================================================================

  Widget _buildInvoiceDataSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        18,
      ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(
                    10,
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              const Expanded(
                child: Text(
                  'بيانات الفاتورة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
              ),
              ChoiceChip(
                label: const Text('دينار'),
                selected: _purchaseCurrency == 'IQD',
                onSelected: _saving ? null : (_) => _setPurchaseCurrency('IQD'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('دولار'),
                selected: _purchaseCurrency == 'USD',
                onSelected: _saving ? null : (_) => _setPurchaseCurrency('USD'),
              ),
              const SizedBox(width: 12),
              Text(
                '${_items.length} مادة',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          LayoutBuilder(
            builder: (
                context,
                constraints,
                ) {
              if (constraints.maxWidth < 1050) {
                return _buildCompactInvoiceData();
              }

              return _buildDesktopInvoiceData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopInvoiceData() {
    return Column(
      children: [
        _buildSupplierField(),
        const SizedBox(height: 12),
        Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // =====================================================================
        // WAREHOUSE
        // =====================================================================

        Expanded(
          flex: 5,
          child: _buildWarehouseField(),
        ),

        const SizedBox(
          width: 12,
        ),

        // =====================================================================
        // SUBTOTAL
        // =====================================================================

        SizedBox(
          width: 145,
          child: _InvoiceMetric(
            title: 'المجموع',
            value: _formatPrice(
              _subtotal,
            ),
          ),
        ),

        const SizedBox(
          width: 12,
        ),

        // =====================================================================
        // DISCOUNT
        // =====================================================================

        SizedBox(
          width: 135,
          child: _buildInvoiceDiscountField(),
        ),

        const SizedBox(
          width: 12,
        ),

        SizedBox(
          width: 135,
          child: _buildInvoicePorterageField(),
        ),

        const SizedBox(
          width: 12,
        ),

        // =====================================================================
        // TOTAL
        // =====================================================================

        SizedBox(
          width: 155,
          child: _InvoiceMetric(
            title: 'الإجمالي',
            value: _formatPrice(
              _total,
            ),
            emphasized: true,
          ),
        ),

        const SizedBox(
          width: 14,
        ),

        // =====================================================================
        // PAYMENT TYPE
        // =====================================================================

        SizedBox(
          width: 265,
          child: _buildPaymentTypeField(),
        ),
      ],
        ),
      ],
    );
  }

  Widget _buildCompactInvoiceData() {
    return Column(
      children: [
        _buildSupplierField(),
        const SizedBox(
          height: 12,
        ),
        _buildWarehouseField(),
        const SizedBox(
          height: 14,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _InvoiceMetric(
                title: 'المجموع',
                value: _formatPrice(
                  _subtotal,
                ),
              ),
            ),
            const SizedBox(
              width: 10,
            ),
            SizedBox(
              width: 130,
              child: _buildInvoiceDiscountField(),
            ),
            const SizedBox(
              width: 10,
            ),
            SizedBox(
              width: 130,
              child: _buildInvoicePorterageField(),
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: _InvoiceMetric(
                title: 'الإجمالي',
                value: _formatPrice(
                  _total,
                ),
                emphasized: true,
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            SizedBox(
              width: 250,
              child: _buildPaymentTypeField(),
            ),
          ],
        ),
        if (_paymentType == PurchasePaymentType.partial) ...[
          const SizedBox(
            height: 12,
          ),
          _buildPartialPaymentRow(),
        ],
      ],
    );
  }

  void _selectSupplier(SupplierModel supplier) {
    _selectedSupplierId = supplier.id;
    _supplierNameController.value = TextEditingValue(
      text: supplier.name,
      selection: TextSelection.collapsed(offset: supplier.name.length),
    );
    setState(() {});
  }

  void _reopenSupplierMenu() {
    if (!_supplierMenuController.isOpen || !mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_supplierFocus.hasFocus) {
        return;
      }
      if (_supplierMenuController.isOpen) {
        _supplierMenuController.close();
      }
      _supplierMenuController.open();
    });
  }

  Future<void> _openSupplierFolder() {
    return showSupplierFolderDialog(
      context,
      _supplierNameController.text,
    );
  }

  // ===========================================================================
  // SUPPLIER
  // ===========================================================================

  Widget _buildSupplierField() {
    final names = _suppliers.take(12).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'المورد',
          style: TextStyle(
            fontSize: 10.5,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 6,
        ),
        Row(
          children: [
            Expanded(
              child: MenuAnchor(
                controller: _supplierMenuController,
                style: const MenuStyle(
                  maximumSize: WidgetStatePropertyAll(Size(640, 280)),
                ),
                alignmentOffset: const Offset(0, 6),
                menuChildren: [
                  if (names.isEmpty)
                    const MenuItemButton(
                      child: Text('لا يوجد مورد بهذا الاسم. اكتب الاسم كاملاً لحفظه.'),
                    )
                  else
                    for (final supplier in names)
                      MenuItemButton(
                        onPressed: () => _selectSupplier(supplier),
                        child: SizedBox(
                          width: 420,
                          child: Text(
                            supplier.name,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryTextColor,
                            ),
                          ),
                        ),
                      ),
                ],
                builder: (context, controller, child) {
                  return TextField(
                    controller: _supplierNameController,
                    focusNode: _supplierFocus,
                    enabled: !_saving,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryTextColor,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'اسم المورد',
                    ),
                    onTap: () {
                      if (!controller.isOpen) {
                        controller.open();
                      }
                    },
                    onChanged: (value) {
                      _onSupplierTyped(value);
                      if (!controller.isOpen) {
                        controller.open();
                      }
                    },
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'مجلد المورد',
              onPressed: _saving ? null : _openSupplierFolder,
              icon: const Icon(Icons.folder_open_rounded),
            ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // WAREHOUSE
  // ===========================================================================

  Widget _buildWarehouseField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'المخزن',
          style: TextStyle(
            fontSize: 10.5,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 6,
        ),
        if (_warehouses.isEmpty)
          Container(
            width: double.infinity,
            height: 46,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
            ),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(
              color: const Color(
                0xFFFFF4E5,
              ),
              borderRadius: BorderRadius.circular(
                10,
              ),
            ),
            child: const Text(
              'لا يوجد مخزن فعال',
              style: TextStyle(
                fontSize: 11,
              ),
            ),
          )
        else
          DropdownButtonFormField<String>(
            value: _selectedWarehouseId,
            isExpanded: true,
            decoration: const InputDecoration(
              hintText: 'اختر المخزن',
              isDense: true,
            ),
            items: _warehouses.map(
                  (warehouse) {
                return DropdownMenuItem<String>(
                  value: warehouse.id,
                  child: Text(
                    warehouse.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ).toList(),
            onChanged: _saving || _warehouseLocked
                ? null
                : (value) {
              setState(() {
                _selectedWarehouseId = value;
              });
            },
          ),
      ],
    );
  }

  // ===========================================================================
  // INVOICE DISCOUNT
  // ===========================================================================

  Widget _buildInvoiceDiscountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'خصم الفاتورة',
          style: TextStyle(
            fontSize: 10.5,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 6,
        ),
        SizedBox(
          height: 46,
          child: TextField(
            controller: _discountController,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              hintText: '0',
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoicePorterageField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الحمالية',
          style: TextStyle(
            fontSize: 10.5,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 6,
        ),
        SizedBox(
          height: 46,
          child: TextField(
            controller: _porterageController,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              hintText: '0',
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // PAYMENT TYPE
  // ===========================================================================

  Widget _buildPaymentTypeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'طريقة الدفع',
          style: TextStyle(
            fontSize: 10.5,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 6,
        ),
        SizedBox(
          height: 46,
          child: Row(
            children: PurchasePaymentType.values.map(
                  (type) {
                final selected = _paymentType == type;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                    ),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(
                          0,
                          46,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        backgroundColor: selected
                            ? AppTheme.primaryColor
                            : Colors.white,
                        foregroundColor: selected
                            ? Colors.white
                            : AppTheme.primaryTextColor,
                        side: BorderSide(
                          color: selected
                              ? AppTheme.primaryColor
                              : AppTheme.subtleBorderColor,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            10,
                          ),
                        ),
                      ),
                      onPressed: _saving
                          ? null
                          : () {
                        setState(() {
                          _paymentType = type;

                          if (type != PurchasePaymentType.partial) {
                            _paidController.text = '0';
                          }
                        });
                      },
                      child: Text(
                        type.title,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ).toList(),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // PARTIAL PAYMENT
  // ===========================================================================

  Widget _buildPartialPaymentRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        12,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xFFFAFAFB,
        ),
        borderRadius: BorderRadius.circular(
          12,
        ),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 190,
            child: TextField(
              controller: _paidController,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'المبلغ المدفوع',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(
            width: 18,
          ),
          Expanded(
            child: _InvoiceMetric(
              title: 'المدفوع',
              value: _formatPrice(
                _paid,
              ),
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: _InvoiceMetric(
              title: 'المتبقي',
              value: _formatPrice(
                _remaining,
              ),
              danger: _remaining > 0,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ITEMS
  // ===========================================================================

  Widget _buildItemsSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: PurchaseExcelGrid(
              key: _gridKey,
              products: const [],
              variants: const [],
              searchCatalog: _searchCatalog,
              items: _items,
              units: _units,
              enabled: !_saving,
              onAddItem: _addItem,
              onQuantityChanged: _changeQuantity,
              onUnitCostChanged: _changeUnitCost,
              onDiscountChanged: _changeItemDiscount,
              onDeleteItem: _deleteItem,
              onCycleUnit: (index) {
                _cyclePurchaseUnit(index);
              },
              onPiecesChanged: (index, pieces) {
                _changePurchasePieces(index, pieces);
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _notesController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                hintText: 'اكتب ملاحظة قائمة الشراء',
              ),
            ),
          ),

          // =============================================================
          // BOTTOM TOTAL + SAVE BAR
          // =============================================================

          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 14,
      ),
      decoration: const BoxDecoration(
        color: Color(
          0xFFFAFAFB,
        ),
        border: Border(
          top: BorderSide(
            color: AppTheme.subtleBorderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          // ===================================================================
          // TOTAL
          // ===================================================================

          _BottomSummaryValue(
            title: 'المجموع',
            value: _formatPrice(
              _subtotal,
            ),
          ),

          const SizedBox(
            width: 28,
          ),

          _BottomSummaryValue(
            title: 'الخصم',
            value: _formatPrice(
              _discount,
            ),
          ),

          const SizedBox(
            width: 28,
          ),

          _BottomSummaryValue(
            title: 'الإجمالي',
            value: _formatPrice(
              _total,
            ),
            emphasized: true,
          ),

          const SizedBox(
            width: 28,
          ),

          _BottomSummaryValue(
            title: 'المدفوع',
            value: _formatPrice(
              _paid,
            ),
          ),

          const SizedBox(
            width: 28,
          ),

          _BottomSummaryValue(
            title: 'المتبقي',
            value: _formatPrice(
              _remaining,
            ),
            danger: _remaining > 0,
          ),

          const Spacer(),

          // ===================================================================
          // SAVE
          // ===================================================================

          SizedBox(
            width: 220,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _items.isEmpty ||
                  _saving ||
                  _selectedSupplierId == null ||
                  _selectedWarehouseId == null
                  ? null
                  : _completePurchase,
              icon: _saving
                  ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(
                Icons.check_rounded,
              ),
              label: Text(
                _saving ? 'جاري الحفظ...' : 'حفظ فاتورة الشراء',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // COMPLETE PURCHASE
  // ===========================================================================

  Future<void> _completePurchase() async {
    final String supplierId;
    try {
      supplierId = await _resolveSupplierId();
    } catch (error) {
      _showMessage(_errorMessage(error));
      return;
    }
    final warehouseId = _selectedWarehouseId;

    if (warehouseId == null) {
      _showMessage(
        'اختر المخزن.',
      );

      return;
    }

    if (_items.isEmpty) {
      _showMessage(
        'أضف مادة واحدة على الأقل.',
      );

      return;
    }

    for (final item in _items) {
      if (item.variantId.trim().isEmpty) {
        _showMessage(
          'إحدى المواد لا تحتوي على خيار محدد.',
        );

        return;
      }

      if (item.unitId.trim().isEmpty) {
        _showMessage(
          'إحدى المواد غير مرتبطة بوحدة قياس.',
        );

        return;
      }

      if (item.quantity <= 0) {
        _showMessage(
          'اكتب عدد الكارتون.',
        );

        return;
      }

      if (item.unitCost < 0) {
        _showMessage(
          'إحدى المواد تحتوي على سعر شراء غير صحيح.',
        );

        return;
      }

      if (item.discountPercent < 0 || item.discountPercent > 100) {
        _showMessage(
          'إحدى المواد تحتوي على نسبة خصم غير صحيحة.',
        );

        return;
      }
    }

    if (_discount < 0) {
      _showMessage(
        'قيمة الخصم غير صحيحة.',
      );

      return;
    }

    if (_discount > _subtotal) {
      _showMessage(
        'الخصم أكبر من المجموع.',
      );

      return;
    }

    if (_paymentType == PurchasePaymentType.partial &&
        (_paid <= 0 || _paid >= _total)) {
      _showMessage(
        'بالدفع الجزئي يجب أن يكون المدفوع أكبر من صفر وأقل من الإجمالي.',
      );

      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final purchase = await _repository.createPurchase(
        supplierId: supplierId,
        warehouseId: warehouseId,
        items: List<PurchaseItemModel>.from(
          _items,
        ),
        discount: _discount,
        porterage: _porterage,
        paymentType: _paymentType,
        paid: _paid,
        note: _notesController.text.trim(),
        currency: _purchaseCurrency,
        exchangeRate: _purchaseCurrency == 'USD' ? _usdRate : 0,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;

        _items.clear();

        _discountController.text = '0';
        _porterageController.text = '0';
        _paidController.text = '0';
        _notesController.clear();

        _paymentType = PurchasePaymentType.cash;
        _purchaseCurrency = 'IQD';
      });

      await _loadData();

      if (!mounted) {
        return;
      }

      try {
        await AppServices.syncNow();
      } catch (_) {
        // الفاتورة محفوظة محلياً.
        // إذا فشل الاتصال سيعيد الـ Outbox المحاولة لاحقاً.
      }

      if (!mounted) {
        return;
      }

      showDialog<void>(
        context: context,
        builder: (
            context,
            ) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text(
                'تم حفظ فاتورة الشراء',
              ),
              content: Text(
                'رقم الفاتورة: ${purchase.invoiceNumber}\n'
                    'الإجمالي: ${_formatPrice(purchase.total)}\n'
                    'المتبقي للمورد: ${_formatPrice(purchase.remaining)}',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'تم',
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      _showMessage(
        _errorMessage(error),
      );
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
    if (_purchaseCurrency == 'USD' && _usdRate > 0) {
      final dollars = value / _usdRate;
      final negative = dollars < 0;
      return '${negative ? '-' : ''}${dollars.abs().toStringAsFixed(2)} \$';
    }

    final negative = value < 0;

    final text = value.abs().toStringAsFixed(
      0,
    );

    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) {
        buffer.write(',');
      }

      buffer.write(
        text[i],
      );
    }

    return '${negative ? '-' : ''}${buffer.toString()} د.ع';
  }
}

// =============================================================================
// INVOICE METRIC
// =============================================================================

class _InvoiceMetric extends StatelessWidget {
  final String title;
  final String value;

  final bool emphasized;
  final bool danger;

  const _InvoiceMetric({
    required this.title,
    required this.value,
    this.emphasized = false,
    this.danger = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: emphasized
            ? const Color(
          0xFF1C1C1E,
        )
            : const Color(
          0xFFF8F8FA,
        ),
        borderRadius: BorderRadius.circular(
          11,
        ),
        border: emphasized
            ? null
            : Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 9.5,
              color: emphasized
                  ? Colors.white.withValues(
                alpha: 0.65,
              )
                  : AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: emphasized ? 15 : 13,
              fontWeight: FontWeight.w700,
              color: danger
                  ? AppTheme.dangerColor
                  : emphasized
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
// BOTTOM SUMMARY VALUE
// =============================================================================

class _BottomSummaryValue extends StatelessWidget {
  final String title;
  final String value;

  final bool emphasized;
  final bool danger;

  const _BottomSummaryValue({
    required this.title,
    required this.value,
    this.emphasized = false,
    this.danger = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 9.5,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 3,
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasized ? 15 : 12.5,
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
            color: danger
                ? AppTheme.dangerColor
                : AppTheme.primaryTextColor,
          ),
        ),
      ],
    );
  }
}