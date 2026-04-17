import 'product_groups.dart';

/// Datentyp eines gruppenspezifischen Felds.
enum FieldType {
  number,    // Zahl (int oder double, je nach fractionDigits)
  text,      // Freitext
  boolean,   // Ja/Nein
  enumValue, // Auswahl aus enumValues
}

/// Spezifikation eines einzelnen gruppenspezifischen Felds.
///
/// Diese Felder erscheinen zusätzlich zum allgemeinen Stammdaten-Block
/// im Produkt-Sheet des Excel-Templates und werden beim Import in die
/// entsprechenden DB-Spalten geschrieben.
class FieldSpec {
  const FieldSpec({
    required this.key,
    required this.label,
    required this.type,
    required this.dbColumn,
    this.unit,
    this.required = false,
    this.help,
    this.enumValues,
    this.minValue,
    this.maxValue,
    this.fractionDigits = 0,
  });

  /// Interner Key, wird als Excel-Spaltenheader in snake_case verwendet.
  final String key;

  /// Menschenlesbares Label für die Excel-Datei.
  final String label;

  final FieldType type;

  /// Name der DB-Spalte in der `products`-Tabelle.
  /// Muss exakt mit dem Spaltennamen in `products.dart` übereinstimmen.
  final String dbColumn;

  /// Einheit zur Anzeige (°C, min, %, g, kg, ...).
  final String? unit;

  /// Pflichtfeld? Wenn ja, bricht der Import ab, wenn leer.
  final bool required;

  /// Hilfetext für den Nutzer (erscheint als Excel-Kommentar).
  final String? help;

  /// Erlaubte Werte bei [FieldType.enumValue].
  final List<String>? enumValues;

  /// Für Zahlen: min/max zur Excel-Validierung.
  final double? minValue;
  final double? maxValue;

  /// Für Zahlen: Anzahl Nachkommastellen (0 = Integer).
  final int fractionDigits;

  /// Header mit Einheit, wie er in Excel erscheint.
  String get displayLabel => unit != null ? '$label ($unit)' : label;
}

/// Zentrales Register: welche Felder gehören zu welcher Gruppe.
///
/// Der Eintrag unter [ProductGroup] ist eine Liste von [FieldSpec]s, die
/// im Produkt-Sheet-Stammdatenblock nach den allgemeinen Feldern
/// (Artikelnr, Bezeichnung, Verpackung, MHD etc.) erscheinen.
class ProductGroupFields {
  ProductGroupFields._();

  /// Allgemeine Stammdatenfelder, die für ALLE Gruppen gelten.
  /// Entsprechen den bereits vorhandenen Spalten in `products`.
  static const List<FieldSpec> allgemein = [
    FieldSpec(
      key: 'artikelnummer',
      label: 'Artikelnr',
      type: FieldType.text,
      dbColumn: 'artikelnummer',
      required: true,
      help: 'Eindeutige Artikelnummer (z.B. 10001)',
    ),
    FieldSpec(
      key: 'artikelbezeichnung',
      label: 'Bezeichnung',
      type: FieldType.text,
      dbColumn: 'artikelbezeichnung',
      required: true,
    ),
    FieldSpec(
      key: 'beschreibung',
      label: 'Beschreibung',
      type: FieldType.text,
      dbColumn: 'beschreibung',
    ),
    FieldSpec(
      key: 'produktgruppe',
      label: 'Produktgruppe',
      type: FieldType.enumValue,
      dbColumn: 'produktgruppe',
      required: true,
      help: 'Bestimmt, welche Felder unten abgefragt werden.',
      enumValues: [
        'Brühwurst',
        'Rohwurst',
        'Kochpökelwaren',
        'Rohpökelwaren',
        'Aufschnitt',
        'Bratstraßenartikel Natur',
        'Bratstraßenartikel paniert',
        'Hackprodukte gegart',
        'Hackprodukte roh',
        'Braten',
        'Sous Vide gegarte Produkte',
        'Angebratene Brühwürste',
      ],
    ),
    FieldSpec(
      key: 'verpackungsart',
      label: 'Verpackungsart',
      type: FieldType.enumValue,
      dbColumn: 'verpackungsart',
      enumValues: ['Vakuum', 'MAP', 'Skin-Pack', 'Frischetheke', 'Thermoform'],
    ),
    FieldSpec(
      key: 'gebinde_kg',
      label: 'Gebinde',
      type: FieldType.number,
      dbColumn: 'gebinde_groesse_kg',
      unit: 'kg',
      fractionDigits: 3,
      minValue: 0,
    ),
    FieldSpec(
      key: 'mhd_tage',
      label: 'MHD',
      type: FieldType.number,
      dbColumn: 'haltbarkeit_tage',
      unit: 'Tage',
      minValue: 0,
    ),
    FieldSpec(
      key: 'gesamtausbeute',
      label: 'Gesamtausbeute',
      type: FieldType.number,
      dbColumn: 'gesamt_ausbeute_faktor',
      fractionDigits: 2,
      minValue: 0,
      maxValue: 1,
      help: 'Faktor 0.0–1.0, z.B. 0.85 = 15% Verlust',
    ),
    FieldSpec(
      key: 'vorlaufzeit_tage',
      label: 'Vorlaufzeit',
      type: FieldType.number,
      dbColumn: 'mindest_vorlaufzeit_tage',
      unit: 'Tage',
      minValue: 0,
    ),
  ];

