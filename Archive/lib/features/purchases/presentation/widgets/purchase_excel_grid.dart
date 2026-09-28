import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/paging/list_page.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../products/models/product_model.dart';
import '../../../products/models/unit_model.dart';
import '../../models/purchase_model.dart';

class PurchaseCatalogPage {
  final List<ProductModel> products;
  final List<ProductVariant> variants;

  const PurchaseCatalogPage({
    required this.products,
    required this.variants,
  });
}

class PurchaseExcelGrid extends StatefulWidget {
  final List<ProductModel> products;
  final List<ProductVariant> variants;
  final List<PurchaseItemModel> items;

  final List<UnitModel> units;

  final bool enabled;

  final ValueChanged<PurchaseItemModel> onAddItem;

  final void Function(
      int index,
      int quantity,
      ) onQuantityChanged;

  final void Function(
      int index,
      double unitCost,
      ) onUnitCostChanged;

  final void Function(
      int index,
      double discountPercent,
      ) onDiscountChanged;

  final ValueChanged<int> onDeleteItem;

  final ValueChanged<int>? onCycleUnit;

  final void Function(int index, int pieces)? onPiecesChanged;

  /// بحث في قاعدة البيانات بدل تحميل كل المواد والخيارات.
  final Future<PurchaseCatalogPage> Function(
    String query,
    int limit,
    int offset,
  )? searchCatalog;

  const PurchaseExcelGrid({
    super.key,
    required this.products,
    required this.variants,
    required this.items,
    this.units = const [],
    required this.enabled,
    required this.onAddItem,
    required this.onQuantityChanged,
    required this.onUnitCostChanged,
    required this.onDiscountChanged,
    required this.onDeleteItem,
    this.onCycleUnit,
    this.onPiecesChanged,
    this.searchCatalog,
  });

  @override
  State<PurchaseExcelGrid> createState() => PurchaseExcelGridState();
}

class PurchaseExcelGridState extends State<PurchaseExcelGrid> {
  static const double _productWidth = 330;
  static const double _quantityWidth = 120;
  static const double _piecesWidth = 120;
  static const double _costWidth = 180;
  static const double _discountWidth = 150;
  static const double _totalWidth = 190;
  static const double _deleteWidth = 80;

  final TextEditingController _searchController = TextEditingController();

  final FocusNode _searchFocus = FocusNode();

  final LayerLink _searchLayerLink = LayerLink();

  OverlayEntry? _overlayEntry;

  List<_PurchaseVariantSearchResult> _searchResults = [];
  int _searchToken = 0;
  int _searchPage = 1;
  bool _searchHasNext = false;
  static const int _searchPageSize = 12;
  String _lastSearch = '';
  final Map<String, ProductVariant> _knownVariants = {};

  int _highlightedIndex = 0;

  bool _selectingSuggestion = false;

  final Map<String, FocusNode> _quantityFocusNodes = {};
  final Map<String, FocusNode> _costFocusNodes = {};
  final Map<String, FocusNode> _discountFocusNodes = {};

  @override
  void initState() {
    super.initState();

    _searchFocus.addListener(
      _handleSearchFocus,
    );
  }

  @override
  void didUpdateWidget(
      covariant PurchaseExcelGrid oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (!widget.enabled) {
      _removeOverlay();
    }

    _cleanupFocusNodes();
  }

  @override
  void dispose() {
    _removeOverlay();

    _searchFocus.removeListener(
      _handleSearchFocus,
    );

    _searchController.dispose();
    _searchFocus.dispose();

    for (final node in _quantityFocusNodes.values) {
      node.dispose();
    }

    for (final node in _costFocusNodes.values) {
      node.dispose();
    }

    for (final node in _discountFocusNodes.values) {
      node.dispose();
    }

    super.dispose();
  }

  // ===========================================================================
  // PUBLIC
  // ===========================================================================

  void focusSearch() {
    if (!widget.enabled) {
      return;
    }

    _searchFocus.requestFocus();
  }

  // ===========================================================================
  // FOCUS
  // ===========================================================================

  String _itemKey(
      PurchaseItemModel item,
      ) {
    return '${item.productId}::${item.variantId}';
  }

  FocusNode _quantityFocusFor(
      PurchaseItemModel item,
      ) {
    return _quantityFocusNodes.putIfAbsent(
      _itemKey(item),
          () => FocusNode(
        debugLabel: 'purchase-quantity-${_itemKey(item)}',
      ),
    );
  }

