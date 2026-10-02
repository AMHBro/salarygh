import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/paging/list_page.dart';
import '../../../../core/theme/app_theme.dart';
import '../../products/models/product_model.dart';
import '../../products/models/product_variant_model.dart';
import '../models/cart_item_model.dart';

class SalesExcelGrid extends StatefulWidget {
  final List<ProductModel> products;
  final List<CartItemModel> items;

  /// Variant local ID -> stock quantity.
  final Map<String, double> stockMap;

  final PriceType selectedPriceType;

  final bool enabled;

  final ValueChanged<CartItemModel> onAddItem;

  final void Function(
      int index,
      int quantity,
      ) onQuantityChanged;

  final void Function(
      int index,
      PriceType type,
      double price,
      ) onPriceChanged;

  final ValueChanged<int> onDeleteItem;

  final void Function(int index, String notes) onNotesChanged;

  final void Function(int index, int pieces)? onPiecesChanged;

  /// بحث في قاعدة البيانات بدل مسح كل المواد المحمّلة.
  final Future<List<ProductModel>> Function(
    String query,
    int limit,
    int offset,
  )? searchProducts;

  const SalesExcelGrid({
    super.key,
    required this.products,
    required this.items,
    required this.stockMap,
    required this.selectedPriceType,
    required this.enabled,
    required this.onAddItem,
    required this.onQuantityChanged,
    required this.onPriceChanged,
    required this.onDeleteItem,
    required this.onNotesChanged,
    this.onPiecesChanged,
    this.searchProducts,
  });

  @override
  State<SalesExcelGrid> createState() {
    return _SalesExcelGridState();
  }
}

class _SalesExcelGridState extends State<SalesExcelGrid> {
  static const double _productWidth = 320;
  static const double _quantityWidth = 100;
  static const double _piecesWidth = 100;
  static const double _priceWidth = 150;
  static const double _totalWidth = 150;
  static const double _notesWidth = 180;
  static const double _deleteWidth = 70;

  /// Editable columns:
  ///
  /// 0 = Quantity
  /// 1 = Cost
  /// 2 = Wholesale
  /// 3 = Representative
  /// 4 = Retail
  static const int _editableColumnCount = 2;

  final TextEditingController _searchController = TextEditingController();

  final FocusNode _searchFocus = FocusNode(
    debugLabel: 'sales-grid-search',
  );

  final FocusNode _searchKeyboardFocus = FocusNode(
    skipTraversal: true,
    debugLabel: 'sales-grid-search-keyboard',
  );

  final LayerLink _searchLayerLink = LayerLink();

  /// Focus nodes are managed by the parent grid so arrows can move
  /// vertically/horizontally between cells.
  final Map<String, List<FocusNode>> _rowFocusNodes = {};

  OverlayEntry? _overlayEntry;

  List<_VariantSearchResult> _searchResults = [];
  int _searchPage = 1;
  bool _searchHasNext = false;
  static const int _searchPageSize = 10;
  int _searchToken = 0;
  String _lastSearch = '';

  int _highlightedIndex = 0;

  bool _selectingSuggestion = false;

  /// When a new item is added we remember its variant id.
  /// After rebuild we focus its quantity cell.
  String? _pendingNewVariantFocusId;

  @override
  void initState() {
    super.initState();

    _searchFocus.addListener(
      _handleSearchFocus,
    );

    _syncRowFocusNodes();
  }

