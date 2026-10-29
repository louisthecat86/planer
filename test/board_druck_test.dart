import 'dart:convert' show latin1;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_optionen.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';
import 'package:produktion_planer/core/providers/database_provider.dart';
import 'package:produktion_planer/core/services/tagesaufgaben_service.dart';
import 'package:produktion_planer/core/utils/pdf_text.dart';
import 'package:produktion_planer/features/board/board_druck_dialog.dart';
import 'package:produktion_planer/features/board/board_print_service.dart';
import 'package:produktion_planer/features/board/board_providers.dart';

import 'helpers/test_db.dart';

/// Tests für den Druck des Planungsboards: Wochen- und Tagesplan, gesamte
/// Übersicht und je Abteilung ein Blatt, was auf dem Plan steht, dazu die
/// Wahl im Druckfenster.
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

  /// Setzt [dokument] wie das Druckfenster — unkomprimiert, damit sich
  /// der Text lesen lässt.
  Future<(DruckErgebnis, String)> setze(
    DruckDokument dokument, [
    DruckLayout layout = const DruckLayout(),
  ]) async {
    final e = await druckSetzen(dokument, layout, komprimiert: false);
    return (e, latin1.decode(e.bytes));
  }

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
      final dokument = BoardPrintService.wochenDruck(
        await woche(),
        aufgaben: await aufgaben(),
        gedrucktAm: gedruckt,
      );
      final (e, t) = await setze(dokument);

      expect(e.seiten, 1);
      expect(e.format.width, greaterThan(e.format.height), reason: 'quer');
      expect(dokument.dateiname, 'Wochenplan_KW_42');
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
      final (_, t) = await setze(
        BoardPrintService.wochenDruck(
          await woche(),
          aufgaben: await aufgaben(),
        ),
      );
      expect(t, contains('("Spezial")'));
      expect(t, contains('(x)'));
    });

    test('ohne sonstige Aufgaben keine Aufgaben-Zeile in der Übersicht',
        () async {
      final (_, t) = await setze(
        BoardPrintService.wochenDruck(await woche(), aufgaben: const {}),
      );
      expect(t, contains('(10815)'));
      expect(t, isNot(contains('(Sonstige)')));
    });

    test('je Abteilung ein eigenes Blatt mit eigener Seitenzählung',
        () async {
      final (e, t) = await setze(
        BoardPrintService.wochenDruck(
          await woche(),
          aufgaben: await aufgaben(),
          inhalt: const PlanDruckInhalt(
            abteilungen: {Abteilung.verpackung, Abteilung.wurstkueche},
            einzeln: true,
          ),
        ),
      );

      expect(e.blattSeiten, [1, 1]);
      expect(t, contains('(Wochenplan)'));
      expect(t, contains('(Multivac)'));
      expect(t, contains('(Kessel)'));
      // Das Blatt der Abteilung zeigt ihre Aufgaben-Zeile immer — auch
      // zum Nachtragen von Hand.
      expect(t, contains('(Sonstige)'));
      expect(seitenAngaben(t), [(1, 1), (1, 1)]);
      // In der Reihenfolge des Boards: die Wurstküche vor der Verpackung.
      expect(t.indexOf('(Kessel)'), lessThan(t.indexOf('(Multivac)')));
    });

    test('nur die gewählten Abteilungen, auch in der Übersicht', () async {
      final dokument = BoardPrintService.wochenDruck(
        await woche(),
        aufgaben: await aufgaben(),
        inhalt: const PlanDruckInhalt(abteilungen: {Abteilung.verpackung}),
      );
      final (e, t) = await setze(dokument);
      expect(e.blaetter, 1);
      expect(t, contains('(Multivac)'));
      expect(t, isNot(contains('(10815)')));
      expect(t, isNot(contains('(Kessel)')));
    });

    test('nur die gewählten Tage', () async {
      final (_, t) = await setze(
        BoardPrintService.wochenDruck(
          await woche(),
          aufgaben: await aufgaben(),
          inhalt: const PlanDruckInhalt(wochentage: {1}),
        ),
      );
      expect(t, contains('(Montag)'));
      expect(t, isNot(contains('(Dienstag)')));
      expect(t, contains('(10815)'));
      // Der Auftrag der Verpackung liegt am Dienstag.
      expect(t, isNot(contains('(20417)')));
      expect(t, isNot(contains('(Folie)')));
    });

    test('ohne Erledigtes, ohne Aufgaben, ohne leere Anlagen', () async {
      final board = await woche();
      final alle = await aufgaben();

      final (_, ohneErledigte) = await setze(
        BoardPrintService.wochenDruck(
          board,
          aufgaben: alle,
          inhalt: const PlanDruckInhalt(erledigte: false),
        ),
      );
      expect(ohneErledigte, contains('(Kessel)'));
      expect(ohneErledigte, isNot(contains('(Folie)')));

      final (_, ohneAufgaben) = await setze(
        BoardPrintService.wochenDruck(
          board,
          aufgaben: alle,
          inhalt: const PlanDruckInhalt(aufgaben: false),
        ),
      );
      expect(ohneAufgaben, isNot(contains('(Sonstige)')));
      expect(ohneAufgaben, isNot(contains('(Kessel)')));

      final (_, ohneLeere) = await setze(
        BoardPrintService.wochenDruck(
          board,
          aufgaben: alle,
          inhalt: const PlanDruckInhalt(leereSpuren: false),
        ),
      );
      expect(ohneLeere, contains('(Multivac)'));
      expect(ohneLeere, isNot(contains('(Tiefzieher)')));
    });

    test('ohne Kästchen weniger Rahmen', () async {
      final board = await woche();
      final alle = await aufgaben();
      int rahmen(String t) => RegExp(r' re ').allMatches(t).length;

      final (_, mit) = await setze(
        BoardPrintService.wochenDruck(board, aufgaben: alle),
      );
      final (_, ohne) = await setze(
        BoardPrintService.wochenDruck(
          board,
          aufgaben: alle,
          inhalt: const PlanDruckInhalt(kaestchen: false),
        ),
      );
      expect(rahmen(ohne), lessThan(rahmen(mit)));
      expect(ohne, contains('(10815)'));
    });

    test('ein voller Tag läuft über mehrere Seiten weiter', () async {
      await vieleAuftraege(40);
      final board = await woche();

      final (uebersicht, _) = await setze(
        BoardPrintService.wochenDruck(board, aufgaben: await aufgaben()),
      );
      expect(uebersicht.seiten, greaterThan(1));

      final (blaetter, t) = await setze(
        BoardPrintService.wochenDruck(
          board,
          aufgaben: await aufgaben(),
          inhalt: const PlanDruckInhalt(
            abteilungen: {Abteilung.wurstkueche, Abteilung.verpackung},
            einzeln: true,
          ),
        ),
      );
      final n = blaetter.blattSeiten.first;
      expect(n, greaterThan(1), reason: 'Die Wurstküche braucht mehr Platz');
      expect(blaetter.blattSeiten.last, 1);
      expect(seitenAngaben(t), [
        for (var i = 1; i <= n; i++) (i, n),
        (1, 1),
      ]);
    });

    test('alles auf eine Seite: je Abteilung ein Blatt, je Blatt eine Seite',
        () async {
      await vieleAuftraege(40);
      final (e, t) = await setze(
        BoardPrintService.wochenDruck(
          await woche(),
          aufgaben: await aufgaben(),
          inhalt: const PlanDruckInhalt(
            abteilungen: {Abteilung.wurstkueche, Abteilung.verpackung},
            einzeln: true,
          ),
        ),
        const DruckLayout(anpassung: DruckAnpassung.eineSeite),
      );
      expect(e.blattSeiten, [1, 1]);
      expect(e.passtNicht, isFalse);
      expect(e.massstaebe.first, lessThan(1));
      expect(e.massstaebe.last, 1);
      expect(seitenAngaben(t), [(1, 1), (1, 1)]);
    });

    test('sehr lange Aufgaben werden gekürzt statt die Seite zu sprengen',
        () async {
      await TagesaufgabenService.anlegen(
        db,
        tag: montag,
        abteilung: 'wurstkueche',
        inhalt: List.filled(1500, 'Wort').join(' '),
      );
      final (e, _) = await setze(
        BoardPrintService.wochenDruck(
          await woche(),
          aufgaben: await aufgaben(),
          inhalt: const PlanDruckInhalt(
            abteilungen: {Abteilung.wurstkueche},
            einzeln: true,
          ),
        ),
      );
      expect(e.seiten, 1);
    });

    test('leere Auswahl ist ein Fehler', () async {
      final board = await woche();
      expect(
        () => BoardPrintService.wochenDruck(
          board,
          aufgaben: const {},
          inhalt: const PlanDruckInhalt(abteilungen: {}),
        ),
        throwsArgumentError,
      );
      expect(
        () => BoardPrintService.wochenDruck(
          board,
          aufgaben: const {},
          inhalt: const PlanDruckInhalt(wochentage: {6, 7}),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Tagesplan', () {
    test('Tabelle mit Artikelnummer, ohne leere Start-Spalte', () async {
      final dokument = BoardPrintService.tagesDruck(
        await tag(montag),
        aufgaben: await aufgaben(),
        gedrucktAm: gedruckt,
      );
      final (e, t) = await setze(dokument);

      expect(e.format.width, lessThan(e.format.height), reason: 'hoch');
      expect(dokument.dateiname, 'Tagesplan_2026-10-12');
      for (final wort in [
        'Tagesplan',
        'Art.-Nr.',
        'Bezeichnung',
        'Dauer',
        'Belegt',
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
      final (_, t) = await setze(
        BoardPrintService.tagesDruck(
          await tag(montag),
          aufgaben: await aufgaben(),
        ),
      );
      expect(t, contains('(Start)'));
      expect(t, contains('(06:30)'));
    });

    test('ohne Dauer und Belegung, ohne leere Spuren', () async {
      final (_, t) = await setze(
        BoardPrintService.tagesDruck(
          await tag(montag),
          aufgaben: await aufgaben(),
          inhalt: const PlanDruckInhalt(belegung: false, leereSpuren: false),
        ),
      );
      expect(t, contains('(10815)'));
      expect(t, isNot(contains('(Dauer)')));
      expect(t, isNot(contains('(Belegt)')));
      expect(t, isNot(contains('(Keine)')));
    });

    test('je Abteilung ein eigenes Blatt', () async {
      final dokument = BoardPrintService.tagesDruck(
        await tag(dienstag),
        aufgaben: await aufgaben(),
        inhalt: const PlanDruckInhalt(
          abteilungen: {Abteilung.verpackung, Abteilung.zerlegung},
          einzeln: true,
        ),
      );
      final (e, t) = await setze(dokument);

      expect(e.blattSeiten, [1, 1]);
      expect(t, contains('(20417)'));
      expect(t, contains('(Folie)'));
      expect(t, isNot(contains('(10815)')), reason: 'Wurstküche fehlt');
      expect(seitenAngaben(t), [(1, 1), (1, 1)]);
    });

    test('nur eine Abteilung: ihr Name im Dateinamen', () async {
      final dokument = BoardPrintService.tagesDruck(
        await tag(dienstag),
        aufgaben: await aufgaben(),
        inhalt: const PlanDruckInhalt(
          abteilungen: {Abteilung.verpackung},
          einzeln: true,
        ),
      );
      expect(dokument.dateiname, 'Tagesplan_2026-10-13_Verpackung');
    });

    test('viele Aufträge an einer Spur laufen über die Seite', () async {
      await vieleAuftraege(60);
      final (e, _) = await setze(
        BoardPrintService.tagesDruck(
          await tag(montag),
          aufgaben: await aufgaben(),
          inhalt: const PlanDruckInhalt(
            abteilungen: {Abteilung.wurstkueche},
            einzeln: true,
          ),
        ),
      );
      expect(e.seiten, greaterThan(1));
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

      expect(
        druckUmfangText((auftraege: 3, aufgaben: 1)),
        '3 Aufträge · 1 Aufgabe',
      );
      expect(druckUmfangText((auftraege: 1, aufgaben: 0)), '1 Auftrag');
      expect(druckUmfangText((auftraege: 0, aufgaben: 0)), 'nichts geplant');
    });
  });

  group('Wahl im Druckfenster', () {
    Future<DruckAuftrag> plan({
      DruckZeitraum zeitraum = DruckZeitraum.woche,
    }) async =>
        planDruckAuftrag(
          woche: await woche(),
          tag: await tag(montag),
          aufgaben: await aufgaben(),
          zeitraum: zeitraum,
          gedrucktAm: gedruckt,
        );

    DruckOption option(DruckAuftrag a, String schluessel) =>
        a.optionen.firstWhere((o) => o.schluessel == schluessel);

    test('vorgewählt: der Zeitraum des Boards, die Abteilungen mit Plan',
        () async {
      final a = await plan();
      final wahl = DruckWahl.standard(a.optionen);
      expect(wahl.eins(PlanDruckWahl.zeitraum), 'woche');
      expect(wahl.eins(PlanDruckWahl.umfang), 'uebersicht');
      expect(
        wahl.mehrere(PlanDruckWahl.abteilungenWoche),
        {'wurstkueche', 'verpackung'},
      );
      // Am Montag hat nur die Wurstküche etwas zu tun.
      expect(wahl.mehrere(PlanDruckWahl.abteilungenTag), {'wurstkueche'});
      expect(wahl.mehrere(PlanDruckWahl.tage), {'1', '2', '3', '4', '5'});

      final tagesPlan = await plan(zeitraum: DruckZeitraum.tag);
      expect(
        DruckWahl.standard(tagesPlan.optionen).eins(PlanDruckWahl.zeitraum),
        'tag',
      );
    });

    test('Woche und Tag zeigen je ihre eigenen Möglichkeiten', () async {
      final a = await plan();
      final woche = DruckWahl.standard(a.optionen);
      final tag = woche.mit(PlanDruckWahl.zeitraum, 'tag');
      for (final (schluessel, inWoche, amTag) in [
        (PlanDruckWahl.abteilungenWoche, true, false),
        (PlanDruckWahl.abteilungenTag, false, true),
        (PlanDruckWahl.tage, true, false),
        (PlanDruckWahl.belegung, false, true),
        (PlanDruckWahl.kaestchen, true, true),
      ]) {
        final o = option(a, schluessel);
        expect(o.istSichtbar(woche), inWoche, reason: schluessel);
        expect(o.istSichtbar(tag), amTag, reason: schluessel);
      }
      final wurstkueche = (option(a, PlanDruckWahl.abteilungenWoche)
              as DruckWahlMehrere)
          .werte
          .firstWhere((w) => w.wert == 'wurstkueche');
      expect(wurstkueche.hinweis, '1 Auftrag · 1 Aufgabe');
      expect(wurstkueche.kuerzel, 'WK');
    });

    test('aus der Wahl entsteht das Dokument', () async {
      final a = await plan();
      final standard = DruckWahl.standard(a.optionen);

      final (uebersicht, t) = await setze(await a.bauen(standard));
      expect(uebersicht.blaetter, 1);
      expect(t, contains('(Kessel)'));
      expect(t, contains('(Multivac)'));

      final (einzeln, _) = await setze(
        await a.bauen(standard.mit(PlanDruckWahl.umfang, 'einzeln')),
      );
      expect(einzeln.blaetter, 2);

      final (tag, tagText) = await setze(
        await a.bauen(standard.mit(PlanDruckWahl.zeitraum, 'tag')),
      );
      expect(tag.format.width, lessThan(tag.format.height));
      expect(tagText, contains('(Tagesplan)'));
      expect(tagText, contains('(10815)'));

      final (ohne, ohneText) = await setze(
        await a.bauen(
          standard
              .mit(PlanDruckWahl.aufgaben, false)
              .mit(PlanDruckWahl.tage, {'2'}),
        ),
      );
      expect(ohne.seiten, 1);
      expect(ohneText, isNot(contains('(Kessel)')));
      expect(ohneText, contains('(20417)'));
    });

    test('ohne Abteilung oder Tag sagt es, was fehlt', () async {
      final a = await plan();
      final standard = DruckWahl.standard(a.optionen);
      expect(
        () => a.bauen(
          standard.mit(PlanDruckWahl.abteilungenWoche, <String>{}),
        ),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
      expect(
        () => a.bauen(standard.mit(PlanDruckWahl.tage, <String>{})),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
      // Am Tag zählen die Tage der Woche nicht.
      final tag = standard
          .mit(PlanDruckWahl.zeitraum, 'tag')
          .mit(PlanDruckWahl.tage, <String>{});
      expect(await a.bauen(tag), isA<DruckDokument>());
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
}
