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

/// Quelle eines Bedarfs, der im Auftragsbestand aus abgehakten
/// Versandtagen entstanden ist — ein Planungsauftrag für den
/// Planungsvorschlag.
const String kQuelleAuftragsbestand = 'auftragsbestand';

/// Kurzbeschreibung gebündelter Auftragszeilen für die Bedarfsliste, etwa
/// „Versand Mi 02.10.–Fr 04.10. · 5 Aufträge · Kunde A, Kunde B, …".
String beschreibeBezuege(List<AuftragsBezug> bezuege) {
  if (bezuege.isEmpty) return '';
  final tage = [for (final b in bezuege) b.warenausgang]..sort();
  final von = tage.first;
  final bis = tage.last;
  final zeitraum = von.isAtSameMomentAs(bis)
      ? _tagKurz(von)
      : '${_tagKurz(von)}–${_tagKurz(bis)}';
  final kunden = <String>[];
  for (final b in bezuege) {
    final k = b.debitor.trim();
    if (k.isNotEmpty && !kunden.contains(k)) kunden.add(k);
  }
  final n = bezuege.length;
  return [
    'Versand $zeitraum',
    n == 1 ? '1 Auftrag' : '$n Aufträge',
    if (kunden.isNotEmpty)
      kunden.length <= 3
          ? kunden.join(', ')
          : '${kunden.take(3).join(', ')} …',
  ].join(' · ');
}

/// Was von den Auftragszeilen [alle] noch nicht an Produktionen vergeben
/// ist: je Zeile die Menge abzüglich dessen, was [vergeben] für dieselbe
/// Zeile trägt.
///
/// Wird ein Planungsauftrag in Teilen eingeplant, trägt jede Produktion
/// ihren Teil der Zeilen. Der Rest bleibt beim Planungsauftrag.
List<AuftragsBezug> restBezuege(
  List<AuftragsBezug> alle,
  List<AuftragsBezug> vergeben,
) {
  if (vergeben.isEmpty) return alle;
  final weg = <String, double>{};
  for (final b in vergeben) {
    weg[b.schluessel] = (weg[b.schluessel] ?? 0) + b.kg;
  }
  final rest = <AuftragsBezug>[];
  for (final b in alle) {
    final abzug = min(weg[b.schluessel] ?? 0.0, b.kg);
    if (abzug > 0) weg[b.schluessel] = weg[b.schluessel]! - abzug;
    final kg = b.kg - abzug;
    if (kg < _schwelle) continue;
    rest.add(
      abzug > 0
          ? AuftragsBezug(
              beleg: b.beleg,
              warenausgang: b.warenausgang,
              kg: kg,
              debitor: b.debitor,
            )
          : b,
    );
  }
  return rest;
}

/// Verteilt [kg] auf die Auftragszeilen [bezuege], der früheste
/// Warenausgang zuerst. Reicht die Menge nicht für alle, bekommt die letzte
/// Zeile nur den Rest, und die übrigen gehen leer aus. Mehr als ihre eigene
/// Menge bekommt keine Zeile.
///
/// So trägt eine Produktion, die nur einen Teil eines Planungsauftrags
/// abdeckt, auch nur die Zeilen, die sie wirklich bedient.
List<AuftragsBezug> teileBezuegeZu(List<AuftragsBezug> bezuege, double kg) {
  final sortiert = [...bezuege]..sort((a, b) {
      final t = a.warenausgang.compareTo(b.warenausgang);
      return t != 0 ? t : a.beleg.compareTo(b.beleg);
    });
  final ergebnis = <AuftragsBezug>[];
  var rest = kg;
  for (final b in sortiert) {
    if (rest < _schwelle) break;
    if (b.kg <= rest + _epsilon) {
      ergebnis.add(b);
      rest -= b.kg;
    } else {
      ergebnis.add(
        AuftragsBezug(
          beleg: b.beleg,
          warenausgang: b.warenausgang,
          kg: rest,
          debitor: b.debitor,
        ),
      );
      rest = 0;
    }
  }
  return ergebnis;
}

// ═══════════════════════════════════════════════════════════════════════════
// Vormerkungen: an den Planungsvorschlag übergeben, noch nicht eingeplant
// ═══════════════════════════════════════════════════════════════════════════

