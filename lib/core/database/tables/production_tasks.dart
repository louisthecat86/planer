import 'package:drift/drift.dart';
import 'products.dart';

/// Ein geplanter Produktions-Auftrag in der Wochenplanung.
///
/// Jede Karte auf dem Whiteboard entspricht einem Eintrag hier. Aus den
/// [ProductSteps] eines Produkts werden bei der Anlage automatisch
/// vorgelagerte Tasks über [parentTaskId] erzeugt — so entsteht die
/// Abhängigkeits-Kette zwischen Abteilungen.
///
/// Die `geplante_*`-Felder werden beim Anlegen aus den `basis_*`-Werten
/// der [ProductSteps] skaliert, können danach aber manuell übersteuert
/// werden (Produktionsleiter weiß es diese Woche besser).
class ProductionTasks extends Table {
  TextColumn get id => text()();

  TextColumn get productId => text().references(Products, #id)();

  RealColumn get mengeKg => real()();

  /// Das Datum, für das der Auftrag geplant ist (Konvention: 00:00 Uhr lokal).
  DateTimeColumn get datum => dateTime()();

  /// Abteilung, in der dieser Task ausgeführt wird.
  /// Gespeichert als [Abteilung.dbValue].
  TextColumn get abteilung => text()();

  /// Geplante Startzeit als "HH:MM"-String (z.B. "08:30"). Null, wenn der
  /// Task für den Tag geplant ist, aber keine feste Uhrzeit hat.
  TextColumn get startZeit => text().nullable()();

  /// Aus Skalierung berechnete Dauer, aber speicherbar, weil manuell
  /// übersteuerbar.
  RealColumn get geplanteDauerMinuten => real()();

  IntColumn get geplanteMitarbeiter => integer()();

  /// Status des Auftrags. Erlaubte Werte (als Konstanten im Repo-Layer):
  /// 'geplant', 'in_arbeit', 'fertig', 'storniert'.
  TextColumn get status =>
      text().withDefault(const Constant('geplant'))();

  /// Self-Referenz für automatisch erzeugte Vor-Tasks.
  /// Beispiel: Auftrag "Leberkäse Bratstraße" erzeugt vorgelagert
  /// "Leberkäse Wurstküche" und "Leberkäse Zerlegung" — alle mit
  /// parent_task_id auf den Bratstraßen-Task.
  TextColumn get parentTaskId => text().nullable()();

  TextColumn get notizen => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
