import 'package:flutter/material.dart';

/// Zentrales Theme der App — angelehnt an Microsoft Dynamics NAV
/// („Navision"), damit sich das Team optisch sofort zurechtfindet.
///
/// Die Gestaltungsregeln stammen aus der NAV-Oberfläche:
///  • dicht statt luftig — mehr Zeilen aufs Bild, wenig Leerraum
///  • kantig statt rund — Radius 3 px, keine „App-Kacheln"
///  • dünne graue Linien als Struktur, keine Schatten
///  • ein kräftiges Blau als einziger Akzent (Titel, Links, Auswahl)
///  • Segoe UI als Schrift (unter Windows vorhanden, sonst Fallback)
///
/// Beide Modi nutzen dieselbe Struktur; im Dunkelmodus sind lediglich die
/// Flächen abgestuft und das Blau aufgehellt, damit der Kontrast stimmt.
class AppTheme {
  // ── Farbwelt Navision ───────────────────────────────────────────────
  /// Kräftiges NAV-Blau (Titelzeilen, aktive Elemente, Statusleiste).
  static const Color navBlau = Color(0xFF1E5B94);

  /// Link-/Aktionsblau wie in den NAV-Rollencentern.
  static const Color navLink = Color(0xFF0563C1);

  /// Aufgehelltes Blau für den Dunkelmodus (Kontrast auf dunklem Grund).
  static const Color navBlauHell = Color(0xFF4C9FE0);

  /// Hintergrund markierter Tabellenzeilen (hell / dunkel).
  static const Color navAuswahlHell = Color(0xFFCDE3F5);
  static const Color navAuswahlDunkel = Color(0xFF16344F);

  /// Schrift: Segoe UI ist die NAV-Schrift. Fehlt sie (macOS, Linux),
  /// greifen die Fallbacks.
  static const String _schrift = 'Segoe UI';
  static const List<String> _schriftFallback = [
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
  ];

  /// Einheitlicher Radius — NAV ist nahezu rechtwinklig.
  static const double _radius = 3;

