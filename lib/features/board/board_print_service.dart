import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart' show Tagesaufgabe;
import '../../core/druck/druck_optionen.dart' show druckDateiname;
import '../../core/druck/druck_satz.dart';
import '../../core/services/tagesaufgaben_service.dart' show AufgabenZelle;
import '../../core/utils/format.dart';
import '../../core/utils/kalenderwoche.dart';
import '../../core/utils/pdf_text.dart';
import '../../core/utils/zeit.dart';
import 'board_providers.dart';

/// Was vom Plan gedruckt wird — die Wahl im Druckfenster.
class PlanDruckInhalt {
  const PlanDruckInhalt({
    this.abteilungen,
    this.einzeln = false,
    this.wochentage,
    this.aufgaben = true,
    this.erledigte = true,
    this.kaestchen = true,
    this.leereSpuren = true,
    this.belegung = true,
  });

  /// Diese Abteilungen — null: alle. Gedruckt wird in der Reihenfolge des
  /// Boards.
  final Set<Abteilung>? abteilungen;

  /// Je Abteilung ein eigenes Blatt statt der gesamten Übersicht.
  final bool einzeln;

  /// Nur diese Wochentage (1 = Montag) — null: alle. Nur im Wochenplan.
  final Set<int>? wochentage;

  /// Die sonstigen Aufgaben.
  final bool aufgaben;

  /// Was schon erledigt ist — grau mit Haken.
  final bool erledigte;

  /// Ein Kästchen vor jedem Eintrag, zum Abhaken von Hand.
  final bool kaestchen;

  /// Anlagen ohne Aufträge — als leere Zeilen, etwa zum Nachtragen.
  final bool leereSpuren;

  /// Im Tagesplan: Belegung der Spuren und Dauer der Aufträge.
  final bool belegung;
}

/// Druckt das Planungsboard: die Woche im Querformat, den Tag im
/// Hochformat — als gesamte Übersicht oder je Abteilung ein eigenes Blatt,
/// das sich an die Abteilung weitergeben lässt.
///
/// Gedruckt wird in Schwarz und Grau. Die Abteilungsfarbe steht nur als
/// Kante am Rand: So bleibt der Plan auch vom Schwarzweiß-Drucker gut
/// lesbar, und es geht kein Toner für Farbflächen drauf.
///
/// Jeder Auftrag und jede sonstige Aufgabe hat ein Kästchen zum Abhaken
/// von Hand. Was beim Drucken schon erledigt ist, steht grau mit Haken da.
///
/// Zum Seitenumbruch: Das PDF bricht nur zwischen Zeilen um, und keine
/// Zeile darf höher als eine Seite werden — sonst legte es endlos leere
/// Seiten an. Deshalb ist jeder Eintrag eine eigene Tabellenzeile, und
/// lange Texte sind auf wenige Zeilen begrenzt.
class BoardPrintService {
  const BoardPrintService._();

  // -------------------------------------------------------------------------
  // Woche (Querformat)
  // -------------------------------------------------------------------------

  /// Der Wochenplan zum Drucken.
  ///
  /// Raster wie im Board: je Anlage eine Zeile, darunter die sonstigen
  /// Aufgaben der Abteilung, die Tage als Spalten. Je Auftrag
  /// Artikelnummer, Bezeichnung und Menge — bewusst ohne Zeiten.
  ///
  /// [archiviertAm]: ein Plan aus dem Archiv — Kopf und Fuß sagen das,
  /// damit das Blatt nicht für den aktuellen Plan gehalten wird.
  static DruckDokument wochenDruck(
    WeekBoard board, {
    required Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
    PlanDruckInhalt inhalt = const PlanDruckInhalt(),
    DateTime? gedrucktAm,
    DateTime? archiviertAm,
  }) {
    final wochentage = inhalt.wochentage;
    final tage = [
      for (final t in board.tage)
        if (wochentage == null || wochentage.contains(t.weekday)) t,
    ];
    if (tage.isEmpty) {
      throw ArgumentError('Kein Tag zum Drucken gewählt.');
    }
    final kw = isoKalenderwoche(board.wochenStart);
    final gedruckt = _gedruckt(gedrucktAm ?? DateTime.now());

    final gruppen = <Abteilung, List<BoardSpur>>{};
    for (final spur in board.spuren) {
      (gruppen[spur.abteilung] ??= <BoardSpur>[]).add(spur);
    }
    final abteilungen = _auswahl(gruppen.keys, inhalt.abteilungen);

    final plan = _WochenPlan(
      board,
      tage,
      aufgaben,
      inhalt,
      gedruckt,
      archiviertAm: archiviertAm,
    );
    final titel = archiviertAm == null
        ? 'Wochenplan KW $kw'
        : 'Wochenplan KW $kw Archiv';
    return DruckDokument(
      titel: titel,
      dateiname: _dateiname(titel, abteilungen, inhalt),
      blaetter: inhalt.einzeln
          ? [
              for (final abt in abteilungen)
                plan.blatt(
                  {abt: gruppen[abt] ?? const <BoardSpur>[]},
                  abteilung: abt,
                ),
            ]
          : [
              plan.blatt({
                for (final abt in abteilungen)
                  abt: gruppen[abt] ?? const <BoardSpur>[],
              }),
            ],
    );
  }

