import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/models/stock_movement_model.dart';
import '../../products/models/product_model.dart';
import '../models/warehouse_model.dart';
import 'warehouse_details_screen.dart';
import 'warehouse_approvals_screen.dart';

class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({
    super.key,
  });

  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  final _warehousesRepository = AppServices.warehousesRepository;

  final _inventoryRepository = AppServices.inventoryRepository;

  final _productsRepository = AppServices.productsRepository;

  List<WarehouseModel> _warehouses = [];
  List<ProductModel> _products = [];
  List<_MovementViewModel> _movements = [];

  final Map<String, _WarehouseStats> _warehouseStats = {};

  String _selectedWarehouse = 'الكل';
  String _selectedMovementType = 'الكل';

  bool _isLoading = true;
  int _movementPage = 1;
  int _movementTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ===========================================================================
  // LOAD DATA
  // ===========================================================================

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final warehouses = await _warehousesRepository.getWarehouses();

      for (final warehouse in warehouses) {
        debugPrint(
          '[WAREHOUSE LOCAL] '
              'id=${warehouse.id} '
              'name=${warehouse.name} '
              'type=${warehouse.type.databaseValue} '
              'parent=${warehouse.parentWarehouseId} '
              'branchId=${warehouse.branchId} '
              'serverId=${warehouse.serverId} '
              'status=${warehouse.status}',
        );
      }

      final movementRows = await _inventoryRepository.getMovements(
        limit: kListPageSize,
        offset: (_movementPage - 1) * kListPageSize,
      );
      final movementTotal = await _inventoryRepository.countMovements();

      final balanceRows = await AppServices.database
          .select(
        AppServices.database.stockBalances,
      )
          .get();

      final variantIds = {
        for (final balance in balanceRows) balance.variantId,
        for (final movement in movementRows) movement.variantId,
      };
      final products = <ProductModel>[];
      if (variantIds.isNotEmpty) {
        final variantRows = await (AppServices.database.select(
          AppServices.database.productVariants,
        )..where((table) => table.id.isIn(variantIds.toList())))
            .get();
        final productIds = {for (final row in variantRows) row.productId};
        for (final id in productIds) {
          final product = await _productsRepository.getProductById(id);
          if (product != null) {
            products.add(product);
          }
        }
      }

      final warehouseMap = {
        for (final warehouse in warehouses) warehouse.id: warehouse,
      };

      final variantMap = <String, _VariantLookup>{};

      for (final product in products) {
        for (final variant in product.variants) {
          if (variant.deletedAt != null) {
            continue;
          }

          variantMap[variant.id] = _VariantLookup(
            product: product,
            variantId: variant.id,
            variantName: variant.displayName,
            barcode: variant.barcode.trim().isNotEmpty
                ? variant.barcode
                : product.barcode,
          );
        }
      }

      final stats = <String, _WarehouseStats>{};

      for (final warehouse in warehouses) {
        final warehouseBalances = balanceRows.where(
              (balance) => balance.warehouseId == warehouse.id,
        );

        final productIdsInWarehouse = <String>{};

        double totalQuantity = 0;
        int lowStockCount = 0;

        for (final balance in warehouseBalances) {
          final lookup = variantMap[balance.variantId];

          if (lookup == null) {
            continue;
          }

          final product = lookup.product;

          if (balance.quantity > 0) {
            productIdsInWarehouse.add(product.id);
          }

          totalQuantity += balance.quantity;

          if (product.isActive &&
              product.minimumStock > 0 &&
              balance.quantity <= product.minimumStock) {
            lowStockCount++;
          }
        }

        stats[warehouse.id] = _WarehouseStats(
          productsCount: productIdsInWarehouse.length,
          totalQuantity: totalQuantity,
          lowStockCount: lowStockCount,
        );
      }

      final movements = movementRows.map(
            (movement) {
          final lookup = variantMap[movement.variantId];

          final warehouse = warehouseMap[movement.warehouseId];

          String? targetWarehouseName;

          if (movement.referenceType == 'TRANSFER' &&
              movement.referenceId != null) {
            for (final other in movementRows) {
              if (other.id == movement.id) {
                continue;
              }

              if (other.referenceType != 'TRANSFER' ||
                  other.referenceId != movement.referenceId) {
                continue;
              }

              if (other.warehouseId == movement.warehouseId) {
                continue;
              }

              targetWarehouseName = warehouseMap[other.warehouseId]?.name;

              if (targetWarehouseName != null) {
                break;
              }
            }
          }

          return _MovementViewModel(
            id: movement.id,
            productName: lookup == null
                ? 'منتج غير معروف'
                : _variantDisplayName(
              product: lookup.product,
              variantName: lookup.variantName,
            ),
            barcode: lookup?.barcode ?? '',
            warehouseName: warehouse?.name ?? 'مخزن غير معروف',
            targetWarehouseName: targetWarehouseName,
            type: _movementTypeFromDatabase(
              movement.type,
            ),
            quantity: movement.quantity,
            date: movement.createdAt,
            userName: movement.userId?.trim().isNotEmpty == true
                ? movement.userId!
                : 'مدير النظام',
            note: movement.note,
          );
        },
      ).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _warehouses = warehouses;
        _products = products;
        _movements = movements;
        _movementTotal = movementTotal;

        _warehouseStats
          ..clear()
          ..addAll(stats);

        if (_selectedWarehouse != 'الكل' &&
            !_warehouses.any(
                  (warehouse) => warehouse.name == _selectedWarehouse,
            )) {
          _selectedWarehouse = 'الكل';
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
  // PARENT WAREHOUSES
  // ===========================================================================

  List<WarehouseModel> _getParentCandidates({
    String? excludeWarehouseId,
  }) {
    return _warehouses.where(
          (warehouse) {
        if (warehouse.deletedAt != null) {
          return false;
        }

        if (!warehouse.isActive) {
          return false;
        }

        if (excludeWarehouseId != null &&
            warehouse.id == excludeWarehouseId) {
          return false;
        }

        return true;
      },
    ).toList();
  }

  String _parentCandidateLabel(
      WarehouseModel warehouse,
      ) {
    final syncLabel = warehouse.isSynced ? 'مزامن' : 'محلي';

    return '${warehouse.name} • ${warehouse.type.displayName} • $syncLabel';
  }

  // ===========================================================================
  // INVENTORY VARIANT CHOICES
  // ===========================================================================

  List<_InventoryVariantChoice> get _inventoryVariantChoices {
    final choices = <_InventoryVariantChoice>[];

    for (final product in _products) {
      if (!product.isActive) {
        continue;
      }

      for (final variant in product.variants) {
        if (!variant.isActive || variant.deletedAt != null) {
          continue;
        }

        choices.add(
          _InventoryVariantChoice(
            variantId: variant.id,
            productId: product.id,
            label: _variantDisplayName(
              product: product,
              variantName: variant.displayName,
            ),
            barcode: variant.barcode.trim().isNotEmpty
                ? variant.barcode
                : product.barcode,
          ),
        );
      }
    }

    return choices;
  }

  String _variantDisplayName({
    required ProductModel product,
    required String variantName,
  }) {
    final clean = variantName.trim();

    if (clean.isEmpty || clean == 'الخيار الرئيسي') {
      return product.name;
    }

    return '${product.name} - $clean';
  }

  // ===========================================================================
  // TOTALS
  // ===========================================================================

  int get _totalProducts {
    final productIds = <String>{};

    for (final product in _products) {
      if (product.isActive) {
        productIds.add(product.id);
      }
    }

    return productIds.length;
  }

  double get _totalQuantity {
    return _warehouseStats.values.fold(
      0,
          (
          sum,
          stats,
          ) =>
      sum + stats.totalQuantity,
    );
  }

  int get _lowStock {
    return _warehouseStats.values.fold(
      0,
          (
          sum,
          stats,
          ) =>
      sum + stats.lowStockCount,
    );
  }

  List<String> get _warehouseNames {
    return [
      'الكل',
      ..._warehouses.map(
            (warehouse) => warehouse.name,
      ),
    ];
  }

  List<_MovementViewModel> get _filteredMovements {
    return _movements.where(
          (movement) {
        final warehouseMatches = _selectedWarehouse == 'الكل' ||
            movement.warehouseName == _selectedWarehouse ||
            movement.targetWarehouseName == _selectedWarehouse;

        final typeMatches = _selectedMovementType == 'الكل' ||
            movement.type.title == _selectedMovementType;

        return warehouseMatches && typeMatches;
      },
    ).toList();
  }

  // =======================
  Future<void> _openWarehouseDetails(
      WarehouseModel warehouse,
      ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            WarehouseDetailsScreen(
              warehouse: warehouse,
            ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadData();
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
          : RefreshIndicator(
        onRefresh: _loadData,
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
              _buildWarehousesSection(),
              const SizedBox(
                height: 22,
              ),
              _buildMovementSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader() {
    final choices = _inventoryVariantChoices;

    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'المخازن',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: AppTheme.primaryTextColor,
                ),
              ),
              SizedBox(
                height: 6,
              ),
              Text(
                'إدارة المخازن والكميات والتحويلات وحركة المواد.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),

        // ---------------------------------------------------------------------
        // APPROVALS
        // ---------------------------------------------------------------------

        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const WarehouseApprovalsScreen(),
              ),
            );

            if (!mounted) {
              return;
            }

            await _loadData();
          },
          icon: const Icon(
            Icons.fact_check_outlined,
            size: 18,
          ),
          label: const Text(
            'الاعتمادات',
          ),
        ),

        const SizedBox(
          width: 10,
        ),

        OutlinedButton.icon(
          onPressed: _showAddWarehouseDialog,
          icon: const Icon(
            Icons.warehouse_outlined,
            size: 18,
          ),
          label: const Text(
            'إضافة مخزن',
          ),
        ),

        const SizedBox(
          width: 10,
        ),

        OutlinedButton.icon(
          onPressed: _warehouses.length < 2 || choices.isEmpty
              ? null
              : _showTransferDialog,
          icon: const Icon(
            Icons.swap_horiz_rounded,
            size: 18,
          ),
          label: const Text(
            'تحويل بين المخازن',
          ),
        ),

        const SizedBox(
          width: 10,
        ),

        ElevatedButton.icon(
          onPressed: _warehouses.isEmpty || choices.isEmpty
              ? null
              : _showStockMovementDialog,
          icon: const Icon(
            Icons.add_rounded,
            size: 18,
          ),
          label: const Text(
            'حركة مخزون',
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // STATS
  // ===========================================================================

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: 'عدد المخازن',
            value: '${_warehouses.length}',
            subtitle: 'مخازن مرتبطة بالنظام',
            icon: Icons.warehouse_outlined,
            highlighted: true,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _StatCard(
            title: 'إجمالي الأصناف',
            value: _formatNumber(
              _totalProducts,
            ),
            subtitle: 'أصناف مسجلة بالنظام',
            icon: Icons.inventory_2_outlined,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _StatCard(
            title: 'إجمالي الكمية',
            value: _formatQuantity(
              _totalQuantity,
            ),
            subtitle: 'وحدة مخزنية',
            icon: Icons.layers_outlined,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _StatCard(
            title: 'نقص المخزون',
            value: '$_lowStock',
            subtitle: 'خيار تحت الحد الأدنى',
            icon: Icons.warning_amber_rounded,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // WAREHOUSES
  // ===========================================================================

  Widget _buildWarehousesSection() {
    if (_warehouses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: 60,
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
        child: const Column(
          children: [
            Icon(
              Icons.warehouse_outlined,
              size: 42,
              color: AppTheme.tertiaryTextColor,
            ),
            SizedBox(
              height: 12,
            ),
            Text(
              'لا توجد مخازن بعد.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryTextColor,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'المخازن والفروع',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryTextColor,
          ),
        ),
        const SizedBox(
          height: 5,
        ),
        const Text(
          'ملخص سريع عن حالة كل مخزن.',
          style: TextStyle(
            fontSize: 11.5,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(
          height: 14,
        ),
        LayoutBuilder(
          builder: (
              context,
              constraints,
              ) {
            int columns;

            if (constraints.maxWidth >= 1150) {
              columns = 3;
            } else if (constraints.maxWidth >= 720) {
              columns = 2;
            } else {
              columns = 1;
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _warehouses.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                mainAxisExtent: 210,
              ),
              itemBuilder: (
                  context,
                  index,
                  ) {
                final warehouse = _warehouses[index];

                final stats = _warehouseStats[warehouse.id] ??
                    const _WarehouseStats();

                return _WarehouseCard(
                  warehouse: warehouse,
                  stats: stats,
                  parentWarehouseName: _parentWarehouseName(
                    warehouse,
                  ),
                  onOpen: () {

                    _openWarehouseDetails(

                      warehouse,

                    );

                  },
                  onEdit: () {
                    if (warehouse.isSynced) {
                      _showSyncedWarehouseEditBlockedDialog(
                        warehouse,
                      );

                      return;
                    }

                    _showEditWarehouseDialog(
                      warehouse,
                    );
                  },
                  onToggleActive: () {
                    _toggleWarehouse(
                      warehouse,
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  String? _parentWarehouseName(
      WarehouseModel warehouse,
      ) {
    final parentId = warehouse.parentWarehouseId;

    if (parentId == null || parentId.trim().isEmpty) {
      return null;
    }

    for (final parent in _warehouses) {
      if (parent.id == parentId) {
        return parent.name;
      }
    }

    return null;
  }

  // ===========================================================================
  // MOVEMENTS
  // ===========================================================================

  Widget _buildMovementSection() {
    final movements = _filteredMovements;

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
              20,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'حركة المخزون',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryTextColor,
                        ),
                      ),
                      SizedBox(
                        height: 4,
                      ),
                      Text(
                        'سجل عمليات الإدخال والإخراج والتحويل والتسوية.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: _buildDropdown(
                    value: _selectedWarehouse,
                    items: _warehouseNames,
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _selectedWarehouse = value;
                      });
                    },
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                SizedBox(
                  width: 150,
                  child: _buildDropdown(
                    value: _selectedMovementType,
                    items: const [
                      'الكل',
                      'إدخال',
                      'إخراج',
                      'تحويل',
                      'تسوية',
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _selectedMovementType = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            color: AppTheme.subtleBorderColor,
          ),
          const _MovementTableHeader(),
          if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 50,
              ),
              child: Text(
                'لا توجد حركات مطابقة.',
                style: TextStyle(
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            )
          else
            ...movements.map(
              _buildMovementRow,
            ),
          ListPagination(
            page: _movementPage,
            totalItems: _movementTotal,
            onPageChanged: (page) {
              setState(() {
                _movementPage = page;
              });
              _loadData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMovementRow(
      _MovementViewModel movement,
      ) {
    return Container(
      height: 66,
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.productName,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  movement.barcode,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _MovementTypeBadge(
              type: movement.type,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              movement.type == _MovementUiType.transfer &&
                  movement.targetWarehouseName != null
                  ? '${movement.warehouseName} ← ${movement.targetWarehouseName}'
                  : movement.warehouseName,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatQuantity(
                movement.quantity,
              ),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatDate(
                movement.date,
              ),
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              movement.userName,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              tooltip: movement.note?.trim().isNotEmpty == true
                  ? movement.note!
                  : 'بدون ملاحظة',
              onPressed: () {},
              icon: const Icon(
                Icons.more_horiz_rounded,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // DROPDOWN
  // ===========================================================================

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          11,
        ),
        border: Border.all(
          color: AppTheme.borderColor,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
          ),
          style: const TextStyle(
            fontSize: 11.5,
            color: AppTheme.primaryTextColor,
          ),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
              ),
            ),
          )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ===========================================================================
  // ADD WAREHOUSE
  // ===========================================================================

  Future<void> _showAddWarehouseDialog() async {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final addressController = TextEditingController();
    final notesController = TextEditingController();

    WarehouseType selectedType = WarehouseType.main;

    String? selectedParentWarehouseId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
              dialogContext,
              setDialogState,
              ) {
            final parentCandidates = _getParentCandidates();

            if (selectedType == WarehouseType.sub &&
                parentCandidates.isNotEmpty &&
                (selectedParentWarehouseId == null ||
                    !parentCandidates.any(
                          (warehouse) =>
                      warehouse.id == selectedParentWarehouseId,
                    ))) {
              selectedParentWarehouseId = parentCandidates.first.id;
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text(
                  'إضافة مخزن',
                ),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DialogField(
                          title: 'اسم المخزن',
                          controller: nameController,
                          hint: 'مثال: المخزن الرئيسي',
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        _DialogField(
                          title: 'رمز المخزن',
                          controller: codeController,
                          hint: 'WH-001',
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        _DialogDropdown(
                          title: 'نوع المخزن',
                          value: selectedType.databaseValue,
                          items: const [
                            'MAIN',
                            'SUB',
                            'VIRTUAL',
                          ],
                          labels: const {
                            'MAIN': 'مخزن رئيسي',
                            'SUB': 'مخزن فرعي',
                            'VIRTUAL': 'مخزن افتراضي',
                          },
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }

                            setDialogState(
                                  () {
                                selectedType =
                                    WarehouseTypeExtension.fromValue(
                                      value,
                                    );

                                if (selectedType != WarehouseType.sub) {
                                  selectedParentWarehouseId = null;
                                } else if (parentCandidates.isNotEmpty) {
                                  selectedParentWarehouseId ??=
                                      parentCandidates.first.id;
                                }
                              },
                            );
                          },
                        ),
                        if (selectedType == WarehouseType.sub) ...[
                          const SizedBox(
                            height: 14,
                          ),
                          if (parentCandidates.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFF4E5,
                                ),
                                borderRadius: BorderRadius.circular(
                                  10,
                                ),
                              ),
                              child: const Text(
                                'لا يوجد مخزن آخر يمكن اختياره كمخزن أب. '
                                    'أنشئ المخزن الرئيسي أولاً.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(
                                    0xFF8A5700,
                                  ),
                                ),
                              ),
                            )
                          else
                            _DialogDropdown(
                              title: 'المخزن الأب',
                              value: selectedParentWarehouseId ??
                                  parentCandidates.first.id,
                              items: parentCandidates
                                  .map(
                                    (warehouse) => warehouse.id,
                              )
                                  .toList(),
                              labels: {
                                for (final warehouse in parentCandidates)
                                  warehouse.id: _parentCandidateLabel(
                                    warehouse,
                                  ),
                              },
                              onChanged: (value) {
                                setDialogState(
                                      () {
                                    selectedParentWarehouseId = value;
                                  },
                                );
                              },
                            ),
                        ],
                        const SizedBox(
                          height: 14,
                        ),
                        _DialogField(
                          title: 'العنوان',
                          controller: addressController,
                          hint: 'عنوان المخزن',
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        _DialogField(
                          title: 'ملاحظات',
                          controller: notesController,
                          hint: 'ملاحظة اختيارية',
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                      );
                    },
                    child: const Text(
                      'إلغاء',
                    ),
                  ),
                  ElevatedButton(
                    onPressed: selectedType == WarehouseType.sub &&
                        selectedParentWarehouseId == null
                        ? null
                        : () async {
                      final name = nameController.text.trim();

                      if (name.isEmpty) {
                        _showMessage(
                          'اسم المخزن مطلوب.',
                        );

                        return;
                      }

                      try {
                        await _warehousesRepository.createWarehouse(
                          name: name,
                          code: codeController.text,
                          type: selectedType,
                          parentWarehouseId:
                          selectedType == WarehouseType.sub
                              ? selectedParentWarehouseId
                              : null,
                          address: addressController.text,
                          notes: notesController.text,
                        );

                        if (!dialogContext.mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                        );

                        await _loadData();

                        await AppServices.syncNow();

                        await _loadData();
                      } catch (error) {
                        if (!mounted) {
                          return;
                        }

                        _showMessage(
                          _errorMessage(
                            error,
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'حفظ المخزن',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    codeController.dispose();
    addressController.dispose();
    notesController.dispose();
  }

  // ===========================================================================
  // SYNCED WAREHOUSE EDIT BLOCK
  // ===========================================================================

  Future<void> _showSyncedWarehouseEditBlockedDialog(
      WarehouseModel warehouse,
      ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'تعديل المخزن',
            ),
            content: SizedBox(
              width: 470,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReadOnlyInfoField(
                    title: 'اسم المخزن',
                    value: warehouse.name,
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  _ReadOnlyInfoField(
                    title: 'رمز المخزن',
                    value: warehouse.code?.trim().isNotEmpty == true
                        ? warehouse.code!
                        : 'بدون رمز',
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  _ReadOnlyInfoField(
                    title: 'نوع المخزن',
                    value: warehouse.type.displayName,
                  ),
                  if (warehouse.type == WarehouseType.sub) ...[
                    const SizedBox(
                      height: 12,
                    ),
                    _ReadOnlyInfoField(
                      title: 'المخزن الأب',
                      value: _parentWarehouseName(
                        warehouse,
                      ) ??
                          'غير محدد',
                    ),
                  ],
                  const SizedBox(
                    height: 16,
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(
                      13,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFFFFF4E5,
                      ),
                      borderRadius: BorderRadius.circular(
                        11,
                      ),
                      border: Border.all(
                        color: const Color(
                          0xFFFFD59A,
                        ),
                      ),
                    ),
                    child: const Text(
                      'هذا المخزن مربوط بالسيرفر. '
                          'تم إيقاف التعديل مؤقتاً لأن الـBackend لا يوفر حالياً '
                          'واجهة مؤكدة لتعديل بيانات المخزن أو نوعه أو المخزن الأب. '
                          'هذا يمنع اختلاف البيانات بين الجهاز والسيرفر.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.6,
                        color: Color(
                          0xFF8A5700,
                        ),
                      ),
                    ),
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
                child: const Text(
                  'حسناً',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // EDIT LOCAL WAREHOUSE
  // ===========================================================================

  Future<void> _showEditWarehouseDialog(
      WarehouseModel warehouse,
      ) async {
    final nameController = TextEditingController(
      text: warehouse.name,
    );

    final codeController = TextEditingController(
      text: warehouse.code ?? '',
    );

    final addressController = TextEditingController(
      text: warehouse.address ?? '',
    );

    final notesController = TextEditingController(
      text: warehouse.notes ?? '',
    );

    WarehouseType selectedType = warehouse.type;

    String? selectedParentWarehouseId = warehouse.parentWarehouseId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
              dialogContext,
              setDialogState,
              ) {
            final parentCandidates = _getParentCandidates(
              excludeWarehouseId: warehouse.id,
            );

            if (selectedType == WarehouseType.sub &&
                parentCandidates.isNotEmpty &&
                (selectedParentWarehouseId == null ||
                    !parentCandidates.any(
                          (candidate) =>
                      candidate.id == selectedParentWarehouseId,
                    ))) {
              selectedParentWarehouseId = parentCandidates.first.id;
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text(
                  'تعديل المخزن',
                ),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DialogField(
                          title: 'اسم المخزن',
                          controller: nameController,
                          hint: 'اسم المخزن',
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        _DialogField(
                          title: 'رمز المخزن',
                          controller: codeController,
                          hint: 'WH-001',
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        _DialogDropdown(
                          title: 'نوع المخزن',
                          value: selectedType.databaseValue,
                          items: const [
                            'MAIN',
                            'SUB',
                            'VIRTUAL',
                          ],
                          labels: const {
                            'MAIN': 'مخزن رئيسي',
                            'SUB': 'مخزن فرعي',
                            'VIRTUAL': 'مخزن افتراضي',
                          },
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }

                            setDialogState(
                                  () {
                                selectedType =
                                    WarehouseTypeExtension.fromValue(
                                      value,
                                    );

                                if (selectedType != WarehouseType.sub) {
                                  selectedParentWarehouseId = null;
                                } else if (parentCandidates.isNotEmpty) {
                                  selectedParentWarehouseId ??=
                                      parentCandidates.first.id;
                                }
                              },
                            );
                          },
                        ),
                        if (selectedType == WarehouseType.sub) ...[
                          const SizedBox(
                            height: 14,
                          ),
                          if (parentCandidates.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFF4E5,
                                ),
                                borderRadius: BorderRadius.circular(
                                  10,
                                ),
                              ),
                              child: const Text(
                                'لا يوجد مخزن آخر يمكن اختياره كمخزن أب.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(
                                    0xFF8A5700,
                                  ),
                                ),
                              ),
                            )
                          else
                            _DialogDropdown(
                              title: 'المخزن الأب',
                              value: parentCandidates.any(
                                    (candidate) =>
                                candidate.id ==
                                    selectedParentWarehouseId,
                              )
                                  ? selectedParentWarehouseId!
                                  : parentCandidates.first.id,
                              items: parentCandidates
                                  .map(
                                    (candidate) => candidate.id,
                              )
                                  .toList(),
                              labels: {
                                for (final parent in parentCandidates)
                                  parent.id: _parentCandidateLabel(
                                    parent,
                                  ),
                              },
                              onChanged: (value) {
                                setDialogState(
                                      () {
                                    selectedParentWarehouseId = value;
                                  },
                                );
                              },
                            ),
                        ],
                        const SizedBox(
                          height: 14,
                        ),
                        _DialogField(
                          title: 'العنوان',
                          controller: addressController,
                          hint: 'عنوان المخزن',
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        _DialogField(
                          title: 'ملاحظات',
                          controller: notesController,
                          hint: 'ملاحظة اختيارية',
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                      );
                    },
                    child: const Text(
                      'إلغاء',
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (selectedType == WarehouseType.sub &&
                          selectedParentWarehouseId == null) {
                        _showMessage(
                          'اختر المخزن الأب.',
                        );

                        return;
                      }

                      final name = nameController.text.trim();

                      if (name.isEmpty) {
                        _showMessage(
                          'اسم المخزن مطلوب.',
                        );

                        return;
                      }

                      try {
                        final updated = warehouse.copyWith(
                          name: name,
                          code: codeController.text.trim(),
                          type: selectedType,
                          parentWarehouseId:
                          selectedType == WarehouseType.sub
                              ? selectedParentWarehouseId
                              : null,
                          clearParentWarehouseId:
                          selectedType != WarehouseType.sub,
                          isMain: selectedType == WarehouseType.main,
                          address: addressController.text.trim(),
                          notes: notesController.text.trim(),
                          updatedAt: DateTime.now(),
                        );

                        debugPrint(
                          '[WAREHOUSE EDIT LOCAL] '
                              'id=${updated.id} '
                              'name=${updated.name} '
                              'type=${updated.type.databaseValue} '
                              'parent=${updated.parentWarehouseId}',
                        );

                        await _warehousesRepository.updateWarehouse(
                          updated,
                        );

                        if (!dialogContext.mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                        );

                        await _loadData();

                        await AppServices.syncNow();

                        await _loadData();
                      } catch (error) {
                        if (!mounted) {
                          return;
                        }

                        _showMessage(
                          _errorMessage(
                            error,
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'حفظ التعديلات',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    codeController.dispose();
    addressController.dispose();
    notesController.dispose();
  }

  // ===========================================================================
  // TOGGLE WAREHOUSE
  // ===========================================================================

  Future<void> _toggleWarehouse(
      WarehouseModel warehouse,
      ) async {
    if (warehouse.isSynced && !warehouse.isActive) {
      _showMessage(
        'لا يمكن إعادة تفعيل المخزن حالياً لأن '
            'واجهة إعادة التفعيل غير متوفرة في الـBackend.',
      );

      return;
    }

    try {
      await _warehousesRepository.setActive(
        warehouse: warehouse,
        isActive: !warehouse.isActive,
      );

      await _loadData();

      await AppServices.syncNow();

      await _loadData();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _errorMessage(
          error,
        ),
      );
    }
  }

  // ===========================================================================
  // STOCK MOVEMENT DIALOG
  // ===========================================================================

  Future<void> _showStockMovementDialog() async {
    final choices = _inventoryVariantChoices;

    if (_warehouses.isEmpty || choices.isEmpty) {
      _showMessage(
        'لا توجد منتجات تحتوي على خيارات مخزون صالحة.',
      );

      return;
    }

    String selectedType = 'إدخال';

    String selectedWarehouseId = _warehouses.first.id;

    String selectedVariantId = choices.first.variantId;

    final quantityController = TextEditingController();

    final noteController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text(
                  'إضافة حركة مخزون',
                ),
                content: SizedBox(
                  width: 560,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DialogDropdown(
                        title: 'نوع الحركة',
                        value: selectedType,
                        items: const [
                          'إدخال',
                          'إخراج',
                          'تسوية',
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(
                                () {
                              selectedType = value;
                            },
                          );
                        },
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      _DialogDropdown(
                        title: 'المخزن',
                        value: selectedWarehouseId,
                        items: _warehouses
                            .map(
                              (warehouse) => warehouse.id,
                        )
                            .toList(),
                        labels: {
                          for (final warehouse in _warehouses)
                            warehouse.id: warehouse.name,
                        },
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(
                                () {
                              selectedWarehouseId = value;
                            },
                          );
                        },
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      _DialogDropdown(
                        title: 'المنتج / الخيار',
                        value: selectedVariantId,
                        items: choices
                            .map(
                              (choice) => choice.variantId,
                        )
                            .toList(),
                        labels: {
                          for (final choice in choices)
                            choice.variantId: choice.barcode.trim().isEmpty
                                ? choice.label
                                : '${choice.label} — ${choice.barcode}',
                        },
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(
                                () {
                              selectedVariantId = value;
                            },
                          );
                        },
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      _DialogField(
                        title: 'الكمية',
                        controller: quantityController,
                        hint: '0',
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
                    onPressed: () {
                      Navigator.pop(
                        context,
                      );
                    },
                    child: const Text(
                      'إلغاء',
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final quantity = double.tryParse(
                        quantityController.text.trim(),
                      ) ??
                          0;

                      if (quantity <= 0) {
                        _showMessage(
                          'أدخل كمية صحيحة.',
                        );

                        return;
                      }

                      final type = switch (selectedType) {
                        'إخراج' => StockMovementType.adjustmentOut,
                        'تسوية' => StockMovementType.adjustmentIn,
                        _ => StockMovementType.adjustmentIn,
                      };

                      try {
                        await _inventoryRepository.addMovement(
                          variantId: selectedVariantId,
                          warehouseId: selectedWarehouseId,
                          type: type,
                          quantity: quantity,
                          referenceType: 'MANUAL',
                          note: noteController.text,
                        );

                        if (!context.mounted) {
                          return;
                        }

                        Navigator.pop(
                          context,
                        );

                        await _loadData();
                      } catch (error) {
                        if (!mounted) {
                          return;
                        }

                        _showMessage(
                          _errorMessage(
                            error,
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'حفظ الحركة',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    quantityController.dispose();
    noteController.dispose();
  }

  // ===========================================================================
  // TRANSFER DIALOG
  // ===========================================================================

  Future<void> _showTransferDialog() async {
    final choices = _inventoryVariantChoices;

    if (_warehouses.length < 2 || choices.isEmpty) {
      return;
    }

    String fromWarehouseId = _warehouses.first.id;

    String toWarehouseId = _warehouses[1].id;

    String selectedVariantId = choices.first.variantId;

    final quantityController = TextEditingController();

    final noteController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text(
                  'تحويل بين المخازن',
                ),
                content: SizedBox(
                  width: 580,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _DialogDropdown(
                              title: 'من مخزن',
                              value: fromWarehouseId,
                              items: _warehouses
                                  .map(
                                    (warehouse) => warehouse.id,
                              )
                                  .toList(),
                              labels: {
                                for (final warehouse in _warehouses)
                                  warehouse.id: warehouse.name,
                              },
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }

                                setDialogState(
                                      () {
                                    fromWarehouseId = value;
                                  },
                                );
                              },
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(
                              14,
                              24,
                              14,
                              0,
                            ),
                            child: Icon(
                              Icons.arrow_forward,
                              size: 20,
                            ),
                          ),
                          Expanded(
                            child: _DialogDropdown(
                              title: 'إلى مخزن',
                              value: toWarehouseId,
                              items: _warehouses
                                  .map(
                                    (warehouse) => warehouse.id,
                              )
                                  .toList(),
                              labels: {
                                for (final warehouse in _warehouses)
                                  warehouse.id: warehouse.name,
                              },
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }

                                setDialogState(
                                      () {
                                    toWarehouseId = value;
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      _DialogDropdown(
                        title: 'المنتج / الخيار',
                        value: selectedVariantId,
                        items: choices
                            .map(
                              (choice) => choice.variantId,
                        )
                            .toList(),
                        labels: {
                          for (final choice in choices)
                            choice.variantId: choice.barcode.trim().isEmpty
                                ? choice.label
                                : '${choice.label} — ${choice.barcode}',
                        },
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(
                                () {
                              selectedVariantId = value;
                            },
                          );
                        },
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      _DialogField(
                        title: 'الكمية',
                        controller: quantityController,
                        hint: '0',
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      _DialogField(
                        title: 'ملاحظة',
                        controller: noteController,
                        hint: 'سبب التحويل أو ملاحظة',
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                      );
                    },
                    child: const Text(
                      'إلغاء',
                    ),
                  ),
                  ElevatedButton(
                    onPressed: fromWarehouseId == toWarehouseId
                        ? null
                        : () async {
                      final quantity = double.tryParse(
                        quantityController.text.trim(),
                      ) ??
                          0;

                      if (quantity <= 0) {
                        _showMessage(
                          'أدخل كمية صحيحة.',
                        );

                        return;
                      }

                      try {
                        await _inventoryRepository.transferStock(
                          variantId: selectedVariantId,
                          fromWarehouseId: fromWarehouseId,
                          toWarehouseId: toWarehouseId,
                          quantity: quantity,
                          note: noteController.text,
                        );

                        if (!context.mounted) {
                          return;
                        }

                        Navigator.pop(
                          context,
                        );

                        await _loadData();
                      } catch (error) {
                        if (!mounted) {
                          return;
                        }

                        _showMessage(
                          _errorMessage(
                            error,
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'تأكيد التحويل',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    quantityController.dispose();
    noteController.dispose();
  }

  // ===========================================================================
  // MOVEMENT TYPE
  // ===========================================================================

  _MovementUiType _movementTypeFromDatabase(
      String value,
      ) {
    switch (value) {
      case 'PURCHASE':
      case 'RETURN_IN':
      case 'ADJUSTMENT_IN':
        return _MovementUiType.stockIn;

      case 'SALE':
      case 'RETURN_OUT':
      case 'ADJUSTMENT_OUT':
        return _MovementUiType.stockOut;

      case 'TRANSFER_IN':
      case 'TRANSFER_OUT':
        return _MovementUiType.transfer;

      default:
        return _MovementUiType.adjustment;
    }
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  String _errorMessage(
      Object error,
      ) {
    final message = error.toString();

    if (message.startsWith(
      'Bad state: ',
    )) {
      return message.replaceFirst(
        'Bad state: ',
        '',
      );
    }

    if (message.startsWith(
      'Invalid argument(s): ',
    )) {
      return message.replaceFirst(
        'Invalid argument(s): ',
        '',
      );
    }

    return message;
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

  // ===========================================================================
  // FORMAT
  // ===========================================================================

  String _formatNumber(
      int value,
      ) {
    final text = value.toString();

    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) {
        buffer.write(',');
      }

      buffer.write(
        text[i],
      );
    }

    return buffer.toString();
  }

  String _formatQuantity(
      double value,
      ) {
    if (value == value.roundToDouble()) {
      return _formatNumber(
        value.toInt(),
      );
    }

    return value.toStringAsFixed(
      2,
    );
  }

  String _formatDate(
      DateTime date,
      ) {
    final day = date.day.toString().padLeft(
      2,
      '0',
    );

    final month = date.month.toString().padLeft(
      2,
      '0',
    );

    final hour12 = date.hour > 12
        ? date.hour - 12
        : date.hour == 0
        ? 12
        : date.hour;

    final minute = date.minute.toString().padLeft(
      2,
      '0',
    );

    final period = date.hour >= 12 ? 'م' : 'ص';

    return '$day/$month/${date.year} - '
        '$hour12:$minute $period';
  }
}

// =============================================================================
// VARIANT LOOKUP
// =============================================================================

class _VariantLookup {
  final ProductModel product;

  final String variantId;
  final String variantName;
  final String barcode;

  const _VariantLookup({
    required this.product,
    required this.variantId,
    required this.variantName,
    required this.barcode,
  });
}

// =============================================================================
// INVENTORY VARIANT CHOICE
// =============================================================================

class _InventoryVariantChoice {
  final String variantId;
  final String productId;

  final String label;
  final String barcode;

  const _InventoryVariantChoice({
    required this.variantId,
    required this.productId,
    required this.label,
    required this.barcode,
  });
}

// =============================================================================
// WAREHOUSE STATS
// =============================================================================

class _WarehouseStats {
  final int productsCount;
  final double totalQuantity;
  final int lowStockCount;

  const _WarehouseStats({
    this.productsCount = 0,
    this.totalQuantity = 0,
    this.lowStockCount = 0,
  });
}

// =============================================================================
// MOVEMENT UI TYPE
// =============================================================================

enum _MovementUiType {
  stockIn,
  stockOut,
  transfer,
  adjustment,
}

extension on _MovementUiType {
  String get title {
    switch (this) {
      case _MovementUiType.stockIn:
        return 'إدخال';

      case _MovementUiType.stockOut:
        return 'إخراج';

      case _MovementUiType.transfer:
        return 'تحويل';

      case _MovementUiType.adjustment:
        return 'تسوية';
    }
  }
}

// =============================================================================
// MOVEMENT VIEW MODEL
// =============================================================================

class _MovementViewModel {
  final String id;

  final String productName;
  final String barcode;

  final String warehouseName;
  final String? targetWarehouseName;

  final _MovementUiType type;

  final double quantity;

  final DateTime date;

  final String userName;
  final String? note;

  const _MovementViewModel({
    required this.id,
    required this.productName,
    required this.barcode,
    required this.warehouseName,
    this.targetWarehouseName,
    required this.type,
    required this.quantity,
    required this.date,
    required this.userName,
    this.note,
  });
}

// =============================================================================
// WAREHOUSE CARD
// =============================================================================

class _WarehouseCard extends StatelessWidget {
  final WarehouseModel warehouse;
  final _WarehouseStats stats;

  final String? parentWarehouseName;

  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  const _WarehouseCard({
    required this.warehouse,
    required this.stats,
    required this.parentWarehouseName,
    required this.onOpen,
    required this.onEdit,
    required this.onToggleActive,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final dark = warehouse.isMain;

    return MouseRegion(

        cursor: SystemMouseCursors.click,

        child: GestureDetector(

        behavior: HitTestBehavior.opaque,

        onTap: onOpen,

        child: Container(
      height: 210,
      padding: const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        color: dark
            ? const Color(
          0xFF1D1D1F,
        )
            : Colors.white,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: dark
            ? null
            : Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: dark
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
                  _warehouseIcon(
                    warehouse.type,
                  ),
                  size: 19,
                  color: dark ? Colors.white : AppTheme.primaryTextColor,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              _WarehouseTypeBadge(
                type: warehouse.type,
                dark: dark,
              ),
              const Spacer(),
              if (!warehouse.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.white.withValues(
                      alpha: 0.10,
                    )
                        : const Color(
                      0xFFFFECEC,
                    ),
                    borderRadius: BorderRadius.circular(
                      20,
                    ),
                  ),
                  child: Text(
                    'موقوف',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: dark ? Colors.white : AppTheme.dangerColor,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: 'خيارات',
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  }

                  if (value == 'toggle') {
                    onToggleActive();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text(
                      'تعديل',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      warehouse.isActive ? 'إيقاف المخزن' : 'تفعيل المخزن',
                    ),
                  ),
                ],
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: dark ? Colors.white : AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            warehouse.name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: dark ? Colors.white : AppTheme.primaryTextColor,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            warehouse.address?.trim().isNotEmpty == true
                ? warehouse.address!
                : warehouse.code ?? 'بدون عنوان',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: dark
                  ? const Color(
                0xFFB8B8BD,
              )
                  : AppTheme.secondaryTextColor,
            ),
          ),
          if (warehouse.type == WarehouseType.sub &&
              parentWarehouseName != null) ...[
            const SizedBox(
              height: 4,
            ),
            Text(
              'تابع إلى: $parentWarehouseName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                color: dark
                    ? const Color(
                  0xFF8E8E93,
                )
                    : AppTheme.tertiaryTextColor,
              ),
            ),
          ],
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _WarehouseMetric(
                  title: 'الأصناف',
                  value: '${stats.productsCount}',
                  dark: dark,
                ),
              ),
              Expanded(
                child: _WarehouseMetric(
                  title: 'الكمية',
                  value: stats.totalQuantity ==
                      stats.totalQuantity.roundToDouble()
                      ? '${stats.totalQuantity.toInt()}'
                      : stats.totalQuantity.toStringAsFixed(
                    2,
                  ),
                  dark: dark,
                ),
              ),
              Expanded(
                child: _WarehouseMetric(
                  title: 'تنبيه',
                  value: '${stats.lowStockCount}',
                  dark: dark,
                ),
              ),
            ],
          ),
        ],
      ),
    )
    ),
    );//////////////
  }

  IconData _warehouseIcon(
      WarehouseType type,
      ) {
    switch (type) {
      case WarehouseType.main:
        return Icons.warehouse_outlined;

      case WarehouseType.sub:
        return Icons.inventory_2_outlined;

      case WarehouseType.virtual:
        return Icons.cloud_outlined;
    }
  }
}

// =============================================================================
// WAREHOUSE TYPE BADGE
// =============================================================================

class _WarehouseTypeBadge extends StatelessWidget {
  final WarehouseType type;
  final bool dark;

  const _WarehouseTypeBadge({
    required this.type,
    required this.dark,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(
          alpha: 0.10,
        )
            : const Color(
          0xFFF5F5F7,
        ),
        borderRadius: BorderRadius.circular(
          20,
        ),
      ),
      child: Text(
        type.displayName,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: dark ? Colors.white : AppTheme.secondaryTextColor,
        ),
      ),
    );
  }
}

// =============================================================================
// WAREHOUSE METRIC
// =============================================================================

class _WarehouseMetric extends StatelessWidget {
  final String title;
  final String value;
  final bool dark;

  const _WarehouseMetric({
    required this.title,
    required this.value,
    required this.dark,
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
          style: TextStyle(
            fontSize: 9.5,
            color: dark
                ? const Color(
              0xFF8E8E93,
            )
                : AppTheme.tertiaryTextColor,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: dark ? Colors.white : AppTheme.primaryTextColor,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// MOVEMENT TABLE HEADER
// =============================================================================

class _MovementTableHeader extends StatelessWidget {
  const _MovementTableHeader();

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
      color: const Color(
        0xFFF8F8FA,
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'المنتج / الخيار',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الحركة',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'المخزن',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الكمية',
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'التاريخ',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'المستخدم',
              style: style,
            ),
          ),
          SizedBox(
            width: 40,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MOVEMENT BADGE
// =============================================================================

class _MovementTypeBadge extends StatelessWidget {
  final _MovementUiType type;

  const _MovementTypeBadge({
    required this.type,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    late Color background;
    late Color foreground;

    switch (type) {
      case _MovementUiType.stockIn:
        background = const Color(
          0xFFEAF7EE,
        );

        foreground = const Color(
          0xFF248A3D,
        );
        break;

      case _MovementUiType.stockOut:
        background = const Color(
          0xFFFFECEC,
        );

        foreground = const Color(
          0xFFC92A2A,
        );
        break;

      case _MovementUiType.transfer:
        background = const Color(
          0xFFEEF4FF,
        );

        foreground = const Color(
          0xFF3567C8,
        );
        break;

      case _MovementUiType.adjustment:
        background = const Color(
          0xFFFFF4E5,
        );

        foreground = const Color(
          0xFFB26A00,
        );
        break;
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(
            20,
          ),
        ),
        child: Text(
          type.title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// STAT CARD
// =============================================================================

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
      padding: const EdgeInsets.all(
        18,
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
                  style: TextStyle(
                    fontSize: 23,
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

// =============================================================================
// DIALOG FIELD
// =============================================================================

class _DialogField extends StatelessWidget {
  final String title;

  final TextEditingController controller;

  final String hint;

  const _DialogField({
    required this.title,
    required this.controller,
    required this.hint,
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
          decoration: InputDecoration(
            hintText: hint,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// DIALOG DROPDOWN
// =============================================================================

class _DialogDropdown extends StatelessWidget {
  final String title;
  final String value;

  final List<String> items;

  final Map<String, String>? labels;

  final ValueChanged<String?> onChanged;

  const _DialogDropdown({
    required this.title,
    required this.value,
    required this.items,
    this.labels,
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
        DropdownButtonFormField<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                labels?[item] ?? item,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// =============================================================================
// READ ONLY INFO FIELD
// =============================================================================

class _ReadOnlyInfoField extends StatelessWidget {
  final String title;
  final String value;

  const _ReadOnlyInfoField({
    required this.title,
    required this.value,
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 13,
          ),
          decoration: BoxDecoration(
            color: const Color(
              0xFFF5F5F7,
            ),
            borderRadius: BorderRadius.circular(
              10,
            ),
            border: Border.all(
              color: AppTheme.subtleBorderColor,
            ),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.primaryTextColor,
            ),
          ),
        ),
      ],
    );
  }
}