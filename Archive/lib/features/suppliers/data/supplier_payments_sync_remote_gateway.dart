import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_remote_gateway.dart';

class SupplierPaymentsSyncRemoteGateway
    implements SyncRemoteGateway {
  final AppDatabase database;
  final ApiClient apiClient;

  SupplierPaymentsSyncRemoteGateway({
    required this.database,
    required this.apiClient,
  });

  // ===========================================================================
  // SUPPORTED ENTITIES
  // ===========================================================================

  @override
  Set<String> get supportedEntityTypes => {
    'supplier_payment',
  };

  // ===========================================================================
  // PUSH
  // ===========================================================================

  @override
  Future<void> pushOperation(
      SyncOutboxData operation,
      ) async {
    final operationName =
    operation.operation
        .trim()
        .toUpperCase();

    switch (operationName) {
      case 'CREATE':
        await _pushCreate(
          operation,
        );
        return;

      default:
        throw StateError(
          'Unsupported supplier payment sync operation: '
              '${operation.operation}',
        );
    }
  }

  // ===========================================================================
  // CREATE
  // ===========================================================================

  Future<void> _pushCreate(
      SyncOutboxData operation,
      ) async {
    final payment =
    await _getLocalPayment(
      operation.entityId,
    );

    if (payment == null) {
      throw StateError(
        'سند دفع المورد المحلي غير موجود: '
            '${operation.entityId}',
      );
    }

    if (payment.amount <= 0) {
      throw StateError(
        'مبلغ سند دفع المورد يجب أن يكون أكبر من صفر.',
      );
    }

    final supplier =
    await _getLocalSupplier(
      payment.supplierId,
    );

    if (supplier == null) {
      throw StateError(
        'المورد المرتبط بسند الدفع غير موجود محلياً.',
      );
    }

    if (supplier.deletedAt != null) {
      throw StateError(
        'لا يمكن مزامنة سند دفع لمورد محذوف.',
      );
    }

    if (!supplier.isActive) {
      throw StateError(
        'لا يمكن مزامنة سند دفع لمورد غير فعال.',
      );
    }

    final serverSupplierId =
    _clean(
      supplier.serverId,
    );

    if (serverSupplierId == null) {
      throw StateError(
        'المورد لم تتم مزامنته مع السيرفر بعد. '
            'سيتم إعادة محاولة إرسال سند الدفع بعد مزامنة المورد.',
      );
    }

    final paymentMethod =
    _normalizePaymentMethod(
      payment.method,
    );

    // -----------------------------------------------------------------------
    // Backend contract:
    //
    // POST /supplier-payments
    //
    // supplier_id     required UUID
    // invoice_id      optional UUID
    // amount          required number
    // payment_method  required enum
    // notes           optional
    //
    // سند الدفع الحالي في النظام هو سداد عام للمورد، لذلك لا نرسل
    // invoice_id ما لم نضيف لاحقاً ربط سند الدفع بفاتورة شراء محددة.
    // -----------------------------------------------------------------------

    final body =
    <String, dynamic>{
      'supplier_id':
      serverSupplierId,
      'amount': payment.amount,
      'payment_method':
      paymentMethod,
    };

    final cleanNote =
    _clean(
      payment.note,
    );

    if (cleanNote != null) {
      body['notes'] =
          cleanNote;
    }

    try {
      debugPrint(
        '[SUPPLIER PAYMENT SYNC] Sending payment: '
            'payment=${payment.id}, '
            'supplierLocal=${supplier.id}, '
            'supplierServer=$serverSupplierId, '
            'amount=${payment.amount}, '
            'method=$paymentMethod',
      );

      final response =
      await apiClient.post(
        '/supplier-payments',
        data: body,
      );

      final statusCode =
          response.statusCode ?? 0;

      if (statusCode < 200 ||
          statusCode >= 300) {
        throw StateError(
          'فشل إرسال سند دفع المورد. '
              'HTTP $statusCode',
        );
      }

      final raw =
          response.data;

      // لا نعتمد على شكل Response محدد.
      //
      // إذا كان السيرفر يرجع success:false بشكل صريح،
      // نعتبر العملية فاشلة.
      //
      // خلاف ذلك، أي 2xx يعتبر نجاحاً.
      if (raw is Map) {
        final map =
        Map<String, dynamic>.from(
          raw,
        );

        if (map['success'] == false) {
          throw StateError(
            _messageFromMap(
              map,
            ) ??
                'فشل تسجيل سند دفع المورد على السيرفر.',
          );
        }
      }

      debugPrint(
        '[SUPPLIER PAYMENT SYNC] Payment synced: '
            'payment=${payment.id}, '
            'voucher=${payment.voucherNumber}, '
            'supplierServer=$serverSupplierId',
      );
    } on DioException catch (error) {
      _logDioError(
        operation.entityId,
        error,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // PULL
  // ===========================================================================

  @override
  Future<SyncPullResult> pullChanges({
    String? cursor,
  }) async {
    // لا يوجد حالياً endpoint مؤكد لسحب جميع سندات دفع الموردين.
    //
    // لذلك هذا الـGateway مسؤول عن PUSH فقط.
    return const SyncPullResult(
      nextCursor: null,
      changes: [],
    );
  }

  // ===========================================================================
  // LOCAL LOOKUPS
  // ===========================================================================

  Future<SupplierPayment?>
  _getLocalPayment(
      String paymentId,
      ) {
    final query =
    database.select(
      database.supplierPayments,
    )
      ..where(
            (table) =>
            table.id.equals(
              paymentId,
            ),
      );

    return query.getSingleOrNull();
  }

  Future<Supplier?>
  _getLocalSupplier(
      String supplierId,
      ) {
    final query =
    database.select(
      database.suppliers,
    )
      ..where(
            (table) =>
            table.id.equals(
              supplierId,
            ),
      );

    return query.getSingleOrNull();
  }

  // ===========================================================================
  // PAYMENT METHOD
  // ===========================================================================

  String _normalizePaymentMethod(
      String value,
      ) {
    switch (
    value.trim().toUpperCase()) {
      case 'CASH':
        return 'CASH';

      case 'BANK_TRANSFER':
      case 'BANK':
        return 'BANK_TRANSFER';

      case 'CHECK':
        return 'CHECK';

      case 'POS_MACHINE':
      case 'POS':
        return 'POS_MACHINE';

    // Legacy compatibility only.
    //
    // OTHER ليس ضمن enum الخاص بالـBackend.
      case 'OTHER':
        return 'CASH';

      default:
        throw StateError(
          'طريقة دفع المورد غير مدعومة: $value',
        );
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String? _clean(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final clean =
    value.trim();

    return clean.isEmpty
        ? null
        : clean;
  }

  String? _messageFromMap(
      Map<String, dynamic> map,
      ) {
    final message =
    map['message'];

    if (message is String &&
        message.trim().isNotEmpty) {
      return message.trim();
    }

    if (message is List) {
      final messages = message
          .map(
            (item) =>
            item.toString().trim(),
      )
          .where(
            (item) =>
        item.isNotEmpty,
      )
          .toList();

      if (messages.isNotEmpty) {
        return messages.join(
          '\n',
        );
      }
    }

    return null;
  }

  // ===========================================================================
  // ERROR LOG
  // ===========================================================================

  void _logDioError(
      String paymentId,
      DioException error,
      ) {
    debugPrint(
      '[SUPPLIER PAYMENT SYNC] '
          'Failed payment=$paymentId',
    );

    debugPrint(
      '[SUPPLIER PAYMENT SYNC] '
          'HTTP ${error.response?.statusCode}',
    );

    debugPrint(
      '[SUPPLIER PAYMENT SYNC] '
          '${error.response?.data}',
    );
  }
}