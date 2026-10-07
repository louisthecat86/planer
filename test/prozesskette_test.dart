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
}
