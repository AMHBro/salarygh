import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/printing/print_preview.dart';
import '../../../core/theme/app_theme.dart';
import '../../representatives/data/rep_debt_ceiling.dart';
import '../../warehouses/models/warehouse_model.dart';
import '../models/ecommerce_order_model.dart';

PrintDocument storeOrderDocument(EcommerceOrderModel order) {
  String money(double value) => value.toStringAsFixed(0);
  final date = order.submittedAt ?? order.acceptedAt;
  final address = order.customer?.address ?? order.party?.address;

  return PrintDocument(
    kind: order.isRepresentative ? 'طلب مندوب' : 'طلب متجر',
    title: order.orderNumber,
    party: order.partyDisplayName,
    printedDate: date == null ? '' : printDateText(date),
    printedTime: date == null ? '' : printTimeText(date),
    documentType: order.paymentTypeDisplayName,
    lines: [
      'المصدر: ${order.sourceDisplayName}',
      'الحالة: ${order.statusDisplayName}',
      if (order.partyPhone != null) 'الهاتف: ${order.partyPhone}',
      if (address != null && address.trim().isNotEmpty) 'العنوان: $address',
      if (order.representative != null) 'المندوب: ${order.representative!.name}',
      if (order.notes != null && order.notes!.trim().isNotEmpty)
        'ملاحظات: ${order.notes}',
      if (order.isAccepted) 'بعد الموافقة دخلت هذه البيانات إلى النظام كقائمة بيع.',
    ],
    columns: const ['المادة', 'الوحدة', 'العدد', 'السعر', 'المجموع'],
    rows: [
      for (final item in order.items)
        [
          item.productName,
          item.unitName,
          item.quantity.toStringAsFixed(0),
          money(item.unitPrice),
          money(item.lineTotal),
        ],
    ],
    grandTotal: order.total,
    discount: order.discountAmount,
    totals: const [],
  );
}

class EcommerceOrderDetailsScreen extends StatefulWidget {
  final EcommerceOrderModel initialOrder;

  const EcommerceOrderDetailsScreen({
    super.key,
    required this.initialOrder,
  });

  @override
  State<EcommerceOrderDetailsScreen> createState() =>
      _EcommerceOrderDetailsScreenState();
}

