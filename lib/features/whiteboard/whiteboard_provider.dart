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
  /// Hinterlegte Leistungsdaten der Abteilung — „Menge X kg in Zeit Y".
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
// Erfasste Produktionen: Grundlage für Ausbeute und Leistung
// ---------------------------------------------------------------------------

/// Aus so vielen der zuletzt erfassten Produktionen eines Artikels werden
/// Ausbeute und Leistung gemittelt. Ältere zählen nicht mehr mit — Anlagen,
/// Rezepturen und Mannschaft ändern sich, und der Plan soll zeigen, was
/// heute zu schaffen ist.
const int kLetzteProduktionen = 10;

/// Die erfassten Produktionen eines Artikels, neueste zuerst.
Future<List<ProductionHistoryData>> _ladeProduktionen(
  AppDatabase db,
  String productId,
) {
  return (db.select(db.productionHistory)
        ..where((h) => h.productId.equals(productId))
        ..where((h) => h.deletedAt.isNull())
        ..orderBy([
          (h) => OrderingTerm.desc(h.datum),
          (h) => OrderingTerm.desc(h.createdAt),
        ]))
      .get();
}

/// „Ø der letzten 6 Produktionen" bzw. „der letzten Produktion".
String _letzteProduktionenText(int anzahl) => anzahl == 1
    ? 'der letzten Produktion'
    : 'Ø der letzten $anzahl Produktionen';

// ---------------------------------------------------------------------------
// Ausbeute: Rohware ↔ Fertigware
// ---------------------------------------------------------------------------

/// Woher die Ausbeute eines Artikels stammt.
///
/// Sie kommt aus den erfassten Produktionen: Ø der letzten
/// [kLetzteProduktionen], bei denen Roh- und Fertigware bekannt sind. Ist
/// noch keine solche erfasst, gilt die Eingabe im Planen-Dialog.
enum AusbeuteQuelle {
  /// Ø der zuletzt erfassten Produktionen.
  historie,

  /// Im Planen-Dialog von Hand eingetragen — gilt nur, solange keine
  /// Produktion mit Fertigware erfasst ist.
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
    this.historieAnzahl = 0,
  });

  /// Keine Ausbeute bekannt: Rohware = Fertigware.
  static const unbekannt = Ausbeute(faktor: 1, quelle: AusbeuteQuelle.keine);

  /// Fertigware je kg Rohware, 0 < faktor ≤ 1.
  final double faktor;

  final AusbeuteQuelle quelle;

  /// Aus wie vielen erfassten Produktionen [faktor] stammt — bei
  /// [AusbeuteQuelle.historie].
  final int historieAnzahl;

  bool get bekannt => quelle != AusbeuteQuelle.keine;

  double rohAusFertig(double fertigKg) => fertigKg / faktor;

  double fertigAusRoh(double rohKg) => rohKg * faktor;
}

/// Verlustanteil einer erfassten Produktion (0…1): der gespeicherte, sonst
/// aus Roh- und Fertigware. null, wenn er sich nicht ergibt oder nicht
/// plausibel ist — negativer oder voller Verlust ist ein Erfassungsfehler
/// und würde den Schnitt verzerren.
double? _verlust(ProductionHistoryData h) {
  var v = h.verlustAnteil;
  final roh = h.kgRohware;
  final fertig = h.kgFertigware;
  if (v == null && roh != null && roh > 0 && fertig != null) {
    v = 1 - fertig / roh;
  }
  if (v == null || !v.isFinite || v <= 0 || v >= 1) return null;
  return v;
}

/// Ø Ausbeute der letzten [kLetzteProduktionen] Produktionen, für die sich
/// ein Verlust ergibt — aus [neuesteZuerst]. null ohne solche.
({double faktor, int anzahl})? ausbeuteAusProduktionen(
  List<ProductionHistoryData> neuesteZuerst,
) {
  var summe = 0.0;
  var anzahl = 0;
  for (final h in neuesteZuerst) {
    final v = _verlust(h);
    if (v == null) continue;
    summe += v;
    anzahl++;
    if (anzahl >= kLetzteProduktionen) break;
  }
  if (anzahl == 0) return null;
  return (faktor: 1 - summe / anzahl, anzahl: anzahl);
}

/// Ermittelt die Ausbeute eines Artikels nach denselben Regeln wie
/// [berechneSchrittPlan]. [ersatz] (0 < x < 1) gilt nur, solange keine
/// Produktion mit Roh- und Fertigware erfasst ist.
Future<Ausbeute> ermittleAusbeute(
  AppDatabase db,
  String productId, {
  double? ersatz,
}) async {
  return _ausbeuteAus(await _ladeProduktionen(db, productId), ersatz: ersatz);
}

