import 'package:flutter_test/flutter_test.dart';
import 'package:sales_system/core/printing/print_preview.dart';

void main() {
  test('متبقي السلة هو الإجمالي ناقص المسدد والرصيد النهائي يضم الدين السابق', () {
    final figures = printMoneyFigures(
      invoiceTotal: 10000,
      paid: 4000,
      previousBalance: 2500,
    );

    expect(figures.invoiceTotal, 10000);
    expect(figures.paid, 4000);
    expect(figures.invoiceRemaining, 6000);
    expect(figures.finalBalance, 8500);

    final lines = printMoneyLines(figures);
    expect(lines, contains('متبقي القائمة: 6,000'));
    expect(lines, contains('الرصيد النهائي: 8,500'));
  });

  test('رصيد الدفتر المحفوظ يغلب الحساب المحلي للرصيد النهائي', () {
    final figures = printMoneyFigures(
      invoiceTotal: 10000,
      paid: 10000,
      previousBalance: 2500,
      ledgerFinalBalance: 2500,
    );

    expect(figures.invoiceRemaining, 0);
    expect(figures.finalBalance, 2500);
  });

  test('بيع نقدي كامل يبقي الرصيد النهائي على الدين السابق', () {
    final figures = printMoneyFigures(
      invoiceTotal: 7000,
      paid: 7000,
      previousBalance: 1500,
    );

    expect(figures.invoiceRemaining, 0);
    expect(figures.finalBalance, 1500);
  });
}
