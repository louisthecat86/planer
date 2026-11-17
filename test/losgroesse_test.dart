import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/rezepturen/losgroesse.dart';

import 'helpers/test_db.dart';

/// Tests für die Losgröße: Die Rezeptur wird auf eine gewünschte
/// Gesamtmenge umgerechnet — jede Zeile im selben Verhältnis, die Summe
/// trifft die Menge aufs Gramm. Alle Rezepturen sind erfunden.
void main() {
  double summe(List<double> m) => m.fold<double>(0, (s, x) => s + x);

  group('Umrechnen', () {
    test('jede Zeile im selben Verhältnis', () {
      expect(aufLosgroesse([98, 2], 250), [245, 5]);
      expect(aufLosgroesse([60, 30, 10], 50), [30, 15, 5]);
    });

    test('kleiner geht genauso wie größer', () {
      expect(aufLosgroesse([245, 5], 100), [98, 2]);
      expect(aufLosgroesse([100], 12.5), [12.5]);
    });

    test('dieselbe Losgröße ändert nichts', () {
      expect(aufLosgroesse([98, 1.8, 0.2], 100), [98, 1.8, 0.2]);
    });

    test('die Summe stimmt aufs Gramm — der Rest geht an die größte Zeile', () {
      // Drei gleiche Teile von 100 kg: 33,333 + 33,333 + 33,333 = 99,999.
      final neu = aufLosgroesse([1, 1, 1], 100);
      expect(summe(neu), closeTo(100, 1e-9));
      expect(neu, [33.334, 33.333, 33.333]);

      final krumm = aufLosgroesse([71.3, 18.25, 7.777, 2.1, 0.573], 333.333);
      expect(summe(krumm), closeTo(333.333, 1e-9));
      // Die größte Zeile bleibt die größte, und keine springt.
      expect(krumm.first, closeTo(71.3 * 333.333 / 100, 0.002));
      for (final m in krumm) {
        expect((m * 1000 - (m * 1000).round()).abs(), lessThan(1e-6));
      }
    });

    test('die Anteile bleiben', () {
      const alt = [82.0, 12.0, 4.5, 1.5];
      final neu = aufLosgroesse(alt, 1250);
      for (var i = 0; i < alt.length; i++) {
        expect(neu[i] / 1250, closeTo(alt[i] / 100, 1e-6));
      }
    });

    test('Zeilen ohne Menge bleiben bei 0', () {
      expect(aufLosgroesse([50, 0, 50], 10), [5, 0, 5]);
    });

    test('ohne Mengen oder ohne Ziel gibt es nichts umzurechnen', () {
      expect(() => aufLosgroesse([], 100), throwsArgumentError);
      expect(() => aufLosgroesse([0, 0], 100), throwsArgumentError);
      expect(() => aufLosgroesse([10], 0), throwsArgumentError);
      expect(() => aufLosgroesse([10], -5), throwsArgumentError);
      expect(() => aufLosgroesse([10], double.nan), throwsArgumentError);
    });
  });

  group('Im Entwurf', () {
    late AppDatabase db;
    late EntwicklungRepository repo;

    setUp(() {
      db = testDatenbank();
      repo = EntwicklungRepository(db);
    });
    tearDown(() => db.close());

    Future<String> zutat(String name) => repo.zutatAnlegen(
          EntwicklungZutatenCompanion(name: Value(name)),
        );

    Future<RezepturVersion> rezeptur() async {
      final id = await repo.rezepturAnlegen(name: 'Testwurst');
      final v = (await repo.neuesteVersion(id))!;
      await repo.positionHinzufuegen(
        v.id,
        zutatId: await zutat('Testfleisch'),
        mengeKg: 98,
      );
      await repo.positionHinzufuegen(
        v.id,
        zutatId: await zutat('Testsalz'),
        mengeKg: 2,
      );
      return v;
    }

    Future<List<double>> mengen(String versionId) async =>
        [for (final p in await repo.positionen(versionId)) p.mengeKg];

    test('alle Zeilen des Stands werden umgerechnet', () async {
      final v = await rezeptur();

      final vorher = await repo.losgroesseSetzen(v.id, 250);

      expect(await mengen(v.id), [245, 5]);
      expect(vorher.values, [98, 2]);
    });

    test('ein anderer Stand bleibt, wie er ist', () async {
      final v = await rezeptur();
      final andere = await repo.rezepturAnlegen(name: 'Andere Testwurst');
      final w = (await repo.neuesteVersion(andere))!;
      await repo.positionHinzufuegen(
        w.id,
        zutatId: await zutat('Testwasser'),
        mengeKg: 40,
      );

      await repo.losgroesseSetzen(v.id, 10);

      expect(await mengen(w.id), [40]);
    });

    test('Rückgängig: genau die Mengen von vorher', () async {
      final v = await rezeptur();
      // Eine Menge, die sich nicht glatt zurückrechnen ließe.
      final vorher = await repo.losgroesseSetzen(v.id, 33.333);
      expect(await mengen(v.id), isNot([98, 2]));

      await repo.zeilenMengenSetzen(v.id, vorher);

      expect(await mengen(v.id), [98, 2]);
    });

    test('ein abgeschlossener Stand lässt sich nicht umrechnen', () async {
      final v = await rezeptur();
      await repo.versionAbschliessen(v.id);

      await expectLater(repo.losgroesseSetzen(v.id, 250), throwsStateError);
      expect(await mengen(v.id), [98, 2]);
    });

    test('ohne Mengen bleibt alles stehen', () async {
      final id = await repo.rezepturAnlegen(name: 'Leere Testwurst');
      final v = (await repo.neuesteVersion(id))!;
      await repo.positionHinzufuegen(v.id, zutatId: await zutat('Testsalz'));

      await expectLater(repo.losgroesseSetzen(v.id, 100), throwsArgumentError);
      expect(await mengen(v.id), [0]);
    });
  });
}
