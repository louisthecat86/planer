import 'package:drift/drift.dart';

import '../database/database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Produktionen der App
// ═══════════════════════════════════════════════════════════════════════════

/// Wie eine Produktion der App zum Stand des Auftragsbestands steht.
///
/// Der Auftragsbestand zeigt das Lager zum Zeitpunkt des Berichts. Was die
/// App produziert oder eingeplant hat, kommt obendrauf — aber nur, solange
/// es in diesem Lager noch nicht steckt. Sonst zählte dieselbe Ware
/// doppelt, und es würde zu wenig produziert.
enum ZugangsArt {
  /// Der letzte Schritt der Kette ist heute oder später — die Ware
  /// entsteht erst noch.
  eingeplant,

  /// Fertig geworden am Tag des Berichts oder danach. Im Lager des
  /// Berichts steckt sie noch nicht, sie zählt also dazu.
  nachBericht,

  /// Vor dem Tag des Berichts fertig geworden. Die App geht davon aus,
  /// dass Navision sie bis zum Bericht gebucht hat — sie steckt dann im
  /// Lager und zählt nicht ein zweites Mal. Steht nur zur Information da.
  imLager,
}

/// Eine Produktion der App — eine Auftragskette auf dem Board — für einen
/// Artikel.
class ProduktionsZugang {
  const ProduktionsZugang({
    required this.kettenId,
    required this.productId,
    required this.fertigAm,
    required this.art,
    this.kg,
    this.erfasst = false,
  });

  /// ID der Wurzel der Kette (erster Schritt).
  final String kettenId;
  final String productId;

  /// Tag des letzten Schritts der Kette. Ab diesem Tag ist die Ware da.
  final DateTime fertigAm;

  final ZugangsArt art;

  /// Fertigware in kg: aus der Produktionserfassung, wenn die Produktion
  /// schon erfasst ist, sonst die geplante Fertigmenge.
  ///
  /// null, wenn die Kette ohne Fertigmenge geplant wurde (Eingabe in
  /// Rohware). Dann kennt die App die Menge nicht und rechnet sie nicht
  /// mit — lieber sichtbar „unbekannt" als still geraten.
  final double? kg;

  /// Die Menge stammt aus der Produktionserfassung, nicht aus dem Plan.
  final bool erfasst;

  /// Zählt gegen die Aufträge.
  bool get zaehlt => art != ZugangsArt.imLager && (kg ?? 0) > 0;
}