  /// Bis zu so vielen Einträgen an einem Tag bleibt eine Zeile des Rasters
  /// auf einer Seite zusammen. Eine Eintragszeile ist höchstens rund
  /// 50 Punkt hoch, eine Seite bietet über 450 — das passt sicher.
  static const int _rasterZusammenBis = 8;

  /// Eine Zeile des Wochenrasters (eine Spur oder die sonstigen Aufgaben)
  /// als eigene Tabelle mit denselben Spaltenbreiten wie der Kopf.
  ///
  /// Jeder Eintrag steht in einer eigenen Tabellenzeile ohne Trennlinie:
  /// Es sieht aus wie eine Zelle je Tag, aber ein Seitenumbruch darf
  /// zwischen zwei Einträgen fallen, wenn ein Tag sehr voll ist.
  static List<pw.Widget> _wochenZeile({
    required Abteilung abteilung,
    required pw.Widget label,
    required List<List<pw.Widget>> tage,
    required _Stil stil,
    required DruckRahmen rahmen,
  }) {
    var zeilen = 1;
    for (final eintraege in tage) {
      if (eintraege.length > zeilen) zeilen = eintraege.length;
    }
    // Bis zu einigen Einträgen untrennbar: Ein Seitenumbruch mitten in
    // einer kurzen Zeile hilft niemandem.
    final teilbar = zeilen > _rasterZusammenBis;
    final halb = stil.abstandEintrag / 2;

    final tabelle = pw.Table(
      border: _rahmen,
      columnWidths: _spalten(stil, tage.length),
      children: [
        // Darf die Zeile umbrechen, steht die Beschriftung in einer eigenen
        // Zeile, die sich auf jeder Folgeseite wiederholt — sonst wüsste
        // dort niemand, zu welcher Anlage die Einträge gehören.
        if (teilbar)
          pw.TableRow(
            repeat: true,
            verticalAlignment: pw.TableCellVerticalAlignment.full,
            children: [
              _labelZelle(abteilung, label),
              for (var i = 0; i < tage.length; i++) pw.SizedBox(),
            ],
          ),
        for (var z = 0; z < zeilen; z++)
          pw.TableRow(
            // Volle Höhe: Die Kante der Abteilung läuft lückenlos über
            // alle Einträge.
            verticalAlignment: pw.TableCellVerticalAlignment.full,
            children: [
              _labelZelle(abteilung, !teilbar && z == 0 ? label : null),
              for (final eintraege in tage)
                pw.Padding(
                  padding: pw.EdgeInsets.fromLTRB(
                    4,
                    z == 0 ? 4 : halb,
                    4,
                    z == zeilen - 1 ? 4 : halb,
                  ),
                  child: z < eintraege.length ? eintraege[z] : pw.SizedBox(),
                ),
            ],
          ),
      ],
    );
    if (!teilbar) return [pw.Inseparable(child: tabelle)];
    // Nicht mit nur einem Eintrag unten auf der Seite anfangen — außer das
    // Blatt soll auf eine feste Zahl Seiten passen.
    return [
      if (rahmen.umbrueche) pw.NewPage(freeSpace: 120),
      tabelle,
    ];
  }

