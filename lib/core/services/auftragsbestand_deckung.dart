import 'dart:convert';
import 'dart:math' show min;

import 'package:drift/drift.dart';

import '../database/database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Bezug: Produktion ↔ Auftragszeile
// ═══════════════════════════════════════════════════════════════════════════

/// Schlüssel einer Auftragszeile innerhalb eines Artikels: Beleg und
/// Warenausgang.
///
/// Die Zeilen-IDs des Auftragsbestands taugen dafür nicht — jeder Import
/// legt die Tabelle neu an und vergibt neue. Beleg und Tag bleiben über
/// Importe hinweg gleich. Verschiebt Navision den Warenausgang, ist die
/// Zeile für die App eine neue und wieder offen; die Produktion zählt dann
/// trotzdem weiter gegen den Artikel.
String auftragsZeilenSchluessel(String beleg, DateTime warenausgang) =>
    '${beleg.trim()}|${_datumText(warenausgang)}';

/// Eine Auftragszeile, für die eine Produktion eingeplant wurde.
///
/// Steht als JSON-Liste an der Wurzel der Kette
/// (`production_tasks.auftrags_zeilen`).
class AuftragsBezug {
  const AuftragsBezug({
    required this.beleg,
    required this.warenausgang,
    required this.kg,
    this.debitor = '',
  });

  /// Belegnummer des Verkaufsauftrags, z.B. „VA2608879".
  final String beleg;

  /// Warenausgang der Zeile (Tag, 00:00).
  final DateTime warenausgang;

  /// Menge, für die die Produktion eingeplant wurde, in kg.
  final double kg;

  /// Kunde — nur zur Anzeige.
  final String debitor;

  String get schluessel => auftragsZeilenSchluessel(beleg, warenausgang);

  Map<String, Object> toJson() => {
        'beleg': beleg,
        'wa': _datumText(warenausgang),
        'kg': kg,
        if (debitor.isNotEmpty) 'kunde': debitor,
      };

  /// Liest einen Eintrag. null bei allem, was nicht passt — eine kaputte
  /// Zeile soll die übrigen nicht mitreißen.
  static AuftragsBezug? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final beleg = json['beleg'];
    final wa = json['wa'];
    final kg = json['kg'];
    if (beleg is! String || wa is! String || kg is! num) return null;
    final tag = DateTime.tryParse(wa);
    if (tag == null) return null;
    final kunde = json['kunde'];
    return AuftragsBezug(
      beleg: beleg,
      warenausgang: DateTime(tag.year, tag.month, tag.day),
      kg: kg.toDouble(),
      debitor: kunde is String ? kunde : '',
    );
  }

  /// Für die Spalte an der Wurzel. null bei leerer Liste.
  static String? kodiere(List<AuftragsBezug> bezuege) => bezuege.isEmpty
      ? null
      : jsonEncode([for (final b in bezuege) b.toJson()]);

  /// Aus der Spalte an der Wurzel. Leer bei null oder unlesbarem Inhalt.
  static List<AuftragsBezug> dekodiere(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    final Object? daten;
    try {
      daten = jsonDecode(text);
    } on FormatException {
      return const [];
    }
    if (daten is! List<dynamic>) return const [];
    final liste = <AuftragsBezug>[];
    for (final e in daten) {
      final b = fromJson(e);
      if (b != null) liste.add(b);
    }
    return liste;
  }
}

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
    this.startAm,
    this.bezuege = const [],
  });

  /// ID der Wurzel der Kette (erster Schritt).
  final String kettenId;
  final String productId;

  /// Tag des letzten Schritts der Kette. Ab diesem Tag ist die Ware da.
  final DateTime fertigAm;

  /// Tag des ersten Schritts. Ohne Angabe gleich [fertigAm].
  final DateTime? startAm;

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

  /// Auftragszeilen, für die diese Produktion ausdrücklich eingeplant
  /// wurde. Leer bei allem, was ohne Auftragsbestand geplant wurde.
  final List<AuftragsBezug> bezuege;

  DateTime get beginn => startAm ?? fertigAm;

  /// Zählt gegen die Aufträge.
  bool get zaehlt => art != ZugangsArt.imLager && (kg ?? 0) > 0;
}

