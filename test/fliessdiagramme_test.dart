// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/providers/database_provider.dart';
import 'package:produktion_planer/features/entwicklung/bericht/projekt_bericht.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/fliessdiagramm_liste.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';

import 'helpers/test_db.dart';

/// Tests für die Fließdiagramme als Auswahlliste: eingefügte Listen, der
/// Text im Projekt und im Bericht, PDFs aus einer früheren Version
/// entfernen. Alle Namen erfunden.
void main() {
  group('Liste', () {
    test('eingefügt: Tabulator, Semikolon, Leerzeichen, Striche', () {
      final liste = fliessdiagrammeAusText(
        'FD_101\tTestware natur\n'
        'FD_102;Testware roh\n'
        '\n'
        'FD_103 – Testware gegart, gekühlt\n'
        'FD_104: Testware Form A/B\n'
        'FD_101 doppelt\n'
        'FD_105\n',
      );
      expect([for (final f in liste) (f.id, f.bezeichnung)], [
        ('FD_101', 'Testware natur'),
        ('FD_102', 'Testware roh'),
        ('FD_103', 'Testware gegart, gekühlt'),
        ('FD_104', 'Testware Form A/B'),
        ('FD_105', 'FD_105'),
      ]);
    });

    test('Text: Kennung und Bezeichnung', () {
      expect(
        fdText('FD_101', bezeichnung: 'Testware paniert'),
        'FD_101 · Testware paniert',
      );
      expect(fdText('FD_101', bezeichnung: 'FD_101'), 'FD_101');
      expect(fdText('FD_101', bezeichnung: ''), 'FD_101');
      expect(fdText('FD_101'), 'FD_101');
    });
  });

  group('Mit der Datenbank', () {
    late AppDatabase db;
    late ProjektRepository repo;
    late EntwicklungDateienDienst dateien;

    setUp(() async {
      db = testDatenbank();
      repo = ProjektRepository(db);
      dateien = EntwicklungDateienDienst(db);
      // Der Datenschlüssel entsteht mit dem Passwort.
      await EntwicklungZugang(
        DbEntwicklungsSpeicher(db),
        iterationen: 1000,
        imHintergrund: false,
      ).festlegen('geheim123');
    });
    tearDown(() => db.close());

    Future<List<(String, String)>> liste() async => [
          for (final f in await repo.fliessdiagrammeBeobachten().first)
            (f.id, f.bezeichnung),
        ];

    test('eine Liste übernehmen: neue hinten, vorhandene umbenannt', () async {
      await repo.fliessdiagrammSpeichern(id: 'FD_102', bezeichnung: 'Alt');
      for (final e in fliessdiagrammeAusText(
        'FD_101 Testware\nFD_102 Testware neu\nFD_103 Testware gebrüht',
      )) {
        await repo.fliessdiagrammSpeichern(id: e.id, bezeichnung: e.bezeichnung);
      }
      // FD_102 stand schon da und behält seinen Platz.
      expect(await liste(), [
        ('FD_102', 'Testware neu'),
        ('FD_101', 'Testware'),
        ('FD_103', 'Testware gebrüht'),
      ]);
    });

    test('der Projektbericht nennt Kennung und Bezeichnung', () async {
      await repo.fliessdiagrammSpeichern(
        id: 'FD_101',
        bezeichnung: 'Testware paniert',
      );
      final id = await repo.projektAnlegen(name: 'Testprodukt');
      await repo.projektAendern(
        id,
        const EntwicklungProjekteCompanion(fliessdiagramm: Value('FD_101')),
      );
      var b = await berichtLaden(db, dateien, (await repo.projekt(id))!);
      expect(b.fliessdiagramm, 'FD_101 · Testware paniert');

      // Nicht (mehr) in der Liste: nur die Kennung.
      await repo.projektAendern(
        id,
        const EntwicklungProjekteCompanion(fliessdiagramm: Value('FD_999')),
      );
      b = await berichtLaden(db, dateien, (await repo.projekt(id))!);
      expect(b.fliessdiagramm, 'FD_999');

      await repo.projektAendern(
        id,
        const EntwicklungProjekteCompanion(fliessdiagramm: Value(null)),
      );
      b = await berichtLaden(db, dateien, (await repo.projekt(id))!);
      expect(b.fliessdiagramm, isNull);
    });

    test('PDFs aus einer früheren Version finden und entfernen', () async {
      const alt = '${kFdPdfPraefix}FD_101:2026-07-31';
      await dateien.speichern(
        id: alt,
        name: 'FD_101 Testware 260731.pdf',
        inhalt: const [1, 2, 3],
        mimeTyp: 'application/pdf',
      );
      final andere = await dateien.speichern(
        name: 'Datenblatt.pdf',
        inhalt: const [4, 5],
        mimeTyp: 'application/pdf',
      );
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final ids = await container.read(fliessdiagrammAltePdfsProvider.future);
      expect(ids, [alt]);
      await fdAltePdfsEntfernen(dateien, ids);
      expect(await dateien.datei(alt), isNull);
      expect(await dateien.lesen(alt), isNull);
      // Andere Dateien bleiben.
      expect(await dateien.datei(andere), isNotNull);
    });
  });
}