Ausbeute _ausbeuteAus(
  List<ProductionHistoryData> neuesteZuerst, {
  double? ersatz,
}) {
  final erfasst = ausbeuteAusProduktionen(neuesteZuerst);
  if (erfasst != null) {
    return Ausbeute(
      faktor: erfasst.faktor,
      quelle: AusbeuteQuelle.historie,
      historieAnzahl: erfasst.anzahl,
    );
  }
  if (ersatz != null && ersatz > 0 && ersatz < 1) {
    return Ausbeute(faktor: ersatz, quelle: AusbeuteQuelle.eingabe);
  }
  return Ausbeute.unbekannt;
}

Future<List<ProductStep>> _ladeSchritte(AppDatabase db, String productId) {
  return (db.select(db.productSteps)
        ..where((s) => s.productId.equals(productId))
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
      .get();
}

// ---------------------------------------------------------------------------
// Leistung: hinterlegt je Abteilung oder gemessen in den Produktionen
// ---------------------------------------------------------------------------

/// Von Hand hinterlegte Leistung einer Abteilung bei einem Artikel:
/// „Menge X kg in Zeit Y". Daraus rechnet die App jede andere Menge
/// linear hoch.
class Leistungsdaten {
  const Leistungsdaten({
    required this.mengeKg,
    required this.minuten,
    required this.stepId,
  });

  final double mengeKg;
  final double minuten;

  /// Der Schritt, an dem die Werte gespeichert sind.
  final String stepId;

  double get kgProStunde => mengeKg / minuten * 60;

  /// Minuten für [kg] — linear hochgerechnet.
  double minutenFuer(double kg) => minuten * kg / mengeKg;
}

/// Die hinterlegten Leistungsdaten einer Abteilung: die des ersten
/// Schritts in [schritteDerAbteilung], der Menge UND Zeit trägt. null,
/// wenn keiner.
///
/// Bewusst „der erste mit Werten" und nicht „der erste": Zieht man eine
/// andere Anlage der Abteilung nach vorn, bleiben die Leistungsdaten
/// trotzdem gültig — früher waren sie dann scheinbar verschwunden.
Leistungsdaten? leistungsdatenVon(Iterable<ProductStep> schritteDerAbteilung) {
  for (final s in schritteDerAbteilung) {
    if (s.basisMengeKg > 0 && s.basisDauerMinuten > 0) {
      return Leistungsdaten(
        mengeKg: s.basisMengeKg,
        minuten: s.basisDauerMinuten,
        stepId: s.id,
      );
    }
  }
  return null;
}

/// Was die zuletzt erfassten Produktionen eines Artikels im Schnitt
/// geschafft haben: Ø Rohware in Ø Produktionszeit.
///
/// Menge und Zeit werden getrennt gemittelt — wie bei den Leistungsdaten
/// („Menge X kg in Zeit Y"), und daraus rechnet die App jede andere Menge
/// genauso linear hoch.
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
  String get herkunft => _letzteProduktionenText(anzahl);

  /// „480 kg Rohware in 4:10 h (≈ 115 kg/h)".
  String get kennzahlen => '${_kgText(mengeKg)} kg Rohware in '
      '${Zeit.kurz(minuten)} (≈ ${_kgText(kgProStunde)} kg/h)';
}