  FocusNode _costFocusFor(
      PurchaseItemModel item,
      ) {
    return _costFocusNodes.putIfAbsent(
      _itemKey(item),
          () => FocusNode(
        debugLabel: 'purchase-cost-${_itemKey(item)}',
      ),
    );
  }

  FocusNode _discountFocusFor(
      PurchaseItemModel item,
      ) {
    return _discountFocusNodes.putIfAbsent(
      _itemKey(item),
          () => FocusNode(
        debugLabel: 'purchase-discount-${_itemKey(item)}',
      ),
    );
  }

  void _cleanupFocusNodes() {
    final activeKeys = widget.items
        .map(
      _itemKey,
    )
        .toSet();

    void cleanMap(
        Map<String, FocusNode> map,
        ) {
      final removedKeys = map.keys
          .where(
            (key) => !activeKeys.contains(key),
      )
          .toList();

      for (final key in removedKeys) {
        final node = map.remove(key);

        if (node != null) {
          node.dispose();
        }
      }
    }

    cleanMap(
      _quantityFocusNodes,
    );

    cleanMap(
      _costFocusNodes,
    );

    cleanMap(
      _discountFocusNodes,
    );
  }

  void _requestFocus(
      FocusNode node,
      ) {
    WidgetsBinding.instance.addPostFrameCallback(
          (_) {
        if (!mounted || !widget.enabled) {
          return;
        }

        node.requestFocus();
      },
    );
  }

  void _focusQuantity(
      PurchaseItemModel item,
      ) {
    _requestFocus(
      _quantityFocusFor(
        item,
      ),
    );
  }

  void _focusSearchNextFrame() {
    _requestFocus(
      _searchFocus,
    );
  }

  // ===========================================================================
  // SEARCH
  // ===========================================================================

  void _handleSearchFocus() {
    if (_searchFocus.hasFocus) {
      final text = _searchController.text.trim();

      if (text.isNotEmpty) {
        _runSearch(
          text,
        );
      }

      return;
    }

    Future<void>.delayed(
      const Duration(
        milliseconds: 120,
      ),
          () {
        if (!_selectingSuggestion) {
          _removeOverlay();
        }
      },
    );
  }

  Future<void> _runSearch(
      String value,
      ) async {
    final query = value.trim().toLowerCase();
    if (query != _lastSearch) {
      _searchPage = 1;
      _lastSearch = query;
    }
    final token = ++_searchToken;

    if (query.isEmpty) {
      _searchResults = [];
      _highlightedIndex = 0;

      _removeOverlay();

      if (mounted) {
        setState(() {});
      }

      return;
    }

    var products = widget.products;
    var variants = widget.variants;
    if (widget.searchCatalog != null) {
      final page = await widget.searchCatalog!(
        value.trim(),
        _searchPageSize + 1,
        (_searchPage - 1) * _searchPageSize,
      );
      if (!mounted || token != _searchToken) {
        return;
      }
      _searchHasNext = page.products.length > _searchPageSize;
      products = page.products.take(_searchPageSize).toList();
      variants = page.variants;
      for (final variant in variants) {
        _knownVariants[variant.id] = variant;
      }
    }

    final results = <_PurchaseVariantSearchResult>[];

    for (final product in products) {
      if (!product.isActive || product.deletedAt != null) {
        continue;
      }

      final productName = product.name.trim().toLowerCase();
      final productBarcode = product.barcode.trim().toLowerCase();
      final productSku = (product.sku ?? '').trim().toLowerCase();

      final productVariants = variants.where(
            (variant) {
          return variant.productId == product.id &&
              variant.isActive &&
              variant.deletedAt == null;
        },
      );

      for (final variant in productVariants) {
        final variantBarcode =
        (variant.barcode ?? '').trim().toLowerCase();

        final variantSku = (variant.sku ?? '').trim().toLowerCase();

        final variantTitle = _variantTitle(
          variant,
        ).toLowerCase();

        final matches = productName.contains(query) ||
            productBarcode.contains(query) ||
            productSku.contains(query) ||
            variantBarcode.contains(query) ||
            variantSku.contains(query) ||
            variantTitle.contains(query);

        if (!matches) {
          continue;
        }

        results.add(
          _PurchaseVariantSearchResult(
            product: product,
            variant: variant,
          ),
        );
      }
    }

    results.sort(
          (a, b) {
        final aExact = _isExactMatch(
          a,
          query,
        );

        final bExact = _isExactMatch(
          b,
          query,
        );

        if (aExact && !bExact) {
          return -1;
        }

        if (!aExact && bExact) {
          return 1;
        }

        final nameComparison = a.product.name.compareTo(
          b.product.name,
        );

        if (nameComparison != 0) {
          return nameComparison;
        }

        return _variantTitle(
          a.variant,
        ).compareTo(
          _variantTitle(
            b.variant,
          ),
        );
      },
    );

    if (widget.searchCatalog == null) {
      final start = (_searchPage - 1) * _searchPageSize;
      _searchHasNext = results.length > start + _searchPageSize;
      _searchResults = results.skip(start).take(_searchPageSize).toList();
    } else {
      _searchResults = results;
    }

    _highlightedIndex = 0;

    if (_searchResults.isEmpty) {
      _removeOverlay();
    } else {
      _showOverlay();
    }

    if (mounted) {
      setState(() {});
    }
  }

