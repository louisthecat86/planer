import '../../core/constants/abteilungen.dart';
import '../../core/utils/datum.dart';
import '../board/board_providers.dart'
    show BoardSpur, CapacityStatus, SpurTagBelegung;
import 'statistik_daten.dart';

// Die Zahlen über den Bereichen der Statistik: wie gut der Plan war (Plan
// gegen Ist), wo es in den nächsten Tagen eng wird (Vorschau) und der
// Überblick ganz oben — fünf Kennzahlen mit dem Vergleich zum Zeitraum
// davor und eine kurze Liste dessen, was Aufmerksamkeit braucht.
//
// Wie in statistik_daten.dart reine Funktionen über den geladenen Daten;
// der Abteilungsfilter wirkt erst hier.

// ---------------------------------------------------------------------------
// Themen der Seite
// ---------------------------------------------------------------------------

/// Die Themen unter dem Überblick — je eines ist zu sehen.
enum StatistikThema {
  kapazitaet('Kapazität'),
  planIst('Plan & Ist'),
  ausbeute('Ausbeute'),
  leistung('Leistung'),
  artikel('Artikel & Stammdaten');

  const StatistikThema(this.label);

  final String label;
}

// ---------------------------------------------------------------------------
// Plan gegen Ist
// ---------------------------------------------------------------------------

/// Ab so viel Abweichung der Rohware vom Plan liegt eine Produktion
/// außerhalb des Bands: 10 %.
const double kMengenBand = 0.10;

/// Ab so viel Abweichung der Dauer vom Plan: 20 % — wie bei den
/// Leistungsdaten.
const double kZeitBand = 0.20;

/// So viele Abweichungen zeigt die Liste.
const int kPlanIstListe = 10;

/// Eine erfasste Produktion neben ihrem Plan — je Artikel und Tag.
class PlanIstPaar {
  const PlanIstPaar({
    required this.artikel,
    required this.datum,
    this.planKg,
    this.istKg,
    this.planMinuten,
    this.istMinuten,
  });

  final StatistikArtikel artikel;
  final DateTime datum;

  /// Geplante Rohware an der Wurzel der Kette.
  final double? planKg;
  final double? istKg;

  /// Geplante Dauer an der Bratstraße — dort wird die Zeit gemessen.
  final double? planMinuten;
  final double? istMinuten;

  static double? _abweichung(double? plan, double? ist) {
    if (plan == null || ist == null || plan <= 0 || ist <= 0) return null;
    return ist / plan - 1;
  }

  /// Ist ÷ Plan − 1 der Rohware — null ohne beides.
  double? get mengeAbweichung => _abweichung(planKg, istKg);

  /// Ist ÷ Plan − 1 der Dauer — null ohne beides.
  double? get zeitAbweichung => _abweichung(planMinuten, istMinuten);

  bool get mengeImBand {
    final a = mengeAbweichung;
    return a != null && a.abs() <= kMengenBand;
  }

  bool get zeitImBand {
    final a = zeitAbweichung;
    return a != null && a.abs() <= kZeitBand;
  }

  /// Wie weit das Paar über sein Band hinausgeht — 0: in beiden Bändern.
  double get ueberBand {
    final m = mengeAbweichung;
    final z = zeitAbweichung;
    final ueberM = m == null ? 0.0 : m.abs() / kMengenBand;
    final ueberZ = z == null ? 0.0 : z.abs() / kZeitBand;
    final hoechstes = ueberM > ueberZ ? ueberM : ueberZ;
    return hoechstes > 1 ? hoechstes : 0;
  }
}

/// Mengen- und Zeittreue in einem Abschnitt des Verlaufs.
class TreuePunkt {
  const TreuePunkt({
    required this.abschnitt,
    this.mengentreue,
    this.zeittreue,
  });

  final DateTime abschnitt;
  final double? mengentreue;
  final double? zeittreue;
}

class PlanIstAuswertung {
  const PlanIstAuswertung({
    required this.produktionen,
    required this.ungeplant,
    required this.paare,
    required this.verlauf,
  });

  /// Erfasste Produktionen im Zeitraum (und im Filter), je Artikel und
  /// Tag zusammengefasst.
  final int produktionen;

  /// Davon ohne Karte im Board an diesem Tag.
  final int ungeplant;

