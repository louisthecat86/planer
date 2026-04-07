import 'package:drift/drift.dart';
import 'raw_materials.dart';

/// Bestellliste pro Woche — das, was der Produktionsleiter abhakt,
/// wenn er beim Lieferanten anruft.
///
/// Wird in Phase 4 vom MRP-Modul automatisch erzeugt: Für jede Woche
/// wird aus allen [ProductionTasks] der Rohwaren-Bedarf aufsummiert,
/// der aktuelle Lagerbestand ([RawMaterialBatches.mengeAktuell]) abgezogen,
/// und die Differenz landet hier als [benoetigteMenge].
///
/// Der Produktionsleiter kann Einträge manuell hinzufügen, Mengen anpassen
/// und jeden Eintrag in zwei Stufen abhaken:
///   1. [bestellt] = Anruf/Mail an Lieferant raus
///   2. [geliefert] = Ware ist eingegangen (triggert idealerweise das Anlegen
///      einer neuen [RawMaterialBatches]-Zeile)
class OrderListItems extends Table {
  TextColumn get id => text()();

  TextColumn get rawMaterialId => text().references(RawMaterials, #id)();

  /// Montag der Woche, für die bestellt wird (00:00 Uhr lokal).
  DateTimeColumn get wocheStartDatum => dateTime()();

  RealColumn get benoetigteMenge => real()();

  /// Denormalisiert aus [RawMaterials.einheit], damit die Liste auch dann
  /// korrekt angezeigt wird, wenn sich die Stammdaten nachträglich ändern.
  TextColumn get einheit => text()();

  BoolColumn get bestellt => boolean().withDefault(const Constant(false))();
  DateTimeColumn get bestelltAm => dateTime().nullable()();

  BoolColumn get geliefert => boolean().withDefault(const Constant(false))();
  DateTimeColumn get geliefertAm => dateTime().nullable()();

  TextColumn get notizen => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