  bool _isExactMatch(
      _PurchaseVariantSearchResult result,
      String query,
      ) {
    final productBarcode = result.product.barcode.trim().toLowerCase();

    final productSku = (result.product.sku ?? '').trim().toLowerCase();

    final variantBarcode =
    (result.variant.barcode ?? '').trim().toLowerCase();

    final variantSku = (result.variant.sku ?? '').trim().toLowerCase();

    return productBarcode == query ||
        productSku == query ||
        variantBarcode == query ||
        variantSku == query;
  }

  void _showOverlay() {
    _removeOverlay();

    if (!_searchFocus.hasFocus ||
        _searchResults.isEmpty ||
        !widget.enabled) {
      return;
    }

    final overlay = Overlay.of(
      context,
    );

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: _productWidth,
          child: CompositedTransformFollower(
            link: _searchLayerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(
              0,
              6,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Material(
                color: Colors.transparent,
                elevation: 0,
                child: Container(
                  constraints: const BoxConstraints(
                    maxHeight: 360,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(
                      14,
                    ),
                    border: Border.all(
                      color: AppTheme.subtleBorderColor,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: 0.10,
                        ),
                        blurRadius: 24,
                        offset: const Offset(
                          0,
                          8,
                        ),
                      ),
                    ],
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                    ),
                    shrinkWrap: true,
                    itemCount: _searchResults.length +
                        ((_searchPage > 1 || _searchHasNext) ? 1 : 0),
                    separatorBuilder: (_, __) {
                      return const Divider(
                        height: 1,
                        indent: 12,
                        endIndent: 12,
                        color: AppTheme.subtleBorderColor,
                      );
                    },
                    itemBuilder: (
                        context,
                        index,
                        ) {
                      if (index >= _searchResults.length) {
                        return ListPagination(
                          page: _searchPage,
                          hasNextPage: _searchHasNext,
                          pageSize: _searchPageSize,
                          onPageChanged: (page) {
                            _searchPage = page;
                            _runSearch(_searchController.text);
                          },
                        );
                      }
                      return _buildSuggestion(
                        _searchResults[index],
                        index,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(
      _overlayEntry!,
    );
  }

  void _removeOverlay() {
    _overlayEntry?.remove();

    _overlayEntry = null;
  }

  Widget _buildSuggestion(
      _PurchaseVariantSearchResult result,
      int index,
      ) {
    final selected = index == _highlightedIndex;

    final barcode = _barcodeFor(
      result.product,
      result.variant,
    );

    return MouseRegion(
      onEnter: (_) {
        _highlightedIndex = index;

        _showOverlay();
      },
      child: InkWell(
        onTap: () {
          _selectResult(
            result,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          color: selected
              ? const Color(
            0xFFF5F5F7,
          )
              : Colors.white,
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
                    9,
                  ),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 17,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryTextColor,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      _variantTitle(
                        result.variant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      barcode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppTheme.tertiaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Text(
                _formatPrice(
                  _purchaseCostFor(
                    result.product,
                    result.variant,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleSearchKey(
      FocusNode node,
      KeyEvent event,
      ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _removeOverlay();

      return KeyEventResult.handled;
    }

    if (_searchResults.isEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
          widget.items.isNotEmpty) {
        final lastItem = widget.items.last;

        _discountFocusFor(
          lastItem,
        ).requestFocus();

        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex =
            (_highlightedIndex + 1) % _searchResults.length;
      });

      _showOverlay();

      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex--;

        if (_highlightedIndex < 0) {
          _highlightedIndex = _searchResults.length - 1;
        }
      });

      _showOverlay();

      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final index = _highlightedIndex.clamp(
        0,
        _searchResults.length - 1,
      );

      _selectResult(
        _searchResults[index],
      );

      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _selectResult(
      _PurchaseVariantSearchResult result,
      ) {
    _selectingSuggestion = true;

    final baseUnitId = result.product.baseUnitId?.trim();

    if (baseUnitId == null || baseUnitId.isEmpty) {
      _selectingSuggestion = false;

      _showMessage(
        'هذه المادة غير مرتبطة بوحدة قياس أساسية.',
      );

      return;
    }

    final factor = result.product.piecesPerCarton <= 1
        ? 1.0
        : result.product.piecesPerCarton;
    var unitId = baseUnitId;
    if (factor > 1) {
      for (final unit in widget.units) {
        if (unit.isActive && unit.parentUnitId == baseUnitId) {
          unitId = unit.id;
          break;
        }
      }
    }
    final cartonCost =
        _purchaseCostFor(result.product, result.variant) * factor;

    final barcode = _barcodeFor(
      result.product,
      result.variant,
    );

    final existingIndex = widget.items.indexWhere(
          (item) {
        return item.productId == result.product.id &&
            item.variantId == result.variant.id;
      },
    );

    late PurchaseItemModel targetItem;

    if (existingIndex >= 0) {
      final old = widget.items[existingIndex];

      targetItem = PurchaseItemModel(
        productId: old.productId,
        variantId: old.variantId,
        unitId: old.unitId,
        productName: old.productName,
        barcode: old.barcode,
        quantity: old.quantity + 1,
        unitCost: old.unitCost,
        unitFactor: old.unitFactor,
        discountPercent: old.discountPercent,
      );

      widget.onQuantityChanged(
        existingIndex,
        old.quantity + 1,
      );
    } else {
      targetItem = PurchaseItemModel(
        productId: result.product.id,
        variantId: result.variant.id,
        unitId: unitId,
        productName: result.product.name,
        barcode: barcode == '-' ? '' : barcode,
        quantity: 0,
        unitFactor: factor,
        unitCost: cartonCost,
        discountPercent: 0,
      );

      widget.onAddItem(
        targetItem,
      );
    }

    _searchController.clear();

    _searchResults = [];

    _highlightedIndex = 0;

    _removeOverlay();

    _selectingSuggestion = false;

    _focusQuantity(
      targetItem,
    );

    if (mounted) {
      setState(() {});
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const Divider(
          height: 1,
          color: AppTheme.subtleBorderColor,
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _tableWidth,
                child: Column(
                  children: [
                    _buildTableHeader(),
                    ...List.generate(
                      widget.items.length,
                          (index) {
                        return _buildItemRow(
                          widget.items[index],
                          index,
                        );
                      },
                    ),
                    _buildEntryRow(),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double get _tableWidth {
    return _productWidth +
        _quantityWidth +
        _piecesWidth +
        _costWidth +
        _discountWidth +
        _totalWidth +
        _deleteWidth +
        32;
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        18,
        20,
        16,
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مواد الفاتورة',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
                SizedBox(
                  height: 4,
                ),
                Text(
                  'اكتب عدد الكارتون. قطع الكارتون تجي من المنتج وتقدر تغيرها ثم Enter. سعر الشراء هو سعر الكارتون، وسعر القطعة يظهر تحت الإجمالي.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: const Color(
                0xFFF5F5F7,
              ),
              borderRadius: BorderRadius.circular(
                20,
              ),
            ),
            child: Text(
              '${widget.items.length} مادة',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      decoration: const BoxDecoration(
        color: Color(
          0xFFFAFAFB,
        ),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.subtleBorderColor,
          ),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: _productWidth,
            child: Text(
              'المادة',
              textAlign: TextAlign.center,
              style: _purchaseGridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _quantityWidth,
            child: Text(
              'كارتون',
              textAlign: TextAlign.center,
              style: _purchaseGridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _piecesWidth,
            child: Text(
              'قطع الكارتون',
              textAlign: TextAlign.center,
              style: _purchaseGridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _costWidth,
            child: Text(
              'سعر الشراء',
              textAlign: TextAlign.center,
              style: _purchaseGridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _discountWidth,
            child: Text(
              'الخصم %',
              textAlign: TextAlign.center,
              style: _purchaseGridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _totalWidth,
            child: Text(
              'الإجمالي',
              textAlign: TextAlign.center,
              style: _purchaseGridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _deleteWidth,
            child: Text(
              'حذف',
              textAlign: TextAlign.center,
              style: _purchaseGridHeaderStyle,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ITEM ROW
  // ===========================================================================

  Widget _buildItemRow(
      PurchaseItemModel item,
      int index,
      ) {
    final variant = _variantById(
      item.variantId,
    );

    return Container(
      constraints: const BoxConstraints(
        minHeight: 76,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.subtleBorderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _productWidth,
            child: _buildProductCell(
              item,
              variant,
            ),
          ),

          // ===================================================================
          // QUANTITY
          // ===================================================================

          SizedBox(
            width: _quantityWidth,
            child: _PurchaseNumberCell(
              key: ValueKey(
                'purchase-qty-${_itemKey(item)}',
              ),
              value: item.quantity.toDouble(),
              integerOnly: true,
              enabled: widget.enabled,
              focusNode: _quantityFocusFor(
                item,
              ),
              onChanged: (value) {
                final quantity = value.round();

                if (quantity < 0) {
                  return;
                }

                widget.onQuantityChanged(
                  index,
                  quantity,
                );
              },
              onMoveUp: () {
                _moveVertical(
                  rowIndex: index,
                  column: _PurchaseGridColumn.quantity,
                  direction: -1,
                );
              },
              onMoveDown: () {
                _moveVertical(
                  rowIndex: index,
                  column: _PurchaseGridColumn.quantity,
                  direction: 1,
                );
              },
              onMoveLeft: () {
                _costFocusFor(
                  item,
                ).requestFocus();
              },
              onMoveRight: null,
            ),
          ),

          SizedBox(
            width: _piecesWidth,
            child: _PurchasePiecesField(
              pieces: item.unitFactor <= 0 ? 1 : item.unitFactor,
              enabled: widget.enabled,
              onChanged: (pieces) {
                widget.onPiecesChanged?.call(index, pieces);
              },
            ),
          ),

          // ===================================================================
          // COST
          // ===================================================================

          SizedBox(
            width: _costWidth,
            child: _PurchaseNumberCell(
              key: ValueKey(
                'purchase-cost-${_itemKey(item)}',
              ),
              value: item.unitCost,
              enabled: widget.enabled,
              focusNode: _costFocusFor(
                item,
              ),
              onChanged: (value) {
                if (value < 0) {
                  return;
                }

                widget.onUnitCostChanged(
                  index,
                  value,
                );
              },
              onMoveUp: () {
                _moveVertical(
                  rowIndex: index,
                  column: _PurchaseGridColumn.cost,
                  direction: -1,
                );
              },
              onMoveDown: () {
                _moveVertical(
                  rowIndex: index,
                  column: _PurchaseGridColumn.cost,
                  direction: 1,
                );
              },
              onMoveLeft: () {
                _discountFocusFor(
                  item,
                ).requestFocus();
              },
              onMoveRight: () {
                _quantityFocusFor(
                  item,
                ).requestFocus();
              },
            ),
          ),

          // ===================================================================
          // DISCOUNT
          // ===================================================================

          SizedBox(
            width: _discountWidth,
            child: _PurchaseNumberCell(
              key: ValueKey(
                'purchase-discount-${_itemKey(item)}',
              ),
              value: item.discountPercent,
              enabled: widget.enabled,
              focusNode: _discountFocusFor(
                item,
              ),
              suffixText: '%',
              onChanged: (value) {
                if (value < 0 || value > 100) {
                  return;
                }

                widget.onDiscountChanged(
                  index,
                  value,
                );
              },
              onSubmitted: (value) {
                if (value < 0 || value > 100) {
                  _showMessage(
                    'نسبة الخصم يجب أن تكون بين 0 و100.',
                  );

                  return;
                }

                if (index == widget.items.length - 1) {
                  _focusSearchNextFrame();
                }
              },
              onMoveUp: () {
                _moveVertical(
                  rowIndex: index,
                  column: _PurchaseGridColumn.discount,
                  direction: -1,
                );
              },
              onMoveDown: () {
                _moveVertical(
                  rowIndex: index,
                  column: _PurchaseGridColumn.discount,
                  direction: 1,
                );
              },
              onMoveLeft: () {
                if (index == widget.items.length - 1) {
                  _searchFocus.requestFocus();
                }
              },
              onMoveRight: () {
                _costFocusFor(
                  item,
                ).requestFocus();
              },
            ),
          ),

          // ===================================================================
          // TOTAL
          // ===================================================================

          SizedBox(
            width: _totalWidth,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatPrice(
                      item.total,
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryTextColor,
                    ),
                  ),
                  if (item.unitFactor > 1)
                    Text(
                      'القطعة ${_formatPrice(item.pieceCost)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ===================================================================
          // DELETE
          // ===================================================================

          SizedBox(
            width: _deleteWidth,
            child: Center(
              child: ExcludeFocus(
                child: IconButton(
                  tooltip: 'حذف المادة',
                  onPressed: widget.enabled
                      ? () {
                    widget.onDeleteItem(
                      index,
                    );
                  }
                      : null,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: AppTheme.dangerColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCell(
      PurchaseItemModel item,
      ProductVariant? variant,
      ) {
    final variantText = variant == null
        ? 'الخيار'
        : _variantTitle(
      variant,
    );

    return Padding(
      padding: const EdgeInsets.only(
        left: 12,
      ),
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
                9,
              ),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 17,
              color: AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(
            width: 9,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  '$variantText • ${item.barcode.trim().isEmpty ? 'بدون باركود' : item.barcode}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppTheme.tertiaryTextColor,
                  ),
                ),
                if (item.unitFactor > 1) ...[
                  const SizedBox(height: 2),
                  Text(
                    'الكارتون = ${item.unitFactor.toStringAsFixed(0)} قطعة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.secondaryTextColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ENTRY ROW
  // ===========================================================================

  Widget _buildEntryRow() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 9,
      ),
      decoration: const BoxDecoration(
        color: Color(
          0xFFFCFCFD,
        ),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.subtleBorderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _productWidth,
            child: CompositedTransformTarget(
              link: _searchLayerLink,
              child: Focus(
                onKeyEvent: _handleSearchKey,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  enabled: widget.enabled,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'ابحث عن المادة أو الباركود...',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                    ),
                    isDense: true,
                  ),
                  onChanged: _runSearch,
                  onSubmitted: (_) {
                    if (_searchResults.isEmpty) {
                      return;
                    }

                    final index = _highlightedIndex.clamp(
                      0,
                      _searchResults.length - 1,
                    );

                    _selectResult(
                      _searchResults[index],
                    );
                  },
                ),
              ),
            ),
          ),
          SizedBox(
            width: _quantityWidth,
            child: _emptyCell(
              '0',
            ),
          ),
          SizedBox(
            width: _piecesWidth,
            child: _emptyCell(
              '1',
            ),
          ),
          SizedBox(
            width: _costWidth,
            child: _emptyCell(
              '0',
            ),
          ),
          SizedBox(
            width: _discountWidth,
            child: _emptyCell(
              '0%',
            ),
          ),
          SizedBox(
            width: _totalWidth,
            child: const Center(
              child: Text(
                '0 د.ع',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.tertiaryTextColor,
                ),
              ),
            ),
          ),
          const SizedBox(
            width: _deleteWidth,
          ),
        ],
      ),
    );
  }

  Widget _emptyCell(
      String value,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 5,
      ),
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(
            9,
          ),
          border: Border.all(
            color: AppTheme.subtleBorderColor,
          ),
        ),
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.tertiaryTextColor,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 12,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.keyboard_alt_outlined,
            size: 16,
            color: AppTheme.tertiaryTextColor,
          ),
          const SizedBox(
            width: 7,
          ),
          const Expanded(
            child: Text(
              'اكتب للبحث • Enter للاختيار • ↑ ↓ بين المواد • ← → بين الخلايا • Tab للانتقال',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.tertiaryTextColor,
              ),
            ),
          ),
          Text(
            '${widget.items.length} مادة',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ARROW NAVIGATION
  // ===========================================================================

  void _moveVertical({
    required int rowIndex,
    required _PurchaseGridColumn column,
    required int direction,
  }) {
    final targetIndex = rowIndex + direction;

    if (targetIndex < 0) {
      return;
    }

    if (targetIndex >= widget.items.length) {
      if (direction > 0) {
        _searchFocus.requestFocus();
      }

      return;
    }

    final targetItem = widget.items[targetIndex];

    switch (column) {
      case _PurchaseGridColumn.quantity:
        _quantityFocusFor(
          targetItem,
        ).requestFocus();
        break;

      case _PurchaseGridColumn.cost:
        _costFocusFor(
          targetItem,
        ).requestFocus();
        break;

      case _PurchaseGridColumn.discount:
        _discountFocusFor(
          targetItem,
        ).requestFocus();
        break;
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  ProductVariant? _variantById(
      String variantId,
      ) {
    final known = _knownVariants[variantId];
    if (known != null) {
      return known;
    }
    for (final variant in widget.variants) {
      if (variant.id == variantId) {
        return variant;
      }
    }

    return null;
  }

  double _purchaseCostFor(
      ProductModel product,
      ProductVariant variant,
      ) {
    if (variant.lastPurchasePrice > 0) {
      return variant.lastPurchasePrice;
    }

    if (variant.costPrice > 0) {
      return variant.costPrice;
    }

    return product.costPrice;
  }

  String _barcodeFor(
      ProductModel product,
      ProductVariant variant,
      ) {
    final variantBarcode = (variant.barcode ?? '').trim();

    if (variantBarcode.isNotEmpty) {
      return variantBarcode;
    }

    final variantSku = (variant.sku ?? '').trim();

    if (variantSku.isNotEmpty) {
      return variantSku;
    }

    if (product.barcode.trim().isNotEmpty) {
      return product.barcode.trim();
    }

    if ((product.sku ?? '').trim().isNotEmpty) {
      return product.sku!.trim();
    }

    return '-';
  }

  String _variantTitle(
      ProductVariant variant,
      ) {
    final rawJson = variant.attributesJson.trim();

    if (rawJson.isEmpty || rawJson == '{}') {
      return 'الخيار الرئيسي';
    }

    try {
      final decoded = jsonDecode(
        rawJson,
      );

      if (decoded is Map) {
        final values = decoded.values
            .map(
              (value) => value.toString().trim(),
        )
            .where(
              (value) => value.isNotEmpty,
        )
            .toList();

        if (values.isNotEmpty) {
          return values.join(
            ' - ',
          );
        }
      }
    } catch (_) {
      // Keep fallback below.
    }

    return 'الخيار الرئيسي';
  }

  String _formatPrice(
      double value,
      ) {
    final negative = value < 0;

    final text = value.abs().toStringAsFixed(
      0,
    );

    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) {
        buffer.write(
          ',',
        );
      }

      buffer.write(
        text[i],
      );
    }

    return '${negative ? '-' : ''}${buffer.toString()} د.ع';
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

enum _PurchaseGridColumn {
  quantity,
  cost,
  discount,
}

class _PurchaseVariantSearchResult {
  final ProductModel product;
  final ProductVariant variant;

  const _PurchaseVariantSearchResult({
    required this.product,
    required this.variant,
  });
}

// =============================================================================
// KEYBOARD INTENTS
// =============================================================================

class _MoveUpIntent extends Intent {
  const _MoveUpIntent();
}

class _MoveDownIntent extends Intent {
  const _MoveDownIntent();
}

class _MoveLeftIntent extends Intent {
  const _MoveLeftIntent();
}

class _MoveRightIntent extends Intent {
  const _MoveRightIntent();
}

// =============================================================================
// NUMBER CELL
// =============================================================================

class _PurchaseNumberCell extends StatefulWidget {
  final double value;

  final bool integerOnly;

  final bool enabled;

  final FocusNode focusNode;

  final String? suffixText;

  final ValueChanged<double> onChanged;

  final ValueChanged<double>? onSubmitted;

  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;

  const _PurchaseNumberCell({
    super.key,
    required this.value,
    required this.enabled,
    required this.focusNode,
    required this.onChanged,
    this.integerOnly = false,
    this.suffixText,
    this.onSubmitted,
    this.onMoveUp,
    this.onMoveDown,
    this.onMoveLeft,
    this.onMoveRight,
  });

  @override
  State<_PurchaseNumberCell> createState() => _PurchaseNumberCellState();
}

class _PurchaseNumberCellState extends State<_PurchaseNumberCell> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(
      text: _textForValue(
        widget.value,
      ),
    );

    widget.focusNode.addListener(
      _handleFocus,
    );
  }

  @override
  void didUpdateWidget(
      covariant _PurchaseNumberCell oldWidget,
      ) {
    super.didUpdateWidget(
      oldWidget,
    );

    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(
        _handleFocus,
      );

      widget.focusNode.addListener(
        _handleFocus,
      );
    }

    if (widget.focusNode.hasFocus) {
      return;
    }

    if (oldWidget.value != widget.value) {
      final text = _textForValue(
        widget.value,
      );

      if (_controller.text != text) {
        _controller.text = text;
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(
      _handleFocus,
    );

    _controller.dispose();

    super.dispose();
  }

  void _handleFocus() {
    if (!widget.focusNode.hasFocus) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback(
          (_) {
        if (!mounted || !widget.focusNode.hasFocus) {
          return;
        }

        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      },
    );
  }

  String _textForValue(
      double value,
      ) {
    if (widget.integerOnly || value == value.roundToDouble()) {
      return value.round().toString();
    }

    return value.toStringAsFixed(
      2,
    );
  }

  double? _parse(
      String value,
      ) {
    final cleaned = value
        .trim()
        .replaceAll(
      ',',
      '',
    )
        .replaceAll(
      '%',
      '',
    );

    if (cleaned.isEmpty) {
      return null;
    }

    return double.tryParse(
      cleaned,
    );
  }

  void _selectAll() {
    WidgetsBinding.instance.addPostFrameCallback(
          (_) {
        if (!mounted || !widget.focusNode.hasFocus) {
          return;
        }

        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      },
    );
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(
        LogicalKeyboardKey.arrowUp,
      ): const _MoveUpIntent(),

      const SingleActivator(
        LogicalKeyboardKey.arrowDown,
      ): const _MoveDownIntent(),

      const SingleActivator(
        LogicalKeyboardKey.arrowLeft,
      ): const _MoveLeftIntent(),

      const SingleActivator(
        LogicalKeyboardKey.arrowRight,
      ): const _MoveRightIntent(),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 5,
      ),
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            _MoveUpIntent: CallbackAction<_MoveUpIntent>(
              onInvoke: (_) {
                if (widget.onMoveUp == null) {
                  return null;
                }

                widget.onMoveUp!.call();

                return null;
              },
            ),
            _MoveDownIntent: CallbackAction<_MoveDownIntent>(
              onInvoke: (_) {
                if (widget.onMoveDown == null) {
                  return null;
                }

                widget.onMoveDown!.call();

                return null;
              },
            ),
            _MoveLeftIntent: CallbackAction<_MoveLeftIntent>(
              onInvoke: (_) {
                if (widget.onMoveLeft == null) {
                  return null;
                }

                widget.onMoveLeft!.call();

                return null;
              },
            ),
            _MoveRightIntent: CallbackAction<_MoveRightIntent>(
              onInvoke: (_) {
                if (widget.onMoveRight == null) {
                  return null;
                }

                widget.onMoveRight!.call();

                return null;
              },
            ),
          },
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(
                9,
              ),
              border: Border.all(
                color: widget.focusNode.hasFocus
                    ? AppTheme.primaryColor
                    : AppTheme.subtleBorderColor,
                width: widget.focusNode.hasFocus ? 1.4 : 1,
              ),
            ),
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.numberWithOptions(
                decimal: !widget.integerOnly,
              ),
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  widget.integerOnly
                      ? RegExp(
                    r'[0-9]',
                  )
                      : RegExp(
                    r'[0-9.]',
                  ),
                ),
              ],
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryTextColor,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
                suffixText: widget.suffixText,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 13,
                ),
              ),
              onTap: _selectAll,
              onChanged: (text) {
                final value = _parse(
                  text,
                );

                if (value == null || value < 0) {
                  return;
                }

                widget.onChanged(
                  value,
                );
              },
              onSubmitted: (text) {
                final value = _parse(
                  text,
                );

                if (value == null) {
                  return;
                }

                widget.onSubmitted?.call(
                  value,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

const TextStyle _purchaseGridHeaderStyle = TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w600,
  color: AppTheme.secondaryTextColor,
);

class _PurchasePiecesField extends StatefulWidget {
  final double pieces;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _PurchasePiecesField({
    required this.pieces,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_PurchasePiecesField> createState() => _PurchasePiecesFieldState();
}

class _PurchasePiecesFieldState extends State<_PurchasePiecesField> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.pieces.toStringAsFixed(0),
    );
  }

  @override
  void didUpdateWidget(_PurchasePiecesField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.pieces.toStringAsFixed(0);
    if (!_focus.hasFocus && text != _controller.text) {
      _controller.text = text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final pieces = int.tryParse(_controller.text.trim()) ?? 1;
    widget.onChanged(pieces < 1 ? 1 : pieces);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppTheme.subtleBorderColor),
        ),
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          enabled: widget.enabled,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          ),
          onSubmitted: (_) => _commit(),
          onEditingComplete: _commit,
        ),
      ),
    );
  }
}