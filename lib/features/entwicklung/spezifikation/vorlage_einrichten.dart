import 'dart:typed_data';

import 'spez_angaben.dart';
import 'xlsx_blatt.dart';
import 'xlsx_vorlage.dart';

// Eine Spezifikation, wie die Firma sie als Formblatt in Excel führt,
// selbst einrichten: Die App liest die Beschriftungen („Artikelnummer:",
// „Zutaten:", „Brennwert kJ", die Allergentabelle mit „ja/nein/Spuren",
// die Verpackung …) und schreibt die passenden Platzhalter in die Zellen
// daneben — oder unter die Kontrollkästchen. Auf Deutsch und auf
// Englisch.
//
// So bleibt das Formblatt, wie es ist: Logo, Kopf- und Fußzeile,
// Rahmen und Kästchen. Was die App nicht erkennt, bleibt leer; dafür kann
// man Platzhalter auch von Hand eintragen. Eine Vorlage, die schon
// Platzhalter enthält, bleibt unberührt.

/// Was beim Einrichten herauskam.
class EinrichtenErgebnis {
  const EinrichtenErgebnis({
    required this.bytes,
    required this.felder,
    this.schonEingerichtet = false,
  });

  /// Die Vorlage mit Platzhaltern.
  final Uint8List bytes;

  /// Platzhalter → wo er steht, etwa „C5", „B66 (Kästchen)" oder
  /// „Kopfzeile".
  final Map<String, String> felder;

  /// Die Vorlage hatte schon Platzhalter und blieb, wie sie war.
  final bool schonEingerichtet;

  /// Wie viele Platzhalter unter Kontrollkästchen liegen.
  int get kaestchen =>
      felder.values.where((o) => o.endsWith('(Kästchen)')).length;

  /// Wichtige Felder, die nicht gefunden wurden.
  List<String> get fehlend => [
        for (final f in kWichtigeFelder)
          if (!felder.containsKey(f)) f,
      ];
}

/// Felder, die in jeder Spezifikation stehen sollten — fehlen sie nach
/// dem Einrichten, sagt die App es.
const List<String> kWichtigeFelder = [
  'artikelnummer',
  'bezeichnung',
  'zutaten',
  'naehrwert.energie_kj',
  'naehrwert.energie_kcal',
  'naehrwert.fett',
  'naehrwert.gesaettigte_fettsaeuren',
  'naehrwert.kohlenhydrate',
  'naehrwert.zucker',
  'naehrwert.eiweiss',
  'naehrwert.salz',
];

/// Beschriftungen, neben denen ein Wert steht: Platzhalter → Varianten
/// (klein geschrieben, ohne Einheit und Doppelpunkt).
const Map<String, List<String>> _nebenan = {
  'artikelnummer': [
    'artikelnummer',
    'artikel-nr.',
    'artikel-nr',
    'art.-nr.',
    'art.-nr',
    'article number',
    'article no.',
    'article no',
    'item number',
    'item no.',
  ],
  'bezeichnung': [
    'artikelbezeichnung',
    'bezeichnung',
    'produktbezeichnung',
    'verkehrsbezeichnung',
    'article',
    'article name',
    'product name',
    'product designation',
  ],
  'kunde': ['kunde', 'customer'],
  'sensorik.gewicht': [
    'stückgewicht',
    'stueckgewicht',
    'unit weight',
    'piece weight',
  ],
  'toleranz': ['toleranz', 'tolerance'],
  'zutaten': [
    'zutaten',
    'zutatenliste',
    'zutatenverzeichnis',
    'ingredients',
    'list of ingredients',
  ],
  'sensorik.aussehen': ['optik', 'aussehen', 'visual appearance', 'appearance'],
  'sensorik.konsistenz': ['konsistenz', 'textur', 'texture', 'consistency'],
  'sensorik.geruch': ['geruch', 'smell', 'odour', 'odor'],
  'sensorik.geschmack': ['geschmack', 'taste', 'flavour', 'flavor'],
  'sensorik.zubereitung': [
    'zubereitung',
    'zubereitungsempfehlung',
    'preparation',
  ],
  'lagerung': [
    'transport- und lagerbedingungen',
    'transport und lagerbedingungen',
    'lagerbedingungen',
    'lagerung',
    'transport and storage conditions',
    'storage conditions',
    'storage',
  ],
  'haltbarkeit': [
    'mindesthaltbarkeitsdatum',
    'mindesthaltbarkeit',
    'haltbarkeit',
    'mhd',
    'best before date',
    'best before',
    'shelf life',
  ],
  'gueltig_ab': [
    'gültig ab',
    'gueltig ab',
    'spezifikation gültig ab',
    'valid from',
    'specification valid from',
  ],
  'kuerzel': ['kürzel', 'kuerzel', 'initials'],
  'naehrwert.energie_kj': ['brennwert kj', 'energie kj', 'energy kj'],
  'naehrwert.energie_kcal': ['brennwert kcal', 'energie kcal', 'energy kcal'],
  'naehrwert.fett': ['fett', 'fat'],
  'naehrwert.gesaettigte_fettsaeuren': [
    'gesättigte fettsäuren',
    'gesaettigte fettsaeuren',
    'saturated fat',
    'saturates',
  ],
  'naehrwert.kohlenhydrate': ['kohlenhydrate', 'carbohydrate', 'carbohydrates'],
  'naehrwert.zucker': ['zucker', 'sugars', 'sugar'],
  'naehrwert.eiweiss': ['eiweiß', 'eiweiss', 'protein'],
  'naehrwert.salz': ['salz', 'salt'],
};

