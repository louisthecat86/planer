import 'dart:math' show max, min;

import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../core/services/auftragsbestand_deckung.dart';
import '../../core/services/auftragsbestand_vergleich.dart';
import 'auftrags_einplanung.dart' show vorschlagProduktionstag;

// Planung prüfen: Passt, was verplant ist, noch zum Auftragsbestand?
//
// Planungsaufträge (Vormerkungen) und Produktionen im Board hängen über
// Beleg und Versandtag an Auftragszeilen (siehe AuftragsBezug). Ändert
// Navision eine Zeile, hängt die Planung an einer Zeile, die es so nicht
// mehr gibt:
//
// * Verschoben: Die Zeile am neuen Tag steht als offen da und würde ein
//   zweites Mal gebündelt — doppelte Produktion.
// * Weniger bestellt, entfallen, ausgeliefert: Der Planungsauftrag würde
//   trotzdem die volle Menge produzieren — Überproduktion.
//
// Die Prüfung findet solche Stellen und schlägt je eine Anpassung vor. An
// Produktionen im Board ändert sie nur die Zuordnung zu den Aufträgen, nie
// Menge oder Tag: Ob eine Produktion kleiner wird, wegfällt oder verlegt
// wird, entscheidet der Planer im Board.

// ═══════════════════════════════════════════════════════════════════════════
// Konflikte
// ═══════════════════════════════════════════════════════════════════════════

/// Was an einer Planung nicht mehr zum Auftragsbestand passt.
enum PruefArt {
  /// Die Zeile steht noch im Bericht, aber mit weniger Menge, als für sie
  /// verplant ist.
  weniger('weniger bestellt'),

  /// Derselbe Auftrag steht jetzt an einem anderen Versandtag.
  verschoben('verschoben'),

  /// Die Zeile fehlt, ihr Versandtag ist vorbei oder heute: vermutlich
  /// ausgeliefert.
  ausgeliefert('vermutlich ausgeliefert'),

  /// Die Zeile fehlt, obwohl ihr Versandtag noch kommt: storniert oder
  /// geändert.
  entfallen('entfallen');

  const PruefArt(this.label);
  final String label;
}

/// Ein Teil einer Planung, der an einer Auftragszeile hängt: der noch
/// nicht eingeplante Rest eines Planungsauftrags (Vormerkung) oder die
/// Zuordnung einer Produktion im Board.
class Verplanung {
  const Verplanung({
    required this.kg,
    this.bedarfId,
    this.kettenId,
    this.tag,
    this.beginn,
  });

  /// Der Planungsauftrag — bei einer Vormerkung.
  final String? bedarfId;

  /// Die Wurzel der Kette — bei einer Produktion.
  final String? kettenId;

  /// Für die Zeile verplant, in kg.
  final double kg;

  /// Vormerkung: spätester Produktionstag. Produktion: der Tag, an dem
  /// sie fertig ist.
  final DateTime? tag;

  /// Produktion: Tag des ersten Schritts.
  final DateTime? beginn;

  bool get istVormerkung => kettenId == null;
}

/// Eine Auftragszeile, an der Planung hängt, die nicht mehr passt — samt
/// Vorschlag, was damit zu tun ist (siehe [passeAn]).
class PlanungsKonflikt {
  const PlanungsKonflikt({
    required this.art,
    required this.artikelnummer,
    required this.beleg,
    required this.warenausgang,
    required this.verplant,
    this.bezeichnung = '',
    this.debitor = '',
    this.imBerichtKg = 0,
    this.neuerWarenausgang,
    this.sicher = true,
    this.vorZeitraum = false,
  });

  final PruefArt art;
  final String artikelnummer;
  final String bezeichnung;
  final String beleg;
  final String debitor;

  /// Der Versandtag, für den geplant wurde.
  final DateTime warenausgang;

  /// Bei [PruefArt.verschoben]: der neue Versandtag.
  final DateTime? neuerWarenausgang;

  /// Was der Bericht für die Zeile jetzt zeigt, in kg: bei
  /// [PruefArt.verschoben] die Zeile am neuen Tag, bei einer fehlenden
  /// Zeile 0.
  final double imBerichtKg;

  /// Was an der Zeile hängt.
  final List<Verplanung> verplant;

  /// Eindeutig: weniger im Bericht, im Zeitraum des Berichts entfallen
  /// oder ausgeliefert, verschoben mit Beleg, der beim letzten Einlesen am
  /// alten Tag verschwand und am neuen auftauchte. Nur eindeutige
  /// Vorschläge lassen sich gesammelt übernehmen.
  final bool sicher;

  /// Der Versandtag liegt vor dem Zeitraum des Berichts — er sagt über die
  /// Zeile nichts. Vermutlich ist sie ausgeliefert, sicher ist es nicht.
  final bool vorZeitraum;

  double get geplantKg => verplant.fold<double>(0, (s, v) => s + v.kg);

