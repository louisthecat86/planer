import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';

// ---------------------------------------------------------------------------
// Datums-Auswahl
// ---------------------------------------------------------------------------

/// Das aktuell angezeigte Datum (Tagesansicht).
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Montag der Woche des gewählten Datums (abgeleitet).
DateTime mondayOfWeek(DateTime date) {
  final d = date.subtract(Duration(days: date.weekday - 1));
  return DateTime(d.year, d.month, d.day);
}

// ---------------------------------------------------------------------------
// Whiteboard-Task-Modell
// ---------------------------------------------------------------------------

/// Ein [ProductionTask] angereichert mit Produktname fürs Whiteboard.
class WhiteboardTask {
  WhiteboardTask({
    required this.task,
    required this.produktName,
    required this.artikelnummer,
  });

  final ProductionTask task;
  final String produktName;
  final String artikelnummer;

  Abteilung get abteilungEnum => Abteilung.fromDbValue(task.abteilung);

  /// Startzeit als Minuten seit Mitternacht (oder null).
  int? get startMinutes {
    final sz = task.startZeit;
    if (sz == null || sz.isEmpty) return null;
    final parts = sz.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}

// ---------------------------------------------------------------------------
// Tages-Tasks laden
// ---------------------------------------------------------------------------

/// Alle nicht-stornierten Tasks des gewählten Tages mit Produktinfos.
final dailyTasksProvider = FutureProvider<List<WhiteboardTask>>((ref) async {
  final db = ref.watch(databaseProvider);
  final date = ref.watch(selectedDateProvider);
  final nextDay = date.add(const Duration(days: 1));

  final query = db.select(db.productionTasks).join([
    innerJoin(
      db.products,
      db.products.id.equalsExp(db.productionTasks.productId),
    ),
  ])
    ..where(db.productionTasks.deletedAt.isNull())
    ..where(db.productionTasks.datum.isBiggerOrEqualValue(date))
    ..where(db.productionTasks.datum.isSmallerThanValue(nextDay))
    ..where(db.productionTasks.status.isNotIn(const ['storniert']));

  final rows = await query.get();

  return rows.map((row) {
    final task = row.readTable(db.productionTasks);
    final product = row.readTable(db.products);
    return WhiteboardTask(
      task: task,
      produktName: product.artikelbezeichnung,
      artikelnummer: product.artikelnummer,
    );
  }).toList();
});

// ---------------------------------------------------------------------------
// Produkt planen: Schritt-Plan berechnen + Tasks erzeugen
// ---------------------------------------------------------------------------

/// dbValue der Bratstraße — für diese Abteilung kommt die realistische Dauer
/// aus der Produktions-Historie (dort wird die Zeit tatsächlich gemessen).
const String _kBratstrasseDbValue = 'bratstrasse';

/// Ein berechneter Planungs-Schritt: was eine Abteilung für die geplante
/// Menge zu tun hat. Der [tag] ist im Planen-Dialog frei verschiebbar.
class GeplanterSchritt {
  GeplanterSchritt({
    required this.stepId,
    required this.reihenfolge,
    required this.abteilungDbValue,
    required this.prozessschritt,
    required this.mengeKg,
    required this.dauerMinuten,
    required this.mitarbeiter,
    required this.ausHistorie,
    required this.platzhalter,
    required this.notizen,
    required this.tag,
  });

  final String stepId;
  final int reihenfolge;
  final String abteilungDbValue;
  final String? prozessschritt;

  /// Eingangsmenge dieses Schritts in kg (rückwärts über die Ausbeute).
  final double mengeKg;

  /// Berechnete Dauer in Minuten.
  final double dauerMinuten;
  final int mitarbeiter;

  /// Dauer stammt aus dem Historie-Durchschnitt (Bratstraße).
  final bool ausHistorie;

  /// Keine gepflegten Zeit-Stammdaten → Dauer ist ein Platzhalter.
  final bool platzhalter;

  final String? notizen;

  /// Zugewiesener Produktionstag (im Dialog veränderbar).
  DateTime tag;

  Abteilung? get abteilung {
    try {
      return Abteilung.fromDbValue(abteilungDbValue);
    } catch (_) {
      return null;
    }
  }
}

/// Ergebnis von [berechneSchrittPlan].
class GeplanterPlan {
  GeplanterPlan({required this.rohwareKg, required this.schritte});

