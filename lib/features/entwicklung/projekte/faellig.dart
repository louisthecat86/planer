import '../../../core/database/database.dart';
import 'projekt_modell.dart';

// „Fällig bis" eines Verlaufseintrags. Das Feld ist frei geschrieben — ein
// Datum („30.11.2026", „30.11."), eine Kalenderwoche („KW 48",
// „KW 48/2026") oder ein Satz („nach der Verkostung"). Was sich als Tag
// lesen lässt, kann überfällig werden; alles andere steht einfach da.

/// Wie viele Einträge offen sind und wie viele davon überfällig.
typedef OffeneEintraege = ({int offen, int ueberfaellig});

final _iso = RegExp(r'(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)');
final _datum = RegExp(
  r'(?<![\d.,])(\d{1,2})\.(\d{1,2})(?:\.(\d{4}|\d{2})?)?(?![\d,])',
);
final _woche = RegExp(
  r'\b(?:KW|Kalenderwoche)\.?\s*(\d{1,2})'
  r'(?:\s*[/.\-]\s*(\d{4}|\d{2})|\s+(\d{4}))?(?!\d)',
  caseSensitive: false,
);

/// Der letzte Tag, bis zu dem [text] reicht — null, wenn darin weder ein
/// Datum noch eine Kalenderwoche steht. Eine Woche reicht bis zu ihrem
/// Sonntag. Fehlt das Jahr, gilt das, mit dem der Tag [bezug] (dem Datum
/// des Eintrags) am nächsten liegt: „10.01." an einem Eintrag vom
/// 20.12.2026 ist der 10.01.2027.
DateTime? faelligAm(String? text, {required DateTime bezug}) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return null;
  if (_iso.firstMatch(t) case final m?) {
    final tag = _tag(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    if (tag != null) return tag;
  }
  for (final m in _datum.allMatches(t)) {
    final tag = int.parse(m[1]!);
    final monat = int.parse(m[2]!);
    final jahr = m[3];
    final d = jahr != null
        ? _tag(_jahr(jahr), monat, tag)
        : _amNaechsten(bezug, (j) => _tag(j, monat, tag));
    if (d != null) return d;
  }
  for (final m in _woche.allMatches(t)) {
    final woche = int.parse(m[1]!);
    final jahr = m[2] ?? m[3];
    final d = jahr != null
        ? _wochenende(_jahr(jahr), woche)
        : _amNaechsten(bezug, (j) => _wochenende(j, woche));
    if (d != null) return d;
  }
  return null;
}

/// Ob „Fällig bis" [text] am Tag [heute] vorbei ist — ohne lesbaren Tag
/// nie.
bool istUeberfaellig(
  String? text, {
  required DateTime bezug,
  required DateTime heute,
}) {
  final tag = faelligAm(text, bezug: bezug);
  return tag != null &&
      tag.isBefore(DateTime(heute.year, heute.month, heute.day));
}

/// Ob der Eintrag [e] offen und am Tag [heute] überfällig ist.
bool eintragUeberfaellig(ProjektEintrag e, {required DateTime heute}) =>
    EintragStatus.aus(e.status) == EintragStatus.offen &&
    istUeberfaellig(e.ziel, bezug: e.datum, heute: heute);

/// Die offenen unter [eintraege] — und wie viele davon am Tag [heute]
/// überfällig sind.
OffeneEintraege offeneZaehlen(
  Iterable<ProjektEintrag> eintraege, {
  required DateTime heute,
}) {
  var offen = 0;
  var ueberfaellig = 0;
  for (final e in eintraege) {
    if (EintragStatus.aus(e.status) != EintragStatus.offen) continue;
    offen++;
    if (istUeberfaellig(e.ziel, bezug: e.datum, heute: heute)) {
      ueberfaellig++;
    }
  }
  return (offen: offen, ueberfaellig: ueberfaellig);
}

/// Je Projekt (ID) die offenen Einträge — Projekte ohne offene fehlen.
Map<String, OffeneEintraege> offeneJeProjekt(
  Iterable<ProjektEintrag> eintraege, {
  required DateTime heute,
}) {
  final jeProjekt = <String, List<ProjektEintrag>>{};
  for (final e in eintraege) {
    if (EintragStatus.aus(e.status) != EintragStatus.offen) continue;
    (jeProjekt[e.projektId] ??= []).add(e);
  }
  return {
    for (final MapEntry(key: id, value: liste) in jeProjekt.entries)
      id: offeneZaehlen(liste, heute: heute),
  };
}

/// „2 offene Einträge, 1 überfällig" — mit [imVerlauf] „2 offene Einträge
/// im Verlauf, 1 überfällig".
String offeneEintraegeText(OffeneEintraege o, {bool imVerlauf = false}) {
  final basis =
      o.offen == 1 ? '1 offener Eintrag' : '${o.offen} offene Einträge';
  final ort = imVerlauf ? ' im Verlauf' : '';
  if (o.ueberfaellig <= 0) return '$basis$ort';
  if (o.offen == 1) return '$basis$ort, überfällig';
  return '$basis$ort, ${o.ueberfaellig} überfällig';
}

DateTime? _tag(int jahr, int monat, int tag) {
  if (monat < 1 || monat > 12 || tag < 1 || tag > 31) return null;
  final d = DateTime(jahr, monat, tag);
  return d.month == monat ? d : null;
}

int _jahr(String text) =>
    text.length == 2 ? 2000 + int.parse(text) : int.parse(text);

/// Der Sonntag der Kalenderwoche [woche] (nach ISO 8601: Woche 1 ist die
/// mit dem 4. Januar) — null, wenn es sie in [jahr] nicht gibt.
DateTime? _wochenende(int jahr, int woche) {
  if (woche < 1 || woche > 53) return null;
  final vierter = DateTime(jahr, 1, 4);
  final montag =
      DateTime(jahr, 1, 4 - (vierter.weekday - 1) + (woche - 1) * 7);
  // Die 53. Woche gibt es nur, wenn ihr Donnerstag noch im Jahr liegt.
  final donnerstag = DateTime(montag.year, montag.month, montag.day + 3);
  if (donnerstag.year != jahr) return null;
  return DateTime(montag.year, montag.month, montag.day + 6);
}

/// Der Tag aus dem Jahr vor, von oder nach [bezug], der [bezug] am
/// nächsten liegt — bei gleichem Abstand der spätere.
DateTime? _amNaechsten(DateTime bezug, DateTime? Function(int jahr) tag) {
  final b = DateTime(bezug.year, bezug.month, bezug.day);
  DateTime? bester;
  int? abstand;
  for (final jahr in [bezug.year - 1, bezug.year, bezug.year + 1]) {
    final d = tag(jahr);
    if (d == null) continue;
    final a = d.difference(b).inHours.abs();
    if (abstand == null || a <= abstand) {
      bester = d;
      abstand = a;
    }
  }
  return bester;
}
