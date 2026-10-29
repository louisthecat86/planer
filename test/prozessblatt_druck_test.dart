import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_optionen.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';
import 'package:produktion_planer/features/articles/prozessblatt_druck.dart';

import 'helpers/test_db.dart';

/// Tests für das Prozessblatt: welche Abteilungen und Schritte, eigene
/// Seiten je Abteilung und was je Anlage darauf steht. Alle Daten sind
/// erfunden; gelesen wird das unkomprimierte PDF, Wort für Wort.
void main() {
  late AppDatabase db;
  late ProzessblattDaten daten;
  final gedruckt = DateTime(2026, 10, 29, 9, 15);

  Future<void> parameter(
    String id,
    String stepId,
    String gruppe,
    String name,
    String wert,
  ) =>
      db.into(db.productStepParameters).insert(
            ProductStepParametersCompanion.insert(
              id: id,
              stepId: stepId,
              parameterGruppe: gruppe,
              parameterName: name,
              wert: Value(wert),
            ),
          );

  setUp(() async {
    db = testDatenbank();
    await seedArtikel(
      db,
      id: 'p1',
      nummer: '47110',
      bezeichnung: 'Testfrikadelle 80 g',
    );
    await seedAnlage(db, id: 'k1', name: 'Kutter K1', abteilung: 'wurstkueche');
    await seedAnlage(
      db,
      id: 'b1',
      name: 'Bratstraße 1',
      abteilung: 'bratstrasse',
    );
    await seedSchritt(
      db,
      id: 's1',
      productId: 'p1',
      reihenfolge: 1,
      abteilung: 'wurstkueche',
      maschineId: 'k1',
      prozessschritt: 'Kuttern',
      basisMengeKg: 600,
      basisDauerMinuten: 60,
    );
    await seedSchritt(
      db,
      id: 's2',
      productId: 'p1',
      reihenfolge: 2,
      abteilung: 'bratstrasse',
      maschineId: 'b1',
      prozessschritt: 'Braten',
    );
    await parameter('a', 's1', 'KUTTER', 'Drehzahl', '3000');
    await parameter(
      'b',
      's1',
      'MASCHINENEINSTELLUNGEN',
      'Maschineneinstellungen',
      'Messer frisch geschliffen',
    );
    await parameter('c', 's2', 'BRATSTRASSE', 'Plattenschema', 'bratstrasse');
    await parameter('d', 's2', 'BRATSTRASSE', 'Platte Oben 1', '235');
    await parameter('e', 's2', 'BRATSTRASSE', 'Bandgeschwindigkeit', '4,5');

    final produkt = await (db.select(db.products)
          ..where((p) => p.id.equals('p1')))
        .getSingle();
    final schritte = await (db.select(db.productSteps)
          ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
        .get();
    final alle = await db.select(db.productStepParameters).get();
    final maschinen = await db.select(db.machines).get();
    daten = ProzessblattDaten(
      produkt: produkt,
      schritte: schritte,
      parameter: {
        for (final s in schritte)
          s.id: [
            for (final p in alle)
              if (p.stepId == s.id) p,
          ],
      },
      maschinen: {
        for (final s in schritte)
          s.id: maschinen.where((m) => m.id == s.maschineId).firstOrNull,
      },
    );
  });

  tearDown(() => db.close());

  Future<(DruckErgebnis, String)> setze(
    DruckDokument dokument, [
    DruckLayout layout = const DruckLayout(),
  ]) async {
    final e = await druckSetzen(dokument, layout, komprimiert: false);
    return (e, latin1.decode(e.bytes));
  }

  test('alles: Kopf, Bänder, Anlagen, Raster, Parameter', () async {
    final (e, t) = await setze(prozessblattDruck(daten, gedrucktAm: gedruckt));
    expect(e.blaetter, 1);
    for (final wort in [
      '47110',
      'Testfrikadelle',
      'Prozessblatt',
      '29.10.2026',
      'Wurstküche',
      'Bratstraße',
      'Leistung:',
      '600',
      'Kutter',
      'Kuttern',
      'Personen',
      'Drehzahl',
      '3000',
      'MASCHINENEINSTELLUNGEN',
      'geschliffen',
      'Laufrichtung',
      '235',
      'Bandgeschwindigkeit',
      '4,5',
    ]) {
      expect(t, contains('($wort)'), reason: wort);
    }
    // Die Platten stehen im Raster, nicht in der Parameterliste.
    expect(t, isNot(contains('(Plattenschema)')));
  });

  test('nur eine Abteilung, auf eigener Seite', () async {
    final dokument = prozessblattDruck(
      daten,
      inhalt: const ProzessblattInhalt(
        abteilungen: {'bratstrasse'},
        eigeneSeiten: true,
      ),
    );
    final (e, t) = await setze(dokument);
    expect(e.blaetter, 1);
    expect(t, contains('(Braten)'));
    expect(t, isNot(contains('(Kuttern)')));
    expect(dokument.dateiname, 'Prozessblatt_47110_Bratstrasse');
  });

  test('jede Abteilung auf eigener Seite: zwei Blätter mit Kopf', () async {
    final (e, t) = await setze(
      prozessblattDruck(
        daten,
        inhalt: const ProzessblattInhalt(eigeneSeiten: true),
      ),
    );
    expect(e.blattSeiten, [1, 1]);
    expect(RegExp(r'\(Testfrikadelle\)').allMatches(t), hasLength(2));
  });

  test('ohne Raster, Parameter, Einstellungen und Leistung', () async {
    final (_, t) = await setze(
      prozessblattDruck(
        daten,
        inhalt: const ProzessblattInhalt(
          platten: false,
          parameter: false,
          einstellungen: false,
          leistung: false,
          kennwerte: false,
        ),
      ),
    );
    expect(t, contains('(Kuttern)'));
    for (final wort in [
      'Laufrichtung',
      'Drehzahl',
      'geschliffen',
      'Leistung:',
      'Personen',
    ]) {
      expect(t, isNot(contains('($wort)')), reason: wort);
    }
  });

  test('Platz für Notizen von Hand', () async {
    final (_, ohne) = await setze(prozessblattDruck(daten));
    final (_, mit) = await setze(
      prozessblattDruck(
        daten,
        inhalt: const ProzessblattInhalt(notizfeld: true),
      ),
    );
    expect(ohne, isNot(contains('(NOTIZEN)')));
    expect(RegExp(r'\(NOTIZEN\)').allMatches(mit), hasLength(2));
  });

  group('Wahl im Druckfenster', () {
    test('vorgewählt ist alles, gemerkt werden nur die Inhalte', () {
      final a = prozessblattDruckAuftrag(daten);
      final wahl = DruckWahl.standard(a.optionen);
      expect(wahl.mehrere('abteilungen'), {'wurstkueche', 'bratstrasse'});
      expect(wahl.mehrere('schritte'), {'s1', 's2'});
      expect(wahl.an('eigeneSeiten'), isFalse);
      expect(wahl.an('notizfeld'), isFalse);
      final json = wahl.toJson(a.optionen);
      expect(json['werte'], isNot(contains('abteilungen')));
      expect(json['werte'], isNot(contains('schritte')));
      expect(json['werte'], contains('platten'));
    });

    test('Schritte abwählen, nichts gewählt sagt, was fehlt', () async {
      final a = prozessblattDruckAuftrag(daten, gedrucktAm: gedruckt);
      final wahl = DruckWahl.standard(a.optionen);

      final (_, t) = await setze(await a.bauen(wahl.mit('schritte', {'s2'})));
      expect(t, contains('(Braten)'));
      expect(t, isNot(contains('(Kuttern)')));
      expect(t, isNot(contains('(Wurstküche)')));

      expect(
        () => a.bauen(wahl.mit('abteilungen', <String>{})),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
      expect(
        () => a.bauen(
          wahl.mit('abteilungen', {'wurstkueche'}).mit('schritte', {'s2'}),
        ),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
    });

    test('alles auf eine Seite', () async {
      final a = prozessblattDruckAuftrag(daten);
      final (e, _) = await setze(
        await a.bauen(DruckWahl.standard(a.optionen)),
        const DruckLayout(anpassung: DruckAnpassung.eineSeite),
      );
      expect(e.seiten, 1);
    });
  });
}
