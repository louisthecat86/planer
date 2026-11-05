import 'package:drift/drift.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/services/entwicklung_vorgabe.dart';
import '../../core/utils/format.dart';
import '../entwicklung/freigabe/fleischanteil_vorgabe.dart';
import 'whiteboard_provider.dart';

// Die Mengen einer Produktion im Board: Rohware, Fertigware und
// Fleischeinwaage — und womit jeder ihrer Aufträge arbeitet.
//
// Eine Produktion ist eine Kette von Aufträgen, je Abteilung einer, auf
// mehrere Tage verteilt auch mehrere. Bis einschließlich der Bratstraße
// arbeiten die Schritte mit der Rohware, danach mit der Fertigware — so
// legt [berechneSchrittPlan] sie an. Ohne Bratstraße im Prozess arbeitet
// die ganze Kette mit der Rohware.
//
// Fertigware und Fleischeinwaage stehen an der Wurzel der Kette. Die
// Rohware ist die Menge der ersten Abteilung, die mit ihr arbeitet.

/// Womit ein Auftrag arbeitet.
enum MengenBezug { rohware, fertigware }

double? _positiv(double? wert) =>
    wert != null && wert.isFinite && wert > 0 ? wert : null;

/// Eine Produktion im Board: die Kette der Aufträge, zu der ein Auftrag
/// gehört — mit der Stufe und dem Bezug jedes Auftrags.
class ProduktionsKette {
  ProduktionsKette._({
    required this.start,
    required this.wurzel,
    required this.schritte,
    required this.hatBratstrasse,
    required Map<String, int> stufen,
    required Map<int, MengenBezug> bezuege,
  })  : _stufen = stufen,
        _bezuege = bezuege;

  /// Die Kette um den Auftrag [startId], aus allen Aufträgen seines
  /// Artikels [alle] — auch gelöschten und stornierten: Sie verbinden die
  /// Kette, und an der Wurzel stehen Fertigware und Fleischeinwaage, auch
  /// wenn ihr Schritt aus dem Board entfernt wurde. [abteilungen] sind die
  /// Abteilungen des Prozesses in ihrer Reihenfolge (siehe
  /// [prozessAbteilungen]).
  ///
  /// null, wenn es den Auftrag nicht gibt.
  static ProduktionsKette? aus(
    String startId,
    List<ProductionTask> alle,
    List<String> abteilungen,
  ) {
    final jeId = {for (final t in alle) t.id: t};
    final start = jeId[startId];
    if (start == null) return null;

    var wurzel = start;
    final besucht = <String>{wurzel.id};
    while (true) {
      final eltern = jeId[wurzel.parentTaskId];
      if (eltern == null || !besucht.add(eltern.id)) break;
      wurzel = eltern;
    }

    // Je Abteilung eine Stufe mehr. Ein Kind derselben Abteilung ist ein
    // auf Tage verteiltes Teil und teilt die Stufe.
    final kinder = <String, List<ProductionTask>>{};
    for (final t in alle) {
      final p = t.parentTaskId;
      if (p != null) kinder.putIfAbsent(p, () => []).add(t);
    }
    final stufen = <String, int>{wurzel.id: 0};
    final abteilungJeStufe = <int, String>{0: wurzel.abteilung};
    final offen = [wurzel];
    while (offen.isNotEmpty) {
      final t = offen.removeLast();
      final s = stufen[t.id]!;
      for (final k in kinder[t.id] ?? const <ProductionTask>[]) {
        if (stufen.containsKey(k.id)) continue;
        final ks = k.abteilung == t.abteilung ? s : s + 1;
        stufen[k.id] = ks;
        abteilungJeStufe.putIfAbsent(ks, () => k.abteilung);
        offen.add(k);
      }
    }

    // Bezug je Stufe: über die Abteilungen des Prozesses. Auch eine beim
    // Planen abgewählte Bratstraße zählt — die Schritte danach arbeiten
    // trotzdem mit der Fertigware.
    final brat = Abteilung.bratstrasse.dbValue;
    final letzteBrat = abteilungen.lastIndexOf(brat);
    final bezuege = <int, MengenBezug>{};
    var naechster = 0;
    var vorher = MengenBezug.rohware;
    var vorherBrat = false;
    for (final s in abteilungJeStufe.keys.toList()..sort()) {
      final abteilung = abteilungJeStufe[s]!;
      final i = abteilungen.indexOf(abteilung, naechster);
      final MengenBezug bezug;
      if (i >= 0) {
        naechster = i + 1;
        bezug = letzteBrat < 0 || i <= letzteBrat
            ? MengenBezug.rohware
            : MengenBezug.fertigware;
      } else {
        // Den Schritt kennt der Prozess (nicht mehr): wie der davor —
        // nach der Bratstraße mit der Fertigware.
        bezug = vorherBrat ? MengenBezug.fertigware : vorher;
      }
      bezuege[s] = bezug;
      vorher = bezug;
      vorherBrat = abteilung == brat;
    }

    final schritte = [
      for (final t in alle)
        if (stufen.containsKey(t.id) &&
            t.deletedAt == null &&
            t.status != 'storniert')
          t,
    ]..sort((a, b) {
        final d = stufen[a.id]!.compareTo(stufen[b.id]!);
        return d != 0 ? d : a.datum.compareTo(b.datum);
      });

    return ProduktionsKette._(
      start: start,
      wurzel: wurzel,
      schritte: schritte,
      hatBratstrasse: letzteBrat >= 0,
      stufen: stufen,
      bezuege: bezuege,
    );
  }

