import 'package:flutter/material.dart';

class AliraColors {
  static const canvas = Color(0xFFD5DEE6);
  static const background = Color(0xFFF1F4F7);
  static const paper = Color(0xFFFFFFFF);
  static const text = Color(0xFF1C2430);
  static const muted = Color(0xFF6B7788);
  static const line = Color(0xFFD7DEE6);
  static const capsule = Color(0xFFE7ECF1);
  static const frame = BorderSide(color: line, width: 1);
  static const teal = Color(0xFF0F4C45);
  static const green = teal;
  static const orange = Color(0xFFE07A1F);
  static const red = Color(0xFFD64545);
  static const radius = 18.0;
}

class AliraPhone extends StatelessWidget {
  final double maxWidth;
  final String fontFamily;
  final Widget child;

  const AliraPhone({
    super.key,
    required this.child,
    this.maxWidth = 390,
    this.fontFamily = 'IBM Plex Sans Arabic',
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AliraColors.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: 844,
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 16),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AliraColors.background,
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: AliraColors.line, width: 1.2),
            ),
            child: Theme(
              data: _framedTheme(context),
              child: Material(
                color: AliraColors.background,
                child: DefaultTextStyle(
                  style: TextStyle(
                    fontFamily: fontFamily,
                    color: AliraColors.text,
                    fontSize: 14,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData _framedTheme(BuildContext context) {
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AliraColors.line),
  );
  return Theme.of(context).copyWith(
    colorScheme: Theme.of(context).colorScheme.copyWith(
      primary: AliraColors.teal,
      surface: AliraColors.paper,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AliraColors.teal),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AliraColors.paper,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(color: AliraColors.teal, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AliraColors.teal,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFB7C4C2),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AliraColors.radius)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AliraColors.paper,
      selectedColor: AliraColors.teal,
      side: const BorderSide(color: AliraColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: const TextStyle(color: AliraColors.text, fontSize: 12),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AliraColors.teal,
        side: const BorderSide(color: AliraColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AliraColors.radius)),
      ),
    ),
  );
}

class AliraStatusBar extends StatelessWidget {
  final String title;
  final String? hint;
  final VoidCallback? onBack;

  const AliraStatusBar({
    super.key,
    required this.title,
    this.hint,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AliraColors.teal,
      padding: const EdgeInsets.fromLTRB(8, 10, 14, 14),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text('9:41', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white)),
                Spacer(),
                Text('LTE · 57%', style: TextStyle(fontSize: 12, color: Color(0xCCFFFFFF))),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                  visualDensity: VisualDensity.compact,
                )
              else
                Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0x22FFFFFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'أ',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                    if (hint != null)
                      Text(hint!, style: const TextStyle(fontSize: 11, color: Color(0xCCFFFFFF))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AliraFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const AliraFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: selected ? AliraColors.teal : AliraColors.paper,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? AliraColors.teal : AliraColors.line),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AliraColors.text,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AliraQtyCapsule extends StatelessWidget {
  final int quantity;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const AliraQtyCapsule({
    super.key,
    required this.quantity,
    this.onMinus,
    this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AliraColors.capsule,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(Icons.remove, onMinus),
          SizedBox(
            width: 28,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          _button(Icons.add, onPlus),
        ],
      ),
    ),
    );
  }

  Widget _button(IconData icon, VoidCallback? onPressed) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 16,
        color: AliraColors.teal,
        icon: Icon(icon),
      ),
    );
  }
}

class AliraSoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AliraSoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AliraColors.paper,
        borderRadius: BorderRadius.circular(AliraColors.radius),
        boxShadow: const [
          BoxShadow(color: Color(0x120F4C45), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: child,
    );
  }
}
