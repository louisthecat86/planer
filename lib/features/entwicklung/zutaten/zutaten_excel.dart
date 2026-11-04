import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/database/database.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/krypto.dart';
import '../../../core/utils/xlsx_leser.dart';
import '../../../core/utils/xlsx_schreiber.dart';
import '../daten/entwicklung_repository.dart';
import '../entwicklung_format.dart';
import '../rechenkern/rechen_modell.dart';

// Der Zutatenkatalog als Excel-Mappe — hin und zurück.
//
// Die Mappe ist zum Weiterarbeiten da: exportieren, in Excel pflegen,
// wieder importieren und zwischendurch auch in der App ändern. Damit dabei
// nichts verloren geht, steht in jeder Zeile neben der ID der „Stand": ein
// Fingerabdruck der Werte beim Export. Beim Import zeigt er, wo sich eine
// Zutat seither geändert hat — in der Datei, in der App oder auf beiden
// Seiten.
//
// Die Regeln:
// - Eine Zeile findet ihre Zutat über die ID, ohne ID über die
//   Artikelnummer, ohne Artikelnummer über den Namen. Ohne Treffer ist sie
//   neu.
// - Eine leere Zelle leert den Wert. Eine fehlende Spalte lässt ihn, wie er
//   ist; Spalten, die die App nicht kennt, liest sie nicht.
// - Gelöscht wird über die Mappe nichts.

// ═══════════════════════════════════════════════════════════════════════════
// Felder und Werte
// ═══════════════════════════════════════════════════════════════════════════

enum _Art { text, janein, zahl, tierart, allergene }

/// Die Angaben einer Zutat, die in der Mappe stehen.
enum ZutatFeld {
  name('Name', _Art.text),
  etikettName('Name auf dem Etikett', _Art.text),
  artikelnummer('Artikelnummer', _Art.text),
  istFleisch('Fleisch', _Art.janein),
  tierart('Tierart', _Art.tierart),
  bindegewebe('Bindegewebe', _Art.zahl),
  istWasser('Wasser/Eis', _Art.janein),
  quidPflicht('QUID', _Art.janein),
  unterzutaten('Unterzutaten', _Art.text),
  verarbeitungshilfsstoffe('Verarbeitungshilfsstoffe', _Art.text),
  allergene('Allergene', _Art.allergene),
  energieKj('Energie kJ', _Art.zahl),
  energieKcal('Energie kcal', _Art.zahl),
  fett('Fett', _Art.zahl),
  gesaettigt('davon gesättigt', _Art.zahl),
  kohlenhydrate('Kohlenhydrate', _Art.zahl),
  zucker('davon Zucker', _Art.zahl),
  eiweiss('Eiweiß', _Art.zahl),
  salz('Salz', _Art.zahl),
  wasser('Wasser', _Art.zahl),
  asche('Asche', _Art.zahl),
  beffe('BEFFE', _Art.zahl),
  notiz('Notiz', _Art.text);

  const ZutatFeld(this.label, this._art);

  /// Für die Vorschau: „Fett", „Allergene".
  final String label;

  final _Art _art;
}

final RegExp _steuerzeichen = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');

/// Ein Text, wie er verglichen wird: Zeilenenden als „\n", ohne
/// Steuerzeichen und ohne Leerraum am Rand — leer heißt null.
String? _text(String? s) {
  if (s == null) return null;
  final t = s
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(_steuerzeichen, '')
      .trim();
  return t.isEmpty ? null : t;
}

double? _zahl(double? wert) => wert == null || !wert.isFinite ? null : wert;

/// Die Allergene aus der Datenbank, gleich gemacht: nur bekannte, in der
/// Reihenfolge der Liste — und „Keine" nur, wenn sonst nichts dasteht. Ein
/// Allergen neben „Keine" ist die vorsichtigere Angabe.
String? _allergene(String? gespeichert) {
  final gesetzt = merkmaleAusText(gespeichert);
  final bekannt = [
    for (final m in kAllergene)
      if (gesetzt.contains(m.dbValue)) m.dbValue,
  ];
  if (bekannt.length > 1) bekannt.remove(kAllergenKeine);
  return merkmaleZuText(bekannt, kAllergene);
}

/// Eine Zahl, wie sie verglichen wird: auf sechs Nachkommastellen. So stört
/// es nicht, dass eine Tabelle 1,1 als „1.1000000000000001" speichert.
String _zahlSchluessel(double wert) {
  final t = wert.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
  return t == '-0' ? '0' : t;
}

/// Die Werte einer Zutat, gleich gemacht für den Vergleich zwischen App und
/// Mappe: Texte ohne Leerraum am Rand (leer heißt null), Allergene in der
/// Reihenfolge der Liste, Tierart und Bindegewebe nur bei Fleisch — wie im
/// Fenster der Zutat.
class ZutatWerte {
  const ZutatWerte._(this._werte);

  /// Eine Zutat ohne jede Angabe — die Grundlage einer neuen.
  static const ZutatWerte leer = ZutatWerte._(<ZutatFeld, Object?>{});

  /// Die Werte von [z].
  factory ZutatWerte.aus(Zutat z) => ZutatWerte._({
        ZutatFeld.name: _text(z.name),
        ZutatFeld.etikettName: _text(z.etikettName),
        ZutatFeld.artikelnummer: _text(z.artikelnummer),
        ZutatFeld.istFleisch: z.istFleisch,
        ZutatFeld.tierart: Tierart.aus(z.tierart)?.schluessel,
        ZutatFeld.bindegewebe: _zahl(z.bindegewebe),
        ZutatFeld.istWasser: z.istWasser,
        ZutatFeld.quidPflicht: z.quidPflicht,
        ZutatFeld.unterzutaten: _text(z.unterzutaten),
        ZutatFeld.verarbeitungshilfsstoffe: _text(z.verarbeitungshilfsstoffe),
        ZutatFeld.allergene: _allergene(z.allergene),
        ZutatFeld.energieKj: _zahl(z.energieKj),
        ZutatFeld.energieKcal: _zahl(z.energieKcal),
        ZutatFeld.fett: _zahl(z.fett),
        ZutatFeld.gesaettigt: _zahl(z.gesaettigteFettsaeuren),
        ZutatFeld.kohlenhydrate: _zahl(z.kohlenhydrate),
        ZutatFeld.zucker: _zahl(z.zucker),
        ZutatFeld.eiweiss: _zahl(z.eiweiss),
        ZutatFeld.salz: _zahl(z.salz),
        ZutatFeld.wasser: _zahl(z.wasser),
        ZutatFeld.asche: _zahl(z.asche),
        ZutatFeld.beffe: _zahl(z.beffe),
        ZutatFeld.notiz: _text(z.notiz),
      })._geregelt();

