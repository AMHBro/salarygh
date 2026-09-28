import 'package:flutter/material.dart';

class AliraColors {
  static const canvas = Color(0xFFDFE5EE);
  static const background = Color(0xFFF3F5F8);
  static const paper = Color(0xFFFFFFFF);
  static const text = Color(0xFF1C2430);
  static const muted = Color(0xFF6B7788);
  static const line = Color(0xFF8E9AAB);
  static const frame = BorderSide(color: line, width: 1.4);
  static const green = Color(0xFF1F8A5B);
  static const orange = Color(0xFFE07A1F);
  static const red = Color(0xFFD64545);
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
              border: Border.all(color: AliraColors.line, width: 1.6),
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
    borderRadius: BorderRadius.circular(12),
    borderSide: AliraColors.frame,
  );
  return Theme.of(context).copyWith(
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AliraColors.paper,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(color: AliraColors.text, width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AliraColors.paper,
      selectedColor: const Color(0xFFE7EEF6),
      side: AliraColors.frame,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: const TextStyle(color: AliraColors.text, fontSize: 12),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: AliraColors.frame,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      color: AliraColors.paper,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        children: [
          const Row(
            children: [
              Text('9:41', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              Spacer(),
              Text('LTE · 57%', style: TextStyle(fontSize: 12, color: AliraColors.muted)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  visualDensity: VisualDensity.compact,
                )
              else
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AliraColors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'أ',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    if (hint != null)
                      Text(hint!, style: const TextStyle(fontSize: 11, color: AliraColors.muted)),
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
