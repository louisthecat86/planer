import 'dart:convert';

// Die Angaben einer Spezifikation, die weder aus der Rezeptur noch aus der
// Sensorik kommen: die Artikelbezeichnung, Toleranz des Stückgewichts,
// Lagerung, Haltbarkeit, Produkthinweise, mögliche Spuren von Allergenen
// und die Verpackung.
//
// Sie gehören zum Projekt (Spalte `spezifikation`, als JSON) und gelten
// für jede Sprache: Die englische Spezifikation übersetzt die Texte auf
// Wunsch mit DeepL, Kreuze und Zahlen braucht sie nicht zu übersetzen.

/// Höchstens so viele Verarbeitungshilfsstoffe haben einen Platzhalter.
const int kHilfsstoffPlaetze = 6;

/// Höchstens so viele Produkthinweise haben einen eigenen Platzhalter.
const int kHinweisPlaetze = 6;

/// Eine Auswahl: Schlüssel im JSON und Text in der App.
typedef SpezWahl = ({String schluessel, String label});

/// Die Umverpackung — mehrere gleichzeitig möglich.
const List<SpezWahl> kUmverpackungen = [
  (schluessel: 'e2_kiste', label: 'E2-Kiste'),
  (schluessel: 'karton_gross', label: 'Karton groß'),
  (schluessel: 'karton_klein', label: 'Karton klein'),
];

/// Wie der Karton aussieht.
const List<SpezWahl> kKartonAufmachungen = [
  (schluessel: 'neutral', label: 'neutral'),
  (schluessel: 'bedruckt', label: 'Firmenkarton'),
];

/// Wie die Umverpackung gefüllt wird.
const List<SpezWahl> kUmFuellungen = [
  (schluessel: 'egalisiert', label: 'egalisiert'),
  (schluessel: 'gewogen', label: 'gewogen'),
];

/// Die Einzelverpackung — mehrere gleichzeitig möglich.
const List<SpezWahl> kEinzelverpackungen = [
  (schluessel: 'beutel', label: 'Beutel'),
  (schluessel: 'seitenfaltenbeutel', label: 'Seitenfaltenbeutel E2'),
];

/// Die Atmosphäre in der Einzelverpackung.
const List<SpezWahl> kAtmosphaeren = [
  (schluessel: 'schutzgas', label: 'Schutzgas'),
  (schluessel: 'vakuum', label: 'Vakuum'),
  (schluessel: 'luft', label: 'normale Atmosphäre'),
];

/// Wie die Einzelverpackung gefüllt wird.
const List<SpezWahl> kEinzelFuellungen = [
  (schluessel: 'egalisiert', label: 'egalisiert'),
  (schluessel: 'gewogen', label: 'gewogen'),
  (schluessel: 'gezaehlt', label: 'gezählt'),
];

String _text(Map<String, dynamic> m, String k) =>
    m[k] is String ? (m[k] as String).trim() : '';

Set<String> _menge(Map<String, dynamic> m, String k) => {
      for (final v in m[k] is List ? m[k] as List : const [])
        if (v is String && v.trim().isNotEmpty) v.trim(),
    };

List<String> _sortiert(Set<String> werte) => werte.toList()..sort();

/// Umverpackung und Einzelverpackung. Leere Texte heißen „nicht
/// angegeben"; bei einer Auswahl heißt der leere Text „nichts gewählt".
class Verpackung {
  const Verpackung({
    this.um = const {},
    this.karton = '',
    this.umFuellung = '',
    this.umTara = '',
    this.umNetto = '',
    this.umMaterial = '',
    this.einzel = const {},
    this.anzahl = '',
    this.atmosphaere = '',
    this.einzelFuellung = '',
    this.stueckzahl = '',
    this.einzelTara = '',
    this.einzelNetto = '',
    this.einzelMaterial = '',
  });

  /// Schlüssel aus [kUmverpackungen].
  final Set<String> um;

  /// Schlüssel aus [kKartonAufmachungen].
  final String karton;

  /// Schlüssel aus [kUmFuellungen].
  final String umFuellung;
  final String umTara;
  final String umNetto;
  final String umMaterial;