  /// Erste Spalte einer Rasterzeile: ein Hauch der Abteilungsfarbe und ihre
  /// Farbe als Kante. Die Beschriftung ([label]) steht nur in einer Zeile.
  static pw.Widget _labelZelle(Abteilung abteilung, pw.Widget? label) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(6, 4, 4, 4),
      decoration: pw.BoxDecoration(
        color: _hell(abteilung.farbwert),
        border: pw.Border(
          left: pw.BorderSide(color: _farbe(abteilung.farbwert), width: 3),
        ),
      ),
      child: label ?? pw.SizedBox(),
    );
  }

  /// Kopfzeile des Rasters mit den Tagen — steht auf jeder Seite.
  static pw.Widget _tageKopf(
    List<DateTime> tage,
    _Stil stil, {
    required String erste,
  }) {
    pw.Widget zelle(String text) => pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(6, 4, 4, 4),
          child: pw.Text(
            pdfText(text),
            maxLines: 1,
            style: pw.TextStyle(
              fontSize: stil.schrift + 1,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );

    return pw.Table(
      border: _gitter,
      columnWidths: _spalten(stil, tage.length),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            zelle(erste),
            for (final t in tage)
              zelle(
                '${Format.wochentage[t.weekday - 1]} ${Format.datumKurz(t)}',
              ),
          ],
        ),
      ],
    );
  }

  /// Erste Spalte fest, die Tage teilen sich den Rest gleichmäßig.
  static Map<int, pw.TableColumnWidth> _spalten(_Stil stil, int tage) => {
        0: pw.FixedColumnWidth(stil.labelBreite),
        for (var i = 1; i <= tage; i++) i: const pw.FlexColumnWidth(),
      };

  /// Beschriftung einer Spur.
  ///
  /// Übersicht: In der ersten Zeile einer Abteilung steht ihr Name, darunter
  /// die Anlage. Auf dem Blatt einer Abteilung steht deren Name schon oben
  /// — dort genügt die Anlage.
  static pw.Widget _spurLabel(
    Abteilung abt,
    BoardSpur spur, {
    required bool erste,
    required bool blatt,
    required bool hatAnlagen,
    required _Stil stil,
  }) {
    // Die Sammelspur heißt neben Anlagen „Ohne Anlage" — wie im Board.
    final anlage = spur.istAnlage
        ? spur.anzeigeName
        : (hatAnlagen ? 'Ohne Anlage' : null);
    if (blatt) return _label(oben: anlage ?? 'Aufträge', stil: stil);
    return _label(
      oben: erste ? abt.anzeigeName : null,
      unten: anlage,
      kursiv: !spur.istAnlage,
      stil: stil,
    );
  }

  /// Zwei Zeilen Beschriftung: [oben] fett, [unten] normal oder kursiv.
  static pw.Widget _label({
    String? oben,
    String? unten,
    bool kursiv = false,
    required _Stil stil,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (oben != null)
          pw.Text(
            pdfText(oben),
            maxLines: 2,
            style: pw.TextStyle(
              fontSize: stil.schrift + 1,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        if (unten != null)
          pw.Padding(
            padding: pw.EdgeInsets.only(top: oben == null ? 0 : 1),
            child: pw.Text(
              pdfText(unten),
              maxLines: 2,
              style: pw.TextStyle(
                fontSize: stil.schrift + 0.5,
                fontStyle: kursiv ? pw.FontStyle.italic : pw.FontStyle.normal,
                color: kursiv ? PdfColors.grey800 : PdfColors.black,
              ),
            ),
          ),
      ],
    );
  }

  /// Ein Auftrag im Wochenraster: oben Artikelnummer und Menge, darunter
  /// die Bezeichnung.
  static pw.Widget _auftragEintrag(
    BoardTask t,
    _Stil stil, {
    required bool kaestchen,
  }) {
    final erledigt = t.erledigt != null;
    final farbe = erledigt ? _grauErledigt : PdfColors.black;
    final fett = pw.TextStyle(
      fontSize: stil.schrift,
      fontWeight: pw.FontWeight.bold,
      color: farbe,
    );
    final normal = pw.TextStyle(fontSize: stil.schrift, color: farbe);
    final nummer = t.artikelnummer.trim();

    return _mitKaestchen(
      erledigt: erledigt,
      groesse: kaestchen ? stil.kaestchen : null,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                // Ohne Nummer rückt die Bezeichnung nach oben.
                child: pw.Text(
                  pdfText(nummer.isEmpty ? t.productName : nummer),
                  maxLines: nummer.isEmpty ? stil.nameZeilen : 1,
                  style: nummer.isEmpty ? normal : fett,
                ),
              ),
              pw.SizedBox(width: 4),
              pw.Text(pdfText(Format.kg(t.mengeKg)), style: fett),
            ],
          ),
          if (nummer.isNotEmpty)
            pw.Text(
              pdfText(t.productName),
              maxLines: stil.nameZeilen,
              style: normal,
            ),
        ],
      ),
    );
  }

  /// Eine sonstige Aufgabe im Wochenraster.
  static pw.Widget _aufgabeEintrag(
    Tagesaufgabe a,
    _Stil stil, {
    required bool kaestchen,
  }) {
    return _mitKaestchen(
      erledigt: a.erledigt,
      groesse: kaestchen ? stil.kaestchen : null,
      child: pw.Text(
        pdfText(a.inhalt.trim()),
        maxLines: stil.aufgabeZeilen,
        style: pw.TextStyle(
          fontSize: stil.schrift,
          color: a.erledigt ? _grauErledigt : PdfColors.black,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tag (Hochformat)
  // -------------------------------------------------------------------------

  /// Der Tagesplan zum Drucken.
  ///
  /// Je Abteilung ihre Spuren mit Belegung und einer Tabelle der Aufträge
  /// (Artikelnummer, Bezeichnung, Menge, Dauer), darunter die sonstigen
  /// Aufgaben.
  static DruckDokument tagesDruck(
    DayBoard board, {
    required Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
    PlanDruckInhalt inhalt = const PlanDruckInhalt(),
    DateTime? gedrucktAm,
  }) {
    final gedruckt = _gedruckt(gedrucktAm ?? DateTime.now());
    final gruppen = <Abteilung, List<DayLane>>{};
    for (final lane in board.lanes) {
      (gruppen[lane.abteilung] ??= <DayLane>[]).add(lane);
    }
    final abteilungen = _auswahl(gruppen.keys, inhalt.abteilungen);
    final plan = _TagesPlan(board, aufgaben, inhalt, gedruckt);
    final titel = 'Tagesplan ${_isoDatum(board.tag)}';
    return DruckDokument(
      titel: 'Tagesplan ${Format.datum(board.tag)}',
      dateiname: _dateiname(titel, abteilungen, inhalt),
      blaetter: inhalt.einzeln
          ? [
              for (final abt in abteilungen)
                plan.blatt(
                  {abt: gruppen[abt] ?? const <DayLane>[]},
                  abteilung: abt,
                ),
            ]
          : [
              plan.blatt({
                for (final abt in abteilungen)
                  abt: gruppen[abt] ?? const <DayLane>[],
              }),
            ],
    );
  }

  /// Bis zu so vielen Aufträgen bleibt eine Spur samt Überschrift auf
  /// einer Seite zusammen: Eine Zeile ist höchstens rund 37 Punkt hoch,
  /// die Seite bietet über 700. Mehr darf über die Seite laufen — die
  /// Kopfzeile der Tabelle wiederholt sich dann.
  static const int _spurZusammenBis = 15;

  /// Bis zu so vielen sonstigen Aufgaben (je höchstens sechs Zeilen)
  /// bleiben sie samt Überschrift zusammen.
  static const int _aufgabenZusammenBis = 8;

  /// Leiste mit dem Namen der Abteilung — nur in der Übersicht; auf ihrem
  /// eigenen Blatt steht die Abteilung schon im Kopf.
  static pw.Widget _abteilungsLeiste(Abteilung abt) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 2),
      padding: const pw.EdgeInsets.fromLTRB(8, 4, 6, 4),
      decoration: pw.BoxDecoration(
        color: _hell(abt.farbwert),
        border: pw.Border(
          left: pw.BorderSide(color: _farbe(abt.farbwert), width: 4),
        ),
      ),
      child: pw.Text(
        pdfText(abt.anzeigeName),
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  /// Name der Spur und — mit [belegung] — ihre Belegung an diesem Tag.
  static pw.Widget _spurKopf(
    String name,
    DayLane lane, {
    required bool belegung,
  }) {
    final ueberbucht = lane.status == CapacityStatus.ueberbucht;
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(2, 6, 2, 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Text(
              pdfText(name),
              maxLines: 1,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if (belegung)
            pw.Text(
              pdfText(
                'Belegt ${Zeit.kurzOhneEinheit(lane.belegtMinuten)} von '
                '${Zeit.kurz(lane.kapazitaetMinuten)}'
                '${ueberbucht ? ' · überbucht' : ''}',
              ),
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight:
                    ueberbucht ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: ueberbucht ? PdfColors.black : PdfColors.grey700,
              ),
            ),
        ],
      ),
    );
  }

  /// Die Aufträge einer Spur — die Kopfzeile wiederholt sich, wenn die
  /// Tabelle über die Seite läuft.
  static pw.Widget _auftragsTabelle(
    List<BoardTask> tasks, {
    required bool mitStart,
    required bool mitDauer,
    required bool kaestchen,
  }) {
    pw.Widget zelle(
      String text, {
      bool fett = false,
      bool rechts = false,
      int zeilen = 1,
      PdfColor farbe = PdfColors.black,
    }) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(
            pdfText(text),
            maxLines: zeilen,
            textAlign: rechts ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: fett ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: farbe,
            ),
          ),
        );

    // Die Spalten der Reihe nach — ohne Kästchen und Dauer rücken die
    // übrigen auf.
    var nr = 0;
    final spalten = <int, pw.TableColumnWidth>{
      if (kaestchen) nr++: const pw.FixedColumnWidth(18),
      nr++: const pw.FixedColumnWidth(58),
      nr++: const pw.FlexColumnWidth(),
      nr++: const pw.FixedColumnWidth(62),
      if (mitDauer) nr++: const pw.FixedColumnWidth(48),
      if (mitStart) nr++: const pw.FixedColumnWidth(40),
    };

    return pw.Table(
      border: _gitter,
      columnWidths: spalten,
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            if (kaestchen) pw.SizedBox(),
            zelle('Art.-Nr.', fett: true),
            zelle('Bezeichnung', fett: true),
            zelle('Menge', fett: true, rechts: true),
            if (mitDauer) zelle('Dauer', fett: true, rechts: true),
            if (mitStart) zelle('Start', fett: true, rechts: true),
          ],
        ),
        for (final t in tasks)
          pw.TableRow(
            children: [
              if (kaestchen)
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(5, 3.5, 3, 3),
                  child: _kaestchen(erledigt: t.erledigt != null, groesse: 8),
                ),
              zelle(
                t.artikelnummer.trim().isEmpty ? '-' : t.artikelnummer.trim(),
                fett: true,
                farbe: _schrift(t),
              ),
              zelle(t.productName, zeilen: 3, farbe: _schrift(t)),
              zelle(Format.kg(t.mengeKg), rechts: true, farbe: _schrift(t)),
              if (mitDauer)
                zelle(
                  Zeit.kurz(t.dauerMinuten),
                  rechts: true,
                  farbe: _schrift(t),
                ),
              if (mitStart)
                zelle(t.startZeit ?? '-', rechts: true, farbe: _schrift(t)),
            ],
          ),
      ],
    );
  }

  /// Schriftfarbe eines Auftrags: grau, wenn er erledigt ist.
  static PdfColor _schrift(BoardTask t) =>
      t.erledigt != null ? _grauErledigt : PdfColors.black;

  static pw.Widget _zwischentitel(String text) => pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(2, 8, 2, 3),
        child: pw.Text(
          pdfText(text),
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      );

  static pw.Widget _hinweis(String text) => pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(4, 1, 2, 2),
        child: pw.Text(
          pdfText(text),
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
        ),
      );

  // -------------------------------------------------------------------------
  // Gemeinsame Teile
  // -------------------------------------------------------------------------

  /// Dünne graue Linien — das Raster soll führen, nicht auffallen.
  static const pw.BorderSide _linie =
      pw.BorderSide(color: PdfColors.grey500, width: 0.5);

  /// Tabelle mit Linien zwischen allen Zeilen und Spalten.
  static const pw.TableBorder _gitter = pw.TableBorder(
    left: _linie,
    top: _linie,
    right: _linie,
    bottom: _linie,
    horizontalInside: _linie,
    verticalInside: _linie,
  );

  /// Wie [_gitter], aber ohne Linien zwischen den Zeilen — für eine
  /// Rasterzeile, deren Einträge je eine eigene Tabellenzeile sind.
  static const pw.TableBorder _rahmen = pw.TableBorder(
    left: _linie,
    top: _linie,
    right: _linie,
    bottom: _linie,
    verticalInside: _linie,
  );

  /// Schrift für Erledigtes: grau, aber noch gut lesbar.
  static const PdfColor _grauErledigt = PdfColors.grey600;

  /// Die gewählten Abteilungen in der Reihenfolge des Boards ([board]);
  /// gewählte, die dort keine Spur haben, danach.
  static List<Abteilung> _auswahl(
    Iterable<Abteilung> board,
    Set<Abteilung>? gewaehlt,
  ) {
    final reihenfolge = [
      ...board,
      for (final abt in Abteilung.values)
        if (!board.contains(abt)) abt,
    ];
    final liste = [
      for (final abt in reihenfolge)
        if (gewaehlt == null ? board.contains(abt) : gewaehlt.contains(abt))
          abt,
    ];
    if (liste.isEmpty) {
      throw ArgumentError('Keine Abteilung zum Drucken gewählt.');
    }
    return liste;
  }

  /// Kopf jedes Blatts: Titel, Zeitraum und wann gedruckt wurde. Auf dem
  /// Blatt einer Abteilung mit ihrer Farbe als Kante.
  static pw.Widget _kopf({
    required String titel,
    required String zeile,
    required Abteilung? abteilung,
    required String gedruckt,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey800, width: 1),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (abteilung != null) ...[
            pw.Container(
              width: 5,
              height: 30,
              color: _farbe(abteilung.farbwert),
            ),
            pw.SizedBox(width: 8),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  pdfText(titel),
                  maxLines: 1,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  pdfText(zeile),
                  maxLines: 1,
                  style: const pw.TextStyle(
                    fontSize: 9.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          pw.Text(
            pdfText(gedruckt),
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _fuss(String links, String rechts) {
    const stil = pw.TextStyle(fontSize: 7, color: PdfColors.grey600);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(pdfText(links), maxLines: 1, style: stil),
          ),
          pw.Text(pdfText(rechts), style: stil),
        ],
      ),
    );
  }

  /// Ein Eintrag mit Kästchen davor — ohne [groesse] ohne Kästchen.
  static pw.Widget _mitKaestchen({
    required bool erledigt,
    required double? groesse,
    required pw.Widget child,
  }) {
    if (groesse == null) return child;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 0.5),
          child: _kaestchen(erledigt: erledigt, groesse: groesse),
        ),
        pw.SizedBox(width: 3),
        pw.Expanded(child: child),
      ],
    );
  }

  /// Kästchen zum Abhaken von Hand — erledigt mit Haken.
  ///
  /// Der Haken ist gezeichnet, nicht geschrieben: Die PDF-Standardschrift
  /// hat kein Häkchen-Zeichen.
  static pw.Widget _kaestchen({
    required bool erledigt,
    required double groesse,
  }) {
    return pw.Container(
      width: groesse,
      height: groesse,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: erledigt ? _grauErledigt : PdfColors.grey800,
          width: 0.6,
        ),
      ),
      child: erledigt
          ? pw.CustomPaint(
              size: PdfPoint(groesse, groesse),
              // PDF zählt von unten nach oben: Der Haken geht links in der
              // Mitte los, unten durch und rechts nach oben.
              painter: (canvas, size) => canvas
                ..setStrokeColor(PdfColors.grey800)
                ..setLineWidth(0.9)
                ..setLineCap(PdfLineCap.round)
                ..setLineJoin(PdfLineJoin.round)
                ..moveTo(size.x * 0.18, size.y * 0.52)
                ..lineTo(size.x * 0.42, size.y * 0.24)
                ..lineTo(size.x * 0.84, size.y * 0.82)
                ..strokePath(),
            )
          : null,
    );
  }

  static String _gedruckt(DateTime d) =>
      'Gedruckt ${Format.datum(d)}, ${Format.uhrzeit(d)}';

  /// „2026-10-08" — sortiert sich im Dateinamen richtig.
  static String _isoDatum(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Name zum Speichern — mit der Abteilung, wenn nur eine auf eigenem
  /// Blatt gedruckt wird.
  static String _dateiname(
    String basis,
    List<Abteilung> abteilungen,
    PlanDruckInhalt inhalt,
  ) =>
      druckDateiname(
        inhalt.einzeln && abteilungen.length == 1
            ? '$basis ${abteilungen.single.anzeigeName}'
            : basis,
      );
}

