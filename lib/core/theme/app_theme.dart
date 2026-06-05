import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// LIITA DESIGN SYSTEM — Warm Charcoal + Gold Edition
// =============================================================================
// Dual-tone palette: near-black warm charcoal base + muted amber/gold accent.
// Minimal, premium, distinctive — not cold-grey, not generic.

class AppColors {
  AppColors._();

  // ── Backgrounds — warm charcoal ──
  static const Color background    = Color(0xFF0E0D0C); // warm near-black
  static const Color backgroundLight = Color(0xFF131210); // slightly lifted
  static const Color surface       = Color(0xFF1A1816); // warm dark surface
  static const Color surfaceLight  = Color(0xFF252220); // elevated surface

  // ── Glass / borders ──
  static const Color glass         = Color(0x14C9A85C); // gold tint 8%
  static const Color glassBorder   = Color(0x14C9A85C); // gold tint 8%

  // ── Accent — muted gold (buttons, active state, indicators) ──
  static const Color primary       = Color(0xFFC9A85C); // warm amber/gold
  static const Color primaryLight  = Color(0xFFD4B870); // lighter gold
  static const Color primaryDark   = Color(0xFFAA8C48); // deeper gold

  // ── Keep for BLE status indicators ──
  static const Color accent        = Color(0xFFC9A85C);
  static const Color accentLight   = Color(0xFFD4B870);
  static const Color accentDark    = Color(0xFFAA8C48);
  static const Color accentMuted   = Color(0xFF8A7145);

  // ── Semantic colours ──
  static const Color wave          = Color(0xFFC9A85C);
  static const Color waveLight     = Color(0xFFD4B870);
  static const Color waveDark      = Color(0xFFAA8C48);
  static const Color match         = Color(0xFFC9A85C);
  static const Color matchLight    = Color(0xFFD4B870);
  static const Color success       = Color(0xFF4A4540);
  static const Color successDark   = Color(0xFF3A3530);
  static const Color error         = Color(0xFFEF4444);
  static const Color warning       = Color(0xFFC9A85C);

  // ── Text hierarchy ──
  static const Color textPrimary   = Color(0xFFF5F0E8); // warm off-white
  static const Color textSecondary = Color(0xFF9E9589); // warm grey
  static const Color textTertiary  = Color(0xFF5C5450); // muted warm grey
  static const Color textOnPrimary = Color(0xFF0E0D0C); // dark text on gold button

  // ── Structural ──
  static const Color divider       = Color(0xFF2A2620);
  static const Color shimmer       = Color(0xFF252220);

  // ── Avatar backgrounds (warm tones) ──
  static const List<Color> avatarColors = [
    Color(0xFF2A2620),
    Color(0xFF1E1C18),
    Color(0xFF352F28),
    Color(0xFF181614),
  ];

  // ── Gradients ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFC9A85C), Color(0xFFAA8C48)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF1A1816), Color(0xFF252220)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Legacy gradient aliases
  static const LinearGradient accentGradient    = primaryGradient;
  static const LinearGradient radarGradient     = primaryGradient;
  static const LinearGradient sentBubbleGradient = primaryGradient;
  static const LinearGradient navGlowGradient   = LinearGradient(
    colors: [Color(0x00C9A85C), Color(0x22C9A85C), Color(0x00C9A85C)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const RadialGradient radarPulseGradient = RadialGradient(
    colors: [Color(0x22C9A85C), Color(0x11C9A85C), Color(0x00C9A85C)],
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
        brightness: Brightness.dark,
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