/// Überschriften der Produkthinweise — darunter je Zeile ein Hinweis.
const List<String> _hinweisKopf = [
  'produkthinweise',
  'hinweise',
  'verbraucherhinweise',
  'product comments',
  'product notes',
  'product information',
];

/// Die Beschriftung des Blocks der Verarbeitungshilfsstoffe.
const List<String> _hilfsstoffBlock = [
  'verarbeitungshilfsstoffe',
  'technische hilfsstoffe',
  'technical excipients',
  'processing aids',
];

const List<String> _hilfsstoffSpalte = [
  'hilfsstoff',
  'verarbeitungshilfsstoff',
  'excipient',
  'processing aid',
];

const List<String> _quellSpalte = [
  'ursprungszutat',
  'ursprung',
  'herkunft',
  'quelle',
  'enthalten in',
  'allergenursprung',
  'source',
  'origin',
  'contained in',
];

const List<String> _jaSpalte = ['ja', 'yes'];
const List<String> _neinSpalte = ['nein', 'no'];
const List<String> _spurenSpalte = ['spuren', 'spur', 'traces', 'trace'];

/// Woran eine Zeile der Allergentabelle ihr Allergen erkennt — die
/// Reihenfolge zählt: Erdnüsse vor Schalenfrüchten („Peanuts", „nuts").
const List<(String, String)> _allergenMuster = [
  ('gluten', r'gluten|getreide|cereal'),
  ('krebstiere', r'krebstier|crustacean'),
  ('eier', r'\beier|\bei\b|\beggs?\b'),
  ('fisch', r'\bfisch|\bfish'),
  ('erdnuesse', r'erdnüss|erdnuss|peanut'),
  ('soja', r'\bsoja|\bsoy'),
  ('milch', r'\bmilch|\bmilk|laktose|lactose'),
  ('schalenfruechte', r'schalenfr|nüsse|\bnuts?\b'),
  ('sellerie', r'sellerie|celery'),
  ('senf', r'\bsenf|mustard'),
  ('sesam', r'\bsesam'),
  ('sulfit', r'sulfit|\bso2|schwefeldioxid|sulphur|sulfur|sulphite'),
  ('lupinen', r'lupin'),
  ('weichtiere', r'weichtier|mollus'),
];

/// Überschriften der Verpackungsabschnitte.
const List<String> _umKopf = [
  'umverpackung',
  'umkarton',
  'secondary packaging',
  'outer packaging',
];
const List<String> _einzelKopf = [
  'einzelverpackung',
  'verkaufsverpackung',
  'primary packaging',
  'inner packaging',
];

