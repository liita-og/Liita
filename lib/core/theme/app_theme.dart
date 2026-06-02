import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// LIITA DESIGN SYSTEM — Monochromatic Minimal Edition
// =============================================================================
// Faithful implementation of the Figma/v0 design:
// Near-black surfaces, off-white accent, Inter font, no colour noise.

class AppColors {
  AppColors._();

  // ── Backgrounds ──
  static const Color background    = Color(0xFF09090B);
  static const Color backgroundLight = Color(0xFF0F0F11);
  static const Color surface       = Color(0xFF121214);
  static const Color surfaceLight  = Color(0xFF1C1C1F);

  // ── Glass / borders ──
  static const Color glass         = Color(0x0FFFFFFF); // white 6%
  static const Color glassBorder   = Color(0x0FFFFFFF); // white 6%

  // ── Accent — near-white (buttons, active state) ──
  static const Color primary       = Color(0xFFEDEDED);
  static const Color primaryLight  = Color(0xFFFAFAFA);
  static const Color primaryDark   = Color(0xFFD4D4D4);

  // ── Keep these for BLE status indicators only ──
  static const Color accent        = Color(0xFFEDEDED);
  static const Color accentLight   = Color(0xFFFAFAFA);
  static const Color accentDark    = Color(0xFFD4D4D4);
  static const Color accentMuted   = Color(0xFFA1A1AA);

  // ── Semantic colours (minimal usage) ──
  static const Color wave          = Color(0xFFEDEDED);
  static const Color waveLight     = Color(0xFFFAFAFA);
  static const Color waveDark      = Color(0xFFD4D4D4);
  static const Color match         = Color(0xFFEDEDED);
  static const Color matchLight    = Color(0xFFFAFAFA);
  static const Color success       = Color(0xFF52525B);
  static const Color successDark   = Color(0xFF3F3F46);
  static const Color error         = Color(0xFFEF4444);
  static const Color warning       = Color(0xFFF59E0B);

  // ── Text hierarchy ──
  static const Color textPrimary   = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textTertiary  = Color(0xFF52525B);
  static const Color textOnPrimary = Color(0xFF09090B); // dark text on light button

  // ── Structural ──
  static const Color divider       = Color(0xFF27272A);
  static const Color shimmer       = Color(0xFF1C1C1F);

  // ── Avatar backgrounds (monochrome palette) ──
  static const List<Color> avatarColors = [
    Color(0xFF27272A),
    Color(0xFF1C1C1F),
    Color(0xFF3F3F46),
    Color(0xFF18181B),
  ];

  // ── Gradients (subtle, monochromatic) ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFEDEDED), Color(0xFFD4D4D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF121214), Color(0xFF1C1C1F)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Legacy gradient aliases kept to avoid breaking existing references
  static const LinearGradient accentGradient    = primaryGradient;
  static const LinearGradient radarGradient     = primaryGradient;
  static const LinearGradient sentBubbleGradient = primaryGradient;
  static const LinearGradient navGlowGradient   = LinearGradient(
    colors: [Color(0x00EDEDED), Color(0x22EDEDED), Color(0x00EDEDED)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const RadialGradient radarPulseGradient = RadialGradient(
    colors: [Color(0x22EDEDED), Color(0x11EDEDED), Color(0x00EDEDED)],
    stops: [0.0, 0.5, 1.0],
  );
}

class AppSpacing {
  AppSpacing._();

  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 16.0;
  static const double lg   = 24.0;
  static const double xl   = 32.0;
  static const double xxl  = 48.0;
  static const double xxxl = 64.0;
}

class AppRadius {
  AppRadius._();

  static const double sm   = 8.0;
  static const double md   = 12.0;
  static const double lg   = 16.0;
  static const double xl   = 20.0;
  static const double pill = 999.0;

  static final BorderRadius smAll   = BorderRadius.circular(sm);
  static final BorderRadius mdAll   = BorderRadius.circular(md);
  static final BorderRadius lgAll   = BorderRadius.circular(lg);
  static final BorderRadius xlAll   = BorderRadius.circular(xl);
  static final BorderRadius pillAll = BorderRadius.circular(pill);
}

class AppShadows {
  AppShadows._();

  static List<BoxShadow> get glow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.5),
      blurRadius: 32,
      offset: const Offset(0, 16),
    ),
  ];

  static List<BoxShadow> get primaryGlow => [
    BoxShadow(
      color: Colors.white.withValues(alpha: 0.04),
      blurRadius: 20,
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get card => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get elevated => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.5),
      blurRadius: 40,
      offset: const Offset(0, 16),
    ),
  ];
}

/// Surface card decoration helper.
class AppGlass {
  AppGlass._();

  static BoxDecoration card({
    double borderRadius = AppRadius.lg,
    double borderOpacity = 0.06,
  }) => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(
      color: Colors.white.withValues(alpha: borderOpacity),
      width: 1,
    ),
  );

  static BoxDecoration surface({
    double borderRadius = AppRadius.lg,
  }) => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(
      color: AppColors.glassBorder,
      width: 1,
    ),
    boxShadow: AppShadows.card,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final textTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.textOnPrimary,
        onSecondary: AppColors.textOnPrimary,
        onSurface: AppColors.textPrimary,
        onError: AppColors.textPrimary,
      ),
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.8,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.5,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.3,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.2,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        titleSmall: textTheme.titleSmall?.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w400,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(
          color: AppColors.textPrimary,
          height: 1.5,
          fontWeight: FontWeight.w300,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
          height: 1.5,
        ),
        bodySmall: textTheme.bodySmall?.copyWith(
          color: AppColors.textTertiary,
          fontSize: 12,
          height: 1.5,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 18,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: AppColors.textPrimary,
        unselectedItemColor: AppColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: false,
        showSelectedLabels: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: const BorderSide(color: AppColors.glassBorder, width: 1),
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: AppRadius.lgAll,
          borderSide: const BorderSide(color: AppColors.glassBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgAll,
          borderSide: const BorderSide(color: AppColors.glassBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgAll,
          borderSide: const BorderSide(color: AppColors.textSecondary, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgAll,
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.lgAll,
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.glassBorder, width: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.lgAll,
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 0.5,
        space: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceLight,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.3,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceLight,
        side: const BorderSide(color: AppColors.glassBorder, width: 1),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.pillAll,
        ),
      ),
    );
  }
}
