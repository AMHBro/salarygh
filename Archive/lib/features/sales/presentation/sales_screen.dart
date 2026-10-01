import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/floor/floor_guard.dart';
import '../../../core/floor/floor_store.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/printing/print_preview.dart';
import '../../settings/data/company_settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../customers/models/customer_model.dart';
import '../../products/models/product_model.dart';
import '../../products/models/unit_model.dart';
import '../../products/models/product_variant_model.dart';
import '../../representatives/models/representative_model.dart';
import '../../warehouses/models/warehouse_model.dart';
import '../models/cart_item_model.dart';
import '../models/held_sale_model.dart';
import '../models/sale_model.dart';
import '../widgets/sales_excel_grid.dart';
import 'sales_history_screen.dart';


class SalesScreen extends StatefulWidget {
  const SalesScreen({
    super.key,
  });

  @override
  State<SalesScreen> createState() {
    return _SalesScreenState();
  }
}

class _SalesScreenState extends State<SalesScreen> {
  static const String _cashCustomerId =
      '__CASH_CUSTOMER__';

  static const String _noRepresentativeId =
      '__NO_REPRESENTATIVE__';

  final _productsRepository =
      AppServices.productsRepository;

  final _warehousesRepository =
      AppServices.warehousesRepository;

  final _inventoryRepository =
      AppServices.inventoryRepository;

  final _customersRepository =
      AppServices.customersRepository;

  final _representativesRepository =
      AppServices.representativesRepository;

  final _salesRepository =
      AppServices.salesRepository;

  final TextEditingController
  _productSearchController =
  TextEditingController();

  final TextEditingController
  _discountController =
  TextEditingController(
    text: '0',
  );

  final TextEditingController _porterageController =
      TextEditingController(text: '0');

  final TextEditingController
  _paidController =
  TextEditingController(
    text: '0',
  );

  final TextEditingController
  _customerNameController =
  TextEditingController();

  final TextEditingController
  _notesController =
  TextEditingController();

  bool _showCustomerSuggestions =
      false;

  final LayerLink _customerFieldLink = LayerLink();

  final OverlayPortalController _customerPortal =
      OverlayPortalController();

  final FocusNode _customerFocus = FocusNode();

  double _customerFieldWidth = 320;

  /// يمنع مزامنة الاسم أثناء تعبئة الحقل برمجياً.
  bool _suppressCustomerSync =
      false;

  List<ProductModel> _products = [];

  List<UnitModel> _units = [];

  List<WarehouseModel> _warehouses = [];

  List<CustomerModel> _suggestions = [];
  int _suggestionTotal = 0;
  int _suggestionPage = 1;
  CustomerModel? _pickedCustomer;

  List<RepresentativeModel>
  _representatives = [];

  /// Local Variant ID -> quantity.
  Map<String, double> _stockMap = {};

  final List<CartItemModel> _cart = [];

  String _selectedCustomerId =
      _cashCustomerId;

  String _selectedRepresentativeId =
      _noRepresentativeId;

  String? _selectedWarehouseId;
  bool _warehouseLocked = false;

  PriceType _selectedPriceType =
      PriceType.retail;

  PaymentType _paymentType =
      PaymentType.cash;

  /// IQD أو USD. أسعار المواد تبقى بالدينار ويُحوَّل المجموع بسعر الإعدادات.
  String _saleCurrency = 'IQD';

  double _usdRate = 0;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isHolding = false;

  /// عدد القوائم المخزنة محلياً في الانتظار.
  int _heldSalesCount = 0;

  /// إذا كانت القائمة الحالية مسترجعة من الانتظار
  /// نحتفظ بالـID حتى:
  ///
  /// 1. إعادة حفظها بالانتظار يحدث نفس القائمة.
  /// 2. عند إتمام البيع نحذف قائمة الانتظار.
  String? _activeHeldSaleId;

  @override
  void initState() {
    super.initState();

    _discountController.addListener(
      _refresh,
    );
    _porterageController.addListener(_refresh);

    _paidController.addListener(
      _refresh,
    );

    _customerFocus.addListener(_onCustomerFocus);
    _loadData();
    _loadUsdRate();
    _loadUnits();
  }

