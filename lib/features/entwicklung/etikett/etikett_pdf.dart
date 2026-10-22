import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/format.dart';
import '../../../core/utils/pdf_text.dart';
import 'etikett.dart';

// Das Etikett eines Stands als PDF-Entwurf: zum Abstimmen mit dem Kunden
// oder der Etikettendruckerei, nicht als Druckvorlage. Die Angaben, die
// erst beim Verpacken feststehen, stehen grau als Platzhalter darin.

const PdfColor _grau = PdfColors.grey700;
const PdfColor _hell = PdfColors.grey500;
const PdfColor _linie = PdfColors.grey400;

pw.Widget _text(
  String text, {
  double groesse = 9,
  bool fett = false,
  PdfColor? farbe,
  bool kursiv = false,
}) =>
    pw.Text(
      pdfText(text),
      style: pw.TextStyle(
        fontSize: groesse,
        fontWeight: fett ? pw.FontWeight.bold : null,
        fontStyle: kursiv ? pw.FontStyle.italic : null,
        color: farbe,
      ),
    );

/// Baut den Entwurf als PDF.
Future<Uint8List> baueEtikettPdf(EtikettInhalt e, {DateTime? erstellt}) {
  final jetzt = erstellt ?? DateTime.now();
  final doc = pw.Document(
    title: 'Etikett ${e.bezeichnung}',
    creator: 'Produktions Planer',
  );
  final theme = pw.ThemeData.withFont(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    italic: pw.Font.helveticaOblique(),
  );

  final etikett = pw.Container(
    width: 110 * PdfPageFormat.mm,
    padding: const pw.EdgeInsets.all(4 * PdfPageFormat.mm),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _text(e.bezeichnung, groesse: 12, fett: true),
        pw.SizedBox(height: 6),
        pw.RichText(
          text: pw.TextSpan(
            style: const pw.TextStyle(fontSize: 8),
            children: [
              pw.TextSpan(
                text: 'Zutaten: ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.TextSpan(text: pdfText(e.zutatenliste)),
            ],
          ),
        ),
        if (e.spurenSatz.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          _text(e.spurenSatz, groesse: 8),
        ],
        pw.SizedBox(height: 6),
        _text('Durchschnittliche Nährwerte je 100 g', groesse: 8, fett: true),
        pw.SizedBox(height: 2),
        pw.Table(
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _linie, width: 0.4),
            top: pw.BorderSide(color: _linie, width: 0.4),
            bottom: pw.BorderSide(color: _linie, width: 0.4),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(),
            1: pw.FixedColumnWidth(80),
          },
          children: [
            for (final n in e.naehrwerte)
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: pw.EdgeInsets.fromLTRB(n.davon ? 8 : 0, 1.5, 0, 1.5),
                    child: _text(n.label, groesse: 8),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: _text(n.wert, groesse: 8),
                    ),
                  ),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 6),
        if (e.lagerung.isNotEmpty) _text('Lagerung: ${e.lagerung}', groesse: 8),
        if (e.zubereitung.isNotEmpty)
          _text('Zubereitung: ${e.zubereitung}', groesse: 8),
        for (final h in e.hinweise) _text(h, groesse: 8),
        if (e.schutzgas) _text('Unter Schutzatmosphäre verpackt.', groesse: 8),
        pw.SizedBox(height: 4),
        _text(
          e.nettofuellmenge.isEmpty
              ? 'Nettofüllmenge: …'
              : 'Nettofüllmenge: ${e.nettofuellmenge}',
          groesse: 8,
          farbe: e.nettofuellmenge.isEmpty ? _hell : null,
          kursiv: e.nettofuellmenge.isEmpty,
        ),
        _text(
          'Zu verbrauchen bis / mindestens haltbar bis: beim Verpacken',
          groesse: 8,
          farbe: _hell,
          kursiv: true,
        ),
        _text('Los: beim Verpacken', groesse: 8, farbe: _hell, kursiv: true),
        _text(
          'Name und Anschrift des Lebensmittelunternehmers',
          groesse: 8,
          farbe: _hell,
          kursiv: true,
        ),
      ],
    ),
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18 * PdfPageFormat.mm),
      theme: theme,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _text('ETIKETT-ENTWURF', groesse: 9, fett: true, farbe: _grau),
          pw.SizedBox(height: 2),
          _text(e.bezeichnung, groesse: 16, fett: true),
          if (e.stand.isNotEmpty) _text(e.stand, farbe: _grau),
          _text('erstellt am ${Format.datum(jetzt)}', farbe: _grau),
          pw.SizedBox(height: 14),
          etikett,
          if (e.fehlt.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _text('Noch offen', fett: true),
            for (final f in e.fehlt) _text('- $f'),
          ],
          pw.SizedBox(height: 18),
          _text(
            'Entwurf zur Abstimmung, keine Druckvorlage. Grau: Angaben, die '
            'erst beim Verpacken oder im Etikettendruck feststehen.',
            groesse: 7,
            farbe: _grau,
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
