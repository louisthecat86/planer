// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/auftragsbestand_deckung.dart';
import 'package:produktion_planer/features/auftragsbestand/auftrags_einplanung.dart';
import 'package:produktion_planer/features/datenblatt/datenblatt.dart';
import 'package:produktion_planer/features/whiteboard/whiteboard_provider.dart'
    show berechneSchrittPlan, erstelleTasksAusPlan;

import 'helpers/test_db.dart';

/// Tests für das Datenblatt einer gebündelten Planung: welcher Artikel,
/// wie viel, bis wann, für welche Aufträge — und dass das PDF entsteht.
///
/// Alle Daten sind erfunden.
void main() {
  late AppDatabase db;

  final termin = DateTime(2026, 10, 7);
  final dienstag = DateTime(2026, 10, 6);
  final bezuege = [
    AuftragsBezug(
      beleg: 'VA-T1',
      warenausgang: DateTime(2026, 10, 8),
      kg: 200,
      debitor: 'Kunde A',
    ),
    AuftragsBezug(
      beleg: 'VA-T2',
      warenausgang: DateTime(2026, 10, 9),
      kg: 200,
      debitor: 'Kunde B',
    ),
    AuftragsBezug(
      beleg: 'VA-T3',
      warenausgang: DateTime(2026, 10, 12),
      kg: 100,
      debitor: 'Kunde C',
    ),
  ];

  setUp(() async {
    db = testDatenbank();
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: 'p1',
            artikelnummer: 'T-100',
            artikelbezeichnung: 'Testschinken',
            beschreibung: const Value('gekocht, am Stück'),
            allergene: const Value('eier,milch'),
            qualitaetsstufe: const Value('konventionell'),
            verarbeitungsstufe: const Value('gegart'),
            haltbarkeitTage: const Value(21),
            gesamtAusbeuteFaktor: const Value(0.8),
          ),
        );
    await seedSchritt(
      db,
      id: 's1',
      productId: 'p1',
      reihenfolge: 1,
      abteilung: 'wurstkueche',
    );
    await seedSchritt(
      db,
      id: 's2',
      productId: 'p1',
      reihenfolge: 2,
      abteilung: 'bratstrasse',
    );
    await seedSchritt(
      db,
      id: 's3',
      productId: 'p1',
      reihenfolge: 3,
      abteilung: 'verpackung',
    );
  });
  tearDown(() => db.close());

  Future<String> planungsauftrag() => uebergebeAnPlanungsvorschlag(
        db: db,
        productId: 'p1',
        fertigKg: 500,
        termin: termin,
        bezuege: bezuege,
      );

  Future<List<ProductionTask>> schritte() =>
      db.select(db.productionTasks).get();

  group('Planungsauftrag', () {
    test('Artikel, Menge, spätester Tag und die gebündelten Aufträge',
        () async {
      final id = await planungsauftrag();
      final b = (await datenblattFuerBedarf(db, id))!;

      expect(b.artikelnummer, 'T-100');
      expect(b.bezeichnung, 'Testschinken');
      expect(b.bezeichnung2, 'gekocht, am Stück');
      expect(b.fertigKg, 500);
      expect(b.rohwareKg, closeTo(625, 1e-9));
      expect(b.ausbeuteProzent, closeTo(80, 1e-9));
      expect(b.tag, termin);
      expect(b.tagArt, DatenblattTag.spaetestens);
      expect(b.mhd, isNull, reason: 'Der Produktionstag steht noch nicht fest');
      expect(b.bezuege.map((z) => z.beleg), ['VA-T1', 'VA-T2', 'VA-T3']);
      expect(b.auftragKg, 500);
      expect(b.status, 'Noch nicht im Board eingeplant');
      expect(b.notiz, isNull, reason: 'Die Notiz zählt nur die Aufträge auf');
      expect(b.merkmale, ['Allergene: Eier, Milch', 'Konventionell', 'Gegart']);
      expect(b.haltbarkeitTage, 21);
    });

    test('Ablauf wie beim Einplanen: Rohware bis zur Bratstraße', () async {
      final id = await planungsauftrag();
      final b = (await datenblattFuerBedarf(db, id))!;

      expect(
        b.schritte.map((s) => s.abteilung),
        ['Wurstküche', 'Bratstraße', 'Verpackung'],
      );
      expect(b.schritte[0].mengeKg, closeTo(625, 1e-9));
      expect(b.schritte[1].mengeKg, closeTo(625, 1e-9));
      expect(b.schritte[2].mengeKg, closeTo(500, 1e-9));
      expect(b.schritte.every((s) => s.dauerMinuten != null), isTrue);
      expect(
        b.schritte.every((s) => s.tag == null),
        isTrue,
        reason: 'Ohne Produktionstag keine Tage je Abteilung',
      );
    });

    test('Vormerkung: nur der Teil, der noch nicht im Board steht', () async {
      final id = await planungsauftrag();
      // Wie beim Übernehmen eines Tages aus dem Planungsvorschlag.
      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p1',
        mengeKg: 200,
        startTag: dienstag,
      );
      await erstelleTasksAusPlan(
        db: db,
        productId: 'p1',
        schritte: plan.schritte,
        bedarfId: id,
        fertigMengeKg: 200,
        auftragsBezuege: teileBezuegeZu(bezuege, 200),
      );

      final offen = (await datenblattFuerBedarf(db, id, nurOffen: true))!;
      expect(offen.fertigKg, 300);
      expect(offen.bezuege.map((z) => z.beleg), ['VA-T2', 'VA-T3']);
      expect(offen.status, contains('200 kg davon stehen schon im Board'));

      final ganz = (await datenblattFuerBedarf(db, id))!;
      expect(ganz.fertigKg, 500);
      expect(ganz.status, 'Davon im Board eingeplant: 200 kg');
    });

    test('Notiz eines gewöhnlichen Bedarfs steht drauf', () async {
      await db.into(db.demands).insert(
            DemandsCompanion.insert(
              id: 'b1',
              productId: 'p1',
              mengeKgFertig: 80,
              notizen: const Value('  Aktion Kunde A  '),
            ),
          );
      final b = (await datenblattFuerBedarf(db, 'b1'))!;
      expect(b.notiz, 'Aktion Kunde A');
      expect(b.tag, isNull);
      expect(b.bezuege, isEmpty);
    });
  });

  group('Produktion im Board', () {
    test('Tage je Abteilung, Aufträge und Menge von der Wurzel', () async {
      final e = await planeAuftragszeilen(
        db: db,
        productId: 'p1',
        fertigKg: 500,
        tag: dienstag,
        bezuege: bezuege,
      );
      expect(e.wurzelId, isNotNull);

      final b = (await datenblattFuerKette(db, e.wurzelId!))!;
      expect(b.fertigKg, 500);
      expect(b.fertigGeschaetzt, isFalse);
      expect(b.rohwareKg, closeTo(625, 1e-9));
      expect(b.ausbeuteProzent, closeTo(80, 1e-9));
      expect(b.tag, dienstag);
      expect(b.tagArt, DatenblattTag.produktion);
      expect(b.mhd, DateTime(2026, 10, 27));
      expect(b.status, 'Eingeplant im Board');
      expect(b.bezuege, hasLength(3));
      expect(
        b.schritte.map((s) => s.abteilung),
        ['Wurstküche', 'Bratstraße', 'Verpackung'],
      );
      expect(b.schritte.every((s) => s.tag == dienstag), isTrue);

      // Von jedem Schritt der Kette aus dasselbe Blatt.
      final verpackung =
          (await schritte()).firstWhere((t) => t.abteilung == 'verpackung');
      final vonHinten = (await datenblattFuerKette(db, verpackung.id))!;
      expect(vonHinten.fertigKg, 500);
      expect(vonHinten.bezuege, hasLength(3));
    });

    test('über mehrere Tage: fertig am letzten, Beginn im Status', () async {
      final e = await planeAuftragszeilen(
        db: db,
        productId: 'p1',
        fertigKg: 500,
        tag: dienstag,
        bezuege: bezuege,
      );
      final verpackung =
          (await schritte()).firstWhere((t) => t.abteilung == 'verpackung');
      await (db.update(db.productionTasks)
            ..where((t) => t.id.equals(verpackung.id)))
          .write(ProductionTasksCompanion(datum: Value(termin)));

      final b = (await datenblattFuerKette(db, e.wurzelId!))!;
      expect(b.tag, termin);
      expect(b.tagArt, DatenblattTag.fertig);
      expect(b.mhd, DateTime(2026, 10, 28));
      expect(b.status, contains('Beginn Di 06.10.2026'));
      expect(b.schritte.last.tag, termin);
    });

    test('erster Schritt gelöscht: Menge und Aufträge bleiben', () async {
      final e = await planeAuftragszeilen(
        db: db,
        productId: 'p1',
        fertigKg: 500,
        tag: dienstag,
        bezuege: bezuege,
      );
      await (db.update(db.productionTasks)
            ..where((t) => t.id.equals(e.wurzelId!)))
          .write(ProductionTasksCompanion(deletedAt: Value(DateTime(2026))));

      final b = (await datenblattFuerKette(db, e.wurzelId!))!;
      expect(b.fertigKg, 500);
      expect(b.bezuege, hasLength(3));
      expect(
        b.schritte.map((s) => s.abteilung),
        ['Bratstraße', 'Verpackung'],
      );
    });

    test('ganz gelöscht: kein Blatt', () async {
      final e = await planeAuftragszeilen(
        db: db,
        productId: 'p1',
        fertigKg: 500,
        tag: dienstag,
        bezuege: bezuege,
      );
      await db
          .update(db.productionTasks)
          .write(ProductionTasksCompanion(deletedAt: Value(DateTime(2026))));

      expect(await datenblattFuerKette(db, e.wurzelId!), isNull);
    });

    test('in Rohware geplant: Fertigware über die Ausbeute geschätzt',
        () async {
      final plan = await berechneSchrittPlan(
        db: db,
        productId: 'p1',
        mengeKg: 400,
        startTag: dienstag,
      );
      final id = await erstelleTasksAusPlan(
        db: db,
        productId: 'p1',
        schritte: plan.schritte,
      );

      final b = (await datenblattFuerKette(db, id!))!;
      expect(b.fertigGeschaetzt, isTrue);
      expect(b.rohwareKg, closeTo(500, 1e-9));
      expect(b.fertigKg, closeTo(400, 1e-9));
      expect(b.bezuege, isEmpty);
    });
  });

  group('Posten des Planungsvorschlags', () {
    test('mit Produktionstag: Tage je Abteilung und Haltbarkeit', () async {
      final b = (await datenblattFuerMenge(
        db,
        productId: 'p1',
        fertigKg: 300,
        tag: dienstag,
        bezuege: teileBezuegeZu(bezuege, 300),
        status: 'Planungsvorschlag',
      ))!;

      expect(b.tagArt, DatenblattTag.produktion);
      expect(b.mhd, DateTime(2026, 10, 27));
      expect(b.rohwareKg, closeTo(375, 1e-9));
      expect(b.bezuege.map((z) => z.kg), [200, 100]);
      expect(b.schritte.every((s) => s.tag == dienstag), isTrue);
    });
  });

  group('Fehlt etwas', () {
    test('unbekannter Bedarf, Schritt oder Artikel: kein Blatt', () async {
      expect(await datenblattFuerBedarf(db, 'gibt-es-nicht'), isNull);
      expect(await datenblattFuerKette(db, 'gibt-es-nicht'), isNull);
      expect(
        await datenblattFuerMenge(db, productId: 'fehlt', fertigKg: 1),
        isNull,
      );
      expect(await alsListe(Future<Datenblatt?>.value()), isEmpty);
    });
  });

  group('PDF', () {
    test('ein Blatt je Planung, auch mit Zeichen außerhalb von Latin-1',
        () async {
      final blatt = Datenblatt(
        artikelnummer: 'T-100',
        bezeichnung: 'Testschinken „Spezial" – 2 × 500 g …',
        bezeichnung2: 'mit Emoji 🥩 und €',
        fertigKg: 1250,
        rohwareKg: 1562.5,
        ausbeuteProzent: 80,
        tag: dienstag,
        status: 'Eingeplant im Board',
        bezuege: bezuege,
        merkmale: const ['Allergene: Eier, Milch'],
        schritte: [
          DatenblattSchritt(
            abteilung: 'Bratstraße',
            tag: dienstag,
            mengeKg: 1562.5,
            dauerMinuten: 135,
          ),
        ],
        haltbarkeitTage: 21,
        notiz: 'Zeile 1\r\nZeile 2\tmit Tab',
      );

      final bytes = await baueDatenblattPdf(
        [blatt, blatt],
        gedrucktAm: DateTime(2026, 10, 1, 8, 30),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });

    test('viele Aufträge laufen über mehrere Seiten', () async {
      final viele = [
        for (var i = 0; i < 150; i++)
          AuftragsBezug(
            beleg: 'VA$i',
            warenausgang: DateTime(2026, 10, 8),
            kg: 10,
            debitor: 'Kunde $i',
          ),
      ];
      final bytes = await baueDatenblattPdf([
        Datenblatt(
          artikelnummer: 'T-100',
          bezeichnung: 'Test',
          fertigKg: 1500,
          tagArt: DatenblattTag.spaetestens,
          bezuege: viele,
        ),
      ]);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