  /// Der Auftrag, um den die Kette gebaut ist — etwa der im Fenster.
  final ProductionTask start;

  /// Der erste Auftrag der Kette. Er trägt Fertigware, Fleischeinwaage und
  /// Bedarf — auch dann, wenn er selbst aus dem Board gelöscht ist.
  final ProductionTask wurzel;

  /// Die Aufträge im Board — ohne gelöschte und stornierte —, nach Stufe
  /// und Tag.
  final List<ProductionTask> schritte;

  /// Ob der Prozess des Artikels eine Bratstraße hat.
  final bool hatBratstrasse;

  final Map<String, int> _stufen;
  final Map<int, MengenBezug> _bezuege;

  /// 0 für die erste Abteilung, je weitere eins mehr.
  int stufeVon(ProductionTask t) => _stufen[t.id] ?? 0;

  /// Womit [t] arbeitet.
  MengenBezug bezugVon(ProductionTask t) =>
      _bezuege[stufeVon(t)] ?? MengenBezug.rohware;

  /// Die Aufträge auf der Stufe von [t] — mehr als einer, wenn sie auf
  /// mehrere Tage verteilt ist.
  List<ProductionTask> teileVon(ProductionTask t) {
    final s = stufeVon(t);
    return [
      for (final x in schritte)
        if (stufeVon(x) == s) x,
    ];
  }

  /// Die Menge der ganzen Stufe von [t].
  double stufenMenge(ProductionTask t) =>
      teileVon(t).fold<double>(0, (s, x) => s + x.mengeKg);

  /// Die Rohware der Produktion: die Menge der Stufe von [start], wenn sie
  /// mit Rohware arbeitet, sonst die der ersten Stufe im Board, die es tut.
  /// null, wenn keine im Board steht.
  ///
  /// Von [start] aus, weil ältere Planungen auseinanderlaufen konnten:
  /// Früher änderte das Fenster nur seinen eigenen Auftrag. Wer die
  /// Bratstraße öffnet, sieht deren Menge — und Speichern bringt die ganze
  /// Kette wieder auf eine.
  double? get rohKg {
    if (bezugVon(start) == MengenBezug.rohware &&
        schritte.any((t) => t.id == start.id)) {
      return _positiv(stufenMenge(start));
    }
    for (final t in schritte) {
      if (bezugVon(t) == MengenBezug.rohware) return _positiv(stufenMenge(t));
    }
    return null;
  }

