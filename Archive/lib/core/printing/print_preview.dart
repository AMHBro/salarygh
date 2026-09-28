import 'dart:convert';

import 'package:flutter/material.dart';

import '../../features/reports/models/report_catalog.dart';
import '../../features/settings/data/company_settings_repository.dart';
import '../../features/settings/models/document_layout.dart';
import '../di/app_services.dart';
import '../theme/app_theme.dart';
import 'print_channel.dart';

class PrintDocument {
  final String kind;
  final String title;
  final String partyLabel;
  final String party;
  final String printedDate;
  final String printedTime;
  final String documentTypeLabel;
  final String documentType;
  final List<String> lines;
  final List<String> columns;
  final List<List<String>> rows;
  final List<String> totals;
  final String number;
  final double discount;
  final double porterage;
  final double cartonCount;
  final double previousIqd;
  final double paidIqd;
  final double remainingIqd;
  final double previousUsd;
  final double paidUsd;
  final double remainingUsd;
  final double grandTotal;
  final String previousIqdLabel;
  final String paidIqdLabel;
  final String remainingIqdLabel;

  const PrintDocument({
    required this.kind,
    required this.title,
    this.partyLabel = 'الزبون',
    this.party = '',
    this.printedDate = '',
    this.printedTime = '',
    this.documentTypeLabel = 'نوع القائمة',
    this.documentType = '',
    this.lines = const [],
    this.columns = const [],
    this.rows = const [],
    this.totals = const [],
    this.number = '',
    this.discount = 0,
    this.porterage = 0,
    this.cartonCount = 0,
    this.previousIqd = 0,
    this.paidIqd = 0,
    this.remainingIqd = 0,
    this.previousUsd = 0,
    this.paidUsd = 0,
    this.remainingUsd = 0,
    this.grandTotal = 0,
    this.previousIqdLabel = 'الرصيد السابق دينار',
    this.paidIqdLabel = 'المبلغ المسدد دينار',
    this.remainingIqdLabel = 'الرصيد المتبقي دينار',
  });

  bool get hasIdentity =>
      party.trim().isNotEmpty ||
      printedDate.trim().isNotEmpty ||
      printedTime.trim().isNotEmpty ||
      documentType.trim().isNotEmpty;
}

