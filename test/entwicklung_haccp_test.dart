import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/parameter_namen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/auto_backup_trigger.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/freigabe/freigabe.dart';
import 'package:produktion_planer/features/entwicklung/haccp/anlagen_katalog.dart';
import 'package:produktion_planer/features/entwicklung/haccp/eingabe_dialoge.dart';
import 'package:produktion_planer/features/entwicklung/haccp/haccp_ansicht.dart';
import 'package:produktion_planer/features/entwicklung/haccp/haccp_modell.dart';
import 'package:produktion_planer/features/entwicklung/haccp/kette_bausteine.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_kette.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/fliessdiagramme_dialog.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_screen.dart';

import 'helpers/test_db.dart';

/// Tests für die Gefahrenanalyse und die Fließdiagramme — und die Reiter
/// „Herstellung" einer Projektseite mit der Prozesskette und HACCP. Das
/// Modell der Kette prüft entwicklung_prozesskette_test.dart. Alles
/// erfunden.
void main() {
  group('Entscheidungsbaum', () {
    test('alle Wege wie im HACCP-Konzept', () {
      expect(baumWeg(const {}).frage, 'f1');
      expect(baumWeg(const {'f1': true}).frage, 'f2');
      // Frage 2 ja: CCP.
      expect(baumWeg(const {'f1': true, 'f2': true}).ende, BaumEnde.ccp);
      expect(baumWeg(const {'f1': true, 'f2': false}).frage, 'f3');
      // Frage 3 nein: CP.
      expect(
        baumWeg(const {'f1': true, 'f2': false, 'f3': false}).ende,
        BaumEnde.cp,
      );
      // Frage 4 ja: CP, nein: CCP.
      expect(
        baumWeg(const {'f1': true, 'f2': false, 'f3': true, 'f4': true}).ende,
        BaumEnde.cp,
      );
      expect(
        baumWeg(const {'f1': true, 'f2': false, 'f3': true, 'f4': false}).ende,
        BaumEnde.ccp,
      );
      // Frage 1 nein: die Zusatzfrage — ja: modifizieren, nein: CP.
      expect(baumWeg(const {'f1': false}).frage, 'f1b');
      expect(
        baumWeg(const {'f1': false, 'f1b': true}).ende,
        BaumEnde.modifizieren,
      );
      expect(
        baumWeg(const {'f1': false, 'f1b': false}).ende,
        BaumEnde.cp,
      );
      expect(
        [for (final f in kEntscheidungsbaum.values) f.nummer],
        ['Frage 1', 'Zusatzfrage zu Frage 1', 'Frage 2', 'Frage 3', 'Frage 4'],
      );
      expect(
        [for (final f in kEntscheidungsbaum.values) f.kurz],
        ['F1', 'F1 Zusatz', 'F2', 'F3', 'F4'],
      );
      // Frühere Ziele gelten weiter.
      expect(BaumEnde.aus('ergebnis:KP'), BaumEnde.cp);
      expect(BaumEnde.aus('ergebnis:ANPASSEN'), BaumEnde.modifizieren);
    });

    test('Risiko: gering, mittel, hoch', () {
      expect(risikoText(2), 'gering');
      expect(risikoText(4), 'mittel');
      expect(risikoText(6), 'hoch');
      expect(risikoArt(9), StatusArt.fehler);
      expect(risikoArt(1), StatusArt.ok);
    });

    testWidgets('der Assistent führt bis zum CCP', (tester) async {
      HaccpErgebnis? ergebnis;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  ergebnis = await showDialog<HaccpErgebnis>(
                    context: context,
                    builder: (_) => const HaccpAssistent(),
                  );
                },
                child: const Text('los'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('los'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Gefahr'),
        'Metallteile',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Prozessschritt'),
        'Metalldetektion',
      );
      await tester.tap(find.text('3 · schwer'));
      await tester.tap(find.text('2 · möglich'));
      await tester.pump();
      expect(find.textContaining('Risiko 6: hoch'), findsOneWidget);

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.text(kEntscheidungsbaum['f1']!.text), findsOneWidget);
      await tester.tap(find.text('Ja'));
      await tester.pumpAndSettle();
      expect(find.text(kEntscheidungsbaum['f2']!.text), findsOneWidget);
      await tester.tap(find.text('Ja'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Kritischer Lenkungspunkt'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Lenkung'),
        'Prüfkörper je Schicht',
      );
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();

      final e = ergebnis!;
      expect(e.gefahr.gefahr, 'Metallteile');
      expect(e.gefahr.risiko, 6);
      final punkt = e.lenkungspunkt!;
      expect(punkt.ergebnis, Lenkungsart.ccp);
      expect(punkt.schritt, 'Metalldetektion');
      expect(punkt.antworten, {'f1': true, 'f2': true});
      expect(punkt.lenkung, 'Prüfkörper je Schicht');
    });

    testWidgets('modifizieren: neu prüfen beginnt wieder bei Frage 1',
        (tester) async {
      HaccpErgebnis? ergebnis;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  ergebnis = await showDialog<HaccpErgebnis>(
                    context: context,
                    builder: (_) => const HaccpAssistent(),
                  );
                },
                child: const Text('los'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('los'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Gefahr'),
        'Listerien',
      );
      await tester.tap(find.text('3 · schwer'));
      await tester.tap(find.text('2 · möglich'));
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(find.text('Frage 1'), findsOneWidget);
      await tester.tap(find.text('Nein'));
      await tester.pumpAndSettle();
      expect(find.text('Zusatzfrage zu Frage 1'), findsOneWidget);
      expect(find.text(kEntscheidungsbaum['f1b']!.text), findsOneWidget);
      await tester.tap(find.text('Ja'));
      await tester.pumpAndSettle();
      expect(find.textContaining('modifizieren'), findsOneWidget);

      // Nach der Änderung: wieder bei Frage 1, diesmal bis zum CCP.
      await tester.tap(find.text('Neu prüfen'));
      await tester.pumpAndSettle();
      expect(find.text(kEntscheidungsbaum['f1']!.text), findsOneWidget);
      await tester.tap(find.text('Ja'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ja'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Kritischer Lenkungspunkt'), findsOneWidget);
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(ergebnis!.lenkungspunkt!.ergebnis, Lenkungsart.ccp);
      expect(ergebnis!.lenkungspunkt!.antworten, {'f1': true, 'f2': true});
    });

    testWidgets('geringes Risiko braucht keinen Lenkungspunkt', (tester) async {
      HaccpErgebnis? ergebnis;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  ergebnis = await showDialog<HaccpErgebnis>(
                    context: context,
                    builder: (_) => const HaccpAssistent(),
                  );
                },
                child: const Text('los'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('los'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Gefahr'),
        'Folienreste',
      );
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hygienepraxis'), findsWidgets);
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(ergebnis!.gefahr.risiko, 1);
      expect(ergebnis!.lenkungspunkt, isNull);
    });
  });

  group('Fließdiagramme', () {
    test('eine eingefügte Liste wird gelesen', () {
      final liste = fliessdiagrammeAusText(
        'FD_001 Testware A\n'
        '\n'
        'FD_002;Testware B\n'
        'FD_003\tTestware C\n'
        'FD_004 – Testware D\n'
        'FD_005\n'
        'FD_001 doppelt\n',
      );
      expect([
        for (final f in liste) f.id,
      ], [
        'FD_001',
        'FD_002',
        'FD_003',
        'FD_004',
        'FD_005',
      ]);
      expect(liste[0].bezeichnung, 'Testware A');
      expect(liste[1].bezeichnung, 'Testware B');
      expect(liste[2].bezeichnung, 'Testware C');
      expect(liste[3].bezeichnung, 'Testware D');
      expect(liste[4].bezeichnung, 'FD_005');
    });

    test('ordnen', () async {
      final db = testDatenbank();
      addTearDown(db.close);
      final repo = ProjektRepository(db);
      for (final id in ['A', 'B', 'C']) {
        await repo.fliessdiagrammSpeichern(id: id, bezeichnung: id);
      }
      await repo.fliessdiagrammeOrdnen(['C', 'A', 'B']);
      final liste = await repo.fliessdiagrammeBeobachten().first;
      expect([for (final f in liste) f.id], ['C', 'A', 'B']);
    });
  });

  group('Seiten', () {
    final zeit = DateTime(2026, 10, 16);
    const kette = [
      ProzessSchritt(
        id: 's1',
        abteilung: 'zerlegung',
        maschineId: 'm-wolf',
        maschine: 'Testwolf',
        prozessschritt: 'Wolfen',
      ),
      ProzessSchritt(
        id: 's2',
        abteilung: 'bratstrasse',
        maschineId: 'm-brat',
        maschine: 'Testbratstraße',
        werte: [
          ProzessWert(
            name: 'Bandgeschwindigkeit',
            wert: '4',
            einheit: 'm/min',
            gruppe: kMaschinenNotizGruppe,
          ),
        ],
      ),
    ];
    final prozess = Prozessparameter(
      version: '1.1',
      stand: zeit,
      schritte: kette,
    );
    const haccp = Haccp(
      gefahren: [
        Gefahr(
          id: 'g1',
          gefahr: 'Metallteile',
          schwere: 3,
          wahrscheinlichkeit: 2,
          massnahmen: 'Metalldetektor',
        ),
        Gefahr(id: 'g2', gefahr: 'Folienreste'),
      ],
      lenkungspunkte: [
        Lenkungspunkt(
          id: 'l1',
          schritt: 'Metalldetektion',
          antworten: {'f1': true, 'f2': true},
          ergebnis: Lenkungsart.ccp,
          lenkung: 'Prüfkörper je Schicht',
        ),
        // Frage 1 nein, Zusatzfrage nein: CP.
        Lenkungspunkt(
          id: 'l2',
          schritt: 'Verpacken',
          antworten: {'f1': false, 'f1b': false},
          ergebnis: Lenkungsart.cp,
        ),
      ],
    );

    EntwicklungsProjekt projekt({
      String? prozessJson,
      List<ProzessStand>? historie,
    }) =>
        EntwicklungsProjekt(
          id: 'p1',
          name: 'Schnitzel Wiener Art',
          status: 'entwicklung',
          neuerProzess: true,
          neueZutaten: false,
          prozess: prozessJson,
          prozessHistorie: ProzessStand.listeZuJson(
            historie ??
                [
                  ProzessStand(
                    version: '1.0',
                    datum: zeit,
                    parameter: prozess.kopie(version: '1.0'),
                  ),
                  ProzessStand(
                    version: '1.1',
                    datum: zeit,
                    notiz: 'Band schneller',
                    parameter: prozess,
                  ),
                ],
          ),
          haccp: haccp.alsJson(),
          createdAt: zeit,
          updatedAt: zeit,
        );

    // Was gespeichert würde — der Prozess speichert sich selbst (F29).
    late _Speicher speicher;
    setUp(() => speicher = _Speicher());

    Future<void> zeige(
      WidgetTester tester,
      EntwicklungsProjekt p, {
      Size groesse = const Size(1400, 900),
    }) async {
      tester.view.physicalSize = groesse;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projektRepositoryProvider.overrideWithValue(speicher),
            autoBackupTriggerProvider.overrideWithValue(_OhneSicherung()),
            anlagenQuelleProvider.overrideWithValue(_Quelle()),
            projektProvider.overrideWith((ref, id) => Stream.value(p)),
            projektEintraegeProvider
                .overrideWith((ref, id) => Stream.value(const [])),
            projektDateienProvider
                .overrideWith((ref, id) => Stream.value(const [])),
            projektRezepturenProvider
                .overrideWith((ref, id) => Stream.value(const [])),
            fliessdiagrammeProvider
                .overrideWith((ref) => Stream.value(const [])),
            alleVersionenProvider.overrideWith((ref) => Stream.value(const [])),
            freigabeUebersichtProvider.overrideWith(
              (ref, id) async => const FreigabeUebersicht(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ProjektScreen(projektId: 'p1')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> reiter(WidgetTester tester, String name) async {
      final tab = find.widgetWithText(Tab, name);
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Der Katalog der Anlagen kommt nach.
      await tester.pump();
      await tester.pump();
    }

    // Fenster blenden in 150 ms ein und aus.
    Future<void> bilder(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    String fassung(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('prozess-fassung')))
        .data!;

    /// [text] im obersten Fenster der Art [T].
    Finder imFenster<T>(String text) => find.descendant(
          of: find.byType(T),
          matching: find.text(text),
        );

    testWidgets('Prozess: die Kette wie im Artikel — Werte, zurück, festhalten',
        (tester) async {
      await zeige(tester, projekt(prozessJson: prozess.alsJson()));
      await reiter(tester, 'Herstellung');

      // Der Stand entspricht der zuletzt festgehaltenen Version.
      expect(fassung(tester), 'Version 1.1 vom 16.10.2026');
      expect(find.byKey(const ValueKey('prozess-festhalten')), findsNothing);
      expect(find.textContaining('Band schneller'), findsOneWidget);
      // Stationen nach Abteilung, darin die Anlagen mit ihren Werten.
      expect(find.text('Zerlegung'), findsOneWidget);
      expect(find.text('Bratstraße'), findsOneWidget);
      expect(find.text('Testwolf'), findsOneWidget);
      expect(find.text('Wolfen'), findsOneWidget);
      expect(find.text('0/1 Werte'), findsOneWidget);
      // Bandgeschwindigkeit ja, Platten noch nicht.
      expect(find.text('1/2 Werte'), findsOneWidget);

      // Antippen öffnet den Schritt: Plattenschema und Steckbrief.
      await tester.tap(find.byKey(const ValueKey('prozess-schritt-s2')));
      await bilder(tester);
      expect(find.byKey(const ValueKey('schritt-blatt')), findsOneWidget);
      expect(find.text('Plattentemperaturen (oben / unten)'), findsOneWidget);
      // Titel und Zusatz stehen in einem Text: „Testbratstraße   Steckbrief".
      expect(find.textContaining('Steckbrief'), findsOneWidget);
      expect(find.text('Bandgeschwindigkeit (m/min)'), findsOneWidget);

      // Ein Wert mit den Grenzen aus der Planung: über der harten gesperrt,
      // über der weichen ein Hinweis.
      await tester.tap(
        find.byKey(const ValueKey('steckbrief-Bandgeschwindigkeit')),
      );
      await bilder(tester);
      final eingabe = find.byKey(const ValueKey('wert-eingabe'));
      await tester.enterText(eingabe, '9');
      await tester.pump();
      expect(find.text('Über der technischen Obergrenze (8).'), findsOneWidget);
      await tester.tap(imFenster<WertDialog>('Speichern'));
      await bilder(tester);
      expect(find.byType(WertDialog), findsOneWidget);
      await tester.enterText(eingabe, '7');
      await tester.pump();
      expect(
        find.text('Ungewöhnlich hoch — üblich ist bis 6.'),
        findsOneWidget,
      );
      await tester.enterText(eingabe, '5');
      await tester.pump();
      await tester.tap(imFenster<WertDialog>('Speichern'));
      await bilder(tester);
      expect(find.byType(WertDialog), findsNothing);
      // Sofort gespeichert.
      expect(speicher.prozess, contains('"wert":"5"'));
      await tester.tap(find.byKey(const ValueKey('schritt-schliessen')));
      await bilder(tester);
      expect(find.byKey(const ValueKey('schritt-blatt')), findsNothing);
      expect(fassung(tester), 'Version 1.1 vom 16.10.2026, seitdem geändert');

      // Zurück zur festgehaltenen Version — nach einer Rückfrage.
      await tester.tap(find.byKey(const ValueKey('prozess-mehr')));
      await bilder(tester);
      expect(find.text('Versionen vergleichen…'), findsOneWidget);
      await tester.tap(find.text('Zurück zu Version 1.1…'));
      await bilder(tester);
      expect(find.text('Zurück zu Version 1.1?'), findsOneWidget);
      await tester.tap(find.text('Zurücksetzen'));
      await bilder(tester);
      expect(speicher.prozess, contains('"wert":"4"'));
      expect(fassung(tester), 'Version 1.1 vom 16.10.2026');

      // Eine eigene Angabe, dann festhalten: die nächste Nummer, mit
      // Notiz — auch im Verlauf.
      await tester.tap(find.byKey(const ValueKey('prozess-schritt-s1')));
      await bilder(tester);
      await tester.tap(find.byKey(const ValueKey('eigener-wert-neu')));
      await bilder(tester);
      await tester.enterText(
        find.byKey(const ValueKey('eigener-wert-name')),
        'Kerntemperatur',
      );
      await tester.enterText(
        find.byKey(const ValueKey('eigener-wert-wert')),
        '2 °C',
      );
      await tester.tap(imFenster<EigenerWertDialog>('Übernehmen'));
      await bilder(tester);
      expect(find.text('2 °C'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('schritt-schliessen')));
      await bilder(tester);
      expect(find.text('0/2 Werte'), findsNothing);
      expect(find.text('1/2 Werte'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('prozess-festhalten')));
      await bilder(tester);
      expect(find.text('Version 1.2 festhalten'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(TextEingabeDialog),
          matching: find.byType(TextField),
        ),
        'Kerntemperatur beim Wolfen',
      );
      await tester.tap(imFenster<TextEingabeDialog>('Festhalten'));
      await bilder(tester);
      final historie = speicher.gespeichert.last.prozessHistorie.value;
      expect(historie, contains('"version":"1.2"'));
      expect(historie, contains('Kerntemperatur beim Wolfen'));
      expect(speicher.eintraege, ['Prozessparameter 1.2']);
      expect(fassung(tester), startsWith('Version 1.2 vom '));
      expect(find.byKey(const ValueKey('prozess-festhalten')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Prozess: leer — Station, Anlage, Schritt ohne Anlage',
        (tester) async {
      await zeige(tester, projekt(historie: const []));
      await reiter(tester, 'Herstellung');
      expect(find.textContaining('Noch keine Prozesskette'), findsOneWidget);
      expect(find.byKey(const ValueKey('prozess-mehr')), findsNothing);

      // Die erste Anlage: alle nach Abteilung.
      await tester.tap(find.byKey(const ValueKey('prozess-erste-anlage')));
      await bilder(tester);
      expect(find.text('Neue Station'), findsOneWidget);
      expect(imFenster<AnlagenWahl>('Verpackung'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('anlage-m-wolf')));
      await bilder(tester);
      expect(find.text('Zerlegung'), findsOneWidget);
      expect(find.text('Testwolf'), findsOneWidget);
      expect(speicher.prozess, contains('Testwolf'));
      expect(fassung(tester), 'Noch keine Version festgehalten');

      // „+ Anlage": erst die eigene Abteilung, die anderen auf Wunsch —
      // und ganz unten ein Schritt ohne Anlage.
      await tester.tap(find.byKey(const ValueKey('prozess-plus-0')));
      await bilder(tester);
      expect(find.text('Anlage für Zerlegung'), findsOneWidget);
      expect(find.byKey(const ValueKey('anlage-m-pack')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('anlage-andere')));
      await bilder(tester);
      expect(find.byKey(const ValueKey('anlage-m-pack')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('anlage-ohne')));
      await bilder(tester);
      expect(find.text('Schritt ohne Anlage'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('schritt-prozessschritt')),
        'Abkühlen',
      );
      await tester.tap(imFenster<SchrittDialog>('Hinzufügen'));
      await bilder(tester);
      expect(find.text('Abkühlen'), findsOneWidget);

      // Eine neue Station am Ende.
      await tester.tap(find.byKey(const ValueKey('prozess-neue-station')));
      await bilder(tester);
      await tester.tap(find.byKey(const ValueKey('anlage-m-pack')));
      await bilder(tester);
      expect(find.text('Verpackung'), findsOneWidget);
      final gespeichert = Prozessparameter.aus(speicher.prozess);
      expect(
        [for (final s in gespeichert.schritte) '${s.abteilung}:${s.name}'],
        ['zerlegung:Testwolf', 'zerlegung:Abkühlen', 'verpackung:Testpacker'],
      );
      expect(find.byKey(const ValueKey('prozess-festhalten')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Prozess: frühere Abschnitte werden zur Kette (F34)',
        (tester) async {
      const frueher = Prozessparameter(
        version: '1.1',
        abschnitte: [
          ProzessAbschnitt(
            id: 'garen',
            titel: 'Garen und Braten',
            felder: [
              ProzessFeld(
                id: 'anlage',
                label: 'Anlage',
                wert: 'Testbratstraße',
              ),
              ProzessFeld(id: 'b', label: 'Bandgeschwindigkeit', wert: '4'),
            ],
          ),
          // Nie ausgefüllt — entfällt.
          ProzessAbschnitt(
            id: 'formen',
            titel: 'Formen',
            felder: [ProzessFeld(id: 'f', label: 'Form')],
          ),
        ],
      );
      final alt = frueher.kopie(stand: zeit);
      await zeige(
        tester,
        projekt(
          prozessJson: alt.alsJson(),
          historie: [ProzessStand(version: '1.1', datum: zeit, parameter: alt)],
        ),
      );
      await reiter(tester, 'Herstellung');
      await bilder(tester);

      expect(
        find.byKey(const ValueKey('prozess-umgesetzt')),
        findsOneWidget,
      );
      expect(
        find.textContaining('1 Schritt, ein leerer Abschnitt ist entfallen'),
        findsOneWidget,
      );
      expect(find.text('Bratstraße'), findsOneWidget);
      expect(find.text('Testbratstraße'), findsOneWidget);
      expect(find.text('Garen und Braten'), findsOneWidget);
      // Die festgehaltene Version wurde mit umgesetzt — nichts geändert.
      expect(fassung(tester), 'Version 1.1 vom 16.10.2026');
      final daten = speicher.gespeichert.single;
      expect(daten.prozess.value, contains('"schritte"'));
      expect(daten.prozess.value, isNot(contains('"abschnitte"')));
      expect(daten.prozessHistorie.value, contains('"schritte"'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Prozess: die Kette aus einem Artikel übernehmen',
        (tester) async {
      await zeige(tester, projekt(historie: const []));
      await reiter(tester, 'Herstellung');
      await tester.tap(find.byKey(const ValueKey('prozess-aus-artikel')));
      await bilder(tester);
      expect(find.text('1001 · Testware'), findsOneWidget);
      expect(find.text('2 Schritte'), findsOneWidget);
      await tester.tap(find.text('1001 · Testware'));
      await bilder(tester);
      expect(find.text('Testwolf'), findsOneWidget);
      expect(find.text('Testbratstraße'), findsOneWidget);
      expect(
        find.text('Kette von Artikel 1001 übernommen — 2 Schritte.'),
        findsOneWidget,
      );
      expect(Prozessparameter.aus(speicher.prozess).schritte, hasLength(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('HACCP: Gefahren mit Risiko und Lenkungspunkte',
        (tester) async {
      await zeige(tester, projekt(prozessJson: prozess.alsJson()));
      await reiter(tester, 'Herstellung');

      expect(find.text('Metallteile'), findsOneWidget);
      expect(find.text('Risiko 6 · hoch'), findsOneWidget);
      expect(find.text('Risiko 1 · gering'), findsOneWidget);
      expect(find.text('Metalldetektion'), findsOneWidget);
      expect(find.text('CCP'), findsOneWidget);
      expect(find.textContaining('F1 Ja · F2 Ja'), findsOneWidget);
      // Die Zusatzfrage steht mit in der Zeile.
      expect(find.text('Verpacken'), findsOneWidget);
      expect(find.textContaining('F1 Nein · F1 Zusatz Nein'), findsOneWidget);
      expect(find.text('CP'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is BereichKopf && w.untertitel == '1 CCP · 1 CP',
        ),
        findsOneWidget,
      );
    });

    testWidgets('HACCP schmal: kein Überlauf, Hinweis bei neuem Prozess',
        (tester) async {
      final p = projekt();
      await zeige(
        tester,
        EntwicklungsProjekt.fromJson({...p.toJson(), 'haccp': null}),
        groesse: const Size(640, 800),
      );
      await reiter(tester, 'Herstellung');
      // Schmal: erst der Prozess, HACCP zum Umschalten.
      expect(find.textContaining('Gefahrenanalyse fehlt noch'), findsNothing);
      await tester.tap(find.text('HACCP'));
      await tester.pump();
      expect(find.textContaining('Gefahrenanalyse fehlt noch'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Herstellung: breit nebeneinander, schmal umschalten',
        (tester) async {
      await zeige(tester, projekt(prozessJson: prozess.alsJson()));
      await reiter(tester, 'Herstellung');
      // Breit: Prozess und HACCP nebeneinander, ohne Umschalter.
      expect(
        find.byKey(const ValueKey('herstellung-umschalten')),
        findsNothing,
      );
      expect(find.text('Testbratstraße'), findsOneWidget);
      expect(find.text('Metallteile'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Metallteile')).dx,
        greaterThan(tester.getTopLeft(find.text('Testbratstraße')).dx + 400),
      );

      // Schmal ist nur einer zu sehen.
      tester.view.physicalSize = const Size(900, 900);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('herstellung-umschalten')),
        findsOneWidget,
      );
      expect(find.text('Testbratstraße'), findsOneWidget);
      expect(find.text('Metallteile'), findsNothing);
      await tester.tap(find.text('HACCP'));
      await tester.pump();
      expect(find.text('Metallteile'), findsOneWidget);
      expect(find.text('Testbratstraße'), findsNothing);
      await tester.tap(find.text('Prozess'));
      await tester.pump();
      expect(find.text('Testbratstraße'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Hält fest, was gespeichert würde — ohne Datenbank.
class _Speicher implements ProjektRepository {
  final gespeichert = <EntwicklungProjekteCompanion>[];
  final eintraege = <String>[];

  /// Der zuletzt gespeicherte Prozess.
  String? get prozess =>
      gespeichert.lastWhere((d) => d.prozess.present).prozess.value;

  @override
  Future<void> projektAendern(
    String id,
    EntwicklungProjekteCompanion daten,
  ) async =>
      gespeichert.add(daten);

  @override
  Future<String> eintragAnlegen({
    required String projektId,
    required EintragArt art,
    required String titel,
    required DateTime datum,
    String? benutzer,
    String? beschreibung,
    EintragStatus status = EintragStatus.offen,
    String? wert,
    String? ziel,
    String? dateiId,
    String? versionId,
    List<String> aenderungen = const [],
  }) async {
    eintraege.add(titel);
    return 'e${eintraege.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Ohne Sicherung — keine Zeitgeber im Test.
class _OhneSicherung implements AutoBackupTrigger {
  @override
  void fireDebounced({String reason = 'Daten-Änderung'}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Der Katalog der Planung — ohne Datenbank, erfunden.
class _Quelle implements AnlagenQuelle {
  @override
  Future<List<KatalogAnlage>> anlagen() async => const [
        KatalogAnlage(
          id: 'm-brat',
          name: 'Testbratstraße',
          abteilung: 'bratstrasse',
          steckbrief: [SteckbriefFeld('Bandgeschwindigkeit', einheit: 'm/min')],
        ),
        KatalogAnlage(
          id: 'm-pack',
          name: 'Testpacker',
          abteilung: 'verpackung',
        ),
        KatalogAnlage(
          id: 'm-wolf',
          name: 'Testwolf',
          abteilung: 'zerlegung',
          steckbrief: [SteckbriefFeld('Lochscheibe', einheit: 'mm')],
        ),
      ];

  @override
  Future<GrenzenKatalog> grenzen() async => GrenzenKatalog({
        GrenzenKatalog.schluessel('Testbratstraße', 'Bandgeschwindigkeit'):
            const ParameterGrenze(hartMax: 8, weichMax: 6),
      });

  @override
  Future<List<ArtikelMitKette>> artikel() async => const [
        ArtikelMitKette(
          id: 'a1',
          nummer: '1001',
          bezeichnung: 'Testware',
          schritte: 2,
        ),
      ];

  @override
  Future<List<ProzessSchritt>> kette(
    String productId, {
    required List<KatalogAnlage> katalog,
    required String Function() neueId,
  }) async =>
      [
        ProzessSchritt(
          id: neueId(),
          abteilung: 'zerlegung',
          maschineId: 'm-wolf',
          maschine: 'Testwolf',
        ),
        ProzessSchritt(
          id: neueId(),
          abteilung: 'bratstrasse',
          maschineId: 'm-brat',
          maschine: 'Testbratstraße',
        ),
      ];
}
