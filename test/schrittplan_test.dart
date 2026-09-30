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

  group('Ausbeute: Rohware und Fertigware', () {
    Future<void> gesamtausbeute(String productId, double faktor) async {
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion(gesamtAusbeuteFaktor: Value(faktor)));
    }

    Future<void> historie(
      String productId, {
      required String id,
      required double verlust,
      double? kgProStundeRoh,
    }) async {
      await db.into(db.productionHistory).insert(
            ProductionHistoryCompanion.insert(
              id: id,
              productId: productId,
              datum: DateTime(2026, 9, 1),
              kgRohware: const Value(1000),
              kgFertigware: Value(1000 * (1 - verlust)),
              verlustAnteil: Value(verlust),
              kgProStundeRoh: Value(kgProStundeRoh),
            ),
          );
    }

    test('die Gesamtausbeute des Artikels geht vor der Historie', () async {
      await seedArtikel(db, id: 'p7', nummer: '12429');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p7',
        reihenfolge: 1,
        abteilung: 'bratstrasse',
      );
      await gesamtausbeute('p7', 0.56);
      await historie('p7', id: 'h1', verlust: 0.44);

      final a = await ermittleAusbeute(db, 'p7');

      expect(a.quelle, AusbeuteQuelle.artikel);
      expect(a.faktor, closeTo(0.56, 1e-9));
      // Die Historie steht zum Vergleich daneben.
      expect(a.historie, closeTo(0.56, 1e-9));
    });

    test('ohne Artikelwert zählt die Historie, erst danach die Eingabe',
        () async {
      await seedArtikel(db, id: 'p8', nummer: '1008');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p8',
        reihenfolge: 1,
        abteilung: 'bratstrasse',
      );

      expect(
        (await ermittleAusbeute(db, 'p8', ersatz: 0.7)).quelle,
        AusbeuteQuelle.eingabe,
      );
      expect((await ermittleAusbeute(db, 'p8')).quelle, AusbeuteQuelle.keine);

      await historie('p8', id: 'h1', verlust: 0.25);
      final a = await ermittleAusbeute(db, 'p8', ersatz: 0.7);

      expect(a.quelle, AusbeuteQuelle.historie);
      expect(a.faktor, closeTo(0.75, 1e-9));
    });

    test('Rohware umgerechnet und geplant ergibt wieder dieselbe Rohware',
        () async {
      // Der Fehler aus dem Planen-Dialog: 7.200 kg Rohware gingen als
      // Fertigware in den Plan, und heraus kamen 12.857 kg Rohware — der
      // Verlust war doppelt drin. Richtig: 7.200 kg Rohware ergeben bei
      // 56 % Ausbeute 4.032 kg Fertigware, und der Plan dazu braucht
      // wieder genau 7.200 kg Rohware.
      await seedArtikel(db, id: 'p9', nummer: '12429');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p9',
        reihenfolge: 1,
        abteilung: 'bratstrasse',
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p9',
        reihenfolge: 2,
        abteilung: 'verpackung',
      );
      await gesamtausbeute('p9', 0.56);

      final a = await ermittleAusbeute(db, 'p9');
      final fertig = a.fertigAusRoh(7200);
      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p9',
        mengeKg: fertig,
        startTag: DateTime(2026, 9, 14),
      );

      expect(fertig, closeTo(4032, 0.01));
      expect(plan.rohwareKg, closeTo(7200, 0.01));
      expect(plan.fertigwareKg, closeTo(4032, 0.01));
      expect(plan.ausbeute.quelle, AusbeuteQuelle.artikel);
      // Bis einschließlich Bratstraße Rohware, danach Fertigware.
      expect(plan.schritte[0].mengeKg, closeTo(7200, 0.01));
      expect(plan.schritte[1].mengeKg, closeTo(4032, 0.01));
    });

    test('die Bratstraße rechnet mit dem Ø kg/h Rohware der Historie',
        () async {
      // 620 kg Rohware je Stunde: 5.580 kg Rohware brauchen 9 Stunden.
      await seedArtikel(db, id: 'p10', nummer: '12429');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p10',
        reihenfolge: 1,
        abteilung: 'bratstrasse',
      );
      await gesamtausbeute('p10', 0.56);
      await historie('p10', id: 'h1', verlust: 0.44, kgProStundeRoh: 620);

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p10',
        mengeKg: 5580 * 0.56,
        startTag: DateTime(2026, 9, 14),
      );

      expect(plan.rohwareKg, closeTo(5580, 0.01));
      expect(plan.schritte.single.ausHistorie, isTrue);
      expect(plan.schritte.single.dauerMinuten, closeTo(540, 0.5));
    });

    test('ein von Hand eingetragener Verlust gilt nur ohne eigene Ausbeute',
        () async {
      await seedArtikel(db, id: 'p11', nummer: '1011');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p11',
        reihenfolge: 1,
        abteilung: 'bratstrasse',
      );

      final ohne = await berechneSchrittPlan(
        db: db,
        productId: 'p11',
        mengeKg: 800,
        startTag: DateTime(2026, 9, 14),
        ausbeuteErsatz: 0.8,
      );
      expect(ohne.ausbeute.quelle, AusbeuteQuelle.eingabe);
      expect(ohne.rohwareKg, closeTo(1000, 0.01));

      await gesamtausbeute('p11', 0.5);
      final mit = await berechneSchrittPlan(
        db: db,
        productId: 'p11',
        mengeKg: 800,
        startTag: DateTime(2026, 9, 14),
        ausbeuteErsatz: 0.8,
      );
      expect(mit.ausbeute.quelle, AusbeuteQuelle.artikel);
      expect(mit.rohwareKg, closeTo(1600, 0.01));
    });
  });
}
