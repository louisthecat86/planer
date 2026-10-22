import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/freigabe/freigabe.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/haccp/haccp_ansicht.dart';
import 'package:produktion_planer/features/entwicklung/haccp/haccp_modell.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_ansicht.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_modell.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_vorlage.dart';
import 'package:produktion_planer/features/entwicklung/projekte/fliessdiagramme_dialog.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_screen.dart';

import 'helpers/test_db.dart';

/// Tests für Prozessparameter, Gefahrenanalyse und Fließdiagramme: Versionen,
/// Vergleich, Vorlage, Entscheidungsbaum, die eingefügte Liste — und die
/// Reiter „Herstellung" einer Projektseite mit Prozess und HACCP. Alles
/// erfunden.
void main() {
  ProzessFeld feld(String id, String wert) =>
      ProzessFeld(id: id, label: 'Feld $id', wert: wert);

  group('Prozessparameter', () {
    test('Versionen zählen in Zehnteln weiter', () {
      expect(naechsteVersion('1.0'), '1.1');
      expect(naechsteVersion('1.9'), '2.0');
      expect(naechsteVersion('2,4'), '2.5');
      expect(naechsteVersion('0.9'), '1.0');
      expect(naechsteVersion(null), '1.0');
      expect(naechsteVersion('neu'), '1.0');
    });

    test('der Vergleich findet geänderte, neue und entfallene Werte', () {
      final alt = Prozessparameter(
        abschnitte: [
          ProzessAbschnitt(
            id: 'garen',
            titel: 'Garen',
            felder: [feld('t', '180'), feld('z', '12 min'), feld('weg', 'x')],
          ),
        ],
      );
      final neu = Prozessparameter(
        abschnitte: [
          ProzessAbschnitt(
            id: 'garen',
            titel: 'Garen',
            felder: [feld('t', '175'), feld('z', '12 min'), feld('neu', 'y')],
          ),
        ],
      );
      final a = vergleicheParameter(alt, neu);
      expect(a, hasLength(3));
      final temperatur = a.firstWhere((x) => x.feld == 'Feld t');
      expect((temperatur.alt, temperatur.neu), ('180', '175'));
      expect(a.firstWhere((x) => x.feld == 'Feld neu').alt, isNull);
      expect(a.firstWhere((x) => x.feld == 'Feld weg').neu, isNull);
      expect(vergleicheParameter(neu, neu), isEmpty);
    });

    test('eine Vorlage behält Abschnitte und Felder, nicht die Werte', () {
      const p = Prozessparameter(
        version: '2.3',
        abschnitte: [
          ProzessAbschnitt(
            id: 'v',
            titel: 'Verpackung',
            felder: [
              ProzessFeld(
                id: 'art',
                label: 'Art',
                wert: 'Vakuum',
                typ: FeldTyp.auswahl,
                optionen: ['Vakuum', 'offen'],
              ),
            ],
          ),
        ],
      );
      final v = alsVorlage(p);
      expect(v.version, '1.0');
      final f = v.abschnitte.single.felder.single;
      expect(f.wert, '');
      expect(f.optionen, ['Vakuum', 'offen']);
      expect(f.typ, FeldTyp.auswahl);
    });

    test('die eingebaute Vorlage ist neutral und hat eindeutige IDs', () {
      const v = kNeutraleProzessVorlage;
      expect(v.abschnitte, isNotEmpty);
      final ids = [for (final a in v.abschnitte) a.id];
      expect(ids.toSet().length, ids.length);
      for (final a in v.abschnitte) {
        final felder = [for (final f in a.felder) f.id];
        expect(felder.toSet().length, felder.length, reason: a.titel);
        expect(a.felder.every((f) => f.wert.isEmpty), isTrue);
      }
      // Als JSON hin und zurück.
      final zurueck = Prozessparameter.aus(v.alsJson());
      expect(zurueck.abschnitte.length, v.abschnitte.length);
    });

    test('neue IDs weichen vorhandenen aus', () {
      expect(neueParameterId('Kühlen & Frosten', const []), 'kuehlen-frosten');
      expect(neueParameterId('Garen', const ['garen']), 'garen-2');
      expect(neueParameterId('Garen', const ['garen', 'garen-2']), 'garen-3');
      expect(neueParameterId('???', const []), 'feld');
    });
  });

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

    testWidgets('geringes Risiko braucht keinen Lenkungspunkt',
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
      expect([for (final f in liste) f.id], [
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

  group('Vorlage in der Datenbank', () {
    test('speichern, lesen, zurücksetzen', () async {
      final db = testDatenbank();
      addTearDown(db.close);
      await EntwicklungZugang(
        DbEntwicklungsSpeicher(db),
        iterationen: 1000,
        imHintergrund: false,
      ).festlegen('geheim123');
      final dienst = ProzessVorlageDienst(EntwicklungDateienDienst(db));

      expect(await dienst.eigene(), isNull);
      expect(
        (await dienst.vorlage()).abschnitte.length,
        kNeutraleProzessVorlage.abschnitte.length,
      );

      await dienst.speichern(
        Prozessparameter(
          abschnitte: [
            ProzessAbschnitt(
              id: 'k',
              titel: 'Kutter',
              felder: [feld('drehzahl', '3000')],
            ),
          ],
        ),
      );
      final eigene = (await dienst.eigene())!;
      expect(eigene.abschnitte.single.titel, 'Kutter');
      expect(eigene.abschnitte.single.felder.single.wert, '');
      // Verschlüsselt, nicht als Klartext.
      final roh = await db.select(db.entwicklungDateiInhalte).getSingle();
      expect(String.fromCharCodes(roh.inhalt).contains('Kutter'), isFalse);

      await dienst.zuruecksetzen();
      expect(await dienst.eigene(), isNull);
    });
  });

  group('Seiten', () {
    final zeit = DateTime(2026, 10, 16);
    final prozess = Prozessparameter(
      version: '1.1',
      stand: zeit,
      abschnitte: const [
        ProzessAbschnitt(
          id: 'garen',
          titel: 'Garen und Braten',
          felder: [
            ProzessFeld(
              id: 't',
              label: 'Temperaturen (°C)',
              wert: '180',
            ),
            ProzessFeld(
              id: 'art',
              label: 'Verpackungsart',
              typ: FeldTyp.auswahl,
              optionen: ['Vakuum', 'offen'],
              wert: 'Vakuum',
            ),
          ],
        ),
      ],
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

    EntwicklungsProjekt projekt({String? prozessJson}) => EntwicklungsProjekt(
          id: 'p1',
          name: 'Schnitzel Wiener Art',
          status: 'entwicklung',
          neuerProzess: true,
          neueZutaten: false,
          prozess: prozessJson,
          prozessHistorie: ProzessStand.listeZuJson([
            ProzessStand(
              version: '1.0',
              datum: zeit,
              parameter: prozess.kopie(version: '1.0'),
            ),
            ProzessStand(
              version: '1.1',
              datum: zeit,
              notiz: 'Temperatur gesenkt',
              parameter: prozess,
            ),
          ]),
          haccp: haccp.alsJson(),
          createdAt: zeit,
          updatedAt: zeit,
        );

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
      await tester.tap(find.widgetWithText(Tab, name));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('Prozess: Version, Abschnitte, Änderung und Verwerfen',
        (tester) async {
      await zeige(tester, projekt(prozessJson: prozess.alsJson()));
      await reiter(tester, 'Herstellung');

      expect(find.textContaining('Version 1.1'), findsWidgets);
      expect(find.text('Garen und Braten'), findsOneWidget);
      expect(find.text('180'), findsOneWidget);
      expect(find.textContaining('Temperatur gesenkt'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '180'), '175');
      await tester.pump();
      expect(find.text('ungespeichert'), findsOneWidget);

      await tester.tap(find.text('Verwerfen'));
      await tester.pump();
      expect(find.text('ungespeichert'), findsNothing);
      expect(find.text('180'), findsOneWidget);
    });

    testWidgets('Prozess: leer beginnen mit einem eigenen Abschnitt',
        (tester) async {
      await zeige(tester, projekt());
      await reiter(tester, 'Herstellung');

      expect(find.text('Vorlage verwenden'), findsOneWidget);
      await tester.tap(find.text('Leer beginnen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Kutter');
      await tester.tap(find.text('Hinzufügen'));
      await tester.pumpAndSettle();

      expect(find.text('Kutter'), findsOneWidget);
      expect(find.text('ungespeichert'), findsOneWidget);
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
      expect(find.text('Garen und Braten'), findsOneWidget);
      expect(find.text('Metallteile'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Metallteile')).dx,
        greaterThan(tester.getTopLeft(find.text('Garen und Braten')).dx + 400),
      );
      // Eine Änderung, noch nicht gespeichert …
      await tester.enterText(find.widgetWithText(TextField, '180'), '175');
      await tester.pump();
      expect(find.text('ungespeichert'), findsOneWidget);

      // … übersteht den Wechsel auf schmal.
      tester.view.physicalSize = const Size(900, 900);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('herstellung-umschalten')),
        findsOneWidget,
      );
      expect(find.text('ungespeichert'), findsOneWidget);
      expect(find.text('175'), findsOneWidget);
      // Schmal ist nur einer zu sehen.
      expect(find.text('Metallteile'), findsNothing);
      await tester.tap(find.text('HACCP'));
      await tester.pump();
      expect(find.text('Metallteile'), findsOneWidget);
      expect(find.text('Garen und Braten'), findsNothing);
      await tester.tap(find.text('Prozess'));
      await tester.pump();
      expect(find.text('175'), findsOneWidget);
      expect(find.text('ungespeichert'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