/// Kästchen der Verpackung je Abschnitt: Platzhalter-Ende → Varianten.
const Map<String, List<String>> _umKreuze = {
  'e2_kiste': ['e2 kiste', 'e2-kiste', 'e2 euro box', 'e2 box', 'e2 crate'],
  'karton_gross': [
    'karton groß',
    'karton gross',
    'großer karton',
    'cardboard box big',
    'big cardboard box',
    'large cardboard box',
  ],
  'karton_klein': [
    'karton klein',
    'kleiner karton',
    'cardboard box small',
    'small cardboard box',
  ],
  'neutral': [
    'neutraler karton',
    'karton neutral',
    'neutral cardboard box',
    'neutral',
  ],
  'egalisiert': ['egalisiert', 'equalized packaging', 'equalized'],
  'gewogen': ['gewogen', 'weighted', 'weighed'],
};
const Map<String, List<String>> _einzelKreuze = {
  'beutel': ['beutel', 'bag'],
  'seitenfaltenbeutel': [
    'seitenfaltenbeutel e2',
    'seitenfaltenbeutel',
    'side gusseted bag e2',
    'side gusseted bag',
  ],
  'schutzgas': [
    'schutzgasatmosphäre',
    'schutzgas',
    'modified atmosphere',
    'map',
  ],
  'vakuum': ['vakuum', 'vacuum'],
  'luft': ['atmosphäre', 'atmosphere', 'luft'],
  'egalisiert': ['egalisiert', 'equalized packaging', 'equalized'],
  'gewogen': ['gewogen', 'weighted', 'weighed'],
  'gezaehlt': ['gezählt', 'gezaehlt', 'counted'],
};

/// Texte der Verpackung je Abschnitt: Platzhalter-Ende → Varianten.
const Map<String, List<String>> _umTexte = {
  'tara': ['taragewicht', 'tara', 'tare weight'],
  'netto': ['nettogewicht', 'netto', 'net weight'],
  'material': ['material', 'verpackungsmaterial'],
};
const Map<String, List<String>> _einzelTexte = {
  'tara': ['taragewicht', 'tara', 'tare weight'],
  'netto': ['nettogewicht', 'netto', 'net weight'],
  'material': ['material', 'verpackungsmaterial'],
  'anzahl': [
    'anzahl beutel je karton',
    'anzahl je karton',
    'beutel je karton',
    'stück je karton',
    'number of bags per box',
    'bags per box',
  ],
  'stueckzahl': ['stückzahl', 'stueckzahl', 'number of pieces', 'pieces'],
};

/// Eine Beschriftung, vereinfacht: klein, ohne Einheiten in Klammern,
/// ohne Doppelpunkt am Ende und ohne „davon"/„in g".
String beschriftungNorm(String text) {
  var s = text.toLowerCase().replaceAll(' ', ' ');
  s = s
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  s = s.replaceAll(RegExp(r'[:*]+$'), '').trim();
  s = s.replaceFirst(RegExp(r'^(davon|of which)\s+'), '');
  s = s.replaceFirst(RegExp(r'\s+in (g|kg|mg)$'), '');
  return s.trim();
}

/// Das Datumsfeld einer Vorlage: „xx.xx.xxxx", „TT.MM.JJJJ" …
final RegExp _datumsMaske = RegExp(
  r'\b(xx|tt|dd)\.(xx|mm)\.(xxxx|jjjj|yyyy)\b',
  caseSensitive: false,
);

/// Zeilen, die für ein Kürzel stehen.
const Set<String> _kuerzelZeilen = {
  'kürzel',
  'kuerzel',
  'kürzel:',
  'initials',
  'initialen',
  'handzeichen',
  'xx',
};

/// Die Artikelnummer in einer Kopfzeile: ein Wort hinter einem Steuercode
/// oder Zeilenanfang, direkt vor dem nächsten Steuercode.
final RegExp _kopfArtikelnummer = RegExp(
  r'''(?<=["\d\s]|^)(Artikelnummer|Artikel-Nr\.?|Art\.-Nr\.?|Article number|Item number|number)(?=&|\n|$)''',
);