  /// Produktionen mit Karte — mit Plan und Ist, soweit bekannt.
  final List<PlanIstPaar> paare;

  final List<TreuePunkt> verlauf;

  int get mengePaare => paare.where((p) => p.mengeAbweichung != null).length;
  int get mengeImBand => paare.where((p) => p.mengeImBand).length;
  int get zeitPaare => paare.where((p) => p.zeitAbweichung != null).length;
  int get zeitImBand => paare.where((p) => p.zeitImBand).length;

  /// Anteil der Produktionen, deren Rohware im Band lag — null ohne Paar.
  double? get mengentreue => mengePaare > 0 ? mengeImBand / mengePaare : null;

  /// Anteil der Produktionen, deren Dauer im Band lag — null ohne Paar.
  double? get zeittreue => zeitPaare > 0 ? zeitImBand / zeitPaare : null;

  /// Produktionen, die länger dauerten als das Band erlaubt.
  int get zuLang =>
      paare.where((p) => (p.zeitAbweichung ?? 0) > kZeitBand).length;

  /// Die größten Abweichungen, größte zuerst — nur außerhalb des Bands.
  List<PlanIstPaar> get abweichungen {
    final liste = [
      for (final p in paare)
        if (p.ueberBand > 0) p,
    ]..sort((a, b) => b.ueberBand.compareTo(a.ueberBand));
    return liste.take(kPlanIstListe).toList();
  }

  bool get leer => mengePaare == 0 && zeitPaare == 0;
}

class _IstSumme {
  double kg = 0;
  double minuten = 0;
  bool hatKg = false;
  bool hatMinuten = false;
}

class _PlanSumme {
  double kg = 0;
  double minuten = 0;
  bool hatKg = false;
  bool hatMinuten = false;
}

