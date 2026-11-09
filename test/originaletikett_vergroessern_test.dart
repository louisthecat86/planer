import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/entwicklung_daten.dart';
import 'package:produktion_planer/features/entwicklung/bericht/projekt_bericht.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/daten/etikett_scan.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';

import 'helpers/test_db.dart';

/// Ein zu kleines Originaletikett vergrößern: im Rahmen auf das Etikett
/// zoomen — der Bericht zeigt nur diesen Ausschnitt, so groß, wie Platz
/// ist. Wie Ansicht und Ausschnitt sich ineinander rechnen, wie das Bild
/// zugeschnitten wird und was Projekt, Bericht und Backup daraus machen.
/// Alle Daten sind erfunden.
void main() {
  /// Ein Bild [breite] × [hoehe]: links rot, rechts blau.
  img.Image zweifarbig(int breite, int hoehe) {
    final bild = img.Image(width: breite, height: hoehe);
    img.fillRect(
      bild,
      x1: 0,
      y1: 0,
      x2: breite ~/ 2 - 1,
      y2: hoehe - 1,
      color: img.ColorRgb8(220, 0, 0),
    );
    img.fillRect(
      bild,
      x1: breite ~/ 2,
      y1: 0,
      x2: breite - 1,
      y2: hoehe - 1,
      color: img.ColorRgb8(0, 0, 220),
    );
    return bild;
  }

  group('Ausschnitt', () {
    test('gespeichert und gelesen — Unbrauchbares zählt nicht', () {
      const a = EtikettAusschnitt(
        datei: 'd1',
        x: .25,
        y: .5,
        breite: .5,
        hoehe: .25,
      );
      final b = EtikettAusschnitt.ausJson(a.alsJson())!;
      expect(b.datei, 'd1');
      expect([b.x, b.y, b.breite, b.hoehe], [.25, .5, .5, .25]);

      for (final kaputt in [
        null,
        '',
        'kaputt',
        '[1, 2]',
        '{"datei": 7, "x": 0, "y": 0, "b": 0.5, "h": 0.5}',
        '{"datei": "d1", "x": 0.8, "y": 0, "b": 0.5, "h": 0.5}',
        '{"datei": "d1", "x": 0, "y": 0, "b": 0, "h": 0.5}',
        '{"datei": "d1", "x": 0, "y": 0.6, "b": 0.5, "h": 0.5}',
      ]) {
        expect(EtikettAusschnitt.ausJson(kaputt), isNull, reason: kaputt);
      }
    });

    test('gehört zu seinem Scan — ein anderer zeigt wieder alles', () {
      final jetzt = DateTime(2026, 11, 9);
      EntwicklungsProjekt projekt(String? datei, String? ausschnitt) =>
          EntwicklungsProjekt(
            id: 'p',
            name: 'Testart',
            status: 'entwicklung',
            neuerProzess: false,
            neueZutaten: false,
            createdAt: jetzt,
            updatedAt: jetzt,
            etikettDateiId: datei,
            etikettAusschnitt: ausschnitt,
          );
      final json = const EtikettAusschnitt(
        datei: 'scan1',
        x: 0,
        y: 0,
        breite: .5,
        hoehe: .5,
      ).alsJson();
      expect(etikettAusschnitt(projekt('scan1', json)), isNotNull);
      expect(etikettAusschnitt(projekt('scan2', json)), isNull);
      expect(etikettAusschnitt(projekt(null, json)), isNull);
      expect(etikettAusschnitt(projekt('scan1', null)), isNull);
    });
  });

  group('Ansicht und Ausschnitt', () {
    // Ein Scan hoch (1000 × 2000) im Rahmen von der Form des Platzes im
    // Bericht: eingepasst 200 × 400, mittig ab x = 184.
    const bildB = 1000.0;
    const bildH = 2000.0;
    const rahmenB = 568.0;
    const rahmenH = 400.0;

    EtikettAusschnitt? ausschnitt(double v, double dx, double dy) =>
        ausschnittDerAnsicht(
          datei: 'd',
          bildBreite: bildB,
          bildHoehe: bildH,
          rahmenBreite: rahmenB,
          rahmenHoehe: rahmenH,
          vergroesserung: v,
          dx: dx,
          dy: dy,
        );

    test('das Bild im Rahmen: ganz, mittig', () {
      final r = bildImRahmen(
        bildBreite: bildB,
        bildHoehe: bildH,
        rahmenBreite: rahmenB,
        rahmenHoehe: rahmenH,
      );
      expect([r.x, r.y, r.breite, r.hoehe], [184, 0, 200, 400]);
    });

    test('ungezoomt kein Ausschnitt — gezoomt der Teil im Rahmen', () {
      expect(ausschnitt(1, 0, 0), isNull);
      // Doppelt, oben links: Vom Rand des Rahmens zählt nur das Bild.
      final a = ausschnitt(2, 0, 0)!;
      expect(a.x, closeTo(0, 1e-9));
      expect(a.y, closeTo(0, 1e-9));
      expect(a.breite, closeTo(.5, 1e-9));
      expect(a.hoehe, closeTo(.5, 1e-9));
      // Ganz außerhalb des Bilds: nichts zu zeigen.
      expect(ausschnitt(4, 0, 0), isNull);
    });

    test('hin und zurück: dieselbe Stelle, so groß, wie sie passt', () {
      // Ein Teil in der Form des Rahmens: 71 × 50 Punkte im Rahmen.
      const a = EtikettAusschnitt(
        datei: 'd',
        x: .2,
        y: .3,
        breite: .355,
        hoehe: .125,
      );
      final ansicht = ansichtFuer(
        a,
        bildBreite: bildB,
        bildHoehe: bildH,
        rahmenBreite: rahmenB,
        rahmenHoehe: rahmenH,
      );
      expect(ansicht.vergroesserung, closeTo(8, 1e-9));
      final zurueck =
          ausschnitt(ansicht.vergroesserung, ansicht.dx, ansicht.dy)!;
      expect(zurueck.x, closeTo(a.x, 1e-9));
      expect(zurueck.y, closeTo(a.y, 1e-9));
      expect(zurueck.breite, closeTo(a.breite, 1e-9));
      expect(zurueck.hoehe, closeTo(a.hoehe, 1e-9));
    });

    test('am Rand: nicht über den Rahmen hinaus, höchstens zehnfach', () {
      const winzig = EtikettAusschnitt(
        datei: 'd',
        x: .99,
        y: .99,
        breite: .01,
        hoehe: .01,
      );
      final ansicht = ansichtFuer(
        winzig,
        bildBreite: bildB,
        bildHoehe: bildH,
        rahmenBreite: rahmenB,
        rahmenHoehe: rahmenH,
      );
      expect(ansicht.vergroesserung, kEtikettMaxVergroesserung);
      expect(ansicht.dx, inInclusiveRange(rahmenB * (1 - 10), 0));
      expect(ansicht.dy, inInclusiveRange(rahmenH * (1 - 10), 0));
      final zurueck =
          ausschnitt(ansicht.vergroesserung, ansicht.dx, ansicht.dy)!;
      for (final w in [zurueck.x, zurueck.y]) {
        expect(w, inInclusiveRange(0, 1));
      }
      expect(zurueck.x + zurueck.breite, lessThanOrEqualTo(1 + 1e-9));
      expect(zurueck.y + zurueck.hoehe, lessThanOrEqualTo(1 + 1e-9));
    });
  });

  group('Zuschneiden', () {
    test('genau der Teil — PNG bleibt PNG, JPEG bleibt JPEG', () {
      const rechts = EtikettAusschnitt(
        datei: 'd',
        x: .5,
        y: 0,
        breite: .5,
        hoehe: 1,
      );
      final png = Uint8List.fromList(img.encodePng(zweifarbig(40, 20)));
      final teil = etikettZuschneiden(png, rechts);
      expect(teil.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final bild = img.decodePng(teil)!;
      expect([bild.width, bild.height], [20, 20]);
      for (final (x, y) in [(0, 0), (19, 19), (10, 5)]) {
        final p = bild.getPixel(x, y);
        expect([p.r, p.g, p.b], [0, 0, 220], reason: '($x, $y)');
      }

      final jpeg = Uint8List.fromList(img.encodeJpg(zweifarbig(40, 20)));
      final jpegTeil = etikettZuschneiden(jpeg, rechts);
      expect(jpegTeil.sublist(0, 2), [0xFF, 0xD8]);
      expect(img.decodeJpg(jpegTeil)!.width, 20);
    });

    test('gedreht, wie es angezeigt wird', () {
      // 40 × 20 mit der Angabe „90° gedreht": angezeigt 20 × 40.
      final bild = zweifarbig(40, 20);
      bild.exif.imageIfd.orientation = 6;
      final jpeg = Uint8List.fromList(img.encodeJpg(bild));
      final teil = etikettZuschneiden(
        jpeg,
        const EtikettAusschnitt(datei: 'd', x: 0, y: .5, breite: 1, hoehe: .5),
      );
      final gelesen = img.decodeJpg(teil)!;
      expect([gelesen.width, gelesen.height], [20, 20]);
      // Schon gedreht — ein Leser darf es nicht noch einmal drehen.
      expect(gelesen.exif.imageIfd.orientation ?? 1, 1);
    });

    test('unlesbar: bleibt, wie es ist', () async {
      final kein = Uint8List.fromList([1, 2, 3, 4]);
      const a =
          EtikettAusschnitt(datei: 'd', x: 0, y: 0, breite: .5, hoehe: .5);
      expect(etikettZuschneiden(kein, a), kein);
      expect(await etikettZuschneidenImHintergrund(kein, a), kein);
    });
  });

  group('im Projekt und im Bericht', () {
    late AppDatabase db;
    late ProjektRepository projekte;
    late EntwicklungDateienDienst dateien;

    setUp(() async {
      db = testDatenbank();
      projekte = ProjektRepository(db);
      dateien = EntwicklungDateienDienst(db);
      // Der Datenschlüssel entsteht mit dem Passwort.
      await EntwicklungZugang(
        DbEntwicklungsSpeicher(db),
        iterationen: 1000,
        imHintergrund: false,
      ).festlegen('geheim123');
    });
    tearDown(() => db.close());

    Future<EntwicklungsProjekt> projekt(String id) async =>
        (await projekte.projekt(id))!;

    Future<String> scanAblegen(String projektId) async {
      final d = await dateien.speichern(
        name: 'Etikett.png',
        inhalt: img.encodePng(zweifarbig(200, 100)),
        projektId: projektId,
        mimeTyp: 'image/png',
      );
      await projekte.originaletikettSetzen(projektId, d);
      return d;
    }

    test('der Bericht zeigt nur den Ausschnitt — ein neuer Scan wieder alles',
        () async {
      final id = await projekte.projektAnlegen(name: 'Leberkäse Testart');
      final scan = await scanAblegen(id);
      await projekte.originaletikettAusschnitt(
        id,
        EtikettAusschnitt(datei: scan, x: .5, y: 0, breite: .5, hoehe: 1),
      );
      var b = await berichtLaden(db, dateien, await projekt(id));
      expect(b.etikettAusschnitt?.datei, scan);
      final teil = img.decodePng(b.etikettBilder.single)!;
      expect([teil.width, teil.height], [100, 100]);
      final roh = latin1.decode(
        await baueProjektPdf(
          b,
          gedrucktAm: DateTime(2026, 11, 9),
          komprimiert: false,
        ),
      );
      expect(roh, contains('(vergrößerter)'));
      expect(roh, contains('(Ausschnitt)'));
      expect(roh, matches(RegExp(r'/Width 100\s*/Height 100\b')));

      // Wieder das ganze Etikett.
      await projekte.originaletikettAusschnitt(id, null);
      b = await berichtLaden(db, dateien, await projekt(id));
      expect(b.etikettAusschnitt, isNull);
      expect(img.decodePng(b.etikettBilder.single)!.width, 200);

      // Ein neuer Scan beginnt ganz — der Ausschnitt galt dem alten.
      await projekte.originaletikettAusschnitt(
        id,
        EtikettAusschnitt(datei: scan, x: 0, y: 0, breite: .5, hoehe: .5),
      );
      await scanAblegen(id);
      expect((await projekt(id)).etikettAusschnitt, isNull);
      b = await berichtLaden(db, dateien, await projekt(id));
      expect(b.etikettAusschnitt, isNull);
      expect(img.decodePng(b.etikettBilder.single)!.width, 200);
    });

    test('lösen nimmt den Ausschnitt mit — im Backup bleibt er', () async {
      final id = await projekte.projektAnlegen(name: 'Leberkäse Testart');
      final scan = await scanAblegen(id);
      final a = EtikettAusschnitt(
        datei: scan,
        x: .1,
        y: .2,
        breite: .3,
        hoehe: .4,
      );
      await projekte.originaletikettAusschnitt(id, a);

      final daten = jsonDecode(jsonEncode(await EntwicklungDaten.lesen(db)))
          as Map<String, dynamic>;
      await EntwicklungDaten.leeren(db);
      await EntwicklungDaten.schreiben(db, daten, const {});
      expect(etikettAusschnitt(await projekt(id))?.breite, .3);

      // Ein Backup von vor dem Ausschnitt kennt das Feld nicht.
      for (final z in daten['projekte'] as List) {
        (z as Map<String, dynamic>).remove('etikettAusschnitt');
      }
      await EntwicklungDaten.leeren(db);
      await EntwicklungDaten.schreiben(db, daten, const {});
      expect((await projekt(id)).etikettAusschnitt, isNull);

      await projekte.originaletikettAusschnitt(id, a);
      await projekte.originaletikettLoesen(id);
      final p = await projekt(id);
      expect(p.etikettDateiId, isNull);
      expect(p.etikettAusschnitt, isNull);
    });
  });
}
