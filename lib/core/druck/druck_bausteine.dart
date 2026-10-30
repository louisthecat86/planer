/// Bausteine der Listen zum Drucken — Kopf und Fuß eines Blatts, Tabellen,
/// Leisten über Abschnitten, Kennzahlen. Erfassungsliste, Auftragsbestand,
/// Bedarfsliste und Planungsvorschlag sehen damit aus wie der Plan aus dem
/// Board: schwarz und grau, Farbe nur als schmale Kante oder kleiner Punkt
/// neben dem Text — so bleibt alles auch vom Schwarzweiß-Drucker lesbar.
///
/// Zum Seitenumbruch: Das PDF bricht nur zwischen Tabellenzeilen um, und
/// keine Zeile darf höher als eine Seite werden. Texte in Zellen sind
/// deshalb auf wenige Zeilen begrenzt. Eine Tabelle läuft nur über die
/// Seite, wenn sie direkt im Inhalt des Blatts steht — nicht in einer
/// Spalte (siehe [druckGruppe]).
///
/// Bewusst ohne Flutter-Abhängigkeit — die Listen lassen sich so ohne
/// Oberfläche prüfen.
library;

import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/format.dart';
import '../utils/pdf_text.dart';
import 'druck_satz.dart';

/// Dünne graue Linie — das Raster soll führen, nicht auffallen.
const pw.BorderSide kDruckLinie =
    pw.BorderSide(color: PdfColors.grey500, width: 0.5);

/// Tabelle mit Linien zwischen allen Zeilen und Spalten.
const pw.TableBorder kDruckGitter = pw.TableBorder(
  left: kDruckLinie,
  top: kDruckLinie,
  right: kDruckLinie,
  bottom: kDruckLinie,
  horizontalInside: kDruckLinie,
  verticalInside: kDruckLinie,
);

/// Grau für Nebensächliches und Erledigtes — noch gut lesbar.
const PdfColor kDruckGrau = PdfColors.grey600;

/// Fläche der Kopfzeile einer Tabelle.
const PdfColor kDruckKopfFlaeche = PdfColors.grey200;

/// Fläche einer hervorgehobenen Zeile — etwa der Artikel über seinen
/// Versandtagen.
const PdfColor kDruckZeilenFlaeche = PdfColors.grey100;

/// „Gedruckt 09.10.2026, 14:05"
String druckGedruckt(DateTime d) =>
    'Gedruckt ${Format.datum(d)}, ${Format.uhrzeit(d)}';

/// „2026-10-08" — sortiert sich im Dateinamen richtig.
String druckIsoDatum(DateTime d) => '${d.year}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// App-Farbe (0xAARRGGBB) als PDF-Farbe — so übernimmt der Ausdruck exakt
/// die Farben der App, etwa die der Abteilungen.
PdfColor druckFarbe(int argb) => PdfColor(
      ((argb >> 16) & 0xFF) / 255,
      ((argb >> 8) & 0xFF) / 255,
      (argb & 0xFF) / 255,
    );

/// Ein Hauch von [argb] — fast weiß, damit der Schwarzweiß-Druck sauber
/// bleibt.
PdfColor druckHell(int argb) {
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

/// Kopf eines Blatts: Titel, darunter eine Zeile (Zeitraum, Stand), rechts
/// wann gedruckt wurde. Mit [farbe] steht davor eine Kante in dieser Farbe —
/// auf dem Blatt einer Abteilung ihre.
pw.Widget druckKopf({
  required String titel,
  required String zeile,
  required String gedruckt,
  int? farbe,
  double abstand = 8,
}) {
  return pw.Padding(
    padding: pw.EdgeInsets.only(bottom: abstand),
    child: pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey800, width: 1),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (farbe != null) ...[
            pw.Container(width: 5, height: 30, color: druckFarbe(farbe)),
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
          pw.SizedBox(width: 8),
          pw.Text(
            pdfText(gedruckt),
            style: const pw.TextStyle(fontSize: 7.5, color: kDruckGrau),
          ),
        ],
      ),
    ),
  );
}

/// Fuß eines Blatts: links, was es ist, rechts die Seite.
pw.Widget druckFuss(String links, String rechts) {
  const stil = pw.TextStyle(fontSize: 7, color: kDruckGrau);
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

/// Text in einer Tabellenzelle — höchstens [zeilen] Zeilen.
pw.Widget druckZelle(
  String text, {
  bool fett = false,
  bool rechts = false,
  int zeilen = 1,
  PdfColor farbe = PdfColors.black,
  double groesse = 9,
}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        pdfText(text),
        maxLines: zeilen,
        textAlign: rechts ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: groesse,
          fontWeight: fett ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: farbe,
        ),
      ),
    );

