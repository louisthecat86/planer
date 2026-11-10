import 'package:flutter/material.dart';

// Das Aussehen der App — die Farben des Produktions Planers (sein Blau,
// seine grauen Flächen, eckige Kanten), aber mit großen Tippflächen für
// die Arbeit an der Anlage.

/// Maße.
abstract final class Masse {
  static const BorderRadius ecken = BorderRadius.all(Radius.circular(4));

  /// Die Mindesthöhe von Zeilen und Knöpfen zum Antippen.
  static const double tippHoehe = 56;
}

/// Die Statusfarben neben dem Farbschema.
class Farben extends ThemeExtension<Farben> {
  const Farben({required this.ok, required this.warnung});

  final Color ok;
  final Color warnung;

  static Farben von(BuildContext context) =>
      Theme.of(context).extension<Farben>()!;

  @override
  Farben copyWith({Color? ok, Color? warnung}) =>
      Farben(ok: ok ?? this.ok, warnung: warnung ?? this.warnung);

  @override
  Farben lerp(Farben? other, double t) => other == null
      ? this
      : Farben(
          ok: Color.lerp(ok, other.ok, t)!,
          warnung: Color.lerp(warnung, other.warnung, t)!,
        );
}

abstract final class AppStil {
  static const Color blau = Color(0xFF1E5B94);
  static const Color blauHell = Color(0xFF4C9FE0);

  static ThemeData hell() => _bauen(
        const ColorScheme(
          brightness: Brightness.light,
          primary: blau,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFCDE3F5),
          onPrimaryContainer: Color(0xFF0B3A63),
          secondary: Color(0xFF2F6FA8),
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFE3EFFA),
          onSecondaryContainer: Color(0xFF0B3A63),
          error: Color(0xFFB4232A),
          onError: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xFF1A1A1A),
          onSurfaceVariant: Color(0xFF5A5A5A),
          surfaceContainerHighest: Color(0xFFEDEDED),
          outline: Color(0xFFD4D4D4),
          outlineVariant: Color(0xFFE2E2E2),
        ),
        hintergrund: const Color(0xFFF3F3F3),
        farben: const Farben(
          ok: Color(0xFF2E7D32),
          warnung: Color(0xFFB26A00),
        ),
      );

  static ThemeData dunkel() => _bauen(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: blauHell,
          onPrimary: Color(0xFF06243D),
          primaryContainer: Color(0xFF16344F),
          onPrimaryContainer: Color(0xFFD6E9FA),
          secondary: Color(0xFF6FB4E8),
          onSecondary: Color(0xFF06243D),
          secondaryContainer: Color(0xFF1B3B57),
          onSecondaryContainer: Color(0xFFD6E9FA),
          error: Color(0xFFEF6B6B),
          onError: Color(0xFF3B0709),
          surface: Color(0xFF252526),
          onSurface: Color(0xFFE8E8E8),
          onSurfaceVariant: Color(0xFFA8A8A8),
          surfaceContainerHighest: Color(0xFF2F2F30),
          outline: Color(0xFF3C3C3C),
          outlineVariant: Color(0xFF343435),
        ),
        hintergrund: const Color(0xFF1E1E1E),
        farben: const Farben(
          ok: Color(0xFF7BC67E),
          warnung: Color(0xFFF0B45A),
        ),
      );

  static ThemeData _bauen(
    ColorScheme f, {
    required Color hintergrund,
    required Farben farben,
  }) {
    final rand = BorderSide(color: f.outline);
    const form = RoundedRectangleBorder(borderRadius: Masse.ecken);
    return ThemeData(
      useMaterial3: true,
      colorScheme: f,
      scaffoldBackgroundColor: hintergrund,
      extensions: [farben],
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor:
            f.brightness == Brightness.light ? AppStil.blau : f.surface,
        foregroundColor:
            f.brightness == Brightness.light ? Colors.white : f.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: f.brightness == Brightness.light ? Colors.white : f.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: f.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: Masse.ecken, side: rand),
      ),
      dividerTheme: DividerThemeData(color: f.outlineVariant, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, Masse.tippHoehe),
          shape: form,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, Masse.tippHoehe),
          shape: form,
          side: rand,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: form,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: f.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(borderRadius: Masse.ecken, borderSide: rand),
        enabledBorder:
            OutlineInputBorder(borderRadius: Masse.ecken, borderSide: rand),
        focusedBorder: OutlineInputBorder(
          borderRadius: Masse.ecken,
          borderSide: BorderSide(color: f.primary, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: f.surface,
        surfaceTintColor: Colors.transparent,
        shape: form,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
