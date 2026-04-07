import 'package:drift/drift.dart';
import 'production_tasks.dart';

/// Ist-Erfassung eines abgeschlossenen Auftrags.
///
/// Wird vom Produktionsleiter oder Abteilungsleiter nach Auftragsende
/// ausgefüllt und ist das **Futter für die Lernlogik**: Mittelwerte und
/// Standardabweichung in [ProductSteps] werden aus allen Runs des
/// jeweiligen Schritts berechnet.
///
/// Die Berechnung der neuen Basis-Werte läuft in der Domain-Schicht
/// (`features/production_runs/domain/`) nach jedem Insert/Update dieser
/// Tabelle — nicht als DB-Trigger, damit die Logik testbar bleibt und
/// später 1:1 in der Supabase-Sync-Schicht wiederverwendet werden kann.
class ProductionRuns extends Table {
  TextColumn get id => text()();

  TextColumn get taskId => text().references(ProductionTasks, #id)();

  /// Tatsächlich verbrauchte Zeit am Stück, in Minuten.
  RealColumn get tatsaechlicheDauerMinuten => real()();

  IntColumn get tatsaechlicheMitarbeiter => integer()();

  /// Tatsächlich produzierte Menge — kann von der geplanten abweichen
  /// (weniger Rohware da, Maschinenausfall, mehr bestellt etc.).
  RealColumn get tatsaechlicheMengeKg => real()();

  /// JSON-Objekt: welche Chargen wurden verbraucht und wieviel.
  /// Format: `{"batch_uuid_1": 45.2, "batch_uuid_2": 10.0}`
  /// Wird in der MRP-/Chargen-Logik gegen [RawMaterialBatches.mengeAktuell]
  /// verrechnet. HACCP-relevant: komplette Rückverfolgbarkeit.
  TextColumn get verwendeteChargenJson => text().nullable()();

  TextColumn get notizen => text().nullable()();

  /// Wer hat die Werte eingetragen (Freitext, in Phase 1 noch kein User-System).
  TextColumn get erfasstVon => text().nullable()();

  DateTimeColumn get erfasstAm => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
