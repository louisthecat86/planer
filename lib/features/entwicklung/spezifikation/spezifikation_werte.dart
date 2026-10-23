import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/utils/format.dart';
import '../projekte/projekt_modell.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechenkern.dart';
import 'spez_angaben.dart';

export 'spez_angaben.dart' show kHilfsstoffPlaetze, kHinweisPlaetze;

// Die Werte einer Spezifikation als Platzhalter für eine Excel-Vorlage.
//
// Die Vorlage selbst gehört der Firma und steht nicht im Code: Man wählt
// sie in der App — die App richtet sie selbst ein (vorlage_einrichten.dart)
// oder man schreibt in ihre Zellen Platzhalter wie {{artikelnummer}} oder
// {{naehrwert.fett}}. Beim Erstellen ersetzt die App sie durch die Werte
// des Projekts — Formatierung, Logo und Aufbau der Vorlage bleiben, wie
// sie sind.
//
// Platzhalter, die ein „X" oder nichts ergeben (Allergene ja/nein/Spuren,
// die Verpackung), setzen unter einem Kontrollkästchen dessen Häkchen.

/// Sprache der Spezifikation.
enum SpezSprache {
  de('Deutsch'),
  en('Englisch');

  const SpezSprache(this.label);

  final String label;
}

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

/// Die Kreuze der Verpackung: Platzhalter-Name und Erklärung.
const List<({String name, String erklaerung})> _verpackungsKreuze = [
  (name: 'verpackung.um.e2_kiste', erklaerung: 'Umverpackung E2-Kiste'),
  (name: 'verpackung.um.karton_gross', erklaerung: 'Umverpackung Karton groß'),
  (name: 'verpackung.um.karton_klein', erklaerung: 'Umverpackung Karton klein'),
  (name: 'verpackung.um.neutral', erklaerung: 'neutraler Karton'),
  (name: 'verpackung.um.bedruckt', erklaerung: 'Firmenkarton (bedruckt)'),
  (name: 'verpackung.um.egalisiert', erklaerung: 'Umverpackung egalisiert'),
  (name: 'verpackung.um.gewogen', erklaerung: 'Umverpackung gewogen'),
  (name: 'verpackung.einzel.beutel', erklaerung: 'Einzelverpackung Beutel'),
  (
    name: 'verpackung.einzel.seitenfaltenbeutel',
    erklaerung: 'Einzelverpackung Seitenfaltenbeutel',
  ),
  (name: 'verpackung.einzel.schutzgas', erklaerung: 'unter Schutzgas'),
  (name: 'verpackung.einzel.vakuum', erklaerung: 'vakuumverpackt'),
  (name: 'verpackung.einzel.luft', erklaerung: 'normale Atmosphäre'),
  (name: 'verpackung.einzel.egalisiert', erklaerung: 'Einzelverpackung egalisiert'),
  (name: 'verpackung.einzel.gewogen', erklaerung: 'Einzelverpackung gewogen'),
  (name: 'verpackung.einzel.gezaehlt', erklaerung: 'Einzelverpackung gezählt'),
];

/// Die Texte der Verpackung: Platzhalter-Name und Erklärung.
const List<({String name, String erklaerung})> _verpackungsTexte = [
  (name: 'verpackung.um.tara', erklaerung: 'Taragewicht der Umverpackung'),
  (name: 'verpackung.um.netto', erklaerung: 'Nettogewicht der Umverpackung'),
  (name: 'verpackung.um.material', erklaerung: 'Material der Umverpackung'),
  (name: 'verpackung.einzel.anzahl', erklaerung: 'Einzelverpackungen je Umverpackung'),
  (name: 'verpackung.einzel.stueckzahl', erklaerung: 'Stück je Einzelverpackung'),
  (name: 'verpackung.einzel.tara', erklaerung: 'Taragewicht der Einzelverpackung'),
  (name: 'verpackung.einzel.netto', erklaerung: 'Nettogewicht der Einzelverpackung'),
  (name: 'verpackung.einzel.material', erklaerung: 'Material der Einzelverpackung'),
];

/// Ob [name] ein Kreuz ist: „X" oder nichts — unter einem Kontroll-
/// kästchen setzt er dessen Häkchen.
bool istKreuzPlatzhalter(String name) =>
    RegExp(r'^allergen\.[a-z_]+\.(ja|nein|spuren)$').hasMatch(name) ||
    _verpackungsKreuze.any((k) => k.name == name);

