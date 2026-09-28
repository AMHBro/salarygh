import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/floor/floor_store.dart';
import '../../../core/theme/app_theme.dart';

class SaleConflictsScreen extends StatefulWidget {
  const SaleConflictsScreen({super.key});

  @override
  State<SaleConflictsScreen> createState() => _SaleConflictsScreenState();
}

class _SaleConflictsScreenState extends State<SaleConflictsScreen> {
  List<SaleConflictRow> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await FloorStore.conflicts(AppServices.database);
    if (!mounted) {
      return;
    }
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _acknowledge(SaleConflictRow row) async {
    await FloorStore.acknowledge(AppServices.database, row.id);
    await _load();
  }

  Future<void> _release(SaleConflictRow row) async {
    final serverId = row.serverVariantId.trim();
    if (serverId.isNotEmpty) {
      try {
        await AppServices.apiClient.post(
          '/floor/locks/release',
          data: {'variant_id': serverId},
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فك القفل على السيرفر: $error')),
        );
        return;
      }
    }
    await FloorStore.markReleased(AppServices.database, row.id);
    if (!mounted) {
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'نواقص البيع',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'فاتورة الأوفلاين تبقى محفوظة. المادة تقف عن البيع حتى يقر المدير النقص أو يفك القفل بعد وصول بضاعة.',
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_rows.isEmpty)
                const Expanded(child: Center(child: Text('لا توجد نواقص مفتوحة.')))
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.status == 'ACK' ? 'تم الإقرار' : 'بانتظار المراجعة',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(row.message),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  if (row.status != 'ACK')
                                    OutlinedButton(
                                      onPressed: () => _acknowledge(row),
                                      child: const Text('إقرار النقص'),
                                    ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () => _release(row),
                                    child: const Text('فك القفل'),
                                  ),
                                ],
                              ),
                            ],
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
    );
  }
}
