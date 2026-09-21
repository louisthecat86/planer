/// ISO-8601-Kalenderwoche — die einzige Berechnung in der App.
///
/// Vorher gab es drei eigene Fassungen: im Wochenboard, in der
/// Produktionserfassung und im Wochenarchiv. Alle drei rechneten in
/// Ortszeit und zählten die Tage seit dem 1. Januar mit
/// `difference().inDays`. Zwischen dem 1. Januar (Winterzeit) und einem
/// Tag im Sommer fehlt aber eine Stunde — aus 266 Tagen wurden 265 Tage
/// und 23 Stunden, `inDays` schnitt auf 265 ab, und die Division durch 7
/// landete eine Woche zu früh. Betroffen war etwa jede siebte Woche im
/// Sommerhalbjahr, darunter der 21.09.2026 (KW 39, angezeigt als KW 38).
///
/// Gerechnet wird deshalb in UTC, wo es keine Zeitumstellung gibt.
///
/// Bewusst ohne Flutter-Abhängigkeit, damit auch Dienste und Isolates sie
/// benutzen können.
library;

/// Kalenderwoche (1..53) nach ISO 8601.
///
/// Woche 1 ist die Woche mit dem ersten Donnerstag des Jahres. Deshalb
/// kann der 29.12.2025 schon in KW 1/2026 liegen und der 01.01.2027 noch
/// in KW 53/2026 — maßgeblich ist der Donnerstag derselben Woche.
int isoKalenderwoche(DateTime datum) {
  final donnerstag = _donnerstagDerWoche(datum);
  final jahresbeginn = DateTime.utc(donnerstag.year);
  return 1 + donnerstag.difference(jahresbeginn).inDays ~/ 7;
}

/// Das Jahr, zu dem die Kalenderwoche gehört.
///
/// Weicht am Jahreswechsel vom Kalenderjahr ab: Der 01.01.2027 gehört zu
/// KW 53 des Jahres 2026. Wer „KW 53" ohne dieses Jahr anzeigt, zeigt
/// eine Woche, die es 2027 nicht gibt.
int isoKalenderjahr(DateTime datum) => _donnerstagDerWoche(datum).year;

DateTime _donnerstagDerWoche(DateTime datum) {
  final tag = DateTime.utc(datum.year, datum.month, datum.day);
  return tag.add(Duration(days: DateTime.thursday - tag.weekday));
}
