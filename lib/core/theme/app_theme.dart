import 'package:flutter/material.dart';

/// Zentrales Theme der App.
///
/// Hell: sauber, weiß-basiert. Dunkel: ruhige, abgestufte Flächen —
/// wichtig, weil Windows-Builds fest im Dunkelmodus laufen.
///
/// Gemeinsame Komponenten-Stile (Buttons, Eingabefelder, Chips, Dialoge)
/// sind für beide Modi identisch aufgebaut, damit die App überall gleich
/// „spricht": Radius 16 für Karten, 12 für Felder/Menüs, 10 für Buttons.
class AppTheme {
  static ThemeData light() {
    const seed = Color(0xFF455A64); // Blue Grey 700 – neutral, professionell
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    ).copyWith(
      inputDecorationTheme: _eingabefelder(colorScheme),
      filledButtonTheme: _filledButtons(),
      outlinedButtonTheme: _outlinedButtons(),
      textButtonTheme: _textButtons(),
      chipTheme: _chips(colorScheme),
      dialogTheme: _dialoge(colorScheme),
      popupMenuTheme: _popupMenus(colorScheme),
      snackBarTheme: _snackBars(colorScheme),
    );
  }

  static ThemeData dark() {
    const seed = Color(0xFF455A64);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );

    // Abgestufte dunkle Flächen: Hintergrund am tiefsten, Karten eine
    // Stufe heller, AppBar dazwischen — gibt ruhige, klare Schichtung.
    const hintergrund = Color(0xFF121417);
    const flaeche = Color(0xFF1C2025);
    const leiste = Color(0xFF181B1F);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: hintergrund,
      appBarTheme: AppBarTheme(
        backgroundColor: leiste,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: flaeche,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.08),
        thickness: 1,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    ).copyWith(
      inputDecorationTheme: _eingabefelder(colorScheme),
      filledButtonTheme: _filledButtons(),
      outlinedButtonTheme: _outlinedButtons(),
      textButtonTheme: _textButtons(),
      chipTheme: _chips(colorScheme),
      dialogTheme: _dialoge(colorScheme, hintergrund: flaeche),
      popupMenuTheme: _popupMenus(colorScheme, hintergrund: flaeche),
      snackBarTheme: _snackBars(colorScheme),
    );
  }

  // ── Gemeinsame Komponenten-Stile ──────────────────────────────────

  static InputDecorationTheme _eingabefelder(ColorScheme colors) {
    return InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.4),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colors.onSurface.withValues(alpha: 0.12),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colors.onSurface.withValues(alpha: 0.12),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.primary, width: 1.6),
      ),
    );
  }

  static FilledButtonThemeData _filledButtons() {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtons() {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  static TextButtonThemeData _textButtons() {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  static ChipThemeData _chips(ColorScheme colors) {
    return ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: colors.onSurface.withValues(alpha: 0.12)),
      ),
      labelStyle: TextStyle(fontSize: 13, color: colors.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    );
  }

  static DialogThemeData _dialoge(
    ColorScheme colors, {
    Color? hintergrund,
  }) {
    return DialogThemeData(
      backgroundColor: hintergrund,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      titleTextStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  static PopupMenuThemeData _popupMenus(
    ColorScheme colors, {
    Color? hintergrund,
  }) {
    return PopupMenuThemeData(
      color: hintergrund,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  static SnackBarThemeData _snackBars(ColorScheme colors) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}