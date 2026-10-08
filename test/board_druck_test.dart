import 'dart:convert' show latin1;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/providers/database_provider.dart';
import 'package:produktion_planer/core/services/tagesaufgaben_service.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/utils/pdf_text.dart';
import 'package:produktion_planer/features/board/board_druck_dialog.dart';
import 'package:produktion_planer/features/board/board_print_service.dart';
import 'package:produktion_planer/features/board/board_providers.dart';

import 'helpers/test_db.dart';

/// Tests für den Druck des Planungsboards: Wochen- und Tagesplan, gesamte
/// Übersicht und je Abteilung ein Blatt, dazu der Druck-Dialog.
///
/// Die PDFs entstehen unkomprimiert — so steht jedes gedruckte Wort als
/// „(Wort)" im Dokument und lässt sich suchen. Alle Daten sind erfunden.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  final montag = DateTime(2026, 10, 12);
  final dienstag = DateTime(2026, 10, 13);
  final gedruckt = DateTime(2026, 10, 9, 14, 5);

  Future<void> auftrag(
    String id,
    String productId,
    String abteilung,
    DateTime tag, {
    String? maschine,
    double kg = 100,
    String? start,
  }) =>
      db.into(db.productionTasks).insert(
            ProductionTasksCompanion.insert(
              id: id,
              productId: productId,
              mengeKg: kg,
              datum: tag,
              abteilung: abteilung,
              maschineId: Value(maschine),
              startZeit: Value(start),
              geplanteDauerMinuten: 90,
              geplanteMitarbeiter: 2,
            ),
          );

  setUp(() async {
    db = testDatenbank();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await seedArtikel(
      db,
      id: 'p1',
      nummer: '10815',
      bezeichnung: 'BIO Rinderpatties 4x150g',
    );
    await seedArtikel(
      db,
      id: 'p2',
      nummer: '20417',
      bezeichnung: 'Schinken „Spezial“ – 2 × 500 g 🥩',
    );
    await seedAnlage(db, id: 'mv', name: 'Multivac', abteilung: 'verpackung');
    await seedAnlage(db, id: 'tz', name: 'Tiefzieher', abteilung: 'verpackung');

    await auftrag('t1', 'p1', 'wurstkueche', montag, kg: 2156.4);
    await auftrag('t2', 'p2', 'verpackung', dienstag, maschine: 'mv', kg: 480);

    await TagesaufgabenService.anlegen(
      db,
      tag: montag,
      abteilung: 'wurstkueche',
      inhalt: 'Kessel entkalken',
    );
    final folie = await TagesaufgabenService.anlegen(
      db,
      tag: dienstag,
      abteilung: 'verpackung',
      inhalt: 'Folie bestellen',
    );
    await TagesaufgabenService.abhaken(db, folie, erledigt: true);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<WeekBoard> woche() async {
    container.invalidate(weekBoardProvider(montag));
    final abo = container.listen(weekBoardProvider(montag), (_, __) {});
    try {
      return await container.read(weekBoardProvider(montag).future);
    } finally {
      abo.close();
    }
  }

  Future<DayBoard> tag(DateTime d) async {
    container.invalidate(dayBoardProvider(d));
    final abo = container.listen(dayBoardProvider(d), (_, __) {});
    try {
      return await container.read(dayBoardProvider(d).future);
    } finally {
      abo.close();
    }
  }

  Future<Map<AufgabenZelle, List<Tagesaufgabe>>> aufgaben() =>
      TagesaufgabenService.fuerZeitraum(
        db,
        von: montag,
        bisExkl: DateTime(2026, 10, 19),
      );

  Future<String> text(pw.Document doc) async => latin1.decode(await doc.save());

  int seiten(pw.Document doc) => doc.document.pdfPageList.pages.length;

  /// Die Seitenangaben aller Fußzeilen: („Seite 2 von 3" → (2, 3)).
  List<(int, int)> seitenAngaben(String t) => [
        for (final m in RegExp(
          r'\(Seite\)\]TJ.*?\((\d+)\)\]TJ.*?\(von\)\]TJ.*?\((\d+)\)\]TJ',
          dotAll: true,
        ).allMatches(t))
          (int.parse(m.group(1)!), int.parse(m.group(2)!)),
      ];

  /// [anzahl] verschiedene Artikel an einem Tag in der Wurstküche — die
  /// Karten im Board bündeln nur gleiche Artikel.
  Future<void> vieleAuftraege(int anzahl) async {
    for (var i = 0; i < anzahl; i++) {
      await seedArtikel(db, id: 'v$i', nummer: '${30000 + i}');
      await auftrag('v$i', 'v$i', 'wurstkueche', montag);
    }
  }

  group('Wochenplan', () {
    test('Übersicht: Artikelnummer, Bezeichnung, Menge und Aufgaben',
        () async {
      final doc = BoardPrintService.wochenDokument(
        await woche(),
        aufgaben: await aufgaben(),
        gedrucktAm: gedruckt,
        komprimiert: false,
      );
      final t = await text(doc);

      expect(seiten(doc), 1);
      for (final wort in [
        'Produktionsplan',
        'KW',
        '42',
        '10815',
        'Rinderpatties',
        '2.156',
        '20417',
        'Wurstküche',
        'Verpackung',
        'Multivac',
        'Tiefzieher',
        'Sonstige',
        'Kessel',
        'entkalken',
        'Folie',
        'Gedruckt',
        '09.10.2026,',
      ]) {
        expect(t, contains('($wort)'), reason: wort);
      }
    });

    test('Zeichen außerhalb von Latin-1 werden ersetzt', () async {
      final t = await text(
        BoardPrintService.wochenDokument(
          await woche(),
          aufgaben: await aufgaben(),
          komprimiert: false,
        ),
      );
      expect(t, contains('("Spezial")'));
      expect(t, contains('(x)'));
    });

    test('ohne sonstige Aufgaben keine Aufgaben-Zeile in der Übersicht',
        () async {
      final t = await text(
        BoardPrintService.wochenDokument(
          await woche(),
          aufgaben: const {},
          komprimiert: false,
        ),
      );
      expect(t, contains('(10815)'));
      expect(t, isNot(contains('(Sonstige)')));
    });

    test('je Abteilung ein eigenes Blatt mit eigener Seitenzählung',
        () async {
      final doc = BoardPrintService.wochenDokument(
        await woche(),
        aufgaben: await aufgaben(),
        abteilungen: const [Abteilung.verpackung, Abteilung.wurstkueche],
        komprimiert: false,
      );
      final t = await text(doc);

      expect(seiten(doc), 2);
      expect(t, contains('(Wochenplan)'));
      expect(t, contains('(Multivac)'));
      expect(t, contains('(Kessel)'));
      // Das Blatt der Abteilung zeigt ihre Aufgaben-Zeile immer — auch
      // zum Nachtragen von Hand.
      expect(t, contains('(Sonstige)'));
      expect(seitenAngaben(t), [(1, 1), (1, 1)]);
    });

    test('ein voller Tag läuft über mehrere Seiten weiter', () async {
      await vieleAuftraege(40);
      final board = await woche();

      final uebersicht = BoardPrintService.wochenDokument(
        board,
        aufgaben: await aufgaben(),
        komprimiert: false,
      );
      expect(seiten(uebersicht), greaterThan(1));

      final blaetter = BoardPrintService.wochenDokument(
        board,
        aufgaben: await aufgaben(),
        abteilungen: const [Abteilung.wurstkueche, Abteilung.verpackung],
        komprimiert: false,
      );
      final n = seiten(blaetter) - 1;
      expect(n, greaterThan(1), reason: 'Die Wurstküche braucht mehr Platz');
      expect(seitenAngaben(await text(blaetter)), [
        for (var i = 1; i <= n; i++) (i, n),
        (1, 1),
      ]);
    });

    test('sehr lange Aufgaben werden gekürzt statt die Seite zu sprengen',
        () async {
      await TagesaufgabenService.anlegen(
        db,
        tag: montag,
        abteilung: 'wurstkueche',
        inhalt: List.filled(1500, 'Wort').join(' '),
      );
      final doc = BoardPrintService.wochenDokument(
        await woche(),
        aufgaben: await aufgaben(),
        abteilungen: const [Abteilung.wurstkueche],
      );
      expect(seiten(doc), 1);
    });

    test('leere Auswahl ist ein Fehler', () async {
      final board = await woche();
      expect(
        () => BoardPrintService.wochenDokument(
          board,
          aufgaben: const {},
          abteilungen: const [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('Tagesplan', () {
    test('Tabelle mit Artikelnummer, ohne leere Start-Spalte', () async {
      final doc = BoardPrintService.tagesDokument(
        await tag(montag),
        aufgaben: await aufgaben(),
        gedrucktAm: gedruckt,
        komprimiert: false,
      );
      final t = await text(doc);

      for (final wort in [
        'Tagesplan',
        'Art.-Nr.',
        'Bezeichnung',
        'Dauer',
        '10815',
        'Rinderpatties',
        '2.156',
        '1:30',
        'Sonstige',
        'Kessel',
        'Keine',
      ]) {
        expect(t, contains('($wort)'), reason: wort);
      }
      expect(t, isNot(contains('(Start)')));
    });

    test('mit Startzeit erscheint die Spalte', () async {
      await auftrag('t3', 'p1', 'bratstrasse', montag, start: '06:30');
      final t = await text(
        BoardPrintService.tagesDokument(
          await tag(montag),
          aufgaben: await aufgaben(),
          komprimiert: false,
        ),
      );
      expect(t, contains('(Start)'));
      expect(t, contains('(06:30)'));
    });

    test('je Abteilung ein eigenes Blatt', () async {
      final doc = BoardPrintService.tagesDokument(
        await tag(dienstag),
        aufgaben: await aufgaben(),
        abteilungen: const [Abteilung.verpackung, Abteilung.zerlegung],
        komprimiert: false,
      );
      final t = await text(doc);

      expect(seiten(doc), 2);
      expect(t, contains('(20417)'));
      expect(t, contains('(Folie)'));
      expect(t, isNot(contains('(10815)')), reason: 'Wurstküche fehlt');
      expect(seitenAngaben(t), [(1, 1), (1, 1)]);
    });

    test('viele Aufträge an einer Spur laufen über die Seite', () async {
      await vieleAuftraege(60);
      final doc = BoardPrintService.tagesDokument(
        await tag(montag),
        aufgaben: await aufgaben(),
        abteilungen: const [Abteilung.wurstkueche],
      );
      expect(seiten(doc), greaterThan(1));
    });
  });

  group('Umfang je Abteilung', () {
    test('Woche und Tag zählen Aufträge und Aufgaben', () async {
      final a = await aufgaben();
      final w = druckUmfangWoche(await woche(), a);
      expect(w[Abteilung.wurstkueche], (auftraege: 1, aufgaben: 1));
      expect(w[Abteilung.verpackung], (auftraege: 1, aufgaben: 1));
      expect(w[Abteilung.zerlegung], (auftraege: 0, aufgaben: 0));
      expect(w.length, Abteilung.values.length);

      final m = druckUmfangTag(await tag(montag), a);
      expect(m[Abteilung.wurstkueche], (auftraege: 1, aufgaben: 1));
      expect(m[Abteilung.verpackung], (auftraege: 0, aufgaben: 0));
    });
  });

  group('PDF-Text', () {
    test('typografische Zeichen werden ersetzt, Latin-1 bleibt', () {
      expect(
        pdfText('„Spezial“ – 2 × 500 g …'),
        '"Spezial" - 2 x 500 g ...',
      );
      expect(pdfText('Müller ½ Ø'), 'Müller ½ Ø');
      expect(pdfText('Rind 🥩'), 'Rind ?');
      expect(pdfText('a\r\nb\tc'), 'a\nb c');
    });
  });

  group('Druck-Dialog', () {
    const umfangWoche = <Abteilung, DruckUmfang>{
      Abteilung.wurstkueche: (auftraege: 3, aufgaben: 1),
      Abteilung.verpackung: (auftraege: 1, aufgaben: 0),
    };
    const umfangTag = <Abteilung, DruckUmfang>{
      Abteilung.verpackung: (auftraege: 2, aufgaben: 0),
    };

    /// Öffnet den Dialog; das Ergebnis steht nach dem Schließen in
    /// [ergebnis] bereit.
    Future<List<BoardDruckAuswahl?>> oeffne(WidgetTester tester) async {
      final ergebnis = <BoardDruckAuswahl?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => ergebnis.add(
                    await zeigeBoardDruckDialog(
                      context,
                      zeitraum: DruckZeitraum.woche,
                      woche: 'KW 42',
                      tag: 'Mo 12.10.',
                      umfangWoche: umfangWoche,
                      umfangTag: umfangTag,
                    ),
                  ),
                  child: const Text('öffnen'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('öffnen'));
      await tester.pumpAndSettle();
      return ergebnis;
    }

    bool aktiv(WidgetTester tester, String label) => tester
        .widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .enabled;

    bool angehakt(WidgetTester tester, String abteilung) => tester
        .widget<CheckboxListTile>(
          find.widgetWithText(CheckboxListTile, abteilung),
        )
        .value!;

    testWidgets('vorgewählt: die gesamte Übersicht der Woche',
        (tester) async {
      final ergebnis = await oeffne(tester);

      await tester.tap(find.text('Drucken'));
      await tester.pumpAndSettle();

      expect(ergebnis, hasLength(1));
      expect(ergebnis.single!.zeitraum, DruckZeitraum.woche);
      expect(ergebnis.single!.abteilungen, isNull);
    });

    testWidgets('einzelne Abteilungen: vorgeschlagen sind die mit Plan',
        (tester) async {
      final ergebnis = await oeffne(tester);

      await tester.tap(find.text('Einzelne Abteilungen'));
      await tester.pumpAndSettle();

      expect(angehakt(tester, 'Wurstküche'), isTrue);
      expect(angehakt(tester, 'Verpackung'), isTrue);
      expect(angehakt(tester, 'Zerlegung'), isFalse);
      expect(find.text('3 Aufträge · 1 Aufgabe'), findsOneWidget);
      expect(find.text('nichts geplant'), findsWidgets);

      await tester.tap(find.text('Drucken · 2 Abteilungen'));
      await tester.pumpAndSettle();

      expect(
        ergebnis.single!.abteilungen,
        [Abteilung.wurstkueche, Abteilung.verpackung],
      );
    });

    testWidgets('ohne Abteilung lässt sich nicht drucken', (tester) async {
      await oeffne(tester);
      await tester.tap(find.text('Einzelne Abteilungen'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keine'));
      await tester.pumpAndSettle();
      expect(aktiv(tester, 'Drucken · 0 Abteilungen'), isFalse);

      await tester.ensureVisible(find.text('Zerlegung'));
      await tester.tap(find.text('Zerlegung'));
      await tester.pumpAndSettle();
      expect(aktiv(tester, 'Drucken · 1 Abteilung'), isTrue);
    });

    testWidgets('der Tag hat seinen eigenen Vorschlag', (tester) async {
      final ergebnis = await oeffne(tester);

      await tester.tap(find.text('Tag · Mo 12.10.'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einzelne Abteilungen'));
      await tester.pumpAndSettle();

      expect(angehakt(tester, 'Wurstküche'), isFalse);
      expect(angehakt(tester, 'Verpackung'), isTrue);

      await tester.tap(find.text('Drucken · 1 Abteilung'));
      await tester.pumpAndSettle();

      expect(ergebnis.single!.zeitraum, DruckZeitraum.tag);
      expect(ergebnis.single!.abteilungen, [Abteilung.verpackung]);
    });

    testWidgets('Abbrechen liefert nichts', (tester) async {
      final ergebnis = await oeffne(tester);

      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(ergebnis, [null]);
    });
  });
}
