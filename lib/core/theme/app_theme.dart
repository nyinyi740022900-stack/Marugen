import 'package:flutter/material.dart';

/// Marugen Fish Farm brand palette — derived from the shop logo
/// (black ring, red hanko seal, white brush strokes, red/white koi).
class AppColors {
  AppColors._();

  static const Color black = Color(0xFF0B0507);
  static const Color charcoal = Color(0xFF1C1416);
  static const Color red = Color(0xFFD31F16);
  static const Color redDark = Color(0xFF9C160F);
  static const Color redSoft = Color(0xFFFBE7E5);
  static const Color white = Color(0xFFFDFDFB);
  static const Color offWhite = Color(0xFFF4F2EE);
  static const Color grey = Color(0xFF6B6B6B);
  // Secondary text must remain readable on white and warm ivory surfaces.
  static const Color greySoft = Color(0xFF6B6B6B);
  static const Color lightGrey = Color(0xFFE3E1DC);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFB8860B);
  static const Color error = Color(0xFFB00020);
}

/// Color roles resolve from the nearest theme, including dialogs and sheets.
/// Brand artwork and photo overlays continue to use the fixed AppColors.
class AppPalette {
  final Color background, surface, surfaceMuted, text, textMuted, border;
  final Color accent, accentSoft, success, warning, error;
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.error,
  });
  static const light = AppPalette(
    background: AppColors.offWhite,
    surface: AppColors.white,
    surfaceMuted: AppColors.offWhite,
    text: AppColors.black,
    textMuted: AppColors.grey,
    border: AppColors.lightGrey,
    accent: AppColors.red,
    accentSoft: AppColors.redSoft,
    success: AppColors.success,
    warning: Color(0xFF806000),
    error: AppColors.error,
  );
  static const dark = AppPalette(
    background: Color(0xFF130F11),
    surface: Color(0xFF21191C),
    surfaceMuted: Color(0xFF30262A),
    text: Color(0xFFF4EEE9),
    textMuted: Color(0xFFC4B9B5),
    border: Color(0xFF68575E),
    accent: Color(0xFFFF8178),
    accentSoft: Color(0xFF482423),
    success: Color(0xFF93D59B),
    warning: Color(0xFFEAC46A),
    error: Color(0xFFFF8FA3),
  );
  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// 4pt-based spacing scale used across every screen so paddings/margins
/// read as one consistent rhythm instead of ad-hoc numbers.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Corner radii — one scale, reused everywhere (cards, buttons, sheets).
class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 18;
  static const double pill = 100;
}

/// Soft, low-opacity shadows in place of flat Material elevation — reads
/// as considered "product photography" depth rather than a generic app.
class AppShadows {
  AppShadows._();

