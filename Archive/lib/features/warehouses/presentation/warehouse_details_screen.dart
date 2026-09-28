import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/theme/app_theme.dart';
import '../../products/models/product_model.dart';
import '../models/warehouse_model.dart';
import 'stock_item_screen.dart';

class WarehouseDetailsScreen extends StatefulWidget {
  final WarehouseModel warehouse;

  const WarehouseDetailsScreen({
    super.key,
    required this.warehouse,
  });

  @override
  State<WarehouseDetailsScreen> createState() =>
      _WarehouseDetailsScreenState();
}

class _WarehouseDetailsScreenState extends State<WarehouseDetailsScreen> {
  final _productsRepository =
      AppServices.productsRepository;

  bool _isLoading = true;

  List<_WarehouseInventoryItem> _items = [];

  String _searchQuery = '';
  int _inventoryPage = 1;

  @override
  void initState() {
    super.initState();

    _loadData();
  }

  // ===========================================================================
  // LOAD
  // ===========================================================================

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final balances =
      await (AppServices.database.select(
        AppServices.database.stockBalances,
      )
        ..where(
              (table) => table.warehouseId.equals(
            widget.warehouse.id,
          ),
        ))
          .get();

      final variantIds = [for (final balance in balances) balance.variantId];
      final products = <ProductModel>[];
      if (variantIds.isNotEmpty) {
        final variantRows = await (AppServices.database.select(
          AppServices.database.productVariants,
        )..where((table) => table.id.isIn(variantIds)))
            .get();
        final productIds = {for (final row in variantRows) row.productId};
        for (final id in productIds) {
          final product = await _productsRepository.getProductById(id);
          if (product != null) {
            products.add(product);
          }
        }
      }

      final balanceMap = {
        for (final balance in balances)
          balance.variantId: balance,
      };

      final items = <_WarehouseInventoryItem>[];

      for (final product in products) {
        if (product.deletedAt != null) {
          continue;
        }

        for (final variant in product.variants) {
          if (variant.deletedAt != null) {
            continue;
          }

          final balance =
          balanceMap[variant.id];

          if (balance == null) {
            continue;
          }

          //
          // حالياً نعرض فقط المواد التي فعلاً موجودة داخل المخزن.
          //
          if (balance.quantity <= 0) {
            continue;
          }

          final variantName =
          variant.displayName.trim();

          final barcode =
          variant.barcode.trim().isNotEmpty
              ? variant.barcode.trim()
              : product.barcode.trim();

          items.add(
            _WarehouseInventoryItem(
              productId: product.id,
              variantId: variant.id,
              productName: product.name,
              variantName: variantName,
              barcode: barcode,
              unit: product.unit,
              quantity: balance.quantity,
              minimumStock:
              product.minimumStock,
              isProductActive:
              product.isActive,
              isVariantActive:
              variant.isActive,
              updatedAt:
              balance.updatedAt,
            ),
          );
        }
      }