/// Eine Zelle mit zwei Teilen: oben der Text, darunter kleiner und grau
/// (oder in [farbeUnten]) [unten] — etwa Bezeichnung und Herkunft. Ohne
/// [unten] nur der Text.
pw.Widget druckZelleMitZeile(
  String oben,
  String? unten, {
  bool fett = false,
  int zeilenOben = 2,
  int zeilenUnten = 2,
  PdfColor farbe = PdfColors.black,
  PdfColor farbeUnten = kDruckGrau,
  double groesse = 9,
  double einzug = 0,
}) {
  final zweite = unten?.trim() ?? '';
  return pw.Padding(
    padding: pw.EdgeInsets.fromLTRB(4 + einzug, 3, 4, 3),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          pdfText(oben),
          maxLines: zeilenOben,
          style: pw.TextStyle(
            fontSize: groesse,
            fontWeight: fett ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: farbe,
          ),
        ),
        if (zweite.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 1),
            child: pw.Text(
              pdfText(zweite),
              maxLines: zeilenUnten,
              style: pw.TextStyle(fontSize: groesse - 1.5, color: farbeUnten),
            ),
          ),
      ],
    ),
  );
}

/// Überschrift einer Spalte in der Kopfzeile.
pw.Widget druckKopfZelle(String text, {bool rechts = false}) =>
    druckZelle(text, fett: true, rechts: rechts, groesse: 8.5);

/// Kopfzeile einer Tabelle: grau hinterlegt — sie wiederholt sich, wenn die
/// Tabelle über die Seite läuft.
pw.TableRow druckKopfzeile(List<pw.Widget> zellen) => pw.TableRow(
      repeat: true,
      decoration: const pw.BoxDecoration(color: kDruckKopfFlaeche),
      children: zellen,
    );

/// Leiste über einem Abschnitt — ein Tag, ein Kunde, eine Abteilung: der
/// Titel fett, rechts eine graue Angabe, links eine Kante in [farbe] (ohne:
/// grau).
pw.Widget druckLeiste(String titel, {String? rechts, int? farbe}) {
  final kante = farbe == null ? PdfColors.grey600 : druckFarbe(farbe);
  final grund = farbe == null ? kDruckZeilenFlaeche : druckHell(farbe);
  return pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(bottom: 3),
    padding: const pw.EdgeInsets.fromLTRB(8, 4, 6, 4),
    decoration: pw.BoxDecoration(
      color: grund,
      border: pw.Border(left: pw.BorderSide(color: kante, width: 4)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Text(
            pdfText(titel),
            maxLines: 1,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ),
        if (rechts != null && rechts.isNotEmpty) ...[
          pw.SizedBox(width: 8),
          pw.Text(
            pdfText(rechts),
            maxLines: 1,
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
          ),
        ],
      ],
    ),
  );
}