  static List<BoxShadow> card = [
    BoxShadow(
      color: AppColors.black.withValues(alpha: 0.06),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> raised = [
    BoxShadow(
      color: AppColors.black.withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final colors = AppPalette.dark;
    final base = light;
    final textTheme = _textTheme.apply(
      bodyColor: colors.text,
      displayColor: colors.text,
    );
    final scheme = ColorScheme.dark(
      primary: colors.accent,
      onPrimary: AppColors.black,
      secondary: colors.accent,
      onSecondary: AppColors.black,
      primaryContainer: colors.accentSoft,
      onPrimaryContainer: colors.text,
      secondaryContainer: colors.accentSoft,
      onSecondaryContainer: colors.text,
      surface: colors.surface,
      onSurface: colors.text,
      surfaceContainerHighest: colors.surfaceMuted,
      onSurfaceVariant: colors.textMuted,
      outline: colors.border,
      outlineVariant: colors.border,
      error: colors.error,
      onError: AppColors.black,
    );
    final input = base.inputDecorationTheme;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
      cardColor: colors.surface,
      dividerColor: colors.border,
      disabledColor: colors.textMuted.withValues(alpha: .45),
      hintColor: colors.textMuted,
      textTheme: textTheme.copyWith(
        bodySmall: textTheme.bodySmall?.copyWith(color: colors.textMuted),
        labelSmall: textTheme.labelSmall?.copyWith(color: colors.textMuted),
      ),
      iconTheme: IconThemeData(color: colors.text),
      primaryIconTheme: const IconThemeData(color: AppColors.white),
      listTileTheme: ListTileThemeData(
        textColor: colors.text,
        iconColor: colors.textMuted,
      ),
      inputDecorationTheme: input.copyWith(
        fillColor: colors.surface,
        labelStyle: TextStyle(color: colors.textMuted, fontSize: 14),
        hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
        border: border(colors.border),
        enabledBorder: border(colors.border),
        focusedBorder: border(colors.accent, 1.6),
        errorBorder: border(colors.error, 1.4),
        focusedErrorBorder: border(colors.error, 1.6),
      ),
      cardTheme: base.cardTheme.copyWith(color: colors.surface),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.text,
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: colors.border, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colors.surface,
        selectedColor: colors.accentSoft,
        side: BorderSide(color: colors.border),
        labelStyle: TextStyle(
          color: colors.text,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        secondaryLabelStyle: TextStyle(
          color: colors.text,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
        backgroundColor: colors.surface,
        selectedItemColor: colors.accent,
        unselectedItemColor: colors.textMuted,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.accentSoft,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? colors.accent
                : colors.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.accent
                : colors.textMuted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.accentSoft,
        selectedIconTheme: IconThemeData(color: colors.accent),
        unselectedIconTheme: IconThemeData(color: colors.textMuted),
        selectedLabelTextStyle: TextStyle(color: colors.accent),
        unselectedLabelTextStyle: TextStyle(color: colors.textMuted),
      ),
      dividerTheme: base.dividerTheme.copyWith(color: colors.border),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: colors.surface,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: colors.surface,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        textStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: colors.surfaceMuted,
        contentTextStyle: TextStyle(color: colors.text, fontSize: 14),
        actionTextColor: colors.accent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.accent,
        selectionColor: colors.accent.withValues(alpha: .25),
        selectionHandleColor: colors.accent,
      ),
    );
  }

  // Type scale. System fonts (SF Pro / Roboto) with deliberate weights and
  // tracking instead of default Material sizing — a tight, editorial scale
  // that matches the hanko-seal / brush-stroke mark rather than a generic
  // rounded UI font.
  static const String _fontFamily = '.SF Pro Text';

  static TextTheme get _textTheme => const TextTheme(
    displayLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.15,
      color: AppColors.black,
    ),
    headlineMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.2,
      color: AppColors.black,
    ),
    titleLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 19,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: AppColors.black,
    ),
    titleMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AppColors.black,
    ),
    titleSmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: AppColors.black,
    ),
    bodyLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: AppColors.black,
    ),
    bodyMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: AppColors.black,
    ),
    bodySmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.35,
      color: AppColors.grey,
    ),
    labelLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    labelMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    ),
    labelSmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      color: AppColors.grey,
    ),
  );

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = _textTheme;
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.offWhite,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: const ColorScheme.light(
        primary: AppColors.black,
        secondary: AppColors.red,
        surface: AppColors.white,
        error: AppColors.error,
        onPrimary: AppColors.white,
        onSecondary: AppColors.white,
        onSurface: AppColors.black,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: AppColors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      // TabBars sit in the black AppBar — force light labels so "Varieties /
      // Care Guides" (and admin tabs) are readable; default onSurface is black.
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.white,
        unselectedLabelColor: Color(0xFFB8B1AD),
        indicatorColor: AppColors.red,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.red,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.red.withValues(alpha: 0.4),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.black,
          side: const BorderSide(color: AppColors.black, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.red,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: AppColors.grey, fontSize: 14),
        hintStyle: const TextStyle(color: AppColors.greySoft, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.lightGrey, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.lightGrey, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.red, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 1.4),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.white,
        selectedColor: AppColors.black,
        side: const BorderSide(color: AppColors.lightGrey),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        labelStyle: const TextStyle(
          color: AppColors.black,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AppColors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.red,
        unselectedItemColor: AppColors.greySoft,
        showUnselectedLabels: true,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.redSoft,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.red : AppColors.greySoft,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.red : AppColors.greySoft,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightGrey,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.black,
        contentTextStyle: const TextStyle(color: AppColors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.red,
      ),
    );
  }
}
