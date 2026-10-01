// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/auftragsbestand_deckung.dart';
import 'package:produktion_planer/features/auftragsbestand/auftrags_einplanung.dart';

import 'helpers/test_db.dart';

/// Tests für „Zur Planung hinzufügen" im Auftragsbestand — beide Wege:
///
/// * Fester Tag: Die Produktion entsteht im Board, trägt die
///   Auftragszeilen an der Wurzel, und die Zeilen sind damit eingeplant —
///   bis die Produktion gelöscht wird.
/// * Planungsvorschlag: Es entsteht ein Planungsauftrag, die Zeilen sind
///   vorgemerkt — bis er eingeplant oder aufgehoben wird.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = testDatenbank();
    await seedArtikel(db, id: 'p1', nummer: '12981');
    await seedSchritt(
      db,
      id: 's1',
      productId: 'p1',
      reihenfolge: 1,
      abteilung: 'bratstrasse',
    );
    await seedSchritt(
      db,
      id: 's2',
      productId: 'p1',
      reihenfolge: 2,
      abteilung: 'verpackung',
    );
  });
  tearDown(() => db.close());

  final montag = DateTime(2026, 10, 5);
  final bezug = AuftragsBezug(
    beleg: 'VA1',
    warenausgang: montag,
    kg: 250,
    debitor: 'Kunde 1',
  );
  final position = AuftragsPosition(
    id: 1,
    artikelnummer: '12981',
    beleg: 'VA1',
    debitor: 'Kunde 1',
    warenausgang: montag,
    menge: 250,
    kg: 250,
  );

  Future<List<ProduktionsZugang>> zugaenge() async {
    final z = await ladeProduktionsZugaenge(
      db,
      heute: DateTime(2026, 9, 30),
      berichtTag: DateTime(2026, 9, 30),
    );
    return z['12981'] ?? const [];
  }

  test('legt die Kette mit Fertigmenge und Auftragszeilen an', () async {
    final e = await planeAuftragszeilen(
      db: db,
      productId: 'p1',
      fertigKg: 250,
      tag: DateTime(2026, 10, 2, 14, 30),
      bezuege: [bezug],
    );

    expect(e.schritte, 2);
    expect(e.tag, DateTime(2026, 10, 2));

    final tasks = await db.select(db.productionTasks).get();
    expect(tasks, hasLength(2));
    final wurzel = tasks.singleWhere((t) => t.parentTaskId == null);
    expect(wurzel.fertigMengeKg, 250);
    expect(AuftragsBezug.dekodiere(wurzel.auftragsZeilen).single.beleg, 'VA1');
    // Nur die Wurzel trägt die Zuordnung.
    final folge = tasks.singleWhere((t) => t.parentTaskId != null);
    expect(folge.auftragsZeilen, isNull);
    // Alle Schritte am gewählten Tag.
    expect(tasks.every((t) => t.datum == DateTime(2026, 10, 2)), isTrue);
  });

  test('die eingeplante Zeile ist gedeckt und markiert', () async {
    await planeAuftragszeilen(
      db: db,
      productId: 'p1',
      fertigKg: 250,
      tag: DateTime(2026, 10, 2),
      bezuege: [bezug],
    );

    final z = await zugaenge();
    expect(z.single.bezuege.single.beleg, 'VA1');

    final d = berechneDeckung(
      lagerKg: 0,
      positionen: [position],
      zugaenge: z,
    );
    expect(d.fehltKg, 0);
    expect(d.tage.single.zeilen.single.geplant, isTrue);
    expect(d.tage.single.einplanbar, isFalse);
  });

  test('im Board gelöscht: die Zeile ist wieder offen', () async {
    await planeAuftragszeilen(
      db: db,
      productId: 'p1',
      fertigKg: 250,
      tag: DateTime(2026, 10, 2),
      bezuege: [bezug],
    );
    // „Ganze Produktion löschen" im Board: alle Schritte bekommen
    // deletedAt.
    await db
        .update(db.productionTasks)
        .write(ProductionTasksCompanion(deletedAt: Value(DateTime.now())));

    final z = await zugaenge();
    expect(z, isEmpty);

    final d = berechneDeckung(
      lagerKg: 0,
      positionen: [position],
      zugaenge: z,
    );
    expect(d.fehltKg, 250);
    expect(d.tage.single.zeilen.single.geplant, isFalse);
    expect(d.tage.single.einplanbar, isTrue);
  });

  test('ohne Prozessschritte wird nichts angelegt', () async {
    await seedArtikel(db, id: 'p2', nummer: '13977');

    await expectLater(
      planeAuftragszeilen(
        db: db,
        productId: 'p2',
        fertigKg: 100,
        tag: DateTime(2026, 10, 2),
        bezuege: const [],
      ),
      throwsA(isA<StateError>()),
    );
    expect(await db.select(db.productionTasks).get(), isEmpty);
  });

  group('An den Planungsvorschlag übergeben', () {
    test('legt einen Planungsauftrag mit Zeilen und Termin an', () async {
      final id = await uebergebeAnPlanungsvorschlag(
        db: db,
        productId: 'p1',
        fertigKg: 250,
        termin: DateTime(2026, 10, 2, 14, 30),
        bezuege: [bezug],
      );

      final d = await (db.select(db.demands)..where((x) => x.id.equals(id)))
          .getSingle();
      expect(d.quelle, kQuelleAuftragsbestand);
      expect(d.mengeKgFertig, 250);
      expect(d.termin, DateTime(2026, 10, 2));
      expect(AuftragsBezug.dekodiere(d.auftragsZeilen).single.beleg, 'VA1');
      expect(d.notizen, contains('Kunde 1'));
      // Im Board steht noch nichts — das legt erst der Vorschlag an.
      expect(await db.select(db.productionTasks).get(), isEmpty);
    });

    test('die Zeile ist vorgemerkt und lässt sich nicht erneut bündeln',
        () async {
      await uebergebeAnPlanungsvorschlag(
        db: db,
        productId: 'p1',
        fertigKg: 250,
        termin: DateTime(2026, 10, 2),
        bezuege: [bezug],
      );

      final v = await ladeVormerkungen(db);
      final d = berechneDeckung(
        lagerKg: 0,
        positionen: [position],
        zugaenge: await zugaenge(),
        vormerkungen: v['12981'] ?? const [],
      );
      final z = d.tage.single.zeilen.single;
      expect(z.vorgemerkt, isTrue);
      expect(z.geplant, isFalse);
      expect(d.tage.single.einplanbar, isFalse);
      expect(d.erledigt, isTrue);
      expect(d.fruehesterVormerkTermin, DateTime(2026, 10, 2));
    });

    test('Vormerkung aufgehoben: die Zeile ist wieder offen', () async {
      final id = await uebergebeAnPlanungsvorschlag(
        db: db,
        productId: 'p1',
        fertigKg: 250,
        termin: DateTime(2026, 10, 2),
        bezuege: [bezug],
      );
      await hebeVormerkungAuf(db: db, bedarfId: id);

      final v = await ladeVormerkungen(db);
      expect(v, isEmpty);
      final d = berechneDeckung(
        lagerKg: 0,
        positionen: [position],
        vormerkungen: v['12981'] ?? const [],
      );
      expect(d.tage.single.einplanbar, isTrue);
    });
  });

  group('Vorschlag für den Produktionstag', () {
    final heute = DateTime(2026, 9, 30); // Mittwoch

    test('der Arbeitstag vor dem Versand', () {
      // Versand Mittwoch 07.10. → Dienstag 06.10.
      expect(
        vorschlagProduktionstag(DateTime(2026, 10, 7), heute),
        DateTime(2026, 10, 6),
      );
    });

    test('über das Wochenende auf den Freitag', () {
      // Versand Montag 05.10. → Freitag 02.10.
      expect(
        vorschlagProduktionstag(DateTime(2026, 10, 5), heute),
        DateTime(2026, 10, 2),
      );
    });

    test('nie vor heute', () {
      expect(
        vorschlagProduktionstag(DateTime(2026, 9, 30), heute),
        heute,
      );
      expect(
        vorschlagProduktionstag(DateTime(2026, 9, 28), heute),
        heute,
      );
    });
  });
}
