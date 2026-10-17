import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/rezepturen/rezeptur_screen.dart';
import 'package:produktion_planer/features/entwicklung/rezepturen/rezepturen_ansicht.dart';
import 'package:produktion_planer/features/entwicklung/zutaten/zutaten_ansicht.dart';

/// Seitentests der Produktentwicklung: Zutaten, Rezepturen und eine
/// Rezeptur mit Ständen — in breiten und schmalen Fenstern, hell und
/// dunkel, ohne Überlauf. Die Daten kommen aus den Providern, nicht aus
/// einer Datenbank. Alles erfunden.
void main() {
  final zeit = DateTime(2026, 10, 16);

  Zutat zutat(
    String id,
    String name, {
    bool fleisch = false,
    String? allergene,
    double? fett,
  }) =>
      Zutat(
        id: id,
        name: name,
        istFleisch: fleisch,
        istWasser: false,
        tierart: fleisch ? 'schwein' : null,
        quidPflicht: false,
        allergene: allergene,
        fett: fett,
        eiweiss: fleisch ? 18 : null,
        createdAt: zeit,
        updatedAt: zeit,
      );

  final schwein = zutat('z1', 'Schweineschulter S3', fleisch: true, fett: 22);
  final senf = zutat(
    'z2',
    'Senfsaat gemahlen mit einem sehr langen Namen aus dem Katalog',
    allergene: 'senf',
  );

  final rezeptur = Rezeptur(
    id: 'r1',
    name: 'Bratwurst grob',
    artikelnummer: '4711',
    createdAt: zeit,
    updatedAt: zeit,
  );

  RezepturVersion version(String id, int nummer, String status) =>
      RezepturVersion(
        id: id,
        rezepturId: 'r1',
        nummer: nummer,
        status: status,
        verlustProzent: 10,
        fettVerlustProzent: 0,
        verlustArt: 'garen',
        createdAt: zeit,
        updatedAt: zeit,
      );

  final v1 = version('v1', 1, VersionStatus.abgeschlossen);
  final v2 = version('v2', 2, VersionStatus.entwurf);

  RezepturPosition position(String id, String zutatId, double kg, int i) =>
      RezepturPosition(
        id: id,
        versionId: 'v2',
        reihenfolge: i,
        zutatId: zutatId,
        mengeKg: kg,
        createdAt: zeit,
        updatedAt: zeit,
      );

  final positionen = [
    position('p1', 'z1', 97.5, 0),
    position('p2', 'z2', 2.5, 1),
  ];

  RechenRezeptur rechen() => RechenRezeptur(
        id: 'r1',
        name: 'Bratwurst grob',
        verlustProzent: 10,
        verlustart: Verlustart.garen,
        positionen: [
          RechenPosition.zutat(rechenZutatAus(schwein), mengeKg: 97.5),
          RechenPosition.zutat(rechenZutatAus(senf), mengeKg: 2.5),
        ],
      );

  final overrides = [
    zutatenProvider.overrideWith((ref) => Stream.value([schwein, senf])),
    alleZutatenProvider.overrideWith(
      (ref) => Stream.value({'z1': schwein, 'z2': senf}),
    ),
    rezepturenProvider.overrideWith((ref) => Stream.value([rezeptur])),
    alleRezepturenProvider.overrideWith(
      (ref) => Stream.value({'r1': rezeptur}),
    ),
    alleVersionenProvider.overrideWith((ref) => Stream.value([v1, v2])),
    rezepturProvider.overrideWith((ref, id) => Stream.value(rezeptur)),
    versionenProvider.overrideWith((ref, id) => Stream.value([v2, v1])),
    positionenProvider.overrideWith((ref, id) => Stream.value(positionen)),
    rechenRezepturProvider.overrideWith((ref, id) async => rechen()),
  ];

  /// Ein Bereich über seinen Kopf — der Titel steht dort mit dem Zusatz
  /// in einem Text.
  Finder bereich(String titel) => find.byWidgetPredicate(
        (w) => w is BereichKopf && w.titel == titel,
      );

  Future<void> zeige(
    WidgetTester tester,
    Widget seite, {
    Size groesse = const Size(1400, 900),
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
          home: Scaffold(body: seite),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Zutaten: Liste mit Art, Allergenen und Nährwerten',
      (tester) async {
    await zeige(tester, const ZutatenAnsicht());

    expect(find.text('Schweineschulter S3'), findsOneWidget);
    expect(find.text('Fleisch · Schwein'), findsOneWidget);
    expect(find.text('Senf'), findsOneWidget);
    expect(find.text('2 von 2 Zutaten'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'senf');
    await tester.pump();
    expect(find.text('1 von 2 Zutaten'), findsOneWidget);
  });

  testWidgets('Zutaten schmal und dunkel: kein Überlauf', (tester) async {
    await zeige(
      tester,
      const ZutatenAnsicht(),
      groesse: const Size(640, 600),
      theme: AppTheme.dark(),
    );
    expect(find.text('Schweineschulter S3'), findsOneWidget);
  });

  testWidgets('Rezepturen: Liste mit neuestem Stand', (tester) async {
    await zeige(tester, const RezepturenAnsicht());

    expect(find.text('Bratwurst grob'), findsOneWidget);
    expect(find.text('Stand 2 · Entwurf'), findsOneWidget);
  });

  testWidgets('Rezeptur breit: Zusammensetzung neben dem Ergebnis',
      (tester) async {
    await zeige(tester, const RezepturScreen(rezepturId: 'r1'));
    await tester.pump();

    expect(bereich('Zusammensetzung'), findsOneWidget);
    expect(bereich('Zutatenliste'), findsOneWidget);
    expect(find.text('Schweineschulter S3'), findsOneWidget);
    expect(bereich('Nährwerte je 100 g'), findsOneWidget);
    // Der Entwurf ist bearbeitbar, der Stand lässt sich abschließen.
    expect(find.text('Abschließen'), findsOneWidget);
    expect(find.text('Vergleichen'), findsOneWidget);
  });

  testWidgets('Rezeptur schmal und dunkel: untereinander, kein Überlauf',
      (tester) async {
    await zeige(
      tester,
      const RezepturScreen(rezepturId: 'r1'),
      groesse: const Size(760, 700),
      theme: AppTheme.dark(),
    );
    await tester.pump();

    expect(bereich('Zusammensetzung'), findsOneWidget);
  });

  testWidgets('Vergleich zweier Stände öffnet sich', (tester) async {
    await zeige(tester, const RezepturScreen(rezepturId: 'r1'));
    await tester.pump();

    await tester.tap(find.text('Vergleichen'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Vergleich'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pump();
  });
}