/// Was für einen Bedarf schon im Board steht.
class BedarfsPlanung {
  const BedarfsPlanung({required this.ketten, required this.bezuege});

  /// Je Kette mit diesem Bedarf: Tag der Wurzel und eingeplante
  /// Fertigmenge.
  final List<({DateTime tag, double kg})> ketten;

  /// Die Auftragszeilen, die diese Ketten tragen.
  final List<AuftragsBezug> bezuege;

  /// Eingeplante Fertigmenge aller Ketten.
  double get kg => ketten.fold<double>(0, (s, k) => s + k.kg);

  /// Davon auf Tagen vor [heute] — gilt als produziert.
  double produziertVor(DateTime heute) {
    final h = _tag(heute);
    return ketten.fold<double>(
      0,
      (s, k) => _tag(k.tag).isBefore(h) ? s + k.kg : s,
    );
  }
}

/// Je Bedarf die eingeplanten Ketten und die Auftragszeilen, die sie
/// tragen.
///
/// Bedarf, Fertigmenge und Auftragszeilen stehen an der Wurzel einer
/// Kette. Eine Kette zählt, solange einer ihrer Schritte lebt — auch wenn
/// die Wurzel selbst gelöscht ist: Wer im Board nur den ersten Schritt
/// löscht, etwa die Zerlegung, weil das Fleisch schon zerlegt kommt,
/// produziert trotzdem. Sonst stünde der Bedarf wieder als offen da und
/// würde ein zweites Mal eingeplant.
///
/// Bedarfsliste, Auftragsbestand und Planungsvorschlag rechnen alle
/// hiermit, damit sie dieselbe Menge als eingeplant sehen.
Future<Map<String, BedarfsPlanung>> ladeBedarfsPlanung(AppDatabase db) async {
  final wurzeln = await (db.select(db.productionTasks)
        ..where((t) => t.bedarfId.isNotNull()))
      .get();
  final lebtNoch = await _lebendeKetten(db, [
    for (final w in wurzeln)
      if (w.deletedAt != null) w.id,
  ]);

  final ketten = <String, List<({DateTime tag, double kg})>>{};
  final bezuege = <String, List<AuftragsBezug>>{};
  for (final w in wurzeln) {
    final bid = w.bedarfId;
    if (bid == null) continue;
    if (w.deletedAt != null && !lebtNoch.contains(w.id)) continue;
    ketten
        .putIfAbsent(bid, () => [])
        .add((tag: w.datum, kg: w.fertigMengeKg ?? 0.0));
    bezuege
        .putIfAbsent(bid, () => <AuftragsBezug>[])
        .addAll(AuftragsBezug.dekodiere(w.auftragsZeilen));
  }
  return {
    for (final e in ketten.entries)
      e.key: BedarfsPlanung(
        ketten: e.value,
        bezuege: bezuege[e.key] ?? const [],
      ),
  };
}

/// Welche der gelöschten Wurzeln [wurzelIds] noch einen lebenden Schritt
/// in ihrer Kette haben. Ebene für Ebene abwärts über `parentTaskId` —
/// Ketten sind kurz, ein paar Abfragen reichen.
Future<Set<String>> _lebendeKetten(
  AppDatabase db,
  List<String> wurzelIds,
) async {
  final lebt = <String>{};
  // Schritt-ID → ID der Wurzel, zu der er gehört.
  var ebene = {for (final id in wurzelIds) id: id};
  // Sicherung gegen Kreise in den Daten.
  for (var tiefe = 0; ebene.isNotEmpty && tiefe < 20; tiefe++) {
    final ids = ebene.keys.toList();
    final naechste = <String, String>{};
    for (var i = 0; i < ids.length; i += _blockGroesse) {
      final block = ids.sublist(i, min(i + _blockGroesse, ids.length));
      final kinder = await (db.select(db.productionTasks)
            ..where((t) => t.parentTaskId.isIn(block)))
          .get();
      for (final k in kinder) {
        final wurzel = ebene[k.parentTaskId];
        if (wurzel == null || lebt.contains(wurzel)) continue;
        if (k.deletedAt == null) {
          lebt.add(wurzel);
        } else {
          naechste[k.id] = wurzel;
        }
      }
    }
    naechste.removeWhere((_, wurzel) => lebt.contains(wurzel));
    ebene = naechste;
  }
  return lebt;
}

