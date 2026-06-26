import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// LIITA DESIGN SYSTEM — Cool Slate + Soft Blue (dark neumorphic)
// =============================================================================
// Dark soft-UI palette: a true mid-dark cool-slate base (so neu light/dark
// shadows both read) with a calm blue accent that is analogous to the base.
// Minimal, premium, cohesive. See NeuDark for the neumorphic surface tokens.

class AppColors {
  AppColors._();

  // ── Backgrounds — cool slate (background == NeuDark.base) ──
  static const Color background    = Color(0xFF262A33); // mid-dark slate
  static const Color backgroundLight = Color(0xFF2A2E37); // slightly lifted
  static const Color surface       = Color(0xFF2A2E37); // flat-card fallback
  static const Color surfaceLight  = Color(0xFF323843); // elevated / chips

  // ── Glass / borders — subtle light hairline ──
  static const Color glass         = Color(0x0FFFFFFF); // white 6%
  static const Color glassBorder   = Color(0x0FFFFFFF); // white 6%

  // ── Accent — soft blue (buttons, active state, indicators) ──
  static const Color primary       = Color(0xFF4F8FCB); // blue
  static const Color primaryLight  = Color(0xFF6FA8DC); // brighter on-dark
  static const Color primaryDark   = Color(0xFF3E73A6); // pressed

  // ── Keep for BLE status indicators ──
  static const Color accent        = Color(0xFF4F8FCB);
  static const Color accentLight   = Color(0xFF6FA8DC);
  static const Color accentDark    = Color(0xFF3E73A6);
  static const Color accentMuted   = Color(0xFF4A6A8A);

  // ── Semantic colours ──
  static const Color wave          = Color(0xFF4F8FCB);
  static const Color waveLight     = Color(0xFF6FA8DC);
  static const Color waveDark      = Color(0xFF3E73A6);
  static const Color match         = Color(0xFF4F8FCB);
  static const Color matchLight    = Color(0xFF6FA8DC);
  static const Color success       = Color(0xFF5DBE9A); // muted teal
  static const Color successDark   = Color(0xFF3E8E72);
  static const Color error         = Color(0xFFE5645D); // softened red
  static const Color warning       = Color(0xFFE0A24A); // amber (semantic)

  // ── Text hierarchy ──
  static const Color textPrimary   = Color(0xFFE7E9EE); // soft near-white
  static const Color textSecondary = Color(0xFFA2A9B5); // cool grey
  static const Color textTertiary  = Color(0xFF6C7280); // muted cool grey
  static const Color textOnPrimary = Color(0xFFFFFFFF); // white text on blue

  // ── Structural ──
  static const Color divider       = Color(0xFF2F343D);
  static const Color shimmer       = Color(0xFF2A2E37);

  // ── Avatar backgrounds (cool slate tones) ──
  static const List<Color> avatarColors = [
    Color(0xFF2E333D),
    Color(0xFF272B33),
    Color(0xFF343A45),
    Color(0xFF22262D),
  ];

  // ── Gradients ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF4F8FCB), Color(0xFF3E73A6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF2A2E37), Color(0xFF323843)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Legacy gradient aliases
  static const LinearGradient accentGradient    = primaryGradient;
  static const LinearGradient radarGradient     = primaryGradient;
  static const LinearGradient sentBubbleGradient = primaryGradient;
  static const LinearGradient navGlowGradient   = LinearGradient(
    colors: [Color(0x004F8FCB), Color(0x224F8FCB), Color(0x004F8FCB)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const RadialGradient radarPulseGradient = RadialGradient(
    colors: [Color(0x224F8FCB), Color(0x114F8FCB), Color(0x004F8FCB)],
    stops: [0.0, 0.5, 1.0],
  );
}

/// Design tokens for the neumorphic (soft-UI) showcase surface.
///
/// This is a deliberately LIGHT palette, distinct from the app's dark
/// "Warm Charcoal + Gold" theme — it backs the standalone neumorphic showcase
/// screen, which is wrapped in its own NeumorphicTheme rather than altering the
/// app-wide theme.
class NeuTokens {
  NeuTokens._();

  static const Color base = Color(0xFFE3E6EB); // soft light-grey surface
  static const Color lightShadow = Color(0xFFFFFFFF); // top-left highlight
  static const Color darkShadow = Color(0xFFA3B1C6); // bottom-right shadow
  static const Color accent = Color(0xFF4F8FCB); // blue accent
  static const Color text = Color(0xFF4A4A4A); // primary text/icon

  static const double pillRadius = 50.0;
}

/// Dark neumorphic (soft-UI) tokens — the app's primary surface language.
///
/// A true mid-dark cool-slate base so both the top-left highlight and the
/// bottom-right shadow read on dark; a calm blue accent analogous to the base;
/// a faint white hairline to crisp edges where the soft shadow alone is muddy.
/// These back the app-wide dark [NeumorphicThemeData] (built in main.dart) and
/// are referenced directly by hand-painted surfaces.
class NeuDark {
  NeuDark._();

  static const Color base = Color(0xFF262A33); // background + raised surface
  static const Color highlight = Color(0xFF31363F); // top-left light shadow
  static const Color shadow = Color(0xFF1B1E24); // bottom-right dark shadow
  static const Color hairline = Color(0x0FFFFFFF); // white 6% edge crisp

  static const Color accent = Color(0xFF4F8FCB); // blue
  static const Color accentBright = Color(0xFF6FA8DC); // accent text/icon on dark
  static const Color accentDeep = Color(0xFF3E73A6); // pressed/active

  static const Color text = Color(0xFFE7E9EE);
  static const Color textMuted = Color(0xFFA2A9B5);
  static const Color textFaint = Color(0xFF6C7280);

  static const double radius = 18.0;
  static const double pillRadius = 999.0;
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
        fillColor: AppColors.surfaceLight,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
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