/// Lädt die Produktionen der App, gruppiert nach Artikelnummer.
///
/// Eine Produktion ist eine Auftragskette auf dem Board: ein Schritt je
/// Abteilung, verbunden über `parentTaskId`. Die Fertigmenge steht an der
/// Wurzel, fertig ist die Ware am Tag des letzten Schritts.
///
/// [berichtTag] ist der Tag, an dem Navision den Auftragsbestand erzeugt
/// hat. Er entscheidet, ob eine fertige Produktion im Lager des Berichts
/// schon enthalten ist (siehe [ZugangsArt]). Vor dem Bericht fertig
/// gewordene Produktionen werden [infoTageVorBericht] Tage zurück
/// mitgeliefert — nur zur Anzeige.
Future<Map<String, List<ProduktionsZugang>>> ladeProduktionsZugaenge(
  AppDatabase db, {
  required DateTime heute,
  required DateTime berichtTag,
  int infoTageVorBericht = 7,
}) async {
  final heuteTag = _tag(heute);
  final bericht = _tag(berichtTag);
  final frueher = bericht.isBefore(heuteTag) ? bericht : heuteTag;
  // Eine Kette reicht selten über mehr als ein paar Tage. Mit 30 Tagen
  // Vorlauf ist auch die Wurzel einer langen Kette sicher dabei.
  final fensterStart = DateTime(frueher.year, frueher.month, frueher.day - 30);
  final infoAb = DateTime(
    bericht.year,
    bericht.month,
    bericht.day - infoTageVorBericht,
  );

  // Bewusst AUCH gelöschte und stornierte Aufträge: Sie werden gebraucht,
  // um die Wurzel einer Kette zu finden. Löscht jemand im Board nur einen
  // einzelnen Schritt — etwa die Zerlegung, weil das Fleisch schon zerlegt
  // kommt —, läuft der Rest der Kette weiter, und die Fertigmenge steht
  // nach wie vor an der gelöschten Wurzel.
  final tasks = await (db.select(db.productionTasks)
        ..where((t) => t.datum.isBiggerOrEqualValue(fensterStart)))
      .get();
  if (tasks.isEmpty) return const {};

  final jeId = {for (final t in tasks) t.id: t};
  final wurzelJeId = <String, String>{};

  String wurzelVon(ProductionTask start) {
    var aktuell = start;
    final weg = <String>{aktuell.id};
    while (true) {
      final bekannt = wurzelJeId[aktuell.id];
      if (bekannt != null) {
        for (final id in weg) {
          wurzelJeId[id] = bekannt;
        }
        return bekannt;
      }
      final elternId = aktuell.parentTaskId;
      final eltern = elternId == null ? null : jeId[elternId];
      // Kein Elternteil (mehr) im Fenster, oder ein Kreis in den Daten:
      // Dann ist der aktuelle Auftrag die Wurzel.
      if (eltern == null || !weg.add(eltern.id)) break;
      aktuell = eltern;
    }
    for (final id in weg) {
      wurzelJeId[id] = aktuell.id;
    }
    return aktuell.id;
  }

  // Eine Kette zählt, solange mindestens ein Schritt lebt. Fertig ist sie
  // am Tag ihres letzten lebenden Schritts.
  final letzterTag = <String, DateTime>{};
  for (final t in tasks) {
    if (t.deletedAt != null || t.status == 'storniert') continue;
    final wurzel = wurzelVon(t);
    final tag = _tag(t.datum);
    final bisher = letzterTag[wurzel];
    if (bisher == null || tag.isAfter(bisher)) letzterTag[wurzel] = tag;
  }
  if (letzterTag.isEmpty) return const {};

  // Produktionserfassung: Sie hängt am Artikel und am Tag der Wurzel —
  // genau so ordnet auch der Erfassungs-Bildschirm zu.
  String schluessel(String productId, DateTime tag) =>
      '$productId|${tag.year}-${tag.month}-${tag.day}';

  final historie = await (db.select(db.productionHistory)
        ..where((h) => h.deletedAt.isNull())
        ..where((h) => h.datum.isBiggerOrEqualValue(fensterStart)))
      .get();
  final erfasstKg = <String, double>{};
  for (final h in historie) {
    final kg = h.kgFertigware;
    if (kg == null || kg <= 0) continue;
    final k = schluessel(h.productId, _tag(h.datum));
    erfasstKg[k] = (erfasstKg[k] ?? 0) + kg;
  }
  // Laufen zwei Produktionen desselben Artikels am selben Tag an, lässt
  // sich die erfasste Menge keiner der beiden eindeutig zuordnen. Dann
  // gilt für beide der Plan.
  final kettenJeSchluessel = <String, int>{};
  for (final wurzel in letzterTag.keys) {
    final w = jeId[wurzel]!;
    final k = schluessel(w.productId, _tag(w.datum));
    kettenJeSchluessel[k] = (kettenJeSchluessel[k] ?? 0) + 1;
  }

  // Alle Artikel, auch gelöschte: Das Board zeigt Aufträge gelöschter
  // Artikel weiter an, also zählen sie hier ebenfalls.
  final produkte = await db.select(db.products).get();
  final nummerJeId = {for (final p in produkte) p.id: p.artikelnummer};

  final ergebnis = <String, List<ProduktionsZugang>>{};
  for (final e in letzterTag.entries) {
    final wurzel = jeId[e.key]!;
    final fertigAm = e.value;

    final ZugangsArt art;
    if (!fertigAm.isBefore(heuteTag)) {
      art = ZugangsArt.eingeplant;
    } else if (!fertigAm.isBefore(bericht)) {
      art = ZugangsArt.nachBericht;
    } else if (!fertigAm.isBefore(infoAb)) {
      art = ZugangsArt.imLager;
    } else {
      continue;
    }

    final nummer = nummerJeId[wurzel.productId];
    if (nummer == null || nummer.isEmpty) continue;

    final k = schluessel(wurzel.productId, _tag(wurzel.datum));
    final erfasst = kettenJeSchluessel[k] == 1 ? erfasstKg[k] : null;
    final geplant = wurzel.fertigMengeKg;

    ergebnis.putIfAbsent(nummer, () => []).add(
          ProduktionsZugang(
            kettenId: wurzel.id,
            productId: wurzel.productId,
            fertigAm: fertigAm,
            art: art,
            kg: erfasst ?? (geplant != null && geplant > 0 ? geplant : null),
            erfasst: erfasst != null,
          ),
        );
  }
  for (final liste in ergebnis.values) {
    liste.sort((a, b) => a.fertigAm.compareTo(b.fertigAm));
  }
  return ergebnis;
}

// ═══════════════════════════════════════════════════════════════════════════
// Deckung
// ═══════════════════════════════════════════════════════════════════════════