/// Höchstens so viele IDs je Abfrage — SQLite begrenzt die Zahl der
/// Platzhalter.
const int _blockGroesse = 500;

/// Die Auftragszeilen, die eine neue Produktion über [fertigKg] für
/// [bedarf] trägt: von den Zeilen, die noch keine Kette trägt, die
/// frühesten — so viele, wie die Menge bedient.
///
/// Für einen Planungsauftrag, der nicht über den Planungsvorschlag,
/// sondern von Hand im Board eingeplant wird. Leer bei einem Bedarf ohne
/// Auftragszeilen.
Future<List<AuftragsBezug>> bezuegeFuerNeueProduktion(
  AppDatabase db,
  Demand bedarf,
  double fertigKg,
) async {
  final alle = AuftragsBezug.dekodiere(bedarf.auftragsZeilen);
  if (alle.isEmpty || fertigKg <= 0) return const [];
  final planung = await ladeBedarfsPlanung(db);
  return teileBezuegeZu(
    restBezuege(alle, planung[bedarf.id]?.bezuege ?? const []),
    fertigKg,
  );
}

/// Ein offener Planungsauftrag aus dem Auftragsbestand: Die Versandtage
/// sind gebündelt und an den Planungsvorschlag übergeben, eingeplant ist
/// (noch) nichts oder nur ein Teil.
///
/// Er deckt nichts — dafür gibt es noch keine Produktion —, hält die
/// Zeilen aber fest, damit sie niemand ein zweites Mal bündelt.
class Vormerkung {
  const Vormerkung({
    required this.bedarfId,
    required this.offenKg,
    required this.bezuege,
    this.termin,
  });

  final String bedarfId;

  /// Was vom Planungsauftrag noch nicht eingeplant ist, in kg.
  final double offenKg;

  /// Spätester Produktionstag.
  final DateTime? termin;

  /// Die Auftragszeilen, die noch keine Produktion trägt.
  final List<AuftragsBezug> bezuege;
}