class _EcommerceOrderDetailsScreenState
    extends State<EcommerceOrderDetailsScreen> {
  late EcommerceOrderModel _order;

  bool _loading = false;
  bool _processing = false;

  String? _error;

  String? _debtWarning;

  @override
  void initState() {
    super.initState();

    _order = widget.initialOrder;

    _refresh();
    _loadDebtWarning();
  }

  Future<void> _loadDebtWarning() async {
    final name = _order.representative?.name.trim() ?? '';
    if (!_order.isRepresentative || name.isEmpty) return;
    final messages = await RepDebtCeiling.messagesForNames(
      AppServices.database,
      {name},
    );
    if (!mounted) return;
    setState(() {
      _debtWarning = messages.isEmpty ? null : messages.first;
    });
  }

  // ===========================================================================
  // REFRESH
  // ===========================================================================

  Future<void> _refresh() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final order = await AppServices
          .ecommerceOrdersRepository
          .getOrder(
        _order.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _order = order;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = _errorText(
          error,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ===========================================================================
  // ACCEPT
  // ===========================================================================

  Future<void> _showAcceptDialog() async {
    if (_processing) {
      return;
    }

    List<WarehouseModel> warehouses;
    String? inactiveName;
    String? inactiveStatus;
    final cloudIdByLocalId = <String, String>{};

    try {
      final allWarehouses =
      await AppServices.warehousesRepository.getWarehouses();

      final stationWarehouseId =
          (await AuthStorage().readStationWarehouseId())?.trim() ?? '';
      final cloudWarehouses = await _cloudWarehouses();
      final cloudById = {
        for (final warehouse in cloudWarehouses) warehouse.id: warehouse,
      };
      final cloudByName = <String, _CloudWarehouse>{};
      for (final warehouse in cloudWarehouses) {
        cloudByName.putIfAbsent(warehouse.name.trim(), () => warehouse);
      }
      _CloudWarehouse? cloudFor(WarehouseModel warehouse) {
        final stored = warehouse.serverId?.trim();
        if (stored != null && stored.isNotEmpty) {
          final byId = cloudById[stored];
          if (byId != null) {
            return byId;
          }
        }
        return cloudByName[warehouse.name.trim()];
      }

      warehouses = allWarehouses.where((warehouse) {
        if (!warehouse.isActive || warehouse.deletedAt != null) {
          return false;
        }
        if (stationWarehouseId.isNotEmpty && warehouse.id != stationWarehouseId) {
          return false;
        }
        final cloud = cloudFor(warehouse);
        if (cloud == null) {
          return false;
        }
        if (!cloud.isActive) {
          inactiveName = warehouse.name;
          inactiveStatus = cloud.status;
          return false;
        }
        cloudIdByLocalId[warehouse.id] = cloud.id;
        return true;
      }).toList()
        ..sort((a, b) {
          if (a.isMain != b.isMain) {
            return a.isMain ? -1 : 1;
          }
          return a.name.compareTo(b.name);
        });
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _errorText(error),
      );

      return;
    }

    if (!mounted) {
      return;
    }

    if (warehouses.isEmpty) {
      final status = inactiveStatus?.trim().toUpperCase() ?? '';
      final message = inactiveName == null
          ? 'المخزن موجود على هذه الحاسبة، ورقمه غير مسجّل على السيرفر. الموافقة تستخدم فقط مخزن المتجر النشط.'
          : (status == 'PENDING_APPROVAL' ||
                  status == 'DRAFT' ||
                  status == 'REJECTED' ||
                  status == 'LOCAL')
              ? 'المخزن «$inactiveName» غير مفعّل على السيرفر. من شاشة المخازن افتح النقاط بجانبه واضغط اعتماد وتفعيل، ثم أعد الموافقة.'
              : 'المخزن «$inactiveName» موجود على السيرفر لكنه غير مفعّل. فعّله من شاشة المخازن ثم أعد الموافقة.';
      _showMessage(
        message,
      );

      return;
    }

    WarehouseModel selectedWarehouse = warehouses.first;

    final paidController = TextEditingController();

    final result = await showDialog<_AcceptDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text(
                  'قبول الطلب',
                ),
                content: SizedBox(
                  width: 440,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'بعد الموافقة تدخل البيانات إلى النظام كقائمة بيع ويُخصم المخزون.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        initialValue:
                        selectedWarehouse.id,
                        decoration: const InputDecoration(
                          labelText: 'المخزن',
                          border: OutlineInputBorder(),
                        ),
                        items: warehouses
                            .map(
                              (warehouse) =>
                              DropdownMenuItem<String>(
                                value: warehouse.id,
                                child: Text(
                                  warehouse.name,
                                ),
                              ),
                        )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          final match = warehouses.firstWhere(
                                (warehouse) =>
                            warehouse.id == value,
                          );

                          setDialogState(() {
                            selectedWarehouse = match;
                          });
                        },
                      ),
                      if (_order.isPartialPayment) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: paidController,
                          keyboardType:
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'المبلغ المدفوع',
                            hintText: 'أدخل المبلغ المدفوع',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _DialogInfoRow(
                        title: 'نوع الدفع',
                        value: _order.paymentTypeDisplayName,
                      ),
                      const SizedBox(height: 8),
                      _DialogInfoRow(
                        title: 'إجمالي الطلب',
                        value: _money(
                          _order.total,
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
                    onPressed: () async {
                      double? paidAmount;

                      if (_order.isPartialPayment) {
                        paidAmount = double.tryParse(
                          paidController.text
                              .trim()
                              .replaceAll(',', ''),
                        );

                        if (paidAmount == null ||
                            paidAmount < 0) {
                          ScaffoldMessenger.of(
                            dialogContext,
                          ).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'أدخل مبلغاً مدفوعاً صالحاً.',
                              ),
                            ),
                          );

                          return;
                        }
                      }

                      final cloudId = cloudIdByLocalId[selectedWarehouse.id];
                      if (cloudId == null || cloudId.isEmpty) {
                        return;
                      }
                      final stored = selectedWarehouse.serverId?.trim();
                      if (stored != cloudId) {
                        try {
                          await AppServices.warehousesRepository.saveServerSnapshot(
                            localId: selectedWarehouse.id,
                            serverId: cloudId,
                            status: 'ACTIVE',
                            type: selectedWarehouse.type,
                          );
                        } catch (_) {}
                      }
                      if (!dialogContext.mounted) {
                        return;
                      }
                      Navigator.pop(
                        dialogContext,
                        _AcceptDialogResult(
                          warehouseServerId: cloudId,
                          paidAmount: paidAmount,
                        ),
                      );
                    },
                    child: const Text(
                      'تأكيد القبول',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    paidController.dispose();

    if (result == null || !mounted) {
      return;
    }

    await _acceptOrder(
      result,
    );
  }

  Future<void> _acceptOrder(
      _AcceptDialogResult result,
      ) async {
    setState(() {
      _processing = true;
    });

    try {
      final response = await AppServices
          .ecommerceOrdersRepository
          .acceptOrder(
        orderId: _order.id,
        warehouseId: result.warehouseServerId,
        paidAmount: result.paidAmount,
      );

      if (!mounted) {
        return;
      }

      try {
        await AppServices.syncNow();
      } catch (_) {}

      if (!mounted) {
        return;
      }

      _showMessage(
        response.message.trim().isNotEmpty
            ? response.message
            : 'تمت الموافقة ودخلت القائمة إلى النظام.',
      );

      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _errorText(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  // ===========================================================================
  // REJECT
  // ===========================================================================

  Future<void> _showRejectDialog() async {
    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'رفض الطلب',
            ),
            content: SizedBox(
              width: 420,
              child: TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'سبب الرفض',
                  hintText: 'اكتب سبب رفض الطلب',
                  border: OutlineInputBorder(),
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
                onPressed: () {
                  final value = controller.text.trim();

                  if (value.isEmpty) {
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'سبب الرفض مطلوب.',
                        ),
                      ),
                    );

                    return;
                  }

                  Navigator.pop(
                    dialogContext,
                    value,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.dangerColor,
                  foregroundColor: Colors.white,
                ),
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
        reason.trim().isEmpty ||
        !mounted) {
      return;
    }

    await _rejectOrder(
      reason,
    );
  }

  Future<void> _rejectOrder(
      String reason,
      ) async {
    setState(() {
      _processing = true;
    });

    try {
      final order = await AppServices
          .ecommerceOrdersRepository
          .rejectOrder(
        orderId: _order.id,
        reason: reason,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _order = order;
      });

      _showMessage(
        'تم رفض الطلب.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _errorText(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
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
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            _buildHeader(),
            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2,
              ),
            if (_debtWarning != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                child: RepDebtBanner(message: _debtWarning!),
              ),
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(
        horizontal: 28,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.subtleBorderColor,
          ),
        ),
      ),
      child: Row(
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
              Icons.arrow_forward_rounded,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  _order.orderNumber,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'تفاصيل طلب المتجر',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          _StatusChip(
            order: _order,
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () {
              showPrintPreview(
                context,
                storeOrderDocument(_order),
              );
            },
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('طباعة'),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null && _order.id.isEmpty) {
      return Center(
        child: Text(
          _error!,
        ),
      );
    }

    return SelectionArea(
      child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1150,
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                _ErrorCard(
                  message: _error!,
                ),
                const SizedBox(height: 18),
              ],
              _buildSummary(),
              const SizedBox(height: 18),
              _buildPartyCard(),
              const SizedBox(height: 18),
              _buildItemsCard(),
              if (_order.rejectionReason != null) ...[
                const SizedBox(height: 18),
                _buildReasonCard(
                  title: 'سبب الرفض',
                  reason: _order.rejectionReason!,
                  icon: Icons.cancel_outlined,
                ),
              ],
              if (_order.cancellationReason != null) ...[
                const SizedBox(height: 18),
                _buildReasonCard(
                  title: 'سبب الإلغاء',
                  reason: _order.cancellationReason!,
                  icon: Icons.block_rounded,
                ),
              ],
              if (_order.salesInvoiceId != null) ...[
                const SizedBox(height: 18),
                _buildInvoiceCard(),
              ],
              if (_order.isSubmitted) ...[
                const SizedBox(height: 24),
                _buildActions(),
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildSummary() {
    return _Card(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(
            icon: Icons.receipt_long_outlined,
            title: 'معلومات الطلب',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _InfoBox(
                title: 'رقم الطلب',
                value: _order.orderNumber,
              ),
              _InfoBox(
                title: 'المصدر',
                value: _order.sourceDisplayName,
              ),
              _InfoBox(
                title: 'نوع الدفع',
                value: _order.paymentTypeDisplayName,
              ),
              _InfoBox(
                title: 'تاريخ الطلب',
                value: _dateTime(
                  _order.submittedAt,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(
            color: AppTheme.subtleBorderColor,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _AmountBox(
                  title: 'المجموع',
                  value: _order.subtotal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AmountBox(
                  title: 'الخصم',
                  value: _order.discountAmount,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AmountBox(
                  title: 'الإجمالي',
                  value: _order.total,
                  emphasized: true,
                ),
              ),
            ],
          ),
          if (_order.notes != null) ...[
            const SizedBox(height: 18),
            _InfoLine(
              title: 'ملاحظات',
              value: _order.notes!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPartyCard() {
    return _Card(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            icon: _order.isRepresentative
                ? Icons.badge_outlined
                : Icons.person_outline_rounded,
            title: _order.isRepresentative
                ? 'بيانات المندوب والجهة'
                : 'بيانات الزبون',
          ),
          const SizedBox(height: 20),
          if (_order.customer != null) ...[
            _InfoLine(
              title: 'الاسم',
              value: _order.customer!.name,
            ),
            _InfoLine(
              title: 'الهاتف',
              value: _order.customer!.phone,
            ),
            if (_order.customer!.email != null)
              _InfoLine(
                title: 'البريد الإلكتروني',
                value: _order.customer!.email!,
              ),
            if (_order.customer!.address != null)
              _InfoLine(
                title: 'العنوان',
                value: _order.customer!.address!,
              ),
          ],
          if (_order.representative != null) ...[
            _InfoLine(
              title: 'المندوب',
              value: _order.representative!.name,
            ),
            if (_order.representative!.phone != null)
              _InfoLine(
                title: 'هاتف المندوب',
                value: _order.representative!.phone!,
              ),
            if (_order.representative!.officeName != null)
              _InfoLine(
                title: 'المكتب',
                value: _order.representative!.officeName!,
              ),
          ],
          if (_order.party != null) ...[
            const Divider(
              height: 26,
              color: AppTheme.subtleBorderColor,
            ),
            _InfoLine(
              title: 'الجهة',
              value: _order.party!.name,
            ),
            if (_order.party!.phone != null)
              _InfoLine(
                title: 'هاتف الجهة',
                value: _order.party!.phone!,
              ),
            if (_order.party!.address != null)
              _InfoLine(
                title: 'عنوان الجهة',
                value: _order.party!.address!,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsCard() {
    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              22,
              22,
              18,
            ),
            child: _CardTitle(
              icon: Icons.inventory_2_outlined,
              title: 'مواد الطلب',
            ),
          ),
          const Divider(
            height: 1,
            color: AppTheme.subtleBorderColor,
          ),
          if (_order.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'لا توجد مواد في هذا الطلب.',
                ),
              ),
            )
          else
            ..._order.items.map(
                  (item) => _OrderItemRow(
                item: item,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReasonCard({
    required String title,
    required String reason,
    required IconData icon,
  }) {
    return _Card(
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: AppTheme.dangerColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reason,
                  style: TextStyle(
                    color: AppTheme.secondaryTextColor,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'دخلت هذه البيانات إلى النظام كقائمة بيع بعد الموافقة.',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryTextColor,
            ),
          ),
          const SizedBox(height: 10),
          _InfoLine(
            title: 'معرف فاتورة المبيعات',
            value: _order.salesInvoiceId!,
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed:
          _processing ? null : _showRejectDialog,
          icon: const Icon(
            Icons.close_rounded,
          ),
          label: const Text(
            'رفض الطلب',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.dangerColor,
            padding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 16,
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed:
          _processing ? null : _showAcceptDialog,
          icon: _processing
              ? const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(
            Icons.check_rounded,
          ),
          label: const Text(
            'قبول الطلب',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  void _showMessage(
      String message,
      ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
          ),
        ),
      );
  }

  Future<List<_CloudWarehouse>> _cloudWarehouses() async {
    final response = await AppServices.apiClient.get(
      '/warehouses',
      queryParameters: {
        'page': 1,
        'limit': 100,
      },
      requiresBranch: false,
    );
    final body = response.data;
    final raw = body is Map ? body['data'] : null;
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw.whereType<Map>())
        _CloudWarehouse(
          id: '${item['id'] ?? ''}'.trim(),
          name: '${item['name'] ?? ''}'.trim(),
          status: '${item['status'] ?? ''}'.trim(),
        ),
    ].where((warehouse) => warehouse.id.isNotEmpty && warehouse.name.isNotEmpty).toList();
  }

  String _errorText(
      Object error,
      ) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
        if (message is Map && message['message'] is String) {
          final nested = '${message['message']}'.trim();
          if (nested.isNotEmpty) {
            return nested;
          }
        }
        if (message is List && message.isNotEmpty) {
          return message.map((item) => '$item').join('\n');
        }
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return 'تعذر الاتصال بالسيرفر. تحقق من الإنترنت ثم أعد الموافقة.';
        default:
          break;
      }
    }
    return error
        .toString()
        .replaceFirst(
      'Bad state: ',
      '',
    )
        .replaceFirst(
      'Exception: ',
      '',
    )
        .replaceFirst(
      'DioException [bad response]: ',
      '',
    );
  }
}

// =============================================================================
// ACCEPT RESULT
// =============================================================================

class _CloudWarehouse {
  final String id;
  final String name;
  final String status;

  const _CloudWarehouse({
    required this.id,
    required this.name,
    required this.status,
  });

  bool get isActive => status.toUpperCase() == 'ACTIVE';
}

class _AcceptDialogResult {
  final String warehouseServerId;
  final double? paidAmount;

  const _AcceptDialogResult({
    required this.warehouseServerId,
    required this.paidAmount,
  });
}

// =============================================================================
// UI
// =============================================================================

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _CardTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: AppTheme.primaryTextColor,
        ),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryTextColor,
          ),
        ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String title;
  final String value;

  const _InfoBox({
    required this.title,
    required this.value,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      width: 235,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountBox extends StatelessWidget {
  final String title;
  final double value;
  final bool emphasized;

  const _AmountBox({
    required this.title,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: emphasized
            ? AppTheme.primaryColor
            : const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: emphasized
                  ? Colors.white70
                  : AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _money(value),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: emphasized
                  ? Colors.white
                  : AppTheme.primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String title;
  final String value;

  const _InfoLine({
    required this.title,
    required this.value,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogInfoRow extends StatelessWidget {
  final String title;
  final String value;

  const _DialogInfoRow({
    required this.title,
    required this.value,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  final EcommerceOrderItemModel item;

  const _OrderItemRow({
    required this.item,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 22,
        vertical: 17,
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
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 19,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
                if (item.sku != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.sku!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.secondaryTextColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${_quantity(item.quantity)} ${item.unitName}',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              _money(item.unitPrice),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              _money(item.lineTotal),
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final EcommerceOrderModel order;

  const _StatusChip({
    required this.order,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    Color background;
    Color foreground;

    switch (order.status.toUpperCase()) {
      case 'ACCEPTED':
        background = const Color(0xFFEAF7EF);
        foreground = const Color(0xFF217A45);
        break;

      case 'REJECTED':
      case 'CANCELLED':
        background = const Color(0xFFFDEEEE);
        foreground = AppTheme.dangerColor;
        break;

      default:
        background = const Color(0xFFFFF5DF);
        foreground = const Color(0xFF9B6B00);
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        order.statusDisplayName,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({
    required this.message,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEEEE),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.dangerColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FORMAT
// =============================================================================

String _money(
    double value,
    ) {
  final integer = value == value.roundToDouble();

  final text = integer
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  final parts = text.split('.');

  final digits = parts.first;

  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    final position = digits.length - i;

    buffer.write(
      digits[i],
    );

    if (position > 1 &&
        (position - 1) % 3 == 0) {
      buffer.write(',');
    }
  }

  if (parts.length > 1) {
    buffer
      ..write('.')
      ..write(parts[1]);
  }

  return '${buffer.toString()} د.ع';
}

String _quantity(
    double value,
    ) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }

  return value.toStringAsFixed(2);
}

String _dateTime(
    DateTime? value,
    ) {
  if (value == null) {
    return '-';
  }

  String two(
      int number,
      ) =>
      number.toString().padLeft(2, '0');

  return '${value.year}/${two(value.month)}/${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}