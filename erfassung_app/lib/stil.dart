import 'package:flutter/material.dart';

// Das Aussehen der App: ruhige Flächen ohne Rahmen, runde Ecken, große
// Zahlen und große Tippflächen für die Arbeit an der Anlage. Die Farben
// tragen überall dieselbe Bedeutung — Blau ist die nächste Aktion, Orange
// heißt läuft oder offen, Grün heißt erledigt oder geändert, Rot nur bei
// einem Fehler.

/// Maße.
abstract final class Masse {
  /// Die Ecken von Flächen und Karten.
  static const BorderRadius ecken = BorderRadius.all(Radius.circular(18));

  /// Die Ecken von Knöpfen, Feldern und kleinen Kacheln.
  static const BorderRadius eckenKlein = BorderRadius.all(Radius.circular(14));

  /// Die Mindesthöhe von Zeilen und Knöpfen zum Antippen.
  static const double tippHoehe = 56;
}

/// Die Statusfarben neben dem Farbschema.
class Farben extends ThemeExtension<Farben> {
  const Farben({
    required this.ok,
    required this.warnung,
    required this.flaeche2,
  });

  /// Erledigt, erfasst, geändert.
  final Color ok;

  /// Läuft, offen, weiche Grenze überschritten.
  final Color warnung;

  /// Eine Stufe heller als die Fläche — für Felder und Kacheln auf einer
  /// Karte.
  final Color flaeche2;

  static Farben von(BuildContext context) =>
      Theme.of(context).extension<Farben>()!;

  @override
  Farben copyWith({Color? ok, Color? warnung, Color? flaeche2}) => Farben(
        ok: ok ?? this.ok,
        warnung: warnung ?? this.warnung,
        flaeche2: flaeche2 ?? this.flaeche2,
      );

  @override
  Farben lerp(Farben? other, double t) => other == null
      ? this
      : Farben(
          ok: Color.lerp(ok, other.ok, t)!,
          warnung: Color.lerp(warnung, other.warnung, t)!,
          flaeche2: Color.lerp(flaeche2, other.flaeche2, t)!,
        );
}

abstract final class AppStil {
  static ThemeData hell() => _bauen(
        const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF2563C9),
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFDCE7FB),
          onPrimaryContainer: Color(0xFF0D2C63),
          secondary: Color(0xFF2563C9),
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFDCE7FB),
          onSecondaryContainer: Color(0xFF0D2C63),
          error: Color(0xFFC62828),
          onError: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xFF16181C),
          onSurfaceVariant: Color(0xFF60646C),
          surfaceContainerHighest: Color(0xFFEEF0F3),
          outline: Color(0xFFD9DCE1),
          outlineVariant: Color(0xFFE6E8EC),
        ),
        hintergrund: const Color(0xFFF3F4F6),
        farben: const Farben(
          ok: Color(0xFF15935A),
          warnung: Color(0xFFC77700),
          flaeche2: Color(0xFFF1F3F6),
        ),
      );

  static ThemeData dunkel() => _bauen(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF6AA8FF),
          onPrimary: Color(0xFF08111F),
          primaryContainer: Color(0xFF21324D),
          onPrimaryContainer: Color(0xFFD6E6FF),
          secondary: Color(0xFF6AA8FF),
          onSecondary: Color(0xFF08111F),
          secondaryContainer: Color(0xFF21324D),
          onSecondaryContainer: Color(0xFFD6E6FF),
          error: Color(0xFFF26D6D),
          onError: Color(0xFF2B0606),
          surface: Color(0xFF1B1C20),
          onSurface: Color(0xFFF2F3F5),
          onSurfaceVariant: Color(0xFFA6A9B0),
          surfaceContainerHighest: Color(0xFF2E3036),
          outline: Color(0xFF34363C),
          outlineVariant: Color(0xFF2A2C31),
        ),
        hintergrund: const Color(0xFF111214),
        farben: const Farben(
          ok: Color(0xFF3ECF8E),
          warnung: Color(0xFFF5A524),
          flaeche2: Color(0xFF24262B),
        ),
      );

  static ThemeData _bauen(
    ColorScheme f, {
    required Color hintergrund,
    required Farben farben,
  }) {
    const form = RoundedRectangleBorder(borderRadius: Masse.eckenKlein);
    return ThemeData(
      useMaterial3: true,
      colorScheme: f,
      scaffoldBackgroundColor: hintergrund,
      canvasColor: hintergrund,
      extensions: [farben],
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: hintergrund,
        foregroundColor: f.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: f.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: f.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: Masse.ecken),
      ),
      dividerTheme: DividerThemeData(color: f.outlineVariant, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: f.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: f.primaryContainer,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected)
                ? f.onSurface
                : f.onSurfaceVariant,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, Masse.tippHoehe),
          shape: form,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, Masse.tippHoehe),
          shape: form,
          side: BorderSide(color: f.outline),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: form,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: farben.flaeche2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: const OutlineInputBorder(
          borderRadius: Masse.eckenKlein,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: Masse.eckenKlein,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Masse.eckenKlein,
          borderSide: BorderSide(color: f.primary, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: f.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Masse.ecken),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: f.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: f.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Masse.eckenKlein),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
