import 'package:drift/drift.dart';

/// Artikelkatalog aus Navision (Dynamics NAV), eingelesen aus der
/// Artikelübersicht-Excel.
///
/// Bewusst eine EIGENE Tabelle neben [Products]: Navision ist die
/// Warenwirtschaft und liefert *was* gebraucht wird — Bestand, offene
/// Aufträge, Kategorien. Die App-Artikel beschreiben dagegen *wie*
/// produziert wird (Schritte, Anlagen, Leistungsdaten). Beides zu
/// vermischen würde bedeuten, dass ein Navision-Import die mühsam
/// gepflegten Prozessdaten überschreibt.
///
/// Die Verbindung entsteht über die Artikelnummer — sie ist in beiden
/// Systemen dieselbe.
@DataClassName('NavisionArtikel')
class NavisionArtikelKatalog extends Table {
  /// Artikelnummer aus Navision (Spalte „Nr."). Zugleich Schlüssel zur
  /// App-Artikelnummer.
  TextColumn get nummer => text()();

  /// Zusatzkennung („Nummer 2"), z.B. LOHNFERTIGUNG.
  TextColumn get nummer2 => text().nullable()();

  TextColumn get beschreibung => text().withDefault(const Constant(''))();
  TextColumn get beschreibung2 => text().nullable()();

  /// Suchbegriff — enthält bei euch u.a. die Allergen-Hinweise.
  TextColumn get suchbegriff => text().nullable()();

  TextColumn get pluCode => text().nullable()();
  TextColumn get stuecklistenNr => text().nullable()();
  TextColumn get basiseinheit => text().nullable()();

  /// Aktueller Lagerbestand.
  RealColumn get lagerbestand => real().withDefault(const Constant(0))();

  /// Menge, die bereits in Fertigungsaufträgen steckt (also verplant).
  RealColumn get mengeInFa => real().withDefault(const Constant(0))();

  /// Menge in Kundenaufträgen — der eigentliche Bedarfstreiber.
  RealColumn get mengeInAuftrag => real().withDefault(const Constant(0))();

  TextColumn get produktbuchungsgruppe => text().nullable()();
  TextColumn get artikelkategorie => text().nullable()();
  TextColumn get produktgruppe => text().nullable()();

  /// Wann dieser Stand aus Navision gezogen wurde.
  DateTimeColumn get importiertAm =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {nummer};
}
