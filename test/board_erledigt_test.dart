// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/providers/database_provider.dart';
import 'package:produktion_planer/core/services/erledigt_service.dart';
import 'package:produktion_planer/features/board/board_providers.dart';

import 'helpers/test_db.dart';

/// Tests für „erledigt" an den Karten des Wochenboards — so, wie das Board
/// sie lädt: Mehrere Aufträge desselben Artikels in derselben Abteilung am
/// selben Tag sind EINE Karte. Alle Daten sind erfunden.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  final freitag = DateTime(2026, 10, 2);
  final montag = DateTime(2026, 10, 5);

  setUp(() async {
    db = testDatenbank();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await seedArtikel(db, id: 'p1', nummer: '6001');
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> auftrag(
    String id, {
    required DateTime tag,
    String abteilung = 'zerlegung',
    String? vorgaenger,
    String status = 'geplant',
  }) =>
      db.into(db.productionTasks).insert(
            ProductionTasksCompanion.insert(
              id: id,
              productId: 'p1',
              mengeKg: 100,
              datum: tag,
              abteilung: abteilung,
              geplanteDauerMinuten: 60,
              geplanteMitarbeiter: 2,
              status: Value(status),
              parentTaskId: Value(vorgaenger),
            ),
          );

  var erfassungen = 0;
  Future<void> erfasse(DateTime tag) =>
      db.into(db.productionHistory).insert(
            ProductionHistoryCompanion.insert(
              id: 'h${++erfassungen}',
              productId: 'p1',
              datum: tag,
              kgRohware: const Value(100),
            ),
          );

  /// Die eine Karte der Zerlegung am Montag, frisch geladen.
  Future<BoardTask> karte() async {
    container.invalidate(weekBoardProvider(montag));
    final abo = container.listen(weekBoardProvider(montag), (_, __) {});
    try {
      final board = await container.read(weekBoardProvider(montag).future);
      return board.cells.values.expand((c) => c.tasks).single;
    } finally {
      abo.close();
    }
  }

  test('eine gebündelte Karte ist erst erledigt, wenn alle Aufträge es sind',
      () async {
    await auftrag('a', tag: montag, status: 'fertig');
    await auftrag('b', tag: montag);

    final halb = await karte();
    expect(halb.mitgliederIds.toSet(), {'a', 'b'});
    expect(halb.erledigt, isNull);

    await ErledigtService.abhaken(db, ['b'], erledigt: true);

    expect((await karte()).erledigt, Erledigt.abgehakt);
  });

  test('erfasst ist die Karte nur, wenn es alle ihre Aufträge sind',
      () async {
    // „a" beginnt am Montag. „b" gehört zu einer Kette, die schon am
    // Freitag davor in der Wurstküche begann — außerhalb der Woche.
    await auftrag('a', tag: montag);
    await auftrag('w', tag: freitag, abteilung: 'wurstkueche');
    await auftrag('b', tag: montag, vorgaenger: 'w', status: 'fertig');
    await erfasse(montag);

    expect(
      (await karte()).erledigt,
      Erledigt.abgehakt,
      reason: '„a" ist erfasst, „b" nur abgehakt',
    );

    await erfasse(freitag);

    expect((await karte()).erledigt, Erledigt.erfasst);
  });
}