/// Richtet [xlsx] ein: schreibt Platzhalter neben erkannte Beschriftungen
/// und unter erkannte Kontrollkästchen. Wirft [FormatException], wenn
/// [xlsx] keine Excel-Mappe ist.
EinrichtenErgebnis vorlageEinrichten(Uint8List xlsx) {
  if (platzhalterIn(xlsx).isNotEmpty) {
    return EinrichtenErgebnis(
      bytes: xlsx,
      felder: const {},
      schonEingerichtet: true,
    );
  }
  final mappe = XlsxMappe.lesen(xlsx);
  final felder = <String, String>{};
  for (final pfad in mappe.blattPfade) {
    final blatt = XlsxBlatt(mappe, pfad);
    final neu = _Einrichten(blatt, felder).ausfuehren(mappe.text(pfad) ?? '');
    mappe.schreibe(pfad, neu);
  }
  return EinrichtenErgebnis(bytes: mappe.packen(), felder: felder);
}

class _Einrichten {
  _Einrichten(this.blatt, this.felder);

  final XlsxBlatt blatt;

  /// Was schon vergeben ist — über alle Blätter.
  final Map<String, String> felder;

  /// Zelle → neuer Text.
  final Map<String, String> _setzen = {};

  /// Beschriftungen: vereinfachter Text und Bereich.
  late final List<({String norm, Bereich bereich, Zelle zelle})> _texte = [
    for (final z in blatt.zellen)
      if (z.text.trim().isNotEmpty)
        (
          norm: beschriftungNorm(z.text),
          bereich: blatt.bereichVon(z.zeile, z.spalte),
          zelle: z,
        ),
  ];

  bool _istBeschriftung(String norm) =>
      _nebenan.values.any((v) => v.contains(norm)) ||
      _hinweisKopf.contains(norm) ||
      _hilfsstoffBlock.contains(norm) ||
      _umKopf.contains(norm) ||
      _einzelKopf.contains(norm) ||
      _umKreuze.values.any((v) => v.contains(norm)) ||
      _einzelKreuze.values.any((v) => v.contains(norm)) ||
      _umTexte.values.any((v) => v.contains(norm)) ||
      _einzelTexte.values.any((v) => v.contains(norm)) ||
      norm.contains('karton') ||
      norm.contains('brand');

  /// Der Text in der linken oberen Zelle von [b] — leer, wenn keiner.
  String _textIn(Bereich b) => blatt.zelle(b.z1, b.s1)?.text.trim() ?? '';

  /// Die Wertzelle rechts neben [b]: die nächste angelegte Zelle (Wert-
  /// felder haben ein Format) höchstens drei Spalten weiter — ihr Bereich,
  /// wenn er in derselben Zeile beginnt und dort keine andere Beschriftung
  /// steht.
  Bereich? _rechts(Bereich b) {
    for (var s = b.s2 + 1; s <= b.s2 + 3; s++) {
      final ziel = blatt.bereichVon(b.z1, s);
      if (blatt.zelle(ziel.z1, ziel.s1) == null) continue;
      if (ziel.z1 != b.z1) return null;
      final text = _textIn(ziel);
      if (text.isNotEmpty && _istBeschriftung(beschriftungNorm(text))) {
        return null;
      }
      return ziel;
    }
    return null;
  }

  void _feld(String name, Bereich ziel, {bool kaestchen = false}) {
    if (felder.containsKey(name)) return;
    final ref = zellName(ziel.z1, ziel.s1);
    if (_setzen.containsKey(ref)) return;
    _setzen[ref] = '{{$name}}';
    felder[name] = kaestchen ? '$ref (Kästchen)' : ref;
  }

  /// Das erste Kontrollkästchen rechts von [b] in derselben Zeile.
  Kaestchen? _kaestchenRechts(Bereich b) {
    final kandidaten = [
      for (final k in blatt.kaestchen)
        if (k.zeile >= b.z1 && k.zeile <= b.z2 && k.spalte > b.s2) k,
    ]..sort((x, y) => x.spalte.compareTo(y.spalte));
    return kandidaten.isEmpty ? null : kandidaten.first;
  }

  /// Ein Kreuz: unter das Kästchen rechts daneben, sonst in die Zelle
  /// rechts daneben.
  void _kreuz(String name, Bereich b) {
    final k = _kaestchenRechts(b);
    if (k != null) {
      _feld(
        name,
        blatt.bereichVon(k.zeile, k.spalte),
        kaestchen: true,
      );
      return;
    }
    final r = _rechts(b);
    if (r != null) _feld(name, r);
  }

