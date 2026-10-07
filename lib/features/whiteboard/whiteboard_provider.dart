import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auftragsbestand_deckung.dart' show AuftragsBezug;
import '../../core/services/produktion_erfassen_service.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/zeit.dart';

// ---------------------------------------------------------------------------
// Datums-Auswahl
// ---------------------------------------------------------------------------

/// Das aktuell angezeigte Datum (Tagesansicht).
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Montag der Woche des gewählten Datums (abgeleitet).
DateTime mondayOfWeek(DateTime date) => tagPlus(date, -(date.weekday - 1));

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
  final nextDay = tagPlus(date, 1);

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

/// Woher die Dauer einer Abteilung stammt.
enum DauerQuelle {
  /// Gepflegte Leistungsdaten der Abteilung — „Menge X kg in Zeit Y" —
  /// oder eine feste Zeit ohne Menge.
  leistungsdaten,

  /// Ø der letzten erfassten Produktionen. Für die Bratstraße der
  /// Regelfall: Dort wird die Zeit tatsächlich gemessen.
  historie,

  /// Für die Abteilung sind keine Leistungsdaten gepflegt. Ersatzweise
  /// zählt der Ø der letzten erfassten Produktionen des Artikels.
  historieErsatz,

  /// Weder Leistungsdaten noch Produktionen mit Zeit: Die Dauer ist ein
  /// Platzhalter.
  platzhalter,
}

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
    required this.dauerQuelle,
    required this.notizen,
    required this.tag,
    this.historie,
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

  /// Woher [dauerMinuten] stammt.
  final DauerQuelle dauerQuelle;

  /// Die Produktionen, aus denen die Dauer stammt — gesetzt, wenn
  /// [ausHistorie].
  final HistorienLeistung? historie;

  /// Dauer stammt aus dem Ø der letzten Produktionen: in der Bratstraße
  /// regulär, sonst ersatzweise für fehlende Leistungsdaten.
  bool get ausHistorie =>
      dauerQuelle == DauerQuelle.historie ||
      dauerQuelle == DauerQuelle.historieErsatz;

  /// Weder Leistungsdaten noch Produktionen mit Zeit → die Dauer ist ein
  /// Platzhalter.
  bool get platzhalter => dauerQuelle == DauerQuelle.platzhalter;

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
  GeplanterPlan({
    required this.rohwareKg,
    required this.fertigwareKg,
    required this.ausbeute,
    required this.schritte,
  });

  /// Benötigte Rohwarenmenge (Input des ersten Schritts).
  final double rohwareKg;

  /// Fertigmenge, für die der Plan gerechnet wurde.
  final double fertigwareKg;

  /// Die Ausbeute, mit der zwischen beiden gerechnet wurde.
  final Ausbeute ausbeute;

  final List<GeplanterSchritt> schritte;
}

// ---------------------------------------------------------------------------
// Ausbeute: Rohware ↔ Fertigware
// ---------------------------------------------------------------------------

/// Woher die Ausbeute eines Artikels stammt.
///
/// Gesucht wird so: Sind mindestens [kMindestErfassungenAusbeute]
/// Produktionen erfasst, gilt deren Ø — gemessen schlägt gepflegt. Sonst
/// die Ausbeute an den Schritten, dann die Gesamtausbeute des Artikels,
/// dann der Ø aus den wenigen erfassten Produktionen, zuletzt die Eingabe
/// im Planen-Dialog.
enum AusbeuteQuelle {
  /// Ausbeute-Faktoren an den einzelnen Prozessschritten; sie
  /// multiplizieren sich über die Kette.
  schritte,

  /// „Gesamtausbeute" in den Stammdaten des Artikels.
  artikel,

  /// Ø Verlust aus den erfassten Produktionen.
  historie,

  /// Im Planen-Dialog von Hand eingetragen — gilt nur, wenn der Artikel
  /// selbst keine Ausbeute liefert.
  eingabe,

