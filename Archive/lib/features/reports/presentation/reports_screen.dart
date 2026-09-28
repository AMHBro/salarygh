import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/paging/list_page.dart';
import '../../../core/printing/print_preview.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../representatives/models/representative_model.dart';
import '../../warehouses/models/warehouse_model.dart';
import '../../settings/data/company_settings_repository.dart';
import '../data/local_statements_repository.dart';
import '../data/reports_repository.dart';
import '../models/report_catalog.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  final _repository = ReportsRepository(
    apiClient: AppServices.apiClient,
  );
  final _localStatements = LocalStatementsRepository(
    customersRepository: AppServices.customersRepository,
    salesRepository: AppServices.salesRepository,
    database: AppServices.database,
  );

  late final TabController _tabs;

  List<WarehouseModel> _warehouses = [];
  String? _stationWarehouseId;
  String? _reportWarehouseId;

  List<RepresentativeModel> _representatives = [];
  List<String> _customerGroups = [];
  String _customerLabel = '';
  String _productLabel = '';
  String _variantLabel = '';

  late ReportDefinition _report;
  String? _customerId;
  String? _groupName;
  String? _representativeId;
  String? _variantId;
  String? _productId;
  String? _from;
  String? _to;
  final _daysController = TextEditingController(text: '30');

  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;
  final Map<String, Set<String>> _printFields = {};

  static const _groups = [
    (reportGroupWarehouses, 'المخازن'),
    (reportGroupCustomers, 'الزبائن'),
    (reportGroupMaterials, 'المواد'),
    (reportGroupCash, 'الصندوق ورأس المال'),
    (reportGroupProfits, 'الأرباح'),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _groups.length, vsync: this);
    _report = reportCatalog.firstWhere(
      (item) => item.localKind == 'warehouseMovement',
    );
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) {
        return;
      }
      final group = _groups[_tabs.index].$1;
      if (_report.group == group) {
        return;
      }
      final next = reportCatalog.firstWhere(
        (item) => item.group == group,
      );
      setState(() {
        _report = next;
        _rows = [];
        _error = null;
      });
    });
    _loadLookups();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _daysController.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    try {
      final warehouses = await AppServices.warehousesRepository.getWarehouses();
      final stationWarehouseId = await AuthStorage().readStationWarehouseId();
      final groups = await _localStatements.groupNames();
      List<RepresentativeModel> representatives = [];
      try {
        representatives =
            await AppServices.representativesRepository.getRepresentatives();
      } catch (_) {}

      if (!mounted) {
        return;
      }

      setState(() {
        _warehouses = warehouses
            .where((warehouse) => warehouse.isActive && warehouse.deletedAt == null)
            .toList();
        _stationWarehouseId = _warehouses.any(
          (warehouse) => warehouse.id == stationWarehouseId,
        )
            ? stationWarehouseId
            : null;
        _customerGroups = groups;
        _representatives = representatives
            .where((item) => item.deletedAt == null)
            .toList();
      });
    } catch (_) {
      // القوائم المحلية اختيارية للتقارير التي لا تحتاج زبون أو مادة.
    }
  }

  List<ReportDefinition> get _visibleReports {
    final group = _groups[_tabs.index].$1;
    return reportCatalog.where((item) {
      if (item.group != group) {
        return false;
      }
      if (_stationWarehouseId != null && item.localKind == 'warehouseTotals') {
        return false;
      }
      return true;
    }).toList();
  }

  String? get _activeWarehouseId {
    final station = _stationWarehouseId?.trim() ?? '';
    if (station.isNotEmpty) {
      return station;
    }
    final selected = _reportWarehouseId?.trim() ?? '';
    return selected.isEmpty ? null : selected;
  }

  Future<void> _run() async {
    if (_report.localKind == 'group' &&
        (_groupName == null || _groupName!.trim().isEmpty)) {
      setState(() {
        _error = 'اختر العائلة أو التصنيف.';
      });
      return;
    }

    if ((_report.localKind == 'customersByRepresentative' ||
            _report.localKind == 'representative') &&
        (_representativeId == null || _representativeId!.isEmpty)) {
      setState(() {
        _error = 'اختر المندوب.';
      });
      return;
    }

    if (_report.customer && (_customerId == null || _customerId!.isEmpty)) {
      setState(() {
        _error = 'اختر زبوناً مزامناً مع الخادم.';
      });
      return;
    }

    if (_report.localKind == 'productInvoices' &&
        (_productId == null || _productId!.isEmpty)) {
      setState(() {
        _error = 'اختر المادة.';
      });
      return;
    }

    if (_report.variant && (_variantId == null || _variantId!.isEmpty)) {
      setState(() {
        _error = 'اختر مادة مزامنة مع الخادم.';
      });
      return;
    }

    final query = <String, String>{'limit': '100'};

    if (_report.dates) {
      if (_from != null) {
        query['from'] = _from!;
      }
      if (_to != null) {
        query['to'] = _to!;
      }
    }

    if (_report.customer && _customerId != null) {
      query['customer_id'] = _customerId!;
    }

    if (_report.variant && _variantId != null) {
      query['variant_id'] = _variantId!;
    }

    final warehouse = _selectedWarehouse;
    if (warehouse?.serverId != null && warehouse!.serverId!.trim().isNotEmpty) {
      query['warehouse_id'] = warehouse.serverId!.trim();
    }

    if (_report.expiryDays) {
      final days = int.tryParse(_daysController.text.trim());
      if (days == null || days < 0) {
        setState(() {
          _error = 'عدد أيام الصلاحية غير صحيح.';
        });
        return;
      }
      query['days'] = days.toString();
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = _report.localKind == null
          ? await _repository.fetch(
              _report.path,
              query: query,
            )
          : await _localRows();

      if (!mounted) {
        return;
      }

      setState(() {
        _rows = _withDollarColumns(_withOperationTypes(rows));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _rows = [];
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<List<Map<String, dynamic>>> _capitalRows(
    DateTime? from,
    DateTime? to,
  ) async {
    final opening = await CompanySettingsRepository(
      apiClient: AppServices.apiClient,
    ).readOpeningCapital();
    return _localStatements.capitalStatement(
      openingCapital: opening,
      from: from,
      to: to,
    );
  }

  Future<List<Map<String, dynamic>>> _localRows() {
    final from = _parseDate(_from);
    final to = _parseDate(_to);

    switch (_report.localKind) {
      case 'group':
        return _localStatements.groupStatement(
          groupName: _groupName!.trim(),
          from: from,
          to: to,
        );
      case 'customersByRepresentative':
        return _localStatements.customersByRepresentative(
          _representativeId!,
        );
      case 'representative':
        return _localStatements.representativeStatement(
          representativeId: _representativeId!,
          from: from,
          to: to,
        );
      case 'productInvoices':
        return _productInvoices();
      case 'warehouseMovement':
        return _localStatements.warehouseMovement(
          warehouseId: _activeWarehouseId,
          from: from,
          to: to,
        );
      case 'warehouseTotals':
        return _localStatements.warehouseTotals(
          warehouseId: _activeWarehouseId,
        );
      case 'currencyStatement':
        return _localStatements.currencyStatement(
          from: from,
          to: to,
        );
      case 'capital':
        return _capitalRows(from, to);
      default:
        return Future.value(const []);
    }
  }

  Future<List<Map<String, dynamic>>> _productInvoices() async {
    final database = AppServices.database;
    final items = await (database.select(database.saleItems)
          ..where((table) => table.productId.equals(_productId!)))
        .get();
    final sales = await database.select(database.sales).get();
    final byId = {for (final sale in sales) sale.id: sale};
    final rows = <Map<String, dynamic>>[];

    for (final item in items) {
      final sale = byId[item.saleId];
      if (sale == null) {
        continue;
      }
      final date = sale.createdAt;
      rows.add({
        'رقم القائمة': sale.invoiceNumber,
        'التاريخ':
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'الزبون': sale.customerName,
        'الكمية': item.quantity,
        'الإجمالي': item.total,
      });
    }

    rows.sort(
      (a, b) => '${b['التاريخ']}'.compareTo('${a['التاريخ']}'),
    );
    return rows;
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.length < 10) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
    );

    if (picked == null || !mounted) {
      return;
    }

    final value =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';

    setState(() {
      if (isFrom) {
        _from = value;
      } else {
        _to = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reports = _visibleReports;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'التقارير',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(width: 280, child: _stationPicker()),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'كل تقرير يقرأ من خادم النظام المحلي عبر نفس واجهة التقارير.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              labelColor: AppTheme.primaryTextColor,
              tabs: [
                for (final group in _groups) Tab(text: group.$2),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 280,
                    child: ListView.separated(
                      itemCount: reports.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = reports[index];
                        final selected = item.path == _report.path;

                        return Material(
                          color: selected
                              ? AppTheme.surfaceColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: selected
                                    ? AppTheme.primaryColor
                                    : AppTheme.borderColor,
                              ),
                            ),
                            title: Text(
                              item.title,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                            selected: selected,
                            onTap: () {
                              setState(() {
                                _report = item;
                                _rows = [];
                                _error = null;
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _buildResult()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _report.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _report.purpose,
            style: const TextStyle(color: AppTheme.secondaryTextColor),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_report.dates) ...[
                _dateButton('من', _from, () => _pickDate(true)),
                _dateButton('إلى', _to, () => _pickDate(false)),
              ],
              if (_report.localKind == 'group') _groupPicker(),
              if (_report.localKind == 'customersByRepresentative' ||
                  _report.localKind == 'representative')
                _representativePicker(),
              if (_report.customer) _customerPicker(),
              if (_report.variant) _variantPicker(),
              if (_report.localKind == 'productInvoices') _productPicker(),
              _warehouseFilter(),
              if (_report.expiryDays)
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _daysController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'أيام الصلاحية',
                    ),
                  ),
                ),
              FilledButton(
                onPressed: _loading ? null : _run,
                child: const Text('عرض'),
              ),
              OutlinedButton.icon(
                onPressed: _rows.isEmpty ? null : _choosePrintFields,
                icon: const Icon(Icons.checklist_rounded, size: 16),
                label: const Text('حقول الطباعة'),
              ),
              OutlinedButton.icon(
                onPressed: _rows.isEmpty ? null : _printReport,
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('طباعة'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  WarehouseModel? get _selectedWarehouse {
    final id = _activeWarehouseId;
    if (id == null) {
      return null;
    }
    for (final warehouse in _warehouses) {
      if (warehouse.id == id) {
        return warehouse;
      }
    }
    return null;
  }

  Widget _stationPicker() {
    return _TypedPicker(
      label: 'هذه الحاسبة',
      width: 280,
      valueId: _stationWarehouseId,
      emptyLabel: 'رئيسية — كل المخازن',
      live: false,
      choices: [
        for (final warehouse in _warehouses)
          _Choice(warehouse.id, warehouse.name),
      ],
      onChanged: (value) async {
        await AuthStorage().saveStationWarehouseId(value);
        if (!mounted) {
          return;
        }
        setState(() {
          _stationWarehouseId = value;
          _rows = [];
          if (value != null && _report.localKind == 'warehouseTotals') {
            _report = reportCatalog.firstWhere(
              (item) => item.localKind == 'warehouseMovement',
            );
          }
        });
      },
    );
  }

  Widget _warehouseFilter() {
    if (_stationWarehouseId != null) {
      return Chip(
        label: Text('مخزن هذه الحاسبة: ${_selectedWarehouse?.name ?? ''}'),
      );
    }

    return _TypedPicker(
      label: 'المخزن',
      valueId: _reportWarehouseId,
      emptyLabel: 'مجموع كل المخازن',
      choices: [
        for (final warehouse in _warehouses) _Choice(warehouse.id, warehouse.name),
      ],
      onChanged: (value) {
        setState(() {
          _reportWarehouseId = value;
          _rows = [];
        });
      },
    );
  }

  Widget _dateButton(
    String label,
    String? value,
    VoidCallback onTap,
  ) {
    return OutlinedButton(
      onPressed: onTap,
      child: Text(value == null ? label : '$label: $value'),
    );
  }

  Widget _groupPicker() {
    if (_customerGroups.isEmpty) {
      return const Text('أضف عائلة أو تصنيفاً من شاشة الزبائن أولاً');
    }

    return _TypedPicker(
      label: 'العائلة أو التصنيف',
      valueId: _groupName,
      choices: [
        for (final group in _customerGroups) _Choice(group, group),
      ],
      onChanged: (value) {
        setState(() {
          _groupName = value;
        });
      },
    );
  }

  Widget _representativePicker() {
    if (_representatives.isEmpty) {
      return const Text('لا يوجد مندوب مسجل');
    }

    return _TypedPicker(
      label: 'المندوب',
      valueId: _representativeId,
      choices: [
        for (final representative in _representatives)
          _Choice(representative.id, representative.name),
      ],
      onChanged: (value) {
        setState(() {
          _representativeId = value;
        });
      },
    );
  }

  Widget _productPicker() {
    return _QueryPicker(
      label: 'المادة',
      load: (query, limit, offset) async {
        final page = await AppServices.productsRepository.loadProductPage(
          search: query,
          limit: limit,
          offset: offset,
        );
        return [
          for (final product in page.items) _Choice(product.id, product.name),
        ];
      },
      onChanged: (choice) {
        setState(() {
          _productId = choice?.id;
          _productLabel = choice?.label ?? '';
        });
      },
    );
  }

  Widget _customerPicker() {
    return _QueryPicker(
      label: 'الزبون',
      load: (query, limit, offset) async {
        final page = await AppServices.customersRepository.pageCustomers(
          search: query,
          limit: limit,
          offset: offset,
        );
        return [
          for (final customer in page.items)
            if (_hasId(customer.serverId))
              _Choice(customer.serverId!.trim(), customer.name),
        ];
      },
      onChanged: (choice) {
        setState(() {
          _customerId = choice?.id;
          _customerLabel = choice?.label ?? '';
        });
      },
    );
  }

  Widget _variantPicker() {
    return _QueryPicker(
      label: 'المادة',
      width: 280,
      load: (query, limit, offset) async {
        final page = await AppServices.productsRepository.loadProductPage(
          search: query,
          limit: limit,
          offset: offset,
        );
        return [
          for (final product in page.items)
            for (final variant in product.variants)
              if (variant.isActive && variant.deletedAt == null && _hasId(variant.serverId))
                _Choice(variant.serverId!.trim(), '${product.name} ${variant.displayName}'.trim()),
        ];
      },
      onChanged: (choice) {
        setState(() {
          _variantId = choice?.id;
          _variantLabel = choice?.label ?? '';
        });
      },
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.dangerColor),
        ),
      );
    }

    if (_rows.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد بيانات. اضغط عرض لتشغيل التقرير.',
          style: TextStyle(color: AppTheme.secondaryTextColor),
        ),
      );
    }

    final head = _statementHead();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (head != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              head.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (_report.chart && _report.chartValueKey != null)
          _MonthChart(
            rows: _rows,
            valueKey: _report.chartValueKey!,
          ),
        Expanded(
          child: _ReportTable(
            rows: _rows,
            hidden: head == null ? const {} : {head.column},
          ),
        ),
      ],
    );
  }

  _StatementHead? _statementHead() {
    const keys = [
      'customer_name',
      'supplier_name',
      'company_name',
      'product_name',
      'party_name',
    ];
    for (final key in keys) {
      final name = _uniform(key);
      if (name != null) {
        return _StatementHead(name, key);
      }
    }

    if (_report.customer && (_customerId ?? '').isNotEmpty && _customerLabel.isNotEmpty) {
      return _StatementHead(_customerLabel, 'customer_name');
    }

    if (_report.localKind == 'productInvoices' &&
        (_productId ?? '').isNotEmpty &&
        _productLabel.isNotEmpty) {
      return _StatementHead(_productLabel, 'product_name');
    }

    if ((_variantId ?? '').isNotEmpty && _variantLabel.isNotEmpty) {
      return _StatementHead(_variantLabel, 'product_name');
    }

    return null;
  }

  String? _uniform(String key) {
    String? found;
    var present = false;
    for (final row in _rows) {
      if (!row.containsKey(key)) {
        continue;
      }
      present = true;
      final text = '${row[key] ?? ''}'.trim();
      if (text.isEmpty || text == '—' || text == '-') {
        continue;
      }
      if (found == null) {
        found = text;
      } else if (found != text) {
        return null;
      }
    }
    if (!present || found == null) {
      return null;
    }
    return found;
  }

  List<String> _printColumns() {
    final columns = _rows.isEmpty ? <String>[] : _rows.first.keys.toList();
    final saved = _printFields[_report.path];
    if (saved != null) {
      final chosen = [
        for (final column in columns)
          if (saved.contains(column)) column,
      ];
      if (chosen.isNotEmpty) {
        return chosen;
      }
    }
    final hide = _statementHead()?.column;
    return [
      for (final column in columns)
        if (column != hide) column,
    ];
  }

  Future<void> _choosePrintFields() async {
    final columns = _rows.isEmpty ? <String>[] : _rows.first.keys.toList();
    if (columns.isEmpty) {
      return;
    }
    final selected = {..._printColumns()};
    final saved = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('حقول طباعة ${_report.title}'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final column in columns)
                        CheckboxListTile(
                          dense: true,
                          value: selected.contains(column),
                          title: Text(reportColumnLabel(column)),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                selected.add(column);
                              } else {
                                selected.remove(column);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      selected
                        ..clear()
                        ..addAll(columns);
                    });
                  },
                  child: const Text('تحديد الكل'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, selected),
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved == null || !mounted) {
      return;
    }
    setState(() {
      _printFields[_report.path] = saved;
    });
  }

  void _printReport() {
    final columns = _printColumns();
    final head = _statementHead();
    showPrintPreview(
      context,
      PrintDocument(
        kind: 'كشف',
        title: head?.title ?? _report.title,
        partyLabel: head == null ? '' : 'كشف',
        party: head?.name ?? '',
        columns: [
          for (final column in columns) reportColumnLabel(column),
        ],
        rows: [
          for (final row in _rows)
            [
              for (final column in columns) _formatCell(row[column]),
            ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _withOperationTypes(
    List<Map<String, dynamic>> rows,
  ) {
    return [
      for (final row in rows) _operationRow(row),
    ];
  }

  Map<String, dynamic> _operationRow(Map<String, dynamic> row) {
    final label = _operationLabel(row);
    final reference = _documentReference(row);
    final next = <String, dynamic>{};

    for (final entry in row.entries) {
      if (entry.key == 'reference_number' || entry.key == 'entry_type') {
        continue;
      }
      if (reference != null &&
          (entry.key == 'invoice_number' || entry.key == 'voucher_number')) {
        continue;
      }
      next[entry.key] = entry.value;
    }

    if (reference != null) {
      next['reference_number'] = reference;
    }
    if (label != null) {
      next['entry_type'] = label;
      next.remove('operation_type');
      next.remove('movement_type');
      next.remove('movement_kind');
      if (row.containsKey('voucher_type')) {
        next['voucher_type'] = label;
      }
    }

    return next;
  }

  String? _documentReference(Map<String, dynamic> row) {
    for (final key in [
      'voucher_number',
      'invoice_number',
      'reference_number',
    ]) {
      final value = '${row[key] ?? ''}'.trim();
      if (value.isEmpty || value == 'null' || _isMovementCode(value)) {
        continue;
      }
      return value;
    }
    return null;
  }

  bool _isMovementCode(String value) {
    const codes = {
      'SALE',
      'PURCHASE',
      'RECEIPT',
      'PAYMENT',
      'PAYMENT_AT_SALE',
      'بيع',
      'شراء',
      'قبض',
      'صرف',
    };
    return codes.contains(value) || codes.contains(value.toUpperCase());
  }

  String? _operationLabel(Map<String, dynamic> row) {
    final current = '${row['operation_type'] ?? row['entry_type'] ?? ''}'.trim();
    if (current == 'بيع' ||
        current == 'شراء' ||
        current == 'قبض' ||
        current == 'صرف') {
      return current;
    }

    final raw = '${row['entry_type'] ?? row['voucher_type'] ?? row['movement_type'] ?? row['movement_kind'] ?? row['operation_type'] ?? ''}'
        .trim()
        .toUpperCase();

    switch (raw) {
      case 'SALE':
        return 'بيع';
      case 'PURCHASE':
        return 'شراء';
      case 'RECEIPT':
      case 'PAYMENT_AT_SALE':
        return 'قبض';
      case 'PAYMENT':
        return 'صرف';
      default:
        return current.isEmpty ? null : current;
    }
  }

  List<Map<String, dynamic>> _withDollarColumns(
    List<Map<String, dynamic>> rows,
  ) {
    return [
      for (final row in rows) _dollarRow(row),
    ];
  }

  Map<String, dynamic> _dollarRow(Map<String, dynamic> row) {
    final next = Map<String, dynamic>.from(row);
    final currency = '${row['currency'] ?? 'IQD'}';
    final explicitUsd = _asDouble(row['total_usd']);

    for (final key in row.keys.toList()) {
      if (!_isMoneyColumn(key)) {
        continue;
      }

      final usdKey = '${key}_usd';

      if (next[usdKey] != null) {
        continue;
      }

      if (currency == 'USD' &&
          explicitUsd > 0 &&
          (key == 'sales_iqd' || key == 'total' || key == 'amount_iqd')) {
        next[usdKey] = explicitUsd;
      } else {
        next[usdKey] = 0;
      }
    }

    return next;
  }

  bool _isMoneyColumn(String key) {
    if (key.endsWith('_usd')) {
      return false;
    }

    const names = {
      'price',
      'subtotal',
      'total',
      'balance',
      'amount',
      'recorded_balance',
      'sales_iqd',
      'commission_iqd',
    };

    return key.endsWith('_iqd') || names.contains(key);
  }

  double _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse('${value ?? ''}') ?? 0;
  }

  bool _hasId(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}

class _MonthChart extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String valueKey;

  const _MonthChart({
    required this.rows,
    required this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final row in rows) double.tryParse('${row[valueKey]}') ?? 0,
    ];
    final maxValue = values.fold<double>(0, (max, value) {
      return value > max ? value : max;
    });

    return SizedBox(
      height: 180,
      child: ListView.separated(
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final row = rows[index];
          final value = values[index];
          final widthFactor = maxValue == 0 ? 0.0 : value / maxValue;
          final month = '${row['month'] ?? ''}';
          final label = month.length >= 7 ? month.substring(0, 7) : month;

          return Row(
            children: [
              SizedBox(width: 72, child: Text(label)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 14,
                    value: widthFactor == 0 ? 0.02 : widthFactor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: Text(
                  _formatCell(row[valueKey]),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatementHead {
  final String name;
  final String column;

  const _StatementHead(this.name, this.column);

  String get title => 'كشف $name';
}

class _ReportTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Set<String> hidden;

  const _ReportTable({
    required this.rows,
    this.hidden = const {},
  });

  @override
  Widget build(BuildContext context) {
    final columns = [
      for (final column in rows.first.keys)
        if (!hidden.contains(column)) column,
    ];
    if (columns.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (final column in columns)
              DataColumn(label: Text(reportColumnLabel(column))),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [
                  for (final column in columns)
                    DataCell(Text(_formatCell(row[column]))),
                ],
              ),
            DataRow(
              cells: [
                for (var index = 0; index < columns.length; index++)
                  DataCell(
                    Text(
                      _totalCell(rows, columns, index),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _totalCell(
  List<Map<String, dynamic>> rows,
  List<String> columns,
  int index,
) {
  final column = columns[index];
  if (!_summableColumn(column)) {
    return index == 0 ? 'المجموع النهائي' : '';
  }

  var sum = 0.0;
  for (final row in rows) {
    final value = row[column];
    if (value is num) {
      sum += value.toDouble();
    } else {
      sum += double.tryParse('${value ?? ''}') ?? 0;
    }
  }

  final total = _formatCell(sum);
  return index == 0 ? 'المجموع النهائي $total' : total;
}

bool _summableColumn(String key) {
  if (key.endsWith('_usd') || key.endsWith('_iqd')) {
    return true;
  }
  const names = {
    'amount',
    'total',
    'balance',
    'price',
    'subtotal',
    'quantity',
    'capital_iqd',
  };
  return names.contains(key);
}

String _formatCell(Object? value) {
  if (value == null) {
    return '—';
  }

  if (value is bool) {
    return value ? 'نعم' : 'لا';
  }

  final text = value.toString();

  if (text.contains('T') && text.length >= 10) {
    final date = DateTime.tryParse(text);
    if (date != null) {
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      return '${date.year}-$month-$day';
    }
  }

  return text;
}

class _Choice {
  final String id;
  final String label;

  const _Choice(this.id, this.label);
}

class _QueryPicker extends StatefulWidget {
  final String label;
  final double width;
  final Future<List<_Choice>> Function(String query, int limit, int offset) load;
  final ValueChanged<_Choice?> onChanged;

  const _QueryPicker({
    required this.label,
    required this.load,
    required this.onChanged,
    this.width = 240,
  });

  @override
  State<_QueryPicker> createState() => _QueryPickerState();
}

class _QueryPickerState extends State<_QueryPicker> {
  final _controller = TextEditingController();
  Timer? _timer;
  List<_Choice> _choices = const [];
  int _page = 1;
  bool _hasNext = false;
  bool _loading = false;
  static const int _pageSize = 20;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), _fetch);
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final choices = await widget.load(
      _controller.text.trim(),
      _pageSize + 1,
      (_page - 1) * _pageSize,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _hasNext = choices.length > _pageSize;
      _choices = choices.take(_pageSize).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: 'اكتب للبحث',
            ),
            onTap: _schedule,
            onChanged: (_) {
              _page = 1;
              _schedule();
            },
          ),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2),
          if (_choices.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final choice in _choices)
                    ListTile(
                      dense: true,
                      title: Text(choice.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        _controller.text = choice.label;
                        setState(() => _choices = const []);
                        widget.onChanged(choice);
                      },
                    ),
                  ListPagination(
                    page: _page,
                    hasNextPage: _hasNext,
                    pageSize: _pageSize,
                    loading: _loading,
                    onPageChanged: (page) {
                      _page = page;
                      _fetch();
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TypedPicker extends StatefulWidget {
  final String label;
  final String? valueId;
  final String emptyLabel;
  final List<_Choice> choices;
  final ValueChanged<String?> onChanged;
  final double width;
  final bool live;

  const _TypedPicker({
    required this.label,
    required this.valueId,
    required this.choices,
    required this.onChanged,
    this.emptyLabel = '',
    this.width = 240,
    this.live = true,
  });

  @override
  State<_TypedPicker> createState() => _TypedPickerState();
}

class _TypedPickerState extends State<_TypedPicker> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _labelFor(widget.valueId));
    _focus = FocusNode();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _apply(_controller.text, force: true);
      }
    });
  }

  @override
  void didUpdateWidget(_TypedPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focus.hasFocus) {
      return;
    }
    final next = _labelFor(widget.valueId);
    if (_controller.text != next) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _labelFor(String? id) {
    if (id == null || id.isEmpty) {
      return widget.emptyLabel;
    }
    for (final choice in widget.choices) {
      if (choice.id == id) {
        return choice.label;
      }
    }
    return '';
  }

  String? _match(String text) {
    final query = text.trim();
    if (query.isEmpty || query == widget.emptyLabel) {
      return null;
    }
    final exact = widget.choices.where((choice) => choice.label.trim() == query);
    if (exact.length == 1) {
      return exact.first.id;
    }
    final contains = widget.choices.where((choice) => choice.label.contains(query));
    if (contains.length == 1) {
      return contains.first.id;
    }
    return null;
  }

  void _apply(String text, {bool force = false}) {
    if (!force && !widget.live) {
      return;
    }
    final next = _match(text);
    if (next == widget.valueId) {
      return;
    }
    if (!force && next == null && text.trim().isNotEmpty && text.trim() != widget.emptyLabel) {
      if (widget.valueId != null) {
        widget.onChanged(null);
      }
      return;
    }
    widget.onChanged(next);
    if (force && next != null) {
      final label = _labelFor(next);
      if (label.isNotEmpty && _controller.text != label) {
        _controller.text = label;
      }
    }
    if (force && next == null && (text.trim().isEmpty || text.trim() == widget.emptyLabel)) {
      _controller.text = widget.emptyLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = <_Choice>[
      if (widget.emptyLabel.isNotEmpty) _Choice('', widget.emptyLabel),
      ...widget.choices,
    ];

    return SizedBox(
      width: widget.width,
      child: RawAutocomplete<_Choice>(
        textEditingController: _controller,
        focusNode: _focus,
        displayStringForOption: (choice) => choice.label,
        optionsBuilder: (value) {
          final query = value.text.trim();
          if (query.isEmpty || query == widget.emptyLabel) {
            return options.take(8);
          }
          return options.where((choice) => choice.label.contains(query)).take(8);
        },
        onSelected: (choice) {
          widget.onChanged(choice.id.isEmpty ? null : choice.id);
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: 'اكتب للبحث',
            ),
            onChanged: _apply,
            onSubmitted: (text) => _apply(text, force: true),
          );
        },
        optionsViewBuilder: (context, onSelected, suggestions) {
          final items = suggestions.toList();
          return Align(
            alignment: AlignmentDirectional.topStart,
            child: Material(
              elevation: 3,
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 220, maxWidth: widget.width),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final choice = items[index];
                    return InkWell(
                      onTap: () => onSelected(choice),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          choice.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