String printDateText(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String printTimeText(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

const kInvoiceColumns = <String>[
  'ت',
  'التفاصيل',
  'كارتون',
  'سعر الكارتون',
  'قطعة',
  'سعر القطعة',
  'المبلغ',
  'ملاحظة',
];

String moneyText(num value) {
  final rounded = value.round();
  final negative = rounded < 0;
  final text = rounded.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(text[index]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

List<String> invoiceCells({
  required int index,
  required String details,
  required double quantity,
  required double unitPrice,
  required double factor,
  required double amount,
  String note = '',
  bool asCarton = false,
  double loose = 0,
  bool priceIsPerPiece = false,
}) {
  if (priceIsPerPiece) {
    final factorSafe = factor <= 0 ? 1.0 : factor;
    final piecePrice = unitPrice;
    final cartonPrice = piecePrice * factorSafe;
    return [
      '$index',
      details,
      (quantity < 0 ? 0 : quantity).toStringAsFixed(0),
      moneyText(cartonPrice),
      (loose < 0 ? 0 : loose).toStringAsFixed(0),
      moneyText(piecePrice),
      moneyText(amount),
      note,
    ];
  }

  final carton = asCarton || factor > 1.001;
  final piecePrice = factor > 1.001 ? unitPrice / factor : unitPrice;
  return [
    '$index',
    details,
    (carton ? quantity : 0).toStringAsFixed(0),
    moneyText(carton ? unitPrice : 0),
    (carton ? loose : quantity).toStringAsFixed(0),
    moneyText(piecePrice),
    moneyText(amount),
    note,
  ];
}

double cartonPieces(double quantity, double factor) {
  return factor > 1.001 ? quantity : 0;
}

/// أرقام ورقة البيع: إجمالي السلة، المسدد، متبقي هذه القائمة، والرصيد النهائي على الزبون.
class PrintMoneyFigures {
  final double invoiceTotal;
  final double paid;
  final double invoiceRemaining;
  final double previousBalance;
  final double finalBalance;

  const PrintMoneyFigures({
    required this.invoiceTotal,
    required this.paid,
    required this.invoiceRemaining,
    required this.previousBalance,
    required this.finalBalance,
  });
}

PrintMoneyFigures printMoneyFigures({
  required double invoiceTotal,
  required double paid,
  required double previousBalance,
  double? ledgerFinalBalance,
}) {
  final total = invoiceTotal < 0 ? 0.0 : invoiceTotal;
  final settled = paid < 0 ? 0.0 : paid;
  final invoiceRemaining = total - settled;
  return PrintMoneyFigures(
    invoiceTotal: total,
    paid: settled,
    invoiceRemaining: invoiceRemaining,
    previousBalance: previousBalance,
    finalBalance: ledgerFinalBalance ?? (previousBalance + invoiceRemaining),
  );
}

List<String> printMoneyLines(PrintMoneyFigures figures) {
  return [
    'إجمالي القائمة: ${moneyText(figures.invoiceTotal)}',
    'المسدد: ${moneyText(figures.paid)}',
    'متبقي القائمة: ${moneyText(figures.invoiceRemaining)}',
    'الرصيد السابق: ${moneyText(figures.previousBalance)}',
    'الرصيد النهائي: ${moneyText(figures.finalBalance)}',
  ];
}

Future<void> showPrintPreview(
  BuildContext context,
  PrintDocument document,
) async {
  var header = const DocumentHeader();
  var sections = const <String>[];
  try {
    final company = await CompanySettingsRepository(
      apiClient: AppServices.apiClient,
    ).getCompany();
    final settings = company['settings'];
    header = DocumentLayouts.headerFrom(settings);
    final receipt = document.kind.contains('وصل') || document.kind.contains('سند');
    final blocks = receipt
        ? DocumentLayouts.receiptFrom(settings)
        : DocumentLayouts.invoiceFrom(settings);
    sections = [
      for (final block in blocks)
        if (block.visible) block.id,
    ];
    if (header.officeName.trim().isEmpty) {
      header = DocumentHeader(
        officeName: '${company['name'] ?? ''}',
        address: header.address.isEmpty ? '${company['address'] ?? ''}' : header.address,
        description: header.description,
        phone: header.phone.isEmpty ? '${company['phone'] ?? ''}' : header.phone,
        phone2: header.phone2,
        phoneLabel: header.phoneLabel,
        phone2Label: header.phone2Label,
        logoUrl: header.logoUrl,
        position: header.position,
        extraLines: header.extraLines,
        watermark: header.watermark,
      );
    }
  } catch (_) {
    header = const DocumentHeader();
    sections = _localPrintSections(document);
  }

  if (sections.isEmpty) {
    sections = _localPrintSections(document);
  }

  if (!context.mounted) return;

  return showDialog<void>(
    context: context,
    builder: (context) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: const Color(0xFFE8E8ED),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'وصل الطباعة · ${document.kind}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('إغلاق'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => openPrintWindow(_html(document, header, sections)),
                        icon: const Icon(Icons.print_outlined, size: 16),
                        label: const Text('طباعة'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Center(
                      child: _Paper(
                        document: document,
                        header: header,
                        sections: sections,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Paper extends StatelessWidget {
  final PrintDocument document;
  final DocumentHeader header;
  final List<String> sections;

  const _Paper({
    required this.document,
    required this.header,
    required this.sections,
  });

  bool get _all => sections.isEmpty;

  bool _on(String id) => _all || sections.contains(id);

  @override
  Widget build(BuildContext context) {
    const footerIds = {
      'totals',
      'words',
      'discount',
      'hamala',
      'cartons',
      'dinar',
      'dollar',
      'payment',
      'amount',
      'balance',
    };
    final order = sections.isEmpty
        ? const [
            'company',
            'meta',
            'customer',
            'items',
            'totals',
            'notes',
            'signature',
            'extra',
          ]
        : sections;
    final children = <Widget>[];
    var footerDrawn = false;
    for (final id in order) {
      if (footerIds.contains(id)) {
        if (!footerDrawn) {
          children.add(_footer());
          footerDrawn = true;
        }
        continue;
      }
      final section = _section(id);
      if (section != null) {
        children.add(section);
      }
    }

    return Container(
      width: 680,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 1.4),
      ),
      child: Stack(
        children: [
          if (header.watermark && header.logoUrl.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: 0.08,
                    child: _logoImage(header.logoUrl, size: 280),
                  ),
                ),
              ),
            ),
          SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...children,
                if (document.totals.isNotEmpty) _moneyLines(document.totals),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _section(String id) {
    switch (id) {
      case 'company':
        return _CompanyBlock(header: header);
      case 'meta':
        return _meta();
      case 'customer':
        return document.party.trim().isEmpty ? null : _customer();
      case 'items':
        return document.columns.isEmpty ? null : _items();
      case 'notes':
        return document.lines.isEmpty ? null : _MetaLines(lines: document.lines);
      case 'signature':
        return const Padding(
          padding: EdgeInsets.only(top: 18),
          child: Text('التوقيع'),
        );
      case 'extra':
        return header.extraLines.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in header.extraLines)
                      Text(line, textAlign: TextAlign.center),
                  ],
                ),
              );
      case 'method':
        return document.documentType.trim().isEmpty
            ? null
            : Text('${document.documentTypeLabel}: ${_arabic(document.documentType)}');
      default:
        return null;
    }
  }

  Widget _meta() {
    final number = document.number.trim().isNotEmpty
        ? document.number.trim()
        : document.title.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(child: Text('رقم $number', textAlign: TextAlign.start)),
          Expanded(
            child: Text(
              _arabic(document.documentType),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('التاريخ: ${document.printedDate}'),
                Text('الوقت: ${document.printedTime}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _customer() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(border: Border.all(color: Colors.black)),
      child: Text(
        document.partyLabel.trim() == 'كشف'
            ? 'كشف ${document.party.trim()}'
            : 'حضرة السيد : ${document.party.trim()} المحترم',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _items() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Table(
        border: TableBorder.all(color: Colors.black),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              for (final column in document.columns)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    _arabic(column),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          for (final row in document.rows)
            TableRow(
              children: [
                for (final cell in row)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      _arabic(cell),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                for (var index = row.length; index < document.columns.length; index++)
                  const SizedBox.shrink(),
              ],
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    final total = document.grandTotal > 0
        ? document.grandTotal
        : _totalFromLines(document.totals);
    final cells = <TableRow>[];
    if (_on('discount') || _on('hamala') || _on('cartons') || _on('amount')) {
      cells.add(_gridRow([
        _on('discount') ? _pair('الخصم', moneyText(document.discount)) : const SizedBox.shrink(),
        _on('hamala') ? _pair('الحمالية', moneyText(document.porterage)) : const SizedBox.shrink(),
        _on('cartons') ? _pair('عدد الكارتون', moneyText(document.cartonCount)) : const SizedBox.shrink(),
      ]));
    }
    if (_on('dinar') || _on('payment') || _on('balance') || _on('totals')) {
      cells.add(_gridRow([
        _pair(document.previousIqdLabel, moneyText(document.previousIqd)),
        _pair(document.paidIqdLabel, moneyText(document.paidIqd)),
        _pair(document.remainingIqdLabel, moneyText(document.remainingIqd)),
      ]));
    }
    if (_on('dollar') || _on('payment') || _on('balance')) {
      cells.add(_gridRow([
        _pair('الرصيد السابق دولار', moneyText(document.previousUsd)),
        _pair('المبلغ المسدد دولار', moneyText(document.paidUsd)),
        _pair('الرصيد النهائي دولار', moneyText(document.remainingUsd)),
      ]));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_on('totals'))
            Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.black)),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        moneyText(total),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 32, color: Colors.black),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('مجموع القائمة', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          if (_on('words'))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                arabicMoneyWords(total),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          if (cells.isNotEmpty)
            Table(
              border: TableBorder.all(color: Colors.black),
              children: [
                for (final row in cells) row,
              ],
            ),
        ],
      ),
    );
  }

  TableRow _gridRow(List<Widget> children) {
    return TableRow(
      children: [
        for (final child in children)
          Padding(padding: const EdgeInsets.all(6), child: child),
      ],
    );
  }

  Widget _moneyLines(List<String> lines) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines)
            Text(
              line,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }

  Widget _pair(String label, String value) {
    return Row(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

class _IdentityStrip extends StatelessWidget {
  final PrintDocument document;

  const _IdentityStrip({required this.document});

  @override
  Widget build(BuildContext context) {
    final cells = <(String, String)>[
      if (document.party.trim().isNotEmpty)
        (document.partyLabel.trim().isEmpty ? 'الزبون' : document.partyLabel, document.party.trim()),
      if (document.printedDate.trim().isNotEmpty) ('التاريخ', document.printedDate.trim()),
      if (document.printedTime.trim().isNotEmpty) ('الوقت', document.printedTime.trim()),
      if (document.documentType.trim().isNotEmpty)
        (
          document.documentTypeLabel.trim().isEmpty
              ? 'نوع القائمة'
              : document.documentTypeLabel,
          document.documentType.trim(),
        ),
    ];

    return Row(
      children: [
        for (var index = 0; index < cells.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(child: _FactCell(label: cells[index].$1, value: cells[index].$2)),
        ],
      ],
    );
  }
}

class _FactCell extends StatelessWidget {
  final String label;
  final String value;

  const _FactCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F9),
        border: Border.all(color: AppTheme.borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.secondaryTextColor),
          ),
          const SizedBox(height: 3),
          Text(
            _arabic(value),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MetaLines extends StatelessWidget {
  final List<String> lines;

  const _MetaLines({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.subtleBorderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: _LabeledLine(line: line),
            ),
        ],
      ),
    );
  }
}

class _LabeledLine extends StatelessWidget {
  final String line;

  const _LabeledLine({required this.line});

  @override
  Widget build(BuildContext context) {
    final text = _arabic(line);
    final split = text.indexOf(':');
    if (split <= 0) {
      return Align(
        alignment: Alignment.centerRight,
        child: Text(text, style: const TextStyle(fontSize: 13)),
      );
    }
    return Row(
      children: [
        Text(
          text.substring(0, split).trim(),
          style: const TextStyle(fontSize: 12, color: AppTheme.secondaryTextColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text.substring(split + 1).trim(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _TotalsBox extends StatelessWidget {
  final List<String> totals;

  const _TotalsBox({required this.totals});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            for (var index = 0; index < totals.length; index++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: index == totals.length - 1
                      ? null
                      : const Border(bottom: BorderSide(color: AppTheme.subtleBorderColor)),
                ),
                child: _LabeledLine(line: totals[index]),
              ),
          ],
        ),
      ),
    );
  }
}

Widget _logoImage(String url, {double size = 64}) {
  if (url.startsWith('data:')) {
    final comma = url.indexOf(',');
    if (comma > 0) {
      try {
        return Image.memory(
          base64Decode(url.substring(comma + 1)),
          width: size,
          height: size,
          fit: BoxFit.contain,
        );
      } catch (_) {}
    }
  }
  return Image.network(
    url,
    width: size,
    height: size,
    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
  );
}

double _totalFromLines(List<String> totals) {
  for (final line in totals) {
    if (line.contains('الكلي') || line.contains('المجموع')) {
      final digits = line.replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(digits) ?? 0;
    }
  }
  return 0;
}

String arabicMoneyWords(num value) {
  final amount = value.round().abs();
  if (amount == 0) {
    return 'صفر دينار فقط';
  }
  return '${_arabicAmount(amount)} دينار فقط';
}

String _arabicAmount(int value) {
  if (value == 0) {
    return 'صفر';
  }
  if (value < 0) {
    return 'سالب ${_arabicAmount(-value)}';
  }
  const ones = [
    '',
    'واحد',
    'اثنان',
    'ثلاثة',
    'أربعة',
    'خمسة',
    'ستة',
    'سبعة',
    'ثمانية',
    'تسعة',
    'عشرة',
    'أحد عشر',
    'اثنا عشر',
    'ثلاثة عشر',
    'أربعة عشر',
    'خمسة عشر',
    'ستة عشر',
    'سبعة عشر',
    'ثمانية عشر',
    'تسعة عشر',
  ];
  const tens = [
    '',
    '',
    'عشرون',
    'ثلاثون',
    'أربعون',
    'خمسون',
    'ستون',
    'سبعون',
    'ثمانون',
    'تسعون',
  ];
  String belowHundred(int number) {
    if (number < 20) {
      return ones[number];
    }
    final ten = number ~/ 10;
    final one = number % 10;
    if (one == 0) {
      return tens[ten];
    }
    return '${ones[one]} و${tens[ten]}';
  }

  String belowThousand(int number) {
    final hundred = number ~/ 100;
    final rest = number % 100;
    const hundreds = [
      '',
      'مئة',
      'مئتان',
      'ثلاثمئة',
      'أربعمئة',
      'خمسمئة',
      'ستمئة',
      'سبعمئة',
      'ثمانمئة',
      'تسعمئة',
    ];
    if (hundred == 0) {
      return belowHundred(rest);
    }
    if (rest == 0) {
      return hundreds[hundred];
    }
    return '${hundreds[hundred]} و${belowHundred(rest)}';
  }

  String scale(int number, String single, String dual, String plural) {
    if (number == 0) {
      return '';
    }
    if (number == 1) {
      return single;
    }
    if (number == 2) {
      return dual;
    }
    if (number < 11) {
      return '${belowThousand(number)} $plural';
    }
    return '${belowThousand(number)} $single';
  }

  final millions = value ~/ 1000000;
  final thousands = (value % 1000000) ~/ 1000;
  final rest = value % 1000;
  final parts = <String>[
    if (millions > 0) scale(millions, 'مليون', 'مليونان', 'ملايين'),
    if (thousands > 0) scale(thousands, 'ألف', 'ألفان', 'آلاف'),
    if (rest > 0) belowThousand(rest),
  ];
  return parts.join(' و');
}

String _escape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

class _CompanyBlock extends StatelessWidget {
  final DocumentHeader header;

  const _CompanyBlock({required this.header});

  @override
  Widget build(BuildContext context) {
    final phones = [
      if (header.phone.trim().isNotEmpty)
        '${header.phoneLabel.trim().isEmpty ? '' : '${header.phoneLabel.trim()} : '}${header.phone.trim()}',
      if (header.phone2.trim().isNotEmpty)
        '${header.phone2Label.trim().isEmpty ? '' : '${header.phone2Label.trim()} : '}${header.phone2.trim()}',
    ].where((line) => line.trim().isNotEmpty).join(' - ');
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (header.officeName.trim().isNotEmpty)
          Text(
            header.officeName.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
        if (header.address.trim().isNotEmpty)
          Text(header.address.trim(), textAlign: TextAlign.center),
        if (header.description.trim().isNotEmpty)
          Text(header.description.trim(), textAlign: TextAlign.center),
        if (phones.isNotEmpty) Text(phones, textAlign: TextAlign.center),
      ],
    );
    if (header.officeName.trim().isEmpty &&
        header.address.trim().isEmpty &&
        phones.isEmpty) {
      return const SizedBox.shrink();
    }
    final smallLogo = header.logoUrl.isEmpty || header.watermark
        ? const SizedBox.shrink()
        : _logoImage(header.logoUrl);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1.4),
      ),
      child: header.position == 'left'
          ? Row(children: [Expanded(child: text), smallLogo])
          : header.position == 'right'
              ? Row(children: [smallLogo, const SizedBox(width: 8), Expanded(child: text)])
              : text,
    );
  }
}

const _arabicWords = {
  'CASH': 'نقداً',
  'CREDIT': 'آجل',
  'PARTIAL': 'جزئي',
  'SALE': 'بيع',
  'PURCHASE': 'شراء',
  'RECEIPT': 'قبض',
  'PAYMENT': 'صرف',
  'PAID': 'مدفوعة',
  'PENDING': 'بانتظار',
  'ACTIVE': 'فعال',
  'INACTIVE': 'متوقف',
  'IQD': 'دينار',
  'USD': 'دولار',
  'TRUE': 'نعم',
  'FALSE': 'لا',
  'YES': 'نعم',
  'NO': 'لا',
};

String _arabic(String value) {
  final trimmed = value.trim();
  final labeled = reportColumnLabel(trimmed);
  if (labeled != trimmed) return labeled;
  final direct = _arabicWords[trimmed.toUpperCase()];
  if (direct != null) return direct;
  var next = value;
  for (final entry in _arabicWords.entries) {
    next = next.replaceAll(RegExp('\\b${entry.key}\\b', caseSensitive: false), entry.value);
  }
  return next;
}

String _phoneLine(DocumentHeader header) {
  final phones = [
    if (header.phone.trim().isNotEmpty)
      '${header.phoneLabel.trim().isEmpty ? '' : '${header.phoneLabel.trim()} : '}${header.phone.trim()}',
    if (header.phone2.trim().isNotEmpty)
      '${header.phone2Label.trim().isEmpty ? '' : '${header.phone2Label.trim()} : '}${header.phone2.trim()}',
  ];
  return phones.where((line) => line.trim().isNotEmpty).join(' - ');
}

String _companyHtml(DocumentHeader header) {
  final phones = _phoneLine(header);
  if (header.officeName.trim().isEmpty &&
      header.address.trim().isEmpty &&
      phones.isEmpty) {
    return '';
  }
  return '''
<div class="company">
  <div class="office">${_escape(header.officeName.trim())}</div>
  <div>${_escape(header.address.trim())}</div>
  <div>${_escape(header.description.trim())}</div>
  <div>${_escape(phones)}</div>
</div>
''';
}

String _pairHtml(String line) {
  final text = _arabic(line);
  final split = text.indexOf(':');
  if (split <= 0) {
    return '<div class="pair"><span></span><b>${_escape(text)}</b></div>';
  }
  return '<div class="pair"><span>${_escape(text.substring(0, split).trim())}</span><b>${_escape(text.substring(split + 1).trim())}</b></div>';
}

String _identityHtml(PrintDocument document) {
  if (!document.hasIdentity) return '';
  final cells = <String>[
    if (document.party.trim().isNotEmpty)
      '<div class="fact"><span>${_escape(document.partyLabel.trim().isEmpty ? 'الزبون' : document.partyLabel)}</span><strong>${_escape(_arabic(document.party.trim()))}</strong></div>',
    if (document.printedDate.trim().isNotEmpty)
      '<div class="fact"><span>التاريخ</span><strong>${_escape(document.printedDate.trim())}</strong></div>',
    if (document.printedTime.trim().isNotEmpty)
      '<div class="fact"><span>الوقت</span><strong>${_escape(document.printedTime.trim())}</strong></div>',
    if (document.documentType.trim().isNotEmpty)
      '<div class="fact"><span>${_escape(document.documentTypeLabel.trim().isEmpty ? 'نوع القائمة' : document.documentTypeLabel)}</span><strong>${_escape(_arabic(document.documentType.trim()))}</strong></div>',
  ];
  return '<div class="facts">${cells.join()}</div>';
}

List<String> _localPrintSections(PrintDocument document) {
  final receipt = document.kind.contains('وصل') || document.kind.contains('سند');
  final blocks = receipt ? DocumentLayouts.receiptDefaults : DocumentLayouts.invoiceDefaults;
  return [
    for (final block in blocks) block.id,
  ];
}

String _html(PrintDocument document, DocumentHeader header, List<String> sections) {
  bool on(String id) => sections.isEmpty || sections.contains(id);
  final head = document.columns
      .map((column) => '<th>${_escape(_arabic(column))}</th>')
      .join();
  final body = document.rows
      .map(
        (row) =>
            '<tr>${row.map((cell) => '<td>${_escape(_arabic(cell))}</td>').join()}</tr>',
      )
      .join();
  final total = document.grandTotal > 0
      ? document.grandTotal
      : _totalFromLines(document.totals);
  final number = document.number.trim().isNotEmpty
      ? document.number.trim()
      : document.title.trim();
  final watermark = header.watermark && header.logoUrl.isNotEmpty
      ? '<img class="watermark" src="${header.logoUrl.replaceAll('"', '')}" alt="">'
      : '';
  final notes = document.lines.map((line) => '<div>${_escape(_arabic(line))}</div>').join();
  final extras = header.extraLines.map((line) => '<div>${_escape(line)}</div>').join();

  return '''
<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<title>${_escape(_arabic(document.title))}</title>
<style>
  body { font-family: Tahoma, "Segoe UI", sans-serif; margin: 18px; color: #111; direction: rtl; }
  .sheet { position: relative; border: 1.5px solid #111; padding: 12px; min-height: 520px; }
  .watermark { position: absolute; left: 50%; top: 42%; width: 280px; height: 280px; object-fit: contain; opacity: 0.08; transform: translate(-50%, -50%); }
  .company { border: 1.5px solid #111; text-align: center; padding: 8px; margin-bottom: 8px; }
  .office { font-size: 26px; font-weight: 800; }
  .meta, .party, table, .sum { width: 100%; border-collapse: collapse; }
  .meta td, table th, table td, .sum td, .grid td { border: 1px solid #111; padding: 4px; text-align: center; }
  .party { margin-top: 8px; }
  table { margin-top: 8px; }
  .words { text-align: center; font-weight: 700; margin: 6px 0; }
  .sign { margin-top: 16px; }
  .print-btn { margin-bottom: 12px; }
  @media print { .print-btn { display: none; } }
</style>
</head>
<body>
<button class="print-btn" onclick="window.print()">طباعة</button>
<div class="sheet">
  $watermark
  ${on('company') ? _companyHtml(header) : ''}
  ${on('meta') ? '<table class="meta"><tr><td>رقم ${_escape(number)}</td><td>${_escape(_arabic(document.documentType))}</td><td>التاريخ: ${_escape(document.printedDate)}<br>الوقت: ${_escape(document.printedTime)}</td></tr></table>' : ''}
  ${on('customer') && document.party.trim().isNotEmpty ? '<table class="party"><tr><td>${document.partyLabel.trim() == 'كشف' ? 'كشف ${_escape(document.party.trim())}' : 'حضرة السيد : ${_escape(document.party.trim())} المحترم'}</td></tr></table>' : ''}
  ${on('items') && document.columns.isNotEmpty ? '<table><thead><tr>$head</tr></thead><tbody>$body</tbody></table>' : ''}
  ${on('totals') ? '<table class="sum"><tr><td>${moneyText(total)}</td><td>مجموع القائمة</td></tr></table>' : ''}
  ${on('words') ? '<div class="words">${_escape(arabicMoneyWords(total))}</div>' : ''}
  <table class="grid">
    <tr>
      <td>الخصم ${moneyText(document.discount)}</td>
      <td>الحمالية ${moneyText(document.porterage)}</td>
      <td>عدد الكارتون ${moneyText(document.cartonCount)}</td>
    </tr>
    <tr>
      <td>${_escape(document.previousIqdLabel)} ${moneyText(document.previousIqd)}</td>
      <td>${_escape(document.paidIqdLabel)} ${moneyText(document.paidIqd)}</td>
      <td>${_escape(document.remainingIqdLabel)} ${moneyText(document.remainingIqd)}</td>
    </tr>
    <tr>
      <td>الرصيد السابق دولار ${moneyText(document.previousUsd)}</td>
      <td>المبلغ المسدد دولار ${moneyText(document.paidUsd)}</td>
      <td>الرصيد النهائي دولار ${moneyText(document.remainingUsd)}</td>
    </tr>
  </table>
  ${on('notes') && notes.isNotEmpty ? '<div class="words">$notes</div>' : ''}
  ${document.totals.map((line) => '<div class="words">${_escape(_arabic(line))}</div>').join()}
  ${on('extra') && extras.isNotEmpty ? '<div class="words">$extras</div>' : ''}
  ${on('signature') ? '<div class="sign">التوقيع</div>' : ''}
</div>
<script>window.addEventListener('load', function () { window.print(); });</script>
</body>
</html>
''';
}