  @override
  void didUpdateWidget(
      covariant SalesExcelGrid oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    _syncRowFocusNodes();

    if (!widget.enabled) {
      _removeOverlay();
    }

    final pendingVariantId = _pendingNewVariantFocusId;

    if (pendingVariantId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        final nodes = _rowFocusNodes[pendingVariantId];

        if (nodes == null || nodes.isEmpty) {
          return;
        }

        _pendingNewVariantFocusId = null;

        nodes[0].requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();

    _searchFocus.removeListener(
      _handleSearchFocus,
    );

    _searchController.dispose();
    _searchFocus.dispose();
    _searchKeyboardFocus.dispose();

    for (final nodes in _rowFocusNodes.values) {
      for (final node in nodes) {
        node.dispose();
      }
    }

    _rowFocusNodes.clear();

    super.dispose();
  }

  // ===========================================================================
  // FOCUS MANAGEMENT
  // ===========================================================================

  void _syncRowFocusNodes() {
    final currentVariantIds = widget.items
        .map((item) => item.variantId)
        .whereType<String>()
        .toSet();

    final removedIds = _rowFocusNodes.keys
        .where(
          (id) => !currentVariantIds.contains(id),
    )
        .toList();

    for (final id in removedIds) {
      final nodes = _rowFocusNodes.remove(id);

      if (nodes != null) {
        for (final node in nodes) {
          node.dispose();
        }
      }
    }

    for (final item in widget.items) {
      final variantId = item.variantId;

      if (variantId == null) {
        continue;
      }

      _rowFocusNodes.putIfAbsent(
        variantId,
            () => List.generate(
          _editableColumnCount,
              (column) => FocusNode(
            debugLabel: 'sales-grid-$variantId-$column',
          ),
        ),
      );
    }
  }

  List<FocusNode>? _focusNodesForItem(
      CartItemModel item,
      ) {
    final variantId = item.variantId;

    if (variantId == null) {
      return null;
    }

    return _rowFocusNodes[variantId];
  }

  void _moveCellFocus({
    required int rowIndex,
    required int columnIndex,
    required _GridDirection direction,
  }) {
    if (widget.items.isEmpty) {
      _searchFocus.requestFocus();
      return;
    }

    switch (direction) {
      case _GridDirection.up:
        if (rowIndex <= 0) {
          return;
        }

        _focusCell(
          rowIndex - 1,
          columnIndex,
        );
        return;

      case _GridDirection.down:
        if (rowIndex >= widget.items.length - 1) {
          _focusSearch();
          return;
        }

        _focusCell(
          rowIndex + 1,
          columnIndex,
        );
        return;

      case _GridDirection.left:
      /// RTL visually:
      /// Product is on the right, then quantity, then the invoice price.
      ///
      /// Moving LEFT therefore advances toward the invoice price cell.
        if (columnIndex < _editableColumnCount - 1) {
          _focusCell(
            rowIndex,
            columnIndex + 1,
          );
          return;
        }

        /// From the last editable cell go to the next row's quantity.
        if (rowIndex < widget.items.length - 1) {
          _focusCell(
            rowIndex + 1,
            0,
          );
        } else {
          _focusSearch();
        }

        return;

      case _GridDirection.right:
        if (columnIndex > 0) {
          _focusCell(
            rowIndex,
            columnIndex - 1,
          );
          return;
        }

        /// من خانة العدد يرجع لحقل المنتج (سطر الإدخال).
        _focusSearch();

        return;
    }
  }

  void _focusCell(
      int rowIndex,
      int columnIndex,
      ) {
    if (rowIndex < 0 ||
        rowIndex >= widget.items.length ||
        columnIndex < 0 ||
        columnIndex >= _editableColumnCount) {
      return;
    }

    final item = widget.items[rowIndex];

    final nodes = _focusNodesForItem(item);

    if (nodes == null ||
        columnIndex >= nodes.length) {
      return;
    }

    nodes[columnIndex].requestFocus();
  }

  void _focusSearch() {
    _searchFocus.requestFocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    });
  }

  void _focusLastItem({
    int columnIndex = 0,
  }) {
    if (widget.items.isEmpty) {
      return;
    }

    _focusCell(
      widget.items.length - 1,
      columnIndex,
    );
  }

  // ===========================================================================
  // SEARCH
  // ===========================================================================

  void _handleSearchFocus() {
    if (_searchFocus.hasFocus) {
      if (_searchController.text.trim().isNotEmpty) {
        _runSearch(
          _searchController.text,
        );
      }
    } else {
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

    final results = <_VariantSearchResult>[];
    final products = widget.searchProducts == null
        ? widget.products
        : await widget.searchProducts!(
            value.trim(),
            _searchPageSize + 1,
            (_searchPage - 1) * _searchPageSize,
          );
    if (!mounted || token != _searchToken) {
      return;
    }
    if (widget.searchProducts != null) {
      _searchHasNext = products.length > _searchPageSize;
    }

    for (final product in products.take(
      widget.searchProducts == null ? products.length : _searchPageSize,
    )) {
      if (!product.isActive ||
          product.deletedAt != null) {
        continue;
      }

      final productName = product.name.toLowerCase();

      final productBarcode = product.barcode.trim().toLowerCase();

      final productSku = (product.sku ?? '').trim().toLowerCase();

      for (final variant in product.variants) {
        if (!variant.isActive ||
            variant.deletedAt != null) {
          continue;
        }

        final stock = widget.stockMap[variant.id] ?? 0.0;

        final variantBarcode = variant.barcode.trim().toLowerCase();

        final variantSku = (variant.sku ?? '').trim().toLowerCase();

        final variantName = variant.displayName.trim().toLowerCase();

        final matches =
            productName.contains(query) ||
                productBarcode.contains(query) ||
                productSku.contains(query) ||
                variantBarcode.contains(query) ||
                variantSku.contains(query) ||
                variantName.contains(query);

        if (!matches) {
          continue;
        }

        results.add(
          _VariantSearchResult(
            product: product,
            variant: variant,
            stock: stock,
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

        return a.product.name.compareTo(
          b.product.name,
        );
      },
    );

    if (widget.searchProducts == null) {
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
      _VariantSearchResult result,
      String query,
      ) {
    final variantBarcode = result.variant.barcode.trim().toLowerCase();

    final variantSku = (result.variant.sku ?? '').trim().toLowerCase();

    final productBarcode = result.product.barcode.trim().toLowerCase();

    final productSku = (result.product.sku ?? '').trim().toLowerCase();

    return variantBarcode == query ||
        variantSku == query ||
        productBarcode == query ||
        productSku == query;
  }

  void _showOverlay() {
    _removeOverlay();

    if (!_searchFocus.hasFocus ||
        _searchResults.isEmpty ||
        !widget.enabled) {
      return;
    }

    final overlay = Overlay.of(context);

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
                    maxHeight: 330,
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
                    separatorBuilder: (_, _) {
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
                      final result = _searchResults[index];

                      return _buildSuggestion(
                        result,
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
      _VariantSearchResult result,
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
                      _variantName(
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
                      '$barcode • متوفر ${_formatQuantity(result.stock)}',
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
                  _priceForVariant(
                    result.variant,
                    widget.selectedPriceType,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSearchKey(
      KeyEvent event,
      ) {
    if (event is! KeyDownEvent) {
      return;
    }

    final key = event.logicalKey;

    /// إذا عندنا نتائج بحث، الأسهم تتحكم بالاقتراحات.
    if (_searchResults.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _highlightedIndex =
              (_highlightedIndex + 1) % _searchResults.length;
        });

        _showOverlay();

        return;
      }

      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _highlightedIndex--;

          if (_highlightedIndex < 0) {
            _highlightedIndex = _searchResults.length - 1;
          }
        });

        _showOverlay();

        return;
      }

      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        final index = _highlightedIndex.clamp(
          0,
          _searchResults.length - 1,
        );

        _selectResult(
          _searchResults[index],
        );

        return;
      }
    }

    /// إذا خانة البحث فارغة وماكو Suggestions:
    /// ↑ يرجع لآخر مادة.
    if (key == LogicalKeyboardKey.arrowUp &&
        _searchResults.isEmpty &&
        _searchController.text.trim().isEmpty) {
      _focusLastItem(
        columnIndex: 0,
      );

      return;
    }

    if (key == LogicalKeyboardKey.arrowLeft &&
        widget.items.isNotEmpty) {
      _focusLastItem();
      return;
    }

    if (key == LogicalKeyboardKey.arrowRight &&
        widget.items.isNotEmpty) {
      _focusLastItem(
        columnIndex: _editableColumnCount - 1,
      );
      return;
    }

    if (key == LogicalKeyboardKey.escape) {
      _removeOverlay();
    }
  }

  void _selectResult(
      _VariantSearchResult result,
      ) {
    _selectingSuggestion = true;

    if (result.stock <= 0) {
      _selectingSuggestion = false;
      _showMessage(
        'هذه المادة غير متوفرة في المخزن المختار. حدّث المبيعات بعد الشراء أو اختر مخزن الشراء.',
      );
      return;
    }

    final unitId = result.product.baseUnitId?.trim();

    if (unitId == null ||
        unitId.isEmpty) {
      _selectingSuggestion = false;

      _showMessage(
        'هذه المادة لا تحتوي على وحدة أساسية.',
      );

      return;
    }

    final existingIndex = widget.items.indexWhere(
          (item) => item.variantId == result.variant.id,
    );

    if (existingIndex >= 0) {
      final existing = widget.items[existingIndex];

      final newQuantity = existing.quantity + 1;

      if (newQuantity * _factorOf(existing) > result.stock) {
        _selectingSuggestion = false;

        _showMessage(
          'لا توجد كمية إضافية متوفرة من هذه المادة.',
        );

        return;
      }

      widget.onQuantityChanged(
        existingIndex,
        newQuantity,
      );

      /// المادة موجودة أصلاً، نركز على كمية نفس السطر.
      final existingVariantId = existing.variantId;

      if (existingVariantId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }

          final nodes = _rowFocusNodes[existingVariantId];

          if (nodes != null && nodes.isNotEmpty) {
            nodes[0].requestFocus();
          }
        });
      }
    } else {
      final selectedPrice = _priceForVariant(
        result.variant,
        widget.selectedPriceType,
      );

      /// بعد ما يعاد بناء الـitems نروح لخانة العدد للمادة الجديدة.
      _pendingNewVariantFocusId = result.variant.id;

      widget.onAddItem(
        CartItemModel(
          product: result.product,
          variantId: result.variant.id,
          unitId: unitId,
          quantity: 1,
          priceType: widget.selectedPriceType,
          unitPriceOverride: selectedPrice,
          costPriceOverride: result.variant.costPrice,
          representativePriceOverride:
          result.variant.representativePrice,
          wholesalePriceOverride: result.variant.wholesalePrice,
          retailPriceOverride: result.variant.retailPrice,
        ),
      );
    }

    _searchController.clear();
    _searchResults = [];
    _highlightedIndex = 0;

    _removeOverlay();

    _selectingSuggestion = false;

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
        SingleChildScrollView(
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

                /// السطر الفارغ موجود دائماً.
                _buildEntryRow(),
                _buildFooter(),
              ],
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
        (_priceWidth * 5) +
        _notesWidth +
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
                  'مواد القائمة',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
                SizedBox(
                  height: 5,
                ),
                Text(
                  'حقل الكارتون وحقل القطع هما الكمية. اكتب أحدهما أو الاثنين، والفارغ يبقى صفراً. سعر القطعة في القائمة، وسعر الكارتون = سعر القطعة × قطع الكارتون.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
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
                fontSize: 11,
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
      height: 52,
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
            child: ColoredBox(
              color: Color(0xFFFFF3C4),
              child: Text(
                'المادة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryTextColor,
                ),
              ),
            ),
          ),
          SizedBox(
            width: _quantityWidth,
            child: Text(
              'كارتون',
              textAlign: TextAlign.center,
              style: _gridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _piecesWidth,
            child: Text(
              'قطع',
              textAlign: TextAlign.center,
              style: _gridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _priceWidth,
            child: Text(
              'الكلفة',
              textAlign: TextAlign.center,
              style: _gridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _priceWidth,
            child: Text(
              'الجملة',
              textAlign: TextAlign.center,
              style: _gridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _priceWidth,
            child: Text(
              'المندوب',
              textAlign: TextAlign.center,
              style: _gridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _priceWidth,
            child: Text(
              'المفرد',
              textAlign: TextAlign.center,
              style: _gridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _priceWidth,
            child: Text(
              'سعر القائمة',
              textAlign: TextAlign.center,
              style: _gridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _totalWidth,
            child: Text(
              'المجموع',
              textAlign: TextAlign.center,
              style: _gridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _notesWidth,
            child: Text(
              'ملاحظات',
              textAlign: TextAlign.center,
              style: _gridHeaderStyle,
            ),
          ),
          SizedBox(
            width: _deleteWidth,
            child: Text(
              'حذف',
              textAlign: TextAlign.center,
              style: _gridHeaderStyle,
            ),
          ),
        ],
      ),
    );
  }

  double _factorOf(CartItemModel item) {
    return item.unitFactor <= 0 ? 1 : item.unitFactor;
  }

  // ===========================================================================
  // ITEM ROW
  // ===========================================================================

  Widget _buildItemRow(
      CartItemModel item,
      int index,
      ) {
    final variant = _variantForItem(item);

    if (variant == null) {
      return _buildInvalidRow(
        item,
        index,
      );
    }

    final stock = widget.stockMap[variant.id] ?? 0.0;

    final focusNodes = _focusNodesForItem(item);

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
              item.product,
              variant,
              stock,
              item.quantity * _factorOf(item) + item.loosePieces,
              _factorOf(item),
            ),
          ),

          // Quantity
          SizedBox(
            width: _quantityWidth,
            child: _GridNumberCell(
              key: ValueKey(
                'quantity-${variant.id}',
              ),
              focusNode: focusNodes?[0],
              value: item.quantity.toDouble(),
              integerOnly: true,
              enabled: widget.enabled,
              selected: false,
              onDelete: () => widget.onDeleteItem(index),
              onMove: (direction) {
                _moveCellFocus(
                  rowIndex: index,
                  columnIndex: 0,
                  direction: direction,
                );
              },
              onChanged: (value) {
                final quantity = value.round();

                if (quantity < 0 ||
                    quantity * _factorOf(item) + item.loosePieces > stock) {
                  return;
                }

                widget.onQuantityChanged(
                  index,
                  quantity,
                );
              },
              onSubmitted: (value) {
                final quantity = value.round();
                final billed =
                    quantity * _factorOf(item) + item.loosePieces;

                if (billed > stock) {
                  _showMessage(
                    'الكمية المطلوبة أكبر من المتوفر (${_formatQuantity(stock)}).',
                  );
                }
              },
            ),
          ),

          SizedBox(
            width: _piecesWidth,
            child: _GridNumberCell(
              key: ValueKey(
                'pieces-${variant.id}',
              ),
              value: item.loosePieces.toDouble(),
              integerOnly: true,
              enabled: widget.enabled,
              selected: false,
              onDelete: () => widget.onDeleteItem(index),
              onMove: (_) {},
              onChanged: (value) {
                final pieces = value.round();
                if (pieces < 0 ||
                    item.quantity * _factorOf(item) + pieces > stock) {
                  return;
                }
                widget.onPiecesChanged?.call(index, pieces);
              },
            ),
          ),

          _basePriceCell(
            variant.costPrice,
            selected: widget.selectedPriceType == PriceType.cost,
          ),
          _basePriceCell(
            variant.wholesalePrice,
            selected: widget.selectedPriceType == PriceType.wholesale,
          ),
          _basePriceCell(
            variant.representativePrice,
            selected: widget.selectedPriceType == PriceType.representative,
          ),
          _basePriceCell(
            variant.retailPrice,
            selected: widget.selectedPriceType == PriceType.retail,
          ),

          SizedBox(
            width: _priceWidth,
            child: _GridNumberCell(
              key: ValueKey(
                'invoice-${variant.id}',
              ),
              focusNode: focusNodes?[1],
              value: item.unitPrice,
              enabled: widget.enabled,
              selected: true,
              onDelete: () => widget.onDeleteItem(index),
              onMove: (direction) {
                _moveCellFocus(
                  rowIndex: index,
                  columnIndex: 1,
                  direction: direction,
                );
              },
              onChanged: (value) {
                widget.onPriceChanged(
                  index,
                  widget.selectedPriceType,
                  value,
                );
              },
            ),
          ),

          // Total
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
                  if (_factorOf(item) > 1)
                    Text(
                      'كارتون ${_formatPrice(item.unitPrice * _factorOf(item))}',
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

          SizedBox(
            width: _notesWidth,
            child: _GridNoteCell(
              key: ValueKey('notes-${variant.id}'),
              value: item.notes,
              enabled: widget.enabled,
              onChanged: (value) {
                widget.onNotesChanged(index, value);
              },
            ),
          ),

          // Delete
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
      ProductModel product,
      ProductVariantModel variant,
      double stock,
      double billedPieces,
      double cartonFactor,
      ) {
    final barcode = _barcodeFor(
      product,
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
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  '${_variantName(variant)} • $barcode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppTheme.tertiaryTextColor,
                  ),
                ),
                if (cartonFactor > 1) ...[
                  const SizedBox(
                    height: 2,
                  ),
                  Text(
                    'الكارتون = ${cartonFactor.toStringAsFixed(0)} قطعة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.secondaryTextColor,
                    ),
                  ),
                ],
                const SizedBox(
                  height: 2,
                ),
                Text(
                  'متوفر ${_formatQuantity(stock)}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: billedPieces > stock
                        ? AppTheme.dangerColor
                        : AppTheme.successColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // EMPTY ENTRY ROW
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
              child: KeyboardListener(
                focusNode: _searchKeyboardFocus,
                onKeyEvent: _handleSearchKey,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  enabled: widget.enabled,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'المادة',
                    hintText: 'ابحث عن المادة أو الباركود...',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                    ),
                    isDense: true,
                  ),
                  onChanged: _runSearch,
                  onSubmitted: (_) {
                    if (_searchResults.isNotEmpty) {
                      _selectResult(
                        _searchResults[_highlightedIndex],
                      );
                    }
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
              '0',
            ),
          ),
          SizedBox(
            width: _priceWidth,
            child: _emptyCell(
              '0',
            ),
          ),
          SizedBox(
            width: _priceWidth,
            child: _emptyCell(
              '0',
            ),
          ),
          SizedBox(
            width: _priceWidth,
            child: _emptyCell(
              '0',
            ),
          ),
          SizedBox(
            width: _priceWidth,
            child: _emptyCell(
              '0',
            ),
          ),
          SizedBox(
            width: _priceWidth,
            child: _emptyCell(
              '0',
            ),
          ),
          const SizedBox(
            width: _notesWidth,
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
          const Text(
            'Enter ينتقل للكمية ثم سعر القائمة • الأسهم بين السطور • ذ أو Delete يحذف السطر',
            style: TextStyle(
              fontSize: 10,
              color: AppTheme.tertiaryTextColor,
            ),
          ),
          const Spacer(),
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

  Widget _buildInvalidRow(
      CartItemModel item,
      int index,
      ) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
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
            child: Text(
              '${item.product.name} - تعذر العثور على خيار المنتج.',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.dangerColor,
              ),
            ),
          ),
          ExcludeFocus(
            child: IconButton(
              onPressed: widget.enabled
                  ? () {
                widget.onDeleteItem(
                  index,
                );
              }
                  : null,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.dangerColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  ProductVariantModel? _variantForItem(
      CartItemModel item,
      ) {
    final id = item.variantId;

    if (id == null) {
      return null;
    }

    for (final variant in item.product.variants) {
      if (variant.id == id) {
        return variant;
      }
    }

    return null;
  }

  double _priceForVariant(
      ProductVariantModel variant,
      PriceType type,
      ) {
    switch (type) {
      case PriceType.cost:
        return variant.costPrice;

      case PriceType.representative:
        return variant.representativePrice;

      case PriceType.wholesale:
        return variant.wholesalePrice;

      case PriceType.retail:
        return variant.retailPrice;
    }
  }

  String _variantName(
      ProductVariantModel variant,
      ) {
    final name = variant.displayName.trim();

    if (name.isEmpty) {
      return 'الخيار الرئيسي';
    }

    return name;
  }

  String _barcodeFor(
      ProductModel product,
      ProductVariantModel variant,
      ) {
    if (variant.barcode.trim().isNotEmpty) {
      return variant.barcode.trim();
    }

    if ((variant.sku ?? '').trim().isNotEmpty) {
      return variant.sku!.trim();
    }

    if (product.barcode.trim().isNotEmpty) {
      return product.barcode.trim();
    }

    if ((product.sku ?? '').trim().isNotEmpty) {
      return product.sku!.trim();
    }

    return '-';
  }

  String _formatQuantity(
      double value,
      ) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(
      2,
    );
  }

  Widget _basePriceCell(
    double value, {
    required bool selected,
  }) {
    return SizedBox(
      width: _priceWidth,
      child: Center(
        child: Text(
          _formatPrice(value),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected
                ? AppTheme.primaryColor
                : AppTheme.secondaryTextColor,
          ),
        ),
      ),
    );
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
      if (i > 0 &&
          (text.length - i) % 3 == 0) {
        buffer.write(',');
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
      ),
    );
  }
}

