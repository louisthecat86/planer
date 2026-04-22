import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/app_settings.dart';
import 'tables/machines.dart';
import 'tables/order_list_items.dart';
import 'tables/product_raw_materials.dart';
import 'tables/product_step_parameters.dart';
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
/// Nach Änderungen an den Tabellen-Dateien unbedingt ausführen:
///     dart run build_runner build --delete-conflicting-outputs
@DriftDatabase(
  tables: [
    Products,
    ProductSteps,
    ProductStepParameters,
    Machines,
    RawMaterials,
    ProductRawMaterials,
    RawMaterialBatches,
    ProductionTasks,
    ProductionRuns,
    TaskDependencies,
    OrderListItems,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Konstruktor für Tests — erlaubt Injection eines In-Memory-Executors.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        onUpgrade: (m, from, to) async {
          // ─── v1 → v2: Basis-Erweiterung products/product_steps ───────
          if (from < 2) {
            await _addColumnIfNotExists('products', 'verpackungsart', 'TEXT');
            await _addColumnIfNotExists('products', 'gebinde_groesse_kg', 'REAL');
            await _addColumnIfNotExists('products', 'haltbarkeit_tage', 'INTEGER');
            await _addColumnIfNotExists('products', 'gesamt_ausbeute_faktor', 'REAL');
            await _addColumnIfNotExists('products', 'mindest_vorlaufzeit_tage', 'INTEGER');
            await _addColumnIfNotExists('products', 'planungsgruppe', 'TEXT');

            await _addColumnIfNotExists('product_steps', 'ausbeute_faktor', 'REAL');
            await _addColumnIfNotExists('product_steps', 'wartezeit_minuten', 'REAL');
            await _addColumnIfNotExists('product_steps', 'min_chargen_kg', 'REAL');
            await _addColumnIfNotExists('product_steps', 'max_chargen_kg', 'REAL');
            await _addColumnIfNotExists('product_steps', 'kerntemperatur_ziel', 'REAL');
            await _addColumnIfNotExists('product_steps', 'raumtemperatur_max', 'REAL');
            await _addColumnIfNotExists('product_steps', 'maschine', 'TEXT');
            await _addColumnIfNotExists('product_steps', 'maschinen_einstellungen_json', 'TEXT');
          }

          // ─── v2 → v3: Produktgruppen + gruppenspezifische Felder ─────
          if (from < 3) {
            // Produktgruppe
            await _addColumnIfNotExists('products', 'produktgruppe', 'TEXT');

            // Temperaturen (gruppenübergreifend)
            await _addColumnIfNotExists('products', 'ziel_kerntemp_c', 'REAL');
            await _addColumnIfNotExists('products', 'kutter_endtemp_c', 'REAL');

            // Brät / Wurst
            await _addColumnIfNotExists('products', 'braet_feinheit', 'TEXT');
            await _addColumnIfNotExists('products', 'kochkammer_programm', 'TEXT');
            await _addColumnIfNotExists('products', 'raeucherart', 'TEXT');

            // Rohwurst / Reifung
            await _addColumnIfNotExists('products', 'startkultur', 'TEXT');
            await _addColumnIfNotExists('products', 'reifezeit_tage', 'INTEGER');
            await _addColumnIfNotExists('products', 'klimaprogramm', 'TEXT');
            await _addColumnIfNotExists('products', 'ziel_ph', 'REAL');
            await _addColumnIfNotExists('products', 'ziel_aw', 'REAL');
            await _addColumnIfNotExists('products', 'gewichtsverlust_prozent', 'REAL');

            // Pökelware
            await _addColumnIfNotExists('products', 'poekelart', 'TEXT');
            await _addColumnIfNotExists('products', 'lake_konzentration_prozent', 'REAL');
            await _addColumnIfNotExists('products', 'poekelzeit_tage', 'INTEGER');
            await _addColumnIfNotExists('products', 'tumbelzeit_min', 'REAL');

            // Aufschnitt
            await _addColumnIfNotExists('products', 'basis_produkt_artikelnummer', 'TEXT');
            await _addColumnIfNotExists('products', 'scheibendicke_mm', 'REAL');
            await _addColumnIfNotExists('products', 'scheiben_pro_packung', 'INTEGER');
            await _addColumnIfNotExists('products', 'packungsgewicht_g', 'REAL');
            await _addColumnIfNotExists('products', 'map_gas', 'TEXT');

            // Bratstraße
            await _addColumnIfNotExists('products', 'formgewicht_g', 'REAL');
            await _addColumnIfNotExists('products', 'form', 'TEXT');
            await _addColumnIfNotExists('products', 'bratgrad', 'TEXT');
            await _addColumnIfNotExists('products', 'panierart', 'TEXT');
            await _addColumnIfNotExists('products', 'panier_aufnahme_prozent', 'REAL');

            // Hackprodukte
            await _addColumnIfNotExists('products', 'fleischanteil_typ', 'TEXT');
            await _addColumnIfNotExists('products', 'gesamtdurchlaufzeit_max_std', 'REAL');
            await _addColumnIfNotExists('products', 'wolf_lochscheibe_mm', 'REAL');
            await _addColumnIfNotExists('products', 'abkuehlgradient', 'TEXT');

            // Braten
            await _addColumnIfNotExists('products', 'braten_variante', 'TEXT');
            await _addColumnIfNotExists('products', 'fuellung', 'TEXT');
            await _addColumnIfNotExists('products', 'netzbindung', 'INTEGER'); // bool in SQLite

            // Sous Vide
            await _addColumnIfNotExists('products', 'sv_badtemp_c', 'REAL');
            await _addColumnIfNotExists('products', 'sv_garzeit_std', 'REAL');

            // Angebratene Brühwurst
            await _addColumnIfNotExists('products', 'anbratgrad', 'TEXT');

            // product_steps — Programm-Felder
            await _addColumnIfNotExists('product_steps', 'kochkammer_programm', 'TEXT');
            await _addColumnIfNotExists('product_steps', 'klimaprogramm', 'TEXT');
            await _addColumnIfNotExists('product_steps', 'bratparameter', 'TEXT');

            // Index auf Produktgruppe (häufige Filter-Query)
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_products_produktgruppe '
              'ON products(produktgruppe)',
            );
          }

          // ─── v3 → v4: Anlagen-Katalog + flexible Schritt-Parameter ───
          if (from < 4) {
            await m.createTable(machines);
            await m.createTable(productStepParameters);

            await _addColumnIfNotExists('product_steps', 'maschine_id', 'TEXT');
            await _addColumnIfNotExists('product_steps', 'prozessschritt', 'TEXT');
            await _addColumnIfNotExists('product_steps', 'menge_kg', 'REAL');

            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_machines_abteilung '
              'ON machines(abteilung)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_machines_name '
              'ON machines(name)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_step_params_step_id '
              'ON product_step_parameters(step_id, reihenfolge)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_step_params_name '
              'ON product_step_parameters(parameter_name)',
            );
          }

          // ─── v4 → v5: App-Settings für Excel-Export-Workflow ─────────
          if (from < 5) {
            await m.createTable(appSettings);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Indizes für typische Query-Patterns anlegen.
  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_products_artikelnummer '
      'ON products(artikelnummer)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_products_produktgruppe '
      'ON products(produktgruppe)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_product_steps_product_id '
      'ON product_steps(product_id, reihenfolge)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_production_tasks_datum_abteilung '
      'ON production_tasks(datum, abteilung)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_production_runs_task_id '
      'ON production_runs(task_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_batches_raw_material_id '
      'ON raw_material_batches(raw_material_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_order_list_woche '
      'ON order_list_items(woche_start_datum)',
    );
    // v4-Indizes
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_machines_abteilung '
      'ON machines(abteilung)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_machines_name '
      'ON machines(name)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_step_params_step_id '
      'ON product_step_parameters(step_id, reihenfolge)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_step_params_name '
      'ON product_step_parameters(parameter_name)',
    );
  }

  /// Fügt eine Spalte nur hinzu, wenn sie noch nicht existiert.
  /// Verhindert Fehler bei wiederholter Migration.
  Future<void> _addColumnIfNotExists(
    String table,
    String column,
    String type,
  ) async {
    final result = await customSelect(
      "SELECT COUNT(*) AS cnt FROM pragma_table_info('$table') WHERE name = '$column'",
    ).getSingle();
    if (result.read<int>('cnt') == 0) {
      await customStatement('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'produktion_planer');
}