  /// So viel ist zu viel verplant.
  double get zuVielKg {
    final d = geplantKg - imBerichtKg;
    return d > 0 ? d : 0.0;
  }

  String get schluessel => auftragsZeilenSchluessel(beleg, warenausgang);

  /// Bei [PruefArt.verschoben]: der Schlüssel der Zeile am neuen Tag.
  String? get neuerSchluessel {
    final neu = neuerWarenausgang;
    return neu == null ? null : auftragsZeilenSchluessel(beleg, neu);
  }

  /// Derselbe Auftrag als entfallen statt verschoben — für „Nicht
  /// verschoben": Der alte Auftrag ist weg, der am neuen Tag ist ein
  /// eigener. Die alte Zeile verlässt dann die Planung, und die neue lässt
  /// sich ganz normal bündeln.
  PlanungsKonflikt get alsEntfallen => PlanungsKonflikt(
        art: PruefArt.entfallen,
        artikelnummer: artikelnummer,
        bezeichnung: bezeichnung,
        beleg: beleg,
        debitor: debitor,
        warenausgang: warenausgang,
        verplant: verplant,
        sicher: sicher,
      );

  /// Ein Planungsauftrag hängt an der Zeile.
  bool get mitVormerkung => verplant.any((v) => v.istVormerkung);

  /// Eine Produktion im Board hängt an der Zeile.
  bool get mitProduktion => verplant.any((v) => !v.istVormerkung);

  /// Auf einen früheren Tag verschoben, und eine Produktion wird erst
  /// danach fertig — im Board vorziehen.
  bool get produktionZuSpaet {
    final neu = neuerWarenausgang;
    if (neu == null) return false;
    return verplant.any((v) {
      final fertig = v.tag;
      return !v.istVormerkung && fertig != null && fertig.isAfter(neu);
    });
  }
}

