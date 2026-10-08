import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart' show Tagesaufgabe;
import '../../core/services/tagesaufgaben_service.dart' show AufgabenZelle;
import '../../core/utils/format.dart';
import '../../core/utils/kalenderwoche.dart';
import '../../core/utils/pdf_text.dart';
import '../../core/utils/zeit.dart';
import 'board_providers.dart';

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
  // Drucken
  // -------------------------------------------------------------------------

  /// Öffnet die Druckvorschau für die Woche.
  ///
  /// [abteilungen]: null druckt die gesamte Übersicht, sonst je Abteilung
  /// ein eigenes Blatt — in dieser Reihenfolge.
  static Future<void> druckeWoche(
    WeekBoard board, {
    required Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
    List<Abteilung>? abteilungen,
  }) async {
    final bytes = await wochenDokument(
      board,
      aufgaben: aufgaben,
      abteilungen: abteilungen,
    ).save();
    await Printing.layoutPdf(
      name: _dateiname(
        'Wochenplan KW ${isoKalenderwoche(board.wochenStart)}',
        abteilungen,
      ),
      onLayout: (_) async => bytes,
    );
  }

  /// Öffnet die Druckvorschau für den Tag — [abteilungen] wie bei
  /// [druckeWoche].
  static Future<void> druckeTag(
    DayBoard board, {
    required Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
    List<Abteilung>? abteilungen,
  }) async {
    final bytes = await tagesDokument(
      board,
      aufgaben: aufgaben,
      abteilungen: abteilungen,
    ).save();
    await Printing.layoutPdf(
      name: _dateiname('Tagesplan ${_isoDatum(board.tag)}', abteilungen),
      onLayout: (_) async => bytes,
    );
  }

  // -------------------------------------------------------------------------
  // Woche (Querformat)
  // -------------------------------------------------------------------------

  /// Der Wochenplan als PDF-Dokument — ohne Drucken, damit er sich prüfen
  /// lässt.
  ///
  /// Raster wie im Board: je Anlage eine Zeile, darunter die sonstigen
  /// Aufgaben der Abteilung, Montag bis Freitag als Spalten. Je Auftrag
  /// Artikelnummer, Bezeichnung und Menge — bewusst ohne Zeiten.
  ///
  /// [komprimiert]: false lässt den Text im PDF lesbar — für Tests.
  static pw.Document wochenDokument(
    WeekBoard board, {
    required Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
    List<Abteilung>? abteilungen,
    DateTime? gedrucktAm,
    bool komprimiert = true,
  }) {
    _pruefeAuswahl(abteilungen);
    final kw = isoKalenderwoche(board.wochenStart);
    final doc = _dokument('Wochenplan KW $kw', komprimiert: komprimiert);
    final gedruckt = _gedruckt(gedrucktAm ?? DateTime.now());

    final gruppen = <Abteilung, List<BoardSpur>>{};
    for (final spur in board.spuren) {
      (gruppen[spur.abteilung] ??= <BoardSpur>[]).add(spur);
    }

    if (abteilungen == null) {
      doc.addPage(_wochenBlatt(board, gruppen, aufgaben, gedruckt));
    } else {
      for (final abt in abteilungen) {
        doc.addPage(
          _wochenBlatt(
            board,
            {abt: gruppen[abt] ?? const <BoardSpur>[]},
            aufgaben,
            gedruckt,
            abteilung: abt,
          ),
        );
      }
    }
    return doc;
  }

  /// Ein Blatt der Woche: die gesamte Übersicht ([abteilung] null) oder
  /// das Blatt einer Abteilung.
  static pw.MultiPage _wochenBlatt(
    WeekBoard board,
    Map<Abteilung, List<BoardSpur>> gruppen,
    Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
    String gedruckt, {
    Abteilung? abteilung,
  }) {
    final kw = isoKalenderwoche(board.wochenStart);
    final zeitraum = '${Format.tagKurz(board.tage.first)} - '
        '${Format.tagKurz(board.tage.last)}${board.tage.last.year}';
    final stil = abteilung == null ? _Stil.uebersicht : _Stil.blatt;
    final seiten = _Seiten();

    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 16),
      header: (ctx) {
        seiten.merke(ctx);
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _kopf(
              titel: abteilung?.anzeigeName ?? 'Produktionsplan',
              zeile: abteilung == null
                  ? 'KW $kw · $zeitraum'
                  : 'Wochenplan KW $kw · $zeitraum',
              abteilung: abteilung,
              gedruckt: gedruckt,
            ),
            pw.SizedBox(height: 8),
            _tageKopf(
              board.tage,
              stil,
              erste: abteilung == null ? 'Abteilung / Anlage' : 'Anlage',
            ),
          ],
        );
      },
      footer: (ctx) => _fuss(
        abteilung == null
            ? 'Produktionsplan KW $kw'
            : '${abteilung.anzeigeName} · Wochenplan KW $kw',
        seiten.text(ctx),
      ),
      build: (ctx) => [
        for (final e in gruppen.entries) ...[
          ..._wochenAbteilung(
            board,
            e.key,
            e.value,
            aufgaben,
            stil,
            blatt: abteilung != null,
          ),
          // Luft zwischen den Abteilungen — innerhalb einer Abteilung
          // stoßen die Zeilen aneinander wie in einer Tabelle.
          if (abteilung == null) pw.SizedBox(height: 6),
        ],
      ],
    );
  }

  /// Die Zeilen einer Abteilung: je Spur eine, darunter die sonstigen
  /// Aufgaben.
  ///
  /// In der Übersicht steht die Aufgaben-Zeile nur, wenn es in der Woche
  /// Aufgaben gibt. Auf dem Blatt der Abteilung steht sie immer — dort
  /// ist sie zugleich Platz, um etwas von Hand nachzutragen.
  static List<pw.Widget> _wochenAbteilung(
    WeekBoard board,
    Abteilung abt,
    List<BoardSpur> spuren,
    Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
    _Stil stil, {
    required bool blatt,
  }) {
    final aufgabenJeTag = [
      for (final tag in board.tage)
        aufgaben[(abt.dbValue, tag)] ?? const <Tagesaufgabe>[],
    ];
    final mitAufgaben = blatt || aufgabenJeTag.any((l) => l.isNotEmpty);
    final hatAnlagen = spuren.any((s) => s.istAnlage);

    return [
      for (var i = 0; i < spuren.length; i++)
        ..._wochenZeile(
          abteilung: abt,
          stil: stil,
          label: _spurLabel(
            abt,
            spuren[i],
            erste: i == 0,
            blatt: blatt,
            hatAnlagen: hatAnlagen,
            stil: stil,
          ),
          tage: [
            for (final tag in board.tage)
              [
                for (final t in board.cellFor(spuren[i], tag).tasks)
                  _auftragEintrag(t, stil),
              ],
          ],
        ),
      if (mitAufgaben)
        ..._wochenZeile(
          abteilung: abt,
          stil: stil,
          label: blatt
              ? _label(oben: 'Sonstige Aufgaben', stil: stil)
              : _label(unten: 'Sonstige Aufgaben', kursiv: true, stil: stil),
          tage: [
            for (final liste in aufgabenJeTag)
              [for (final a in liste) _aufgabeEintrag(a, stil)],
          ],
        ),
    ];
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
    // Nicht mit nur einem Eintrag unten auf der Seite anfangen.
    return [pw.NewPage(freeSpace: 120), tabelle];
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
  static pw.Widget _auftragEintrag(BoardTask t, _Stil stil) {
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
      groesse: stil.kaestchen,
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
  static pw.Widget _aufgabeEintrag(Tagesaufgabe a, _Stil stil) {
    return _mitKaestchen(
      erledigt: a.erledigt,
      groesse: stil.kaestchen,
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

  /// Der Tagesplan als PDF-Dokument — ohne Drucken, damit er sich prüfen
  /// lässt.
  ///
  /// Je Abteilung ihre Spuren mit Belegung und einer Tabelle der Aufträge
  /// (Artikelnummer, Bezeichnung, Menge, Dauer), darunter die sonstigen
  /// Aufgaben. [abteilungen] und [komprimiert] wie bei [wochenDokument].
  static pw.Document tagesDokument(
    DayBoard board, {
    required Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
    List<Abteilung>? abteilungen,
    DateTime? gedrucktAm,
    bool komprimiert = true,
  }) {
    _pruefeAuswahl(abteilungen);
    final doc = _dokument(
      'Tagesplan ${Format.datum(board.tag)}',
      komprimiert: komprimiert,
    );
    final gedruckt = _gedruckt(gedrucktAm ?? DateTime.now());

    final gruppen = <Abteilung, List<DayLane>>{};
    for (final lane in board.lanes) {
      (gruppen[lane.abteilung] ??= <DayLane>[]).add(lane);
    }

    if (abteilungen == null) {
      doc.addPage(_tagesBlatt(board, gruppen, aufgaben, gedruckt));
    } else {
      for (final abt in abteilungen) {
        doc.addPage(
          _tagesBlatt(
            board,
            {abt: gruppen[abt] ?? const <DayLane>[]},
            aufgaben,
            gedruckt,
            abteilung: abt,
          ),
        );
      }
    }
    return doc;
  }

  static pw.MultiPage _tagesBlatt(
    DayBoard board,
    Map<Abteilung, List<DayLane>> gruppen,
    Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
    String gedruckt, {
    Abteilung? abteilung,
  }) {
    final tag = board.tag;
    final kw = isoKalenderwoche(tag);
    // Startzeiten setzt kaum jemand — eine Spalte voller Striche wäre nur
    // Ballast. Sie erscheint, sobald auf dem Blatt eine Zeit steht.
    final mitStart = gruppen.values.any(
      (lanes) => lanes.any((l) => l.tasks.any((t) => t.startZeit != null)),
    );
    final seiten = _Seiten();

    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 20),
      header: (ctx) {
        seiten.merke(ctx);
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: _kopf(
            titel: abteilung?.anzeigeName ?? 'Tagesplan',
            zeile: abteilung == null
                ? '${Format.datumLang(tag)} · KW $kw'
                : 'Tagesplan ${Format.datumLang(tag)} · KW $kw',
            abteilung: abteilung,
            gedruckt: gedruckt,
          ),
        );
      },
      footer: (ctx) => _fuss(
        abteilung == null
            ? 'Tagesplan ${Format.datum(tag)}'
            : '${abteilung.anzeigeName} · Tagesplan ${Format.datum(tag)}',
        seiten.text(ctx),
      ),
      build: (ctx) => [
        for (final e in gruppen.entries)
          ..._tagesAbteilung(
            e.key,
            e.value,
            aufgaben[(e.key.dbValue, tag)] ?? const <Tagesaufgabe>[],
            blatt: abteilung != null,
            mitStart: mitStart,
          ),
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

  /// Eine Abteilung im Tagesplan: in der Übersicht mit farbiger Leiste,
  /// je Spur Überschrift und Tabelle, darunter die sonstigen Aufgaben.
  static List<pw.Widget> _tagesAbteilung(
    Abteilung abt,
    List<DayLane> lanes,
    List<Tagesaufgabe> aufgaben, {
    required bool blatt,
    required bool mitStart,
  }) {
    final hatAnlagen = lanes.any((l) => l.spur.istAnlage);
    final ergebnis = <pw.Widget>[];

    void zusammen(List<pw.Widget> teile, {required bool untrennbar}) {
      if (untrennbar) {
        ergebnis.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: teile,
            ),
          ),
        );
      } else {
        // Überschriften nicht allein unten auf der Seite stehen lassen.
        ergebnis
          ..add(pw.NewPage(freeSpace: 120))
          ..addAll(teile);
      }
    }

    for (var i = 0; i < lanes.length; i++) {
      final lane = lanes[i];
      final name = lane.spur.istAnlage
          ? lane.spur.anzeigeName
          : (hatAnlagen ? 'Ohne Anlage' : 'Aufträge');
      zusammen(
        [
          // Die Leiste der Abteilung bleibt bei ihrer ersten Spur — sonst
          // stünde sie womöglich allein unten auf der Seite.
          if (!blatt && i == 0) _abteilungsLeiste(abt),
          _spurKopf(name, lane),
          if (lane.tasks.isEmpty)
            _hinweis('Keine Aufträge.')
          else
            _auftragsTabelle(lane.tasks, mitStart: mitStart),
        ],
        untrennbar: lane.tasks.length <= _spurZusammenBis,
      );
    }
    if (aufgaben.isNotEmpty) {
      zusammen(
        [
          _zwischentitel('Sonstige Aufgaben'),
          for (final a in aufgaben)
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(4, 2, 2, 2),
              child: _mitKaestchen(
                erledigt: a.erledigt,
                groesse: 8,
                child: pw.Text(
                  pdfText(a.inhalt.trim()),
                  maxLines: 6,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: a.erledigt ? _grauErledigt : PdfColors.black,
                  ),
                ),
              ),
            ),
        ],
        untrennbar: aufgaben.length <= _aufgabenZusammenBis,
      );
    }

    ergebnis.add(pw.SizedBox(height: 14));
    return ergebnis;
  }

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

  /// Name der Spur und ihre Belegung an diesem Tag.
  static pw.Widget _spurKopf(String name, DayLane lane) {
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

    return pw.Table(
      border: _gitter,
      columnWidths: {
        0: const pw.FixedColumnWidth(18),
        1: const pw.FixedColumnWidth(58),
        2: const pw.FlexColumnWidth(),
        3: const pw.FixedColumnWidth(62),
        4: const pw.FixedColumnWidth(48),
        if (mitStart) 5: const pw.FixedColumnWidth(40),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.SizedBox(),
            zelle('Art.-Nr.', fett: true),
            zelle('Bezeichnung', fett: true),
            zelle('Menge', fett: true, rechts: true),
            zelle('Dauer', fett: true, rechts: true),
            if (mitStart) zelle('Start', fett: true, rechts: true),
          ],
        ),
        for (final t in tasks)
          pw.TableRow(
            children: [
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

  static pw.Document _dokument(String titel, {required bool komprimiert}) {
    return pw.Document(
      title: titel,
      creator: 'Produktion Planer',
      compress: komprimiert,
      // Einmal für das ganze Dokument: Jedes Blatt nutzt dieselben
      // Schriften, statt sie je Blatt neu anzulegen.
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      ),
    );
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

  /// Ein Eintrag mit Kästchen davor.
  static pw.Widget _mitKaestchen({
    required bool erledigt,
    required double groesse,
    required pw.Widget child,
  }) {
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

  static void _pruefeAuswahl(List<Abteilung>? abteilungen) {
    if (abteilungen != null && abteilungen.isEmpty) {
      throw ArgumentError('Keine Abteilung zum Drucken gewählt.');
    }
  }

  static String _gedruckt(DateTime d) =>
      'Gedruckt ${Format.datum(d)}, ${Format.uhrzeit(d)}';

  /// „2026-10-08" — sortiert sich im Dateinamen richtig.
  static String _isoDatum(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Name, unter dem die Druckvorschau das PDF speichern würde — ohne
  /// Umlaute und Leerzeichen.
  static String _dateiname(String basis, List<Abteilung>? abteilungen) {
    var name = abteilungen != null && abteilungen.length == 1
        ? '$basis ${abteilungen.single.anzeigeName}'
        : basis;
    const umlaute = {
      'ä': 'ae',
      'ö': 'oe',
      'ü': 'ue',
      'Ä': 'Ae',
      'Ö': 'Oe',
      'Ü': 'Ue',
      'ß': 'ss',
    };
    for (final e in umlaute.entries) {
      name = name.replaceAll(e.key, e.value);
    }
    return name.replaceAll(RegExp('[^A-Za-z0-9-]+'), '_');
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

/// Zählt die Seiten EINES Blatts. Bei „je Abteilung ein Blatt" fängt jede
/// Abteilung bei Seite 1 an — ihre Seiten werden ja getrennt verteilt.
///
/// Die Kopfzeile jeder Seite meldet die Seite an, bevor ihre Fußzeile
/// entsteht; die endgültige Fußzeile malt das PDF erst, wenn alle Seiten
/// feststehen.
class _Seiten {
  final List<PdfPage> _liste = <PdfPage>[];

  void merke(pw.Context ctx) {
    if (!_liste.contains(ctx.page)) _liste.add(ctx.page);
  }

  String text(pw.Context ctx) {
    final nr = _liste.indexOf(ctx.page) + 1;
    final von = _liste.length;
    return 'Seite ${nr < 1 ? 1 : nr} von ${von < 1 ? 1 : von}';
  }
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
