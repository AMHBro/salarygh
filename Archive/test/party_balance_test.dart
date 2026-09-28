import 'package:flutter_test/flutter_test.dart';
import 'package:sales_system/core/money/party_balance.dart';

void main() {
  test('قبض 500000 ثم صرف 1000000 يقلب اتجاه الذمة', () {
    final at = DateTime(2026, 9, 27, 10);
    final lines = [
      LedgerLine(
        id: 'a',
        type: 'RECEIPT',
        referenceId: 'receipt-1',
        createdAt: at,
        amount: Money.parse(500000),
      ),
      LedgerLine(
        id: 'b',
        type: 'PAYMENT',
        referenceId: 'pay-1',
        createdAt: at.add(const Duration(minutes: 5)),
        amount: Money.parse(1000000),
      ),
    ];

    final receipt = voucherSnapshot(
      lines: lines,
      referenceId: 'receipt-1',
      effectOf: customerLedgerEffect,
    );
    final disbursement = voucherSnapshot(
      lines: lines,
      referenceId: 'pay-1',
      effectOf: customerLedgerEffect,
    );

    expect(receipt, isNotNull);
    expect(receipt!.previous.isZero, isTrue);
    expect(receipt.remaining.toDouble(), -500000);
    expect(balanceWords(receipt.remaining), '500,000 له');

    expect(disbursement, isNotNull);
    expect(disbursement!.previous.toDouble(), -500000);
    expect(disbursement.amount.toDouble(), 1000000);
    expect(disbursement.remaining.toDouble(), 500000);
    expect(balanceWords(disbursement.previous), '500,000 له');
    expect(balanceWords(disbursement.remaining), '500,000 عليه');
    expect(
      (disbursement.previous + disbursement.amount).toDouble(),
      disbursement.remaining.toDouble(),
    );
  });

  test('قائمة البيع تُبقي الرصيد الدائن ولا تصفّره', () {
    final lines = [
      LedgerLine(
        id: 'a',
        type: 'RECEIPT',
        referenceId: 'receipt-1',
        createdAt: DateTime(2026, 9, 27, 10),
        amount: Money.parse(500000),
      ),
      LedgerLine(
        id: 'sale',
        type: 'SALE',
        referenceId: 'sale-1',
        createdAt: DateTime(2026, 9, 27, 11),
        amount: Money.parse(200000),
      ),
    ];

    final snapshot = saleBalanceSnapshot(
      lines: lines,
      saleId: 'sale-1',
      invoiceTotal: Money.parse(200000),
      paid: Money.parse(0),
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.previous.toDouble(), -500000);
    expect(snapshot.remaining.toDouble(), -300000);
    expect(balanceWords(snapshot.remaining), '300,000 له');
  });

  test('بيع الدولار لا يغيّر رصيد الدينار', () {
    final lines = [
      LedgerLine(
        id: 'iqd-sale',
        type: 'SALE',
        referenceId: 'sale-iqd',
        createdAt: DateTime(2026, 9, 28, 9),
        amount: Money.parse(200000),
        currency: 'IQD',
      ),
      LedgerLine(
        id: 'usd-sale',
        type: 'SALE',
        referenceId: 'sale-usd',
        createdAt: DateTime(2026, 9, 28, 10),
        amount: Money.parse(100),
        currency: 'USD',
      ),
      LedgerLine(
        id: 'usd-pay',
        type: 'RECEIPT',
        referenceId: 'pay-usd',
        createdAt: DateTime(2026, 9, 28, 11),
        amount: Money.parse(40),
        currency: 'USD',
      ),
    ];

    final iqd = saleBalanceSnapshot(
      lines: lines,
      saleId: 'sale-iqd',
      invoiceTotal: Money.parse(200000),
      paid: Money.parse(0),
    );
    final usd = saleBalanceSnapshot(
      lines: lines,
      saleId: 'sale-usd',
      invoiceTotal: Money.parse(100),
      paid: Money.parse(40),
    );

    expect(iqd!.previous.toDouble(), 0);
    expect(iqd.remaining.toDouble(), 200000);
    expect(usd!.previous.toDouble(), 0);
    expect(usd.remaining.toDouble(), 60);
    expect(
      partyBalanceLabel(200000, 60),
      '200,000 د.ع\n60.00 \$',
    );
  });

  test('التدوير Half-Up عند منتصف الألف', () {
    expect(Money.fromDecimal('1.0005').minor, BigInt.from(1001));
    expect(Money.fromDecimal('1.0004').minor, BigInt.from(1000));
    expect(Money.fromDecimal('-1.0005').toDouble(), -1.001);
  });
}