/// Alle Platzhalter, die die App füllt.
List<Platzhalter> get kSpezifikationPlatzhalter => [
      (name: 'gueltig_ab', erklaerung: 'Datum, ab dem die Spezifikation gilt'),
      (name: 'kuerzel', erklaerung: 'Kürzel dessen, der sie erstellt'),
      (name: 'artikelnummer', erklaerung: 'Artikelnummer'),
      (name: 'bezeichnung', erklaerung: 'Bezeichnung des Artikels'),
      (name: 'kunde', erklaerung: 'Kunde des Projekts'),
      (name: 'projekt', erklaerung: 'Name des Projekts'),
      (name: 'stand', erklaerung: 'Rezepturstand, etwa „Stand 3"'),
      (name: 'zutaten', erklaerung: 'Zutatenliste mit Allergenen in GROSS'),
      (name: 'fleischanteil', erklaerung: 'Fleischanteil nach LMIV'),
      (name: 'beffe', erklaerung: 'BEFFE je 100 g, wenn bekannt'),
      (name: 'verlust', erklaerung: 'Verlust der Rezeptur'),
      (
        name: 'haltbarkeit',
        erklaerung: 'Haltbarkeit (Angabe im Projekt, sonst aus dem Artikel)',
      ),
      (name: 'lagerung', erklaerung: 'Transport- und Lagerbedingungen'),
      (name: 'toleranz', erklaerung: 'Toleranz des Stückgewichts'),
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
      (
        name: 'produktbild',
        erklaerung: 'Produktfoto — allein in eine Zelle; es füllt deren '
            'verbundenen Bereich',
      ),
      (name: 'hinweise', erklaerung: 'Alle Produkthinweise, je Zeile einer'),
      for (var i = 1; i <= kHinweisPlaetze; i++)
        (name: 'hinweis.$i', erklaerung: 'Produkthinweis $i'),
      for (var i = 1; i <= kHilfsstoffPlaetze; i++) ...[
        (name: 'hilfsstoff.$i.name', erklaerung: 'Hilfsstoff $i'),
        (name: 'hilfsstoff.$i.quelle', erklaerung: 'Hilfsstoff $i: aus'),
      ],
      for (final a in kSpezAllergene) ...[
        (name: 'allergen.$a.ja', erklaerung: '„X", wenn enthalten'),
        (name: 'allergen.$a.nein', erklaerung: '„X", wenn weder enthalten '
            'noch als Spur möglich'),
        (name: 'allergen.$a.spuren', erklaerung: '„X", wenn Spuren möglich'),
        (name: 'allergen.$a.quelle', erklaerung: 'Zutaten mit $a'),
      ],
      for (final k in _verpackungsKreuze)
        (name: k.name, erklaerung: '„X": ${k.erklaerung}'),
      for (final t in _verpackungsTexte) (name: t.name, erklaerung: t.erklaerung),
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
    this.angaben = const SpezAngaben(),
    this.kuerzel,
  });

  final String projektName;
  final RezepturErgebnis ergebnis;
  final double verlustProzent;
  final String? artikelnummer;

  /// Bezeichnung des Artikels — sonst der Projektname.
  final String? bezeichnung;
  final String? kunde;
  final int? standNummer;

  /// Haltbarkeit aus dem Artikel des Planers — gilt, wenn das Projekt
  /// selbst keine angibt.
  final int? haltbarkeitTage;
  final double? aw;
  final Sensorik sensorik;

  /// Was das Projekt für die Spezifikation selbst angibt.
  final SpezAngaben angaben;

  /// Kürzel dessen, der die Spezifikation erstellt.
  final String? kuerzel;
}

/// Die Texte, die eine Übersetzung braucht — Schlüssel wie bei den
/// Platzhaltern. Zahlen, Daten, „X" und was die App schon englisch
/// schreibt („None", „-", „14 days") bleiben außen vor.
Map<String, String> uebersetzbareTexte(Map<String, String> werte) => {
      for (final MapEntry(:key, :value) in werte.entries)
        if (_uebersetzbar(key) &&
            !_schonFertig.hasMatch(value) &&
            _buchstabe.hasMatch(value) &&
            !_tage.hasMatch(value))
          key: value,
    };