  /// Die geplante Fertigware — null, wenn die Produktion ohne sie geplant
  /// wurde (in Rohware, ohne bekannte Ausbeute).
  double? get fertigKg => _positiv(wurzel.fertigMengeKg);

  /// Die geplante Fleischeinwaage — null, wenn keine geplant ist.
  double? get fleischKg => _positiv(wurzel.fleischMengeKg);

  /// Die Menge von [t], wenn die Produktion [rohKg] Rohware und
  /// [fertigKg] Fertigware bekommt. Auf Tage verteilte Teile behalten ihr
  /// Verhältnis. Ohne [fertigKg] gehen die Fertigware-Schritte im
  /// Verhältnis der Rohware mit; ohne [rohKg] bleiben die Rohware-Schritte.
  double mengeFuer(
    ProductionTask t, {
    required double? rohKg,
    required double? fertigKg,
  }) {
    final summe = stufenMenge(t);
    final double? ziel;
    if (bezugVon(t) == MengenBezug.rohware) {
      ziel = rohKg;
    } else {
      final bisher = this.rohKg;
      ziel = fertigKg ??
          (rohKg != null && bisher != null ? summe * rohKg / bisher : null);
    }
    if (ziel == null || summe <= 0) return t.mengeKg;
    return t.mengeKg * ziel / summe;
  }

  /// Die neuen Mengen der Aufträge, die sich ändern, je ID — nach
  /// [mengeFuer].
  Map<String, double> neueMengen({
    required double? rohKg,
    required double? fertigKg,
  }) {
    final ergebnis = <String, double>{};
    for (final t in schritte) {
      final neu = mengeFuer(t, rohKg: rohKg, fertigKg: fertigKg);
      if ((neu - t.mengeKg).abs() > 1e-6) ergebnis[t.id] = neu;
    }
    return ergebnis;
  }
}

