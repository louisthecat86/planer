import 'package:drift/drift.dart';

/// Auftragsbestand aus Navision (Bericht 50018), je Artikel.
///
/// Ein Abbild des zuletzt eingelesenen Berichts — wie der Navision-
/// Artikelkatalog: Jeder Import ersetzt den kompletten Stand, deshalb gibt
/// es hier keine Sync-Felder und kein Soft-Delete.
///
/// Stand und Zeitraum des Berichts stehen bewusst an jeder Zeile und nicht
/// in den App-Einstellungen. Die Einstellungen stellt ein Backup wieder
/// her, diese Tabelle nicht. Stünde der Stand dort, zeigte die App nach
/// einem Restore einen Stand zu Daten, die es gar nicht gibt.
@DataClassName('AuftragsArtikel')
class AuftragsbestandArtikel extends Table {
  /// Navision-Artikelnummer — dieselbe wie in der App.
  TextColumn get artikelnummer => text()();

  TextColumn get bezeichnung => text().withDefault(const Constant(''))();

  /// Zweite Zeile der Bezeichnung, z.B. „geschnitten, egal. 500g Pack".
  TextColumn get bezeichnung2 => text().nullable()();

  /// „Nettogewicht Auf Lager" laut Bericht, in kg.
  RealColumn get lagerKg => real().withDefault(const Constant(0))();

  /// Summe aller Auftragszeilen im Zeitraum, in kg (Zeile „Gesamt").
  RealColumn get auftragKg => real().withDefault(const Constant(0))();

  /// Dieselbe Summe in der Einheit des Berichts, z.B. 35 PACK.
  RealColumn get auftragMenge => real().nullable()();
  TextColumn get auftragEinheit => text().nullable()();

  /// Wann Navision den Bericht erzeugt hat (Kopf des Berichts).
  DateTimeColumn get berichtStand => dateTime().nullable()();

  /// Filterzeitraum des Berichts (Warenausgang von … bis).
  DateTimeColumn get zeitraumVon => dateTime().nullable()();
  DateTimeColumn get zeitraumBis => dateTime().nullable()();

  /// Wann die Datei in die App eingelesen wurde.
  DateTimeColumn get importiertAm =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {artikelnummer};
}

/// Eine Auftragszeile des Berichts: ein Kundenauftrag für einen Artikel.
///
/// Die Menge steht in der Verkaufseinheit (PACK, KT, STCK …), das
/// Nettogewicht immer in kg. Gerechnet wird ausschließlich mit dem
/// Nettogewicht — Umrechnungsfaktoren braucht es dafür nicht.
@DataClassName('AuftragsPosition')
class AuftragsbestandPositionen extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get artikelnummer => text()();

  /// Belegnummer des Verkaufsauftrags, z.B. „VA2608879".
  TextColumn get beleg => text()();

  /// Kunde laut Bericht.
  TextColumn get debitor => text().withDefault(const Constant(''))();

  /// Warenausgangsdatum — der Tag, an dem die Ware das Haus verlässt.
  DateTimeColumn get warenausgang => dateTime()();

  /// Lieferdatum beim Kunden. In den bisherigen Berichten immer leer.
  DateTimeColumn get lieferdatum => dateTime().nullable()();

  /// Menge in der Verkaufseinheit.
  RealColumn get menge => real().withDefault(const Constant(0))();
  TextColumn get einheit => text().nullable()();

  /// Nettogewicht in kg.
  RealColumn get kg => real().withDefault(const Constant(0))();
}
