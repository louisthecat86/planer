// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/artikel_anlage_service.dart';
import 'package:produktion_planer/core/services/auftragsbestand_deckung.dart';

import 'helpers/test_db.dart';

/// Tests für die Deckung im Auftragsbestand: Lager, dann die Produktionen
/// der App, und was danach noch einzuplanen ist.
///
/// Hier entscheidet sich, ob doppelt oder zu wenig produziert wird. Zählt
/// eine Produktion zu Unrecht, fehlt am Versandtag Ware. Zählt sie zu
/// Unrecht NICHT, plant jemand dieselbe Menge ein zweites Mal ein.
void main() {
  group('Deckung mit Produktion', () {
    test('eine rechtzeitige Produktion deckt, was das Lager nicht schafft',
        () {
      // Lager 5 kg. 30.09.: 1 kg, 02.10.: 7 kg. Am 01.10. werden 3 kg
      // fertig — damit reicht es auch am 02.10.
      final d = berechneDeckung(
        lagerKg: 5,
        positionen: [_pos(1, _tag(30), 1), _pos(2, _tag(32), 7)],
        zugaenge: [_zugang(_tag(31), 3)],
      );

      expect(d.tage[1].ausLagerKg, 4);
      expect(d.tage[1].ausPlanungKg, 3);
      expect(d.tage[1].fehltKg, 0);
      expect(d.gedeckt, isTrue);
      expect(d.lagerReicht, isFalse);
      expect(d.ersterEngpass, isNull);
    });

    test('fertig am Versandtag zählt, gilt aber als knapp', () {
      final d = berechneDeckung(
        lagerKg: 0,
        positionen: [_pos(1, _tag(32), 10)],
        zugaenge: [_zugang(_tag(32), 10)],
      );

      expect(d.tage.single.ausPlanungKg, 10);
      expect(d.tage.single.knappKg, 10);
      expect(d.gedeckt, isTrue);
    });

    test('eine zu späte Produktion deckt die Menge, nicht den Tag', () {
      final d = berechneDeckung(
        lagerKg: 0,
        positionen: [_pos(1, _tag(35), 100)],
        zugaenge: [_zugang(_tag(36), 100)],
      );

      final t = d.tage.single;
      expect(t.ausPlanungKg, 0);
      expect(t.zuSpaetKg, 100);
      expect(t.zuSpaetBis, _tag(36));
      expect(t.fehltKg, 0);
      expect(d.gedeckt, isFalse);
      expect(d.ersterFehltag, isNull);
      expect(d.ersterZuSpaet, _tag(35));
    });

    test('was fehlt, bleibt beim frühesten Auftrag — das ist der Termin', () {
      // Mo und Di je 100 kg, eingeplant sind nur 100 kg für Mi. Die
      // Mi-Ware kann den Di-Auftrag (zu spät) bedienen; für Mo muss neu
      // eingeplant werden, und zwar bis Mo.
      final d = berechneDeckung(
        lagerKg: 0,
        positionen: [_pos(1, _tag(35), 100), _pos(2, _tag(36), 100)],
        zugaenge: [_zugang(_tag(37), 100)],
      );

      expect(d.tage[0].fehltKg, 100);
      expect(d.tage[0].zuSpaetKg, 0);
      expect(d.tage[1].zuSpaetKg, 100);
      expect(d.fehltKg, 100);
      expect(d.ersterFehltag, _tag(35));
      expect(d.ersterEngpass, _tag(35));
    });

    test('der frühere Auftrag bekommt die frühere Ware', () {
      final d = berechneDeckung(
        lagerKg: 0,
        positionen: [_pos(1, _tag(35), 100), _pos(2, _tag(36), 100)],
        zugaenge: [_zugang(_tag(37), 100), _zugang(_tag(39), 100)],
      );

      expect(d.tage[0].zuSpaetBis, _tag(37));
      expect(d.tage[1].zuSpaetBis, _tag(39));
      expect(d.fehltKg, 0);
    });

    test('rechtzeitige Ware geht an den Auftrag, den sie erreicht', () {
      // Mi 100, Fr 100, fertig Do 100: Für Mi kommt sie zu spät, für Fr
      // rechtzeitig. Also deckt sie Fr — und Mi fehlt.
      final d = berechneDeckung(
        lagerKg: 0,
        positionen: [_pos(1, _tag(30), 100), _pos(2, _tag(32), 100)],
        zugaenge: [_zugang(_tag(31), 100)],
      );

      expect(d.tage[0].fehltKg, 100);
      expect(d.tage[1].ausPlanungKg, 100);
      expect(d.zuSpaetKg, 0);
      expect(d.ersterFehltag, _tag(30));
    });

    test('mehr eingeplant als bestellt: der Rest ist Überschuss', () {
      final d = berechneDeckung(
        lagerKg: 0,
        positionen: [_pos(1, _tag(31), 50)],
        zugaenge: [_zugang(_tag(30), 80)],
      );

      expect(d.tage.single.ausPlanungKg, 50);
      expect(d.zugangKg, 80);
      expect(d.ueberschussKg, closeTo(30, 1e-9));
    });

    test('Produktionen, die nicht zählen, decken nichts', () {
      final d = berechneDeckung(
        lagerKg: 0,
        positionen: [_pos(1, _tag(32), 100)],
        zugaenge: [
          _zugang(_tag(29), 100, art: ZugangsArt.imLager),
          _zugang(_tag(31), null),
        ],
      );

      expect(d.fehltKg, 100);
      expect(d.zugangKg, 0);
    });
  });

  group('Produktionen der App laden', () {
    late AppDatabase db;

    setUp(() async {
      db = testDatenbank();
      await seedArtikel(db, id: 'p1', nummer: '12981');
    });
    tearDown(() => db.close());

    test('eine Kette ist am Tag ihres letzten Schritts fertig', () async {
      await _kette(
        db,
        id: 'k1',
        tage: [_tag(28), _tag(29), _tag(31)],
        fertigKg: 500,
      );

      final z = await ladeProduktionsZugaenge(
        db,
        heute: _tag(30),
        berichtTag: _tag(30),
      );

      final liste = z['12981']!;
      expect(liste, hasLength(1));
      expect(liste.single.kettenId, 'k1');
      expect(liste.single.fertigAm, _tag(31));
      expect(liste.single.art, ZugangsArt.eingeplant);
      expect(liste.single.kg, 500);
      expect(liste.single.zaehlt, isTrue);
    });

    test('ordnet nach Berichtstag ein', () async {
      // Bericht vom 30.09., heute ist der 02.10.
      await _kette(db, id: 'heute', tage: [_tag(32)], fertigKg: 10);
      await _kette(db, id: 'nachher', tage: [_tag(31)], fertigKg: 10);
      await _kette(db, id: 'berichtstag', tage: [_tag(30)], fertigKg: 10);
      await _kette(db, id: 'vorher', tage: [_tag(29)], fertigKg: 10);
      await _kette(db, id: 'alt', tage: [_tag(20)], fertigKg: 10);

      final z = await ladeProduktionsZugaenge(
        db,
        heute: _tag(32),
        berichtTag: _tag(30),
      );

      final art = {for (final x in z['12981']!) x.kettenId: x.art};
      expect(art, {
        'heute': ZugangsArt.eingeplant,
        'nachher': ZugangsArt.nachBericht,
        'berichtstag': ZugangsArt.nachBericht,
        'vorher': ZugangsArt.imLager,
      });
    });

    test('gelöschte Wurzel: der Rest der Kette zählt mit ihrer Fertigmenge',
        () async {
      await _kette(
        db,
        id: 'k1',
        tage: [_tag(30), _tag(31)],
        fertigKg: 400,
        wurzelGeloescht: true,
      );

      final z = await ladeProduktionsZugaenge(
        db,
        heute: _tag(30),
        berichtTag: _tag(30),
      );

      expect(z['12981']!.single.kg, 400);
      expect(z['12981']!.single.fertigAm, _tag(31));
    });

    test('ganz gelöschte und stornierte Ketten zählen nicht', () async {
      await _kette(
        db,
        id: 'weg',
        tage: [_tag(31)],
        fertigKg: 100,
        wurzelGeloescht: true,
      );
      await _kette(
        db,
        id: 'storno',
        tage: [_tag(31), _tag(32)],
        fertigKg: 100,
        status: 'storniert',
      );

      final z = await ladeProduktionsZugaenge(
        db,
        heute: _tag(30),
        berichtTag: _tag(30),
      );

      expect(z, isEmpty);
    });

    test('erfasste Produktion zählt mit der erfassten Menge', () async {
      await _kette(db, id: 'k1', tage: [_tag(30)], fertigKg: 500);
      await _erfassung(db, id: 'h1', tag: _tag(30), kg: 430);

      final z = await ladeProduktionsZugaenge(
        db,
        heute: _tag(31),
        berichtTag: _tag(30),
      );

      expect(z['12981']!.single.kg, 430);
      expect(z['12981']!.single.erfasst, isTrue);
    });

    test('zwei Produktionen am selben Tag: dann gilt der Plan', () async {
      await _kette(db, id: 'k1', tage: [_tag(30)], fertigKg: 500);
      await _kette(db, id: 'k2', tage: [_tag(30)], fertigKg: 300);
      await _erfassung(db, id: 'h1', tag: _tag(30), kg: 900);

      final z = await ladeProduktionsZugaenge(
        db,
        heute: _tag(31),
        berichtTag: _tag(30),
      );

      final kg = {for (final x in z['12981']!) x.kettenId: x.kg};
      expect(kg, {'k1': 500, 'k2': 300});
      expect(z['12981']!.every((x) => !x.erfasst), isTrue);
    });

    test('ohne Fertigmenge geplant: Menge unbekannt, zählt nicht', () async {
      await _kette(db, id: 'k1', tage: [_tag(31)], fertigKg: 0);

      final z = await ladeProduktionsZugaenge(
        db,
        heute: _tag(30),
        berichtTag: _tag(30),
      );

      expect(z['12981']!.single.kg, isNull);
      expect(z['12981']!.single.zaehlt, isFalse);
    });
  });

  group('Fehlende Artikel anlegen', () {
    late AppDatabase db;
    late ArtikelAnlageService service;

    setUp(() {
      db = testDatenbank();
      service = ArtikelAnlageService(db);
    });
    tearDown(() => db.close());

    Future<Product?> artikel(String nummer) =>
        (db.select(db.products)..where((p) => p.artikelnummer.equals(nummer)))
            .getSingleOrNull();

    test('legt neue Artikel als „nicht eingepflegt" an', () async {
      final e = await service.legeAn(const [
        FehlenderArtikel(
          nummer: '13977',
          bezeichnung: 'Köttbullar',
          bezeichnung2: '500g Beutel',
        ),
      ]);

      expect(e.angelegt, 1);
      final p = await artikel('13977');
      expect(p, isNotNull);
      expect(p!.artikelbezeichnung, 'Köttbullar');
      expect(p.beschreibung, '500g Beutel');
      expect(p.istEingepflegt, isFalse);
    });

    test('ohne Bezeichnung wird die Nummer der Name', () async {
      await service.legeAn(const [
        FehlenderArtikel(nummer: '4711', bezeichnung: ''),
      ]);

      expect((await artikel('4711'))!.artikelbezeichnung, '4711');
    });

    test('ein vorhandener Artikel bleibt unberührt', () async {
      await seedArtikel(db, id: 'p1', nummer: '12981', bezeichnung: 'Pute');

      final e = await service.legeAn(const [
        FehlenderArtikel(nummer: '12981', bezeichnung: 'Anders'),
      ]);

      expect(e.schonVorhanden, 1);
      expect(e.gesamt, 0);
      final p = await artikel('12981');
      expect(p!.artikelbezeichnung, 'Pute');
      expect(p.istEingepflegt, isTrue);
    });

    test('ein gelöschter Artikel wird wieder aktiviert', () async {
      await seedArtikel(db, id: 'p1', nummer: '12981', bezeichnung: 'Pute');
      await (db.update(db.products)..where((p) => p.id.equals('p1')))
          .write(ProductsCompanion(deletedAt: Value(DateTime(2026, 9, 1))));

      final e = await service.legeAn(const [
        FehlenderArtikel(nummer: '12981', bezeichnung: 'Pute neu'),
      ]);

      expect(e.reaktiviert, 1);
      expect(e.angelegt, 0);
      final p = await artikel('12981');
      expect(p!.id, 'p1');
      expect(p.deletedAt, isNull);
      expect(p.istEingepflegt, isFalse);
    });

    test('doppelte Nummern werden nur einmal angelegt', () async {
      final e = await service.legeAn(const [
        FehlenderArtikel(nummer: '13977', bezeichnung: 'Köttbullar'),
        FehlenderArtikel(nummer: '13977', bezeichnung: 'Köttbullar'),
      ]);

      expect(e.angelegt, 1);
      expect(await db.select(db.products).get(), hasLength(1));
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Hilfen
// ═══════════════════════════════════════════════════════════════════════════

/// Tag im Herbst 2026: 30 = 30.09., 31 = 01.10., 35 = 05.10. — DateTime
/// rechnet den Monatswechsel selbst.
DateTime _tag(int septemberTag) => DateTime(2026, 9, septemberTag);

AuftragsPosition _pos(int id, DateTime warenausgang, double kg) =>
    AuftragsPosition(
      id: id,
      artikelnummer: '12981',
      beleg: 'VA$id',
      debitor: 'Kunde $id',
      warenausgang: warenausgang,
      menge: kg,
      kg: kg,
    );

ProduktionsZugang _zugang(
  DateTime fertigAm,
  double? kg, {
  ZugangsArt art = ZugangsArt.eingeplant,
}) =>
    ProduktionsZugang(
      kettenId: 'k${fertigAm.day}',
      productId: 'p1',
      fertigAm: fertigAm,
      art: art,
      kg: kg,
    );

/// Legt eine Auftragskette an: ein Schritt je Tag in [tage], verkettet
/// wie im Board über `parentTaskId`. Die Fertigmenge steht an der Wurzel.
Future<void> _kette(
  AppDatabase db, {
  required String id,
  required List<DateTime> tage,
  required double fertigKg,
  String status = 'geplant',
  bool wurzelGeloescht = false,
}) async {
  String? vorher;
  for (var i = 0; i < tage.length; i++) {
    final taskId = i == 0 ? id : '$id-$i';
    await db.into(db.productionTasks).insert(
          ProductionTasksCompanion.insert(
            id: taskId,
            productId: 'p1',
            mengeKg: fertigKg,
            datum: tage[i],
            abteilung: 'bratstrasse',
            fertigMengeKg: Value(i == 0 ? fertigKg : null),
            geplanteDauerMinuten: 60,
            geplanteMitarbeiter: 2,
            status: Value(status),
            parentTaskId: Value(vorher),
            deletedAt: Value(
              i == 0 && wurzelGeloescht ? DateTime(2026, 9, 1) : null,
            ),
          ),
        );
    vorher = taskId;
  }
}

Future<void> _erfassung(
  AppDatabase db, {
  required String id,
  required DateTime tag,
  required double kg,
}) async {
  await db.into(db.productionHistory).insert(
        ProductionHistoryCompanion.insert(
          id: id,
          productId: 'p1',
          datum: tag,
          kgFertigware: Value(kg),
        ),
      );
}
