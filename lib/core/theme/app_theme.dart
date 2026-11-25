import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Palette 100 % lumineuse fidèle au Web XFY (Zéro noir / zéro bloc sombre) :
/// Fond clair #F0F4FF · Indigo/Violet #6366F1 → #8B5CF6 · Bleu XFY #1C84EE ·
/// Cartes KPI dégradées identiques à `analytics.component.scss` et `statistics.component.scss`.
class XfyColors {
  XfyColors._();

  // Couleurs principales lumineuses Web XFY
  static const Color primary = Color(0xFF4F46E5);
  static const Color primaryDark = Color(0xFF3F51B5);
  static const Color primaryVibrant = Color(0xFF6366F1);
  static const Color primaryBlue = Color(0xFF1C84EE);
  static const Color primaryViolet = Color(0xFF8B5CF6);
  static const Color primarySoft = Color(0xFFEEF2FF);

  // Accent signature orange du logo xfy.
  static const Color accent = Color(0xFFFF6D00);
  static const Color accentSoft = Color(0xFFFFF3E6);

  // Textes (ardoise lisible sur fond blanc — jamais de fond noir)
  static const Color ink = Color(0xFF1E293B);
  static const Color inkSecondary = Color(0xFF475569);
  static const Color inkMuted = Color(0xFF94A3B8);

  // Surfaces claires Web XFY
  static const Color canvas = Color(0xFFF0F4FF);
  static const Color canvasAlt = Color(0xFFF8F9FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFEEF2F8);

  // Sémantique statuts & KPIs Web XFY
  static const Color cyan = Color(0xFF06B6D4);
  static const Color cyanSoft = Color(0xFFECFEFF);

  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldSoft = Color(0xFFECFDF5);

  static const Color indigo = Color(0xFF6366F1);
  static const Color indigoSoft = Color(0xFFEEF2FF);

  static const Color amber = Color(0xFFF59E0B);
  static const Color amberSoft = Color(0xFFFFFBEB);

  static const Color rose = Color(0xFFF43F5E);
  static const Color roseSoft = Color(0xFFFFF1F2);

  static const Color violet = Color(0xFF8B5CF6);
  static const Color violetSoft = Color(0xFFF5F3FF);

  static const Color teal = Color(0xFF14B8A6);
  static const Color pink = Color(0xFFEC4899);

  static const Color whatsapp = Color(0xFF16A34A);

  // Dégradés exacts de analytics.component.scss & statistics.component.scss
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF4F46E5), Color(0xFF6366F1), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient statsGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient kpiRevenueGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient kpiOrdersGradient = LinearGradient(
    colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient kpiGreenGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient kpiReturnsGradient = LinearGradient(
    colors: [Color(0xFFF43F5E), Color(0xFFE11D48)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient kpiAmberGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient kpiTealGradient = LinearGradient(
    colors: [Color(0xFF14B8A6), Color(0xFF0F766E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient kpiPinkGradient = LinearGradient(
    colors: [Color(0xFFEC4899), Color(0xFFDB2777)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient kpiPurpleGradient = LinearGradient(
    colors: [Color(0xFFA855F7), Color(0xFF7E22CE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0D6366F1),
      blurRadius: 8,
      offset: Offset(0, 3),
    ),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    const colorScheme = ColorScheme.light(
      primary: XfyColors.primary,
      onPrimary: Colors.white,
      secondary: XfyColors.primaryVibrant,
      onSecondary: Colors.white,
      surface: XfyColors.surface,
      onSurface: XfyColors.ink,
      error: XfyColors.rose,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: XfyColors.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: XfyColors.surface,
        foregroundColor: XfyColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: XfyColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: XfyColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: XfyColors.border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: XfyColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: XfyColors.inkMuted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: XfyColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: XfyColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: XfyColors.primaryVibrant, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: XfyColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: XfyColors.primary,
          side: const BorderSide(color: XfyColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? XfyColors.primaryVibrant
              : const Color(0xFFCBD5E1);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: XfyColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: XfyColors.divider,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: XfyColors.primaryDark,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
