/// Zahlen und Daten für die Anzeige — deutsch und an einer Stelle.
///
/// Vorher formatierte fast jede Ansicht selbst: rund zehn eigene
/// kg-Formate und ein Dutzend Datumsformate. Das Board schrieb
/// „12.500 kg", der Artikel „17195.7 kg" — mit Punkt statt Komma und ohne
/// Tausenderpunkt.
///
/// Bewusst ohne intl: Dessen Sprachdaten initialisiert die App nicht, und
/// für Tausenderpunkt und Komma braucht es sie nicht. Ohne
/// Flutter-Abhängigkeit, damit auch Dienste sie benutzen können.
library;

abstract final class Format {
  static const List<String> wochentage = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  static const List<String> wochentageKurz = [
    'Mo',
    'Di',
    'Mi',
    'Do',
    'Fr',
    'Sa',
    'So',
  ];

  static const List<String> monate = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];

  // ── Zahlen ──────────────────────────────────────────────────────────

  /// „17.195,7" — mit genau [nachkomma] Stellen, Komma und Tausenderpunkt.
  static String zahl(num wert, {int nachkomma = 0}) {
    if (!wert.isFinite) return '—';
    final text = wert.abs().toStringAsFixed(nachkomma);
    final teile = text.split('.');
    final ganz = _tausender(teile.first);
    final rest = teile.length > 1 ? ',${teile[1]}' : '';
    // Kein „-0" oder „-0,0": negativ nur, wenn nach dem Runden etwas
    // übrig bleibt.
    final negativ = wert < 0 && text.replaceAll(RegExp('[0.]'), '').isNotEmpty;
    return '${negativ ? '-' : ''}$ganz$rest';
  }

  /// Eine Menge in Kilogramm, ohne Einheit: ab 100 ganze Zahlen, darunter
  /// eine Nachkommastelle, wenn es eine gibt — „2.156", „68,3", „4".
  ///
  /// So rechnet man in der Produktion: Bei großen Mengen stört die
  /// Nachkommastelle, bei kleinen zählt sie.
  static String menge(num kg) {
    if (!kg.isFinite) return '—';
    if (kg.abs() >= 100) return zahl(kg);
    final eineStelle = zahl(kg, nachkomma: 1);
    return eineStelle.endsWith(',0')
        ? eineStelle.substring(0, eineStelle.length - 2)
        : eineStelle;
  }

  /// „2.156 kg", „68,3 kg" — [menge] mit Einheit.
  static String kg(num kg) => '${menge(kg)} kg';

  /// „89,7 %" — [anteil] als Bruchteil (0,897), mit [nachkomma] Stellen.
  static String prozent(double anteil, {int nachkomma = 1}) =>
      '${zahl(anteil * 100, nachkomma: nachkomma)} %';

  // ── Daten ───────────────────────────────────────────────────────────

  /// „08.10.2026"
  static String datum(DateTime d) => '${datumKurz(d)}${d.year}';

  /// „08.10."
  static String datumKurz(DateTime d) =>
      '${_zwei(d.day)}.${_zwei(d.month)}.';

  /// „Do 08.10."
  static String tagKurz(DateTime d) =>
      '${wochentageKurz[d.weekday - 1]} ${datumKurz(d)}';

  /// „Donnerstag, 8. Oktober 2026"
  static String datumLang(DateTime d) =>
      '${wochentage[d.weekday - 1]}, ${d.day}. ${monate[d.month - 1]} '
      '${d.year}';

  /// „07:41"
  static String uhrzeit(DateTime d) => '${_zwei(d.hour)}:${_zwei(d.minute)}';

  static String _zwei(int n) => n.toString().padLeft(2, '0');

  /// Tausenderpunkte in eine Ziffernfolge setzen: „17195" → „17.195".
  static String _tausender(String ziffern) {
    final b = StringBuffer();
    for (var i = 0; i < ziffern.length; i++) {
      if (i > 0 && (ziffern.length - i) % 3 == 0) b.write('.');
      b.write(ziffern[i]);
    }
    return b.toString();
  }
}
