import 'package:drift/drift.dart';

/// Was Navision über einen Artikel weiß — der Stand der zuletzt
/// eingelesenen Artikelübersicht, je Artikelnummer eine Zeile.
///
/// Anders als [Products] stehen hier ALLE Artikel der Übersicht, auch
/// Rohwaren, Zutaten und solche, die es in der App nicht gibt. Daraus
/// liest die App, was sie selbst nicht pflegt: ob ein Artikel in Navision
/// noch als Muster geführt wird (Spalte „Nummer 2") und zu welchen Gruppen
/// er dort gehört.
///
/// Eingelesen wird ergänzend: Eine Übersicht mit weniger Artikeln — etwa
/// gefiltert — lässt die übrigen Zeilen stehen.
@DataClassName('NavisionArtikelZeile')
class NavisionArtikel extends Table {
  @override
  String get tableName => 'navision_artikel';

  /// Artikelnummer (Spalte „Nr.") — dieselbe wie in der App.
  TextColumn get artikelnummer => text()();

  /// Spalte „Nummer 2". Steht dort „MUSTER", ist der Artikel noch kein
  /// Bestandsartikel.
  TextColumn get nummer2 => text().nullable()();

  TextColumn get beschreibung => text().withDefault(const Constant(''))();
  TextColumn get beschreibung2 => text().nullable()();

  /// Trägt u.a. die Allergen-Hinweise.
  TextColumn get suchbegriff => text().nullable()();
  TextColumn get basiseinheit => text().nullable()();

  /// Woran sich Rohwaren und Zutaten von Fertigware unterscheiden lassen.
  TextColumn get produktbuchungsgruppe => text().nullable()();
  TextColumn get artikelkategorie => text().nullable()();
  TextColumn get produktgruppe => text().nullable()();

  /// Wann diese Zeile zuletzt aus einer Übersicht kam.
  DateTimeColumn get eingelesenAm => dateTime()();

  @override
  Set<Column> get primaryKey => {artikelnummer};
}
