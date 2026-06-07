import 'package:drift/drift.dart';

/// Eingefrorener Snapshot einer Planungswoche.
///
/// Beim „Woche archivieren" wird der komplette Plan der Woche (alle Aufträge
/// je Abteilung/Tag samt Mengen, Dauern, Personen) zusammen mit den zu dem
/// Zeitpunkt gültigen Tageskapazitäten als JSON eingefroren. Der Snapshot ist
/// **unveränderlich** — spätere Umplanungen ändern ihn nicht. So bleibt
/// nachvollziehbar, was in einer vergangenen KW geplant war, und man kann
/// Kennzahlen/Erkenntnisse daraus ziehen.
///
/// Die eigentlichen Daten liegen in [datenJson] (siehe
/// `week_snapshot_service.dart` für das Format), damit der Snapshot in einem
/// Stück gelesen und ausgewertet werden kann.
class WeekSnapshots extends Table {
  TextColumn get id => text()();

  /// Montag der Woche, 00:00 Uhr.
  DateTimeColumn get wochenStart => dateTime()();

  /// ISO-Kalenderwoche (1..53).
  IntColumn get kw => integer()();

  /// Jahr der Kalenderwoche.
  IntColumn get jahr => integer()();

  /// Optionaler Titel/Label für den Snapshot.
  TextColumn get titel => text().nullable()();

  /// Frei eingebbare Notiz/Erkenntnis zur Woche.
  TextColumn get notiz => text().nullable()();

  /// Eingefrorene Wochendaten als JSON (Aufträge + Tageskapazitäten).
  TextColumn get datenJson => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}