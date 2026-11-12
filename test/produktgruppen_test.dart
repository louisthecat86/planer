import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/product_groups.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/articles/produktgruppen.dart';

import 'helpers/test_db.dart';

/// Tests für die Produktgruppen: Zur Wahl stehen die Fließdiagramme des
/// Betriebs; die früheren festen Gruppen bleiben nur für das, was sie
/// schon trägt. Alle Fließdiagramme sind erfunden.
void main() {
  late AppDatabase db;

  setUp(() => db = testDatenbank());
  tearDown(() async {
    eigeneProduktgruppenSetzen(const {});
    await db.close();
  });

  Future<void> fd(String id, String bezeichnung, {int sortierung = 0}) =>
      db.into(db.entwicklungFliessdiagramme).insert(
            EntwicklungFliessdiagrammeCompanion.insert(
              id: id,
              bezeichnung: bezeichnung,
              sortierung: Value(sortierung),
            ),
          );

  Future<List<Fliessdiagramm>> liste() =>
      db.select(db.entwicklungFliessdiagramme).get();

  group('Zur Wahl', () {
    test('ohne Fließdiagramme die früheren festen Gruppen', () {
      final gruppen = produktgruppenAus(const []);
      expect(gruppen, hasLength(ProductGroup.values.length));
      expect(gruppen.first, (wert: 'bruehwurst', label: 'Brühwurst'));
    });

    test('mit Fließdiagrammen nur noch die', () async {
      await fd('FD_901', 'Testware natur');
      await fd('FD_902', 'FD_902');

      final gruppen = produktgruppenAus(await liste());

      expect(gruppen, [
        (wert: 'FD_901', label: 'FD_901 · Testware natur'),
        // Sagt die Bezeichnung nichts, steht nur die Kennung da.
        (wert: 'FD_902', label: 'FD_902'),
      ]);
    });

    test('„keine" steht vorn, wenn gewünscht', () {
      const gruppen = [(wert: 'FD_901', label: 'FD_901 · Testware natur')];
      expect(
        produktgruppenWahl(gruppen).map((g) => g.wert),
        ['', 'FD_901'],
      );
      expect(
        produktgruppenWahl(gruppen, mitKeine: false).map((g) => g.wert),
        ['FD_901'],
      );
    });

    test('die bisherige Gruppe eines Artikels bleibt wählbar', () {
      const gruppen = [(wert: 'FD_901', label: 'FD_901 · Testware natur')];

      final wahl = produktgruppenWahl(gruppen, aktuell: 'bruehwurst');

      expect(
        wahl.last,
        (wert: 'bruehwurst', label: 'Brühwurst (bisherige Gruppe)'),
      );
      // Steht die Gruppe ohnehin zur Wahl, kommt sie nicht doppelt.
      expect(
        produktgruppenWahl(gruppen, aktuell: 'FD_901').map((g) => g.wert),
        ['', 'FD_901'],
      );
      expect(produktgruppenWahl(gruppen, aktuell: '  '), hasLength(2));
    });
  });

  group('Anzeigename', () {
    test('die früheren Gruppen heißen wie bisher', () {
      expect(produktgruppeLabel('bruehwurst'), 'Brühwurst');
      expect(produktgruppeLabel(null), '');
      expect(produktgruppeLabel('unbekannt'), 'unbekannt');
    });

    test('ein Fließdiagramm heißt nach Kennung und Bezeichnung', () async {
      await fd('FD_901', 'Testware natur');
      expect(produktgruppeLabel('FD_901'), 'FD_901');

      await produktgruppenNamenLaden(db);

      expect(produktgruppeLabel('FD_901'), 'FD_901 · Testware natur');
      // Die früheren Gruppen bleiben daneben lesbar.
      expect(produktgruppeLabel('rohwurst'), 'Rohwurst');
    });

    test('folgt der Liste: Umbenannt und entfernt', () async {
      await fd('FD_901', 'Testware natur');
      await produktgruppenNamenLaden(db);

      await db.update(db.entwicklungFliessdiagramme).write(
            const EntwicklungFliessdiagrammeCompanion(
              bezeichnung: Value('Testware gegart'),
            ),
          );
      await produktgruppenNamenLaden(db);
      expect(produktgruppeLabel('FD_901'), 'FD_901 · Testware gegart');

      await db.delete(db.entwicklungFliessdiagramme).go();
      await produktgruppenNamenLaden(db);
      // Der Artikel behält seinen Wert; ohne Liste steht die Kennung da.
      expect(produktgruppeLabel('FD_901'), 'FD_901');
    });
  });
}