  final Map<ZutatFeld, Object?> _werte;

  /// Der Wert von [f]: Text, Zahl (double), ja/nein (bool) — oder null.
  /// Die Tierart als Schlüssel („schwein"), die Allergene als Kommaliste
  /// wie in der Datenbank.
  Object? operator [](ZutatFeld f) =>
      _werte[f] ?? (f._art == _Art.janein ? false : null);

  bool get istFleisch => this[ZutatFeld.istFleisch] == true;
  bool get istWasser => this[ZutatFeld.istWasser] == true;
  String? get name => this[ZutatFeld.name] as String?;
  String? get artikelnummer => this[ZutatFeld.artikelnummer] as String?;

  /// Diese Werte, überschrieben mit [neu] — nur mit den Feldern, die darin
  /// stehen.
  ZutatWerte mit(Map<ZutatFeld, Object?> neu) =>
      ZutatWerte._({..._werte, ...neu})._geregelt();

  /// Ohne Fleisch keine Tierart und kein Bindegewebe — wie im Fenster.
  ZutatWerte _geregelt() {
    if (istFleisch ||
        (this[ZutatFeld.tierart] == null &&
            this[ZutatFeld.bindegewebe] == null)) {
      return this;
    }
    return ZutatWerte._({
      ..._werte,
      ZutatFeld.tierart: null,
      ZutatFeld.bindegewebe: null,
    });
  }

  static String _schluessel(Object? wert) => switch (wert) {
        null => '',
        final bool j => j ? '1' : '0',
        final double d => _zahlSchluessel(d),
        _ => '$wert',
      };

  /// Die Vorsilbe des Stands. Sie nennt die Fassung des Fingerabdrucks:
  /// Kommen später Felder dazu, gilt ein alter Stand als unbekannt statt
  /// als geändert.
  static const String standVorsilbe = 'S1-';

  /// Der Fingerabdruck der Werte — er steht beim Export in der Spalte
  /// „Stand".
  String get stand {
    final teile = [
      for (final f in ZutatFeld.values) _schluessel(this[f]),
    ];
    final summe = pruefsumme(utf8.encode(teile.join('\u001f')));
    return '$standVorsilbe${summe.substring(0, 16)}';
  }

  /// Die Felder, in denen sich diese Werte von [andere] unterscheiden.
  Set<ZutatFeld> unterschiedeZu(ZutatWerte andere) => {
        for (final f in ZutatFeld.values)
          if (_schluessel(this[f]) != _schluessel(andere[f])) f,
      };

  /// Der Wert von [f] zum Lesen: „ja", „12,5", „Senf, Sellerie",
  /// „Schwein" — leer, wenn nichts angegeben ist.
  String anzeige(ZutatFeld f) {
    final wert = this[f];
    return switch (wert) {
      null => '',
      final bool j => j ? 'ja' : 'nein',
      final double d => feldText(d),
      final String t when f == ZutatFeld.tierart => Tierart.aus(t)?.label ?? t,
      final String t when f == ZutatFeld.allergene =>
        merkmaleLabel(t, kAllergene),
      _ => '$wert',
    };
  }

