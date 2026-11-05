import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/entwicklung_daten.dart';
import 'package:produktion_planer/features/entwicklung/bericht/projekt_bericht.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/daten/etikett_scan.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_checkliste.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';

import 'helpers/test_db.dart';

/// Das Originaletikett eines Projekts: der Scan des gedruckten Etiketts
/// beim Etikett nach LMIV — ein Bild oder ein PDF. Was das Feld nimmt, wie
/// ein neuer Scan den alten ersetzt und wie es im Projektbericht steht.
/// Alle Daten sind erfunden.
void main() {
  // Ein Bild mit einem Bildpunkt (PNG).
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAj'
    'CB0C8AAAAASUVORK5CYII=',
  );
  final datum = DateTime(2026, 11, 5, 9, 30);

  /// Ein echtes PDF mit [seiten] Seiten.
  Future<Uint8List> pdfMit(int seiten) async {
    final doc = pw.Document();
    for (var i = 0; i < seiten; i++) {
      doc.addPage(pw.Page(build: (_) => pw.Text('Etikett Seite ${i + 1}')));
    }
    return doc.save();
  }

  EntwicklungsDatei datei(String name, {String? mimeTyp}) => EntwicklungsDatei(
        id: 'd',
        name: name,
        mimeTyp: mimeTyp,
        groesse: 0,
        createdAt: datum,
      );

  group('Bild oder PDF', () {
    test('ein PDF am Inhalt erkannt — sonst an Medientyp und Endung', () async {
      final pdf = await pdfMit(1);
      expect(istPdfDatei(datei('scan.jpg'), pdf), isTrue);
      expect(istPdfDatei(datei('scan.pdf'), png), isFalse);
      // Etwas vor „%PDF" ist erlaubt.
      expect(
        istPdfDatei(
          datei('scan'),
          Uint8List.fromList([0xEF, 0xBB, 0xBF, ...pdf]),
        ),
        isTrue,
      );
      expect(istPdfDatei(datei('Scan.PDF')), isTrue);
      expect(istPdfDatei(datei('x', mimeTyp: 'application/pdf')), isTrue);
      expect(istPdfDatei(datei('scan.png')), isFalse);
    });

    test('als Bilder: ein Bild, wie es ist — ein PDF als seine Seiten',
        () async {
      final pdf = await pdfMit(6);
      expect(await etikettAlsBilder(datei('scan.png'), png), [png]);
      // Ohne jemanden, der rastert, kein Bild.
      expect(await etikettAlsBilder(datei('scan.pdf'), pdf), isEmpty);

      var aufrufe = 0;
      Future<List<Uint8List>> rastern(Uint8List daten) async {
        aufrufe++;
        expect(daten, pdf);
        return [for (var i = 0; i < 6; i++) png];
      }

      final seiten = await etikettAlsBilder(
        datei('scan.pdf'),
        pdf,
        pdfSeiten: rastern,
      );
      expect(seiten, hasLength(kEtikettMaxSeiten));
      expect(aufrufe, 1);

      // Scheitert das Rastern, bleibt es eine Datei.
      expect(
        await etikettAlsBilder(
          datei('scan.pdf'),
          pdf,
          pdfSeiten: (_) async => throw StateError('kaputt'),
        ),
        isEmpty,
      );
    });
  });

  group('im Projekt', () {
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

    Future<String> ablegen(String projektId, String name, List<int> inhalt) =>
        dateien.speichern(
          name: name,
          inhalt: inhalt,
          projektId: projektId,
          mimeTyp: name.endsWith('.pdf') ? 'application/pdf' : 'image/png',
        );

    test('ein neuer Scan ersetzt den alten — der bleibt unter den Dateien',
        () async {
      final id = await projekte.projektAnlegen(name: 'Leberkäse Testart');
      expect(originaletikettStand(await projekt(id)), contains('fehlt noch'));

      final alt = await ablegen(id, 'Etikett alt.png', png);
      await projekte.originaletikettSetzen(id, alt);
      expect((await projekt(id)).etikettDateiId, alt);
      expect(
        originaletikettStand(await projekt(id)),
        'Originaletikett hinterlegt',
      );

      final neu = await ablegen(id, 'Etikett neu.png', png);
      await projekte.originaletikettSetzen(id, neu);
      expect((await projekt(id)).etikettDateiId, neu);
      expect(await dateien.datei(alt), isNotNull);

      // Lösen lässt die Datei, wo sie ist.
      await projekte.originaletikettLoesen(id);
      expect((await projekt(id)).etikettDateiId, isNull);
      expect(await dateien.datei(neu), isNotNull);
    });

    test('im Backup — auch ältere ohne Originaletikett', () async {
      final id = await projekte.projektAnlegen(name: 'Leberkäse Testart');
      final d = await ablegen(id, 'Etikett.png', png);
      await projekte.originaletikettSetzen(id, d);
      final daten = jsonDecode(jsonEncode(await EntwicklungDaten.lesen(db)))
          as Map<String, dynamic>;

      await EntwicklungDaten.leeren(db);
      await EntwicklungDaten.schreiben(db, daten, const {});
      expect((await projekt(id)).etikettDateiId, d);

      // Ein Backup von vor dem Originaletikett kennt das Feld nicht.
      for (final z in daten['projekte'] as List) {
        (z as Map<String, dynamic>).remove('etikettDateiId');
      }
      await EntwicklungDaten.leeren(db);
      await EntwicklungDaten.schreiben(db, daten, const {});
      expect((await projekt(id)).etikettDateiId, isNull);
    });

    test('zählt nicht für „Etikett erstellt"', () async {
      final id = await projekte.projektAnlegen(name: 'Leberkäse Testart');
      final vorher = projektCheckStand(
        projekt: await projekt(id),
        rezepturen: const [],
        versionen: const [],
      ).punkt('etikettErstellt')!;
      await projekte.originaletikettSetzen(
        id,
        await ablegen(id, 'Etikett.png', png),
      );
      final nachher = projektCheckStand(
        projekt: await projekt(id),
        rezepturen: const [],
        versionen: const [],
      ).punkt('etikettErstellt')!;
      expect(nachher.erledigt, vorher.erledigt);
      expect(nachher.text, vorher.text);
    });

    test(
        'gelöscht oder in ein anderes Projekt verschoben: nicht mehr das '
        'Originaletikett', () async {
      final id = await projekte.projektAnlegen(name: 'Leberkäse Testart');
      final d = await ablegen(id, 'Etikett.png', png);
      await projekte.originaletikettSetzen(id, d);
      await projekte.dateiVerweiseEntfernen(d);
      expect((await projekt(id)).etikettDateiId, isNull);

      final g = await projekte.gesamtprojektAnlegen(name: 'Sortiment Test');
      final muster = await projekte.projektAnlegen(
        name: 'Muster A',
        gesamtprojektId: g,
      );
      final d2 = await ablegen(muster, 'Etikett.png', png);
      await projekte.originaletikettSetzen(muster, d2);
      await projekte.dateiVerschieben(d2, g);
      expect((await projekt(muster)).etikettDateiId, isNull);
      expect((await dateien.datei(d2))!.projektId, g);
    });

    test('im Bericht: unter den Pflichtangaben, ein PDF als seine Seiten',
        () async {
      final id = await projekte.projektAnlegen(name: 'Leberkäse Testart');

      // Ohne Scan: ein Hinweis.
      var b = await berichtLaden(db, dateien, await projekt(id));
      expect(b.etikettDatei, isNull);
      var roh = latin1.decode(
        await baueProjektPdf(b, gedrucktAm: datum, komprimiert: false),
      );
      expect(roh, contains('(Noch)'));
      expect(roh, contains('(fehlt)'));
      expect(roh, isNot(contains('/Subtype/Image')));

      // Ein Bild steht als Bild darin — gekennzeichnet unter den Dateien.
      await projekte.originaletikettSetzen(
        id,
        await ablegen(id, 'Etikett.png', png),
      );
      b = await berichtLaden(db, dateien, await projekt(id));
      expect(b.etikettDatei?.name, 'Etikett.png');
      expect(b.etikettBilder, [png]);
      roh = latin1.decode(
        await baueProjektPdf(b, gedrucktAm: datum, komprimiert: false),
      );
      expect(roh, contains('(Originaletikett)'));
      expect(roh, contains('(hinterlegt)'));
      expect(roh, contains('/Subtype/Image'));
      expect(roh, contains(r'(\(Originaletikett\))'));

      // Ein PDF: seine Seiten, wenn es jemand rastert …
      final pdf = await pdfMit(2);
      await projekte.originaletikettSetzen(
        id,
        await ablegen(id, 'Etikett.pdf', pdf),
      );
      b = await berichtLaden(
        db,
        dateien,
        await projekt(id),
        pdfSeiten: (_) async => [png, png],
      );
      expect(b.etikettBilder, [png, png]);

      // … sonst steht es als Datei da.
      b = await berichtLaden(db, dateien, await projekt(id));
      expect(b.etikettDatei?.name, 'Etikett.pdf');
      expect(b.etikettBilder, isEmpty);
      roh = latin1.decode(
        await baueProjektPdf(b, gedrucktAm: datum, komprimiert: false),
      );
      expect(roh, contains('(Etikett.pdf)'));
      expect(roh, contains('(liegt)'));
      expect(roh, isNot(contains('/Subtype/Image')));
    });
  });
}