/// Jede erfasste Produktion neben ihren Karten im Board — zugeordnet über
/// Artikel und Tag, wie die Planerfüllung. Mehrere Produktionen eines
/// Artikels am selben Tag zählen zusammen. Mit [abteilung] nur Artikel,
/// die einen Schritt in dieser Abteilung haben.
PlanIstAuswertung wertePlanIstAus(
  List<PlanKarte> karten,
  List<ErfassteProduktion> produktionen,
  Map<String, StatistikArtikel> artikel,
  StatistikSpanne spanne, {
  Abteilung? abteilung,
}) {
  bool imFilter(String productId) {
    final a = artikel[productId];
    if (a == null) return false;
    return abteilung == null || a.abteilungen.contains(abteilung.dbValue);
  }

  final ist = <(String, DateTime), _IstSumme>{};
  for (final p in produktionen) {
    if (!spanne.enthaelt(p.datum) || !imFilter(p.productId)) continue;
    final s = ist.putIfAbsent((p.productId, p.datum), _IstSumme.new);
    final kg = p.kgRohware;
    if (kg != null && kg.isFinite && kg > 0) {
      s
        ..kg += kg
        ..hatKg = true;
    }
    final m = p.minuten;
    if (m != null && m.isFinite && m > 0) {
      s
        ..minuten += m
        ..hatMinuten = true;
    }
  }

  final plan = <(String, DateTime), _PlanSumme>{};
  for (final k in karten) {
    final key = (k.productId, tagOhneZeit(k.datum));
    if (!ist.containsKey(key)) continue;
    final s = plan.putIfAbsent(key, _PlanSumme.new);
    final kg = k.mengeKg;
    if (k.wurzel && kg != null && kg.isFinite && kg > 0) {
      s
        ..kg += kg
        ..hatKg = true;
    }
    final m = k.dauerMinuten;
    if (k.abteilung == Abteilung.bratstrasse &&
        m != null &&
        m.isFinite &&
        m > 0) {
      s
        ..minuten += m
        ..hatMinuten = true;
    }
  }

  final paare = <PlanIstPaar>[];
  var ungeplant = 0;
  for (final MapEntry(key: key, value: i) in ist.entries) {
    final p = plan[key];
    if (p == null) {
      ungeplant++;
      continue;
    }
    paare.add(
      PlanIstPaar(
        artikel: artikel[key.$1]!,
        datum: key.$2,
        planKg: p.hatKg ? p.kg : null,
        istKg: i.hatKg ? i.kg : null,
        planMinuten: p.hatMinuten ? p.minuten : null,
        istMinuten: i.hatMinuten ? i.minuten : null,
      ),
    );
  }
  paare.sort((a, b) => b.datum.compareTo(a.datum));

  final jeAbschnitt = <DateTime, List<PlanIstPaar>>{};
  for (final p in paare) {
    (jeAbschnitt[spanne.abschnittVon(p.datum)] ??= []).add(p);
  }
  double? anteil(
    List<PlanIstPaar> liste,
    bool Function(PlanIstPaar) mit,
    bool Function(PlanIstPaar) gut,
  ) {
    final n = liste.where(mit).length;
    return n == 0 ? null : liste.where(gut).length / n;
  }

  return PlanIstAuswertung(
    produktionen: ist.length,
    ungeplant: ungeplant,
    paare: paare,
    verlauf: [
      for (final a in spanne.abschnitte)
        TreuePunkt(
          abschnitt: a,
          mengentreue: anteil(
            jeAbschnitt[a] ?? const [],
            (p) => p.mengeAbweichung != null,
            (p) => p.mengeImBand,
          ),
          zeittreue: anteil(
            jeAbschnitt[a] ?? const [],
            (p) => p.zeitAbweichung != null,
            (p) => p.zeitImBand,
          ),
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Vorschau: die nächsten Werktage
// ---------------------------------------------------------------------------

/// So viele Werktage zeigt die Vorschau.
const int kVorschauWerktage = 10;

/// Eine Abteilung (mit Filter: eine Spur) an einem Tag der Vorschau.
class VorschauZelle {
  const VorschauZelle({
    required this.tag,
    required this.auslastung,
    required this.belegtMinuten,
  });

  final DateTime tag;

  /// Die Auslastung der vollsten Spur der Zeile an diesem Tag — ein
  /// Engpass an einer Anlage zählt, auch wenn die anderen Luft haben.
  final double auslastung;

  final double belegtMinuten;

  bool get leer => belegtMinuten <= 0;

  CapacityStatus get status => leer
      ? CapacityStatus.frei
      : auslastung > 1
          ? CapacityStatus.ueberbucht
          : auslastung >= 0.75
              ? CapacityStatus.gut
              : CapacityStatus.frei;
}

class VorschauZeile {
  const VorschauZeile({
    required this.abteilung,
    required this.name,
    required this.zellen,
  });

  final Abteilung abteilung;
  final String name;

  /// Eine Zelle je Tag der Vorschau, in derselben Reihenfolge.
  final List<VorschauZelle> zellen;
}

class VorschauAuswertung {
  const VorschauAuswertung({required this.tage, required this.zeilen});

  /// Die Werktage ab heute.
  final List<DateTime> tage;

  /// Nur Zeilen, in denen etwas geplant ist — in der Reihenfolge des
  /// Boards.
  final List<VorschauZeile> zeilen;

  bool get leer => zeilen.isEmpty;

  /// Überbuchte Zellen, die vollste zuerst.
  List<(VorschauZeile, VorschauZelle)> get ueberbucht => [
        for (final z in zeilen)
          for (final c in z.zellen)
            if (c.status == CapacityStatus.ueberbucht) (z, c),
      ]..sort((a, b) => b.$2.auslastung.compareTo(a.$2.auslastung));
}

/// Die nächsten [kVorschauWerktage] Werktage ab [heute] je Abteilung —
/// mit [abteilung] je Spur dieser Abteilung.
VorschauAuswertung werteVorschauAus(
  List<SpurTagBelegung> belegung, {
  required DateTime heute,
  Abteilung? abteilung,
}) {
  final tage = <DateTime>[];
  var t = tagOhneZeit(heute);
  while (tage.length < kVorschauWerktage) {
    if (t.weekday <= DateTime.friday) tage.add(t);
    t = tagPlus(t, 1);
  }
  final index = {for (var i = 0; i < tage.length; i++) tage[i]: i};

  final zeilen = <String, (BoardSpur, List<double>, List<double>)>{};
  final mitAnlagen = {
    for (final b in belegung)
      if (b.spur.maschineId != null) b.spur.abteilung,
  };
  for (final b in belegung) {
    final i = index[tagOhneZeit(b.tag)];
    if (i == null) continue;
    if (abteilung != null && b.spur.abteilung != abteilung) continue;
    final key = abteilung == null ? b.spur.abteilung.dbValue : b.spur.id;
    final z = zeilen.putIfAbsent(
      key,
      () => (
        b.spur,
        List.filled(tage.length, 0.0),
        List.filled(tage.length, 0.0),
      ),
    );
    final anteil = b.kapazitaetMinuten > 0
        ? b.belegtMinuten / b.kapazitaetMinuten
        : (b.belegtMinuten > 0 ? double.infinity : 0.0);
    if (anteil > z.$2[i]) z.$2[i] = anteil;
    z.$3[i] += b.belegtMinuten;
  }

  final sortiert = [
    for (final z in zeilen.values)
      if (z.$3.any((m) => m > 0)) z,
  ]..sort((a, b) {
      final x = a.$1.abteilung.index.compareTo(b.$1.abteilung.index);
      if (x != 0 || abteilung == null) return x;
      return spurName(a.$1, abteilungHatAnlagen: true)
          .compareTo(spurName(b.$1, abteilungHatAnlagen: true));
    });

  return VorschauAuswertung(
    tage: tage,
    zeilen: [
      for (final (spur, anteile, minuten) in sortiert)
        VorschauZeile(
          abteilung: spur.abteilung,
          name: abteilung == null
              ? spur.abteilung.anzeigeName
              : spurName(
                  spur,
                  abteilungHatAnlagen: mitAnlagen.contains(spur.abteilung),
                ),
          zellen: [
            for (var i = 0; i < tage.length; i++)
              VorschauZelle(
                tag: tage[i],
                auslastung: anteile[i].isFinite ? anteile[i] : 9.99,
                belegtMinuten: minuten[i],
              ),
          ],
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Überblick: fünf Kennzahlen und was Aufmerksamkeit braucht
// ---------------------------------------------------------------------------

/// Ab diesem Anteil im Band gilt Mengen- und Zeittreue als gut …
const double kTreueGut = 0.8;

/// … ab diesem noch als Warnung, darunter als kritisch.
const double kTreueWarnung = 0.6;

/// Planerfüllung: gut ab 95 %, Warnung ab 85 %.
const double kErfuellungGut = 0.95;
const double kErfuellungWarnung = 0.85;

/// Ausbeute: so viel schlechter als im Zeitraum davor ist eine Warnung
/// (1 Punkt), so viel kritisch (3 Punkte).
const double kAusbeuteWarnung = 0.01;
const double kAusbeuteKritisch = 0.03;

/// Ein Artikel, dessen Ausbeute so viel unter der des Zeitraums davor
/// liegt, wird gemeldet: 3 Punkte.
const double kArtikelAusbeuteMeldung = 0.03;

/// So viele Tage zurück sucht der Überblick offene Karten — ältere sind
/// meist schlicht nicht abgehakt worden.
const int kOffenTage = 14;

/// Höchstens so viele Hinweise.
const int kHinweiseHoechstens = 5;

/// Wie eine Kennzahl steht.
enum Ampel { gut, warnung, kritisch, neutral }

/// Eine Kennzahl im Überblick.
class UeberblickKennzahl {
  const UeberblickKennzahl({
    required this.name,
    required this.thema,
    required this.wert,
    required this.ampel,
    required this.verlauf,
    this.vorher,
    this.ziel,
    this.hoeherIstBesser = true,
  });

  final String name;

  /// Wohin ein Klick führt.
  final StatistikThema thema;

  /// Anteil 0…1 — null: im Zeitraum keine Daten.
  final double? wert;

  /// Derselbe Wert im Zeitraum davor — null: kein Vergleich.
  final double? vorher;

  final Ampel ampel;

  /// Je Abschnitt des Zeitraums — für die kleine Linie.
  final List<double?> verlauf;

  /// Woran die Ampel gemessen wird, in einem Satz.
  final String? ziel;

  /// Ob ein höherer Wert besser ist — bei der Auslastung nicht.
  final bool hoeherIstBesser;

  /// Veränderung in Prozentpunkten — null ohne beide Werte.
  double? get differenz {
    final w = wert;
    final v = vorher;
    if (w == null || v == null) return null;
    return w - v;
  }
}

/// Wohin ein Hinweis führt.
enum HinweisZiel { board, artikel, thema, erfassung }

/// Wie dringend ein Hinweis ist — kritisch zuerst.
enum HinweisSchwere { kritisch, warnung, info }

/// Ein Satz im Überblick, der zu einer Handlung führt.
class StatistikHinweis {
  const StatistikHinweis({
    required this.text,
    required this.unter,
    required this.schwere,
    required this.ziel,
    this.tag,
    this.artikelId,
    this.thema,
  });

  final String text;

  /// Was ein Klick öffnet, in Worten.
  final String unter;
  final HinweisSchwere schwere;
  final HinweisZiel ziel;

  /// Bei [HinweisZiel.board]: der Tag.
  final DateTime? tag;

  /// Bei [HinweisZiel.artikel]: der Artikel.
  final String? artikelId;

  /// Bei [HinweisZiel.thema]: das Thema.
  final StatistikThema? thema;
}

class UeberblickAuswertung {
  const UeberblickAuswertung({
    required this.kennzahlen,
    required this.hinweise,
    required this.vorschau,
    required this.planIst,
  });

  final List<UeberblickKennzahl> kennzahlen;
  final List<StatistikHinweis> hinweise;
  final VorschauAuswertung vorschau;
  final PlanIstAuswertung planIst;
}

Ampel _treueAmpel(double? w) => w == null
    ? Ampel.neutral
    : w >= kTreueGut
        ? Ampel.gut
        : w >= kTreueWarnung
            ? Ampel.warnung
            : Ampel.kritisch;

const _wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// „Do 03.12."
String tagText(DateTime d) => '${_wochentage[d.weekday - 1]} '
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.';

String _prozent(double anteil) => '${(anteil * 100).round()} %';

/// Der Überblick über alles: die fünf Kennzahlen mit Vergleich, die
/// Hinweise und die Vorschau.
UeberblickAuswertung werteUeberblickAus(
  StatistikDaten daten, {
  Abteilung? abteilung,
}) {
  final spanne = daten.spanne;
  final vorher = daten.vorher;
  final heute = tagOhneZeit(daten.stand);

  // Auslastung
  final auslastung =
      werteAuslastungAus(daten.belegung, spanne, abteilung: abteilung);
  final auslastungVorher = vorher == null
      ? null
      : werteAuslastungAus(
          vorher.belegung,
          vorher.spanne,
          abteilung: abteilung,
        );

  // Plan gegen Ist
  final planIst = wertePlanIstAus(
    daten.karten,
    daten.produktionen,
    daten.artikel,
    spanne,
    abteilung: abteilung,
  );
  final planIstVorher = vorher == null
      ? null
      : wertePlanIstAus(
          vorher.karten,
          vorher.produktionen,
          daten.artikel,
          vorher.spanne,
          abteilung: abteilung,
        );

  // Ausbeute
  final ausbeute = werteAusbeuteAus(
    daten.produktionen,
    daten.artikel,
    spanne,
    abteilung: abteilung,
  );
  final ausbeuteVorher = vorher == null
      ? null
      : werteAusbeuteAus(
          vorher.produktionen,
          daten.artikel,
          vorher.spanne,
          abteilung: abteilung,
        );

  // Planerfüllung
  final erfuellung = werteErfuellungAus(
    daten.karten,
    spanne,
    heute: daten.stand,
    abteilung: abteilung,
  );
  final erfuellungVorher = vorher == null
      ? null
      : werteErfuellungAus(
          vorher.karten,
          vorher.spanne,
          heute: daten.stand,
          abteilung: abteilung,
        );

  final vorschau = werteVorschauAus(
    daten.vorschau,
    heute: daten.stand,
    abteilung: abteilung,
  );

  double? auslastungWert(AuslastungsAuswertung? a) =>
      a == null || a.leer ? null : a.auslastung;
  double? erfuellungWert(ErfuellungsAuswertung? e) =>
      e == null || e.leer ? null : e.gesamt.anteilErledigt;

  final aWert = auslastungWert(auslastung);
  final eWert = erfuellungWert(erfuellung);
  final bWert = ausbeute.mittlereAusbeute;
  final bVorher = ausbeuteVorher?.mittlereAusbeute;

  Ampel ausbeuteAmpel() {
    if (bWert == null || bVorher == null) return Ampel.neutral;
    final d = bWert - bVorher;
    if (d <= -kAusbeuteKritisch) return Ampel.kritisch;
    if (d <= -kAusbeuteWarnung) return Ampel.warnung;
    return Ampel.gut;
  }

  final kennzahlen = [
    UeberblickKennzahl(
      name: 'Ø Auslastung',
      thema: StatistikThema.kapazitaet,
      wert: aWert,
      vorher: auslastungWert(auslastungVorher),
      ampel: aWert == null
          ? Ampel.neutral
          : switch (auslastungsStatus(
              auslastung.belegtMinuten,
              auslastung.kapazitaetMinuten,
            )) {
              CapacityStatus.ueberbucht => Ampel.kritisch,
              CapacityStatus.gut => Ampel.gut,
              CapacityStatus.frei => Ampel.neutral,
            },
      verlauf: [
        for (final p in auslastung.verlauf) p.hatDaten ? p.auslastung : null,
      ],
      ziel: 'gut gefüllt ab 75 %, überbucht über 100 %',
      hoeherIstBesser: false,
    ),
    UeberblickKennzahl(
      name: 'Mengentreue',
      thema: StatistikThema.planIst,
      wert: planIst.mengentreue,
      vorher: planIstVorher?.mengentreue,
      ampel: _treueAmpel(planIst.mengentreue),
      verlauf: [for (final p in planIst.verlauf) p.mengentreue],
      ziel: 'Rohware ±${_prozent(kMengenBand)} vom Plan',
    ),
    UeberblickKennzahl(
      name: 'Zeittreue',
      thema: StatistikThema.planIst,
      wert: planIst.zeittreue,
      vorher: planIstVorher?.zeittreue,
      ampel: _treueAmpel(planIst.zeittreue),
      verlauf: [for (final p in planIst.verlauf) p.zeittreue],
      ziel: 'Dauer ±${_prozent(kZeitBand)} vom Plan (Bratstraße)',
    ),
    UeberblickKennzahl(
      name: 'Ø Ausbeute',
      thema: StatistikThema.ausbeute,
      wert: bWert,
      vorher: bVorher,
      ampel: ausbeuteAmpel(),
      verlauf: [
        for (final p in ausbeute.verlauf)
          p.mittlererVerlust == null ? null : 1 - p.mittlererVerlust!,
      ],
      ziel: bVorher == null
          ? null
          : 'Zeitraum davor ${(bVorher * 100).toStringAsFixed(1).replaceAll('.', ',')} %',
    ),
    UeberblickKennzahl(
      name: 'Planerfüllung',
      thema: StatistikThema.planIst,
      wert: eWert,
      vorher: erfuellungWert(erfuellungVorher),
      ampel: eWert == null
          ? Ampel.neutral
          : eWert >= kErfuellungGut
              ? Ampel.gut
              : eWert >= kErfuellungWarnung
                  ? Ampel.warnung
                  : Ampel.kritisch,
      verlauf: [
        for (final p in erfuellung.verlauf)
          p.hatDaten ? p.zahlen.anteilErledigt : null,
      ],
      ziel: 'erledigt bis gestern, Ziel ab ${_prozent(kErfuellungGut)}',
    ),
  ];

  // --- Hinweise ---
  final hinweise = <StatistikHinweis>[];

  // Überbuchte Tage der nächsten Werktage — die zwei vollsten.
  for (final (zeile, zelle) in vorschau.ueberbucht.take(2)) {
    hinweise.add(
      StatistikHinweis(
        text: '${tagText(zelle.tag)}: ${zeile.name} '
            '${zelle.auslastung >= 9.99 ? 'ohne Kapazität belegt' : '${_prozent(zelle.auslastung)} belegt'}',
        unter: 'Board an diesem Tag öffnen',
        schwere: HinweisSchwere.kritisch,
        ziel: HinweisZiel.board,
        tag: zelle.tag,
      ),
    );
  }

  // Artikel, deren Ausbeute deutlich unter dem Zeitraum davor liegt.
  if (vorher != null) {
    final jetzt = _ausbeuteJeArtikel(
      daten.produktionen,
      daten.artikel,
      spanne,
      abteilung,
    );
    final davor = _ausbeuteJeArtikel(
      vorher.produktionen,
      daten.artikel,
      vorher.spanne,
      abteilung,
    );
    final schlechter = <(String, double)>[
      for (final MapEntry(key: id, value: a) in jetzt.entries)
        if (davor[id] != null && davor[id]! - a >= kArtikelAusbeuteMeldung)
          (id, davor[id]! - a),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    for (final (id, d) in schlechter.take(2)) {
      final a = daten.artikel[id]!;
      hinweise.add(
        StatistikHinweis(
          text: '${a.bezeichnung}: Ausbeute '
              '${(d * 100).toStringAsFixed(1).replaceAll('.', ',')} '
              'Punkte unter dem Zeitraum davor',
          unter: 'Artikel öffnen',
          schwere: HinweisSchwere.warnung,
          ziel: HinweisZiel.artikel,
          artikelId: id,
        ),
      );
    }
  }

  // Produktionen, die deutlich länger dauerten als geplant.
  final zuLang = planIst.zuLang;
  if (zuLang >= 3 &&
      planIst.zeitPaare > 0 &&
      zuLang / planIst.zeitPaare >= 0.25) {
    hinweise.add(
      StatistikHinweis(
        text: '$zuLang von ${planIst.zeitPaare} Produktionen über '
            '${_prozent(kZeitBand)} länger als geplant',
        unter: 'Plan & Ist ansehen',
        schwere: HinweisSchwere.warnung,
        ziel: HinweisZiel.thema,
        thema: StatistikThema.planIst,
      ),
    );
  }

  // Karten der letzten Tage, die weder erfasst noch abgehakt sind.
  final abOffen = tagPlus(heute, -kOffenTage);
  final offen = daten.karten
      .where(
        (k) =>
            k.erledigt == null &&
            k.datum.isBefore(heute) &&
            !k.datum.isBefore(abOffen) &&
            (abteilung == null || k.abteilung == abteilung),
      )
      .length;
  if (offen > 0) {
    hinweise.add(
      StatistikHinweis(
        text: offen == 1
            ? '1 Karte der letzten $kOffenTage Tage weder erfasst noch '
                'abgehakt'
            : '$offen Karten der letzten $kOffenTage Tage weder erfasst '
                'noch abgehakt',
        unter: 'Produktionserfassung öffnen',
        schwere: HinweisSchwere.warnung,
        ziel: HinweisZiel.erfassung,
      ),
    );
  }

  // Aktive Artikel mit Lücken in den Stammdaten.
  final aktiv = daten.aktiveArtikel;
  final mitLuecken = aktiv
      .where((id) => daten.artikel[id]?.luecken.isNotEmpty ?? false)
      .length;
  if (mitLuecken > 0) {
    hinweise.add(
      StatistikHinweis(
        text: mitLuecken == 1
            ? '1 aktiver Artikel mit Lücken in den Stammdaten'
            : '$mitLuecken aktive Artikel mit Lücken in den Stammdaten',
        unter: 'Artikel & Stammdaten ansehen',
        schwere: HinweisSchwere.info,
        ziel: HinweisZiel.thema,
        thema: StatistikThema.artikel,
      ),
    );
  }

  hinweise.sort((a, b) => a.schwere.index.compareTo(b.schwere.index));

  return UeberblickAuswertung(
    kennzahlen: kennzahlen,
    hinweise: hinweise.take(kHinweiseHoechstens).toList(),
    vorschau: vorschau,
    planIst: planIst,
  );
}

/// Ø Ausbeute je Artikel im Zeitraum — nur Artikel mit mindestens zwei
/// gültigen Produktionen.
Map<String, double> _ausbeuteJeArtikel(
  List<ErfassteProduktion> produktionen,
  Map<String, StatistikArtikel> artikel,
  StatistikSpanne spanne,
  Abteilung? abteilung,
) {
  final summen = <String, (int, double)>{};
  for (final p in produktionen) {
    final v = p.verlust;
    if (v == null || !spanne.enthaelt(p.datum)) continue;
    final a = artikel[p.productId];
    if (a == null) continue;
    if (abteilung != null && !a.abteilungen.contains(abteilung.dbValue)) {
      continue;
    }
    final s = summen[p.productId] ?? (0, 0.0);
    summen[p.productId] = (s.$1 + 1, s.$2 + (1 - v));
  }
  return {
    for (final MapEntry(key: id, value: (n, summe)) in summen.entries)
      if (n >= 2) id: summe / n,
  };
}
