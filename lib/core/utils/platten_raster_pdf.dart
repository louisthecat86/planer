import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Das Plattenraster einer Bratstraße oder eines Kombiofens im PDF — wie
/// auf der Einstellvorlage: die Laufrichtung von rechts nach links (Zone 1
/// ist der Einlauf rechts), die Bratstraße mit Platten oben und unten, der
/// Kombiofen nur unten und in zwei Gruppen zu sechs. Je wärmer eine
/// Platte, desto kräftiger ihr Orange; eine Platte ohne Wert bleibt grau.
///
/// Prozessblatt und Projektbericht zeichnen es beide hiermit — so sieht es
/// überall gleich aus. [massstab] verkleinert es (1: wie im Prozessblatt).
///
/// [wert] liefert die Temperatur zu einem Namen wie „Platte Oben 3" —
/// null: nicht gesetzt.
pw.Widget plattenRasterPdf({
  required bool kombiofen,
  required int zonen,
  required double? Function(String name) wert,
  double massstab = 1,
}) {
  final m = massstab;

  pw.Widget reihe(String praefix) {
    // Laufrichtung: Zone 1 = Einlauf rechts — links steht die höchste.
    final zellen = <pw.Widget>[];
    for (var anzeige = 0; anzeige < zonen; anzeige++) {
      final zone = zonen - anzeige;
      // Der Kombiofen in zwei Gruppen zu sechs, wie auf der Vorlage.
      if (kombiofen && anzeige == 6) zellen.add(pw.SizedBox(width: 6 * m));
      zellen.add(_zelle(zone, wert('$praefix $zone'), m));
    }
    return pw.Row(children: zellen);
  }

  pw.Widget beschriftung(String text) => pw.Text(
    text,
    style: pw.TextStyle(fontSize: 7 * m, color: PdfColors.grey700),
  );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        children: [
          pw.Text(
            kombiofen ? 'Kombiofen' : 'Bratstrasse',
            style: pw.TextStyle(
              fontSize: 8.5 * m,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(width: 10 * m),
          pw.Text(
            '<----- Laufrichtung (Zone 1 = Einlauf rechts)',
            style: pw.TextStyle(fontSize: 7 * m, color: PdfColors.grey600),
          ),
        ],
      ),
      pw.SizedBox(height: 3 * m),
      if (!kombiofen) ...[
        beschriftung('Platten oben'),
        pw.SizedBox(height: 1 * m),
        reihe('Platte Oben'),
        pw.SizedBox(height: 3 * m),
      ],
      beschriftung('Platten unten'),
      pw.SizedBox(height: 1 * m),
      reihe('Platte Unten'),
    ],
  );
}

/// Eine Platte: oben links ihre Zone, in der Mitte die Temperatur.
pw.Widget _zelle(int zone, double? wert, double m) {
  final PdfColor hinten;
  if (wert == null) {
    hinten = PdfColors.grey200;
  } else if (wert <= 0) {
    hinten = PdfColors.grey300;
  } else if (wert < 160) {
    hinten = PdfColor.fromHex('#FFF3E0');
  } else if (wert < 230) {
    hinten = PdfColor.fromHex('#FFE0B2');
  } else {
    hinten = PdfColor.fromHex('#FFCC80');
  }
  return pw.Container(
    width: 36 * m,
    height: 24 * m,
    margin: pw.EdgeInsets.only(right: 2 * m),
    decoration: pw.BoxDecoration(
      color: hinten,
      border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
      borderRadius: pw.BorderRadius.circular(2 * m),
    ),
    child: pw.Stack(
      children: [
        pw.Positioned(
          top: 1 * m,
          left: 2 * m,
          child: pw.Text(
            '$zone',
            style: pw.TextStyle(
              // Kleiner als 4,5 pt liest sich die Zone nicht mehr.
              fontSize: 5 * m < 4.5 ? 4.5 : 5 * m,
              color: PdfColors.grey600,
            ),
          ),
        ),
        pw.Center(
          child: pw.Text(
            wert == null ? '-' : plattenWertText(wert),
            style: pw.TextStyle(
              fontSize: 9 * m,
              fontWeight: pw.FontWeight.bold,
              color: wert == null ? PdfColors.grey500 : PdfColors.grey900,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Eine Temperatur, wie sie auf der Platte steht: ganze Grad ohne Komma,
/// sonst eine Nachkommastelle — „185", „182,5".
String plattenWertText(double wert) => wert == wert.roundToDouble()
    ? wert.toInt().toString()
    : wert.toStringAsFixed(1).replaceAll('.', ',');
