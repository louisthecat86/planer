import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/bedarf_uebernahme_service.dart';

import 'helpers/test_db.dart';

/// Tests für die Übernahme von Navision-Positionen in die Bedarfsliste.
///
/// Der heikelste Teil ist die Delta-Rechnung: Liegt für einen Artikel schon
/// etwas offen im Bedarf, darf nur die Differenz zum Navision-Stand
/// dazukommen. Fehlt das, entsteht bei jedem Import derselben Bestellung
/// ein zweiter Auftrag — und produziert wird am Ende doppelt.
void main() {
  late AppDatabase db;
  late BedarfUebernahmeService service;

  setUp(() {
    db = testDatenbank();
    service = BedarfUebernahmeService(db);
  });
  tearDown(() => db.close());

  group('Offener Bedarf', () {
    test('ist Auftrag minus Bestand', () async {
      await seedNavisionArtikel(
        db,
        nummer: '1001',
        mengeInAuftrag: 1000,
        lagerbestand: 300,
      );
      final artikel = await ladeNavisionArtikel(db);

      expect(offenerBedarf(artikel.single), 700);
    });

    test('wird nie negativ', () async {
      await seedNavisionArtikel(
        db,
        nummer: '1001',
        mengeInAuftrag: 100,
        lagerbestand: 500,
      );
      final artikel = await ladeNavisionArtikel(db);

      expect(offenerBedarf(artikel.single), 0);
    });

    test('„Menge in FA" wird nicht abgezogen', () async {
      // Bewusste Fachregel: Die Menge in Fertigungsaufträgen ist in
      // Navision eine erste Anfrage, keine geplante Produktionsmenge.
      // Abziehen würde den Bedarf systematisch zu klein rechnen.
      await seedNavisionArtikel(
        db,
        nummer: '1001',
        mengeInAuftrag: 1000,
        lagerbestand: 0,
        mengeInFa: 400,
      );
      final artikel = await ladeNavisionArtikel(db);

      expect(offenerBedarf(artikel.single), 1000);
    });
  });

  group('Übernahme', () {
    test('legt Bedarf und fehlende Artikelmaske an', () async {
      await seedNavisionArtikel(
        db,
        nummer: '1001',
        beschreibung: 'Krakauer',
        mengeInAuftrag: 500,
      );

      final res = await service.uebernehmen(
        kandidaten: await ladeNavisionArtikel(db),
        faktorVon: const {},
      );

      expect(res.uebernommen, 1);
      expect(res.angelegt, 1);

      final artikel = await db.select(db.products).get();
      expect(artikel.single.artikelnummer, '1001');
      expect(artikel.single.artikelbezeichnung, 'Krakauer');
      // Stubs sind als „noch nicht eingepflegt" markiert — die Prozessdaten
      // fehlen ja noch.
      expect(artikel.single.istEingepflegt, isFalse);

      final bedarf = await db.select(db.demands).get();
      expect(bedarf.single.mengeKgFertig, 500);
    });

    test('nutzt eine vorhandene Artikelmaske statt einer neuen', () async {
      await seedArtikel(db, id: 'p1', nummer: '1001');
      await seedNavisionArtikel(db, nummer: '1001', mengeInAuftrag: 500);

      final res = await service.uebernehmen(
        kandidaten: await ladeNavisionArtikel(db),
        faktorVon: const {},
      );

      expect(res.angelegt, 0);
      expect((await db.select(db.products).get()).length, 1);
      expect((await db.select(db.demands).get()).single.productId, 'p1');
    });

    test('rechnet Nicht-kg-Einheiten mit dem Faktor um', () async {
      // 1000 Beutel à 0,48 kg → 480 kg.
      await seedNavisionArtikel(
        db,
        nummer: '1001',
        basiseinheit: 'BTL',
        mengeInAuftrag: 1000,
      );

      final res = await service.uebernehmen(
        kandidaten: await ladeNavisionArtikel(db),
        faktorVon: const {'1001': 0.48},
      );

      expect(res.uebernommen, 1);
      expect(
        (await db.select(db.demands).get()).single.mengeKgFertig,
        closeTo(480, 0.01),
      );
    });

    test('überspringt Nicht-kg-Positionen ohne Faktor', () async {
      await seedNavisionArtikel(
        db,
        nummer: '1001',
        basiseinheit: 'BTL',
        mengeInAuftrag: 1000,
      );

      final res = await service.uebernehmen(
        kandidaten: await ladeNavisionArtikel(db),
        faktorVon: const {},
      );

      expect(res.uebersprungen, 1);
      expect(res.uebernommen, 0);
      // Ohne belastbare kg-Menge darf auch keine Artikelmaske entstehen.
      expect(await db.select(db.demands).get(), isEmpty);
    });

    test('ignoriert Positionen ohne offenen Bedarf', () async {
      await seedNavisionArtikel(
        db,
        nummer: '1001',
        mengeInAuftrag: 100,
        lagerbestand: 500,
      );

      final res = await service.uebernehmen(
        kandidaten: await ladeNavisionArtikel(db),
        faktorVon: const {},
      );

      expect(res.uebernommen, 0);
      expect(await db.select(db.demands).get(), isEmpty);
    });
  });

  group('Delta-Rechnung — kein doppelter Bedarf', () {
    test('zweimalige Übernahme erzeugt keinen zweiten Auftrag', () async {
      await seedNavisionArtikel(db, nummer: '1001', mengeInAuftrag: 500);
      final artikel = await ladeNavisionArtikel(db);

      final erste = await service.uebernehmen(
        kandidaten: artikel,
        faktorVon: const {},
      );
      final zweite = await service.uebernehmen(
        kandidaten: artikel,
        faktorVon: const {},
      );

      expect(erste.uebernommen, 1);
      expect(zweite.uebernommen, 0);
      expect(zweite.bereitsGedeckt, 1);
      expect((await db.select(db.demands).get()).length, 1);
    });

    test('ein gestiegener Navision-Bedarf ergänzt nur die Differenz',
        () async {
      await seedArtikel(db, id: 'p1', nummer: '1001');
      // 300 kg liegen bereits offen im Bedarf.
      await seedBedarf(db, id: 'd1', productId: 'p1', mengeKgFertig: 300);
      // Navision meldet inzwischen 500 kg.
      await seedNavisionArtikel(db, nummer: '1001', mengeInAuftrag: 500);

      final res = await service.uebernehmen(
        kandidaten: await ladeNavisionArtikel(db),
        faktorVon: const {},
      );

      expect(res.uebernommen, 1);
      final bedarfe = await db.select(db.demands).get();
      expect(bedarfe.length, 2);
      // Nur die Differenz, nicht die vollen 500.
      final neu = bedarfe.firstWhere((d) => d.id != 'd1');
      expect(neu.mengeKgFertig, closeTo(200, 0.01));
    });

    test('abgehakte Bedarfe decken nicht mehr', () async {
      await seedArtikel(db, id: 'p1', nummer: '1001');
      // Manuell erledigt → gilt als nicht mehr offen, der Navision-Bedarf
      // wird wieder frei.
      await seedBedarf(
        db,
        id: 'd1',
        productId: 'p1',
        mengeKgFertig: 500,
        manuellErledigt: true,
      );
      await seedNavisionArtikel(db, nummer: '1001', mengeInAuftrag: 500);

      final res = await service.uebernehmen(
        kandidaten: await ladeNavisionArtikel(db),
        faktorVon: const {},
      );

      expect(res.uebernommen, 1);
      expect(res.bereitsGedeckt, 0);
    });

    test('dieselbe Artikelnummer zweimal in einer Liste legt EINE Maske an',
        () async {
      // Die Spalte artikelnummer ist unique — würde die Maske zweimal
      // entstehen, fiele die ganze Transaktion.
      await seedNavisionArtikel(db, nummer: '1001', mengeInAuftrag: 500);
      final artikel = await ladeNavisionArtikel(db);

      final res = await service.uebernehmen(
        kandidaten: [...artikel, ...artikel],
        faktorVon: const {},
      );

      expect(res.angelegt, 1);
      expect((await db.select(db.products).get()).length, 1);
    });
  });

  group('Umrechnungsfaktoren', () {
    test('werden gemerkt und wieder gefunden', () async {
      await service.merkeFaktoren({'1001': 0.48}, {'1001': 'BTL'});

      final bekannt = await service.ladeUmrechnungen();
      expect(bekannt.faktoren['1001'], 0.48);
      expect(bekannt.einheiten['1001'], 'BTL');
    });

    test('kg-Artikel brauchen keinen Faktor', () async {
      await seedNavisionArtikel(db, nummer: '1001', mengeInAuftrag: 500);
      final bekannt = await service.ladeUmrechnungen();

      final fehlend = service.fehlendeUmrechnungen(
        await ladeNavisionArtikel(db),
        bekannt,
      );

      expect(fehlend, isEmpty);
    });

    test('ein Faktor für eine andere Einheit zählt nicht', () async {
      // Navision kann die Basiseinheit eines Artikels ändern. Ein Faktor
      // „0,48 kg je BTL" ist wertlos, sobald derselbe Artikel in KT
      // geführt wird — dann muss neu gefragt werden.
      await service.merkeFaktoren({'1001': 0.48}, {'1001': 'BTL'});
      await seedNavisionArtikel(
        db,
        nummer: '1001',
        basiseinheit: 'KT',
        mengeInAuftrag: 100,
      );

      final fehlend = service.fehlendeUmrechnungen(
        await ladeNavisionArtikel(db),
        await service.ladeUmrechnungen(),
      );

      expect(fehlend.length, 1);
    });
  });
}