// =============================================================================
// SEARCH RESULT
// =============================================================================

class _VariantSearchResult {
  final ProductModel product;

  final ProductVariantModel variant;

  final double stock;

  const _VariantSearchResult({
    required this.product,
    required this.variant,
    required this.stock,
  });
}

// =============================================================================
// GRID DIRECTION
// =============================================================================

enum _GridDirection {
  up,
  down,
  left,
  right,
}

// =============================================================================
// NUMBER CELL
// =============================================================================

class _GridNumberCell extends StatefulWidget {
  final double value;

  final bool integerOnly;

  final bool enabled;

  final bool selected;

  /// Focus is controlled by SalesExcelGrid.
  final FocusNode? focusNode;

  final ValueChanged<double> onChanged;

  final ValueChanged<double>? onSubmitted;

  final ValueChanged<_GridDirection> onMove;

  final VoidCallback? onDelete;

  const _GridNumberCell({
    super.key,
    required this.value,
    required this.enabled,
    required this.selected,
    required this.onChanged,
    required this.onMove,
    this.onDelete,
    this.integerOnly = false,
    this.focusNode,
    this.onSubmitted,
  });

  @override
  State<_GridNumberCell> createState() {
    return _GridNumberCellState();
  }
}

class _GridNumberCellState extends State<_GridNumberCell> {
  late final TextEditingController _controller;

