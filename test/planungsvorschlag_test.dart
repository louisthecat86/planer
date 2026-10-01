// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/auftragsbestand_deckung.dart';
import 'package:produktion_planer/features/auftragsbestand/auftrags_einplanung.dart';
import 'package:produktion_planer/features/planung/planungsvorschlag_service.dart';

import 'helpers/test_db.dart';

/// Tests für den Planungsvorschlag: Er plant nur, was ausgewählt ist, legt
/// es so spät wie möglich — aber nie nach dem Termin — und gibt beim
/// Übernehmen die Auftragszeilen an die Produktion weiter.
///
/// Die Artikel laufen mit 100 kg je Stunde über die Bratstraße, die
/// Tageskapazität ist 600 Minuten. Rüsten und Reinigen stehen auf 0,
/// damit die Rechnung in den Tests übersichtlich bleibt — außer dort, wo
/// es genau um die Endreinigung geht.
void main() {
  late AppDatabase db;
  late PlanungsvorschlagService service;

  // Montag, 05.10.2026, bis Freitag, 09.10.2026.
  final montag = DateTime(2026, 10, 5);
  final dienstag = DateTime(2026, 10, 6);
  final mittwoch = DateTime(2026, 10, 7);
  final donnerstag = DateTime(2026, 10, 8);
  final freitag = DateTime(2026, 10, 9);

  VorschlagEinstellungen woche({bool spaet = true, Set<String>? auswahl}) =>
      VorschlagEinstellungen(
        startTag: montag,
        maxArbeitstage: 5,
        ruestenMinuten: 0,
        zwischenreinigungMinuten: 0,
        endreinigungMinuten: 0,
        moeglichstSpaet: spaet,
        bedarfIds: auswahl,
      );

  /// Ein planbarer Artikel: Merkmale gepflegt, Bratstraße 100 kg je
  /// Stunde.
  Future<void> artikel(String id, String nummer) async {
    await seedArtikel(db, id: id, nummer: nummer);
    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      const ProductsCompanion(
        allergene: Value('keine'),
        qualitaetsstufe: Value('konventionell'),
        verarbeitungsstufe: Value('gegart'),
      ),
    );
    await seedSchritt(
      db,
      id: 's-$id',
      productId: id,
      reihenfolge: 1,
      abteilung: 'bratstrasse',
    );
  }

  Future<void> bedarf(
    String id,
    String productId,
    double kg, {
    DateTime? termin,
  }) async {
    await db.into(db.demands).insert(
          DemandsCompanion.insert(
            id: id,
            productId: productId,
            mengeKgFertig: kg,
            termin: Value(termin),
          ),
        );
  }

  /// Ein fest eingeplanter Auftrag, der die Bratstraße an [tag] für
  /// [minuten] belegt.
  Future<void> belege(DateTime tag, double minuten) async {
    await db.into(db.productionTasks).insert(
          ProductionTasksCompanion.insert(
            id: 'fest-${tag.month}-${tag.day}',
            productId: 'p2',
            mengeKg: 100,
            datum: tag,
            abteilung: 'bratstrasse',
            geplanteDauerMinuten: minuten,
            geplanteMitarbeiter: 2,
          ),
        );
  }

  List<DateTime> tageMit(Planungsvorschlag v, String bedarfId) => [
        for (final t in v.tage)
          if (t.posten.any((p) => p.bedarfId == bedarfId)) t.tag,
      ];

  setUp(() async {
    db = testDatenbank();
    service = PlanungsvorschlagService(db);
    await artikel('p1', '12981');
    await artikel('p2', '13977');
  });
  tearDown(() => db.close());

  group('Wann geplant wird', () {
    test('möglichst spät: am letzten Arbeitstag vor dem Termin', () async {
      await bedarf('b1', 'p1', 200, termin: freitag);

      final v = await service.berechne(woche());

      expect(tageMit(v, 'b1'), [freitag]);
      expect(v.nichtPlanbar, isEmpty);
    });

    test('möglichst früh: am ersten Tag', () async {
      await bedarf('b1', 'p1', 200, termin: freitag);

      final v = await service.berechne(woche(spaet: false));

      expect(tageMit(v, 'b1'), [montag]);
    });

    test('ist der Termintag voll, wird es früher — nie später', () async {
      await bedarf('b1', 'p1', 200, termin: mittwoch);
      await belege(mittwoch, 550);

      final v = await service.berechne(woche());

      expect(tageMit(v, 'b1'), [dienstag]);
    });

    test('ist vor dem Termin kein Platz, kommt es in die Restliste',
        () async {
      await bedarf('b1', 'p1', 200, termin: dienstag);
      await belege(montag, 550);
      await belege(dienstag, 550);

      for (final spaet in [true, false]) {
        final v = await service.berechne(woche(spaet: spaet));

        expect(tageMit(v, 'b1'), isEmpty);
        expect(v.nichtPlanbar.single.grund, contains('Vor dem Termin'));
        expect(v.nichtPlanbar.single.grund, contains('Di 06.10.'));
      }
    });

    test('Termin schon vorbei: so früh wie möglich, mit Hinweis', () async {
      await bedarf('b1', 'p1', 200, termin: DateTime(2026, 10, 2));

      final v = await service.berechne(woche());

      expect(tageMit(v, 'b1'), [montag]);
      expect(v.tage.first.warnungen.single, contains('überschritten'));
    });

    test('ohne Termin: so früh wie möglich', () async {
      await bedarf('b1', 'p1', 200);

      final v = await service.berechne(woche());

      expect(tageMit(v, 'b1'), [montag]);
    });

    test('jeder Bedarf so nah an seinem Termin wie möglich', () async {
      await bedarf('mi', 'p1', 400, termin: mittwoch);
      await bedarf('fr', 'p2', 400, termin: freitag);

      final v = await service.berechne(woche());

      expect(tageMit(v, 'mi'), [mittwoch]);
      expect(tageMit(v, 'fr'), [freitag]);
    });

    test('passen zwei nicht an den Termintag, rückt einer davor', () async {
      // Je 550 kg = 5:30 h — zusammen mehr als ein Tag.
      await bedarf('b1', 'p1', 550, termin: freitag);
      await bedarf('b2', 'p2', 550, termin: freitag);

      final v = await service.berechne(woche());

      expect(
        {...tageMit(v, 'b1'), ...tageMit(v, 'b2')},
        {donnerstag, freitag},
      );
      expect(v.nichtPlanbar, isEmpty);
    });

    test('alle Arbeitstage des Zeitraums, auch die leeren', () async {
      await bedarf('b1', 'p1', 200, termin: freitag);

      final v = await service.berechne(woche());

      expect(
        v.tage.map((t) => t.tag),
        [montag, dienstag, mittwoch, donnerstag, freitag],
      );
    });
  });

  group('Auswahl', () {
    test('nur die ausgewählten Bedarfe — die übrigen auch nicht als Rest',
        () async {
      await bedarf('b1', 'p1', 200, termin: freitag);
      await bedarf('b2', 'p2', 200, termin: freitag);

      final v = await service.berechne(woche(auswahl: {'b2'}));

      expect(tageMit(v, 'b1'), isEmpty);
      expect(tageMit(v, 'b2'), [freitag]);
      expect(v.nichtPlanbar, isEmpty);
    });

    test('vorausgewählt: fällig im Zeitraum und ohne Termin', () {
      OffenerBedarf offen(String id, DateTime? termin) => OffenerBedarf(
            bedarfId: id,
            productId: 'p1',
            artikelnummer: '12981',
            bezeichnung: 'Testartikel',
            offenKg: 10,
            quelle: 'bestellung',
            prioritaet: 0,
            termin: termin,
          );

      final auswahl = vorauswahl(
        [
          offen('ueberfaellig', DateTime(2026, 10, 1)),
          offen('im Zeitraum', freitag),
          offen('ohne Termin', null),
          offen('später', DateTime(2026, 10, 20)),
        ],
        vorschlagsTage(woche()),
      );

      expect(auswahl, {'ueberfaellig', 'im Zeitraum', 'ohne Termin'});
    });

    test('die Auswahl zeigt die offene Menge, frühester Termin zuerst',
        () async {
      await bedarf('ohne', 'p1', 100);
      await bedarf('spaet', 'p1', 200, termin: freitag);
      await bedarf('frueh', 'p2', 300, termin: montag);

      final liste = await service.ladeOffeneBedarfe();

      expect(liste.map((b) => b.bedarfId), ['frueh', 'spaet', 'ohne']);
      expect(liste.first.offenKg, 300);
      expect(liste.first.artikelnummer, '13977');
    });
  });

  group('Kapazität', () {
    test('die Endreinigung zählt einmal je Tag', () async {
      // 900 kg = 540 min, dazu 45 min Endreinigung = 585 von 600. Früher
      // kam die Endreinigung doppelt dazu (630), und der Artikel passte an
      // keinen Tag.
      await bedarf('b1', 'p1', 900, termin: freitag);

      final v = await service.berechne(
        woche().kopieMit(endreinigungMinuten: 45),
      );

      expect(tageMit(v, 'b1'), [freitag]);
      expect(v.tage.last.neuMinuten, 585);
    });

    test('mehr als ein ganzer Tag: Restliste mit Grund', () async {
      // 1.000 kg = 600 min, mit Endreinigung 645 — mehr als ein Tag.
      await bedarf('b1', 'p1', 1000, termin: freitag);

      final v = await service.berechne(
        woche().kopieMit(endreinigungMinuten: 45),
      );

      expect(tageMit(v, 'b1'), isEmpty);
      expect(v.nichtPlanbar.single.grund, contains('mehr als ein ganzer Tag'));
    });

    test('Rüstzeit einer zweiten Übernahme kommt dazu, Endreinigung '
        'bleibt eine', () async {
      VorschlagPosten posten(String productId, String nummer, double neben) =>
          VorschlagPosten(
            bedarfId: null,
            productId: productId,
            artikelnummer: nummer,
            bezeichnung: 'Testartikel',
            mengeKg: 100,
            rohwareKg: 100,
            dauerMinuten: 60,
            ausHistorie: false,
            nebenzeitMinuten: neben,
            wechselGrund: WechselGrund.umstellen,
            begruendung: '',
            allergenRang: 0,
            bioRang: 1,
            rohRang: 0,
            plattenTemp: 0,
            hoehe: 0,
            ausgangsMengeKg: 100,
          );
      VorschlagTag tag(VorschlagPosten p) => VorschlagTag(
            tag: montag,
            posten: [p],
            kapazitaetMinuten: 600,
            belegtVorherMinuten: 0,
            endreinigungMinuten: 45,
            warnungen: const [],
          );

      await service.uebernehmeTag(tag(posten('p1', '12981', 20)));
      await service.uebernehmeTag(tag(posten('p2', '13977', 30)));

      final bloecke = await db.select(db.zusatzzeiten).get();
      expect(
        bloecke.where((z) => z.art == 'ruesten').single.minuten,
        50,
      );
      expect(
        bloecke.where((z) => z.art == 'reinigen').single.minuten,
        45,
      );

      // Der nächste Vorschlag weiß, dass die Endreinigung am Montag schon
      // im Board steht.
      final v = await service.berechne(
        woche().kopieMit(endreinigungMinuten: 45),
      );
      expect(v.tage.first.endreinigungMinuten, 0);
      expect(v.tage[1].endreinigungMinuten, 45);
    });
  });

  group('Planungsaufträge aus dem Auftragsbestand', () {
    final a = AuftragsBezug(
      beleg: 'VA1',
      warenausgang: DateTime(2026, 10, 12),
      kg: 120,
      debitor: 'Kunde 1',
    );
    final b = AuftragsBezug(
      beleg: 'VA2',
      warenausgang: DateTime(2026, 10, 13),
      kg: 80,
      debitor: 'Kunde 2',
    );

    test('Übernahme: die Kette trägt Bedarf und Auftragszeilen', () async {
      final id = await uebergebeAnPlanungsvorschlag(
        db: db,
        productId: 'p1',
        fertigKg: 200,
        termin: freitag,
        bezuege: [a, b],
      );

      final v = await service.berechne(woche());
      final tag = v.tage.singleWhere((t) => t.posten.isNotEmpty);
      expect(tag.tag, freitag);
      expect(tag.posten.single.auftragsBezuege, hasLength(2));

      await service.uebernehmeTag(tag);

      final wurzel = (await db.select(db.productionTasks).get())
          .singleWhere((t) => t.parentTaskId == null);
      expect(wurzel.bedarfId, id);
      expect(wurzel.fertigMengeKg, 200);
      expect(
        AuftragsBezug.dekodiere(wurzel.auftragsZeilen).map((x) => x.beleg),
        ['VA1', 'VA2'],
      );
      // Ganz eingeplant: nichts mehr vorgemerkt, nichts mehr offen.
      expect(await ladeVormerkungen(db), isEmpty);
      expect(await service.ladeOffeneBedarfe(), isEmpty);
    });

    test('Teilmenge übernommen: der Rest bleibt vorgemerkt', () async {
      await uebergebeAnPlanungsvorschlag(
        db: db,
        productId: 'p1',
        fertigKg: 200,
        termin: freitag,
        bezuege: [a, b],
      );

      final v = await service.berechne(woche());
      final tag = v.tage.singleWhere((t) => t.posten.isNotEmpty);
      await service.uebernehmeTag(
        tag.kopieMit(posten: [tag.posten.single.mitMenge(150)]),
      );

      // Die Kette trägt VA1 ganz und 30 kg von VA2.
      final wurzel = (await db.select(db.productionTasks).get())
          .singleWhere((t) => t.parentTaskId == null);
      final getragen = AuftragsBezug.dekodiere(wurzel.auftragsZeilen);
      expect(getragen.map((x) => x.beleg), ['VA1', 'VA2']);
      expect(getragen[1].kg, closeTo(30, 1e-9));

      // Der Rest — 50 kg von VA2 — bleibt vorgemerkt …
      final rest = (await ladeVormerkungen(db))['12981']!.single;
      expect(rest.offenKg, closeTo(50, 1e-9));
      expect(rest.bezuege.single.beleg, 'VA2');
      expect(rest.bezuege.single.kg, closeTo(50, 1e-9));

      // … und der nächste Vorschlag plant nur noch ihn.
      final offen = (await service.ladeOffeneBedarfe()).single;
      expect(offen.offenKg, closeTo(50, 1e-9));
      expect(offen.auftragsBezuege.single.kg, closeTo(50, 1e-9));
    });

    test('Kette im Board gelöscht: der Auftrag ist wieder offen', () async {
      await uebergebeAnPlanungsvorschlag(
        db: db,
        productId: 'p1',
        fertigKg: 200,
        termin: freitag,
        bezuege: [a, b],
      );
      final v = await service.berechne(woche());
      await service.uebernehmeTag(
        v.tage.singleWhere((t) => t.posten.isNotEmpty),
      );

      await db
          .update(db.productionTasks)
          .write(ProductionTasksCompanion(deletedAt: Value(DateTime.now())));

      final rest = (await ladeVormerkungen(db))['12981']!.single;
      expect(rest.offenKg, 200);
      expect(rest.bezuege, hasLength(2));
    });
  });

  group('Zeitumstellung', () {
    test('der Zeitraum läuft über den 25.10. hinweg', () {
      final tage = vorschlagsTage(
        VorschlagEinstellungen(
          startTag: DateTime(2026, 10, 19),
          maxArbeitstage: 10,
        ),
      );

      expect(tage, hasLength(10));
      expect(tage.first, DateTime(2026, 10, 19));
      expect(tage.last, DateTime(2026, 10, 30));
      expect(tage.every((t) => t.hour == 0 && t.minute == 0), isTrue);
      expect(
        tage.every((t) => t.weekday <= DateTime.friday),
        isTrue,
      );
    });

    test('ein Vorschlag über die Zeitumstellung wird fertig', () async {
      await bedarf('b1', 'p1', 200, termin: DateTime(2026, 10, 27));

      final v = await service.berechne(
        VorschlagEinstellungen(
          startTag: DateTime(2026, 10, 19),
          maxArbeitstage: 10,
        ),
      );

      expect(tageMit(v, 'b1'), [DateTime(2026, 10, 27)]);
    });
  });
}