  /// Nichts bekannt: Es wird ohne Verlust gerechnet.
  keine,
}

/// Wie viel Fertigware aus einem Kilo Rohware wird, und woher die Zahl
/// stammt.
///
/// Rohware heißt hier: was am Anfang der Kette in den ersten Schritt geht.
/// Fertigware: was am Ende herauskommt. Mit genau dieser Zahl rechnet
/// [berechneSchrittPlan] — wer irgendwo zwischen Rohware und Fertigware
/// umrechnet, muss sie verwenden, sonst passen Anzeige und Plan nicht
/// zusammen.
class Ausbeute {
  const Ausbeute({
    required this.faktor,
    required this.quelle,
    this.historie,
    this.historieAnzahl = 0,
  });

  /// Keine Ausbeute bekannt: Rohware = Fertigware.
  static const unbekannt = Ausbeute(faktor: 1, quelle: AusbeuteQuelle.keine);

  /// Fertigware je kg Rohware, 0 < faktor ≤ 1.
  final double faktor;

  final AusbeuteQuelle quelle;

  /// Ø Ausbeute laut Produktionshistorie — zum Vergleich, auch wenn eine
  /// andere Quelle gilt. null ohne Historie.
  final double? historie;

  /// Aus wie vielen erfassten Produktionen [historie] stammt.
  final int historieAnzahl;

  bool get bekannt => quelle != AusbeuteQuelle.keine;

  double rohAusFertig(double fertigKg) => fertigKg / faktor;

  double fertigAusRoh(double rohKg) => rohKg * faktor;
}

/// Ermittelt die Ausbeute eines Artikels nach denselben Regeln wie
/// [berechneSchrittPlan]. [ersatz] (0 < x < 1) gilt nur, wenn der Artikel
/// weder an den Schritten noch in den Stammdaten noch in der Historie eine
/// Ausbeute hat.
Future<Ausbeute> ermittleAusbeute(
  AppDatabase db,
  String productId, {
  double? ersatz,
}) async {
  final steps = await _ladeSchritte(db, productId);
  return _ausbeuteFuer(db, productId, steps, ersatz: ersatz);
}