  String ausfuehren(String xml) {
    _einfacheFelder();
    _hinweise();
    _hilfsstoffe();
    _allergene();
    _verpackung();
    var neu = xml;
    neu = _datumUndKuerzel(neu);
    for (final MapEntry(:key, :value) in _setzen.entries) {
      neu = zelleSetzen(neu, key, value);
    }
    return _kopfzeile(neu);
  }

  void _einfacheFelder() {
    for (final t in _texte) {
      for (final MapEntry(:key, :value) in _nebenan.entries) {
        if (!value.contains(t.norm)) continue;
        final ziel = _rechts(t.bereich);
        if (ziel != null) _feld(key, ziel);
        break;
      }
    }
  }

  void _hinweise() {
    for (final t in _texte) {
      if (!_hinweisKopf.contains(t.norm)) continue;
      final erste = _rechts(t.bereich);
      if (erste == null) return;
      var platz = 1;
      _feld('hinweis.$platz', erste);
      // Darunter: solange links keine neue Beschriftung beginnt.
      for (var z = erste.z2 + 1; platz < kHinweisPlaetze; z++) {
        final links = blatt.bereichVon(z, t.bereich.s1);
        if (_textIn(links).isNotEmpty && links.z1 == z) break;
        final wert = blatt.bereichVon(z, erste.s1);
        if (wert.z1 != z || wert.s1 != erste.s1) break;
        if (blatt.zelle(z, erste.s1) == null) break;
        platz++;
        _feld('hinweis.$platz', wert);
      }
      return;
    }
  }

  void _hilfsstoffe() {
    for (final kopf in _texte) {
      if (!_hilfsstoffSpalte.contains(kopf.norm)) continue;
      final zeile = kopf.bereich.z1;
      final quelle = _texte.where(
        (t) =>
            t.bereich.z1 == zeile &&
            t.bereich.s1 > kopf.bereich.s2 &&
            _quellSpalte.contains(t.norm),
      );
      // Die Plätze: die Zeilen der Blockbeschriftung, sonst vier darunter.
      final block = _texte.where(
        (t) =>
            _hilfsstoffBlock.contains(t.norm) &&
            t.bereich.z1 > zeile &&
            t.bereich.z1 <= zeile + 2,
      );
      final von = block.isEmpty ? zeile + 1 : block.first.bereich.z1;
      final bis = block.isEmpty ? zeile + 4 : block.first.bereich.z2;
      var platz = 0;
      for (var z = von; z <= bis && platz < kHilfsstoffPlaetze; z++) {
        platz++;
        _feld(
          'hilfsstoff.$platz.name',
          blatt.bereichVon(z, kopf.bereich.s1),
        );
        if (quelle.isNotEmpty) {
          _feld(
            'hilfsstoff.$platz.quelle',
            blatt.bereichVon(z, quelle.first.bereich.s1),
          );
        }
      }
      return;
    }
  }

  void _allergene() {
    for (final ja in _texte) {
      if (!_jaSpalte.contains(ja.norm)) continue;
      final zeile = ja.bereich.z1;
      int? spalte(List<String> namen) {
        for (final t in _texte) {
          if (t.bereich.z1 == zeile && namen.contains(t.norm)) {
            return t.bereich.s1;
          }
        }
        return null;
      }

      final nein = spalte(_neinSpalte);
      if (nein == null) continue;
      final spuren = spalte(_spurenSpalte);
      final quelle = spalte(_quellSpalte);
      var gefunden = 0;
      for (var z = zeile + 1; z <= zeile + 20; z++) {
        final allergen = _allergenDerZeile(z, ja.bereich.s1);
        if (allergen == null) {
          if (gefunden > 0) break;
          continue;
        }
        gefunden++;
        void setze(String endung, int s) {
          final b = blatt.bereichVon(z, s);
          _feld(
            'allergen.$allergen.$endung',
            b,
            kaestchen: blatt.kaestchenIn(b).isNotEmpty,
          );
        }

        setze('ja', ja.bereich.s1);
        setze('nein', nein);
        if (spuren != null) setze('spuren', spuren);
        if (quelle != null) setze('quelle', quelle);
      }
      if (gefunden > 0) return;
    }
  }