/// Unter 5 g ist Rundung, kein Bedarf.
const double _schwelle = 0.005;

/// Rechengenauigkeit, damit Schleifen nicht an Resten wie 1e-13 hängen.
const double _epsilon = 1e-9;

/// Aufträge eines Artikels an einem Warenausgangstag.
class TagesDeckung {
  const TagesDeckung({
    required this.tag,
    required this.positionen,
    required this.kg,
    required this.ausLagerKg,
    this.ausPlanungKg = 0,
    this.knappKg = 0,
    this.zuSpaetKg = 0,
    this.zuSpaetBis,
  });

  final DateTime tag;
  final List<AuftragsPosition> positionen;

  /// Summe der Aufträge an diesem Tag.
  final double kg;

  /// Davon aus dem Lager gedeckt.
  final double ausLagerKg;

  /// Davon aus Produktionen der App, die rechtzeitig fertig werden.
  final double ausPlanungKg;

  /// Teil von [ausPlanungKg], der erst am Versandtag selbst fertig wird.
  /// Geht, ist aber knapp.
  final double knappKg;

  /// Aus Produktionen, die erst NACH dem Versandtag fertig werden. Die
  /// Menge ist eingeplant, der Tag passt nicht.
  final double zuSpaetKg;

  /// Wann die zu spät eingeplante Ware da ist.
  final DateTime? zuSpaetBis;

  /// Weder im Lager noch eingeplant — das ist noch einzuplanen.
  double get fehltKg {
    final rest = kg - ausLagerKg - ausPlanungKg - zuSpaetKg;
    return rest > 0 ? rest : 0.0;
  }

  /// Nicht rechtzeitig gedeckt: fehlt oder kommt zu spät.
  bool get offen => fehltKg + zuSpaetKg >= _schwelle;
}

/// Wie weit Lager und Produktion eines Artikels die Aufträge tragen.
class ArtikelDeckung {
  const ArtikelDeckung({
    required this.lagerKg,
    required this.tage,
    this.zugangKg = 0,
    this.ueberschussKg = 0,
  });

  final double lagerKg;

  /// Nach Warenausgang sortiert, der früheste zuerst.
  final List<TagesDeckung> tage;

  /// Summe der Produktionen, die mitzählen.
  final double zugangKg;

  /// Davon über die Aufträge im Bericht hinaus — etwa fürs Lager oder für
  /// Aufträge nach dem Berichtszeitraum.
  final double ueberschussKg;

  double get auftragKg => _summe((t) => t.kg);
  double get ausLagerKg => _summe((t) => t.ausLagerKg);
  double get ausPlanungKg => _summe((t) => t.ausPlanungKg);
  double get knappKg => _summe((t) => t.knappKg);
  double get zuSpaetKg => _summe((t) => t.zuSpaetKg);

  /// Noch einzuplanen: weder im Lager noch in einer Produktion der App.
  double get fehltKg => _summe((t) => t.fehltKg);

  double _summe(double Function(TagesDeckung t) wert) =>
      tage.fold<double>(0, (s, t) => s + wert(t));

  /// Alles rechtzeitig gedeckt — aus dem Lager oder aus der Planung.
  bool get gedeckt => fehltKg < _schwelle && zuSpaetKg < _schwelle;

  /// Das Lager allein trägt alle Aufträge.
  bool get lagerReicht => gedeckt && ausPlanungKg < _schwelle;

  /// Erster Warenausgang, der nicht rechtzeitig gedeckt ist.
  DateTime? get ersterEngpass => _ersterTag((t) => t.offen);

  /// Erster Warenausgang, für den noch etwas eingeplant werden muss — das
  /// ist der Termin für die fehlende Menge.
  DateTime? get ersterFehltag => _ersterTag((t) => t.fehltKg >= _schwelle);

  /// Erster Warenausgang, dessen Ware zu spät fertig wird.
  DateTime? get ersterZuSpaet => _ersterTag((t) => t.zuSpaetKg >= _schwelle);

  DateTime? _ersterTag(bool Function(TagesDeckung t) passt) {
    for (final t in tage) {
      if (passt(t)) return t.tag;
    }
    return null;
  }
}

