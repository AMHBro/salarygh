class PrintCustomField {
  final String id;
  final String label;
  final String value;
  final String zone;
  final String align;
  final double fontSize;
  final double dx;
  final double dy;

  const PrintCustomField({
    required this.id,
    required this.label,
    required this.value,
    this.zone = 'footer',
    this.align = 'center',
    this.fontSize = 13,
    this.dx = 0,
    this.dy = 0,
  });

  factory PrintCustomField.fromJson(Map<String, dynamic> json) {
    double read(String key, double fallback) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return double.tryParse('$value') ?? fallback;
    }

    final zone = json['zone']?.toString() ?? 'footer';
    final align = json['align']?.toString() ?? 'center';
    return PrintCustomField(
      id: json['id']?.toString().isNotEmpty == true
          ? json['id'].toString()
          : 'field',
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      zone: zone == 'header' ? 'header' : 'footer',
      align: align == 'right' || align == 'left' ? align : 'center',
      fontSize: read('font_size', 13).clamp(10, 32),
      dx: read('dx', 0),
      dy: read('dy', 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'value': value,
      'zone': zone,
      'align': align,
      'font_size': fontSize,
      'dx': dx,
      'dy': dy,
    };
  }

  PrintCustomField copyWith({
    String? label,
    String? value,
    String? zone,
    String? align,
    double? fontSize,
    double? dx,
    double? dy,
  }) {
    return PrintCustomField(
      id: id,
      label: label ?? this.label,
      value: value ?? this.value,
      zone: zone ?? this.zone,
      align: align ?? this.align,
      fontSize: fontSize ?? this.fontSize,
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
    );
  }
}

class PrintSettings {
  final String headerText;
  final String footerText;
  final String logoData;
  final String logoPosition;
  final double logoSize;
  final String headerAlign;
  final String footerAlign;
  final double headerFontSize;
  final double footerFontSize;
  final double tableFontSize;
  final String watermarkData;
  final bool useLogoAsWatermark;
  final double watermarkOpacity;
  final double watermarkWidth;
  final double watermarkHeight;
  final List<PrintCustomField> customFields;
  final String driverName;
  final bool showDate;
  final bool showTime;
  final bool showNumber;
  final bool showCustomer;
  final bool showPhone;
  final bool showItemCode;
  final bool showUnitPrice;
  final bool showLineDiscount;
  final bool showLineTotal;
  final bool showPaid;
  final bool showRemaining;
  final bool showPreviousDebt;
  final bool showFinalNet;
  final bool showRepresentative;
  final bool showDriver;
  final bool showCartons;
  final bool showQr;

  const PrintSettings({
    this.headerText = '',
    this.footerText = '',
    this.logoData = '',
    this.logoPosition = 'top',
    this.logoSize = 120,
    this.headerAlign = 'center',
    this.footerAlign = 'center',
    this.headerFontSize = 16,
    this.footerFontSize = 13,
    this.tableFontSize = 12,
    this.watermarkData = '',
    this.useLogoAsWatermark = true,
    this.watermarkOpacity = 0.12,
    this.watermarkWidth = 260,
    this.watermarkHeight = 260,
    this.customFields = const [],
    this.driverName = '',
    this.showDate = true,
    this.showTime = true,
    this.showNumber = true,
    this.showCustomer = true,
    this.showPhone = true,
    this.showItemCode = true,
    this.showUnitPrice = true,
    this.showLineDiscount = true,
    this.showLineTotal = true,
    this.showPaid = true,
    this.showRemaining = true,
    this.showPreviousDebt = true,
    this.showFinalNet = true,
    this.showRepresentative = true,
    this.showDriver = true,
    this.showCartons = true,
    this.showQr = true,
  });

  String watermarkSource(String logoUrl) {
    if (watermarkData.trim().isNotEmpty) return watermarkData.trim();
    if (useLogoAsWatermark) return logoUrl.trim();
    return '';
  }

