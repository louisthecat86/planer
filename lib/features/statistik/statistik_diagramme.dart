import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_stil.dart';
import '../../core/utils/format.dart';

// Diagramme der Statistik-Seite.
//
// Kreise und Säulen zeichnet fl_chart — mit Animation und Hinweis beim
// Darüberfahren. Vergleiche mit langen Namen (Abteilungen, Anlagen,
// Artikel) stehen dagegen als Tabelle mit Balken: Die Namen bleiben
// lesbar, und jeder Wert steht ohne Darüberfahren da.
//
// Farbe trägt nur, was sie tragen muss: Reihen in einer festen, auf
// Farbsehschwäche geprüften Folge; Ampel- und Erledigt-Farben nur dort,
// wo sie dasselbe heißen wie im Board; eine einzelne Reihe in der
// Akzentfarbe. Jede Farbe steht neben einem Namen — nie allein.

// ---------------------------------------------------------------------------
// Farben
// ---------------------------------------------------------------------------

/// Reihenfarben, hell — feste Folge, nie gemischt. Geprüft auf
/// Unterscheidbarkeit bei Farbsehschwäche gegen den weißen Grund.
const List<Color> _reihenHell = [
  Color(0xFF2A78D6),
  Color(0xFFEB6834),
  Color(0xFF1BAF7A),
  Color(0xFFEDA100),
  Color(0xFFE87BA4),
  Color(0xFF008300),
];

/// Dieselben Töne, für den dunklen Grund abgestuft.
const List<Color> _reihenDunkel = [
  Color(0xFF3987E5),
  Color(0xFFD95926),
  Color(0xFF199E70),
  Color(0xFFC98500),
  Color(0xFFD55181),
  Color(0xFF008300),
];

/// Reihenfarbe Nummer [i] (ab 0). Mehr als sechs Reihen gibt es nicht —
/// darüber fasst die Statistik zu „Übrige" zusammen.
Color reihenFarbe(BuildContext context, int i) {
  final reihe = Theme.of(context).brightness == Brightness.dark
      ? _reihenDunkel
      : _reihenHell;
  return reihe[math.min(math.max(i, 0), reihe.length - 1)];
}

/// Grau für Auslastung unter 75 % — wie „frei" im Board — und für Artikel
/// ohne Produktgruppe. Etwas dunkler als im Board: Als Balken auf heller
/// Fläche braucht es mehr Kontrast als ein kleines Feld.
Color grauFarbe(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF9A9A9A)
        : const Color(0xFF858585);

/// Helles Grau für „Übrige" — vom dunkleren [grauFarbe] zu unterscheiden.
Color hellgrauFarbe(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF5E5E5E)
        : const Color(0xFFC4C4C4);

/// Grau für den offenen Rest eines Ganzen — kaum anders als die leere
/// Spur eines Balkens, damit das Erledigte heraussticht.
Color restFarbe(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF3F3F40)
        : const Color(0xFFDDDDDD);

/// [farbe] blasser — als deckende Farbe auf dem Grund gemischt, nicht
/// durchscheinend: Übereinander gemalt (Säulen mit Stapel) schiene sonst
/// die Farbe darunter durch.
Color blasseFarbe(
  BuildContext context,
  Color farbe, {
  double deckkraft = 0.45,
}) =>
    Color.alphaBlend(
      farbe.withValues(alpha: deckkraft),
      Theme.of(context).colorScheme.surface,
    );

