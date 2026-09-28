import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../models/warehouse_approval_model.dart';

class WarehouseApprovalsScreen extends StatefulWidget {
  const WarehouseApprovalsScreen({
    super.key,
  });

  @override
  State<WarehouseApprovalsScreen> createState() =>
      _WarehouseApprovalsScreenState();
}

class _WarehouseApprovalsScreenState
    extends State<WarehouseApprovalsScreen> {
  final _repository =
      AppServices.warehouseApprovalsRepository;

  List<WarehouseApprovalModel> _warehouses = [];

  int _totalPending = 0;

  bool _isLoading = true;

  String? _processingWarehouseId;

  @override
  void initState() {
    super.initState();

    _loadApprovals();
  }

  // ===========================================================================
  // LOAD
  // ===========================================================================

  Future<void> _loadApprovals() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final result =
      await _repository.getApprovals();

      if (!mounted) {
        return;
      }

      setState(() {
        _totalPending = result.totalPending;
        _warehouses = result.warehouses;
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
        _errorMessage(
          error,
        ),
      );
    }
  }

  // ===========================================================================
  // APPROVE
  // ===========================================================================

  Future<void> _approve(
      WarehouseApprovalModel warehouse,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'اعتماد المخزن',
            ),
            content: SizedBox(
              width: 430,
              child: Text(
                'هل تريد اعتماد "${warehouse.name}" وتفعيله؟',
                style: const TextStyle(
                  height: 1.6,
                ),
              ),
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
                  'اعتماد',
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _processingWarehouseId = warehouse.id;
    });

    try {
      await _repository.approveWarehouse(
        warehouseServerId: warehouse.id,
      );

      await AppServices.syncNow();

      await _loadApprovals();

      if (!mounted) {
        return;
      }

      _showMessage(
        'تم اعتماد المخزن بنجاح.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _processingWarehouseId = null;
      });

      _showMessage(
        _errorMessage(
          error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingWarehouseId = null;
        });
      }
    }
  }

  // ===========================================================================
  // REJECT
  // ===========================================================================

  Future<void> _reject(
      WarehouseApprovalModel warehouse,
      ) async {
    final controller =
    TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'رفض المخزن',
            ),
            content: SizedBox(
              width: 470,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    warehouse.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryTextColor,
                    ),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  const Text(
                    'سبب الرفض',
                    style: TextStyle(
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
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText:
                      'مثال: البيانات غير مكتملة أو الموقع غير محدد بدقة',
                    ),
                  ),
                ],
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
                onPressed: () {
                  final value =
                  controller.text.trim();

                  if (value.isEmpty) {
                    return;
                  }

                  Navigator.pop(
                    dialogContext,
                    value,
                  );
                },
                child: const Text(
                  'رفض الطلب',
                ),
              ),
            ],
          ),
        );
      },
    );

    controller.dispose();

    if (reason == null ||
        reason.trim().isEmpty) {
      return;
    }

    setState(() {
      _processingWarehouseId = warehouse.id;
    });

    try {
      await _repository.rejectWarehouse(
        warehouseServerId: warehouse.id,
        rejectionReason: reason,
      );

      await AppServices.syncNow();

      await _loadApprovals();

      if (!mounted) {
        return;
      }

      _showMessage(
        'تم رفض طلب المخزن.',
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
          _processingWarehouseId = null;
        });
      }
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
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(
          child: CircularProgressIndicator(),
        )
            : RefreshIndicator(
          onRefresh: _loadApprovals,
          child: SingleChildScrollView(
            physics:
            const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
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
                _buildSummary(),
                const SizedBox(
                  height: 22,
                ),
                _buildContent(),
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
            Navigator.pop(
              context,
              true,
            );
          },
          icon: const Icon(
            Icons.arrow_back_rounded,
          ),
        ),
        const SizedBox(
          width: 8,
        ),
        const Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'الاعتمادات',
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
                'مراجعة طلبات المخازن المعلقة واعتمادها أو رفضها.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _loadApprovals,
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
  // SUMMARY
  // ===========================================================================

  Widget _buildSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        22,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xFF1D1D1F,
        ),
        borderRadius: BorderRadius.circular(
          18,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(
                13,
              ),
            ),
            child: const Icon(
              Icons.fact_check_outlined,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(
            width: 16,
          ),
          const Expanded(
            child: Text(
              'طلبات بانتظار الاعتماد',
              style: TextStyle(
                fontSize: 13,
                color: Color(
                  0xFFB8B8BD,
                ),
              ),
            ),
          ),
          Text(
            '$_totalPending',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CONTENT
  // ===========================================================================

  Widget _buildContent() {
    if (_warehouses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: 70,
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
              Icons.verified_outlined,
              size: 44,
              color: AppTheme.tertiaryTextColor,
            ),
            SizedBox(
              height: 12,
            ),
            Text(
              'لا توجد طلبات معلقة.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryTextColor,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        final columns =
        constraints.maxWidth >= 1050
            ? 2
            : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics:
          const NeverScrollableScrollPhysics(),
          itemCount: _warehouses.length,
          gridDelegate:
          SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 310,
          ),
          itemBuilder: (
              context,
              index,
              ) {
            final warehouse =
            _warehouses[index];

            return _ApprovalCard(
              warehouse: warehouse,
              isProcessing:
              _processingWarehouseId ==
                  warehouse.id,
              onApprove: () {
                _approve(
                  warehouse,
                );
              },
              onReject: () {
                _reject(
                  warehouse,
                );
              },
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  String _errorMessage(
      Object error,
      ) {
    final text = error.toString();

    if (text.startsWith(
      'Bad state: ',
    )) {
      return text.replaceFirst(
        'Bad state: ',
        '',
      );
    }

    if (text.startsWith(
      'Invalid argument(s): ',
    )) {
      return text.replaceFirst(
        'Invalid argument(s): ',
        '',
      );
    }

    return text;
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
// CARD
// =============================================================================

class _ApprovalCard extends StatelessWidget {
  final WarehouseApprovalModel warehouse;

  final bool isProcessing;

  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalCard({
    required this.warehouse,
    required this.isProcessing,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding: const EdgeInsets.all(
        20,
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
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFF5F5F7,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                ),
                child: const Icon(
                  Icons.warehouse_outlined,
                  size: 19,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      warehouse.name,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight:
                        FontWeight.w600,
                        color: AppTheme
                            .primaryTextColor,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      warehouse.code ??
                          'بدون رمز',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTheme
                            .secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              _ApprovalBadge(
                text:
                warehouse.typeDisplayName,
              ),
            ],
          ),
          const SizedBox(
            height: 18,
          ),
          _InfoRow(
            title: 'الفرع',
            value: warehouse.branchName
                .trim()
                .isNotEmpty
                ? warehouse.branchName
                : warehouse.branchId,
          ),
          const SizedBox(
            height: 10,
          ),
          _InfoRow(
            title: 'العنوان',
            value: warehouse.address ??
                'غير محدد',
          ),
          const SizedBox(
            height: 10,
          ),
          _InfoRow(
            title: 'مقدم الطلب',
            value:
            warehouse.creatorUsername
                .trim()
                .isNotEmpty
                ? warehouse
                .creatorUsername
                : warehouse.createdBy,
          ),
          const SizedBox(
            height: 10,
          ),
          _InfoRow(
            title: 'التاريخ',
            value: _formatDate(
              warehouse.createdAt,
            ),
          ),
          const Spacer(),
          if (isProcessing)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 17,
                    ),
                    label: const Text(
                      'رفض',
                    ),
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(
                      Icons.check_rounded,
                      size: 17,
                    ),
                    label: const Text(
                      'اعتماد',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _formatDate(
      DateTime? value,
      ) {
    if (value == null) {
      return 'غير محدد';
    }

    final day =
    value.day.toString().padLeft(
      2,
      '0',
    );

    final month =
    value.month.toString().padLeft(
      2,
      '0',
    );

    return '$day/$month/${value.year}';
  }
}

// =============================================================================
// INFO ROW
// =============================================================================

class _InfoRow extends StatelessWidget {
  final String title;
  final String value;

  const _InfoRow({
    required this.title,
    required this.value,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Row(
      children: [
        SizedBox(
          width: 95,
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppTheme.secondaryTextColor,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppTheme.primaryTextColor,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// BADGE
// =============================================================================

class _ApprovalBadge extends StatelessWidget {
  final String text;

  const _ApprovalBadge({
    required this.text,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xFFFFF4E5,
        ),
        borderRadius: BorderRadius.circular(
          20,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: Color(
            0xFF9A5A00,
          ),
        ),
      ),
    );
  }
}