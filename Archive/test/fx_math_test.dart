import 'package:flutter_test/flutter_test.dart';
import 'package:sales_system/core/money/fx_math.dart';

void main() {
  test('ten dollars at 1500 is 15000 dinars', () {
    expect(iqdFromUsd(10000, 1500000), 15000);
  });

  test('paying the same ten dollars at 1700 loses 2000', () {
    expect(
      fxDifferenceIqd(
        usdMinor: 10000,
        debtRateMillis: 1500000,
        payRateMillis: 1700000,
      ),
      2000,
    );
    expect(fxMovementNote(1500000, 1700000), 'ارتفاع الدولار من 1500 إلى 1700');
  });

  test('a drop in the dollar is a gain', () {
    expect(
      fxDifferenceIqd(
        usdMinor: 10000,
        debtRateMillis: 1700000,
        payRateMillis: 1500000,
      ),
      -2000,
    );
  });

  test('line cost uses half-up on pieces and piece cost', () {
    expect(lineCostIqd(2500, 1000000), 2500);
    expect(lineCostIqd(1000, 1500500), 1501);
  });

  test('usd layer average and sale slice stay on the dollar goods', () {
    final average = blendAverage(
      oldPieces: 10000,
      oldCost: 10000,
      addPieces: 10000,
      addCost: 12000,
    );
    expect(average, 11000);
    expect(
      takeUsdPieces(layerPieces: 5000, onHandPieces: 10000, soldPieces: 4000),
      2000,
    );
  });

  test('replacement keeps the dinar portion and reprices the dollar portion', () {
    expect(
      replacementIqd(
        costIqd: 15000,
        usdMinor: 10000,
        usdBookIqd: 15000,
        rateMillis: 1700000,
      ),
      17000,
    );
  });
}
