// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/prozesskette_service.dart';
import 'package:produktion_planer/features/whiteboard/whiteboard_provider.dart'
    show leistungsdatenVon;

import 'helpers/test_db.dart';

/// Tests für die Leistungsdaten je Abteilung beim Umbauen der Kette.
///
/// Leistungsdaten gehören der Abteilung, gespeichert sind sie an einem
/// ihrer Schritte. Entfernen, Verschieben oder ein Abteilungswechsel
/// dürfen sie weder verlieren noch in eine fremde Abteilung tragen.
/// Alle Daten sind erfunden.
void main() {
  late AppDatabase db;

  setUp(() => db = testDatenbank());
  tearDown(() => db.close());

  Future<ProductStep> schritt(String id) =>
      (db.select(db.productSteps)..where((s) => s.id.equals(id))).getSingle();

  Future<List<ProductStep>> kette() => ProzesskettenService.schritte(db, 'p1');

  /// Zerlegung (z1, z2) → Bratstraße (b1, b2) → Verpackung (v1), alle
  /// ohne Leistungsdaten.
  Future<void> legeKetteAn() async {
    await seedArtikel(db, id: 'p1', nummer: '3001');
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
      );
    }
  }

  Future<void> setze(String stepId, double kg, double minuten) =>
      ProzesskettenService.setzeLeistungsdaten(
        db,
        productId: 'p1',
        stepId: stepId,
        mengeKg: kg,
        minuten: minuten,
      );

  test('der Block einer Abteilung umfasst ihre zusammenhängenden Schritte',
      () async {
    await legeKetteAn();

    final block = ProzesskettenService.blockVon(await kette(), 'b2');

    expect(block.map((s) => s.id), ['b1', 'b2']);
  });

  test('Leistungsdaten landen am ersten Schritt, Altwerte daneben '
      'verschwinden', () async {
    await legeKetteAn();
    // Ein Altwert am zweiten Bratstraßen-Schritt.
    await (db.update(db.productSteps)..where((s) => s.id.equals('b2'))).write(
      const ProductStepsCompanion(
        basisMengeKg: Value(100),
        basisDauerMinuten: Value(30),
      ),
    );

    await setze('b2', 600, 60);

    final b1 = await schritt('b1');
    final b2 = await schritt('b2');
    expect(b1.basisMengeKg, 600);
    expect(b1.basisDauerMinuten, 60);
    expect(b2.basisMengeKg, 0);
    expect(b2.basisDauerMinuten, 0);
    expect(leistungsdatenVon([b1, b2])?.stepId, 'b1');
  });

  test('ohne Menge oder Zeit werden keine Leistungsdaten gesetzt', () async {
    await legeKetteAn();

    await expectLater(setze('z1', 0, 60), throwsArgumentError);
    await expectLater(setze('z1', 100, 0), throwsArgumentError);
  });

  test('entfernte Leistungsdaten sind an allen Schritten weg', () async {
    await legeKetteAn();
    await setze('z1', 500, 50);

    await ProzesskettenService.entferneLeistungsdaten(
      db,
      productId: 'p1',
      stepId: 'z2',
    );

    final zerlegung = ProzesskettenService.blockVon(await kette(), 'z1');
    expect(leistungsdatenVon(zerlegung), isNull);
  });

  test('wird der Schritt mit den Leistungsdaten entfernt, übernimmt der '
      'nächste der Abteilung', () async {
    await legeKetteAn();
    await setze('b1', 600, 60);

    await ProzesskettenService.entferneSchritt(db, 'b1');

    final rest = await kette();
    expect(rest.map((s) => s.id), ['z1', 'z2', 'b2', 'v1']);
    // Lückenlos neu nummeriert — der Excel-Export nimmt die Nummer als
    // Spalte.
    expect(rest.map((s) => s.reihenfolge), [1, 2, 3, 4]);
    final bratstrasse = ProzesskettenService.blockVon(rest, 'b2');
    final l = leistungsdatenVon(bratstrasse);
    expect(l?.stepId, 'b2');
    expect(l?.mengeKg, 600);
    expect(l?.minuten, 60);
    expect((await schritt('b1')).deletedAt, isNotNull);
  });

  test('wechselt ein Schritt die Abteilung, bleiben ihre Leistungsdaten '
      'zurück', () async {
    await legeKetteAn();
    await setze('z1', 500, 50);
    await setze('v1', 300, 30);

    // z1 arbeitet bei diesem Artikel für die Verpackung.
    await ProzesskettenService.wechsleAbteilung(db, 'z1', 'verpackung');

    final z1 = await schritt('z1');
    expect(z1.abteilung, 'verpackung');
    expect(z1.basisMengeKg, 0, reason: 'Nimmt nichts in die Verpackung mit');

    final alle = await kette();
    final zerlegung = leistungsdatenVon(
      ProzesskettenService.blockVon(alle, 'z2'),
    );
    expect(zerlegung?.stepId, 'z2');
    expect(zerlegung?.mengeKg, 500);

    final verpackung = leistungsdatenVon(
      ProzesskettenService.blockVon(alle, 'v1'),
    );
    expect(verpackung?.mengeKg, 300);
  });

  test('zerfällt eine Abteilung in zwei Blöcke, behalten beide die '
      'Leistungsdaten', () async {
    await seedArtikel(db, id: 'p1', nummer: '3001');
    for (var i = 1; i <= 3; i++) {
      await seedSchritt(
        db,
        id: 'w$i',
        productId: 'p1',
        reihenfolge: i,
        abteilung: 'wurstkueche',
        basisMengeKg: 0,
        basisDauerMinuten: 0,
      );
    }
    await setze('w1', 400, 40);

    // Der mittlere Schritt arbeitet für die Verpackung — die Wurstküche
    // steht danach zweimal in der Kette.
    await ProzesskettenService.wechsleAbteilung(db, 'w2', 'verpackung');

    final bloecke = ProzesskettenService.bloecke(await kette());
    expect(bloecke.map((b) => b.map((s) => s.id).toList()), [
      ['w1'],
      ['w2'],
      ['w3'],
    ]);
    expect(leistungsdatenVon(bloecke[0])?.mengeKg, 400);
    expect(leistungsdatenVon(bloecke[1]), isNull);
    expect(leistungsdatenVon(bloecke[2])?.mengeKg, 400);
  });

  group('Kette umbauen', () {
    Future<List<String>> abfolge() async =>
        [for (final s in await kette()) s.id];

    test('eine verschobene Station nimmt ihre Leistungsdaten mit', () async {
      await legeKetteAn();
      await setze('z1', 500, 50);
      await setze('b1', 600, 60);

      await ProzesskettenService.ordneNeu(
        db,
        'p1',
        ['b1', 'b2', 'z1', 'z2', 'v1'],
      );

      final alle = await kette();
      expect(alle.map((s) => s.id), ['b1', 'b2', 'z1', 'z2', 'v1']);
      expect(alle.map((s) => s.reihenfolge), [1, 2, 3, 4, 5]);
      expect(
        leistungsdatenVon(ProzesskettenService.blockVon(alle, 'b1'))?.mengeKg,
        600,
      );
      expect(
        leistungsdatenVon(ProzesskettenService.blockVon(alle, 'z1'))?.mengeKg,
        500,
      );
    });

    test('innerhalb einer Station verschoben, bleiben die Leistungsdaten '
        'an der Station — am neuen ersten Schritt', () async {
      await legeKetteAn();
      await setze('b1', 600, 60);

      await ProzesskettenService.ordneNeu(
        db,
        'p1',
        ['z1', 'z2', 'b2', 'b1', 'v1'],
      );

      final l = leistungsdatenVon(
        ProzesskettenService.blockVon(await kette(), 'b1'),
      );
      expect(l?.stepId, 'b2');
      expect(l?.mengeKg, 600);
      expect((await schritt('b1')).basisMengeKg, 0);
    });

    test('eine Anlage in eine andere Abteilung ziehen: Sie nimmt keine '
        'Leistungsdaten mit, ihre alte Station behält sie', () async {
      await legeKetteAn();
      await setze('z1', 500, 50);
      await setze('b1', 600, 60);

      // z1 arbeitet bei diesem Artikel an der Bratstraße — zwischen b1
      // und b2.
      await ProzesskettenService.ordneNeu(
        db,
        'p1',
        ['z2', 'b1', 'z1', 'b2', 'v1'],
        abteilungen: {'z1': 'bratstrasse'},
      );

      final alle = await kette();
      final z1 = await schritt('z1');
      expect(z1.abteilung, 'bratstrasse');
      expect(z1.basisMengeKg, 0);
      final zerlegung =
          leistungsdatenVon(ProzesskettenService.blockVon(alle, 'z2'));
      expect(zerlegung?.stepId, 'z2');
      expect(zerlegung?.mengeKg, 500);
      final bratstrasse = ProzesskettenService.blockVon(alle, 'z1');
      expect(bratstrasse.map((s) => s.id), ['b1', 'z1', 'b2']);
      expect(leistungsdatenVon(bratstrasse)?.mengeKg, 600);
    });

    /// Zerlegung (z1, z2) → Bratstraße (b1) → Zerlegung (z3): Die
    /// Zerlegung steht zweimal in der Kette. Die erste Station hat
    /// Leistungsdaten an z1, die zweite nur mit [hintenMitWerten].
    Future<void> legeZweiZerlegungenAn({required bool hintenMitWerten}) async {
      await seedArtikel(db, id: 'p1', nummer: '3001');
      const schritte = [
        ('z1', 'zerlegung'),
        ('z2', 'zerlegung'),
        ('b1', 'bratstrasse'),
        ('z3', 'zerlegung'),
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
        );
      }
      await setze('z1', 100, 60);
      if (hintenMitWerten) await setze('z3', 200, 90);
    }

    test('in eine Station derselben Abteilung an anderer Stelle gezogen, '
        'nimmt eine Anlage keine Leistungsdaten mit', () async {
      await legeZweiZerlegungenAn(hintenMitWerten: true);

      // z1 trägt die Werte der ersten Station und zieht in die zweite.
      await ProzesskettenService.ordneNeu(db, 'p1', ['z2', 'b1', 'z1', 'z3']);

      final bloecke = ProzesskettenService.bloecke(await kette());
      expect(bloecke.map((b) => b.map((s) => s.id).toList()), [
        ['z2'],
        ['b1'],
        ['z1', 'z3'],
      ]);
      final vorne = leistungsdatenVon(bloecke[0]);
      expect(vorne?.mengeKg, 100);
      expect(vorne?.minuten, 60);
      final hinten = leistungsdatenVon(bloecke[2]);
      expect(hinten?.mengeKg, 200, reason: 'Die Station behält ihre Werte');
      expect(hinten?.minuten, 90);
    });

    test('eine Station ohne Leistungsdaten bekommt keine, wenn eine Anlage '
        'mit Werten hineinzieht', () async {
      await legeZweiZerlegungenAn(hintenMitWerten: false);

      await ProzesskettenService.ordneNeu(db, 'p1', ['z2', 'b1', 'z1', 'z3']);

      final bloecke = ProzesskettenService.bloecke(await kette());
      expect(leistungsdatenVon(bloecke[0])?.mengeKg, 100);
      expect(leistungsdatenVon(bloecke[2]), isNull);
      expect((await schritt('z1')).basisMengeKg, 0);
    });

    test('eine veraltete Abfolge wird abgewiesen', () async {
      await legeKetteAn();

      await expectLater(
        ProzesskettenService.ordneNeu(db, 'p1', ['z1', 'z2', 'b1']),
        throwsArgumentError,
      );
      expect(await abfolge(), ['z1', 'z2', 'b1', 'b2', 'v1']);
    });

    test('einfügen an einer Stelle und in einer fremden Abteilung', () async {
      await legeKetteAn();
      await seedAnlage(
        db,
        id: 'm1',
        name: 'Rollenschneider',
        abteilung: 'zerlegung',
      );

      final id = await ProzesskettenService.fuegeEin(
        db,
        productId: 'p1',
        abteilung: 'bratstrasse',
        index: 3,
        maschineId: 'm1',
        maschine: 'Rollenschneider',
      );

      final alle = await kette();
      expect(alle.map((s) => s.id), ['z1', 'z2', 'b1', id, 'b2', 'v1']);
      expect(alle.map((s) => s.reihenfolge), [1, 2, 3, 4, 5, 6]);
      final neu = await schritt(id);
      expect(neu.abteilung, 'bratstrasse');
      expect(neu.maschineId, 'm1');
      expect(neu.basisMitarbeiter, 1);
      expect(neu.basisMengeKg, 0);
    });

    test('ohne Stelle kommt ein Schritt ans Ende seiner Abteilung', () async {
      await legeKetteAn();

      final zerlegung = await ProzesskettenService.fuegeEin(
        db,
        productId: 'p1',
        abteilung: 'zerlegung',
      );
      final neueAbteilung = await ProzesskettenService.fuegeEin(
        db,
        productId: 'p1',
        abteilung: 'schneideabteilung',
      );

      expect(
        await abfolge(),
        ['z1', 'z2', zerlegung, 'b1', 'b2', 'v1', neueAbteilung],
      );
    });

    test('mehr als 20 Schritte passen nicht ins Artikelblatt', () async {
      await seedArtikel(db, id: 'p1', nummer: '3001');
      for (var i = 1; i <= ProzesskettenService.maxSchritte; i++) {
        await seedSchritt(
          db,
          id: 's$i',
          productId: 'p1',
          reihenfolge: i,
          abteilung: 'verpackung',
        );
      }

      await expectLater(
        ProzesskettenService.fuegeEin(
          db,
          productId: 'p1',
          abteilung: 'verpackung',
        ),
        throwsStateError,
      );

      // Gelöschte zählen nicht: Danach ist wieder Platz.
      await ProzesskettenService.entferneSchritt(db, 's20');
      await ProzesskettenService.fuegeEin(
        db,
        productId: 'p1',
        abteilung: 'verpackung',
      );
      expect((await kette()).length, ProzesskettenService.maxSchritte);
    });
  });
}
