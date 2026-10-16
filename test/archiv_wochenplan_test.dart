import 'dart:convert';

// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/erledigt_service.dart';
import 'package:produktion_planer/core/services/tagesaufgaben_service.dart';
import 'package:produktion_planer/core/services/week_snapshot_service.dart';
import 'package:produktion_planer/features/board/board_providers.dart';

import 'helpers/test_db.dart';

/// Tests für den archivierten Wochenplan: Beim Archivieren friert das
/// Archiv das Wochenboard so ein, wie es gerade aussieht — Spuren, Karten,
/// Ketten, Haken, Nebenzeiten und sonstige Aufgaben —, und die Ansicht
/// baut daraus dasselbe Board wieder auf. Alle Daten sind erfunden.
void main() {
  group('mit Datenbank', () {
    late AppDatabase db;

    setUp(() async {
      db = testDatenbank();
      await seedArtikel(db, id: 'p1', nummer: '7001');
      await seedArtikel(db, id: 'p2', nummer: '7002');
    });
    tearDown(() => db.close());

    Future<void> auftrag(
      String id, {
      required String productId,
      required DateTime tag,
      String abteilung = 'zerlegung',
      String? vorgaenger,
      String? maschineId,
      double mengeKg = 100,
      double dauerMinuten = 60,
    }) =>
        db.into(db.productionTasks).insert(
              ProductionTasksCompanion.insert(
                id: id,
                productId: productId,
                mengeKg: mengeKg,
                datum: tag,
                abteilung: abteilung,
                geplanteDauerMinuten: dauerMinuten,
                geplanteMitarbeiter: 2,
                parentTaskId: Value(vorgaenger),
                maschineId: Value(maschineId),
              ),
            );

    /// Archiviert die Woche ab [montag] wie der Knopf im Archiv und gibt
    /// das Board von vorher und das wieder aufgebaute zurück.
    Future<(WeekBoard, WeekBoard)> archiviere(DateTime montag) async {
      final board = await ladeWochenboard(db, montag);
      final aufgaben = await TagesaufgabenService.fuerZeitraum(
        db,
        von: montag,
        bisExkl: montag.add(const Duration(days: 7)),
      );
      await erstelleWochenSnapshot(
        db: db,
        wochenStart: montag,
        kapazitaeten: const {},
        plan: archivPlanAusBoard(board, aufgaben),
      );
      final snap = (await db.select(db.weekSnapshots).get()).single;
      final daten = dekodiereSnapshot(snap);
      expect(daten.plan, isNotNull, reason: 'Der Plan wird mitgespeichert');
      final archiv = wochenboardAusArchiv(
        daten.plan!,
        stand: snap.createdAt,
        zusatzzeiten: daten.zusatzzeiten,
      );
      return (board, archiv);
    }

    test('das Archiv zeigt dieselben Spuren, Karten, Ketten und Haken wie '
        'das Board beim Archivieren', () async {
      final montag = DateTime(2026, 10, 5);
      await seedAnlage(
        db,
        id: 'm1',
        name: 'Testanlage',
        abteilung: 'verpackung',
        kapazitaetMinutenProTag: 480,
      );
      // Eine Kette über drei Abteilungen, eine Folgestufe in der Woche
      // darauf und ein zweiter Artikel ohne Kette.
      await auftrag('z', productId: 'p1', tag: montag);
      await auftrag(
        'b',
        productId: 'p1',
        tag: DateTime(2026, 10, 6),
        abteilung: 'bratstrasse',
        vorgaenger: 'z',
      );
      await auftrag(
        'v',
        productId: 'p1',
        tag: DateTime(2026, 10, 7),
        abteilung: 'verpackung',
        vorgaenger: 'b',
        maschineId: 'm1',
      );
      await auftrag(
        'n',
        productId: 'p1',
        tag: DateTime(2026, 10, 12),
        abteilung: 'schneideabteilung',
        vorgaenger: 'v',
      );
      await auftrag(
        'w',
        productId: 'p2',
        tag: DateTime(2026, 10, 8),
        abteilung: 'wurstkueche',
        mengeKg: 250,
        dauerMinuten: 150,
      );
      await ErledigtService.abhaken(db, ['z'], erledigt: true);
      await db.into(db.zusatzzeiten).insert(
            ZusatzzeitenCompanion.insert(
              id: 'r1',
              datum: montag,
              spurId: 'zerlegung|',
              art: 'reinigen',
              minuten: 45,
            ),
          );

      final (board, archiv) = await archiviere(montag);

      expect(archiv.tage, board.tage);
      expect(
        [for (final s in archiv.spuren) s.id],
        [for (final s in board.spuren) s.id],
      );
      expect(
        archiv.spuren.any((s) => s.id == 'verpackung|m1'),
        isTrue,
        reason: 'Die Anlage behält ihre eigene Spur',
      );

      for (final spur in board.spuren) {
        for (final tag in board.tage) {
          final vorher = board.cellFor(spur, tag);
          final nachher = archiv.cellFor(spur, tag);
          expect(
            [
              for (final t in nachher.tasks)
                (
                  t.productName,
                  t.artikelnummer,
                  t.mengeKg,
                  t.dauerMinuten,
                  t.kettenId,
                  t.erledigt,
                ),
            ],
            [
              for (final t in vorher.tasks)
                (
                  t.productName,
                  t.artikelnummer,
                  t.mengeKg,
                  t.dauerMinuten,
                  t.kettenId,
                  t.erledigt,
                ),
            ],
            reason: 'Zelle ${spur.id} am $tag',
          );
          expect(nachher.belegtMinuten, vorher.belegtMinuten);
          expect(nachher.kapazitaetMinuten, vorher.kapazitaetMinuten);
          expect(nachher.status, vorher.status);
        }
      }

      // Haken und Nebenzeit am Montag in der Zerlegung.
      final zerlegung = archiv.spuren.firstWhere(
        (s) => s.abteilung == Abteilung.zerlegung,
      );
      final montagsZelle = archiv.cellFor(zerlegung, montag);
      expect(montagsZelle.tasks.single.erledigt, Erledigt.abgehakt);
      expect(montagsZelle.zusatzMinuten, 45);

      // Kettenmarker: Die Folgestufe liegt in der Woche darauf.
      final verpackung =
          archiv.spuren.firstWhere((s) => s.id == 'verpackung|m1');
      final karte =
          archiv.cellFor(verpackung, DateTime(2026, 10, 7)).tasks.single;
      final folge = archiv.nachbarnFuer(karte)?.nachher;
      expect(folge?.abteilung, Abteilung.schneideabteilung);
      expect(folge?.datum, DateTime(2026, 10, 12));
      expect(folge?.kw, 42);
    });

    test('die sonstigen Aufgaben der Woche kommen mit — nur Mo bis Fr',
        () async {
      final montag = DateTime(2026, 10, 5);
      await TagesaufgabenService.anlegen(
        db,
        tag: DateTime(2026, 10, 6),
        abteilung: 'bratstrasse',
        inhalt: 'Fett wechseln',
      );
      final erledigt = await TagesaufgabenService.anlegen(
        db,
        tag: DateTime(2026, 10, 6),
        abteilung: 'bratstrasse',
        inhalt: 'Ofen prüfen',
      );
      await TagesaufgabenService.abhaken(db, erledigt, erledigt: true);
      // Samstag: zeigt das Board nicht — also auch das Archiv nicht.
      await TagesaufgabenService.anlegen(
        db,
        tag: DateTime(2026, 10, 10),
        abteilung: 'bratstrasse',
        inhalt: 'Grundreinigung',
      );

      await archiviere(montag);
      final snap = (await db.select(db.weekSnapshots).get()).single;
      final aufgaben = dekodiereSnapshot(snap).plan!.aufgaben;

      expect(
        [for (final a in aufgaben) (a.inhalt, a.erledigt, a.abteilung)],
        [
          ('Fett wechseln', false, 'bratstrasse'),
          ('Ofen prüfen', true, 'bratstrasse'),
        ],
      );
      expect(aufgaben.first.datum, DateTime(2026, 10, 6));
    });
  });

  group('ohne Datenbank', () {
    test('ältere Snapshots ohne Plan bleiben lesbar', () {
      final alt = WochenSnapshotDaten.fromJson(
        jsonDecode(
          '{"tasks": [], "kapazitaeten": {"zerlegung": 540}, '
          '"zusatzzeiten": []}',
        ) as Map<String, dynamic>,
      );
      expect(alt.plan, isNull);
      expect(alt.kapazitaeten, {'zerlegung': 540.0});
      expect(
        const WochenSnapshotDaten(tasks: [], kapazitaeten: {})
            .toJson()
            .containsKey('plan'),
        isFalse,
      );
    });

    test('der Plan übersteht den Weg über JSON', () {
      final plan = ArchivPlan(
        tage: [DateTime(2026, 10, 5), DateTime(2026, 10, 6)],
        spuren: const [
          ArchivSpur(abteilung: 'zerlegung', kapazitaetMinuten: 540),
          ArchivSpur(
            abteilung: 'verpackung',
            maschineId: 'm1',
            maschineName: 'Testanlage',
            eignungHinweis: 'nur Testware',
            kapazitaetMinuten: 480,
          ),
        ],
        karten: [
          ArchivKarte(
            spurId: 'verpackung|m1',
            abteilung: 'verpackung',
            datum: DateTime(2026, 10, 6),
            productId: 'p1',
            productName: 'Testbraten',
            artikelnummer: '7001',
            startZeit: '06:30',
            dauerMinuten: 90,
            mengeKg: 120.5,
            sortierung: 2,
            status: 'fertig',
            kettenId: 'k1',
            erledigt: Erledigt.erfasst,
            auftraege: 2,
          ),
        ],
        aufgaben: [
          ArchivAufgabe(
            abteilung: 'zerlegung',
            datum: DateTime(2026, 10, 5),
            inhalt: 'Messer schleifen',
            erledigt: true,
          ),
        ],
        kettenNachbarn: {
          'k1': ArchivKettenNachbar(
            vorher: ArchivKettenSchritt(
              abteilung: 'zerlegung',
              datum: DateTime(2026, 9, 30),
              kw: 40,
            ),
          ),
        },
      );
      final daten = WochenSnapshotDaten(
        tasks: const [],
        kapazitaeten: const {},
        plan: plan,
      );

      final zurueck = WochenSnapshotDaten.fromJson(
        jsonDecode(jsonEncode(daten.toJson())) as Map<String, dynamic>,
      ).plan!;

      expect(zurueck.tage, plan.tage);
      expect([for (final s in zurueck.spuren) s.id], [
        'zerlegung|',
        'verpackung|m1',
      ]);
      expect(zurueck.spuren.last.maschineName, 'Testanlage');
      expect(zurueck.spuren.last.eignungHinweis, 'nur Testware');
      expect(zurueck.spuren.last.kapazitaetMinuten, 480);

      final k = zurueck.karten.single;
      expect(
        (
          k.spurId,
          k.abteilung,
          k.datum,
          k.productId,
          k.productName,
          k.artikelnummer,
          k.startZeit,
          k.dauerMinuten,
          k.mengeKg,
          k.sortierung,
          k.status,
          k.kettenId,
          k.erledigt,
          k.auftraege,
        ),
        (
          'verpackung|m1',
          'verpackung',
          DateTime(2026, 10, 6),
          'p1',
          'Testbraten',
          '7001',
          '06:30',
          90.0,
          120.5,
          2,
          'fertig',
          'k1',
          Erledigt.erfasst,
          2,
        ),
      );
      final a = zurueck.aufgaben.single;
      expect(
        (a.abteilung, a.datum, a.inhalt, a.erledigt),
        ('zerlegung', DateTime(2026, 10, 5), 'Messer schleifen', true),
      );
      final vorher = zurueck.kettenNachbarn['k1']!.vorher!;
      expect(
        (vorher.abteilung, vorher.datum, vorher.kw),
        ('zerlegung', DateTime(2026, 9, 30), 40),
      );
      expect(zurueck.kettenNachbarn['k1']!.nachher, isNull);
    });

    test('eine Abteilung, die es nicht mehr gibt, verhindert die Ansicht '
        'nicht', () {
      final plan = ArchivPlan(
        tage: [DateTime(2026, 10, 5)],
        spuren: const [
          ArchivSpur(abteilung: 'zerlegung', kapazitaetMinuten: 540),
          ArchivSpur(abteilung: 'gibt_es_nicht', kapazitaetMinuten: 540),
        ],
        karten: [
          ArchivKarte(
            spurId: 'gibt_es_nicht|',
            abteilung: 'gibt_es_nicht',
            datum: DateTime(2026, 10, 5),
            productId: 'p1',
            productName: 'Testbraten',
            dauerMinuten: 60,
            mengeKg: 100,
            kettenId: 'k1',
          ),
          ArchivKarte(
            spurId: 'zerlegung|',
            abteilung: 'zerlegung',
            datum: DateTime(2026, 10, 5),
            productId: 'p2',
            productName: 'Testwurst',
            dauerMinuten: 30,
            mengeKg: 50,
            kettenId: 'k2',
          ),
        ],
      );

      final board = wochenboardAusArchiv(plan, stand: DateTime(2026, 10, 9));

      expect([for (final s in board.spuren) s.id], ['zerlegung|']);
      final zelle = board.cellFor(board.spuren.single, DateTime(2026, 10, 5));
      expect(zelle.tasks.single.productName, 'Testwurst');
      expect(board.wochenStart, DateTime(2026, 10, 5));
    });
  });
}
