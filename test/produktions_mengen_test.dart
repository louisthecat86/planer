// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/providers/database_provider.dart';
import 'package:produktion_planer/core/services/produktion_erfassen_service.dart';
import 'package:produktion_planer/core/utils/format.dart';
import 'package:produktion_planer/features/erfassung/erfassung_druck.dart';
import 'package:produktion_planer/features/erfassung/geplante_produktion.dart';
import 'package:produktion_planer/features/erfassung/produktion_erfassung_screen.dart';
import 'package:produktion_planer/features/whiteboard/produktions_mengen.dart';
import 'package:produktion_planer/features/whiteboard/whiteboard_provider.dart'
    show berechneSchrittPlan, erstelleTasksAusPlan, ladeAbteilungsDauerModell;

import 'helpers/test_db.dart';

/// Rohware, Fertigware und Fleischeinwaage einer Produktion im Board: womit
/// jeder Auftrag der Kette arbeitet, woher Ausbeute und Fleischanteil
/// kommen und was beim Speichern an allen Aufträgen ankommt. Artikel,
/// Mengen und Rezepturen sind erfunden.
void main() {
  late AppDatabase db;
  final montag = DateTime(2026, 11, 9);

  setUp(() async {
    db = testDatenbank();
    await seedArtikel(db, id: 'p1', nummer: 'T-200', bezeichnung: 'Testbraten');
    // Zerlegung → Wurstküche → Bratstraße → Verpackung, je 100 kg in
    // 10, 20, 30 und 5 Minuten.
    const abteilungen = [
      'zerlegung',
      'wurstkueche',
      'bratstrasse',
      'verpackung',
    ];
    const minuten = [10.0, 20.0, 30.0, 5.0];
    for (var i = 0; i < abteilungen.length; i++) {
      await seedSchritt(
        db,
        id: 's${i + 1}',
        productId: 'p1',
        reihenfolge: i + 1,
        abteilung: abteilungen[i],
        basisDauerMinuten: minuten[i],
      );
    }
    // Eine erfasste Produktion: 1.000 kg Rohware, davon 700 kg Fleisch,
    // ergaben 800 kg Fertigware.
    await ProduktionErfassenService.speichere(
      db: db,
      productId: 'p1',
      datum: DateTime(2026, 10, 1),
      kgRohware: 1000,
      kgFleischeinwaage: 700,
      kgFertigware: 800,
    );
  });
  tearDown(() => db.close());

  /// Plant [fertig] kg Fertigware ein — ohne die Abteilungen in [ohne].
  /// [mitFertig]: Die Wurzel trägt die Fertigmenge — sonst ist sie, wie
  /// bei einer Planung in Rohware ohne bekannte Ausbeute, 0.
  Future<String> planen({
    String productId = 'p1',
    double fertig = 800,
    bool mitFertig = true,
    Set<String> ohne = const {},
  }) async {
    final plan = await berechneSchrittPlan(
      db: db,
      productId: productId,
      mengeKg: fertig,
      startTag: montag,
    );
    return (await erstelleTasksAusPlan(
      db: db,
      productId: productId,
      schritte: [
        for (final s in plan.schritte)
          if (!ohne.contains(s.abteilungDbValue)) s,
      ],
      fertigMengeKg: mitFertig ? fertig : 0,
    ))!;
  }

  /// Die Aufträge der Abteilung [abteilung] im Board, nach Tag.
  Future<List<ProductionTask>> auftraege(
    String abteilung, {
    String productId = 'p1',
  }) async =>
      (await (db.select(db.productionTasks)
            ..where((t) => t.productId.equals(productId))
            ..where((t) => t.abteilung.equals(abteilung))
            ..where((t) => t.deletedAt.isNull()))
          .get())
        ..sort((a, b) => a.datum.compareTo(b.datum));

  Future<ProductionTask> auftrag(String abteilung) async =>
      (await auftraege(abteilung)).first;

  Future<ProductionTask> lies(String id) async =>
      (await db.select(db.productionTasks).get())
          .singleWhere((t) => t.id == id);

  /// Verteilt [t] wie „Auf mehrere Tage verteilen": [t] behält die erste
  /// Menge, die übrigen werden Teile an den Folgetagen.
  Future<void> teilen(ProductionTask t, List<double> mengen) async {
    await (db.update(db.productionTasks)..where((x) => x.id.equals(t.id)))
        .write(ProductionTasksCompanion(mengeKg: Value(mengen.first)));
    for (var i = 1; i < mengen.length; i++) {
      await db.into(db.productionTasks).insert(
            ProductionTasksCompanion.insert(
              id: '${t.id}-teil$i',
              productId: t.productId,
              mengeKg: mengen[i],
              datum: t.datum.add(Duration(days: i)),
              abteilung: t.abteilung,
              geplanteDauerMinuten: 10,
              geplanteMitarbeiter: 1,
              parentTaskId: Value(t.parentTaskId ?? t.id),
            ),
          );
    }
  }

  group('Kette und Bezug', () {
    test('bis einschließlich Bratstraße Rohware, danach Fertigware', () async {
      await planen();
      final brat = await auftrag('bratstrasse');
      final m = (await ladeProduktionsMengen(db, brat.id))!;
      final k = m.kette;
      expect(
        k.schritte.map((t) => t.abteilung),
        ['zerlegung', 'wurstkueche', 'bratstrasse', 'verpackung'],
      );
      expect(
        [for (final t in k.schritte) k.bezugVon(t)],
        [
          MengenBezug.rohware,
          MengenBezug.rohware,
          MengenBezug.rohware,
          MengenBezug.fertigware,
        ],
      );
      expect(k.hatBratstrasse, isTrue);
      expect(k.rohKg, 1000);
      expect(k.fertigKg, 800);
      expect(k.fleischKg, isNull);

      expect(m.ausbeute!.wert, closeTo(0.8, 1e-9));
      expect(m.ausbeute!.herkunft, 'wie geplant');
      expect(m.fleischanteil!.wert, closeTo(0.7, 1e-9));
      expect(m.fleischanteil!.herkunft, 'aus der letzten Produktion');
    });

    test('eine abgewählte Bratstraße zählt trotzdem', () async {
      await planen(ohne: {'wurstkueche', 'bratstrasse'});
      final pack = await auftrag('verpackung');
      final k = (await ladeProduktionsMengen(db, pack.id))!.kette;
      expect(k.schritte.map((t) => t.abteilung), ['zerlegung', 'verpackung']);
      expect(k.bezugVon(pack), MengenBezug.fertigware);
      expect(pack.mengeKg, 800);
      expect(k.rohKg, 1000);
    });

    test('ohne Bratstraße im Prozess arbeitet alles mit der Rohware', () async {
      await seedArtikel(db, id: 'p2', nummer: 'T-300');
      await seedSchritt(
        db,
        id: 'q1',
        productId: 'p2',
        reihenfolge: 1,
        abteilung: 'zerlegung',
      );
      await seedSchritt(
        db,
        id: 'q2',
        productId: 'p2',
        reihenfolge: 2,
        abteilung: 'verpackung',
      );
      await planen(productId: 'p2', fertig: 500);
      final pack = (await auftraege('verpackung', productId: 'p2')).single;
      final m = (await ladeProduktionsMengen(db, pack.id))!;
      expect(m.kette.hatBratstrasse, isFalse);
      expect(m.kette.bezugVon(pack), MengenBezug.rohware);
      expect(m.fleischanteil, isNull, reason: 'keine Produktion, Rezeptur');
    });

    test('auf Tage verteilt: Die Rohware zählt alle Teile', () async {
      final wurzelId = await planen();
      await teilen(await auftrag('zerlegung'), [400, 600]);
      final brat = await auftrag('bratstrasse');
      await teilen(brat, [700, 300]);
      final k = (await ladeProduktionsMengen(db, brat.id))!.kette;
      final b = k.schritte.firstWhere((t) => t.id == brat.id);
      expect(k.rohKg, 1000);
      expect(k.teileVon(b), hasLength(2));
      expect(k.stufenMenge(b), 1000);
      expect(k.stufeVon(b), 2);
      expect(
        k.stufeVon(k.schritte.firstWhere((t) => t.id == '$wurzelId-teil1')),
        0,
        reason: 'das Teil der Wurzel bleibt in der ersten Stufe',
      );
    });

    test('auseinandergelaufene Mengen: das Fenster zeigt seinen Auftrag',
        () async {
      // Früher änderte das Fenster nur seinen eigenen Auftrag.
      await planen();
      final brat = await auftrag('bratstrasse');
      await (db.update(db.productionTasks)..where((t) => t.id.equals(brat.id)))
          .write(const ProductionTasksCompanion(mengeKg: Value(900)));
      final k = (await ladeProduktionsMengen(db, brat.id))!.kette;
      expect(k.rohKg, 900);
      final z = (await ladeProduktionsMengen(
        db,
        (await auftrag('zerlegung')).id,
      ))!
          .kette;
      expect(z.rohKg, 1000);

      // Speichern bringt alle Rohware-Schritte wieder auf eine Menge.
      await produktionsMengenSpeichern(
        db,
        k,
        rohKg: 900,
        fertigKg: 720,
        fleischKg: null,
      );
      for (final a in ['zerlegung', 'wurstkueche', 'bratstrasse']) {
        expect((await auftrag(a)).mengeKg, 900, reason: a);
      }
      expect((await auftrag('verpackung')).mengeKg, 720);
    });

    test('ohne geplante Fertigware: die Ausbeute der Produktionen', () async {
      final wurzelId = await planen(mitFertig: false);
      final m = (await ladeProduktionsMengen(db, wurzelId))!;
      expect(m.kette.fertigKg, isNull);
      expect(m.ausbeute!.quelle, VerhaeltnisQuelle.produktionen);
      expect(m.ausbeute!.wert, closeTo(0.8, 1e-9));
      expect(m.ausbeute!.herkunft, 'aus der letzten Produktion');
    });
  });

  group('Speichern', () {
    test(
        'neue Mengen an allen Aufträgen, Fertigware und Fleisch an der '
        'Wurzel, Dauern neu', () async {
      final wurzelId = await planen();
      final brat = await auftrag('bratstrasse');
      final dauerVorher = brat.geplanteDauerMinuten;
      final m = (await ladeProduktionsMengen(db, brat.id))!;
      await produktionsMengenSpeichern(
        db,
        m.kette,
        rohKg: 1200,
        fertigKg: 960,
        fleischKg: 840,
      );

      for (final a in ['zerlegung', 'wurstkueche', 'bratstrasse']) {
        expect((await auftrag(a)).mengeKg, 1200, reason: a);
      }
      expect((await auftrag('verpackung')).mengeKg, 960);
      final wurzel = await lies(wurzelId);
      expect(wurzel.fertigMengeKg, 960);
      expect(wurzel.fleischMengeKg, 840);

      final nachher = await auftrag('bratstrasse');
      final modell = (await ladeAbteilungsDauerModell(
        db,
        productId: 'p1',
        abteilung: 'bratstrasse',
      ))!;
      expect(
        nachher.geplanteDauerMinuten,
        modell.dauerFuer(1200).minuten.roundToDouble(),
      );
      expect(nachher.geplanteDauerMinuten, greaterThan(dauerVorher));
    });

    test('auf Tage verteilte Teile behalten ihr Verhältnis', () async {
      await planen();
      await teilen(await auftrag('zerlegung'), [400, 600]);
      final brat = await auftrag('bratstrasse');
      await teilen(brat, [700, 300]);
      final k = (await ladeProduktionsMengen(db, brat.id))!.kette;
      await produktionsMengenSpeichern(
        db,
        k,
        rohKg: 1500,
        fertigKg: 1200,
        fleischKg: null,
      );
      expect(
        (await auftraege('zerlegung')).map((t) => t.mengeKg),
        [600, 900],
      );
      expect(
        (await auftraege('bratstrasse')).map((t) => t.mengeKg),
        [1050, 450],
      );
      expect((await auftrag('verpackung')).mengeKg, 1200);
    });

    test('ohne Fertigware gehen die Fertigware-Schritte mit der Rohware',
        () async {
      final wurzelId = await planen(mitFertig: false);
      final k = (await ladeProduktionsMengen(db, wurzelId))!.kette;
      await produktionsMengenSpeichern(
        db,
        k,
        rohKg: 1200,
        fertigKg: null,
        fleischKg: null,
      );
      expect((await auftrag('verpackung')).mengeKg, closeTo(960, 1e-9));
      expect((await lies(wurzelId)).fertigMengeKg, 0);
    });

    test('nur die Fleischeinwaage geändert: nur die Wurzel', () async {
      final wurzelId = await planen();
      final vorher = await db.select(db.productionTasks).get();
      final k = (await ladeProduktionsMengen(db, wurzelId))!.kette;
      await produktionsMengenSpeichern(
        db,
        k,
        rohKg: 1000,
        fertigKg: 800,
        fleischKg: 650,
      );
      final nachher = await db.select(db.productionTasks).get();
      for (final t in vorher) {
        final n = nachher.singleWhere((x) => x.id == t.id);
        expect(n.mengeKg, t.mengeKg);
        expect(n.geplanteDauerMinuten, t.geplanteDauerMinuten);
      }
      expect((await lies(wurzelId)).fleischMengeKg, 650);
    });

    test('der Auftrag des Fensters bekommt seine Dauer und Angaben', () async {
      await planen();
      final brat = await auftrag('bratstrasse');
      final k = (await ladeProduktionsMengen(db, brat.id))!.kette;
      await produktionsMengenSpeichern(
        db,
        k,
        rohKg: 1100,
        fertigKg: 880,
        fleischKg: 770,
        auftragId: brat.id,
        auftrag: const ProductionTasksCompanion(
          geplanteDauerMinuten: Value(123),
          geplanteMitarbeiter: Value(3),
          startZeit: Value('06:30'),
          notizen: Value('Anlage vorheizen'),
        ),
      );
      final b = await lies(brat.id);
      expect(b.mengeKg, 1100);
      expect(b.geplanteDauerMinuten, 123);
      expect(b.geplanteMitarbeiter, 3);
      expect(b.startZeit, '06:30');
      expect(b.notizen, 'Anlage vorheizen');
      final z = await auftrag('zerlegung');
      expect(z.mengeKg, 1100);
      expect(z.startZeit, isNull);
    });

    test('eine gelöschte Wurzel trägt weiter Fertigware und Fleisch', () async {
      final wurzelId = await planen();
      await (db.update(db.productionTasks)..where((t) => t.id.equals(wurzelId)))
          .write(ProductionTasksCompanion(deletedAt: Value(DateTime.now())));
      final brat = await auftrag('bratstrasse');
      final k = (await ladeProduktionsMengen(db, brat.id))!.kette;
      expect(k.wurzel.id, wurzelId);
      expect(k.schritte.map((t) => t.abteilung), isNot(contains('zerlegung')));
      expect(k.rohKg, 1000);
      await produktionsMengenSpeichern(
        db,
        k,
        rohKg: 1000,
        fertigKg: 800,
        fleischKg: 700,
      );
      expect((await lies(wurzelId)).fleischMengeKg, 700);
    });
  });

  group('Felder im Fenster', () {
    test('füllen sich aus der Planung und rechnen gegenseitig mit', () async {
      await planen();
      final pack = await auftrag('verpackung');
      final e = MengenEingabe((await ladeProduktionsMengen(db, pack.id))!);
      expect([e.roh, e.fertig, e.fleisch], ['1000', '800', '700']);
      expect([e.verlust, e.anteil], ['20', '70']);
      expect(e.verlustHerkunft, 'wie geplant');
      expect(e.anteilHerkunft, 'aus der letzten Produktion');

      e.setzeRoh('1200');
      expect([e.fertig, e.fleisch], ['960', '840']);
      expect(e.auftragsMenge(pack), closeTo(960, 1e-9));

      e.setzeFertig('880');
      expect([e.roh, e.fleisch], ['1100', '770']);

      e.setzeFleisch('560');
      expect([e.roh, e.fertig], ['800', '640']);

      // Ein anderer Verlust: Die Rohware bleibt, die Fertigware folgt.
      e.setzeVerlust('25');
      expect([e.roh, e.fertig], ['800', '600']);
      expect(e.verlustHerkunft, 'von Hand');

      e.setzeAnteil('50');
      expect([e.roh, e.fleisch], ['800', '400']);
      expect(e.gueltig, isTrue);
      expect((e.rohKg, e.fertigKg, e.fleischKg), (800, 600, 400));
    });

    test('unberührt genau wie geplant — nicht auf 0,1 kg gerundet', () async {
      // 333 kg Fertigware bei 80 % Ausbeute: gut 416,2 kg Rohware.
      final wurzelId = await planen(fertig: 333);
      final wurst = await auftrag('wurstkueche');
      final roh = wurst.mengeKg;
      final m = (await ladeProduktionsMengen(db, wurst.id))!;
      final e = MengenEingabe(m);
      expect(Format.lies(e.roh), isNot(roh), reason: 'Im Feld gerundet');
      expect(e.rohKg, roh);
      expect(e.fertigKg, 333);
      expect(e.fleischKg, closeTo(roh * 0.7, 1e-9));
      expect(e.auftragsMenge(wurst), roh);
      expect(e.geaendert, isFalse);

      // Nur der Fleischanteil: Rohware und Fertigware bleiben genau — kein
      // Auftrag bekommt eine andere Menge oder Dauer.
      e.setzeAnteil('60');
      expect(e.geaendert, isTrue);
      expect(e.rohKg, roh);
      final vorher = {
        for (final t in await db.select(db.productionTasks).get()) t.id: t,
      };
      await produktionsMengenSpeichern(
        db,
        m.kette,
        rohKg: e.rohKg,
        fertigKg: e.fertigKg,
        fleischKg: e.fleischKg,
      );
      for (final t in await db.select(db.productionTasks).get()) {
        final v = vorher[t.id]!;
        expect(t.mengeKg, v.mengeKg, reason: t.abteilung);
        expect(
          t.geplanteDauerMinuten,
          v.geplanteDauerMinuten,
          reason: t.abteilung,
        );
      }
      final w = await lies(wurzelId);
      expect(w.fertigMengeKg, 333);
      // Die neue Fleischeinwaage, wie sie im Feld steht.
      expect(w.fleischMengeKg, e.fleischKg);
      expect(w.fleischMengeKg, closeTo(roh * 0.6, 0.06));

      // Zurückgetippt ist nichts mehr geändert.
      e.setzeAnteil('70');
      expect(e.geaendert, isFalse);
    });

    test('ohne Verhältnis legt die Menge es fest', () async {
      await seedArtikel(db, id: 'p2', nummer: 'T-300');
      await seedSchritt(
        db,
        id: 'q1',
        productId: 'p2',
        reihenfolge: 1,
        abteilung: 'bratstrasse',
      );
      final wurzelId =
          await planen(productId: 'p2', fertig: 500, mitFertig: false);
      final e = MengenEingabe((await ladeProduktionsMengen(db, wurzelId))!);
      expect([e.roh, e.fertig, e.fleisch], ['500', '', '']);
      expect([e.verlust, e.anteil], ['', '']);
      expect(e.verlustHerkunft, isNull);

      // Die Fertigware ergibt den Verlust — auch beim Weitertippen.
      e.setzeFertig('4');
      e.setzeFertig('45');
      e.setzeFertig('450');
      expect(e.roh, '500');
      expect(e.verlust, '10');
      expect(e.verlustHerkunft, 'von Hand');

      // Danach zieht die Rohware die Fertigware mit.
      e.setzeRoh('600');
      expect(e.fertig, '540');

      e.setzeFleisch('300');
      expect(e.anteil, '50');
      expect(e.roh, '600');
    });

    test('prüfen, was sich nicht speichern lässt', () async {
      await planen();
      final e = MengenEingabe(
        (await ladeProduktionsMengen(db, (await auftrag('zerlegung')).id))!,
      );
      e.setzeVerlust('');
      e.setzeFertig('1100');
      expect(e.fertigFehler, startsWith('Mehr Fertigware als Rohware'));
      expect(e.gueltig, isFalse);
      e.setzeFertig('900');
      e.setzeFleisch('');
      e.setzeAnteil('');
      e.setzeFleisch('1200');
      expect(e.fleischFehler, startsWith('Mehr Fleisch als Rohware'));
      e.setzeFleisch('');
      expect(e.gueltig, isTrue);
      e.setzeRoh('');
      expect(e.rohFehler, 'Bitte die Rohware eintragen.');
      e.setzeRoh('1000');
      e.setzeVerlust('100');
      expect(e.verlustFehler, isNotNull);
      e.setzeVerlust('10');
      e.setzeAnteil('0');
      expect(e.anteilFehler, isNotNull);
      e.setzeAnteil('');
      expect(e.gueltig, isTrue);
    });
  });

  group('Fleischanteil und Ausbeute ohne Planung', () {
    test('Ø der Produktionen; mehr Fleisch als Rohware zählt nicht', () async {
      for (final (roh, fleisch) in [
        (1000.0, 600.0),
        (500.0, null),
        (100.0, 150.0),
      ]) {
        await ProduktionErfassenService.speichere(
          db: db,
          productId: 'p1',
          datum: DateTime(2026, 10, 2),
          kgRohware: roh,
          kgFleischeinwaage: fleisch,
        );
      }
      final a = (await fleischanteilFuer(db, 'p1'))!;
      expect(a.wert, closeTo(0.65, 1e-9));
      expect(a.anzahl, 2);
      expect(a.herkunft, 'Ø der letzten 2 Produktionen');
    });

    test('ohne Produktionen aus der freigegebenen Rezeptur', () async {
      await seedArtikel(db, id: 'p3', nummer: 'T-400');
      await db.into(db.entwicklungZutaten).insert(
            EntwicklungZutatenCompanion.insert(
              id: 'z-fleisch',
              name: 'Schweinebauch',
              istFleisch: const Value(true),
              tierart: const Value('schwein'),
            ),
          );
      await db.into(db.entwicklungZutaten).insert(
            EntwicklungZutatenCompanion.insert(
              id: 'z-salz',
              name: 'Speisesalz',
            ),
          );
      await db.into(db.entwicklungRezepturen).insert(
            EntwicklungRezepturenCompanion.insert(id: 'r1', name: 'Testwurst'),
          );
      await db.into(db.entwicklungRezepturVersionen).insert(
            EntwicklungRezepturVersionenCompanion.insert(
              id: 'v1',
              rezepturId: 'r1',
              nummer: 1,
              verlustProzent: const Value(10),
              verlustArt: const Value('garen'),
            ),
          );
      for (final (id, zutat, kg) in [
        ('pos1', 'z-fleisch', 60.0),
        ('pos2', 'z-salz', 40.0),
      ]) {
        await db.into(db.entwicklungRezepturPositionen).insert(
              EntwicklungRezepturPositionenCompanion.insert(
                id: id,
                versionId: 'v1',
                zutatId: Value(zutat),
                mengeKg: Value(kg),
              ),
            );
      }
      await db.into(db.entwicklungProjekte).insert(
            EntwicklungProjekteCompanion.insert(
              id: 'pr1',
              name: 'Testwurst',
              artikelId: const Value('p3'),
              freigabeVersionId: const Value('v1'),
              freigegebenAm: Value(DateTime(2026, 10, 20)),
            ),
          );

      final anteil = (await fleischanteilFuer(db, 'p3'))!;
      expect(anteil.wert, closeTo(0.6, 1e-9));
      expect(anteil.herkunft, 'aus der Rezeptur');
      final ausbeute = (await ausbeuteFuer(db, 'p3'))!;
      expect(ausbeute.wert, closeTo(0.9, 1e-9));
      expect(ausbeute.quelle, VerhaeltnisQuelle.rezeptur);
    });
  });

  group('Produktionserfassung', () {
    Future<List<GeplanteProduktion>> woche() async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          erfassungWocheProvider.overrideWith((ref) => montag),
        ],
      );
      addTearDown(container.dispose);
      final tage = await container.read(erfassungWocheDatenProvider.future);
      return [for (final liste in tage.values) ...liste];
    }

    test('vorgeschlagen: Rohware aller Teile und die Fleischeinwaage',
        () async {
      final wurzelId = await planen();
      await (db.update(db.productionTasks)
            ..where((t) => t.id.equals(wurzelId)))
          .write(const ProductionTasksCompanion(fleischMengeKg: Value(700)));
      // Der erste Schritt auf drei Tage verteilt, einer davon storniert.
      await teilen(await lies(wurzelId), [400, 300, 300, 100]);
      await (db.update(db.productionTasks)
            ..where((t) => t.id.equals('$wurzelId-teil3')))
          .write(const ProductionTasksCompanion(status: Value('storniert')));

      final p = (await woche()).single;
      expect(p.task.id, wurzelId, reason: 'Nur die Wurzel wird erfasst');
      expect(p.rohKg, 1000);
      expect(p.fertigKg, 800);
      expect(p.fleischKg, 700);
      expect(
        erfassungPlanText(p),
        startsWith('Plan: 1.000 kg Rohware · 800 kg Fertigware · '
            '700 kg Fleisch'),
      );
    });

    test('ohne Fertigware und Fleischeinwaage: nur die Rohware', () async {
      await planen(mitFertig: false);
      final p = (await woche()).single;
      expect(p.rohKg, 1000);
      expect(p.fertigKg, isNull);
      expect(p.fleischKg, isNull);
      expect(p.mengeKg, 1000);
    });
  });
}
