import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/planung/wochenliste.dart';

import 'helpers/test_db.dart';

/// Tests für die Wochenliste: Umrechnung zwischen Rohware,
/// Fleischeinwaage und Fertigware, die kleine Rechnung im Mengenfeld,
/// Speichern als Bedarf und die Dauer je Abteilung. Alle Daten erfunden.
void main() {
  group('Mengen umrechnen', () {
    test('Fertigware: Rohware und Fleisch zurückgerechnet', () {
      final m = rechneMengen(
        MengenFeld.fertig,
        80,
        ausbeute: 0.8,
        fleischanteil: 0.7,
      );
      expect(m.fertig, 80);
      expect(m.roh, closeTo(100, 1e-9));
      expect(m.fleisch, closeTo(70, 1e-9));
      expect(m.planbar, isTrue);
      expect(m.fehlt, isNull);
    });

    test('Rohware: Fertigware über die Ausbeute', () {
      final m = rechneMengen(
        MengenFeld.roh,
        270,
        ausbeute: 0.8,
        fleischanteil: 0.5,
      );
      expect(m.fertig, closeTo(216, 1e-9));
      expect(m.fleisch, closeTo(135, 1e-9));
    });

    test('Fleischeinwaage: erst Rohware, dann Fertigware', () {
      final m = rechneMengen(
        MengenFeld.fleisch,
        70,
        ausbeute: 0.8,
        fleischanteil: 0.7,
      );
      expect(m.roh, closeTo(100, 1e-9));
      expect(m.fertig, closeTo(80, 1e-9));
    });

    test('ohne Ausbeute oder Fleischanteil wird nichts geraten', () {
      final roh = rechneMengen(MengenFeld.roh, 100);
      expect(roh.planbar, isFalse);
      expect(roh.fehlt, contains('Ausbeute'));

      final fleisch = rechneMengen(MengenFeld.fleisch, 70, ausbeute: 0.8);
      expect(fleisch.planbar, isFalse);
      expect(fleisch.roh, isNull);
      expect(fleisch.fehlt, contains('Fleischanteil'));

      // Fertigware geht immer — die Planung rechnet die Rohware dann eins
      // zu eins, wie bei jedem Bedarf.
      final fertig = rechneMengen(MengenFeld.fertig, 50);
      expect(fertig.planbar, isTrue);
      expect(fertig.roh, isNull);
    });
  });

  group('Rechnen im Mengenfeld', () {
    test('Zahlen und Punkt vor Strich', () {
      expect(rechneMenge('270'), 270);
      expect(rechneMenge('270,5'), 270.5);
      expect(rechneMenge('1.200'), 1200);
      expect(rechneMenge('2.5'), 2.5);
      expect(rechneMenge('27*10'), 270);
      expect(rechneMenge('27 x 10'), 270);
      expect(rechneMenge('100+80*2'), 260);
      expect(rechneMenge('300-50/2'), 275);
    });

    test('Unsinn ergibt null', () {
      for (final t in ['', 'abc', '10/0', '5*', '*5', '1..2', '12kg']) {
        expect(rechneMenge(t), isNull, reason: t);
      }
    });
  });

  group('Eingaben in den Einstellungen', () {
    test('hin und zurück, Unlesbares fällt weg', () {
      final text = eingabenAlsText({
        'a': const WochenEingabe(feld: MengenFeld.roh, kg: 270, fertigKg: 216),
      });
      final zurueck = eingabenAusText(text);
      expect(zurueck['a']!.feld, MengenFeld.roh);
      expect(zurueck['a']!.kg, 270);
      expect(zurueck['a']!.fertigKg, 216);

      expect(eingabenAusText('kein json'), isEmpty);
      expect(
        eingabenAusText('{"x":{"feld":"quark","kg":1,"fertig":1}}'),
        isEmpty,
      );
    });
  });

  group('Zeilen speichern', () {
    late AppDatabase db;
    late WochenlisteService dienst;
    final mittwoch = DateTime(2026, 10, 7);

    setUp(() async {
      db = testDatenbank();
      dienst = WochenlisteService(db);
      await seedArtikel(db, id: 'p1', nummer: '9101');
      await seedArtikel(db, id: 'p2', nummer: '9102');
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
        basisDauerMinuten: 30,
      );
      // Eine erfasste Produktion: 100 kg Rohware, 80 kg Fertigware,
      // 70 kg Fleisch.
      await db.into(db.productionHistory).insert(
            ProductionHistoryCompanion.insert(
              id: 'h1',
              productId: 'p1',
              datum: DateTime(2026, 9, 1),
              kgRohware: const Value(100),
              kgFertigware: const Value(80),
              kgFleischeinwaage: const Value(70),
            ),
          );
    });
    tearDown(() => db.close());

    test('eine Zeile wird ein Bedarf aus der Wochenliste', () async {
      final v = await dienst.verhaeltnisse('p1');
      expect(v.ausbeute!.wert, closeTo(0.8, 1e-9));
      expect(v.fleischanteil!.wert, closeTo(0.7, 1e-9));
      final m = v.rechne(MengenFeld.roh, 270);

      final id = await dienst.speichere(
        productId: 'p1',
        wunschtag: mittwoch.add(const Duration(hours: 9)),
        feld: MengenFeld.roh,
        kg: 270,
        fertigKg: m.fertig!,
      );
      final bedarf = await (db.select(db.demands)
            ..where((d) => d.id.equals(id)))
          .getSingle();
      expect(bedarf.quelle, kQuelleWochenliste);
      expect(bedarf.mengeKgFertig, closeTo(216, 1e-9));
      // Der Wunschtag ohne Uhrzeit.
      expect(bedarf.termin, mittwoch);

      final zeilen = await dienst.lade();
      expect(zeilen.single.feld, MengenFeld.roh);
      expect(zeilen.single.kg, 270);
      expect(zeilen.single.artikelnummer, '9101');
      expect(zeilen.single.wunschtag, mittwoch);
    });

    test('Wunschtag zuerst, ohne Wunschtag zuletzt — andere Bedarfe nicht',
        () async {
      await dienst.speichere(
        productId: 'p2',
        wunschtag: null,
        feld: MengenFeld.fertig,
        kg: 50,
        fertigKg: 50,
      );
      await dienst.speichere(
        productId: 'p1',
        wunschtag: mittwoch,
        feld: MengenFeld.fertig,
        kg: 80,
        fertigKg: 80,
      );
      await seedBedarf(db, id: 'fremd', productId: 'p1', mengeKgFertig: 10);

      final zeilen = await dienst.lade();
      expect([for (final z in zeilen) z.artikelnummer], ['9101', '9102']);
    });

    test('in der Bedarfsliste geändert: dann gilt die Fertigware', () async {
      final id = await dienst.speichere(
        productId: 'p1',
        wunschtag: mittwoch,
        feld: MengenFeld.roh,
        kg: 100,
        fertigKg: 80,
      );
      await (db.update(db.demands)..where((d) => d.id.equals(id)))
          .write(const DemandsCompanion(mengeKgFertig: Value(120)));
      final z = (await dienst.lade()).single;
      expect(z.feld, MengenFeld.fertig);
      expect(z.kg, 120);
    });

    test('ändern, ganz im Board, löschen', () async {
      final id = await dienst.speichere(
        productId: 'p1',
        wunschtag: mittwoch,
        feld: MengenFeld.fertig,
        kg: 80,
        fertigKg: 80,
      );
      await dienst.speichere(
        bedarfId: id,
        productId: 'p1',
        wunschtag: null,
        feld: MengenFeld.fleisch,
        kg: 140,
        fertigKg: 160,
      );
      var z = (await dienst.lade()).single;
      expect(z.feld, MengenFeld.fleisch);
      expect((z.kg, z.fertigKg), (140.0, 160.0));
      expect(z.wunschtag, isNull);

      // Halb im Board: bleibt stehen und sagt, wie viel schon drin ist.
      Future<void> kette(String tid, double kg) =>
          db.into(db.productionTasks).insert(
                ProductionTasksCompanion.insert(
                  id: tid,
                  productId: 'p1',
                  mengeKg: kg,
                  datum: mittwoch,
                  abteilung: 'bratstrasse',
                  geplanteDauerMinuten: 60,
                  geplanteMitarbeiter: 2,
                  bedarfId: Value(id),
                  fertigMengeKg: Value(kg),
                ),
              );
      await kette('t1', 100);
      z = (await dienst.lade()).single;
      expect(z.imBoardKg, 100);

      // Ganz im Board: nicht mehr in der Liste.
      await kette('t2', 60);
      expect(await dienst.lade(), isEmpty);

      // Gelöscht: der Bedarf ist weg, die Eingabe auch.
      await dienst.loesche(id);
      final b = await (db.select(db.demands)..where((d) => d.id.equals(id)))
          .getSingle();
      expect(b.deletedAt, isNotNull);
      final s = await (db.select(db.appSettings)
            ..where((s) => s.key.equals(kWochenlisteEingabenSchluessel)))
          .getSingle();
      expect(eingabenAusText(s.value), isEmpty);
    });

    test('Dauer je Abteilung wie im Planungsvorschlag', () async {
      // 80 kg Fertigware = 100 kg Rohware durch die Bratstraße
      // (100 kg je Stunde), dann 80 kg in die Verpackung (100 kg in 30 min).
      final d = await dienst.dauer('p1', 80);
      expect(d.minuten.keys, [Abteilung.bratstrasse, Abteilung.verpackung]);
      expect(d.minuten[Abteilung.bratstrasse], 60);
      expect(d.minuten[Abteilung.verpackung], 24);
      expect(d.gesamt, 84);
      expect(d.geschaetzt, isFalse);

      final summe = summeJeAbteilung([d, d]);
      expect(summe[Abteilung.bratstrasse], 120);
      expect(summe[Abteilung.verpackung], 48);
      expect((await dienst.dauer('p1', 0)).minuten, isEmpty);
    });
  });
}
