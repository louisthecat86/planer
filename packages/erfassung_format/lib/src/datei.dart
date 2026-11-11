import 'dart:convert';

/// Woran eine Datei des Austauschs zu erkennen ist.
const String kFormatName = 'planer-erfassung';

/// Die höchste Fassung des Formats, die diese App und dieser Planer lesen.
/// Eine Datei aus einer neueren Fassung lesen sie nicht — und sagen das,
/// statt halb zu lesen.
///
/// 1 → Produktionen und Maschineneinstellungen
/// 2 → ein Ergebnis kann Fotos enthalten
const int kFormatVersion = 2;

/// Die Fassung ohne Fotos. So schreibt weiter, wer keine Fotos mitgibt:
/// Ein Planer oder eine App auf älterem Stand liest die Datei dann wie
/// bisher.
const int kFormatVersionOhneFotos = 1;

/// Was in einer Datei steht.
enum DateiArt {
  /// Vom Planer fürs Handy.
  paket('paket'),

  /// Vom Handy zurück an den Planer.
  ergebnis('ergebnis');

  const DateiArt(this.schluessel);

  final String schluessel;
}

/// Eine Datei, die sich nicht lesen lässt — mit einem Satz, der sagt,
/// warum.
class FormatFehler implements Exception {
  const FormatFehler(this.meldung);

  final String meldung;

  @override
  String toString() => meldung;
}

/// Ein Objekt aus der Datei.
typedef JsonObjekt = Map<String, Object?>;

/// Liest den Text einer Datei: prüft, ob sie aus dem Austausch stammt,
/// welche Art sie ist und ob die Fassung passt.
JsonObjekt dateiLesen(String text, DateiArt erwartet) {
  final Object? daten;
  try {
    daten = jsonDecode(text);
  } on FormatException {
    throw const FormatFehler(
      'Die Datei ist keine Erfassungsdatei des Produktions Planers.',
    );
  }
  if (daten is! JsonObjekt || daten['format'] != kFormatName) {
    throw const FormatFehler(
      'Die Datei ist keine Erfassungsdatei des Produktions Planers.',
    );
  }
  final art = daten['art'];
  if (art != erwartet.schluessel) {
    throw FormatFehler(
      erwartet == DateiArt.paket
          ? 'Das ist ein Ergebnis vom Handy — es gehört in den Planer '
              '(Einstellungen → Handy-Erfassung → Ergebnis einlesen).'
          : 'Das ist ein Paket für das Handy, kein Ergebnis — es gehört '
              'in die App „Planer Erfassung".',
    );
  }
  final version = daten['version'];
  if (version is! int || version > kFormatVersion) {
    throw const FormatFehler(
      'Die Datei stammt aus einer neueren Fassung — bitte Planer und App '
      'auf denselben Stand bringen.',
    );
  }
  return daten;
}

/// Welche Art von Datei [text] ist — null, wenn keine des Austauschs.
DateiArt? dateiArtVon(String text) {
  try {
    final daten = jsonDecode(text);
    if (daten is! JsonObjekt || daten['format'] != kFormatName) return null;
    for (final a in DateiArt.values) {
      if (daten['art'] == a.schluessel) return a;
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// Der Kopf jeder Datei.
JsonObjekt dateiKopf(
  DateiArt art, {
  int version = kFormatVersionOhneFotos,
}) =>
    {
      'format': kFormatName,
      'art': art.schluessel,
      'version': version,
    };

// ── Lesen einzelner Werte ─────────────────────────────────────────────
//
// Fehlt etwas Nötiges oder hat es den falschen Typ, gibt es einen
// FormatFehler mit Ort — nie einen Absturz mitten in der Datei.

/// Ein Pflichttext.
String jsonText(JsonObjekt j, String schluessel, String wo) {
  final v = j[schluessel];
  if (v is String) return v;
  throw FormatFehler('Die Datei ist beschädigt: In $wo fehlt „$schluessel".');
}

/// Ein freiwilliger Text.
String? jsonTextOder(JsonObjekt j, String schluessel) {
  final v = j[schluessel];
  return v is String ? v : null;
}

/// Eine freiwillige Zahl.
double? jsonZahlOder(JsonObjekt j, String schluessel) {
  final v = j[schluessel];
  return v is num ? v.toDouble() : null;
}

/// Eine Pflichtzahl.
double jsonZahl(JsonObjekt j, String schluessel, String wo) =>
    jsonZahlOder(j, schluessel) ??
    (throw FormatFehler(
      'Die Datei ist beschädigt: In $wo fehlt „$schluessel".',
    ));

/// Eine freiwillige ganze Zahl.
int? jsonGanzOder(JsonObjekt j, String schluessel) {
  final v = j[schluessel];
  return v is int ? v : null;
}

/// Eine Liste von Objekten — leer, wenn sie fehlt.
List<JsonObjekt> jsonListe(JsonObjekt j, String schluessel, String wo) {
  final v = j[schluessel];
  if (v == null) return const [];
  if (v is! List) {
    throw FormatFehler('Die Datei ist beschädigt: „$schluessel" in $wo.');
  }
  return [
    for (final e in v)
      if (e is JsonObjekt)
        e
      else
        throw FormatFehler('Die Datei ist beschädigt: „$schluessel" in $wo.'),
  ];
}

/// Ein freiwilliges Objekt.
JsonObjekt? jsonObjektOder(JsonObjekt j, String schluessel) {
  final v = j[schluessel];
  return v is JsonObjekt ? v : null;
}

/// Ein Zeitpunkt (ISO 8601).
DateTime jsonZeitpunkt(JsonObjekt j, String schluessel, String wo) {
  final t = DateTime.tryParse(jsonText(j, schluessel, wo));
  if (t == null) {
    throw FormatFehler('Die Datei ist beschädigt: „$schluessel" in $wo.');
  }
  return t;
}

/// Ein Tag („2026-11-09").
DateTime jsonTag(JsonObjekt j, String schluessel, String wo) {
  final t = DateTime.tryParse(jsonText(j, schluessel, wo));
  if (t == null) {
    throw FormatFehler('Die Datei ist beschädigt: „$schluessel" in $wo.');
  }
  return DateTime(t.year, t.month, t.day);
}

/// Schreibt die Datei — kompakt, eine Zeile.
String dateiText(JsonObjekt daten) => jsonEncode(daten);

/// „2026-11-09".
String tagText(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// „2026-11-09_1745" — für Dateinamen.
String zeitstempelText(DateTime d) => '${tagText(d)}_'
    '${d.hour.toString().padLeft(2, '0')}'
    '${d.minute.toString().padLeft(2, '0')}';
