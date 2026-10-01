// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/auftragsbestand_deckung.dart';
import 'package:produktion_planer/core/services/auftragsbestand_import_service.dart';
import 'package:produktion_planer/core/services/auftragsbestand_vergleich.dart';
import 'package:produktion_planer/features/auftragsbestand/auftrags_einplanung.dart';
import 'package:produktion_planer/features/auftragsbestand/planung_pruefen.dart';

import 'helpers/test_db.dart';

/// Tests für „Planung prüfen": Planungsaufträge und Produktionen, die an
/// Auftragszeilen hängen, die sich im Auftragsbestand geändert haben.
///
/// Mit erfundenen Aufträgen — ein echter Bericht gehört nicht ins
/// Repository.
void main() {
  // Heute ist Donnerstag, der 01.10.2026 — derselbe Tag wie der Bericht.
  final heute = DateTime(2026, 10, 1);
  final vorherStand = DateTime(2026, 9, 30, 6);
  final jetztStand = DateTime(2026, 10, 1, 6);
  final freitag2 = DateTime(2026, 10, 2);
  final montag = DateTime(2026, 10, 5);
  final dienstag = DateTime(2026, 10, 6);
  final mittwoch = DateTime(2026, 10, 7);
  final freitag = DateTime(2026, 10, 9);

  AuftragsBezug bezug(String beleg, DateTime tag, double kg) => AuftragsBezug(
        beleg: beleg,
        warenausgang: tag,
        kg: kg,
        debitor: 'Kunde A',
      );

  group('ermittleKonflikte', () {
    BestandsZeile zeile(String beleg, DateTime tag, double kg) =>
        BestandsZeile(
          artikelnummer: '12981',
          beleg: beleg,
          warenausgang: tag,
          kg: kg,
          debitor: 'Kunde A',
        );

    BestandsStand stand(
      DateTime erstellt,
      List<BestandsZeile> zeilen, {
      DateTime? von,
    }) =>
        BestandsStand(
          stand: erstellt,
          von: von ?? DateTime(2026, 9, 28),
          bis: DateTime(2026, 10, 31),
          importiertAm: erstellt,
          artikel: const {
            '12981': BestandsArtikel(
              nummer: '12981',
              bezeichnung: 'Testartikel',
            ),
          },
          zeilen: zeilen,
        );

    Map<String, List<Vormerkung>> vorgemerkt(
      List<AuftragsBezug> bezuege, {
      List<AuftragsBezug> zweiter = const [],
    }) =>
        {
          '12981': [
            Vormerkung(
              bedarfId: 'b1',
              offenKg: bezuege.fold<double>(0, (s, b) => s + b.kg),
              termin: freitag2,
              bezuege: bezuege,
            ),
            if (zweiter.isNotEmpty)
              Vormerkung(
                bedarfId: 'b2',
                offenKg: zweiter.fold<double>(0, (s, b) => s + b.kg),
                termin: freitag2,
                bezuege: zweiter,
              ),
          ],
        };

    Map<String, List<ProduktionsZugang>> produziert(
      List<AuftragsBezug> bezuege, {
      DateTime? fertig,
      ZugangsArt art = ZugangsArt.eingeplant,
    }) =>
        {
          '12981': [
            ProduktionsZugang(
              kettenId: 'k1',
              productId: 'p1',
              fertigAm: fertig ?? freitag2,
              art: art,
              kg: 100,
              bezuege: bezuege,
            ),
          ],
        };

    test('passt alles, gibt es nichts zu prüfen', () {
      final k = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA1', montag, 100)]),
        vormerkungen: vorgemerkt([bezug('VA1', montag, 60)]),
        zugaenge: produziert([bezug('VA1', montag, 40)]),
      );

      expect(k, isEmpty);
    });

    test('Vormerkung und Produktion zählen zusammen', () {
      // 100 kg vorgemerkt und 100 kg im Board für eine Zeile über 100 kg.
      final k = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA1', montag, 100)]),
        vormerkungen: vorgemerkt([bezug('VA1', montag, 100)]),
        zugaenge: produziert([bezug('VA1', montag, 100)]),
      ).single;

      expect(k.art, PruefArt.weniger);
      expect(k.geplantKg, 200);
      expect(k.zuVielKg, 100);
      expect(k.mitVormerkung, isTrue);
      expect(k.mitProduktion, isTrue);
    });

    test('weniger bestellt', () {
      final k = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA1', montag, 60)]),
        vormerkungen: vorgemerkt([bezug('VA1', montag, 100)]),
      ).single;

      expect(k.art, PruefArt.weniger);
      expect(k.imBerichtKg, 60);
      expect(k.geplantKg, 100);
      expect(k.zuVielKg, 40);
      expect(k.mitVormerkung, isTrue);
      expect(k.mitProduktion, isFalse);
      expect(k.sicher, isTrue);
      expect(k.bezeichnung, 'Testartikel');
    });

    test('verschoben — eindeutig dank des vorigen Berichts', () {
      final k = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA1', freitag, 100)]),
        vorher: stand(vorherStand, [zeile('VA1', montag, 100)]),
        vormerkungen: vorgemerkt([bezug('VA1', montag, 100)]),
      ).single;

      expect(k.art, PruefArt.verschoben);
      expect(k.warenausgang, montag);
      expect(k.neuerWarenausgang, freitag);
      expect(k.imBerichtKg, 100);
      expect(k.zuVielKg, 0);
      expect(k.sicher, isTrue);
    });

    test('verschoben ohne vorigen Bericht ist nicht eindeutig', () {
      final k = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA1', freitag, 100)]),
        vormerkungen: vorgemerkt([bezug('VA1', montag, 100)]),
      ).single;

      expect(k.art, PruefArt.verschoben);
      expect(k.sicher, isFalse);
    });

    test('hängt am neuen Tag schon Planung, ist nichts verschoben', () {
      final k = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA1', freitag, 100)]),
        vorher: stand(vorherStand, [zeile('VA1', montag, 100)]),
        vormerkungen: vorgemerkt(
          [bezug('VA1', montag, 100)],
          zweiter: [bezug('VA1', freitag, 100)],
        ),
      ).single;

      expect(k.art, PruefArt.entfallen);
      expect(k.warenausgang, montag);
    });

    test('entfallen: fehlt, obwohl der Versandtag noch kommt', () {
      final k = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA2', dienstag, 50)]),
        vorher: stand(
          vorherStand,
          [zeile('VA1', montag, 100), zeile('VA2', dienstag, 50)],
        ),
        vormerkungen: vorgemerkt(
          [bezug('VA1', montag, 100), bezug('VA2', dienstag, 50)],
        ),
      ).single;

      expect(k.art, PruefArt.entfallen);
      expect(k.beleg, 'VA1');
      expect(k.zuVielKg, 100);
      expect(k.sicher, isTrue);
    });

    test('ausgeliefert: fehlt, und der Versandtag ist vorbei', () {
      final k = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA2', dienstag, 50)]),
        vormerkungen: vorgemerkt([bezug('VA1', DateTime(2026, 9, 30), 20)]),
      ).single;

      expect(k.art, PruefArt.ausgeliefert);
      expect(k.sicher, isTrue);
      expect(k.vorZeitraum, isFalse);
    });

    test('vor dem Zeitraum: vermutlich ausgeliefert, nicht eindeutig', () {
      final k = ermittleKonflikte(
        bestand: stand(
          jetztStand,
          [zeile('VA2', dienstag, 50)],
          von: DateTime(2026, 9, 29),
        ),
        vormerkungen: vorgemerkt([bezug('VA1', DateTime(2026, 9, 28), 20)]),
      ).single;

      expect(k.art, PruefArt.ausgeliefert);
      expect(k.vorZeitraum, isTrue);
      expect(k.sicher, isFalse);
    });

    test('nach dem Zeitraum: Der Bericht sagt nichts, kein Konflikt', () {
      final k = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA2', dienstag, 50)]),
        vormerkungen: vorgemerkt([bezug('VA1', DateTime(2026, 11, 5), 20)]),
      );

      expect(k, isEmpty);
    });

    test('Produktionen, die schon im Lager stecken, zählen nicht', () {
      final k = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA2', dienstag, 50)]),
        zugaenge: produziert(
          [bezug('VA1', montag, 100)],
          art: ZugangsArt.imLager,
        ),
      );

      expect(k, isEmpty);
    });

    test('verschoben: gerechnet am neuen Tag, gebündelt wird nicht', () {
      final vormerkungen = vorgemerkt([bezug('VA1', montag, 100)]);
      final konflikte = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA1', freitag, 100)]),
        vorher: stand(vorherStand, [zeile('VA1', montag, 100)]),
        vormerkungen: vormerkungen,
      );

      final gerechnet = wieUmgehaengt(
        vormerkungen: vormerkungen,
        zugaenge: const {},
        konflikte: konflikte,
      );
      final v = gerechnet.vormerkungen['12981']!.single;
      expect(v.bezuege.single.warenausgang, freitag);
      expect(v.bedarfId, 'b1');
      // Das Original bleibt, wie es ist.
      expect(vormerkungen['12981']!.single.bezuege.single.warenausgang, montag);

      final ziele = verschobeneZiele(konflikte)['12981']!;
      expect(ziele.keys, [auftragsZeilenSchluessel('VA1', freitag)]);

      final d = berechneDeckung(
        lagerKg: 0,
        positionen: [
          AuftragsPosition(
            id: 1,
            artikelnummer: '12981',
            beleg: 'VA1',
            debitor: 'Kunde A',
            warenausgang: freitag,
            menge: 120,
            kg: 120,
          ),
        ],
        vormerkungen: gerechnet.vormerkungen['12981']!,
        gesperrt: ziele.keys.toSet(),
      );
      final z = d.tage.single.zeilen.single;
      // 100 kg hängen am alten Tag und zählen hier als vorgemerkt; die
      // 20 kg mehr fehlen — bündeln lässt sich aber nichts, bis die
      // Verschiebung geklärt ist.
      expect(z.vorgemerktKg, 100);
      expect(z.offenKg, 20);
      expect(z.gesperrt, isTrue);
      expect(d.tage.single.einplanbar, isFalse);
      expect(bezuegeFuerTage(d, {freitag}), isEmpty);
    });

    test('ohne Verschiebung bleibt alles, wie es ist', () {
      final vormerkungen = vorgemerkt([bezug('VA1', montag, 100)]);
      final gerechnet = wieUmgehaengt(
        vormerkungen: vormerkungen,
        zugaenge: const {},
        konflikte: const [],
      );

      expect(identical(gerechnet.vormerkungen, vormerkungen), isTrue);
      expect(verschobeneZiele(const []), isEmpty);
    });

    test('nach vorn verschoben: Die Produktion wird zu spät fertig', () {
      final k = ermittleKonflikte(
        bestand: stand(jetztStand, [zeile('VA1', montag, 100)]),
        vorher: stand(vorherStand, [zeile('VA1', freitag, 100)]),
        zugaenge: produziert([bezug('VA1', freitag, 100)], fertig: mittwoch),
      ).single;

      expect(k.art, PruefArt.verschoben);
      expect(k.neuerWarenausgang, montag);
      expect(k.mitProduktion, isTrue);
      expect(k.produktionZuSpaet, isTrue);
    });
  });

  group('Anpassen', () {
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

    AuftragsbestandBericht bericht(
      DateTime erstellt,
      List<(String, DateTime, double)> zeilen,
    ) {
      final artikel = BerichtArtikel('12981')..bezeichnung = 'Testartikel';
      for (final (beleg, tag, kg) in zeilen) {
        artikel.positionen.add(
          BerichtPosition(
            beleg: beleg,
            debitor: 'Kunde A',
            warenausgang: tag,
            menge: kg,
            kg: kg,
          ),
        );
      }
      return AuftragsbestandBericht(
        artikel: [artikel],
        uebersprungen: const [],
        warnungen: const [],
        stand: erstellt,
        von: DateTime(2026, 9, 28),
        bis: DateTime(2026, 10, 31),
      );
    }

    /// Liest zwei Berichte nacheinander ein: [vorher], dann [jetzt].
    Future<void> einlesen(
      List<(String, DateTime, double)> vorher,
      List<(String, DateTime, double)> jetzt,
    ) async {
      final service = AuftragsbestandImportService(db);
      await service.speichere(bericht(vorherStand, vorher));
      await service.speichere(bericht(jetztStand, jetzt));
    }

    Future<String> planungsauftrag(
      List<AuftragsBezug> bezuege, {
      double? kg,
    }) =>
        uebergebeAnPlanungsvorschlag(
          db: db,
          productId: 'p1',
          fertigKg: kg ?? bezuege.fold<double>(0, (s, b) => s + b.kg),
          termin: freitag2,
          bezuege: bezuege,
        );

    Future<Demand> bedarf(String id) =>
        (db.select(db.demands)..where((d) => d.id.equals(id))).getSingle();

    test('verschoben: Der Planungsauftrag hängt am neuen Tag', () async {
      await einlesen([('VA1', montag, 100)], [('VA1', freitag, 100)]);
      final id = await planungsauftrag([bezug('VA1', montag, 100)]);

      final konflikte = await pruefePlanung(db, heute: heute);
      expect(konflikte.single.art, PruefArt.verschoben);
      expect(konflikte.single.sicher, isTrue);
      expect(await passeAn(db, konflikte, heute: heute), 1);

      final d = await bedarf(id);
      final zeilen = AuftragsBezug.dekodiere(d.auftragsZeilen);
      expect(zeilen.single.warenausgang, freitag);
      expect(zeilen.single.kg, 100);
      expect(d.mengeKgFertig, 100);
      // Später versandt: Der Termin bleibt — zu früh fertig schadet nicht.
      expect(d.termin, freitag2);
      expect(d.notizen, contains('Fr 09.10.'));
      expect(await pruefePlanung(db, heute: heute), isEmpty);
    });

    test('nicht verschoben: Die alte Zeile verlässt die Planung', () async {
      await einlesen([('VA1', montag, 100)], [('VA1', freitag, 100)]);
      final id = await planungsauftrag([bezug('VA1', montag, 100)]);

      final k = (await pruefePlanung(db, heute: heute)).single;
      expect(k.art, PruefArt.verschoben);
      expect(await passeAn(db, [k.alsEntfallen], heute: heute), 1);

      // Der Planungsauftrag trug nur diese Zeile — er ist weg, und der
      // Auftrag am neuen Tag ist frei zum Bündeln.
      expect((await bedarf(id)).deletedAt, isNotNull);
      expect(await pruefePlanung(db, heute: heute), isEmpty);
    });

    test('auf früher verschoben: Der Termin rückt vor', () async {
      await einlesen([('VA1', montag, 100)], [('VA1', freitag2, 100)]);
      final id = await planungsauftrag([bezug('VA1', montag, 100)]);

      await passeAn(db, await pruefePlanung(db, heute: heute), heute: heute);

      // Versand Fr 02.10. → spätestens Do 01.10. produzieren.
      expect((await bedarf(id)).termin, DateTime(2026, 10, 1));
    });

    test('weniger bestellt: Der Planungsauftrag wird kleiner', () async {
      await einlesen([('VA1', montag, 100)], [('VA1', montag, 60)]);
      final id = await planungsauftrag([bezug('VA1', montag, 100)]);

      final konflikte = await pruefePlanung(db, heute: heute);
      expect(konflikte.single.art, PruefArt.weniger);
      expect(konflikte.single.zuVielKg, 40);
      await passeAn(db, konflikte, heute: heute);

      final d = await bedarf(id);
      expect(d.mengeKgFertig, 60);
      expect(AuftragsBezug.dekodiere(d.auftragsZeilen).single.kg, 60);
      expect(d.deletedAt, isNull);
      expect(await pruefePlanung(db, heute: heute), isEmpty);
    });

    test('entfallen: Die Zeile verlässt den Planungsauftrag', () async {
      await einlesen(
        [('VA1', montag, 100), ('VA2', dienstag, 50)],
        [('VA2', dienstag, 50)],
      );
      final id = await planungsauftrag(
        [bezug('VA1', montag, 100), bezug('VA2', dienstag, 50)],
      );

      final konflikte = await pruefePlanung(db, heute: heute);
      expect(konflikte.single.art, PruefArt.entfallen);
      await passeAn(db, konflikte, heute: heute);

      final d = await bedarf(id);
      expect(d.mengeKgFertig, 50);
      expect(
        AuftragsBezug.dekodiere(d.auftragsZeilen).map((b) => b.beleg),
        ['VA2'],
      );
      expect(d.deletedAt, isNull);
      expect(await pruefePlanung(db, heute: heute), isEmpty);
    });

    test('entfällt die letzte Zeile, wird der Planungsauftrag gelöscht',
        () async {
      await einlesen(
        [('VA1', montag, 100), ('VA2', dienstag, 50)],
        [('VA2', dienstag, 50)],
      );
      final id = await planungsauftrag([bezug('VA1', montag, 100)]);

      await passeAn(db, await pruefePlanung(db, heute: heute), heute: heute);

      expect((await bedarf(id)).deletedAt, isNotNull);
      expect(await ladeVormerkungen(db), isEmpty);
    });

    test('eine Produktion verliert nur die Zuordnung', () async {
      await einlesen(
        [('VA1', montag, 100), ('VA2', dienstag, 50)],
        [('VA2', dienstag, 50)],
      );
      final e = await planeAuftragszeilen(
        db: db,
        productId: 'p1',
        fertigKg: 100,
        tag: freitag2,
        bezuege: [bezug('VA1', montag, 100)],
      );

      final konflikte = await pruefePlanung(db, heute: heute);
      expect(konflikte.single.art, PruefArt.entfallen);
      expect(konflikte.single.mitProduktion, isTrue);
      expect(konflikte.single.mitVormerkung, isFalse);
      await passeAn(db, konflikte, heute: heute);

      final wurzel = await (db.select(db.productionTasks)
            ..where((t) => t.id.equals(e.wurzelId!)))
          .getSingle();
      expect(wurzel.auftragsZeilen, isNull);
      expect(wurzel.fertigMengeKg, 100, reason: 'Menge bleibt im Board');
      expect(wurzel.deletedAt, isNull);
      expect(await pruefePlanung(db, heute: heute), isEmpty);
    });

    test('weniger: erst der offene Rest, dann die Zuordnung der Produktion',
        () async {
      await einlesen([('VA1', montag, 100)], [('VA1', montag, 50)]);
      final id = await planungsauftrag([bezug('VA1', montag, 100)]);
      // 60 kg davon stehen schon im Board, 40 kg sind noch vorgemerkt.
      await db.into(db.productionTasks).insert(
            ProductionTasksCompanion.insert(
              id: 'k1',
              productId: 'p1',
              mengeKg: 60,
              datum: freitag2,
              abteilung: 'bratstrasse',
              geplanteDauerMinuten: 60,
              geplanteMitarbeiter: 2,
              bedarfId: Value(id),
              fertigMengeKg: const Value(60),
              auftragsZeilen: Value(
                AuftragsBezug.kodiere([bezug('VA1', montag, 60)]),
              ),
            ),
          );

      final konflikte = await pruefePlanung(db, heute: heute);
      expect(konflikte.single.art, PruefArt.weniger);
      expect(konflikte.single.geplantKg, 100);
      expect(konflikte.single.zuVielKg, 50);
      await passeAn(db, konflikte, heute: heute);

      final d = await bedarf(id);
      expect(d.mengeKgFertig, 60, reason: 'nur noch, was im Board steht');
      expect(AuftragsBezug.dekodiere(d.auftragsZeilen).single.kg, 50);
      final kette = await (db.select(db.productionTasks)
            ..where((t) => t.id.equals('k1')))
          .getSingle();
      expect(AuftragsBezug.dekodiere(kette.auftragsZeilen).single.kg, 50);
      expect(kette.fertigMengeKg, 60, reason: 'die Produktion selbst bleibt');
      expect(await pruefePlanung(db, heute: heute), isEmpty);
    });

    test('mehrere Vorschläge auf einmal', () async {
      await einlesen(
        [('VA1', montag, 100), ('VA2', dienstag, 50)],
        [('VA1', freitag, 100), ('VA2', dienstag, 30)],
      );
      final id = await planungsauftrag(
        [bezug('VA1', montag, 100), bezug('VA2', dienstag, 50)],
      );

      final konflikte = await pruefePlanung(db, heute: heute);
      expect(
        konflikte.map((k) => k.art),
        unorderedEquals([PruefArt.verschoben, PruefArt.weniger]),
      );
      expect(await passeAn(db, konflikte, heute: heute), 2);

      expect((await bedarf(id)).mengeKgFertig, 130);
      expect(await pruefePlanung(db, heute: heute), isEmpty);
      // Schon angepasst: Ein zweites Mal ändert nichts.
      expect(await passeAn(db, konflikte, heute: heute), 0);
      expect((await bedarf(id)).mengeKgFertig, 130);
    });
  });
}