/// Ein Wochenplan beim Setzen: was in jedes Blatt gehört.
class _WochenPlan {
  _WochenPlan(
    this.board,
    this.tage,
    this.aufgaben,
    this.inhalt,
    this.gedruckt, {
    this.archiviertAm,
  });

  final WeekBoard board;

  /// Der Plan stammt aus dem Archiv — eingefroren zu dieser Zeit.
  final DateTime? archiviertAm;

  /// Die gedruckten Tage.
  final List<DateTime> tage;
  final Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben;
  final PlanDruckInhalt inhalt;
  final String gedruckt;

  /// Ein Blatt der Woche: die gesamte Übersicht ([abteilung] null) oder
  /// das Blatt einer Abteilung.
  DruckBlatt blatt(
    Map<Abteilung, List<BoardSpur>> gruppen, {
    Abteilung? abteilung,
  }) {
    final kw = isoKalenderwoche(board.wochenStart);
    final zeitraum = tage.length == 1
        ? '${Format.tagKurz(tage.single)}${tage.single.year}'
        : '${Format.tagKurz(tage.first)} - '
            '${Format.tagKurz(tage.last)}${tage.last.year}';
    final stil = abteilung == null ? _Stil.uebersicht : _Stil.blatt;

    return DruckBlatt(
      quer: true,
      rand: const pw.EdgeInsets.fromLTRB(24, 20, 24, 16),
      bauen: (r) {
        final zeilen = <pw.Widget>[
          for (final e in gruppen.entries)
            ...abteilungZeilen(
              e.key,
              e.value,
              stil,
              r,
              blatt: abteilung != null,
            ),
        ];
        return DruckSeiten(
          kopf: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              BoardPrintService._kopf(
                titel: abteilung?.anzeigeName ?? 'Produktionsplan',
                zeile: [
                  if (abteilung == null)
                    'KW $kw · $zeitraum'
                  else
                    'Wochenplan KW $kw · $zeitraum',
                  if (archiviertAm case final am?)
                    'Archiv: Stand ${Format.datum(am)}, '
                        '${Format.uhrzeit(am)}',
                ].join(' · '),
                abteilung: abteilung,
                gedruckt: gedruckt,
              ),
              pw.SizedBox(height: 8),
              BoardPrintService._tageKopf(
                tage,
                stil,
                erste: abteilung == null ? 'Abteilung / Anlage' : 'Anlage',
              ),
            ],
          ),
          fuss: (ctx) => BoardPrintService._fuss(
            [
              if (abteilung == null)
                'Produktionsplan KW $kw'
              else
                '${abteilung.anzeigeName} · Wochenplan KW $kw',
              if (archiviertAm != null) 'Archiv',
            ].join(' · '),
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => zeilen.isEmpty
              ? [BoardPrintService._hinweis('Nichts geplant.')]
              : zeilen,
        );
      },
    );
  }

  /// Die Zeilen einer Abteilung: je Spur eine, darunter die sonstigen
  /// Aufgaben. In der Übersicht mit etwas Luft danach — innerhalb einer
  /// Abteilung stoßen die Zeilen aneinander wie in einer Tabelle.
  ///
  /// In der Übersicht steht die Aufgaben-Zeile nur, wenn es in der Woche
  /// Aufgaben gibt. Auf dem Blatt der Abteilung steht sie immer — dort
  /// ist sie zugleich Platz, um etwas von Hand nachzutragen.
  List<pw.Widget> abteilungZeilen(
    Abteilung abt,
    List<BoardSpur> spuren,
    _Stil stil,
    DruckRahmen rahmen, {
    required bool blatt,
  }) {
    bool zeigen(BoardTask t) => inhalt.erledigte || t.erledigt == null;
    final aufgabenJeTag = [
      for (final tag in tage)
        [
          if (inhalt.aufgaben)
            for (final a in aufgaben[(abt.dbValue, tag)] ??
                const <Tagesaufgabe>[])
              if (inhalt.erledigte || !a.erledigt) a,
        ],
    ];
    final mitAufgaben = inhalt.aufgaben &&
        (blatt || aufgabenJeTag.any((l) => l.isNotEmpty));
    final hatAnlagen = spuren.any((s) => s.istAnlage);
    final gezeigt = [
      for (final spur in spuren)
        if (inhalt.leereSpuren ||
            tage.any(
              (tag) => board.cellFor(spur, tag).tasks.any(zeigen),
            ))
          spur,
    ];

    final zeilen = <pw.Widget>[
      for (var i = 0; i < gezeigt.length; i++)
        ...BoardPrintService._wochenZeile(
          abteilung: abt,
          stil: stil,
          rahmen: rahmen,
          label: BoardPrintService._spurLabel(
            abt,
            gezeigt[i],
            erste: i == 0,
            blatt: blatt,
            hatAnlagen: hatAnlagen,
            stil: stil,
          ),
          tage: [
            for (final tag in tage)
              [
                for (final t in board.cellFor(gezeigt[i], tag).tasks)
                  if (zeigen(t))
                    BoardPrintService._auftragEintrag(
                      t,
                      stil,
                      kaestchen: inhalt.kaestchen,
                    ),
              ],
          ],
        ),
      if (mitAufgaben)
        ...BoardPrintService._wochenZeile(
          abteilung: abt,
          stil: stil,
          rahmen: rahmen,
          label: blatt || gezeigt.isEmpty
              ? BoardPrintService._label(
                  oben: blatt ? 'Sonstige Aufgaben' : abt.anzeigeName,
                  unten: blatt ? null : 'Sonstige Aufgaben',
                  stil: stil,
                )
              : BoardPrintService._label(
                  unten: 'Sonstige Aufgaben',
                  kursiv: true,
                  stil: stil,
                ),
          tage: [
            for (final liste in aufgabenJeTag)
              [
                for (final a in liste)
                  BoardPrintService._aufgabeEintrag(
                    a,
                    stil,
                    kaestchen: inhalt.kaestchen,
                  ),
              ],
          ],
        ),
    ];
    if (zeilen.isEmpty || blatt) return zeilen;
    return [...zeilen, pw.SizedBox(height: 6)];
  }
}

