import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/constants/product_groups.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/format.dart';
import '../../core/utils/kalenderwoche.dart';
import '../board/board_providers.dart'
    show BoardSpur, CapacityStatus, SpurTagBelegung, belegungImZeitraum;
import '../whiteboard/whiteboard_provider.dart' show verlustAnteilVon;

// Die Zahlen hinter der Statistik-Seite.
//
// Zwei Quellen, je nach Frage:
//  • Auslastung und Zeit stammen aus der Planung im Board — Woche für Woche
//    so, wie das Board sie zeigt ([belegungImZeitraum]), mit der heutigen
//    Kapazität.
//  • Ausbeute, Verlust und Produktmix stammen aus den erfassten
//    Produktionen — dem, was wirklich herauskam.
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
  });

  final String id;
  final String artikelnummer;
  final String bezeichnung;

  /// Produktgruppe als dbValue — null: keine.
  final String? produktgruppe;

  /// Abteilungen seiner Prozessschritte (dbValues).
  final Set<String> abteilungen;
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
// Laden
// ---------------------------------------------------------------------------

/// Alles, was die Statistik-Seite für einen Zeitraum braucht.
class StatistikDaten {
  const StatistikDaten({
    required this.spanne,
    required this.belegung,
    required this.produktionen,
    required this.artikel,
  });

  final StatistikSpanne spanne;

  /// Planung: jede Spur an jedem Werktag des Zeitraums.
  final List<SpurTagBelegung> belegung;

  /// Erfasste Produktionen im Zeitraum.
  final List<ErfassteProduktion> produktionen;

  /// Die Artikel der Produktionen, nach ID.
  final Map<String, StatistikArtikel> artikel;
}

/// Höchstzahl an IDs in einer `IN (...)`-Abfrage — wie im Board.
const int _kIdBlock = 400;

Iterable<List<String>> _bloecke(Set<String> ids) sync* {
  final liste = ids.toList();
  for (var i = 0; i < liste.length; i += _kIdBlock) {
    final ende = i + _kIdBlock;
    yield liste.sublist(i, ende > liste.length ? liste.length : ende);
  }
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

/// Lädt Planung und erfasste Produktionen für [zeitraum], von [heute] aus
/// gesehen (Standard: jetzt).
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

  final historie = await (db.select(db.productionHistory)
        ..where((h) => h.deletedAt.isNull())
        ..where((h) => h.datum.isBiggerOrEqualValue(spanne.von))
        ..where((h) => h.datum.isSmallerThanValue(spanne.bisExkl)))
      .get();

  final ids = {for (final h in historie) h.productId};
  final produkte = <Product>[];
  final schritte = <ProductStep>[];
  for (final block in _bloecke(ids)) {
    produkte.addAll(
      await (db.select(db.products)
            ..where((p) => p.id.isIn(block))
            ..where((p) => p.deletedAt.isNull()))
          .get(),
    );
    schritte.addAll(
      await (db.select(db.productSteps)
            ..where((s) => s.productId.isIn(block))
            ..where((s) => s.deletedAt.isNull()))
          .get(),
    );
  }
  final abteilungenJeArtikel = <String, Set<String>>{};
  for (final s in schritte) {
    (abteilungenJeArtikel[s.productId] ??= <String>{}).add(s.abteilung);
  }
  final artikel = {
    for (final p in produkte)
      p.id: StatistikArtikel(
        id: p.id,
        artikelnummer: p.artikelnummer,
        bezeichnung: p.artikelbezeichnung,
        produktgruppe: p.produktgruppe,
        abteilungen: abteilungenJeArtikel[p.id] ?? const {},
      ),
  };

  return StatistikDaten(
    spanne: spanne,
    belegung: belegung,
    // Produktionen gelöschter Artikel zeigt die App sonst nirgends mehr —
    // hier zählen sie auch nicht.
    produktionen: [
      for (final h in historie)
        if (artikel.containsKey(h.productId)) ErfassteProduktion.aus(h),
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
