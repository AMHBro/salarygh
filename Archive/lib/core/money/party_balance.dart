/// إذا كان المبلغ محفوظاً بالدينار والقائمة بالدولار، يُرجَع المبلغ بالدولار.
/// سند القبض يُمرَّر كما كُتب، بدون تحويل.
({double amount, String currency}) nativeLedgerAmount({
  required double amount,
  required String currency,
  double exchangeRate = 0,
  bool amountIsIqd = false,
}) {
  if (currency != 'USD') {
    return (amount: amount, currency: 'IQD');
  }
  if (!amountIsIqd) {
    return (amount: amount, currency: 'USD');
  }
  if (exchangeRate <= 0) {
    throw StateError('حدد سعر الدولار قبل تسجيل قائمة بالدولار.');
  }
  return (amount: amount / exchangeRate, currency: 'USD');
}

/// سطر الدينار ثم سطر الدولار. الصفر في العملتين يظهر «مسدد».
String partyBalanceLabel(double iqd, double usd) {
  if (iqd.abs() < 0.5 && usd.abs() < 0.005) {
    return 'مسدد';
  }
  final dinar = Money.parse(iqd).wholeDinars;
  final dinarText = dinar < BigInt.zero
      ? '${groupedWhole(dinar.abs())} د.ع له'
      : '${groupedWhole(dinar)} د.ع';
  final dollar = usd < 0
      ? '${usd.abs().toStringAsFixed(2)} \$ له'
      : '${usd.toStringAsFixed(2)} \$';
  return '$dinarText\n$dollar';
}

/// مبالغ ثابتة النقطة العشرية (ثلاثة أرقام) حتى لا يدخل الكسر الثنائي في الذمة.
class Money {
  final BigInt minor;

  static const int scale = 1000;
  static final BigInt _scale = BigInt.from(scale);

  const Money._(this.minor);

  static final Money zero = Money._(BigInt.zero);

  factory Money.parse(num value) {
    if (value.isNaN || value.isInfinite) {
      throw StateError('المبلغ غير صالح.');
    }
    return Money.fromDecimal(value.toStringAsFixed(8));
  }

  factory Money.fromDecimal(String raw) {
    final text = raw.trim().replaceAll(',', '');
    if (text.isEmpty) {
      throw StateError('المبلغ فارغ.');
    }
    var negative = false;
    var body = text;
    if (body.startsWith('-')) {
      negative = true;
      body = body.substring(1);
    } else if (body.startsWith('+')) {
      body = body.substring(1);
    }
    final parts = body.split('.');
    if (parts.length > 2 || parts.isEmpty) {
      throw StateError('المبلغ غير صالح.');
    }
    final whole = parts.first.isEmpty ? '0' : parts.first;
    final fraction = parts.length == 2 ? parts[1] : '';
    if (!RegExp(r'^\d+$').hasMatch(whole) ||
        (fraction.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fraction))) {
      throw StateError('المبلغ غير صالح.');
    }
    final padded = fraction.padRight(4, '0');
    final keep = padded.substring(0, 3);
    final roundDigit = int.parse(padded[3]);
    var minor = BigInt.parse(whole) * _scale + BigInt.parse(keep);
    if (roundDigit >= 5) {
      minor += BigInt.one;
    }
    if (negative) {
      minor = -minor;
    }
    return Money._(minor);
  }

  Money operator +(Money other) => Money._(minor + other.minor);

  Money operator -(Money other) => Money._(minor - other.minor);

  Money abs() => Money._(minor.abs());

  bool get isNegative => minor < BigInt.zero;

  bool get isZero => minor == BigInt.zero;

  double toDouble() {
    final negative = minor < BigInt.zero;
    final absolute = minor.abs();
    final whole = absolute ~/ _scale;
    final fraction = absolute.remainder(_scale);
    final value = whole.toDouble() + fraction.toDouble() / scale;
    return negative ? -value : value;
  }

  /// دينار صحيح بتدوير Half-Up بعيداً عن الصفر.
  BigInt get wholeDinars {
    final negative = minor < BigInt.zero;
    final absolute = minor.abs();
    var whole = absolute ~/ _scale;
    final fraction = absolute.remainder(_scale);
    if (fraction * BigInt.two >= _scale) {
      whole += BigInt.one;
    }
    return negative ? -whole : whole;
  }
}

class LedgerLine {
  final String id;
  final String type;
  final String? referenceId;
  final DateTime createdAt;
  final Money amount;
  final String currency;

  const LedgerLine({
    required this.id,
    required this.type,
    required this.referenceId,
    required this.createdAt,
    required this.amount,
    this.currency = 'IQD',
  });
}

class VoucherSnapshot {
  final Money previous;
  final Money amount;
  final Money remaining;
  final String type;