  /// Für die Datenbank: alle Felder — oder nur die in [nur].
  EntwicklungZutatenCompanion companion([Set<ZutatFeld>? nur]) {
    Value<T> v<T>(ZutatFeld f) => nur == null || nur.contains(f)
        ? Value<T>(this[f] as T)
        : Value<T>.absent();
    return EntwicklungZutatenCompanion(
      name: v<String>(ZutatFeld.name),
      etikettName: v<String?>(ZutatFeld.etikettName),
      artikelnummer: v<String?>(ZutatFeld.artikelnummer),
      istFleisch: v<bool>(ZutatFeld.istFleisch),
      tierart: v<String?>(ZutatFeld.tierart),
      bindegewebe: v<double?>(ZutatFeld.bindegewebe),
      istWasser: v<bool>(ZutatFeld.istWasser),
      quidPflicht: v<bool>(ZutatFeld.quidPflicht),
      unterzutaten: v<String?>(ZutatFeld.unterzutaten),
      verarbeitungshilfsstoffe: v<String?>(ZutatFeld.verarbeitungshilfsstoffe),
      allergene: v<String?>(ZutatFeld.allergene),
      energieKj: v<double?>(ZutatFeld.energieKj),
      energieKcal: v<double?>(ZutatFeld.energieKcal),
      fett: v<double?>(ZutatFeld.fett),
      gesaettigteFettsaeuren: v<double?>(ZutatFeld.gesaettigt),
      kohlenhydrate: v<double?>(ZutatFeld.kohlenhydrate),
      zucker: v<double?>(ZutatFeld.zucker),
      eiweiss: v<double?>(ZutatFeld.eiweiss),
      salz: v<double?>(ZutatFeld.salz),
      wasser: v<double?>(ZutatFeld.wasser),
      asche: v<double?>(ZutatFeld.asche),
      beffe: v<double?>(ZutatFeld.beffe),
      notiz: v<String?>(ZutatFeld.notiz),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Spalten
// ═══════════════════════════════════════════════════════════════════════════

enum _Rolle { feld, allergen, id, stand }

/// Eine Spalte der Mappe: ein Feld, ein Allergen, die ID oder der Stand.
class _Spalte {
  const _Spalte._(
    this.rolle,
    this.kopf,
    this.breite, {
    this.feld,
    this.allergen,
    this.aliase = const [],
  });

  _Spalte.feld(
    ZutatFeld f,
    String kopf,
    double breite, {
    List<String> aliase = const [],
  }) : this._(
          _Rolle.feld,
          kopf,
          breite,
          feld: f,
          aliase: [f.label, ...aliase],
        );

  _Spalte.allergen(Merkmal m)
      : this._(
          _Rolle.allergen,
          m.dbValue == kAllergenKeine ? 'Keine Allergene' : m.label,
          m.dbValue == kAllergenKeine
              ? 10.0
              : (m.label.length > 8 ? 12.0 : 9.0),
          allergen: m.dbValue,
          aliase: m.dbValue == kAllergenKeine
              ? const ['Keine', 'Allergenfrei']
              : [m.dbValue, 'Allergen ${m.label}'],
        );

  static const _Spalte id = _Spalte._(_Rolle.id, 'ID', 38);
  static const _Spalte stand = _Spalte._(_Rolle.stand, 'Stand', 22);

  final _Rolle rolle;

  /// Die Überschrift beim Export.
  final String kopf;
  final double breite;
  final ZutatFeld? feld;

  /// Der Wert des Allergens in der Datenbank, etwa „senf".
  final String? allergen;

  /// Weitere Überschriften, an denen der Import die Spalte erkennt.
  final List<String> aliase;
}

/// Die Spalten in der Reihenfolge der Mappe — wie im Fenster der Zutat.
final List<_Spalte> _spalten = [
  _Spalte.feld(ZutatFeld.name, 'Name', 30, aliase: ['Zutat', 'Bezeichnung']),
  _Spalte.feld(
    ZutatFeld.etikettName,
    'Name auf dem Etikett',
    26,
    aliase: ['Etikett', 'Etikettname'],
  ),
  _Spalte.feld(
    ZutatFeld.artikelnummer,
    'Artikelnummer',
    15,
    aliase: ['Art.-Nr.', 'Artikel-Nr.', 'Artikelnr'],
  ),
  _Spalte.feld(ZutatFeld.istFleisch, 'Fleisch', 9),
  _Spalte.feld(ZutatFeld.tierart, 'Tierart', 18),
  _Spalte.feld(ZutatFeld.bindegewebe, 'Bindegewebe %', 13),
  _Spalte.feld(
    ZutatFeld.istWasser,
    'Wasser/Eis',
    10,
    aliase: ['Zugesetztes Wasser oder Eis', 'Wasser oder Eis'],
  ),
  _Spalte.feld(ZutatFeld.quidPflicht, 'QUID', 8),
  _Spalte.feld(ZutatFeld.unterzutaten, 'Unterzutaten', 40),
  _Spalte.feld(
    ZutatFeld.verarbeitungshilfsstoffe,
    'Verarbeitungshilfsstoffe',
    26,
    aliase: ['Hilfsstoffe'],
  ),
  for (final m in kAllergene) _Spalte.allergen(m),
  _Spalte.feld(ZutatFeld.energieKj, 'Energie kJ', 11, aliase: ['kJ']),
  _Spalte.feld(ZutatFeld.energieKcal, 'Energie kcal', 11, aliase: ['kcal']),
  _Spalte.feld(ZutatFeld.fett, 'Fett g', 10),
  _Spalte.feld(
    ZutatFeld.gesaettigt,
    'davon gesättigt g',
    12,
    aliase: [
      'gesättigt',
      'gesättigte Fettsäuren',
      'davon gesättigte Fettsäuren',
    ],
  ),
  _Spalte.feld(ZutatFeld.kohlenhydrate, 'Kohlenhydrate g', 13),
  _Spalte.feld(ZutatFeld.zucker, 'davon Zucker g', 11, aliase: ['Zucker']),
  _Spalte.feld(ZutatFeld.eiweiss, 'Eiweiß g', 10, aliase: ['Protein']),
  _Spalte.feld(ZutatFeld.salz, 'Salz g', 10),
  _Spalte.feld(ZutatFeld.wasser, 'Wasser g', 10),
  _Spalte.feld(ZutatFeld.asche, 'Asche g', 10),
  _Spalte.feld(ZutatFeld.beffe, 'BEFFE %', 10),
  _Spalte.feld(ZutatFeld.notiz, 'Notiz', 30, aliase: ['Bemerkung']),
  _Spalte.id,
  _Spalte.stand,
];

/// Eine Überschrift ohne Groß- und Kleinschreibung, Umlaute, Leer- und
/// Satzzeichen: „Eiweiß g" → „eiweissg".
String _kopfSchluessel(String s) => s
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp('[^a-z0-9]'), '');

/// Die Spalte je Schlüssel ihrer Überschriften.
final Map<String, _Spalte> _spalteNachSchluessel = {
  for (final s in _spalten)
    for (final k in [s.kopf, ...s.aliase]) _kopfSchluessel(k): s,
};

/// Die Spalte zur Überschrift [kopf] — auch ohne „je 100 g" und ohne die
/// Einheit „g" am Ende: „Fett (g/100 g)" findet die Spalte „Fett g".
_Spalte? _spalteZu(String kopf) {
  final k = _kopfSchluessel(kopf);
  if (k.isEmpty) return null;
  final ohne100 = k.replaceFirst(RegExp(r'(je|pro)?100g$'), '');
  final ohneG = ohne100.endsWith('g')
      ? ohne100.substring(0, ohne100.length - 1)
      : ohne100;
  for (final v in [k, ohne100, ohneG]) {
    final s = _spalteNachSchluessel[v];
    if (s != null) return s;
  }
  return null;
}

/// Schlüssel für Namen und Artikelnummern: ohne Groß- und Kleinschreibung
/// und doppelten Leerraum.
String _suchSchluessel(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

// ═══════════════════════════════════════════════════════════════════════════
// Export
// ═══════════════════════════════════════════════════════════════════════════

String _zwei(int n) => n.toString().padLeft(2, '0');

/// Der Vorschlag für den Dateinamen: „Zutaten_2026-11-04.xlsx".
String zutatenDateiname(DateTime stand) =>
    'Zutaten_${stand.year}-${_zwei(stand.month)}-${_zwei(stand.day)}.xlsx';

/// Der Katalog als Excel-Mappe: ein Blatt „Zutaten" mit einer Zeile je
/// Zutat (nach Namen) und ein Blatt „Hinweise". Ohne Zutaten ist es eine
/// leere Vorlage. Gelöschte Zutaten bleiben draußen.
Uint8List zutatenMappe(List<Zutat> zutaten, {required DateTime stand}) {
  final liste = [
    for (final z in zutaten)
      if (z.deletedAt == null) z,
  ]..sort((a, b) => nachName(a.name, b.name));
  final mappe = XlsxSchreiber();
  final b = mappe.blatt('Zutaten');
  for (var i = 0; i < _spalten.length; i++) {
    b.text(1, i + 1, _spalten[i].kopf, XlsxStil.kopfUmbruch);
  }
  b
    ..hoehe(1, 32)
    ..breiten({
      for (var i = 0; i < _spalten.length; i++) i + 1: _spalten[i].breite,
    })
    ..fixiere('B2');

  var r = 2;
  for (final z in liste) {
    final w = ZutatWerte.aus(z);
    final allergene = merkmaleAusText(w[ZutatFeld.allergene] as String?);
    for (var i = 0; i < _spalten.length; i++) {
      final s = _spalten[i];
      final c = i + 1;
      switch (s.rolle) {
        case _Rolle.id:
          b.text(r, c, z.id, XlsxStil.berechnet);
        case _Rolle.stand:
          b.text(r, c, w.stand, XlsxStil.berechnet);
        case _Rolle.allergen:
          b.text(
            r,
            c,
            allergene.contains(s.allergen) ? 'x' : null,
            XlsxStil.wert,
          );
        case _Rolle.feld:
          final f = s.feld!;
          switch (w[f]) {
            case final double d:
              b.zahl(r, c, d, XlsxStil.wert);
            case final bool j:
              b.text(r, c, j ? 'ja' : 'nein', XlsxStil.wert);
            case String():
              b.text(r, c, w.anzeige(f), XlsxStil.wert);
            default:
              b.leer(r, c, XlsxStil.wert);
          }
      }
    }
    r++;
  }

  // Auswahllisten bis weit unter die letzte Zeile — für neue Zutaten.
  final bis = r + 500 < 1000 ? 1000 : r + 500;
  final tierarten = Tierart.values.map((t) => t.label).join(',');
  for (var i = 0; i < _spalten.length; i++) {
    final s = _spalten[i];
    final spalte = xlsxSpalte(i + 1);
    final bereich = '${spalte}2:$spalte$bis';
    if (s.rolle == _Rolle.allergen) {
      b.auswahl(bereich, '"x"');
    } else if (s.feld?._art == _Art.janein) {
      b.auswahl(bereich, '"ja,nein"');
    } else if (s.feld == ZutatFeld.tierart) {
      b.auswahl(bereich, '"$tierarten"');
    }
  }

  _hinweise(mappe.blatt('Hinweise'), anzahl: liste.length, stand: stand);
  return mappe.packe();
}

void _hinweise(
  XlsxSchreibBlatt b, {
  required int anzahl,
  required DateTime stand,
}) {
  b
    ..breiten({1: 120})
    ..text(1, 1, 'Zutaten aus dem Produktions Planer', XlsxStil.artikelKopf)
    ..text(
      2,
      1,
      'Export vom ${Format.datum(stand)}, ${Format.uhrzeit(stand)} Uhr · '
      '$anzahl ${anzahl == 1 ? 'Zutat' : 'Zutaten'}',
      XlsxStil.hinweis,
    );
  const zeilen = [
    'Zurück in die App: Entwicklung → Zutaten → Excel → Importieren. Vor '
        'dem Übernehmen zeigt die App, was sich ändert.',
    'Neue Zutat: eine Zeile ohne ID anfügen. Die App sucht sie über die '
        'Artikelnummer, sonst über den Namen — ohne Treffer legt sie sie '
        'neu an.',
    'ID und Stand bitte nicht ändern. Daran erkennt die App die Zutat und '
        'ob sie seit dem Export auch in der App geändert wurde.',
    'Eine leere Zelle leert den Wert in der App. Eine gelöschte Spalte '
        'ändert nichts, eigene Spalten liest die App nicht.',
    'Eine gelöschte Zeile löscht keine Zutat — gelöscht wird in der App.',
    'Fleisch, Wasser/Eis und QUID: ja oder nein. Allergene: x heißt '
        'enthalten. „Keine Allergene" heißt geprüft allergenfrei, ganz leer '
        'heißt noch nicht angegeben.',
    'Nährwerte je 100 g, Bindegewebe und BEFFE in Prozent. Zahlen mit '
        'Komma oder Punkt.',
    'Nach einem Import am besten neu exportieren — dann tragen auch die '
        'neuen Zutaten ihre ID.',
  ];
  for (var i = 0; i < zeilen.length; i++) {
    b.text(4 + i, 1, zeilen[i], 0);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Einlesen
// ═══════════════════════════════════════════════════════════════════════════

/// Eine Zeile der Mappe, gelesen.
class ZutatenZeile {
  const ZutatenZeile({
    required this.nummer,
    required this.werte,
    this.allergene = const {},
    this.id,
    this.stand,
    this.fehler = const [],
  });

  /// Die Zeilennummer in der Mappe.
  final int nummer;
  final String? id;
  final String? stand;

  /// Die Werte der Spalten, die es gibt — fehlt eine Spalte, fehlt ihr
  /// Feld.
  final Map<ZutatFeld, Object?> werte;

  /// Je Allergenspalte, die es gibt: angekreuzt oder nicht.
  final Map<String, bool> allergene;

  /// Was sich nicht lesen ließ. Dann bleibt die Zeile außen vor.
  final List<String> fehler;

  String? get name => werte[ZutatFeld.name] as String?;
  String? get artikelnummer => werte[ZutatFeld.artikelnummer] as String?;

  /// Die Werte von [basis], überschrieben mit dem, was diese Zeile angibt.
  ZutatWerte auf(ZutatWerte basis) {
    final neu = Map<ZutatFeld, Object?>.of(werte);
    if (allergene.isNotEmpty) {
      final gesetzt = merkmaleAusText(basis[ZutatFeld.allergene] as String?)
        ..removeAll(allergene.keys)
        ..addAll([
          for (final MapEntry(:key, :value) in allergene.entries)
            if (value) key,
        ]);
      // „Keine" und ein Allergen: Ausdrücklich angekreuzt gewinnt „Keine",
      // sonst das Allergen. Beides angekreuzt ist schon ein Lesefehler.
      if (gesetzt.contains(kAllergenKeine) && gesetzt.length > 1) {
        if (allergene[kAllergenKeine] == true) {
          gesetzt.retainAll({kAllergenKeine});
        } else {
          gesetzt.remove(kAllergenKeine);
        }
      }
      neu[ZutatFeld.allergene] = merkmaleZuText(gesetzt, kAllergene);
    }
    return basis.mit(neu);
  }
}

/// Was die Mappe enthält.
class ZutatenDatei {
  const ZutatenDatei({
    required this.zeilen,
    required this.vollstaendig,
    this.hinweise = const [],
  });

  /// Die Zeilen mit Inhalt; leere fehlen.
  final List<ZutatenZeile> zeilen;

  /// Ob alle Spalten der Werte da sind. Nur dann zeigt der Stand auch, ob
  /// eine Zeile in der Datei unverändert ist.
  final bool vollstaendig;

  /// Was an der Datei auffiel, etwa Spalten, die die App nicht liest.
  final List<String> hinweise;
}

typedef _Kopf = ({int zeile, Map<int, _Spalte> spalten, List<String> fremd});

/// Liest die Zutaten aus der Mappe [bytes]: aus dem Blatt „Zutaten" — oder
/// dem ersten Blatt mit einer Kopfzeile, in der „Name" steht.
///
/// Wirft eine [FormatException] mit lesbarer Meldung, wenn die Datei keine
/// Excel-Mappe ist oder keine Zutatenliste enthält.
ZutatenDatei zutatenDateiLesen(Uint8List bytes) {
  final tabellen = xlsxLesen(bytes);
  bool istZutaten(XlsxTabelle t) => _kopfSchluessel(t.name) == 'zutaten';
  for (final t in [
    ...tabellen.where(istZutaten),
    ...tabellen.where((t) => !istZutaten(t)),
  ]) {
    final kopf = _kopfFinden(t);
    if (kopf != null) return _zeilenLesen(t, kopf);
  }
  throw const FormatException(
    'In der Datei steht keine Zutatenliste: Keine Kopfzeile hat eine '
    'Spalte „Name".',
  );
}

_Kopf? _kopfFinden(XlsxTabelle t) {
  final bis = t.letzteZeile < 20 ? t.letzteZeile : 20;
  for (var z = 1; z <= bis; z++) {
    final zellen = t.zellen[z];
    if (zellen == null) continue;
    final spalten = <int, _Spalte>{};
    final fremd = <String>[];
    final doppelt = <String>[];
    for (final nr in zellen.keys.toList()..sort()) {
      final zelle = zellen[nr]!;
      if (zelle.art != XlsxArt.text) continue;
      final kopf = zelle.wert.trim();
      final s = _spalteZu(kopf);
      if (s == null) {
        if (kopf.isNotEmpty) fremd.add(kopf);
      } else if (spalten.containsValue(s)) {
        doppelt.add(kopf);
      } else {
        spalten[nr] = s;
      }
    }
    final mitName = spalten.values.any((s) => s.feld == ZutatFeld.name);
    if (!mitName) continue;
    if (doppelt.isNotEmpty) {
      throw FormatException(
        'Die Spalte „${doppelt.first}" steht zweimal in der Kopfzeile — '
        'bitte eine davon umbenennen oder löschen.',
      );
    }
    return (zeile: z, spalten: spalten, fremd: fremd);
  }
  return null;
}

ZutatenDatei _zeilenLesen(XlsxTabelle t, _Kopf kopf) {
  final zeilen = <ZutatenZeile>[];
  for (var r = kopf.zeile + 1; r <= t.letzteZeile; r++) {
    final zellen = t.zellen[r];
    if (zellen == null) continue;
    final werte = <ZutatFeld, Object?>{};
    final allergene = <String, bool>{};
    final fehler = <String>[];
    String? id;
    String? stand;
    var inhalt = false;
    for (final MapEntry(key: nr, value: s) in kopf.spalten.entries) {
      final zelle = zellen[nr];
      if (zelle != null &&
          (zelle.art != XlsxArt.text || zelle.wert.trim().isNotEmpty)) {
        inhalt = true;
      }
      switch (s.rolle) {
        case _Rolle.id:
          id = _zellText(zelle, s.kopf, fehler);
        case _Rolle.stand:
          stand = _zellText(zelle, s.kopf, fehler);
        case _Rolle.allergen:
          final an = _janein(zelle, s.kopf, fehler);
          if (an != null) allergene[s.allergen!] = an;
        case _Rolle.feld:
          werte[s.feld!] = _zellWert(s.feld!, zelle, s.kopf, fehler);
      }
    }
    if (!inhalt) continue;
    if (werte[ZutatFeld.name] == null &&
        !fehler.any((f) => f.startsWith('„Name"'))) {
      fehler.add('Der Name fehlt.');
    }
    final keine = allergene[kAllergenKeine] == true;
    final angekreuzt = [
      for (final m in kAllergene)
        if (m.dbValue != kAllergenKeine && allergene[m.dbValue] == true)
          m.label,
    ];
    if (keine && angekreuzt.isNotEmpty) {
      fehler.add(
        '„Keine Allergene" und „${angekreuzt.first}" sind zugleich '
        'angekreuzt.',
      );
    }
    zeilen.add(
      ZutatenZeile(
        nummer: r,
        id: id,
        stand: stand,
        werte: werte,
        allergene: allergene,
        fehler: fehler,
      ),
    );
  }

  final da = kopf.spalten.values.toSet();
  final fehlen = [
    for (final s in _spalten)
      if ((s.rolle == _Rolle.feld || s.rolle == _Rolle.allergen) &&
          !da.contains(s))
        s.kopf,
  ];
  return ZutatenDatei(
    zeilen: zeilen,
    vollstaendig: fehlen.isEmpty,
    hinweise: [
      if (fehlen.isNotEmpty)
        'Diese Spalten fehlen in der Datei, ihre Werte bleiben in der App, '
            'wie sie sind: ${_aufzaehlung(fehlen)}.',
      if (!da.contains(_Spalte.id))
        'Die Spalte „ID" fehlt — jede Zeile wird über Artikelnummer oder '
            'Namen zugeordnet.',
      if (kopf.fremd.isNotEmpty)
        'Diese Spalten liest die App nicht: ${_aufzaehlung(kopf.fremd)}.',
    ],
  );
}

String _aufzaehlung(List<String> namen) {
  final gezeigt = namen.take(8).map((n) => '„$n"').join(', ');
  return namen.length > 8
      ? '$gezeigt und ${namen.length - 8} weitere'
      : gezeigt;
}

Object? _zellWert(
  ZutatFeld f,
  XlsxZelle? zelle,
  String kopf,
  List<String> fehler,
) =>
    switch (f._art) {
      _Art.text => _zellText(zelle, kopf, fehler),
      _Art.janein => _janein(zelle, kopf, fehler) ?? false,
      _Art.zahl => _zellZahl(zelle, kopf, fehler),
      _Art.tierart => _tierart(zelle, kopf, fehler),
      // Allergene stehen je in eigener Spalte.
      _Art.allergene => null,
    };

String? _zellText(XlsxZelle? zelle, String kopf, List<String> fehler) {
  if (zelle == null) return null;
  switch (zelle.art) {
    case XlsxArt.text:
      return _text(zelle.wert);
    case XlsxArt.zahl:
      final d = double.tryParse(zelle.wert);
      if (d == null) return _text(zelle.wert);
      // Eine Artikelnummer, als Zahl eingetippt: „10010", nicht „10010.0".
      return d == d.truncateToDouble() && d.abs() < 1e15
          ? d.toInt().toString()
          : feldText(d);
    case XlsxArt.wahrheitswert:
      return zelle.wert == '1' ? 'WAHR' : 'FALSCH';
    case XlsxArt.datum:
      fehler.add(
        '„$kopf" steht als Datum in der Zelle — bitte als Text eingeben.',
      );
      return null;
    case XlsxArt.fehler:
      fehler.add('„$kopf" enthält den Fehlerwert ${zelle.wert}.');
      return null;
  }
}

double? _zellZahl(XlsxZelle? zelle, String kopf, List<String> fehler) {
  if (zelle == null) return null;
  switch (zelle.art) {
    case XlsxArt.zahl:
      return _zahl(double.tryParse(zelle.wert));
    case XlsxArt.text:
      final t = zelle.wert.trim();
      if (t.isEmpty || t == '-' || t == '–') return null;
      final wert = zahlAus(t.endsWith('%') ? t.substring(0, t.length - 1) : t);
      if (wert == null || !wert.isFinite) {
        fehler.add('„$kopf" ist keine Zahl: „$t".');
        return null;
      }
      return wert;
    case XlsxArt.datum:
      fehler.add(
        '„$kopf" steht als Datum in der Zelle — Excel macht aus „1.5" den '
        '1. Mai. Bitte mit Komma eingeben.',
      );
      return null;
    case XlsxArt.wahrheitswert:
      fehler.add('„$kopf" ist keine Zahl.');
      return null;
    case XlsxArt.fehler:
      fehler.add('„$kopf" enthält den Fehlerwert ${zelle.wert}.');
      return null;
  }
}

const Set<String> _ja = {'ja', 'j', 'x', 'wahr', 'true', 'yes', 'y', '1'};
const Set<String> _nein = {'nein', 'n', 'falsch', 'false', 'no', '0', '-'};

/// Ja oder nein — leer ist nein. null, wenn sich nichts davon lesen lässt.
bool? _janein(XlsxZelle? zelle, String kopf, List<String> fehler) {
  if (zelle == null) return false;
  switch (zelle.art) {
    case XlsxArt.wahrheitswert:
      return zelle.wert == '1';
    case XlsxArt.zahl:
      final d = double.tryParse(zelle.wert);
      if (d == 1) return true;
      if (d == 0) return false;
    case XlsxArt.text:
      final t = zelle.wert.trim().toLowerCase();
      if (t.isEmpty || _nein.contains(t)) return false;
      if (_ja.contains(t)) return true;
    case XlsxArt.datum:
    case XlsxArt.fehler:
      break;
  }
  fehler.add(
    '„$kopf": „${zelle.wert}" lässt sich nicht lesen — erlaubt sind ja oder '
    'nein, bei Allergenen x oder leer.',
  );
  return null;
}

String? _tierart(XlsxZelle? zelle, String kopf, List<String> fehler) {
  final t = _zellText(zelle, kopf, fehler);
  if (t == null) return null;
  final klein = t.toLowerCase();
  for (final art in Tierart.values) {
    if (art.label.toLowerCase() == klein || art.schluessel == klein) {
      return art.schluessel;
    }
  }
  final art = Tierart.aus(t);
  if (art != null) return art.schluessel;
  fehler.add('Die Tierart „$t" kennt die App nicht.');
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// Abgleich
// ═══════════════════════════════════════════════════════════════════════════

/// Eine Änderung, die der Import vorschlägt.
class ZutatVorschlag {
  const ZutatVorschlag({
    required this.zeile,
    required this.zutat,
    required this.werte,
    required this.felder,
    this.hinweis,
    this.grund,
  });

  /// Die Zeilennummer in der Mappe.
  final int zeile;

  /// Die Zutat der App — null bei einer neuen.
  final Zutat? zutat;

  /// Die Werte nach dem Import.
  final ZutatWerte werte;

  /// Was sich ändert — bei einer neuen Zutat, was angegeben ist.
  final Set<ZutatFeld> felder;

  /// Wie die Zeile zu ihrer Zutat kam, wenn das nicht selbstverständlich
  /// ist — etwa „Kopie von Zeile 9".
  final String? hinweis;

  /// Bei einem Konflikt: warum nicht klar ist, welche Seite gilt.
  final String? grund;

  String get name => werte.name ?? zutat?.name ?? '';

  /// Die Werte der App vor dem Import — null bei einer neuen Zutat.
  ZutatWerte? get vorher => zutat == null ? null : ZutatWerte.aus(zutat!);
}

/// Eine Zeile, die der Import auslässt, und warum.
class ZeilenFehler {
  const ZeilenFehler(this.zeile, this.text);

  final int zeile;
  final String text;
}

/// Was ein Import ändern würde.
class ZutatenAbgleich {
  const ZutatenAbgleich({
    this.neu = const [],
    this.geaendert = const [],
    this.konflikte = const [],
    this.unveraendert = 0,
    this.inAppNeuer = 0,
    this.fehler = const [],
    this.hinweise = const [],
  });

  /// Zeilen ohne passende Zutat — sie werden angelegt.
  final List<ZutatVorschlag> neu;

  /// In der Datei geändert, in der App seit dem Export nicht.
  final List<ZutatVorschlag> geaendert;

  /// Auf beiden Seiten geändert — oder ohne Stand, sodass sich nicht sagen
  /// lässt, welche Seite neuer ist. Hier entscheidet der Mensch.
  final List<ZutatVorschlag> konflikte;

  /// Zeilen, die zur App passen.
  final int unveraendert;

  /// Zeilen, die in der Datei unverändert sind, deren Zutat aber seit dem
  /// Export in der App geändert wurde. Sie bleiben, wie die App sie hat.
  final int inAppNeuer;

  final List<ZeilenFehler> fehler;
  final List<String> hinweise;

  /// Ob es etwas zu übernehmen gibt.
  bool get hatAenderungen =>
      neu.isNotEmpty || geaendert.isNotEmpty || konflikte.isNotEmpty;
}

const String _grundBeide =
    'In der App und in der Datei geändert, seit die Datei exportiert wurde.';
const String _grundOhneStand =
    'Die Zeile hat keinen Stand — ob App oder Datei neuer ist, lässt sich '
    'nicht sagen.';

/// Vergleicht [datei] mit den Zutaten der App ([alle], auch gelöschte).
ZutatenAbgleich zutatenAbgleichen(ZutatenDatei datei, List<Zutat> alle) {
  final nachId = {for (final z in alle) z.id: z};
  final nachNummer = <String, List<Zutat>>{};
  final nachName = <String, List<Zutat>>{};
  for (final z in alle) {
    if (z.deletedAt != null) continue;
    final nr = _text(z.artikelnummer);
    if (nr != null) {
      nachNummer.putIfAbsent(_suchSchluessel(nr), () => []).add(z);
    }
    nachName.putIfAbsent(_suchSchluessel(z.name), () => []).add(z);
  }

  final fehler = <ZeilenFehler>[];
  final gueltig = <ZutatenZeile>[];
  for (final z in datei.zeilen) {
    if (z.fehler.isEmpty) {
      gueltig.add(z);
    } else {
      fehler.addAll([for (final f in z.fehler) ZeilenFehler(z.nummer, f)]);
    }
  }

  // Welche Zeile welche Zutat bekommt — null heißt: neu anlegen.
  final zuordnung = <int, Zutat?>{};
  final vergeben = <String, int>{};
  final hinweis = <int, String>{};
  final kopien = <int>{};

  // 1. Zeilen mit ID. Steht dieselbe ID mehrmals da, ist eine Zeile kopiert
  //    worden: Die mit dem Namen der Zutat ist das Original, die übrigen
  //    werden neue Zutaten.
  final nachZeilenId = <String, List<ZutatenZeile>>{};
  for (final z in gueltig) {
    if (z.id case final id?) nachZeilenId.putIfAbsent(id, () => []).add(z);
  }
  for (final MapEntry(key: id, value: gruppe) in nachZeilenId.entries) {
    final zutat = nachId[id];
    if (zutat == null) {
      fehler.addAll([
        for (final z in gruppe)
          ZeilenFehler(
            z.nummer,
            'Die ID kennt die App nicht. Für eine neue Zutat die ID-Zelle '
            'leeren.',
          ),
      ]);
      continue;
    }
    if (zutat.deletedAt != null) {
      fehler.addAll([
        for (final z in gruppe)
          ZeilenFehler(
            z.nummer,
            '„${zutat.name}" ist in der App gelöscht — die Zeile bleibt '
            'außen vor.',
          ),
      ]);
      continue;
    }
    final original = gruppe.length == 1
        ? gruppe.single
        : switch ([
            for (final z in gruppe)
              if (_suchSchluessel(z.name ?? '') == _suchSchluessel(zutat.name))
                z,
          ]) {
            [final einzig] => einzig,
            _ => null,
          };
    if (original == null) {
      final nummern = gruppe.map((z) => z.nummer).join(', ');
      fehler.addAll([
        for (final z in gruppe)
          ZeilenFehler(
            z.nummer,
            'Dieselbe ID steht in den Zeilen $nummern. Bei einer kopierten '
            'Zeile bitte die ID-Zelle leeren.',
          ),
      ]);
      continue;
    }
    zuordnung[original.nummer] = zutat;
    vergeben[zutat.id] = original.nummer;
    for (final kopie in gruppe) {
      if (identical(kopie, original)) continue;
      zuordnung[kopie.nummer] = null;
      kopien.add(kopie.nummer);
      hinweis[kopie.nummer] = 'Kopie von Zeile ${original.nummer}';
    }
  }

  // 2. Zeilen ohne ID: über die Artikelnummer, sonst über den Namen. Eine
  //    Zutat ohne Artikelnummer findet auch eine Zeile mit Nummer — so
  //    lässt sich die Nummer in der Datei nachtragen.
  for (final z in gueltig) {
    if (z.id != null) continue;
    final name = z.name!;
    final nr = z.artikelnummer;
    var treffer = const <Zutat>[];
    var ueberName = nr == null;
    if (nr != null) {
      treffer = nachNummer[_suchSchluessel(nr)] ?? const [];
      if (treffer.isEmpty) {
        ueberName = true;
        treffer = [
          for (final k in nachName[_suchSchluessel(name)] ?? const <Zutat>[])
            if (_text(k.artikelnummer) == null) k,
        ];
      }
    } else {
      treffer = nachName[_suchSchluessel(name)] ?? const [];
    }
    if (treffer.length > 1) {
      fehler.add(
        ZeilenFehler(
          z.nummer,
          ueberName
              ? '„$name" gibt es in der App mehrmals — bitte die ID oder eine '
                  'Artikelnummer angeben.'
              : 'Die Artikelnummer „$nr" haben in der App mehrere Zutaten.',
        ),
      );
      continue;
    }
    if (treffer.isEmpty) {
      zuordnung[z.nummer] = null;
      continue;
    }
    final zutat = treffer.single;
    final schon = vergeben[zutat.id];
    if (schon != null) {
      fehler.add(
        ZeilenFehler(z.nummer, '„${zutat.name}" steht schon in Zeile $schon.'),
      );
      continue;
    }
    vergeben[zutat.id] = z.nummer;
    zuordnung[z.nummer] = zutat;
    if (nr != null && ueberName) {
      hinweis[z.nummer] = 'über den Namen gefunden';
    }
  }

  // 3. Vergleichen — in der Reihenfolge der Datei.
  final neu = <ZutatVorschlag>[];
  final geaendert = <ZutatVorschlag>[];
  final konflikte = <ZutatVorschlag>[];
  var unveraendert = 0;
  var inAppNeuer = 0;
  // Neue Zutaten: je Name, ob sie eine Artikelnummer haben; je Nummer die
  // Zeile.
  final neueNamen = <String, ({int zeile, bool mitNummer})>{};
  final neueNummern = <String, int>{};

  for (final z in gueltig) {
    if (!zuordnung.containsKey(z.nummer)) continue;
    final zutat = zuordnung[z.nummer];
    final alt = zutat == null ? ZutatWerte.leer : ZutatWerte.aus(zutat);
    final werte = z.auf(alt);
    final felder = werte.unterschiedeZu(alt);
    if (zutat != null && felder.isEmpty) {
      unveraendert++;
      continue;
    }
    // Erst hier: Eine Zutat, die in der App schon beides ist, soll nicht
    // jeden Import einer unveränderten Zeile scheitern lassen.
    if (werte.istFleisch && werte.istWasser) {
      fehler.add(
        ZeilenFehler(
          z.nummer,
          'Fleisch und Wasser/Eis zugleich — eine Zutat ist das eine oder '
          'das andere.',
        ),
      );
      continue;
    }

    if (zutat == null) {
      final name = werte.name!;
      final nr = werte.artikelnummer;
      final nameSchluessel = _suchSchluessel(name);
      final gleicherName = neueNamen[nameSchluessel];
      String? problem;
      if (nr != null) {
        final nrSchluessel = _suchSchluessel(nr);
        final belegt = nachNummer[nrSchluessel];
        final vorher = neueNummern[nrSchluessel];
        if (belegt != null) {
          problem = 'Die Artikelnummer „$nr" hat schon „${belegt.first.name}".';
        } else if (vorher != null) {
          problem = 'Die Artikelnummer „$nr" steht schon in Zeile $vorher.';
        } else if (gleicherName != null && !gleicherName.mitNummer) {
          problem = '„$name" steht schon in Zeile ${gleicherName.zeile}.';
        }
      } else if (gleicherName != null) {
        problem = '„$name" steht schon in Zeile ${gleicherName.zeile}.';
      } else if (kopien.contains(z.nummer) &&
          nachName.containsKey(nameSchluessel)) {
        problem = '„$name" gibt es in der App schon — für eine zweite Zutat '
            'dieses Namens bitte eine Artikelnummer angeben.';
      }
      if (problem != null) {
        fehler.add(ZeilenFehler(z.nummer, problem));
        continue;
      }
      if (nr != null) neueNummern[_suchSchluessel(nr)] = z.nummer;
      neueNamen.putIfAbsent(
        nameSchluessel,
        () => (zeile: z.nummer, mitNummer: nr != null),
      );
      neu.add(
        ZutatVorschlag(
          zeile: z.nummer,
          zutat: null,
          werte: werte,
          felder: felder,
          hinweis: hinweis[z.nummer],
        ),
      );
      continue;
    }

    final stand = z.stand;
    final standBekannt =
        stand != null && stand.startsWith(ZutatWerte.standVorsilbe);
    // Ohne bekannten Stand weiß niemand, ob die App sich geändert hat.
    final appGeaendert = standBekannt ? alt.stand != stand : null;
    if (appGeaendert == false) {
      geaendert.add(
        ZutatVorschlag(
          zeile: z.nummer,
          zutat: zutat,
          werte: werte,
          felder: felder,
          hinweis: hinweis[z.nummer],
        ),
      );
      continue;
    }
    // Die App hat sich geändert. Ist die Zeile in der Datei noch so, wie
    // sie exportiert wurde, ist einfach die App neuer.
    final dateiUnveraendert = standBekannt &&
        datei.vollstaendig &&
        z.auf(ZutatWerte.leer).stand == stand;
    if (appGeaendert == true && dateiUnveraendert) {
      inAppNeuer++;
      continue;
    }
    konflikte.add(
      ZutatVorschlag(
        zeile: z.nummer,
        zutat: zutat,
        werte: werte,
        felder: felder,
        hinweis: hinweis[z.nummer],
        grund: appGeaendert == null ? _grundOhneStand : _grundBeide,
      ),
    );
  }

  fehler.sort((a, b) => a.zeile.compareTo(b.zeile));
  return ZutatenAbgleich(
    neu: neu,
    geaendert: geaendert,
    konflikte: konflikte,
    unveraendert: unveraendert,
    inAppNeuer: inAppNeuer,
    fehler: fehler,
    hinweise: datei.hinweise,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Übernehmen
// ═══════════════════════════════════════════════════════════════════════════

/// Schreibt, was [abgleich] vorschlägt: die neuen Zutaten, die Änderungen
/// und von den Konflikten die, deren Zeile in [dateiGewinnt] steht — alles
/// oder nichts. Gibt zurück, wie viele Zutaten angelegt und geändert
/// wurden.
Future<({int neu, int geaendert})> zutatenUebernehmen(
  AppDatabase db,
  ZutatenAbgleich abgleich, {
  Set<int> dateiGewinnt = const {},
}) async {
  final repo = EntwicklungRepository(db);
  final aendern = [
    ...abgleich.geaendert,
    for (final k in abgleich.konflikte)
      if (dateiGewinnt.contains(k.zeile)) k,
  ];
  await db.transaction(() async {
    for (final v in abgleich.neu) {
      await repo.zutatAnlegen(v.werte.companion());
    }
    for (final v in aendern) {
      await repo.zutatAendern(v.zutat!.id, v.werte.companion(v.felder));
    }
  });
  return (neu: abgleich.neu.length, geaendert: aendern.length);
}
