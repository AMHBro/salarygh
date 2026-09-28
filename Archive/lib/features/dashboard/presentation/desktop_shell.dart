import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/auth/auth_user.dart';
import '../../../core/di/app_services.dart';
import '../../../core/floor/floor_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../alira/presentation/agent_app.dart';
import '../../alira/presentation/shop_app.dart';
import '../../archive/presentation/archive_screen.dart';
import '../../customers/presentation/customers_screen.dart';
import '../../ecommerce/presentation/ecommerce_orders_screen.dart';
import '../../finance/presentation/capital_screen.dart';
import '../../finance/presentation/finance_screen.dart';
import '../../products/data/carton_sample.dart';
import '../../products/presentation/products_screen.dart';
import '../../purchases/presentation/purchases_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../representatives/presentation/representatives_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../users/presentation/office_activity_screen.dart';
import '../../users/presentation/stations_screen.dart';
import '../../sales/presentation/sale_conflicts_screen.dart';
import '../../sales/presentation/sales_screen.dart';
import '../../suppliers/presentation/suppliers_screen.dart';
import '../../warehouses/presentation/warehouses_screen.dart';
import '../data/dashboard_repository.dart';
import 'dashboard_screen.dart';

class DesktopShell extends StatefulWidget {
  final VoidCallback onLogout;

  const DesktopShell({
    super.key,
    required this.onLogout,
  });

  @override
  State<DesktopShell> createState() =>
      _DesktopShellState();
}

