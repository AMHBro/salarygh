class LayoutBlock {
  final String id;
  final String title;
  final bool visible;

  const LayoutBlock({
    required this.id,
    required this.title,
    this.visible = true,
  });

  LayoutBlock copyWith({
    bool? visible,
  }) {
    return LayoutBlock(
      id: id,
      title: title,
      visible: visible ?? this.visible,
    );
  }
}

class DocumentLayouts {
  static const invoiceDefaults = <LayoutBlock>[
    LayoutBlock(id: 'company', title: 'رأس الشركة'),
    LayoutBlock(id: 'meta', title: 'رقم القائمة والتاريخ'),
    LayoutBlock(id: 'customer', title: 'الزبون'),
    LayoutBlock(id: 'items', title: 'جدول المواد'),
    LayoutBlock(id: 'totals', title: 'مجموع القائمة'),
    LayoutBlock(id: 'words', title: 'المبلغ كتابة'),
    LayoutBlock(id: 'discount', title: 'الخصم'),
    LayoutBlock(id: 'hamala', title: 'الحمالية'),
    LayoutBlock(id: 'cartons', title: 'عدد الكارتون'),
    LayoutBlock(id: 'dinar', title: 'رصيد الدينار'),
    LayoutBlock(id: 'dollar', title: 'رصيد الدولار'),
    LayoutBlock(id: 'notes', title: 'الملاحظات'),
    LayoutBlock(id: 'signature', title: 'التوقيع'),
    LayoutBlock(id: 'extra', title: 'سطور إضافية'),
  ];

  static const receiptDefaults = <LayoutBlock>[
    LayoutBlock(id: 'company', title: 'رأس الشركة'),
    LayoutBlock(id: 'meta', title: 'رقم الوصل والتاريخ'),
    LayoutBlock(id: 'customer', title: 'الزبون'),
    LayoutBlock(id: 'amount', title: 'المبلغ'),
    LayoutBlock(id: 'method', title: 'طريقة الدفع'),
    LayoutBlock(id: 'dinar', title: 'رصيد الدينار'),
    LayoutBlock(id: 'dollar', title: 'رصيد الدولار'),
    LayoutBlock(id: 'notes', title: 'الملاحظات'),
    LayoutBlock(id: 'signature', title: 'التوقيع'),
    LayoutBlock(id: 'extra', title: 'سطور إضافية'),
  ];

  static List<LayoutBlock> invoiceFrom(Object? settings) {
    return _read(settings, 'invoice', invoiceDefaults);
  }

  static List<LayoutBlock> receiptFrom(Object? settings) {
    return _read(settings, 'receipt', receiptDefaults);
  }

  static Map<String, dynamic> toSettings({
    required List<LayoutBlock> invoice,
    required List<LayoutBlock> receipt,
    DocumentHeader header = const DocumentHeader(),
  }) {
    return {
      'invoice': _encode(invoice),
      'receipt': _encode(receipt),
      'header': header.toJson(),
    };
  }

  static DocumentHeader headerFrom(Object? settings) {
    if (settings is! Map) {
      return const DocumentHeader();
    }

    final layouts = settings['document_layouts'];
    if (layouts is! Map) {
      return const DocumentHeader();
    }

    return DocumentHeader.fromJson(layouts['header']);
  }

  static List<LayoutBlock> _read(
    Object? settings,
    String key,
    List<LayoutBlock> defaults,
  ) {
    if (settings is! Map) {
      return List<LayoutBlock>.from(defaults);
    }

    final layouts = settings['document_layouts'];
    if (layouts is! Map) {
      return List<LayoutBlock>.from(defaults);
    }

    final stored = layouts[key];
    if (stored is! List) {
      return List<LayoutBlock>.from(defaults);
    }

    final catalog = {for (final block in defaults) block.id: block};
    final result = <LayoutBlock>[];

    for (final item in stored) {
      if (item is! Map) {
        continue;
      }

      final id = item['id']?.toString();
      final block = id == null ? null : catalog.remove(id);
      if (block == null) {
        continue;
      }

      result.add(
        block.copyWith(visible: item['visible'] != false),
      );
    }

    result.addAll(catalog.values);
    return result;
  }

  static List<Map<String, dynamic>> _encode(List<LayoutBlock> blocks) {
    return [
      for (final block in blocks)
        {
          'id': block.id,
          'visible': block.visible,
        },
    ];
  }
}

class DocumentHeader {
  final String officeName;
  final String address;
  final String description;
  final String phone;
  final String phone2;
  final String phoneLabel;
  final String phone2Label;
  final String logoUrl;
  final String position;
  final List<String> extraLines;
  final bool watermark;

  const DocumentHeader({
    this.officeName = '',
    this.address = '',
    this.description = '',
    this.phone = '',
    this.phone2 = '',
    this.phoneLabel = '',
    this.phone2Label = '',
    this.logoUrl = '',
    this.position = 'top',
    this.extraLines = const [],
    this.watermark = true,
  });

  factory DocumentHeader.fromJson(Object? json) {
    if (json is! Map) {
      return const DocumentHeader();
    }

    String read(String key) => json[key]?.toString() ?? '';

    final rawLines = json['extra_lines'];
    final lines = rawLines is List
        ? [
            for (final line in rawLines)
              if ('$line'.trim().isNotEmpty) '$line'.trim(),
          ]
        : read('extra_lines')
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();

    return DocumentHeader(
      officeName: read('office_name'),
      address: read('address'),
      description: read('description'),
      phone: read('phone'),
      phone2: read('phone2'),
      phoneLabel: read('phone_label'),
      phone2Label: read('phone2_label'),
      logoUrl: read('logo_url'),
      position: read('position').isEmpty ? 'top' : read('position'),
      extraLines: lines,
      watermark: json['watermark'] != false && read('watermark') != '0',
    );
  }

  Map<String, String> toJson() {
    return {
      'office_name': officeName,
      'address': address,
      'description': description,
      'phone': phone,
      'phone2': phone2,
      'phone_label': phoneLabel,
      'phone2_label': phone2Label,
      'logo_url': logoUrl,
      'position': position,
      'extra_lines': extraLines.join('\n'),
      'watermark': watermark ? '1' : '0',
    };
  }
}
