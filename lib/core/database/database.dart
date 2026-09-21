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
import 'tables/navision_artikel_katalog.dart';
import 'tables/navision_umrechnungen.dart';
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
    NavisionArtikelKatalog,
    NavisionUmrechnungen,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Nur für Tests: Datenbank auf einem frei wählbaren Executor.
  ///
  /// Der normale Konstruktor legt die SQLite-Datei im Anwendungsordner an —
  /// in einem Test wäre das ein gemeinsamer Zustand zwischen Testläufen und
  /// bräuchte ein Dateisystem. Mit `NativeDatabase.memory()` bekommt jeder
  /// Test eine frische, leere Datenbank im Arbeitsspeicher, auf die
  /// `onCreate` dasselbe Schema anlegt wie in der echten App.
  AppDatabase.forTesting(super.executor);

  /// Konstruktor für Tests — erlaubt Injection eines In-Memory-Executors.

  @override
  int get schemaVersion => 21;

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

          // --- v14 -> v15: Artikelkatalog aus Navision -----------------
          if (from < 15) {
            await m.createTable(navisionArtikelKatalog);
          }

          // --- v15 -> v16: Einheiten-Umrechnung (BTL/PACK → kg) --------
          // Eigene Tabelle, weil der Katalog bei jedem Import ersetzt wird
          // und die mühsam erfassten Faktoren sonst verloren gingen.
          if (from < 16) {
            await m.createTable(navisionUmrechnungen);
          }
          // --- v16 -> v17: Pflegestatus für Artikel ----------------
          // Stub-Artikel aus dem Navision-Abgleich werden mit
          // ist_eingepflegt = 0 angelegt. Bestehende Artikel gelten
          // dank DEFAULT 1 automatisch als eingepflegt.
          if (from < 17) {
            await _addColumnIfNotExists(
              'products',
              'ist_eingepflegt',
              'INTEGER NOT NULL DEFAULT 1',
            );
          }

          if (from < 19) {
            // Bewusst auch für Datenbanken, die schon auf 18 stehen: Der
            // erste Anlauf ist unterwegs abgebrochen, und die Routine ist
            // so gebaut, dass ein zweiter Lauf nichts kaputtmacht.
            await _migrationKombiofenAufraeumen();
          }

          if (from < 20) {
            await _migrationAltnamenZusammenfuehren();
          }

          if (from < 21) {
            // Die alte Excel-Vorlage lag als Base64-Text in app_settings —
            // mehrere Megabyte, die in jedem Backup mitgesichert wurden.
            // Seit der Generator die Mappe selbst baut, liest sie niemand
            // mehr.
            await customStatement(
              "DELETE FROM app_settings WHERE key IN ("
              "'last_import_excel_bytes', 'last_import_excel_filename', "
              "'last_import_datum')",
            );
          }

        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await _sichereEingepflegtRegel();
        },
      );

  /// Ein Artikel mit Prozessschritten gilt als eingepflegt.
  ///
  /// Bisher wurde das Kennzeichen nur gesetzt, wenn der Artikel eine
  /// Produktgruppe bekam. Ein Artikel, der schon seinen ganzen Prozess
  /// hatte, trug deshalb weiter das Schild „Noch nicht eingepflegt" — das
  /// ist nur für die leeren Hüllen aus dem Navision-Abgleich gedacht.
  ///
  /// Schritte entstehen an vielen Stellen: in der Artikelansicht, beim
  /// Excel-Import, beim Wiederherstellen eines Backups. Statt jede davon
  /// anzufassen, übernimmt das ein Trigger in der Datenbank. Er greift bei
  /// jedem Weg, auch bei künftigen, die heute noch niemand kennt.
  ///
  /// Läuft bei jedem Öffnen: `IF NOT EXISTS` macht den Trigger idempotent,
  /// und die einmalige Nachkorrektur trifft danach keine Zeile mehr. So
  /// gibt es auch nach einem Reset keine Lücke — die Regel steht, bevor
  /// der erste Schritt geschrieben wird.
  Future<void> _sichereEingepflegtRegel() async {
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS trg_schritt_macht_eingepflegt '
      'AFTER INSERT ON product_steps '
      'BEGIN '
      'UPDATE products SET ist_eingepflegt = 1 '
      'WHERE id = NEW.product_id AND ist_eingepflegt = 0; '
      'END',
    );
    // Bestand: Artikel, die schon Schritte haben.
    await customStatement(
      'UPDATE products SET ist_eingepflegt = 1 '
      'WHERE ist_eingepflegt = 0 AND id IN ('
      'SELECT DISTINCT product_id FROM product_steps '
      'WHERE deleted_at IS NULL)',
    );
  }

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
  /// Kombiofen als einziger Name, Platten gehören der Leiste.
  ///
  /// Die Routine ist **wiederholbar**: Jeder Abschnitt prüft selbst, ob
  /// noch etwas zu tun ist, und jeder läuft in seinem eigenen try/catch.
  /// Der erste Anlauf ist unterwegs stehengeblieben — vermutlich am
  /// Löschen einer Maschine, auf die noch verwiesen wurde. Damals riss
  /// dieser eine Fehler alles Folgende mit.
  ///
  /// Bereinigt werden:
  ///
  /// **Drei Namen für eine Anlage.** Der Ofen hieß „Dampftunnel",
  /// „Heißluftofen" und „Kombiofen". Es ist dieselbe Maschine — sie kann
  /// Heißluft und Dampf. Ab jetzt heißt sie überall Kombiofen.
  ///
  /// **Plattentemperaturen als Steckbrief-Zeilen.** Die App verwaltet die
  /// Platten über die Leiste, die Parameter mit den Namen
  /// `Platte Oben N` / `Platte Unten N` liest und sie aus der normalen
  /// Parameterliste ausblendet. Falsch benannte Zeilen erschienen deshalb
  /// doppelt: einmal in der Leiste, einmal in der Liste.
  Future<void> _migrationKombiofenAufraeumen() async {
    /// Führt einen Abschnitt aus und lässt die übrigen weiterlaufen, wenn
    /// er scheitert. Ohne das blockiert ein einzelnes Hindernis alles.
    Future<void> abschnitt(String name, Future<void> Function() tun) async {
      try {
        await tun();
      } catch (e) {
        // ignore: avoid_print
        print('Migration „$name" übersprungen: $e');
      }
    }

    const ofenBedingung =
        "LOWER(name) LIKE '%kombiofen%' OR LOWER(name) LIKE '%dampftunnel%' "
        "OR LOWER(name) LIKE '%heißluft%' OR LOWER(name) LIKE '%heissluft%'";

    await abschnitt('Öfen zusammenführen', () async {
      final oefen = await customSelect(
        'SELECT id, name FROM machines WHERE $ofenBedingung',
      ).get();
      if (oefen.isEmpty) return;

      final bleibt = oefen.firstWhere(
        (r) => r.read<String>('name').toLowerCase().contains('kombiofen'),
        orElse: () => oefen.first,
      );
      final bleibtId = bleibt.read<String>('id');

      for (final r in oefen) {
        final id = r.read<String>('id');
        if (id == bleibtId) continue;
        await customStatement(
          "UPDATE product_steps SET maschine_id = ?, maschine = 'Kombiofen' "
          'WHERE maschine_id = ?',
          [bleibtId, id],
        );
        await customStatement(
          'UPDATE production_tasks SET maschine_id = ? WHERE maschine_id = ?',
          [bleibtId, id],
        );
        await customStatement(
          'DELETE FROM machine_parameter_defs WHERE maschine_id = ?',
          [id],
        );
        try {
          await customStatement('DELETE FROM machines WHERE id = ?', [id]);
        } catch (_) {
          // Verweist noch etwas darauf, bleibt die Zeile als gelöscht
          // markiert stehen — sichtbar ist sie dann nicht mehr.
          await customStatement(
            'UPDATE machines SET deleted_at = ? WHERE id = ?',
            [DateTime.now().millisecondsSinceEpoch ~/ 1000, id],
          );
        }
      }

      await customStatement(
        "UPDATE machines SET name = 'Kombiofen' WHERE id = ?",
        [bleibtId],
      );
      await customStatement(
        "UPDATE product_steps SET maschine = 'Kombiofen' WHERE maschine_id = ?",
        [bleibtId],
      );
    });

    await abschnitt('Abteilungen der Maschinen', () async {
      const abteilungen = <String, String>{
        'zerlegung': 'zerlegung',
        'wurstküche': 'wurstkueche',
        'wurstkueche': 'wurstkueche',
        'kutterabteilung': 'kutterabteilung',
        'bratstraße': 'bratstrasse',
        'bratstrasse': 'bratstrasse',
        'schneideabteilung': 'schneideabteilung',
        'verpackung': 'verpackung',
        'verpackungsabteilung': 'verpackung',
        'tef1': 'verpackung_tef1',
        'verpackung tef1': 'verpackung_tef1',
        'tef2': 'verpackung_tef2',
        'verpackung tef2': 'verpackung_tef2',
        'pökelraum': 'wurstkueche',
        'mobil': 'verpackung',
      };
      for (final e in abteilungen.entries) {
        await customStatement(
          'UPDATE machines SET abteilung = ? WHERE LOWER(abteilung) = ?',
          [e.value, e.key],
        );
      }
    });

    await abschnitt('Parameternamen', () async {
      const umbenennungen = <String, String>{
        'Zeit Eingang': 'Einlaufzeit',
        'Zeit Ausgang': 'Auslaufzeit',
        'Durchlaufzeit': 'Zeit',
      };
      const tabellen = ['machine_parameter_defs', 'product_step_parameters'];
      for (final u in umbenennungen.entries) {
        for (final tabelle in tabellen) {
          await customStatement(
            'UPDATE $tabelle SET parameter_name = ? WHERE parameter_name = ?',
            [u.value, u.key],
          );
        }
      }
    });

    await abschnitt('Plattenzeilen aus den Steckbriefen', () async {
      await customStatement(
        'DELETE FROM machine_parameter_defs '
        "WHERE parameter_name LIKE 'Platte %' "
        "OR parameter_name LIKE 'Plattentemperatur%'",
      );
    });

    await abschnitt('Plattenwerte auf die Leiste umbiegen', () async {
      for (var i = 1; i <= 12; i++) {
        await customStatement(
          'UPDATE product_step_parameters SET parameter_name = ?, '
          "parameter_gruppe = 'BRATSTRASSE' WHERE parameter_name = ?",
          ['Platte Oben $i', 'Plattentemperatur Oben $i (°C)'],
        );
        await customStatement(
          'UPDATE product_step_parameters SET parameter_name = ?, '
          "parameter_gruppe = 'BRATSTRASSE' WHERE parameter_name = ?",
          ['Platte Unten $i', 'Plattentemperatur Unten $i (°C)'],
        );
        await customStatement(
          'UPDATE product_step_parameters SET parameter_name = ?, '
          "parameter_gruppe = 'DAMPFTUNNEL' WHERE parameter_name = ?",
          ['Platte Unten $i', 'Plattentemperatur $i (°C)'],
        );
      }
    });
  }

  /// Alte Anlagennamen auf den maßgeblichen Maschinenkatalog umstellen.
  ///
  /// Über die Jahre sind für dieselben Geräte mehrere Namen entstanden —
  /// „Mehrkopfwaage" neben „Mehrkopfwage", „Füllmaschine B 1" neben
  /// „Füllmaschine Bratstraße 1". Ein Katalog-Import legt die neuen Namen
  /// an, lässt die alten aber stehen, weil er Anlagen, die in der Datei
  /// fehlen, grundsätzlich nicht löscht. Beide Namen erschienen deshalb
  /// nebeneinander.
  ///
  /// Für jedes Paar gilt:
  ///   * gibt es beide, wandert alles vom alten auf den neuen Eintrag, der
  ///     alte wird als gelöscht markiert;
  ///   * gibt es nur den alten, wird er umbenannt.
  ///
  /// Umgehängt wird an allen Stellen, die auf eine Maschine verweisen:
  /// Prozessschritte, Produktionsaufträge, Steckbrief-Zeilen und die
  /// Nebenzeiten der Planungsspuren (deren Schlüssel die Maschinen-ID
  /// enthält). Wiederholbar: Ein zweiter Lauf findet nichts mehr.
  Future<void> _migrationAltnamenZusammenfuehren() async {
    const altZuNeu = <String, String>{
      'Mehrkopfwaage': 'Mehrkopfwage',
      'Füllmaschine B 1': 'Füllmaschine Bratstraße 1',
      'Füllmaschine B 2': 'Füllmaschine Bratstraße 2',
      'Füllmaschine WK 1': 'Füllmaschine Wurstküche 1',
      'Füllmaschine WK 2': 'Füllmaschine Wurstküche 2',
      'Schockfroster': 'Froster Tef2',
      'Volleimaschine': 'Volleianlage',
      'Plattierer B': 'Plattierer 1',
      'Plattierer': 'Plattierer 2',
      'Multivac Anlage Neu': 'Multivac Verpackung',
      'Multivac Neu': 'Multivac Verpackung',
      'Verpackung Tef2': 'Multivac Tef2',
      'Fleischwolf': 'Wolf',
      'Scanveagt': 'Scan Veagt',
      'Weberslicer': 'Weber Slicer',
      'Abschneidervorrichtung': 'Abschneidevorrichtung 1',
      'Abfließer': 'Abfließer 1',
      'Clippanlage': 'Clipper',
      'Gekühlte Polter 1': 'Polter groß 1',
      'Gekühlte Polter 2': 'Polter groß 2',
      'Hebevorrichtung': 'Hebevorrichtung 2',
      'Rollenschneider': 'Rollenschneider 1',
      'Treif Würfelschneider': 'Treif Würfelschneider 1',
      'Kochkammer 1': 'Kochkammer 1-4',
      'Kochkammer 2': 'Kochkammer 1-4',
      'Kochkammer 3': 'Kochkammer 1-4',
      'Kochkammer 4': 'Kochkammer 1-4',
    };

    Future<String?> idVon(String name) async {
      final r = await customSelect(
        'SELECT id FROM machines WHERE name = ? AND deleted_at IS NULL',
        variables: [Variable.withString(name)],
      ).getSingleOrNull();
      return r?.read<String>('id');
    }

    for (final paar in altZuNeu.entries) {
      try {
        final altId = await idVon(paar.key);
        if (altId == null) continue;
        final neuId = await idVon(paar.value);

        if (neuId == null) {
          // Nur der alte Name existiert → umbenennen genügt.
          await customStatement(
            'UPDATE machines SET name = ? WHERE id = ?',
            [paar.value, altId],
          );
          await customStatement(
            'UPDATE product_steps SET maschine = ? WHERE maschine_id = ?',
            [paar.value, altId],
          );
          continue;
        }

        // Beide existieren → alles auf den neuen Eintrag umhängen.
        await customStatement(
          'UPDATE product_steps SET maschine_id = ?, maschine = ? '
          'WHERE maschine_id = ?',
          [neuId, paar.value, altId],
        );
        await customStatement(
          'UPDATE production_tasks SET maschine_id = ? WHERE maschine_id = ?',
          [neuId, altId],
        );
        await customStatement(
          "UPDATE zusatzzeiten SET spur_id = REPLACE(spur_id, ?, ?) "
          "WHERE spur_id LIKE '%|' || ?",
          ['|$altId', '|$neuId', altId],
        );
        await customStatement(
          'DELETE FROM machine_parameter_defs WHERE maschine_id = ?',
          [altId],
        );
        await customStatement(
          'UPDATE machines SET deleted_at = ? WHERE id = ?',
          [DateTime.now().millisecondsSinceEpoch ~/ 1000, altId],
        );
      } catch (e) {
        // ignore: avoid_print
        print('Zusammenführen „${paar.key}" übersprungen: $e');
      }
    }
  }

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