/// Die Abteilungen des Prozesses von [productId] in ihrer Reihenfolge —
/// aufeinanderfolgende Schritte derselben Abteilung als eine, wie im Plan.
Future<List<String>> prozessAbteilungen(
  AppDatabase db,
  String productId,
) async {
  final schritte = await (db.select(db.productSteps)
        ..where((s) => s.productId.equals(productId))
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
      .get();
  final abteilungen = <String>[];
  for (final s in schritte) {
    if (abteilungen.isEmpty || abteilungen.last != s.abteilung) {
      abteilungen.add(s.abteilung);
    }
  }
  return abteilungen;
}

// ═══════════════════════════════════════════════════════════════════════════
// Verhältnisse zur Rohware
// ═══════════════════════════════════════════════════════════════════════════

/// Woher ein Verhältnis stammt.
enum VerhaeltnisQuelle {
  /// Aus den Mengen, mit denen die Produktion geplant ist.
  geplant,

  /// Ø der zuletzt erfassten Produktionen.
  produktionen,

  /// Aus der freigegebenen Rezeptur der Produktentwicklung.
  rezeptur,

  /// Im Fenster eingetragen.
  eingabe,
}

/// Ein Verhältnis zur Rohware — die Ausbeute (Fertigware je kg Rohware)
/// oder der Fleischanteil (Fleisch je kg Rohware) — und woher es stammt.
class Verhaeltnis {
  const Verhaeltnis(this.wert, this.quelle, {this.anzahl = 0});

  /// Je kg Rohware, also 0,85 für 85 %.
  final double wert;
  final VerhaeltnisQuelle quelle;

  /// Aus wie vielen Produktionen [wert] stammt — bei
  /// [VerhaeltnisQuelle.produktionen].
  final int anzahl;

  /// „wie geplant", „Ø der letzten 9 Produktionen" …
  String get herkunft => switch (quelle) {
        VerhaeltnisQuelle.geplant => 'wie geplant',
        VerhaeltnisQuelle.produktionen => anzahl == 1
            ? 'aus der letzten Produktion'
            : 'Ø der letzten $anzahl Produktionen',
        VerhaeltnisQuelle.rezeptur => 'aus der Rezeptur',
        VerhaeltnisQuelle.eingabe => 'von Hand',
      };
}

/// Ø Fleischanteil der letzten [kLetzteProduktionen] Produktionen mit
/// Rohware und Fleischeinwaage — aus [neuesteZuerst]. null ohne solche.
/// Mehr Fleisch als Rohware ist ein Erfassungsfehler und zählt nicht.
({double anteil, int anzahl})? fleischanteilAusProduktionen(
  List<ProductionHistoryData> neuesteZuerst,
) {
  var summe = 0.0;
  var anzahl = 0;
  for (final h in neuesteZuerst) {
    final roh = h.kgRohware;
    final fleisch = h.kgFleischeinwaage;
    if (roh == null || fleisch == null || roh <= 0 || fleisch <= 0) continue;
    if (fleisch > roh) continue;
    summe += fleisch / roh;
    anzahl++;
    if (anzahl >= kLetzteProduktionen) break;
  }
  if (anzahl == 0) return null;
  return (anteil: summe / anzahl, anzahl: anzahl);
}

/// Der Fleischanteil eines Artikels, solange keiner geplant ist: Ø der
/// letzten Produktionen mit Fleischeinwaage, sonst aus der freigegebenen
/// Rezeptur. null, wenn es keins von beidem gibt.
Future<Verhaeltnis?> fleischanteilFuer(
  AppDatabase db,
  String productId,
) async {
  final produktionen = await (db.select(db.productionHistory)
        ..where((h) => h.productId.equals(productId))
        ..where((h) => h.deletedAt.isNull())
        ..orderBy([
          (h) => OrderingTerm.desc(h.datum),
          (h) => OrderingTerm.desc(h.createdAt),
        ]))
      .get();
  final erfasst = fleischanteilAusProduktionen(produktionen);
  if (erfasst != null) {
    return Verhaeltnis(
      erfasst.anteil,
      VerhaeltnisQuelle.produktionen,
      anzahl: erfasst.anzahl,
    );
  }
  final rezeptur = await fleischanteilAusEntwicklung(db, productId);
  return rezeptur == null
      ? null
      : Verhaeltnis(rezeptur, VerhaeltnisQuelle.rezeptur);
}

/// Die Ausbeute eines Artikels, solange die Produktion keine geplante
/// Fertigware hat: wie bei der Planung aus den erfassten Produktionen,
/// sonst aus dem Verlust der freigegebenen Rezeptur.
Future<Verhaeltnis?> ausbeuteFuer(AppDatabase db, String productId) async {
  final verlust = await verlustVorgabeAusEntwicklung(db, productId);
  final a = await ermittleAusbeute(
    db,
    productId,
    ersatz: verlust == null ? null : 1 - verlust / 100,
  );
  if (!a.bekannt) return null;
  return a.quelle == AusbeuteQuelle.historie
      ? Verhaeltnis(
          a.faktor,
          VerhaeltnisQuelle.produktionen,
          anzahl: a.historieAnzahl,
        )
      : Verhaeltnis(a.faktor, VerhaeltnisQuelle.rezeptur);
}

// ═══════════════════════════════════════════════════════════════════════════
// Laden und Speichern
// ═══════════════════════════════════════════════════════════════════════════

/// Alles, womit das Fenster eines Auftrags die Mengen seiner Produktion
/// rechnet.
class ProduktionsMengen {
  const ProduktionsMengen({
    required this.kette,
    this.ausbeute,
    this.fleischanteil,
  });

  final ProduktionsKette kette;

  /// Fertigware je kg Rohware — null, wenn sie unbekannt ist.
  final Verhaeltnis? ausbeute;

  /// Fleisch je kg Rohware — null, wenn er unbekannt ist.
  final Verhaeltnis? fleischanteil;
}

/// Lädt die Produktion des Auftrags [taskId]: ihre Kette und die
/// Verhältnisse zur Rohware — wie geplant, sonst aus den erfassten
/// Produktionen oder der Rezeptur. null, wenn es den Auftrag nicht gibt.
Future<ProduktionsMengen?> ladeProduktionsMengen(
  AppDatabase db,
  String taskId,
) async {
  final start = await (db.select(db.productionTasks)
        ..where((t) => t.id.equals(taskId)))
      .getSingleOrNull();
  if (start == null) return null;
  final productId = start.productId;
  final alle = await (db.select(db.productionTasks)
        ..where((t) => t.productId.equals(productId)))
      .get();
  final kette = ProduktionsKette.aus(
    taskId,
    alle,
    await prozessAbteilungen(db, productId),
  );
  if (kette == null) return null;

  final roh = kette.rohKg;
  final fertig = kette.fertigKg;
  final fleisch = kette.fleischKg;
  return ProduktionsMengen(
    kette: kette,
    ausbeute: roh != null && fertig != null
        ? Verhaeltnis(fertig / roh, VerhaeltnisQuelle.geplant)
        : await ausbeuteFuer(db, productId),
    fleischanteil: roh != null && fleisch != null
        ? Verhaeltnis(fleisch / roh, VerhaeltnisQuelle.geplant)
        : await fleischanteilFuer(db, productId),
  );
}

bool _gleich(double? a, double? b) =>
    a == null || b == null ? a == b : (a - b).abs() < 1e-6;

/// Speichert neue Mengen der Produktion von [kette] — alles oder nichts:
/// an allen Aufträgen die Menge nach [ProduktionsKette.mengeFuer], bei
/// denen, deren Menge sich ändert, die Dauer neu hochgerechnet; an der
/// Wurzel Fertigware und Fleischeinwaage.
///
/// [rohKg]: die Rohware; null lässt die Rohware-Schritte, wie sie sind.
/// [fertigKg]: die Fertigware; null lässt sie an der Wurzel stehen.
/// [fleischKg]: die geplante Fleischeinwaage; null heißt keine.
///
/// [auftragId] und [auftrag]: was am Auftrag des Fensters sonst noch zu
/// schreiben ist — Dauer, Personen, Start, Notiz. Seine Dauer gilt dann
/// statt der hochgerechneten.
Future<void> produktionsMengenSpeichern(
  AppDatabase db,
  ProduktionsKette kette, {
  required double? rohKg,
  required double? fertigKg,
  required double? fleischKg,
  String? auftragId,
  ProductionTasksCompanion auftrag = const ProductionTasksCompanion(),
}) async {
  final mengen = kette.neueMengen(rohKg: rohKg, fertigKg: fertigKg);

  // Neue Dauer für jeden Auftrag mit neuer Menge — nach denselben Regeln
  // wie beim Einplanen. Lässt sie sich nicht hochrechnen, bleibt sie.
  final dauern = <String, double>{};
  final modelle = <String, AbteilungsDauerModell?>{};
  for (final t in kette.schritte) {
    final menge = mengen[t.id];
    if (menge == null) continue;
    if (t.id == auftragId && auftrag.geplanteDauerMinuten.present) continue;
    final schluessel = '${t.abteilung}|${t.maschineId ?? ''}';
    if (!modelle.containsKey(schluessel)) {
      modelle[schluessel] = await ladeAbteilungsDauerModell(
        db,
        productId: t.productId,
        abteilung: t.abteilung,
        maschineId: t.maschineId,
      );
    }
    final d = modelle[schluessel]?.dauerFuer(menge);
    if (d == null ||
        d.quelle == DauerQuelle.platzhalter ||
        !d.minuten.isFinite ||
        d.minuten <= 0) {
      continue;
    }
    dauern[t.id] = d.minuten.roundToDouble();
  }

  final w = kette.wurzel;
  final neueFertig = fertigKg != null && !_gleich(fertigKg, w.fertigMengeKg);
  final neuesFleisch = !_gleich(fleischKg, w.fleischMengeKg);
  final jetzt = DateTime.now();

  await db.transaction(() async {
    final ids = <String>{
      ...mengen.keys,
      ...dauern.keys,
      if (auftragId != null) auftragId,
      if (neueFertig || neuesFleisch) w.id,
    };
    for (final id in ids) {
      final fuerAuftrag = id == auftragId;
      final menge = mengen[id];
      final dauer = dauern[id];
      final c = ProductionTasksCompanion(
        mengeKg: menge == null ? const Value.absent() : Value(menge),
        geplanteDauerMinuten:
            fuerAuftrag && auftrag.geplanteDauerMinuten.present
                ? auftrag.geplanteDauerMinuten
                : (dauer == null ? const Value.absent() : Value(dauer)),
        geplanteMitarbeiter:
            fuerAuftrag ? auftrag.geplanteMitarbeiter : const Value.absent(),
        startZeit: fuerAuftrag ? auftrag.startZeit : const Value.absent(),
        notizen: fuerAuftrag ? auftrag.notizen : const Value.absent(),
        fertigMengeKg:
            id == w.id && neueFertig ? Value(fertigKg) : const Value.absent(),
        fleischMengeKg: id == w.id && neuesFleisch
            ? Value(fleischKg)
            : const Value.absent(),
        updatedAt: Value(jetzt),
      );
      await (db.update(db.productionTasks)..where((t) => t.id.equals(id)))
          .write(c);
    }
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Die Felder im Fenster
// ═══════════════════════════════════════════════════════════════════════════

/// Die gekoppelten Felder im Fenster eines Auftrags — Rohware, Fertigware
/// und Fleischeinwaage der Produktion, dazu Verlust und Fleischanteil —
/// als Text, wie er in den Feldern steht. Ändert sich eins, rechnen die
/// anderen mit:
///
/// * Rohware → Fertigware über den Verlust, Fleischeinwaage über den
///   Fleischanteil.
/// * Fertigware oder Fleischeinwaage → die Rohware zurück, daraus das
///   jeweils andere.
/// * Verlust oder Fleischanteil → Fertigware bzw. Fleischeinwaage; die
///   Rohware bleibt.
///
/// Ist ein Verhältnis unbekannt, legt die eingetragene Menge es fest:
/// Fertigware ohne Verlust ergibt den Verlust, und solange das gilt,
/// ändert die Fertigware den Verlust statt der Rohware. Ebenso
/// Fleischeinwaage und Fleischanteil.
///
/// Ein Feld, das noch steht wie geladen, liefert genau die geplante Menge,
/// nicht die auf 0,1 kg gerundete im Feld — sonst verschöbe Speichern die
/// Mengen und Dauern der Kette um Rundungsreste.
class MengenEingabe {
  MengenEingabe(this.mengen) {
    final k = mengen.kette;
    final a = mengen.ausbeute?.wert;
    final f = mengen.fleischanteil?.wert;
    var rohKg = k.rohKg;
    var fertigKg = k.fertigKg;
    if (rohKg == null && fertigKg != null && a != null && a > 0) {
      rohKg = fertigKg / a;
    }
    if (fertigKg == null && rohKg != null && a != null) fertigKg = rohKg * a;
    final fleischKg =
        k.fleischKg ?? (rohKg != null && f != null ? rohKg * f : null);
    _ausbeute = a;
    _verlustHerkunft = mengen.ausbeute?.herkunft;
    _fleischanteil = f;
    _anteilHerkunft = mengen.fleischanteil?.herkunft;
    roh = _rohAnfang = kgText(rohKg);
    fertig = _fertigAnfang = kgText(fertigKg);
    fleisch = _fleischAnfang = kgText(fleischKg);
    _rohGeladen = _nurPositiv(rohKg);
    _fertigGeladen = _nurPositiv(fertigKg);
    _fleischGeladen = _nurPositiv(fleischKg);
    verlust = prozentText(a == null ? null : 1 - a);
    anteil = prozentText(f);
  }

  final ProduktionsMengen mengen;

  // Die Mengen, wie sie geladen wurden — als Text im Feld und genau.
  late final String _rohAnfang;
  late final String _fertigAnfang;
  late final String _fleischAnfang;
  late final double? _rohGeladen;
  late final double? _fertigGeladen;
  late final double? _fleischGeladen;

  String roh = '';
  String fertig = '';
  String fleisch = '';
  String verlust = '';
  String anteil = '';

  double? _ausbeute;
  String? _verlustHerkunft;
  bool _ausbeuteAusFertig = false;
  double? _fleischanteil;
  String? _anteilHerkunft;
  bool _anteilAusFleisch = false;

  /// Woher der Verlust stammt — null, wenn er unbekannt ist.
  String? get verlustHerkunft => _verlustHerkunft;

  /// Woher der Fleischanteil stammt — null, wenn er unbekannt ist.
  String? get anteilHerkunft => _anteilHerkunft;

  static const String _vonHand = 'von Hand';

  /// Eine Menge fürs Feld: „1200", „960,5" — leer für keine.
  static String kgText(double? kg) =>
      kg == null || !kg.isFinite ? '' : Format.eingabe(kg, nachkomma: 1);

  /// [anteil] (0,2) als Prozent fürs Feld: „20".
  static String prozentText(double? anteil) =>
      anteil == null ? '' : Format.eingabe(anteil * 100, nachkomma: 1);

  static double? _wert(String text) {
    final v = Format.lies(text);
    return v != null && v.isFinite ? v : null;
  }

  static double? _positiv(String text) => _nurPositiv(_wert(text));

  static double? _nurPositiv(double? v) =>
      v != null && v.isFinite && v > 0 ? v : null;

  /// Die Rohware — null, wenn das Feld leer oder ungültig ist.
  double? get rohKg => roh == _rohAnfang ? _rohGeladen : _positiv(roh);
  double? get fertigKg =>
      fertig == _fertigAnfang ? _fertigGeladen : _positiv(fertig);
  double? get fleischKg =>
      fleisch == _fleischAnfang ? _fleischGeladen : _positiv(fleisch);

  /// Ob eine der drei Mengen anders ist als geladen. Sonst gibt es an der
  /// Produktion nichts zu speichern.
  bool get geaendert =>
      roh != _rohAnfang || fertig != _fertigAnfang || fleisch != _fleischAnfang;

  /// Die Menge von [auftrag] nach den Feldern.
  double auftragsMenge(ProductionTask auftrag) => mengen.kette.mengeFuer(
        auftrag,
        rohKg: roh == _rohAnfang ? _rohGeladen : _wert(roh),
        fertigKg: fertig == _fertigAnfang ? _fertigGeladen : _wert(fertig),
      );

  void setzeRoh(String text) {
    roh = text;
    final r = _positiv(text);
    if (r == null) return;
    final a = _ausbeute;
    if (a != null) fertig = kgText(r * a);
    final f = _fleischanteil;
    if (f != null) fleisch = kgText(r * f);
  }

  void setzeFertig(String text) {
    fertig = text;
    final fe = _positiv(text);
    if (fe == null) {
      // Hatte die Fertigware den Verlust festgelegt, ist er wieder offen.
      if (text.trim().isEmpty && _ausbeuteAusFertig) {
        _ausbeute = null;
        _verlustHerkunft = null;
        verlust = '';
      }
      return;
    }
    final a = _ausbeute;
    if (a != null && a > 0 && !_ausbeuteAusFertig) {
      final r = fe / a;
      roh = kgText(r);
      final f = _fleischanteil;
      if (f != null) fleisch = kgText(r * f);
      return;
    }
    // Ohne Verhältnis legt die Fertigware den Verlust fest.
    final r = rohKg;
    if (r == null) return;
    _ausbeuteAusFertig = true;
    _ausbeute = fe / r;
    _verlustHerkunft = _vonHand;
    verlust = prozentText(1 - fe / r);
  }

  void setzeFleisch(String text) {
    fleisch = text;
    final fl = _positiv(text);
    if (fl == null) {
      // Hatte die Fleischeinwaage den Anteil festgelegt, ist er wieder offen.
      if (text.trim().isEmpty && _anteilAusFleisch) {
        _fleischanteil = null;
        _anteilHerkunft = null;
        anteil = '';
      }
      return;
    }
    final f = _fleischanteil;
    if (f != null && f > 0 && !_anteilAusFleisch) {
      final r = fl / f;
      roh = kgText(r);
      final a = _ausbeute;
      if (a != null) fertig = kgText(r * a);
      return;
    }
    // Ohne Verhältnis legt die Fleischeinwaage den Anteil fest.
    final r = rohKg;
    if (r == null) return;
    _anteilAusFleisch = true;
    _fleischanteil = fl / r;
    _anteilHerkunft = _vonHand;
    anteil = prozentText(fl / r);
  }

  void setzeVerlust(String text) {
    verlust = text;
    _ausbeuteAusFertig = false;
    if (text.trim().isEmpty) {
      _ausbeute = null;
      _verlustHerkunft = null;
      return;
    }
    final p = _wert(text);
    if (p == null || p < 0 || p >= 100) return;
    final a = 1 - p / 100;
    _ausbeute = a;
    _verlustHerkunft = _vonHand;
    final r = rohKg;
    if (r != null) fertig = kgText(r * a);
  }

  void setzeAnteil(String text) {
    anteil = text;
    _anteilAusFleisch = false;
    if (text.trim().isEmpty) {
      _fleischanteil = null;
      _anteilHerkunft = null;
      return;
    }
    final p = _wert(text);
    if (p == null || p <= 0 || p > 100) return;
    final f = p / 100;
    _fleischanteil = f;
    _anteilHerkunft = _vonHand;
    final r = rohKg;
    if (r != null) fleisch = kgText(r * f);
  }

  // Prüfungen — null, wenn alles passt.

  String? get rohFehler {
    if (roh.trim().isEmpty) {
      // Pflicht, sobald die Produktion Schritte mit Rohware im Board hat.
      return mengen.kette.rohKg == null ? null : 'Bitte die Rohware eintragen.';
    }
    return rohKg == null ? 'Keine gültige Menge.' : null;
  }

  String? get fertigFehler {
    if (fertig.trim().isEmpty) return null;
    final fe = fertigKg;
    if (fe == null) return 'Keine gültige Menge.';
    final r = rohKg;
    if (r != null && fe > r + 1e-6) {
      return 'Mehr Fertigware als Rohware — Prozessschritte verlieren nur '
          'Gewicht.';
    }
    return null;
  }

  String? get fleischFehler {
    if (fleisch.trim().isEmpty) return null;
    final fl = _wert(fleisch);
    if (fl == null || fl < 0) return 'Keine gültige Menge.';
    final r = rohKg;
    if (r != null && fl > r + 1e-6) {
      return 'Mehr Fleisch als Rohware — die Rohware zählt alles mit.';
    }
    return null;
  }

  String? get verlustFehler {
    if (verlust.trim().isEmpty) return null;
    final p = _wert(verlust);
    return p == null || p < 0 || p >= 100 ? '0 bis unter 100 %' : null;
  }

  String? get anteilFehler {
    if (anteil.trim().isEmpty) return null;
    final p = _wert(anteil);
    return p == null || p <= 0 || p > 100 ? 'Über 0 bis 100 %' : null;
  }

  /// Ob sich die Mengen so speichern lassen.
  bool get gueltig =>
      rohFehler == null &&
      fertigFehler == null &&
      fleischFehler == null &&
      verlustFehler == null &&
      anteilFehler == null;
}