/// Leer, nur Striche oder das „None" der App.
final RegExp _schonFertig = RegExp(r'^\s*(-*|None|none)\s*$');

/// Ohne Buchstaben gibt es nichts zu übersetzen („26", „± 5").
final RegExp _buchstabe = RegExp('[A-Za-zÄÖÜäöüß]');

/// Die Haltbarkeit in Tagen schreibt die App selbst englisch.
final RegExp _tage = RegExp(r'^\d+ (days|Tage)$');

bool _uebersetzbar(String schluessel) =>
    schluessel == 'bezeichnung' ||
    schluessel == 'zutaten' ||
    schluessel == 'lagerung' ||
    schluessel == 'haltbarkeit' ||
    schluessel == 'toleranz' ||
    schluessel == 'hinweise' ||
    schluessel.startsWith('hinweis.') ||
    schluessel.startsWith('sensorik.') ||
    (schluessel.startsWith('verpackung.') && !istKreuzPlatzhalter(schluessel)) ||
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
  final a = q.angaben;
  final v = a.verpackung;
  String zahl(num wert, int nachkomma) {
    final t = Format.zahl(wert, nachkomma: nachkomma);
    return en ? t.replaceAll('.', '').replaceAll(',', '.') : t;
  }

  String prozent(double wert) => '${zahl(wert, 1)} %';
  String gerundet(Naehrstoff s) {
    final t = naehrwertGerundet(s, naehrstoffWert(e.je100g, s));
    return en ? t.replaceAll(',', '.') : t;
  }

  // Selbst eingetragene Zahlen: im Englischen mit Dezimalpunkt.
  String eingabe(String t) => en
      ? t.trim().replaceAllMapped(
            RegExp(r'(\d),(\d)'),
            (m) => '${m[1]}.${m[2]}',
          )
      : t.trim();
  String kreuz(bool an) => an ? 'X' : '';
  String tage(int n) => '$n ${en ? 'days' : 'Tage'}';

  final haltbarkeit = a.haltbarkeit.trim();
  final d = datum;
  final tag = '${d.day}'.padLeft(2, '0');
  final monat = '${d.month}'.padLeft(2, '0');
  final hinweise = a.hinweisZeilen;
  final werte = <String, String>{
    'gueltig_ab': en ? '$tag/$monat/${d.year}' : '$tag.$monat.${d.year}',
    'kuerzel': q.kuerzel?.trim() ?? '',
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
    'haltbarkeit': haltbarkeit.isNotEmpty
        ? (RegExp(r'^\d+$').hasMatch(haltbarkeit)
            ? tage(int.parse(haltbarkeit))
            : haltbarkeit)
        : (q.haltbarkeitTage == null ? '' : tage(q.haltbarkeitTage!)),
    'lagerung': a.lagerung.trim(),
    'toleranz': eingabe(a.toleranz),
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
    'sensorik.gewicht': eingabe(q.sensorik.gewicht),
    'sensorik.zubereitung': q.sensorik.zubereitung,
    // Das Foto ist ein Bild, kein Text: Die Zelle wird leer, das Bild
    // setzt der Dienst ein (xlsx_bild.dart).
    'produktbild': '',
    'hinweise': hinweise.join('\n'),
    for (var i = 1; i <= kHinweisPlaetze; i++)
      'hinweis.$i': i <= hinweise.length ? hinweise[i - 1] : '',
    'verpackung.um.e2_kiste': kreuz(v.um.contains('e2_kiste')),
    'verpackung.um.karton_gross': kreuz(v.um.contains('karton_gross')),
    'verpackung.um.karton_klein': kreuz(v.um.contains('karton_klein')),
    'verpackung.um.neutral': kreuz(v.karton == 'neutral'),
    'verpackung.um.bedruckt': kreuz(v.karton == 'bedruckt'),
    'verpackung.um.egalisiert': kreuz(v.umFuellung == 'egalisiert'),
    'verpackung.um.gewogen': kreuz(v.umFuellung == 'gewogen'),
    'verpackung.um.tara': eingabe(v.umTara),
    'verpackung.um.netto': eingabe(v.umNetto),
    'verpackung.um.material': v.umMaterial.trim(),
    'verpackung.einzel.beutel': kreuz(v.einzel.contains('beutel')),
    'verpackung.einzel.seitenfaltenbeutel':
        kreuz(v.einzel.contains('seitenfaltenbeutel')),
    'verpackung.einzel.schutzgas': kreuz(v.atmosphaere == 'schutzgas'),
    'verpackung.einzel.vakuum': kreuz(v.atmosphaere == 'vakuum'),
    'verpackung.einzel.luft': kreuz(v.atmosphaere == 'luft'),
    'verpackung.einzel.egalisiert': kreuz(v.einzelFuellung == 'egalisiert'),
    'verpackung.einzel.gewogen': kreuz(v.einzelFuellung == 'gewogen'),
    'verpackung.einzel.gezaehlt': kreuz(v.einzelFuellung == 'gezaehlt'),
    'verpackung.einzel.anzahl': eingabe(v.anzahl),
    'verpackung.einzel.stueckzahl': eingabe(v.stueckzahl),
    'verpackung.einzel.tara': eingabe(v.einzelTara),
    'verpackung.einzel.netto': eingabe(v.einzelNetto),
    'verpackung.einzel.material': v.einzelMaterial.trim(),
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
      : [for (final x in enthalten.keys) allergenName(x, sprache)].join(', ');
  for (final x in kSpezAllergene) {
    final quellen = enthalten[x];
    final spuren = quellen == null && a.spuren.contains(x);
    werte['allergen.$x.ja'] = kreuz(quellen != null);
    werte['allergen.$x.spuren'] = kreuz(spuren);
    werte['allergen.$x.nein'] = kreuz(quellen == null && !spuren);
    werte['allergen.$x.quelle'] = quellen?.join(', ') ?? '';
  }
  return werte;
}

