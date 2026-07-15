import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'board_providers.dart';

/// Wandelt eine App-Farbe (0xAARRGGBB) in eine PDF-Farbe. So übernimmt der
/// Ausdruck exakt die Abteilungsfarben aus dem Board.
PdfColor _pdf(int argb) => PdfColor(
      ((argb >> 16) & 0xFF) / 255,
      ((argb >> 8) & 0xFF) / 255,
      (argb & 0xFF) / 255,
    );

/// Aufgehellte Variante einer Farbe für Zellenhintergründe (mischt mit Weiß).
PdfColor _pdfHell(int argb, double weissAnteil) {
  final r = ((argb >> 16) & 0xFF) / 255;
  final g = ((argb >> 8) & 0xFF) / 255;
  final b = (argb & 0xFF) / 255;
  double misch(double c) => c + (1 - c) * weissAnteil;
  return PdfColor(misch(r), misch(g), misch(b));
}

/// Erzeugt druckbare A4-PDFs aus den Board-Daten.
///
/// - [druckeWoche]: Querformat, Raster Abteilungen × Mo–Fr, je Zelle die
///   Aufträge (Artikel · Menge · Dauer) plus Auslastungs-Summe.
/// - [druckeTag]: Hochformat, je Abteilung eine Tabelle (Artikel, Menge,
///   Dauer, Start) mit Auslastung im Abschnittskopf.
///
/// Beide rufen den System-Druck-/Vorschau-Dialog über `printing` auf.
class BoardPrintService {
  const BoardPrintService._();

  static const _dayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];
  static const _wochentage = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  // -------------------------------------------------------------------------
  // Öffentliche API
  // -------------------------------------------------------------------------

  static Future<void> druckeWoche(WeekBoard board) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => _wocheContent(board),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  static Future<void> druckeTag(DayBoard board) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => _tagContent(board),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  // -------------------------------------------------------------------------
  // Woche (Querformat)
  // -------------------------------------------------------------------------

  static pw.Widget _wocheContent(WeekBoard board) {
    final kw = _isoKw(board.wochenStart);
    final mo = board.tage.first;
    final fr = board.tage.last;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Produktionsplan - KW $kw',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          '${mo.day}.${mo.month}. - ${fr.day}.${fr.month}.${fr.year}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FixedColumnWidth(95),
            for (var i = 1; i <= board.tage.length; i++)
              i: const pw.FlexColumnWidth(),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _headerCell('Abteilung'),
                for (var i = 0; i < board.tage.length; i++)
                  _headerCell(
                    '${_dayLabels[i]} '
                    '${board.tage[i].day}.${board.tage[i].month}.',
                  ),
              ],
            ),
            for (final spur in board.spuren)
              pw.TableRow(
                children: [
                  // Zeilenkopf in der Abteilungsfarbe — der Ausdruck spiegelt
                  // die Farbgebung des Boards.
                  _deptCell(
                    spur.anzeigeName,
                    farbwert: spur.abteilung.farbwert,
                    einger: spur.istAnlage,
                  ),
                  for (final tag in board.tage)
                    _wocheTagZelle(
                      board.cellFor(spur, tag),
                      spur.abteilung.farbwert,
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _headerCell(String text) => pw.Container(
        padding: const pw.EdgeInsets.all(4),
        alignment: pw.Alignment.center,
        child: pw.Text(
          text,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        ),
      );

  static pw.Widget _deptCell(
    String name, {
    required int farbwert,
    bool einger = false,
  }) =>
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(4, 4, 4, 4),
        decoration: pw.BoxDecoration(
          // Zeilenkopf in der Abteilungsfarbe: kräftig für die Abteilung,
          // aufgehellt für die eingerückten Anlagen-Spuren.
          color: einger ? _pdfHell(farbwert, 0.82) : _pdf(farbwert),
          border: pw.Border(
            left: pw.BorderSide(color: _pdf(farbwert), width: 3),
          ),
        ),
        child: pw.Text(
          name,
          style: pw.TextStyle(
            fontWeight: einger ? pw.FontWeight.normal : pw.FontWeight.bold,
            fontSize: einger ? 8 : 9,
            // Auf der kräftigen Abteilungsfarbe steht weißer Text.
            color: einger ? PdfColors.black : PdfColors.white,
          ),
        ),
      );

  static pw.Widget _wocheTagZelle(BoardCell cell, int farbwert) {
    final lines = <pw.Widget>[];
    for (final t in cell.tasks) {
      lines.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Farbpunkt in der Abteilungsfarbe statt eines Sonderzeichens.
            pw.Container(
              width: 5,
              height: 5,
              margin: const pw.EdgeInsets.only(top: 2, right: 3),
              decoration: pw.BoxDecoration(
                color: _pdf(farbwert),
                shape: pw.BoxShape.circle,
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                // Nur Artikel und Menge — KEINE Zeitangaben (Wunsch: die
                // Uhrzeiten sollen nicht mitgedruckt werden).
                '${t.productName}  ${t.mengeKg.toStringAsFixed(0)} kg',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      );
    }
    if (lines.isEmpty) {
      lines.add(
        pw.Text(
          '-',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
        ),
      );
    }
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tag (Hochformat)
  // -------------------------------------------------------------------------

  static List<pw.Widget> _tagContent(DayBoard board) {
    final t = board.tag;
    final widgets = <pw.Widget>[
      pw.Text(
        'Tagesplan - ${_wochentage[t.weekday - 1]} '
        '${t.day}.${t.month}.${t.year}',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 12),
    ];

    for (final lane in board.lanes) {
      widgets.add(
        pw.Container(
          width: double.infinity,
          // Abschnittskopf in der Abteilungsfarbe — konsistent zur App.
          color: _pdf(lane.spur.abteilung.farbwert),
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                lane.spur.anzeigeName,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 11,
                  color: PdfColors.white,
                ),
              ),
              pw.Text(
                '${_fmtH(lane.belegtMinuten)} / '
                '${_fmtH(lane.kapazitaetMinuten)} h',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
              ),
            ],
          ),
        ),
      );

      if (lane.tasks.isEmpty) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(6, 3, 6, 3),
            child: pw.Text(
              '-',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
            ),
          ),
        );
      } else {
        widgets.add(
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _cell('Artikel', bold: true),
                  _cell('Menge', bold: true),
                  _cell('Dauer', bold: true),
                  _cell('Start', bold: true),
                ],
              ),
              for (final task in lane.tasks)
                pw.TableRow(
                  children: [
                    _cell(task.productName),
                    _cell('${task.mengeKg.toStringAsFixed(0)} kg'),
                    _cell('${_fmtH(task.dauerMinuten)} h'),
                    _cell(task.startZeit ?? '-'),
                  ],
                ),
            ],
          ),
        );
      }
      widgets.add(pw.SizedBox(height: 12));
    }

    return widgets;
  }

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  // -------------------------------------------------------------------------
  // Helfer
  // -------------------------------------------------------------------------

  static String _fmtH(double minuten) {
    final s = (minuten / 60).toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  static int _isoKw(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final dayOfYear = d.difference(DateTime(d.year, 1, 1)).inDays + 1;
    final wday = d.weekday;
    final wn = ((dayOfYear - wday + 10) / 7).floor();
    if (wn < 1) return _isoKw(DateTime(d.year - 1, 12, 31));
    if (wn > 52) {
      final dec31 = DateTime(d.year, 12, 31);
      if (dec31.weekday < 4) return 1;
    }
    return wn;
  }
}