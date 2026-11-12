import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/providers/database_provider.dart';
import 'package:produktion_planer/core/providers/daten_waechter.dart';
import 'package:produktion_planer/features/bedarf/bedarf_screen.dart';
import 'package:produktion_planer/features/board/board_providers.dart';

import 'helpers/test_db.dart';

/// Ansichten halten sich selbst aktuell: Ein Provider, der aus der
/// Datenbank liest, lädt neu, sobald sich dort etwas ändert — ohne dass ihn
/// jemand anstößt. Alle Daten sind erfunden.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  /// Wie oft der Zähl-Provider geladen hat.
  var geladen = 0;

  /// Ein Provider wie die der Ansichten: liest und zählt mit.
  final zaehler = FutureProvider.autoDispose<int>((ref) async {
    final db = ref.watch(databaseProvider);
    neuLadenBeiAenderung(ref, db);
    geladen++;
    return (await db.select(db.products).get()).length;
  });

  /// Länger als die Wartezeit des Wächters.
  Future<void> warten() =>
      Future<void>.delayed(kNeuLadenNach + const Duration(milliseconds: 150));

  setUp(() async {
    db = testDatenbank();
    geladen = 0;
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('eine Änderung lädt neu — ohne Anstoß von außen', () async {
    final abo = container.listen(zaehler, (_, __) {});
    expect(await container.read(zaehler.future), 0);
    expect(geladen, 1);

    await seedArtikel(db, id: 'a1', nummer: '4711');
    await warten();

    expect(await container.read(zaehler.future), 1);
    expect(geladen, 2);
    abo.close();
  });

  test('viele Änderungen kurz hintereinander: ein Laden', () async {
    final abo = container.listen(zaehler, (_, __) {});
    await container.read(zaehler.future);

    for (var i = 0; i < 25; i++) {
      await seedArtikel(db, id: 'a$i', nummer: '47$i');
    }
    await warten();

    expect(await container.read(zaehler.future), 25);
    expect(geladen, 2);
    abo.close();
  });

  test('was die Planung nicht betrifft, lädt nichts neu', () async {
    final abo = container.listen(zaehler, (_, __) {});
    await container.read(zaehler.future);

    // Die Produktentwicklung hat ihre eigenen Abfragen.
    await db.into(db.entwicklungZutaten).insert(
          const EntwicklungZutatenCompanion(
            id: Value('z1'),
            name: Value('Pfeffer'),
          ),
        );
    await warten();

    expect(geladen, 1);
    abo.close();
  });

  test('schaut niemand mehr hin, wird auch nicht mehr geladen', () async {
    final abo = container.listen(zaehler, (_, __) {});
    await container.read(zaehler.future);
    abo.close();
    // autoDispose räumt den Provider ab — und mit ihm den Wächter.
    await warten();

    await seedArtikel(db, id: 'a1', nummer: '4711');
    await warten();
    expect(geladen, 1);
  });

  test('das Board zeigt einen neuen Auftrag von selbst', () async {
    final montag = DateTime(2026, 11, 9);
    await seedArtikel(db, id: 'a1', nummer: '4711');
    final provider = weekBoardProvider(montag);
    final abo = container.listen(provider, (_, __) {});
    final vorher = await container.read(provider.future);
    expect(vorher.cells.values.expand((c) => c.tasks), isEmpty);

    await db.into(db.productionTasks).insert(
          ProductionTasksCompanion.insert(
            id: 't1',
            productId: 'a1',
            datum: montag,
            abteilung: 'bratstrasse',
            mengeKg: 100,
            geplanteDauerMinuten: 60,
            geplanteMitarbeiter: 2,
          ),
        );
    await warten();

    final nachher = await container.read(provider.future);
    expect(
      [for (final c in nachher.cells.values) ...c.tasks].single.id,
      't1',
    );
    abo.close();
  });

  test('der Bedarf zeigt einen neuen Eintrag von selbst', () async {
    await seedArtikel(db, id: 'a1', nummer: '4711');
    final abo = container.listen(bedarfProvider, (_, __) {});
    expect(await container.read(bedarfProvider.future), isEmpty);

    await db.into(db.demands).insert(
          DemandsCompanion.insert(
            id: 'b1',
            productId: 'a1',
            mengeKgFertig: 100,
          ),
        );
    await warten();

    final liste = await container.read(bedarfProvider.future);
    expect(liste.single.bedarf.id, 'b1');
    abo.close();
  });
}