/// Ein Tagesplan beim Setzen.
class _TagesPlan {
  _TagesPlan(this.board, this.aufgaben, this.inhalt, this.gedruckt);

  final DayBoard board;
  final Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben;
  final PlanDruckInhalt inhalt;
  final String gedruckt;

  bool _zeigen(BoardTask t) => inhalt.erledigte || t.erledigt == null;

  DruckBlatt blatt(
    Map<Abteilung, List<DayLane>> gruppen, {
    Abteilung? abteilung,
  }) {
    final tag = board.tag;
    final kw = isoKalenderwoche(tag);
    // Startzeiten setzt kaum jemand — eine Spalte voller Striche wäre nur
    // Ballast. Sie erscheint, sobald auf dem Blatt eine Zeit steht.
    final mitStart = gruppen.values.any(
      (lanes) => lanes.any(
        (l) => l.tasks.any((t) => t.startZeit != null && _zeigen(t)),
      ),
    );
    return DruckBlatt(
      rand: const pw.EdgeInsets.fromLTRB(28, 24, 28, 20),
      bauen: (r) {
        final teile = <pw.Widget>[
          for (final e in gruppen.entries)
            ...abteilungTeile(
              e.key,
              e.value,
              r,
              blatt: abteilung != null,
              mitStart: mitStart,
            ),
        ];
        return DruckSeiten(
          kopf: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: BoardPrintService._kopf(
              titel: abteilung?.anzeigeName ?? 'Tagesplan',
              zeile: abteilung == null
                  ? '${Format.datumLang(tag)} · KW $kw'
                  : 'Tagesplan ${Format.datumLang(tag)} · KW $kw',
              abteilung: abteilung,
              gedruckt: gedruckt,
            ),
          ),
          fuss: (ctx) => BoardPrintService._fuss(
            abteilung == null
                ? 'Tagesplan ${Format.datum(tag)}'
                : '${abteilung.anzeigeName} · Tagesplan ${Format.datum(tag)}',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile.isEmpty
              ? [BoardPrintService._hinweis('Nichts geplant.')]
              : teile,
        );
      },
    );
  }

