import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/utils/format.dart';
import '../projekte/projekt_modell.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechenkern.dart';

// Die Werte einer Spezifikation als Platzhalter für eine Excel-Vorlage.
//
// Die Vorlage selbst gehört der Firma und steht nicht im Code: Man wählt
// sie in der App und schreibt in ihre Zellen Platzhalter wie
// {{artikelnummer}} oder {{naehrwert.fett}}. Beim Erstellen ersetzt die App
// sie durch die Werte des Projekts — Formatierung, Logo und Aufbau der
// Vorlage bleiben, wie sie sind.

/// Sprache der Spezifikation.
enum SpezSprache {
  de('Deutsch'),
  en('Englisch');

  const SpezSprache(this.label);

  final String label;
}

/// Höchstens so viele Verarbeitungshilfsstoffe haben einen Platzhalter.
const int kHilfsstoffPlaetze = 6;

/// Englische Namen der Allergene (LMIV Anhang II, englische Fassung).
const Map<String, String> _allergenEnglisch = {
  'gluten': 'Cereals containing gluten',
  'eier': 'Eggs',
  'soja': 'Soybeans',
  'milch': 'Milk',
  'schalenfruechte': 'Nuts',
  'sellerie': 'Celery',
  'senf': 'Mustard',
  'sesam': 'Sesame seeds',
  'sulfit': 'Sulphur dioxide and sulphites',
  'krebstiere': 'Crustaceans',
  'fisch': 'Fish',
  'erdnuesse': 'Peanuts',
  'lupinen': 'Lupin',
  'weichtiere': 'Molluscs',
};

/// Die 14 Hauptallergene in der Reihenfolge des Planers (ohne „keine").
List<String> get kSpezAllergene => [
      for (final m in kAllergene)
        if (m.dbValue != kAllergenKeine) m.dbValue,
    ];

/// Name eines Allergens in [sprache].
String allergenName(String dbValue, SpezSprache sprache) {
  if (sprache == SpezSprache.en) return _allergenEnglisch[dbValue] ?? dbValue;
  for (final m in kAllergene) {
    if (m.dbValue == dbValue) return m.label;
  }
  return dbValue;
}

/// Ein Platzhalter mit Erklärung — für die Liste in der App und die
/// Beispielvorlage.
typedef Platzhalter = ({String name, String erklaerung});

/// Alle Platzhalter, die die App füllt.
List<Platzhalter> get kSpezifikationPlatzhalter => [
      (name: 'gueltig_ab', erklaerung: 'Datum, ab dem die Spezifikation gilt'),
      (name: 'artikelnummer', erklaerung: 'Artikelnummer'),
      (name: 'bezeichnung', erklaerung: 'Bezeichnung des Artikels'),
      (name: 'kunde', erklaerung: 'Kunde des Projekts'),
      (name: 'projekt', erklaerung: 'Name des Projekts'),
      (name: 'stand', erklaerung: 'Rezepturstand, etwa „Stand 3"'),
      (name: 'zutaten', erklaerung: 'Zutatenliste mit Allergenen in GROSS'),
      (name: 'fleischanteil', erklaerung: 'Fleischanteil nach LMIV'),
      (name: 'beffe', erklaerung: 'BEFFE je 100 g, wenn bekannt'),
      (name: 'verlust', erklaerung: 'Verlust der Rezeptur'),
      (name: 'haltbarkeit', erklaerung: 'Haltbarkeit des Artikels'),
      (name: 'aw', erklaerung: 'aw-Wert (Grenze aus dem Projekt)'),
      (name: 'allergene', erklaerung: 'Enthaltene Allergene als Liste'),
      (name: 'naehrwert.energie', erklaerung: 'Energie „kJ / kcal"'),
      for (final s in Naehrstoff.values)
        (
          name: 'naehrwert.${_naehrstoffName(s)}',
          erklaerung: '${s.label} je 100 g (${s.einheit}), gerundet',
        ),
      for (final f in const [
        'aussehen',
        'geruch',
        'geschmack',
        'konsistenz',
        'laenge',
        'durchmesser',
        'gewicht',
        'zubereitung',
      ])
        (name: 'sensorik.$f', erklaerung: 'Sensorik: $f'),
      for (var i = 1; i <= kHilfsstoffPlaetze; i++) ...[
        (name: 'hilfsstoff.$i.name', erklaerung: 'Hilfsstoff $i'),
        (name: 'hilfsstoff.$i.quelle', erklaerung: 'Hilfsstoff $i: aus'),
      ],
      for (final a in kSpezAllergene) ...[
        (name: 'allergen.$a.ja', erklaerung: '„X", wenn enthalten'),
        (name: 'allergen.$a.nein', erklaerung: '„X", wenn nicht enthalten'),
        (name: 'allergen.$a.quelle', erklaerung: 'Zutaten mit $a'),
      ],
    ];

String _naehrstoffName(Naehrstoff s) => switch (s) {
      Naehrstoff.energieKj => 'energie_kj',
      Naehrstoff.energieKcal => 'energie_kcal',
      Naehrstoff.fett => 'fett',
      Naehrstoff.gesaettigteFettsaeuren => 'gesaettigte_fettsaeuren',
      Naehrstoff.kohlenhydrate => 'kohlenhydrate',
      Naehrstoff.zucker => 'zucker',
      Naehrstoff.eiweiss => 'eiweiss',
      Naehrstoff.salz => 'salz',
    };

/// Was in die Spezifikation einfließt.
class SpezifikationsQuelle {
  const SpezifikationsQuelle({
    required this.projektName,
    required this.ergebnis,
    required this.verlustProzent,
    this.artikelnummer,
    this.bezeichnung,
    this.kunde,
    this.standNummer,
    this.haltbarkeitTage,
    this.aw,
    this.sensorik = const Sensorik(),
  });