TextStyle _achsenStil(BuildContext context) => TextStyle(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

// ---------------------------------------------------------------------------
// Kreis
// ---------------------------------------------------------------------------

/// Ein Stück des Kreises.
class KreisStueck {
  const KreisStueck({
    required this.name,
    required this.wert,
    required this.farbe,
    required this.wertText,
  });

  final String name;
  final double wert;
  final Color farbe;

  /// Der Wert lesbar, etwa „312:00 h" oder „2.156 kg".
  final String wertText;
}

/// Kreis mit Legende: Anteile an einem Ganzen, höchstens sechs Stücke.
///
/// Darüberfahren hebt das Stück im Kreis und seine Zeile in der Legende
/// hervor — in beide Richtungen —, und die Mitte zeigt seinen Wert.
class StatistikKreis extends StatefulWidget {
  const StatistikKreis({
    super.key,
    required this.stuecke,
    required this.summeText,
    required this.summeLabel,
  });

  final List<KreisStueck> stuecke;

  /// In der Mitte die Summe, etwa „412:30 h" …
  final String summeText;

  /// … und darunter, was sie zählt.
  final String summeLabel;

  @override
  State<StatistikKreis> createState() => _StatistikKreisState();
}

class _StatistikKreisState extends State<StatistikKreis> {
  int? _aktiv;

  void _setzeAktiv(int? index) {
    if (index != _aktiv) setState(() => _aktiv = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final stuecke = widget.stuecke;
    final summe = stuecke.fold(0.0, (s, k) => s + k.wert);
    final aktiv = _aktiv;
    final gewaehlt =
        aktiv != null && aktiv < stuecke.length ? stuecke[aktiv] : null;

    final kreis = SizedBox(
      width: 184,
      height: 184,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sections: [
                for (var i = 0; i < stuecke.length; i++)
                  PieChartSectionData(
                    value: stuecke[i].wert,
                    color: stuecke[i].farbe,
                    radius: i == aktiv ? 34 : 28,
                    showTitle: false,
                  ),
              ],
              centerSpaceRadius: 54,
              sectionsSpace: 2,
              startDegreeOffset: -90,
              borderData: FlBorderData(show: false),
              pieTouchData: PieTouchData(
                touchCallback: (ereignis, antwort) {
                  if (!ereignis.isInterestedForInteractions) {
                    _setzeAktiv(null);
                    return;
                  }
                  final index = antwort?.touchedSection?.touchedSectionIndex;
                  _setzeAktiv(index == null || index < 0 ? null : index);
                },
              ),
            ),
            duration: const Duration(milliseconds: 200),
          ),
          // Die Mitte: die Summe — oder das Stück unter dem Zeiger.
          IgnorePointer(
            child: SizedBox(
              width: 96,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      gewaehlt?.wertText ?? widget.summeText,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    gewaehlt?.name ?? widget.summeLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: grau, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final legende = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < stuecke.length; i++)
          MouseRegion(
            onEnter: (_) => _setzeAktiv(i),
            onExit: (_) => _setzeAktiv(null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: i == aktiv ? theme.colorScheme.primaryContainer : null,
                borderRadius: AppMasse.ecken,
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: stuecke[i].farbe,
                      borderRadius: AppMasse.eckenKlein,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: stuecke[i].name,
                      waitDuration: const Duration(milliseconds: 600),
                      child: Text(
                        stuecke[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: Text(
                      stuecke[i].wertText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      summe > 0 ? Format.prozent(stuecke[i].wert / summe) : '—',
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    // Breit: Legende neben dem Kreis. Schmaler: darunter — dort hat jeder
    // Name die ganze Breite.
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 560) {
          return Row(
            children: [
              kreis,
              const SizedBox(width: 20),
              Expanded(child: legende),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: kreis),
            const SizedBox(height: 12),
            legende,
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Säulen
// ---------------------------------------------------------------------------

/// Eine Säule im Verlauf.
class Saeule {
  const Saeule({
    required this.label,
    required this.wert,
    required this.farbe,
    required this.hinweis,
    this.segmente = const [],
  });

  /// Beschriftung unter der Säule, etwa „KW 42".
  final String label;

  /// null: keine Daten — die Stelle bleibt leer.
  final double? wert;

  final Color farbe;

  /// Text beim Darüberfahren.
  final String hinweis;

  /// Gestapelte Teile von unten nach oben, zusammen [wert] — leer: die
  /// ganze Säule in [farbe].
  final List<(double, Color)> segmente;
}

/// Eine „runde" Teilung für eine Achse bis [spanne]: 1, 2, 2,5 oder 5 mal
/// einer Zehnerpotenz, für etwa vier Abschnitte.
double achsenSchritt(double spanne) {
  if (!(spanne > 0)) return 1;
  final roh = spanne / 4;
  final potenz =
      math.pow(10, (math.log(roh) / math.ln10).floor()).toDouble();
  for (final faktor in const [1.0, 2.0, 2.5, 5.0]) {
    if (roh <= faktor * potenz) return faktor * potenz;
  }
  return 10 * potenz;
}

/// Oberes Ende der Achse für Werte bis [hoechster]: ein ganzer Schritt,
/// mit etwas Luft über der höchsten Säule.
double achsenMax(double hoechster, double schritt) {
  var oben = (hoechster / schritt).ceil() * schritt;
  if (oben <= 0) oben = schritt;
  if (hoechster > oben - schritt * 0.15) oben += schritt;
  return oben;
}

/// Säulen über die Zeit — eine Reihe, eine Säule je Woche oder Monat;
/// mit [Saeule.segmente] gestapelt.
class StatistikSaeulen extends StatelessWidget {
  const StatistikSaeulen({
    super.key,
    required this.saeulen,
    required this.achsenText,
    this.linie,
    this.linienFarbe,
    this.festesMax,
    this.hoehe = 200,
  });

  final List<Saeule> saeulen;

  /// Beschriftung der senkrechten Achse, etwa „100 %".
  final String Function(double wert) achsenText;

  /// Gestrichelte Bezugslinie auf dieser Höhe, etwa 100 % — null: keine.
  final double? linie;
  final Color? linienFarbe;

  /// Festes oberes Ende der Achse, etwa 100 für Anteile in Prozent — null:
  /// nach der höchsten Säule.
  final double? festesMax;

  final double hoehe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final achse = _achsenStil(context);
    final bezug = linie;
    final fest = festesMax;

    var hoechster = bezug ?? 0.0;
    for (final s in saeulen) {
      final w = s.wert;
      if (w != null && w > hoechster) hoechster = w;
    }
    final schritt = achsenSchritt(fest ?? hoechster);
    final yMax = fest ?? achsenMax(hoechster, schritt);

    return SizedBox(
      height: hoehe,
      child: LayoutBuilder(
        builder: (context, c) {
          const links = 44.0;
          final flaeche = math.max(c.maxWidth - links, 1.0);
          final anzahl = math.max(saeulen.length, 1);
          final breite = (flaeche / anzahl * 0.6).clamp(3.0, 28.0).toDouble();
          // Jede wievielte Säule beschriftet ist — damit sich die Namen
          // nicht überlappen.
          final jede = math.max(1, (anzahl * 46 / flaeche).ceil());

          return Padding(
            padding: const EdgeInsets.only(top: 8, right: 4),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                minY: 0,
                maxY: yMax,
                barGroups: [
                  for (var i = 0; i < saeulen.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: saeulen[i].wert ?? 0,
                          color: saeulen[i].farbe,
                          width: breite,
                          borderRadius: _saeulenEcken,
                          rodStackItems: _stapel(saeulen[i], farben.surface),
                        ),
                      ],
                    ),
                ],
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: links,
                      interval: schritt,
                      getTitlesWidget: (wert, meta) => SideTitleWidget(
                        meta: meta,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(achsenText(wert), style: achse),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (wert, meta) {
                        final i = wert.toInt();
                        if (i < 0 || i >= saeulen.length || i % jede != 0) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          space: 6,
                          child: Text(saeulen[i].label, style: achse),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: schritt,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: farben.outlineVariant,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(bottom: BorderSide(color: farben.outline)),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (bezug != null)
                      HorizontalLine(
                        y: bezug,
                        color: linienFarbe ?? farben.onSurfaceVariant,
                        strokeWidth: 1,
                        dashArray: const [4, 3],
                      ),
                  ],
                ),
                barTouchData: BarTouchData(
                  touchExtraThreshold: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => farben.inverseSurface,
                    tooltipBorderRadius: AppMasse.ecken,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    tooltipMargin: 6,
                    maxContentWidth: 240,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (gruppe, gruppenIndex, stab, stabIndex) {
                      final i = gruppe.x;
                      if (i < 0 || i >= saeulen.length) return null;
                      if (saeulen[i].wert == null) return null;
                      return BarTooltipItem(
                        saeulen[i].hinweis,
                        TextStyle(
                          color: farben.onInverseSurface,
                          fontSize: 12,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.left,
                      );
                    },
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 250),
            ),
          );
        },
      ),
    );
  }
}

/// Oben leicht abgerundet, unten gerade auf der Grundlinie.
const BorderRadius _saeulenEcken = BorderRadius.vertical(
  top: Radius.circular(2),
);

/// Die Teile einer gestapelten Säule — getrennt durch eine feine Fuge in
/// der Grundfarbe.
List<BarChartRodStackItem> _stapel(Saeule saeule, Color fuge) {
  if (saeule.wert == null || saeule.segmente.isEmpty) return const [];
  final teile = <BarChartRodStackItem>[];
  var unten = 0.0;
  for (final (wert, farbe) in saeule.segmente) {
    if (!(wert > 0)) continue;
    teile.add(
      BarChartRodStackItem(
        unten,
        unten + wert,
        farbe,
        borderSide: BorderSide(color: fuge),
      ),
    );
    unten += wert;
  }
  return teile;
}

// ---------------------------------------------------------------------------
// Balken in Tabellenzeilen
// ---------------------------------------------------------------------------

/// Ein Balken aus Segmenten nebeneinander, skaliert auf [max] — für einen
/// einzelnen Wert ein Segment. Mit [marke] steht an dieser Stelle ein
/// senkrechter Strich, etwa bei 100 %.
class SegmentBalken extends StatelessWidget {
  const SegmentBalken({
    super.key,
    required this.segmente,
    required this.max,
    this.marke,
    this.hoehe = 8,
  });

  final List<(double, Color)> segmente;
  final double max;
  final double? marke;
  final double hoehe;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final strich = marke;
    return LayoutBuilder(
      builder: (context, c) {
        final breite = c.maxWidth;
        double x(double wert) =>
            max > 0 ? math.min(math.max(wert / max, 0.0), 1.0) * breite : 0;

        final teile = <Widget>[];
        var links = 0.0;
        for (final (wert, farbe) in segmente) {
          final w = x(wert);
          if (w <= 0) continue;
          teile.add(
            Positioned(
              left: links,
              top: 2,
              bottom: 2,
              width: w,
              // Ein schmaler Spalt in der Grundfarbe trennt die Segmente.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: farbe,
                  border: Border(
                    right: BorderSide(color: farben.surface),
                  ),
                ),
              ),
            ),
          );
          links += w;
        }

        return SizedBox(
          height: hoehe + 4,
          width: breite,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 2,
                bottom: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: farben.surfaceContainerHighest,
                    borderRadius: AppMasse.eckenKlein,
                  ),
                ),
              ),
              ...teile,
              if (strich != null && strich <= max)
                Positioned(
                  left: math.max(x(strich) - 1, 0.0),
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: ColoredBox(color: farben.onSurface),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Spanne von [von] bis [bis] mit einem Punkt bei [mitte], auf einer
/// Achse von [achseVon] bis [achseBis].
class SpannenBalken extends StatelessWidget {
  const SpannenBalken({
    super.key,
    required this.von,
    required this.bis,
    required this.mitte,
    required this.achseVon,
    required this.achseBis,
  });

  final double von;
  final double bis;
  final double mitte;
  final double achseVon;
  final double achseBis;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final breite = c.maxWidth;
        final spanne = achseBis - achseVon;
        double x(double wert) => spanne > 0
            ? math.min(math.max((wert - achseVon) / spanne, 0.0), 1.0) * breite
            : 0;
        final links = x(von);
        final rechts = math.max(x(bis), links + 2);
        final punkt = x(mitte);
        return SizedBox(
          height: 12,
          width: breite,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 5,
                height: 2,
                child: ColoredBox(color: farben.outlineVariant),
              ),
              Positioned(
                left: links,
                width: rechts - links,
                top: 2,
                height: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: farben.primary.withValues(alpha: 0.45),
                    borderRadius: AppMasse.eckenKlein,
                  ),
                ),
              ),
              Positioned(
                left: math.max(punkt - 5, 0.0),
                top: 1,
                width: 10,
                height: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: farben.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: farben.surface, width: 2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Abweichung von einem Bezugswert in der Mitte: ein Balken nach links
/// (weniger) oder nach rechts (mehr), auf einer Achse von −[grenze] bis
/// +[grenze]. Was darüber hinausgeht, endet am Rand — den genauen Wert
/// nennt die Zeile.
class AbweichungsBalken extends StatelessWidget {
  const AbweichungsBalken({
    super.key,
    required this.wert,
    required this.grenze,
    required this.farbeWeniger,
    required this.farbeMehr,
  });

  /// Etwa −0,25 für ein Viertel weniger.
  final double wert;
  final double grenze;
  final Color farbeWeniger;
  final Color farbeMehr;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final breite = c.maxWidth;
        final mitte = breite / 2;
        final anteil = grenze > 0
            ? math.min(math.max(wert / grenze, -1.0), 1.0)
            : 0.0;
        final laenge = anteil.abs() * mitte;
        return SizedBox(
          height: 12,
          width: breite,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 2,
                height: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: farben.surfaceContainerHighest,
                    borderRadius: AppMasse.eckenKlein,
                  ),
                ),
              ),
              if (laenge > 0)
                Positioned(
                  left: anteil < 0 ? mitte - laenge : mitte,
                  width: laenge,
                  top: 2,
                  height: 8,
                  child: ColoredBox(
                    color: anteil < 0 ? farbeWeniger : farbeMehr,
                  ),
                ),
              // Der Bezugswert.
              Positioned(
                left: mitte - 1,
                width: 2,
                top: 0,
                bottom: 0,
                child: ColoredBox(color: farben.onSurface),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Eine Zeile einer Tabelle mit Balken: vorne eine Marke, dann Name und
/// Werte in einer Zeile, darunter der Balken.
///
/// Mit [namensBreite] steht alles in EINER Zeile — Name, Balken, Werte —,
/// wie in einer Tabelle mit Balkenspalte. Das passt für kurze Namen
/// (Abteilungen, Anlagen). Bleibt dem Balken dann zu wenig Platz, steht er
/// doch wieder unter dem Namen.
class BalkenZeile extends StatelessWidget {
  const BalkenZeile({
    super.key,
    required this.name,
    required this.balken,
    this.werte = const [],
    this.vorne,
    this.unterzeile,
    this.hinweis,
    this.onTap,
    this.letzte = false,
    this.namensBreite,
  });

  final String name;
  final Widget balken;

  /// Werte rechts neben dem Namen — jeweils mit fester Breite, damit die
  /// Spalten untereinander stehen.
  final List<Widget> werte;

  /// Vorne, etwa die Abteilungsmarke.
  final Widget? vorne;

  /// Kleine graue Zeile unter dem Namen — nur zweizeilig.
  final String? unterzeile;

  /// Erklärung beim Darüberfahren.
  final String? hinweis;

  final VoidCallback? onTap;

  /// Letzte Zeile: ohne Linie darunter.
  final bool letzte;

  /// Breite der Namensspalte für die einzeilige Form — null: zweizeilig.
  final double? namensBreite;

  /// So schmal darf der Balken in der einzeiligen Form höchstens werden.
  static const double _balkenMindestens = 140;

  @override
  Widget build(BuildContext context) {
    final breite = namensBreite;
    if (breite == null) return _rahmen(context, _zweizeilig(context));
    return LayoutBuilder(
      builder: (context, c) {
        var belegt = 8.0 + breite + 24 + (vorne == null ? 0 : 40);
        for (final w in werte) {
          belegt += w is ZeilenWert ? w.breite : 40;
        }
        final passt = c.maxWidth - belegt >= _balkenMindestens;
        return _rahmen(
          context,
          passt ? _einzeilig(breite) : _zweizeilig(context),
        );
      },
    );
  }

  Text _name() => Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      );

  Widget _einzeilig(double breite) {
    final vorn = vorne;
    return Row(
      children: [
        if (vorn != null) ...[
          vorn,
          const SizedBox(width: 10),
        ],
        SizedBox(width: breite, child: _name()),
        const SizedBox(width: 12),
        Expanded(child: balken),
        const SizedBox(width: 12),
        ...werte,
      ],
    );
  }

  Widget _zweizeilig(BuildContext context) {
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    final vorn = vorne;
    final zusatz = unterzeile;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (vorn != null) ...[
          vorn,
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _name()),
                  ...werte,
                ],
              ),
              if (zusatz != null)
                Text(
                  zusatz,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: grau),
                ),
              const SizedBox(height: 4),
              balken,
            ],
          ),
        ),
      ],
    );
  }

  /// Linie darunter, Antippen und Erklärung — für beide Formen gleich.
  Widget _rahmen(BuildContext context, Widget inhalt) {
    final theme = Theme.of(context);
    Widget zeile = Container(
      padding: EdgeInsets.symmetric(
        horizontal: 4,
        vertical: namensBreite == null ? 7 : 6,
      ),
      decoration: BoxDecoration(
        border: letzte
            ? null
            : Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
      ),
      child: inhalt,
    );
    final tippen = onTap;
    if (tippen != null) {
      zeile = InkWell(onTap: tippen, child: zeile);
    }
    final erklaerung = hinweis;
    if (erklaerung != null) {
      zeile = Tooltip(
        message: erklaerung,
        waitDuration: const Duration(milliseconds: 400),
        child: zeile,
      );
    }
    return zeile;
  }
}

