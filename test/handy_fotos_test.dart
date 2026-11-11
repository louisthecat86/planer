import 'dart:convert';
import 'dart:typed_data';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:produktion_planer/core/constants/entwicklung.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/artikel_fotos.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/handy_erfassung/handy_erfassung_dienst.dart';

import 'helpers/test_db.dart';

/// Fotos in der Handy-Erfassung: wie sie in der Ergebnis-Datei stehen, was
/// der Planer davon übernimmt — das Foto aus der Produktion zum Artikel,
/// das Musterfoto in den Foto-Eingang der Produktentwicklung — und das
/// Zuordnen zu einem Projekt. Alle Bilder sind hier erzeugt, alles
/// erfunden.
void main() {
  Uint8List jpeg({int farbe = 0, int breite = 64, int hoehe = 48}) {
    final bild = img.Image(width: breite, height: hoehe);
    for (final p in bild) {
      p
        ..r = (p.x * 4 + farbe) % 256
        ..g = (p.y * 5) % 256
        ..b = farbe % 256;
    }
    return img.encodeJpg(bild, quality: 80);
  }

  ErfasstesFoto produktionsfoto(
    String id, {
    String artikelId = 'a1',
    Uint8List? bild,
    String? bezeichnung,
  }) =>
      ErfasstesFoto(
        id: id,
        art: FotoArt.produktion,
        aufgenommenAm: DateTime(2026, 11, 10, 9, 30),
        artikelId: artikelId,
        artikel: 'Grillwurst',
        produktionId: 't1',
        bezeichnung: bezeichnung,
        kuerzel: 'AB',
      ).mit(bild ?? jpeg());

  ErfasstesFoto musterfoto(String id, String bezeichnung, {Uint8List? bild}) =>
      ErfasstesFoto(
        id: id,
        art: FotoArt.muster,
        aufgenommenAm: DateTime(2026, 11, 10, 11, 5),
        bezeichnung: bezeichnung,
        kuerzel: 'AB',
      ).mit(bild ?? jpeg(farbe: 120));

  ErfassungsErgebnis ergebnisMit(List<ErfasstesFoto> fotos) =>
      ErfassungsErgebnis(
        paketId: 'paket-1',
        erstellt: DateTime(2026, 11, 10, 18),
        fotos: fotos,
      );

  group('Austauschformat', () {
    test('ein Ergebnis mit Fotos: hin und zurück, Fassung 2', () {
      final bild = jpeg();
      final ergebnis = ergebnisMit([
        produktionsfoto('f1', bild: bild, bezeichnung: 'Anschnitt'),
        musterfoto('f2', 'Pfeffer grob'),
      ]);
      expect(ergebnis.leer, isFalse);
      final text = ergebnis.alsText();
      expect((jsonDecode(text) as Map)['version'], 2);

      final zurueck = ErfassungsErgebnis.ausText(text);
      expect(zurueck.alsText(), text);
      final f = zurueck.fotos.first;
      expect(f.art, FotoArt.produktion);
      expect(f.artikelId, 'a1');
      expect(f.produktionId, 't1');
      expect(f.bezeichnung, 'Anschnitt');
      expect(f.kuerzel, 'AB');
      expect(f.aufgenommenAm, DateTime(2026, 11, 10, 9, 30));
      expect(f.daten, bild);
      expect(f.groesse, bild.length);
      expect(zurueck.fotos.last.art, FotoArt.muster);
      expect(zurueck.fotos.last.artikelId, isNull);
    });

    test(
        'ohne Fotos bleibt es bei Fassung 1 — ein älterer Planer liest '
        'die Datei weiter', () {
      final text = ergebnisMit(const []).alsText();
      final kopf = jsonDecode(text) as Map;
      expect(kopf['version'], 1);
      expect(kopf.containsKey('fotos'), isFalse);
      expect(ErfassungsErgebnis.ausText(text).fotos, isEmpty);
    });

    test('ein Foto ohne Bild (der Stand auf dem Handy) und ein kaputtes', () {
      final ohne = ErfasstesFoto(
        id: 'f1',
        art: FotoArt.muster,
        aufgenommenAm: DateTime(2026, 11, 10),
        groesse: 4711,
      );
      final j = ohne.toJson();
      expect(j.containsKey('daten'), isFalse);
      final wieder = ErfasstesFoto.ausJson(j);
      expect(wieder.daten, isNull);
      expect(wieder.groesse, 4711);

      expect(
        () => ErfasstesFoto.ausJson({...j, 'daten': 'kein base64 !'}),
        throwsA(
          isA<FormatFehler>()
              .having((e) => e.meldung, 'meldung', contains('Foto')),
        ),
      );
    });

    test('der Dateiname eines Fotos', () {
      expect(
        musterfoto('f', 'Pfeffer: grob / fein').dateiname,
        'Musterfoto Pfeffer grob fein 2026-11-10_1105.jpg',
      );
      expect(
        produktionsfoto('f').dateiname,
        'Foto Grillwurst 2026-11-10_0930.jpg',
      );
      expect(
        ErfasstesFoto(
          id: 'f',
          art: FotoArt.muster,
          aufgenommenAm: DateTime(2026, 1, 2, 3, 4),
        ).dateiname,
        'Musterfoto 2026-01-02_0304.jpg',
      );
    });

    test('JPEG erkennen', () {
      expect(istJpeg(jpeg()), isTrue);
      expect(istJpeg(utf8.encode('kein Bild')), isFalse);
      expect(istJpeg(null), isFalse);
      expect(istJpeg(const [0xFF, 0xD8]), isFalse);
    });
  });

  group('im Planer', () {
    late AppDatabase db;
    late HandyErfassungDienst dienst;

    setUp(() async {
      db = testDatenbank();
      dienst = HandyErfassungDienst(db);
      await seedArtikel(
        db,
        id: 'a1',
        nummer: '4711',
        bezeichnung: 'Grillwurst',
      );
    });
    tearDown(() => db.close());

    Future<void> entwicklungEinrichten() => EntwicklungZugang(
          DbEntwicklungsSpeicher(db),
          iterationen: 1000,
          imHintergrund: false,
        ).festlegen('geheim123');

    test('ein Foto aus der Produktion kommt zum Artikel — einmal', () async {
      final bild = jpeg();
      final ergebnis = ergebnisMit([
        produktionsfoto('f1', bild: bild, bezeichnung: 'Anschnitt'),
        produktionsfoto('f2', artikelId: 'gibt-es-nicht'),
        ErfasstesFoto(
          id: 'f3',
          art: FotoArt.produktion,
          aufgenommenAm: DateTime(2026, 11, 10),
          artikelId: 'a1',
        ).mit(Uint8List.fromList(utf8.encode('kein Bild'))),
      ]);
      final v = await dienst.vorschau(ergebnis);
      expect(
        [for (final f in v.fotos) f.stand],
        [FotoStand.neu, FotoStand.artikelFehlt, FotoStand.unlesbar],
      );
      expect(v.fotos.first.ziel, '4711 · Grillwurst');
      expect(v.fotos.first.vorgewaehlt, isTrue);
      expect(v.fotos[1].moeglich, isFalse);

      // Auch angehakt kommt nur das eine an.
      final bericht = await dienst.uebernehmen(
        produktionen: const [],
        werte: const [],
        fotos: v.fotos,
      );
      expect(bericht, (produktionen: 0, werte: 0, fotos: 1));
      final fotos = await ArtikelFotoDienst(db).beobachten('a1').first;
      final foto = fotos.single;
      expect(foto.id, 'f1');
      expect(foto.bezeichnung, 'Anschnitt');
      expect(foto.kuerzel, 'AB');
      expect(foto.aufgenommenAm, DateTime(2026, 11, 10, 9, 30));
      expect(foto.istReferenz, isFalse);
      expect(await ArtikelFotoDienst(db).bild('f1'), bild);

      // Dieselbe Datei noch einmal: nichts doppelt.
      final nochmal = await dienst.vorschau(ergebnis);
      expect(nochmal.fotos.first.stand, FotoStand.schonDa);
      expect(nochmal.fotos.first.vorgewaehlt, isFalse);
      await dienst.uebernehmen(
        produktionen: const [],
        werte: const [],
        fotos: nochmal.fotos,
      );
      expect(await db.select(db.artikelFotos).get(), hasLength(1));
    });

    test('ein zu großes Foto wird beim Übernehmen verkleinert', () async {
      // Als käme es unverkleinert vom Handy.
      final gross = jpeg(breite: 2400, hoehe: 1800);
      final v = await dienst.vorschau(
        ergebnisMit([produktionsfoto('f1', bild: gross)]),
      );
      expect(v.fotos.single.stand, FotoStand.neu);
      await dienst.uebernehmen(
        produktionen: const [],
        werte: const [],
        fotos: v.fotos,
      );
      final bild = (await ArtikelFotoDienst(db).bild('f1'))!;
      final gelesen = img.decodeJpg(bild)!;
      expect((gelesen.width, gelesen.height), (kFotoKante, 1200));
      final foto = await db.select(db.artikelFotos).getSingle();
      expect(foto.groesse, bild.length);
    });

    test(
        'ein Musterfoto bleibt in der Datei, solange die '
        'Produktentwicklung nicht eingerichtet ist', () async {
      final ergebnis = ergebnisMit([
        produktionsfoto('f1'),
        musterfoto('m1', 'Pfeffer grob'),
      ]);
      final v = await dienst.vorschau(ergebnis);
      expect(v.fotos.first.stand, FotoStand.neu);
      expect(v.fotos.last.stand, FotoStand.entwicklungFehlt);
      expect(v.fotos.last.hinweis, contains('nicht eingerichtet'));

      // Das Foto aus der Produktion kommt trotzdem an.
      final bericht = await dienst.uebernehmen(
        produktionen: const [],
        werte: const [],
        fotos: v.fotos,
      );
      expect(bericht.fotos, 1);
      expect(await db.select(db.entwicklungDateien).get(), isEmpty);
    });

    test(
        'ein Musterfoto kommt verschlüsselt in den Foto-Eingang und von '
        'dort zu einem Projekt', () async {
      await entwicklungEinrichten();
      final bild = jpeg(farbe: 120);
      final ergebnis =
          ergebnisMit([musterfoto('m1', 'Pfeffer grob', bild: bild)]);
      final v = await dienst.vorschau(ergebnis);
      expect(v.fotos.single.stand, FotoStand.neu);
      expect(v.fotos.single.ziel, contains('Foto-Eingang'));
      await dienst.uebernehmen(
        produktionen: const [],
        werte: const [],
        fotos: v.fotos,
      );

      final repo = ProjektRepository(db);
      final eingang =
          await repo.dateienBeobachten(kEntwicklungFotoEingang).first;
      final datei = eingang.single;
      expect(datei.id, 'm1');
      expect(datei.name, 'Musterfoto Pfeffer grob 2026-11-10_1105.jpg');
      expect(datei.mimeTyp, 'image/jpeg');
      expect(datei.groesse, bild.length);
      // In der Datenbank steht nicht das Bild, sondern sein Paket.
      final roh = await db.select(db.entwicklungDateiInhalte).getSingle();
      expect(istJpeg(roh.inhalt), isFalse);
      expect(await EntwicklungDateienDienst(db).lesen('m1'), bild);
      // Nicht beim Artikel.
      expect(await db.select(db.artikelFotos).get(), isEmpty);

      // Noch einmal eingelesen: schon da — auch nach dem Zuordnen.
      expect(
        (await dienst.vorschau(ergebnis)).fotos.single.stand,
        FotoStand.schonDa,
      );

      final projekt = await repo.projektAnlegen(name: 'Muster A');
      await repo.dateiVerschieben('m1', projekt);
      await repo.produktfotoSetzen(projekt, 'm1');
      expect(
        await repo.dateienBeobachten(kEntwicklungFotoEingang).first,
        isEmpty,
      );
      expect(
        [for (final d in await repo.dateienBeobachten(projekt).first) d.id],
        ['m1'],
      );
      expect((await repo.projekt(projekt))!.bildDateiId, 'm1');
      expect(
        (await dienst.vorschau(ergebnis)).fotos.single.stand,
        FotoStand.schonDa,
      );
    });
  });
}
