import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';

/// Schließt die Lernschleife: erfasst die Ist-Werte eines abgeschlossenen
/// Auftrags, schreibt einen [ProductionRun] und rechnet die `basis_*`-Werte
/// des zugehörigen [ProductStep] aus **allen** bisherigen Runs neu.
///
/// Lernregel (vom Nutzer festgelegt): Menge und Dauer werden **getrennt**
/// über alle Ist-Durchläufe gemittelt. So bleibt das Verhältnis min/kg
/// realistisch und die lineare Skalierung in `createTasksFromProduct`
/// (`basis_dauer * menge / basis_menge`) stimmt mit der Realität überein.
///
/// Die Zuordnung Task → Schritt erfolgt über `(productId, abteilung)` —
/// dieselbe Konvention wie im Bearbeiten-Sheet. Gibt es mehrere Schritte
/// derselben Abteilung, wird der mit der kleinsten `reihenfolge` gelernt.
class LernschleifeService {
  const LernschleifeService._();

  /// Erfasst die Ist-Werte für [task], legt einen Run an, setzt den Task auf
  /// `'fertig'` und aktualisiert die Basis-Werte des Schritts.
  ///
  /// Alles in einer Transaktion: Entweder wird vollständig gelernt oder gar
  /// nichts geschrieben.
  static Future<void> erfasseIst({
    required AppDatabase db,
    required ProductionTask task,
    required double istDauerMinuten,
    required int istMitarbeiter,
    required double istMengeKg,
    String? notizen,
    String? erfasstVon,
  }) async {
    final now = DateTime.now();

    await db.transaction(() async {
      // 1. Ist-Erfassung als Run speichern.
      await db.into(db.productionRuns).insert(
            ProductionRunsCompanion.insert(
              id: const Uuid().v4(),
              taskId: task.id,
              tatsaechlicheDauerMinuten: istDauerMinuten,
              tatsaechlicheMitarbeiter: istMitarbeiter,
              tatsaechlicheMengeKg: istMengeKg,
              notizen: Value(notizen),
              erfasstVon: Value(erfasstVon),
            ),
          );

      // 2. Auftrag als fertig markieren.
      await (db.update(db.productionTasks)
            ..where((t) => t.id.equals(task.id)))
          .write(
        ProductionTasksCompanion(
          status: const Value('fertig'),
          updatedAt: Value(now),
        ),
      );

      // 3. Basis-Werte des zugehörigen Schritts neu lernen.
      await _rechneSchrittNeu(
        db,
        productId: task.productId,
        abteilung: task.abteilung,
        now: now,
      );
    });
  }

  /// Berechnet die `basis_*`-Werte des Schritts `(productId, abteilung)` neu
  /// aus allen nicht gelöschten Runs. Läuft innerhalb der Transaktion von
  /// [erfasseIst], sieht den frisch eingefügten Run also bereits mit.
  static Future<void> _rechneSchrittNeu(
    AppDatabase db, {
    required String productId,
    required String abteilung,
    required DateTime now,
  }) async {
    // Passenden Schritt finden (erster nicht-gelöschter dieser Abteilung).
    final step = await (db.select(db.productSteps)
          ..where((s) => s.productId.equals(productId))
          ..where((s) => s.abteilung.equals(abteilung))
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)])
          ..limit(1))
        .getSingleOrNull();
    if (step == null) return; // kein passender Schritt -> nichts zu lernen

    // Alle Runs dieses Schritts über die Tasks (productId + abteilung).
    final rows = await (db.select(db.productionRuns).join([
      innerJoin(
        db.productionTasks,
        db.productionTasks.id.equalsExp(db.productionRuns.taskId),
      ),
    ])
          ..where(db.productionRuns.deletedAt.isNull())
          ..where(db.productionTasks.deletedAt.isNull())
          ..where(db.productionTasks.productId.equals(productId))
          ..where(db.productionTasks.abteilung.equals(abteilung)))
        .get();

    final dauern = <double>[];
    final mengen = <double>[];
    final mitarbeiter = <int>[];
    for (final row in rows) {
      final run = row.readTable(db.productionRuns);
      dauern.add(run.tatsaechlicheDauerMinuten);
      mengen.add(run.tatsaechlicheMengeKg);
      mitarbeiter.add(run.tatsaechlicheMitarbeiter);
    }
    if (dauern.isEmpty) return;

    final n = dauern.length;
    final meanDauer = dauern.reduce((a, b) => a + b) / n;
    final meanMenge = mengen.reduce((a, b) => a + b) / n;
    final meanMitarbeiter = (mitarbeiter.reduce((a, b) => a + b) / n).round();

    // Stichproben-Standardabweichung der Dauer (erst ab 2 Messungen sinnvoll).
    double? std;
    if (n >= 2) {
      final summeQuadrate = dauern
          .map((d) => (d - meanDauer) * (d - meanDauer))
          .reduce((a, b) => a + b);
      std = math.sqrt(summeQuadrate / (n - 1));
    }

    await (db.update(db.productSteps)..where((s) => s.id.equals(step.id)))
        .write(
      ProductStepsCompanion(
        basisMengeKg: Value(meanMenge),
        basisDauerMinuten: Value(meanDauer),
        basisMitarbeiter: Value(meanMitarbeiter < 1 ? 1 : meanMitarbeiter),
        dauerStdAbweichung: Value(std),
        basisAnzahlMessungen: Value(n),
        updatedAt: Value(now),
      ),
    );
  }
}