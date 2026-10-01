import 'package:flutter/material.dart';

import '../../../core/printing/print_preview.dart';
import '../../../core/theme/app_theme.dart';
import '../models/document_layout.dart';
import '../models/print_settings.dart';
import 'print_logo_pick.dart';

class PrintTemplateSection extends StatefulWidget {
  final PrintSettings settings;
  final ValueChanged<PrintSettings> onChanged;

  const PrintTemplateSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  State<PrintTemplateSection> createState() => _PrintTemplateSectionState();
}

class _PrintTemplateSectionState extends State<PrintTemplateSection> {
  String _preview = 'sale';

  PrintSettings get settings => widget.settings;

  void _change(PrintSettings value) => widget.onChanged(value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'إعدادات المطبوعات',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'تُحفظ كصورة ونصوص داخل الحاسبة وتنطبق على فواتير البيع والشراء، وصولات القبض والدفع، كشوف الزبائن والموردين، وتقارير المخزون والحسابات. اسحب الحقل المخصص داخل المعاينة لتغيير مكانه.',
          style: TextStyle(color: AppTheme.secondaryTextColor),
        ),
        const SizedBox(height: 14),
        _LivePreview(
          kind: _preview,
          settings: settings,
          onKind: (value) => setState(() => _preview = value),
          onFieldMoved: (id, dx, dy) {
            _change(
              settings.copyWith(
                customFields: [
                  for (final field in settings.customFields)
                    if (field.id == id)
                      field.copyWith(dx: dx, dy: dy)
                    else
                      field,
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _LogoCard(settings: settings, onChanged: _change),
        const SizedBox(height: 12),
        _WatermarkCard(settings: settings, onChanged: _change),
        const SizedBox(height: 12),
        _TextCard(settings: settings, onChanged: _change),
        const SizedBox(height: 12),
        _StyleCard(settings: settings, onChanged: _change),
        const SizedBox(height: 12),
        _FieldsCard(settings: settings, onChanged: _change),
        const SizedBox(height: 12),
        _ToggleCard(
          title: 'المعلومات الأساسية',
          children: [
            _switch(settings, 'التاريخ', settings.showDate, (value) => settings.copyWith(showDate: value), _change),
            _switch(settings, 'الوقت', settings.showTime, (value) => settings.copyWith(showTime: value), _change),
            _switch(settings, 'رقم الوصل أو القائمة', settings.showNumber, (value) => settings.copyWith(showNumber: value), _change),
            _switch(settings, 'اسم الزبون', settings.showCustomer, (value) => settings.copyWith(showCustomer: value), _change),
            _switch(settings, 'رقم الهاتف', settings.showPhone, (value) => settings.copyWith(showPhone: value), _change),
          ],
        ),
        const SizedBox(height: 12),
        _ToggleCard(
          title: 'تفاصيل المواد',
          children: [
            _switch(settings, 'رمز المادة', settings.showItemCode, (value) => settings.copyWith(showItemCode: value), _change),
            _switch(settings, 'السعر الفردي', settings.showUnitPrice, (value) => settings.copyWith(showUnitPrice: value), _change),
            _switch(settings, 'الخصم', settings.showLineDiscount, (value) => settings.copyWith(showLineDiscount: value), _change),
            _switch(settings, 'إجمالي السطر', settings.showLineTotal, (value) => settings.copyWith(showLineTotal: value), _change),
          ],
        ),
        const SizedBox(height: 12),
        _ToggleCard(
          title: 'الذيل المالي',
          children: [
            _switch(settings, 'المدفوع', settings.showPaid, (value) => settings.copyWith(showPaid: value), _change),
            _switch(settings, 'المتبقي', settings.showRemaining, (value) => settings.copyWith(showRemaining: value), _change),
            _switch(settings, 'الدين السابق', settings.showPreviousDebt, (value) => settings.copyWith(showPreviousDebt: value), _change),
            _switch(settings, 'الصافي النهائي', settings.showFinalNet, (value) => settings.copyWith(showFinalNet: value), _change),
          ],
        ),
        const SizedBox(height: 12),
        _ToggleCard(
          title: 'بيانات فواتير البيع',
          children: [
            _switch(settings, 'اسم المندوب', settings.showRepresentative, (value) => settings.copyWith(showRepresentative: value), _change),
            _switch(settings, 'السائق', settings.showDriver, (value) => settings.copyWith(showDriver: value), _change),
            _switch(settings, 'إجمالي الكراتين', settings.showCartons, (value) => settings.copyWith(showCartons: value), _change),
          ],
        ),
        const SizedBox(height: 12),
        _ToggleCard(
          title: 'التحقق',
          children: [
            _switch(settings, 'رمز المتجر', settings.showQr, (value) => settings.copyWith(showQr: value), _change),
          ],
        ),
      ],
    );
  }
}

Widget _switch(
  PrintSettings settings,
  String title,
  bool value,
  PrintSettings Function(bool value) next,
  ValueChanged<PrintSettings> onChanged,
) {
  return SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    value: value,
    onChanged: (selected) => onChanged(next(selected)),
  );
}

class _ToggleCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ToggleCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ...children,
        ],
      ),
    );
  }
}