  /// Schlüssel aus [kEinzelverpackungen].
  final Set<String> einzel;

  /// Einzelverpackungen je Umverpackung.
  final String anzahl;

  /// Schlüssel aus [kAtmosphaeren].
  final String atmosphaere;

  /// Schlüssel aus [kEinzelFuellungen].
  final String einzelFuellung;

  /// Stück je Einzelverpackung.
  final String stueckzahl;
  final String einzelTara;
  final String einzelNetto;
  final String einzelMaterial;

  bool get leer =>
      um.isEmpty &&
      einzel.isEmpty &&
      [
        karton,
        umFuellung,
        umTara,
        umNetto,
        umMaterial,
        anzahl,
        atmosphaere,
        einzelFuellung,
        stueckzahl,
        einzelTara,
        einzelNetto,
        einzelMaterial,
      ].every((t) => t.trim().isEmpty);

  Map<String, Object> toJson() => {
        if (um.isNotEmpty) 'um': _sortiert(um),
        if (karton.isNotEmpty) 'karton': karton,
        if (umFuellung.isNotEmpty) 'umFuellung': umFuellung,
        if (umTara.isNotEmpty) 'umTara': umTara,
        if (umNetto.isNotEmpty) 'umNetto': umNetto,
        if (umMaterial.isNotEmpty) 'umMaterial': umMaterial,
        if (einzel.isNotEmpty) 'einzel': _sortiert(einzel),
        if (anzahl.isNotEmpty) 'anzahl': anzahl,
        if (atmosphaere.isNotEmpty) 'atmosphaere': atmosphaere,
        if (einzelFuellung.isNotEmpty) 'einzelFuellung': einzelFuellung,
        if (stueckzahl.isNotEmpty) 'stueckzahl': stueckzahl,
        if (einzelTara.isNotEmpty) 'einzelTara': einzelTara,
        if (einzelNetto.isNotEmpty) 'einzelNetto': einzelNetto,
        if (einzelMaterial.isNotEmpty) 'einzelMaterial': einzelMaterial,
      };

  static Verpackung ausJson(Object? json) {
    if (json is! Map<String, dynamic>) return const Verpackung();
    return Verpackung(
      um: _menge(json, 'um'),
      karton: _text(json, 'karton'),
      umFuellung: _text(json, 'umFuellung'),
      umTara: _text(json, 'umTara'),
      umNetto: _text(json, 'umNetto'),
      umMaterial: _text(json, 'umMaterial'),
      einzel: _menge(json, 'einzel'),
      anzahl: _text(json, 'anzahl'),
      atmosphaere: _text(json, 'atmosphaere'),
      einzelFuellung: _text(json, 'einzelFuellung'),
      stueckzahl: _text(json, 'stueckzahl'),
      einzelTara: _text(json, 'einzelTara'),
      einzelNetto: _text(json, 'einzelNetto'),
      einzelMaterial: _text(json, 'einzelMaterial'),
    );
  }

  Verpackung kopie({
    Set<String>? um,
    String? karton,
    String? umFuellung,
    String? umTara,
    String? umNetto,
    String? umMaterial,
    Set<String>? einzel,
    String? anzahl,
    String? atmosphaere,
    String? einzelFuellung,
    String? stueckzahl,
    String? einzelTara,
    String? einzelNetto,
    String? einzelMaterial,
  }) =>
      Verpackung(
        um: um ?? this.um,
        karton: karton ?? this.karton,
        umFuellung: umFuellung ?? this.umFuellung,
        umTara: umTara ?? this.umTara,
        umNetto: umNetto ?? this.umNetto,
        umMaterial: umMaterial ?? this.umMaterial,
        einzel: einzel ?? this.einzel,
        anzahl: anzahl ?? this.anzahl,
        atmosphaere: atmosphaere ?? this.atmosphaere,
        einzelFuellung: einzelFuellung ?? this.einzelFuellung,
        stueckzahl: stueckzahl ?? this.stueckzahl,
        einzelTara: einzelTara ?? this.einzelTara,
        einzelNetto: einzelNetto ?? this.einzelNetto,
        einzelMaterial: einzelMaterial ?? this.einzelMaterial,
      );
}

