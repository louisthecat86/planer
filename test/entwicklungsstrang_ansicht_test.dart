import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/etikett/etikett.dart';
import 'package:produktion_planer/features/entwicklung/etikett/etikett_dialog.dart';
import 'package:produktion_planer/features/entwicklung/etikett/etikett_dienst.dart';
import 'package:produktion_planer/features/entwicklung/projekte/entwicklungsstrang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/entwicklungsweg_ansicht.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_verlauf.dart';
import 'package:produktion_planer/features/entwicklung/projekte/zeitstrahl.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/rezepturen/stand_abschliessen_dialog.dart';

/// Tests für die Fenster und Ansichten des Entwicklungsstrangs: Stand
/// abschließen, „Zu Stand", Zeitstrahl mit Stationen und Phasen, der
/// Entwicklungsweg und das Etikett. Alles erfunden.
void main() {
  final zeit = DateTime(2026, 3, 1);
  var zaehler = 0;

  ProjektEintrag eintrag(
    String id,
    EintragArt art, {
    required int tag,
    String? titel,
    String? versionId,
    String? wert,
    String? beschreibung,
    List<String> aenderungen = const [],
    EintragStatus status = EintragStatus.erledigt,
  }) =>
      ProjektEintrag(
        id: id,
        projektId: 'p1',
        art: art.schluessel,
        titel: titel ?? id,
        datum: zeit.add(Duration(days: tag)),
        status: status.schluessel,
        versionId: versionId,
        wert: wert,
        beschreibung: beschreibung,
        aenderungen: texteZuJson(aenderungen),
        createdAt: zeit.add(Duration(minutes: zaehler++)),
        updatedAt: zeit,
      );

  RezepturVersion version(
    String id,
    int nummer, {
    String status = VersionStatus.abgeschlossen,
    String? notiz,
  }) =>
      RezepturVersion(
        id: id,
        rezepturId: 'r1',
        nummer: nummer,
        status: status,
        notiz: notiz,
        verlustProzent: 10,
        fettVerlustProzent: 0,
        verlustArt: 'garen',
        abgeschlossenAm: status == VersionStatus.abgeschlossen ? zeit : null,
        createdAt: zeit,
        updatedAt: zeit.add(Duration(days: nummer)),
      );

  Future<void> zeige(
    WidgetTester tester,
    Widget kind, {
    List<Override> overrides = const [],
    Size groesse = const Size(1200, 1000),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: Scaffold(body: kind),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Ein Knopf, der [oeffnen] aufruft — für Fenster, die etwas
  /// zurückgeben.
  Widget starter(Future<void> Function(BuildContext context) oeffnen) =>
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => oeffnen(context),
            child: const Text('Öffnen'),
          ),
        ),
      );

  Future<void> antippen(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Stand abschließen', () {
    testWidgets('Änderungen, Grund vorbelegt und zurückgegeben',
        (tester) async {
      String? grund = 'nicht gefragt';
      await zeige(
        tester,
        starter((context) async {
          grund = await standAbschliessenFragen(
            context,
            version: version('v2', 2, status: VersionStatus.entwurf, notiz: 'Salz gesenkt'),
            aenderungen: const [
              'Neu: Senf (0,5 kg)',
              'Salz je 100 g: 1,8 → 1,6 g',
            ],
            vorherNummer: 1,
            imProjekt: true,
          );
        }),
      );
      await antippen(tester, find.text('Öffnen'));
      expect(find.text('Stand 2 abschließen?'), findsOneWidget);
      expect(find.text('Was sich gegenüber Stand 1 ändert'), findsOneWidget);
      expect(find.text('• Neu: Senf (0,5 kg)'), findsOneWidget);
      expect(find.text('Salz gesenkt'), findsOneWidget);
      expect(
        find.text('Steht am Stand und im Verlauf des Projekts.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('stand-grund')),
        'Salz gesenkt, der Kunde wünscht es milder',
      );
      await antippen(tester, find.text('Abschließen'));
      expect(grund, 'Salz gesenkt, der Kunde wünscht es milder');
    });

    testWidgets('Abbrechen gibt nichts zurück', (tester) async {
      String? grund = 'nicht gefragt';
      await zeige(
        tester,
        starter((context) async {
          grund = await standAbschliessenFragen(
            context,
            version: version('v1', 1, status: VersionStatus.entwurf),
            aenderungen: const ['Endgewicht 9 kg aus 10 kg', '2 Zeilen'],
          );
        }),
      );
      await antippen(tester, find.text('Öffnen'));
      expect(find.text('Der erste Stand'), findsOneWidget);
      expect(find.text('Steht als Notiz am Stand.'), findsOneWidget);
      await antippen(tester, find.text('Abbrechen'));
      expect(grund, isNull);
    });
  });

  group('Zu Stand', () {
    const staende = <StandWahl>[
      (versionId: 'v2', label: 'Frikadelle · Stand 2 (Entwurf)'),
      (versionId: 'v1', label: 'Frikadelle · Stand 1'),
    ];

    testWidgets('ein neuer Eintrag bekommt seinen Stand', (tester) async {
      EintragEingabe? eingabe;
      await zeige(
        tester,
        starter((context) async {
          eingabe = await showDialog<EintragEingabe>(
            context: context,
            builder: (_) => const EintragDialog(staende: staende),
          );
        }),
      );
      await antippen(tester, find.text('Öffnen'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Titel'),
        'Rückmeldung Kunde',
      );
      await antippen(tester, find.text('— keinem —'));
      await antippen(tester, find.text('Frikadelle · Stand 1').last);
      await antippen(tester, find.text('Anlegen'));
      expect(eingabe?.titel, 'Rückmeldung Kunde');
      expect(eingabe?.versionId, 'v1');
    });

    testWidgets('ohne Stände keine Auswahl, ein alter Bezug bleibt sichtbar',
        (tester) async {
      await zeige(
        tester,
        starter((context) async {
          await showDialog<EintragEingabe>(
            context: context,
            builder: (_) => const EintragDialog(),
          );
        }),
      );
      await antippen(tester, find.text('Öffnen'));
      expect(find.byKey(const ValueKey('eintrag-stand')), findsNothing);
      await antippen(tester, find.text('Abbrechen'));

      EintragEingabe? eingabe;
      await zeige(
        tester,
        starter((context) async {
          eingabe = await showDialog<EintragEingabe>(
            context: context,
            builder: (_) => EintragDialog(
              eintrag: eintrag(
                'e1',
                EintragArt.notiz,
                tag: 1,
                titel: 'Verkostung',
                versionId: 'weg',
              ),
            ),
          );
        }),
      );
      await antippen(tester, find.text('Öffnen'));
      expect(find.text('ein Stand, der nicht mehr da ist'), findsOneWidget);
      await antippen(tester, find.text('Speichern'));
      expect(eingabe?.versionId, 'weg');
    });

    testWidgets('ein Rezepturstand im Verlauf bleibt bei seinem Stand',
        (tester) async {
      EintragEingabe? eingabe;
      await zeige(
        tester,
        starter((context) async {
          eingabe = await showDialog<EintragEingabe>(
            context: context,
            builder: (_) => EintragDialog(
              staende: staende,
              eintrag: eintrag(
                's1',
                EintragArt.rezeptur,
                tag: 1,
                titel: 'Frikadelle · Stand 1',
                versionId: 'v1',
              ),
            ),
          );
        }),
      );
      await antippen(tester, find.text('Öffnen'));
      expect(find.byKey(const ValueKey('eintrag-stand')), findsNothing);
      await antippen(tester, find.text('Speichern'));
      expect(eingabe?.versionId, 'v1');
    });
  });

  group('Zeitstrahl', () {
    testWidgets('Stationen, Linien zur Station und das Phasenband',
        (tester) async {
      final liste = [
        eintrag('angelegt', EintragArt.meilenstein, tag: 0),
        eintrag('s1', EintragArt.rezeptur, tag: 2, versionId: 'v1'),
        eintrag('rueck', EintragArt.email, tag: 3, versionId: 'v1'),
        eintrag(
          'wechsel',
          EintragArt.meilenstein,
          tag: 4,
          wert: statusWert(ProjektStatus.entwicklung, ProjektStatus.validierung),
        ),
        eintrag('s2', EintragArt.rezeptur, tag: 5, versionId: 'v2'),
      ];
      await zeige(
        tester,
        ListView(
          children: [
            Zeitstrahl(
              eintraege: liste,
              onTippen: (_) {},
              versionen: {'v1': version('v1', 1), 'v2': version('v2', 2)},
              phasen: statusJeEintrag(liste, ProjektStatus.validierung),
            ),
          ],
        ),
      );
      // Die Stationen tragen ihre Nummer.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('phase-0-entwicklung')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('phase-1-validierung')),
        findsOneWidget,
      );
      // Eine Linie von der Rückmeldung zu Stand 1.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_BezugsMaler',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ohne Phasen kein Band, schmal und dunkel ohne Überlauf',
        (tester) async {
      await zeige(
        tester,
        ListView(
          children: [
            Zeitstrahl(
              eintraege: [
                for (var i = 0; i < 6; i++)
                  eintrag(
                    'e$i',
                    i.isEven ? EintragArt.rezeptur : EintragArt.notiz,
                    tag: i,
                    versionId: 'v1',
                  ),
              ],
              onTippen: (_) {},
            ),
          ],
        ),
        groesse: const Size(360, 700),
        theme: AppTheme.dark(),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is DecoratedBox && w.key.toString().contains('phase-'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Entwicklungsweg', () {
    final projekt = EntwicklungsProjekt(
      id: 'p1',
      name: 'Frikadelle Testart',
      kunde: 'Muster GmbH',
      status: ProjektStatus.produktion.schluessel,
      produktidee: 'Saftige Frikadelle für den Grill',
      neuerProzess: false,
      neueZutaten: false,
      artikelnummer: 'T-200',
      freigabeVersionId: 'v2',
      freigegebenAm: DateTime(2026, 5, 1),
      createdAt: zeit,
      updatedAt: zeit,
    );
    final rezeptur = Rezeptur(
      id: 'r1',
      name: 'Frikadelle',
      projektId: 'p1',
      createdAt: zeit,
      updatedAt: zeit,
    );
    const schwein = RechenZutat(
      id: 'z1',
      name: 'Schweinefleisch',
      istFleisch: true,
      tierart: Tierart.schwein,
      naehrwerte: Naehrwerte(fett: 20, eiweiss: 18),
    );
    const senf = RechenZutat(
      id: 'z2',
      name: 'Senf',
      allergene: {'senf'},
      naehrwerte: Naehrwerte(fett: 10, eiweiss: 6),
    );
    RechenRezeptur rechen(List<RechenPosition> p) => RechenRezeptur(
          id: 'r1',
          name: 'Frikadelle',
          verlustProzent: 10,
          verlustart: Verlustart.garen,
          positionen: p,
        );

    testWidgets('Idee, Stationen mit Kennzahlen, Phase, In Arbeit, Freigabe',
        (tester) async {
      final liste = [
        eintrag('angelegt', EintragArt.meilenstein, tag: 0, titel: 'Projekt angelegt'),
        eintrag('anfrage', EintragArt.email, tag: 1, titel: 'Anfrage per Mail'),
        eintrag(
          's1',
          EintragArt.rezeptur,
          tag: 5,
          titel: 'Frikadelle · Stand 1',
          versionId: 'v1',
          beschreibung: 'Erstes Muster',
          aenderungen: const ['1 Zeile'],
        ),
        eintrag(
          'rueck',
          EintragArt.email,
          tag: 7,
          titel: 'Rückmeldung Kunde',
          versionId: 'v1',
          status: EintragStatus.offen,
        ),
        eintrag(
          'wechsel',
          EintragArt.meilenstein,
          tag: 8,
          titel: 'Validierung begonnen',
          wert: statusWert(ProjektStatus.entwicklung, ProjektStatus.validierung),
        ),
        eintrag(
          's2',
          EintragArt.rezeptur,
          tag: 10,
          titel: 'Frikadelle · Stand 2',
          versionId: 'v2',
          aenderungen: const ['Neu: Senf (0,5 kg)'],
        ),
        // Die Freigabe hält den Schritt in die Produktion fest.
        eintrag(
          'freigabe',
          EintragArt.meilenstein,
          tag: 12,
          titel: 'Freigegeben als neuer Artikel T-200',
          versionId: 'v2',
          wert: statusWert(ProjektStatus.validierung, ProjektStatus.produktion),
        ),
      ];
      await zeige(
        tester,
        SingleChildScrollView(
          child: EntwicklungswegAnsicht(
            projekt: projekt,
            eintraege: liste.reversed.toList(),
            versionen: {
              'v1': version('v1', 1),
              'v2': version('v2', 2),
              'v3': version('v3', 3, status: VersionStatus.entwurf),
            },
          ),
        ),
        overrides: [
          projektRezepturenProvider.overrideWith(
            (ref, id) => Stream.value([rezeptur]),
          ),
          rechenRezepturProvider.overrideWith(
            (ref, id) async => id == 'v1'
                ? rechen([const RechenPosition.zutat(schwein, mengeKg: 10)])
                : rechen([
                    const RechenPosition.zutat(schwein, mengeKg: 10),
                    const RechenPosition.zutat(senf, mengeKg: 0.5),
                  ]),
          ),
        ],
      );
      // Die Kennzahlen rechnen erst nach dem Aufbau.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Idee und Anfrage'), findsOneWidget);
      expect(find.text('Saftige Frikadelle für den Grill'), findsOneWidget);
      expect(find.text('Anfrage per Mail'), findsOneWidget);
      expect(find.text('Frikadelle · Stand 1'), findsOneWidget);
      expect(find.textContaining('Station 1 · '), findsOneWidget);
      expect(find.text('Erstes Muster'), findsOneWidget);
      expect(find.text('Rückmeldung Kunde'), findsOneWidget);
      expect(find.text('offen'), findsOneWidget);
      expect(find.textContaining('Validierung begonnen · '), findsOneWidget);
      expect(find.text('Frikadelle · Stand 2'), findsOneWidget);
      expect(find.text('• Neu: Senf (0,5 kg)'), findsOneWidget);
      expect(find.text('Mit Stand 1 vergleichen'), findsOneWidget);
      // Kennzahlen an beiden Stationen, beim zweiten mit Veränderung.
      expect(find.textContaining('Fleischanteil '), findsNWidgets(2));
      expect(find.text('Etikett'), findsNWidgets(2));
      expect(
        find.textContaining('In Arbeit: Frikadelle · Stand 3'),
        findsOneWidget,
      );
      // Die Freigabe steht einmal auf dem Weg — mit ihrem Stand —, der
      // freigegebene Stand trägt die Marke.
      expect(
        find.textContaining('Freigegeben als neuer Artikel T-200 · Stand 2 · '),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.verified_outlined), findsNWidgets(2));
      expect(find.text('freigegeben'), findsOneWidget);
      expect(find.textContaining('Artikel T-200'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ohne Stand ein Hinweis', (tester) async {
      await zeige(
        tester,
        SingleChildScrollView(
          child: EntwicklungswegAnsicht(
            projekt: projekt,
            eintraege: [eintrag('angelegt', EintragArt.meilenstein, tag: 0)],
          ),
        ),
        overrides: [
          projektRezepturenProvider.overrideWith(
            (ref, id) => Stream.value(const <Rezeptur>[]),
          ),
        ],
        groesse: const Size(420, 900),
        theme: AppTheme.dark(),
      );
      expect(find.text('Idee und Anfrage'), findsOneWidget);
      expect(
        find.textContaining('Noch kein abgeschlossener Stand.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Etikett', () {
    const inhalt = EtikettInhalt(
      bezeichnung: 'Frikadelle Testart',
      zutatenliste: 'Schweinefleisch (80,0 %), WEIZENmehl, Speisesalz',
      allergene: ['Gluten'],
      spuren: ['Senf'],
      naehrwerte: [
        (label: 'Energie', wert: '900 kJ / 215 kcal', davon: false),
        (label: 'Fett', wert: '15 g', davon: false),
        (label: 'davon gesättigte Fettsäuren', wert: '6,0 g', davon: true),
      ],
      lagerung: 'gekühlt',
      stand: 'Frikadelle · Stand 2 · abgeschlossen am 05.03.2026',
      fehlt: ['Nettofüllmenge (Reiter „Produkt", Verpackung)'],
    );

    testWidgets('Vorschau, was fehlt, Text kopieren', (tester) async {
      String? kopiert;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (aufruf) async {
          if (aufruf.method == 'Clipboard.setData') {
            kopiert = (aufruf.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await zeige(
        tester,
        const EtikettDialog(versionId: 'v2'),
        overrides: [
          etikettProvider.overrideWith((ref, id) async => inhalt),
        ],
      );
      await tester.pump();
      expect(find.text(inhalt.stand), findsOneWidget);
      expect(find.text('Frikadelle Testart'), findsOneWidget);
      expect(find.textContaining('WEIZENmehl'), findsOneWidget);
      expect(find.text('Kann Spuren von Senf enthalten.'), findsOneWidget);
      expect(find.text('Durchschnittliche Nährwerte je 100 g'), findsOneWidget);
      expect(find.text('900 kJ / 215 kcal'), findsOneWidget);
      expect(find.text('Lagerung: gekühlt'), findsOneWidget);
      expect(find.text('Nettofüllmenge: …'), findsOneWidget);
      expect(find.text('Für das fertige Etikett fehlt noch'), findsOneWidget);
      expect(find.textContaining('Enthaltene Allergene: Gluten'), findsOneWidget);
      expect(find.text('PDF-Entwurf…'), findsOneWidget);

      await tester.tap(find.text('Text kopieren'));
      await tester.pump();
      await tester.pump();
      expect(kopiert, etikettText(inhalt));
      expect(find.text('Etikett als Text kopiert.'), findsOneWidget);
    });

    testWidgets('einen Stand, den es nicht gibt', (tester) async {
      await zeige(
        tester,
        const EtikettDialog(versionId: 'weg'),
        overrides: [etikettProvider.overrideWith((ref, id) async => null)],
      );
      await tester.pump();
      expect(find.text('Diesen Stand gibt es nicht mehr.'), findsOneWidget);
      final knopf = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Text kopieren'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(knopf.enabled, isFalse);
    });
  });
}