Future<List<ProductStep>> _ladeSchritte(AppDatabase db, String productId) {
  return (db.select(db.productSteps)
        ..where((s) => s.productId.equals(productId))
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
      .get();
}

/// Ab so vielen erfassten Produktionen gilt deren Ø-Ausbeute vor den
/// gepflegten Stammdaten. Eine einzelne Produktion kann ein Ausreißer
/// sein; ab drei trägt der Schnitt.
const int kMindestErfassungenAusbeute = 3;

Future<Ausbeute> _ausbeuteFuer(
  AppDatabase db,
  String productId,
  List<ProductStep> steps, {
  double? ersatz,
}) async {
  final (:historie, :anzahl) = await _historienAusbeute(db, productId);

  Ausbeute ausHistorie(double faktor) => Ausbeute(
        faktor: faktor,
        quelle: AusbeuteQuelle.historie,
        historie: faktor,
        historieAnzahl: anzahl,
      );

  // 1. Genug erfasste Produktionen: Gemessen schlägt gepflegt.
  if (historie != null && anzahl >= kMindestErfassungenAusbeute) {
    return ausHistorie(historie);
  }

  // 2. Ausbeute an den Schritten: Sie multipliziert sich über die Kette.
  var kette = 1.0;
  var hatSchrittAusbeute = false;
  for (final s in steps) {
    final a = s.ausbeuteFaktor;
    if (a != null && a > 0 && a < 1) {
      kette *= a;
      hatSchrittAusbeute = true;
    }
  }
  if (hatSchrittAusbeute) {
    return Ausbeute(
      faktor: kette,
      quelle: AusbeuteQuelle.schritte,
      historie: historie,
      historieAnzahl: anzahl,
    );
  }

  // 3. Gesamtausbeute am Artikel.
  final produkt = await (db.select(db.products)
        ..where((p) => p.id.equals(productId)))
      .getSingleOrNull();
  final gesamt = produkt?.gesamtAusbeuteFaktor;
  if (gesamt != null && gesamt > 0 && gesamt < 1) {
    return Ausbeute(
      faktor: gesamt,
      quelle: AusbeuteQuelle.artikel,
      historie: historie,
      historieAnzahl: anzahl,
    );
  }

  // 4. Wenige erfasste Produktionen sind immer noch besser als nichts.
  if (historie != null) return ausHistorie(historie);

  // 5. Von Hand im Dialog eingetragen.
  if (ersatz != null && ersatz > 0 && ersatz < 1) {
    return Ausbeute(faktor: ersatz, quelle: AusbeuteQuelle.eingabe);
  }
  return Ausbeute.unbekannt;
}

/// Berechnet aus Produkt + gewünschter **Fertigmenge** den Schritt-Plan:
/// pro Schritt Eingangsmenge (rückwärts über die Ausbeute), Dauer und
/// Personen. Für die **Bratstraße** kommt die Dauer aus dem Ø der letzten
/// erfassten Produktionen, sonst aus den Leistungsdaten der Abteilung,
/// linear auf die Menge skaliert. Fehlen die Leistungsdaten, dienen auch
/// dort die letzten Produktionen als Basis (siehe [HistorienLeistung]).
/// Alle Schritte starten auf [startTag]; die Tageszuordnung wird
/// anschließend im Dialog angepasst.
///
/// [mengeKg] ist IMMER Fertigware. Wer von einer Rohwarenmenge ausgeht,
/// rechnet sie vorher mit [ermittleAusbeute] um — sonst wird der Verlust
/// ein zweites Mal aufgeschlagen, und der Plan ist um genau diesen Faktor
/// zu groß. [ausbeuteErsatz] gilt nur für Artikel ohne eigene Ausbeute
/// (siehe [AusbeuteQuelle.eingabe]).
Future<GeplanterPlan> berechneSchrittPlan({
  required AppDatabase db,
  required String productId,
  required double mengeKg,
  required DateTime startTag,
  double? ausbeuteErsatz,
}) async {
  final steps = await _ladeSchritte(db, productId);

  if (steps.isEmpty) {
    return GeplanterPlan(
      rohwareKg: mengeKg,
      fertigwareKg: mengeKg,
      ausbeute: Ausbeute.unbekannt,
      schritte: const [],
    );
  }

  final ausbeute = await _ausbeuteFuer(
    db,
    productId,
    steps,
    ersatz: ausbeuteErsatz,
  );

  // Rückwärtsrechnung der Eingangsmengen (letzter Schritt = mengeKg Fertig).
  final inputMengen = List<double>.filled(steps.length, mengeKg);
  if (ausbeute.quelle == AusbeuteQuelle.schritte) {
    for (var i = steps.length - 1; i >= 0; i--) {
      final a = steps[i].ausbeuteFaktor;
      if (a != null && a > 0 && a < 1) {
        inputMengen[i] = inputMengen[i] / a;
      }
      if (i > 0) inputMengen[i - 1] = inputMengen[i];
    }
  } else if (ausbeute.bekannt) {
    // Eine Gesamtausbeute für den ganzen Artikel. Ohne sie wäre die
    // Rohwarenmenge gleich der Fertigmenge — der Bratverlust fiele unter
    // den Tisch, und eine Bestellung nach diesen Zahlen käme zu knapp.
    //
    // Der Verlust entsteht beim Garen. Alles bis einschließlich der
    // Bratstraße arbeitet deshalb mit der Rohmenge, alles danach
    // (Verpackung, Wiegen) mit der Fertigmenge. Gibt es keine Bratstraße,
    // gilt die Rohmenge für die ganze Kette.
    final rohMenge = ausbeute.rohAusFertig(mengeKg);
    var letzterGarschritt = steps.length - 1;
    for (var i = steps.length - 1; i >= 0; i--) {
      if (steps[i].abteilung == _kBratstrasseDbValue) {
        letzterGarschritt = i;
        break;
      }
    }
    for (var i = 0; i <= letzterGarschritt; i++) {
      inputMengen[i] = rohMenge;
    }
  }

  // Ø der letzten Produktionen: Grundlage der Bratstraße und Ersatz für
  // fehlende Leistungsdaten in allen anderen Abteilungen.
  final historie = await historienLeistung(db, productId);

  final tagNorm = DateTime(startTag.year, startTag.month, startTag.day);

  // Aufeinanderfolgende Schritte derselben Abteilung zu EINEM Block bündeln
  // (z.B. Bratstraße = Verbufa + Bratstraße + Dampftunnel → ein Eintrag).
  final result = <GeplanterSchritt>[];
  var i = 0;
  while (i < steps.length) {
    final abt = steps[i].abteilung;
    final block = <({ProductStep step, double menge})>[];
    while (i < steps.length && steps[i].abteilung == abt) {
      block.add((step: steps[i], menge: inputMengen[i]));
      i++;
    }

    final labels = block
        .map((b) => _schrittBezeichnung(b.step))
        .where((l) => l.isNotEmpty)
        .toList();
    final dauer = _blockDauer(block, historie);

    final notizen = StringBuffer();
    if (labels.length > 1) {
      notizen.write('Maschinen/Schritte: ${labels.join(' · ')}. ');
    }
    notizen.write(dauer.hinweise);

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
        mengeKg: block.first.menge,
        dauerMinuten: dauer.minuten.roundToDouble(),
        mitarbeiter: mitarbeiter,
        dauerQuelle: dauer.quelle,
        historie: dauer.historie,
        notizen: notizen.isEmpty ? null : notizen.toString().trim(),
        tag: tagNorm,
      ),
    );
  }

  return GeplanterPlan(
    rohwareKg: inputMengen[0],
    fertigwareKg: mengeKg,
    ausbeute: ausbeute,
    schritte: result,
  );
}