  final String projektName;
  final RezepturErgebnis ergebnis;
  final double verlustProzent;
  final String? artikelnummer;

  /// Bezeichnung des Artikels — sonst der Projektname.
  final String? bezeichnung;
  final String? kunde;
  final int? standNummer;
  final int? haltbarkeitTage;
  final double? aw;
  final Sensorik sensorik;
}

/// Die Texte, die eine Übersetzung braucht — Schlüssel wie bei den
/// Platzhaltern. Zahlen, Daten, „X" und was die App schon englisch
/// schreibt („None", „-") bleiben außen vor.
Map<String, String> uebersetzbareTexte(Map<String, String> werte) => {
      for (final MapEntry(:key, :value) in werte.entries)
        if (_uebersetzbar(key) && !_schonFertig.hasMatch(value)) key: value,
    };

/// Leer, nur Striche oder das „None" der App.
final RegExp _schonFertig = RegExp(r'^\s*(-*|None|none)\s*$');

bool _uebersetzbar(String schluessel) =>
    schluessel == 'bezeichnung' ||
    schluessel == 'zutaten' ||
    schluessel.startsWith('sensorik.') ||
    (schluessel.startsWith('hilfsstoff.') && schluessel.endsWith('.name')) ||
    (schluessel.startsWith('hilfsstoff.') && schluessel.endsWith('.quelle')) ||
    (schluessel.startsWith('allergen.') && schluessel.endsWith('.quelle'));

/// Die Werte aller Platzhalter für [q] in [sprache].
Map<String, String> spezifikationsWerte(
  SpezifikationsQuelle q, {
  required SpezSprache sprache,
  required DateTime datum,
}) {
  final en = sprache == SpezSprache.en;
  final e = q.ergebnis;
  String zahl(num wert, int nachkomma) {
    final t = Format.zahl(wert, nachkomma: nachkomma);
    return en ? t.replaceAll('.', '').replaceAll(',', '.') : t;
  }

  String prozent(double wert) => '${zahl(wert, 1)} %';
  String gerundet(Naehrstoff s) {
    final t = naehrwertGerundet(s, naehrstoffWert(e.je100g, s));
    return en ? t.replaceAll(',', '.') : t;
  }

  final d = datum;
  final tag = '${d.day}'.padLeft(2, '0');
  final monat = '${d.month}'.padLeft(2, '0');
  final werte = <String, String>{
    'gueltig_ab': en ? '$tag/$monat/${d.year}' : '$tag.$monat.${d.year}',
    'artikelnummer': q.artikelnummer ?? '',
    'bezeichnung': (q.bezeichnung?.trim().isNotEmpty ?? false)
        ? q.bezeichnung!.trim()
        : q.projektName,
    'kunde': q.kunde ?? '',
    'projekt': q.projektName,
    'stand': q.standNummer == null
        ? ''
        : (en ? 'Version ${q.standNummer}' : 'Stand ${q.standNummer}'),
    'zutaten': e.zutatenliste,
    'fleischanteil':
        e.fleischanteilProzent > 0 ? prozent(e.fleischanteilProzent) : '',
    'beffe': e.je100g.beffe == null ? '' : prozent(e.je100g.beffe!),
    'verlust': prozent(q.verlustProzent),
    'haltbarkeit': q.haltbarkeitTage == null
        ? ''
        : '${q.haltbarkeitTage} ${en ? 'days' : 'Tage'}',
    'aw': q.aw == null ? '' : zahl(q.aw!, 2),
    'naehrwert.energie': '${gerundet(Naehrstoff.energieKj)} kJ / '
        '${gerundet(Naehrstoff.energieKcal)} kcal',
    for (final s in Naehrstoff.values)
      'naehrwert.${_naehrstoffName(s)}': gerundet(s),
    'sensorik.aussehen': q.sensorik.aussehen,
    'sensorik.geruch': q.sensorik.geruch,
    'sensorik.geschmack': q.sensorik.geschmack,
    'sensorik.konsistenz': q.sensorik.konsistenz,
    'sensorik.laenge': q.sensorik.laenge,
    'sensorik.durchmesser': q.sensorik.durchmesser,
    'sensorik.gewicht': q.sensorik.gewicht,
    'sensorik.zubereitung': q.sensorik.zubereitung,
  };

  // Verarbeitungshilfsstoffe: der erste Platz sagt „keine", wenn es keine
  // gibt — wie in den Spezifikationen der Suite.
  final hilfsstoffe = e.verarbeitungshilfsstoffe.entries.toList();
  for (var i = 1; i <= kHilfsstoffPlaetze; i++) {
    final h = i <= hilfsstoffe.length ? hilfsstoffe[i - 1] : null;
    werte['hilfsstoff.$i.name'] = h?.key ??
        (i == 1 && hilfsstoffe.isEmpty ? (en ? 'None' : 'Keine') : '');
    werte['hilfsstoff.$i.quelle'] = h == null
        ? (i == 1 && hilfsstoffe.isEmpty ? '-' : '')
        : h.value.join(', ');
  }

  final enthalten = e.allergene;
  werte['allergene'] = enthalten.isEmpty
      ? (en ? 'none' : 'keine')
      : [for (final a in enthalten.keys) allergenName(a, sprache)].join(', ');
  for (final a in kSpezAllergene) {
    final quellen = enthalten[a];
    werte['allergen.$a.ja'] = quellen == null ? '' : 'X';
    werte['allergen.$a.nein'] = quellen == null ? 'X' : '';
    werte['allergen.$a.quelle'] = quellen?.join(', ') ?? '';
  }
  return werte;
}
