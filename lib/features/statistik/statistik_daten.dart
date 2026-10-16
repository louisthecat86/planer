import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/constants/product_groups.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/erledigt_service.dart' show Erledigt;
import '../../core/utils/datum.dart';
import '../../core/utils/format.dart';
import '../../core/utils/kalenderwoche.dart';
import '../articles/artikel_luecken.dart';
import '../board/board_providers.dart'
    show
        BoardSpur,
        CapacityStatus,
        SpurTagBelegung,
        belegungImZeitraum,
        kartenImZeitraum;
import '../whiteboard/whiteboard_provider.dart'
    show leistungsdatenVon, produktionsMinutenVon, verlustAnteilVon;

// Die Zahlen hinter der Statistik-Seite.
//
// Drei Quellen, je nach Frage:
//  • Auslastung und Zeit stammen aus der Planung im Board — Woche für Woche
//    so, wie das Board sie zeigt ([belegungImZeitraum]), mit der heutigen
//    Kapazität. Die Planerfüllung zählt die Karten des Boards
//    ([kartenImZeitraum]) — erledigt, wie das Board es anzeigt.
//  • Ausbeute, Verlust, Leistung und Produktmix stammen aus den erfassten
//    Produktionen — dem, was wirklich herauskam.
//  • Die Stammdaten-Pflege zählt die Lücken aller Artikel — nach denselben
//    Regeln wie die Artikelliste ([artikelLuecken]).
//
// Die Auswertungen sind reine Funktionen über diesen Daten. Der
// Abteilungsfilter wirkt erst hier: Ihn umzuschalten lädt nichts neu.

// ---------------------------------------------------------------------------
// Zeitraum
// ---------------------------------------------------------------------------

/// Zeiträume der Statistik — jeweils bis einschließlich der laufenden
/// Woche.
enum StatistikZeitraum {
  vierWochen('4 Wochen', 4),
  quartal('Quartal', 13),
  zwoelfMonate('12 Monate', 52),
  alles('Alles', null);

  const StatistikZeitraum(this.label, this.wochen);

  final String label;

  /// Anzahl der Wochen bis einschließlich der laufenden — null: so weit
  /// zurück, wie Daten da sind.
  final int? wochen;
}

/// Wie fein die Verläufe unterteilt sind.
enum StatistikRaster { woche, monat }

/// Bis zu so vielen Wochen zeigen die Verläufe Wochen, darüber Monate.
const int kWochenRasterBis = 13;

/// So weit reicht „Alles" höchstens zurück: zehn Jahre.
const int kWochenHoechstens = 520;

const List<String> _monateKurz = [
  'Jan',
  'Feb',
  'Mär',
  'Apr',
  'Mai',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Okt',
  'Nov',
  'Dez',
];

/// Montag der Woche von [d], 00:00 Uhr.
DateTime _montagVon(DateTime d) => tagPlus(d, -(d.weekday - 1));

