import 'package:drift/drift.dart';
import 'raw_materials.dart';

/// Konkrete Charge einer Rohware im Lager.
///
/// Eine Charge entsteht beim Wareneingang und repräsentiert eine physische
/// Lieferung mit eigenem MHD und Lieferanten-Chargennummer (HACCP-relevant).
///
/// **Design-Entscheidung:** Das in der ursprünglichen Planung separate `stock`-
/// Table wurde in [mengeAktuell] dieser Tabelle zusammengeführt. Grund: Bestand
/// ist immer chargen-gebunden (HACCP), eine separate Stock-Tabelle wäre reine
/// Duplikation. Der Gesamtbestand einer Rohware ergibt sich als
/// `SUM(menge_aktuell) WHERE raw_material_id = X AND deleted_at IS NULL`.
class RawMaterialBatches extends Table {
  TextColumn get id => text()();

  TextColumn get rawMaterialId => text().references(RawMaterials, #id)();

  /// Chargennummer vom Lieferanten (wie auf dem Lieferschein).
  TextColumn get chargennummer => text()();

  /// Mindesthaltbarkeitsdatum. Nullable, weil nicht jede Rohware eins hat.
  DateTimeColumn get mhd => dateTime().nullable()();

  /// Wann die Charge ins Lager kam.
  DateTimeColumn get eingangsDatum => dateTime()();

  /// Ursprünglich gelieferte Menge (bleibt konstant, historisch).
  RealColumn get mengeInitial => real()();

  /// Aktuell noch verfügbare Menge in der Charge. Wird bei jedem Verbrauch
  /// durch einen ProductionRun dekrementiert. Bei 0 ist die Charge leer,
  /// wird aber **nicht gelöscht** (HACCP-Nachvollziehbarkeit).
  RealColumn get mengeAktuell => real()();

  /// Einheit — denormalisiert aus [RawMaterials.einheit], damit historische
  /// Chargen ihre Einheit behalten, falls sich die Stammdaten ändern.
  TextColumn get einheit => text()();

  TextColumn get lieferant => text().nullable()();
  TextColumn get notizen => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
