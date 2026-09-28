import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Main Colors
  static const Color primaryColor = Color(0xFF1D1D1F);
  static const Color backgroundColor = Color(0xFFF5F5F7);
  static const Color surfaceColor = Color(0xFFFFFFFF);

  // Text
  static const Color primaryTextColor = Color(0xFF1D1D1F);
  static const Color secondaryTextColor = Color(0xFF6E6E73);
  static const Color tertiaryTextColor = Color(0xFF86868B);

  // Borders — visible frames so each block stays easy to scan
  static const Color borderColor = Color(0xFFB4B4BA);
  static const Color subtleBorderColor = Color(0xFFC8C8CE);
  static const BorderSide frame = BorderSide(
    color: borderColor,
    width: 1.4,
  );

  // Semantic
  static const Color successColor = Color(0xFF248A3D);
  static const Color warningColor = Color(0xFFD97706);
  static const Color dangerColor = Color(0xFFD70015);

  // Compatibility
  static const Color mutedTextColor = secondaryTextColor;
  static const Color cardColor = surfaceColor;

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      surface: surfaceColor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: backgroundColor,

      colorScheme: colorScheme.copyWith(
        primary: primaryColor,
        surface: surfaceColor,
        outline: borderColor,
      ),

      dividerColor: borderColor,

      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: const Color(0xFFF2F2F4),

      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: surfaceColor,
        foregroundColor: primaryTextColor,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: primaryTextColor,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),

      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: frame,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,

        hintStyle: const TextStyle(
          color: tertiaryTextColor,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),

        labelStyle: const TextStyle(
          color: secondaryTextColor,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: borderColor,
          ),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: frame,
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: primaryColor,
            width: 1.2,
          ),
        ),

        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: dangerColor,
          ),
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: dangerColor,
            width: 1.2,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,

          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),

          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          foregroundColor: primaryTextColor,
          backgroundColor: surfaceColor,

          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 15,
          ),

          side: frame,

          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryTextColor,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: primaryTextColor,
          hoverColor: const Color(0xFFF2F2F4),
          highlightColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: frame,
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 20,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: frame,
        ),
        titleTextStyle: const TextStyle(
          color: primaryTextColor,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: secondaryTextColor,
          fontSize: 14,
          height: 1.5,
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: primaryColor,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(false),
        thickness: WidgetStateProperty.all(5),
        radius: const Radius.circular(20),
        thumbColor: WidgetStateProperty.all(
          const Color(0xFFC7C7CC),
        ),
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: primaryTextColor,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),

        headlineMedium: TextStyle(
          color: primaryTextColor,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),

        headlineSmall: TextStyle(
          color: primaryTextColor,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),

        titleLarge: TextStyle(
          color: primaryTextColor,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),

        titleMedium: TextStyle(
          color: primaryTextColor,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),

        titleSmall: TextStyle(
          color: primaryTextColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),

        bodyLarge: TextStyle(
          color: primaryTextColor,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),

        bodyMedium: TextStyle(
          color: primaryTextColor,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),

        bodySmall: TextStyle(
          color: secondaryTextColor,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}