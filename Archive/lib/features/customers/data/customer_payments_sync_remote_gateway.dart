import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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

  static const Uuid _uuid = Uuid();

  @override
  Future<SyncPullResult> pullChanges({
    String? cursor,
  }) async {
    try {
      final customers = await (database.select(database.customers)
            ..where((table) => table.deletedAt.isNull()))
          .get();
      final byServerId = <String, Customer>{};
      final byName = <String, Customer>{};
      final nameCount = <String, int>{};
      for (final customer in customers) {
        final serverId = (customer.serverId ?? '').trim();
        if (serverId.isNotEmpty) byServerId[serverId] = customer;
        final key = customer.name.trim();
        if (key.isEmpty) continue;
        nameCount[key] = (nameCount[key] ?? 0) + 1;
        byName[key] = customer;
      }
      var page = 1;
      var saved = 0;
      while (page <= 40) {
        final response = await apiClient.get(
          '/reports/cash/vouchers',
          queryParameters: {
            'page': '$page',
            'limit': '100',
          },
        );
        final rows = _rows(response.data);
        if (rows.isEmpty) break;
        for (final row in rows) {
          if ('${row['voucher_type'] ?? ''}'.toUpperCase() != 'RECEIPT') {
            continue;
          }
          final number = '${row['voucher_number'] ?? ''}'.trim();
          final party = '${row['party_name'] ?? ''}'.trim();
          final amount = _amount(row['amount_iqd']);
          if (number.isEmpty || party.isEmpty || party == 'غير محدد' || amount == null || amount <= 0) {
            continue;
          }
          final serverParty = '${row['customer_id'] ?? ''}'.trim();
          final customer = serverParty.isNotEmpty
              ? byServerId[serverParty]
              : (nameCount[party] == 1 ? byName[party] : null);
          if (customer == null) continue;
          final existing = await (database.select(database.customerPayments)
                ..where((table) => table.voucherNumber.equals(number)))
              .getSingleOrNull();
          if (existing != null) continue;
          final createdAt = DateTime.tryParse('${row['created_at'] ?? row['voucher_date'] ?? ''}') ??
              DateTime.now();
          final invoiceNumber = '${row['invoice_number'] ?? ''}'.trim();
          try {
            final paymentId = _uuid.v4();
            await database.into(database.customerPayments).insert(
                  CustomerPaymentsCompanion.insert(
                    id: paymentId,
                    voucherNumber: number,
                    customerId: customer.id,
                    method: Value(_localMethod('${row['payment_method'] ?? ''}')),
                    amount: amount,
                    note: Value(_clean('${row['notes'] ?? ''}')),
                    createdAt: createdAt,
                  ),
                );
            if (invoiceNumber.isEmpty) {
              final ledger = await (database.select(database.customerLedgerEntries)
                    ..where(
                      (table) =>
                          table.referenceType.equals('VOUCHER') &
                          table.referenceId.equals(number),
                    ))
                  .getSingleOrNull();
              if (ledger == null) {
                await database.into(database.customerLedgerEntries).insert(
                      CustomerLedgerEntriesCompanion.insert(
                        id: _uuid.v4(),
                        customerId: customer.id,
                        type: 'RECEIPT',
                        amount: amount,
                        referenceType: const Value('VOUCHER'),
                        referenceId: Value(number),
                        createdAt: createdAt,
                      ),
                    );
              }
            }
            saved++;
          } catch (error) {
            debugPrint('[CUSTOMER PAYMENT SYNC] Skip voucher $number: $error');
          }
        }
        if (rows.length < 100) break;
        page++;
      }
      debugPrint('[CUSTOMER PAYMENT SYNC] Pulled $saved receipt(s).');
    } catch (error) {
      debugPrint('[CUSTOMER PAYMENT SYNC] Receipt pull skipped: $error');
    }
    return const SyncPullResult(
      nextCursor: null,
      changes: [],
    );
  }

  List<Map<String, dynamic>> _rows(dynamic raw) {
    final data = raw is Map && raw['data'] is List ? raw['data'] : raw;
    if (data is! List) return const [];
    return data.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  double? _amount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  String _localMethod(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'BANK_TRANSFER':
      case 'BANK':
        return 'BANK';
      case 'CASH':
        return 'CASH';
      default:
        return 'OTHER';
    }
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