/// Bezeichnung eines Schritts für Plan und Notizen: der Prozessschritt,
/// sonst die Maschine.
String _schrittBezeichnung(ProductStep step) {
  final p = step.prozessschritt;
  if (p != null && p.isNotEmpty) return p;
  return step.maschine ?? '';
}

// ---------------------------------------------------------------------------
// Dauer einer Abteilung
// ---------------------------------------------------------------------------

/// Dauer einer Abteilung für eine Menge — und woher sie stammt.
class AbteilungsDauer {
  const AbteilungsDauer({
    required this.minuten,
    required this.quelle,
    this.historie,
    this.hinweise = '',
  });

  final double minuten;
  final DauerQuelle quelle;

  /// Die Produktionen, aus denen die Dauer stammt — gesetzt bei
  /// [DauerQuelle.historie] und [DauerQuelle.historieErsatz].
  final HistorienLeistung? historie;

  /// Erläuterung für die Notizen des Auftrags, z.B. Auflage + Durchlauf.
  final String hinweise;
}

/// Rechnet die Dauer eines Abteilungsblocks — aufeinanderfolgende Schritte
/// derselben Abteilung, jeder mit seiner Eingangsmenge. Dieselbe Regel
/// gilt beim Einplanen ([berechneSchrittPlan]) und beim Ändern der Menge
/// eines Auftrags ([AbteilungsDauerModell]):
///
/// - **Bratstraße:** Gibt es erfasste Produktionen mit Zeit, kommt die
///   Auflagezeit aus deren Ø, dazu die festen Durchlaufzeiten der
///   Stationen. Sonst zählt die längste Station laut Leistungsdaten.
/// - **Jede andere Abteilung:** die Leistungsdaten ihres ersten Schritts.
///   Fehlen sie, gilt der Ø der letzten Produktionen als Basis. Erst ohne
///   beides ist die Dauer ein Platzhalter.
AbteilungsDauer _blockDauer(
  List<({ProductStep step, double menge})> block,
  HistorienLeistung? historie,
) {
  final hinweise = StringBuffer();
  final menge = block.first.menge;
  double dauer;
  DauerQuelle quelle;

  if (block.first.step.abteilung == _kBratstrasseDbValue) {
    if (historie != null) {
      // Auflagezeit (erste bis letzte Auflage aufs Band) aus dem gemessenen
      // Durchsatz; fixe Durchlauf-/Verpackzeiten der Maschinen oben drauf.
      final auflage = historie.minutenFuer(menge);
      final durchlauf = block.fold<double>(
        0,
        (summe, b) => summe + (b.step.fixZeitMinuten ?? 0.0),
      );
      dauer = auflage + durchlauf;
      quelle = DauerQuelle.historie;
      if (durchlauf > 0) {
        hinweise.write(
          'Auflage ${auflage.round()} min (${historie.herkunft}) + '
          'Durchlauf/Verpacken ${durchlauf.round()} min. ',
        );
      } else {
        hinweise.write('Dauer aus ${historie.herkunft} (Auflagezeit). ');
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
      dauer = 0;
      var ohneDaten = true;
      for (final b in block) {
        final (d, platzhalter) = _skaliereDauer(b.step, b.menge);
        if (d > dauer) dauer = d;
        if (!platzhalter) ohneDaten = false;
      }
      // Hat keine Station Leistungsdaten, ist auch die Linie geraten —
      // der Planungsvorschlag lässt solche Artikel deshalb aus.
      quelle =
          ohneDaten ? DauerQuelle.platzhalter : DauerQuelle.leistungsdaten;
      if (block.length > 1) {
        hinweise.write('Durchlaufende Linie (längste Station zählt). ');
      }
      if (ohneDaten) {
        hinweise.write('Zeit ist Platzhalter (Leistungsdaten pflegen). ');
      }
    }
  } else {
    // Alle anderen Abteilungen: EINE Leistung je Abteilung. Maßgeblich
    // ist die Basis (Menge/Dauer) des ERSTEN Schritts der Abteilung —
    // genau die Werte, die der Leistungsdaten-Dialog pflegt. Die App
    // skaliert diese eine Referenz auf die Blockmenge hoch, statt die
    // Einzelschritte zu skalieren und zu addieren (das führte bei
    // mehrschrittigen Abteilungen wie Wolf+Kutter zu falschen Zeiten).
    final erster = block.first.step;
    final (d, platzhalter) = _skaliereDauer(erster, menge);
    if (!platzhalter) {
      dauer = d;
      quelle = DauerQuelle.leistungsdaten;
    } else if (historie != null) {
      // Keine Leistungsdaten: Die letzten Produktionen des Artikels
      // dienen als Basis — Ø Menge in Ø Zeit, genauso hochgerechnet.
      dauer = _skaliereDauer(erster, menge, ersatz: historie).$1;
      quelle = DauerQuelle.historieErsatz;
      hinweise.write(
        'Keine Leistungsdaten — Dauer aus ${historie.herkunft} '
        '(≈ ${_kgText(historie.kgProStunde)} kg/h). ',
      );
    } else {
      dauer = d;
      quelle = DauerQuelle.platzhalter;
      hinweise.write('Zeit ist Platzhalter (Leistungsdaten pflegen). ');
    }
  }

  // Sicherheitsnetz gegen unsinnige Werte.
  if (!dauer.isFinite || dauer < 0) dauer = 30.0;
  if (dauer > 60 * 24 * 7) dauer = 30.0;

  final ausHistorie = quelle == DauerQuelle.historie ||
      quelle == DauerQuelle.historieErsatz;
  return AbteilungsDauer(
    minuten: dauer,
    quelle: quelle,
    historie: ausHistorie ? historie : null,
    hinweise: hinweise.toString(),
  );
}

/// Lineare Dauer-Skalierung inkl. Chargen-Logik:
/// Fixzeit + Basisdauer × Menge ÷ Basismenge.
///
/// Die Basis sind die Leistungsdaten des Schritts. Fehlen sie und ist
/// [ersatz] gesetzt, dienen die letzten Produktionen als Basis.
/// Liefert (Dauer, istPlatzhalter).
(double, bool) _skaliereDauer(
  ProductStep step,
  double stepMenge, {
  HistorienLeistung? ersatz,
}) {
  final fixZeit = step.fixZeitMinuten ?? 0.0;
  var basisMenge = step.basisMengeKg;
  var basisDauer = step.basisDauerMinuten;
  if (basisDauer <= 0 && ersatz != null) {
    basisMenge = ersatz.mengeKg;
    basisDauer = ersatz.minuten;
  }

  double dauer;
  var platzhalter = false;

  if (basisMenge > 0 && basisDauer > 0) {
    dauer = fixZeit + basisDauer * (stepMenge / basisMenge);
  } else if (basisDauer > 0) {
    dauer = fixZeit + basisDauer;
  } else {
    dauer = fixZeit > 0 ? fixZeit : 30.0;
    platzhalter = true;
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
  }

  return (dauer, platzhalter);
}

/// Grundlage für die Dauer EINER Abteilung eines Artikels — einmal aus
/// der Datenbank geladen, danach für jede Menge ohne Datenbank rechenbar.
///
/// Für das Ändern eines Auftrags im Board: Ändert sich die Menge, rechnet
/// [dauerFuer] die Dauer nach genau denselben Regeln wie beim Einplanen
/// ([berechneSchrittPlan]) — mit den Leistungsdaten, ohne sie mit dem Ø
/// der letzten Produktionen, in der Bratstraße immer mit diesem.
class AbteilungsDauerModell {
  const AbteilungsDauerModell({
    required this.schritte,
    required this.historie,
    required this.schrittAusbeute,
  });

  /// Die Schritte der Abteilung — ein zusammenhängender Block in der
  /// Reihenfolge des Prozesses.
  final List<ProductStep> schritte;

  /// Ø der letzten Produktionen, null ohne Produktionen mit Zeit.
  final HistorienLeistung? historie;

  /// Rechnet der Artikel mit Ausbeuten an den einzelnen Schritten? Dann
  /// sinkt die Menge schon innerhalb der Abteilung von Schritt zu Schritt.
  final bool schrittAusbeute;

  ProductStep get ersterSchritt => schritte.first;

  bool get istBratstrasse => ersterSchritt.abteilung == _kBratstrasseDbValue;

  /// Summe der festen Zeiten der Schritte — in der Bratstraße die
  /// Durchlauf- und Verpackzeit, die zur Auflagezeit hinzukommt.
  double get festeZeitMinuten =>
      schritte.fold<double>(0, (s, x) => s + (x.fixZeitMinuten ?? 0.0));

  /// Dauer für [mengeKg] — die Eingangsmenge der Abteilung, wie sie am
  /// Auftrag steht.
  AbteilungsDauer dauerFuer(double mengeKg) {
    final block = <({ProductStep step, double menge})>[];
    var menge = mengeKg;
    for (final s in schritte) {
      block.add((step: s, menge: menge));
      final a = s.ausbeuteFaktor;
      if (schrittAusbeute && a != null && a > 0 && a < 1) menge *= a;
    }
    return _blockDauer(block, historie);
  }
}

/// Lädt das [AbteilungsDauerModell] für [abteilung] des Artikels. null,
/// wenn der Artikel dort keinen Schritt hat.
///
/// Kommt die Abteilung im Prozess mehrmals vor, gilt der Block mit der
/// Anlage [maschineId] des Auftrags, sonst der erste.
Future<AbteilungsDauerModell?> ladeAbteilungsDauerModell(
  AppDatabase db, {
  required String productId,
  required String abteilung,
  String? maschineId,
}) async {
  final steps = await _ladeSchritte(db, productId);

  // Zusammenhängende Blöcke dieser Abteilung — wie im Plan.
  final bloecke = <List<ProductStep>>[];
  var i = 0;
  while (i < steps.length) {
    if (steps[i].abteilung != abteilung) {
      i++;
      continue;
    }
    final block = <ProductStep>[];
    while (i < steps.length && steps[i].abteilung == abteilung) {
      block.add(steps[i]);
      i++;
    }
    bloecke.add(block);
  }
  if (bloecke.isEmpty) return null;
  final passend = maschineId == null
      ? null
      : bloecke
          .where((b) => b.any((s) => s.maschineId == maschineId))
          .firstOrNull;

  final ausbeute = await _ausbeuteFuer(db, productId, steps);
  final historie = await historienLeistung(db, productId);
  return AbteilungsDauerModell(
    schritte: passend ?? bloecke.first,
    historie: historie,
    schrittAusbeute: ausbeute.quelle == AusbeuteQuelle.schritte,
  );
}

// ---------------------------------------------------------------------------
// Leistung aus den letzten Produktionen
// ---------------------------------------------------------------------------

/// Aus so vielen der zuletzt erfassten Produktionen eines Artikels wird
/// seine Leistung gemittelt. Ältere zählen nicht mehr mit — Anlagen,
/// Rezepturen und Mannschaft ändern sich, und der Plan soll zeigen, was
/// heute zu schaffen ist.
const int kLetzteProduktionen = 10;

/// Was die zuletzt erfassten Produktionen eines Artikels im Schnitt
/// geschafft haben: Ø Rohware in Ø Produktionszeit.
///
/// Menge und Zeit werden getrennt gemittelt — wie bei den Leistungsdaten
/// („Menge X kg in Zeit Y"), und daraus rechnet die App jede andere Menge
/// genauso linear hoch. Die Bratstraße rechnet immer damit, weil dort die
/// Zeit gemessen wird; jede andere Abteilung nur, wenn für sie keine
/// Leistungsdaten gepflegt sind.
class HistorienLeistung {
  const HistorienLeistung({
    required this.mengeKg,
    required this.minuten,
    required this.anzahl,
  });

  /// Ø Rohware je Produktion in kg.
  final double mengeKg;

  /// Ø Produktionszeit je Produktion in Minuten.
  final double minuten;

  /// Aus so vielen Produktionen stammt der Schnitt.
  final int anzahl;

  /// Ø kg Rohware je Stunde.
  double get kgProStunde => mengeKg / minuten * 60;

  /// Minuten für [kg] — linear hochgerechnet.
  double minutenFuer(double kg) => minuten * kg / mengeKg;

  /// „Ø der letzten 6 Produktionen" bzw. „der letzten Produktion".
  String get herkunft => anzahl == 1
      ? 'der letzten Produktion'
      : 'Ø der letzten $anzahl Produktionen';

  /// „480 kg Rohware in 4:10 h (≈ 115 kg/h)".
  String get kennzahlen => '${_kgText(mengeKg)} kg Rohware in '
      '${Zeit.kurz(minuten)} (≈ ${_kgText(kgProStunde)} kg/h)';
}

/// Ø Menge und Ø Zeit der letzten [kLetzteProduktionen] erfassten
/// Produktionen des Artikels, bei denen beides bekannt ist. null, wenn
/// keine Produktion mit Menge und Zeit erfasst ist.
///
/// Die Zeit ist die erfasste Produktionszeit, sonst die Spanne zwischen
/// Start und Ende, sonst die Menge geteilt durch das erfasste kg/h.
Future<HistorienLeistung?> historienLeistung(
  AppDatabase db,
  String productId,
) async {
  final rows = await (db.select(db.productionHistory)
        ..where((h) => h.productId.equals(productId))
        ..where((h) => h.deletedAt.isNull())
        ..orderBy([
          (h) => OrderingTerm.desc(h.datum),
          (h) => OrderingTerm.desc(h.createdAt),
        ]))
      .get();

  var summeKg = 0.0;
  var summeMinuten = 0.0;
  var anzahl = 0;
  for (final h in rows) {
    final kg = h.kgRohware;
    if (kg == null || !kg.isFinite || kg <= 0) continue;
    final minuten = _produktionsMinuten(h, kg);
    if (minuten == null) continue;
    summeKg += kg;
    summeMinuten += minuten;
    anzahl++;
    if (anzahl >= kLetzteProduktionen) break;
  }
  if (anzahl == 0) return null;
  return HistorienLeistung(
    mengeKg: summeKg / anzahl,
    minuten: summeMinuten / anzahl,
    anzahl: anzahl,
  );
}

/// Produktionszeit einer erfassten Produktion in Minuten, oder null.
double? _produktionsMinuten(ProductionHistoryData h, double kg) {
  final erfasst = h.produktionszeitMinuten;
  if (erfasst != null && erfasst.isFinite && erfasst > 0) return erfasst;
  final ausUhrzeit = ProduktionErfassenService.produktionszeitMinuten(
    h.startzeit,
    h.endzeit,
  );
  if (ausUhrzeit != null && ausUhrzeit > 0) return ausUhrzeit;
  final kgh = h.kgProStundeRoh;
  if (kgh != null && kgh.isFinite && kgh > 0) return kg / kgh * 60;
  return null;
}

/// Kilogramm als ganze Zahl mit Tausenderpunkt: „12.857".
String _kgText(double kg) => kg.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );

