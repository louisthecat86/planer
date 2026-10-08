import 'package:flutter/material.dart';

/// Feste Maße der Oberfläche.
///
/// Alle Ansichten nehmen diese Werte statt eigener Zahlen. Vorher steckten
/// im Code 14 verschiedene Eckenradien zwischen 2 und 20 — dazu Schatten
/// und Verläufe. Das Theme sagt seit jeher „Navision": kantig, dünne
/// Linien, keine Schatten. Hier steht, wie das in Zahlen aussieht.
abstract final class AppMasse {
  /// Eckenradius — Navision ist nahezu rechtwinklig.
  static const double radius = 3;

  /// [radius] als BorderRadius, für Rahmen und Flächen.
  static const BorderRadius ecken = BorderRadius.all(Radius.circular(radius));

  /// Kleine Marken (Abteilungskürzel, Status) — noch etwas kantiger.
  static const BorderRadius eckenKlein = BorderRadius.all(Radius.circular(2));

  /// Höhe der Kopfzeile eines Bereichs.
  static const double kopfHoehe = 40;

  /// Breite der Navigationsleiste — offen und eingeklappt.
  static const double leisteBreit = 232;
  static const double leisteSchmal = 56;
}

/// Farben, die das [ColorScheme] nicht kennt: Statusfarben und die Fläche
/// der Kopfzeilen und der Navigationsleiste.
///
/// Statusfarben sind Signale, keine Dekoration: grün = in Ordnung oder
/// erledigt, orange = Achtung, rot = Problem, blau = Hinweis. Jede gibt es
/// als Schrift- und Symbolfarbe und als blasse Fläche dahinter — jeweils
/// passend für hell und dunkel. Vorher gab es Grün in vier und Orange in
/// fünf Tönen, und im Dunkelmodus blieben manche hell.
@immutable
class AppFarben extends ThemeExtension<AppFarben> {
  const AppFarben({
    required this.leiste,
    required this.ok,
    required this.okFlaeche,
    required this.warnung,
    required this.warnungFlaeche,
    required this.fehler,
    required this.fehlerFlaeche,
    required this.info,
    required this.infoFlaeche,
  });

  /// Kopfzeilen und Navigationsleiste (wie das Ribbon in Navision).
  final Color leiste;

  /// In Ordnung, erledigt, gut gefüllt.
  final Color ok;
  final Color okFlaeche;

  /// Achtung: liegt zurück, fast voll, unvollständig.
  final Color warnung;
  final Color warnungFlaeche;

  /// Problem: überbucht, fehlt, Fehler.
  final Color fehler;
  final Color fehlerFlaeche;

  /// Hinweis ohne Wertung.
  final Color info;
  final Color infoFlaeche;

  static const AppFarben hell = AppFarben(
    leiste: Color(0xFFF5F6F7),
    ok: Color(0xFF2E7D32),
    okFlaeche: Color(0xFFE7F2E8),
    warnung: Color(0xFFB45309),
    warnungFlaeche: Color(0xFFFDF2E4),
    fehler: Color(0xFFB4232A),
    fehlerFlaeche: Color(0xFFFBEAEA),
    info: Color(0xFF1E5B94),
    infoFlaeche: Color(0xFFE6F0FA),
  );

  static const AppFarben dunkel = AppFarben(
    leiste: Color(0xFF2B2B2C),
    ok: Color(0xFF7CC47F),
    okFlaeche: Color(0xFF1F3322),
    warnung: Color(0xFFF0A955),
    warnungFlaeche: Color(0xFF3A2A16),
    fehler: Color(0xFFEF6B6B),
    fehlerFlaeche: Color(0xFF3B1E1F),
    info: Color(0xFF6FB4E8),
    infoFlaeche: Color(0xFF16344F),
  );

  /// Die Farben zum aktuellen Theme.
  static AppFarben von(BuildContext context) =>
      Theme.of(context).extension<AppFarben>() ?? hell;

  @override
  AppFarben copyWith({
    Color? leiste,
    Color? ok,
    Color? okFlaeche,
    Color? warnung,
    Color? warnungFlaeche,
    Color? fehler,
    Color? fehlerFlaeche,
    Color? info,
    Color? infoFlaeche,
  }) {
    return AppFarben(
      leiste: leiste ?? this.leiste,
      ok: ok ?? this.ok,
      okFlaeche: okFlaeche ?? this.okFlaeche,
      warnung: warnung ?? this.warnung,
      warnungFlaeche: warnungFlaeche ?? this.warnungFlaeche,
      fehler: fehler ?? this.fehler,
      fehlerFlaeche: fehlerFlaeche ?? this.fehlerFlaeche,
      info: info ?? this.info,
      infoFlaeche: infoFlaeche ?? this.infoFlaeche,
    );
  }

  @override
  AppFarben lerp(covariant ThemeExtension<AppFarben>? other, double t) {
    if (other is! AppFarben) return this;
    Color mische(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppFarben(
      leiste: mische(leiste, other.leiste),
      ok: mische(ok, other.ok),
      okFlaeche: mische(okFlaeche, other.okFlaeche),
      warnung: mische(warnung, other.warnung),
      warnungFlaeche: mische(warnungFlaeche, other.warnungFlaeche),
      fehler: mische(fehler, other.fehler),
      fehlerFlaeche: mische(fehlerFlaeche, other.fehlerFlaeche),
      info: mische(info, other.info),
      infoFlaeche: mische(infoFlaeche, other.infoFlaeche),
    );
  }
}
