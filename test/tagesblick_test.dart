import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/erledigt_service.dart';
import 'package:produktion_planer/features/shell/tagesblick.dart';

import 'helpers/test_db.dart';

/// Tests für den Tagesblick der Übersicht: Fortschritt des Tages und der
/// nächste Tag mit Planung. Alle Artikel erfunden.
void main() {
  group('Fortschritt', () {
    test('erledigt, Rohware und erfasst', () {
      final f = TagesFortschritt.aus(const [
        (rohKg: 300, erledigt: Erledigt.erfasst, erfasst: true),
        (rohKg: 200, erledigt: Erledigt.abgehakt, erfasst: false),
        (rohKg: 500, erledigt: null, erfasst: false),
      ]);
      expect((f.produktionen, f.erledigt, f.erfasst), (3, 2, 1));
      expect((f.rohKg, f.rohKgErledigt), (1000.0, 500.0));
      expect(f.anteil, 0.5);
      expect(f.leer, isFalse);
      expect(TagesFortschritt.aus(const []).leer, isTrue);
    });
  });

  group('nächster Tag', () {
    late AppDatabase db;
    final freitag = DateTime(2026, 11, 27);
    final montag = DateTime(2026, 11, 30);

    setUp(() async {
      db = testDatenbank();
      await seedArtikel(db, id: 'p1', nummer: '9101', bezeichnung: 'Braten');
      await seedArtikel(db, id: 'p2', nummer: '9102', bezeichnung: 'Wurst');
    });
    tearDown(() => db.close());

    Future<void> karte(
      String id,
      String productId,
      DateTime tag,
      String abteilung, {
      String? parent,
      int sortierung = 0,
      String? start,
      double kg = 100,
    }) =>
        db.into(db.productionTasks).insert(
              ProductionTasksCompanion.insert(
                id: id,
                productId: productId,
                mengeKg: kg,
                datum: tag,
                abteilung: abteilung,
                geplanteDauerMinuten: 60,
                geplanteMitarbeiter: 2,
                parentTaskId: Value(parent),
                sortierung: Value(sortierung),
                startZeit: Value(start),
              ),
            );

    test('über das Wochenende: Montag, je Abteilung der erste', () async {
      // Heute selbst zählt nicht.
      await karte('h', 'p1', freitag, 'bratstrasse');
      await karte('a', 'p2', montag, 'bratstrasse', sortierung: 1, kg: 400);
      await karte('b', 'p1', montag, 'bratstrasse', start: '06:15', kg: 300);
      await karte('c', 'p1', montag, 'verpackung', parent: 'b', kg: 240);
      // Dienstag ist später.
      await karte('d', 'p2', DateTime(2026, 12, 1), 'zerlegung');

      final tasks = await db.select(db.productionTasks).get();
      final produkte = {
        for (final p in await db.select(db.products).get()) p.id: p,
      };
      final n = naechsterTagAus(freitag, tasks, produkte)!;
      expect(n.tag, montag);
      expect(n.produktionen, 2);
      expect(n.rohKg, 700);
      expect(
        [for (final a in n.abteilungen) a.abteilung],
        [Abteilung.bratstrasse, Abteilung.verpackung],
      );
      final brat = n.abteilungen.first;
      expect((brat.nummer, brat.startZeit, brat.anzahl), ('9101', '06:15', 2));
      expect(n.abteilungen.last.startZeit, isNull);

      expect(naechsterTagAus(DateTime(2026, 12, 1), tasks, produkte), isNull);
    });
  });
}