  // ── Hell ────────────────────────────────────────────────────────────
  static ThemeData light() {
    const flaeche = Colors.white; // Listen/Inhalte sind weiß
    const hintergrund = Color(0xFFF3F3F3); // Rahmen um den Inhalt
    const linie = Color(0xFFD4D4D4);
    const leiste = Color(0xFFF5F6F7); // Ribbon/Kopfzeile

    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: navBlau,
      onPrimary: Colors.white,
      primaryContainer: navAuswahlHell,
      onPrimaryContainer: Color(0xFF0B3A63),
      secondary: navLink,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE3EFFA),
      onSecondaryContainer: Color(0xFF0B3A63),
      error: Color(0xFFB4232A),
      onError: Colors.white,
      surface: flaeche,
      onSurface: Color(0xFF1A1A1A),
      onSurfaceVariant: Color(0xFF5A5A5A),
      surfaceContainerHighest: Color(0xFFEDEDED),
      outline: linie,
      outlineVariant: Color(0xFFE2E2E2),
    );

    return _basis(
      colorScheme: colorScheme,
      scaffold: hintergrund,
      leiste: leiste,
      linie: linie,
      auswahl: navAuswahlHell,
      karte: flaeche,
    );
  }

  // ── Dunkel ──────────────────────────────────────────────────────────
  static ThemeData dark() {
    const flaeche = Color(0xFF252526); // Inhaltsflächen
    const hintergrund = Color(0xFF1E1E1E); // Rahmen um den Inhalt
    const linie = Color(0xFF3C3C3C);
    const leiste = Color(0xFF2B2B2C); // Ribbon/Kopfzeile

    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: navBlauHell,
      onPrimary: Color(0xFF06243D),
      primaryContainer: navAuswahlDunkel,
      onPrimaryContainer: Color(0xFFD6E9FA),
      secondary: Color(0xFF6FB4E8),
      onSecondary: Color(0xFF06243D),
      secondaryContainer: Color(0xFF1B3B57),
      onSecondaryContainer: Color(0xFFD6E9FA),
      error: Color(0xFFEF6B6B),
      onError: Color(0xFF3B0709),
      surface: flaeche,
      onSurface: Color(0xFFE8E8E8),
      onSurfaceVariant: Color(0xFFA8A8A8),
      surfaceContainerHighest: Color(0xFF2F2F30),
      outline: linie,
      outlineVariant: Color(0xFF343435),
    );

    return _basis(
      colorScheme: colorScheme,
      scaffold: hintergrund,
      leiste: leiste,
      linie: linie,
      auswahl: navAuswahlDunkel,
      karte: flaeche,
    );
  }

  // ── Gemeinsamer Aufbau ──────────────────────────────────────────────
  static ThemeData _basis({
    required ColorScheme colorScheme,
    required Color scaffold,
    required Color leiste,
    required Color linie,
    required Color auswahl,
    required Color karte,
  }) {
    final radius = BorderRadius.circular(_radius);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffold,
      fontFamily: _schrift,
      fontFamilyFallback: _schriftFallback,
      // Auf dem Desktop automatisch kompakt (NAV-Dichte), auf dem Tablet
      // bleiben die Tippflächen groß genug.
      visualDensity: VisualDensity.adaptivePlatformDensity,

      // Kopfzeile wie das NAV-Ribbon: ruhige Fläche, klare Unterkante.
      appBarTheme: AppBarTheme(
        backgroundColor: leiste,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: linie)),
        titleTextStyle: TextStyle(
          fontFamily: _schrift,
          fontFamilyFallback: _schriftFallback,
          color: colorScheme.primary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Karten sind in NAV eher „Bereiche": kantig, mit dünnem Rand.
      cardTheme: CardThemeData(
        color: karte,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 3),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: linie),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: linie,
        thickness: 1,
        space: 1,
      ),

      // Listen dicht wie ein NAV-Grid.
      listTileTheme: ListTileThemeData(
        dense: true,
        selectedTileColor: auswahl,
        selectedColor: colorScheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: radius),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      ),

      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(colorScheme.surfaceContainerHighest),
        headingTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
          fontSize: 13,
        ),
        dataTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 13,
        ),
        dividerThickness: 1,
        horizontalMargin: 10,
        columnSpacing: 18,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        dividerColor: linie,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.brightness == Brightness.dark
              ? const Color(0xFF3A3A3B)
              : const Color(0xFFFFFFE1), // NAV-Gelb wie Windows-Tooltips
          border: Border.all(color: linie),
          borderRadius: BorderRadius.circular(2),
        ),
        textStyle: TextStyle(
          color: colorScheme.brightness == Brightness.dark
              ? const Color(0xFFE8E8E8)
              : const Color(0xFF1A1A1A),
          fontSize: 12,
        ),
      ),
    ).copyWith(
      inputDecorationTheme: _eingabefelder(colorScheme, linie),
      filledButtonTheme: _filledButtons(),
      outlinedButtonTheme: _outlinedButtons(linie),
      textButtonTheme: _textButtons(),
      chipTheme: _chips(colorScheme, linie),
      dialogTheme: _dialoge(colorScheme, linie),
      popupMenuTheme: _popupMenus(colorScheme, linie),
      snackBarTheme: _snackBars(colorScheme),
      segmentedButtonTheme: _segmente(colorScheme, linie),
    );
  }

  static InputDecorationTheme _eingabefelder(
    ColorScheme colors,
    Color linie,
  ) {
    OutlineInputBorder rand(Color farbe, [double breite = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: farbe, width: breite),
        );
    return InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: rand(linie),
      enabledBorder: rand(linie),
      focusedBorder: rand(colors.primary, 1.6),
      errorBorder: rand(colors.error),
      focusedErrorBorder: rand(colors.error, 1.6),
      labelStyle: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
      hintStyle: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
    );
  }

  static FilledButtonThemeData _filledButtons() {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtons(Color linie) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
        side: BorderSide(color: linie),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }

  static TextButtonThemeData _textButtons() {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: navLink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }

  static ChipThemeData _chips(ColorScheme colors, Color linie) {
    return ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: BorderSide(color: linie),
      ),
      backgroundColor: colors.surfaceContainerHighest,
      labelStyle: TextStyle(fontSize: 12, color: colors.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    );
  }

  static DialogThemeData _dialoge(ColorScheme colors, Color linie) {
    return DialogThemeData(
      backgroundColor: colors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: linie),
      ),
      titleTextStyle: TextStyle(
        color: colors.primary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(color: colors.onSurface, fontSize: 14),
    );
  }

  static PopupMenuThemeData _popupMenus(ColorScheme colors, Color linie) {
    return PopupMenuThemeData(
      color: colors.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: BorderSide(color: linie),
      ),
      textStyle: TextStyle(color: colors.onSurface, fontSize: 13),
    );
  }

  static SnackBarThemeData _snackBars(ColorScheme colors) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
      backgroundColor: colors.brightness == Brightness.dark
          ? const Color(0xFF3A3A3B)
          : const Color(0xFF303030),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
    );
  }

  static SegmentedButtonThemeData _segmente(ColorScheme colors, Color linie) {
    return SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
            side: BorderSide(color: linie),
          ),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
