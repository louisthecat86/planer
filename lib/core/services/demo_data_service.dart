import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

/// Erzeugt realistische Testdaten für den Produktionsplaner.
///
/// Wird beim ersten Start angeboten, damit alle Dashboard-Elemente
/// sofort mit Daten gefüllt sind und der Anwender die App erkunden kann.
class DemoDataService {
  static const _uuid = Uuid();

  /// Prüft, ob die Datenbank leer ist (keine Produkte vorhanden).
  static Future<bool> isDatabaseEmpty(AppDatabase db) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM products WHERE deleted_at IS NULL',
        )
        .getSingle();
    return row.read<int>('c') == 0;
  }

  /// Befüllt die Datenbank mit realistischen Demo-Daten.
  static Future<void> seedDemoData(AppDatabase db) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dayAfter = today.add(const Duration(days: 2));

    // Produkt-IDs
    final lk = _uuid.v4();
    final ww = _uuid.v4();
    final bw = _uuid.v4();
    final ks = _uuid.v4();
    final sm = _uuid.v4();

    // Rohwaren-IDs
    final schwein = _uuid.v4();
    final rind = _uuid.v4();
    final salz = _uuid.v4();
    final gewuerz = _uuid.v4();
    final naturdarm = _uuid.v4();
    final kunstdarm = _uuid.v4();
    final eis = _uuid.v4();
    final pfeffer = _uuid.v4();

    await db.transaction(() async {
      // ── Produkte ──────────────────────────────────────────────
      for (final p in [
        (lk, 'LK-001', 'Leberkäse grob', 'Klassischer Leberkäse, grob gewolft'),
        (ww, 'WW-002', 'Wiener Würstchen', 'Brühwurst im Saitling'),
        (bw, 'BW-003', 'Bratwurst fein', 'Feine Bratwurst, Naturdarm'),
        (ks, 'KS-004', 'Kochschinken', 'Schinken, mild gepökelt'),
        (sm, 'SM-005', 'Salami Milano', 'Luftgetrocknete Salami'),
      ]) {
        await db.into(db.products).insert(ProductsCompanion(
          id: Value(p.$1),
          artikelnummer: Value(p.$2),
          artikelbezeichnung: Value(p.$3),
          beschreibung: Value(p.$4),
        ),);
      }

      // ── Rohwaren ──────────────────────────────────────────────
      for (final m in <(String, String, String, String, String?)>[
        (schwein, 'Schweinebauch', 'RW-001', 'kg', 'Fleisch Müller GmbH'),
        (rind, 'Rindfleisch', 'RW-002', 'kg', 'Fleisch Müller GmbH'),
        (salz, 'Nitritpökelsalz', 'RW-003', 'kg', 'Gewürzhandel Schmidt'),
        (gewuerz, 'Gewürzmischung LK', 'RW-004', 'kg', 'Gewürzhandel Schmidt'),
        (naturdarm, 'Naturdarm 28mm', 'RW-005', 'Stk', 'Darmhandel Weber'),
        (kunstdarm, 'Kunstdarm 60mm', 'RW-006', 'Stk', 'Darmhandel Weber'),
        (eis, 'Eis/Wasser', 'RW-007', 'kg', null),
        (pfeffer, 'Pfeffermischung', 'RW-008', 'kg', 'Gewürzhandel Schmidt'),
      ]) {
        await db.into(db.rawMaterials).insert(RawMaterialsCompanion(
          id: Value(m.$1),
          name: Value(m.$2),
          artikelnummer: Value(m.$3),
          einheit: Value(m.$4),
          lieferant: Value(m.$5),
        ),);
      }

      // ── Rezepturen ────────────────────────────────────────────
      for (final r in [
        (lk, schwein, 0.60), (lk, rind, 0.20), (lk, salz, 0.02),
        (lk, gewuerz, 0.01), (lk, eis, 0.15),
        (ww, schwein, 0.55), (ww, rind, 0.15), (ww, salz, 0.02),
        (ww, eis, 0.20),
        (bw, schwein, 0.70), (bw, salz, 0.018), (bw, pfeffer, 0.005),
        (ks, schwein, 0.65), (ks, salz, 0.025), (ks, pfeffer, 0.003),
        (sm, schwein, 0.50), (sm, rind, 0.25), (sm, salz, 0.03),
        (sm, pfeffer, 0.008),
      ]) {
        await db.into(db.productRawMaterials).insert(ProductRawMaterialsCompanion(
          id: Value(_uuid.v4()),
          productId: Value(r.$1),
          rawMaterialId: Value(r.$2),
          mengeProKgProdukt: Value(r.$3),
        ),);
      }

      // ── Produktionsschritte ───────────────────────────────────
      // Leberkäse: Zerlegung → Wurstküche → Bratstraße → Verpackung
      await _insertSteps(db, lk, [
        ('zerlegung', 100.0, 90.0, 2),
        ('wurstkueche', 100.0, 120.0, 3),
        ('bratstrasse', 100.0, 180.0, 2),
        ('verpackung', 100.0, 60.0, 2),
      ]);
      // Wiener: Zerlegung → Wurstküche → Verpackung
      await _insertSteps(db, ww, [
        ('zerlegung', 80.0, 60.0, 2),
        ('wurstkueche', 80.0, 150.0, 3),
        ('verpackung', 80.0, 45.0, 2),
      ]);
      // Bratwurst: Zerlegung → Wurstküche → Schneide → Verpackung
      await _insertSteps(db, bw, [
        ('zerlegung', 60.0, 45.0, 2),
        ('wurstkueche', 60.0, 90.0, 2),
        ('schneideabteilung', 60.0, 30.0, 1),
        ('verpackung', 60.0, 40.0, 2),
      ]);
      // Kochschinken: Zerlegung → Wurstküche → Schneide → Verpackung Tef1
      await _insertSteps(db, ks, [
        ('zerlegung', 120.0, 120.0, 3),
        ('wurstkueche', 120.0, 90.0, 2),
        ('schneideabteilung', 120.0, 60.0, 2),
        ('verpackung_tef1', 120.0, 50.0, 2),
      ]);
      // Salami: Zerlegung → Wurstküche → Verpackung Tef1
      await _insertSteps(db, sm, [
        ('zerlegung', 50.0, 60.0, 2),
        ('wurstkueche', 50.0, 180.0, 3),
        ('verpackung_tef1', 50.0, 40.0, 1),
      ]);

      // ── Produktionsaufträge ───────────────────────────────────
      // Heute
      await _insertTask(db, lk, today, 'zerlegung', 200, 180, 2, '06:00', 'in_arbeit');
      await _insertTask(db, lk, today, 'wurstkueche', 200, 240, 3, '09:30', 'geplant');
      await _insertTask(db, lk, today, 'bratstrasse', 200, 360, 2, '14:00', 'geplant');
      await _insertTask(db, ww, today, 'zerlegung', 100, 75, 2, '07:00', 'in_arbeit');
      await _insertTask(db, ww, today, 'wurstkueche', 100, 190, 3, '10:00', 'geplant');
      await _insertTask(db, bw, today, 'schneideabteilung', 80, 40, 1, '08:00', 'fertig');
      // Morgen
      await _insertTask(db, bw, tomorrow, 'zerlegung', 120, 90, 2, '06:00', 'geplant');
      await _insertTask(db, bw, tomorrow, 'wurstkueche', 120, 180, 2, '09:00', 'geplant');
      await _insertTask(db, ks, tomorrow, 'zerlegung', 150, 150, 3, '06:30', 'geplant');
      await _insertTask(db, ks, tomorrow, 'wurstkueche', 150, 112, 2, '10:00', 'geplant');
      // Übermorgen
      await _insertTask(db, sm, dayAfter, 'zerlegung', 80, 96, 2, '06:00', 'geplant');
      await _insertTask(db, sm, dayAfter, 'wurstkueche', 80, 288, 3, '08:30', 'geplant');
      await _insertTask(db, lk, dayAfter, 'verpackung', 200, 120, 2, '07:00', 'geplant');
      await _insertTask(db, ww, dayAfter, 'verpackung', 100, 56, 2, '10:00', 'geplant');

      // ── Chargen (Lagerbestand) ────────────────────────────────
      final weekAgo = now.subtract(const Duration(days: 7));
      await _insertBatch(db, schwein, 'CH-2026-001', weekAgo, 450.0, 320.5, 'kg');
      await _insertBatch(db, rind, 'CH-2026-002', weekAgo, 200.0, 145.0, 'kg');
      await _insertBatch(db, salz, 'CH-2026-003', weekAgo, 50.0, 42.0, 'kg');
      await _insertBatch(db, gewuerz, 'CH-2026-004', weekAgo, 10.0, 8.5, 'kg');
      await _insertBatch(db, eis, 'CH-2026-005', weekAgo, 100.0, 75.0, 'kg');
      await _insertBatch(db, pfeffer, 'CH-2026-006', weekAgo, 5.0, 4.2, 'kg');
      await _insertBatch(db, naturdarm, 'CH-2026-007', weekAgo, 500.0, 380.0, 'Stk');
      await _insertBatch(db, kunstdarm, 'CH-2026-008', weekAgo, 200.0, 190.0, 'Stk');
    });
  }

  // ── Hilfsfunktionen ─────────────────────────────────────────────

  static Future<void> _insertSteps(
    AppDatabase db,
    String productId,
    List<(String abteilung, double basisMenge, double basisDauer, int mitarbeiter)> steps,
  ) async {
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      await db.into(db.productSteps).insert(ProductStepsCompanion(
        id: Value(_uuid.v4()),
        productId: Value(productId),
        reihenfolge: Value(i + 1),
        abteilung: Value(s.$1),
        basisMengeKg: Value(s.$2),
        basisDauerMinuten: Value(s.$3),
        basisMitarbeiter: Value(s.$4),
      ),);
    }
  }

  static Future<void> _insertTask(
    AppDatabase db,
    String productId,
    DateTime datum,
    String abteilung,
    double mengeKg,
    double dauerMin,
    int mitarbeiter,
    String startZeit,
    String status,
  ) async {
    await db.into(db.productionTasks).insert(ProductionTasksCompanion(
      id: Value(_uuid.v4()),
      productId: Value(productId),
      mengeKg: Value(mengeKg),
      datum: Value(datum),
      abteilung: Value(abteilung),
      startZeit: Value(startZeit),
      geplanteDauerMinuten: Value(dauerMin),
      geplanteMitarbeiter: Value(mitarbeiter),
      status: Value(status),
    ),);
  }

  static Future<void> _insertBatch(
    AppDatabase db,
    String rawMaterialId,
    String chargennummer,
    DateTime eingangsDatum,
    double mengeInitial,
    double mengeAktuell,
    String einheit,
  ) async {
    await db.into(db.rawMaterialBatches).insert(RawMaterialBatchesCompanion(
      id: Value(_uuid.v4()),
      rawMaterialId: Value(rawMaterialId),
      chargennummer: Value(chargennummer),
      eingangsDatum: Value(eingangsDatum),
      mengeInitial: Value(mengeInitial),
      mengeAktuell: Value(mengeAktuell),
      einheit: Value(einheit),
    ),);
  }
}
