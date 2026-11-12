// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/auftragsbestand_deckung.dart';
import 'package:produktion_planer/core/services/loeschen_mit_rueckweg.dart';
import 'package:produktion_planer/features/auftragsbestand/auftrags_einplanung.dart';

import 'helpers/test_db.dart';

/// Tests für das Löschen ohne Rückfrage: Bedarf, Auftrag im Board und
/// erfasste Produktion verschwinden sofort — und „Rückgängig" holt genau
/// das zurück, was gelöscht wurde, in dem Zustand von vorher.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = testDatenbank();
    await seedArtikel(db, id: 'p1', nummer: '70001');
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

  Future<void> auftrag(
    String id, {
    String? eltern,
    DateTime? geloescht,
    String productId = 'p1',
  }) =>
      db.into(db.productionTasks).insert(
            ProductionTasksCompanion.insert(
              id: id,
              productId: productId,
              mengeKg: 100,
              datum: DateTime(2026, 10, 2),
              abteilung: eltern == null ? 'bratstrasse' : 'verpackung',
              geplanteDauerMinuten: 60,
              geplanteMitarbeiter: 2,
              parentTaskId: Value(eltern),
              startZeit: const Value('07:30'),
              notizen: Value('Notiz $id'),
              deletedAt: Value(geloescht),
            ),
          );

  Future<ProductionTask> lade(String id) =>
      (db.select(db.productionTasks)..where((t) => t.id.equals(id)))
          .getSingle();

  Future<Set<String>> sichtbar() async => {
        for (final t in await (db.select(db.productionTasks)
              ..where((t) => t.deletedAt.isNull()))
            .get())
          t.id,
      };

  group('Bedarf', () {
    test('löschen und zurückholen', () async {
      await seedBedarf(db, id: 'b1', productId: 'p1', mengeKgFertig: 300);
      final vorher = await db.select(db.demands).getSingle();

      expect(await LoeschenMitRueckweg.bedarf(db, 'b1'), isTrue);
      expect((await db.select(db.demands).getSingle()).deletedAt, isNotNull);

      await LoeschenMitRueckweg.bedarfZurueck(db, 'b1');
      // Die ganze Zeile wie vorher — nicht nur „wieder da".
      expect(await db.select(db.demands).getSingle(), vorher);
    });

    test('schon gelöscht oder unbekannt: nichts zu tun', () async {
      await seedBedarf(db, id: 'b1', productId: 'p1', mengeKgFertig: 300);
      final frueher = DateTime(2026, 9, 1, 8);
      await LoeschenMitRueckweg.bedarf(db, 'b1', jetzt: frueher);

      expect(await LoeschenMitRueckweg.bedarf(db, 'b1'), isFalse);
      expect(await LoeschenMitRueckweg.bedarf(db, 'gibt-es-nicht'), isFalse);
      // Der Zeitpunkt der ersten Löschung bleibt stehen.
      expect((await db.select(db.demands).getSingle()).deletedAt, frueher);
    });

    test('Planungsauftrag: Zeilen frei, nach Rückgängig wieder vorgemerkt',
        () async {
      final id = await uebergebeAnPlanungsvorschlag(
        db: db,
        productId: 'p1',
        fertigKg: 250,
        termin: DateTime(2026, 10, 2),
        bezuege: [bezug],
      );
      expect(await ladeVormerkungen(db), isNotEmpty);

      await LoeschenMitRueckweg.bedarf(db, id);
      expect(await ladeVormerkungen(db), isEmpty);

      await LoeschenMitRueckweg.bedarfZurueck(db, id);
      final v = await ladeVormerkungen(db);
      expect(v['70001'], hasLength(1));
      expect(v['70001']!.single.bedarfId, id);
    });
  });

  group('Auftrag im Board', () {
    test('ein Schritt: nur der verschwindet und kommt wieder', () async {
      await auftrag('t1');
      await auftrag('t2', eltern: 't1');
      final vorher = await lade('t2');

      final weg = await LoeschenMitRueckweg.auftraege(db, ['t2']);
      expect(weg, ['t2']);
      expect(await sichtbar(), {'t1'});

      await LoeschenMitRueckweg.auftraegeZurueck(db, weg);
      expect(await sichtbar(), {'t1', 't2'});
      // Tag, Zeit, Notiz, Verkettung: alles wie vorher. Nur der
      // Änderungsstempel ist neu.
      final nachher = await lade('t2');
      expect(nachher.copyWith(updatedAt: vorher.updatedAt), vorher);
    });

    test('die Kette: Wurzel und alle Nachfahren, sonst nichts', () async {
      await auftrag('t1');
      await auftrag('t2', eltern: 't1');
      await auftrag('t3', eltern: 't2');
      // Eine zweite Planung desselben Artikels — eigene Kette.
      await auftrag('u1');
      await auftrag('u2', eltern: 'u1');
      // Ein anderer Artikel.
      await seedArtikel(db, id: 'p2', nummer: '70002');
      await auftrag('x1', productId: 'p2');

      // Von jedem Glied aus dieselbe Kette.
      for (final start in ['t1', 't2', 't3']) {
        final kette = await LoeschenMitRueckweg.kette(db, await lade(start));
        expect(kette.toSet(), {'t1', 't2', 't3'}, reason: 'ab $start');
      }

      final weg = await LoeschenMitRueckweg.auftraege(
        db,
        await LoeschenMitRueckweg.kette(db, await lade('t2')),
      );
      expect(weg.toSet(), {'t1', 't2', 't3'});
      expect(await sichtbar(), {'u1', 'u2', 'x1'});

      await LoeschenMitRueckweg.auftraegeZurueck(db, weg);
      expect(await sichtbar(), {'t1', 't2', 't3', 'u1', 'u2', 'x1'});
    });

    test('was vorher schon gelöscht war, kommt nicht mit zurück', () async {
      final frueher = DateTime(2026, 9, 1, 8);
      await auftrag('t1');
      await auftrag('t2', eltern: 't1', geloescht: frueher);
      await auftrag('t3', eltern: 't1');

      // Auch wenn jemand die alte ID mitgibt: Gelöscht wird nur, was da
      // ist — und nur das meldet die Funktion zurück.
      final weg = await LoeschenMitRueckweg.auftraege(db, ['t1', 't2', 't3']);
      expect(weg.toSet(), {'t1', 't3'});
      expect((await lade('t2')).deletedAt, frueher);

      await LoeschenMitRueckweg.auftraegeZurueck(db, weg);
      expect(await sichtbar(), {'t1', 't3'});
      expect((await lade('t2')).deletedAt, frueher);
    });

    test('nichts zu löschen: leere Liste, nichts angefasst', () async {
      await auftrag('t1');
      final vorher = await lade('t1');

      expect(await LoeschenMitRueckweg.auftraege(db, const []), isEmpty);
      expect(await LoeschenMitRueckweg.auftraege(db, ['fehlt']), isEmpty);
      await LoeschenMitRueckweg.auftraegeZurueck(db, const []);
      expect(await lade('t1'), vorher);
    });

    test('Auftragszeilen: nach dem Löschen offen, nach Rückgängig geplant',
        () async {
      await planeAuftragszeilen(
        db: db,
        productId: 'p1',
        fertigKg: 250,
        tag: DateTime(2026, 10, 2),
        bezuege: [bezug],
      );
      Future<List<ProduktionsZugang>> zugaenge() async {
        final z = await ladeProduktionsZugaenge(
          db,
          heute: DateTime(2026, 9, 30),
          berichtTag: DateTime(2026, 9, 30),
        );
        return z['70001'] ?? const [];
      }

      expect(await zugaenge(), hasLength(1));
      final wurzel = (await db.select(db.productionTasks).get())
          .singleWhere((t) => t.parentTaskId == null);

      final weg = await LoeschenMitRueckweg.auftraege(
        db,
        await LoeschenMitRueckweg.kette(db, wurzel),
      );
      expect(weg, hasLength(2));
      expect(await zugaenge(), isEmpty);

      await LoeschenMitRueckweg.auftraegeZurueck(db, weg);
      final z = await zugaenge();
      expect(z, hasLength(1));
      // Die Zuordnung zu den Auftragszeilen hängt wieder an der Wurzel.
      expect(
        AuftragsBezug.dekodiere((await lade(wurzel.id)).auftragsZeilen)
            .single
            .beleg,
        'VA1',
      );
    });
  });

  group('Erfasste Produktion', () {
    Future<void> erfassung(String id) => db.into(db.productionHistory).insert(
          ProductionHistoryCompanion.insert(
            id: id,
            productId: 'p1',
            datum: DateTime(2026, 10, 1),
            kgRohware: const Value(1000),
            kgFertigware: const Value(800),
            verlustAnteil: const Value(0.2),
          ),
        );

    Future<ProductionHistoryData> ladeErfassung(String id) =>
        (db.select(db.productionHistory)..where((h) => h.id.equals(id)))
            .getSingle();

    test('löschen und zurückholen', () async {
      await erfassung('h1');
      await erfassung('h2');
      final vorher = await ladeErfassung('h1');

      expect(await LoeschenMitRueckweg.produktion(db, 'h1'), isTrue);
      expect((await ladeErfassung('h1')).deletedAt, isNotNull);
      expect((await ladeErfassung('h2')).deletedAt, isNull);

      await LoeschenMitRueckweg.produktionZurueck(db, 'h1');
      final nachher = await ladeErfassung('h1');
      expect(nachher.copyWith(updatedAt: vorher.updatedAt), vorher);
    });

    test('schon gelöscht oder unbekannt: nichts zu tun', () async {
      await erfassung('h1');
      final frueher = DateTime(2026, 9, 1, 8);
      await LoeschenMitRueckweg.produktion(db, 'h1', jetzt: frueher);

      expect(await LoeschenMitRueckweg.produktion(db, 'h1'), isFalse);
      expect(await LoeschenMitRueckweg.produktion(db, 'fehlt'), isFalse);
      expect((await ladeErfassung('h1')).deletedAt, frueher);
    });
  });
}
