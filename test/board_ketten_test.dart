// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/providers/database_provider.dart';
import 'package:produktion_planer/features/board/board_providers.dart';

import 'helpers/test_db.dart';

/// Tests für die Auftragsketten im Wochenboard: gleiche Akzentfarbe und
/// Kettenmarker über alle Schritte einer Produktion.
///
/// Jeder Schritt zeigt auf seinen VORGÄNGER, nicht auf die Wurzel. Früher
/// galt `parentTaskId ?? id` als Kennung der Kette — ab dem dritten Schritt
/// bekam jede Karte eine eigene. Alle Daten sind erfunden.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = testDatenbank();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await seedArtikel(db, id: 'p1', nummer: '7001');
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
    DateTime? geloescht,
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
              parentTaskId: Value(vorgaenger),
              deletedAt: Value(geloescht),
            ),
          );

  /// Das Wochenboard ab [montag], frisch geladen.
  Future<WeekBoard> woche(DateTime montag) async {
    container.invalidate(weekBoardProvider(montag));
    final abo = container.listen(weekBoardProvider(montag), (_, __) {});
    try {
      return await container.read(weekBoardProvider(montag).future);
    } finally {
      abo.close();
    }
  }

  List<BoardTask> karten(WeekBoard board) =>
      board.cells.values.expand((c) => c.tasks).toList();

  test('alle Schritte einer Kette tragen ihre Wurzel als Kennung — auch '
      'über die Woche hinaus', () async {
    // Zerlegung Do, Bratstraße Fr, Verpackung am Montag darauf.
    await auftrag('z', tag: DateTime(2026, 10, 1));
    await auftrag(
      'b',
      tag: DateTime(2026, 10, 2),
      abteilung: 'bratstrasse',
      vorgaenger: 'z',
    );
    await auftrag(
      'v',
      tag: DateTime(2026, 10, 5),
      abteilung: 'verpackung',
      vorgaenger: 'b',
    );

    final kw40 = await woche(DateTime(2026, 9, 28));
    final vorne = karten(kw40);
    expect(vorne.map((k) => k.kettenId).toSet(), {'z'});
    final folge = kw40.nachbarnFuer(vorne.first)?.nachher;
    expect(folge?.abteilung, Abteilung.verpackung);
    expect(folge?.datum, DateTime(2026, 10, 5));

    final kw41 = await woche(DateTime(2026, 10, 5));
    final hinten = karten(kw41).single;
    expect(
      hinten.kettenId,
      'z',
      reason: 'Der dritte Schritt gehört zur selben Kette',
    );
    final vor = kw41.nachbarnFuer(hinten)?.vorher;
    expect(vor?.abteilung, Abteilung.bratstrasse);
    expect(vor?.datum, DateTime(2026, 10, 2));
  });

  test('ein gelöschter Zwischenschritt trennt die Kette nicht', () async {
    await auftrag('z', tag: DateTime(2026, 10, 5));
    await auftrag(
      'b',
      tag: DateTime(2026, 10, 6),
      abteilung: 'bratstrasse',
      vorgaenger: 'z',
      geloescht: DateTime(2026, 10, 1),
    );
    await auftrag(
      'v',
      tag: DateTime(2026, 10, 7),
      abteilung: 'verpackung',
      vorgaenger: 'b',
    );

    final kw41 = await woche(DateTime(2026, 10, 5));

    expect(
      {for (final k in karten(kw41)) k.id: k.kettenId},
      {'z': 'z', 'v': 'z'},
    );
  });
}