      items.sort(
            (a, b) => a.productName.compareTo(
          b.productName,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _errorMessage(
              error,
            ),
          ),
        ),
      );
    }
  }

  // ===========================================================================
  // FILTER
  // ===========================================================================

  List<_WarehouseInventoryItem> get _filteredItems {
    final query =
    _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return _items;
    }

    return _items.where(
          (item) {
        return item.productName
            .toLowerCase()
            .contains(query) ||
            item.variantName
                .toLowerCase()
                .contains(query) ||
            item.barcode
                .toLowerCase()
                .contains(query);
      },
    ).toList();
  }

  // ===========================================================================
  // STATS
  // ===========================================================================

  int get _productsCount {
    return _items
        .map(
          (item) => item.productId,
    )
        .toSet()
        .length;
  }

  int get _variantsCount {
    return _items.length;
  }

  double get _totalQuantity {
    return _items.fold(
      0,
          (
          sum,
          item,
          ) =>
      sum + item.quantity,
    );
  }

  int get _lowStockCount {
    return _items.where(
          (item) {
        return item.minimumStock > 0 &&
            item.quantity <= item.minimumStock;
      },
    ).length;
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
      body: SafeArea(
        child: _isLoading
            ? const Center(
          child:
          CircularProgressIndicator(),
        )
            : RefreshIndicator(
          onRefresh: _loadData,
          child:
          SingleChildScrollView(
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
                  height: 26,
                ),
                _buildWarehouseInfo(),
                const SizedBox(
                  height: 20,
                ),
                _buildStats(),
                const SizedBox(
                  height: 20,
                ),
                _buildInventorySection(),
              ],
            ),
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
        IconButton(
          tooltip: 'رجوع',
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.arrow_back_rounded,
          ),
        ),
        const SizedBox(
          width: 8,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                widget.warehouse.name,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight:
                  FontWeight.w700,
                  letterSpacing: -0.5,
                  color:
                  AppTheme.primaryTextColor,
                ),
              ),
              const SizedBox(
                height: 5,
              ),
              const Text(
                'تفاصيل المنتجات والكميات الموجودة داخل المخزن.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme
                      .secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _loadData,
          icon: const Icon(
            Icons.refresh_rounded,
            size: 18,
          ),
          label: const Text(
            'تحديث',
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // WAREHOUSE INFO
  // ===========================================================================

  Widget _buildWarehouseInfo() {
    final warehouse =
        widget.warehouse;

    final code =
    warehouse.code?.trim();

    final address =
    warehouse.address?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        20,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xFF1D1D1F,
        ),
        borderRadius:
        BorderRadius.circular(
          18,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color:
              Colors.white.withValues(
                alpha: 0.10,
              ),
              borderRadius:
              BorderRadius.circular(
                14,
              ),
            ),
            child: const Icon(
              Icons.warehouse_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(
            width: 16,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  warehouse.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight:
                    FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(
                  height: 5,
                ),
                Text(
                  address?.isNotEmpty == true
                      ? address!
                      : 'لا يوجد عنوان مسجل',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(
                      0xFFB8B8BD,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _WarehouseInfoValue(
            title: 'النوع',
            value:
            warehouse.type.displayName,
          ),
          const SizedBox(
            width: 30,
          ),
          _WarehouseInfoValue(
            title: 'الرمز',
            value:
            code?.isNotEmpty == true
                ? code!
                : '—',
          ),
          const SizedBox(
            width: 30,
          ),
          _WarehouseInfoValue(
            title: 'الحالة',
            value: warehouse.isActive
                ? 'فعال'
                : 'موقوف',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // STATS
  // ===========================================================================

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _DetailsStatCard(
            title: 'عدد المنتجات',
            value:
            '$_productsCount',
            subtitle:
            'منتجات مختلفة',
            icon:
            Icons.inventory_2_outlined,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _DetailsStatCard(
            title: 'عدد الخيارات',
            value:
            '$_variantsCount',
            subtitle:
            'Variants بالمخزن',
            icon:
            Icons.category_outlined,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _DetailsStatCard(
            title: 'إجمالي الكمية',
            value: _formatQuantity(
              _totalQuantity,
            ),
            subtitle:
            'إجمالي الوحدات',
            icon:
            Icons.layers_outlined,
            highlighted: true,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _DetailsStatCard(
            title: 'نقص المخزون',
            value:
            '$_lowStockCount',
            subtitle:
            'خيارات تحت الحد',
            icon:
            Icons.warning_amber_rounded,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // INVENTORY
  // ===========================================================================

  Widget _buildInventorySection() {
    final items =
        _filteredItems;

    return Container(
      width: double.infinity,
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
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Text(
                        'مخزون المنتجات',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                          FontWeight.w600,
                          color: AppTheme
                              .primaryTextColor,
                        ),
                      ),
                      SizedBox(
                        height: 4,
                      ),
                      Text(
                        'جميع المنتجات والخيارات المتوفرة داخل هذا المخزن.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme
                              .secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 300,
                  height: 42,
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery =
                            value;
                        _inventoryPage = 1;
                      });
                    },
                    decoration:
                    const InputDecoration(
                      hintText:
                      'بحث بالمنتج أو الباركود...',
                      prefixIcon: Icon(
                        Icons
                            .search_rounded,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            color:
            AppTheme.subtleBorderColor,
          ),
          const _InventoryTableHeader(),
          if (items.isEmpty)
            _buildEmptyState()
          else ...[
            ...items
                .skip((_inventoryPage - 1) * kListPageSize)
                .take(kListPageSize)
                .map(
              _buildInventoryRow,
            ),
            ListPagination(
              page: _inventoryPage,
              totalItems: items.length,
              onPageChanged: (page) {
                setState(() {
                  _inventoryPage = page;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 60,
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(
                0xFFF5F5F7,
              ),
              borderRadius:
              BorderRadius.circular(
                16,
              ),
            ),
            child: const Icon(
              Icons
                  .inventory_2_outlined,
              color: AppTheme
                  .tertiaryTextColor,
            ),
          ),
          const SizedBox(
            height: 14,
          ),
          Text(
            _searchQuery.trim().isEmpty
                ? 'هذا المخزن لا يحتوي على منتجات حالياً.'
                : 'لا توجد نتائج مطابقة للبحث.',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight:
              FontWeight.w500,
              color: AppTheme
                  .secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryRow(
      _WarehouseInventoryItem item,
      ) {
    final lowStock =
        item.minimumStock > 0 &&
            item.quantity <=
                item.minimumStock;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StockItemScreen(
              productId: item.productId,
              productName: item.productName,
              barcode: item.barcode,
              unit: item.unit,
              quantity: item.quantity,
            ),
          ),
        );
      },
      child: Container(
      constraints:
      const BoxConstraints(
        minHeight: 72,
      ),
      padding:
      const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 12,
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
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  const TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                    FontWeight.w600,
                    color: AppTheme
                        .primaryTextColor,
                  ),
                ),
                if (item.hasVisibleVariant) ...[
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    item.variantName,
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style:
                    const TextStyle(
                      fontSize: 10.5,
                      color: AppTheme
                          .secondaryTextColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              item.barcode.isEmpty
                  ? '—'
                  : item.barcode,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme
                    .secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              item.unit,
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
              _formatQuantity(
                item.quantity,
              ),
              style: const TextStyle(
                fontSize: 13,
                fontWeight:
                FontWeight.w700,
                color: AppTheme
                    .primaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              item.minimumStock > 0
                  ? _formatQuantity(
                item.minimumStock,
              )
                  : '—',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme
                    .secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment:
              Alignment.centerRight,
              child: Container(
                padding:
                const EdgeInsets
                    .symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration:
                BoxDecoration(
                  color: lowStock
                      ? const Color(
                    0xFFFFECEC,
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
                  lowStock
                      ? 'مخزون منخفض'
                      : 'متوفر',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight:
                    FontWeight.w600,
                    color: lowStock
                        ? const Color(
                      0xFFC92A2A,
                    )
                        : const Color(
                      0xFF248A3D,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatDate(
                item.updatedAt,
              ),
              style: const TextStyle(
                fontSize: 10.5,
                color: AppTheme
                    .tertiaryTextColor,
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  // ===========================================================================
  // FORMAT
  // ===========================================================================

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

  String _formatDate(
      DateTime date,
      ) {
    final day =
    date.day.toString().padLeft(
      2,
      '0',
    );

    final month =
    date.month.toString().padLeft(
      2,
      '0',
    );

    return '$day/$month/${date.year}';
  }

  String _errorMessage(
      Object error,
      ) {
    final message =
    error.toString();

    if (message.startsWith(
      'Bad state: ',
    )) {
      return message.replaceFirst(
        'Bad state: ',
        '',
      );
    }

    return message;
  }
}

// =============================================================================
// INVENTORY ITEM
// =============================================================================

class _WarehouseInventoryItem {
  final String productId;
  final String variantId;

  final String productName;
  final String variantName;
  final String barcode;
  final String unit;

  final double quantity;
  final double minimumStock;

  final bool isProductActive;
  final bool isVariantActive;

  final DateTime updatedAt;

  const _WarehouseInventoryItem({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.barcode,
    required this.unit,
    required this.quantity,
    required this.minimumStock,
    required this.isProductActive,
    required this.isVariantActive,
    required this.updatedAt,
  });

  bool get hasVisibleVariant {
    final clean =
    variantName.trim();

    return clean.isNotEmpty &&
        clean != 'الخيار الرئيسي';
  }
}

// =============================================================================
// WAREHOUSE INFO VALUE
// =============================================================================

class _WarehouseInfoValue
    extends StatelessWidget {
  final String title;
  final String value;

  const _WarehouseInfoValue({
    required this.title,
    required this.value,
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
            fontSize: 9.5,
            color: Color(
              0xFF8E8E93,
            ),
          ),
        ),
        const SizedBox(
          height: 5,
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight:
            FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// STAT CARD
// =============================================================================

class _DetailsStatCard
    extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  final bool highlighted;

  const _DetailsStatCard({
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
      height: 126,
      padding: const EdgeInsets.all(
        18,
      ),
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
                  height: 7,
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight:
                    FontWeight.w700,
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
            decoration: BoxDecoration(
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

// =============================================================================
// TABLE HEADER
// =============================================================================

class _InventoryTableHeader
    extends StatelessWidget {
  const _InventoryTableHeader();

  static const _style =
  TextStyle(
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
      color: const Color(
        0xFFF8F8FA,
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'المنتج / الخيار',
              style: _style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'الباركود',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الوحدة',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الكمية',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الحد الأدنى',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الحالة',
              style: _style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'آخر تحديث',
              style: _style,
            ),
          ),
        ],
      ),
    );
  }
}