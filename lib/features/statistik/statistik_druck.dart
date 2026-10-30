import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/abteilungen.dart';
import '../../core/druck/druck_bausteine.dart';
import '../../core/druck/druck_optionen.dart';
import '../../core/druck/druck_satz.dart';
import '../../core/utils/format.dart';
import '../../core/utils/pdf_text.dart';
import '../../core/utils/zeit.dart';
import '../board/board_providers.dart' show CapacityStatus;
import 'statistik_daten.dart';

// Die Statistik auf Papier — dieselben Teile wie auf dem Schirm: wo es
// eng wird, wohin die Zeit geht, wie viel vom Plan erledigt ist, Ausbeute,
// Leistung, Produktmix und Stammdaten. Statt der Diagramme Tabellen mit
// Balken; die Verläufe Woche für Woche (oder Monat für Monat) als Zeilen.

/// Die Teile der Statistik in der Reihenfolge der Seite.
enum StatistikTeil {
  auslastung('Auslastung und Engpässe'),
  zeit('Wohin die Zeit geht'),
  erfuellung('Planerfüllung'),
  ausbeute('Ausbeute und Verlust'),
  leistung('Leistung'),
  produktmix('Produktmix'),
  pflege('Stammdaten-Pflege');

  const StatistikTeil(this.titel);

  final String titel;
}

/// Schlüssel der Wahl im Druckfenster.
abstract final class StatistikDruckWahl {
  static const teile = 'teile';
  static const abteilung = 'abteilung';
  static const verlaeufe = 'verlaeufe';
  static const erklaerungen = 'erklaerungen';
  static const einzeln = 'einzeln';

  /// Der Wert für „alle Abteilungen" in [abteilung].
  static const alle = 'alle';
}

/// Was gedruckt wird — die Wahl im Druckfenster.
class StatistikDruckInhalt {
  const StatistikDruckInhalt({
    this.teile = const {...StatistikTeil.values},
    this.abteilung,
    this.verlaeufe = true,
    this.erklaerungen = true,
    this.einzeln = false,
  });

  final Set<StatistikTeil> teile;

  /// Nur diese Abteilung — null: alle.
  final Abteilung? abteilung;

  /// Die Verläufe als Tabellen.
  final bool verlaeufe;

  /// Die erklärenden Sätze unter den Teilen.
  final bool erklaerungen;

  /// Jeder Teil auf einer neuen Seite.
  final bool einzeln;
}

/// Die Statistik zum Drucken.
DruckDokument statistikDruck(
  StatistikDaten daten, {
  StatistikDruckInhalt inhalt = const StatistikDruckInhalt(),
  DateTime? gedrucktAm,
}) {
  final gedruckt = gedrucktAm ?? DateTime.now();
  final statistik = _Statistik(daten, inhalt, druckGedruckt(gedruckt));
  final titel = [
    'Statistik',
    daten.spanne.zeitraum.label,
    if (inhalt.abteilung case final a?) a.anzeigeName,
    druckIsoDatum(gedruckt),
  ].join(' ');
  return DruckDokument(
    titel: titel,
    dateiname: druckDateiname(titel),
    blaetter: [statistik.blatt()],
  );
}