class _DesktopShellState
    extends State<DesktopShell> {
  int selectedIndex = 0;
  String _role = '';
  int _pendingStoreOrders = 0;
  int _openSaleConflicts = 0;
  Timer? _storeOrderBadgeTimer;

  bool _isLoggingOut = false;

  late final DashboardRepository
  _dashboardRepository;

  final List<_MenuItem> menuItems =
  const [
    _MenuItem(
      title: 'لوحة التحكم',
      icon: Icons.space_dashboard_outlined,
      selectedIcon:
      Icons.space_dashboard_rounded,
    ),
    _MenuItem(
      title: 'المبيعات',
      icon: Icons.point_of_sale_outlined,
      selectedIcon:
      Icons.point_of_sale_rounded,
    ),
    _MenuItem(
      title: 'طلبات المتجر',
      icon: Icons.shopping_bag_outlined,
      selectedIcon:
      Icons.shopping_bag_rounded,
    ),
    _MenuItem(
      title: 'الديون والدفعات',
      icon: Icons.payments_outlined,
      selectedIcon:
      Icons.payments_rounded,
    ),
    _MenuItem(
      title: 'المنتجات',
      icon: Icons.inventory_2_outlined,
      selectedIcon:
      Icons.inventory_2_rounded,
    ),
    _MenuItem(
      title: 'المخازن',
      icon: Icons.warehouse_outlined,
      selectedIcon:
      Icons.warehouse_rounded,
    ),
    _MenuItem(
      title: 'المشتريات',
      icon: Icons.shopping_bag_outlined,
      selectedIcon:
      Icons.shopping_bag_rounded,
    ),
    _MenuItem(
      title: 'الزبائن',
      icon: Icons.people_outline_rounded,
      selectedIcon:
      Icons.people_rounded,
    ),
    _MenuItem(
      title: 'الموردون',
      icon: Icons.business_outlined,
      selectedIcon:
      Icons.business_rounded,
    ),
    _MenuItem(
      title: 'المندوبون',
      icon: Icons.badge_outlined,
      selectedIcon:
      Icons.badge_rounded,
    ),
    _MenuItem(
      title: 'الأرشيف',
      icon: Icons.folder_outlined,
      selectedIcon:
      Icons.folder_rounded,
    ),
    _MenuItem(
      title: 'التقارير',
      icon: Icons.bar_chart_outlined,
      selectedIcon:
      Icons.bar_chart_rounded,
    ),
    _MenuItem(
      title: 'الإعدادات',
      icon: Icons.settings_outlined,
      selectedIcon:
      Icons.settings_rounded,
    ),
    _MenuItem(
      title: 'تطبيق المندوب',
      icon: Icons.route_outlined,
      selectedIcon:
      Icons.route_rounded,
    ),
    _MenuItem(
      title: 'متجر الزبون',
      icon: Icons.storefront_outlined,
      selectedIcon:
      Icons.storefront_rounded,
    ),
    _MenuItem(
      title: 'رأس المال',
      icon: Icons.savings_outlined,
      selectedIcon: Icons.savings_rounded,
    ),
    _MenuItem(
      title: 'خانة المسؤول',
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications_rounded,
    ),
    _MenuItem(
      title: 'الحاسبات والصلاحيات',
      icon: Icons.admin_panel_settings_outlined,
      selectedIcon: Icons.admin_panel_settings_rounded,
    ),
    _MenuItem(
      title: 'نواقص البيع',
      icon: Icons.report_outlined,
      selectedIcon: Icons.report_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();

    _dashboardRepository =
        DashboardRepository(
          database: AppServices.database,
        );
    ensureCartonSample();
    _loadRole();
    _refreshPendingStoreOrders();
    _refreshSaleConflicts();
    _storeOrderBadgeTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) {
        _refreshPendingStoreOrders();
        _refreshSaleConflicts();
      },
    );
  }

  @override
  void dispose() {
    _storeOrderBadgeTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPendingStoreOrders() async {
    final online = await AppServices.authRepository.ensureOnlineSession();
    if (!mounted) {
      return;
    }
    if (!online) {
      if (_pendingStoreOrders != 0) {
        setState(() => _pendingStoreOrders = 0);
      }
      return;
    }

    try {
      final result = await AppServices.ecommerceOrdersRepository.getOrders(
        page: 1,
        limit: 1,
        status: 'SUBMITTED',
      );
      if (!mounted || _pendingStoreOrders == result.total) {
        return;
      }
      setState(() => _pendingStoreOrders = result.total);
    } catch (_) {}
  }

  Future<void> _refreshSaleConflicts() async {
    final count = await FloorStore.openConflictCount(AppServices.database);
    if (!mounted || count == _openSaleConflicts) {
      return;
    }
    setState(() => _openSaleConflicts = count);
  }

  Future<void> _loadRole() async {
    final session = await AppServices.authRepository.currentSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _role = session?.user.role ?? '';
    });
  }

  bool get _canOpenFinance => canOpenFinanceReports(_role);

  // ===========================================================================
  // NAVIGATION
  // ===========================================================================

  void _selectScreen(
      int index,
      ) {
    if (!mounted) {
      return;
    }

    setState(() {
      selectedIndex = index;
    });
    _refreshPendingStoreOrders();
  }

  // ===========================================================================
  // CURRENT SCREEN
  // ===========================================================================

  Widget _buildCurrentScreen() {
    switch (selectedIndex) {
      case 0:
        return DashboardScreen(
          repository:
          _dashboardRepository,
          onViewAllSales: () {
            _selectScreen(1);
          },
        );

      case 1:
        return const SalesScreen();

      case 2:
        return const EcommerceOrdersScreen();

      case 3:
        return const FinanceScreen();

      case 4:
        return const ProductsScreen();

      case 5:
        return const WarehousesScreen();

      case 6:
        return const PurchasesScreen();

      case 7:
        return const CustomersScreen();

      case 8:
        return const SuppliersScreen();

      case 9:
        return const RepresentativesScreen();

      case 10:
        return const ArchiveScreen();

      case 11:
        if (!_canOpenFinance) {
          return const _RestrictedScreen(
            title: 'التقارير',
          );
        }
        return const ReportsScreen();

      case 12:
        return const SettingsScreen();

      case 13:
        return const AliraAgentApp();

      case 14:
        return const AliraShopApp();

      case 15:
        if (!_canOpenFinance) {
          return const _RestrictedScreen(
            title: 'رأس المال',
          );
        }
        return const CapitalScreen();

      case 16:
        return const OfficeActivityScreen();

      case 17:
        return const StationsScreen();

      case 18:
        return const SaleConflictsScreen();

      default:
        return DashboardScreen(
          repository:
          _dashboardRepository,
          onViewAllSales: () {
            _selectScreen(1);
          },
        );
    }
  }

  // ===========================================================================
  // LOGOUT
  // ===========================================================================

  Future<void> _logout() async {
    if (_isLoggingOut) {
      return;
    }

    final shouldLogout =
        await showDialog<bool>(
          context: context,
          builder: (
              dialogContext,
              ) {
            return Directionality(
              textDirection:
              TextDirection.rtl,
              child: AlertDialog(
                title: const Text(
                  'تسجيل الخروج',
                ),
                content: const Text(
                  'هل تريد تسجيل الخروج من النظام؟',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                        false,
                      );
                    },
                    child: const Text(
                      'إلغاء',
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                        true,
                      );
                    },
                    child: const Text(
                      'تسجيل الخروج',
                    ),
                  ),
                ],
              ),
            );
          },
        ) ??
            false;

    if (!shouldLogout) {
      return;
    }

    setState(() {
      _isLoggingOut = true;
    });

    try {
      await AppServices
          .authRepository
          .logout();

      if (!mounted) {
        return;
      }

      widget.onLogout();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoggingOut = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            error
                .toString()
                .replaceFirst(
              'Bad state: ',
              '',
            ),
          ),
        ),
      );
    }
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
      body: Row(
        textDirection:
        TextDirection.rtl,
        children: [
          _buildSidebar(),
          Expanded(
            child:
            _buildCurrentScreen(),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SIDEBAR
  // ===========================================================================

  Widget _buildSidebar() {
    return Container(
      width: 238,
      decoration:
      const BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          left: BorderSide(
            color:
            AppTheme.subtleBorderColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildBrand(),

          const SizedBox(height: 6),

          Expanded(
            child: ListView(
              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              children: [
                const _SectionLabel(
                  title: 'الرئيسية',
                ),

                const SizedBox(height: 6),

                _buildMenuItem(0),
                _buildMenuItem(16),
                _buildMenuItem(17),

                const SizedBox(height: 16),

                const _SectionLabel(
                  title: 'إدارة المبيعات',
                ),

                const SizedBox(height: 6),

                _buildMenuItem(1),
                _buildMenuItem(2),
                _buildMenuItem(3),
                _buildMenuItem(4),
                _buildMenuItem(5),
                _buildMenuItem(6),

                const SizedBox(height: 16),

                const _SectionLabel(
                  title:
                  'الحسابات والعلاقات',
                ),

                const SizedBox(height: 6),

                _buildMenuItem(7),
                _buildMenuItem(8),
                _buildMenuItem(9),
                if (_canOpenFinance) _buildMenuItem(15),

                const SizedBox(height: 16),

                const _SectionLabel(
                  title: 'النظام',
                ),

                const SizedBox(height: 6),

                _buildMenuItem(10),
                if (_canOpenFinance) _buildMenuItem(11),
                _buildMenuItem(12),

                const SizedBox(height: 16),

                const _SectionLabel(
                  title: 'أليرا',
                ),

                const SizedBox(height: 6),

                _buildMenuItem(13),
                _buildMenuItem(14),
              ],
            ),
          ),

          _buildUserCard(),
        ],
      ),
    );
  }

  // ===========================================================================
  // BRAND
  // ===========================================================================

  Widget _buildBrand() {
    return Container(
      height: 92,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      alignment:
      Alignment.centerRight,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration:
            BoxDecoration(
              color:
              AppTheme.primaryColor,
              borderRadius:
              BorderRadius.circular(
                13,
              ),
            ),
            child: const Icon(
              Icons.auto_graph_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),

          const SizedBox(width: 12),

          const Expanded(
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  'نظام المبيعات',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                    FontWeight.w700,
                    color:
                    AppTheme
                        .primaryTextColor,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'المكتب الرئيسي',
                  style: TextStyle(
                    fontSize: 11.5,
                    color:
                    AppTheme
                        .secondaryTextColor,
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
  // MENU ITEM
  // ===========================================================================

  Widget _buildMenuItem(
      int index,
      ) {
    final item =
    menuItems[index];

    final selected =
        selectedIndex == index;

    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 3,
      ),
      child: Material(
        color: selected
            ? const Color(
          0xFFF1F1F3,
        )
            : Colors.transparent,
        borderRadius:
        BorderRadius.circular(11),
        child: InkWell(
          borderRadius:
          BorderRadius.circular(
            11,
          ),
          onTap: () {
            _selectScreen(index);
          },
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? AppTheme.primaryColor
                    : AppTheme.borderColor,
                width: selected ? 1.6 : 1.2,
              ),
            ),
            padding:
            const EdgeInsets
                .symmetric(
              horizontal: 12,
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? item.selectedIcon
                      : item.icon,
                  size: 19,
                  color: selected
                      ? AppTheme
                      .primaryTextColor
                      : AppTheme
                      .secondaryTextColor,
                ),

                const SizedBox(width: 11),

                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected
                          ? FontWeight
                          .w600
                          : FontWeight
                          .w500,
                      color: selected
                          ? AppTheme
                          .primaryTextColor
                          : AppTheme
                          .secondaryTextColor,
                    ),
                  ),
                ),
                if (index == 18 && _openSaleConflicts > 0)
                  Container(
                    margin: const EdgeInsetsDirectional.only(start: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _openSaleConflicts > 99 ? '99+' : '$_openSaleConflicts',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (index == 2 && _pendingStoreOrders > 0)
                  Container(
                    margin: const EdgeInsetsDirectional.only(start: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _pendingStoreOrders > 99
                          ? '99+'
                          : '$_pendingStoreOrders',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // USER
  // ===========================================================================

  Widget _buildUserCard() {
    return Container(
      margin:
      const EdgeInsets.all(12),
      padding:
      const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
        const Color(0xFFF8F8FA),
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color:
          AppTheme.subtleBorderColor,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration:
            const BoxDecoration(
              color:
              AppTheme.primaryColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              size: 19,
              color: Colors.white,
            ),
          ),

          const SizedBox(width: 10),

          const Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  'مدير النظام',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                    FontWeight.w600,
                    color:
                    AppTheme
                        .primaryTextColor,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'المكتب الرئيسي',
                  style: TextStyle(
                    fontSize: 10.5,
                    color:
                    AppTheme
                        .secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed:
            _isLoggingOut
                ? null
                : _logout,
            icon: _isLoggingOut
                ? const SizedBox(
              width: 18,
              height: 18,
              child:
              CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
                : const Icon(
              Icons.logout_rounded,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SECTION LABEL
// =============================================================================

class _SectionLabel
    extends StatelessWidget {
  final String title;

  const _SectionLabel({
    required this.title,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      child: Text(
        title,
        style:
        const TextStyle(
          fontSize: 10.5,
          fontWeight:
          FontWeight.w600,
          color:
          AppTheme
              .tertiaryTextColor,
        ),
      ),
    );
  }
}

// =============================================================================
// PLACEHOLDER
// =============================================================================

// =============================================================================
// MENU ITEM MODEL
// =============================================================================

class _MenuItem {
  final String title;
  final IconData icon;
  final IconData selectedIcon;

  const _MenuItem({
    required this.title,
    required this.icon,
    required this.selectedIcon,
  });
}

class _RestrictedScreen extends StatelessWidget {
  final String title;

  const _RestrictedScreen({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$title متاح للمدير والمسؤول فقط.',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}