/// Kleine Überschrift — mit [farbe] ein Quadrat davor.
pw.Widget druckZwischentitel(String text, {int? farbe}) => pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(2, 6, 2, 3),
      child: pw.Row(
        children: [
          if (farbe != null) ...[
            pw.Container(width: 7, height: 7, color: druckFarbe(farbe)),
            pw.SizedBox(width: 5),
          ],
          pw.Expanded(
            child: pw.Text(
              pdfText(text),
              maxLines: 1,
              style:
                  pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

/// Ein grauer Hinweis — „Nichts geplant."
pw.Widget druckHinweis(String text, {int zeilen = 4}) => pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(4, 2, 2, 3),
      child: pw.Text(
        pdfText(text),
        maxLines: zeilen,
        style: const pw.TextStyle(fontSize: 8.5, color: kDruckGrau),
      ),
    );

/// Eine Kennzahl im Kopf einer Liste: groß der Wert, klein darunter, was
/// er zählt. [betont]: schwarz statt dunkelgrau — für das, worauf es
/// ankommt.
class DruckKennzahl {
  const DruckKennzahl(this.wert, this.label, {this.betont = false});

  final String wert;
  final String label;
  final bool betont;
}

/// Kennzahlen nebeneinander — reicht die Breite nicht, in mehreren Zeilen.
pw.Widget druckKennzahlen(List<DruckKennzahl> zahlen) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Wrap(
        spacing: 22,
        runSpacing: 6,
        children: [
          for (final z in zahlen)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  pdfText(z.wert),
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: z.betont ? PdfColors.black : PdfColors.grey800,
                  ),
                ),
                pw.Text(
                  pdfText(z.label),
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
        ],
      ),
    );

/// Ein Punkt in [farbe] — der Stand in Farbe, zusätzlich zum Text.
pw.Widget druckPunkt(PdfColor farbe, {double groesse = 5}) => pw.Container(
      width: groesse,
      height: groesse,
      decoration: pw.BoxDecoration(color: farbe, shape: pw.BoxShape.circle),
    );

/// Ein waagrechter Balken, [breite] Punkt breit: die [segmente] (Wert,
/// Farbe) nebeneinander, gemessen an [max], dahinter der leere Rest in
/// Hellgrau. [marke] zieht einen Strich bei diesem Wert — etwa bei 100 %.
/// Was über [max] hinausgeht, endet am Rand.
pw.Widget druckBalken(
  List<(double, PdfColor)> segmente, {
  required double max,
  double breite = 110,
  double hoehe = 6,
  double? marke,
}) =>
    pw.CustomPaint(
      size: PdfPoint(breite, hoehe),
      painter: (canvas, groesse) {
        canvas
          ..setFillColor(PdfColors.grey200)
          ..drawRect(0, 0, groesse.x, groesse.y)
          ..fillPath();
        if (!(max > 0)) return;
        var x = 0.0;
        for (final (wert, farbe) in segmente) {
          if (!(wert > 0)) continue;
          final w = math.min(groesse.x - x, wert / max * groesse.x);
          if (w <= 0) break;
          canvas
            ..setFillColor(farbe)
            ..drawRect(x, 0, w, groesse.y)
            ..fillPath();
          x += w;
        }
        final m = marke;
        if (m != null && m > 0 && m <= max) {
          final mx = m / max * groesse.x;
          canvas
            ..setStrokeColor(PdfColors.grey800)
            ..setLineWidth(0.8)
            ..moveTo(mx, -1.5)
            ..lineTo(mx, groesse.y + 1.5)
            ..strokePath();
        }
      },
    );

/// Ein leeres Kästchen zum Abhaken von Hand.
pw.Widget druckKaestchen({double groesse = 8}) => pw.Container(
      width: groesse,
      height: groesse,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey800, width: 0.6),
      ),
    );

/// Ein Feld zum Schreiben von Hand: klein und grau oben [titel], darunter
/// Platz.
pw.Widget druckSchreibfeld(String titel, {double hoehe = 34}) => pw.Container(
      height: hoehe,
      padding: const pw.EdgeInsets.fromLTRB(5, 3, 5, 3),
      alignment: pw.Alignment.topLeft,
      decoration: const pw.BoxDecoration(
        border: pw.Border.fromBorderSide(kDruckLinie),
      ),
      child: pw.Text(
        pdfText(titel),
        maxLines: 1,
        style: const pw.TextStyle(fontSize: 7.5, color: kDruckGrau),
      ),
    );

/// Text in einer Zelle mit einem Punkt in [farbe] davor.
pw.Widget druckZelleMitPunkt(
  String text,
  PdfColor farbe, {
  bool fett = false,
  int zeilen = 2,
  double groesse = 8.5,
  PdfColor schrift = PdfColors.black,
}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Padding(
            padding: pw.EdgeInsets.only(top: groesse * .3),
            child: druckPunkt(farbe),
          ),
          pw.SizedBox(width: 4),
          pw.Expanded(
            child: pw.Text(
              pdfText(text),
              maxLines: zeilen,
              style: pw.TextStyle(
                fontSize: groesse,
                fontWeight: fett ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: schrift,
              ),
            ),
          ),
        ],
      ),
    );

/// Hält [teile] zusammen auf einer Seite, wenn [zusammen] — sie müssen
/// dann sicher auf eine Seite passen. Sonst stehen sie einzeln im Inhalt
/// (eine Tabelle darf so über die Seite laufen), und davor ein Umbruch,
/// wenn auf der Seite weniger als [frei] Punkt übrig sind: Eine Überschrift
/// soll nicht allein unten stehen. Soll das Blatt auf eine oder zwei Seiten
/// passen, gibt es keinen erzwungenen Umbruch (siehe
/// [DruckRahmen.umbrueche]).
List<pw.Widget> druckGruppe(
  List<pw.Widget> teile, {
  required bool zusammen,
  required DruckRahmen rahmen,
  double frei = 110,
}) {
  if (teile.isEmpty) return const [];
  if (zusammen) {
    return [
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: teile,
        ),
      ),
    ];
  }
  return [
    if (rahmen.umbrueche) pw.NewPage(freeSpace: frei),
    ...teile,
  ];
}