/// Ø Menge und Ø Zeit der letzten [kLetzteProduktionen] Produktionen aus
/// [neuesteZuerst], bei denen beides bekannt ist. null ohne solche.
///
/// Die Zeit ist die erfasste Produktionszeit, sonst die Spanne zwischen
/// Start und Ende, sonst die Menge geteilt durch das erfasste kg/h.
HistorienLeistung? leistungAusProduktionen(
  List<ProductionHistoryData> neuesteZuerst,
) {
  var summeKg = 0.0;
  var summeMinuten = 0.0;
  var anzahl = 0;
  for (final h in neuesteZuerst) {
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

/// Leistung aus den erfassten Produktionen des Artikels — siehe
/// [leistungAusProduktionen].
Future<HistorienLeistung?> historienLeistung(
  AppDatabase db,
  String productId,
) async {
  return leistungAusProduktionen(await _ladeProduktionen(db, productId));
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

// ---------------------------------------------------------------------------
// Schritt-Plan
// ---------------------------------------------------------------------------

/// Berechnet aus Produkt + gewünschter **Fertigmenge** den Schritt-Plan:
/// je Abteilung Eingangsmenge (rückwärts über die Ausbeute), Dauer und
/// Personen. Alle Schritte starten auf [startTag]; die Tageszuordnung wird
/// anschließend im Dialog angepasst.
///
/// Die Dauer je Abteilung regelt [_blockDauer]: hinterlegte Leistungsdaten
/// der Abteilung oder der Ø der letzten erfassten Produktionen.
///
/// [mengeKg] ist IMMER Fertigware. Wer von einer Rohwarenmenge ausgeht,
/// rechnet sie vorher mit [ermittleAusbeute] um — sonst wird der Verlust
/// ein zweites Mal aufgeschlagen, und der Plan ist um genau diesen Faktor
/// zu groß. [ausbeuteErsatz] gilt nur für Artikel ohne erfasste Ausbeute
/// (siehe [AusbeuteQuelle.eingabe]).
Future<GeplanterPlan> berechneSchrittPlan({
  required AppDatabase db,
  required String productId,
  required double mengeKg,
  required DateTime startTag,
  double? ausbeuteErsatz,
}) async {
  final steps = await _ladeSchritte(db, productId);
  final produktionen = await _ladeProduktionen(db, productId);
  final ausbeute = _ausbeuteAus(produktionen, ersatz: ausbeuteErsatz);

  if (steps.isEmpty) {
    return GeplanterPlan(
      rohwareKg: mengeKg,
      fertigwareKg: mengeKg,
      ausbeute: ausbeute,
      schritte: const [],
    );
  }

  // Eingangsmengen. Ohne Ausbeute wäre die Rohwarenmenge gleich der
  // Fertigmenge — der Bratverlust fiele unter den Tisch, und eine
  // Bestellung nach diesen Zahlen käme zu knapp.
  //
  // Der Verlust entsteht beim Garen. Alles bis einschließlich der
  // Bratstraße arbeitet deshalb mit der Rohmenge, alles danach
  // (Verpackung, Wiegen) mit der Fertigmenge. Gibt es keine Bratstraße,
  // gilt die Rohmenge für die ganze Kette.
  final inputMengen = List<double>.filled(steps.length, mengeKg);
  if (ausbeute.bekannt) {
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
  final historie = leistungAusProduktionen(produktionen);

  final tagNorm = DateTime(startTag.year, startTag.month, startTag.day);

  // Aufeinanderfolgende Schritte derselben Abteilung zu EINEM Block bündeln
  // (z.B. Bratstraße = Verbufa + Bratstraße + Dampftunnel → ein Eintrag).
  // Innerhalb eines Blocks ist die Eingangsmenge überall dieselbe: Die
  // Grenze Roh/Fertig liegt immer hinter dem letzten Bratstraßen-Schritt.
  final result = <GeplanterSchritt>[];
  var i = 0;
  while (i < steps.length) {
    final abt = steps[i].abteilung;
    final blockMenge = inputMengen[i];
    final block = <ProductStep>[];
    while (i < steps.length && steps[i].abteilung == abt) {
      block.add(steps[i]);
      i++;
    }

    final labels =
        block.map(_schrittBezeichnung).where((l) => l.isNotEmpty).toList();
    final dauer = _blockDauer(block, blockMenge, historie);

    final notizen = StringBuffer();
    if (labels.length > 1) {
      notizen.write('Maschinen/Schritte: ${labels.join(' · ')}. ');
    }
    notizen.write(dauer.hinweise);

    final mitarbeiter = block
        .map((s) => s.basisMitarbeiter)
        .fold<int>(1, (m, v) => v > m ? v : m);

    result.add(
      GeplanterSchritt(
        stepId: block.first.id,
        reihenfolge: block.first.reihenfolge,
        abteilungDbValue: abt,
        // Anlage aus dem ersten Schritt des Blocks, der eine hat.
        maschineId: block
            .map((s) => s.maschineId)
            .firstWhere((m) => m != null, orElse: () => null),
        prozessschritt: labels.isEmpty ? null : labels.join(' · '),
        mengeKg: blockMenge,
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

  /// Erläuterung für die Notizen des Auftrags.
  final String hinweise;
}

/// Platzhalter-Dauer, wenn es weder Leistungsdaten noch erfasste
/// Produktionen mit Zeit gibt.
const double kPlatzhalterMinuten = 30;

/// Dauer eines Abteilungsblocks — aufeinanderfolgende Schritte derselben
/// Abteilung — für [menge] kg Eingangsmenge. Dieselbe Regel gilt beim
/// Einplanen ([berechneSchrittPlan]) und beim Ändern der Menge eines
/// Auftrags ([AbteilungsDauerModell]):
///
/// - **Bratstraße:** der Ø der letzten erfassten Produktionen — dort wird
///   die Zeit gemessen. Ohne sie die hinterlegten Leistungsdaten.
/// - **Jede andere Abteilung:** ihre hinterlegten Leistungsdaten. Ohne sie
///   der Ø der letzten Produktionen.
/// - Ohne beides ist die Dauer ein Platzhalter.
///
/// Beide Quellen sind „Menge X in Zeit Y" und werden linear auf [menge]
/// hochgerechnet. Feste Zeiten je Anlage gibt es nicht mehr: Wer an einer
/// Anlage steht und wie lange sie läuft, ist von Artikel zu Artikel zu
/// verschieden, um es an der Anlage festzumachen.
AbteilungsDauer _blockDauer(
  List<ProductStep> block,
  double menge,
  HistorienLeistung? historie,
) {
  final istBratstrasse = block.first.abteilung == _kBratstrasseDbValue;
  final leistung = leistungsdatenVon(block);

  AbteilungsDauer ausHistorie(HistorienLeistung h, DauerQuelle quelle) {
    final vorsatz =
        quelle == DauerQuelle.historieErsatz ? 'Keine Leistungsdaten — ' : '';
    return AbteilungsDauer(
      minuten: h.minutenFuer(menge),
      quelle: quelle,
      historie: h,
      hinweise: '${vorsatz}Dauer aus ${h.herkunft} '
          '(≈ ${_kgText(h.kgProStunde)} kg/h). ',
    );
  }

  final AbteilungsDauer ergebnis;
  if (istBratstrasse && historie != null) {
    ergebnis = ausHistorie(historie, DauerQuelle.historie);
  } else if (leistung != null) {
    ergebnis = AbteilungsDauer(
      minuten: leistung.minutenFuer(menge),
      quelle: DauerQuelle.leistungsdaten,
    );
  } else if (historie != null) {
    ergebnis = ausHistorie(historie, DauerQuelle.historieErsatz);
  } else {
    ergebnis = const AbteilungsDauer(
      minuten: kPlatzhalterMinuten,
      quelle: DauerQuelle.platzhalter,
      hinweise: 'Zeit ist Platzhalter (Leistungsdaten pflegen). ',
    );
  }

  // Sicherheitsnetz gegen unsinnige Werte.
  final m = ergebnis.minuten;
  if (!m.isFinite || m < 0 || m > 60 * 24 * 7) {
    return AbteilungsDauer(
      minuten: kPlatzhalterMinuten,
      quelle: ergebnis.quelle,
      historie: ergebnis.historie,
      hinweise: ergebnis.hinweise,
    );
  }
  return ergebnis;
}

/// Grundlage für die Dauer EINER Abteilung eines Artikels — einmal aus
/// der Datenbank geladen, danach für jede Menge ohne Datenbank rechenbar.
///
/// Für das Ändern eines Auftrags im Board: Ändert sich die Menge, rechnet
/// [dauerFuer] die Dauer nach genau denselben Regeln wie beim Einplanen
/// ([berechneSchrittPlan]).
class AbteilungsDauerModell {
  const AbteilungsDauerModell({
    required this.schritte,
    required this.historie,
  });

  /// Die Schritte der Abteilung — ein zusammenhängender Block in der
  /// Reihenfolge des Prozesses.
  final List<ProductStep> schritte;

  /// Ø der letzten Produktionen, null ohne Produktionen mit Zeit.
  final HistorienLeistung? historie;

  ProductStep get ersterSchritt => schritte.first;

  bool get istBratstrasse => ersterSchritt.abteilung == _kBratstrasseDbValue;

  /// Die hinterlegten Leistungsdaten der Abteilung, null ohne.
  Leistungsdaten? get leistungsdaten => leistungsdatenVon(schritte);

  /// Dauer für [mengeKg] — die Eingangsmenge der Abteilung, wie sie am
  /// Auftrag steht.
  AbteilungsDauer dauerFuer(double mengeKg) =>
      _blockDauer(schritte, mengeKg, historie);
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

  return AbteilungsDauerModell(
    schritte: passend ?? bloecke.first,
    historie: await historienLeistung(db, productId),
  );
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