  const VoucherSnapshot({
    required this.previous,
    required this.amount,
    required this.remaining,
    required this.type,
  });

  bool get isDisbursement => type == 'PAYMENT';
}

/// موجب: الطرف مدين (عليه). سالب: الطرف دائن (له).
Money customerLedgerEffect(String type, Money amount) {
  final magnitude = amount.abs();
  switch (type) {
    case 'SALE':
    case 'OPENING_BALANCE':
    case 'PAYMENT':
      return magnitude;
    case 'RECEIPT':
    case 'REVERSAL':
      return Money.zero - magnitude;
    default:
      return Money.zero;
  }
}

/// موجب: نحن مدينون للشركة. سالب: الشركة مدينة لنا.
Money supplierLedgerEffect(String type, Money amount) {
  final magnitude = amount.abs();
  switch (type) {
    case 'PURCHASE':
    case 'OPENING_BALANCE':
      return magnitude;
    case 'PAYMENT':
    case 'RECEIPT':
      return Money.zero - magnitude;
    default:
      return Money.zero;
  }
}

int _typeRank(String type) {
  switch (type) {
    case 'SALE':
    case 'PURCHASE':
    case 'OPENING_BALANCE':
    case 'PAYMENT':
      return 0;
    case 'RECEIPT':
    case 'REVERSAL':
      return 1;
    default:
      return 2;
  }
}

List<LedgerLine> orderedLedger(List<LedgerLine> lines) {
  final copy = List<LedgerLine>.from(lines);
  copy.sort((a, b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    if (byTime != 0) {
      return byTime;
    }
    final byRank = _typeRank(a.type).compareTo(_typeRank(b.type));
    if (byRank != 0) {
      return byRank;
    }
    return a.id.compareTo(b.id);
  });
  return copy;
}

VoucherSnapshot? voucherSnapshot({
  required List<LedgerLine> lines,
  required String referenceId,
  required Money Function(String type, Money amount) effectOf,
}) {
  final key = referenceId.trim();
  if (key.isEmpty) {
    return null;
  }
  final ordered = orderedLedger(lines);
  LedgerLine? target;
  for (final line in ordered) {
    if ((line.referenceId ?? '').trim() == key) {
      target = line;
      break;
    }
  }
  if (target == null) {
    return null;
  }
  final currency = target.currency == 'USD' ? 'USD' : 'IQD';
  var running = Money.zero;
  for (final line in ordered) {
    final lineCurrency = line.currency == 'USD' ? 'USD' : 'IQD';
    if (lineCurrency != currency) {
      continue;
    }
    final effect = effectOf(line.type, line.amount);
    if ((line.referenceId ?? '').trim() == key) {
      return VoucherSnapshot(
        previous: running,
        amount: line.amount.abs(),
        remaining: running + effect,
        type: line.type,
      );
    }
    running += effect;
  }
  return null;
}

class SaleBalanceSnapshot {
  final Money previous;
  final Money paid;
  final Money remaining;

  const SaleBalanceSnapshot({
    required this.previous,
    required this.paid,
    required this.remaining,
  });
}

/// الرصيد قبل قائمة البيع، ثم بعد إجماليها مطروحاً منه المقبوض.
SaleBalanceSnapshot? saleBalanceSnapshot({
  required List<LedgerLine> lines,
  required String saleId,
  required Money invoiceTotal,
  required Money paid,
}) {
  final key = saleId.trim();
  if (key.isEmpty) {
    return null;
  }
  final ordered = orderedLedger(lines);
  String currency = 'IQD';
  for (final line in ordered) {
    if (line.type == 'SALE' && (line.referenceId ?? '').trim() == key) {
      currency = line.currency == 'USD' ? 'USD' : 'IQD';
      break;
    }
  }
  var running = Money.zero;
  for (final line in ordered) {
    final lineCurrency = line.currency == 'USD' ? 'USD' : 'IQD';
    if (lineCurrency != currency) {
      continue;
    }
    if (line.type == 'SALE' && (line.referenceId ?? '').trim() == key) {
      return SaleBalanceSnapshot(
        previous: running,
        paid: paid.abs(),
        remaining: running + invoiceTotal.abs() - paid.abs(),
      );
    }
    running += customerLedgerEffect(line.type, line.amount);
  }
  return null;
}

String groupedWhole(BigInt value) {
  final negative = value < BigInt.zero;
  final text = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(text[index]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

/// عليه = الطرف يطالبنا به. له = نحن نطالبه.
String balanceWords(Money value) {
  final whole = value.wholeDinars;
  if (whole == BigInt.zero) {
    return '0';
  }
  final amount = groupedWhole(whole.abs());
  return whole < BigInt.zero ? '$amount له' : '$amount عليه';
}
