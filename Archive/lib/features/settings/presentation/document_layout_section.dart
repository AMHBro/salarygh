import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../products/presentation/image_pick.dart';
import '../models/document_layout.dart';

class DocumentLayoutSection extends StatelessWidget {
  final List<LayoutBlock> invoice;
  final List<LayoutBlock> receipt;
  final DocumentHeader header;
  final ValueChanged<List<LayoutBlock>> onInvoiceChanged;
  final ValueChanged<List<LayoutBlock>> onReceiptChanged;
  final ValueChanged<DocumentHeader> onHeaderChanged;

  const DocumentLayoutSection({
    super.key,
    required this.invoice,
    required this.receipt,
    required this.header,
    required this.onInvoiceChanged,
    required this.onReceiptChanged,
    required this.onHeaderChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'تصاميم القوائم والوصولات',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'رتّب أقسام ورقة القائمة وورقة الوصل، وأخفِ ما لا تريد طباعته. الترتيب يُحفظ مع إعدادات الشركة.',
          style: TextStyle(color: AppTheme.secondaryTextColor),
        ),
        const SizedBox(height: 14),
        _HeaderEditor(
          header: header,
          onChanged: onHeaderChanged,
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 760;
            final invoiceEditor = _LayoutEditor(
              title: 'القائمة',
              blocks: invoice,
              onChanged: onInvoiceChanged,
            );
            final receiptEditor = _LayoutEditor(
              title: 'الوصل',
              blocks: receipt,
              onChanged: onReceiptChanged,
            );

            if (stacked) {
              return Column(
                children: [
                  invoiceEditor,
                  const SizedBox(height: 12),
                  receiptEditor,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: invoiceEditor),
                const SizedBox(width: 12),
                Expanded(child: receiptEditor),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HeaderEditor extends StatefulWidget {
  final DocumentHeader header;
  final ValueChanged<DocumentHeader> onChanged;

  const _HeaderEditor({
    required this.header,
    required this.onChanged,
  });

  @override
  State<_HeaderEditor> createState() => _HeaderEditorState();
}

class _HeaderEditorState extends State<_HeaderEditor> {
  late final TextEditingController _officeName;
  late final TextEditingController _address;
  late final TextEditingController _description;
  late final TextEditingController _phone;
  late final TextEditingController _phone2;
  late final TextEditingController _phoneLabel;
  late final TextEditingController _phone2Label;
  late final List<TextEditingController> _extraLines;
  late String _logoUrl;
  late String _position;
  late bool _watermark;

  @override
  void initState() {
    super.initState();
    _officeName = TextEditingController(text: widget.header.officeName);
    _address = TextEditingController(text: widget.header.address);
    _description = TextEditingController(text: widget.header.description);
    _phone = TextEditingController(text: widget.header.phone);
    _phone2 = TextEditingController(text: widget.header.phone2);
    _phoneLabel = TextEditingController(text: widget.header.phoneLabel);
    _phone2Label = TextEditingController(text: widget.header.phone2Label);
    _extraLines = [
      for (final line in widget.header.extraLines)
        TextEditingController(text: line),
    ];
    _logoUrl = widget.header.logoUrl;
    _position = widget.header.position;
    _watermark = widget.header.watermark;
  }

  @override
  void didUpdateWidget(covariant _HeaderEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(_officeName, widget.header.officeName);
    _sync(_address, widget.header.address);
    _sync(_description, widget.header.description);
    _sync(_phone, widget.header.phone);
    _sync(_phone2, widget.header.phone2);
    _sync(_phoneLabel, widget.header.phoneLabel);
    _sync(_phone2Label, widget.header.phone2Label);
    _logoUrl = widget.header.logoUrl;
    _position = widget.header.position;
    _watermark = widget.header.watermark;
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }

    controller.text = value;
  }

  @override
  void dispose() {
    _officeName.dispose();
    _address.dispose();
    _description.dispose();
    _phone.dispose();
    _phone2.dispose();
    _phoneLabel.dispose();
    _phone2Label.dispose();
    for (final line in _extraLines) {
      line.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      DocumentHeader(
        officeName: _officeName.text,
        address: _address.text,
        description: _description.text,
        phone: _phone.text,
        phone2: _phone2.text,
        phoneLabel: _phoneLabel.text,
        phone2Label: _phone2Label.text,
        logoUrl: _logoUrl,
        position: _position,
        extraLines: [
          for (final line in _extraLines)
            if (line.text.trim().isNotEmpty) line.text.trim(),
        ],
        watermark: _watermark,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'اسم الشركة وبياناتها',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'تظهر على التقارير والقوائم: اسم الشركة والعنوان والوصف والهواتف والشعار.',
            style: TextStyle(color: AppTheme.secondaryTextColor),
          ),
          const SizedBox(height: 12),
          _box(_officeName, 'اسم الشركة'),
          _box(_address, 'العنوان'),
          _box(_description, 'الوصف', maxLines: 3),
          _box(_phoneLabel, 'اسم الهاتف الأول'),
          _box(_phone, 'رقم الهاتف'),
          _box(_phone2Label, 'اسم الهاتف الثاني'),
          _box(_phone2, 'رقم هاتف إضافي'),
          DropdownButtonFormField<String>(
            initialValue: _position,
            decoration: const InputDecoration(
              labelText: 'موقع بيانات الشركة',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'top', child: Text('أعلى الصفحة')),
              DropdownMenuItem(value: 'right', child: Text('يمين الصفحة')),
              DropdownMenuItem(value: 'left', child: Text('يسار الصفحة')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _position = value);
              _emit();
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton(
                onPressed: () async {
                  final image = await pickProductImage();
                  if (image == null || !mounted) return;
                  setState(() => _logoUrl = image);
                  _emit();
                },
                child: const Text('رفع شعار الشركة'),
              ),
              const SizedBox(width: 8),
              if (_logoUrl.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() => _logoUrl = '');
                    _emit();
                  },
                  child: const Text('إزالة الشعار'),
                ),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _watermark,
            title: const Text('الشعار الكامل بشكل باهت على الورقة'),
            subtitle: const Text('يظهر في وسط القائمة والوصل مثل علامة خفيفة.'),
            onChanged: (value) {
              setState(() => _watermark = value ?? true);
              _emit();
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'سطور إضافية',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < _extraLines.length; index++)
            Row(
              children: [
                Expanded(child: _box(_extraLines[index], 'سطر ${index + 1}')),
                IconButton(
                  tooltip: 'حذف السطر',
                  onPressed: () {
                    final removed = _extraLines.removeAt(index);
                    removed.dispose();
                    setState(_emit);
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _extraLines.add(TextEditingController());
                });
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('إضافة سطر'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: (_) => _emit(),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _LayoutEditor extends StatelessWidget {
  final String title;
  final List<LayoutBlock> blocks;
  final ValueChanged<List<LayoutBlock>> onChanged;

  const _LayoutEditor({
    required this.title,
    required this.blocks,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final visible = blocks.where((block) => block.visible).toList();

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
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < blocks.length; index++)
            _BlockRow(
              block: blocks[index],
              canMoveUp: index > 0,
              canMoveDown: index < blocks.length - 1,
              onVisible: (value) {
                final next = List<LayoutBlock>.from(blocks);
                next[index] = next[index].copyWith(visible: value);
                onChanged(next);
              },
              onMoveUp: () => onChanged(_move(blocks, index, index - 1)),
              onMoveDown: () => onChanged(_move(blocks, index, index + 1)),
            ),
          const SizedBox(height: 12),
          const Text(
            'المعاينة',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: visible.isEmpty
                ? const Text('لا توجد أقسام ظاهرة')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final block in visible)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(block.title),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<LayoutBlock> _move(
    List<LayoutBlock> source,
    int from,
    int to,
  ) {
    final next = List<LayoutBlock>.from(source);
    final block = next.removeAt(from);
    next.insert(to, block);
    return next;
  }
}

class _BlockRow extends StatelessWidget {
  final LayoutBlock block;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<bool> onVisible;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  const _BlockRow({
    required this.block,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onVisible,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: block.visible,
          onChanged: (value) => onVisible(value ?? false),
        ),
        Expanded(
          child: Text(
            block.title,
            style: TextStyle(
              color: block.visible
                  ? AppTheme.primaryTextColor
                  : AppTheme.secondaryTextColor,
            ),
          ),
        ),
        IconButton(
          tooltip: 'أعلى',
          onPressed: canMoveUp ? onMoveUp : null,
          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
        ),
        IconButton(
          tooltip: 'أسفل',
          onPressed: canMoveDown ? onMoveDown : null,
          icon: const Icon(Icons.arrow_downward_rounded, size: 18),
        ),
      ],
    );
  }
}
