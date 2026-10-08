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
/// die Ausbeute zurückgerechnet, wie viel Rohware am Anfang der Kette
/// stehen muss. Rechnet sie falsch, fehlt in der Produktion Ware — und
/// zwar erst dann sichtbar, wenn es zu spät ist.
///
/// Ausbeute und Leistung kommen aus den erfassten Produktionen (Ø der
/// letzten zehn), die Leistung alternativ aus den hinterlegten
/// Leistungsdaten der Abteilung. Alle Daten sind erfunden.
void main() {
  late AppDatabase db;

  setUp(() => db = testDatenbank());
  tearDown(() => db.close());

  /// Eine erfasste Produktion: [kg] Rohware, dazu wahlweise Verlust und
  /// Zeit — als Minuten, als Start/Ende oder als kg/h.
  Future<void> produktion(
    String productId, {
    required String id,
    DateTime? datum,
    double? kg = 1000,
    double? verlust,
    double? minuten,
    String? start,
    String? ende,
    double? kgProStundeRoh,
  }) async {
    await db.into(db.productionHistory).insert(
          ProductionHistoryCompanion.insert(
            id: id,
            productId: productId,
            datum: datum ?? DateTime(2026, 9, 1),
            kgRohware: Value(kg),
            kgFertigware: Value(
              (kg != null && verlust != null) ? kg * (1 - verlust) : null,
            ),
            verlustAnteil: Value(verlust),
            startzeit: Value(start),
            endzeit: Value(ende),
            produktionszeitMinuten: Value(minuten),
            kgProStundeRoh: Value(kgProStundeRoh),
          ),
        );
  }

  group('Rückwärtsrechnung der Mengen', () {
    test('ohne Ausbeute bleibt die Menge über alle Schritte gleich',
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

    test('die Ausbeute der erfassten Produktionen erhöht die Rohware',
        () async {
      await seedArtikel(db, id: 'p2', nummer: '1002');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p2',
        reihenfolge: 1,
        abteilung: 'zerlegung',
      );
      // 20 % Verlust: Für 800 kg fertig braucht es 1000 kg Rohware.
      await produktion('p2', id: 'h1', verlust: 0.2);

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p2',
        mengeKg: 800,
        startTag: DateTime(2026, 9, 14),
      );

      expect(plan.rohwareKg, closeTo(1000, 0.01));
      expect(plan.ausbeute.quelle, AusbeuteQuelle.historie);
    });

    test('Ausbeute an Schritten oder am Artikel zählt nicht mehr', () async {
      // Beides war in der App nie einzugeben. Was davon noch in alten
      // Daten steht, darf den Plan nicht leise verändern.
      await seedArtikel(db, id: 'p3', nummer: '1003');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p3',
        reihenfolge: 1,
        abteilung: 'zerlegung',
        ausbeuteFaktor: 0.5,
      );
      await (db.update(db.products)..where((p) => p.id.equals('p3')))
          .write(const ProductsCompanion(gesamtAusbeuteFaktor: Value(0.6)));

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p3',
        mengeKg: 400,
        startTag: DateTime(2026, 9, 14),
      );

      expect(plan.ausbeute.quelle, AusbeuteQuelle.keine);
      expect(plan.rohwareKg, closeTo(400, 0.01));
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

    test('eine Anlage aus einer anderen Abteilung bestimmt nicht die Spur',
        () async {
      // Der Rollenschneider steht im Katalog der Zerlegung, arbeitet bei
      // diesem Artikel aber vorn an der Bratstraße mit.
      await seedArtikel(db, id: 'p7', nummer: '1007');
      await seedAnlage(
        db,
        id: 'rs',
        name: 'Rollenschneider',
        abteilung: 'zerlegung',
      );
      await seedAnlage(
        db,
        id: 'bs',
        name: 'Bratstraße 1',
        abteilung: 'bratstrasse',
      );
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p7',
        reihenfolge: 1,
        abteilung: 'bratstrasse',
        maschineId: 'rs',
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p7',
        reihenfolge: 2,
        abteilung: 'bratstrasse',
        maschineId: 'bs',
      );

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p7',
        mengeKg: 100,
        startTag: DateTime(2026, 9, 14),
      );

      expect(plan.schritte.single.maschineId, 'bs');
    });
  });

  group('Ausbeute: Rohware und Fertigware', () {
    test('die Ausbeute ist der Ø der erfassten Produktionen', () async {
      await seedArtikel(db, id: 'p7', nummer: '12429');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p7',
        reihenfolge: 1,
        abteilung: 'bratstrasse',
      );
      await produktion('p7', id: 'h1', verlust: 0.40);
      await produktion('p7', id: 'h2', verlust: 0.42);

      final a = await ermittleAusbeute(db, 'p7');

      expect(a.quelle, AusbeuteQuelle.historie);
      expect(a.faktor, closeTo(0.59, 1e-9));
      expect(a.historieAnzahl, 2);
    });

    test('es zählen die letzten zehn Produktionen mit Fertigware', () async {
      await seedArtikel(db, id: 'p12', nummer: '12430');
      // Zehn aktuelle mit 40 % Verlust …
      for (var t = 1; t <= 10; t++) {
        await produktion(
          'p12',
          id: 'neu$t',
          datum: DateTime(2026, 9, t),
          verlust: 0.40,
        );
      }
      // … zwei ältere mit 10 % und eine neue ohne Fertigware: Sie zählen
      // nicht.
      await produktion(
        'p12',
        id: 'alt1',
        datum: DateTime(2025, 1, 1),
        verlust: 0.10,
      );
      await produktion(
        'p12',
        id: 'alt2',
        datum: DateTime(2025, 1, 2),
        verlust: 0.10,
      );
      await produktion('p12', id: 'ohne', datum: DateTime(2026, 9, 20));

      final a = await ermittleAusbeute(db, 'p12');

      expect(a.faktor, closeTo(0.60, 1e-9));
      expect(a.historieAnzahl, kLetzteProduktionen);
    });

    test('ohne erfasste Produktion gilt die Eingabe im Planen-Dialog',
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

      await produktion('p8', id: 'h1', verlust: 0.25);
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
      await produktion('p9', id: 'h1', verlust: 0.44);

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
      expect(plan.ausbeute.quelle, AusbeuteQuelle.historie);
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
      await produktion('p10', id: 'h1', verlust: 0.44, kgProStundeRoh: 620);

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

    test('ein von Hand eingetragener Verlust gilt nur ohne erfasste Ausbeute',
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

      await produktion('p11', id: 'h1', verlust: 0.5);
      final mit = await berechneSchrittPlan(
        db: db,
        productId: 'p11',
        mengeKg: 800,
        startTag: DateTime(2026, 9, 14),
        ausbeuteErsatz: 0.8,
      );
      expect(mit.ausbeute.quelle, AusbeuteQuelle.historie);
      expect(mit.rohwareKg, closeTo(1600, 0.01));
    });
  });

  group('Leistung: hinterlegt oder aus den letzten Produktionen', () {
    test('ohne Leistungsdaten rechnet die Abteilung mit dem Ø der letzten '
        'Produktionen', () async {
      // Ø 500 kg in Ø 300 min → 1.000 kg brauchen 600 min.
      await seedArtikel(db, id: 'p20', nummer: '2020');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p20',
        reihenfolge: 1,
        abteilung: 'wurstkueche',
        basisMengeKg: 0,
        basisDauerMinuten: 0,
      );
      await produktion(
        'p20',
        id: 'h1',
        datum: DateTime(2026, 9, 1),
        kg: 400,
        minuten: 240,
      );
      await produktion(
        'p20',
        id: 'h2',
        datum: DateTime(2026, 9, 2),
        kg: 600,
        minuten: 360,
      );

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p20',
        mengeKg: 1000,
        startTag: DateTime(2026, 9, 14),
      );

      final s = plan.schritte.single;
      expect(s.dauerQuelle, DauerQuelle.historieErsatz);
      expect(s.ausHistorie, isTrue);
      expect(s.platzhalter, isFalse);
      expect(s.historie?.anzahl, 2);
      expect(s.dauerMinuten, closeTo(600, 0.5));
    });

    test('hinterlegte Leistungsdaten gehen den Produktionen vor', () async {
      await seedArtikel(db, id: 'p21', nummer: '2021');
      // 100 kg in 30 min → 1.000 kg in 300 min.
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p21',
        reihenfolge: 1,
        abteilung: 'wurstkueche',
        basisMengeKg: 100,
        basisDauerMinuten: 30,
      );
      await produktion('p21', id: 'h1', kg: 500, minuten: 300);

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p21',
        mengeKg: 1000,
        startTag: DateTime(2026, 9, 14),
      );

      final s = plan.schritte.single;
      expect(s.dauerQuelle, DauerQuelle.leistungsdaten);
      expect(s.ausHistorie, isFalse);
      expect(s.dauerMinuten, closeTo(300, 0.5));
    });

    test('die Leistungsdaten gelten auch, wenn eine andere Anlage der '
        'Abteilung vorn steht', () async {
      // Früher zählte nur der erste Schritt — zog man eine Anlage davor,
      // waren die Leistungsdaten scheinbar weg.
      await seedArtikel(db, id: 'p29', nummer: '2029');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p29',
        reihenfolge: 1,
        abteilung: 'wurstkueche',
        basisMengeKg: 0,
        basisDauerMinuten: 0,
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p29',
        reihenfolge: 2,
        abteilung: 'wurstkueche',
        basisMengeKg: 200,
        basisDauerMinuten: 60,
      );

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p29',
        mengeKg: 600,
        startTag: DateTime(2026, 9, 14),
      );

      expect(plan.schritte.single.dauerQuelle, DauerQuelle.leistungsdaten);
      expect(plan.schritte.single.dauerMinuten, closeTo(180, 0.5));
    });

    test('eine Zeit ohne Menge ist keine Leistung', () async {
      await seedArtikel(db, id: 'p30', nummer: '2030');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p30',
        reihenfolge: 1,
        abteilung: 'wurstkueche',
        basisMengeKg: 0,
        basisDauerMinuten: 90,
      );

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p30',
        mengeKg: 500,
        startTag: DateTime(2026, 9, 14),
      );

      expect(plan.schritte.single.platzhalter, isTrue);
      expect(plan.schritte.single.dauerMinuten, kPlatzhalterMinuten);
    });

    test('fixe Zeiten an den Schritten zählen nicht mehr', () async {
      await seedArtikel(db, id: 'p25', nummer: '2025');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p25',
        reihenfolge: 1,
        abteilung: 'kutterabteilung',
        basisMengeKg: 0,
        basisDauerMinuten: 0,
      );
      // Ein Altwert aus früheren Versionen.
      await (db.update(db.productSteps)..where((s) => s.id.equals('s1')))
          .write(const ProductStepsCompanion(fixZeitMinuten: Value(20)));
      await produktion('p25', id: 'h1', kg: 500, minuten: 300);

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p25',
        mengeKg: 250,
        startTag: DateTime(2026, 9, 14),
      );

      // 150 min für 250 kg — ohne Rüstzeit obendrauf.
      expect(plan.schritte.single.dauerMinuten, closeTo(150, 0.5));
    });

    test('ohne Leistungsdaten und ohne Produktion mit Zeit bleibt es ein '
        'Platzhalter', () async {
      await seedArtikel(db, id: 'p22', nummer: '2022');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p22',
        reihenfolge: 1,
        abteilung: 'wurstkueche',
        basisMengeKg: 0,
        basisDauerMinuten: 0,
      );
      // Eine Menge ohne Zeit: Daraus lässt sich nichts hochrechnen.
      await produktion('p22', id: 'h1', kg: 500);

      expect(await historienLeistung(db, 'p22'), isNull);
      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p22',
        mengeKg: 1000,
        startTag: DateTime(2026, 9, 14),
      );
      expect(plan.schritte.single.platzhalter, isTrue);
      expect(plan.schritte.single.historie, isNull);
    });

    test('es zählen nur die letzten zehn Produktionen mit Zeit', () async {
      await seedArtikel(db, id: 'p23', nummer: '2023');
      // Zehn aktuelle Produktionen mit 100 kg/h …
      for (var t = 1; t <= 10; t++) {
        await produktion(
          'p23',
          id: 'neu$t',
          datum: DateTime(2026, 9, t),
          kg: 500,
          minuten: 300,
        );
      }
      // … zwei alte mit 10 kg/h und eine neue ohne Zeit: Sie zählen nicht.
      await produktion(
        'p23',
        id: 'alt1',
        datum: DateTime(2025, 1, 1),
        kg: 100,
        minuten: 600,
      );
      await produktion(
        'p23',
        id: 'alt2',
        datum: DateTime(2025, 1, 2),
        kg: 100,
        minuten: 600,
      );
      await produktion(
        'p23',
        id: 'ohneZeit',
        datum: DateTime(2026, 9, 20),
        kg: 900,
      );

      final h = await historienLeistung(db, 'p23');

      expect(h, isNotNull);
      expect(h!.anzahl, kLetzteProduktionen);
      expect(h.mengeKg, closeTo(500, 1e-9));
      expect(h.minuten, closeTo(300, 1e-9));
      expect(h.kgProStunde, closeTo(100, 1e-9));
    });

    test('die Zeit kommt notfalls aus Start und Ende oder aus dem kg/h',
        () async {
      await seedArtikel(db, id: 'p24', nummer: '2024');
      // 06:00–10:00 sind 240 min; 600 kg bei 150 kg/h ebenfalls.
      await produktion(
        'p24',
        id: 'h1',
        datum: DateTime(2026, 9, 1),
        kg: 400,
        start: '06:00',
        ende: '10:00',
      );
      await produktion(
        'p24',
        id: 'h2',
        datum: DateTime(2026, 9, 2),
        kg: 600,
        kgProStundeRoh: 150,
      );

      final h = await historienLeistung(db, 'p24');

      expect(h!.anzahl, 2);
      expect(h.mengeKg, closeTo(500, 1e-9));
      expect(h.minuten, closeTo(240, 1e-9));
    });

    test('eine Bratstraße ohne Produktionen und ohne Leistungsdaten ist ein '
        'Platzhalter', () async {
      await seedArtikel(db, id: 'p26', nummer: '2026');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p26',
        reihenfolge: 1,
        abteilung: 'bratstrasse',
        basisMengeKg: 0,
        basisDauerMinuten: 0,
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p26',
        reihenfolge: 2,
        abteilung: 'bratstrasse',
        basisMengeKg: 0,
        basisDauerMinuten: 0,
      );

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p26',
        mengeKg: 500,
        startTag: DateTime(2026, 9, 14),
      );

      // Sonst rutschte der Artikel mit geratenen 30 Minuten in den
      // Planungsvorschlag.
      expect(plan.schritte.single.platzhalter, isTrue);
      expect(plan.schritte.single.ausHistorie, isFalse);
    });

    test('die Menge eines Auftrags ändern rechnet wie das Einplanen',
        () async {
      // Wurstküche ohne Leistungsdaten, Bratstraße mit erfassten
      // Produktionen.
      await seedArtikel(db, id: 'p27', nummer: '2027');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p27',
        reihenfolge: 1,
        abteilung: 'wurstkueche',
        basisMengeKg: 0,
        basisDauerMinuten: 0,
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p27',
        reihenfolge: 2,
        abteilung: 'bratstrasse',
        basisMengeKg: 0,
        basisDauerMinuten: 0,
      );
      await produktion('p27', id: 'h1', kg: 500, minuten: 300);

      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p27',
        mengeKg: 800,
        startTag: DateTime(2026, 9, 14),
      );
      final wurstkueche = await ladeAbteilungsDauerModell(
        db,
        productId: 'p27',
        abteilung: 'wurstkueche',
      );
      final bratstrasse = await ladeAbteilungsDauerModell(
        db,
        productId: 'p27',
        abteilung: 'bratstrasse',
      );

      // 800 kg bei 100 kg/h: 480 min in beiden Abteilungen.
      expect(plan.schritte[0].dauerMinuten, closeTo(480, 0.5));
      expect(plan.schritte[1].dauerMinuten, closeTo(480, 0.5));
      expect(plan.schritte[1].dauerQuelle, DauerQuelle.historie);

      final wk = wurstkueche!.dauerFuer(800);
      expect(wk.minuten, closeTo(plan.schritte[0].dauerMinuten, 0.5));
      expect(wk.quelle, DauerQuelle.historieErsatz);
      final bs = bratstrasse!.dauerFuer(800);
      expect(bs.minuten, closeTo(plan.schritte[1].dauerMinuten, 0.5));
      expect(bs.quelle, DauerQuelle.historie);
      expect(bratstrasse.dauerFuer(400).minuten, closeTo(240, 0.5));

      expect(
        await ladeAbteilungsDauerModell(
          db,
          productId: 'p27',
          abteilung: 'verpackung',
        ),
        isNull,
      );
    });

    test('kommt eine Abteilung zweimal vor, zählt der Block mit der Anlage '
        'des Auftrags', () async {
      await seedArtikel(db, id: 'p28', nummer: '2028');
      await seedAnlage(db, id: 'm1', name: 'Anlage 1', abteilung: 'verpackung');
      await seedAnlage(db, id: 'm2', name: 'Anlage 2', abteilung: 'verpackung');
      // 100 kg: vorne 60 min auf Anlage 1, hinten 30 min auf Anlage 2.
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p28',
        reihenfolge: 1,
        abteilung: 'verpackung',
        maschineId: 'm1',
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p28',
        reihenfolge: 2,
        abteilung: 'bratstrasse',
      );
      await seedSchritt(
        db,
        id: 's3',
        productId: 'p28',
        reihenfolge: 3,
        abteilung: 'verpackung',
        basisDauerMinuten: 30,
        maschineId: 'm2',
      );

      Future<double> dauer(String? maschineId) async {
        final m = await ladeAbteilungsDauerModell(
          db,
          productId: 'p28',
          abteilung: 'verpackung',
          maschineId: maschineId,
        );
        return m!.dauerFuer(100).minuten;
      }

      expect(await dauer('m2'), closeTo(30, 0.5));
      expect(await dauer('m1'), closeTo(60, 0.5));
      expect(await dauer(null), closeTo(60, 0.5));
    });
  });
}
