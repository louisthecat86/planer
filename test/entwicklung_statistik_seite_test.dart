import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/entwicklungsstrang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/statistik/statistik_ansicht.dart';
import 'package:produktion_planer/features/statistik/statistik_diagramme.dart';

/// Der Reiter „Statistik" der Produktentwicklung mit erfundenen Mustern:
/// alle Bereiche erscheinen, der Zeitraum lässt sich umschalten (nicht in
/// die Zukunft), ein Tipp auf einen Kunden filtert, und schmal und dunkel
/// läuft nichts über.
///
/// Ein Überlauf (gelb-schwarzer Streifen) meldet Flutter als Fehler; der
/// Test schlägt dann von selbst fehl.
void main() {
  final heute = DateTime(2026, 11, 9);

  EntwicklungsProjekt projekt(
    String id,
    String name,
    DateTime angelegt, {
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
        createdAt: angelegt,
        updatedAt: angelegt,
      );

  var nr = 0;
  ProjektEintrag wechsel(
    String projektId,
    DateTime datum,
    ProjektStatus neu, {
    String? grund,
  }) =>
      ProjektEintrag(
        id: 'e${nr++}',
        projektId: projektId,
        art: EintragArt.meilenstein.schluessel,
        titel: statusMeilensteinTitel(neu),
        datum: datum,
        beschreibung: grund == null ? null : 'Grund: $grund',
        status: EintragStatus.erledigt.schluessel,
        wert: statusWert(ProjektStatus.entwicklung, neu),
        createdAt: datum,
        updatedAt: datum,
      );

  final projekte = [
    projekt(
      'p1',
      'Grillwurst Probe',
      DateTime(2026, 1, 15),
      status: 'produktion',
      kunde: 'Beispiel Feinkost',
      gesamtprojektId: 'g1',
    ),
    projekt(
      'p2',
      'Grillwurst Variante',
      DateTime(2026, 1, 15),
      status: 'eingestellt',
      kunde: 'Beispiel Feinkost',
      gesamtprojektId: 'g1',
    ),
    projekt(
      'p3',
      'Kochschinken Test',
      DateTime(2026, 6, 1),
      kunde: 'Muster Markt',
    ),
    projekt(
      'p4',
      'Salami Probe',
      DateTime(2025, 5, 10),
      status: 'produktion',
      kunde: 'Muster Markt',
    ),
  ];
  final eintraege = [
    wechsel('p1', DateTime(2026, 3, 20), ProjektStatus.produktion),
    wechsel(
      'p2',
      DateTime(2026, 3, 20),
      ProjektStatus.eingestellt,
      grund: 'Kunde hat die andere Variante gewählt',
    ),
    wechsel('p4', DateTime(2026, 2, 1), ProjektStatus.produktion),
  ];
  final gesamtprojekte = [
    Gesamtprojekt(
      id: 'g1',
      name: 'Anfrage Grillsortiment',
      kunde: 'Beispiel Feinkost',
      createdAt: DateTime(2026, 1, 15),
      updatedAt: DateTime(2026, 1, 15),
    ),
  ];

  Future<void> zeige(
    WidgetTester tester, {
    // So hoch, dass die ganze Seite gebaut wird.
    Size groesse = const Size(1400, 5000),
    ThemeData? theme,
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
          rezepturenProvider.overrideWith((ref) => Stream.value(const [])),
          alleVersionenProvider.overrideWith((ref) => Stream.value(const [])),
          zutatenProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: Scaffold(body: StatistikAnsicht(heute: heute)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Der Kopf des Bereichs mit genau diesem Titel.
  Finder bereich(String titel) => find.byWidgetPredicate(
        (w) => w is BereichKopf && w.titel == titel,
      );

  String zeitraum(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('statistik-zeitraum')))
      .data!;

  testWidgets('breit und hell: alle Bereiche, das laufende Jahr',
      (tester) async {
    await zeige(tester);
    for (final titel in const [
      'Kennzahlen',
      'Verlauf',
      'Was aus den Mustern wurde',
      'Nach Kunde',
      'Warum nicht weiter verfolgt',
      'Muster im Einzelnen',
      'Stand heute',
    ]) {
      expect(bereich(titel), findsOneWidget, reason: titel);
    }
    expect(zeitraum(tester), '2026');
    expect(find.byType(StatistikSaeulen), findsNWidgets(2));
    expect(find.byType(StatistikKreis), findsOneWidget);
    expect(find.text('Kunde hat die andere Variante gewählt'), findsOneWidget);
    expect(find.text('Grillwurst Probe'), findsOneWidget);
    expect(find.text('Kochschinken Test'), findsWidgets);
    // In die Zukunft geht es nicht.
    final danach = tester.widget<IconButton>(
      find.byKey(const ValueKey('statistik-danach')),
    );
    expect(danach.onPressed, isNull);
  });

  testWidgets('Quartal, davor und danach', (tester) async {
    await zeige(tester);
    await tester.tap(find.text('Quartal'));
    await tester.pumpAndSettle();
    expect(zeitraum(tester), '4. Quartal 2026');

    await tester.tap(find.byKey(const ValueKey('statistik-davor')));
    await tester.pumpAndSettle();
    expect(zeitraum(tester), '3. Quartal 2026');

    await tester.tap(find.byKey(const ValueKey('statistik-danach')));
    await tester.pumpAndSettle();
    expect(zeitraum(tester), '4. Quartal 2026');
    expect(bereich('Kennzahlen'), findsOneWidget);
  });

  testWidgets('ein Tipp auf einen Kunden filtert', (tester) async {
    await zeige(tester);
    final zeile = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is Bereich && w.titel == 'Nach Kunde',
      ),
      matching: find.text('Beispiel Feinkost'),
    );
    expect(zeile, findsOneWidget);
    await tester.tap(zeile);
    await tester.pumpAndSettle();
    // Gefiltert braucht es die Kunden nicht mehr.
    expect(bereich('Nach Kunde'), findsNothing);
    expect(find.text('Kochschinken Test'), findsNothing);
    expect(find.text('Grillwurst Probe'), findsOneWidget);
  });

  testWidgets('schmal und dunkel: kein Überlauf', (tester) async {
    await zeige(
      tester,
      groesse: const Size(900, 8000),
      theme: AppTheme.dark(),
    );
    expect(bereich('Muster im Einzelnen'), findsOneWidget);
    expect(bereich('Stand heute'), findsOneWidget);
  });
}
