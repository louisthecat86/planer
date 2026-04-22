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
// Produkt planen: Tasks aus ProductSteps erzeugen
// ---------------------------------------------------------------------------

/// Erzeugt für jedes [ProductStep] eines Produkts einen [ProductionTask]
/// und verkettet sie über [parentTaskId].
///
/// Berücksichtigt:
/// - **Chargengrößen**: Wenn maxChargenKg gesetzt ist, werden mehrere
///   Durchgänge berechnet (Menge ÷ maxCharge, aufgerundet).
/// - **Wartezeiten**: wartezeitMinuten wird als Puffer nach dem Schritt addiert.
/// - **Ausbeute**: Rückwärtsrechnung – wenn 1000 kg Fertigware gewünscht und
///   Gesamtausbeute 0.75, werden 1333 kg Rohware benötigt. Pro Schritt wird
///   die eingehende Menge um den Ausbeutefaktor reduziert.
///
/// **Robustheit bei unvollständigen Stammdaten** (v4-Erweiterung):
/// Wenn `basisMengeKg` oder `basisDauerMinuten` 0 sind (typisch nach einem
/// v3-Excel-Import ohne gepflegte Zeiten), wird ein Default-Wert verwendet
/// damit die Planung nicht durch Division durch Null hängenbleibt. Die
/// resultierenden Zeiten sind dann Platzhalter und müssen in der App
/// nachgepflegt werden.
///
/// Gibt die berechnete Gesamt-Rohwarenmenge (Input Schritt 1) zurück.
Future<double> createTasksFromProduct({
  required AppDatabase db,
  required String productId,
  required double mengeKg,
  required DateTime datum,
}) async {
  const uuid = Uuid();

  final steps = await (db.select(db.productSteps)
        ..where((s) => s.productId.equals(productId))
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
      .get();

  if (steps.isEmpty) return mengeKg;

  // Rückwärtsrechnung der Eingangsmengen pro Schritt.
  // Letzter Schritt produziert mengeKg Fertigware.
  // Jeder Schritt davor muss mehr Input haben wegen Ausbeuteverlust.
  final inputMengen = List<double>.filled(steps.length, mengeKg);
  for (var i = steps.length - 1; i >= 0; i--) {
    final ausbeute = steps[i].ausbeuteFaktor ?? 1.0;
    // Nur gültige Ausbeute-Faktoren berücksichtigen (0 < a < 1).
    if (ausbeute > 0 && ausbeute < 1.0) {
      inputMengen[i] = inputMengen[i] / ausbeute;
    }
    // Vorheriger Schritt muss genug für diesen liefern
    if (i > 0) {
      inputMengen[i - 1] = inputMengen[i];
    }
  }

  String? previousTaskId;
  int offsetMinutes = 4 * 60; // Start bei 04:00

  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final taskId = uuid.v4();
    final stepMenge = inputMengen[i];

    // ── Dauer berechnen, robust gegen fehlende Basiswerte ──────────────
    final fixZeit = step.fixZeitMinuten ?? 0.0;
    final basisMenge = step.basisMengeKg;
    final basisDauer = step.basisDauerMinuten;

    double scaledDauer;
    if (basisMenge > 0 && basisDauer > 0) {
      // Normaler Fall: Lineare Skalierung auf Auftragsmenge
      scaledDauer = fixZeit + basisDauer * (stepMenge / basisMenge);
    } else if (basisDauer > 0) {
      // Dauer vorhanden, aber keine Basismenge -> Dauer direkt übernehmen
      scaledDauer = fixZeit + basisDauer;
    } else {
      // Weder Basismenge noch Basisdauer gepflegt -> 30 min Platzhalter.
      // Der User muss diese Zeit später in der App nachpflegen.
      scaledDauer = fixZeit > 0 ? fixZeit : 30.0;
    }

    // Chargengrößen: mehrere Durchgänge bei Überschreitung der Kapazität
    final maxCharge = step.maxChargenKg;
    int durchgaenge = 1;
    if (maxCharge != null &&
        maxCharge > 0 &&
        stepMenge > maxCharge &&
        basisMenge > 0 &&
        basisDauer > 0) {
      durchgaenge = (stepMenge / maxCharge).ceil();
      final dauerProCharge =
          fixZeit + basisDauer * (maxCharge / basisMenge);
      scaledDauer = dauerProCharge * durchgaenge;
    }

    // Sicherheitsnetz: unsinnige Werte abfangen
    if (!scaledDauer.isFinite || scaledDauer.isNaN || scaledDauer < 0) {
      scaledDauer = 30.0;
    }
    // Obergrenze: mehr als eine Woche pro Schritt ist mit Sicherheit
    // ein Rechenfehler (oder schlecht gepflegte Daten)
    if (scaledDauer > 60 * 24 * 7) {
      scaledDauer = 30.0;
    }

    final dauer = scaledDauer.roundToDouble();

    final hh = (offsetMinutes ~/ 60).toString().padLeft(2, '0');
    final mm = (offsetMinutes % 60).toString().padLeft(2, '0');
    final startZeit = '$hh:$mm';

    // Notizen mit berechneten Details
    final notizen = StringBuffer();
    if (durchgaenge > 1) {
      notizen.write(
        '$durchgaenge Durchgänge à ${maxCharge!.toStringAsFixed(0)} kg. ',
      );
    }
    final ausbeuteNote = step.ausbeuteFaktor;
    if (ausbeuteNote != null && ausbeuteNote < 1.0) {
      final verlust = ((1 - ausbeuteNote) * 100).toStringAsFixed(0);
      notizen.write(
        'Ausbeute ${(ausbeuteNote * 100).toStringAsFixed(0)}% '
        '(Verlust $verlust%). ',
      );
    }
    if (basisMenge == 0 || basisDauer == 0) {
      notizen.write(
        'Zeit ist Platzhalter (Stammdaten noch nicht gepflegt). ',
      );
    }

    // Mitarbeiter: 1 als Default wenn basisMitarbeiter 0 oder negativ
    final mitarbeiter = step.basisMitarbeiter > 0 ? step.basisMitarbeiter : 1;

    await db.into(db.productionTasks).insert(
          ProductionTasksCompanion.insert(
            id: taskId,
            productId: productId,
            mengeKg: stepMenge,
            datum: datum,
            abteilung: step.abteilung,
            geplanteDauerMinuten: dauer,
            geplanteMitarbeiter: mitarbeiter,
            startZeit: Value(startZeit),
            parentTaskId: Value(previousTaskId),
            notizen: Value(
              notizen.isEmpty ? null : notizen.toString().trim(),
            ),
          ),
        );

    previousTaskId = taskId;

    // Offset: Dauer + Wartezeit + 15 min Puffer
    final wartezeit = (step.wartezeitMinuten ?? 0.0).toInt();
    offsetMinutes += dauer.toInt() + wartezeit + 15;
  }

  return inputMengen[0]; // Gesamt-Rohwarenmenge für Schritt 1
}