class _TextCard extends StatefulWidget {
  final PrintSettings settings;
  final ValueChanged<PrintSettings> onChanged;

  const _TextCard({
    required this.settings,
    required this.onChanged,
  });

  @override
  State<_TextCard> createState() => _TextCardState();
}

class _TextCardState extends State<_TextCard> {
  late final TextEditingController _header;
  late final TextEditingController _footer;
  late final TextEditingController _driver;

  @override
  void initState() {
    super.initState();
    _header = TextEditingController(text: widget.settings.headerText);
    _footer = TextEditingController(text: widget.settings.footerText);
    _driver = TextEditingController(text: widget.settings.driverName);
  }

  @override
  void didUpdateWidget(covariant _TextCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(_header, widget.settings.headerText);
    _sync(_footer, widget.settings.footerText);
    _sync(_driver, widget.settings.driverName);
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text != value) {
      controller.text = value;
    }
  }

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    _driver.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      widget.settings.copyWith(
        headerText: _header.text,
        footerText: _footer.text,
        driverName: _driver.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        children: [
          TextField(
            controller: _header,
            maxLines: 2,
            onChanged: (_) => _emit(),
            decoration: const InputDecoration(
              labelText: 'نص الرأس',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _footer,
            maxLines: 2,
            onChanged: (_) => _emit(),
            decoration: const InputDecoration(
              labelText: 'نص الذيل',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _driver,
            onChanged: (_) => _emit(),
            decoration: const InputDecoration(
              labelText: 'اسم السائق على فواتير البيع',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoCard extends StatelessWidget {
  final PrintSettings settings;
  final ValueChanged<PrintSettings> onChanged;

  const _LogoCard({
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('الشعار', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                onPressed: () async {
                  try {
                    final image = await pickPrintImage(title: 'شعار المكتب');
                    if (image == null) return;
                    onChanged(settings.copyWith(logoData: image));
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$error'.replaceFirst('Bad state: ', ''))),
                    );
                  }
                },
                child: const Text('رفع شعار المكتب'),
              ),
              const SizedBox(width: 8),
              if (settings.logoData.isNotEmpty)
                TextButton(
                  onPressed: () => onChanged(settings.copyWith(logoData: '')),
                  child: const Text('إزالة'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: settings.logoPosition,
            decoration: const InputDecoration(
              labelText: 'موقع الشعار',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'top', child: Text('أعلى الورقة')),
              DropdownMenuItem(value: 'right', child: Text('يمين الرأس')),
              DropdownMenuItem(value: 'left', child: Text('يسار الرأس')),
            ],
            onChanged: (value) {
              if (value == null) return;
              onChanged(settings.copyWith(logoPosition: value));
            },
          ),
          const SizedBox(height: 8),
          Text('حجم الشعار: ${settings.logoSize.round()}'),
          Slider(
            min: 48,
            max: 240,
            value: settings.logoSize.clamp(48, 240),
            onChanged: (value) => onChanged(settings.copyWith(logoSize: value)),
          ),
        ],
      ),
    );
  }
}

class _LivePreview extends StatelessWidget {
  final String kind;
  final PrintSettings settings;
  final ValueChanged<String> onKind;
  final void Function(String id, double dx, double dy) onFieldMoved;

  const _LivePreview({
    required this.kind,
    required this.settings,
    required this.onKind,
    required this.onFieldMoved,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8E8ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'معاينة حيّة',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'sale', label: Text('فاتورة بيع')),
              ButtonSegment(value: 'receipt', label: Text('وصل قبض')),
              ButtonSegment(value: 'statement', label: Text('كشف حساب')),
            ],
            selected: {kind},
            onSelectionChanged: (value) => onKind(value.first),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: PrintSheetView(
              document: _sampleDocument(kind),
              settings: settings,
              header: const DocumentHeader(
                officeName: 'مكتب سايلر',
                address: 'شارع فلسطين',
                phone: '07700000000',
              ),
              onFieldMoved: onFieldMoved,
            ),
          ),
        ],
      ),
    );
  }
}