/// Lädt die offenen Planungsaufträge, gruppiert nach Artikelnummer.
///
/// Offen heißt: nicht gelöscht, nicht von Hand erledigt, und die
/// eingeplante Menge reicht noch nicht. Ist er ganz eingeplant, tragen die
/// Ketten die Zeilen weiter — dann ist hier nichts mehr vorzumerken. Ist
/// er zum Teil eingeplant, bleiben nur die Zeilen, die noch keine Kette
/// trägt.
Future<Map<String, List<Vormerkung>>> ladeVormerkungen(AppDatabase db) async {
  final bedarfe = await (db.select(db.demands)
        ..where((d) => d.deletedAt.isNull())
        ..where((d) => d.manuellErledigt.equals(false))
        ..where((d) => d.auftragsZeilen.isNotNull()))
      .get();
  if (bedarfe.isEmpty) return const {};

  final planung = await ladeBedarfsPlanung(db);
  final produkte = await db.select(db.products).get();
  final nummerJeId = {for (final p in produkte) p.id: p.artikelnummer};

  final ergebnis = <String, List<Vormerkung>>{};
  for (final d in bedarfe) {
    final geplant = planung[d.id];
    final offen = d.mengeKgFertig - (geplant?.kg ?? 0);
    if (offen <= 0.5) continue;
    final bezuege = restBezuege(
      AuftragsBezug.dekodiere(d.auftragsZeilen),
      geplant?.bezuege ?? const [],
    );
    final nummer = nummerJeId[d.productId];
    if (bezuege.isEmpty || nummer == null) continue;
    ergebnis.putIfAbsent(nummer, () => []).add(
          Vormerkung(
            bedarfId: d.id,
            offenKg: offen,
            termin: d.termin,
            bezuege: bezuege,
          ),
        );
  }
  return ergebnis;
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
    this.vorgemerktKg = 0,
    this.vorgemerktIn = const [],
    this.gesperrt = false,
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

  /// Teil von [fehltKg], der an den Planungsvorschlag übergeben ist —
  /// gebündelt, aber noch nicht eingeplant.
  final double vorgemerktKg;

  /// Die Planungsaufträge dazu.
  final List<Vormerkung> vorgemerktIn;

  /// Ein verschobener Auftrag, dessen Planung noch am alten Versandtag
  /// hängt (siehe „Planung prüfen"). Bis die Verschiebung übernommen oder
  /// verworfen ist, lässt sich die Zeile nicht bündeln — sonst würde
  /// dieselbe Menge ein zweites Mal eingeplant. Was fehlt, zählt trotzdem
  /// als offen.
  final bool gesperrt;

  double get kg => position.kg;

  String get schluessel =>
      auftragsZeilenSchluessel(position.beleg, position.warenausgang);

  /// Weder im Lager noch eingeplant — das ist noch einzuplanen.
  double get fehltKg {
    final rest = kg - ausLagerKg - ausPlanungKg - zuSpaetKg;
    return rest > 0 ? rest : 0.0;
  }

  /// Was noch niemand angefasst hat: fehlt und ist auch nicht an den
  /// Planungsvorschlag übergeben. Das ist noch zu bündeln.
  double get offenKg {
    final rest = fehltKg - vorgemerktKg;
    return rest > 0 ? rest : 0.0;
  }

  /// Ausdrücklich für diese Zeile eingeplant.
  bool get geplant => eingeplantIn.isNotEmpty;

  /// An den Planungsvorschlag übergeben.
  bool get vorgemerkt => vorgemerktIn.isNotEmpty;

  /// Nicht rechtzeitig gedeckt: fehlt oder kommt zu spät.
  bool get offen => fehltKg + zuSpaetKg >= _schwelle;

  /// Nichts mehr zu tun: nichts offen, nichts zu spät.
  bool get erledigt => offenKg < _schwelle && zuSpaetKg < _schwelle;
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

  /// Weder im Lager noch eingeplant.
  double get fehltKg => _summe((z) => z.fehltKg);

  /// Davon an den Planungsvorschlag übergeben.
  double get vorgemerktKg => _summe((z) => z.vorgemerktKg);

  /// Davon noch zu bündeln.
  double get offenKg => _summe((z) => z.offenKg);

  /// Davon an gesperrten Zeilen — erst zu bündeln, wenn die Verschiebung
  /// geklärt ist.
  double get gesperrtKg => _summe((z) => z.gesperrt ? z.offenKg : 0.0);

  /// Was sich jetzt bündeln lässt: offen und nicht gesperrt.
  double get einplanbarKg => _summe((z) => z.gesperrt ? 0.0 : z.offenKg);

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

  /// Für diesen Tag lässt sich noch etwas einplanen: Es fehlt etwas, das
  /// weder eingeplant noch an den Planungsvorschlag übergeben ist — und
  /// nicht an einer gesperrten Zeile hängt.
  bool get einplanbar => einplanbarKg >= _schwelle;

  /// Planungsaufträge, die Zeilen dieses Tages vorgemerkt haben — jeder
  /// nur einmal.
  List<Vormerkung> get vorgemerktIn {
    final liste = <Vormerkung>[];
    for (final z in zeilen) {
      for (final v in z.vorgemerktIn) {
        if (!liste.contains(v)) liste.add(v);
      }
    }
    return liste;
  }

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

  /// Weder im Lager noch in einer Produktion der App.
  double get fehltKg => _summe((t) => t.fehltKg);

  /// Davon an den Planungsvorschlag übergeben.
  double get vorgemerktKg => _summe((t) => t.vorgemerktKg);

  /// Davon noch zu bündeln — die eigentliche Arbeit im Auftragsbestand.
  double get offenKg => _summe((t) => t.offenKg);

  double _summe(double Function(TagesDeckung t) wert) =>
      tage.fold<double>(0, (s, t) => s + wert(t));

  /// Alles rechtzeitig gedeckt — aus dem Lager oder aus der Planung.
  bool get gedeckt => fehltKg < _schwelle && zuSpaetKg < _schwelle;

  /// Das Lager allein trägt alle Aufträge.
  bool get lagerReicht => gedeckt && ausPlanungKg < _schwelle;

  /// Im Auftragsbestand nichts mehr zu tun: Was fehlt, ist eingeplant
  /// oder an den Planungsvorschlag übergeben, und nichts kommt zu spät.
  bool get erledigt => offenKg < _schwelle && zuSpaetKg < _schwelle;

  /// Erster Warenausgang, der nicht rechtzeitig gedeckt ist.
  DateTime? get ersterEngpass => _ersterTag((t) => t.offen);

  /// Erster Warenausgang, für den noch etwas eingeplant werden muss — das
  /// ist der Termin für die fehlende Menge.
  DateTime? get ersterFehltag => _ersterTag((t) => t.fehltKg >= _schwelle);

  /// Erster Warenausgang, dessen Ware zu spät fertig wird.
  DateTime? get ersterZuSpaet => _ersterTag((t) => t.zuSpaetKg >= _schwelle);

  /// Erster Warenausgang mit etwas, das noch zu bündeln ist.
  DateTime? get ersterOffenTag => _ersterTag((t) => t.offenKg >= _schwelle);

  /// Frühester Termin der Planungsaufträge, die hier etwas vormerken.
  DateTime? get fruehesterVormerkTermin {
    DateTime? frueh;
    for (final t in tage) {
      for (final v in t.vorgemerktIn) {
        final termin = v.termin;
        if (termin != null && (frueh == null || termin.isBefore(frueh))) {
          frueh = termin;
        }
      }
    }
    return frueh;
  }

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
///
/// 5. **Vormerkungen** zuletzt: Was danach noch fehlt, kann ein offener
///    Planungsauftrag ([Vormerkung]) für sich reservieren. Er deckt
///    nichts, die Zeile gilt aber als übergeben und lässt sich nicht ein
///    zweites Mal bündeln.
///
/// [gesperrt] sind Schlüssel von Zeilen, die sich nicht bündeln lassen
/// (siehe [ZeilenDeckung.gesperrt]). An der Rechnung ändern sie nichts.
ArtikelDeckung berechneDeckung({
  required double lagerKg,
  required List<AuftragsPosition> positionen,
  List<ProduktionsZugang> zugaenge = const [],
  List<Vormerkung> vormerkungen = const [],
  Set<String> gesperrt = const {},
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

  // 5. Vormerkungen reservieren, was noch fehlt — frühester Termin zuerst.
  final vorgemerkt = List<double>.filled(n, 0.0);
  final vorgemerktIn =
      List<List<Vormerkung>>.generate(n, (_) => <Vormerkung>[]);
  final nachTermin = [...vormerkungen]..sort((a, b) {
      final ta = a.termin, tb = b.termin;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });
  for (final v in nachTermin) {
    var verfuegbar = v.offenKg;
    for (final b in v.bezuege) {
      final treffer = jeSchluessel[b.schluessel];
      if (treffer == null) continue;
      var anteil = b.kg;
      for (final i in treffer) {
        if (!vorgemerktIn[i].contains(v)) vorgemerktIn[i].add(v);
        final frei = offen[i] - vorgemerkt[i];
        if (anteil <= _epsilon || verfuegbar <= _epsilon || frei <= _epsilon) {
          continue;
        }
        final nimm = min(anteil, min(verfuegbar, frei));
        vorgemerkt[i] += nimm;
        anteil -= nimm;
        verfuegbar -= nimm;
      }
    }
  }

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
          vorgemerktKg: vorgemerkt[k],
          vorgemerktIn: vorgemerktIn[k],
          gesperrt: gesperrt.contains(
            auftragsZeilenSchluessel(zeilen[k].beleg, zeilen[k].warenausgang),
          ),
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

/// Die Auftragszeilen der gewählten Tage, für die noch etwas fehlt, das
/// weder eingeplant noch vorgemerkt ist — mit genau dieser Menge. Das wird
/// beim Einplanen an die Produktion oder den Planungsauftrag gehängt.
/// Gesperrte Zeilen bleiben draußen.
List<AuftragsBezug> bezuegeFuerTage(
  ArtikelDeckung deckung,
  Set<DateTime> tage,
) {
  final gewaehlt = {for (final t in tage) _tag(t)};
  return [
    for (final t in deckung.tage)
      if (gewaehlt.contains(t.tag))
        for (final z in t.zeilen)
          if (z.offenKg >= _schwelle && !z.gesperrt)
            AuftragsBezug(
              beleg: z.position.beleg,
              warenausgang: t.tag,
              kg: z.offenKg,
              debitor: z.position.debitor,
            ),
  ];
}

DateTime _tag(DateTime d) => DateTime(d.year, d.month, d.day);

const _wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// „Mi 02.10."
String _tagKurz(DateTime d) => '${_wochentage[d.weekday - 1]} '
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.';

String _datumText(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