/// Sucht Planung, die nicht mehr zum Auftragsbestand [bestand] passt.
///
/// Geprüft wird, was an Auftragszeilen hängt: die offenen Reste der
/// Planungsaufträge ([vormerkungen]) und die Produktionen im Board
/// ([zugaenge]), die noch nicht im Lager des Berichts stecken. Je Zeile:
///
/// * steht im Bericht, aber mit weniger, als verplant ist →
///   [PruefArt.weniger];
/// * fehlt, und derselbe Beleg hat genau eine neue Zeile an einem anderen
///   Tag, an der noch nichts hängt → [PruefArt.verschoben]. Neu heißt:
///   nicht im vorigen Bericht ([vorher]), aber in dessen Zeitraum. Beide
///   Tage müssen noch kommen;
/// * fehlt im Zeitraum des Berichts → [PruefArt.entfallen], wenn der
///   Versandtag noch kommt, sonst [PruefArt.ausgeliefert];
/// * fehlt, liegt aber vor dem Zeitraum und ist vorbei → vermutlich
///   ausgeliefert, nicht [PlanungsKonflikt.sicher];
/// * liegt nach dem Zeitraum → kein Konflikt: Der Bericht sagt darüber
///   nichts.
///
/// [namen] liefert Bezeichnungen für Artikel, die in keinem der beiden
/// Berichte stehen. Sortiert nach Versandtag, der früheste zuerst.
List<PlanungsKonflikt> ermittleKonflikte({
  required BestandsStand bestand,
  BestandsStand vorher = const BestandsStand(),
  Map<String, List<Vormerkung>> vormerkungen = const {},
  Map<String, List<ProduktionsZugang>> zugaenge = const {},
  Map<String, String> namen = const {},
}) {
  if (bestand.leer) return const [];
  final standTag = bestand.tag;
  final jetzt = zeilenJeArtikel(bestand.zeilen);
  final frueher = zeilenJeArtikel(vorher.zeilen);

  bool kommtNoch(DateTime tag) => standTag == null || tag.isAfter(standTag);

  final konflikte = <PlanungsKonflikt>[];
  for (final nr in {...vormerkungen.keys, ...zugaenge.keys}) {
    // Was an welcher Zeile hängt.
    final verplant = <String, List<Verplanung>>{};
    final bezugJe = <String, AuftragsBezug>{};
    void merke(AuftragsBezug b, Verplanung v) {
      if (b.kg < _schwelle) return;
      bezugJe.putIfAbsent(b.schluessel, () => b);
      verplant.putIfAbsent(b.schluessel, () => []).add(v);
    }

    for (final v in vormerkungen[nr] ?? const <Vormerkung>[]) {
      for (final b in v.bezuege) {
        merke(b, Verplanung(kg: b.kg, bedarfId: v.bedarfId, tag: v.termin));
      }
    }
    for (final z in zugaenge[nr] ?? const <ProduktionsZugang>[]) {
      // Schon im Lager des Berichts: produziert, da gibt es nichts mehr
      // anzupassen.
      if (z.art == ZugangsArt.imLager) continue;
      for (final b in z.bezuege) {
        merke(
          b,
          Verplanung(
            kg: b.kg,
            kettenId: z.kettenId,
            tag: z.fertigAm,
            beginn: z.beginn,
          ),
        );
      }
    }
    if (verplant.isEmpty) continue;

    final zeilen = jetzt[nr] ?? const <String, BestandsZeile>{};
    final zeilenVorher = frueher[nr] ?? const <String, BestandsZeile>{};
    final bezeichnung = bestand.artikel[nr]?.bezeichnung ??
        vorher.artikel[nr]?.bezeichnung ??
        namen[nr] ??
        '';

    // Mögliche Verschiebungen, je Beleg: weggefallene Zeilen, deren Tag
    // noch kommt …
    final wegJeBeleg = <String, List<String>>{};
    for (final e in bezugJe.entries) {
      if (zeilen.containsKey(e.key) || !kommtNoch(e.value.warenausgang)) {
        continue;
      }
      wegJeBeleg.putIfAbsent(e.value.beleg.trim(), () => []).add(e.key);
    }
    // … und neue Zeilen desselben Belegs, an denen nichts hängt und deren
    // Tag ebenfalls noch kommt.
    final zielJeBeleg = <String, List<BestandsZeile>>{};
    for (final e in zeilen.entries) {
      final z = e.value;
      if (verplant.containsKey(e.key) ||
          !wegJeBeleg.containsKey(z.beleg) ||
          !kommtNoch(z.warenausgang)) {
        continue;
      }
      final neu = vorher.leer ||
          (!zeilenVorher.containsKey(e.key) &&
              vorher.imZeitraum(z.warenausgang));
      if (neu) zielJeBeleg.putIfAbsent(z.beleg, () => []).add(z);
    }

    for (final e in verplant.entries) {
      final s = e.key;
      final b = bezugJe[s]!;
      final beleg = b.beleg.trim();
      final geplant = e.value.fold<double>(0, (sum, v) => sum + v.kg);

      PlanungsKonflikt konflikt(
        PruefArt art, {
        double imBerichtKg = 0,
        DateTime? neuerWarenausgang,
        bool sicher = true,
        bool vorZeitraum = false,
      }) =>
          PlanungsKonflikt(
            art: art,
            artikelnummer: nr,
            bezeichnung: bezeichnung,
            beleg: beleg,
            debitor: b.debitor,
            warenausgang: b.warenausgang,
            verplant: e.value,
            imBerichtKg: imBerichtKg,
            neuerWarenausgang: neuerWarenausgang,
            sicher: sicher,
            vorZeitraum: vorZeitraum,
          );

      final zeile = zeilen[s];
      if (zeile != null) {
        if (geplant - zeile.kg >= _toleranz) {
          konflikte.add(konflikt(PruefArt.weniger, imBerichtKg: zeile.kg));
        }
        continue;
      }

      final weg = wegJeBeleg[beleg];
      final ziele = zielJeBeleg[beleg];
      if (weg != null &&
          weg.length == 1 &&
          weg.single == s &&
          ziele != null &&
          ziele.length == 1) {
        konflikte.add(
          konflikt(
            PruefArt.verschoben,
            imBerichtKg: ziele.single.kg,
            neuerWarenausgang: ziele.single.warenausgang,
            sicher: !vorher.leer && zeilenVorher.containsKey(s),
          ),
        );
        continue;
      }

      final tag = b.warenausgang;
      if (bestand.imZeitraum(tag)) {
        konflikte.add(
          konflikt(
            kommtNoch(tag) ? PruefArt.entfallen : PruefArt.ausgeliefert,
          ),
        );
        continue;
      }
      // Außerhalb des Zeitraums. Vor ihm und vorbei: vermutlich
      // ausgeliefert, nur zeigt der Bericht es nicht. Alles andere: Über
      // die Zeile sagt er nichts.
      final von = bestand.von;
      if (von != null && tag.isBefore(_tag(von)) && !kommtNoch(tag)) {
        konflikte.add(
          konflikt(PruefArt.ausgeliefert, sicher: false, vorZeitraum: true),
        );
      }
    }
  }

  konflikte.sort((a, b) {
    final t = a.warenausgang.compareTo(b.warenausgang);
    if (t != 0) return t;
    final n = a.artikelnummer.compareTo(b.artikelnummer);
    return n != 0 ? n : a.beleg.compareTo(b.beleg);
  });
  return konflikte;
}

