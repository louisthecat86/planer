import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/features/handy_erfassung/ergebnis_suche.dart';

/// Tests für das Finden des Ergebnisses vom Handy im Download-Ordner.
void main() {
  late Directory a;
  late Directory b;

  setUp(() {
    a = Directory.systemTemp.createTempSync('suche_a');
    b = Directory.systemTemp.createTempSync('suche_b');
  });
  tearDown(() {
    a.deleteSync(recursive: true);
    b.deleteSync(recursive: true);
  });

  void datei(Directory o, String name) =>
      File('${o.path}/$name').writeAsStringSync('{}');

  test('der Zeitstempel kommt aus dem Namen', () {
    expect(
      zeitstempelAusName('Planer-Erfassung-Ergebnis_2026-11-23_1410_AB.json'),
      '2026-11-23_1410',
    );
    // So hängt es ein E-Mail-Programm beim zweiten Speichern an.
    expect(
      zeitstempelAusName('Planer-Erfassung-Ergebnis_2026-11-23_1410 (1).json'),
      '2026-11-23_1410',
    );
    expect(zeitstempelAusName('Planer-Erfassung_2026-11-23_1410.json'), isNull);
    expect(zeitstempelAusName('Planer-Erfassung-Ergebnis_x.json'), isNull);
    expect(
      zeitstempelAusName('Planer-Erfassung-Ergebnis_2026-11-23_1410.txt'),
      isNull,
    );
  });

  test('das neueste über beide Ordner, ohne schon übernommene', () async {
    datei(a, 'Planer-Erfassung-Ergebnis_2026-11-20_0900_AB.json');
    datei(a, 'Rechnung.pdf');
    datei(b, 'Planer-Erfassung-Ergebnis_2026-11-23_1410_AB.json');
    datei(b, 'Planer-Erfassung-Ergebnis_2026-11-21_1200.json');

    final g = await neuestesErgebnis([a, b, a]);
    expect(g!.zeitstempel, '2026-11-23_1410');
    expect(g.name, 'Planer-Erfassung-Ergebnis_2026-11-23_1410_AB.json');
    expect(File(g.pfad).existsSync(), isTrue);

    final danach = await neuestesErgebnis(
      [a, b],
      uebernommenBis: '2026-11-23_1410',
    );
    expect(danach, isNull);
    final aelter = await neuestesErgebnis(
      [a, b],
      uebernommenBis: '2026-11-20_0900',
    );
    expect(aelter!.zeitstempel, '2026-11-23_1410');
  });

  test('fehlende Ordner stören nicht', () async {
    expect(
      await neuestesErgebnis([Directory('${a.path}/gibt_es_nicht')]),
      isNull,
    );
  });
}