/// Ein Wert in einer [BalkenZeile]: rechtsbündig, feste Breite.
class ZeilenWert extends StatelessWidget {
  const ZeilenWert(
    this.text, {
    super.key,
    this.breite = 76,
    this.farbe,
    this.fett = false,
  });

  final String text;
  final double breite;
  final Color? farbe;
  final bool fett;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: breite,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12,
          fontWeight: fett ? FontWeight.w700 : FontWeight.w400,
          color: farbe ?? Theme.of(context).colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Legende unter einem Diagramm: Farbfelder mit Namen, dazu optional die
/// gestrichelte Bezugslinie.
class FarbLegende extends StatelessWidget {
  const FarbLegende({super.key, required this.eintraege, this.linie});

  final List<(Color, String)> eintraege;

  /// Name der gestrichelten Linie — null: keine.
  final String? linie;

  @override
  Widget build(BuildContext context) {
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    final stil = TextStyle(fontSize: 11, color: grau);
    final strich = linie;
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final (farbe, text) in eintraege)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: farbe,
                  borderRadius: AppMasse.eckenKlein,
                ),
              ),
              const SizedBox(width: 5),
              Text(text, style: stil),
            ],
          ),
        if (strich != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 4,
                  height: 1.5,
                  margin: const EdgeInsets.only(right: 2),
                  color: grau,
                ),
              const SizedBox(width: 3),
              Text(strich, style: stil),
            ],
          ),
      ],
    );
  }
}
