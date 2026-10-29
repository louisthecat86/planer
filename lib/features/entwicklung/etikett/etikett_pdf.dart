import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/druck/druck_optionen.dart';
import '../../../core/druck/druck_satz.dart';
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

/// Was auf das Blatt mit dem Entwurf kommt.
class EtikettDruckInhalt {
  const EtikettDruckInhalt({
    this.breiteMm = 110,
    this.kopf = true,
    this.naehrwerte = true,
    this.platzhalter = true,
    this.offen = true,
    this.hinweis = true,
  });

  /// Breite des Etiketts in Millimetern — so groß wie das echte.
  final double breiteMm;

  /// Über dem Etikett: Bezeichnung, Stand und Datum.
  final bool kopf;

  /// Die Nährwerttabelle.
  final bool naehrwerte;

  /// Grau die Angaben, die erst beim Verpacken feststehen.
  final bool platzhalter;

  /// Unter dem Etikett, was noch fehlt.
  final bool offen;

  /// Der Hinweis, dass es ein Entwurf ist.
  final bool hinweis;
}

/// Die wählbaren Breiten des Etiketts in Millimetern.
const List<int> kEtikettBreitenMm = [80, 110, 150];

/// Schlüssel der Wahl im Druckfenster.
abstract final class EtikettWahl {
  static const breite = 'breite';
  static const kopf = 'kopf';
  static const naehrwerte = 'naehrwerte';
  static const platzhalter = 'platzhalter';
  static const offen = 'offen';
  static const hinweis = 'hinweis';
}

/// Der Druck des Entwurfs für das Druckfenster.
DruckAuftrag etikettDruckAuftrag(EtikettInhalt e, {DateTime? erstellt}) {
  const gruppe = 'Auf dem Blatt';
  return DruckAuftrag(
    art: 'etikett',
    titel: 'Etikett-Entwurf drucken',
    untertitel:
        e.stand.isEmpty ? e.bezeichnung : '${e.bezeichnung} · ${e.stand}',
    optionen: [
      DruckWahlEins(
        schluessel: EtikettWahl.breite,
        titel: 'Breite des Etiketts',
        hinweis: 'So breit wie das echte — zum Vergleichen',
        werte: [
          for (final b in kEtikettBreitenMm) DruckWert('$b', '$b mm'),
        ],
        standard: '110',
      ),
      const DruckSchalter(
        schluessel: EtikettWahl.kopf,
        titel: 'Bezeichnung, Stand und Datum',
        gruppe: gruppe,
      ),
      const DruckSchalter(
        schluessel: EtikettWahl.naehrwerte,
        titel: 'Nährwerttabelle',
        gruppe: gruppe,
      ),
      const DruckSchalter(
        schluessel: EtikettWahl.platzhalter,
        titel: 'Platzhalter',
        hinweis: 'MHD, Los und Anschrift — stehen erst beim Verpacken fest',
        gruppe: gruppe,
      ),
      if (e.fehlt.isNotEmpty)
        const DruckSchalter(
          schluessel: EtikettWahl.offen,
          titel: 'Was noch offen ist',
          gruppe: gruppe,
        ),
      const DruckSchalter(
        schluessel: EtikettWahl.hinweis,
        titel: 'Hinweis „Entwurf"',
        gruppe: gruppe,
      ),
    ],
    bauen: (wahl) => etikettDruck(
      e,
      erstellt: erstellt,
      inhalt: EtikettDruckInhalt(
        breiteMm: double.tryParse(wahl.eins(EtikettWahl.breite)) ?? 110,
        kopf: wahl.an(EtikettWahl.kopf),
        naehrwerte: wahl.an(EtikettWahl.naehrwerte),
        platzhalter: wahl.an(EtikettWahl.platzhalter),
        offen: wahl.an(EtikettWahl.offen),
        hinweis: wahl.an(EtikettWahl.hinweis),
      ),
    ),
  );
}

/// Der Entwurf zum Drucken.
DruckDokument etikettDruck(
  EtikettInhalt e, {
  EtikettDruckInhalt inhalt = const EtikettDruckInhalt(),
  DateTime? erstellt,
}) {
  final jetzt = erstellt ?? DateTime.now();
  final etikett = pw.Container(
    width: inhalt.breiteMm * PdfPageFormat.mm,
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
        if (inhalt.naehrwerte) ...[
          pw.SizedBox(height: 6),
          _text(
            'Durchschnittliche Nährwerte je 100 g',
            groesse: 8,
            fett: true,
          ),
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
                      padding: pw.EdgeInsets.fromLTRB(
                        n.davon ? 8 : 0,
                        1.5,
                        0,
                        1.5,
                      ),
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
        ],
        pw.SizedBox(height: 6),
        if (e.lagerung.isNotEmpty) _text('Lagerung: ${e.lagerung}', groesse: 8),
        if (e.zubereitung.isNotEmpty)
          _text('Zubereitung: ${e.zubereitung}', groesse: 8),
        for (final h in e.hinweise) _text(h, groesse: 8),
        if (e.schutzgas) _text('Unter Schutzatmosphäre verpackt.', groesse: 8),
        pw.SizedBox(height: 4),
        if (e.nettofuellmenge.isNotEmpty)
          _text('Nettofüllmenge: ${e.nettofuellmenge}', groesse: 8)
        else if (inhalt.platzhalter)
          _text('Nettofüllmenge: …', groesse: 8, farbe: _hell, kursiv: true),
        if (inhalt.platzhalter) ...[
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
      ],
    ),
  );

  return DruckDokument(
    titel: 'Etikett ${e.bezeichnung}',
    dateiname: druckDateiname(
      'Etikett ${e.stand.isEmpty ? e.bezeichnung : e.stand}',
    ),
    theme: pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
    ),
    blaetter: [
      DruckBlatt(
        rand: const pw.EdgeInsets.all(18 * PdfPageFormat.mm),
        bauen: (_) => DruckSeiten(
          inhalt: (_) => [
            if (inhalt.kopf) ...[
              _text('ETIKETT-ENTWURF', groesse: 9, fett: true, farbe: _grau),
              pw.SizedBox(height: 2),
              _text(e.bezeichnung, groesse: 16, fett: true),
              if (e.stand.isNotEmpty) _text(e.stand, farbe: _grau),
              _text('erstellt am ${Format.datum(jetzt)}', farbe: _grau),
              pw.SizedBox(height: 14),
            ],
            etikett,
            if (inhalt.offen && e.fehlt.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              _text('Noch offen', fett: true),
              for (final f in e.fehlt) _text('- $f'),
            ],
            if (inhalt.hinweis) ...[
              pw.SizedBox(height: 18),
              _text(
                'Entwurf zur Abstimmung, keine Druckvorlage. Grau: Angaben, '
                'die erst beim Verpacken oder im Etikettendruck feststehen.',
                groesse: 7,
                farbe: _grau,
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
