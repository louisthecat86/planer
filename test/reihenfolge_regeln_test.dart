import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/providers/database_provider.dart';
import 'package:produktion_planer/core/services/reihenfolge_regeln.dart';
import 'package:produktion_planer/features/board/board_providers.dart';
import 'package:produktion_planer/features/planung/planungsvorschlag_service.dart';

import 'helpers/test_db.dart';

/// (Name, Allergen, Bio, Roh, Temperatur)
typedef A = (String, int, int, int, double);

/// Tests für die Reihenfolge nach den Regeln des Betriebs, den Nachlauf
/// des letzten Artikels und den Reinigungsbeginn. Alle Daten erfunden.
void main() {
  group('Ordnen', () {
    ArtikelRegel regel(A a) => ArtikelRegel(
          allergenRang: a.$2,
          bioRang: a.$3,
          rohRang: a.$4,
          plattenTemp: a.$5,
        );
    List<String> ordne(List<A> liste) =>
        [for (final a in ordneNachRegeln(liste, regel, (a) => a.$1)) a.$1];

    test('Allergene vor Bio vor roh', () {
      expect(
        ordne([
          ('roh', 0, 1, 1, 0),
          ('allergen', 3, 0, 0, 0),
          ('konv', 0, 1, 0, 0),
          ('bio', 0, 0, 0, 0),
        ]),
        ['bio', 'konv', 'roh', 'allergen'],
      );
    });

    test('Temperatur ohne Zickzack über die Blöcke', () {
      expect(
        ordne([
          ('a200', 0, 1, 0, 200),
          ('a180', 0, 1, 0, 180),
          ('a220', 0, 1, 0, 220),
          // Nächster Block: beginnt dort, wo der erste aufhört — oben.
          ('b170', 2, 1, 0, 170),
          ('b230', 2, 1, 0, 230),
          ('b210', 2, 1, 0, 210),
          // Ohne Temperatur ans Ende seines Blocks.
          ('b-ohne', 2, 1, 0, 0),
          // Dritter Block: wieder von unten.
          ('c240', 5, 1, 0, 240),
          ('c160', 5, 1, 0, 160),
        ]),
        [
          'a180',
          'a200',
          'a220',
          'b230',
          'b210',
          'b170',
          'b-ohne',
          'c160',
          'c240',
        ],
      );
    });

    test('der Planungsvorschlag ordnet genauso', () {
      VorschlagPosten p(String nr, double temp) => VorschlagPosten(
            bedarfId: nr,
            productId: nr,
            artikelnummer: nr,
            bezeichnung: nr,
            mengeKg: 100,
            rohwareKg: 100,
            dauerMinuten: 60,
            nebenzeitMinuten: 0,
            wechselGrund: WechselGrund.tagesstart,
            ausHistorie: true,
            allergenRang: nr.startsWith('b') ? 2 : 0,
            bioRang: 1,
            rohRang: 0,
            plattenTemp: temp,
            hoehe: 0,
            begruendung: '',
            ausgangsMengeKg: 100,
          );
      final geordnet = Planungsrechner.nachRegeln([
        p('b170', 170),
        p('a220', 220),
        p('a180', 180),
        p('b230', 230),
      ]);
      expect(
        [for (final x in geordnet) x.artikelnummer],
        ['a180', 'a220', 'b230', 'b170'],
      );
    });
  });

  group('Hinweise zur Reihenfolge', () {
    test('Regelbruch, Temperatur hin und her, ungeprüft', () {
      final h = regelHinweise<ArtikelRegel>(
        const [
          ArtikelRegel(allergenRang: 2, plattenTemp: 180),
          ArtikelRegel(allergenRang: 2, plattenTemp: 220),
          ArtikelRegel(allergenRang: 2, plattenTemp: 190),
          // Weniger Allergene als davor.
          ArtikelRegel(plattenTemp: 200),
          ArtikelRegel(allergeneGepflegt: false),
          // Gegart nach roh.
          ArtikelRegel(rohRang: 1),
          ArtikelRegel(),
        ],
        (r) => r,
      );
      expect(h[0], isNull);
      expect(h[1], isNull);
      expect(h[2]!.art, RegelArt.temperatur);
      expect(h[2]!.text, 'Temperatur fällt wieder (220 → 190 °C)');
      expect(h[3]!.art, RegelArt.reinigung);
      expect(h[3]!.text, contains('weniger Allergene'));
      expect(h[4]!.art, RegelArt.ungeprueft);
      expect(h[5], isNull);
      expect(h[6]!.art, RegelArt.reinigung);
      expect(h[6]!.text, contains('gegart nach roh'));
    });

    test('nach Regeln geordnet: keine Hinweise', () {
      const liste = [
        ArtikelRegel(bioRang: 0, plattenTemp: 230),
        ArtikelRegel(plattenTemp: 180),
        ArtikelRegel(allergenRang: 1, plattenTemp: 200),
        ArtikelRegel(allergenRang: 1, plattenTemp: 170),
        ArtikelRegel(allergenRang: 3, rohRang: 1),
      ];
      final geordnet = ordneNachRegeln(liste, (r) => r, (r) => '');
      expect(
        regelHinweise(geordnet, (r) => r).every((h) => h == null),
        isTrue,
      );
    });
  });

  group('Reinigungsbeginn', () {
    test('Vorgabe als Text', () {
      expect(kBratstrasseVorgabe.alsText, '06:15;15:00;15:30');
      final v = ReinigungsVorgabe.ausText('6:30;14:45;15:15')!;
      expect((v.arbeitsbeginn, v.ziel, v.spaetestens), (390, 885, 915));
      expect(ReinigungsVorgabe.ausText('15:00;14:00;15:30'), isNull);
      expect(ReinigungsVorgabe.ausText('06:15;15:40;15:30'), isNull);
      expect(ReinigungsVorgabe.ausText(''), isNull);
    });

    test('gut, knapp, zu spät', () {
      ReinigungsPlan plan(double belegt, double? nachlauf, {String? start}) =>
          reinigungsPlan(
            vorgabe: kBratstrasseVorgabe,
            belegtOhneNachlauf: belegt,
            hatAuftraege: true,
            nachlaufLetzter: nachlauf,
            startZeit: start,
          )!;
      // 6:15 + 7:45 = 14:00, plus 40 min Nachlauf.
      final gut = plan(465, 40);
      expect(uhrzeit(gut.produktionsEnde), '14:00');
      expect(uhrzeit(gut.reinigungAb), '14:40');
      expect(gut.stand, ReinigungsStand.gut);
      expect(plan(465, 70).stand, ReinigungsStand.knapp);
      final spaet = plan(465, 110);
      expect(spaet.stand, ReinigungsStand.zuSpaet);
      expect(spaet.ueberzogen, 20);
      // Mit Startzeit des ersten Auftrags.
      expect(uhrzeit(plan(465, 0, start: '07:00').reinigungAb), '14:45');
      expect(plan(465, null).nachlaufBekannt, isFalse);
      expect(
        reinigungsPlan(
          vorgabe: kBratstrasseVorgabe,
          belegtOhneNachlauf: 0,
          hatAuftraege: false,
          nachlaufLetzter: null,
        ),
        isNull,
      );
    });

    test('Vorgaben speichern und laden — die Bratstraße hat immer eine',
        () async {
      final db = testDatenbank();
      addTearDown(db.close);
      var v = await ladeReinigungsVorgaben(db);
      expect(v.keys, [Abteilung.bratstrasse]);
      await speichereReinigungsVorgabe(
        db,
        Abteilung.wurstkueche,
        ReinigungsVorgabe.ausText('06:00;14:00;14:30'),
      );
      await speichereReinigungsVorgabe(db, Abteilung.bratstrasse, null);
      v = await ladeReinigungsVorgaben(db);
      expect(v.keys, [Abteilung.wurstkueche]);
      expect(v[Abteilung.wurstkueche]!.ziel, 14 * 60);
    });
  });

  group('Nachlauf aus der Datenbank', () {
    late AppDatabase db;
    final montag = DateTime(2026, 10, 5);

    setUp(() async {
      db = testDatenbank();
      await seedArtikel(db, id: 'p1', nummer: '8001');
      await seedArtikel(db, id: 'p2', nummer: '8002');
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p1',
        reihenfolge: 1,
        abteilung: 'bratstrasse',
      );
      await db.into(db.productStepParameters).insert(
            ProductStepParametersCompanion.insert(
              id: 'x1',
              stepId: 's1',
              parameterGruppe: 'Platten',
              parameterName: 'Platte 1 oben',
              wert: const Value('210 °C'),
            ),
          );
      // Drei Erfassungen von p1: Nachlauf 30, 50, 40 — Median 40.
      var i = 0;
      for (final (ende, vpk) in [
        ('13:00', '13:30'),
        ('12:00', '12:50'),
        ('14:00', '14:40'),
      ]) {
        await db.into(db.productionHistory).insert(
              ProductionHistoryCompanion.insert(
                id: 'h${i++}',
                productId: 'p1',
                datum: DateTime(2026, 9, 1 + i),
                endzeit: Value(ende),
                endeVpk: Value(vpk),
              ),
            );
      }
    });
    tearDown(() => db.close());

    test('in den Regeln der Artikel', () async {
      final regeln = await ladeArtikelRegeln(db);
      expect(regeln['p1']!.nachlaufMinuten, 40);
      expect(regeln['p1']!.nachlaufWerte, 3);
      expect(regeln['p1']!.plattenTemp, 210);
      expect(regeln['p2']!.nachlaufMinuten, isNull);
    });

    test('der letzte Artikel an der Bratstraße belegt seinen Nachlauf mit',
        () async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      Future<void> auftrag(String id, String productId, int sortierung) =>
          db.into(db.productionTasks).insert(
                ProductionTasksCompanion.insert(
                  id: id,
                  productId: productId,
                  mengeKg: 100,
                  datum: montag,
                  abteilung: 'bratstrasse',
                  geplanteDauerMinuten: 120,
                  geplanteMitarbeiter: 2,
                  sortierung: Value(sortierung),
                ),
              );
      await auftrag('t1', 'p2', 0);
      await auftrag('t2', 'p1', 1);

      final abo = container.listen(weekBoardProvider(montag), (_, __) {});
      addTearDown(abo.close);
      final board = await container.read(weekBoardProvider(montag).future);
      final zelle = board.cells.values.where((c) => c.tasks.isNotEmpty).single;
      expect(zelle.nachlaufLetzter, 40);
      expect(zelle.belegtOhneNachlauf, 240);
      expect(zelle.belegtMinuten, 280);

      // Dieselbe Belegung in der Statistik.
      final belegung = await belegungImZeitraum(
        db,
        von: montag,
        bisExkl: montag.add(const Duration(days: 7)),
      );
      final b = belegung.where((b) => b.produktionsMinuten > 0).single;
      expect(b.nachlaufMinuten, 40);
      expect(b.belegtMinuten, 280);

      // Steht p2 zuletzt, kennt das Board keinen Nachlauf.
      await (db.update(db.productionTasks)..where((t) => t.id.equals('t2')))
          .write(const ProductionTasksCompanion(sortierung: Value(-1)));
      container.invalidate(weekBoardProvider(montag));
      final neu = await container.read(weekBoardProvider(montag).future);
      final z2 = neu.cells.values.where((c) => c.tasks.isNotEmpty).single;
      expect(z2.tasks.last.productId, 'p2');
      expect(z2.nachlaufLetzter, isNull);
      expect(z2.belegtMinuten, 240);
    });
  });
}
