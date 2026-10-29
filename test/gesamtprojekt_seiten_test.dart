import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/gesamtprojekt_screen.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_screen.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekte_ansicht.dart';

/// Tests für die Seiten mit Gesamtprojekten: die Projektliste mit ihren
/// Gruppen, das Fenster „Neues Projekt" mit mehreren Mustern, die Seite
/// eines Gesamtprojekts und die eines Musters — mit dem Verlauf des
/// Gesamtprojekts darin und „Nicht weiter verfolgen". Die Daten kommen aus
/// den Providern; alles ist erfunden.
void main() {
  final zeit = DateTime(2026, 10, 1);
  final gesamt = Gesamtprojekt(
    id: 'g1',
    name: 'Grillsortiment',
    kunde: 'Beispiel Feinkost',
    anfrage: 'Drei Bratwürste für die Grillsaison',
    createdAt: zeit,
    updatedAt: zeit,
  );
  EntwicklungsProjekt projekt(
    String id,
    String name, {
    String status = 'entwicklung',
    String? gesamtprojektId = 'g1',
    String kunde = 'Beispiel Feinkost',
    int tag = 1,
  }) =>
      EntwicklungsProjekt(
        id: id,
        name: name,
        kunde: kunde,
        status: status,
        neuerProzess: false,
        neueZutaten: false,
        gesamtprojektId: gesamtprojektId,
        createdAt: DateTime(2026, 10, tag),
        updatedAt: DateTime(2026, 10, tag),
      );
  final grob = projekt('a', 'Bratwurst grob');
  final fein = projekt('b', 'Bratwurst fein', status: 'eingestellt', tag: 2);
  final einzeln = projekt(
    'p',
    'Frikadelle',
    status: 'validierung',
    gesamtprojektId: null,
    kunde: 'Muster GmbH',
  );
  ProjektEintrag eintrag(
    String id,
    String projektId,
    String titel, {
    EintragArt art = EintragArt.meilenstein,
    int tag = 1,
    String? wert,
    String? beschreibung,
  }) =>
      ProjektEintrag(
        id: id,
        projektId: projektId,
        art: art.schluessel,
        titel: titel,
        datum: DateTime(2026, 10, tag),
        status: EintragStatus.erledigt.schluessel,
        wert: wert,
        beschreibung: beschreibung,
        createdAt: DateTime(2026, 10, tag),
        updatedAt: DateTime(2026, 10, tag),
      );
  final verlauf = <String, List<ProjektEintrag>>{
    'g1': [
      eintrag(
        'g-mail',
        'g1',
        'Anfrage Grillsortiment',
        art: EintragArt.email,
      ),
    ],
    'a': [eintrag('a-1', 'a', 'Muster angelegt', tag: 2)],
    'b': [
      eintrag(
        'b-2',
        'b',
        'Nicht weiter verfolgt',
        tag: 5,
        wert: 'status:entwicklung>eingestellt',
        beschreibung: 'Grund: Der Kunde nimmt die grobe\n'
            'Status vorher: In Entwicklung',
      ),
      eintrag('b-1', 'b', 'Muster angelegt', tag: 2),
    ],
  };
  final projekte = {for (final p in [grob, fein, einzeln]) p.id: p};

  Future<void> zeige(
    WidgetTester tester,
    Widget seite, {
    Size groesse = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projekteProvider.overrideWith(
            (ref) => Stream.value([grob, fein, einzeln]),
          ),
          gesamtprojekteProvider.overrideWith(
            (ref) => Stream.value([gesamt]),
          ),
          gesamtprojektProvider.overrideWith(
            (ref, id) => Stream.value(id == gesamt.id ? gesamt : null),
          ),
          musterProvider.overrideWith(
            (ref, id) => Stream.value(
              id == gesamt.id ? [grob, fein] : const <EntwicklungsProjekt>[],
            ),
          ),
          projektProvider.overrideWith(
            (ref, id) => Stream.value(projekte[id]),
          ),
          projektEintraegeProvider.overrideWith(
            (ref, id) => Stream.value(verlauf[id] ?? const []),
          ),
          alleEintraegeProvider.overrideWith(
            (ref) => Stream.value([
              for (final liste in verlauf.values) ...liste,
            ]),
          ),
          projektDateienProvider.overrideWith(
            (ref, id) => Stream.value(const <EntwicklungsDatei>[]),
          ),
          projektRezepturenProvider.overrideWith(
            (ref, id) => Stream.value(const <Rezeptur>[]),
          ),
          rezepturenProvider.overrideWith(
            (ref) => Stream.value(const <Rezeptur>[]),
          ),
          alleVersionenProvider.overrideWith(
            (ref) => Stream.value(const <RezepturVersion>[]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: seite),
        ),
      ),
    );
    await bilder(tester);
  }

  testWidgets('Liste: das Gesamtprojekt mit seinen Mustern, zum Zuklappen',
      (tester) async {
    await zeige(tester, const ProjekteAnsicht());

    expect(find.text('Grillsortiment'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('gesamtprojekt-unterzeile-g1')),
          )
          .data,
      '2 Muster: 1 in Entwicklung, 1 nicht weiter verfolgt · '
      '1 hier nicht gezeigt',
    );
    // Aktiv: das laufende Muster darunter, das ruhende nicht.
    expect(find.text('Bratwurst grob'), findsOneWidget);
    expect(find.text('Bratwurst fein'), findsNothing);
    expect(find.text('Frikadelle'), findsOneWidget);
    // Der Kunde steht beim Gesamtprojekt, nicht noch einmal beim Muster.
    expect(find.text('Beispiel Feinkost'), findsOneWidget);
    expect(find.text('2 von 3 Projekten'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('klappen-g1')));
    await bilder(tester);
    expect(find.text('Bratwurst grob'), findsNothing);
    expect(find.text('Grillsortiment'), findsOneWidget);

    // Nicht weiter verfolgt: das ruhende Muster mit seiner Gruppe.
    await tester.tap(find.byKey(const ValueKey('klappen-g1')));
    await tester.tap(find.text('Nicht weiter verfolgt (1)'));
    await bilder(tester);
    expect(find.text('Bratwurst fein'), findsOneWidget);
    expect(find.text('Bratwurst grob'), findsNothing);
    expect(find.text('Frikadelle'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Neues Projekt: ein Gesamtprojekt mit mehreren Mustern',
      (tester) async {
    await zeige(
      tester,
      NeuesProjektDialog(gesamtprojekte: [gesamt]),
      groesse: const Size(1000, 1000),
    );
    expect(find.text('Neues Projekt'), findsOneWidget);
    expect(find.text('Artikelnummer'), findsOneWidget);
    // Ohne Mail gibt es nichts abzulegen.
    expect(find.text('Ablegen'), findsNothing);

    await tester.tap(find.text('Mehrere Muster'));
    await bilder(tester);
    expect(find.text('Neues Gesamtprojekt'), findsOneWidget);
    expect(find.text('Name des Gesamtprojekts'), findsOneWidget);
    expect(find.text('Artikelnummer'), findsNothing);
    expect(find.byKey(const ValueKey('neu-muster-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('neu-muster-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('neu-muster-2')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('neu-muster-mehr')));
    await tester.tap(find.byKey(const ValueKey('neu-muster-mehr')));
    await bilder(tester);
    expect(find.byKey(const ValueKey('neu-muster-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gesamtprojekt: Muster als Karten, Verlauf mit den Mustern',
      (tester) async {
    await zeige(tester, const GesamtprojektScreen(gesamtprojektId: 'g1'));

    expect(find.text('Grillsortiment · Beispiel Feinkost'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('gesamt-zusammenfassung')))
          .data,
      '2 Muster: 1 in Entwicklung, 1 nicht weiter verfolgt',
    );
    expect(find.byKey(const ValueKey('muster-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('muster-b')), findsOneWidget);
    // Beim ruhenden Muster steht, warum.
    expect(find.text('Grund: Der Kunde nimmt die grobe'), findsOneWidget);
    expect(
      [for (final t in tester.widgetList<Tab>(find.byType(Tab))) t.text],
      ['Übersicht', 'Verlauf', 'Dateien'],
    );

    await tester.tap(find.widgetWithText(Tab, 'Verlauf'));
    await bilder(tester);
    // Die Mail des Gesamtprojekts und die Meilensteine der Muster — mit
    // deren Namen.
    expect(find.text('Anfrage Grillsortiment'), findsOneWidget);
    expect(find.text('Muster angelegt'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('herkunft-a-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('herkunft-g-mail')), findsNothing);
    expect(find.text('Meilensteine der Muster (3)'), findsOneWidget);

    await tester.tap(find.text('Meilensteine der Muster (3)'));
    await bilder(tester);
    expect(find.text('Muster angelegt'), findsNothing);
    expect(find.text('Anfrage Grillsortiment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Muster: der Weg zum Gesamtprojekt, dessen Mail im Verlauf',
      (tester) async {
    await zeige(tester, const ProjektScreen(projektId: 'a'));

    expect(
      find.byKey(const ValueKey('projekt-zum-gesamtprojekt')),
      findsOneWidget,
    );
    expect(find.text('Bratwurst grob · Beispiel Feinkost'), findsOneWidget);
    // Die Mail des Gesamtprojekts steht mit im Verlauf, gekennzeichnet.
    expect(find.text('Anfrage Grillsortiment'), findsOneWidget);
    expect(find.byKey(const ValueKey('herkunft-g-mail')), findsOneWidget);
    expect(find.text('2 Einträge'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('verlauf-herkunft')));
    await bilder(tester);
    expect(find.text('Anfrage Grillsortiment'), findsNothing);
    expect(find.text('1 Eintrag'), findsOneWidget);

    // Im Menü: nicht weiter verfolgen und das Gesamtprojekt.
    await tester.tap(find.byKey(const ValueKey('projekt-mehr')));
    await bilder(tester);
    for (final t in const [
      'Nicht weiter verfolgen…',
      'Archivieren…',
      'In ein anderes Gesamtprojekt…',
      'Aus dem Gesamtprojekt lösen…',
      'Muster löschen…',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.tap(find.text('Nicht weiter verfolgen…'));
    await bilder(tester);
    expect(find.text('Muster nicht weiter verfolgen?'), findsOneWidget);
    expect(find.byKey(const ValueKey('nicht-weiter-grund')), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await bilder(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Muster nicht weiter verfolgt: wieder aufnehmen',
      (tester) async {
    await zeige(tester, const ProjektScreen(projektId: 'b'));

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('kopf-phase-titel'))).data,
      'Phase · nicht weiter verfolgt',
    );
    await tester.tap(find.byKey(const ValueKey('kopf-wieder-aufnehmen')));
    await bilder(tester);
    expect(find.text('Muster wieder aufnehmen?'), findsOneWidget);
    expect(
      find.textContaining('in der Phase „In Entwicklung" weiter'),
      findsOneWidget,
    );
    await tester.tap(find.text('Abbrechen'));
    await bilder(tester);
    expect(tester.takeException(), isNull);
  });
}

/// Ein paar Bilder — bis Fenster, Reiter und Daten da sind.
Future<void> bilder(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}
