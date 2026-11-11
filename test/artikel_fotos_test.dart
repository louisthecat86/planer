import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/backup_service.dart';
import 'package:produktion_planer/core/services/datei_ablage.dart';
import 'package:produktion_planer/core/services/artikel_fotos.dart';

import 'helpers/test_db.dart';

/// Tests für die Fotos zum Artikel: das Aufbereiten eines Bilds, Speichern
/// und Referenzbild, und der Weg durchs Backup — im Auto-Backup nur als
/// Prüfsumme, das Bild einmal in der Ablage daneben. Alle Bilder sind
/// hier erzeugt, alle Daten erfunden.
void main() {
  // Zwei Datenbanken zugleich sind Absicht (der „andere Rechner").
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// Ein Bild mit Verlauf — damit das JPEG nicht winzig wird.
  Uint8List jpeg(int breite, int hoehe, {int farbe = 0, img.ExifData? exif}) {
    final bild = img.Image(width: breite, height: hoehe);
    for (final p in bild) {
      p
        ..r = (p.x * 255 ~/ breite + farbe) % 256
        ..g = (p.y * 255 ~/ hoehe) % 256
        ..b = (p.x + p.y + farbe) % 256;
    }
    if (exif != null) bild.exif = exif;
    return img.encodeJpg(bild, quality: 80);
  }

  group('Aufbereiten', () {
    test('ein großes Bild wird auf 1600 px verkleinert', () {
      final foto = fotoNeuRechnen(jpeg(2400, 1200))!;
      expect(istJpeg(foto), isTrue);
      final bild = img.decodeJpg(foto)!;
      expect((bild.width, bild.height), (kFotoKante, 800));

      final hoch = img.decodeJpg(fotoNeuRechnen(jpeg(900, 1800))!)!;
      expect((hoch.width, hoch.height), (800, kFotoKante));
    });

    test('ein kleines Bild behält seine Größe; ein PNG wird zum JPEG', () {
      final png = img.encodePng(img.Image(width: 320, height: 200));
      final foto = fotoNeuRechnen(png)!;
      expect(istJpeg(foto), isTrue);
      final bild = img.decodeJpg(foto)!;
      expect((bild.width, bild.height), (320, 200));
    });

    test('was kein Bild ist, wird abgelehnt', () {
      expect(
        fotoNeuRechnen(Uint8List.fromList(utf8.encode('kein Bild'))),
        isNull,
      );
      expect(fotoSaeubern(Uint8List(0)), isNull);
    });

    test(
        'ein Foto vom Handy verliert Aufnahmeort und Kamera — nicht die '
        'Drehung, und es wird nicht neu gerechnet', () {
      final exif = img.ExifData();
      exif.imageIfd
        ..orientation = 6
        ..make = 'Erfundene Kamera';
      exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
      final roh = jpeg(640, 480, exif: exif);
      final vorher = img.decodeJpgExif(roh)!;
      expect(vorher.gpsIfd.isEmpty, isFalse, reason: 'Vorbedingung');

      final sauber = fotoSaeubern(roh)!;
      final nachher = img.decodeJpgExif(sauber)!;
      expect(nachher.imageIfd.orientation, 6);
      expect(nachher.imageIfd.make, isNull);
      expect(nachher.gpsIfd.isEmpty, isTrue);
      // Dieselben Bildpunkte — nur die Angaben davor sind andere.
      expect(sauber.length, lessThan(roh.length));
      final a = img.decodeJpg(roh)!;
      final b = img.decodeJpg(sauber)!;
      expect(b.getBytes(), a.getBytes());
    });

    test('ein Foto ohne Aufnahmedaten bleibt, wie es ist', () {
      final roh = jpeg(640, 480);
      expect(fotoSaeubern(roh), same(roh));
    });
  });

  group('Fotos eines Artikels', () {
    late AppDatabase db;
    late ArtikelFotoDienst dienst;

    setUp(() async {
      db = testDatenbank();
      dienst = ArtikelFotoDienst(db);
      await seedArtikel(db, id: 'a1', nummer: '4711');
      await seedArtikel(db, id: 'a2', nummer: '4712');
    });
    tearDown(() => db.close());

    test('das Referenzbild zuerst, dann die neuesten', () async {
      final alt = await dienst.speichern(
        productId: 'a1',
        bild: jpeg(64, 48),
        aufgenommenAm: DateTime(2026, 11, 2, 9),
        bezeichnung: '  nach dem Braten ',
        kuerzel: 'AB',
      );
      final neu = await dienst.speichern(
        productId: 'a1',
        bild: jpeg(64, 48, farbe: 40),
        aufgenommenAm: DateTime(2026, 11, 9, 9),
      );
      await dienst.speichern(
        productId: 'a2',
        bild: jpeg(64, 48, farbe: 80),
        aufgenommenAm: DateTime(2026, 11, 10),
      );

      var fotos = await dienst.beobachten('a1').first;
      expect([for (final f in fotos) f.id], [neu, alt]);
      expect(fotos.last.bezeichnung, 'nach dem Braten');
      expect(fotos.last.kuerzel, 'AB');
      expect(fotos.last.groesse, jpeg(64, 48).length);
      expect(fotos.last.pruefsumme, hasLength(64));

      await dienst.referenzSetzen('a1', alt);
      fotos = await dienst.beobachten('a1').first;
      expect([for (final f in fotos) f.id], [alt, neu]);
      expect(fotos.first.istReferenz, isTrue);

      // Je Artikel höchstens eins.
      await dienst.referenzSetzen('a1', neu);
      fotos = await dienst.beobachten('a1').first;
      final referenz = {for (final f in fotos) f.id: f.istReferenz};
      expect(referenz, {neu: true, alt: false});
      // Das Foto eines anderen Artikels wird es nicht.
      await dienst.referenzSetzen('a2', alt);
      expect(
        (await dienst.beobachten('a1').first).where((f) => f.istReferenz),
        hasLength(1),
      );

      await dienst.referenzSetzen('a1', null);
      expect(
        (await dienst.beobachten('a1').first).where((f) => f.istReferenz),
        isEmpty,
      );
    });

    test('Bild lesen, vorhandene erkennen, löschen', () async {
      final bild = jpeg(64, 48);
      final id = await dienst.speichern(
        productId: 'a1',
        bild: bild,
        aufgenommenAm: DateTime(2026, 11, 9),
        id: 'handy-1',
      );
      expect(id, 'handy-1');
      expect(await dienst.bild(id), bild);
      expect(await dienst.vorhandene(['handy-1', 'handy-2']), {'handy-1'});

      await dienst.loeschen(id);
      expect(await dienst.bild(id), isNull);
      expect(await dienst.beobachten('a1').first, isEmpty);
      expect(await db.select(db.artikelFotoInhalte).get(), isEmpty);
    });
  });

  group('Backup', () {
    late AppDatabase db;
    late Directory ordner;
    final gross = jpeg(1200, 900);
    final klein = jpeg(64, 48, farbe: 90);

    setUp(() async {
      db = testDatenbank();
      ordner = await Directory.systemTemp.createTemp('planer_fotos_');
      BackupService.ordnerFuerTests = ordner;
      await seedArtikel(db, id: 'a1', nummer: '4711');
    });

    tearDown(() async {
      BackupService.ordnerFuerTests = null;
      await db.close();
      if (ordner.existsSync()) ordner.deleteSync(recursive: true);
    });

    Future<List<String>> mitFotos(AppDatabase d) async {
      final dienst = ArtikelFotoDienst(d);
      final a = await dienst.speichern(
        productId: 'a1',
        bild: gross,
        aufgenommenAm: DateTime(2026, 11, 9, 10),
        bezeichnung: 'Anschnitt',
      );
      final b = await dienst.speichern(
        productId: 'a1',
        bild: klein,
        aufgenommenAm: DateTime(2026, 11, 10, 10),
      );
      await dienst.referenzSetzen('a1', a);
      return [a, b];
    }

    Directory ablage() => Directory(
          '${ordner.path}${Platform.pathSeparator}${DateiAblage.ordnerName}',
        );

    Map<String, dynamic> datenIn(String pfad) {
      final bytes = File(pfad).readAsBytesSync();
      final backup =
          jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
      return backup['data'] as Map<String, dynamic>;
    }

    test('ohne Fotos steht nichts davon im Backup', () async {
      final daten = (await BackupService.backupInhalt(db))['data']
          as Map<String, dynamic>;
      expect(daten.containsKey(FotoSicherung.kFotos), isFalse);
      expect(daten.containsKey(FotoSicherung.kInhalte), isFalse);
    });

    test('im Auto-Backup nur die Prüfsummen, die Bilder in der Ablage',
        () async {
      final ids = await mitFotos(db);
      final pfad = await BackupService.createAutoBackup(db);
      expect(File(pfad).lengthSync(), lessThan(gross.length ~/ 2));

      final daten = datenIn(pfad);
      expect(daten.containsKey(FotoSicherung.kInhalte), isFalse);
      expect((daten[FotoSicherung.kFotos] as List), hasLength(2));
      final verweise =
          (daten[FotoSicherung.kVerweise] as Map).cast<String, String>();
      expect(verweise.keys.toSet(), ids.toSet());
      final dateien = [
        for (final e in ablage().listSync())
          e.path.split(Platform.pathSeparator).last,
      ]..sort();
      expect(dateien, [for (final s in verweise.values) '$s.bin']..sort());

      // Ein zweites Backup legt nichts neu ab.
      await BackupService.createAutoBackup(db);
      expect(ablage().listSync(), hasLength(2));
    });

    test('die Bilder kommen aus der Ablage zurück — samt Referenzbild',
        () async {
      final ids = await mitFotos(db);
      final pfad = await BackupService.createAutoBackup(db);
      final dienst = ArtikelFotoDienst(db);
      await dienst.loeschen(ids.first);
      // Nach dem Backup dazugekommen — das Einspielen nimmt es wieder weg.
      final spaeter = await dienst.speichern(
        productId: 'a1',
        bild: jpeg(32, 32, farbe: 3),
        aufgenommenAm: DateTime(2026, 11, 11),
      );

      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      final fotos = await dienst.beobachten('a1').first;
      expect([for (final f in fotos) f.id], ids);
      expect(fotos.first.istReferenz, isTrue);
      expect(fotos.first.bezeichnung, 'Anschnitt');
      expect(await dienst.bild(ids.first), gross);
      expect(await dienst.bild(ids.last), klein);
      expect(await dienst.bild(spaeter), isNull);
    });

    test('ohne Ablage, aber mit denselben Fotos in der Datenbank: geht',
        () async {
      final ids = await mitFotos(db);
      final pfad = await BackupService.createAutoBackup(db);
      ablage().deleteSync(recursive: true);

      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);
      expect(await ArtikelFotoDienst(db).bild(ids.first), gross);
    });

    test(
        'fehlt die Ablage auf einem anderen Rechner, wird nichts '
        'eingespielt', () async {
      await mitFotos(db);
      final pfad = await BackupService.createAutoBackup(db);
      ablage().deleteSync(recursive: true);

      final anderer = testDatenbank();
      addTearDown(anderer.close);
      await seedArtikel(anderer, id: 'alt', nummer: '9999');
      await expectLater(
        BackupService.importBackup(pfad, anderer, sicherungAnlegen: false),
        throwsA(
          predicate(
            (e) => '$e'.contains('fehlen 2 Fotos') && '$e'.contains('Komplett'),
          ),
        ),
      );
      final artikel = await anderer.select(anderer.products).get();
      expect(artikel.single.artikelnummer, '9999');
    });

    test(
        'das Komplett-Backup trägt die Bilder selbst — auf einen anderen '
        'Rechner', () async {
      final ids = await mitFotos(db);
      final inhalt = await BackupService.backupInhalt(db);
      final daten = inhalt['data'] as Map<String, dynamic>;
      expect(daten.containsKey(FotoSicherung.kVerweise), isFalse);
      expect((daten[FotoSicherung.kInhalte] as Map).keys.toSet(), ids.toSet());

      final datei = File('${ordner.path}/komplett.planerbackup')
        ..writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(inhalt))));
      final anderer = testDatenbank();
      addTearDown(anderer.close);
      // Dort lag schon ein Foto — das Backup ersetzt es.
      await seedArtikel(anderer, id: 'a1', nummer: '4711');
      await ArtikelFotoDienst(anderer).speichern(
        productId: 'a1',
        bild: jpeg(16, 16),
        aufgenommenAm: DateTime(2026, 1, 1),
        id: 'vorher',
      );

      await BackupService.importBackup(
        datei.path,
        anderer,
        sicherungAnlegen: false,
      );
      final dienst = ArtikelFotoDienst(anderer);
      final fotos = await dienst.beobachten('a1').first;
      expect([for (final f in fotos) f.id], ids);
      expect(await dienst.bild(ids.first), gross);
      expect(await dienst.bild('vorher'), isNull);
    });

    test('ein Backup ohne Fotos nimmt die Fotos dieses Rechners mit weg',
        () async {
      final pfad = await BackupService.createAutoBackup(db);
      await mitFotos(db);
      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);
      expect(await db.select(db.artikelFotos).get(), isEmpty);
      expect(await db.select(db.artikelFotoInhalte).get(), isEmpty);
    });

    test('Aufräumen lässt liegen, was ein Backup noch nennt', () async {
      final ids = await mitFotos(db);
      await BackupService.createAutoBackup(db);
      final vorher = ablage().listSync().length;
      // Alt genug zum Aufräumen.
      final alt = DateTime.now().subtract(const Duration(days: 3));
      for (final e in ablage().listSync().whereType<File>()) {
        e.setLastModifiedSync(alt);
      }
      final verwaist = File(
        '${ablage().path}${Platform.pathSeparator}${'ab' * 32}.bin',
      )
        ..writeAsBytesSync([1, 2, 3])
        ..setLastModifiedSync(alt);

      await BackupService.dateienAufraeumen();
      expect(verwaist.existsSync(), isFalse);
      expect(
        ablage().listSync().whereType<File>().where(
              (e) => e.path.endsWith('.bin'),
            ),
        hasLength(vorher),
      );
      expect(ids, hasLength(2));
    });

    test('eine fehlende Prüfsumme trägt das nächste Backup nach', () async {
      final ids = await mitFotos(db);
      await db.update(db.artikelFotos).write(
            const ArtikelFotosCompanion(pruefsumme: Value(null)),
          );
      final daten = datenIn(await BackupService.createAutoBackup(db));
      final verweise =
          (daten[FotoSicherung.kVerweise] as Map).cast<String, String>();
      for (final f in await db.select(db.artikelFotos).get()) {
        expect(f.pruefsumme, verweise[f.id]);
      }
      expect(verweise.keys.toSet(), ids.toSet());
    });
  });
}
