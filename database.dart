import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/order_list_items.dart';
import 'tables/product_raw_materials.dart';
import 'tables/product_steps.dart';
import 'tables/production_runs.dart';
import 'tables/production_tasks.dart';
import 'tables/products.dart';
import 'tables/raw_material_batches.dart';
import 'tables/raw_materials.dart';
import 'tables/task_dependencies.dart';

part 'database.g.dart';

/// Die lokale SQLite-Datenbank der App.
///
/// Alle Tabellen sind sync-vorbereitet (UUID-IDs, created_at/updated_at,
/// deleted_at für Soft-Delete). Die Wartung der Sync-Felder liegt
/// **in der Repository-Schicht** — drift setzt sie nicht automatisch.
///
/// Regel für jeden Schreibzugriff:
///   - `created_at` und `updated_at` werden durch `currentDateAndTime`-Default
///     beim Insert automatisch gesetzt.
///   - `updated_at` muss bei jedem Update manuell neu gesetzt werden
///     (via Companion mit `updatedAt: Value(DateTime.now())`).
///   - Löschungen sind immer Soft-Deletes: `deletedAt: Value(DateTime.now())`
///     statt `delete()`. Queries filtern mit `WHERE deleted_at IS NULL`.
///
/// Nach Änderungen an den Tabellen-Dateien unbedingt ausführen:
///     dart run build_runner build --delete-conflicting-outputs
@DriftDatabase(
  tables: [
    Products,
    ProductSteps,
    RawMaterials,
    ProductRawMaterials,
    RawMaterialBatches,
    ProductionTasks,
    ProductionRuns,
    TaskDependencies,
    OrderListItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Konstruktor für Tests — erlaubt Injection eines In-Memory-Executors.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        beforeOpen: (details) async {
          // Foreign-Key-Enforcement einschalten (ist per Default in SQLite aus).
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Indizes für typische Query-Patterns anlegen.
  /// Getrennt in eigener Methode, damit sie in späteren Migrationen
  /// einfach ergänzt werden können.
  Future<void> _createIndexes() async {
    // Lookup nach Artikelnummer (Produkt-Suche).
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_products_artikelnummer '
      'ON products(artikelnummer)',
    );
    // Schritte eines Produkts laden (sehr häufig).
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_product_steps_product_id '
      'ON product_steps(product_id, reihenfolge)',
    );
    // Tasks einer Woche/eines Tages laden (Whiteboard-Query).
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_production_tasks_datum_abteilung '
      'ON production_tasks(datum, abteilung)',
    );
    // Runs eines Tasks für Mittelwert-Berechnung.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_production_runs_task_id '
      'ON production_runs(task_id)',
    );
    // Chargen einer Rohware (Bestandsabfrage).
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_batches_raw_material_id '
      'ON raw_material_batches(raw_material_id)',
    );
    // Bestellliste einer Woche.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_order_list_woche '
      'ON order_list_items(woche_start_datum)',
    );
  }
}

QueryExecutor _openConnection() {
  // drift_flutter kümmert sich um Plattform-Besonderheiten (iOS/Android/Desktop).
  // Datenbank-Datei: <app documents>/produktion_planer.sqlite
  return driftDatabase(name: 'produktion_planer');
}
