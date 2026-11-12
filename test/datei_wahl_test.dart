import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:produktion_planer/core/utils/ablage_dateien.dart';
import 'package:produktion_planer/core/utils/datei_wahl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests fürs Einlesen von Dateien: Je Art von Datei merkt sich die App
/// den Ordner, und von dem, was aufs Fenster gezogen wird, zählt die erste
/// passende Datei. Alle Namen und Pfade sind erfunden.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory ordner;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ordner = await Directory.systemTemp.createTemp('planer_einlesen_');
  });

  tearDown(() async {
    if (await ordner.exists()) await ordner.delete(recursive: true);
  });

  group('Gemerkter Ordner', () {
    test('anfangs keiner', () async {
      for (final art in EinleseArt.values) {
        expect(await GemerkterOrdner.lesen(art), isNull);
      }
    });

    test('der Ordner der gewählten Datei, je Art getrennt', () async {
      final berichte = Directory(p.join(ordner.path, 'berichte'));
      final handy = Directory(p.join(ordner.path, 'handy'));
      await berichte.create();
      await handy.create();

      await GemerkterOrdner.merken(
        EinleseArt.auftragsbestand,
        p.join(berichte.path, 'bestand.xlsx'),
      );
      await GemerkterOrdner.merken(
        EinleseArt.handyErgebnis,
        p.join(handy.path, 'ergebnis.json'),
      );

      expect(
        await GemerkterOrdner.lesen(EinleseArt.auftragsbestand),
        berichte.path,
      );
      expect(
        await GemerkterOrdner.lesen(EinleseArt.handyErgebnis),
        handy.path,
      );
      expect(await GemerkterOrdner.lesen(EinleseArt.navisionArtikel), isNull);
    });

    test('die nächste Datei aus einem anderen Ordner ersetzt ihn', () async {
      final alt = Directory(p.join(ordner.path, 'alt'));
      final neu = Directory(p.join(ordner.path, 'neu'));
      await alt.create();
      await neu.create();

      await GemerkterOrdner.merken(
        EinleseArt.navisionArtikel,
        p.join(alt.path, 'a.xlsx'),
      );
      await GemerkterOrdner.merken(
        EinleseArt.navisionArtikel,
        p.join(neu.path, 'b.xlsx'),
      );
      expect(
        await GemerkterOrdner.lesen(EinleseArt.navisionArtikel),
        neu.path,
      );
    });

    test('gibt es den Ordner nicht mehr, zählt er nicht', () async {
      final weg = Directory(p.join(ordner.path, 'weg'));
      await weg.create();
      await GemerkterOrdner.merken(
        EinleseArt.auftragsbestand,
        p.join(weg.path, 'bestand.xlsx'),
      );
      await weg.delete();

      expect(await GemerkterOrdner.lesen(EinleseArt.auftragsbestand), isNull);
    });

    test('ohne Pfad bleibt der gemerkte Ordner stehen', () async {
      await GemerkterOrdner.merken(
        EinleseArt.auftragsbestand,
        p.join(ordner.path, 'bestand.xlsx'),
      );
      await GemerkterOrdner.merken(EinleseArt.auftragsbestand, null);
      await GemerkterOrdner.merken(EinleseArt.auftragsbestand, '  ');
      // Ein bloßer Dateiname sagt nichts über den Ordner.
      await GemerkterOrdner.merken(EinleseArt.auftragsbestand, 'nur.xlsx');

      expect(
        await GemerkterOrdner.lesen(EinleseArt.auftragsbestand),
        ordner.path,
      );
    });
  });

  group('Aufs Fenster gezogen', () {
    AbgelegteDatei datei(String name) =>
        (name: name, inhalt: Uint8List.fromList(name.codeUnits));

    test('die erste Datei mit passender Endung', () {
      final dateien = [
        datei('notiz.txt'),
        datei('bestand.XLSX'),
        datei('zweiter.xlsx'),
      ];
      expect(ersteMitEndung(dateien, ['xlsx'])?.name, 'bestand.XLSX');
      expect(ersteMitEndung(dateien, ['json', 'TXT'])?.name, 'notiz.txt');
    });

    test('nichts Passendes dabei', () {
      expect(ersteMitEndung([datei('bild.png')], ['xlsx']), isNull);
      expect(ersteMitEndung(const [], ['xlsx']), isNull);
      // Die Endung zählt, nicht ein Namensteil.
      expect(ersteMitEndung([datei('xlsx.pdf')], ['xlsx']), isNull);
      expect(ersteMitEndung([datei('ohne_endung')], ['xlsx']), isNull);
    });

    test('die Meldung nennt, was hier geht', () {
      expect(
        falscheDateiText(['xlsx']),
        'Hier lässt sich nur eine .xlsx-Datei einlesen.',
      );
      expect(
        falscheDateiText(['xlsx', 'CSV']),
        'Hier lässt sich nur eine Datei mit .xlsx oder .csv einlesen.',
      );
    });
  });
}