/// Teilt Lager und Produktion den Aufträgen in der Reihenfolge ihres
/// Warenausgangs zu.
///
/// 1. **Lager zuerst**, der früheste Auftrag bekommt zuerst — die
///    Reihenfolge, in der die Ware auch das Haus verlässt.
/// 2. **Dann die Produktionen**, die bis zum Versandtag fertig sind. Wird
///    eine erst am Versandtag selbst fertig, zählt sie, gilt aber als
///    knapp.
/// 3. **Was dann noch offen ist**, bekommt die Produktionen, die erst
///    nach dem Versandtag fertig werden: Die Menge ist eingeplant, nur
///    zu spät. Den späteren Aufträgen zuerst — so bleibt die fehlende
///    Menge beim frühesten Auftrag stehen, und dessen Tag ist der Termin
///    für alles, was noch einzuplanen ist.
///
/// Es zählen nur Produktionen mit [ProduktionsZugang.zaehlt].
ArtikelDeckung berechneDeckung({
  required double lagerKg,
  required List<AuftragsPosition> positionen,
  List<ProduktionsZugang> zugaenge = const [],
}) {
  final jeTag = <DateTime, List<AuftragsPosition>>{};
  for (final p in positionen) {
    jeTag.putIfAbsent(_tag(p.warenausgang), () => []).add(p);
  }
  final tage = jeTag.keys.toList()..sort();

  final zu = [
    for (final z in zugaenge)
      if (z.zaehlt) (tag: _tag(z.fertigAm), kg: z.kg ?? 0.0),
  ]..sort((a, b) => a.tag.compareTo(b.tag));
  final rest = [for (final z in zu) z.kg];
  final zugangKg = rest.fold<double>(0, (s, kg) => s + kg);

  var lagerRest = lagerKg > 0 ? lagerKg : 0.0;
  final summe = <double>[];
  final ausLager = <double>[];
  final ausPlanung = <double>[];
  final knapp = <double>[];
  final offen = <double>[];

  // Schritt 1 und 2: Lager, dann rechtzeitige Produktion.
  for (final tag in tage) {
    final kg = jeTag[tag]!.fold<double>(0, (s, p) => s + p.kg);
    var bedarf = kg;

    final l = bedarf < lagerRest ? bedarf : lagerRest;
    lagerRest -= l;
    bedarf -= l;

    var p = 0.0;
    var k = 0.0;
    for (var i = 0; i < zu.length && bedarf > _epsilon; i++) {
      // Nach Fertigtag sortiert: Ab hier ist alles zu spät für diesen Tag.
      if (zu[i].tag.isAfter(tag)) break;
      if (rest[i] <= _epsilon) continue;
      final nimm = bedarf < rest[i] ? bedarf : rest[i];
      rest[i] -= nimm;
      bedarf -= nimm;
      p += nimm;
      if (zu[i].tag.isAtSameMomentAs(tag)) k += nimm;
    }

    summe.add(kg);
    ausLager.add(l);
    ausPlanung.add(p);
    knapp.add(k);
    offen.add(bedarf > _epsilon ? bedarf : 0.0);
  }

  // Schritt 3: Was übrig ist, kommt nach allen noch offenen Tagen — sonst
  // hätte Schritt 2 es genommen. Späteste Tage zuerst, jeweils aus der
  // spätesten Produktion: Der frühere Auftrag bekommt die frühere Ware.
  final zuSpaet = List<double>.filled(tage.length, 0.0);
  final zuSpaetBis = List<DateTime?>.filled(tage.length, null);
  var j = zu.length - 1;
  for (var t = tage.length - 1; t >= 0 && j >= 0; t--) {
    var bedarf = offen[t];
    while (bedarf > _epsilon && j >= 0) {
      if (rest[j] <= _epsilon) {
        j--;
        continue;
      }
      final nimm = bedarf < rest[j] ? bedarf : rest[j];
      rest[j] -= nimm;
      bedarf -= nimm;
      zuSpaet[t] += nimm;
      final bis = zuSpaetBis[t];
      if (bis == null || zu[j].tag.isAfter(bis)) zuSpaetBis[t] = zu[j].tag;
    }
  }
  final ueberschuss =
      rest.fold<double>(0, (s, r) => s + (r > _epsilon ? r : 0.0));

  return ArtikelDeckung(
    lagerKg: lagerKg,
    zugangKg: zugangKg,
    ueberschussKg: ueberschuss,
    tage: [
      for (var i = 0; i < tage.length; i++)
        TagesDeckung(
          tag: tage[i],
          positionen: jeTag[tage[i]]!,
          kg: summe[i],
          ausLagerKg: ausLager[i],
          ausPlanungKg: ausPlanung[i],
          knappKg: knapp[i],
          zuSpaetKg: zuSpaet[i],
          zuSpaetBis: zuSpaetBis[i],
        ),
    ],
  );
}

DateTime _tag(DateTime d) => DateTime(d.year, d.month, d.day);