  /// Das Allergen, das die Beschriftung links von [bisSpalte] in Zeile
  /// [z] nennt. Ein Text, der über die Spalten der Tabelle hinausreicht,
  /// gehört nicht dazu (etwa ein Satz über die übrigen Allergene).
  String? _allergenDerZeile(int z, int bisSpalte) {
    for (final t in _texte) {
      if (t.bereich.z1 != z || t.bereich.s2 >= bisSpalte) continue;
      final text = t.zelle.text.toLowerCase();
      for (final (allergen, muster) in _allergenMuster) {
        if (RegExp(muster).hasMatch(text)) return allergen;
      }
    }
    return null;
  }

  void _verpackung() {
    // Die Abschnitte: ab ihrer Überschrift bis zur nächsten.
    final abschnitte = <({int von, String art})>[
      for (final t in _texte)
        if (_umKopf.contains(t.norm))
          (von: t.bereich.z1, art: 'um')
        else if (_einzelKopf.contains(t.norm))
          (von: t.bereich.z1, art: 'einzel'),
    ]..sort((a, b) => a.von.compareTo(b.von));
    String? abschnitt(int zeile) {
      String? art;
      for (final a in abschnitte) {
        if (a.von <= zeile) art = a.art;
      }
      return art;
    }

    for (final t in _texte) {
      final art = abschnitt(t.bereich.z1);
      if (art == null ||
          _umKopf.contains(t.norm) ||
          _einzelKopf.contains(t.norm)) {
        continue;
      }
      final kreuze = art == 'um' ? _umKreuze : _einzelKreuze;
      final texte = art == 'um' ? _umTexte : _einzelTexte;
      var erledigt = false;
      for (final MapEntry(:key, :value) in kreuze.entries) {
        if (value.contains(t.norm)) {
          _kreuz('verpackung.$art.$key', t.bereich);
          erledigt = true;
          break;
        }
      }
      if (erledigt) continue;
      for (final MapEntry(:key, :value) in texte.entries) {
        if (value.contains(t.norm)) {
          final ziel = _rechts(t.bereich);
          if (ziel != null) _feld('verpackung.$art.$key', ziel);
          erledigt = true;
          break;
        }
      }
      if (erledigt) continue;
      // Der Karton mit Firmenaufdruck heißt nach der Firma — „… Karton",
      // „… brand".
      if (art == 'um' &&
          (t.norm.endsWith(' karton') || t.norm.endsWith(' brand'))) {
        _kreuz('verpackung.um.bedruckt', t.bereich);
      }
    }
  }

  /// „Spezifikation gültig ab xx.xx.xxxx" und eine Zeile „Kürzel" in
  /// derselben Zelle.
  String _datumUndKuerzel(String xml) {
    var neu = xml;
    for (final t in _texte) {
      final text = t.zelle.text;
      if (!_datumsMaske.hasMatch(text)) continue;
      if (felder.containsKey('gueltig_ab')) break;
      final zeilen = text
          .replaceFirst(_datumsMaske, '{{gueltig_ab}}')
          .split('\n')
          .map((z) {
        final klein = z.trim().toLowerCase();
        if (!_kuerzelZeilen.contains(klein) || felder.containsKey('kuerzel')) {
          return z;
        }
        felder['kuerzel'] = t.zelle.ref;
        return klein == 'xx' ? '{{kuerzel}}' : '${z.trimRight()} {{kuerzel}}';
      }).toList();
      felder['gueltig_ab'] = t.zelle.ref;
      neu = zelleSetzen(neu, t.zelle.ref, zeilen.join('\n'));
      break;
    }
    return neu;
  }

  /// Die Artikelnummer in der Kopfzeile, wo das Formblatt sie vorsieht.
  String _kopfzeile(String xml) => xml.replaceAllMapped(kKopfFuss, (m) {
        if (!m[1]!.endsWith('Header')) return m[0]!;
        final alt = xmlUnescape(m[2]!);
        if (!_kopfArtikelnummer.hasMatch(alt)) return m[0]!;
        felder.putIfAbsent('artikelnummer (Kopfzeile)', () => 'Kopfzeile');
        final neu = alt.replaceFirst(_kopfArtikelnummer, '{{artikelnummer}}');
        return '<${m[1]}>${xmlEscape(neu)}</${m[1]}>';
      });
}