  /// Gruppenspezifische Zusatzfelder.
  static final Map<ProductGroup, List<FieldSpec>> fuerGruppe = {
    ProductGroup.bruehwurst: const [
      FieldSpec(
        key: 'braet_feinheit',
        label: 'Brät-Feinheit',
        type: FieldType.enumValue,
        dbColumn: 'braet_feinheit',
        required: true,
        enumValues: ['grob', 'mittel', 'fein'],
      ),
      FieldSpec(
        key: 'kutter_endtemp',
        label: 'Kutter-Endtemp',
        type: FieldType.number,
        dbColumn: 'kutter_endtemp_c',
        unit: '°C',
        fractionDigits: 1,
        minValue: 0,
        maxValue: 30,
      ),
      FieldSpec(
        key: 'kochkammer_programm',
        label: 'Kochkammer-Programm',
        type: FieldType.text,
        dbColumn: 'kochkammer_programm',
        required: true,
      ),
      FieldSpec(
        key: 'raeucherart',
        label: 'Räucherart',
        type: FieldType.enumValue,
        dbColumn: 'raeucherart',
        enumValues: ['keine', 'kalt', 'warm', 'heiß'],
      ),
      FieldSpec(
        key: 'ziel_kerntemp',
        label: 'Ziel-Kerntemp',
        type: FieldType.number,
        dbColumn: 'ziel_kerntemp_c',
        unit: '°C',
        required: true,
        fractionDigits: 1,
        minValue: 0,
        maxValue: 100,
      ),
    ],

    ProductGroup.rohwurst: const [
      FieldSpec(
        key: 'startkultur',
        label: 'Startkultur',
        type: FieldType.text,
        dbColumn: 'startkultur',
        required: true,
        help: 'Produktname der Starterkultur (Freitext)',
      ),
      FieldSpec(
        key: 'reifezeit_tage',
        label: 'Reifezeit',
        type: FieldType.number,
        dbColumn: 'reifezeit_tage',
        unit: 'Tage',
        required: true,
        minValue: 0,
      ),
      FieldSpec(
        key: 'klimaprogramm',
        label: 'Klimaprogramm',
        type: FieldType.text,
        dbColumn: 'klimaprogramm',
      ),
      FieldSpec(
        key: 'ziel_ph',
        label: 'Ziel-pH',
        type: FieldType.number,
        dbColumn: 'ziel_ph',
        fractionDigits: 2,
        minValue: 3,
        maxValue: 7,
      ),
      FieldSpec(
        key: 'ziel_aw',
        label: 'Ziel-aw-Wert',
        type: FieldType.number,
        dbColumn: 'ziel_aw',
        fractionDigits: 3,
        minValue: 0,
        maxValue: 1,
      ),
      FieldSpec(
        key: 'gewichtsverlust_prozent',
        label: 'Gewichtsverlust',
        type: FieldType.number,
        dbColumn: 'gewichtsverlust_prozent',
        unit: '%',
        required: true,
        fractionDigits: 1,
        minValue: 0,
        maxValue: 60,
      ),
      FieldSpec(
        key: 'raeucherart',
        label: 'Räucherart',
        type: FieldType.enumValue,
        dbColumn: 'raeucherart',
        enumValues: ['keine', 'kalt', 'warm'],
      ),
    ],

    ProductGroup.kochpoekelware: const [
      FieldSpec(
        key: 'poekelart',
        label: 'Pökelart',
        type: FieldType.enumValue,
        dbColumn: 'poekelart',
        required: true,
        enumValues: ['trocken', 'nass', 'injektion'],
      ),
      FieldSpec(
        key: 'lake_konzentration_prozent',
        label: 'Lake-Konzentration',
        type: FieldType.number,
        dbColumn: 'lake_konzentration_prozent',
        unit: '%',
        fractionDigits: 1,
        minValue: 0,
        maxValue: 30,
        help: 'Bei Nass- oder Injektionspökelung',
      ),
      FieldSpec(
        key: 'poekelzeit_tage',
        label: 'Pökelzeit',
        type: FieldType.number,
        dbColumn: 'poekelzeit_tage',
        unit: 'Tage',
        required: true,
        minValue: 0,
      ),
      FieldSpec(
        key: 'tumbelzeit_min',
        label: 'Tumbelzeit',
        type: FieldType.number,
        dbColumn: 'tumbelzeit_min',
        unit: 'min',
        minValue: 0,
        help: 'Nur wenn getumbelt wird',
      ),
      FieldSpec(
        key: 'ziel_kerntemp',
        label: 'Ziel-Kerntemp',
        type: FieldType.number,
        dbColumn: 'ziel_kerntemp_c',
        unit: '°C',
        required: true,
        fractionDigits: 1,
        minValue: 0,
        maxValue: 100,
      ),
      FieldSpec(
        key: 'raeucherart',
        label: 'Räucherart',
        type: FieldType.enumValue,
        dbColumn: 'raeucherart',
        enumValues: ['keine', 'kalt', 'warm', 'heiß'],
      ),
    ],

    ProductGroup.rohpoekelware: const [
      FieldSpec(
        key: 'poekelart',
        label: 'Pökelart',
        type: FieldType.enumValue,
        dbColumn: 'poekelart',
        required: true,
        enumValues: ['trocken', 'nass'],
      ),
      FieldSpec(
        key: 'poekelzeit_tage',
        label: 'Pökelzeit',
        type: FieldType.number,
        dbColumn: 'poekelzeit_tage',
        unit: 'Tage',
        required: true,
        minValue: 0,
      ),
      FieldSpec(
        key: 'reifezeit_tage',
        label: 'Reifezeit',
        type: FieldType.number,
        dbColumn: 'reifezeit_tage',
        unit: 'Tage',
        required: true,
        minValue: 0,
      ),
      FieldSpec(
        key: 'trocknungsverlust_prozent',
        label: 'Trocknungsverlust',
        type: FieldType.number,
        dbColumn: 'gewichtsverlust_prozent',
        unit: '%',
        fractionDigits: 1,
        minValue: 0,
        maxValue: 60,
      ),
      FieldSpec(
        key: 'ziel_aw',
        label: 'Ziel-aw-Wert',
        type: FieldType.number,
        dbColumn: 'ziel_aw',
        fractionDigits: 3,
        minValue: 0,
        maxValue: 1,
      ),
      FieldSpec(
        key: 'raeucherart',
        label: 'Räucherart',
        type: FieldType.enumValue,
        dbColumn: 'raeucherart',
        enumValues: ['keine', 'kalt', 'warm'],
      ),
    ],

    ProductGroup.aufschnitt: const [
      FieldSpec(
        key: 'basis_produkt_artikelnr',
        label: 'Basis-Artikelnr',
        type: FieldType.text,
        dbColumn: 'basis_produkt_artikelnummer',
        required: true,
        help: 'Artikelnummer des Produkts, das aufgeschnitten wird (z.B. Kochschinken 10003)',
      ),
      FieldSpec(
        key: 'scheibendicke_mm',
        label: 'Scheibendicke',
        type: FieldType.number,
        dbColumn: 'scheibendicke_mm',
        unit: 'mm',
        required: true,
        fractionDigits: 1,
        minValue: 0.1,
        maxValue: 20,
      ),
      FieldSpec(
        key: 'scheiben_pro_packung',
        label: 'Scheiben pro Packung',
        type: FieldType.number,
        dbColumn: 'scheiben_pro_packung',
        minValue: 1,
      ),
      FieldSpec(
        key: 'packungsgewicht_g',
        label: 'Packungsgewicht',
        type: FieldType.number,
        dbColumn: 'packungsgewicht_g',
        unit: 'g',
        required: true,
        minValue: 0,
      ),
      FieldSpec(
        key: 'map_gas',
        label: 'MAP-Gasgemisch',
        type: FieldType.text,
        dbColumn: 'map_gas',
        help: 'z.B. 70% N₂ / 30% CO₂',
      ),
    ],

    ProductGroup.bratstrasseNatur: const [
      FieldSpec(
        key: 'formgewicht_g',
        label: 'Formgewicht',
        type: FieldType.number,
        dbColumn: 'formgewicht_g',
        unit: 'g',
        required: true,
        minValue: 0,
      ),
      FieldSpec(
        key: 'form',
        label: 'Form',
        type: FieldType.enumValue,
        dbColumn: 'form',
        enumValues: ['rund', 'oval', 'patty', 'länglich'],
      ),
      FieldSpec(
        key: 'ziel_kerntemp',
        label: 'Ziel-Kerntemp',
        type: FieldType.number,
        dbColumn: 'ziel_kerntemp_c',
        unit: '°C',
        required: true,
        fractionDigits: 1,
        minValue: 0,
        maxValue: 100,
      ),
      FieldSpec(
        key: 'bratgrad',
        label: 'Bratgrad',
        type: FieldType.enumValue,
        dbColumn: 'bratgrad',
        enumValues: ['leicht', 'mittel', 'durch'],
      ),
    ],

    ProductGroup.bratstrassePaniert: const [
      FieldSpec(
        key: 'panierart',
        label: 'Panierart',
        type: FieldType.enumValue,
        dbColumn: 'panierart',
        required: true,
        enumValues: ['Mehl', 'Paniermehl', 'Panko', 'Cornflakes', 'Sonstige'],
      ),
      FieldSpec(
        key: 'panier_aufnahme_prozent',
        label: 'Panier-Aufnahme',
        type: FieldType.number,
        dbColumn: 'panier_aufnahme_prozent',
        unit: '%',
        fractionDigits: 1,
        minValue: 0,
        maxValue: 50,
      ),
      FieldSpec(
        key: 'formgewicht_g',
        label: 'Formgewicht',
        type: FieldType.number,
        dbColumn: 'formgewicht_g',
        unit: 'g',
        required: true,
        minValue: 0,
      ),
      FieldSpec(
        key: 'ziel_kerntemp',
        label: 'Ziel-Kerntemp',
        type: FieldType.number,
        dbColumn: 'ziel_kerntemp_c',
        unit: '°C',
        required: true,
        fractionDigits: 1,
        minValue: 0,
        maxValue: 100,
      ),
    ],

    ProductGroup.hackproduktGegart: const [
      FieldSpec(
        key: 'fleischanteil_typ',
        label: 'Fleischanteil-Typ',
        type: FieldType.enumValue,
        dbColumn: 'fleischanteil_typ',
        required: true,
        enumValues: ['S1', 'S8', 'gemischt', 'R1', 'R8'],
      ),
      FieldSpec(
        key: 'ziel_kerntemp',
        label: 'Ziel-Kerntemp',
        type: FieldType.number,
        dbColumn: 'ziel_kerntemp_c',
        unit: '°C',
        required: true,
        fractionDigits: 1,
        minValue: 0,
        maxValue: 100,
      ),
      FieldSpec(
        key: 'abkuehlgradient',
        label: 'Abkühlgradient',
        type: FieldType.text,
        dbColumn: 'abkuehlgradient',
        help: 'z.B. "auf 7°C in 90 min"',
      ),
    ],

    ProductGroup.hackproduktRoh: const [
      FieldSpec(
        key: 'fleischanteil_typ',
        label: 'Fleischanteil-Typ',
        type: FieldType.enumValue,
        dbColumn: 'fleischanteil_typ',
        required: true,
        enumValues: ['S1', 'S8', 'gemischt', 'R1', 'R8'],
      ),
      FieldSpec(
        key: 'gesamtdurchlaufzeit_max_std',
        label: 'Gesamtdurchlaufzeit max',
        type: FieldType.number,
        dbColumn: 'gesamtdurchlaufzeit_max_std',
        unit: 'Std',
        required: true,
        minValue: 0,
        help: 'Frische-Fenster — max. Zeit von Zerlegung bis Verpackung',
      ),
      FieldSpec(
        key: 'wolf_lochscheibe_mm',
        label: 'Wolf-Lochscheibe',
        type: FieldType.number,
        dbColumn: 'wolf_lochscheibe_mm',
        unit: 'mm',
        fractionDigits: 1,
        minValue: 0,
      ),
    ],

    ProductGroup.braten: const [
      FieldSpec(
        key: 'braten_variante',
        label: 'Variante',
        type: FieldType.enumValue,
        dbColumn: 'braten_variante',
        required: true,
        enumValues: ['roh', 'vorgegart'],
      ),
      FieldSpec(
        key: 'fuellung',
        label: 'Füllung',
        type: FieldType.text,
        dbColumn: 'fuellung',
        help: 'Leer = keine Füllung',
      ),
      FieldSpec(
        key: 'netzbindung',
        label: 'Netzbindung',
        type: FieldType.boolean,
        dbColumn: 'netzbindung',
      ),
      FieldSpec(
        key: 'ziel_kerntemp',
        label: 'Ziel-Kerntemp',
        type: FieldType.number,
        dbColumn: 'ziel_kerntemp_c',
        unit: '°C',
        fractionDigits: 1,
        minValue: 0,
        maxValue: 100,
        help: 'Nur bei Variante = vorgegart',
      ),
    ],

    ProductGroup.sousVide: const [
      FieldSpec(
        key: 'sv_badtemp',
        label: 'SV-Badtemp',
        type: FieldType.number,
        dbColumn: 'sv_badtemp_c',
        unit: '°C',
        required: true,
        fractionDigits: 1,
        minValue: 40,
        maxValue: 95,
      ),
      FieldSpec(
        key: 'sv_garzeit_std',
        label: 'SV-Garzeit',
        type: FieldType.number,
        dbColumn: 'sv_garzeit_std',
        unit: 'Std',
        required: true,
        fractionDigits: 1,
        minValue: 0,
      ),
      FieldSpec(
        key: 'ziel_kerntemp',
        label: 'Ziel-Kerntemp',
        type: FieldType.number,
        dbColumn: 'ziel_kerntemp_c',
        unit: '°C',
        required: true,
        fractionDigits: 1,
        minValue: 0,
        maxValue: 100,
      ),
      FieldSpec(
        key: 'abkuehlgradient',
        label: 'Abkühlgradient',
        type: FieldType.text,
        dbColumn: 'abkuehlgradient',
      ),
    ],

    ProductGroup.angebrateneBruehwurst: const [
      FieldSpec(
        key: 'braet_feinheit',
        label: 'Brät-Feinheit',
        type: FieldType.enumValue,
        dbColumn: 'braet_feinheit',
        required: true,
        enumValues: ['grob', 'mittel', 'fein'],
      ),
      FieldSpec(
        key: 'kutter_endtemp',
        label: 'Kutter-Endtemp',
        type: FieldType.number,
        dbColumn: 'kutter_endtemp_c',
        unit: '°C',
        fractionDigits: 1,
        minValue: 0,
        maxValue: 30,
      ),
      FieldSpec(
        key: 'kochkammer_programm',
        label: 'Kochkammer-Programm',
        type: FieldType.text,
        dbColumn: 'kochkammer_programm',
        required: true,
      ),
      FieldSpec(
        key: 'anbratgrad',
        label: 'Anbratgrad',
        type: FieldType.enumValue,
        dbColumn: 'anbratgrad',
        required: true,
        enumValues: ['hell', 'mittel', 'dunkel'],
      ),
      FieldSpec(
        key: 'ziel_kerntemp',
        label: 'Ziel-Kerntemp',
        type: FieldType.number,
        dbColumn: 'ziel_kerntemp_c',
        unit: '°C',
        required: true,
        fractionDigits: 1,
        minValue: 0,
        maxValue: 100,
      ),
    ],
  };

  /// Liefert alle Felder (allgemein + gruppenspezifisch) für eine Gruppe.
  static List<FieldSpec> alleFelderFuer(ProductGroup group) {
    return [
      ...allgemein,
      ...(fuerGruppe[group] ?? []),
    ];
  }

  /// Liefert nur die Pflichtfelder einer Gruppe.
  static List<FieldSpec> pflichtfelderFuer(ProductGroup group) {
    return alleFelderFuer(group).where((f) => f.required).toList();
  }
}