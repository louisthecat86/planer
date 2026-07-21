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
    this.maschineId,
  });

  final String stepId;
  final int reihenfolge;
  final String abteilungDbValue;

  /// Anlage des Schritts — bestimmt im Board die Kapazitätsspur.
  /// Ohne sie landet der Auftrag in der Sammelspur der Abteilung.
  final String? maschineId;
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

  // Pro Schritt zunächst Dauer + Platzhalter + Bezeichnung berechnen.
  final perStep =
      <({ProductStep step, double menge, double dauer, bool platzhalter, String label})>[];
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final menge = inputMengen[i];
    final muell = StringBuffer();
    final (d, ph) = _skaliereDauer(step, menge, muell);
    final label = (step.prozessschritt != null &&
            step.prozessschritt!.isNotEmpty)
        ? step.prozessschritt!
        : (step.maschine ?? '');
    perStep.add(
      (step: step, menge: menge, dauer: d, platzhalter: ph, label: label),
    );
  }

  // Aufeinanderfolgende Schritte derselben Abteilung zu EINEM Block bündeln
  // (z.B. Bratstraße = Verbufa + Bratstraße + Dampftunnel → ein Eintrag).
  final result = <GeplanterSchritt>[];
  var i = 0;
  while (i < perStep.length) {
    final abt = perStep[i].step.abteilung;
    final block = [perStep[i]];
    var j = i + 1;
    while (j < perStep.length && perStep[j].step.abteilung == abt) {
      block.add(perStep[j]);
      j++;
    }
    i = j;

    final blockMenge = block.first.menge;
    final istBratstrasse = abt == _kBratstrasseDbValue;
    final notizen = StringBuffer();

    final labels =
        block.map((b) => b.label).where((l) => l.isNotEmpty).toList();
    if (labels.length > 1) {
      notizen.write('Maschinen/Schritte: ${labels.join(' · ')}. ');
    }

    var ausHistorie = false;
    var platzhalter = false;
    double dauer;

    if (istBratstrasse && histAvgKgh != null && histAvgKgh > 0) {
      // Auflagezeit (erste bis letzte Auflage aufs Band) aus dem gemessenen
      // Durchsatz; fixe Durchlauf-/Verpackzeiten der Maschinen oben drauf.
      final auflage = blockMenge / histAvgKgh * 60.0;
      final durchlauf = block.fold<double>(
        0,
        (summe, b) => summe + (b.step.fixZeitMinuten ?? 0.0),
      );
      dauer = auflage + durchlauf;
      ausHistorie = true;
      if (durchlauf > 0) {
        notizen.write(
          'Auflage ${auflage.round()} min + Durchlauf/Verpacken '
          '${durchlauf.round()} min. ',
        );
      } else {
        notizen.write('Dauer aus Historie (Ø kg/h, Auflagezeit). ');
      }
    } else {
      // Wichtig: In der Bratstraße bilden Bratstraße, Dampftunnel,
      // Schockfroster & Co. EINE durchlaufende Linie — das Produkt
      // passiert sie nacheinander, aber die Linie läuft als Ganzes.
      // Die Dauern dürfen deshalb NICHT addiert werden; maßgeblich ist
      // die längste Station.
      //
      // Läuft ein Produkt erst ab dem Dampftunnel (ohne Bratstraße),
      // greift genau dieselbe Rechnung — dann ist der Dampftunnel die
      // längste (und einzige) Station und bestimmt die Dauer.
      if (istBratstrasse) {
        dauer = block.fold<double>(0, (m, b) => b.dauer > m ? b.dauer : m);
        if (block.length > 1) {
          notizen.write('Durchlaufende Linie (längste Station zählt). ');
        }
      } else {
        dauer = block.fold<double>(0, (summe, b) => summe + b.dauer);
      }
      platzhalter = block.any((b) => b.platzhalter);
      if (platzhalter) {
        notizen.write('Zeit teils Platzhalter (Stammdaten pflegen). ');
      }
    }

    // Sicherheitsnetz gegen unsinnige Werte.
    if (!dauer.isFinite || dauer.isNaN || dauer < 0) dauer = 30.0;
    if (dauer > 60 * 24 * 7) dauer = 30.0;

    final mitarbeiter = block
        .map((b) => b.step.basisMitarbeiter)
        .fold<int>(1, (m, v) => v > m ? v : m);

    result.add(
      GeplanterSchritt(
        stepId: block.first.step.id,
        reihenfolge: block.first.step.reihenfolge,
        abteilungDbValue: abt,
        // Anlage aus dem ersten Schritt des Blocks, der eine hat.
        maschineId: block
            .map((b) => b.step.maschineId)
            .firstWhere((m) => m != null, orElse: () => null),
        prozessschritt: labels.isEmpty ? null : labels.join(' · '),
        mengeKg: blockMenge,
        dauerMinuten: dauer.roundToDouble(),
        mitarbeiter: mitarbeiter,
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

/// Durchschnittlicher Verlustanteil eines Artikels aus der Historie
/// (0…1, z.B. 0.18 = 18 % Verlust). null, wenn keine brauchbaren Werte da
/// sind. Wird genutzt, um aus einer Fertigmenge die nötige Rohmenge
/// zurückzurechnen: Rohware = Fertigware / (1 − Verlust).
Future<double?> durchschnittsVerlust(
  AppDatabase db,
  String productId,
) async {
  final rows = await (db.select(db.productionHistory)
        ..where((h) => h.productId.equals(productId))
        ..where((h) => h.deletedAt.isNull()))
      .get();

  final werte = rows
      .map((h) => h.verlustAnteil)
      .whereType<double>()
      // Plausibilitätsgrenzen: negativer oder ≥100 % Verlust ist ein
      // Erfassungsfehler und würde den Schnitt verzerren.
      .where((v) => v > 0 && v < 1)
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
  String? bedarfId,
  double? fertigMengeKg,
}) async {
  const uuid = Uuid();
  final sortiert = [...schritte]
    ..sort((a, b) => a.reihenfolge.compareTo(b.reihenfolge));

  String? previousTaskId;
  for (final s in sortiert) {
    final taskId = uuid.v4();
    final tag = DateTime(s.tag.year, s.tag.month, s.tag.day);
    // Der Bedarf hängt an der WURZEL der Kette. Nur dort steht die
    // Fertigmenge — sonst würde sie bei jedem Abteilungsschritt erneut
    // gegen den Bedarf gerechnet und die Liste wäre sofort „gedeckt".
    final istWurzel = previousTaskId == null;

    await db.into(db.productionTasks).insert(
          ProductionTasksCompanion.insert(
            id: taskId,
            productId: productId,
            mengeKg: s.mengeKg,
            datum: tag,
            abteilung: s.abteilungDbValue,
            maschineId: Value(s.maschineId),
            bedarfId: Value(istWurzel ? bedarfId : null),
            fertigMengeKg: Value(istWurzel ? fertigMengeKg : null),
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
  String? bedarfId,
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
    bedarfId: bedarfId,
    // mengeKg ist die geplante FERTIGWARE — genau das, was gegen den
    // Bedarf zählt. Die Rohware rechnet der Plan daraus zurück.
    fertigMengeKg: mengeKg,
  );
  return plan.rohwareKg;
}