  factory PrintSettings.fromJson(Map<String, dynamic> json) {
    bool on(String key) => json[key] != false;
    double number(String key, double fallback, double min, double max) {
      final value = json[key];
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse('$value') ?? fallback;
      return parsed.clamp(min, max);
    }

    final rawFields = json['custom_fields'];
    final fields = rawFields is List
        ? [
            for (final item in rawFields)
              if (item is Map)
                PrintCustomField.fromJson(Map<String, dynamic>.from(item)),
          ]
        : const <PrintCustomField>[];

    String align(String key, String fallback) {
      final value = json[key]?.toString() ?? '';
      if (value == 'right' || value == 'left' || value == 'center') {
        return value;
      }
      return fallback;
    }

    return PrintSettings(
      headerText: json['header_text']?.toString() ?? '',
      footerText: json['footer_text']?.toString() ?? '',
      logoData: json['logo_data']?.toString() ?? '',
      logoPosition: json['logo_position']?.toString().isNotEmpty == true
          ? json['logo_position'].toString()
          : 'top',
      logoSize: number('logo_size', 120, 48, 240),
      headerAlign: align('header_align', 'center'),
      footerAlign: align('footer_align', 'center'),
      headerFontSize: number('header_font_size', 16, 10, 36),
      footerFontSize: number('footer_font_size', 13, 10, 32),
      tableFontSize: number('table_font_size', 12, 9, 22),
      watermarkData: json['watermark_data']?.toString() ?? '',
      useLogoAsWatermark: json['use_logo_as_watermark'] != false,
      watermarkOpacity: number('watermark_opacity', 0.12, 0.05, 0.30),
      watermarkWidth: number('watermark_width', 260, 80, 520),
      watermarkHeight: number('watermark_height', 260, 80, 520),
      customFields: fields,
      driverName: json['driver_name']?.toString() ?? '',
      showDate: on('show_date'),
      showTime: on('show_time'),
      showNumber: on('show_number'),
      showCustomer: on('show_customer'),
      showPhone: on('show_phone'),
      showItemCode: on('show_item_code'),
      showUnitPrice: on('show_unit_price'),
      showLineDiscount: on('show_line_discount'),
      showLineTotal: on('show_line_total'),
      showPaid: on('show_paid'),
      showRemaining: on('show_remaining'),
      showPreviousDebt: on('show_previous_debt'),
      showFinalNet: on('show_final_net'),
      showRepresentative: on('show_representative'),
      showDriver: on('show_driver'),
      showCartons: on('show_cartons'),
      showQr: on('show_qr'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'header_text': headerText,
      'footer_text': footerText,
      'logo_data': logoData,
      'logo_position': logoPosition,
      'logo_size': logoSize,
      'header_align': headerAlign,
      'footer_align': footerAlign,
      'header_font_size': headerFontSize,
      'footer_font_size': footerFontSize,
      'table_font_size': tableFontSize,
      'watermark_data': watermarkData,
      'use_logo_as_watermark': useLogoAsWatermark,
      'watermark_opacity': watermarkOpacity,
      'watermark_width': watermarkWidth,
      'watermark_height': watermarkHeight,
      'custom_fields': [for (final field in customFields) field.toJson()],
      'driver_name': driverName,
      'show_date': showDate,
      'show_time': showTime,
      'show_number': showNumber,
      'show_customer': showCustomer,
      'show_phone': showPhone,
      'show_item_code': showItemCode,
      'show_unit_price': showUnitPrice,
      'show_line_discount': showLineDiscount,
      'show_line_total': showLineTotal,
      'show_paid': showPaid,
      'show_remaining': showRemaining,
      'show_previous_debt': showPreviousDebt,
      'show_final_net': showFinalNet,
      'show_representative': showRepresentative,
      'show_driver': showDriver,
      'show_cartons': showCartons,
      'show_qr': showQr,
    };
  }

  PrintSettings copyWith({
    String? headerText,
    String? footerText,
    String? logoData,
    String? logoPosition,
    double? logoSize,
    String? headerAlign,
    String? footerAlign,
    double? headerFontSize,
    double? footerFontSize,
    double? tableFontSize,
    String? watermarkData,
    bool? useLogoAsWatermark,
    double? watermarkOpacity,
    double? watermarkWidth,
    double? watermarkHeight,
    List<PrintCustomField>? customFields,
    String? driverName,
    bool? showDate,
    bool? showTime,
    bool? showNumber,
    bool? showCustomer,
    bool? showPhone,
    bool? showItemCode,
    bool? showUnitPrice,
    bool? showLineDiscount,
    bool? showLineTotal,
    bool? showPaid,
    bool? showRemaining,
    bool? showPreviousDebt,
    bool? showFinalNet,
    bool? showRepresentative,
    bool? showDriver,
    bool? showCartons,
    bool? showQr,
  }) {
    return PrintSettings(
      headerText: headerText ?? this.headerText,
      footerText: footerText ?? this.footerText,
      logoData: logoData ?? this.logoData,
      logoPosition: logoPosition ?? this.logoPosition,
      logoSize: logoSize ?? this.logoSize,
      headerAlign: headerAlign ?? this.headerAlign,
      footerAlign: footerAlign ?? this.footerAlign,
      headerFontSize: headerFontSize ?? this.headerFontSize,
      footerFontSize: footerFontSize ?? this.footerFontSize,
      tableFontSize: tableFontSize ?? this.tableFontSize,
      watermarkData: watermarkData ?? this.watermarkData,
      useLogoAsWatermark: useLogoAsWatermark ?? this.useLogoAsWatermark,
      watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
      watermarkWidth: watermarkWidth ?? this.watermarkWidth,
      watermarkHeight: watermarkHeight ?? this.watermarkHeight,
      customFields: customFields ?? this.customFields,
      driverName: driverName ?? this.driverName,
      showDate: showDate ?? this.showDate,
      showTime: showTime ?? this.showTime,
      showNumber: showNumber ?? this.showNumber,
      showCustomer: showCustomer ?? this.showCustomer,
      showPhone: showPhone ?? this.showPhone,
      showItemCode: showItemCode ?? this.showItemCode,
      showUnitPrice: showUnitPrice ?? this.showUnitPrice,
      showLineDiscount: showLineDiscount ?? this.showLineDiscount,
      showLineTotal: showLineTotal ?? this.showLineTotal,
      showPaid: showPaid ?? this.showPaid,
      showRemaining: showRemaining ?? this.showRemaining,
      showPreviousDebt: showPreviousDebt ?? this.showPreviousDebt,
      showFinalNet: showFinalNet ?? this.showFinalNet,
      showRepresentative: showRepresentative ?? this.showRepresentative,
      showDriver: showDriver ?? this.showDriver,
      showCartons: showCartons ?? this.showCartons,
      showQr: showQr ?? this.showQr,
    );
  }
}
