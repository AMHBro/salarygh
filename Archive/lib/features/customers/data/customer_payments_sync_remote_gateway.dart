import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_remote_gateway.dart';

class CustomerPaymentsSyncRemoteGateway
    implements SyncRemoteGateway {
  final AppDatabase database;
  final ApiClient apiClient;

  CustomerPaymentsSyncRemoteGateway({
    required this.database,
    required this.apiClient,
  });

  // ===========================================================================
  // SUPPORTED ENTITIES
  // ===========================================================================

  @override
  Set<String> get supportedEntityTypes => {
    'customer_payment',
  };

  // ===========================================================================
  // PUSH
  // ===========================================================================

  @override
  Future<void> pushOperation(
      SyncOutboxData operation,
      ) async {
    final operationName =
    operation.operation.trim().toUpperCase();

    switch (operationName) {
      case 'CREATE':
        await _pushCreate(operation);
        return;

      default:
        throw StateError(
          'Unsupported customer payment sync operation: '
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
    final payment = await _getLocalPayment(
      operation.entityId,
    );

    if (payment == null) {
      throw StateError(
        'سند القبض المحلي غير موجود: '
            '${operation.entityId}',
      );
    }

    if (payment.amount <= 0) {
      throw StateError(
        'مبلغ سند القبض يجب أن يكون أكبر من صفر.',
      );
    }

    final customer = await _getLocalCustomer(
      payment.customerId,
    );

    if (customer == null) {
      throw StateError(
        'الزبون المرتبط بسند القبض غير موجود محلياً.',
      );
    }

    if (customer.deletedAt != null) {
      throw StateError(
        'لا يمكن مزامنة سند قبض لزبون محذوف.',
      );
    }

    final serverCustomerId = _clean(
      customer.serverId,
    );

    if (serverCustomerId == null) {
      throw StateError(
        'الزبون لم تتم مزامنته مع السيرفر بعد. '
            'سيتم إعادة محاولة إرسال سند القبض بعد مزامنة الزبون.',
      );
    }

    final body = <String, dynamic>{
      'amount': payment.amount,
    };

    final cleanNote = _clean(
      payment.note,
    );

    if (cleanNote != null) {
      body['notes'] = cleanNote;
    }

    try {
      debugPrint(
        '[CUSTOMER PAYMENT SYNC] Sending receipt: '
            'payment=${payment.id}, '
            'customerLocal=${customer.id}, '
            'customerServer=$serverCustomerId, '
            'amount=${payment.amount}',
      );

      final response = await apiClient.post(
        '/customers/$serverCustomerId/payments',
        data: body,
      );

      final statusCode =
          response.statusCode ?? 0;

      if (statusCode < 200 ||
          statusCode >= 300) {
        throw StateError(
          'فشل إرسال سند القبض. '
              'HTTP $statusCode',
        );
      }

      final raw = response.data;

      if (raw is Map) {
        final map =
        Map<String, dynamic>.from(raw);

        if (map['success'] == false) {
          throw StateError(
            _messageFromMap(map) ??
                'فشل تسجيل سند القبض على السيرفر.',
          );
        }
      }

      debugPrint(
        '[CUSTOMER PAYMENT SYNC] Receipt synced: '
            'payment=${payment.id}, '
            'voucher=${payment.voucherNumber}',
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
    // حالياً لا يوجد endpoint مستقل في الـAPI
    // لسحب جميع سندات قبض الزبائن.
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

  Future<CustomerPayment?>
  _getLocalPayment(
      String paymentId,
      ) {
    final query = database.select(
      database.customerPayments,
    )
      ..where(
            (table) =>
            table.id.equals(paymentId),
      );

    return query.getSingleOrNull();
  }

  Future<Customer?> _getLocalCustomer(
      String customerId,
      ) {
    final query = database.select(
      database.customers,
    )
      ..where(
            (table) =>
            table.id.equals(customerId),
      );

    return query.getSingleOrNull();
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

    final clean = value.trim();

    return clean.isEmpty
        ? null
        : clean;
  }

  String? _messageFromMap(
      Map<String, dynamic> map,
      ) {
    final message = map['message'];

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
            (item) => item.isNotEmpty,
      )
          .toList();

      if (messages.isNotEmpty) {
        return messages.join('\n');
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
      '[CUSTOMER PAYMENT SYNC] '
          'Failed payment=$paymentId',
    );

    debugPrint(
      '[CUSTOMER PAYMENT SYNC] '
          'HTTP ${error.response?.statusCode}',
    );

    debugPrint(
      '[CUSTOMER PAYMENT SYNC] '
          '${error.response?.data}',
    );
  }
}