/// Was ein Projekt für seine Spezifikation selbst angibt.
class SpezAngaben {
  const SpezAngaben({
    this.bezeichnung = '',
    this.toleranz = '',
    this.lagerung = '',
    this.haltbarkeit = '',
    this.hinweise = '',
    this.spuren = const {},
    this.verpackung = const Verpackung(),
  });

  /// Die Artikelbezeichnung für die Spezifikation — leer: die des
  /// freigegebenen Artikels, sonst der Name des Projekts.
  final String bezeichnung;

  /// Toleranz des Stückgewichts, etwa „± 5".
  final String toleranz;

  /// Transport- und Lagerbedingungen, etwa „gekühlt bei +2 °C bis +7 °C".
  final String lagerung;

  /// Haltbarkeit: eine Zahl gilt als Tage, sonst steht der Text so da
  /// („12 Monate bei -18 °C"). Leer: aus dem Artikel des Planers.
  final String haltbarkeit;

  /// Produkthinweise, je Zeile einer — etwa „Vor dem Verzehr vollständig
  /// durcherhitzen."
  final String hinweise;

  /// Allergene (Planer-Werte), die als Spuren vorkommen können.
  final Set<String> spuren;

  final Verpackung verpackung;

  /// Die Produkthinweise Zeile für Zeile, ohne leere Zeilen.
  List<String> get hinweisZeilen => [
        for (final z in hinweise.split(RegExp(r'\r?\n')))
          if (z.trim().isNotEmpty) z.trim(),
      ];

  bool get leer =>
      bezeichnung.trim().isEmpty &&
      toleranz.trim().isEmpty &&
      lagerung.trim().isEmpty &&
      haltbarkeit.trim().isEmpty &&
      hinweise.trim().isEmpty &&
      spuren.isEmpty &&
      verpackung.leer;

  Map<String, Object> toJson() => {
        if (bezeichnung.trim().isNotEmpty) 'bezeichnung': bezeichnung.trim(),
        if (toleranz.isNotEmpty) 'toleranz': toleranz,
        if (lagerung.isNotEmpty) 'lagerung': lagerung,
        if (haltbarkeit.isNotEmpty) 'haltbarkeit': haltbarkeit,
        if (hinweise.trim().isNotEmpty) 'hinweise': hinweise.trim(),
        if (spuren.isNotEmpty) 'spuren': _sortiert(spuren),
        if (!verpackung.leer) 'verpackung': verpackung.toJson(),
      };

  /// JSON für die Datenbank — null, wenn nichts angegeben ist.
  String? alsJson() => leer ? null : jsonEncode(toJson());

  static SpezAngaben aus(String? json) {
    if (json == null || json.trim().isEmpty) return const SpezAngaben();
    try {
      final d = jsonDecode(json);
      if (d is! Map<String, dynamic>) return const SpezAngaben();
      return SpezAngaben(
        bezeichnung: _text(d, 'bezeichnung'),
        toleranz: _text(d, 'toleranz'),
        lagerung: _text(d, 'lagerung'),
        haltbarkeit: _text(d, 'haltbarkeit'),
        hinweise: _text(d, 'hinweise'),
        spuren: _menge(d, 'spuren'),
        verpackung: Verpackung.ausJson(d['verpackung']),
      );
    } on FormatException {
      return const SpezAngaben();
    }
  }

  SpezAngaben kopie({
    String? bezeichnung,
    String? toleranz,
    String? lagerung,
    String? haltbarkeit,
    String? hinweise,
    Set<String>? spuren,
    Verpackung? verpackung,
  }) =>
      SpezAngaben(
        bezeichnung: bezeichnung ?? this.bezeichnung,
        toleranz: toleranz ?? this.toleranz,
        lagerung: lagerung ?? this.lagerung,
        haltbarkeit: haltbarkeit ?? this.haltbarkeit,
        hinweise: hinweise ?? this.hinweise,
        spuren: spuren ?? this.spuren,
        verpackung: verpackung ?? this.verpackung,
      );
}