  /// Eine Abteilung im Tagesplan: in der Übersicht mit farbiger Leiste,
  /// je Spur Überschrift und Tabelle, darunter die sonstigen Aufgaben.
  List<pw.Widget> abteilungTeile(
    Abteilung abt,
    List<DayLane> lanes,
    DruckRahmen rahmen, {
    required bool blatt,
    required bool mitStart,
  }) {
    final hatAnlagen = lanes.any((l) => l.spur.istAnlage);
    final liste = [
      if (inhalt.aufgaben)
        for (final a in aufgaben[(abt.dbValue, board.tag)] ??
            const <Tagesaufgabe>[])
          if (inhalt.erledigte || !a.erledigt) a,
    ];
    final ergebnis = <pw.Widget>[];
    // Die Leiste der Abteilung steht über ihrem ersten Teil — sonst
    // stünde sie womöglich allein unten auf der Seite.
    var leiste = !blatt;

    void zusammen(List<pw.Widget> teile, {required bool untrennbar}) {
      final mitLeiste = [
        if (leiste) BoardPrintService._abteilungsLeiste(abt),
        ...teile,
      ];
      leiste = false;
      if (untrennbar) {
        ergebnis.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: mitLeiste,
            ),
          ),
        );
      } else {
        // Überschriften nicht allein unten auf der Seite stehen lassen.
        ergebnis
          ..add(
            rahmen.umbrueche ? pw.NewPage(freeSpace: 120) : pw.SizedBox(),
          )
          ..addAll(mitLeiste);
      }
    }

    for (final lane in lanes) {
      final tasks = [
        for (final t in lane.tasks)
          if (_zeigen(t)) t,
      ];
      if (tasks.isEmpty && !inhalt.leereSpuren) continue;
      final name = lane.spur.istAnlage
          ? lane.spur.anzeigeName
          : (hatAnlagen ? 'Ohne Anlage' : 'Aufträge');
      zusammen(
        [
          BoardPrintService._spurKopf(name, lane, belegung: inhalt.belegung),
          if (tasks.isEmpty)
            BoardPrintService._hinweis('Keine Aufträge.')
          else
            BoardPrintService._auftragsTabelle(
              tasks,
              mitStart: mitStart,
              mitDauer: inhalt.belegung,
              kaestchen: inhalt.kaestchen,
            ),
        ],
        untrennbar: tasks.length <= BoardPrintService._spurZusammenBis,
      );
    }
    if (liste.isNotEmpty) {
      zusammen(
        [
          BoardPrintService._zwischentitel('Sonstige Aufgaben'),
          for (final a in liste)
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(4, 2, 2, 2),
              child: BoardPrintService._mitKaestchen(
                erledigt: a.erledigt,
                groesse: inhalt.kaestchen ? 8 : null,
                child: pw.Text(
                  pdfText(a.inhalt.trim()),
                  maxLines: 6,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: a.erledigt
                        ? BoardPrintService._grauErledigt
                        : PdfColors.black,
                  ),
                ),
              ),
            ),
        ],
        untrennbar: liste.length <= BoardPrintService._aufgabenZusammenBis,
      );
    }
    if (ergebnis.isEmpty) return ergebnis;
    ergebnis.add(pw.SizedBox(height: 14));
    return ergebnis;
  }
}