/// Lädt die Produktionen der App, gruppiert nach Artikelnummer.
///
/// Eine Produktion ist eine Auftragskette auf dem Board: ein Schritt je
/// Abteilung, verbunden über `parentTaskId`. Fertigmenge und Auftragsbezug
/// stehen an der Wurzel, fertig ist die Ware am Tag des letzten Schritts.
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
  // kommt —, läuft der Rest der Kette weiter, und Fertigmenge und
  // Auftragsbezug stehen nach wie vor an der gelöschten Wurzel.
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

  // Eine Kette zählt, solange mindestens ein Schritt lebt. Sie beginnt am
  // Tag ihres ersten und ist fertig am Tag ihres letzten lebenden Schritts.
  final ersterTag = <String, DateTime>{};
  final letzterTag = <String, DateTime>{};
  for (final t in tasks) {
    if (t.deletedAt != null || t.status == 'storniert') continue;
    final wurzel = wurzelVon(t);
    final tag = _tag(t.datum);
    final frueh = ersterTag[wurzel];
    if (frueh == null || tag.isBefore(frueh)) ersterTag[wurzel] = tag;
    final spaet = letzterTag[wurzel];
    if (spaet == null || tag.isAfter(spaet)) letzterTag[wurzel] = tag;
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
            startAm: ersterTag[e.key],
            art: art,
            kg: erfasst ?? (geplant != null && geplant > 0 ? geplant : null),
            erfasst: erfasst != null,
            bezuege: AuftragsBezug.dekodiere(wurzel.auftragsZeilen),
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

/// Deckung einer einzelnen Auftragszeile.
class ZeilenDeckung {
  const ZeilenDeckung({
    required this.position,
    required this.ausLagerKg,
    this.ausPlanungKg = 0,
    this.knappKg = 0,
    this.zuSpaetKg = 0,
    this.zuSpaetBis,
    this.eingeplantIn = const [],
  });

  final AuftragsPosition position;

  /// Aus dem Lager gedeckt.
  final double ausLagerKg;

  /// Aus Produktionen der App, die rechtzeitig fertig werden.
  final double ausPlanungKg;

  /// Teil von [ausPlanungKg], der erst am Versandtag selbst fertig wird.
  final double knappKg;

  /// Aus Produktionen, die erst NACH dem Versandtag fertig werden.
  final double zuSpaetKg;

  /// Wann die zu spät eingeplante Ware da ist.
  final DateTime? zuSpaetBis;

  /// Produktionen, die ausdrücklich für diese Zeile eingeplant wurden.
  final List<ProduktionsZugang> eingeplantIn;

  double get kg => position.kg;

  String get schluessel =>
      auftragsZeilenSchluessel(position.beleg, position.warenausgang);

  /// Weder im Lager noch eingeplant — das ist noch einzuplanen.
  double get fehltKg {
    final rest = kg - ausLagerKg - ausPlanungKg - zuSpaetKg;
    return rest > 0 ? rest : 0.0;
  }

  /// Ausdrücklich für diese Zeile eingeplant.
  bool get geplant => eingeplantIn.isNotEmpty;

  /// Nicht rechtzeitig gedeckt: fehlt oder kommt zu spät.
  bool get offen => fehltKg + zuSpaetKg >= _schwelle;
}

/// Aufträge eines Artikels an einem Warenausgangstag.
class TagesDeckung {
  const TagesDeckung({required this.tag, required this.zeilen});

  final DateTime tag;

  /// Die Auftragszeilen des Tages, nach Beleg sortiert.
  final List<ZeilenDeckung> zeilen;

  List<AuftragsPosition> get positionen => [for (final z in zeilen) z.position];

  double get kg => _summe((z) => z.kg);
  double get ausLagerKg => _summe((z) => z.ausLagerKg);
  double get ausPlanungKg => _summe((z) => z.ausPlanungKg);
  double get knappKg => _summe((z) => z.knappKg);
  double get zuSpaetKg => _summe((z) => z.zuSpaetKg);

  /// Weder im Lager noch eingeplant — das ist noch einzuplanen.
  double get fehltKg => _summe((z) => z.fehltKg);

  double _summe(double Function(ZeilenDeckung z) wert) =>
      zeilen.fold<double>(0, (s, z) => s + wert(z));

  /// Wann die zu spät eingeplante Ware da ist — der späteste Tag.
  DateTime? get zuSpaetBis {
    DateTime? bis;
    for (final z in zeilen) {
      final t = z.zuSpaetBis;
      if (t != null && (bis == null || t.isAfter(bis))) bis = t;
    }
    return bis;
  }

  /// Nicht rechtzeitig gedeckt: fehlt oder kommt zu spät.
  bool get offen => fehltKg + zuSpaetKg >= _schwelle;

  /// Für diesen Tag lässt sich noch etwas einplanen.
  bool get einplanbar => fehltKg >= _schwelle;

  /// Produktionen, die ausdrücklich für Zeilen dieses Tages eingeplant
  /// wurden — jede nur einmal.
  List<ProduktionsZugang> get eingeplantIn {
    final liste = <ProduktionsZugang>[];
    for (final z in zeilen) {
      for (final p in z.eingeplantIn) {
        if (!liste.contains(p)) liste.add(p);
      }
    }
    return liste;
  }
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

/// Teilt Lager und Produktion den Auftragszeilen in der Reihenfolge ihres
/// Warenausgangs zu.
///
/// 1. **Lager zuerst**, die früheste Zeile bekommt zuerst — die
///    Reihenfolge, in der die Ware auch das Haus verlässt.
/// 2. **Dann die ausdrücklich eingeplanten Zeilen**: Eine Produktion, die
///    für bestimmte Aufträge angelegt wurde (siehe [AuftragsBezug]),
///    gehört zuerst diesen Aufträgen — bis zu der Menge, für die sie dort
///    eingeplant wurde. Ohne diese Regel könnte die Rechnung sie einer
///    früheren, gar nicht gewählten Zeile geben, und die gewählte stünde
///    weiter als offen da.
/// 3. **Übrige Produktion**, die bis zum Versandtag fertig ist. Wird eine
///    erst am Versandtag selbst fertig, zählt sie, gilt aber als knapp.
/// 4. **Was dann noch offen ist**, bekommt die Produktion, die erst nach
///    dem Versandtag fertig wird: Die Menge ist eingeplant, nur zu spät.
///    Den späteren Zeilen zuerst — so bleibt die fehlende Menge bei der
///    frühesten Zeile stehen, und deren Tag ist der Termin für alles, was
///    noch einzuplanen ist.
///
/// Mengen zählen nur von Produktionen mit [ProduktionsZugang.zaehlt]. Die
/// Markierung „eingeplant für" bekommt eine Zeile aber von jeder
/// Produktion, die für sie angelegt wurde.
ArtikelDeckung berechneDeckung({
  required double lagerKg,
  required List<AuftragsPosition> positionen,
  List<ProduktionsZugang> zugaenge = const [],
}) {
  // Zeilen in Versandreihenfolge: Tag, dann Beleg.
  final zeilen = [...positionen]..sort((a, b) {
      final t = _tag(a.warenausgang).compareTo(_tag(b.warenausgang));
      if (t != 0) return t;
      final beleg = a.beleg.compareTo(b.beleg);
      return beleg != 0 ? beleg : a.id.compareTo(b.id);
    });
  final n = zeilen.length;
  final tagJe = [for (final p in zeilen) _tag(p.warenausgang)];
  final offen = [for (final p in zeilen) p.kg > 0 ? p.kg : 0.0];
  final ausLager = List<double>.filled(n, 0.0);
  final ausPlanung = List<double>.filled(n, 0.0);
  final knapp = List<double>.filled(n, 0.0);
  final zuSpaet = List<double>.filled(n, 0.0);
  final zuSpaetBis = List<DateTime?>.filled(n, null);
  final eingeplantIn =
      List<List<ProduktionsZugang>>.generate(n, (_) => <ProduktionsZugang>[]);

  // 1. Lager.
  var lagerRest = lagerKg > 0 ? lagerKg : 0.0;
  for (var i = 0; i < n && lagerRest > _epsilon; i++) {
    final l = min(offen[i], lagerRest);
    ausLager[i] = l;
    offen[i] -= l;
    lagerRest -= l;
  }

  // Produktionen nach Fertigtag. Was nicht zählt, hat Rest 0 — es kann
  // Zeilen markieren, aber nichts decken.
  final zu = [...zugaenge]..sort((a, b) => a.fertigAm.compareTo(b.fertigAm));
  final fertigJe = [for (final z in zu) _tag(z.fertigAm)];
  final rest = [for (final z in zu) z.zaehlt ? (z.kg ?? 0.0) : 0.0];
  final zugangKg = rest.fold<double>(0, (s, kg) => s + kg);

  void teileZu(int i, int j, double nimm) {
    if (fertigJe[j].isAfter(tagJe[i])) {
      zuSpaet[i] += nimm;
      final bis = zuSpaetBis[i];
      if (bis == null || fertigJe[j].isAfter(bis)) zuSpaetBis[i] = fertigJe[j];
    } else {
      ausPlanung[i] += nimm;
      if (fertigJe[j].isAtSameMomentAs(tagJe[i])) knapp[i] += nimm;
    }
    offen[i] -= nimm;
    rest[j] -= nimm;
  }

  // 2. Ausdrücklich eingeplante Zeilen.
  final jeSchluessel = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    jeSchluessel
        .putIfAbsent(
          auftragsZeilenSchluessel(zeilen[i].beleg, zeilen[i].warenausgang),
          () => <int>[],
        )
        .add(i);
  }
  for (var j = 0; j < zu.length; j++) {
    for (final b in zu[j].bezuege) {
      final treffer = jeSchluessel[b.schluessel];
      if (treffer == null) continue;
      var anteil = b.kg;
      for (final i in treffer) {
        if (!eingeplantIn[i].contains(zu[j])) eingeplantIn[i].add(zu[j]);
        if (anteil <= _epsilon || rest[j] <= _epsilon) continue;
        if (offen[i] <= _epsilon) continue;
        final nimm = min(anteil, min(rest[j], offen[i]));
        teileZu(i, j, nimm);
        anteil -= nimm;
      }
    }
  }

  // 3. Übrige Produktion, rechtzeitig, in Versandreihenfolge.
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < zu.length && offen[i] > _epsilon; j++) {
      // Nach Fertigtag sortiert: Ab hier ist alles zu spät für diese Zeile.
      if (fertigJe[j].isAfter(tagJe[i])) break;
      if (rest[j] <= _epsilon) continue;
      teileZu(i, j, min(offen[i], rest[j]));
    }
  }

  // 4. Was übrig ist, kommt nach allen noch offenen Zeilen — sonst hätte
  //    Schritt 3 es genommen. Späteste Zeilen zuerst, jeweils aus der
  //    spätesten Produktion: Die frühere Zeile bekommt die frühere Ware.
  var spaeteste = zu.length - 1;
  for (var z = n - 1; z >= 0 && spaeteste >= 0; z--) {
    while (offen[z] > _epsilon && spaeteste >= 0) {
      if (rest[spaeteste] <= _epsilon) {
        spaeteste--;
        continue;
      }
      teileZu(z, spaeteste, min(offen[z], rest[spaeteste]));
    }
  }
  final ueberschuss =
      rest.fold<double>(0, (s, r) => s + (r > _epsilon ? r : 0.0));

  // Zu Tagen bündeln.
  final tage = <TagesDeckung>[];
  var k = 0;
  while (k < n) {
    final tag = tagJe[k];
    final gruppe = <ZeilenDeckung>[];
    while (k < n && tagJe[k].isAtSameMomentAs(tag)) {
      gruppe.add(
        ZeilenDeckung(
          position: zeilen[k],
          ausLagerKg: ausLager[k],
          ausPlanungKg: ausPlanung[k],
          knappKg: knapp[k],
          zuSpaetKg: zuSpaet[k],
          zuSpaetBis: zuSpaetBis[k],
          eingeplantIn: eingeplantIn[k],
        ),
      );
      k++;
    }
    tage.add(TagesDeckung(tag: tag, zeilen: gruppe));
  }

  return ArtikelDeckung(
    lagerKg: lagerKg,
    zugangKg: zugangKg,
    ueberschussKg: ueberschuss,
    tage: tage,
  );
}

/// Die Auftragszeilen der gewählten Tage, für die noch etwas fehlt — mit
/// genau der fehlenden Menge. Das wird beim Einplanen an die Produktion
/// gehängt.
List<AuftragsBezug> bezuegeFuerTage(
  ArtikelDeckung deckung,
  Set<DateTime> tage,
) {
  final gewaehlt = {for (final t in tage) _tag(t)};
  return [
    for (final t in deckung.tage)
      if (gewaehlt.contains(t.tag))
        for (final z in t.zeilen)
          if (z.fehltKg >= _schwelle)
            AuftragsBezug(
              beleg: z.position.beleg,
              warenausgang: t.tag,
              kg: z.fehltKg,
              debitor: z.position.debitor,
            ),
  ];
}

DateTime _tag(DateTime d) => DateTime(d.year, d.month, d.day);

String _datumText(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
