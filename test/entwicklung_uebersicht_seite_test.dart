import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/kunden/kunden_ansicht.dart';
import 'package:produktion_planer/features/entwicklung/projekte/datei_aktionen.dart';
import 'package:produktion_planer/features/entwicklung/projekte/foto_eingang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/uebersicht/angeheftet.dart';
import 'package:produktion_planer/features/entwicklung/uebersicht/uebersicht_ansicht.dart';

/// Die Übersicht und die Kundenordner der Produktentwicklung mit
/// erfundenen Projekten: Kacheln, Karten mit dem, was fehlt, Anheften,
/// Suche, Ordner auf- und zuklappen, der Foto-Eingang — und schmal und
/// dunkel läuft nichts über.
///
/// Ein Überlauf (gelb-schwarzer Streifen) meldet Flutter als Fehler; der
/// Test schlägt dann von selbst fehl.
void main() {
  final heute = DateTime(2026, 11, 9);

  EntwicklungsProjekt projekt(
    String id,
    String name,
    DateTime geaendert, {
    String status = 'entwicklung',
    String? kunde,
    String? gesamtprojektId,
  }) =>
      EntwicklungsProjekt(
        id: id,
        name: name,
        status: status,
        kunde: kunde,
        gesamtprojektId: gesamtprojektId,
        neuerProzess: false,
        neueZutaten: false,
        createdAt: geaendert,
        updatedAt: geaendert,
      );

  final projekte = [
    projekt(
      'p1',
      'Grillwurst fein',
      DateTime(2026, 11, 6),
      kunde: 'Beispiel Feinkost',
    ),
    projekt(
      'p2',
      'Kochschinken mild',
      DateTime(2026, 11, 8),
      status: 'validierung',
      kunde: 'Muster Markt',
    ),
    projekt(
      'p3',
      'Bratwurst grob',
      DateTime(2026, 9, 1),
      kunde: 'Testhandel Nord',
    ),
    projekt(
      'alt',
      'Salami alt',
      DateTime(2026, 3, 1),
      status: 'eingestellt',
      kunde: 'Muster Markt',
    ),
    projekt(
      'm1',
      'Muster A',
      DateTime(2026, 11, 2),
      kunde: 'Beispiel Feinkost',
      gesamtprojektId: 'g',
    ),
    projekt('p4', 'Leberkäse', DateTime(2026, 5, 1), status: 'produktion'),
  ];
  final gesamtprojekte = [
    Gesamtprojekt(
      id: 'g',
      name: 'Anfrage Sommer',
      kunde: 'Beispiel Feinkost',
      createdAt: DateTime(2026, 10, 20),
      updatedAt: DateTime(2026, 10, 20),
    ),
  ];
  final eintraege = [
    ProjektEintrag(
      id: 'e1',
      projektId: 'p1',
      art: EintragArt.notiz.schluessel,
      titel: 'Verkostung',
      datum: DateTime(2026, 10, 20),
      status: EintragStatus.offen.schluessel,
      ziel: 'KW 44',
      createdAt: DateTime(2026, 10, 20),
      updatedAt: DateTime(2026, 10, 20),
    ),
  ];
  final rezepturen = [
    Rezeptur(
      id: 'r',
      name: 'Grillbrät',
      artikelnummer: '815',
      projektId: 'p1',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
    ),
  ];

  Future<void> zeige(
    WidgetTester tester,
    Widget seite, {
    Size groesse = const Size(1400, 2000),
    ThemeData? theme,
    List<EntwicklungsDatei> eingang = const [],
  }) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projekteProvider.overrideWith((ref) => Stream.value(projekte)),
          gesamtprojekteProvider.overrideWith(
            (ref) => Stream.value(gesamtprojekte),
          ),
          alleEintraegeProvider.overrideWith((ref) => Stream.value(eintraege)),
          rezepturenProvider.overrideWith((ref) => Stream.value(rezepturen)),
          alleVersionenProvider.overrideWith((ref) => Stream.value(const [])),
          zeilenAenderungenProvider
              .overrideWith((ref) => Stream.value(const {})),
          // Der Foto-Eingang — ohne Datenbank auch ohne Bilder.
          fotoEingangProvider.overrideWith((ref) => Stream.value(eingang)),
          dateiInhaltProvider.overrideWith((ref, id) => null),
          // Ohne Datenbank: Angeheftetes wird nicht gespeichert.
          angehefteteProjekteProvider
              .overrideWith((ref) => AngeheftetNotifier(null)),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: Scaffold(body: seite),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Der Kopf des Bereichs mit genau diesem Titel.
  Finder bereich(String titel) => find.byWidgetPredicate(
        (w) => w is BereichKopf && w.titel == titel,
      );

  Finder schluessel(String s) => find.byKey(ValueKey(s));

  testWidgets(
      'Übersicht: Kacheln, Karten mit dem, was fehlt, Kunden, '
      'was ansteht', (tester) async {
    await zeige(tester, EntwicklungUebersicht(heute: heute));

    for (final titel in const ['Zuletzt bearbeitet', 'Kunden', 'Was ansteht']) {
      expect(bereich(titel), findsOneWidget, reason: titel);
    }
    for (final k in const [
      'kachel-in-arbeit',
      'kachel-ueberfaellig',
      'kachel-ruhen',
      'kachel-gelistet',
    ]) {
      expect(schluessel(k), findsOneWidget, reason: k);
    }
    // Die Projekte in Arbeit als Karten — nicht das ruhende, nicht das
    // in Produktion.
    for (final id in const ['p1', 'p2', 'p3', 'm1']) {
      expect(schluessel('karte-$id'), findsOneWidget, reason: id);
    }
    expect(schluessel('karte-alt'), findsNothing);
    expect(schluessel('karte-p4'), findsNothing);
    // Was fehlt.
    expect(
      find.descendant(
        of: schluessel('karte-p1'),
        matching: find.text('Überfällig seit 01.11.: Verkostung'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: schluessel('karte-p3'),
        matching: find.text('Seit 69 Tagen nichts getan'),
      ),
      findsOneWidget,
    );
    // Was ansteht: der überfällige Eintrag und das ruhende Projekt.
    expect(schluessel('ansteht-e1'), findsOneWidget);
    expect(schluessel('ruht-p3'), findsOneWidget);
    // Die Kunden mit Projekten in Arbeit — ohne Kunden steht hier nicht.
    expect(schluessel('kunde-beispiel feinkost'), findsOneWidget);
    expect(schluessel('kunde-muster markt'), findsOneWidget);
    expect(schluessel('kunde-testhandel nord'), findsOneWidget);
    expect(schluessel('kunde-'), findsNothing);
  });

  testWidgets(
      'Übersicht: aus dem Kundenordner anheften — die Karte steht '
      'vorn', (tester) async {
    await zeige(tester, EntwicklungUebersicht(heute: heute));
    await tester.tap(schluessel('kunde-muster markt'));
    await tester.pumpAndSettle();
    expect(schluessel('projektzeile-alt'), findsOneWidget);

    await tester.tap(schluessel('anheften-alt'));
    await tester.pumpAndSettle();
    expect(schluessel('karte-alt'), findsOneWidget);
    expect(
      tester.getTopLeft(schluessel('karte-alt')).dx,
      lessThan(tester.getTopLeft(schluessel('karte-p2')).dx),
    );

    // Wieder lösen — über die Nadel auf der Karte.
    await tester.tap(
      find.descendant(
        of: schluessel('karte-alt'),
        matching: schluessel('anheften-alt'),
      ),
    );
    await tester.pumpAndSettle();
    expect(schluessel('karte-alt'), findsNothing);
  });

  testWidgets('Übersicht: die Suche findet Projekte und Rezepturen',
      (tester) async {
    await zeige(tester, EntwicklungUebersicht(heute: heute));
    await tester.enterText(schluessel('uebersicht-suche'), 'grill');
    await tester.pumpAndSettle();

    expect(bereich('Suche'), findsOneWidget);
    expect(schluessel('projektzeile-p1'), findsOneWidget);
    expect(schluessel('rezepturzeile-r'), findsOneWidget);
    expect(schluessel('kachel-in-arbeit'), findsNothing);

    await tester.tap(find.byTooltip('Suche leeren'));
    await tester.pumpAndSettle();
    expect(bereich('Suche'), findsNothing);
    expect(schluessel('kachel-in-arbeit'), findsOneWidget);
  });

  testWidgets('Kunden: Ordner, aufklappen, nur in Arbeit, suchen',
      (tester) async {
    await zeige(tester, KundenAnsicht(heute: heute));

    for (final k in const [
      'kunde-beispiel feinkost',
      'kunde-muster markt',
      'kunde-testhandel nord',
      'kunde-',
    ]) {
      expect(schluessel(k), findsOneWidget, reason: k);
    }
    expect(find.text('Ohne Kunden'), findsOneWidget);
    expect(schluessel('gesamtzeile-g'), findsNothing);

    await tester.tap(schluessel('kunden-alle'));
    await tester.pumpAndSettle();
    expect(schluessel('gesamtzeile-g'), findsOneWidget);
    expect(schluessel('projektzeile-m1'), findsOneWidget);
    expect(schluessel('projektzeile-p4'), findsOneWidget);

    await tester.tap(schluessel('kunden-in-arbeit'));
    await tester.pumpAndSettle();
    expect(find.text('Ohne Kunden'), findsNothing);

    await tester.enterText(schluessel('kunden-suche'), 'kochschinken');
    await tester.pumpAndSettle();
    expect(schluessel('kunde-muster markt'), findsOneWidget);
    expect(schluessel('kunde-beispiel feinkost'), findsNothing);
    expect(schluessel('projektzeile-p2'), findsOneWidget);
    expect(schluessel('projektzeile-alt'), findsNothing);
  });

  testWidgets(
      'Foto-Eingang: nur zu sehen, wenn ein Musterfoto wartet — Zuordnen '
      'zeigt die Projekte', (tester) async {
    await zeige(tester, EntwicklungUebersicht(heute: heute));
    expect(schluessel('foto-eingang'), findsNothing);

    final eingang = [
      EntwicklungsDatei(
        id: 'f1',
        projektId: '@foto-eingang',
        name: 'Musterfoto Pfeffer grob 2026-11-08_1105.jpg',
        mimeTyp: 'image/jpeg',
        groesse: 312 * 1024,
        createdAt: DateTime(2026, 11, 9),
      ),
    ];
    // Von vorn — sonst behielte die Seite den leeren Eingang von eben.
    await tester.pumpWidget(const SizedBox());
    // Auch schmal läuft die Zeile nicht über.
    await zeige(
      tester,
      EntwicklungUebersicht(heute: heute),
      groesse: const Size(800, 2400),
      eingang: eingang,
    );
    expect(schluessel('foto-eingang'), findsOneWidget);
    expect(bereich('Foto-Eingang'), findsOneWidget);
    expect(
      find.text('Musterfoto Pfeffer grob 2026-11-08_1105'),
      findsOneWidget,
    );
    expect(
      find.text('eingelesen am 09.11.2026 · 312 KB'),
      findsOneWidget,
    );

    await tester.tap(schluessel('foto-zuordnen-f1'));
    await tester.pumpAndSettle();
    expect(schluessel('foto-ziel-p1'), findsOneWidget);
    expect(schluessel('foto-ziel-m1'), findsOneWidget);
    expect(schluessel('foto-ziel-produktfoto'), findsOneWidget);

    await tester.enterText(schluessel('foto-ziel-suche'), 'leberk');
    await tester.pumpAndSettle();
    expect(schluessel('foto-ziel-p4'), findsOneWidget);
    expect(schluessel('foto-ziel-p1'), findsNothing);
    expect(schluessel('foto-ziel-g'), findsNothing);

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(schluessel('foto-ziel-suche'), findsNothing);
    expect(schluessel('foto-eingang'), findsOneWidget);
  });

  testWidgets('schmal und dunkel: kein Überlauf', (tester) async {
    await zeige(
      tester,
      EntwicklungUebersicht(heute: heute),
      groesse: const Size(800, 2400),
      theme: AppTheme.dark(),
    );
    await tester.tap(schluessel('kunde-beispiel feinkost'));
    await tester.pumpAndSettle();
    expect(schluessel('gesamtzeile-g'), findsOneWidget);

    await zeige(
      tester,
      KundenAnsicht(heute: heute),
      groesse: const Size(640, 1600),
      theme: AppTheme.dark(),
    );
    await tester.tap(schluessel('kunden-alle'));
    await tester.pumpAndSettle();
    expect(schluessel('projektzeile-alt'), findsOneWidget);
  });
}
