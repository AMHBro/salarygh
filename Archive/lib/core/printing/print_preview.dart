import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../../features/reports/models/report_catalog.dart';
import '../../features/settings/data/company_settings_repository.dart';
import '../../features/settings/models/document_layout.dart';
import '../../features/settings/data/print_settings_store.dart';
import '../../features/settings/models/print_settings.dart';
import '../../features/settings/models/public_links.dart';
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
  final String phone;
  final String representative;
  final String driver;
  final List<String> itemCodes;
  final bool accountStatement;
  final double debitTotal;
  final double creditTotal;
  final String lastPaymentDate;
  final double lastPaymentAmount;

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
    this.phone = '',
    this.representative = '',
    this.driver = '',
    this.itemCodes = const [],
    this.accountStatement = false,
    this.debitTotal = 0,
    this.creditTotal = 0,
    this.lastPaymentDate = '',
    this.lastPaymentAmount = 0,
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
  var printSettings = const PrintSettings();
  var storeUrl = PublicLinks.shop;
  try {
    printSettings = await PrintSettingsStore(AppServices.database).read();
  } catch (_) {
    printSettings = const PrintSettings();
  }
  try {
    final company = await CompanySettingsRepository(
      apiClient: AppServices.apiClient,
    ).getCompany();
    final settings = company['settings'];
    header = DocumentLayouts.headerFrom(settings);
    storeUrl = PublicLinks.fromSettings(settings).shopUrl;
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

  final logo = printSettings.logoData.trim().isNotEmpty
      ? printSettings.logoData.trim()
      : header.logoUrl;
  header = DocumentHeader(
    officeName: header.officeName,
    address: header.address,
    description: header.description,
    phone: header.phone,
    phone2: header.phone2,
    phoneLabel: header.phoneLabel,
    phone2Label: header.phone2Label,
    logoUrl: logo,
    position: printSettings.logoPosition,
    extraLines: header.extraLines,
    watermark: header.watermark,
  );

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
                        onPressed: () => openPrintWindow(
                          _html(document, header, sections, printSettings, storeUrl),
                        ),
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
                        settings: printSettings,
                        storeUrl: storeUrl,
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

class PrintSheetView extends StatelessWidget {
  final PrintDocument document;
  final PrintSettings settings;
  final DocumentHeader header;
  final String storeUrl;
  final void Function(String id, double dx, double dy)? onFieldMoved;

  const PrintSheetView({
    super.key,
    required this.document,
    required this.settings,
    this.header = const DocumentHeader(),
    this.storeUrl = PublicLinks.shop,
    this.onFieldMoved,
  });

  @override
  Widget build(BuildContext context) {
    final logo = settings.logoData.trim().isNotEmpty
        ? settings.logoData.trim()
        : header.logoUrl;
    final chrome = DocumentHeader(
      officeName: header.officeName,
      address: header.address,
      description: header.description,
      phone: header.phone,
      phone2: header.phone2,
      phoneLabel: header.phoneLabel,
      phone2Label: header.phone2Label,
      logoUrl: logo,
      position: settings.logoPosition,
      extraLines: header.extraLines,
      watermark: false,
    );
    final receipt = document.kind.contains('وصل') || document.kind.contains('سند');
    final blocks = receipt
        ? DocumentLayouts.receiptDefaults
        : DocumentLayouts.invoiceDefaults;
    return _Paper(
      document: document,
      header: chrome,
      sections: [for (final block in blocks) block.id],
      settings: settings,
      storeUrl: storeUrl,
      onFieldMoved: onFieldMoved,
    );
  }
}

class _Paper extends StatelessWidget {
  final PrintDocument document;
  final DocumentHeader header;
  final List<String> sections;
  final PrintSettings settings;
  final String storeUrl;
  final void Function(String id, double dx, double dy)? onFieldMoved;

  const _Paper({
    required this.document,
    required this.header,
    required this.sections,
    required this.settings,
    this.storeUrl = PublicLinks.shop,
    this.onFieldMoved,
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
          if (_watermarkUrl.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: settings.watermarkOpacity.clamp(0.05, 0.30),
                    child: _logoImage(
                      _watermarkUrl,
                      size: settings.watermarkWidth,
                      height: settings.watermarkHeight,
                    ),
                  ),
                ),
              ),
            ),
          SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (settings.headerText.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      settings.headerText.trim(),
                      textAlign: _textAlign(settings.headerAlign),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: settings.headerFontSize,
                      ),
                    ),
                  ),
                ..._customFields('header'),
                ...children,
                if (_saleInvoice) _logistics(),
                ..._customFields('footer'),
                if (settings.footerText.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      settings.footerText.trim(),
                      textAlign: _textAlign(settings.footerAlign),
                      style: TextStyle(fontSize: settings.footerFontSize),
                    ),
                  ),
                if (settings.showQr) _qrMark(),
                if (_extraMoneyLines().isNotEmpty) _moneyLines(_extraMoneyLines()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _watermarkUrl => settings.watermarkSource(header.logoUrl);

  TextAlign _textAlign(String align) {
    switch (align) {
      case 'right':
        return TextAlign.right;
      case 'left':
        return TextAlign.left;
      default:
        return TextAlign.center;
    }
  }

  Alignment _boxAlign(String align) {
    switch (align) {
      case 'right':
        return Alignment.centerRight;
      case 'left':
        return Alignment.centerLeft;
      default:
        return Alignment.center;
    }
  }

  List<Widget> _customFields(String zone) {
    return [
      for (final field in settings.customFields)
        if (field.zone == zone &&
            (field.label.trim().isNotEmpty || field.value.trim().isNotEmpty))
          Align(
            alignment: _boxAlign(field.align),
            child: GestureDetector(
              onPanUpdate: onFieldMoved == null
                  ? null
                  : (details) {
                      onFieldMoved!(
                        field.id,
                        field.dx + details.delta.dx,
                        field.dy + details.delta.dy,
                      );
                    },
              child: Transform.translate(
                offset: Offset(field.dx, field.dy),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    field.label.trim().isEmpty
                        ? field.value.trim()
                        : '${field.label.trim()}: ${field.value.trim()}',
                    textAlign: _textAlign(field.align),
                    style: TextStyle(fontSize: field.fontSize),
                  ),
                ),
              ),
            ),
          ),
    ];
  }

  Widget? _section(String id) {
    switch (id) {
      case 'company':
        return _CompanyBlock(header: header, logoSize: settings.logoSize);
      case 'meta':
        return _meta();
      case 'customer':
        if (!settings.showCustomer || document.party.trim().isEmpty) {
          return null;
        }
        return _customer();
      case 'items':
        return _items();
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

  bool get _saleInvoice {
    final kind = document.kind;
    if (kind.contains('شراء') || kind.contains('كشف') || kind.contains('سند') || kind.contains('وصل')) {
      return false;
    }
    return kind.contains('بيع') || kind.contains('قائمة');
  }

  Widget _meta() {
    final number = document.number.trim().isNotEmpty
        ? document.number.trim()
        : document.title.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (settings.showNumber)
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
                if (settings.showDate) Text('التاريخ: ${document.printedDate}'),
                if (settings.showTime) Text('الوقت: ${document.printedTime}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _customer() {
    final phone = document.phone.trim();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(border: Border.all(color: Colors.black)),
      child: Column(
        children: [
          Text(
            document.partyLabel.trim() == 'كشف'
                ? 'كشف ${document.party.trim()}'
                : 'حضرة السيد : ${document.party.trim()} المحترم',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (settings.showPhone && phone.isNotEmpty)
            Text('الهاتف: $phone', textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget? _items() {
    final columns = _visibleColumns();
    final rows = _visibleRows();
    if (columns.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Table(
        border: TableBorder.all(color: Colors.black),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              for (final column in columns)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    _arabic(column),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: settings.tableFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          for (final row in rows)
            TableRow(
              children: [
                for (final cell in row)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      _arabic(cell),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: settings.tableFontSize),
                    ),
                  ),
                for (var index = row.length; index < columns.length; index++)
                  const SizedBox.shrink(),
              ],
            ),
        ],
      ),
    );
  }

  List<String> _extraMoneyLines() {
    return [
      for (final line in document.totals)
        if (!_repeatsFinancialFooter(line)) line,
    ];
  }

  bool _keepColumn(String name) {
    if (!settings.showItemCode &&
        (name.contains('رمز') || name.contains('كود') || name.toUpperCase() == 'SKU')) {
      return false;
    }
    if (!settings.showUnitPrice && name.contains('سعر')) return false;
    if (!settings.showLineDiscount && name.contains('خصم')) return false;
    if (!settings.showLineTotal && (name == 'المبلغ' || name.contains('إجمالي'))) {
      return false;
    }
    if (!settings.showCartons && _saleInvoice && name.contains('كارتون')) return false;
    return true;
  }

  List<String> _visibleColumns() {
    final columns = <String>[];
    for (final column in document.columns) {
      if (_keepColumn(column)) columns.add(column);
    }
    if (settings.showItemCode &&
        document.itemCodes.isNotEmpty &&
        !columns.any((column) => column.contains('رمز'))) {
      final insertAt = columns.isEmpty ? 0 : 1;
      columns.insert(insertAt, 'رمز المادة');
    }
    return columns;
  }

  List<List<String>> _visibleRows() {
    final sourceColumns = document.columns;
    final kept = <int>[
      for (var index = 0; index < sourceColumns.length; index++)
        if (_keepColumn(sourceColumns[index])) index,
    ];
    final addCode = settings.showItemCode &&
        document.itemCodes.length == document.rows.length &&
        document.itemCodes.isNotEmpty &&
        !sourceColumns.any((column) => column.contains('رمز'));
    return [
      for (var rowIndex = 0; rowIndex < document.rows.length; rowIndex++)
        [
          if (addCode && kept.isEmpty) document.itemCodes[rowIndex],
          for (var index = 0; index < kept.length; index++) ...[
            if (addCode && index == 1) document.itemCodes[rowIndex],
            document.rows[rowIndex].length > kept[index]
                ? document.rows[rowIndex][kept[index]]
                : '',
          ],
          if (addCode && kept.length == 1) document.itemCodes[rowIndex],
        ],
    ];
  }

  Widget _logistics() {
    final representative = document.representative.trim();
    final driver = document.driver.trim().isNotEmpty
        ? document.driver.trim()
        : settings.driverName.trim();
    final lines = <String>[
      if (settings.showRepresentative && representative.isNotEmpty)
        'المندوب: $representative',
      if (settings.showDriver && driver.isNotEmpty) 'السائق: $driver',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines)
            Text(line, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _qrMark() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Center(child: _qrImage(storeUrl, 96)),
          const SizedBox(height: 4),
          const Text('المتجر', textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _footer() {
    if (document.accountStatement) {
      return _statementFooter();
    }
    final total = document.grandTotal > 0
        ? document.grandTotal
        : _totalFromLines(document.totals);
    final cells = <TableRow>[];
    if (_on('discount') || _on('hamala') || _on('cartons') || _on('amount')) {
      cells.add(_gridRow([
        settings.showLineDiscount && _on('discount')
            ? _pair('الخصم', moneyText(document.discount))
            : const SizedBox.shrink(),
        _on('hamala') ? _pair('الحمالية', moneyText(document.porterage)) : const SizedBox.shrink(),
        settings.showCartons && _saleInvoice && _on('cartons')
            ? _pair('عدد الكارتون', moneyText(document.cartonCount))
            : const SizedBox.shrink(),
      ]));
    }
    if (_on('dinar') || _on('payment') || _on('balance') || _on('totals')) {
      cells.add(_gridRow([
        settings.showPreviousDebt
            ? _pair(document.previousIqdLabel, moneyText(document.previousIqd))
            : const SizedBox.shrink(),
        settings.showPaid
            ? _pair(document.paidIqdLabel, moneyText(document.paidIqd))
            : const SizedBox.shrink(),
        settings.showFinalNet
            ? _pair(document.remainingIqdLabel, moneyText(document.remainingIqd))
            : const SizedBox.shrink(),
      ]));
    }
    if (_on('dollar') || _on('payment') || _on('balance')) {
      cells.add(_gridRow([
        settings.showPreviousDebt
            ? _pair('الرصيد السابق دولار', moneyText(document.previousUsd))
            : const SizedBox.shrink(),
        settings.showPaid
            ? _pair('المبلغ المسدد دولار', moneyText(document.paidUsd))
            : const SizedBox.shrink(),
        settings.showFinalNet
            ? _pair('الرصيد النهائي دولار', moneyText(document.remainingUsd))
            : const SizedBox.shrink(),
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

  Widget _statementFooter() {
    final balance = document.remainingIqd;
    final lastDate = document.lastPaymentDate.trim().isEmpty
        ? '—'
        : document.lastPaymentDate.trim();
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
                        moneyText(balance),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 32, color: Colors.black),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'صافي الرصيد الحالي',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          if (_on('words'))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                arabicMoneyWords(balance),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          Table(
            border: TableBorder.all(color: Colors.black),
            children: [
              _gridRow([
                _pair('إجمالي المدين', moneyText(document.debitTotal)),
                _pair('إجمالي الدائن', moneyText(document.creditTotal)),
                _pair('الرصيد النهائي المستحق', moneyText(balance)),
              ]),
              _gridRow([
                _pair('تاريخ آخر تسديد', lastDate),
                _pair('المبلغ المسدد', moneyText(document.lastPaymentAmount)),
                const SizedBox.shrink(),
              ]),
            ],
          ),
        ],
      ),
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

Widget _logoImage(String url, {double size = 64, double? height}) {
  final boxHeight = height ?? size;
  if (url.startsWith('data:')) {
    final comma = url.indexOf(',');
    if (comma > 0) {
      try {
        return Image.memory(
          base64Decode(url.substring(comma + 1)),
          width: size,
          height: boxHeight,
          fit: BoxFit.contain,
        );
      } catch (_) {}
    }
  }
  return Image.network(
    url,
    width: size,
    height: boxHeight,
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
  final double logoSize;

  const _CompanyBlock({
    required this.header,
    this.logoSize = 72,
  });

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
    final smallLogo = header.logoUrl.trim().isEmpty
        ? const SizedBox.shrink()
        : _logoImage(header.logoUrl, size: logoSize);
    if (header.officeName.trim().isEmpty &&
        header.address.trim().isEmpty &&
        header.description.trim().isEmpty &&
        phones.isEmpty &&
        header.logoUrl.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final centered = Column(
      children: [
        smallLogo,
        text,
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1.4),
      ),
      child: header.position == 'left'
          ? Row(children: [Expanded(child: text), smallLogo])
          : header.position == 'right'
              ? Row(
                  children: [
                    smallLogo,
                    const SizedBox(width: 8),
                    Expanded(child: text),
                  ],
                )
              : centered,
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

String _companyHtml(DocumentHeader header, PrintSettings settings) {
  final phones = _phoneLine(header);
  final logo = header.logoUrl.trim().isEmpty
      ? ''
      : '<img class="logo" style="width:${settings.logoSize.round()}px;height:${settings.logoSize.round()}px;object-fit:contain" src="${header.logoUrl.replaceAll('"', '')}" alt="">';
  if (header.officeName.trim().isEmpty &&
      header.address.trim().isEmpty &&
      phones.isEmpty &&
      logo.isEmpty) {
    return '';
  }
  final align = header.position == 'left'
      ? 'flex-start'
      : header.position == 'right'
          ? 'flex-end'
          : 'center';
  return '''
<div class="company" style="display:flex;flex-direction:column;align-items:$align">
  $logo
  <div class="office">${_escape(header.officeName.trim())}</div>
  <div>${_escape(header.address.trim())}</div>
  <div>${_escape(header.description.trim())}</div>
  <div>${_escape(phones)}</div>
</div>
''';
}

List<String> _localPrintSections(PrintDocument document) {
  final receipt = document.kind.contains('وصل') || document.kind.contains('سند');
  final blocks = receipt ? DocumentLayouts.receiptDefaults : DocumentLayouts.invoiceDefaults;
  return [
    for (final block in blocks) block.id,
  ];
}

String _html(
  PrintDocument document,
  DocumentHeader header,
  List<String> sections,
  PrintSettings settings,
  String storeUrl,
) {
  bool on(String id) => sections.isEmpty || sections.contains(id);
  final sale = _isSaleInvoice(document);
  final columns = _sheetColumns(document, settings, sale);
  final rows = _sheetRows(document, settings, sale);
  final head = columns.map((column) => '<th>${_escape(_arabic(column))}</th>').join();
  final body = rows
      .map(
        (row) => '<tr>${row.map((cell) => '<td>${_escape(_arabic(cell))}</td>').join()}</tr>',
      )
      .join();
  final statement = document.accountStatement;
  final total = statement
      ? document.remainingIqd
      : document.grandTotal > 0
          ? document.grandTotal
          : _totalFromLines(document.totals);
  final totalCaption = statement ? 'صافي الرصيد الحالي' : 'مجموع القائمة';
  final number = document.number.trim().isNotEmpty
      ? document.number.trim()
      : document.title.trim();
  final mark = settings.watermarkSource(header.logoUrl);
  final watermark = mark.isEmpty
      ? ''
      : '<img class="watermark" style="width:${settings.watermarkWidth.round()}px;height:${settings.watermarkHeight.round()}px;opacity:${settings.watermarkOpacity.clamp(0.05, 0.30)}" src="${mark.replaceAll('"', '')}" alt="">';
  final notes = document.lines.map((line) => '<div>${_escape(_arabic(line))}</div>').join();
  final extras = header.extraLines.map((line) => '<div>${_escape(line)}</div>').join();
  final money = document.totals
      .where((line) => !_repeatsFinancialFooter(line))
      .map((line) => '<div class="words">${_escape(_arabic(line))}</div>')
      .join();
  final representative = document.representative.trim();
  final driver = document.driver.trim().isNotEmpty
      ? document.driver.trim()
      : settings.driverName.trim();
  final logistics = !sale
      ? ''
      : [
          if (settings.showRepresentative && representative.isNotEmpty)
            '<div class="words">المندوب: ${_escape(representative)}</div>',
          if (settings.showDriver && driver.isNotEmpty)
            '<div class="words">السائق: ${_escape(driver)}</div>',
        ].join();
  final phone = settings.showPhone && document.phone.trim().isNotEmpty
      ? '<div>الهاتف: ${_escape(document.phone.trim())}</div>'
      : '';
  final qr = settings.showQr
      ? '<div class="words">${_qrSvg(storeUrl, 96)}<div>المتجر</div></div>'
      : '';
  final headerFields = _customFieldsHtml(settings, 'header');
  final footerFields = _customFieldsHtml(settings, 'footer');
  final discountCell = settings.showLineDiscount && on('discount')
      ? '<td>الخصم ${moneyText(document.discount)}</td>'
      : '<td></td>';
  final cartonCell = settings.showCartons && sale && on('cartons')
      ? '<td>عدد الكارتون ${moneyText(document.cartonCount)}</td>'
      : '<td></td>';
  final previousCell = settings.showPreviousDebt
      ? '<td>${_escape(document.previousIqdLabel)} ${moneyText(document.previousIqd)}</td>'
      : '<td></td>';
  final paidCell = settings.showPaid
      ? '<td>${_escape(document.paidIqdLabel)} ${moneyText(document.paidIqd)}</td>'
      : '<td></td>';
  final finalCell = settings.showFinalNet
      ? '<td>${_escape(document.remainingIqdLabel)} ${moneyText(document.remainingIqd)}</td>'
      : '<td></td>';
  final lastPayment = document.lastPaymentDate.trim().isEmpty
      ? '—'
      : document.lastPaymentDate.trim();
  final grid = statement
      ? '<table class="grid"><tr>'
          '<td>إجمالي المدين ${moneyText(document.debitTotal)}</td>'
          '<td>إجمالي الدائن ${moneyText(document.creditTotal)}</td>'
          '<td>الرصيد النهائي المستحق ${moneyText(total)}</td>'
          '</tr><tr>'
          '<td>تاريخ آخر تسديد ${_escape(lastPayment)}</td>'
          '<td>المبلغ المسدد ${moneyText(document.lastPaymentAmount)}</td>'
          '<td></td></tr></table>'
      : '<table class="grid"><tr>$discountCell'
          '<td>${on('hamala') ? 'الحمالية ${moneyText(document.porterage)}' : ''}</td>'
          '$cartonCell</tr><tr>$previousCell$paidCell$finalCell</tr></table>';

  return '''
<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<title>${_escape(_arabic(document.title))}</title>
<style>
  body { font-family: Tahoma, "Segoe UI", sans-serif; margin: 18px; color: #111; direction: rtl; }
  .sheet { position: relative; border: 1.5px solid #111; padding: 12px; min-height: 520px; background: transparent; }
  .sheet-bg { position: absolute; inset: 0; background: #fff; z-index: -2; }
  .watermark { position: absolute; left: 50%; top: 50%; object-fit: contain; transform: translate(-50%, -50%); z-index: -1; pointer-events: none; }
  .sheet-body { position: relative; z-index: 1; }
  .company { border: 1.5px solid #111; text-align: center; padding: 8px; margin-bottom: 8px; }
  .office { font-size: 26px; font-weight: 800; }
  .meta, .party, table, .sum { width: 100%; border-collapse: collapse; }
  .meta td, table th, table td, .sum td, .grid td { border: 1px solid #111; padding: 4px; text-align: center; }
  .party { margin-top: 8px; }
  table { margin-top: 8px; font-size: ${settings.tableFontSize.round()}px; }
  .words { text-align: center; font-weight: 700; margin: 6px 0; }
  .sign { margin-top: 16px; }
  .print-btn { margin-bottom: 12px; }
  @media print { .print-btn { display: none; } }
</style>
</head>
<body>
<button class="print-btn" onclick="window.print()">طباعة</button>
<div class="sheet">
  <div class="sheet-bg"></div>
  $watermark
  <div class="sheet-body">
  ${settings.headerText.trim().isEmpty ? '' : '<div class="words" style="text-align:${settings.headerAlign};font-size:${settings.headerFontSize}px">${_escape(settings.headerText.trim())}</div>'}
  $headerFields
  ${on('company') ? _companyHtml(header, settings) : ''}
  ${on('meta') ? '<table class="meta"><tr>${settings.showNumber ? '<td>رقم ${_escape(number)}</td>' : '<td></td>'}<td>${_escape(_arabic(document.documentType))}</td><td>${settings.showDate ? 'التاريخ: ${_escape(document.printedDate)}' : ''}<br>${settings.showTime ? 'الوقت: ${_escape(document.printedTime)}' : ''}</td></tr></table>' : ''}
  ${on('customer') && settings.showCustomer && document.party.trim().isNotEmpty ? '<table class="party"><tr><td>${document.partyLabel.trim() == 'كشف' ? 'كشف ${_escape(document.party.trim())}' : 'حضرة السيد : ${_escape(document.party.trim())} المحترم'}$phone</td></tr></table>' : ''}
  ${on('items') && columns.isNotEmpty ? '<table><thead><tr>$head</tr></thead><tbody>$body</tbody></table>' : ''}
  ${on('totals') ? '<table class="sum"><tr><td>${moneyText(total)}</td><td>$totalCaption</td></tr></table>' : ''}
  ${on('words') ? '<div class="words">${_escape(arabicMoneyWords(total))}</div>' : ''}
  $grid
  ${on('notes') && notes.isNotEmpty ? '<div class="words">$notes</div>' : ''}
  $money
  $logistics
  $footerFields
  ${on('extra') && extras.isNotEmpty ? '<div class="words">$extras</div>' : ''}
  ${settings.footerText.trim().isEmpty ? '' : '<div class="words" style="text-align:${settings.footerAlign};font-size:${settings.footerFontSize}px">${_escape(settings.footerText.trim())}</div>'}
  $qr
  ${on('signature') ? '<div class="sign">التوقيع</div>' : ''}
  </div>
</div>
<script>window.addEventListener('load', function () { window.print(); });</script>
</body>
</html>
''';
}

String _customFieldsHtml(PrintSettings settings, String zone) {
  final buffer = StringBuffer();
  for (final field in settings.customFields) {
    if (field.zone != zone) continue;
    final text = field.label.trim().isEmpty
        ? field.value.trim()
        : '${field.label.trim()}: ${field.value.trim()}';
    if (text.isEmpty) continue;
    buffer.write(
      '<div style="text-align:${field.align};font-size:${field.fontSize.round()}px;transform:translate(${field.dx}px,${field.dy}px)">${_escape(text)}</div>',
    );
  }
  return buffer.toString();
}

bool _isSaleInvoice(PrintDocument document) {
  final kind = document.kind;
  if (kind.contains('شراء') ||
      kind.contains('كشف') ||
      kind.contains('سند') ||
      kind.contains('وصل')) {
    return false;
  }
  return kind.contains('بيع') || kind.contains('قائمة');
}

bool _repeatsFinancialFooter(String line) {
  const keys = [
    'إجمالي',
    'مجموع',
    'الكلي',
    'المسدد',
    'المدفوع',
    'متبقي',
    'المتبقي',
    'السابق',
    'النهائي',
    'الحالي',
    'الخصم',
    'المبلغ',
  ];
  return keys.any(line.contains);
}

bool _keepSheetColumn(String name, PrintSettings settings, bool sale) {
  if (!settings.showItemCode &&
      (name.contains('رمز') || name.contains('كود') || name.toUpperCase() == 'SKU')) {
    return false;
  }
  if (!settings.showUnitPrice && name.contains('سعر')) return false;
  if (!settings.showLineDiscount && name.contains('خصم')) return false;
  if (!settings.showLineTotal && (name == 'المبلغ' || name.contains('إجمالي'))) {
    return false;
  }
  if (!settings.showCartons && sale && name.contains('كارتون')) return false;
  return true;
}

List<String> _sheetColumns(PrintDocument document, PrintSettings settings, bool sale) {
  final columns = [
    for (final column in document.columns)
      if (_keepSheetColumn(column, settings, sale)) column,
  ];
  if (settings.showItemCode &&
      document.itemCodes.isNotEmpty &&
      !columns.any((column) => column.contains('رمز'))) {
    columns.insert(columns.isEmpty ? 0 : 1, 'رمز المادة');
  }
  return columns;
}

List<List<String>> _sheetRows(PrintDocument document, PrintSettings settings, bool sale) {
  final kept = <int>[
    for (var index = 0; index < document.columns.length; index++)
      if (_keepSheetColumn(document.columns[index], settings, sale)) index,
  ];
  final addCode = settings.showItemCode &&
      document.itemCodes.length == document.rows.length &&
      document.itemCodes.isNotEmpty &&
      !document.columns.any((column) => column.contains('رمز'));
  return [
    for (var rowIndex = 0; rowIndex < document.rows.length; rowIndex++)
      _withCode(
        [
          for (final index in kept)
            index < document.rows[rowIndex].length ? document.rows[rowIndex][index] : '',
        ],
        addCode ? document.itemCodes[rowIndex] : null,
      ),
  ];
}

List<String> _withCode(List<String> cells, String? code) {
  if (code == null) return cells;
  final next = List<String>.from(cells);
  next.insert(next.isEmpty ? 0 : 1, code);
  return next;
}

String _qrSvg(String payload, double size) {
  final code = QrCode.fromData(
    data: payload,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final image = QrImage(code);
  final count = image.moduleCount;
  final cell = size / count;
  final squares = StringBuffer();
  for (var y = 0; y < count; y++) {
    for (var x = 0; x < count; x++) {
      if (image.isDark(y, x)) {
        squares.write(
          '<rect x="${x * cell}" y="${y * cell}" width="$cell" height="$cell" fill="#111"/>',
        );
      }
    }
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" viewBox="0 0 $size $size">${squares.toString()}</svg>';
}

Widget _qrImage(String payload, double size) {
  final code = QrCode.fromData(
    data: payload,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final image = QrImage(code);
  final count = image.moduleCount;
  return SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _QrPainter(image, count)),
  );
}

class _QrPainter extends CustomPainter {
  final QrImage image;
  final int count;

  _QrPainter(this.image, this.count);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF111111);
    final cell = size.width / count;
    for (var y = 0; y < count; y++) {
      for (var x = 0; x < count; x++) {
        if (image.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell, cell),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => false;
}
