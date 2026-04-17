/// Produktgruppen im Fleischbereich.
///
/// Jede Gruppe bestimmt, welche gruppenspezifischen Felder beim
/// Template-Export/-Import abgefragt werden. Die eigentliche
/// Feldspezifikation pro Gruppe liegt in [product_group_fields.dart].
///
/// Die [dbValue]-Strings werden in der Datenbank und im Excel-Template
/// gespeichert. **Diese Strings niemals ändern**, ohne eine Migration
/// und eine Template-Migration zu schreiben.
enum ProductGroup {
  bruehwurst(
    dbValue: 'bruehwurst',
    label: 'Brühwurst',
    beschreibung: 'Leberkäse, Wiener, Bockwurst, Fleischwurst',
  ),
  rohwurst(
    dbValue: 'rohwurst',
    label: 'Rohwurst',
    beschreibung: 'Salami, Landjäger, Mettwurst',
  ),
  kochpoekelware(
    dbValue: 'kochpoekelware',
    label: 'Kochpökelwaren',
    beschreibung: 'Kochschinken, Kasseler, Bierschinken',
  ),
  rohpoekelware(
    dbValue: 'rohpoekelware',
    label: 'Rohpökelwaren',
    beschreibung: 'Schinkenspeck, Lachsschinken, Bündnerfleisch',
  ),
  aufschnitt(
    dbValue: 'aufschnitt',
    label: 'Aufschnitt',
    beschreibung: 'Wurst/Schinken in Scheiben, MAP',
  ),
  bratstrasseNatur(
    dbValue: 'bratstrasse_natur',
    label: 'Bratstraßenartikel Natur',
    beschreibung: 'Frikadellen, Boulette, Hacksteak (unpaniert)',
  ),
  bratstrassePaniert(
    dbValue: 'bratstrasse_paniert',
    label: 'Bratstraßenartikel paniert',
    beschreibung: 'Schnitzel, Cordon Bleu, Nuggets',
  ),
  hackproduktGegart(
    dbValue: 'hackprodukt_gegart',
    label: 'Hackprodukte gegart',
    beschreibung: 'Fleischkäse-Hack, gegarte Bolognese, Chili',
  ),
  hackproduktRoh(
    dbValue: 'hackprodukt_roh',
    label: 'Hackprodukte roh',
    beschreibung: 'Hackfleisch gemischt, Mett, Cevapcici roh',
  ),
  braten(
    dbValue: 'braten',
    label: 'Braten',
    beschreibung: 'Rollbraten, Krustenbraten, Schweinebraten',
  ),
  sousVide(
    dbValue: 'sous_vide',
    label: 'Sous Vide gegarte Produkte',
    beschreibung: 'Pulled Pork, Rinderbäckchen, Rippchen',
  ),
  angebrateneBruehwurst(
    dbValue: 'angebratene_bruehwurst',
    label: 'Angebratene Brühwürste',
    beschreibung: 'Weiße/Rote Bratwurst, angebraten',
  );

  const ProductGroup({
    required this.dbValue,
    required this.label,
    required this.beschreibung,
  });

  final String dbValue;
  final String label;
  final String beschreibung;

  /// Parst einen in der Datenbank oder Excel gespeicherten String zurück.
  ///
  /// Wirft einen [ArgumentError], wenn der Wert unbekannt ist.
  static ProductGroup fromDbValue(String value) {
    return ProductGroup.values.firstWhere(
      (g) => g.dbValue == value,
      orElse: () => throw ArgumentError(
        'Unbekannte Produktgruppe: "$value". '
        'Wurde das Enum geändert ohne Migration?',
      ),
    );
  }

  /// Versucht einen String zu parsen, liefert null wenn unbekannt.
  /// Nützlich für toleranten Excel-Import.
  static ProductGroup? tryFromAnyString(String value) {
    final normalized = value.trim().toLowerCase();
    for (final g in ProductGroup.values) {
      if (g.dbValue == normalized) return g;
      if (g.label.toLowerCase() == normalized) return g;
      // Fuzzy: "Brühwurst" == "bruehwurst" == "brühwurst"
      final normalizedLabel = g.label
          .toLowerCase()
          .replaceAll('ü', 'ue')
          .replaceAll('ö', 'oe')
          .replaceAll('ä', 'ae')
          .replaceAll('ß', 'ss');
      final normalizedInput = normalized
          .replaceAll('ü', 'ue')
          .replaceAll('ö', 'oe')
          .replaceAll('ä', 'ae')
          .replaceAll('ß', 'ss');
      if (normalizedLabel == normalizedInput) return g;
    }
    return null;
  }
}