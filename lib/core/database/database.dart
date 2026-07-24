import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/app_settings.dart';
import 'tables/machine_parameter_defs.dart';
import 'tables/machines.dart';
import 'tables/order_list_items.dart';
import 'tables/parameter_grenzen.dart';
import 'tables/product_raw_materials.dart';
import 'tables/product_step_parameters.dart';
import 'tables/product_steps.dart';
import 'tables/production_history.dart';
import 'tables/production_runs.dart';
import 'tables/demands.dart';
import 'tables/production_tasks.dart';
import 'tables/products.dart';
import 'tables/raw_material_batches.dart';
import 'tables/raw_materials.dart';
import 'tables/task_dependencies.dart';
import 'tables/week_snapshots.dart';
import 'tables/zusatzzeiten.dart';

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
    ProductionHistory,
    TaskDependencies,
    OrderListItems,
    AppSettings,
    WeekSnapshots,
    Demands,
    ParameterGrenzen,
    MachineParameterDefs,
    Zusatzzeiten,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Konstruktor für Tests — erlaubt Injection eines In-Memory-Executors.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        onUpgrade: (m, from, to) async {
          // --- v1 ? v2: Basis-Erweiterung products/product_steps -------
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

          // --- v2 ? v3: Produktgruppen + gruppenspezifische Felder -----
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

          // --- v3 ? v4: Anlagen-Katalog + flexible Schritt-Parameter ---
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

          // --- v4 ? v5: App-Settings für Excel-Export-Workflow ---------
          if (from < 5) {
            await m.createTable(appSettings);
          }

          // --- v5 ? v6: Historische Produktionsdaten je Artikel --------
          if (from < 6) {
            await m.createTable(productionHistory);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_production_history_product '
              'ON production_history(product_id, datum)',
            );
          }

          // --- v6 ? v7: Manuelle Reihenfolge der Tasks je Abteilung/Tag -
          if (from < 7) {
            await _addColumnIfNotExists(
              'production_tasks',
              'sortierung',
              'INTEGER NOT NULL DEFAULT 0',
            );
          }

          // --- v7 -> v8: Eingefrorene Wochen-Snapshots ------------------
          if (from < 8) {
            await m.createTable(weekSnapshots);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_week_snapshots_start '
              'ON week_snapshots(wochen_start)',
            );
          }

          // --- v8 -> v9: Kapazität je ANLAGE statt je Abteilung ---------
          //
          // In der Verpackung laufen mehrere Anlagen echt parallel. Bisher
          // rechnete das Board mit EINER 8-h-Kapazität pro Abteilung, was
          // dort zwangsläufig zu Scheinüberbuchung führte.
          //
          // Neu: Aufträge kennen ihre Anlage; Anlagen können eine eigene
          // Kapazitätsspur haben.
          if (from < 9) {
            await _addColumnIfNotExists(
              'production_tasks',
              'maschine_id',
              'TEXT',
            );
            await _addColumnIfNotExists(
              'machines',
              'ist_planungsressource',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfNotExists(
              'machines',
              'kapazitaet_minuten_pro_tag',
              'REAL NOT NULL DEFAULT 540',
            );
            await _addColumnIfNotExists(
              'machines',
              'eignung_hinweis',
              'TEXT',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_production_tasks_maschine '
              'ON production_tasks(maschine_id)',
            );

            // Bestehende Aufträge bekommen die Anlage ihres Prozessschritts
            // (gleiche Abteilung) — sonst landeten sie in der Spur „ohne
            // Anlage" und die Auslastung wäre falsch verteilt.
            await customStatement('''
              UPDATE production_tasks
                 SET maschine_id = (
                       SELECT ps.maschine_id
                         FROM product_steps ps
                        WHERE ps.product_id = production_tasks.product_id
                          AND ps.abteilung  = production_tasks.abteilung
                          AND ps.deleted_at IS NULL
                          AND ps.maschine_id IS NOT NULL
                        ORDER BY ps.reihenfolge
                        LIMIT 1
                     )
               WHERE maschine_id IS NULL
            ''');
          }

          // --- v9 -> v10: Bedarfsliste ---------------------------------
          //
          // Der Auslöser der Produktion (Bestellungen abzüglich Bestand)
          // lag bisher nur im Kopf des Planers. Die Bedarfsliste macht ihn
          // sichtbar; die Aufträge verweisen darauf zurück.
          if (from < 10) {
            await m.createTable(demands);
            await _addColumnIfNotExists(
              'production_tasks',
              'bedarf_id',
              'TEXT',
            );
            await _addColumnIfNotExists(
              'production_tasks',
              'fertig_menge_kg',
              'REAL',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_production_tasks_bedarf '
              'ON production_tasks(bedarf_id)',
            );
          }

          // --- v10 -> v11: Regelarbeitszeit 8 h -> 9 h ------------------
          //
          // Die Abteilungen arbeiten regulär 9 Stunden. Wir heben nur die
          // Anlagen, die noch exakt auf dem alten Default (480 min = 8 h)
          // stehen — also nie manuell angepasst wurden. Wer bereits einen
          // abweichenden Wert gepflegt hat, behält ihn.
          if (from < 11) {
            await customStatement(
              'UPDATE machines SET kapazitaet_minuten_pro_tag = 540 '
              'WHERE kapazitaet_minuten_pro_tag = 480',
            );
          }

          // --- v11 -> v12: Plausibilitätsgrenzen für Parameter ----------
          if (from < 12) {
            await m.createTable(parameterGrenzen);
          }

          // --- v12 -> v13: Maschinen-Steckbriefe (Parameterdefinitionen) -
          if (from < 13) {
            await m.createTable(machineParameterDefs);
          }

          // --- v13 -> v14: Rüst-/Reinigungszeiten je Tag und Spur -------
          // Ohne sie war die Tagesauslastung zu optimistisch: Umrüsten und
          // Reinigen blockieren dieselbe Anlage wie die Produktion.
          if (from < 14) {
            await m.createTable(zusatzzeiten);
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
      'CREATE INDEX IF NOT EXISTS idx_production_history_product '
      'ON production_history(product_id, datum)',
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