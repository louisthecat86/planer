import 'package:drift/drift.dart';

import '../database/database.dart';

/// Änderungen an der Prozesskette eines Artikels, die über einen einzelnen
/// Schritt hinausgehen: Leistungsdaten je Abteilung, Abteilungswechsel und
/// das Entfernen eines Schritts.
///
/// Leistungsdaten („Menge X kg in Zeit Y") gelten für eine Abteilung,
/// gespeichert werden sie aber an einem ihrer Schritte — in
/// `basisMengeKg`/`basisDauerMinuten`. Es zählt der erste Schritt der
/// Abteilung, der Werte trägt (siehe `leistungsdatenVon`). Damit sie beim
/// Umbauen der Kette weder verloren gehen noch in eine andere Abteilung
/// wandern, laufen solche Änderungen hier durch.
///
/// „Abteilung" meint dabei immer einen zusammenhängenden Block: Kommt eine
/// Abteilung zweimal in der Kette vor, hat jeder Block seine eigenen
/// Leistungsdaten — genau wie bei der Planung.
class ProzesskettenService {
  const ProzesskettenService._();

  /// Aktive Schritte des Artikels in Prozessreihenfolge.
  static Future<List<ProductStep>> schritte(
    AppDatabase db,
    String productId,
  ) {
    return (db.select(db.productSteps)
          ..where((s) => s.productId.equals(productId))
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
        .get();
  }

  /// Der zusammenhängende Block derselben Abteilung, in dem [stepId] liegt.
  /// Leer, wenn es den Schritt in [schritte] nicht gibt.
  static List<ProductStep> blockVon(
    List<ProductStep> schritte,
    String stepId,
  ) {
    final i = schritte.indexWhere((s) => s.id == stepId);
    if (i < 0) return const [];
    final abteilung = schritte[i].abteilung;
    var von = i;
    while (von > 0 && schritte[von - 1].abteilung == abteilung) {
      von--;
    }
    var bis = i + 1;
    while (bis < schritte.length && schritte[bis].abteilung == abteilung) {
      bis++;
    }
    return schritte.sublist(von, bis);
  }

  static bool _hatWerte(ProductStep s) =>
      s.basisMengeKg > 0 && s.basisDauerMinuten > 0;

  static ProductStepsCompanion _werte(double mengeKg, double minuten) =>
      ProductStepsCompanion(
        basisMengeKg: Value(mengeKg),
        basisDauerMinuten: Value(minuten),
        // Spiegel der Menge für die Excel-Vorlage.
        mengeKg: Value(mengeKg),
        updatedAt: Value(DateTime.now()),
      );

  static ProductStepsCompanion _ohneWerte() => ProductStepsCompanion(
        basisMengeKg: const Value(0),
        basisDauerMinuten: const Value(0),
        mengeKg: const Value(null),
        updatedAt: Value(DateTime.now()),
      );

  static Future<void> _schreibe(
    AppDatabase db,
    String stepId,
    ProductStepsCompanion werte,
  ) {
    return (db.update(db.productSteps)..where((s) => s.id.equals(stepId)))
        .write(werte);
  }

  /// Hinterlegt die Leistungsdaten der Abteilung, zu der [stepId] gehört:
  /// am ersten Schritt ihres Blocks. Ältere Werte an anderen Schritten des
  /// Blocks werden entfernt — danach gibt es genau eine Stelle.
  static Future<void> setzeLeistungsdaten(
    AppDatabase db, {
    required String productId,
    required String stepId,
    required double mengeKg,
    required double minuten,
  }) async {
    if (!(mengeKg > 0) || !(minuten > 0)) {
      throw ArgumentError('Menge und Zeit müssen größer als 0 sein.');
    }
    await db.transaction(() async {
      final block = blockVon(await schritte(db, productId), stepId);
      if (block.isEmpty) return;
      await _schreibe(db, block.first.id, _werte(mengeKg, minuten));
      for (final s in block.skip(1)) {
        if (_hatWerte(s)) await _schreibe(db, s.id, _ohneWerte());
      }
    });
  }

  /// Entfernt die hinterlegten Leistungsdaten der Abteilung, zu der
  /// [stepId] gehört. Die Planung rechnet danach mit den erfassten
  /// Produktionen.
  static Future<void> entferneLeistungsdaten(
    AppDatabase db, {
    required String productId,
    required String stepId,
  }) async {
    await db.transaction(() async {
      final block = blockVon(await schritte(db, productId), stepId);
      for (final s in block) {
        if (_hatWerte(s)) await _schreibe(db, s.id, _ohneWerte());
      }
    });
  }

  /// Zerlegt die Kette in zusammenhängende Blöcke derselben Abteilung —
  /// genau so, wie die Planung sie bündelt.
  static List<List<ProductStep>> bloecke(List<ProductStep> schritte) {
    final ergebnis = <List<ProductStep>>[];
    for (final s in schritte) {
      if (ergebnis.isNotEmpty &&
          ergebnis.last.first.abteilung == s.abteilung) {
        ergebnis.last.add(s);
      } else {
        ergebnis.add([s]);
      }
    }
    return ergebnis;
  }

  /// Je Schritt die Leistungsdaten, die für seinen Block gelten — samt
  /// Abteilung, damit sie nie in eine andere wandern.
  static Map<String, ({String abteilung, double mengeKg, double minuten})>
      _geltendeWerte(List<ProductStep> alle) {
    final ergebnis =
        <String, ({String abteilung, double mengeKg, double minuten})>{};
    for (final block in bloecke(alle)) {
      final traeger = block.where(_hatWerte).firstOrNull;
      if (traeger == null) continue;
      for (final s in block) {
        ergebnis[s.id] = (
          abteilung: s.abteilung,
          mengeKg: traeger.basisMengeKg,
          minuten: traeger.basisDauerMinuten,
        );
      }
    }
    return ergebnis;
  }

  /// Nach einem Umbau der Kette: Jeder Block ohne Leistungsdaten bekommt
  /// die, die einer seiner Schritte vorher in derselben Abteilung hatte.
  ///
  /// Das deckt alle Fälle ab, ohne sie einzeln zu kennen: Fällt der
  /// Schritt mit den Werten weg, übernimmt der nächste; zerfällt ein Block
  /// in zwei, haben danach beide die Werte; ein Schritt, der die Abteilung
  /// wechselt, nimmt nichts mit.
  static Future<void> _bewahreLeistungsdaten(
    AppDatabase db,
    String productId,
    Map<String, ({String abteilung, double mengeKg, double minuten})> vorher,
  ) async {
    final alle = await schritte(db, productId);
    for (final block in bloecke(alle)) {
      if (block.any(_hatWerte)) continue;
      for (final s in block) {
        final v = vorher[s.id];
        if (v == null || v.abteilung != s.abteilung) continue;
        await _schreibe(db, block.first.id, _werte(v.mengeKg, v.minuten));
        break;
      }
    }
  }

  /// Nimmt [stepId] aus dem Prozess (Soft-Delete) und nummeriert die
  /// übrigen Schritte lückenlos neu. Trug er die Leistungsdaten seiner
  /// Abteilung, gehen sie an den nächsten Schritt der Abteilung über.
  static Future<void> entferneSchritt(AppDatabase db, String stepId) async {
    await db.transaction(() async {
      final schritt = await (db.select(db.productSteps)
            ..where((s) => s.id.equals(stepId)))
          .getSingleOrNull();
      if (schritt == null) return;
      final alle = await schritte(db, schritt.productId);
      final vorher = _geltendeWerte(alle);

      final jetzt = DateTime.now();
      await _schreibe(
        db,
        stepId,
        ProductStepsCompanion(
          deletedAt: Value(jetzt),
          updatedAt: Value(jetzt),
        ),
      );

      // Übrige Schritte lückenlos neu durchnummerieren (1..n). Ohne das
      // behält der Rest seine alte `reihenfolge` — die App sortiert das
      // zwar weg, der Excel-Export nimmt die Nummer aber als Spalte.
      final rest = alle.where((s) => s.id != stepId).toList();
      for (var i = 0; i < rest.length; i++) {
        if (rest[i].reihenfolge == i + 1) continue;
        await _schreibe(
          db,
          rest[i].id,
          ProductStepsCompanion(
            reihenfolge: Value(i + 1),
            updatedAt: Value(jetzt),
          ),
        );
      }

      await _bewahreLeistungsdaten(db, schritt.productId, vorher);
    });
  }

  /// Stellt [stepId] in die Abteilung [neueAbteilung] (dbValue). Die
  /// Anlage bleibt im Katalog ihrer Stammabteilung — im Prozess dieses
  /// Artikels arbeitet sie für die neue.
  ///
  /// Leistungsdaten, die der Schritt für seine bisherige Abteilung trug,
  /// bleiben dort (siehe [entferneSchritt]); in die neue Abteilung nimmt
  /// er keine mit — sie gehörten zu einer anderen Abteilung.
  static Future<void> wechsleAbteilung(
    AppDatabase db,
    String stepId,
    String neueAbteilung,
  ) async {
    await db.transaction(() async {
      final schritt = await (db.select(db.productSteps)
            ..where((s) => s.id.equals(stepId)))
          .getSingleOrNull();
      if (schritt == null || schritt.abteilung == neueAbteilung) return;
      final vorher =
          _geltendeWerte(await schritte(db, schritt.productId));
      await _schreibe(
        db,
        stepId,
        ProductStepsCompanion(
          abteilung: Value(neueAbteilung),
          basisMengeKg: const Value(0),
          basisDauerMinuten: const Value(0),
          mengeKg: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _bewahreLeistungsdaten(db, schritt.productId, vorher);
    });
  }
}
