import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart' show LayoutCallback;
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/druck/druck_fenster.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_rezeptur.dart';
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

  /// [staende]: die Stände der Rezeptur, der neueste zuerst — sonst ein
  /// abgeschlossener und ein Entwurf.
  List<Override> overrides({List<RezepturVersion>? staende}) => [
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
        versionenProvider.overrideWith(
          (ref, id) => Stream.value(staende ?? [v2, v1]),
        ),
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
    List<RezepturVersion>? staende,
    List<Override> dazu = const [],
  }) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides(staende: staende), ...dazu],
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

  testWidgets('Zutaten drucken: das Fenster — mit der Suche der Liste',
      (tester) async {
    await zeige(
      tester,
      const ZutatenAnsicht(),
      dazu: [druckSystemProvider.overrideWithValue(const _Druck())],
    );
    await tester.enterText(find.byType(TextField), 'senf');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('zutaten-drucken')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Zutaten drucken'), findsOneWidget);
    expect(find.text('Nur Treffer der Suche „senf“'), findsOneWidget);
    expect(find.textContaining('Vorschau:'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    // Der Entwurf ist in Arbeit; der eine Hauptknopf schließt ihn ab.
    expect(find.text('Entwurf · in Arbeit'), findsOneWidget);
    expect(find.text('Stand abschließen…'), findsOneWidget);
    // Das Rezepturblatt hat einen eigenen Knopf.
    expect(find.byKey(const ValueKey('stand-drucken')), findsOneWidget);
    // Alles andere steht unter „Mehr".
    expect(find.text('Mit anderem Stand vergleichen…'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('stand-mehr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (final t in const [
      'Mit anderem Stand vergleichen…',
      'Stände nebeneinander drucken…',
      'Etikett ansehen…',
      'Fleischanteil einstellen…',
      'Neuen Stand daraus anlegen',
      'Entwurf löschen…',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rezeptur: abgeschlossener Stand — zum Entwurf in Arbeit',
      (tester) async {
    await zeige(tester, const RezepturScreen(rezepturId: 'r1'));
    await tester.pump();
    await tester.tap(find.text('Stand 1'));
    await tester.pump();
    await tester.pump();
    // In Worten, was mit ihm ist (ohne Datum: die Testdaten haben keins).
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('stand-zustand'))).data,
      'abgeschlossen',
    );
    // Stand 2 ist schon in Arbeit — dorthin führt der Hauptknopf.
    expect(find.text('Zum Entwurf (Stand 2)'), findsOneWidget);
    expect(find.text('Weiterentwickeln'), findsNothing);
    await tester.tap(find.text('Zum Entwurf (Stand 2)'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Stand abschließen…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rezeptur: nur abgeschlossen — weiterentwickeln', (tester) async {
    await zeige(
      tester,
      const RezepturScreen(rezepturId: 'r1'),
      staende: [v1],
    );
    await tester.pump();
    expect(find.text('Weiterentwickeln'), findsOneWidget);
    expect(find.text('Stand abschließen…'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('stand-mehr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Etikett ansehen…'), findsOneWidget);
    // Weiterentwickeln steht schon als Knopf da, löschen lässt sich nur
    // ein Entwurf, vergleichen erst mit zwei Ständen.
    expect(find.text('Neuen Stand daraus anlegen'), findsNothing);
    expect(find.text('Entwurf löschen…'), findsNothing);
    expect(find.text('Mit anderem Stand vergleichen…'), findsNothing);
    expect(find.text('Stände nebeneinander drucken…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rezeptur: Name und Löschen im Menü der Kopfzeile',
      (tester) async {
    await zeige(tester, const RezepturScreen(rezepturId: 'r1'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rezeptur-mehr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Name und Angaben…'), findsOneWidget);
    expect(find.text('Rezeptur löschen…'), findsOneWidget);
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

    await tester.tap(find.byKey(const ValueKey('stand-mehr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Mit anderem Stand vergleichen…'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Vergleich'), findsOneWidget);
    expect(find.byKey(const ValueKey('vergleich-drucken')), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pump();
  });

  group('Im Projekt', () {
    final projekt = EntwicklungsProjekt(
      id: 'pr1',
      name: 'Bratwurst grob',
      status: 'entwicklung',
      neuerProzess: false,
      neueZutaten: false,
      createdAt: zeit,
      updatedAt: zeit,
    );
    final zweite = Rezeptur(
      id: 'r2',
      name: 'Bratwurst grob mit Käse',
      projektId: 'pr1',
      createdAt: zeit,
      updatedAt: zeit,
    );
    Override rezepturen(List<Rezeptur> liste) =>
        projektRezepturenProvider.overrideWith(
          (ref, id) => Stream.value(liste),
        );

    testWidgets(
        'eingebettet: ohne eigene Titelleiste, Knöpfe und Menü in '
        'einer Zeile', (tester) async {
      await zeige(
        tester,
        RezepturScreen(
          rezepturId: 'r1',
          eingebettet: true,
          aktionen: [
            IconButton(
              key: const ValueKey('extra'),
              onPressed: () {},
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const ValueKey('extra')), findsOneWidget);
      expect(find.byKey(const ValueKey('rezeptur-mehr')), findsOneWidget);
      expect(find.byKey(const ValueKey('stand-haupt')), findsOneWidget);
      expect(bereich('Zusammensetzung'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Reiter „Rezeptur": mehrere Rezepturen zur Wahl',
        (tester) async {
      await zeige(
        tester,
        ProjektRezeptur(projekt: projekt),
        dazu: [
          rezepturen([rezeptur, zweite]),
        ],
      );
      await tester.pump();

      ChoiceChip chip(String id) => tester.widget<ChoiceChip>(
            find.byKey(ValueKey('projekt-rezeptur-wahl-$id')),
          );
      expect(chip('r1').selected, isTrue);
      expect(chip('r2').selected, isFalse);
      expect(
        find.byKey(const ValueKey('projekt-rezeptur-r1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('projekt-rezeptur-wahl-r2')));
      await tester.pump();
      await tester.pump();
      expect(chip('r2').selected, isTrue);
      expect(
        find.byKey(const ValueKey('projekt-rezeptur-r2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('projekt-rezeptur-neu')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Reiter „Rezeptur" schmal und dunkel: eine Rezeptur mit '
        'ihrem Namen', (tester) async {
      await zeige(
        tester,
        ProjektRezeptur(projekt: projekt),
        groesse: const Size(760, 700),
        theme: AppTheme.dark(),
        dazu: [
          rezepturen([rezeptur]),
        ],
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('projekt-rezeptur-wahl-r1')),
        findsNothing,
      );
      expect(find.text('Bratwurst grob'), findsWidgets);
      expect(bereich('Zusammensetzung'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Reiter „Rezeptur" ohne Rezeptur: anlegen oder zuordnen',
        (tester) async {
      await zeige(
        tester,
        ProjektRezeptur(projekt: projekt),
        dazu: [rezepturen(const [])],
      );
      await tester.pump();

      expect(find.text('Noch keine Rezeptur im Projekt.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('projekt-rezeptur-neu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('projekt-rezeptur-zuordnen')),
        findsOneWidget,
      );
    });
  });
}

/// Statt Vorschau und Gedächtnis des Druckfensters — die gibt es im Test
/// nicht.
class _Druck extends DruckSystem {
  const _Druck() : super(null);

  @override
  Widget vorschau(
    BuildContext context,
    DruckErgebnis ergebnis,
    LayoutCallback bauen,
    String dateiname,
  ) =>
      Center(child: Text('Vorschau: ${ergebnis.beschreibung}'));
}
