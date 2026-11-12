import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/navision_import_service.dart';
import 'package:produktion_planer/core/services/navision_katalog.dart';
import 'package:produktion_planer/features/entwicklung/zutaten/zutaten_navision.dart';
import 'package:produktion_planer/features/entwicklung/zutaten/zutatenkatalog_druck.dart';

import 'helpers/test_db.dart';

/// Tests für die Zutaten aus Navision: Die Artikel der gewählten
/// Produktbuchungsgruppen kommen als „nicht gepflegt" in den
/// Zutatenkatalog — zugeordnet allein über die Artikelnummer, und ohne
/// eine bestehende Zutat anzufassen. Alles erfunden.
void main() {
  late AppDatabase db;
  late ZutatenNavision dienst;

  setUp(() async {
    db = testDatenbank();
    dienst = ZutatenNavision(db);
    await NavisionKatalogSpeicher.merken(
      db,
      const NavisionKatalog(
        warnungen: [],
        gelesen: 6,
        zeilen: [
          NavisionZeile(
            nummer: '800010',
            beschreibung: 'Testbauch',
            beschreibung2: 'ohne Schwarte',
            produktbuchungsgruppe: 'TESTROH',
          ),
          NavisionZeile(
            nummer: '800020',
            beschreibung: 'Testschulter',
            produktbuchungsgruppe: 'TESTROH',
          ),
          NavisionZeile(
            nummer: '810010',
            beschreibung: 'Testsalz',
            produktbuchungsgruppe: 'TESTZUTAT',
          ),
          NavisionZeile(
            nummer: '900010',
            beschreibung: 'Testschinken',
            produktbuchungsgruppe: 'TESTFERTIG',
          ),
          NavisionZeile(nummer: '950010', beschreibung: 'Ohne Gruppe'),
          NavisionZeile(nummer: '810020', produktbuchungsgruppe: 'TESTZUTAT'),
        ],
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> zutat(
    String id,
    String name, {
    String? nummer,
    double? fett,
    DateTime? geloescht,
  }) =>
      db.into(db.entwicklungZutaten).insert(
            EntwicklungZutatenCompanion.insert(
              id: id,
              name: name,
              artikelnummer: Value(nummer),
              fett: Value(fett),
              deletedAt: Value(geloescht),
            ),
          );

  Future<List<Zutat>> zutaten() => (db.select(db.entwicklungZutaten)
        ..orderBy([(z) => OrderingTerm.asc(z.name)]))
      .get();

  test('die Gruppen des eingelesenen Stands mit ihrer Artikelzahl', () async {
    expect(await dienst.gruppen(), [
      (gruppe: 'TESTFERTIG', artikel: 1),
      (gruppe: 'TESTROH', artikel: 2),
      (gruppe: 'TESTZUTAT', artikel: 2),
    ]);
  });

  test('die gewählten Gruppen bleiben fürs nächste Mal', () async {
    expect(await dienst.gewaehlteGruppen(), isEmpty);
    await dienst.gruppenMerken({'TESTZUTAT', 'TESTROH'});
    expect(await dienst.gewaehlteGruppen(), {'TESTROH', 'TESTZUTAT'});
    await dienst.gruppenMerken({'TESTROH'});
    expect(await dienst.gewaehlteGruppen(), {'TESTROH'});
  });

  test('ohne Gruppe gibt es nichts abzugleichen', () async {
    final a = await dienst.abgleich({});
    expect(a.neu, isEmpty);
    expect(a.vorhanden, 0);
  });

  test('neu ist, wessen Artikelnummer der Katalog nicht kennt', () async {
    await zutat('z1', 'Bauch, wie ich ihn nenne', nummer: '800010');
    // Gleicher Name, aber ohne Nummer: zählt nicht als vorhanden.
    await zutat('z2', 'Testsalz');
    // Gelöscht: kommt nicht wieder.
    await zutat('z3', 'Alt', nummer: '810020', geloescht: DateTime(2026));

    final a = await dienst.abgleich({'TESTROH', 'TESTZUTAT'});

    // Nach Namen: Testsalz vor Testschulter.
    expect(a.neu.map((n) => n.artikelnummer), ['810010', '800020']);
    expect(a.vorhanden, 2);
  });

  test('anlegen: Nummer und Name, sonst nichts — und nichts überschrieben',
      () async {
    await zutat('z1', 'Bauch, wie ich ihn nenne', nummer: '800010', fett: 30);
    final a = await dienst.abgleich({'TESTROH', 'TESTZUTAT'});
    final wann = DateTime(2026, 11, 3, 8);

    expect(await dienst.anlegen(a.neu, jetzt: wann), 3);

    final alle = await zutaten();
    expect(alle, hasLength(4));
    // Die bestehende Zutat ist unverändert.
    final bestand = alle.singleWhere((z) => z.id == 'z1');
    expect(bestand.name, 'Bauch, wie ich ihn nenne');
    expect(bestand.fett, 30);

    final schulter = alle.singleWhere((z) => z.artikelnummer == '800020');
    expect(schulter.name, 'Testschulter');
    expect(schulter.createdAt, wann);
    expect(schulter.fett, isNull);
    expect(schulter.allergene, isNull);
    expect(schulter.istFleisch, isFalse);
    // Ohne Beschreibung trägt die Zutat ihre Nummer als Namen.
    expect(alle.singleWhere((z) => z.artikelnummer == '810020').name, '810020');

    // Danach ist nichts mehr neu.
    final danach = await dienst.abgleich({'TESTROH', 'TESTZUTAT'});
    expect(danach.neu, isEmpty);
    expect(danach.vorhanden, 4);
  });

  test('zweimal dasselbe anlegen ergibt nichts doppelt', () async {
    final a = await dienst.abgleich({'TESTROH'});
    expect(await dienst.anlegen(a.neu), 2);
    expect(await dienst.anlegen(a.neu), 0);
    expect(await zutaten(), hasLength(2));
  });

  test('der Name nimmt „Beschreibung 2" mit', () async {
    final a = await dienst.abgleich({'TESTROH'});
    expect(zutatName(a.neu.first), 'Testbauch ohne Schwarte');
  });

  test('frisch angelegt heißt „nicht gepflegt" — bis Nährwerte da sind',
      () async {
    await dienst.anlegen((await dienst.abgleich({'TESTZUTAT'})).neu);
    final salz =
        (await zutaten()).singleWhere((z) => z.artikelnummer == '810010');
    expect(zutatGepflegt(salz), isFalse);

    expect(
      zutatGepflegt(
        salz.copyWith(
          energieKj: const Value(0),
          energieKcal: const Value(0),
          fett: const Value(0),
          gesaettigteFettsaeuren: const Value(0),
          kohlenhydrate: const Value(0),
          zucker: const Value(0),
          eiweiss: const Value(0),
          salz: const Value(99),
        ),
      ),
      isTrue,
    );
    // Wasser braucht keine Nährwerte.
    expect(zutatGepflegt(salz.copyWith(istWasser: true)), isTrue);
  });
}