/// Die Statistik für das Druckfenster — vorgewählt die Abteilung der
/// Seite. Der Zeitraum ist der der Seite.
DruckAuftrag statistikDruckAuftrag(
  StatistikDaten daten, {
  Abteilung? abteilung,
  DateTime? gedrucktAm,
}) {
  final spanne = daten.spanne;
  return DruckAuftrag(
    art: 'statistik',
    titel: 'Statistik drucken',
    untertitel: '${spanne.zeitraum.label} · ${spanne.beschreibung}',
    optionen: [
      DruckWahlMehrere(
        schluessel: StatistikDruckWahl.teile,
        titel: 'Teile',
        werte: [
          for (final t in StatistikTeil.values) DruckWert(t.name, t.titel),
        ],
        standard: {for (final t in StatistikTeil.values) t.name},
      ),
      DruckWahlEins(
        schluessel: StatistikDruckWahl.abteilung,
        titel: 'Abteilung',
        hinweis: 'Die Stammdaten-Pflege zählt immer alle Artikel',
        werte: [
          const DruckWert(StatistikDruckWahl.alle, 'Alle Abteilungen'),
          for (final a in Abteilung.values)
            DruckWert(
              a.dbValue,
              a.anzeigeName,
              farbe: a.farbwert,
              kuerzel: a.kurzcode,
            ),
        ],
        standard: abteilung?.dbValue ?? StatistikDruckWahl.alle,
        merken: false,
      ),
      const DruckSchalter(
        schluessel: StatistikDruckWahl.verlaeufe,
        titel: 'Verläufe',
        hinweis: 'Je Woche oder je Monat als Zeilen',
        gruppe: 'Auf dem Blatt',
      ),
      const DruckSchalter(
        schluessel: StatistikDruckWahl.erklaerungen,
        titel: 'Erklärungen',
        hinweis: 'Was gezählt wird und was daraus folgt',
        gruppe: 'Auf dem Blatt',
      ),
      const DruckSchalter(
        schluessel: StatistikDruckWahl.einzeln,
        titel: 'Jeder Teil auf einer neuen Seite',
        standard: false,
        gruppe: 'Auf dem Blatt',
      ),
    ],
    bauen: (wahl) {
      final teile = {
        for (final t in StatistikTeil.values)
          if (wahl.mehrere(StatistikDruckWahl.teile).contains(t.name)) t,
      };
      if (teile.isEmpty) {
        throw const DruckNichtsGewaehlt('Wähle mindestens einen Teil.');
      }
      final gewaehlt = wahl.eins(StatistikDruckWahl.abteilung);
      return statistikDruck(
        daten,
        gedrucktAm: gedrucktAm,
        inhalt: StatistikDruckInhalt(
          teile: teile,
          abteilung:
              Abteilung.values.where((a) => a.dbValue == gewaehlt).firstOrNull,
          verlaeufe: wahl.an(StatistikDruckWahl.verlaeufe),
          erklaerungen: wahl.an(StatistikDruckWahl.erklaerungen),
          einzeln: wahl.an(StatistikDruckWahl.einzeln),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Texte und Farben
// ---------------------------------------------------------------------------

/// Auslastung in ganzen Prozent — „< 1 %" statt „0 %", wenn doch etwas
/// geplant ist.
String _auslastungText(double anteil) => anteil > 0 && anteil < 0.005
    ? '< 1 %'
    : Format.prozent(anteil, nachkomma: 0);

/// Ein Anteil in ganzen Prozent — ohne „0 %" für etwas und ohne „100 %"
/// für nicht alles.
String _ganzeProzent(double anteil) {
  if (anteil > 0 && anteil < 0.005) return '< 1 %';
  if (anteil < 1 && anteil >= 0.995) return '> 99 %';
  return Format.prozent(anteil, nachkomma: 0);
}

/// „1.240 kg/h"
String _kgh(double kgProStunde) => '${Format.zahl(kgProStunde)} kg/h';

/// „+38 %" bzw. „-12 %" — immer mit Vorzeichen.
String _abweichungText(double anteil) {
  final text = Format.prozent(anteil.abs(), nachkomma: 0);
  return anteil < 0 ? '-$text' : '+$text';
}

/// „4711 · Rinderbratwurst"
String _artikelName(StatistikArtikel a) =>
    '${a.artikelnummer} · ${a.bezeichnung}';

String _tage(int n) => n == 1 ? '1 Tag' : '$n Tage';

/// „Wochen" bzw. „Monaten" — für den Hinweis ohne Verlauf.
String _abschnitteText(StatistikSpanne spanne) =>
    spanne.raster == StatistikRaster.woche ? 'Wochen' : 'Monaten';

const PdfColor _gruen = PdfColor.fromInt(0xFF2E7D32);
const PdfColor _gruenBlass = PdfColor.fromInt(0xFFA5D6A7);
const PdfColor _rot = PdfColor.fromInt(0xFFC62828);
const PdfColor _orange = PdfColor.fromInt(0xFFEF6C00);
const PdfColor _blau = PdfColor.fromInt(0xFF1565C0);
const PdfColor _blauBlass = PdfColor.fromInt(0xFF90CAF9);
const PdfColor _petrol = PdfColor.fromInt(0xFF00838F);
const PdfColor _lila = PdfColor.fromInt(0xFF6A1B9A);
const PdfColor _grau = PdfColors.grey500;

/// Ampel wie im Board.
PdfColor _ampel(CapacityStatus status) => switch (status) {
      CapacityStatus.frei => _grau,
      CapacityStatus.gut => _gruen,
      CapacityStatus.ueberbucht => _rot,
    };

/// Die Zeitarten in fester Folge — Farbe gehört zur Art, nicht zum Rang.
const List<(String, String, PdfColor)> _zeitArten = [
  ('produktion', 'Produktion', _blau),
  ('ruesten', 'Rüsten', _orange),
  ('reinigen', 'Reinigen', _petrol),
  ('sonstiges', 'Sonstiges', _lila),
];

double _zeitWert(ZeitAnteile a, String art) => switch (art) {
      'produktion' => a.produktion,
      'ruesten' => a.ruesten,
      'reinigen' => a.reinigen,
      _ => a.sonstiges,
    };

/// Die Teile der Planerfüllung: erfasst, nur abgehakt, offen.
List<(double, PdfColor)> _erfuellung(ErfuellungsZahlen z) => z.karten == 0
    ? const []
    : [
        (z.erfasst / z.karten, _gruen),
        (z.abgehakt / z.karten, _gruenBlass),
      ];

/// Eine Legende: kleine Quadrate in Farbe, daneben was sie bedeuten.
pw.Widget _legende(List<(PdfColor, String)> eintraege) => pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: pw.Wrap(
        spacing: 12,
        runSpacing: 3,
        children: [
          for (final (farbe, text) in eintraege)
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(width: 7, height: 7, color: farbe),
                pw.SizedBox(width: 4),
                pw.Text(
                  pdfText(text),
                  style: const pw.TextStyle(fontSize: 7.5, color: kDruckGrau),
                ),
              ],
            ),
        ],
      ),
    );

/// Ein Balken für die Spanne von [von] bis [bis] mit einem Punkt bei
/// [mitte] — auf der Achse von [achseVon] bis [achseBis].
pw.Widget _spannenBalken({
  required double von,
  required double bis,
  required double mitte,
  required double achseVon,
  required double achseBis,
  double breite = 110,
}) =>
    pw.CustomPaint(
      size: PdfPoint(breite, 8),
      painter: (canvas, groesse) {
        final spanne = achseBis - achseVon;
        if (!(spanne > 0)) return;
        double x(double wert) =>
            ((wert - achseVon) / spanne).clamp(0.0, 1.0) * groesse.x;
        final mittelY = groesse.y / 2;
        canvas
          ..setFillColor(PdfColors.grey200)
          ..drawRect(0, mittelY - 1, groesse.x, 2)
          ..fillPath()
          ..setFillColor(_blauBlass)
          ..drawRect(x(von), mittelY - 2.5, math.max(1, x(bis) - x(von)), 5)
          ..fillPath()
          ..setFillColor(_blau)
          ..drawEllipse(x(mitte), mittelY, 2.6, 2.6)
          ..fillPath();
      },
    );

/// Ein Balken für die Abweichung [wert] (−1…+1) von der Mitte aus — links
/// langsamer, rechts schneller; [grenze] ist der Rand.
pw.Widget _abweichungsBalken(
  double wert, {
  required double grenze,
  double breite = 110,
}) =>
    pw.CustomPaint(
      size: PdfPoint(breite, 7),
      painter: (canvas, groesse) {
        final mitte = groesse.x / 2;
        final w = (wert.abs() / grenze).clamp(0.0, 1.0) * mitte;
        canvas
          ..setFillColor(PdfColors.grey200)
          ..drawRect(0, 0, groesse.x, groesse.y)
          ..fillPath()
          ..setFillColor(wert < 0 ? _orange : _blau)
          ..drawRect(wert < 0 ? mitte - w : mitte, 0, w, groesse.y)
          ..fillPath()
          ..setStrokeColor(PdfColors.grey800)
          ..setLineWidth(0.8)
          ..moveTo(mitte, -1.5)
          ..lineTo(mitte, groesse.y + 1.5)
          ..strokePath();
      },
    );

/// Breite der Balken in den Tabellen.
const double _balkenBreite = 120;

/// Breite der Spalte, in der ein Balken steht.
const double _balkenSpalte = _balkenBreite + 8;

/// Eine Zelle mit einem Balken.
pw.Widget _balkenZelle(pw.Widget balken) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: balken,
    );

// ---------------------------------------------------------------------------
// Satz
// ---------------------------------------------------------------------------

/// Was auf einer Seite zusammenbleiben soll — mit geschätzter Höhe in
/// Punkt (lieber zu hoch als zu niedrig).
typedef _Block = ({List<pw.Widget> teile, double hoehe});

class _Statistik {
  _Statistik(this.daten, this.inhalt, this.gedruckt);

  final StatistikDaten daten;
  final StatistikDruckInhalt inhalt;
  final String gedruckt;

  StatistikSpanne get spanne => daten.spanne;
  Abteilung? get abteilung => inhalt.abteilung;

  DruckBlatt blatt() {
    final s = spanne;
    // „4 Wochen · 05.10.2026 – 01.11.2026" — die Zahl der Wochen nur, wo
    // der Zeitraum sie nicht schon nennt; eine gewählte Abteilung steht
    // im Titel.
    final zeile = [
      s.zeitraum.label,
      s.zeitraum == StatistikZeitraum.vierWochen
          ? s.beschreibung
          : '${s.beschreibung} (${s.wochen} '
              '${s.wochen == 1 ? 'Woche' : 'Wochen'})',
      if (abteilung == null) 'alle Abteilungen',
    ].join(' · ');
    return DruckBlatt(
      bauen: (r) {
        final teile = <pw.Widget>[];
        var erster = true;
        for (final t in StatistikTeil.values) {
          if (!inhalt.teile.contains(t)) continue;
          if (!erster && inhalt.einzeln && r.umbrueche) {
            teile.add(pw.NewPage());
          }
          erster = false;
          teile.addAll(teil(t, r));
        }
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: abteilung == null
                ? 'Statistik'
                : 'Statistik · ${abteilung!.anzeigeName}',
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(
            'Statistik · ${s.zeitraum.label} · Stand '
            '${Format.datum(daten.stand)}, ${Format.uhrzeit(daten.stand)}',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile,
        );
      },
    );
  }

  List<pw.Widget> teil(StatistikTeil t, DruckRahmen r) => switch (t) {
        StatistikTeil.auslastung => auslastung(r),
        StatistikTeil.zeit => zeit(r),
        StatistikTeil.erfuellung => erfuellung(r),
        StatistikTeil.ausbeute => ausbeute(r),
        StatistikTeil.leistung => leistung(r),
        StatistikTeil.produktmix => produktmix(r),
        StatistikTeil.pflege => pflege(r),
      };

  // ── Bausteine ─────────────────────────────────────────────────────────

  /// Die Überschrift eines Teils — mit Abstand davor.
  List<pw.Widget> kopf(StatistikTeil t, String untertitel) => [
        pw.SizedBox(height: 10),
        druckLeiste(t.titel, rechts: untertitel),
        pw.SizedBox(height: 4),
      ];

  /// Ein Teil ohne Daten: Überschrift und Hinweis.
  List<pw.Widget> leer(StatistikTeil t, String untertitel, String hinweis) => [
        pw.Inseparable(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [...kopf(t, untertitel), druckHinweis(hinweis)],
          ),
        ),
      ];

  /// Eine Tabelle: Kopfzeile und Zeilen, [breiten] je Spalte.
  pw.Widget tabelle(
    List<pw.Widget> kopfzeile,
    List<pw.TableRow> zeilen,
    List<pw.TableColumnWidth> breiten,
  ) =>
      pw.Table(
        border: kDruckGitter,
        columnWidths: breiten.asMap(),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [druckKopfzeile(kopfzeile), ...zeilen],
      );

  /// Der Anfang eines Teils: Überschrift, Kennzahlen und Hinweise.
  _Block anfang(StatistikTeil t, String untertitel, List<pw.Widget> teile) =>
      (teile: [...kopf(t, untertitel), ...teile], hoehe: 150);

  /// Ein Abschnitt: Zwischentitel, Tabelle mit [zeilen] Zeilen und was
  /// [danach] kommt (eine Legende, ein Hinweis).
  _Block abschnitt(
    String titel,
    pw.Widget tabelle, {
    required int zeilen,
    List<pw.Widget> danach = const [],
  }) =>
      (
        teile: [druckZwischentitel(titel), tabelle, ...danach],
        hoehe: 30 + (zeilen + 1) * 19 + danach.length * 36,
      );

  /// Ein Hinweis von bis zu [zeilen] Zeilen — mit [titel] darüber.
  _Block hinweis(String text, {String? titel, int zeilen = 2}) => (
        teile: [
          if (titel != null) druckZwischentitel(titel),
          druckHinweis(text, zeilen: zeilen),
        ],
        hoehe: 30 + zeilen * 12,
      );

  /// Setzt die Blöcke eines Teils: Jeder bleibt auf einer Seite, wenn er
  /// sicher darauf passt — sonst läuft seine Tabelle über die Seite. Die
  /// [erklaerung] hängt am letzten Block, damit sie nicht allein oben auf
  /// der nächsten Seite steht.
  List<pw.Widget> setzen(
    DruckRahmen r,
    List<_Block> bloecke, {
    String? erklaerung,
  }) {
    final liste = [...bloecke];
    if (erklaerung != null && inhalt.erklaerungen && liste.isNotEmpty) {
      final letzter = liste.removeLast();
      liste.add(
        (
          teile: [...letzter.teile, druckHinweis(erklaerung, zeilen: 5)],
          hoehe: letzter.hoehe + 70,
        ),
      );
    }
    return [
      for (final b in liste)
        ...druckGruppe(
          b.teile,
          zusammen: b.hoehe <= r.hoehe - 40,
          rahmen: r,
          frei: 90,
        ),
    ];
  }

  /// Der Name einer Zeile mit dem Punkt ihrer Abteilung davor.
  pw.Widget abteilungsZelle(Abteilung a, String name) => druckZelleMitPunkt(
        name,
        druckFarbe(a.farbwert),
        zeilen: 1,
        groesse: 8.5,
      );

  /// „Ein Verlauf braucht … in mindestens zwei Wochen."
  _Block ohneVerlauf(String was, StatistikSpanne vs) => hinweis(
        'Ein Verlauf braucht $was in mindestens zwei '
        '${_abschnitteText(vs)}.',
      );

  // ── Teil 1: Auslastung und Engpässe ───────────────────────────────────

  List<pw.Widget> auslastung(DruckRahmen r) {
    const t = StatistikTeil.auslastung;
    const untertitel = 'Planung · Kapazität von heute';
    final a = werteAuslastungAus(daten.belegung, spanne, abteilung: abteilung);
    if (a.leer) return leer(t, untertitel, 'Im Zeitraum ist nichts geplant.');

    final engpass = a.engpass;
    final wochen = a.geplanteWochen;
    final skala = a.zeilen.fold(1.2, (m, z) => math.max(m, z.auslastung));
    final mitUeberbucht = a.zeilen.any((z) => z.ueberbuchteTage > 0);
    final vs = a.verlaufSpanne;

    final zeilen = [
      for (final z in a.zeilen)
        pw.TableRow(
          children: [
            abteilungsZelle(z.abteilung, z.name),
            druckZelle(
              wochen > 0
                  ? '${Zeit.kurzOhneEinheit(z.belegtMinuten / wochen)} / '
                      '${Zeit.kurz(z.kapazitaetMinuten / wochen)}'
                  : '',
              rechts: true,
              groesse: 8.5,
            ),
            druckZelle(
              _auslastungText(z.auslastung),
              rechts: true,
              fett: true,
              farbe: z.status == CapacityStatus.ueberbucht
                  ? _rot
                  : PdfColors.black,
              groesse: 8.5,
            ),
            _balkenZelle(
              druckBalken(
                [(z.auslastung, _ampel(z.status))],
                max: skala,
                marke: 1,
                breite: _balkenBreite,
              ),
            ),
            if (mitUeberbucht)
              druckZelle(
                z.ueberbuchteTage > 0 ? _tage(z.ueberbuchteTage) : '',
                rechts: true,
                farbe: _rot,
                groesse: 8.5,
              ),
          ],
        ),
    ];

    final verlauf = [
      for (final p in a.verlauf)
        pw.TableRow(
          children: [
            druckZelle(vs.langname(p.abschnitt), groesse: 8.5),
            druckZelle(
              p.hatDaten ? _auslastungText(p.auslastung) : '-',
              rechts: true,
              fett: p.hatDaten,
              farbe: p.status == CapacityStatus.ueberbucht && p.hatDaten
                  ? _rot
                  : PdfColors.black,
              groesse: 8.5,
            ),
            _balkenZelle(
              p.hatDaten
                  ? druckBalken(
                      [(p.auslastung, _ampel(p.status))],
                      max: math.max(1.2, p.auslastung),
                      marke: 1,
                      breite: _balkenBreite,
                    )
                  : pw.SizedBox(),
            ),
            druckZelle(
              p.hatDaten
                  ? '${Zeit.kurzOhneEinheit(p.belegtMinuten)} / '
                      '${Zeit.kurz(p.kapazitaetMinuten)}'
                  : '',
              rechts: true,
              groesse: 8.5,
            ),
            druckZelle(
              p.hatDaten && p.ueberbuchteTage > 0
                  ? '${p.ueberbuchteTage} von ${p.tage}'
                  : '',
              rechts: true,
              farbe: _rot,
              groesse: 8.5,
            ),
          ],
        ),
    ];

    final gewaehlt = abteilung;
    return setzen(
      r,
      [
        anfang(t, untertitel, [
          druckKennzahlen([
            DruckKennzahl(
              _auslastungText(a.auslastung),
              'Ø Auslastung',
              betont: true,
            ),
            DruckKennzahl(
              '${a.ueberbuchteTage}',
              'überbuchte Tage von ${a.planungstage}',
            ),
            if (engpass != null)
              DruckKennzahl(
                engpass.name,
                'Engpass · Ø ${_auslastungText(engpass.auslastung)}',
              ),
            DruckKennzahl(
              '$wochen',
              wochen == 1 ? 'geplante Woche' : 'geplante Wochen',
            ),
          ]),
        ]),
        abschnitt(
          gewaehlt == null
              ? 'Je Abteilung · Ø pro Woche'
              : '${gewaehlt.anzeigeName} je Anlage · Ø pro Woche',
          tabelle(
            [
              druckKopfZelle(gewaehlt == null ? 'Abteilung' : 'Anlage'),
              druckKopfZelle('geplant / Kapazität', rechts: true),
              druckKopfZelle('Ausl.', rechts: true),
              druckKopfZelle(''),
              if (mitUeberbucht) druckKopfZelle('überbucht', rechts: true),
            ],
            zeilen,
            [
              const pw.FlexColumnWidth(),
              const pw.FixedColumnWidth(108),
              const pw.FixedColumnWidth(44),
              const pw.FixedColumnWidth(_balkenSpalte),
              if (mitUeberbucht) const pw.FixedColumnWidth(60),
            ],
          ),
          zeilen: zeilen.length,
          danach: [
            _legende(const [
              (_grau, 'unter 75 %'),
              (_gruen, 'gut gefüllt'),
              (_rot, 'überbucht'),
            ]),
          ],
        ),
        if (inhalt.verlaeufe)
          if (a.verlaufPunkte >= 2)
            abschnitt(
              'Ø Auslastung ${vs.rasterText} · '
              '${gewaehlt?.anzeigeName ?? 'alle Abteilungen zusammen'}',
              tabelle(
                [
                  druckKopfZelle(
                    vs.raster == StatistikRaster.woche ? 'Woche' : 'Monat',
                  ),
                  druckKopfZelle('Ausl.', rechts: true),
                  druckKopfZelle(''),
                  druckKopfZelle('geplant / Kapazität', rechts: true),
                  druckKopfZelle('überbuchte Tage', rechts: true),
                ],
                verlauf,
                const [
                  pw.FlexColumnWidth(),
                  pw.FixedColumnWidth(44),
                  pw.FixedColumnWidth(_balkenSpalte),
                  pw.FixedColumnWidth(112),
                  pw.FixedColumnWidth(80),
                ],
              ),
              zeilen: verlauf.length,
            )
          else
            ohneVerlauf('Planung', vs),
      ],
      erklaerung:
          'Gezählt werden Werktage, an denen im Board etwas geplant war — '
          'Feiertage und Wochen ohne Planung bleiben außen vor. Frühere Wochen '
          'rechnet die Statistik mit der heutigen Kapazität. Wo es regelmäßig '
          'über 100 % geht, fehlt Kapazität oder eine Schicht.',
    );
  }

  // ── Teil 2: Wohin die Zeit geht ───────────────────────────────────────

  List<pw.Widget> zeit(DruckRahmen r) {
    const t = StatistikTeil.zeit;
    const untertitel = 'Planung';
    final z = werteZeitAus(daten.belegung, abteilung: abteilung);
    final g = z.gesamt;
    if (g.summe <= 0) {
      return leer(t, untertitel, 'Im Zeitraum ist nichts geplant.');
    }
    final anteilNeben = g.neben / g.summe;
    final groesste = z.jeSpur.fold(0.0, (m, x) => math.max(m, x.anteile.summe));

    final gesamt = [
      for (final (art, name, farbe) in _zeitArten)
        pw.TableRow(
          children: [
            druckZelleMitPunkt(name, farbe, zeilen: 1, groesse: 8.5),
            druckZelle(
              Zeit.kurz(_zeitWert(g, art)),
              rechts: true,
              groesse: 8.5,
            ),
            druckZelle(
              Format.prozent(_zeitWert(g, art) / g.summe),
              rechts: true,
              groesse: 8.5,
            ),
            _balkenZelle(
              druckBalken(
                [(_zeitWert(g, art), farbe)],
                max: g.summe,
                breite: _balkenBreite,
              ),
            ),
          ],
        ),
    ];

    final jeSpur = [
      for (final x in z.jeSpur)
        pw.TableRow(
          children: [
            abteilungsZelle(x.spur.abteilung, x.name),
            druckZelle(Zeit.kurz(x.anteile.summe), rechts: true, groesse: 8.5),
            druckZelle(
              x.anteile.neben > 0
                  ? '${Format.prozent(x.anteile.neben / x.anteile.summe)} '
                      'Neben'
                  : '',
              rechts: true,
              groesse: 8.5,
            ),
            _balkenZelle(
              druckBalken(
                [
                  for (final (art, _, farbe) in _zeitArten)
                    (_zeitWert(x.anteile, art), farbe),
                ],
                max: groesste,
                breite: _balkenBreite,
              ),
            ),
          ],
        ),
    ];

    const breiten = [
      pw.FlexColumnWidth(),
      pw.FixedColumnWidth(70),
      pw.FixedColumnWidth(80),
      pw.FixedColumnWidth(_balkenSpalte),
    ];
    return setzen(
      r,
      [
        anfang(t, untertitel, [
          druckKennzahlen([
            DruckKennzahl(
              Zeit.kurz(g.produktion),
              'Produktion',
              betont: true,
            ),
            DruckKennzahl(Zeit.kurz(g.neben), 'Rüsten, Reinigen, Sonstiges'),
            DruckKennzahl(Format.prozent(anteilNeben), 'Anteil Nebenzeiten'),
          ]),
          if (g.neben <= 0)
            druckHinweis(
              'Im Zeitraum sind keine Rüst-, Reinigungs- oder sonstigen '
              'Nebenzeiten eingetragen — im Wochenboard über das '
              'Uhr-Symbol in der Tageszelle.',
              zeilen: 3,
            ),
          druckZwischentitel('Gesamt'),
          tabelle(
            [
              druckKopfZelle('Art'),
              druckKopfZelle('Zeit', rechts: true),
              druckKopfZelle('Anteil', rechts: true),
              druckKopfZelle(''),
            ],
            gesamt,
            breiten,
          ),
        ]),
        abschnitt(
          'Je Anlage',
          tabelle(
            [
              druckKopfZelle('Anlage'),
              druckKopfZelle('Zeit', rechts: true),
              druckKopfZelle('Nebenzeit', rechts: true),
              druckKopfZelle(''),
            ],
            jeSpur,
            breiten,
          ),
          zeilen: jeSpur.length,
          danach: [
            _legende([
              for (final (_, name, farbe) in _zeitArten) (farbe, name),
            ]),
          ],
        ),
      ],
      erklaerung:
          'Viel Rüst- und Reinigungszeit an einer Anlage? Ähnliche Artikel '
          'hintereinander zu planen — etwa mit gleichen Allergenen — spart '
          'Wechsel.',
    );
  }

  // ── Teil 3: Planerfüllung ─────────────────────────────────────────────

  List<pw.Widget> erfuellung(DruckRahmen r) {
    const t = StatistikTeil.erfuellung;
    final gewaehlt = abteilung;
    final untertitel = gewaehlt == null
        ? 'Karten im Board bis gestern'
        : 'Karten im Board bis gestern · ${gewaehlt.anzeigeName}';
    final e = werteErfuellungAus(
      daten.karten,
      spanne,
      heute: daten.stand,
      abteilung: gewaehlt,
    );
    if (e.leer) {
      return leer(t, untertitel, 'Im Zeitraum war bis gestern nichts geplant.');
    }
    final g = e.gesamt;
    final vs = e.verlaufSpanne;

    pw.TableRow zeile(pw.Widget name, ErfuellungsZahlen z) => pw.TableRow(
          children: [
            name,
            druckZelle(
              z.karten == 0 ? '' : '${z.erledigt} von ${z.karten}',
              rechts: true,
              groesse: 8.5,
            ),
            druckZelle(
              z.karten == 0 ? '-' : _ganzeProzent(z.anteilErledigt),
              rechts: true,
              fett: z.karten > 0,
              groesse: 8.5,
            ),
            _balkenZelle(
              z.karten == 0
                  ? pw.SizedBox()
                  : druckBalken(
                      _erfuellung(z),
                      max: 1,
                      breite: _balkenBreite,
                    ),
            ),
            druckZelle(
              z.karten == 0 ? '' : '${z.erfasst} · ${z.abgehakt} · ${z.offen}',
              rechts: true,
              groesse: 8,
            ),
          ],
        );

    // Jede Tabelle braucht eigene Zellen — geteilte Widgets setzt das
    // PDF an die falsche Stelle.
    List<pw.Widget> kopfzeile(String erste) => [
          druckKopfZelle(erste),
          druckKopfZelle('erledigt', rechts: true),
          druckKopfZelle('%', rechts: true),
          druckKopfZelle(''),
          druckKopfZelle('erf. · abg. · offen', rechts: true),
        ];
    const breiten = [
      pw.FlexColumnWidth(),
      pw.FixedColumnWidth(70),
      pw.FixedColumnWidth(44),
      pw.FixedColumnWidth(_balkenSpalte),
      pw.FixedColumnWidth(92),
    ];
    final jeAbteilung = [
      for (final z in e.jeAbteilung)
        zeile(abteilungsZelle(z.abteilung, z.abteilung.anzeigeName), z.zahlen),
    ];
    final verlauf = [
      for (final p in e.verlauf)
        zeile(druckZelle(vs.langname(p.abschnitt), groesse: 8.5), p.zahlen),
    ];
    const legende = [
      (_gruen, 'erfasst'),
      (_gruenBlass, 'nur abgehakt'),
      (PdfColors.grey200, 'offen'),
    ];

    return setzen(
      r,
      [
        anfang(t, untertitel, [
          druckKennzahlen([
            DruckKennzahl(
              _ganzeProzent(g.anteilErledigt),
              'erledigt · ${g.erledigt} von ${g.karten} '
              '${g.karten == 1 ? 'Karte' : 'Karten'}',
              betont: true,
            ),
            DruckKennzahl(
              _ganzeProzent(g.anteilErfasst),
              'mit erfasster Produktion',
            ),
            DruckKennzahl(
              '${g.offen}',
              g.offen == 1 ? 'Karte offen' : 'Karten offen',
            ),
          ]),
        ]),
        abschnitt(
          'Je Abteilung',
          tabelle(kopfzeile('Abteilung'), jeAbteilung, breiten),
          zeilen: jeAbteilung.length,
          danach: [_legende(legende)],
        ),
        if (inhalt.verlaeufe)
          if (e.verlaufPunkte >= 2)
            abschnitt(
              'Erledigt ${vs.rasterText} · '
              '${gewaehlt?.anzeigeName ?? 'alle Abteilungen zusammen'}',
              tabelle(
                kopfzeile(
                  vs.raster == StatistikRaster.woche ? 'Woche' : 'Monat',
                ),
                verlauf,
                breiten,
              ),
              zeilen: verlauf.length,
            )
          else
            ohneVerlauf('Karten', vs),
      ],
      erklaerung:
          'Gezählt werden die Karten im Board bis gestern — heute läuft noch. '
          'Erfasst: Die Produktion ist in der Produktionserfassung '
          'eingetragen; das macht ihre ganze Kette erledigt. Nur abgehakt: im '
          'Board von Hand erledigt — dann fehlen der Statistik Ausbeute und '
          'Zeit. Offen: weder noch, vielleicht produziert und nicht '
          'eingetragen.',
    );
  }

  // ── Teil 4: Ausbeute und Verlust ──────────────────────────────────────

  List<pw.Widget> ausbeute(DruckRahmen r) {
    const t = StatistikTeil.ausbeute;
    final gewaehlt = abteilung;
    final untertitel = gewaehlt == null
        ? 'erfasste Produktionen'
        : 'erfasste Produktionen · Artikel mit Schritt in '
            '${gewaehlt.anzeigeName}';
    final a = werteAusbeuteAus(
      daten.produktionen,
      daten.artikel,
      spanne,
      abteilung: gewaehlt,
    );
    if (a.produktionen == 0) {
      return leer(
        t,
        untertitel,
        'Im Zeitraum sind keine Produktionen erfasst. Erfasst werden sie in '
        'der Produktionserfassung.',
      );
    }
    final mittel = a.mittlereAusbeute;
    if (mittel == null) {
      final welche = a.produktionen == 1
          ? 'der erfassten Produktion'
          : 'den ${a.produktionen} erfassten Produktionen';
      return leer(
        t,
        untertitel,
        'Bei $welche fehlt eine plausible Fertigware — ohne sie lässt sich '
        'keine Ausbeute rechnen. Trag sie in der Produktionserfassung nach.',
      );
    }
    final nichtGezaehlt = [
      if (a.unplausibel > 0)
        '${a.unplausibel} mit einer Ausbeute ab 100 % oder von 0 %',
      if (a.ohneAusbeute > 0) '${a.ohneAusbeute} ohne Fertigware',
    ];
    final vs = a.verlaufSpanne;
    final hoechsterVerlust = a.verlauf.fold(
      0.0,
      (m, p) => math.max(m, p.mittlererVerlust ?? 0),
    );

    final verlauf = [
      for (final p in a.verlauf)
        pw.TableRow(
          children: [
            druckZelle(vs.langname(p.abschnitt), groesse: 8.5),
            druckZelle(
              switch (p.mittlererVerlust) {
                final double v => Format.prozent(v),
                null => '-',
              },
              rechts: true,
              fett: p.hatDaten,
              groesse: 8.5,
            ),
            _balkenZelle(
              switch (p.mittlererVerlust) {
                final double v => druckBalken(
                    [(v, _blau)],
                    max: hoechsterVerlust,
                    breite: _balkenBreite,
                  ),
                null => pw.SizedBox(),
              },
            ),
            druckZelle(
              p.hatDaten ? Format.kg(p.verlustKg) : '',
              rechts: true,
              groesse: 8.5,
            ),
            druckZelle(
              p.hatDaten ? '${p.anzahl}' : '',
              rechts: true,
              groesse: 8.5,
            ),
          ],
        ),
    ];

    final spannen = a.spannen;
    var achseVon = 0.0;
    var achseBis = 1.0;
    if (spannen.isNotEmpty) {
      var unten = spannen.first.min;
      var oben = spannen.first.max;
      for (final s in spannen) {
        unten = math.min(unten, s.min);
        oben = math.max(oben, s.max);
      }
      achseVon = (unten * 20).floor() / 20;
      achseBis = (oben * 20).ceil() / 20;
      if (achseBis <= achseVon) achseBis = achseVon + 0.05;
    }
    String prozent(double anteil) => Format.zahl(anteil * 100, nachkomma: 1);
    final spannenZeilen = [
      for (final s in spannen)
        pw.TableRow(
          children: [
            druckZelle(_artikelName(s.artikel), groesse: 8.5),
            druckZelle(
              'Ø ${prozent(s.mittel)} %',
              rechts: true,
              fett: true,
              groesse: 8.5,
            ),
            druckZelle(
              '${prozent(s.min)}–${prozent(s.max)} %',
              rechts: true,
              groesse: 8.5,
            ),
            druckZelle('${s.anzahl}×', rechts: true, groesse: 8.5),
            _balkenZelle(
              _spannenBalken(
                von: s.min,
                bis: s.max,
                mitte: s.mittel,
                achseVon: achseVon,
                achseBis: achseBis,
                breite: _balkenBreite,
              ),
            ),
          ],
        ),
    ];

    return setzen(
      r,
      [
        anfang(t, untertitel, [
          druckKennzahlen([
            DruckKennzahl(
              Format.prozent(mittel),
              'Ø Ausbeute je Produktion',
              betont: true,
            ),
            DruckKennzahl(
              Format.kg(a.verlustKg),
              'Verlust (Rohware - Fertigware)',
            ),
            DruckKennzahl(
              '${a.gueltig}',
              a.gueltig == 1
                  ? 'Produktion mit Ausbeute'
                  : 'Produktionen mit Ausbeute',
            ),
          ]),
          if (nichtGezaehlt.isNotEmpty)
            druckHinweis(
              'Von ${a.produktionen} Produktionen nicht gezählt: '
              '${nichtGezaehlt.join(', ')} — wie in der Planung.',
              zeilen: 2,
            ),
        ]),
        if (inhalt.verlaeufe)
          if (a.verlaufPunkte >= 2)
            abschnitt(
              'Ø Verlust ${vs.rasterText}',
              tabelle(
                [
                  druckKopfZelle(
                    vs.raster == StatistikRaster.woche ? 'Woche' : 'Monat',
                  ),
                  druckKopfZelle('Ø Verlust', rechts: true),
                  druckKopfZelle(''),
                  druckKopfZelle('Verlust', rechts: true),
                  druckKopfZelle('Prod.', rechts: true),
                ],
                verlauf,
                const [
                  pw.FlexColumnWidth(),
                  pw.FixedColumnWidth(56),
                  pw.FixedColumnWidth(_balkenSpalte),
                  pw.FixedColumnWidth(70),
                  pw.FixedColumnWidth(40),
                ],
              ),
              zeilen: verlauf.length,
            )
          else
            ohneVerlauf('Produktionen mit Ausbeute', vs),
        if (spannen.isEmpty)
          hinweis(
            'Ab $kSpanneAbProduktionen Produktionen eines Artikels im '
            'Zeitraum zeigt sich hier, wie weit seine Ausbeute schwankt.',
            titel: 'Größte Schwankung je Artikel',
          )
        else
          abschnitt(
            'Größte Schwankung je Artikel',
            tabelle(
              [
                druckKopfZelle('Artikel'),
                druckKopfZelle('Ø', rechts: true),
                druckKopfZelle('schlechteste–beste', rechts: true),
                druckKopfZelle('Prod.', rechts: true),
                druckKopfZelle(''),
              ],
              spannenZeilen,
              const [
                pw.FlexColumnWidth(),
                pw.FixedColumnWidth(60),
                pw.FixedColumnWidth(92),
                pw.FixedColumnWidth(36),
                pw.FixedColumnWidth(_balkenSpalte),
              ],
            ),
            zeilen: spannenZeilen.length,
            danach: [
              druckHinweis(
                'Balken: schlechteste bis beste Ausbeute, Punkt: Ø — Achse '
                '${Format.zahl(achseVon * 100)} % bis '
                '${Format.zahl(achseBis * 100)} %.',
                zeilen: 2,
              ),
            ],
          ),
      ],
      erklaerung:
          'Die Planung rechnet je Artikel mit dem Ø der letzten Produktionen. '
          'Wo die Ausbeute stark schwankt, liegt sie damit leicht daneben — '
          'dort lohnt Puffer oder die Suche nach der Ursache.',
    );
  }

  // ── Teil 5: Leistung ──────────────────────────────────────────────────

  List<pw.Widget> leistung(DruckRahmen r) {
    const t = StatistikTeil.leistung;
    final gewaehlt = abteilung;
    final untertitel = gewaehlt == null
        ? 'erfasste Produktionen mit Zeit'
        : 'erfasste Produktionen · Artikel mit Schritt in '
            '${gewaehlt.anzeigeName}';
    final l = werteLeistungAus(
      daten.produktionen,
      daten.artikel,
      spanne,
      abteilung: gewaehlt,
    );
    if (l.produktionen == 0) {
      return leer(
        t,
        untertitel,
        'Im Zeitraum ist keine Produktion mit Rohware erfasst. Mit Start und '
        'Ende eingetragen, zeigt sich hier, wie viel je Stunde geschafft '
        'wird.',
      );
    }
    final kgh = l.kgProStunde;
    if (kgh == null) {
      final welche = l.produktionen == 1
          ? 'der erfassten Produktion'
          : 'den ${l.produktionen} erfassten Produktionen';
      return leer(
        t,
        untertitel,
        'Bei $welche fehlt die Produktionszeit — ohne sie lässt sich keine '
        'Leistung rechnen. Trag Start und Ende in der Produktionserfassung '
        'ein.',
      );
    }

    final groesste =
        l.zeitverbraucher.isEmpty ? 0.0 : l.zeitverbraucher.first.minuten;
    final zeitZeilen = [
      for (final a in l.zeitverbraucher)
        pw.TableRow(
          children: [
            druckZelle(_artikelName(a.artikel), groesse: 8.5),
            druckZelle(Zeit.kurz(a.minuten), rechts: true, groesse: 8.5),
            druckZelle(
              'Ø ${_kgh(a.kgProStunde)}',
              rechts: true,
              groesse: 8.5,
            ),
            druckZelle('${a.anzahl}×', rechts: true, groesse: 8.5),
            _balkenZelle(
              druckBalken(
                [(a.minuten, _blau)],
                max: groesste,
                breite: _balkenBreite,
              ),
            ),
          ],
        ),
    ];

    var weiteste = 0.0;
    for (final a in l.abweichungen) {
      weiteste = math.max(weiteste, (a.abweichung ?? 0.0).abs());
    }
    final grenze = math.min(math.max((weiteste * 4).ceil() / 4, 0.5), 1.0);
    final abweichungsZeilen = [
      for (final a in l.abweichungen)
        pw.TableRow(
          children: [
            druckZelle(_artikelName(a.artikel), groesse: 8.5),
            druckZelle(
              '${Format.zahl(a.kgProStunde)} statt '
              '${Format.zahl(a.hinterlegt ?? 0)} kg/h',
              rechts: true,
              groesse: 8.5,
            ),
            druckZelle(
              _abweichungText(a.abweichung ?? 0),
              rechts: true,
              fett: true,
              groesse: 8.5,
            ),
            _balkenZelle(
              _abweichungsBalken(
                a.abweichung ?? 0,
                grenze: grenze,
                breite: _balkenBreite,
              ),
            ),
          ],
        ),
    ];

    final abweichungTitel = l.verglichen == 0
        ? 'Abweichung von den Leistungsdaten'
        : 'Abweichung von den Leistungsdaten · ${l.abweichend} von '
            '${l.verglichen} Artikeln';
    final schwelle = Format.prozent(kLeistungAbweichungAb, nachkomma: 0);

    return setzen(
      r,
      [
        anfang(t, untertitel, [
          druckKennzahlen([
            DruckKennzahl(_kgh(kgh), 'Ø Rohware je Stunde', betont: true),
            DruckKennzahl(Zeit.kurz(l.minuten), 'Produktionszeit'),
            DruckKennzahl(
              '${l.mitZeit}',
              l.mitZeit == 1 ? 'Produktion mit Zeit' : 'Produktionen mit Zeit',
            ),
          ]),
          if (l.ohneZeit > 0)
            druckHinweis(
              'Von ${l.produktionen} Produktionen nicht gezählt: '
              '${l.ohneZeit} ohne Produktionszeit.',
            ),
        ]),
        abschnitt(
          'Die meiste Produktionszeit',
          tabelle(
            [
              druckKopfZelle('Artikel'),
              druckKopfZelle('Zeit', rechts: true),
              druckKopfZelle('Leistung', rechts: true),
              druckKopfZelle('Prod.', rechts: true),
              druckKopfZelle(''),
            ],
            zeitZeilen,
            const [
              pw.FlexColumnWidth(),
              pw.FixedColumnWidth(60),
              pw.FixedColumnWidth(84),
              pw.FixedColumnWidth(36),
              pw.FixedColumnWidth(_balkenSpalte),
            ],
          ),
          zeilen: zeitZeilen.length,
        ),
        if (l.abweichungen.isNotEmpty)
          abschnitt(
            abweichungTitel,
            tabelle(
              [
                druckKopfZelle('Artikel'),
                druckKopfZelle('gemessen statt hinterlegt', rechts: true),
                druckKopfZelle('Abw.', rechts: true),
                druckKopfZelle(''),
              ],
              abweichungsZeilen,
              const [
                pw.FlexColumnWidth(),
                pw.FixedColumnWidth(130),
                pw.FixedColumnWidth(44),
                pw.FixedColumnWidth(_balkenSpalte),
              ],
            ),
            zeilen: abweichungsZeilen.length,
            danach: [
              _legende([
                (_orange, 'langsamer als hinterlegt'),
                (_blau, 'schneller als hinterlegt'),
              ]),
              if (l.abweichend > l.abweichungen.length)
                druckHinweis(
                  'Gezeigt sind die ${l.abweichungen.length} Artikel mit der '
                  'größten Abweichung.',
                ),
              druckHinweis(
                'Strich: hinterlegte Leistung — Achse ±'
                '${Format.prozent(grenze, nachkomma: 0)}.',
              ),
            ],
          )
        else
          hinweis(
            titel: abweichungTitel,
            zeilen: 3,
            l.verglichen == 0
                ? 'Ab $kLeistungVergleichAb Produktionen mit Zeit vergleicht '
                    'die Statistik einen Artikel mit den Leistungsdaten seiner '
                    'Bratstraße. Im Zeitraum hat das noch kein Artikel.'
                : l.verglichen == 1
                    ? 'Der vergleichbare Artikel liegt weniger als $schwelle '
                        'neben seinen Leistungsdaten.'
                    : 'Alle ${l.verglichen} vergleichbaren Artikel liegen '
                        'weniger als $schwelle neben ihren Leistungsdaten.',
          ),
      ],
      erklaerung:
          'Leistung heißt hier: Rohware je Stunde Produktionszeit, wie sie bei '
          'der Erfassung eingetragen wird. An der Bratstraße rechnet die '
          'Planung mit dem Ø der letzten Produktionen — hinterlegte '
          'Leistungsdaten gelten dort nur, solange keine erfasst sind. Weichen '
          'sie stark ab, lohnt es, sie im Artikel nachzuziehen.',
    );
  }

  // ── Teil 6: Produktmix ────────────────────────────────────────────────

  List<pw.Widget> produktmix(DruckRahmen r) {
    const t = StatistikTeil.produktmix;
    final gewaehlt = abteilung;
    final untertitel = gewaehlt == null
        ? 'Rohware aus den erfassten Produktionen'
        : 'Rohware · Artikel mit Schritt in ${gewaehlt.anzeigeName}';
    final m = werteProduktmixAus(
      daten.produktionen,
      daten.artikel,
      spanne,
      abteilung: gewaehlt,
    );
    if (m.kgGesamt <= 0) {
      return leer(
        t,
        untertitel,
        'Im Zeitraum sind keine Produktionen mit Rohware erfasst.',
      );
    }
    final groessteGruppe = m.gruppen.fold(0.0, (x, g) => math.max(x, g.kg));
    final gruppen = [
      for (final g in m.gruppen)
        pw.TableRow(
          children: [
            druckZelle(
              g.name,
              groesse: 8.5,
              farbe: g.ohneGruppe ? kDruckGrau : PdfColors.black,
            ),
            druckZelle(Format.kg(g.kg), rechts: true, groesse: 8.5),
            druckZelle(
              Format.prozent(g.kg / m.kgGesamt),
              rechts: true,
              groesse: 8.5,
            ),
            druckZelle('${g.produktionen}', rechts: true, groesse: 8.5),
            _balkenZelle(
              druckBalken(
                [(g.kg, g.ohneGruppe || g.uebrige ? _grau : _blau)],
                max: groessteGruppe,
                breite: _balkenBreite,
              ),
            ),
          ],
        ),
    ];
    final groessterArtikel = m.topArtikel.isEmpty ? 0.0 : m.topArtikel.first.kg;
    final artikel = [
      for (final a in m.topArtikel)
        pw.TableRow(
          children: [
            druckZelle(_artikelName(a.artikel), groesse: 8.5),
            druckZelle(Format.kg(a.kg), rechts: true, groesse: 8.5),
            druckZelle(
              Format.prozent(a.kg / m.kgGesamt),
              rechts: true,
              groesse: 8.5,
            ),
            druckZelle('${a.produktionen}', rechts: true, groesse: 8.5),
            _balkenZelle(
              druckBalken(
                [(a.kg, _blau)],
                max: groessterArtikel,
                breite: _balkenBreite,
              ),
            ),
          ],
        ),
    ];
    // Jede Tabelle braucht eigene Zellen — geteilte Widgets setzt das
    // PDF an die falsche Stelle.
    List<pw.Widget> kopfzeile(String erste) => [
          druckKopfZelle(erste),
          druckKopfZelle('Rohware', rechts: true),
          druckKopfZelle('Anteil', rechts: true),
          druckKopfZelle('Prod.', rechts: true),
          druckKopfZelle(''),
        ];
    const breiten = [
      pw.FlexColumnWidth(),
      pw.FixedColumnWidth(70),
      pw.FixedColumnWidth(50),
      pw.FixedColumnWidth(36),
      pw.FixedColumnWidth(_balkenSpalte),
    ];
    final anteilOhne = m.kgOhneGruppe / m.kgGesamt;

    return setzen(r, [
      anfang(t, untertitel, [
        druckKennzahlen([
          DruckKennzahl(Format.kg(m.kgGesamt), 'Rohware', betont: true),
          DruckKennzahl(
            '${m.produktionen}',
            m.produktionen == 1 ? 'Produktion' : 'Produktionen',
          ),
          DruckKennzahl('${m.artikelAnzahl}', 'Artikel'),
        ]),
      ]),
      abschnitt(
        'Nach Produktgruppe',
        tabelle(kopfzeile('Gruppe'), gruppen, breiten),
        zeilen: gruppen.length,
        danach: [
          if (anteilOhne >= 0.2)
            druckHinweis(
              '${Format.prozent(anteilOhne, nachkomma: 0)} der Rohware '
              'stammen von Artikeln ohne Produktgruppe. Die Gruppe wird in '
              'den Stammdaten des Artikels gepflegt.',
              zeilen: 2,
            ),
        ],
      ),
      abschnitt(
        m.topArtikel.length == 1
            ? 'Der größte Artikel'
            : 'Die ${m.topArtikel.length} größten Artikel',
        tabelle(kopfzeile('Artikel'), artikel, breiten),
        zeilen: artikel.length,
      ),
    ]);
  }

  // ── Teil 7: Stammdaten-Pflege ─────────────────────────────────────────

  List<pw.Widget> pflege(DruckRahmen r) {
    const t = StatistikTeil.pflege;
    const untertitel = 'alle Artikel · gleich welche Abteilung';
    final p = wertePflegeAus(daten.artikel, daten.aktiveArtikel);
    if (p.artikel == 0) {
      return leer(t, untertitel, 'Es sind noch keine Artikel angelegt.');
    }
    final zeilen = [
      for (final z in p.zeilen)
        pw.TableRow(
          children: [
            druckZelle(z.luecke.titel, groesse: 8.5),
            druckZelle('${z.anzahl}', rechts: true, fett: true, groesse: 8.5),
            druckZelle(
              z.aktiv > 0 ? '${z.aktiv} aktiv' : '',
              rechts: true,
              groesse: 8.5,
            ),
            _balkenZelle(
              druckBalken(
                [
                  (z.aktiv.toDouble(), _blau),
                  ((z.anzahl - z.aktiv).toDouble(), _blauBlass),
                ],
                max: p.artikel.toDouble(),
                breite: _balkenBreite,
              ),
            ),
          ],
        ),
    ];
    final bloecke = setzen(r, [
      anfang(t, untertitel, [
        druckKennzahlen([
          DruckKennzahl('${p.artikel}', 'Artikel', betont: true),
          DruckKennzahl(
            '${p.vollstaendig}',
            'vollständig gepflegt · '
                '${_ganzeProzent(p.anteilVollstaendig)}',
          ),
          DruckKennzahl(
            '${p.aktiv}',
            'aktiv: im Zeitraum produziert oder geplant',
          ),
        ]),
      ]),
      if (p.vollstaendig == p.artikel)
        hinweis(
          p.artikel == 1
              ? 'Dem Artikel fehlt nichts, womit die Planung rechnet.'
              : 'Allen ${p.artikel} Artikeln fehlt nichts, womit die Planung '
                  'rechnet.',
        )
      else
        abschnitt(
          'Artikel mit Lücken',
          tabelle(
            [
              druckKopfZelle('Lücke'),
              druckKopfZelle('Artikel', rechts: true),
              druckKopfZelle('davon', rechts: true),
              druckKopfZelle(''),
            ],
            zeilen,
            const [
              pw.FlexColumnWidth(),
              pw.FixedColumnWidth(48),
              pw.FixedColumnWidth(64),
              pw.FixedColumnWidth(_balkenSpalte),
            ],
          ),
          zeilen: zeilen.length,
          danach: [
            _legende(const [
              (_blau, 'aktiv: im Zeitraum produziert oder geplant'),
              (_blauBlass, 'übrige'),
            ]),
          ],
        ),
    ]);
    if (!inhalt.erklaerungen) return bloecke;
    // Die Liste darf über die Seite laufen — nur der Titel nicht allein.
    return [
      ...bloecke,
      ...druckGruppe(
        [
          druckZwischentitel('Was fehlt — und was daraus folgt'),
          for (final z in p.zeilen)
            druckHinweis('${z.luecke.titel}: ${z.luecke.folge}', zeilen: 3),
          druckHinweis(
            'Gezählt wie in der Artikelliste. Am meisten bringt die Pflege '
            'bei den aktiven — mit ihnen rechnet die Planung gerade.',
            zeilen: 2,
          ),
        ],
        zusammen: false,
        rahmen: r,
        frei: 120,
      ),
    ];
  }
}
