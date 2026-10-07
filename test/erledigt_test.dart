// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/erledigt_service.dart';

import 'helpers/test_db.dart';

/// Tests für „erledigt" im Board: von Hand abgehakt oder automatisch,
/// sobald die Produktion erfasst ist. Alle Daten sind erfunden.
void main() {
  late AppDatabase db;
  var erfassungen = 0;

  setUp(() async {
    db = testDatenbank();
    erfassungen = 0;
    await seedArtikel(db, id: 'p1', nummer: '5001');
    await seedArtikel(db, id: 'p2', nummer: '5002');
  });
  tearDown(() => db.close());

  final montag = DateTime(2026, 10, 5);
  final dienstag = DateTime(2026, 10, 6);

  Future<void> auftrag(
    String id, {
    required DateTime tag,
    String productId = 'p1',
    String abteilung = 'zerlegung',
    String? vorgaenger,
    String status = 'geplant',
    DateTime? geloescht,
  }) =>
      db.into(db.productionTasks).insert(
            ProductionTasksCompanion.insert(
              id: id,
              productId: productId,
              mengeKg: 100,
              datum: tag,
              abteilung: abteilung,
              geplanteDauerMinuten: 60,
              geplanteMitarbeiter: 2,
              status: Value(status),
              parentTaskId: Value(vorgaenger),
              deletedAt: Value(geloescht),
            ),
          );

  Future<void> erfasse(DateTime tag, {String productId = 'p1'}) =>
      db.into(db.productionHistory).insert(
            ProductionHistoryCompanion.insert(
              id: 'h${++erfassungen}',
              productId: productId,
              datum: tag,
              kgRohware: const Value(100),
            ),
          );

  Future<ProductionTask> lade(String id) =>
      (db.select(db.productionTasks)..where((t) => t.id.equals(id)))
          .getSingle();

  Future<List<ProductionTask>> ladeAlle(List<String> ids) async => [
        for (final id in ids) await lade(id),
      ];

  /// Zerlegung am Montag → Bratstraße und Verpackung am Dienstag.
  Future<void> legeKetteAn({DateTime? zerlegungGeloescht}) async {
    await auftrag('z', tag: montag, geloescht: zerlegungGeloescht);
    await auftrag(
      'b',
      tag: dienstag,
      abteilung: 'bratstrasse',
      vorgaenger: 'z',
    );
    await auftrag(
      'v',
      tag: dienstag,
      abteilung: 'verpackung',
      vorgaenger: 'b',
    );
  }

  test('abhaken setzt den Status und nimmt ihn wieder zurück', () async {
    await auftrag('a', tag: montag);
    await auftrag('s', tag: montag, status: 'storniert');

    await ErledigtService.abhaken(db, ['a', 's'], erledigt: true);

    expect((await lade('a')).status, 'fertig');
    expect(
      (await lade('s')).status,
      'storniert',
      reason: 'Ein Haken holt keinen stornierten Auftrag zurück',
    );

    await ErledigtService.abhaken(db, ['a'], erledigt: false);

    expect((await lade('a')).status, 'geplant');
  });

  test('die Wurzel liegt auch außerhalb der geladenen Aufträge', () async {
    await legeKetteAn();

    // Wie im Board einer Woche, die nur den Dienstag zeigt.
    final wurzeln =
        await ErledigtService.wurzeln(db, await ladeAlle(['b', 'v']));

    expect(wurzeln['b']?.id, 'z');
    expect(wurzeln['v']?.id, 'z');
  });

  test('eine erfasste Produktion macht die ganze Kette erledigt', () async {
    await legeKetteAn();
    await erfasse(montag);

    final erfasst = await ErledigtService.erfassteAuftraege(
      db,
      await ladeAlle(['z', 'b', 'v']),
    );

    expect(erfasst, {'z', 'b', 'v'});
  });

  test('zugeordnet wird über den Tag der Wurzel', () async {
    await legeKetteAn();
    // Zweite Produktion desselben Artikels, sie beginnt am Dienstag.
    await auftrag('z2', tag: dienstag);
    await auftrag(
      'b2',
      tag: dienstag,
      abteilung: 'bratstrasse',
      vorgaenger: 'z2',
    );
    await erfasse(dienstag);

    final erfasst = await ErledigtService.erfassteAuftraege(
      db,
      await ladeAlle(['z', 'b', 'v', 'z2', 'b2']),
    );

    expect(
      erfasst,
      {'z2', 'b2'},
      reason: 'Die Kette ab Montag hat am Montag keine Erfassung',
    );
  });

  test('ein gelöschter erster Schritt bleibt die Wurzel', () async {
    // Die Zerlegung wurde aus dem Board gelöscht — das Fleisch kam schon
    // zerlegt. Erfasst wird trotzdem auf den Tag der Kette.
    await legeKetteAn(zerlegungGeloescht: DateTime(2026, 10, 1));
    await erfasse(montag);

    final erfasst = await ErledigtService.erfassteAuftraege(
      db,
      await ladeAlle(['b', 'v']),
    );

    expect(erfasst, {'b', 'v'});
  });

  test('Erfassungen anderer Artikel und gelöschte Erfassungen zählen nicht',
      () async {
    await legeKetteAn();
    await erfasse(montag, productId: 'p2');
    await erfasse(montag);
    await (db.update(db.productionHistory)
          ..where((h) => h.productId.equals('p1')))
        .write(ProductionHistoryCompanion(deletedAt: Value(DateTime.now())));

    final erfasst = await ErledigtService.erfassteAuftraege(
      db,
      await ladeAlle(['z', 'b', 'v']),
    );

    expect(erfasst, isEmpty);
  });

  test('stand: die Erfassung geht vor dem Haken', () async {
    await legeKetteAn();
    await auftrag('x', tag: montag, productId: 'p2', status: 'fertig');
    await auftrag('o', tag: montag, productId: 'p2');
    await ErledigtService.abhaken(db, ['b'], erledigt: true);
    await erfasse(montag);

    final stand = await ErledigtService.stand(
      db,
      await ladeAlle(['z', 'b', 'x', 'o']),
    );

    expect(stand['z'], Erledigt.erfasst);
    expect(stand['b'], Erledigt.erfasst);
    expect(stand['x'], Erledigt.abgehakt);
    expect(stand.containsKey('o'), isFalse);
  });

  test('ein Kreis in den Daten hängt nicht', () async {
    await auftrag('k1', tag: montag, vorgaenger: 'k2');
    await auftrag('k2', tag: montag, vorgaenger: 'k1');

    final wurzeln = await ErledigtService.wurzeln(db, [await lade('k1')]);

    expect(wurzeln.keys, ['k1']);
  });
}
