import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/di/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../data/staff_ledger.dart';

class StaffAccountsScreen extends StatefulWidget {
  const StaffAccountsScreen({super.key});

  @override
  State<StaffAccountsScreen> createState() => _StaffAccountsScreenState();
}

class _StaffAccountsScreenState extends State<StaffAccountsScreen> {
  final _ledger = StaffLedger(AppServices.database);
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  List<StaffEmployee> _employees = const [];
  List<StaffExpense> _expenses = const [];
  String? _employeeId;
  late String _spentOn;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _spentOn = staffDayKey(DateTime.now());
    _loadEmployees();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final employees = await _ledger.employees();
      if (!mounted) {
        return;
      }
      final selected = _employeeId;
      final stillThere = employees.any((employee) => employee.id == selected);
      setState(() {
        _employees = employees;
        _employeeId = stillThere ? selected : null;
        _loading = false;
      });
      if (_employeeId != null) {
        await _loadExpenses();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _loadExpenses() async {
    final employeeId = _employeeId;
    if (employeeId == null) {
      setState(() => _expenses = const []);
      return;
    }
    final expenses = await _ledger.expensesFor(employeeId);
    if (!mounted) {
      return;
    }
    setState(() => _expenses = expenses);
  }

  Future<void> _addEmployee() async {
    try {
      final employee = await _ledger.addEmployee(_nameController.text);
      _nameController.clear();
      if (!mounted) {
        return;
      }
      setState(() => _employeeId = employee.id);
      await _loadEmployees();
    } catch (error) {
      _show(_message(error));
    }
  }

  Future<void> _addExpense() async {
    final employeeId = _employeeId;
    if (employeeId == null) {
      _show('اختر موظفاً أولاً.');
      return;
    }
    final amount = parseStaffDinars(_amountController.text);
    if (amount == null) {
      _show('اكتب مبلغ الصرف بالدينار الصحيح.');
      return;
    }
    try {
      await _ledger.addExpense(
        employeeId: employeeId,
        amountIqd: amount,
        spentOn: _spentOn,
        note: _noteController.text,
      );
      _amountController.clear();
      _noteController.clear();
      await _loadExpenses();
    } catch (error) {
      _show(_message(error));
    }
  }

  Future<void> _removeExpense(StaffExpense expense) async {
    await _ledger.removeExpense(expense.id);
    await _loadExpenses();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_spentOn) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _spentOn = staffDayKey(picked));
  }

  void _show(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _message(Object error) {
    return error.toString().replaceFirst('Bad state: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final selected = _employees.where((employee) => employee.id == _employeeId);
    final employee = selected.isEmpty ? null : selected.first;
    final total = _expenses.fold<int>(0, (sum, expense) => sum + expense.amountIqd);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'حسابات الموظفين',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'صرفيات كل موظف تُحفظ على الحاسبة وتظهر في تقرير الصرفيات وتُطرح من الربح اليومي.',
            style: TextStyle(color: AppTheme.secondaryTextColor),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppTheme.dangerColor)),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 320,
                  child: _panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'الموظفون',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'اسم الموظف',
                          ),
                          onSubmitted: (_) => _addEmployee(),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _addEmployee,
                          child: const Text('إضافة موظف'),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : ListView(
                                  children: [
                                    for (final item in _employees)
                                      ListTile(
                                        selected: item.id == _employeeId,
                                        title: Text(item.name),
                                        onTap: () {
                                          setState(() => _employeeId = item.id);
                                          _loadExpenses();
                                        },
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _panel(
                    child: employee == null
                        ? const Center(child: Text('اختر موظفاً لعرض صرفياته.'))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                employee.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'مجموع الصرفيات ${_group(total)} د.ع',
                                style: const TextStyle(
                                  color: AppTheme.secondaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 180,
                                    child: TextField(
                                      controller: _amountController,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: const InputDecoration(
                                        labelText: 'المبلغ (دينار)',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 220,
                                    child: TextField(
                                      controller: _noteController,
                                      decoration: const InputDecoration(
                                        labelText: 'البيان',
                                      ),
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: _pickDate,
                                    child: Text('يوم الصرف $_spentOn'),
                                  ),
                                  FilledButton(
                                    onPressed: _addExpense,
                                    child: const Text('تسجيل صرف'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: _expenses.isEmpty
                                    ? const Center(child: Text('لا توجد صرفيات.'))
                                    : ListView.separated(
                                        itemCount: _expenses.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final expense = _expenses[index];
                                          return ListTile(
                                            title: Text(
                                              '${_group(expense.amountIqd)} د.ع',
                                            ),
                                            subtitle: Text(
                                              expense.note.isEmpty
                                                  ? expense.spentOn
                                                  : '${expense.spentOn} · ${expense.note}',
                                            ),
                                            trailing: IconButton(
                                              tooltip: 'حذف الصرف',
                                              onPressed: () =>
                                                  _removeExpense(expense),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
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

  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: child,
    );
  }

  String _group(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return negative ? '-$buffer' : buffer.toString();
  }
}
