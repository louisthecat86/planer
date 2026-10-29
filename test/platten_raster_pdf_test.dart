import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:produktion_planer/core/utils/platten_raster_pdf.dart';

/// Tests für das Plattenraster im PDF — dasselbe im Prozessblatt und im
/// Projektbericht. Gelesen wird der Text der unkomprimierten Seite; das
/// PDF schreibt ihn Wort für Wort.
void main() {
  Future<String> seite(pw.Widget raster) async {
    final doc = pw.Document(compress: false)
      ..addPage(pw.Page(build: (_) => raster));
    return latin1.decode(await doc.save());
  }

  test('Temperaturen: ganze Grad ohne Komma, sonst eine Stelle', () {
    expect(plattenWertText(185), '185');
    expect(plattenWertText(182.5), '182,5');
    expect(plattenWertText(182.46), '182,5');
  });

  test('Bratstraße: oben und unten, Zone 1 rechts, leer mit Strich',
      () async {
    final werte = {'Platte Oben 1': 235.0, 'Platte Unten 10': 182.5};
    final text = await seite(
      plattenRasterPdf(
        kombiofen: false,
        zonen: 10,
        wert: (name) => werte[name],
        massstab: .82,
      ),
    );
    expect(text, contains('(Bratstrasse)'));
    expect(text, contains('(Laufrichtung)'));
    expect(text, contains('(oben)'));
    expect(text, contains('(unten)'));
    expect(text, contains('(235)'));
    expect(text, contains('(182,5)'));
    // 20 Platten, zwei davon gesetzt.
    expect(RegExp(r'\(-\)').allMatches(text), hasLength(18));
    // Von links nach rechts gezeichnet: Zone 10 vor Zone 1.
    expect(text.indexOf('(10)'), lessThan(text.indexOf('(235)')));
  });

  test('Kombiofen: nur unten, zwölf Zonen', () async {
    final text = await seite(
      plattenRasterPdf(
        kombiofen: true,
        zonen: 12,
        wert: (name) => name == 'Platte Unten 12' ? 140 : null,
      ),
    );
    expect(text, contains('(Kombiofen)'));
    expect(text, isNot(contains('(oben)')));
    expect(text, contains('(unten)'));
    expect(text, contains('(12)'));
    expect(text, contains('(140)'));
    expect(RegExp(r'\(-\)').allMatches(text), hasLength(11));
  });
}