/// Schriftgrößen und Maße für die Übersicht und das Blatt einer Abteilung.
/// Auf dem Blatt ist mehr Platz — dort darf die Schrift größer sein.
class _Stil {
  const _Stil({
    required this.schrift,
    required this.labelBreite,
    required this.kaestchen,
    required this.abstandEintrag,
    required this.nameZeilen,
    required this.aufgabeZeilen,
  });

  /// Schriftgröße der Einträge.
  final double schrift;

  /// Breite der ersten Spalte.
  final double labelBreite;

  /// Kantenlänge der Kästchen.
  final double kaestchen;

  /// Abstand zwischen zwei Einträgen eines Tages.
  final double abstandEintrag;

  /// Höchstens so viele Zeilen für eine Artikelbezeichnung …
  final int nameZeilen;

  /// … und für eine sonstige Aufgabe. Hält jede Eintragszeile niedriger
  /// als eine Seite.
  final int aufgabeZeilen;

  static const uebersicht = _Stil(
    schrift: 7.5,
    labelBreite: 112,
    kaestchen: 6.5,
    abstandEintrag: 3,
    nameZeilen: 2,
    aufgabeZeilen: 3,
  );

  static const blatt = _Stil(
    schrift: 9,
    labelBreite: 104,
    kaestchen: 7.5,
    abstandEintrag: 4,
    nameZeilen: 3,
    aufgabeZeilen: 4,
  );
}

/// App-Farbe (0xAARRGGBB) als PDF-Farbe — so übernimmt der Ausdruck exakt
/// die Abteilungsfarben aus dem Board.
PdfColor _farbe(int argb) => PdfColor(
      ((argb >> 16) & 0xFF) / 255,
      ((argb >> 8) & 0xFF) / 255,
      (argb & 0xFF) / 255,
    );

/// Ein Hauch der Abteilungsfarbe für die erste Spalte — fast weiß, damit
/// der Schwarzweiß-Druck sauber bleibt.
PdfColor _hell(int argb) {
  const weiss = 0.9;
  double misch(int kanal) {
    final c = kanal / 255;
    return c + (1 - c) * weiss;
  }

  return PdfColor(
    misch((argb >> 16) & 0xFF),
    misch((argb >> 8) & 0xFF),
    misch(argb & 0xFF),
  );
}
