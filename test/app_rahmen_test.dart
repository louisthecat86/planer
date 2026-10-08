import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/shell/app_rahmen.dart';

/// Tests für den Rahmen mit der Navigationsleiste und für die gemeinsamen
/// Bausteine: richtiger Eintrag hervorgehoben, nichts läuft über — auch
/// in schmalen und niedrigen Fenstern und im Dunkelmodus.
///
/// Ein Überlauf (gelb-schwarzer Streifen) meldet Flutter als Fehler; der
/// Test schlägt dann von selbst fehl.
void main() {
  Future<void> zeige(
    WidgetTester tester, {
    required String ort,
    required Size groesse,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Ohne Datenbank: Einklappen wird im Test nicht gespeichert.
          navigationEingeklapptProvider
              .overrideWith((ref) => NavigationsleisteNotifier(null)),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: AppRahmen(
            ort: ort,
            child: Scaffold(
              appBar: AppBar(title: const Text('Seite')),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  FontWeight? gewicht(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.fontWeight;

  testWidgets('breit: alle Bereiche mit Namen, der aktive hervorgehoben',
      (tester) async {
    await zeige(tester, ort: '/board', groesse: const Size(1600, 1000));

    expect(find.text('Übersicht'), findsOneWidget);
    expect(find.text('Auftragsbestand'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('PLANEN'), findsOneWidget);
    expect(gewicht(tester, 'Planungsboard'), FontWeight.w600);
    expect(gewicht(tester, 'Bedarf'), FontWeight.w400);
  });

  testWidgets('Unterseiten heben ihren Bereich hervor', (tester) async {
    await zeige(tester, ort: '/article/p1', groesse: const Size(1600, 1000));
    expect(gewicht(tester, 'Artikel'), FontWeight.w600);
    expect(gewicht(tester, 'Navision-Artikel'), FontWeight.w400);

    await zeige(tester, ort: '/data', groesse: const Size(1600, 1000));
    expect(gewicht(tester, 'Einstellungen'), FontWeight.w600);
  });

  testWidgets('schmales Fenster: nur Symbole, Namen im Tooltip',
      (tester) async {
    await zeige(tester, ort: '/home', groesse: const Size(800, 600));

    expect(find.text('Planungsboard'), findsNothing);
    expect(find.byTooltip('Planungsboard'), findsOneWidget);
    // Zu schmal zum Ausklappen — der Knopf fehlt.
    expect(find.byTooltip('Leiste ausklappen'), findsNothing);
    expect(find.byTooltip('Leiste einklappen'), findsNothing);
  });

  testWidgets('per Knopf ein- und wieder ausklappen', (tester) async {
    await zeige(tester, ort: '/home', groesse: const Size(1600, 900));

    await tester.tap(find.byTooltip('Leiste einklappen'));
    await tester.pump();
    expect(find.text('Planungsboard'), findsNothing);

    await tester.tap(find.byTooltip('Leiste ausklappen'));
    await tester.pump();
    expect(find.text('Planungsboard'), findsOneWidget);
  });

  testWidgets('dunkel und niedrig, offen und eingeklappt: kein Überlauf',
      (tester) async {
    await zeige(
      tester,
      ort: '/home',
      groesse: const Size(1300, 480),
      theme: AppTheme.dark(),
    );
    await tester.tap(find.byTooltip('Leiste einklappen'));
    await tester.pump();
    expect(find.byTooltip('Übersicht'), findsOneWidget);
  });

  testWidgets('Bereich: langer Titel und Zusatz werden gekürzt',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: Bereich(
                titel: 'Ein sehr langer Titel, der nicht in die Kopfzeile '
                    'passt',
                untertitel: '12 Aufträge · 3 erledigt',
                aktionen: [
                  TextButton(onPressed: () {}, child: const Text('Board')),
                ],
                child: const Column(
                  children: [
                    StatusMarke('überbucht', art: StatusArt.fehler),
                    LeerHinweis('Nichts geplant.'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('überbucht'), findsOneWidget);
    expect(find.text('Nichts geplant.'), findsOneWidget);
  });
}