  void _onCustomerFocus() {
    if (_customerFocus.hasFocus) {
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || _customerFocus.hasFocus) {
        return;
      }

      setState(() {
        _showCustomerSuggestions = false;
      });
      _syncCustomerPortal();
    });
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

  double _cartonFactor(ProductModel product) {
    if (product.piecesPerCarton > 1) {
      return product.piecesPerCarton;
    }

    final baseId = product.baseUnitId?.trim() ?? '';
    for (final unit in _units) {
      if (unit.isActive &&
          baseId.isNotEmpty &&
          unit.parentUnitId == baseId &&
          unit.conversionFactor > 1) {
        return unit.conversionFactor;
      }
    }

    return 1;
  }

  Future<void> _changeSalePieces(int index, int pieces) async {
    if (index < 0 || index >= _cart.length) {
      return;
    }

    final item = _cart[index];
    final loose = pieces < 0 ? 0 : pieces;
    final factor = item.unitFactor <= 0 ? 1.0 : item.unitFactor;
    final variantId = item.variantId;
    if (variantId != null) {
      final available = _availableVariantStock(variantId);
      final nextPieces = item.quantity * factor + loose;
      if (nextPieces > available) {
        _showMessage('الكمية أكبر من المتوفر في المخزن.');
        return;
      }
      if (!await _serverAllows(variantId, nextPieces)) {
        return;
      }
    }

    setState(() {
      _cart[index] = item.copyWith(loosePieces: loose);
    });
  }

  @override
  void dispose() {
    _discountController.removeListener(
      _refresh,
    );
    _porterageController.removeListener(_refresh);

    _paidController.removeListener(
      _refresh,
    );

    _productSearchController.dispose();
    _discountController.dispose();
    _porterageController.dispose();
    _paidController.dispose();
    _customerFocus.removeListener(_onCustomerFocus);
    _customerFocus.dispose();
    _customerNameController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  void _refresh() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // ===========================================================================
  // DATA
  // ===========================================================================

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final results = await Future.wait([
        _warehousesRepository
            .getWarehouses(),
        _representativesRepository
            .getRepresentatives(),
        _salesRepository
            .getHeldSalesCount(),
      ]);

      final warehouses =
      results[0] as List<WarehouseModel>;

      final representatives =
      results[1]
      as List<RepresentativeModel>;

      final heldSalesCount =
      results[2] as int;

      var activeWarehouses =
      warehouses
          .where(
            (warehouse) =>
        warehouse.isActive &&
            warehouse.deletedAt ==
                null,
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

      final activeRepresentatives =
      representatives
          .where(
            (representative) =>
        representative.isActive &&
            representative.deletedAt ==
                null,
      )
          .toList();

      String? warehouseId =
          _selectedWarehouseId;

      if (warehouseId == null ||
          !activeWarehouses.any(
                (warehouse) =>
            warehouse.id ==
                warehouseId,
          )) {
        if (activeWarehouses.isNotEmpty) {
          final mainIndex =
          activeWarehouses.indexWhere(
                (warehouse) =>
            warehouse.isMain,
          );

          warehouseId =
          mainIndex >= 0
              ? activeWarehouses[
          mainIndex]
              .id
              : activeWarehouses
              .first.id;
        } else {
          warehouseId = null;
        }
      }

      Map<String, double> stockMap = {};

      if (warehouseId != null) {
        stockMap =
        await _inventoryRepository
            .getWarehouseStockMap(
          warehouseId,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _products = const [];

        _warehouses =
            activeWarehouses;
        _warehouseLocked = warehouseLocked;

        _representatives =
            activeRepresentatives;

        _selectedWarehouseId =
            warehouseId;

        _stockMap = stockMap;

        _heldSalesCount =
            heldSalesCount;

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

  Future<void> _changeWarehouse(
      String warehouseId,
      ) async {
    if (warehouseId ==
        _selectedWarehouseId) {
      return;
    }

    try {
      final stockMap =
      await _inventoryRepository
          .getWarehouseStockMap(
        warehouseId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedWarehouseId =
            warehouseId;

        _stockMap = stockMap;

        _cart.clear();

        /// إذا غيّر المخزن يدوياً بعد استرجاع
        /// قائمة انتظار، تصبح القائمة الحالية
        /// قائمة جديدة.
        _activeHeldSaleId = null;
      });

      _showMessage(
        'تم تغيير المخزن وإفراغ مواد القائمة.',
      );
    } catch (error) {
      _showMessage(
        _errorMessage(error),
      );
    }
  }

  // ===========================================================================
// SUMMARY
// ===========================================================================
  void _changeItemPrice({
    required int index,
    required PriceType type,
    required double value,
  }) {
    if (index < 0 ||
        index >= _cart.length) {
      return;
    }

    if (value < 0) {
      return;
    }

    final current =
    _cart[index];

    /// السعر المكتوب هنا يخص هذه القائمة فقط.
    /// أسعار الكلفة والجملة والمندوب والمفرد تبقى أساس المادة.
    setState(() {
      _cart[index] = current.copyWith(
        unitPriceOverride: value,
        priceType: type,
      );
    });
  }

  // ===========================================================================
  // SELECTED MODELS
  // ===========================================================================

  WarehouseModel?
  get _selectedWarehouse {
    final id =
        _selectedWarehouseId;

    if (id == null) {
      return null;
    }

    for (final warehouse
    in _warehouses) {
      if (warehouse.id == id) {
        return warehouse;
      }
    }

    return null;
  }

  CustomerModel? get _selectedCustomer {
    if (_selectedCustomerId ==
        _cashCustomerId) {
      return null;
    }

    if (_pickedCustomer?.id == _selectedCustomerId) {
      return _pickedCustomer;
    }

    for (final customer
    in _suggestions) {
      if (customer.id ==
          _selectedCustomerId) {
        return customer;
      }
    }

    return _pickedCustomer;
  }

  String get _invoiceCustomerName {
    final selected =
        _selectedCustomer;

    if (selected != null) {
      return selected.name;
    }

    final typed =
        _customerNameController
            .text
            .trim();

    if (typed.isEmpty ||
        typed == 'زبون نقدي') {
      return 'زبون نقدي';
    }

    return typed;
  }

  List<CustomerModel> get _customerSuggestions => _suggestions;

  Future<void> _reloadCustomerSuggestions() async {
    final query = _customerNameController.text.trim();
    final page = await _customersRepository.pageCustomers(
      search: query == 'زبون نقدي' ? '' : query,
      limit: 20,
      offset: (_suggestionPage - 1) * 20,
    );
    if (!mounted) {
      return;
    }
    CustomerModel? exact;
    if (query.isNotEmpty && query != 'زبون نقدي') {
      for (final customer in page.items) {
        if (customer.name.trim() == query) {
          exact = customer;
          break;
        }
      }
    }
    setState(() {
      _suggestions = page.items;
      _suggestionTotal = page.total;
      if (exact != null) {
        _pickedCustomer = exact;
        _selectedCustomerId = exact.id;
      } else if (_pickedCustomer?.name.trim() != query) {
        _pickedCustomer = null;
        if (_selectedCustomerId != _cashCustomerId) {
          _selectedCustomerId = _cashCustomerId;
        }
      }
    });
    _syncCustomerPortal();
  }

  String _composedSaleNotes() {
    final head = _notesController.text.trim();
    final lines = _cart
        .where((item) => item.notes.trim().isNotEmpty)
        .map((item) => '${item.product.name}: ${item.notes.trim()}')
        .join('\n');
    if (head.isEmpty) {
      return lines;
    }
    if (lines.isEmpty) {
      return head;
    }
    return '$head\n$lines';
  }

  PrintDocument _currentInvoiceDocument() {
    final now = DateTime.now();
    final figures = printMoneyFigures(
      invoiceTotal: _total,
      paid: _paidAmount,
      previousBalance: _previousCustomerDebt,
    );
    final dollars = _saleCurrency == 'USD' && _usdRate > 0;
    var cartons = 0.0;
    final rows = <List<String>>[];
    for (var index = 0; index < _cart.length; index++) {
      final item = _cart[index];
      cartons += item.quantity < 0 ? 0 : item.quantity.toDouble();
      rows.add(
        invoiceCells(
          index: index + 1,
          details: item.product.name,
          quantity: item.quantity.toDouble(),
          unitPrice: item.unitPrice,
          factor: item.unitFactor,
          loose: item.loosePieces.toDouble(),
          priceIsPerPiece: true,
          amount: item.total,
          note: item.notes,
        ),
      );
    }
    return PrintDocument(
      kind: 'قائمة بيع',
      title: 'قائمة بيع',
      number: '',
      party: _invoiceCustomerName,
      phone: _selectedCustomer?.phone ?? '',
      representative: _selectedRepresentative?.name ?? '',
      itemCodes: [
        for (final item in _cart)
          (item.product.sku ?? '').trim().isNotEmpty
              ? item.product.sku!.trim()
              : item.product.barcode,
      ],
      printedDate: printDateText(now),
      printedTime: printTimeText(now),
      documentType: _paymentType.title,
      lines: [
        if (_notesController.text.trim().isNotEmpty)
          'ملاحظات: ${_notesController.text.trim()}',
      ],
      columns: kInvoiceColumns,
      rows: rows,
      grandTotal: figures.invoiceTotal,
      discount: _discount,
      porterage: _porterage,
      cartonCount: cartons,
      previousIqd: figures.previousBalance,
      paidIqd: figures.paid,
      remainingIqd: figures.finalBalance,
      previousIqdLabel: 'الرصيد السابق',
      paidIqdLabel: 'المسدد',
      remainingIqdLabel: 'الرصيد النهائي',
      previousUsd: 0,
      paidUsd: dollars ? figures.paid / _usdRate : 0,
      remainingUsd: dollars ? figures.finalBalance / _usdRate : 0,
      totals: printMoneyLines(figures),
    );
  }

  PrintDocument _currentReceiptDocument() {
    final now = DateTime.now();
    final figures = printMoneyFigures(
      invoiceTotal: _total,
      paid: _paidAmount,
      previousBalance: _previousCustomerDebt,
    );
    final dollars = _saleCurrency == 'USD' && _usdRate > 0;
    return PrintDocument(
      kind: 'وصل',
      title: 'وصل قبض',
      party: _invoiceCustomerName,
      phone: _selectedCustomer?.phone ?? '',
      printedDate: printDateText(now),
      printedTime: printTimeText(now),
      documentTypeLabel: 'النوع',
      documentType: 'وصل قبض',
      lines: [
        'نوع الدفع: ${_paymentType.title}',
      ],
      grandTotal: figures.invoiceTotal,
      previousIqd: figures.previousBalance,
      paidIqd: figures.paid,
      remainingIqd: figures.finalBalance,
      previousIqdLabel: 'الرصيد السابق',
      paidIqdLabel: 'المسدد',
      remainingIqdLabel: 'الرصيد النهائي',
      paidUsd: dollars ? figures.paid / _usdRate : 0,
      remainingUsd: dollars ? figures.finalBalance / _usdRate : 0,
      totals: printMoneyLines(figures),
    );
  }

  void _writeCustomerName(
      String value,
      ) {
    _suppressCustomerSync =
    true;

    _customerNameController
        .value =
        TextEditingValue(
          text: value,
          selection:
          TextSelection
              .collapsed(
            offset:
            value.length,
          ),
        );

    _suppressCustomerSync =
    false;
  }

  void _syncCustomerFromText() {
    final typed =
        _customerNameController
            .text
            .trim();

    if (typed.isEmpty || typed == 'زبون نقدي') {
      _pickedCustomer = null;
      _selectedCustomerId = _cashCustomerId;
    }
    _suggestionPage = 1;
    _reloadCustomerSuggestions();

    final unmatched = typed.isEmpty ||
        typed == 'زبون نقدي' ||
        _pickedCustomer?.name.trim() != typed;
    if (unmatched &&
        _paymentType !=
            PaymentType.cash) {
      _paymentType =
          PaymentType.cash;

      _paidController.text =
      '0';
    }
  }

  void _clearCustomerField() {
    _writeCustomerName('');
    _pickedCustomer = null;

    _selectedCustomerId =
        _cashCustomerId;

    _showCustomerSuggestions =
    false;
    _customerPortal.hide();
  }

  void _restoreCustomerName(
      HeldSaleModel held, {
        required bool customerExists,
      }) {
    if (customerExists) {
      _writeCustomerName(
        held.customerName,
      );
    } else if (held.customerId ==
        null &&
        held.customerName !=
            'زبون نقدي') {
      _writeCustomerName(
        held.customerName,
      );
    } else {
      _writeCustomerName('');
    }

    _showCustomerSuggestions =
    false;
    _customerPortal.hide();
  }

  void _syncCustomerPortal() {
    final query = _customerNameController.text.trim();
    final showCash = query.isEmpty || 'زبون نقدي'.contains(query);
    final open = _showCustomerSuggestions &&
        (showCash || _customerSuggestions.isNotEmpty);
    if (open) {
      _customerPortal.show();
    } else {
      _customerPortal.hide();
    }
  }

  Widget _buildCustomerField() {
    final query =
        _customerNameController
            .text
            .trim();

    final suggestions =
        _customerSuggestions;

    final showCash =
        query.isEmpty ||
            'زبون نقدي'.contains(
              query,
            );

    final unmatched =
        query.isNotEmpty &&
            query != 'زبون نقدي' &&
            _selectedCustomer ==
                null;

    return _LabeledField(
      label: 'الزبون',
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment
            .stretch,
        children: [
          OverlayPortal(
            controller: _customerPortal,
            overlayChildBuilder: (context) {
              final width = _customerFieldWidth.isFinite && _customerFieldWidth > 0
                  ? _customerFieldWidth
                  : 320.0;
              // Positioned keeps the overlay from receiving tight full-screen
              // constraints. Without it the suggestion list stretches over the invoice.
              return Positioned(
                width: width,
                child: CompositedTransformFollower(
                  link: _customerFieldLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomCenter,
                  followerAnchor: Alignment.topCenter,
                  offset: const Offset(0, 4),
                  child: _customerSuggestionPanel(
                    showCash: showCash,
                    suggestions: suggestions,
                  ),
                ),
              );
            },
            child: CompositedTransformTarget(
              link: _customerFieldLink,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _customerFieldWidth = constraints.maxWidth;
                  return TextField(
                    controller: _customerNameController,
                    focusNode: _customerFocus,
                    enabled: !_isSaving && !_isHolding,
                    decoration: const InputDecoration(
                      hintText: 'اكتب اسم الزبون',
                      prefixIcon: Icon(
                        Icons.person_outline_rounded,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        _showCustomerSuggestions = true;
                      });
                      _reloadCustomerSuggestions();
                    },
                    onChanged: (_) {
                      if (_suppressCustomerSync) {
                        return;
                      }

                      setState(() {
                        _syncCustomerFromText();
                        _showCustomerSuggestions = true;
                      });
                      _syncCustomerPortal();
                    },
                  );
                },
              ),
            ),
          ),
          if (unmatched)
            const Padding(
              padding:
              EdgeInsets.only(
                top: 6,
              ),
              child: Text(
                'الاسم غير مسجل. البيع يبقى نقدياً بهذا الاسم، وللآجل اختر زبوناً من المقترحات.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme
                      .secondaryTextColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _customerSuggestionPanel({
    required bool showCash,
    required List<CustomerModel> suggestions,
  }) {
    Widget nameTile(String name, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Material(
      elevation: 6,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.borderColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListView(
          shrinkWrap: true,
          primary: false,
          padding: EdgeInsets.zero,
          children: [
            if (showCash)
              nameTile('زبون نقدي', () {
                _writeCustomerName('');
                setState(() {
                  _selectedCustomerId = _cashCustomerId;
                  _showCustomerSuggestions = false;
                  if (_paymentType != PaymentType.cash) {
                    _paymentType = PaymentType.cash;
                    _paidController.text = '0';
                  }
                });
                _syncCustomerPortal();
              }),
            for (final customer in suggestions)
              nameTile(customer.name, () {
                _writeCustomerName(customer.name);
                setState(() {
                  _pickedCustomer = customer;
                  _selectedCustomerId = customer.id;
                  _showCustomerSuggestions = false;
                });
                _syncCustomerPortal();
              }),
            ListPagination(
              page: _suggestionPage,
              totalItems: _suggestionTotal,
              pageSize: 20,
              onPageChanged: (page) {
                setState(() {
                  _suggestionPage = page;
                });
                _reloadCustomerSuggestions();
              },
            ),
          ],
          ),
        ),
      ),
    );
  }

  RepresentativeModel?
  get _selectedRepresentative {
    if (_selectedRepresentativeId ==
        _noRepresentativeId) {
      return null;
    }

    for (final representative
    in _representatives) {
      if (representative.id ==
          _selectedRepresentativeId) {
        return representative;
      }
    }

    return null;
  }

  // ===========================================================================
  // VARIANTS
  // ===========================================================================

  List<ProductVariantModel>
  _activeVariants(
      ProductModel product,
      ) {
    return product.variants
        .where(
          (variant) =>
      variant.isActive &&
          variant.deletedAt == null,
    )
        .toList();
  }

  ProductVariantModel? _variantById(
      ProductModel product,
      String? variantId,
      ) {
    if (variantId == null) {
      return null;
    }

    for (final variant
    in product.variants) {
      if (variant.id == variantId) {
        return variant;
      }
    }

    return null;
  }

  ProductVariantModel?
  _variantForCartItem(
      CartItemModel item,
      ) {
    return _variantById(
      item.product,
      item.variantId,
    );
  }

  double _availableVariantStock(
      String variantId,
      ) {
    return _stockMap[variantId] ?? 0;
  }

  Future<bool> _serverAllows(String variantId, double pieces) async {
    final warehouseId = _selectedWarehouseId;
    if (warehouseId == null) {
      return false;
    }
    final available = _availableVariantStock(variantId);
    final message = await FloorGuard.reserve(
      localVariantId: variantId,
      localWarehouseId: warehouseId,
      pieces: pieces,
      requireCloud: available > 0 && pieces + 0.001 >= available,
    );
    if (!mounted) {
      return false;
    }
    if (message != null) {
      _showMessage(message);
      return false;
    }
    return true;
  }

  double _productTotalStock(
      ProductModel product,
      ) {
    double total = 0;

    for (final variant
    in _activeVariants(product)) {
      total +=
          _availableVariantStock(
            variant.id,
          );
    }

    return total;
  }

  double _priceForVariant(
      ProductVariantModel variant,
      PriceType type,
      ) {
    switch (type) {
      case PriceType.cost:
        return variant.costPrice;

      case PriceType.representative:
        return variant
            .representativePrice;

      case PriceType.wholesale:
        return variant.wholesalePrice;

      case PriceType.retail:
        return variant.retailPrice;
    }
  }

  String _variantDisplayName(
      ProductVariantModel variant,
      ) {
    final name =
    variant.displayName.trim();

    if (name.isEmpty ||
        name == 'الخيار الرئيسي') {
      return 'الخيار الرئيسي';
    }

    return name;
  }


  // ===========================================================================
  // TOTALS
  // ===========================================================================

  double get _subtotal {
    return _cart.fold<double>(
      0.0,
          (sum, item) =>
      sum + item.total,
    );
  }

  double get _discount {
    return _typedToIqd(_discountController.text);
  }

  double get _porterage {
    final value = _typedToIqd(_porterageController.text);
    return value < 0 ? 0 : value;
  }

  double _typedToIqd(String text) {
    final value = double.tryParse(
          text.trim().replaceAll(',', ''),
        ) ??
        0.0;

    if (_saleCurrency == 'USD' && _usdRate > 0) {
      return value * _usdRate;
    }

    return value;
  }

  double get _total {
    final double value =
        _subtotal - _discount + _porterage;

    return value < 0.0
        ? 0.0
        : value;
  }

  double get _paidAmount {
    switch (_paymentType) {
      case PaymentType.cash:
        return _total;

      case PaymentType.credit:
        return 0.0;

      case PaymentType.partial:
        final double amount = _typedToIqd(
          _paidController.text,
        );

        if (amount < 0.0) {
          return 0.0;
        }

        if (amount > _total) {
          return _total;
        }

        return amount;
    }
  }

  double get _remainingAmount {
    final double value =
        _total - _paidAmount;

    return value < 0.0
        ? 0.0
        : value;
  }

  double get _previousCustomerDebt {
    return _selectedCustomer?.balance ??
        0.0;
  }

  double get _finalCustomerBalance {
    return _previousCustomerDebt +
        _remainingAmount;
  }

  double get _commissionPreview {
    final representative =
        _selectedRepresentative;

    if (representative == null) {
      return 0.0;
    }

    return _total *
        representative
            .commissionPercentage /
        100.0;
  }

  // ===========================================================================
  // PRICE TYPE
  // ===========================================================================

  List<PriceType> get _invoicePriceChoices {
    final representative = _selectedRepresentative;

    if (representative == null) {
      return PriceType.values;
    }

    const keys = {
      'wholesale': PriceType.wholesale,
      'representative': PriceType.representative,
      'retail': PriceType.retail,
      'cost': PriceType.cost,
    };

    final allowed = representative.allowedPrices
        .split(',')
        .map((part) => keys[part.trim()])
        .whereType<PriceType>()
        .toSet();

    const order = [
      PriceType.wholesale,
      PriceType.representative,
      PriceType.retail,
      PriceType.cost,
    ];

    final choices = [
      for (final type in order)
        if (allowed.contains(type)) type,
    ];

    if (choices.isEmpty) {
      return const [PriceType.representative];
    }

    return choices;
  }

  void _alignPriceToRepresentative() {
    final choices = _invoicePriceChoices;

    if (choices.contains(_selectedPriceType)) {
      return;
    }

    _changeSalePriceType(choices.first);
  }

  void _changeSalePriceType(
      PriceType type,
      ) {
    setState(() {
      _selectedPriceType =
          type;

      for (int i = 0;
      i < _cart.length;
      i++) {
        final item =
        _cart[i];

        _cart[i] =
            item.copyWith(
              priceType: type,

              /// نستخدم السعر الموجود داخل
              /// الـRow، مو سعر الـVariant الأصلي.
              unitPriceOverride:
              item.priceForType(
                type,
              ),
            );
      }
    });
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
      body: _isLoading
          ? const Center(
        child:
        CircularProgressIndicator(),
      )
          : Directionality(
        textDirection:
        TextDirection.rtl,
        child:
        SingleChildScrollView(
          padding:
          const EdgeInsets
              .fromLTRB(
            28,
            24,
            28,
            32,
          ),
          child: Column(
            children: [
              _buildTopHeader(),
              const SizedBox(
                height: 18,
              ),
              _buildSaleInformationCard(),
              const SizedBox(
                height: 14,
              ),
              _buildItemsCard(),
              const SizedBox(
                height: 14,
              ),
              _buildSummaryCard(),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildTopHeader() {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'قائمة البيع',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight:
                  FontWeight.w700,
                  letterSpacing: -0.6,
                  color: AppTheme
                      .primaryTextColor,
                ),
              ),
              SizedBox(
                height: 5,
              ),
              Text(
                'فاتورة بيع بالكميات والأسعار مع حساب الزبون والمندوب.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme
                      .secondaryTextColor,
                ),
              ),
            ],
          ),
        ),

        _HeaderButton(
          icon:
          Icons.add_rounded,
          title:
          'قائمة جديدة',
          primary: true,
          onPressed:
          _isSaving || _isHolding
              ? null
              : _resetSale,
        ),

        const SizedBox(
          width: 8,
        ),

        _HeaderButton(
          icon:
          Icons.schedule_rounded,
          title:
          'قوائم الانتظار ($_heldSalesCount)',
          onPressed:
          _isSaving || _isHolding
              ? null
              : _openHeldSales,
        ),

        const SizedBox(
          width: 8,
        ),

        _HeaderButton(
          icon: Icons
              .receipt_long_outlined,
          title:
          'سجل القوائم',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) {
                  return const SalesHistoryScreen();
                },
              ),
            );
          },
        ),

        const SizedBox(
          width: 8,
        ),

        _HeaderButton(
          icon:
          Icons.refresh_rounded,
          title:
          'تحديث',
          onPressed:
          _isSaving || _isHolding
              ? null
              : _loadData,
        ),
      ],
    );
  }

  // ===========================================================================
  // SALE INFORMATION
  // ===========================================================================

  Widget _buildSaleInformationCard() {
    return _SectionCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child:
                _LabeledField(
                  label:
                  'رقم الفاتورة',
                  child:
                  const _ReadOnlyBox(
                    value:
                    'تلقائي',
                    icon:
                    Icons.tag_rounded,
                  ),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                flex: 2,
                child:
                _LabeledField(
                  label: 'التاريخ',
                  child:
                  _ReadOnlyBox(
                    value:
                    _formatDate(
                      DateTime.now(),
                    ),
                    icon: Icons
                        .calendar_today_outlined,
                  ),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                flex: 5,
                child:
                _LabeledField(
                  label: _selectedRepresentative == null
                      ? 'نوع القائمة'
                      : 'سعر هذه القائمة',
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children:
                    _invoicePriceChoices
                        .map(
                          (type) {
                        return _ChoiceButton(
                          title:
                          type.title,
                          selected:
                          _selectedPriceType ==
                              type,
                          onTap: () {
                            _changeSalePriceType(
                              type,
                            );
                          },
                        );
                      },
                    ).toList(),
                  ),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              const Expanded(
                flex: 2,
                child:
                _LabeledField(
                  label: 'العملة',
                  child:
                  _ReadOnlyBox(
                    value:
                    'دينار عراقي',
                    icon: Icons
                        .payments_outlined,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 18,
          ),

          Row(
            crossAxisAlignment:
            CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 4,
                child:
                _buildCustomerField(),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                flex: 3,
                child:
                _LabeledField(
                  label:
                  'نوع الحساب',
                  child: Row(
                    children: [
                      Expanded(
                        child:
                        _PaymentChoice(
                          title:
                          'نقد',
                          selected:
                          _paymentType ==
                              PaymentType
                                  .cash,
                          onTap: () {
                            setState(
                                  () {
                                _paymentType =
                                    PaymentType
                                        .cash;
                              },
                            );
                          },
                        ),
                      ),

                      const SizedBox(
                        width: 6,
                      ),

                      Expanded(
                        child:
                        _PaymentChoice(
                          title:
                          'آجل',
                          selected:
                          _paymentType ==
                              PaymentType
                                  .credit,
                          onTap: () {
                            if (_selectedCustomer ==
                                null) {
                              _showMessage(
                                'يجب اختيار زبون مسجل للبيع الآجل.',
                              );

                              return;
                            }

                            setState(
                                  () {
                                _paymentType =
                                    PaymentType
                                        .credit;
                              },
                            );
                          },
                        ),
                      ),

                      const SizedBox(
                        width: 6,
                      ),

                      Expanded(
                        child:
                        _PaymentChoice(
                          title:
                          'جزئي',
                          selected:
                          _paymentType ==
                              PaymentType
                                  .partial,
                          onTap: () {
                            if (_selectedCustomer ==
                                null) {
                              _showMessage(
                                'يجب اختيار زبون مسجل للبيع الجزئي.',
                              );

                              return;
                            }

                            setState(
                                  () {
                                _paymentType =
                                    PaymentType
                                        .partial;
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                flex: 3,
                child:
                _LabeledField(
                  label: 'المندوب',
                  child:
                  DropdownButtonFormField<
                      String>(
                    value:
                    _selectedRepresentativeId,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<
                          String>(
                        value:
                        _noRepresentativeId,
                        child: Text(
                          'بدون مندوب',
                        ),
                      ),
                      ..._representatives.map(
                            (representative) {
                          return DropdownMenuItem<
                              String>(
                            value:
                            representative.id,
                            child: Text(
                              representative
                                  .name,
                              overflow:
                              TextOverflow
                                  .ellipsis,
                            ),
                          );
                        },
                      ),
                    ],
                    onChanged:
                    _isSaving ||
                        _isHolding
                        ? null
                        : (value) {
                      if (value ==
                          null) {
                        return;
                      }

                      setState(
                            () {
                          _selectedRepresentativeId =
                              value;
                        },
                      );

                      _alignPriceToRepresentative();
                    },
                  ),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                flex: 3,
                child:
                _LabeledField(
                  label: 'المخزن',
                  child:
                  DropdownButtonFormField<
                      String>(
                    value:
                    _selectedWarehouseId,
                    isExpanded: true,
                    hint: const Text(
                      'اختر المخزن',
                    ),
                    items:
                    _warehouses.map(
                          (warehouse) {
                        return DropdownMenuItem<
                            String>(
                          value:
                          warehouse.id,
                          child: Text(
                            warehouse.name,
                            overflow:
                            TextOverflow
                                .ellipsis,
                          ),
                        );
                      },
                    ).toList(),
                    onChanged:
                    _warehouseLocked ||
                        _isSaving ||
                        _isHolding
                        ? null
                        : (value) {
                      if (value ==
                          null) {
                        return;
                      }

                      _changeWarehouse(
                        value,
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                flex: 2,
                child:
                _LabeledField(
                  label: 'الحمالية',
                  child: TextField(
                    controller: _porterageController,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    enabled: !_isSaving && !_isHolding,
                    decoration: const InputDecoration(
                      hintText: '0',
                    ),
                  ),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                flex: 2,
                child:
                _LabeledField(
                  label: 'الخصم',
                  child: TextField(
                    controller:
                    _discountController,
                    textAlign:
                    TextAlign.center,
                    keyboardType:
                    TextInputType
                        .number,
                    enabled:
                    !_isSaving &&
                        !_isHolding,
                    decoration:
                    const InputDecoration(
                      hintText: '0',
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 12,
          ),

          _LabeledField(
            label: 'ملاحظات',
            child: TextField(
              controller: _notesController,
              enabled: !_isSaving && !_isHolding,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'ملاحظات القائمة',
              ),
            ),
          ),

          if (_selectedCustomer !=
              null) ...[
            const SizedBox(
              height: 14,
            ),
            Container(
              width:
              double.infinity,
              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              decoration:
              BoxDecoration(
                color:
                const Color(
                  0xFFF7F7F8,
                ),
                borderRadius:
                BorderRadius
                    .circular(
                  12,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons
                        .account_balance_wallet_outlined,
                    size: 17,
                    color: AppTheme
                        .secondaryTextColor,
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  const Text(
                    'الرصيد السابق على الزبون:',
                    style:
                    TextStyle(
                      fontSize: 11.5,
                      color: AppTheme
                          .secondaryTextColor,
                    ),
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  Text(
                    _formatPrice(
                      _selectedCustomer!
                          .balance,
                    ),
                    style:
                    TextStyle(
                      fontSize: 12,
                      fontWeight:
                      FontWeight
                          .w700,
                      color: _selectedCustomer!
                          .balance >
                          0
                          ? AppTheme
                          .dangerColor
                          : AppTheme
                          .primaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_activeHeldSaleId !=
              null) ...[
            const SizedBox(
              height: 14,
            ),
            Container(
              width:
              double.infinity,
              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              decoration:
              BoxDecoration(
                color:
                const Color(
                  0xFFFFF8E7,
                ),
                borderRadius:
                BorderRadius
                    .circular(
                  12,
                ),
                border:
                Border.all(
                  color:
                  const Color(
                    0xFFFFE4A6,
                  ),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons
                        .schedule_rounded,
                    size: 17,
                  ),
                  SizedBox(
                    width: 8,
                  ),
                  Text(
                    'هذه القائمة مسترجعة من قوائم الانتظار.',
                    style:
                    TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                      FontWeight
                          .w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // ITEMS CARD
  // ===========================================================================

  // ===========================================================================
// ITEMS CARD
// ===========================================================================
// ===========================================================================
// ITEMS CARD
// ===========================================================================

  Widget _buildItemsCard() {
    return _SectionCard(
      padding: EdgeInsets.zero,
      child: SalesExcelGrid(
        products: _products,
        searchProducts: (query, limit, offset) {
          return _productsRepository.searchProducts(
            query,
            limit: limit,
            offset: offset,
          );
        },
        items: _cart,
        stockMap: _stockMap,
        selectedPriceType:
        _selectedPriceType,
        enabled:
        !_isSaving &&
            !_isHolding &&
            _selectedWarehouseId != null,

        // ===============================================================
        // ADD ITEM
        // ===============================================================

        onAddItem: (item) async {
          final variantId =
              item.variantId;

          if (variantId == null) {
            return;
          }

          final available =
          _availableVariantStock(
            variantId,
          );

          final factor = item.unitFactor <= 0 ? 1.0 : item.unitFactor;

          if (await FloorStore.isLocked(
            AppServices.database,
            variantId,
          )) {
            _showMessage(
              'هذه المادة مقفلة بعد بيع متعارض. تنتظر مراجعة المدير.',
            );
            return;
          }

          if (available < 1) {
            _showMessage(
              'هذه المادة غير متوفرة في المخزن.',
            );

            return;
          }

          final existingIndex =
          _cart.indexWhere(
                (current) =>
            current.variantId ==
                variantId,
          );

          if (existingIndex >= 0) {
            final current =
            _cart[existingIndex];

            final newQuantity =
                current.quantity + 1;

            if (newQuantity * factor + current.loosePieces >
                available) {
              _showMessage(
                'لا توجد كمية إضافية متوفرة من هذه المادة.',
              );

              return;
            }
            if (!await _serverAllows(
              variantId,
              newQuantity * factor + current.loosePieces,
            )) {
              return;
            }

            setState(() {
              _cart[existingIndex] =
                  current.copyWith(
                    quantity:
                    newQuantity,
                  );
            });

            return;
          }

          final addedFactor = item.unitFactor <= 0 ? 1.0 : item.unitFactor;
          final addedPieces = item.quantity * addedFactor + item.loosePieces;
          if (addedPieces > 0 &&
              !await _serverAllows(variantId, addedPieces)) {
            return;
          }
          setState(() {
            _cart.add(item);
          });
        },

        // ===============================================================
        // QUANTITY
        // ===============================================================

        onQuantityChanged:
            (
            index,
            quantity,
            ) {
          _changeQuantity(
            index,
            quantity,
          );
        },

        // ===============================================================
        // PRICE
        // ===============================================================

        onPriceChanged:
            (
            index,
            type,
            price,
            ) {
          _changeItemPrice(
            index: index,
            type: type,
            value: price,
          );
        },

        // ===============================================================
        // DELETE
        // ===============================================================

        onDeleteItem: (index) {
          if (index < 0 ||
              index >=
                  _cart.length) {
            return;
          }

          setState(() {
            _cart.removeAt(
              index,
            );
          });
        },
        onNotesChanged: (index, notes) {
          if (index < 0 || index >= _cart.length) {
            return;
          }
          _cart[index] = _cart[index].copyWith(notes: notes);
        },
        onPiecesChanged: _changeSalePieces,
      ),
    );
  }

  // ===========================================================================
  // VARIANT PICKER
  // ===========================================================================

  Future<void> _openVariantPicker(
      ProductModel product,
      ) async {
    final variants =
    _activeVariants(
      product,
    );

    if (variants.isEmpty) {
      _showMessage(
        'لا توجد خيارات متاحة لهذه المادة.',
      );

      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection:
          TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              'اختيار خيار - ${product.name}',
            ),
            content: SizedBox(
              width: 620,
              height: 420,
              child:
              ListView.separated(
                itemCount:
                variants.length,
                separatorBuilder:
                    (_, __) {
                  return const Divider(
                    height: 1,
                  );
                },
                itemBuilder: (
                    context,
                    index,
                    ) {
                  final variant =
                  variants[
                  index];

                  final stock =
                  _availableVariantStock(
                    variant.id,
                  );

                  final price =
                  _priceForVariant(
                    variant,
                    _selectedPriceType,
                  );

                  return ListTile(
                    enabled:
                    stock > 0,
                    leading:
                    Container(
                      width: 42,
                      height: 42,
                      alignment:
                      Alignment
                          .center,
                      decoration:
                      BoxDecoration(
                        color:
                        const Color(
                          0xFFF5F5F7,
                        ),
                        borderRadius:
                        BorderRadius
                            .circular(
                          10,
                        ),
                      ),
                      child:
                      const Icon(
                        Icons
                            .tune_rounded,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      _variantDisplayName(
                        variant,
                      ),
                    ),
                    subtitle: Text(
                      stock <= 0
                          ? 'نافد من المخزن'
                          : 'المتوفر ${_formatQuantity(stock)} • ${_formatPrice(price)}',
                    ),
                    trailing:
                    stock <= 0
                        ? const Icon(
                      Icons
                          .block_rounded,
                      size:
                      19,
                    )
                        : const Icon(
                      Icons
                          .add_circle_outline_rounded,
                    ),
                    onTap:
                    stock <= 0
                        ? null
                        : () {
                      Navigator.pop(
                        dialogContext,
                      );

                      _addVariantToCart(
                        product,
                        variant,
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
                child:
                const Text(
                  'رجوع',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // CART
  // ===========================================================================

  Future<void> _addVariantToCart(
      ProductModel product,
      ProductVariantModel variant,
      ) async {
    final unitId =
    product.baseUnitId?.trim();

    if (unitId == null ||
        unitId.isEmpty) {
      _showMessage(
        'هذا المنتج لا يحتوي على وحدة أساسية، لذلك لا يمكن إضافته للبيع.',
      );

      return;
    }

    if (!variant.isActive ||
        variant.deletedAt != null) {
      _showMessage(
        'هذا الخيار غير فعال.',
      );

      return;
    }

    if (await FloorStore.isLocked(
      AppServices.database,
      variant.id,
    )) {
      _showMessage(
        'هذه المادة مقفلة بعد بيع متعارض. تنتظر مراجعة المدير.',
      );
      return;
    }

    final available =
    _availableVariantStock(
      variant.id,
    );

    if (available < 1) {
      _showMessage(
        'هذا الخيار غير متوفر في المخزن.',
      );

      return;
    }

    final existingIndex =
    _cart.indexWhere(
          (item) =>
      item.variantId ==
          variant.id,
    );

    if (existingIndex >= 0) {
      final current =
      _cart[
      existingIndex];

      final factor = current.unitFactor <= 0
          ? 1.0
          : current.unitFactor;
      if ((current.quantity + 1) * factor +
              current.loosePieces >
          available) {
        _showMessage(
          'لا توجد كمية إضافية متوفرة من هذا الخيار.',
        );

        return;
      }
      if (!await _serverAllows(
        variant.id,
        (current.quantity + 1) * factor + current.loosePieces,
      )) {
        return;
      }

      setState(() {
        _cart[existingIndex] =
            current.copyWith(
              quantity:
              current.quantity + 1,
            );
      });

      return;
    }

    final unitPrice =
    _priceForVariant(
      variant,
      _selectedPriceType,
    );

    setState(() {
      _cart.add(
        CartItemModel(
          product: product,
          variantId:
          variant.id,
          unitId: unitId,
          unitFactor: _cartonFactor(product),
          quantity: 0,
          loosePieces: 0,
          priceType:
          _selectedPriceType,
          unitPriceOverride:
          unitPrice,

          costPriceOverride:
          variant.costPrice,

          representativePriceOverride:
          variant
              .representativePrice,

          wholesalePriceOverride:
          variant
              .wholesalePrice,

          retailPriceOverride:
          variant.retailPrice,
        ),
      );
    });
  }

  Future<void> _changeQuantity(
      int index,
      int quantity,
      ) async {
    if (index < 0 ||
        index >= _cart.length) {
      return;
    }

    if (quantity < 0) {
      return;
    }

    final item =
    _cart[index];

    final variantId =
        item.variantId;

    if (variantId == null) {
      _showMessage(
        'هذا السطر لا يحتوي على Variant صحيح.',
      );

      return;
    }

    final available =
    _availableVariantStock(
      variantId,
    );

    final factor = item.unitFactor <= 0 ? 1.0 : item.unitFactor;
    final nextPieces = quantity * factor + item.loosePieces;
    if (nextPieces > available) {
      _showMessage(
        'الكمية المطلوبة أكبر من المتوفر في المخزن.',
      );

      return;
    }
    if (!await _serverAllows(variantId, nextPieces)) {
      return;
    }

    setState(() {
      _cart[index] =
          item.copyWith(
            quantity: quantity,
          );
    });
  }




  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  Widget _buildSummaryCard() {
    return _SectionCard(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'ملخص الحساب',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
              ),
              ChoiceChip(
                label: const Text('دينار'),
                selected: _saleCurrency == 'IQD',
                onSelected: _isSaving
                    ? null
                    : (_) => _setSaleCurrency('IQD'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('دولار'),
                selected: _saleCurrency == 'USD',
                onSelected: _isSaving
                    ? null
                    : (_) => _setSaleCurrency('USD'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'عدد الكارتون: ${_cart.fold<int>(0, (sum, item) => sum + (item.quantity < 0 ? 0 : item.quantity))}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_saleCurrency == 'USD')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'سعر الدولار من الإعدادات: ${_usdRate.toStringAsFixed(0)} دينار',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ),

          const SizedBox(
            height: 16,
          ),

          Row(
            crossAxisAlignment:
            CrossAxisAlignment
                .start,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding:
                  const EdgeInsets
                      .all(
                    20,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    const Color(
                      0xFF111111,
                    ),
                    borderRadius:
                    BorderRadius
                        .circular(
                      16,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      const Text(
                        'مجموع القائمة',
                        style:
                        TextStyle(
                          fontSize:
                          11.5,
                          color:
                          Colors
                              .white70,
                        ),
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      Text(
                        _formatSaleMoney(
                          _total,
                        ),
                        style:
                        const TextStyle(
                          fontSize: 26,
                          fontWeight:
                          FontWeight
                              .w700,
                          color:
                          Colors
                              .white,
                        ),
                      ),
                      const SizedBox(
                        height: 6,
                      ),
                      Text(
                        'قبل الخصم: ${_formatSaleMoney(_subtotal)} · الحمالية: ${_formatSaleMoney(_porterage)}',
                        style:
                        const TextStyle(
                          fontSize:
                          10.5,
                          color:
                          Colors
                              .white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                flex: 7,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child:
                          _SummaryMetric(
                            title:
                            'الدين السابق على الزبون',
                            value:
                            _formatSaleMoney(
                              _previousCustomerDebt,
                            ),
                            danger:
                            _previousCustomerDebt >
                                0,
                          ),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        Expanded(
                          child:
                          _SummaryMetric(
                            title:
                            'مجموع القائمة + الدين السابق',
                            value:
                            _formatSaleMoney(
                              _total +
                                  _previousCustomerDebt,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        Expanded(
                          child:
                          _SummaryMetric(
                            title:
                            'المبلغ المسدد',
                            value:
                            _formatSaleMoney(
                              _paidAmount,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    Container(
                      width:
                      double.infinity,
                      padding:
                      const EdgeInsets
                          .symmetric(
                        horizontal:
                        16,
                        vertical:
                        14,
                      ),
                      decoration:
                      BoxDecoration(
                        color:
                        const Color(
                          0xFFFAFAFB,
                        ),
                        borderRadius:
                        BorderRadius
                            .circular(
                          13,
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
                            child:
                            Text(
                              'المتبقي النهائي على الزبون',
                              style:
                              TextStyle(
                                fontSize:
                                11.5,
                                color: AppTheme
                                    .secondaryTextColor,
                              ),
                            ),
                          ),
                          Text(
                            _formatSaleMoney(
                              _finalCustomerBalance,
                            ),
                            style:
                            TextStyle(
                              fontSize:
                              14,
                              fontWeight:
                              FontWeight
                                  .w700,
                              color: _finalCustomerBalance >
                                  0
                                  ? AppTheme
                                  .dangerColor
                                  : AppTheme
                                  .primaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (_paymentType ==
              PaymentType.partial) ...[
            const SizedBox(
              height: 14,
            ),
            Row(
              children: [
                const SizedBox(
                  width: 180,
                  child: Text(
                    'المبلغ المدفوع الآن',
                    style:
                    TextStyle(
                      fontSize: 11.5,
                      color: AppTheme
                          .secondaryTextColor,
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller:
                    _paidController,
                    keyboardType:
                    TextInputType
                        .number,
                    enabled:
                    !_isSaving &&
                        !_isHolding,
                    decoration:
                    const InputDecoration(
                      hintText: '0',
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (_selectedRepresentative !=
              null) ...[
            const SizedBox(
              height: 12,
            ),
            Row(
              children: [
                const Text(
                  'عمولة المندوب:',
                  style:
                  TextStyle(
                    fontSize: 11.5,
                    color: AppTheme
                        .secondaryTextColor,
                  ),
                ),
                const SizedBox(
                  width: 8,
                ),
                Text(
                  _formatSaleMoney(
                    _commissionPreview,
                  ),
                  style:
                  const TextStyle(
                    fontSize: 12,
                    fontWeight:
                    FontWeight
                        .w700,
                  ),
                ),
                const SizedBox(
                  width: 6,
                ),
                Text(
                  '(${_selectedRepresentative!.commissionPercentage.toStringAsFixed(2)}%)',
                  style:
                  const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme
                        .tertiaryTextColor,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(
            height: 18,
          ),

          Row(
            children: [
              SizedBox(
                width: 220,
                height: 48,
                child:
                ElevatedButton.icon(
                  onPressed:
                  _cart.isEmpty ||
                      _isSaving ||
                      _isHolding ||
                      _selectedWarehouseId ==
                          null
                      ? null
                      : _completeSale,
                  icon: _isSaving
                      ? const SizedBox(
                    width: 17,
                    height: 17,
                    child:
                    CircularProgressIndicator(
                      strokeWidth:
                      2,
                      color:
                      Colors
                          .white,
                    ),
                  )
                      : const Icon(
                    Icons
                        .check_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _isSaving
                        ? 'جاري الحفظ...'
                        : 'حفظ القائمة',
                  ),
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              SizedBox(
                width: 210,
                height: 48,
                child:
                OutlinedButton.icon(
                  onPressed:
                  _cart.isEmpty ||
                      _isSaving ||
                      _isHolding ||
                      _selectedWarehouseId ==
                          null
                      ? null
                      : _holdCurrentSale,
                  icon: _isHolding
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child:
                    CircularProgressIndicator(
                      strokeWidth:
                      2,
                    ),
                  )
                      : const Icon(
                    Icons
                        .schedule_rounded,
                    size: 17,
                  ),
                  label: Text(
                    _isHolding
                        ? 'جاري الحفظ...'
                        : _activeHeldSaleId !=
                        null
                        ? 'إعادة القائمة للانتظار'
                        : 'جعل القائمة في الانتظار',
                  ),
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              SizedBox(
                height: 48,
                child: PopupMenuButton<String>(
                  enabled: _cart.isNotEmpty,
                  onSelected: (value) {
                    showPrintPreview(
                      context,
                      value == 'receipt'
                          ? _currentReceiptDocument()
                          : _currentInvoiceDocument(),
                    );
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'invoice',
                      child: Text('طباعة القائمة'),
                    ),
                    PopupMenuItem(
                      value: 'receipt',
                      child: Text('طباعة الوصل'),
                    ),
                  ],
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.borderColor, width: 1.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.print_outlined, size: 17),
                        SizedBox(width: 8),
                        Text('طباعة'),
                      ],
                    ),
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
  // HELD SALES
  // ===========================================================================

  Future<void>
  _holdCurrentSale() async {
    final warehouse =
        _selectedWarehouse;

    if (warehouse == null) {
      _showMessage(
        'يجب اختيار المخزن أولاً.',
      );

      return;
    }

    if (_cart.isEmpty) {
      _showMessage(
        'لا يمكن وضع قائمة فارغة في الانتظار.',
      );

      return;
    }

    if (_discount < 0) {
      _showMessage(
        'قيمة الخصم غير صحيحة.',
      );

      return;
    }

    if (_discount > _subtotal) {
      _showMessage(
        'الخصم لا يمكن أن يكون أكبر من مجموع القائمة.',
      );

      return;
    }

    if (_paymentType !=
        PaymentType.cash &&
        _selectedCustomer == null) {
      _showMessage(
        'يجب اختيار زبون مسجل للبيع الآجل أو الجزئي.',
      );

      return;
    }

    setState(() {
      _isHolding = true;
    });

    try {
      await _salesRepository
          .holdSale(
        existingHeldSaleId:
        _activeHeldSaleId,
        warehouseId:
        warehouse.id,
        warehouseName:
        warehouse.name,
        customerId:
        _selectedCustomer?.id,
        customerName:
        _invoiceCustomerName,
        representativeId:
        _selectedRepresentative
            ?.id,
        representativeName:
        _selectedRepresentative
            ?.name,
        priceType:
        _selectedPriceType,
        paymentType:
        _paymentType,
        discount:
        _discount,
        paidAmount:
        _paidAmount,
        items:
        List<CartItemModel>.from(
          _cart,
        ),
      );

      final count =
      await _salesRepository
          .getHeldSalesCount();

      if (!mounted) {
        return;
      }

      setState(() {
        _heldSalesCount =
            count;

        _activeHeldSaleId =
        null;

        _cart.clear();

        _discountController.text =
        '0';

        _paidController.text =
        '0';

        _notesController.clear();

        _clearCustomerField();

        _selectedRepresentativeId =
            _noRepresentativeId;

        _selectedPriceType =
            PriceType.retail;

        _paymentType =
            PaymentType.cash;
      });

      _showMessage(
        'تم وضع القائمة في الانتظار.',
      );
    } catch (error) {
      _showMessage(
        _errorMessage(
          error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isHolding =
          false;
        });
      }
    }
  }

  Future<void>
  _openHeldSales() async {
    try {
      final heldSales =
      await _salesRepository
          .getHeldSales();

      if (!mounted) {
        return;
      }

      setState(() {
        _heldSalesCount =
            heldSales.length;
      });

      await showDialog<void>(
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
                return AlertDialog(
                  title: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'قوائم الانتظار',
                        ),
                      ),
                      Container(
                        padding:
                        const EdgeInsets
                            .symmetric(
                          horizontal:
                          10,
                          vertical:
                          5,
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
                            20,
                          ),
                        ),
                        child: Text(
                          '${heldSales.length}',
                          style:
                          const TextStyle(
                            fontSize:
                            11,
                            fontWeight:
                            FontWeight
                                .w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content:
                  SizedBox(
                    width: 760,
                    height: 520,
                    child: heldSales
                        .isEmpty
                        ? const Center(
                      child:
                      Column(
                        mainAxisSize:
                        MainAxisSize
                            .min,
                        children: [
                          Icon(
                            Icons
                                .schedule_outlined,
                            size: 42,
                            color: AppTheme
                                .tertiaryTextColor,
                          ),
                          SizedBox(
                            height:
                            12,
                          ),
                          Text(
                            'لا توجد قوائم في الانتظار',
                            style:
                            TextStyle(
                              fontSize:
                              14,
                              fontWeight:
                              FontWeight
                                  .w600,
                            ),
                          ),
                          SizedBox(
                            height:
                            5,
                          ),
                          Text(
                            'القوائم المؤجلة تظهر هنا وتبقى محفوظة حتى بعد إغلاق البرنامج.',
                            textAlign:
                            TextAlign
                                .center,
                            style:
                            TextStyle(
                              fontSize:
                              11,
                              color: AppTheme
                                  .secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    )
                        : ListView
                        .separated(
                      itemCount:
                      heldSales
                          .length,
                      separatorBuilder:
                          (
                          _,
                          __,
                          ) =>
                      const SizedBox(
                        height:
                        8,
                      ),
                      itemBuilder:
                          (
                          context,
                          index,
                          ) {
                        final held =
                        heldSales[
                        index];

                        return Container(
                          padding:
                          const EdgeInsets
                              .all(
                            14,
                          ),
                          decoration:
                          BoxDecoration(
                            color:
                            const Color(
                              0xFFFAFAFB,
                            ),
                            borderRadius:
                            BorderRadius
                                .circular(
                              13,
                            ),
                            border:
                            Border.all(
                              color: AppTheme
                                  .subtleBorderColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width:
                                44,
                                height:
                                44,
                                alignment:
                                Alignment
                                    .center,
                                decoration:
                                BoxDecoration(
                                  color:
                                  Colors
                                      .white,
                                  borderRadius:
                                  BorderRadius
                                      .circular(
                                    11,
                                  ),
                                  border:
                                  Border.all(
                                    color: AppTheme
                                        .subtleBorderColor,
                                  ),
                                ),
                                child:
                                const Icon(
                                  Icons
                                      .schedule_rounded,
                                  size:
                                  20,
                                ),
                              ),

                              const SizedBox(
                                width:
                                12,
                              ),

                              Expanded(
                                child:
                                Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child:
                                          Text(
                                            held.customerName,
                                            maxLines:
                                            1,
                                            overflow:
                                            TextOverflow.ellipsis,
                                            style:
                                            const TextStyle(
                                              fontSize:
                                              13,
                                              fontWeight:
                                              FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          _formatPrice(
                                            held.total,
                                          ),
                                          style:
                                          const TextStyle(
                                            fontSize:
                                            12,
                                            fontWeight:
                                            FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(
                                      height:
                                      5,
                                    ),
                                    Text(
                                      '${held.warehouseName} • ${held.itemsCount} مادة • ${_paymentTypeTitle(held.paymentType)}',
                                      style:
                                      const TextStyle(
                                        fontSize:
                                        10.5,
                                        color: AppTheme
                                            .secondaryTextColor,
                                      ),
                                    ),
                                    const SizedBox(
                                      height:
                                      3,
                                    ),
                                    Text(
                                      _formatHeldDate(
                                        held.updatedAt,
                                      ),
                                      style:
                                      const TextStyle(
                                        fontSize:
                                        9.5,
                                        color: AppTheme
                                            .tertiaryTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(
                                width:
                                12,
                              ),

                              OutlinedButton.icon(
                                onPressed:
                                    () async {
                                  Navigator.pop(
                                    dialogContext,
                                  );

                                  await _restoreHeldSale(
                                    held,
                                  );
                                },
                                icon:
                                const Icon(
                                  Icons
                                      .restore_rounded,
                                  size:
                                  16,
                                ),
                                label:
                                const Text(
                                  'استرجاع',
                                ),
                              ),

                              const SizedBox(
                                width:
                                7,
                              ),

                              IconButton(
                                tooltip:
                                'حذف القائمة',
                                onPressed:
                                    () async {
                                  final shouldDelete =
                                      await showDialog<bool>(
                                        context:
                                        dialogContext,
                                        builder:
                                            (
                                            confirmContext,
                                            ) {
                                          return Directionality(
                                            textDirection:
                                            TextDirection.rtl,
                                            child:
                                            AlertDialog(
                                              title:
                                              const Text(
                                                'حذف قائمة الانتظار',
                                              ),
                                              content:
                                              Text(
                                                'هل تريد حذف قائمة "${held.customerName}" من الانتظار؟',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed:
                                                      () {
                                                    Navigator.pop(
                                                      confirmContext,
                                                      false,
                                                    );
                                                  },
                                                  child:
                                                  const Text(
                                                    'إلغاء',
                                                  ),
                                                ),
                                                ElevatedButton(
                                                  onPressed:
                                                      () {
                                                    Navigator.pop(
                                                      confirmContext,
                                                      true,
                                                    );
                                                  },
                                                  child:
                                                  const Text(
                                                    'حذف',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ) ??
                                          false;

                                  if (!shouldDelete) {
                                    return;
                                  }

                                  await _salesRepository
                                      .deleteHeldSale(
                                    held.id,
                                  );

                                  heldSales.removeAt(
                                    index,
                                  );

                                  if (mounted) {
                                    setState(
                                          () {
                                        _heldSalesCount =
                                            heldSales.length;

                                        if (_activeHeldSaleId ==
                                            held.id) {
                                          _activeHeldSaleId =
                                          null;
                                        }
                                      },
                                    );
                                  }

                                  dialogSetState(
                                        () {},
                                  );
                                },
                                icon:
                                const Icon(
                                  Icons
                                      .delete_outline_rounded,
                                  color: AppTheme
                                      .dangerColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(
                          dialogContext,
                        );
                      },
                      child:
                      const Text(
                        'إغلاق',
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    } catch (error) {
      _showMessage(
        _errorMessage(
          error,
        ),
      );
    }
  }

  Future<void> _restoreHeldSale(
      HeldSaleModel held,
      ) async {
    try {
      // =======================================================================
      // WAREHOUSE
      // =======================================================================

      final warehouseExists =
      _warehouses.any(
            (warehouse) =>
        warehouse.id ==
            held.warehouseId,
      );

      if (!warehouseExists) {
        _showMessage(
          'المخزن الخاص بهذه القائمة لم يعد متاحاً.',
        );

        return;
      }

      final stockMap =
      await _inventoryRepository
          .getWarehouseStockMap(
        held.warehouseId,
      );

      // =======================================================================
      // CUSTOMER
      // =======================================================================

      String selectedCustomerId =
          _cashCustomerId;

      bool customerExists =
      false;

      if (held.customerId != null) {
        final heldCustomer = await _customersRepository.getCustomerById(
          held.customerId!,
        );
        customerExists = heldCustomer != null && heldCustomer.isActive;
        if (customerExists) {
          selectedCustomerId = held.customerId!;
          _pickedCustomer = heldCustomer;
        }
      }

      // =======================================================================
      // REPRESENTATIVE
      // =======================================================================

      String selectedRepresentativeId =
          _noRepresentativeId;

      if (held.representativeId !=
          null &&
          _representatives.any(
                (representative) =>
            representative.id ==
                held.representativeId,
          )) {
        selectedRepresentativeId =
        held.representativeId!;
      }

      // =======================================================================
      // PAYMENT
      // =======================================================================

      PaymentType paymentType =
          held.paymentType;

      /// إذا الزبون الأصلي انحذف/تعطل،
      /// ما نقدر نخلي القائمة آجل أو جزئي.
      if (!customerExists &&
          held.customerId != null &&
          paymentType !=
              PaymentType.cash) {
        paymentType =
            PaymentType.cash;
      }

      // =======================================================================
      // ITEMS
      // =======================================================================

      final restoredCart =
      <CartItemModel>[];

      final unavailableItems =
      <String>[];

      for (final heldItem
      in held.items) {
        final product = await _productsRepository.getProductById(
          heldItem.productId,
        );

        if (product == null) {
          unavailableItems.add(
            heldItem.productName,
          );

          continue;
        }

        ProductVariantModel? variant;

        for (final candidate
        in product.variants) {
          if (candidate.id ==
              heldItem.variantId &&
              candidate.isActive &&
              candidate.deletedAt ==
                  null) {
            variant =
                candidate;
            break;
          }
        }

        if (variant == null) {
          unavailableItems.add(
            heldItem.productName,
          );

          continue;
        }

        final available =
            stockMap[
            heldItem.variantId] ??
                0.0;

        if (available <
            heldItem.quantity) {
          unavailableItems.add(
            '${heldItem.productName} '
                '(المتوفر ${_formatQuantity(available)})',
          );
        }

        restoredCart.add(
          CartItemModel(
            product:
            product,
            variantId:
            heldItem.variantId,
            unitId:
            heldItem.unitId,
            quantity:
            heldItem.quantity,
            unitFactor: heldItem.unitFactor <= 0 ? 1 : heldItem.unitFactor,
            loosePieces: heldItem.loosePieces,
            priceType:
            heldItem.priceType,
            unitPriceOverride:
            heldItem.unitPrice,
            discountPercent:
            heldItem
                .discountPercent,
          ),
        );
      }

      if (restoredCart.isEmpty &&
          held.items.isNotEmpty) {
        _showMessage(
          'تعذر استرجاع مواد القائمة لأن المنتجات أو الخيارات لم تعد متاحة.',
        );

        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _activeHeldSaleId =
            held.id;

        _selectedWarehouseId =
            held.warehouseId;

        _stockMap =
            stockMap;

        _selectedCustomerId =
            selectedCustomerId;

        _restoreCustomerName(
          held,
          customerExists:
          customerExists,
        );

        _selectedRepresentativeId =
            selectedRepresentativeId;

        _selectedPriceType =
            held.priceType;

        _paymentType =
            paymentType;

        _discountController.text =
            _numberText(
              held.discount,
            );

        _paidController.text =
        paymentType ==
            PaymentType
                .partial
            ? _numberText(
          held.paidAmount,
        )
            : '0';

        _cart
          ..clear()
          ..addAll(
            restoredCart,
          );
      });

      _alignPriceToRepresentative();

      if (!customerExists &&
          held.customerId != null) {
        _showMessage(
          'تم استرجاع القائمة، لكن الزبون الأصلي لم يعد متاحاً؛ تم تحويل الحساب إلى نقدي.',
        );

        return;
      }

      if (unavailableItems.isNotEmpty) {
        _showMessage(
          'تم استرجاع القائمة، لكن مخزون بعض المواد تغير. راجع الكميات قبل الحفظ.',
        );

        return;
      }

      _showMessage(
        'تم استرجاع القائمة من الانتظار.',
      );
    } catch (error) {
      _showMessage(
        _errorMessage(
          error,
        ),
      );
    }
  }

  // ===========================================================================
  // SAVE SALE
  // ===========================================================================

  Future<void> _completeSale() async {
    final warehouse =
        _selectedWarehouse;

    final customer =
        _selectedCustomer;

    final representative =
        _selectedRepresentative;

    if (warehouse == null) {
      _showMessage(
        'يجب اختيار المخزن.',
      );

      return;
    }

    if (_cart.isEmpty) {
      _showMessage(
        'أضف مادة واحدة على الأقل.',
      );

      return;
    }

    // -------------------------------------------------------------------------
    // Refresh stock before final sale.
    // -------------------------------------------------------------------------

    try {
      final freshStock =
      await _inventoryRepository
          .getWarehouseStockMap(
        warehouse.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _stockMap =
            freshStock;
      });
    } catch (error) {
      _showMessage(
        _errorMessage(
          error,
        ),
      );

      return;
    }

    for (final item in _cart) {
      if (item.variantId == null ||
          item.variantId!
              .trim()
              .isEmpty) {
        _showMessage(
          'أحد مواد القائمة لا يحتوي على Variant.',
        );

        return;
      }

      if (item.unitId == null ||
          item.unitId!
              .trim()
              .isEmpty) {
        _showMessage(
          'أحد مواد القائمة لا يحتوي على Unit.',
        );

        return;
      }

      final variant =
      _variantForCartItem(
        item,
      );

      if (variant == null) {
        _showMessage(
          'تعذر العثور على Variant الخاص بالمادة ${item.product.name}.',
        );

        return;
      }

      final available =
      _availableVariantStock(
        variant.id,
      );

      if (item.quantity >
          available) {
        _showMessage(
          'الكمية المطلوبة من ${item.product.name} أكبر من المتوفر. المتوفر حالياً ${_formatQuantity(available)}.',
        );

        return;
      }
    }

    if (!_invoicePriceChoices.contains(_selectedPriceType)) {
      _showMessage(
        'هذا السعر غير مسموح لهذا المندوب. اختر أحد أسعاره لهذه القائمة.',
      );

      return;
    }

    for (final item in _cart) {
      if (item.priceType !=
          _selectedPriceType) {
        _showMessage(
          'يجب أن تكون جميع المواد بنفس نوع السعر.',
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
        'الخصم لا يمكن أن يكون أكبر من المجموع.',
      );

      return;
    }

    if (_total <= 0) {
      _showMessage(
        'إجمالي الفاتورة يجب أن يكون أكبر من صفر.',
      );

      return;
    }

    if (_paymentType !=
        PaymentType.cash &&
        customer == null) {
      _showMessage(
        'يجب اختيار زبون مسجل للبيع الآجل أو الجزئي.',
      );

      return;
    }

    if (_paymentType ==
        PaymentType.partial &&
        _paidAmount <= 0) {
      _showMessage(
        'أدخل المبلغ المدفوع.',
      );

      return;
    }

    if (_paymentType ==
        PaymentType.partial &&
        _paidAmount >= _total) {
      _showMessage(
        'إذا كان المبلغ مسدداً بالكامل اختر نقدي.',
      );

      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final heldSaleIdBeforeSave =
          _activeHeldSaleId;

      final sale =
      await _salesRepository
          .createSale(
        warehouseId:
        warehouse.id,
        warehouseName:
        warehouse.name,
        customerId:
        customer?.id,
        customerName:
        _invoiceCustomerName,
        representativeId:
        representative?.id,
        items:
        List<CartItemModel>.from(
          _cart,
        ),
        subtotal:
        _subtotal,
        discount:
        _discount,
        porterage: _porterage,
        total:
        _total,
        paidAmount:
        _paidAmount,
        remainingAmount:
        _remainingAmount,
        paymentType:
        _paymentType,
        currency: _saleCurrency,
        exchangeRate: _saleCurrency == 'USD' ? _usdRate : 0,
        totalUsd: _saleCurrency == 'USD' && _usdRate > 0
            ? _total / _usdRate
            : 0,
        notes: _composedSaleNotes(),
      );

      // =======================================================================
      // DELETE HELD SALE AFTER SUCCESSFUL LOCAL SALE CREATION
      // =======================================================================

      int heldSalesCount =
          _heldSalesCount;

      if (heldSaleIdBeforeSave !=
          null) {
        try {
          await _salesRepository
              .deleteHeldSale(
            heldSaleIdBeforeSave,
          );

          heldSalesCount =
          await _salesRepository
              .getHeldSalesCount();
        } catch (_) {
          /// لا نفشل البيع إذا حصلت مشكلة
          /// في حذف نسخة الانتظار بعد إنشاء
          /// الفاتورة الحقيقية.
        }
      }

      // =======================================================================
      // SYNC
      // =======================================================================

      try {
        await AppServices.syncNow();
      } catch (_) {
        /// Offline-first:
        /// البيع محفوظ محلياً حتى إذا فشل الإنترنت.
      }

      final newStockMap =
      await _inventoryRepository
          .getWarehouseStockMap(
        warehouse.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _activeHeldSaleId =
        null;

        _heldSalesCount =
            heldSalesCount;

        _cart.clear();

        _discountController.text =
        '0';

        _porterageController.text = '0';

        _paidController.text =
        '0';

        _notesController.clear();

        _paymentType =
            PaymentType.cash;

        _clearCustomerField();

        _selectedRepresentativeId =
            _noRepresentativeId;

        _selectedPriceType =
            PriceType.retail;

        _stockMap =
            newStockMap;

        _pickedCustomer = null;
        _suggestions = const [];
      });

      _showSuccessDialog(
        sale,
        representative:
        representative,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _errorMessage(
          error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving =
          false;
        });
      }
    }
  }

  // ===========================================================================
  // RESET
  // ===========================================================================

  void _resetSale() {
    setState(() {
      /// إذا كانت قائمة مسترجعة، هذا لا يحذف
      /// قائمة الانتظار من قاعدة البيانات.
      ///
      /// فقط يتركها محفوظة ويرجع لبيع جديد.
      _activeHeldSaleId =
      null;

      _cart.clear();

      _discountController.text =
      '0';

      _paidController.text =
      '0';

      _notesController.clear();

      _clearCustomerField();

      _selectedRepresentativeId =
          _noRepresentativeId;

      _selectedPriceType =
          PriceType.retail;

      _paymentType =
          PaymentType.cash;
    });
  }

  // ===========================================================================
  // SUCCESS
  // ===========================================================================

  void _showSuccessDialog(
      SaleModel sale, {
        RepresentativeModel?
        representative,
      }) {
    final double commission =
    representative == null
        ? 0
        : sale.total *
        representative
            .commissionPercentage /
        100;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection:
          TextDirection.rtl,
          child: AlertDialog(
            title:
            const Row(
              children: [
                Icon(
                  Icons
                      .check_circle_rounded,
                  color: AppTheme
                      .successColor,
                ),
                SizedBox(
                  width: 10,
                ),
                Text(
                  'تم حفظ قائمة البيع',
                ),
              ],
            ),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize:
                MainAxisSize.min,
                children: [
                  _DialogRow(
                    title:
                    'رقم الفاتورة',
                    value:
                    sale.invoiceNumber,
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  _DialogRow(
                    title:
                    'الزبون',
                    value:
                    sale.customerName,
                  ),
                  if (representative !=
                      null) ...[
                    const SizedBox(
                      height: 10,
                    ),
                    _DialogRow(
                      title:
                      'المندوب',
                      value:
                      representative
                          .name,
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    _DialogRow(
                      title:
                      'العمولة',
                      value:
                      _formatPrice(
                        commission,
                      ),
                    ),
                  ],
                  const SizedBox(
                    height: 10,
                  ),
                  _DialogRow(
                    title:
                    'الإجمالي',
                    value:
                    _formatPrice(
                      sale.total,
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  _DialogRow(
                    title:
                    'المدفوع',
                    value:
                    _formatPrice(
                      sale.paidAmount,
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  _DialogRow(
                    title:
                    'المتبقي',
                    value:
                    _formatPrice(
                      sale.remainingAmount,
                    ),
                    danger:
                    sale.remainingAmount >
                        0,
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
                child:
                const Text(
                  'قائمة جديدة',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _paymentTypeTitle(
      PaymentType type,
      ) {
    switch (type) {
      case PaymentType.cash:
        return 'نقدي';

      case PaymentType.credit:
        return 'آجل';

      case PaymentType.partial:
        return 'جزئي';
    }
  }

  String _numberText(
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

  String _formatHeldDate(
      DateTime date,
      ) {
    final local =
    date.toLocal();

    final day =
    local.day
        .toString()
        .padLeft(
      2,
      '0',
    );

    final month =
    local.month
        .toString()
        .padLeft(
      2,
      '0',
    );

    final hour =
    local.hour
        .toString()
        .padLeft(
      2,
      '0',
    );

    final minute =
    local.minute
        .toString()
        .padLeft(
      2,
      '0',
    );

    return '$day/$month/${local.year} - $hour:$minute';
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

    message =
        message.replaceFirst(
          'Bad state: ',
          '',
        );

    message =
        message.replaceFirst(
          'Invalid argument(s): ',
          '',
        );

    return message;
  }

  String _formatQuantity(
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

  String _formatPrice(
      double value,
      ) {
    final negative =
        value < 0;

    final absolute =
    value.abs();

    final text =
    absolute.toStringAsFixed(
      0,
    );

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

      buffer.write(
        text[i],
      );
    }

    return '${negative ? '-' : ''}${buffer.toString()} د.ع';
  }

  String _formatSaleMoney(double iqdAmount) {
    if (_saleCurrency == 'USD' && _usdRate > 0) {
      final dollars = iqdAmount / _usdRate;
      return '${dollars.toStringAsFixed(2)} \$';
    }

    return _formatPrice(iqdAmount);
  }

  void _setSaleCurrency(String next) {
    if (next == 'USD' && _usdRate <= 0) {
      _showMessage(
        'حدد سعر الدولار من الإعدادات أولاً.',
      );
      return;
    }

    if (next == _saleCurrency) {
      return;
    }

    setState(() {
      _discountController.text = _convertTypedField(
        _discountController.text,
        next,
      );
      _paidController.text = _convertTypedField(
        _paidController.text,
        next,
      );
      _saleCurrency = next;
    });
  }

  String _convertTypedField(String text, String next) {
    final value = double.tryParse(
          text.trim().replaceAll(',', ''),
        ) ??
        0;

    if (value == 0 || _usdRate <= 0) {
      return '0';
    }

    final converted = next == 'USD' ? value / _usdRate : value * _usdRate;
    return converted.toStringAsFixed(2);
  }

  String _formatDate(
      DateTime date,
      ) {
    final day =
    date.day
        .toString()
        .padLeft(
      2,
      '0',
    );

    final month =
    date.month
        .toString()
        .padLeft(
      2,
      '0',
    );

    return '$day/$month/${date.year}';
  }
}

// =============================================================================
// COMPONENTS
// =============================================================================

class _SectionCard
    extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SectionCard({
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
      decoration: BoxDecoration(
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

class _LabeledField
    extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({
    required this.label,
    required this.child,
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
          label,
          style:
          const TextStyle(
            fontSize: 10.5,
            fontWeight:
            FontWeight.w600,
            color: AppTheme
                .secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 6,
        ),
        child,
      ],
    );
  }
}

class _ReadOnlyBox
    extends StatelessWidget {
  final String value;
  final IconData icon;

  const _ReadOnlyBox({
    required this.value,
    required this.icon,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 48,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 13,
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
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: AppTheme
                .secondaryTextColor,
          ),
          const SizedBox(
            width: 8,
          ),
          Expanded(
            child: Text(
              value,
              style:
              const TextStyle(
                fontSize: 11.5,
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceButton
    extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Material(
      color: selected
          ? AppTheme.primaryColor
          : const Color(
        0xFFF5F5F7,
      ),
      borderRadius:
      BorderRadius.circular(
        10,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius:
        BorderRadius.circular(
          10,
        ),
        child: Padding(
          padding:
          const EdgeInsets
              .symmetric(
            horizontal: 15,
            vertical: 10,
          ),
          child: Text(
            title,
            style:
            TextStyle(
              fontSize: 11,
              fontWeight:
              FontWeight.w600,
              color: selected
                  ? Colors.white
                  : AppTheme
                  .secondaryTextColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentChoice
    extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentChoice({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Material(
      color: selected
          ? AppTheme.primaryColor
          : const Color(
        0xFFF5F5F7,
      ),
      borderRadius:
      BorderRadius.circular(
        10,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius:
        BorderRadius.circular(
          10,
        ),
        child: Container(
          height: 48,
          alignment:
          Alignment.center,
          child: Text(
            title,
            style:
            TextStyle(
              fontSize: 11,
              fontWeight:
              FontWeight.w600,
              color: selected
                  ? Colors.white
                  : AppTheme
                  .primaryTextColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderButton
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onPressed;
  final bool primary;

  const _HeaderButton({
    required this.icon,
    required this.title,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    if (primary) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 17,
        ),
        label: Text(
          title,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 17,
      ),
      label: Text(
        title,
      ),
    );
  }
}

class _SummaryMetric
    extends StatelessWidget {
  final String title;
  final String value;
  final bool danger;

  const _SummaryMetric({
    required this.title,
    required this.value,
    this.danger = false,
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
        color:
        const Color(
          0xFFFAFAFB,
        ),
        borderRadius:
        BorderRadius.circular(
          13,
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
              fontSize: 10,
              color: AppTheme
                  .secondaryTextColor,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            value,
            style:
            TextStyle(
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

class _DialogRow
    extends StatelessWidget {
  final String title;
  final String value;
  final bool danger;

  const _DialogRow({
    required this.title,
    required this.value,
    this.danger = false,
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
            const TextStyle(
              fontSize: 11.5,
              color: AppTheme
                  .secondaryTextColor,
            ),
          ),
        ),
        Text(
          value,
          style:
          TextStyle(
            fontSize: 12.5,
            fontWeight:
            FontWeight.w600,
            color: danger
                ? AppTheme
                .dangerColor
                : AppTheme
                .primaryTextColor,
          ),
        ),
      ],
    );
  }
}