PrintDocument _sampleDocument(String kind) {
  if (kind == 'receipt') {
    return const PrintDocument(
      kind: 'وصل',
      title: 'وصل قبض',
      number: 'R-1042',
      party: 'أحمد علي',
      phone: '07701234567',
      printedDate: '2026-09-29',
      printedTime: '16:40',
      documentTypeLabel: 'النوع',
      documentType: 'وصل قبض',
      grandTotal: 150000,
      paidIqd: 150000,
      previousIqd: 25000,
      remainingIqd: 25000,
      previousIqdLabel: 'الرصيد السابق',
      paidIqdLabel: 'المسدد',
      remainingIqdLabel: 'الرصيد النهائي',
      totals: [
        'المسدد: 150,000',
        'الرصيد السابق: 25,000',
        'الرصيد النهائي: 25,000',
      ],
    );
  }
  if (kind == 'statement') {
    return const PrintDocument(
      kind: 'كشف',
      title: 'كشف حساب زبون',
      partyLabel: 'كشف',
      party: 'أحمد علي',
      phone: '07701234567',
      printedDate: '2026-09-29',
      printedTime: '16:40',
      columns: ['التاريخ', 'البيان', 'مدين', 'دائن', 'الرصيد'],
      rows: [
        ['2026-09-01', 'رصيد افتتاحي', '25,000', '0', '25,000'],
        ['2026-09-20', 'قائمة بيع', '175,000', '0', '200,000'],
        ['2026-09-25', 'تسديد', '0', '150,000', '50,000'],
      ],
      accountStatement: true,
      debitTotal: 200000,
      creditTotal: 150000,
      lastPaymentDate: '2026-09-25',
      lastPaymentAmount: 150000,
      remainingIqd: 50000,
    );
  }
  return const PrintDocument(
    kind: 'قائمة بيع',
    title: 'قائمة بيع',
    number: 'S-2201',
    party: 'أحمد علي',
    phone: '07701234567',
    representative: 'أحمد المندوب',
    driver: 'سائق المكتب',
    printedDate: '2026-09-29',
    printedTime: '16:40',
    documentType: 'آجل',
    columns: ['ت', 'التفاصيل', 'كارتون', 'سعر القطعة', 'المبلغ'],
    itemCodes: ['SKU-1', 'SKU-2'],
    rows: [
      ['1', 'عصير برتقال', '2', '1,500', '36,000'],
      ['2', 'ماء 1.5 لتر', '5', '500', '30,000'],
    ],
    grandTotal: 175000,
    discount: 5000,
    cartonCount: 7,
    paidIqd: 100000,
    previousIqd: 25000,
    remainingIqd: 100000,
    previousIqdLabel: 'الرصيد السابق',
    paidIqdLabel: 'المسدد',
    remainingIqdLabel: 'الرصيد النهائي',
    totals: [
      'إجمالي القائمة: 175,000',
      'المسدد: 100,000',
      'متبقي القائمة: 75,000',
      'الرصيد السابق: 25,000',
      'الرصيد النهائي: 100,000',
    ],
  );
}

class _WatermarkCard extends StatelessWidget {
  final PrintSettings settings;
  final ValueChanged<PrintSettings> onChanged;

  const _WatermarkCard({
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('العلامة المائية', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'تظهر في منتصف كل فاتورة ووصل وكشف وتقرير، خلف النص.',
            style: TextStyle(color: AppTheme.secondaryTextColor),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('استخدام الشعار كعلامة مائية'),
            value: settings.useLogoAsWatermark,
            onChanged: (value) => onChanged(settings.copyWith(useLogoAsWatermark: value)),
          ),
          Row(
            children: [
              OutlinedButton(
                onPressed: () async {
                  try {
                    final image = await pickPrintImage(title: 'العلامة المائية');
                    if (image == null) return;
                    onChanged(settings.copyWith(watermarkData: image));
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$error'.replaceFirst('Bad state: ', ''))),
                    );
                  }
                },
                child: const Text('رفع صورة العلامة'),
              ),
              const SizedBox(width: 8),
              if (settings.watermarkData.isNotEmpty)
                TextButton(
                  onPressed: () => onChanged(settings.copyWith(watermarkData: '')),
                  child: const Text('إزالة الصورة'),
                ),
            ],
          ),
          Text('الشفافية: ${(settings.watermarkOpacity * 100).round()}%'),
          Slider(
            min: 0.05,
            max: 0.30,
            value: settings.watermarkOpacity.clamp(0.05, 0.30),
            onChanged: (value) => onChanged(settings.copyWith(watermarkOpacity: value)),
          ),
          Text('عرض العلامة: ${settings.watermarkWidth.round()}'),
          Slider(
            min: 80,
            max: 520,
            value: settings.watermarkWidth.clamp(80, 520),
            onChanged: (value) => onChanged(settings.copyWith(watermarkWidth: value)),
          ),
          Text('ارتفاع العلامة: ${settings.watermarkHeight.round()}'),
          Slider(
            min: 80,
            max: 520,
            value: settings.watermarkHeight.clamp(80, 520),
            onChanged: (value) => onChanged(settings.copyWith(watermarkHeight: value)),
          ),
        ],
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  final PrintSettings settings;
  final ValueChanged<PrintSettings> onChanged;