/// Kalendertage von [a] bis [b] — in UTC gerechnet, damit die
/// Zeitumstellung keinen Tag verschluckt.
int _tageZwischen(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

/// Der ausgewertete Zeitraum: ganze Wochen ab Montag [von] bis vor Montag
/// [bisExkl].
class StatistikSpanne {
  const StatistikSpanne({
    required this.zeitraum,
    required this.von,
    required this.bisExkl,
  });

  /// Der Zeitraum für [zeitraum], von [heute] aus gesehen. Bei
  /// [StatistikZeitraum.alles] beginnt er in der Woche von [fruehestes].
  factory StatistikSpanne.fuer(
    StatistikZeitraum zeitraum,
    DateTime heute, {
    DateTime? fruehestes,
  }) {
    final dieseWoche = _montagVon(heute);
    final wochen = zeitraum.wochen;
    var von = wochen != null
        ? tagPlus(dieseWoche, -7 * (wochen - 1))
        : _montagVon(fruehestes ?? heute);
    if (von.isAfter(dieseWoche)) von = dieseWoche;
    // Höchstens zehn Jahre: Ein Tippfehler im Datum einer eingelesenen
    // Produktion („1926") soll die Seite nicht hundert Jahre rechnen lassen.
    final grenze = tagPlus(dieseWoche, -7 * kWochenHoechstens);
    if (von.isBefore(grenze)) von = grenze;
    return StatistikSpanne(
      zeitraum: zeitraum,
      von: von,
      bisExkl: tagPlus(dieseWoche, 7),
    );
  }

  final StatistikZeitraum zeitraum;

  /// Montag der ersten Woche, 00:00 Uhr.
  final DateTime von;

  /// Montag nach der letzten Woche, 00:00 Uhr.
  final DateTime bisExkl;

  /// Anzahl der Wochen.
  int get wochen => _tageZwischen(von, bisExkl) ~/ 7;

  StatistikRaster get raster => wochen <= kWochenRasterBis
      ? StatistikRaster.woche
      : StatistikRaster.monat;

  bool enthaelt(DateTime tag) => !tag.isBefore(von) && tag.isBefore(bisExkl);

  /// Beginn des Abschnitts (Woche oder Monat), in den [tag] fällt.
  DateTime abschnittVon(DateTime tag) => raster == StatistikRaster.woche
      ? _montagVon(tag)
      : DateTime(tag.year, tag.month);

  /// Alle Abschnitte des Zeitraums, der Reihe nach.
  List<DateTime> get abschnitte {
    final liste = <DateTime>[];
    var a = abschnittVon(von);
    while (a.isBefore(bisExkl)) {
      liste.add(a);
      a = raster == StatistikRaster.woche
          ? tagPlus(a, 7)
          : DateTime(a.year, a.month + 1);
    }
    return liste;
  }

  /// „KW 42" bzw. „Okt 26" — für die Achse.
  String kurzname(DateTime abschnitt) => raster == StatistikRaster.woche
      ? 'KW ${isoKalenderwoche(abschnitt)}'
      : '${_monateKurz[abschnitt.month - 1]} '
          '${(abschnitt.year % 100).toString().padLeft(2, '0')}';

  /// „KW 42/2026 · 12.10.–16.10." bzw. „Oktober 2026" — für den Tooltip.
  String langname(DateTime abschnitt) => raster == StatistikRaster.woche
      ? 'KW ${isoKalenderwoche(abschnitt)}/${isoKalenderjahr(abschnitt)} · '
          '${Format.datumKurz(abschnitt)}–'
          '${Format.datumKurz(tagPlus(abschnitt, 4))}'
      : '${Format.monate[abschnitt.month - 1]} ${abschnitt.year}';

  /// „20.07.2026 – 18.10.2026"
  String get beschreibung =>
      '${Format.datum(von)} – ${Format.datum(tagPlus(bisExkl, -1))}';

  /// „je Woche" bzw. „je Monat".
  String get rasterText =>
      raster == StatistikRaster.woche ? 'je Woche' : 'je Monat';

  /// Der Zeitraum für den Verlauf eines Teils: bei „Alles" erst ab der
  /// Woche von [erster] — mit eigenem Raster —, sonst unverändert.
  ///
  /// „Alles" beginnt mit den ältesten Daten überhaupt, meist der
  /// eingelesenen Historie. Die Planung setzt oft viel später ein; ihr
  /// Verlauf stünde sonst in Monaten, von denen nur der letzte Daten hat.
  StatistikSpanne abDatenbeginn(DateTime? erster) {
    if (zeitraum != StatistikZeitraum.alles || erster == null) return this;
    final start = _montagVon(erster);
    if (!start.isAfter(von) || !start.isBefore(bisExkl)) return this;
    return StatistikSpanne(zeitraum: zeitraum, von: start, bisExkl: bisExkl);
  }
}

// ---------------------------------------------------------------------------
// Spuren: Reihenfolge und Namen wie im Board
// ---------------------------------------------------------------------------

/// Sortiert wie das Board: Abteilungen in Produktionsfolge, darin die
/// Anlagen nach Namen und die Sammelspur zuletzt.
int _spurVergleich(BoardSpur a, BoardSpur b) {
  final abt = a.abteilung.index.compareTo(b.abteilung.index);
  if (abt != 0) return abt;
  if (a.istAnlage != b.istAnlage) return a.istAnlage ? -1 : 1;
  return (a.maschineName ?? '').compareTo(b.maschineName ?? '');
}

/// Name einer Spur wie im Board: die Anlage, „Ohne Anlage" für die
/// Sammelspur einer Abteilung mit Anlagen, sonst die Abteilung.
String spurName(BoardSpur spur, {required bool abteilungHatAnlagen}) {
  if (spur.istAnlage) return spur.maschineName ?? spur.abteilung.anzeigeName;
  return abteilungHatAnlagen ? 'Ohne Anlage' : spur.abteilung.anzeigeName;
}

Set<Abteilung> _abteilungenMitAnlagen(List<SpurTagBelegung> belegung) => {
      for (final b in belegung)
        if (b.spur.istAnlage) b.spur.abteilung,
    };

/// Ampel wie im Board: überbucht über der Kapazität, gut gefüllt ab 75 %.
CapacityStatus auslastungsStatus(double belegtMinuten, double kapazitaet) {
  if (belegtMinuten > kapazitaet) return CapacityStatus.ueberbucht;
  if (kapazitaet > 0 && belegtMinuten / kapazitaet >= 0.75) {
    return CapacityStatus.gut;
  }
  return CapacityStatus.frei;
}

// ---------------------------------------------------------------------------
// Teil 1: Auslastung und Engpässe
// ---------------------------------------------------------------------------

/// Eine Zeile der Auslastung: eine Abteilung — oder mit Abteilungsfilter
/// eine Spur dieser Abteilung.
class AuslastungsZeile {
  const AuslastungsZeile({
    required this.abteilung,
    required this.name,
    required this.belegtMinuten,
    required this.kapazitaetMinuten,
    required this.ueberbuchteTage,
    this.spur,
  });

  final Abteilung abteilung;
  final String name;

  /// Die Spur — null, wenn die Zeile eine ganze Abteilung zusammenfasst.
  final BoardSpur? spur;

  /// Summen über die Planungstage des Zeitraums.
  final double belegtMinuten;
  final double kapazitaetMinuten;

  /// Tage, an denen mindestens eine Spur der Zeile überbucht war.
  final int ueberbuchteTage;

  double get auslastung =>
      kapazitaetMinuten > 0 ? belegtMinuten / kapazitaetMinuten : 0;

  CapacityStatus get status =>
      auslastungsStatus(belegtMinuten, kapazitaetMinuten);
}

/// Die Auslastung in einem Abschnitt des Verlaufs.
class AuslastungsPunkt {
  const AuslastungsPunkt({
    required this.abschnitt,
    required this.belegtMinuten,
    required this.kapazitaetMinuten,
    required this.tage,
    required this.ueberbuchteTage,
  });

  final DateTime abschnitt;
  final double belegtMinuten;
  final double kapazitaetMinuten;

  /// Planungstage im Abschnitt.
  final int tage;
  final int ueberbuchteTage;

  bool get hatDaten => tage > 0 && kapazitaetMinuten > 0;

  double get auslastung =>
      kapazitaetMinuten > 0 ? belegtMinuten / kapazitaetMinuten : 0;

  CapacityStatus get status =>
      auslastungsStatus(belegtMinuten, kapazitaetMinuten);
}

class AuslastungsAuswertung {
  const AuslastungsAuswertung({
    required this.zeilen,
    required this.verlauf,
    required this.verlaufSpanne,
    required this.planungstage,
    required this.geplanteWochen,
    required this.ueberbuchteTage,
  });

  /// In der Reihenfolge des Boards.
  final List<AuslastungsZeile> zeilen;
  final List<AuslastungsPunkt> verlauf;

  /// Zeitraum und Raster des Verlaufs — bei „Alles" ab der ersten Planung.
  final StatistikSpanne verlaufSpanne;

  /// Abschnitte des Verlaufs mit Daten — ein Verlauf braucht zwei.
  int get verlaufPunkte => verlauf.where((p) => p.hatDaten).length;

  /// Werktage, an denen irgendwo etwas geplant war — nur sie zählen.
  final int planungstage;

  /// Wochen mit mindestens einem Planungstag.
  final int geplanteWochen;

  /// Planungstage mit mindestens einer überbuchten Spur.
  final int ueberbuchteTage;

  bool get leer => planungstage == 0;

  double get belegtMinuten =>
      zeilen.fold(0.0, (summe, z) => summe + z.belegtMinuten);

  double get kapazitaetMinuten =>
      zeilen.fold(0.0, (summe, z) => summe + z.kapazitaetMinuten);

  double get auslastung =>
      kapazitaetMinuten > 0 ? belegtMinuten / kapazitaetMinuten : 0;

  /// Die am stärksten ausgelastete Zeile — erst ab zwei Zeilen eine
  /// Aussage.
  AuslastungsZeile? get engpass {
    final kandidaten = [
      for (final z in zeilen)
        if (z.kapazitaetMinuten > 0) z,
    ];
    if (kandidaten.length < 2) return null;
    return kandidaten.reduce((a, b) => b.auslastung > a.auslastung ? b : a);
  }
}

class _Summen {
  double belegt = 0;
  double kapazitaet = 0;
  final Set<DateTime> tage = {};
  final Set<DateTime> ueberbucht = {};

  void addiere(SpurTagBelegung b) {
    belegt += b.belegtMinuten;
    kapazitaet += b.kapazitaetMinuten;
    tage.add(b.tag);
    if (b.ueberbucht) ueberbucht.add(b.tag);
  }
}

/// Werktage, an denen in irgendeiner Spur etwas geplant war. Tage ohne
/// jede Planung — Feiertage, Betriebsruhe, Wochen vor der App — zählen
/// nicht: Sie würden die Auslastung aller Abteilungen nach unten ziehen.
Set<DateTime> planungstage(List<SpurTagBelegung> belegung) => {
      for (final b in belegung)
        if (b.belegtMinuten > 0) b.tag,
    };

/// Auslastung je Abteilung — mit [abteilung] je Spur dieser Abteilung —
/// und ihr Verlauf über den Zeitraum.
AuslastungsAuswertung werteAuslastungAus(
  List<SpurTagBelegung> belegung,
  StatistikSpanne spanne, {
  Abteilung? abteilung,
}) {
  final tage = planungstage(belegung);
  final mitAnlagen = _abteilungenMitAnlagen(belegung);
  DateTime? ersterTag;
  for (final t in tage) {
    if (ersterTag == null || t.isBefore(ersterTag)) ersterTag = t;
  }
  final verlaufSpanne = spanne.abDatenbeginn(ersterTag);

  final zeilen = <String, (BoardSpur, _Summen)>{};
  final jeAbschnitt = <DateTime, _Summen>{};
  final ueberbucht = <DateTime>{};
  for (final b in belegung) {
    if (!tage.contains(b.tag)) continue;
    if (abteilung != null && b.spur.abteilung != abteilung) continue;
    final key = abteilung == null ? b.spur.abteilung.dbValue : b.spur.id;
    zeilen.putIfAbsent(key, () => (b.spur, _Summen())).$2.addiere(b);
    jeAbschnitt
        .putIfAbsent(verlaufSpanne.abschnittVon(b.tag), _Summen.new)
        .addiere(b);
    if (b.ueberbucht) ueberbucht.add(b.tag);
  }

  final sortiert = zeilen.values.toList()
    ..sort((a, b) {
      if (abteilung != null) return _spurVergleich(a.$1, b.$1);
      return a.$1.abteilung.index.compareTo(b.$1.abteilung.index);
    });

  final verlauf = [
    for (final a in verlaufSpanne.abschnitte)
      AuslastungsPunkt(
        abschnitt: a,
        belegtMinuten: jeAbschnitt[a]?.belegt ?? 0,
        kapazitaetMinuten: jeAbschnitt[a]?.kapazitaet ?? 0,
        tage: jeAbschnitt[a]?.tage.length ?? 0,
        ueberbuchteTage: jeAbschnitt[a]?.ueberbucht.length ?? 0,
      ),
  ];

  return AuslastungsAuswertung(
    zeilen: [
      for (final (spur, summen) in sortiert)
        AuslastungsZeile(
          abteilung: spur.abteilung,
          spur: abteilung == null ? null : spur,
          name: abteilung == null
              ? spur.abteilung.anzeigeName
              : spurName(
                  spur,
                  abteilungHatAnlagen: mitAnlagen.contains(spur.abteilung),
                ),
          belegtMinuten: summen.belegt,
          kapazitaetMinuten: summen.kapazitaet,
          ueberbuchteTage: summen.ueberbucht.length,
        ),
    ],
    verlauf: verlauf,
    verlaufSpanne: verlaufSpanne,
    planungstage: tage.length,
    geplanteWochen: {for (final t in tage) _montagVon(t)}.length,
    ueberbuchteTage: ueberbucht.length,
  );
}

// ---------------------------------------------------------------------------
// Teil 2: Wohin die Zeit geht
// ---------------------------------------------------------------------------

/// Belegte Zeit nach Art, in Minuten.
class ZeitAnteile {
  const ZeitAnteile({
    this.produktion = 0,
    this.ruesten = 0,
    this.reinigen = 0,
    this.sonstiges = 0,
  });

  final double produktion;
  final double ruesten;
  final double reinigen;
  final double sonstiges;

  /// Alle Nebenzeiten zusammen.
  double get neben => ruesten + reinigen + sonstiges;

  double get summe => produktion + neben;

  ZeitAnteile plus(SpurTagBelegung b) => ZeitAnteile(
        produktion: produktion + b.produktionsMinuten,
        ruesten: ruesten + (b.zusatzMinuten['ruesten'] ?? 0),
        reinigen: reinigen + (b.zusatzMinuten['reinigen'] ?? 0),
        sonstiges: sonstiges + (b.zusatzMinuten['sonstiges'] ?? 0),
      );
}

/// Die Zeit einer Spur.
class ZeitZeile {
  const ZeitZeile({
    required this.spur,
    required this.name,
    required this.anteile,
  });

  final BoardSpur spur;
  final String name;
  final ZeitAnteile anteile;
}

class ZeitAuswertung {
  const ZeitAuswertung({required this.gesamt, required this.jeSpur});

  final ZeitAnteile gesamt;

  /// Spuren mit belegter Zeit, in der Reihenfolge des Boards.
  final List<ZeitZeile> jeSpur;
}

/// Wofür die geplante Zeit verwendet wird — insgesamt und je Spur.
ZeitAuswertung werteZeitAus(
  List<SpurTagBelegung> belegung, {
  Abteilung? abteilung,
}) {
  final mitAnlagen = _abteilungenMitAnlagen(belegung);
  var gesamt = const ZeitAnteile();
  final jeSpur = <String, (BoardSpur, ZeitAnteile)>{};
  for (final b in belegung) {
    if (abteilung != null && b.spur.abteilung != abteilung) continue;
    if (b.belegtMinuten <= 0) continue;
    gesamt = gesamt.plus(b);
    final bisher = jeSpur[b.spur.id];
    jeSpur[b.spur.id] = (b.spur, (bisher?.$2 ?? const ZeitAnteile()).plus(b));
  }
  final sortiert = jeSpur.values.toList()
    ..sort((a, b) => _spurVergleich(a.$1, b.$1));
  return ZeitAuswertung(
    gesamt: gesamt,
    jeSpur: [
      for (final (spur, anteile) in sortiert)
        ZeitZeile(
          spur: spur,
          name: spurName(
            spur,
            abteilungHatAnlagen: mitAnlagen.contains(spur.abteilung),
          ),
          anteile: anteile,
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Erfasste Produktionen
// ---------------------------------------------------------------------------

/// Ein Artikel, wie die Statistik ihn braucht.
class StatistikArtikel {
  const StatistikArtikel({
    required this.id,
    required this.artikelnummer,
    required this.bezeichnung,
    this.produktgruppe,
    this.abteilungen = const {},
    this.luecken = const {},
    this.leistungKgH,
  });

  final String id;
  final String artikelnummer;
  final String bezeichnung;

  /// Produktgruppe als dbValue — null: keine.
  final String? produktgruppe;

  /// Abteilungen seiner Prozessschritte (dbValues).
  final Set<String> abteilungen;

  /// Was dem Artikel für die Planung fehlt — wie in der Artikelliste.
  final Set<ArtikelLuecke> luecken;

  /// Hinterlegte Leistung der Bratstraße in kg Rohware je Stunde — null:
  /// keine Leistungsdaten.
  final double? leistungKgH;
}

/// Eine erfasste Produktion.
class ErfassteProduktion {
  const ErfassteProduktion({
    required this.productId,
    required this.datum,
    this.kgRohware,
    this.kgFertigware,
    this.verlust,
    this.ausbeuteAngegeben = false,
    this.minuten,
  });

  factory ErfassteProduktion.aus(ProductionHistoryData h) {
    final roh = h.kgRohware;
    return ErfassteProduktion(
      productId: h.productId,
      datum: tagOhneZeit(h.datum),
      kgRohware: roh,
      kgFertigware: h.kgFertigware,
      verlust: verlustAnteilVon(h),
      ausbeuteAngegeben: h.verlustAnteil != null ||
          (roh != null && roh > 0 && h.kgFertigware != null),
      minuten: roh != null && roh.isFinite && roh > 0
          ? produktionsMinutenVon(h, roh)
          : null,
    );
  }

  final String productId;
  final DateTime datum;
  final double? kgRohware;
  final double? kgFertigware;

  /// Verlustanteil 0…1 nach derselben Regel wie die Planung
  /// ([verlustAnteilVon]) — null: unbekannt oder nicht plausibel.
  final double? verlust;

  /// Ob ein Verlust oder Roh- und Fertigware eingetragen sind. Zusammen
  /// mit [verlust] == null heißt das: eingetragen, aber nicht plausibel.
  final bool ausbeuteAngegeben;

  /// Produktionszeit in Minuten nach derselben Regel wie die Planung
  /// ([produktionsMinutenVon]) — null: keine Zeit erfasst.
  final double? minuten;

  /// kg Rohware je Stunde — null ohne Rohware oder Zeit.
  double? get kgProStunde {
    final kg = kgRohware;
    final m = minuten;
    if (kg == null || m == null || m <= 0) return null;
    return kg / m * 60;
  }
}

/// Eine Karte im Board — für die Planerfüllung.
class PlanKarte {
  const PlanKarte({
    required this.productId,
    required this.abteilung,
    required this.datum,
    this.erledigt,
  });

  final String productId;
  final Abteilung abteilung;

  /// Tag der Karte, 00:00 Uhr.
  final DateTime datum;

  /// Erfasst, abgehakt — oder null: offen.
  final Erledigt? erledigt;
}

bool _imFilter(
  ErfassteProduktion p,
  Map<String, StatistikArtikel> artikel,
  StatistikSpanne spanne,
  Abteilung? abteilung,
) {
  if (!spanne.enthaelt(p.datum)) return false;
  final a = artikel[p.productId];
  if (a == null) return false;
  return abteilung == null || a.abteilungen.contains(abteilung.dbValue);
}

// ---------------------------------------------------------------------------
// Teil 3: Ausbeute und Verlust
// ---------------------------------------------------------------------------

/// Ab so vielen Produktionen im Zeitraum zeigt die Statistik die Spanne
/// eines Artikels — bei weniger sagt sie nichts.
const int kSpanneAbProduktionen = 3;

/// So viele Artikel zeigt die Liste der größten Schwankungen.
const int kSpannenAnzahl = 10;

/// Schlechteste, mittlere und beste Ausbeute eines Artikels.
class AusbeuteSpanne {
  const AusbeuteSpanne({
    required this.artikel,
    required this.min,
    required this.mittel,
    required this.max,
    required this.anzahl,
  });

  final StatistikArtikel artikel;

  /// Ausbeute (1 − Verlust), jeweils 0…1.
  final double min;
  final double mittel;
  final double max;

  /// Produktionen, aus denen die Werte stammen.
  final int anzahl;

  double get spanne => max - min;
}

/// Der Verlust in einem Abschnitt des Verlaufs.
class VerlustPunkt {
  const VerlustPunkt({
    required this.abschnitt,
    required this.anzahl,
    required this.mittlererVerlust,
    required this.verlustKg,
  });

  final DateTime abschnitt;

  /// Produktionen mit gültiger Ausbeute.
  final int anzahl;

  /// Ø Verlust je Produktion (0…1) — null ohne Produktion.
  final double? mittlererVerlust;

  final double verlustKg;

  bool get hatDaten => anzahl > 0;
}

class AusbeuteAuswertung {
  const AusbeuteAuswertung({
    required this.produktionen,
    required this.gueltig,
    required this.unplausibel,
    required this.ohneAusbeute,
    required this.mittlererVerlust,
    required this.verlustKg,
    required this.verlauf,
    required this.verlaufSpanne,
    required this.spannen,
  });

  /// Erfasste Produktionen im Zeitraum (und im Filter).
  final int produktionen;

  /// Davon mit plausibler Ausbeute — nur sie zählen.
  final int gueltig;

  /// Eingetragen, aber nicht plausibel: Ausbeute von 100 % und mehr oder
  /// voller Verlust — meist ein Tippfehler.
  final int unplausibel;

  /// Ohne Fertigware: Ausbeute unbekannt.
  final int ohneAusbeute;

  /// Ø Verlust je Produktion (0…1) — wie die Planung mittelt. null ohne
  /// gültige Produktion.
  final double? mittlererVerlust;

  /// Verlust in kg: Rohware minus Fertigware.
  final double verlustKg;

  final List<VerlustPunkt> verlauf;

  /// Zeitraum und Raster des Verlaufs — bei „Alles" ab der ersten
  /// Produktion.
  final StatistikSpanne verlaufSpanne;

  /// Abschnitte des Verlaufs mit Daten — ein Verlauf braucht zwei.
  int get verlaufPunkte => verlauf.where((p) => p.hatDaten).length;

  /// Die Artikel mit der größten Spanne, größte zuerst.
  final List<AusbeuteSpanne> spannen;

  double? get mittlereAusbeute {
    final v = mittlererVerlust;
    return v == null ? null : 1 - v;
  }
}

class _VerlustSumme {
  int anzahl = 0;
  double summe = 0;
  double kg = 0;
}

/// Ausbeute und Verlust der erfassten Produktionen im Zeitraum. Mit
/// [abteilung] nur Artikel, die einen Schritt in dieser Abteilung haben.
AusbeuteAuswertung werteAusbeuteAus(
  List<ErfassteProduktion> produktionen,
  Map<String, StatistikArtikel> artikel,
  StatistikSpanne spanne, {
  Abteilung? abteilung,
}) {
  var anzahl = 0;
  var unplausibel = 0;
  var ohneAusbeute = 0;
  var verlustSumme = 0.0;
  var verlustKg = 0.0;
  final jeArtikel = <String, List<double>>{};
  // Die gültigen Produktionen: Tag, Verlustanteil, Verlust in kg.
  final gueltige = <(DateTime, double, double)>[];
  DateTime? ersterTag;

  for (final p in produktionen) {
    if (!_imFilter(p, artikel, spanne, abteilung)) continue;
    anzahl++;
    final v = p.verlust;
    if (v == null) {
      if (p.ausbeuteAngegeben) {
        unplausibel++;
      } else {
        ohneAusbeute++;
      }
      continue;
    }
    verlustSumme += v;
    final roh = p.kgRohware;
    final fertig = p.kgFertigware;
    final kg = roh != null && fertig != null && fertig > 0 && fertig < roh
        ? roh - fertig
        : 0.0;
    verlustKg += kg;
    gueltige.add((p.datum, v, kg));
    if (ersterTag == null || p.datum.isBefore(ersterTag)) ersterTag = p.datum;
    (jeArtikel[p.productId] ??= []).add(1 - v);
  }
  final gueltig = gueltige.length;

  final verlaufSpanne = spanne.abDatenbeginn(ersterTag);
  final jeAbschnitt = <DateTime, _VerlustSumme>{};
  for (final (tag, v, kg) in gueltige) {
    final summe = jeAbschnitt.putIfAbsent(
      verlaufSpanne.abschnittVon(tag),
      _VerlustSumme.new,
    );
    summe.anzahl++;
    summe.summe += v;
    summe.kg += kg;
  }

  final verlauf = [
    for (final a in verlaufSpanne.abschnitte)
      VerlustPunkt(
        abschnitt: a,
        anzahl: jeAbschnitt[a]?.anzahl ?? 0,
        mittlererVerlust: switch (jeAbschnitt[a]) {
          final s? when s.anzahl > 0 => s.summe / s.anzahl,
          _ => null,
        },
        verlustKg: jeAbschnitt[a]?.kg ?? 0,
      ),
  ];

  final spannen = <AusbeuteSpanne>[];
  for (final MapEntry(key: id, value: werte) in jeArtikel.entries) {
    final a = artikel[id];
    if (a == null || werte.length < kSpanneAbProduktionen) continue;
    var min = werte.first;
    var max = werte.first;
    var summe = 0.0;
    for (final w in werte) {
      if (w < min) min = w;
      if (w > max) max = w;
      summe += w;
    }
    spannen.add(
      AusbeuteSpanne(
        artikel: a,
        min: min,
        mittel: summe / werte.length,
        max: max,
        anzahl: werte.length,
      ),
    );
  }
  spannen.sort((a, b) {
    final s = b.spanne.compareTo(a.spanne);
    return s != 0 ? s : a.artikel.artikelnummer.compareTo(b.artikel.artikelnummer);
  });

  return AusbeuteAuswertung(
    produktionen: anzahl,
    gueltig: gueltig,
    unplausibel: unplausibel,
    ohneAusbeute: ohneAusbeute,
    mittlererVerlust: gueltig > 0 ? verlustSumme / gueltig : null,
    verlustKg: verlustKg,
    verlauf: verlauf,
    verlaufSpanne: verlaufSpanne,
    spannen: spannen.take(kSpannenAnzahl).toList(),
  );
}

// ---------------------------------------------------------------------------
// Teil 4: Leistung
// ---------------------------------------------------------------------------

/// Ab so vielen Produktionen mit Zeit vergleicht die Statistik einen
/// Artikel mit seinen Leistungsdaten — wie bei der Spanne der Ausbeute.
const int kLeistungVergleichAb = kSpanneAbProduktionen;

/// Ab so viel Abweichung von den Leistungsdaten gilt ein Artikel als
/// abweichend: 20 %.
const double kLeistungAbweichungAb = 0.2;

/// So viele Artikel zeigen die Listen der Leistung.
const int kLeistungAnzahl = 10;

/// Was ein Artikel im Zeitraum geschafft hat — aus seinen Produktionen mit
/// Rohware und Zeit.
class ArtikelLeistung {
  const ArtikelLeistung({
    required this.artikel,
    required this.kg,
    required this.minuten,
    required this.langsamste,
    required this.schnellste,
    required this.anzahl,
  });

  final StatistikArtikel artikel;

  /// Rohware und Produktionszeit zusammen.
  final double kg;
  final double minuten;

  /// kg/h der langsamsten und der schnellsten Produktion.
  final double langsamste;
  final double schnellste;

  /// Produktionen mit Zeit.
  final int anzahl;

  /// Ø kg Rohware je Stunde: alle Rohware durch alle Zeit — so mittelt
  /// auch die Planung.
  double get kgProStunde => minuten > 0 ? kg / minuten * 60 : 0;

  /// Hinterlegte Leistung der Bratstraße — null: keine.
  double? get hinterlegt => artikel.leistungKgH;

  /// Abweichung der gemessenen von der hinterlegten Leistung: +0,25 heißt
  /// ein Viertel schneller, −0,25 ein Viertel langsamer. null ohne
  /// Leistungsdaten.
  double? get abweichung {
    final h = hinterlegt;
    if (h == null || !(h > 0)) return null;
    return kgProStunde / h - 1;
  }

  /// Ob genug Produktionen da sind, um mit den Leistungsdaten zu
  /// vergleichen — und es Leistungsdaten gibt.
  bool get vergleichbar => anzahl >= kLeistungVergleichAb && abweichung != null;
}

class LeistungsAuswertung {
  const LeistungsAuswertung({
    required this.produktionen,
    required this.mitZeit,
    required this.kg,
    required this.minuten,
    required this.zeitverbraucher,
    required this.abweichungen,
    required this.verglichen,
    required this.abweichend,
  });

  /// Erfasste Produktionen mit Rohware im Zeitraum (und im Filter).
  final int produktionen;

  /// Davon mit Produktionszeit — nur sie zählen.
  final int mitZeit;

  /// Rohware und Produktionszeit der Produktionen mit Zeit.
  final double kg;
  final double minuten;

  /// Die Artikel mit der meisten Produktionszeit, meiste zuerst.
  final List<ArtikelLeistung> zeitverbraucher;

  /// Die Artikel, die am stärksten von ihren Leistungsdaten abweichen —
  /// stärkste zuerst, höchstens [kLeistungAnzahl].
  final List<ArtikelLeistung> abweichungen;

  /// Artikel, die sich mit ihren Leistungsdaten vergleichen lassen.
  final int verglichen;

  /// Davon um [kLeistungAbweichungAb] oder mehr daneben.
  final int abweichend;

  /// Produktionen mit Rohware, aber ohne Zeit.
  int get ohneZeit => produktionen - mitZeit;

  /// Ø kg Rohware je Stunde über alle Produktionen mit Zeit — null ohne.
  double? get kgProStunde => minuten > 0 ? kg / minuten * 60 : null;
}

/// Wie viel Rohware je Stunde die erfassten Produktionen geschafft haben —
/// und wo das von den hinterlegten Leistungsdaten abweicht. Mit
/// [abteilung] nur Artikel, die einen Schritt in dieser Abteilung haben.
///
/// Zeit und Rohware nach denselben Regeln wie die Planung
/// ([produktionsMinutenVon]).
LeistungsAuswertung werteLeistungAus(
  List<ErfassteProduktion> produktionen,
  Map<String, StatistikArtikel> artikel,
  StatistikSpanne spanne, {
  Abteilung? abteilung,
}) {
  var anzahl = 0;
  var mitZeit = 0;
  var kgSumme = 0.0;
  var minutenSumme = 0.0;
  // Je Artikel: Rohware und Minuten jeder Produktion mit Zeit.
  final jeArtikel = <String, List<(double, double)>>{};
  for (final p in produktionen) {
    if (!_imFilter(p, artikel, spanne, abteilung)) continue;
    final kg = p.kgRohware;
    if (kg == null || !kg.isFinite || kg <= 0) continue;
    anzahl++;
    final minuten = p.minuten;
    if (minuten == null || !minuten.isFinite || minuten <= 0) continue;
    mitZeit++;
    kgSumme += kg;
    minutenSumme += minuten;
    (jeArtikel[p.productId] ??= []).add((kg, minuten));
  }

  final alle = <ArtikelLeistung>[];
  for (final MapEntry(key: id, value: werte) in jeArtikel.entries) {
    final a = artikel[id];
    if (a == null) continue;
    var kg = 0.0;
    var minuten = 0.0;
    var langsamste = double.infinity;
    var schnellste = 0.0;
    for (final (k, m) in werte) {
      kg += k;
      minuten += m;
      final kgh = k / m * 60;
      if (kgh < langsamste) langsamste = kgh;
      if (kgh > schnellste) schnellste = kgh;
    }
    alle.add(
      ArtikelLeistung(
        artikel: a,
        kg: kg,
        minuten: minuten,
        langsamste: langsamste,
        schnellste: schnellste,
        anzahl: werte.length,
      ),
    );
  }

  int nachNummer(ArtikelLeistung a, ArtikelLeistung b) =>
      a.artikel.artikelnummer.compareTo(b.artikel.artikelnummer);

  final zeitverbraucher = [...alle]..sort((a, b) {
      final m = b.minuten.compareTo(a.minuten);
      return m != 0 ? m : nachNummer(a, b);
    });

  final vergleichbar = [
    for (final a in alle)
      if (a.vergleichbar) (a, (a.abweichung ?? 0.0).abs()),
  ];
  final abweichend = [
    for (final (a, d) in vergleichbar)
      if (d >= kLeistungAbweichungAb) (a, d),
  ]..sort((x, y) {
      final d = y.$2.compareTo(x.$2);
      return d != 0 ? d : nachNummer(x.$1, y.$1);
    });

  return LeistungsAuswertung(
    produktionen: anzahl,
    mitZeit: mitZeit,
    kg: kgSumme,
    minuten: minutenSumme,
    zeitverbraucher: zeitverbraucher.take(kLeistungAnzahl).toList(),
    abweichungen: [
      for (final (a, _) in abweichend.take(kLeistungAnzahl)) a,
    ],
    verglichen: vergleichbar.length,
    abweichend: abweichend.length,
  );
}

// ---------------------------------------------------------------------------
// Teil 5: Produktmix
// ---------------------------------------------------------------------------

/// Höchstens so viele Stücke hat der Kreis — mehr kann niemand ablesen.
const int kKreisStueckeMax = 6;

/// So viele Artikel zeigt die Liste der größten.
const int kTopArtikelAnzahl = 10;

/// Ein Stück des Kreises: eine Produktgruppe, „Übrige" oder die Artikel
/// ohne Produktgruppe.
class MixGruppe {
  const MixGruppe({
    required this.name,
    required this.kg,
    required this.produktionen,
    this.uebrige = false,
    this.ohneGruppe = false,
  });

  final String name;
  final double kg;
  final int produktionen;

  /// Zusammengefasste kleinere Gruppen.
  final bool uebrige;

  /// Artikel, für die noch keine Produktgruppe gepflegt ist.
  final bool ohneGruppe;
}

class MixArtikel {
  const MixArtikel({
    required this.artikel,
    required this.kg,
    required this.produktionen,
  });

  final StatistikArtikel artikel;
  final double kg;
  final int produktionen;
}

class ProduktmixAuswertung {
  const ProduktmixAuswertung({
    required this.kgGesamt,
    required this.produktionen,
    required this.artikelAnzahl,
    required this.gruppen,
    required this.topArtikel,
  });

  /// Eingesetzte Rohware in kg.
  final double kgGesamt;
  final int produktionen;
  final int artikelAnzahl;

  /// Höchstens [kKreisStueckeMax] Stücke: die Produktgruppen, größte
  /// zuerst, dann „Übrige", ganz hinten die Artikel ohne Produktgruppe.
  final List<MixGruppe> gruppen;

  /// Die größten Artikel, größter zuerst.
  final List<MixArtikel> topArtikel;

  /// Rohware von Artikeln ohne Produktgruppe.
  double get kgOhneGruppe => gruppen
      .where((g) => g.ohneGruppe)
      .fold(0.0, (summe, g) => summe + g.kg);
}

/// Wie sich die eingesetzte Rohware auf Produktgruppen und Artikel
/// verteilt. Mit [abteilung] nur Artikel mit einem Schritt dort.
///
/// Gerechnet in Rohware, weil sie bei jeder Erfassung eingetragen wird —
/// die Fertigware fehlt oft.
ProduktmixAuswertung werteProduktmixAus(
  List<ErfassteProduktion> produktionen,
  Map<String, StatistikArtikel> artikel,
  StatistikSpanne spanne, {
  Abteilung? abteilung,
}) {
  final jeGruppe = <String, (double, int)>{};
  final jeArtikel = <String, (double, int)>{};
  var kgGesamt = 0.0;
  var anzahl = 0;
  for (final p in produktionen) {
    if (!_imFilter(p, artikel, spanne, abteilung)) continue;
    final kg = p.kgRohware;
    if (kg == null || kg <= 0) continue;
    // Schlüssel ist der dbValue der Gruppe, leer ohne Gruppe.
    final gruppe = (artikel[p.productId]?.produktgruppe ?? '').trim();
    final g = jeGruppe[gruppe] ?? (0.0, 0);
    jeGruppe[gruppe] = (g.$1 + kg, g.$2 + 1);
    final a = jeArtikel[p.productId] ?? (0.0, 0);
    jeArtikel[p.productId] = (a.$1 + kg, a.$2 + 1);
    kgGesamt += kg;
    anzahl++;
  }

  // Die gepflegten Gruppen nach Menge. Artikel ohne Gruppe stehen immer
  // als eigenes Stück am Ende — sie sind keine Gruppe, sondern eine Lücke
  // in den Stammdaten, und sollen nicht in „Übrige" verschwinden.
  final gepflegt = [
    for (final MapEntry(key: gruppe, value: (kg, n)) in jeGruppe.entries)
      if (gruppe.isNotEmpty)
        MixGruppe(
          name: produktgruppeLabel(gruppe),
          kg: kg,
          produktionen: n,
        ),
  ]..sort((a, b) {
      final k = b.kg.compareTo(a.kg);
      return k != 0 ? k : a.name.compareTo(b.name);
    });
  final ohne = jeGruppe[''];
  final platz = kKreisStueckeMax - (ohne == null ? 0 : 1);
  final List<MixGruppe> sichtbar;
  if (gepflegt.length <= platz) {
    sichtbar = gepflegt;
  } else {
    final rest = gepflegt.sublist(platz - 1);
    sichtbar = [
      ...gepflegt.take(platz - 1),
      MixGruppe(
        name: 'Übrige (${rest.length} Gruppen)',
        kg: rest.fold(0.0, (summe, g) => summe + g.kg),
        produktionen: rest.fold(0, (summe, g) => summe + g.produktionen),
        uebrige: true,
      ),
    ];
  }
  final stuecke = [
    ...sichtbar,
    if (ohne != null)
      MixGruppe(
        name: 'Ohne Produktgruppe',
        kg: ohne.$1,
        produktionen: ohne.$2,
        ohneGruppe: true,
      ),
  ];

  final top = [
    for (final MapEntry(key: id, value: (kg, n)) in jeArtikel.entries)
      if (artikel[id] case final a?)
        MixArtikel(artikel: a, kg: kg, produktionen: n),
  ]..sort((a, b) {
      final k = b.kg.compareTo(a.kg);
      return k != 0
          ? k
          : a.artikel.artikelnummer.compareTo(b.artikel.artikelnummer);
    });

  return ProduktmixAuswertung(
    kgGesamt: kgGesamt,
    produktionen: anzahl,
    artikelAnzahl: jeArtikel.length,
    gruppen: stuecke,
    topArtikel: top.take(kTopArtikelAnzahl).toList(),
  );
}

// ---------------------------------------------------------------------------
// Teil 6: Planerfüllung
// ---------------------------------------------------------------------------

/// Wie viele Karten erledigt sind — und auf welchem Weg.
class ErfuellungsZahlen {
  const ErfuellungsZahlen({
    this.erfasst = 0,
    this.abgehakt = 0,
    this.offen = 0,
  });

  /// Die Produktion ist erfasst.
  final int erfasst;

  /// Von Hand abgehakt, aber nicht erfasst.
  final int abgehakt;

  /// Weder erfasst noch abgehakt.
  final int offen;

  int get karten => erfasst + abgehakt + offen;
  int get erledigt => erfasst + abgehakt;

  double get anteilErledigt => karten > 0 ? erledigt / karten : 0;
  double get anteilErfasst => karten > 0 ? erfasst / karten : 0;

  ErfuellungsZahlen plus(Erledigt? stand) => ErfuellungsZahlen(
        erfasst: erfasst + (stand == Erledigt.erfasst ? 1 : 0),
        abgehakt: abgehakt + (stand == Erledigt.abgehakt ? 1 : 0),
        offen: offen + (stand == null ? 1 : 0),
      );
}

/// Die Planerfüllung einer Abteilung.
class ErfuellungsZeile {
  const ErfuellungsZeile({required this.abteilung, required this.zahlen});

  final Abteilung abteilung;
  final ErfuellungsZahlen zahlen;
}

/// Die Planerfüllung in einem Abschnitt des Verlaufs.
class ErfuellungsPunkt {
  const ErfuellungsPunkt({required this.abschnitt, required this.zahlen});

  final DateTime abschnitt;
  final ErfuellungsZahlen zahlen;

  bool get hatDaten => zahlen.karten > 0;
}

class ErfuellungsAuswertung {
  const ErfuellungsAuswertung({
    required this.gesamt,
    required this.jeAbteilung,
    required this.verlauf,
    required this.verlaufSpanne,
  });

  final ErfuellungsZahlen gesamt;

  /// Abteilungen mit Karten, in Produktionsfolge.
  final List<ErfuellungsZeile> jeAbteilung;

  /// Nur Abschnitte, die vor heute beginnen — spätere können noch nichts
  /// erledigt haben.
  final List<ErfuellungsPunkt> verlauf;

  /// Zeitraum und Raster des Verlaufs — bei „Alles" ab der ersten Karte.
  final StatistikSpanne verlaufSpanne;

  /// Abschnitte des Verlaufs mit Daten — ein Verlauf braucht zwei.
  int get verlaufPunkte => verlauf.where((p) => p.hatDaten).length;

  bool get leer => gesamt.karten == 0;
}

/// Wie viel der Planung erledigt wurde: die Karten im Board bis gestern —
/// heute läuft noch. Mit [abteilung] nur die Karten dieser Abteilung.
ErfuellungsAuswertung werteErfuellungAus(
  List<PlanKarte> karten,
  StatistikSpanne spanne, {
  required DateTime heute,
  Abteilung? abteilung,
}) {
  final bis = tagOhneZeit(heute);
  final gezaehlt = [
    for (final k in karten)
      if (spanne.enthaelt(k.datum) &&
          k.datum.isBefore(bis) &&
          (abteilung == null || k.abteilung == abteilung))
        k,
  ];
  DateTime? ersterTag;
  for (final k in gezaehlt) {
    if (ersterTag == null || k.datum.isBefore(ersterTag)) ersterTag = k.datum;
  }
  final verlaufSpanne = spanne.abDatenbeginn(ersterTag);

  var gesamt = const ErfuellungsZahlen();
  final jeAbteilung = <Abteilung, ErfuellungsZahlen>{};
  final jeAbschnitt = <DateTime, ErfuellungsZahlen>{};
  for (final k in gezaehlt) {
    gesamt = gesamt.plus(k.erledigt);
    jeAbteilung[k.abteilung] =
        (jeAbteilung[k.abteilung] ?? const ErfuellungsZahlen()).plus(k.erledigt);
    final a = verlaufSpanne.abschnittVon(k.datum);
    jeAbschnitt[a] =
        (jeAbschnitt[a] ?? const ErfuellungsZahlen()).plus(k.erledigt);
  }

  final zeilen = [
    for (final MapEntry(key: a, value: zahlen) in jeAbteilung.entries)
      ErfuellungsZeile(abteilung: a, zahlen: zahlen),
  ]..sort((x, y) => x.abteilung.index.compareTo(y.abteilung.index));

  return ErfuellungsAuswertung(
    gesamt: gesamt,
    jeAbteilung: zeilen,
    verlauf: [
      for (final a in verlaufSpanne.abschnitte)
        if (a.isBefore(bis))
          ErfuellungsPunkt(
            abschnitt: a,
            zahlen: jeAbschnitt[a] ?? const ErfuellungsZahlen(),
          ),
    ],
    verlaufSpanne: verlaufSpanne,
  );
}

// ---------------------------------------------------------------------------
// Teil 7: Stammdaten-Pflege
// ---------------------------------------------------------------------------

/// Eine Lücke in den Stammdaten und wie viele Artikel sie haben.
class PflegeZeile {
  const PflegeZeile({
    required this.luecke,
    required this.anzahl,
    required this.aktiv,
  });

  final ArtikelLuecke luecke;

  /// Artikel mit dieser Lücke — genau so viele zeigt die Artikelliste mit
  /// diesem Filter.
  final int anzahl;

  /// Davon im Zeitraum produziert oder geplant.
  final int aktiv;
}

class PflegeAuswertung {
  const PflegeAuswertung({
    required this.artikel,
    required this.vollstaendig,
    required this.aktiv,
    required this.zeilen,
  });

  /// Alle Artikel.
  final int artikel;

  /// Davon ohne jede Lücke.
  final int vollstaendig;

  /// Davon im Zeitraum produziert oder geplant.
  final int aktiv;

  /// Je Lücke eine Zeile, in der Reihenfolge von [ArtikelLuecke].
  final List<PflegeZeile> zeilen;

  double get anteilVollstaendig => artikel > 0 ? vollstaendig / artikel : 0;
}

/// Was den Stammdaten aller [artikel] fehlt — und wie viel davon Artikel
/// betrifft, die im Zeitraum produziert oder geplant wurden ([aktive]).
///
/// Bewusst ohne Abteilungsfilter: Die Zahlen sollen die Länge der Liste
/// sein, die ein Klick in der Artikelliste öffnet.
PflegeAuswertung wertePflegeAus(
  Map<String, StatistikArtikel> artikel,
  Set<String> aktive,
) {
  final anzahl = <ArtikelLuecke, int>{};
  final aktiv = <ArtikelLuecke, int>{};
  var vollstaendig = 0;
  var aktivGesamt = 0;
  for (final a in artikel.values) {
    final istAktiv = aktive.contains(a.id);
    if (istAktiv) aktivGesamt++;
    if (a.luecken.isEmpty) vollstaendig++;
    for (final l in a.luecken) {
      anzahl[l] = (anzahl[l] ?? 0) + 1;
      if (istAktiv) aktiv[l] = (aktiv[l] ?? 0) + 1;
    }
  }
  return PflegeAuswertung(
    artikel: artikel.length,
    vollstaendig: vollstaendig,
    aktiv: aktivGesamt,
    zeilen: [
      for (final l in ArtikelLuecke.values)
        PflegeZeile(luecke: l, anzahl: anzahl[l] ?? 0, aktiv: aktiv[l] ?? 0),
    ],
  );
}

// ---------------------------------------------------------------------------
// Laden
// ---------------------------------------------------------------------------

/// Alles, was die Statistik-Seite für einen Zeitraum braucht.
class StatistikDaten {
  const StatistikDaten({
    required this.spanne,
    required this.stand,
    required this.belegung,
    required this.karten,
    required this.produktionen,
    required this.artikel,
  });

  final StatistikSpanne spanne;

  /// Wann geladen wurde — „heute" für die Planerfüllung.
  final DateTime stand;

  /// Planung: jede Spur an jedem Werktag des Zeitraums.
  final List<SpurTagBelegung> belegung;

  /// Die Karten des Boards im Zeitraum, gebündelt wie dort.
  final List<PlanKarte> karten;

  /// Erfasste Produktionen im Zeitraum.
  final List<ErfassteProduktion> produktionen;

  /// Alle Artikel, nach ID.
  final Map<String, StatistikArtikel> artikel;

  /// Die Artikel, die im Zeitraum produziert oder geplant wurden.
  Set<String> get aktiveArtikel => {
        for (final p in produktionen) p.productId,
        for (final k in karten) k.productId,
      };
}

/// Der früheste Tag mit Planung oder erfasster Produktion — null ohne
/// beides.
Future<DateTime?> _fruehestesDatum(AppDatabase db) async {
  final auftrag = await (db.select(db.productionTasks)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.status.isNotIn(const ['storniert']))
        ..orderBy([(t) => OrderingTerm.asc(t.datum)])
        ..limit(1))
      .getSingleOrNull();
  final produktion = await (db.select(db.productionHistory)
        ..where((h) => h.deletedAt.isNull())
        ..orderBy([(h) => OrderingTerm.asc(h.datum)])
        ..limit(1))
      .getSingleOrNull();
  final a = auftrag?.datum;
  final p = produktion?.datum;
  if (a == null) return p;
  if (p == null) return a;
  return a.isBefore(p) ? a : p;
}

/// Lädt Planung, Karten, erfasste Produktionen und Artikel für
/// [zeitraum], von [heute] aus gesehen (Standard: jetzt).
Future<StatistikDaten> ladeStatistik(
  AppDatabase db,
  StatistikZeitraum zeitraum, {
  DateTime? heute,
}) async {
  final jetzt = heute ?? DateTime.now();
  final fruehestes =
      zeitraum.wochen == null ? await _fruehestesDatum(db) : null;
  final spanne =
      StatistikSpanne.fuer(zeitraum, jetzt, fruehestes: fruehestes);

  final belegung = await belegungImZeitraum(
    db,
    von: spanne.von,
    bisExkl: spanne.bisExkl,
  );
  final karten = await kartenImZeitraum(
    db,
    von: spanne.von,
    bisExkl: spanne.bisExkl,
  );

  // Alle Artikel mit Schritten und ALLEN erfassten Produktionen — wie die
  // Artikelliste: Ob einem Artikel eine Ausbeute oder eine Zeit fehlt,
  // hängt nicht am Zeitraum.
  final produkte = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull()))
      .get();
  final schritte = await (db.select(db.productSteps)
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
      .get();
  final historie = await (db.select(db.productionHistory)
        ..where((h) => h.deletedAt.isNull()))
      .get();
  final grundlagen = produktionsGrundlagen(historie);

  final schritteJeArtikel = <String, List<ProductStep>>{};
  for (final s in schritte) {
    (schritteJeArtikel[s.productId] ??= []).add(s);
  }
  final artikel = <String, StatistikArtikel>{};
  for (final p in produkte) {
    final eigene = schritteJeArtikel[p.id] ?? const <ProductStep>[];
    artikel[p.id] = StatistikArtikel(
      id: p.id,
      artikelnummer: p.artikelnummer,
      bezeichnung: p.artikelbezeichnung,
      produktgruppe: p.produktgruppe,
      abteilungen: {for (final s in eigene) s.abteilung},
      luecken: artikelLuecken(p, eigene, grundlagen[p.id]),
      // Gemessen wird die Zeit an der Bratstraße — verglichen wird mit
      // ihren Leistungsdaten.
      leistungKgH: leistungsdatenVon([
        for (final s in eigene)
          if (s.abteilung == Abteilung.bratstrasse.dbValue) s,
      ])?.kgProStunde,
    );
  }

  return StatistikDaten(
    spanne: spanne,
    stand: jetzt,
    belegung: belegung,
    karten: [
      for (final k in karten)
        PlanKarte(
          productId: k.productId,
          abteilung: k.abteilung,
          datum: k.datum,
          erledigt: k.erledigt,
        ),
    ],
    // Produktionen gelöschter Artikel zeigt die App sonst nirgends mehr —
    // hier zählen sie auch nicht.
    produktionen: [
      for (final h in historie)
        if (artikel.containsKey(h.productId) &&
            spanne.enthaelt(tagOhneZeit(h.datum)))
          ErfassteProduktion.aus(h),
    ],
    artikel: artikel,
  );
}

/// Die Daten der Statistik-Seite für einen Zeitraum. `autoDispose`: Wer
/// die Seite wieder öffnet, sieht den aktuellen Stand.
final statistikProvider = FutureProvider.autoDispose
    .family<StatistikDaten, StatistikZeitraum>((ref, zeitraum) {
  final db = ref.watch(databaseProvider);
  return ladeStatistik(db, zeitraum);
});
