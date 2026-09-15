// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/whiteboard/whiteboard_provider.dart';

import 'helpers/test_db.dart';

/// Tests für `berechneSchrittPlan` — die Rückwärtsrechnung.
///
/// Das ist das Herz der Planung: Aus der gewünschten FERTIGMENGE wird über
/// die Ausbeutefaktoren zurückgerechnet, wie viel Rohware am Anfang der
/// Kette stehen muss. Rechnet sie falsch, fehlt in der Produktion Ware —
/// und zwar erst dann sichtbar, wenn es zu spät ist.
void main() {
  late AppDatabase db;

  setUp(() => db = testDatenbank());
  tearDown(() => db.close());

  group('Rückwärtsrechnung der Mengen', () {
    test('ohne Ausbeutefaktoren bleibt die Menge über alle Schritte gleich',
        () async {
      await seedArtikel(db, id: 'p1', nummer: '1001');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p1',
        reihenfolge: 1,
        abteilung: 'zerlegung',
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p1',
        reihenfolge: 2,
        abteilung: 'verpackung',
      );

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p1',
        mengeKg: 500,
        startTag: DateTime(2026, 9, 14),
      );

      // Rohes Produkt: Was reingeht, kommt raus.
      expect(plan.rohwareKg, closeTo(500, 0.01));
      for (final s in plan.schritte) {
        expect(s.mengeKg, closeTo(500, 0.01));
      }
    });

    test('ein Ausbeutefaktor erhöht die benötigte Rohware', () async {
      await seedArtikel(db, id: 'p2', nummer: '1002');
      // 80 % Ausbeute: Für 800 kg fertig braucht es 1000 kg Rohware.
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p2',
        reihenfolge: 1,
        abteilung: 'zerlegung',
        ausbeuteFaktor: 0.8,
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p2',
        reihenfolge: 2,
        abteilung: 'verpackung',
      );

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p2',
        mengeKg: 800,
        startTag: DateTime(2026, 9, 14),
      );

      expect(plan.rohwareKg, closeTo(1000, 0.01));
    });

    test('mehrere Ausbeutefaktoren multiplizieren sich auf', () async {
      await seedArtikel(db, id: 'p3', nummer: '1003');
      // 0,5 × 0,8 = 0,4 → für 400 kg fertig braucht es 1000 kg Rohware.
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p3',
        reihenfolge: 1,
        abteilung: 'zerlegung',
        ausbeuteFaktor: 0.5,
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p3',
        reihenfolge: 2,
        abteilung: 'wurstkueche',
        ausbeuteFaktor: 0.8,
      );

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p3',
        mengeKg: 400,
        startTag: DateTime(2026, 9, 14),
      );

      expect(plan.rohwareKg, closeTo(1000, 0.01));
    });
  });

  group('Dauer', () {
    test('skaliert linear mit der Menge', () async {
      await seedArtikel(db, id: 'p4', nummer: '1004');
      // 100 kg in 60 Minuten → 300 kg in 180 Minuten.
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p4',
        reihenfolge: 1,
        abteilung: 'zerlegung',
        basisMengeKg: 100,
        basisDauerMinuten: 60,
      );

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p4',
        mengeKg: 300,
        startTag: DateTime(2026, 9, 14),
      );

      expect(plan.schritte.single.dauerMinuten, closeTo(180, 0.5));
    });
  });

  group('Sonderfälle', () {
    test('ein Artikel ohne Schritte liefert einen leeren Plan', () async {
      await seedArtikel(db, id: 'p5', nummer: '1005');

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p5',
        mengeKg: 100,
        startTag: DateTime(2026, 9, 14),
      );

      expect(plan.schritte, isEmpty);
    });

    test('gelöschte Schritte zählen nicht mit', () async {
      await seedArtikel(db, id: 'p6', nummer: '1006');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p6',
        reihenfolge: 1,
        abteilung: 'zerlegung',
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p6',
        reihenfolge: 2,
        abteilung: 'verpackung',
      );
      // Soft-Delete: Der Schritt bleibt in der Tabelle stehen, darf aber
      // nicht mehr eingeplant werden.
      await (db.update(db.productSteps)..where((s) => s.id.equals('s2')))
          .write(ProductStepsCompanion(deletedAt: Value(DateTime.now())));

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p6',
        mengeKg: 100,
        startTag: DateTime(2026, 9, 14),
      );

      expect(plan.schritte.length, 1);
    });
  });
}