  /// Benötigte Rohwarenmenge (Input des ersten Schritts).
  final double rohwareKg;
  final List<GeplanterSchritt> schritte;
}

/// Berechnet aus Produkt + gewünschter Fertigmenge den Schritt-Plan:
/// pro Schritt Eingangsmenge (rückwärts über die Ausbeute), Dauer und
/// Personen. Für die **Bratstraße** wird die Dauer aus dem Ø der
/// Produktions-Historie (kg/h roh) bestimmt, sonst aus den Schritt-Stammdaten
/// linear auf die Menge skaliert. Alle Schritte starten auf [startTag];
/// die Tageszuordnung wird anschließend im Dialog angepasst.
Future<GeplanterPlan> berechneSchrittPlan({
  required AppDatabase db,
  required String productId,
  required double mengeKg,
  required DateTime startTag,
}) async {
  final steps = await (db.select(db.productSteps)
        ..where((s) => s.productId.equals(productId))
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
      .get();

  if (steps.isEmpty) {
    return GeplanterPlan(rohwareKg: mengeKg, schritte: const []);
  }

  // Rückwärtsrechnung der Eingangsmengen (letzter Schritt = mengeKg Fertig).
  final inputMengen = List<double>.filled(steps.length, mengeKg);
  for (var i = steps.length - 1; i >= 0; i--) {
    final ausbeute = steps[i].ausbeuteFaktor ?? 1.0;
    if (ausbeute > 0 && ausbeute < 1.0) {
      inputMengen[i] = inputMengen[i] / ausbeute;
    }
    if (i > 0) inputMengen[i - 1] = inputMengen[i];
  }

  // Ø kg/h roh aus der Historie (für die Bratstraße).
  final histAvgKgh = await _avgKghRohAusHistorie(db, productId);

  final tagNorm = DateTime(startTag.year, startTag.month, startTag.day);
  final result = <GeplanterSchritt>[];

  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final menge = inputMengen[i];
    final notizen = StringBuffer();

    var ausHistorie = false;
    var platzhalter = false;
    double dauer;

    final istBratstrasse = step.abteilung == _kBratstrasseDbValue;
    if (istBratstrasse && histAvgKgh != null && histAvgKgh > 0) {
      // Realistische Dauer aus dem gemessenen Durchsatz.
      dauer = menge / histAvgKgh * 60.0;
      ausHistorie = true;
      notizen.write('Dauer aus Historie (Ø kg/h). ');
    } else {
      final (d, ph) = _skaliereDauer(step, menge, notizen);
      dauer = d;
      platzhalter = ph;
    }

    final ausbeute = step.ausbeuteFaktor;
    if (ausbeute != null && ausbeute < 1.0) {
      final verlust = ((1 - ausbeute) * 100).toStringAsFixed(0);
      notizen.write(
        'Ausbeute ${(ausbeute * 100).toStringAsFixed(0)}% '
        '(Verlust $verlust%). ',
      );
    }

    // Sicherheitsnetz gegen unsinnige Werte.
    if (!dauer.isFinite || dauer.isNaN || dauer < 0) dauer = 30.0;
    if (dauer > 60 * 24 * 7) dauer = 30.0;

    result.add(
      GeplanterSchritt(
        stepId: step.id,
        reihenfolge: step.reihenfolge,
        abteilungDbValue: step.abteilung,
        prozessschritt: step.prozessschritt,
        mengeKg: menge,
        dauerMinuten: dauer.roundToDouble(),
        mitarbeiter: step.basisMitarbeiter > 0 ? step.basisMitarbeiter : 1,
        ausHistorie: ausHistorie,
        platzhalter: platzhalter,
        notizen: notizen.isEmpty ? null : notizen.toString().trim(),
        tag: tagNorm,
      ),
    );
  }

  return GeplanterPlan(rohwareKg: inputMengen[0], schritte: result);
}

/// Lineare Dauer-Skalierung aus den Schritt-Stammdaten inkl. Chargen-Logik.
/// Liefert (Dauer, istPlatzhalter). Schreibt ggf. Hinweise in [notizen].
(double, bool) _skaliereDauer(
  ProductStep step,
  double stepMenge,
  StringBuffer notizen,
) {
  final fixZeit = step.fixZeitMinuten ?? 0.0;
  final basisMenge = step.basisMengeKg;
  final basisDauer = step.basisDauerMinuten;

  double dauer;
  var platzhalter = false;

  if (basisMenge > 0 && basisDauer > 0) {
    dauer = fixZeit + basisDauer * (stepMenge / basisMenge);
  } else if (basisDauer > 0) {
    dauer = fixZeit + basisDauer;
  } else {
    dauer = fixZeit > 0 ? fixZeit : 30.0;
    platzhalter = true;
    notizen.write('Zeit ist Platzhalter (Stammdaten noch nicht gepflegt). ');
  }

  // Chargengrößen: mehrere Durchgänge bei Überschreitung der Kapazität.
  final maxCharge = step.maxChargenKg;
  if (maxCharge != null &&
      maxCharge > 0 &&
      stepMenge > maxCharge &&
      basisMenge > 0 &&
      basisDauer > 0) {
    final durchgaenge = (stepMenge / maxCharge).ceil();
    final dauerProCharge = fixZeit + basisDauer * (maxCharge / basisMenge);
    dauer = dauerProCharge * durchgaenge;
    notizen.write(
      '$durchgaenge Durchgänge à ${maxCharge.toStringAsFixed(0)} kg. ',
    );
  }

  return (dauer, platzhalter);
}

/// Durchschnittliches kg/h roh aus der Produktions-Historie eines Produkts,
/// oder null wenn keine brauchbaren Werte vorliegen.
Future<double?> _avgKghRohAusHistorie(
  AppDatabase db,
  String productId,
) async {
  final rows = await (db.select(db.productionHistory)
        ..where((h) => h.productId.equals(productId))
        ..where((h) => h.deletedAt.isNull()))
      .get();

  final werte = rows
      .map((h) => h.kgProStundeRoh)
      .whereType<double>()
      .where((v) => v > 0)
      .toList();
  if (werte.isEmpty) return null;
  return werte.reduce((a, b) => a + b) / werte.length;
}

/// Legt aus einem [GeplanterPlan] je Schritt einen [ProductionTask] am
/// zugewiesenen [GeplanterSchritt.tag] an und verkettet sie über
/// [parentTaskId] (in Reihenfolge). Es werden **keine** festen Uhrzeiten
/// gesetzt — die Reihenfolge innerhalb eines Tages wird im Board geregelt.
Future<void> erstelleTasksAusPlan({
  required AppDatabase db,
  required String productId,
  required List<GeplanterSchritt> schritte,
}) async {
  const uuid = Uuid();
  final sortiert = [...schritte]
    ..sort((a, b) => a.reihenfolge.compareTo(b.reihenfolge));

  String? previousTaskId;
  for (final s in sortiert) {
    final taskId = uuid.v4();
    final tag = DateTime(s.tag.year, s.tag.month, s.tag.day);

    await db.into(db.productionTasks).insert(
          ProductionTasksCompanion.insert(
            id: taskId,
            productId: productId,
            mengeKg: s.mengeKg,
            datum: tag,
            abteilung: s.abteilungDbValue,
            geplanteDauerMinuten: s.dauerMinuten,
            geplanteMitarbeiter: s.mitarbeiter,
            parentTaskId: Value(previousTaskId),
            notizen: Value(s.notizen),
          ),
        );
    previousTaskId = taskId;
  }
}

/// Komfort-Funktion: berechnet den Plan und legt alle Schritte auf [datum] an.
/// Gibt die benötigte Rohwarenmenge (Input Schritt 1) zurück.
Future<double> createTasksFromProduct({
  required AppDatabase db,
  required String productId,
  required double mengeKg,
  required DateTime datum,
}) async {
  final plan = await berechneSchrittPlan(
    db: db,
    productId: productId,
    mengeKg: mengeKg,
    startTag: datum,
  );
  if (plan.schritte.isEmpty) return mengeKg;
  await erstelleTasksAusPlan(
    db: db,
    productId: productId,
    schritte: plan.schritte,
  );
  return plan.rohwareKg;
}