// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/auftragsbestand_deckung.dart'
    show ladeBedarfsPlanung;
import 'package:produktion_planer/features/whiteboard/whiteboard_provider.dart'
    show berechneSchrittPlan, erstelleTasksAusPlan;

import 'helpers/test_db.dart';

/// Tests für das Einplanen mit abgewählten Abteilungen.
///
/// Im Planen-Dialog lässt sich eine Abteilung für diese eine Planung
/// abwählen — etwa die Zerlegung, wenn das Fleisch schon zerlegt kommt.
/// Die Kette besteht dann nur aus den übrigen Schritten; der erste davon
/// ist die Wurzel und trägt Bedarf und Fertigmenge.
///
/// Alle Daten sind erfunden.
void main() {
  late AppDatabase db;
  final montag = DateTime(2026, 10, 12);

  setUp(() async {
    db = testDatenbank();
    await seedArtikel(db, id: 'p1', nummer: 'T-200');
    // Ausbeute 80 %: 1.000 kg Rohware ergaben 800 kg Fertigware.
    await db.into(db.productionHistory).insert(
          ProductionHistoryCompanion.insert(
            id: 'h1',
            productId: 'p1',
            datum: DateTime(2026, 9, 1),
            kgRohware: const Value(1000),
            kgFertigware: const Value(800),
            verlustAnteil: const Value(0.2),
          ),
        );
    const abteilungen = [
      'zerlegung',
      'wurstkueche',
      'bratstrasse',
      'verpackung',
    ];
    for (var i = 0; i < abteilungen.length; i++) {
      await seedSchritt(
        db,
        id: 's${i + 1}',
        productId: 'p1',
        reihenfolge: i + 1,
        abteilung: abteilungen[i],
      );
    }
    await seedBedarf(db, id: 'b1', productId: 'p1', mengeKgFertig: 400);
  });
  tearDown(() => db.close());

  /// Plant 400 kg Fertigware für den Bedarf ein — ohne die Abteilungen
  /// [ohne], wie im Dialog ohne Haken. Gibt die ID der Wurzel zurück.
  Future<String?> einplanen({required Set<String> ohne}) async {
    final plan = await berechneSchrittPlan(
      db: db,
      productId: 'p1',
      mengeKg: 400,
      startTag: montag,
    );
    return erstelleTasksAusPlan(
      db: db,
      productId: 'p1',
      schritte: [
        for (final s in plan.schritte)
          if (!ohne.contains(s.abteilungDbValue)) s,
      ],
      bedarfId: 'b1',
      fertigMengeKg: 400,
    );
  }

  /// Die angelegten Schritte, je Abteilung.
  Future<Map<String, ProductionTask>> jeAbteilung() async => {
        for (final t in await db.select(db.productionTasks).get())
          t.abteilung: t,
      };

  test('ohne Zerlegung: die Wurstküche ist Wurzel und trägt den Bedarf',
      () async {
    final wurzelId = await einplanen(ohne: {'zerlegung'});
    final t = await jeAbteilung();

    expect(
      t.keys,
      unorderedEquals(['wurstkueche', 'bratstrasse', 'verpackung']),
    );
    final wurst = t['wurstkueche']!;
    expect(wurst.id, wurzelId);
    expect(wurst.parentTaskId, isNull);
    expect(wurst.bedarfId, 'b1');
    expect(wurst.fertigMengeKg, 400);
    // Bis einschließlich Bratstraße rechnet die Kette mit der Rohmenge —
    // daran ändert die fehlende Zerlegung nichts.
    expect(wurst.mengeKg, closeTo(500, 1e-9));

    final brat = t['bratstrasse']!;
    final verpackung = t['verpackung']!;
    expect(brat.parentTaskId, wurst.id);
    expect(verpackung.parentTaskId, brat.id);
    for (final s in [brat, verpackung]) {
      expect(s.bedarfId, isNull);
      expect(s.fertigMengeKg, isNull);
    }

    // Der Bedarf gilt als ganz eingeplant — genau einmal.
    expect((await ladeBedarfsPlanung(db))['b1']!.kg, 400);
  });

  test('Abteilung in der Mitte abgewählt: die Kette schließt die Lücke',
      () async {
    await einplanen(ohne: {'bratstrasse'});
    final t = await jeAbteilung();

    expect(
      t.keys,
      unorderedEquals(['zerlegung', 'wurstkueche', 'verpackung']),
    );
    expect(t['zerlegung']!.parentTaskId, isNull);
    expect(t['zerlegung']!.bedarfId, 'b1');
    expect(t['wurstkueche']!.parentTaskId, t['zerlegung']!.id);
    expect(t['verpackung']!.parentTaskId, t['wurstkueche']!.id);
  });

  test('alles abgewählt: nichts wird angelegt', () async {
    final wurzelId = await einplanen(
      ohne: {'zerlegung', 'wurstkueche', 'bratstrasse', 'verpackung'},
    );

    expect(wurzelId, isNull);
    expect(await db.select(db.productionTasks).get(), isEmpty);
    expect(await ladeBedarfsPlanung(db), isEmpty);
  });
}