/// Prüft die Planung gegen den gespeicherten Auftragsbestand (siehe
/// [ermittleKonflikte]). [bestand] und [vorher] lassen sich mitgeben,
/// wenn sie schon geladen sind.
Future<List<PlanungsKonflikt>> pruefePlanung(
  AppDatabase db, {
  required DateTime heute,
  BestandsStand? bestand,
  BestandsStand? vorher,
}) async {
  final jetzt = bestand ?? await ladeBestand(db);
  if (jetzt.leer) return const [];
  final frueher = vorher ?? await ladeVorherigenBestand(db);
  final vormerkungen = await ladeVormerkungen(db);
  final zugaenge = await ladeProduktionsZugaenge(
    db,
    heute: heute,
    berichtTag: jetzt.tag ?? _tag(heute),
  );
  final produkte = await db.select(db.products).get();
  return ermittleKonflikte(
    bestand: jetzt,
    vorher: frueher,
    vormerkungen: vormerkungen,
    zugaenge: zugaenge,
    namen: {
      for (final p in produkte)
        if (p.deletedAt == null) p.artikelnummer: p.artikelbezeichnung,
    },
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Für die Deckung im Auftragsbestand
// ═══════════════════════════════════════════════════════════════════════════

/// Die Planung so, als wären verschobene Aufträge schon umgehängt — für
/// die Deckung im Auftragsbestand. In der Datenbank ändert sich nichts.
///
/// Solange die Planung noch am alten Versandtag hängt, stünde der Auftrag
/// am neuen Tag als offen da, obwohl für ihn schon produziert wird. Mit
/// dem neuen Tag gerechnet, zeigt die Deckung ihn als vorgemerkt oder
/// eingeplant — und meldet, wenn die Produktion für den neuen Tag zu spät
/// kommt. Gebündelt werden kann die Zeile trotzdem erst, wenn die
/// Verschiebung übernommen oder verworfen ist (siehe [verschobeneZiele]).
({
  Map<String, List<Vormerkung>> vormerkungen,
  Map<String, List<ProduktionsZugang>> zugaenge,
}) wieUmgehaengt({
  required Map<String, List<Vormerkung>> vormerkungen,
  required Map<String, List<ProduktionsZugang>> zugaenge,
  required List<PlanungsKonflikt> konflikte,
}) {
  // Artikelnummer → (alter Schlüssel → neuer Versandtag).
  final umzug = <String, Map<String, DateTime>>{};
  for (final k in konflikte) {
    final neu = k.neuerWarenausgang;
    if (k.art != PruefArt.verschoben || neu == null) continue;
    umzug.putIfAbsent(k.artikelnummer, () => {})[k.schluessel] = neu;
  }
  if (umzug.isEmpty) return (vormerkungen: vormerkungen, zugaenge: zugaenge);

  List<AuftragsBezug> umgehaengt(
    List<AuftragsBezug> bezuege,
    Map<String, DateTime> nach,
  ) {
    return [
      for (final b in bezuege) _amTag(b, nach[b.schluessel]),
    ];
  }

  List<Vormerkung> vorgemerkt(String nr, List<Vormerkung> liste) {
    final nach = umzug[nr];
    if (nach == null) return liste;
    return [
      for (final v in liste)
        Vormerkung(
          bedarfId: v.bedarfId,
          offenKg: v.offenKg,
          termin: v.termin,
          bezuege: umgehaengt(v.bezuege, nach),
        ),
    ];
  }

  List<ProduktionsZugang> produziert(
    String nr,
    List<ProduktionsZugang> liste,
  ) {
    final nach = umzug[nr];
    if (nach == null) return liste;
    return [
      for (final z in liste)
        ProduktionsZugang(
          kettenId: z.kettenId,
          productId: z.productId,
          fertigAm: z.fertigAm,
          startAm: z.startAm,
          art: z.art,
          kg: z.kg,
          erfasst: z.erfasst,
          bezuege: umgehaengt(z.bezuege, nach),
        ),
    ];
  }

  return (
    vormerkungen: {
      for (final e in vormerkungen.entries) e.key: vorgemerkt(e.key, e.value),
    },
    zugaenge: {
      for (final e in zugaenge.entries) e.key: produziert(e.key, e.value),
    },
  );
}

/// [b] am Tag [tag] — oder unverändert, wenn es keinen gibt.
AuftragsBezug _amTag(AuftragsBezug b, DateTime? tag) => tag == null
    ? b
    : AuftragsBezug(
        beleg: b.beleg,
        warenausgang: tag,
        kg: b.kg,
        debitor: b.debitor,
      );

/// Je Artikelnummer die Zeilen, auf die ein Auftrag verschoben wurde,
/// dessen Planung noch am alten Tag hängt: Schlüssel der Zeile am neuen
/// Tag → Konflikt. Diese Zeilen sind gesperrt (siehe
/// [ZeilenDeckung.gesperrt]), bis die Verschiebung geklärt ist.
Map<String, Map<String, PlanungsKonflikt>> verschobeneZiele(
  List<PlanungsKonflikt> konflikte,
) {
  final ziele = <String, Map<String, PlanungsKonflikt>>{};
  for (final k in konflikte) {
    final ziel = k.neuerSchluessel;
    if (k.art != PruefArt.verschoben || ziel == null) continue;
    ziele.putIfAbsent(k.artikelnummer, () => {})[ziel] = k;
  }
  return ziele;
}

// ═══════════════════════════════════════════════════════════════════════════
// Anpassen
// ═══════════════════════════════════════════════════════════════════════════

/// Übernimmt die Vorschläge zu [konflikte]:
///
/// * **verschoben** — alles, was an der Zeile hängt, an den neuen Tag
///   hängen: Planungsaufträge und Produktionen. Ein Planungsauftrag rückt
///   dabei seinen Termin vor, wenn der neue Tag früher ist. Ist die Zeile
///   am neuen Tag kleiner, wird danach verringert wie bei „weniger".
/// * **weniger bestellt** — das zu viel Verplante abziehen: erst vom
///   offenen Rest der Planungsaufträge (die Menge des Auftrags sinkt mit),
///   dann von der Zuordnung der Produktionen.
/// * **entfallen, ausgeliefert** — die Zeile aus der Planung nehmen: Ein
///   Planungsauftrag verliert die Zeile samt ihrem offenen Rest; bleibt
///   nichts übrig und steht nichts im Board, wird er gelöscht. Eine
///   Produktion verliert nur die Zuordnung.
///
/// Menge und Tag einer Produktion im Board bleiben, wie sie sind. Ihre
/// Ware zählt danach für die übrigen Aufträge des Artikels oder fürs
/// Lager — ob sie noch gebraucht wird, entscheidet der Planer im Board.
///
/// Gerechnet wird mit dem Stand der Datenbank, nicht mit dem der
/// Konflikte: Was schon angepasst ist, wird nicht ein zweites Mal
/// abgezogen. Alles in einer Transaktion — scheitert etwas, bleibt die
/// Planung, wie sie war. Gibt zurück, bei wie vielen Konflikten sich
/// etwas geändert hat.
Future<int> passeAn(
  AppDatabase db,
  Iterable<PlanungsKonflikt> konflikte, {
  required DateTime heute,
}) async {
  final jeArtikel = <String, List<PlanungsKonflikt>>{};
  for (final k in konflikte) {
    jeArtikel.putIfAbsent(k.artikelnummer, () => []).add(k);
  }
  if (jeArtikel.isEmpty) return 0;

  var angepasst = 0;
  await db.transaction(() async {
    final grundlage = await _Grundlage.lade(db, heute);
    for (final e in jeArtikel.entries) {
      final stand = await _Arbeitsstand.lade(db, e.key, grundlage, heute);
      for (final k in e.value) {
        if (stand.wende(k)) angepasst++;
      }
      await stand.schreibe(db);
    }
  });
  return angepasst;
}

/// Was für alle Artikel gleich ist: Vormerkungen, die Ketten der
/// Planungsaufträge und die Produktionen im Board.
class _Grundlage {
  const _Grundlage({
    required this.vormerkungen,
    required this.planung,
    required this.zugaenge,
  });

  final Map<String, List<Vormerkung>> vormerkungen;
  final Map<String, BedarfsPlanung> planung;
  final Map<String, List<ProduktionsZugang>> zugaenge;

  static Future<_Grundlage> lade(AppDatabase db, DateTime heute) async {
    // Derselbe Berichtstag wie in der Ansicht: der Stand des Berichts,
    // ersatzweise der Tag des Einlesens.
    final kopf = await (db.select(db.auftragsbestandArtikel)..limit(1))
        .getSingleOrNull();
    final stand =
        kopf == null ? heute : (kopf.berichtStand ?? kopf.importiertAm);
    return _Grundlage(
      vormerkungen: await ladeVormerkungen(db),
      planung: await ladeBedarfsPlanung(db),
      zugaenge: await ladeProduktionsZugaenge(
        db,
        heute: heute,
        berichtTag: _tag(stand),
      ),
    );
  }
}

/// Ein Planungsauftrag mit Auftragszeilen, während er angepasst wird.
class _Bedarf {
  _Bedarf(
    this.zeile, {
    required this.geplantKg,
    required this.hatKetten,
    required this.rest,
  })  : vormerkung = rest.isNotEmpty,
        bezuege = AuftragsBezug.dekodiere(zeile.auftragsZeilen),
        menge = zeile.mengeKgFertig,
        termin = zeile.termin;

  final Demand zeile;

  /// Eingeplante Fertigmenge seiner Ketten im Board.
  final double geplantKg;

  /// Mindestens eine Kette im Board gehört zu ihm.
  final bool hatKetten;

  /// Offen und mit Zeilen, die noch keine Kette trägt — eine Vormerkung.
  final bool vormerkung;

  /// Je Zeile, was noch keine Kette trägt (nur bei einer Vormerkung).
  final Map<String, double> rest;

  List<AuftragsBezug> bezuege;
  double menge;
  DateTime? termin;
  bool geloescht = false;
  bool geaendert = false;

  /// Zieht [kg] vom offenen Rest der Zeile [schluessel] ab — die Menge des
  /// Auftrags sinkt mit.
  void kuerzeRest(String schluessel, double kg) {
    bezuege = _gekuerzt(bezuege, schluessel, kg);
    final r = (rest[schluessel] ?? 0) - kg;
    if (r < _schwelle) {
      rest.remove(schluessel);
    } else {
      rest[schluessel] = r;
    }
    menge = max(geplantKg, menge - kg);
    raeumeAuf();
    geaendert = true;
  }

  /// Ist von den Zeilen nichts mehr offen, bleibt vom Planungsauftrag nur,
  /// was schon im Board steht. Steht nichts im Board, wird er gelöscht.
  void raeumeAuf() {
    if (!vormerkung) return;
    final offen = rest.values.fold<double>(0, (s, kg) => s + kg);
    if (offen >= _schwelle) return;
    menge = geplantKg;
    if (!hatKetten) geloescht = true;
  }

  /// Die Beschreibung folgt den Zeilen — außer, jemand hat sie von Hand
  /// geändert.
  String? get notizen {
    final bisher = zeile.notizen;
    final automatisch = beschreibeBezuege(
      AuftragsBezug.dekodiere(zeile.auftragsZeilen),
    );
    if (bisher != null && bisher.trim().isNotEmpty && bisher != automatisch) {
      return bisher;
    }
    final neu = beschreibeBezuege(bezuege);
    return neu.isEmpty ? null : neu;
  }
}

/// Die Wurzel einer Kette mit Auftragszeilen, während sie angepasst wird.
class _Kette {
  _Kette(this.zeile, this.zugang)
      : bezuege = AuftragsBezug.dekodiere(zeile.auftragsZeilen);

  final ProductionTask zeile;

  /// Wie die Kette zum Auftragsbestand steht. null, wenn sie nicht
  /// mitzählt — im Board gelöscht oder lange vorbei.
  final ProduktionsZugang? zugang;

  List<AuftragsBezug> bezuege;
  bool geaendert = false;

  /// Lebt und steckt noch nicht im Lager des Berichts.
  bool get aktuell {
    final z = zugang;
    return z != null && z.art != ZugangsArt.imLager;
  }

  DateTime get fertigAm => zugang?.fertigAm ?? zeile.datum;
}

/// Planungsaufträge und Ketten eines Artikels, die Auftragszeilen tragen.
class _Arbeitsstand {
  _Arbeitsstand(this.bedarfe, this.ketten, this.heute);

  final Map<String, _Bedarf> bedarfe;
  final List<_Kette> ketten;
  final DateTime heute;

  static Future<_Arbeitsstand> lade(
    AppDatabase db,
    String artikelnummer,
    _Grundlage grundlage,
    DateTime heute,
  ) async {
    // Auch gelöschte Artikel: Ihre Aufträge zählen weiter, solange sie
    // im Board stehen.
    final produkte = await (db.select(db.products)
          ..where((p) => p.artikelnummer.equals(artikelnummer)))
        .get();
    final ids = [for (final p in produkte) p.id];
    if (ids.isEmpty) return _Arbeitsstand({}, [], heute);

    final bedarfe = await (db.select(db.demands)
          ..where((d) => d.productId.isIn(ids))
          ..where((d) => d.deletedAt.isNull())
          ..where((d) => d.auftragsZeilen.isNotNull()))
        .get();
    final rest = <String, Map<String, double>>{};
    for (final v
        in grundlage.vormerkungen[artikelnummer] ?? const <Vormerkung>[]) {
      final r = rest.putIfAbsent(v.bedarfId, () => {});
      for (final b in v.bezuege) {
        r[b.schluessel] = (r[b.schluessel] ?? 0) + b.kg;
      }
    }

    // Auch gelöschte Wurzeln: Eine Kette zählt, solange einer ihrer
    // Schritte lebt — die Zuordnung steht trotzdem an der Wurzel.
    final wurzeln = await (db.select(db.productionTasks)
          ..where((t) => t.productId.isIn(ids))
          ..where((t) => t.auftragsZeilen.isNotNull()))
        .get();
    final zugangJe = {
      for (final z
          in grundlage.zugaenge[artikelnummer] ?? const <ProduktionsZugang>[])
        z.kettenId: z,
    };

    return _Arbeitsstand(
      {
        for (final d in bedarfe)
          d.id: _Bedarf(
            d,
            geplantKg: grundlage.planung[d.id]?.kg ?? 0,
            hatKetten: grundlage.planung.containsKey(d.id),
            rest: rest[d.id] ?? {},
          ),
      },
      [for (final w in wurzeln) _Kette(w, zugangJe[w.id])],
      heute,
    );
  }

  /// Wendet den Vorschlag zu [k] an. true, wenn sich etwas geändert hat.
  bool wende(PlanungsKonflikt k) => switch (k.art) {
        PruefArt.verschoben => _verschiebe(k),
        PruefArt.weniger => verringere(k.schluessel, k.imBerichtKg),
        PruefArt.ausgeliefert || PruefArt.entfallen =>
          nimmHeraus(k.schluessel),
      };

  bool _verschiebe(PlanungsKonflikt k) {
    final neu = k.neuerWarenausgang;
    if (neu == null) return false;
    final umgehaengt = haengeUm(k.schluessel, neu);
    final verringert =
        verringere(auftragsZeilenSchluessel(k.beleg, neu), k.imBerichtKg);
    return umgehaengt || verringert;
  }

  /// Was an allen Zeilen [schluessel] verplant ist: offene Reste der
  /// Planungsaufträge und Zuordnungen der aktuellen Produktionen.
  double verplantKg(String schluessel) {
    var kg = 0.0;
    for (final b in bedarfe.values) {
      if (!b.geloescht) kg += b.rest[schluessel] ?? 0;
    }
    for (final k in ketten) {
      if (k.aktuell) kg += _kgFuer(k.bezuege, schluessel);
    }
    return kg;
  }

  /// Hängt alles, was an der Zeile [alt] hängt, an den Versandtag
  /// [neuerTag] desselben Belegs — in allen Planungsaufträgen und allen
  /// Ketten, damit Auftrag und Kette dieselbe Zeile meinen.
  bool haengeUm(String alt, DateTime neuerTag) {
    var geaendert = false;
    final vorschlag = vorschlagProduktionstag(neuerTag, heute);
    for (final b in bedarfe.values) {
      if (b.geloescht || !_hat(b.bezuege, alt)) continue;
      final neu = _neuerSchluessel(b.bezuege, alt, neuerTag);
      b.bezuege = _umgehaengt(b.bezuege, alt, neuerTag);
      final r = b.rest.remove(alt);
      if (r != null) b.rest[neu] = (b.rest[neu] ?? 0) + r;
      // Früher versandt heißt früher produziert. Später lässt den Termin
      // stehen: Zu früh fertig schadet nicht, zu spät schon.
      final termin = b.termin;
      if (termin != null && vorschlag.isBefore(termin)) b.termin = vorschlag;
      b.geaendert = true;
      geaendert = true;
    }
    for (final k in ketten) {
      if (!_hat(k.bezuege, alt)) continue;
      k.bezuege = _umgehaengt(k.bezuege, alt, neuerTag);
      k.geaendert = true;
      geaendert = true;
    }
    return geaendert;
  }

  /// Kürzt, was an der Zeile [schluessel] verplant ist, auf [bisKg]:
  /// zuerst die offenen Reste der Planungsaufträge — der späteste Termin
  /// zuerst —, dann die Zuordnungen der Produktionen — die zuletzt fertige
  /// zuerst.
  bool verringere(String schluessel, double bisKg) {
    var zuViel = verplantKg(schluessel) - bisKg;
    if (zuViel < _toleranz) return false;

    final vorgemerkt = [
      for (final b in bedarfe.values)
        if (!b.geloescht && (b.rest[schluessel] ?? 0) >= _schwelle) b,
    ]..sort((a, b) => _spaeterZuerst(a.termin, b.termin));
    for (final b in vorgemerkt) {
      if (zuViel < _schwelle) break;
      final kg = min(b.rest[schluessel] ?? 0.0, zuViel);
      b.kuerzeRest(schluessel, kg);
      zuViel -= kg;
    }

    final produktionen = [
      for (final k in ketten)
        if (k.aktuell && _kgFuer(k.bezuege, schluessel) >= _schwelle) k,
    ]..sort((a, b) => _spaeterZuerst(a.fertigAm, b.fertigAm));
    for (final k in produktionen) {
      if (zuViel < _schwelle) break;
      final kg = min(_kgFuer(k.bezuege, schluessel), zuViel);
      k.bezuege = _gekuerzt(k.bezuege, schluessel, kg);
      k.geaendert = true;
      // Der Planungsauftrag der Kette führt die Zeile mit. Dort ebenso
      // kürzen — sonst stünde der Teil als offener Rest wieder da.
      final eigner = bedarfe[k.zeile.bedarfId];
      if (eigner != null && !eigner.geloescht) {
        eigner.bezuege = _gekuerzt(eigner.bezuege, schluessel, kg);
        eigner.geaendert = true;
      }
      zuViel -= kg;
    }
    return true;
  }

  /// Nimmt die Zeile [schluessel] aus der Planung: aus allen
  /// Planungsaufträgen samt ihrem offenen Rest, aus den aktuellen
  /// Produktionen nur die Zuordnung. Was schon im Lager steckt, behält
  /// seine Zuordnung — das ist Geschichte.
  bool nimmHeraus(String schluessel) {
    var geaendert = false;
    for (final b in bedarfe.values) {
      if (b.geloescht || !_hat(b.bezuege, schluessel)) continue;
      final r = b.rest.remove(schluessel) ?? 0.0;
      b.bezuege = _ohne(b.bezuege, schluessel);
      if (b.vormerkung) {
        b.menge = max(b.geplantKg, b.menge - r);
        b.raeumeAuf();
      }
      b.geaendert = true;
      geaendert = true;
    }
    for (final k in ketten) {
      if (!k.aktuell || !_hat(k.bezuege, schluessel)) continue;
      k.bezuege = _ohne(k.bezuege, schluessel);
      k.geaendert = true;
      geaendert = true;
    }
    return geaendert;
  }

  Future<void> schreibe(AppDatabase db) async {
    final jetzt = DateTime.now();
    for (final b in bedarfe.values) {
      if (!b.geaendert) continue;
      await (db.update(db.demands)..where((d) => d.id.equals(b.zeile.id)))
          .write(
        DemandsCompanion(
          mengeKgFertig: Value(b.menge),
          termin: Value(b.termin),
          notizen: Value(b.notizen),
          auftragsZeilen: Value(AuftragsBezug.kodiere(b.bezuege)),
          deletedAt: b.geloescht ? Value(jetzt) : const Value.absent(),
          updatedAt: Value(jetzt),
        ),
      );
    }
    for (final k in ketten) {
      if (!k.geaendert) continue;
      await (db.update(db.productionTasks)
            ..where((t) => t.id.equals(k.zeile.id)))
          .write(
        ProductionTasksCompanion(
          auftragsZeilen: Value(AuftragsBezug.kodiere(k.bezuege)),
          updatedAt: Value(jetzt),
        ),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Hilfen
// ═══════════════════════════════════════════════════════════════════════════

/// Unter 5 g ist Rundung.
const double _schwelle = 0.005;

/// Erst ab 10 g zu viel verplant ist es ein Konflikt.
const double _toleranz = 0.01;

DateTime _tag(DateTime d) => DateTime(d.year, d.month, d.day);

/// Sortierung: der spätere Tag zuerst, ohne Tag ganz hinten.
int _spaeterZuerst(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

bool _hat(List<AuftragsBezug> bezuege, String schluessel) =>
    bezuege.any((b) => b.schluessel == schluessel);

double _kgFuer(List<AuftragsBezug> bezuege, String schluessel) => bezuege
    .where((b) => b.schluessel == schluessel)
    .fold<double>(0, (s, b) => s + b.kg);

List<AuftragsBezug> _ohne(List<AuftragsBezug> bezuege, String schluessel) =>
    [
      for (final b in bezuege)
        if (b.schluessel != schluessel) b,
    ];

/// Zieht [kg] von den Einträgen der Zeile [schluessel] ab; was unter die
/// Rundung fällt, entfällt.
List<AuftragsBezug> _gekuerzt(
  List<AuftragsBezug> bezuege,
  String schluessel,
  double kg,
) {
  var abzug = kg;
  final ergebnis = <AuftragsBezug>[];
  for (final b in bezuege) {
    if (b.schluessel != schluessel || abzug <= 0) {
      ergebnis.add(b);
      continue;
    }
    final weg = min(b.kg, abzug);
    abzug -= weg;
    final rest = b.kg - weg;
    if (rest < _schwelle) continue;
    ergebnis.add(
      AuftragsBezug(
        beleg: b.beleg,
        warenausgang: b.warenausgang,
        kg: rest,
        debitor: b.debitor,
      ),
    );
  }
  return ergebnis;
}

/// Der Schlüssel, den die Zeile [alt] am Tag [neuerTag] hat.
String _neuerSchluessel(
  List<AuftragsBezug> bezuege,
  String alt,
  DateTime neuerTag,
) {
  final b = bezuege.firstWhere((b) => b.schluessel == alt);
  return auftragsZeilenSchluessel(b.beleg, neuerTag);
}

/// Setzt die Einträge der Zeile [alt] auf den Tag [neuerTag]. Gab es die
/// Zeile am neuen Tag schon, werden beide zu einem Eintrag.
List<AuftragsBezug> _umgehaengt(
  List<AuftragsBezug> bezuege,
  String alt,
  DateTime neuerTag,
) {
  final ergebnis = <AuftragsBezug>[];
  final stelle = <String, int>{};
  for (final b in bezuege) {
    final neu = b.schluessel == alt
        ? AuftragsBezug(
            beleg: b.beleg,
            warenausgang: neuerTag,
            kg: b.kg,
            debitor: b.debitor,
          )
        : b;
    final i = stelle[neu.schluessel];
    if (i == null) {
      stelle[neu.schluessel] = ergebnis.length;
      ergebnis.add(neu);
    } else {
      final da = ergebnis[i];
      ergebnis[i] = AuftragsBezug(
        beleg: da.beleg,
        warenausgang: da.warenausgang,
        kg: da.kg + neu.kg,
        debitor: da.debitor,
      );
    }
  }
  return ergebnis;
}
