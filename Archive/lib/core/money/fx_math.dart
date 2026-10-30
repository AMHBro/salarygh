import 'party_balance.dart';

/// ضرب صحيح مع تدوير Half-Up بعيداً عن الصفر.
int mulDivHalfUp(int left, int right, int divisor) {
  if (left == 0 || right == 0 || divisor == 0) {
    return 0;
  }
  final negative = (left < 0) ^ (right < 0) ^ (divisor < 0);
  final product = BigInt.from(left.abs()) * BigInt.from(right.abs());
  final scale = BigInt.from(divisor.abs());
  final whole = (product + (scale ~/ BigInt.two)) ~/ scale;
  final value = whole.toInt();
  return negative ? -value : value;
}

int moneyMinor(num value) {
  if (value.isNaN || value.isInfinite) {
    return 0;
  }
  return Money.parse(value).minor.toInt();
}

/// دينار السطر = القطع × كلفة القطعة، وكلاهما بألف.
int lineCostIqd(int piecesMinor, int pieceCostMinor) {
  return mulDivHalfUp(piecesMinor, pieceCostMinor, 1000000);
}

/// دولارات الطبقة = قطعها × كلفة الدولار للقطعة.
int usdMinorForPieces(int piecesMinor, int usdPerPieceMinor) {
  return mulDivHalfUp(piecesMinor, usdPerPieceMinor, 1000);
}

/// دينار مقابل مبلغ دولار. سعر الصرف أيضاً بالألف: 1500 = 1500000.
int iqdFromUsd(int usdMinor, int rateMillis) {
  return mulDivHalfUp(usdMinor, rateMillis, 1000000);
}

int replacementIqd({
  required int costIqd,
  required int usdMinor,
  required int usdBookIqd,
  required int rateMillis,
}) {
  if (usdMinor <= 0 || rateMillis <= 0) {
    return costIqd;
  }
  return costIqd - usdBookIqd + iqdFromUsd(usdMinor, rateMillis);
}

int fxDifferenceIqd({
  required int usdMinor,
  required int debtRateMillis,
  required int payRateMillis,
}) {
  return iqdFromUsd(usdMinor, payRateMillis) -
      iqdFromUsd(usdMinor, debtRateMillis);
}

int blendAverage({
  required int oldPieces,
  required int oldCost,
  required int addPieces,
  required int addCost,
}) {
  final totalPieces = oldPieces + addPieces;
  if (totalPieces <= 0) {
    return 0;
  }
  if (oldPieces <= 0 || oldCost <= 0) {
    return addCost;
  }
  final weighted = BigInt.from(oldPieces) * BigInt.from(oldCost) +
      BigInt.from(addPieces) * BigInt.from(addCost);
  final divisor = BigInt.from(totalPieces);
  return ((weighted + (divisor ~/ BigInt.two)) ~/ divisor).toInt();
}

/// كمية الدولار التي تخرج مع البيع، بنسبة ما يمثله الدولار من الرصيد.
int takeUsdPieces({
  required int layerPieces,
  required int onHandPieces,
  required int soldPieces,
}) {
  if (layerPieces <= 0 || onHandPieces <= 0 || soldPieces <= 0) {
    return 0;
  }
  final sold = soldPieces > onHandPieces ? onHandPieces : soldPieces;
  final taken = mulDivHalfUp(layerPieces, sold, onHandPieces);
  if (taken < 0) {
    return 0;
  }
  return taken > layerPieces ? layerPieces : taken;
}

String formatRateMillis(int millis) {
  if (millis == 0) {
    return '';
  }
  final negative = millis < 0;
  final absolute = millis.abs();
  final whole = absolute ~/ 1000;
  final fraction = absolute % 1000;
  if (fraction == 0) {
    return negative ? '-$whole' : '$whole';
  }
  final digits = fraction.toString().padLeft(3, '0').replaceFirst(
        RegExp(r'0+$'),
        '',
      );
  final text = '$whole.$digits';
  return negative ? '-$text' : text;
}

String fxMovementNote(int debtRateMillis, int payRateMillis) {
  final from = formatRateMillis(debtRateMillis);
  final to = formatRateMillis(payRateMillis);
  if (payRateMillis > debtRateMillis) {
    return 'ارتفاع الدولار من $from إلى $to';
  }
  if (payRateMillis < debtRateMillis) {
    return 'انخفاض الدولار من $from إلى $to';
  }
  return '';
}