  FocusNode? _internalFocusNode;

  FocusNode get _effectiveFocusNode {
    return widget.focusNode ??
        (_internalFocusNode ??= FocusNode());
  }

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(
      text: _textForValue(
        widget.value,
      ),
    );
  }

  @override
  void didUpdateWidget(
      covariant _GridNumberCell oldWidget,
      ) {
    super.didUpdateWidget(
      oldWidget,
    );

    if (_effectiveFocusNode.hasFocus) {
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
    _controller.dispose();
    _internalFocusNode?.dispose();

    super.dispose();
  }

  String _textForValue(
      double value,
      ) {
    if (widget.integerOnly ||
        value == value.roundToDouble()) {
      return value.round().toString();
    }

    return value.toStringAsFixed(
      2,
    );
  }

  double? _parse(
      String value,
      ) {
    final cleaned = value.trim().replaceAll(
      ',',
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  KeyEventResult _handleKeyEvent(
      FocusNode node,
      KeyEvent event,
      ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onMove(
        _GridDirection.up,
      );

      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onMove(
        _GridDirection.down,
      );

      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onMove(
        _GridDirection.left,
      );

      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onMove(
        _GridDirection.right,
      );

      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.delete || event.character == 'ذ') {
      widget.onDelete?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    final focusNode = _effectiveFocusNode;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 5,
      ),
      child: AnimatedContainer(
        duration: const Duration(
          milliseconds: 120,
        ),
        height: 42,
        decoration: BoxDecoration(
          color: widget.selected
              ? AppTheme.primaryColor.withValues(
            alpha: 0.06,
          )
              : Colors.white,
          borderRadius: BorderRadius.circular(
            9,
          ),
          border: Border.all(
            color: widget.selected
                ? AppTheme.primaryColor
                : AppTheme.subtleBorderColor,
            width: widget.selected ? 1.4 : 1,
          ),
        ),
        child: Focus(
          onKeyEvent: _handleKeyEvent,
          child: TextField(
            controller: _controller,
            focusNode: focusNode,
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
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: widget.selected
                  ? FontWeight.w700
                  : FontWeight.w600,
              color: AppTheme.primaryTextColor,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 13,
              ),
            ),
            onTap: _selectAll,
            onChanged: (text) {
              final value = _parse(
                text,
              );

              if (value == null ||
                  value < 0) {
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

              if (value != null) {
                widget.onSubmitted?.call(
                  value,
                );
              }

              widget.onMove(
                _GridDirection.left,
              );
            },
          ),
        ),
      ),
    );
  }
}

const TextStyle _gridHeaderStyle = TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w600,
  color: AppTheme.secondaryTextColor,
);

class _GridNoteCell extends StatefulWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _GridNoteCell({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_GridNoteCell> createState() => _GridNoteCellState();
}

class _GridNoteCellState extends State<_GridNoteCell> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _GridNoteCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: TextField(
        controller: _controller,
        enabled: widget.enabled,
        style: const TextStyle(fontSize: 11.5),
        decoration: const InputDecoration(
          hintText: 'ملاحظة',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
