import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/providers/database_provider.dart';
import 'package:produktion_planer/features/board/board_providers.dart';

import 'helpers/test_db.dart';

/// Tests für die Spuren des Wochenboards bei Anlagen, die bei einem
/// Artikel in einer anderen Abteilung arbeiten als ihrer Stammabteilung.
/// Alle Daten sind erfunden.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  final montag = DateTime(2026, 10, 5);

  setUp(() async {
    db = testDatenbank();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await seedArtikel(db, id: 'p1', nummer: '8001');
    // Beide Anlagen haben eine eigene Spur — in ihrer Stammabteilung.
    await seedAnlage(
      db,
      id: 'rs',
      name: 'Rollenschneider',
      abteilung: 'zerlegung',
    );
    await seedAnlage(
      db,
      id: 'bs',
      name: 'Bratstraße 1',
      abteilung: 'bratstrasse',
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> auftrag(String id, String abteilung, String? maschineId) =>
      db.into(db.productionTasks).insert(
            ProductionTasksCompanion.insert(
              id: id,
              productId: 'p1',
              mengeKg: 100,
              datum: montag,
              abteilung: abteilung,
              maschineId: Value(maschineId),
              geplanteDauerMinuten: 60,
              geplanteMitarbeiter: 2,
            ),
          );

  Future<WeekBoard> woche() async {
    container.invalidate(weekBoardProvider(montag));
    final abo = container.listen(weekBoardProvider(montag), (_, __) {});
    try {
      return await container.read(weekBoardProvider(montag).future);
    } finally {
      abo.close();
    }
  }

  test('ein Auftrag mit einer Anlage aus einer anderen Abteilung landet in '
      'der Sammelspur seiner Abteilung', () async {
    await auftrag('t1', 'bratstrasse', 'rs');

    final board = await woche();

    final zelle = board.cells.values.where((c) => c.tasks.isNotEmpty).single;
    expect(zelle.spur.abteilung, Abteilung.bratstrasse);
    expect(zelle.spur.maschineId, isNull, reason: 'Sammelspur');
    expect(zelle.tasks.single.id, 't1');
    // Die Karte kennt ihre Spur: Verschiebt man sie dort nur auf einen
    // anderen Tag, behält sie ihre Anlage.
    expect(zelle.tasks.single.spurId, zelle.spur.id);
    expect(zelle.tasks.single.maschineId, 'rs');
  });

  test('auf der eigenen Anlage bleibt der Auftrag auf deren Spur', () async {
    await auftrag('t1', 'bratstrasse', 'bs');
    await auftrag('t2', 'zerlegung', 'rs');

    final board = await woche();

    final belegt = {
      for (final c in board.cells.values)
        for (final t in c.tasks) t.id: c.spur.id,
    };
    expect(belegt, {'t1': 'bratstrasse|bs', 't2': 'zerlegung|rs'});
    expect(
      {
        for (final c in board.cells.values)
          for (final t in c.tasks) t.id: t.spurId,
      },
      belegt,
    );
    // Keine überflüssige Sammelspur.
    expect(
      board.spuren.where((s) => !s.istAnlage).map((s) => s.abteilung),
      isNot(contains(Abteilung.bratstrasse)),
    );
  });
}