// ── Texte für die Vorschau im Reiter ──────────────────────────────────

/// Die Nährwerte je 100 g in einer Zeile: „Energie 1050 kJ / 251 kcal ·
/// Fett 13 g · …".
String vorschauNaehrwerte(Map<String, String> w) => [
      'Energie ${w['naehrwert.energie'] ?? ''}',
      'Fett ${w['naehrwert.fett'] ?? ''} g',
      'davon gesättigte Fettsäuren '
          '${w['naehrwert.gesaettigte_fettsaeuren'] ?? ''} g',
      'Kohlenhydrate ${w['naehrwert.kohlenhydrate'] ?? ''} g',
      'davon Zucker ${w['naehrwert.zucker'] ?? ''} g',
      'Eiweiß ${w['naehrwert.eiweiss'] ?? ''} g',
      'Salz ${w['naehrwert.salz'] ?? ''} g',
    ].join(' · ');

/// Die Verarbeitungshilfsstoffe: „Siliziumdioxid (aus Gewürzmischung)" —
/// „Keine", wenn es keine gibt.
String vorschauHilfsstoffe(Map<String, String> w) => [
      for (var i = 1; i <= kHilfsstoffPlaetze; i++)
        if ((w['hilfsstoff.$i.name'] ?? '').trim().isNotEmpty)
          switch (w['hilfsstoff.$i.quelle']?.trim() ?? '') {
            '' || '-' => w['hilfsstoff.$i.name']!.trim(),
            final aus => '${w['hilfsstoff.$i.name']!.trim()} (aus $aus)',
          },
    ].join(', ');

/// Die Sensorik, je Merkmal eine Zeile — leer, wenn nichts eingetragen ist.
String vorschauSensorik(Map<String, String> w) => [
      for (final (schluessel, label) in const [
        ('aussehen', 'Optik'),
        ('konsistenz', 'Konsistenz'),
        ('geruch', 'Geruch'),
        ('geschmack', 'Geschmack'),
      ])
        if ((w['sensorik.$schluessel'] ?? '').trim().isNotEmpty)
          '$label: ${w['sensorik.$schluessel']!.trim()}',
    ].join('\n');

/// Die möglichen Spuren: „Sellerie, Senf" — leer, wenn keine.
String vorschauSpuren(Map<String, String> w) => [
      for (final x in kSpezAllergene)
        if (w['allergen.$x.spuren'] == 'X') allergenName(x, SpezSprache.de),
    ].join(', ');
