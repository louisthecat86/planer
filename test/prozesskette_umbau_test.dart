import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/prozesskette_service.dart';
import 'package:produktion_planer/features/articles/prozesskette_umbau.dart';
import 'package:produktion_planer/features/whiteboard/whiteboard_provider.dart'
    show leistungsdatenVon;

import 'helpers/test_db.dart';

/// Tests für das Ziehen und Ablegen in der Prozesskette: was ein Zug auf
/// einem Ziel an der Kette ändert — und dass es so in der Datenbank
/// ankommt. Alle Daten sind erfunden.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = testDatenbank();
    await seedArtikel(db, id: 'p1', nummer: '3001');
    await seedAnlage(
      db,
      id: 'm1',
      name: 'Rollenschneider',
      abteilung: 'zerlegung',
    );
    // Zerlegung (z1, z2) → Bratstraße (b1, b2) → Verpackung (v1). z1 ist
    // der Rollenschneider aus dem Katalog der Zerlegung.
    const schritte = [
      ('z1', 'zerlegung'),
      ('z2', 'zerlegung'),
      ('b1', 'bratstrasse'),
      ('b2', 'bratstrasse'),
      ('v1', 'verpackung'),
    ];
    for (var i = 0; i < schritte.length; i++) {
      await seedSchritt(
        db,
        id: schritte[i].$1,
        productId: 'p1',
        reihenfolge: i + 1,
        abteilung: schritte[i].$2,
        basisMengeKg: 0,
        basisDauerMinuten: 0,
        maschineId: schritte[i].$1 == 'z1' ? 'm1' : null,
      );
    }
  });
  tearDown(() => db.close());

  Future<Kettenbau> kette() async => Kettenbau(
        productId: 'p1',
        steps: await ProzesskettenService.schritte(db, 'p1'),
      );

  ProductStep s(Kettenbau k, String id) =>
      k.steps.firstWhere((x) => x.id == id);

  Future<Machine> anlage(String id) =>
      (db.select(db.machines)..where((m) => m.id.equals(id))).getSingle();

  /// Die Kette als „id:abteilung" — ein eingefügter Schritt heißt „neu".
  Future<List<String>> stand() async {
    const bekannt = {'z1', 'z2', 'b1', 'b2', 'v1'};
    return [
      for (final x in await ProzesskettenService.schritte(db, 'p1'))
        '${bekannt.contains(x.id) ? x.id : 'neu'}:${x.abteilung}',
    ];
  }

  /// Zieht [zug] auf [ziel], schreibt das Ergebnis und gibt es zurück.
  Future<KettenUmbau> ziehe(
    Kettenbau k,
    KettenZug zug,
    KettenZiel ziel,
  ) async {
    final umbau = k.umbau(zug, ziel);
    expect(umbau, isNotNull, reason: 'Das Ziel nimmt den Zug an');
    await k.schreibe(db, umbau!);
    return umbau;
  }

  List<String>? ids(KettenUmbau? u) => u is NeueAbfolge ? u.ids : null;

  test('innerhalb einer Station: nach rechts gezogen hinter das Ziel, nach '
      'links davor', () async {
    final k = await kette();

    final rechts = k.umbau(SchrittZug(s(k, 'z1')), ZielAnlage(s(k, 'z2'), 0));
    final links = k.umbau(SchrittZug(s(k, 'b2')), ZielAnlage(s(k, 'b1'), 1));

    expect(ids(rechts), ['z2', 'z1', 'b1', 'b2', 'v1']);
    expect(ids(links), ['z1', 'z2', 'b2', 'b1', 'v1']);
    expect((rechts! as NeueAbfolge).abteilungen, isEmpty);
  });

  test('wo sich nichts ändert, nimmt das Ziel den Zug nicht an', () async {
    final k = await kette();
    final z1 = SchrittZug(s(k, 'z1'));
    final z2 = SchrittZug(s(k, 'z2'));

    expect(k.umbau(z1, ZielAnlage(s(k, 'z1'), 0)), isNull);
    expect(
      k.umbau(z2, const ZielStation(0)),
      isNull,
      reason: 'z2 ist schon die letzte Anlage ihrer Station',
    );
    expect(k.umbau(z1, const ZielLuecke(0)), isNull);
    expect(k.umbau(z2, const ZielLuecke(1)), isNull);
    expect(k.umbau(const StationsZug(1), const ZielStation(1)), isNull);
    expect(k.umbau(const StationsZug(1), const ZielLuecke(1)), isNull);
    expect(k.umbau(const StationsZug(1), const ZielLuecke(2)), isNull);
  });

  test('in eine andere Station gezogen, arbeitet die Anlage für deren '
      'Abteilung — im Katalog bleibt sie in ihrer', () async {
    final k = await kette();

    final umbau =
        await ziehe(k, SchrittZug(s(k, 'z1')), ZielAnlage(s(k, 'b2'), 1));

    expect((umbau as NeueAbfolge).abteilungen, {'z1': 'bratstrasse'});
    expect(await stand(), [
      'z2:zerlegung',
      'b1:bratstrasse',
      'z1:bratstrasse',
      'b2:bratstrasse',
      'v1:verpackung',
    ]);
    expect((await anlage('m1')).abteilung, 'zerlegung');
  });

  test('auf eine Station gezogen, kommt die Anlage an ihr Ende', () async {
    final k = await kette();

    await ziehe(k, SchrittZug(s(k, 'v1')), const ZielStation(0));

    expect(await stand(), [
      'z1:zerlegung',
      'z2:zerlegung',
      'v1:zerlegung',
      'b1:bratstrasse',
      'b2:bratstrasse',
    ]);
  });

  test('in eine Lücke gezogen, behält die Anlage ihre Abteilung und wird '
      'eine eigene Station', () async {
    final k = await kette();

    await ziehe(k, SchrittZug(s(k, 'z1')), const ZielLuecke(2));

    expect(await stand(), [
      'z2:zerlegung',
      'b1:bratstrasse',
      'b2:bratstrasse',
      'z1:zerlegung',
      'v1:verpackung',
    ]);
    expect((await kette()).stationen, hasLength(4));
  });

  test('eine Station rückt an die Stelle, auf die sie gezogen wird', () async {
    final k = await kette();

    // In die Lücke hinter der letzten Station.
    expect(
      ids(k.umbau(const StationsZug(0), const ZielLuecke(3))),
      ['b1', 'b2', 'v1', 'z1', 'z2'],
    );
    // Auf die erste Station: an ihren Platz, sie rückt nach hinten.
    expect(
      ids(k.umbau(const StationsZug(2), ZielAnlage(s(k, 'z1'), 0))),
      ['v1', 'z1', 'z2', 'b1', 'b2'],
    );
    // Auf eine spätere Station: dahinter.
    expect(
      ids(k.umbau(const StationsZug(0), const ZielStation(1))),
      ['b1', 'b2', 'z1', 'z2', 'v1'],
    );
  });

  test('eine Anlage aus dem Katalog kommt vor die Anlage, ans Ende der '
      'Station oder — in einer Lücke — mit ihrer Stammabteilung', () async {
    final k = await kette();
    final zug = AnlagenZug(await anlage('m1'));
    (int, String)? wohin(KettenUmbau? u) =>
        u is AnlageEinfuegen ? (u.index, u.abteilung) : null;

    expect(wohin(k.umbau(zug, ZielAnlage(s(k, 'b2'), 1))), (3, 'bratstrasse'));
    expect(wohin(k.umbau(zug, const ZielStation(2))), (5, 'verpackung'));
    expect(wohin(k.umbau(zug, const ZielLuecke(2))), (4, 'zerlegung'));
  });

  test('aus dem Katalog eingefügt, wird die Anlage ein neuer Schritt — '
      'ihr Katalogeintrag bleibt, wie er ist', () async {
    final k = await kette();

    await ziehe(k, AnlagenZug(await anlage('m1')), ZielAnlage(s(k, 'b2'), 1));

    expect(await stand(), [
      'z1:zerlegung',
      'z2:zerlegung',
      'b1:bratstrasse',
      'neu:bratstrasse',
      'b2:bratstrasse',
      'v1:verpackung',
    ]);
    final neu = (await ProzesskettenService.schritte(db, 'p1'))[3];
    expect(neu.maschineId, 'm1');
    expect(neu.maschine, 'Rollenschneider');
    expect(neu.reihenfolge, 4);
    expect((await anlage('m1')).abteilung, 'zerlegung');
  });

  test('wird eine Anlage in eine andere Station gezogen, bleiben die '
      'Leistungsdaten bei ihrer alten Station', () async {
    await ProzesskettenService.setzeLeistungsdaten(
      db,
      productId: 'p1',
      stepId: 'z1',
      mengeKg: 500,
      minuten: 50,
    );
    final k = await kette();

    await ziehe(k, SchrittZug(s(k, 'z1')), const ZielStation(1));

    final stationen = (await kette()).stationen;
    expect(leistungsdatenVon(stationen[0])?.stepId, 'z2');
    expect(leistungsdatenVon(stationen[0])?.mengeKg, 500);
    expect(leistungsdatenVon(stationen[1]), isNull);
  });

  test('Ziele, die nicht mehr zur Kette passen, werden abgelehnt', () async {
    final k = await kette();
    final z1 = SchrittZug(s(k, 'z1'));

    expect(k.umbau(z1, const ZielStation(3)), isNull);
    expect(k.umbau(z1, const ZielLuecke(4)), isNull);
    expect(
      k.umbau(z1, ZielAnlage(s(k, 'b1'), 0)),
      isNull,
      reason: 'b1 steht nicht in Station 0',
    );
    expect(k.umbau(const StationsZug(5), const ZielLuecke(0)), isNull);
  });

  test('hat sich die Kette inzwischen geändert, wird nichts geschrieben',
      () async {
    final k = await kette();
    final umbau = k.umbau(SchrittZug(s(k, 'z1')), const ZielLuecke(3));
    await ProzesskettenService.entferneSchritt(db, 'v1');

    await expectLater(k.schreibe(db, umbau!), throwsArgumentError);
    expect(await stand(), [
      'z1:zerlegung',
      'z2:zerlegung',
      'b1:bratstrasse',
      'b2:bratstrasse',
    ]);
  });
}