  const _StyleCard({
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('المحاذاة وحجم الخط', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _alignField(
            'محاذاة الرأس',
            settings.headerAlign,
            (value) => onChanged(settings.copyWith(headerAlign: value)),
          ),
          Text('حجم خط الرأس: ${settings.headerFontSize.round()}'),
          Slider(
            min: 10,
            max: 36,
            value: settings.headerFontSize.clamp(10, 36),
            onChanged: (value) => onChanged(settings.copyWith(headerFontSize: value)),
          ),
          _alignField(
            'محاذاة الذيل',
            settings.footerAlign,
            (value) => onChanged(settings.copyWith(footerAlign: value)),
          ),
          Text('حجم خط الذيل: ${settings.footerFontSize.round()}'),
          Slider(
            min: 10,
            max: 32,
            value: settings.footerFontSize.clamp(10, 32),
            onChanged: (value) => onChanged(settings.copyWith(footerFontSize: value)),
          ),
          Text('حجم خط الجدول: ${settings.tableFontSize.round()}'),
          Slider(
            min: 9,
            max: 22,
            value: settings.tableFontSize.clamp(9, 22),
            onChanged: (value) => onChanged(settings.copyWith(tableFontSize: value)),
          ),
        ],
      ),
    );
  }
}

class _FieldsCard extends StatelessWidget {
  final PrintSettings settings;
  final ValueChanged<PrintSettings> onChanged;

  const _FieldsCard({
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('حقول مخصصة', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in const ['الرقم الضريبي', 'رقم الحساب البنكي', 'هاتف إضافي', 'رابط الموقع'])
                ActionChip(
                  label: Text(preset),
                  onPressed: () => onChanged(
                    settings.copyWith(
                      customFields: [
                        ...settings.customFields,
                        PrintCustomField(
                          id: DateTime.now().microsecondsSinceEpoch.toString(),
                          label: preset,
                          value: '',
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final field in settings.customFields) ...[
            _FieldEditor(
              field: field,
              onChanged: (next) {
                onChanged(
                  settings.copyWith(
                    customFields: [
                      for (final item in settings.customFields)
                        if (item.id == field.id) next else item,
                    ],
                  ),
                );
              },
              onDelete: () {
                onChanged(
                  settings.copyWith(
                    customFields: [
                      for (final item in settings.customFields)
                        if (item.id != field.id) item,
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _FieldEditor extends StatefulWidget {
  final PrintCustomField field;
  final ValueChanged<PrintCustomField> onChanged;
  final VoidCallback onDelete;

  const _FieldEditor({
    required this.field,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  late final TextEditingController _label;
  late final TextEditingController _value;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.field.label);
    _value = TextEditingController(text: widget.field.value);
  }

  @override
  void didUpdateWidget(covariant _FieldEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_label.text != widget.field.label) _label.text = widget.field.label;
    if (_value.text != widget.field.value) _value.text = widget.field.value;
  }

  @override
  void dispose() {
    _label.dispose();
    _value.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      widget.field.copyWith(label: _label.text, value: _value.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          TextField(
            controller: _label,
            onChanged: (_) => _emit(),
            decoration: const InputDecoration(labelText: 'عنوان الحقل'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _value,
            onChanged: (_) => _emit(),
            decoration: const InputDecoration(labelText: 'القيمة'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: field.zone,
            decoration: const InputDecoration(labelText: 'الموضع'),
            items: const [
              DropdownMenuItem(value: 'header', child: Text('الرأس')),
              DropdownMenuItem(value: 'footer', child: Text('الذيل')),
            ],
            onChanged: (value) {
              if (value == null) return;
              widget.onChanged(field.copyWith(zone: value));
            },
          ),
          const SizedBox(height: 8),
          _alignField(
            'المحاذاة',
            field.align,
            (value) => widget.onChanged(field.copyWith(align: value)),
          ),
          Text('حجم الخط: ${field.fontSize.round()}'),
          Slider(
            min: 10,
            max: 32,
            value: field.fontSize.clamp(10, 32),
            onChanged: (value) => widget.onChanged(field.copyWith(fontSize: value)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: widget.onDelete, child: const Text('حذف')),
          ),
        ],
      ),
    );
  }
}

Widget _alignField(String label, String value, ValueChanged<String> onChanged) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: const [
        DropdownMenuItem(value: 'right', child: Text('يمين')),
        DropdownMenuItem(value: 'center', child: Text('وسط')),
        DropdownMenuItem(value: 'left', child: Text('يسار')),
      ],
      onChanged: (next) {
        if (next == null) return;
        onChanged(next);
      },
    ),
  );
}

Widget _panel({required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.borderColor),
    ),
    child: child,
  );
}
