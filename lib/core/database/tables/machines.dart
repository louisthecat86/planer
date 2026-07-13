import 'package:drift/drift.dart';

/// Anlagen-Katalog — zentrale Referenz für alle Maschinen im Betrieb.
///
/// Wird beim Excel-Import aus dem „Anlagen-Katalog"-Sheet der v3-Vorlage
/// befüllt. [ProductSteps] verweist über [ProductSteps.maschineId] auf
/// eine Zeile dieser Tabelle.
///
/// Der Name ist eindeutig, die Abteilungs-Zuordnung ist Pflicht.
/// [typischeParameter] ist reine Dokumentation (aus dem Excel-Katalog
/// übernommen, kein Verhalten).
@DataClassName('Machine')
class Machines extends Table {
  /// UUID.
  TextColumn get id => text()();

  /// Eindeutiger Anlagen-Name (z.B. "Verbufa 1", "Bratstraße", "Dampftunnel").
  /// Entspricht der Spalte A im „Anlagen-Katalog"-Sheet.
  TextColumn get name => text().unique()();

  /// Abteilungs-dbValue (z.B. "bratstrasse", "wurstkueche").
  /// Beim Import wird der Klartext aus Spalte B ("Bratstraße" usw.)
  /// auf den dbValue gemappt.
  TextColumn get abteilung => text()();

  /// Typische Einstellungs-Parameter als Freitext (Spalte C im Katalog).
  /// Pure Dokumentation, keine Funktion.
  TextColumn get typischeParameter => text().nullable()();

  // -- Kapazitätsplanung -------------------------------------------------

  /// Ob diese Anlage im Planungsboard eine EIGENE Kapazitätsspur bekommt.
  ///
  /// Hintergrund: In der Verpackung laufen mehrere Anlagen echt parallel
  /// (Multivac, Tiefzieher/Hartschale, Kleinbeutel). Ohne eigene Spuren
  /// würde die Abteilung mit einer 8-h-Kapazität rechnen, obwohl real
  /// das Mehrfache zur Verfügung steht.
  ///
  /// `false` = die Anlage teilt sich die Kapazität ihrer Abteilung
  /// (Normalfall, z.B. eine Bratstraßen-Linie).
  BoolColumn get istPlanungsressource =>
      boolean().withDefault(const Constant(false))();

  /// Tageskapazität dieser Anlage in Minuten (Standard: 8 h).
  /// Nur relevant, wenn [istPlanungsressource] gesetzt ist.
  RealColumn get kapazitaetMinutenProTag =>
      real().withDefault(const Constant(480))();

  /// Kurzer Eignungs-Hinweis für die Planung, z.B.
  /// „nur Aufschnitt / Weberslicer" oder „Ausweichanlage für Multivac".
  ///
  /// Rein informativ — die App verbietet nichts. Die Flexibilität im
  /// Betrieb ist ein Wert und soll nicht durch harte Regeln blockiert
  /// werden; der Hinweis macht nur sichtbar, was üblich ist.
  TextColumn get eignungHinweis => text().nullable()();

  // -- Sync-Felder -------------------------------------------------------

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}