/// Ø Ausbeute aus den erfassten Produktionen samt deren Anzahl. Es zählen
/// dieselben Werte wie bei [durchschnittsVerlust].
Future<({double? historie, int anzahl})> _historienAusbeute(
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
      .where((v) => v > 0 && v < 1)
      .toList();
  if (werte.isEmpty) return (historie: null, anzahl: 0);
  final verlust = werte.reduce((a, b) => a + b) / werte.length;
  return (historie: 1 - verlust, anzahl: werte.length);
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
///
/// Läuft komplett in EINER Transaktion: Eine Auftragskette ist nur als
/// Ganzes sinnvoll. Bräche das Anlegen in der Mitte ab, stünde eine halbe
/// Produktion in der Planung — Zerlegung und Wurstküche eingeplant,
/// Bratstraße und Verpackung fehlen. Schlimmer noch: Die Wurzel trägt
/// `bedarfId` und `fertigMengeKg`, der Bedarf gälte also als vollständig
/// eingeplant, obwohl die Kette hinten abbricht. Entweder alles oder nichts.
///
/// [auftragsBezuege]: Auftragszeilen aus dem Auftragsbestand, für die die
/// Produktion eingeplant wird. Sie stehen wie die Fertigmenge an der
/// Wurzel.
///
/// Gibt die ID der Wurzel zurück — etwa für das Datenblatt der neuen
/// Produktion. null, wenn es keine Schritte gab.
Future<String?> erstelleTasksAusPlan({
  required AppDatabase db,
  required String productId,
  required List<GeplanterSchritt> schritte,
  String? bedarfId,
  double? fertigMengeKg,
  List<AuftragsBezug> auftragsBezuege = const [],
}) async {
  const uuid = Uuid();
  final sortiert = [...schritte]
    ..sort((a, b) => a.reihenfolge.compareTo(b.reihenfolge));
  if (sortiert.isEmpty) return null;

  String? wurzelId;
  await db.transaction(() async {
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
              auftragsZeilen: Value(
                istWurzel ? AuftragsBezug.kodiere(auftragsBezuege) : null,
              ),
              geplanteDauerMinuten: s.dauerMinuten,
              geplanteMitarbeiter: s.mitarbeiter,
              parentTaskId: Value(previousTaskId),
              notizen: Value(s.notizen),
            ),
          );
      wurzelId ??= taskId;
      previousTaskId = taskId;
    }
  });
  return wurzelId;
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





