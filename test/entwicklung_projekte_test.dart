// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/freigabe/freigabe.dart';
import 'package:produktion_planer/features/entwicklung/projekte/datei_aktionen.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_screen.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_verlauf.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekte_ansicht.dart';
import 'package:produktion_planer/features/entwicklung/projekte/zeitstrahl.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';

import 'helpers/test_db.dart';

/// Tests für die Projekte der Produktentwicklung: anlegen, Verlauf,
/// Kommentare, Checklisten, Dateien und Fließdiagramme in der Datenbank —
/// und die Seiten mit Daten aus den Providern. Alles erfunden.
void main() {
  group('Daten', () {
    late AppDatabase db;
    late ProjektRepository repo;
    late EntwicklungRepository rezepte;

    setUp(() {
      db = testDatenbank();
      repo = ProjektRepository(db);
      rezepte = EntwicklungRepository(db);
    });
    tearDown(() => db.close());

    Future<List<ProjektEintrag>> verlauf(String id) =>
        repo.eintraegeBeobachten(id).first;

    test('ein neues Projekt beginnt mit einem Meilenstein', () async {
      final id = await repo.projektAnlegen(
        name: 'Schnitzel Wiener Art',
        kunde: 'Muster GmbH',
        produktidee: 'Paniertes Schnitzel',
        jetzt: DateTime(2026, 3, 2, 9, 30),
      );
      final p = (await repo.projekt(id))!;
      expect(p.kunde, 'Muster GmbH');
      expect(p.status, ProjektStatus.entwicklung.schluessel);
      final e = (await verlauf(id)).single;
      expect(e.art, EintragArt.meilenstein.schluessel);
      expect(e.titel, 'Projekt angelegt');
      expect(e.datum, DateTime(2026, 3, 2));
      expect(await repo.projekteBeobachten().first, hasLength(1));
    });

    test('Checklisten abhaken und wieder lösen', () async {
      final id = await repo.projektAnlegen(name: 'Bratwurst fein');
      await repo.checklistePunkt(
        id,
        schluessel: 'rezepturErstellt',
        erledigt: true,
      );
      await repo.checklistePunkt(
        id,
        schluessel: 'allergene',
        erledigt: true,
        etikett: true,
      );
      var p = (await repo.projekt(id))!;
      expect(checklisteAus(p.checkliste), {'rezepturErstellt'});
      expect(checklisteAus(p.etikettCheckliste), {'allergene'});

      await repo.checklistePunkt(
        id,
        schluessel: 'rezepturErstellt',
        erledigt: false,
      );
      p = (await repo.projekt(id))!;
      expect(p.checkliste, isNull);
    });

    test('Einträge und Kommentare', () async {
      final id = await repo.projektAnlegen(
        name: 'Bratwurst fein',
        jetzt: DateTime(2026, 1, 1),
      );
      final eintrag = await repo.eintragAnlegen(
        projektId: id,
        art: EintragArt.email,
        titel: 'Rückmeldung Kunde',
        datum: DateTime(2026, 3, 5),
        benutzer: 'Entwicklung',
        status: EintragStatus.erhalten,
        ziel: 'KW 12',
        aenderungen: ['Würzung milder'],
      );
      // Das Projekt gilt als geändert.
      final p = (await repo.projekt(id))!;
      expect(p.updatedAt.isAfter(DateTime(2026, 1, 1)), isTrue);

      final liste = await verlauf(id);
      expect(liste.first.id, eintrag);
      expect(liste.first.ziel, 'KW 12');
      expect(texteAus(liste.first.aenderungen), ['Würzung milder']);

      await repo.kommentieren(
        eintrag,
        Kommentar(name: 'QS', text: 'passt', datum: DateTime(2026, 3, 6)),
      );
      await repo.kommentieren(
        eintrag,
        Kommentar(name: 'Vertrieb', text: 'ok', datum: DateTime(2026, 3, 7)),
      );
      var e = (await repo.eintrag(eintrag))!;
      expect([for (final k in Kommentar.listeAus(e.kommentare)) k.name], [
        'QS',
        'Vertrieb',
      ]);
      await repo.kommentarLoeschen(eintrag, 0);
      e = (await repo.eintrag(eintrag))!;
      expect(Kommentar.listeAus(e.kommentare).single.text, 'ok');

      await repo.eintragLoeschen(eintrag);
      expect(await verlauf(id), hasLength(1));
    });

    test('Löschen gibt die Rezepturen frei', () async {
      final id = await repo.projektAnlegen(name: 'Bratwurst fein');
      final rezeptur = await rezepte.rezepturAnlegen(
        name: 'Bratwurst fein',
        projektId: id,
      );
      expect(await repo.rezepturenBeobachten(id).first, hasLength(1));
      await repo.projektLoeschen(id);
      expect(await repo.projekteBeobachten().first, isEmpty);
      expect((await rezepte.rezeptur(rezeptur))!.projektId, isNull);
    });

    test('ein abgeschlossener Stand steht im Verlauf des Projekts', () async {
      final id = await repo.projektAnlegen(name: 'Bratwurst fein');
      final rezeptur = await rezepte.rezepturAnlegen(
        name: 'Bratwurst fein',
        projektId: id,
      );
      final schwein = await rezepte.zutatAnlegen(
        const EntwicklungZutatenCompanion(
          name: Value('Schweineschulter S3'),
          istFleisch: Value(true),
          tierart: Value('schwein'),
          fett: Value(20),
          eiweiss: Value(18),
        ),
      );
      final v = (await rezepte.neuesteVersion(rezeptur))!;
      await rezepte.positionHinzufuegen(v.id, zutatId: schwein, mengeKg: 10);
      await rezepte.versionAbschliessen(v.id);

      final e = (await verlauf(id)).firstWhere(
        (e) => e.art == EintragArt.rezeptur.schluessel,
      );
      expect(e.titel, 'Rezepturstand 1 abgeschlossen');
      expect(e.versionId, v.id);
      expect(e.status, EintragStatus.erledigt.schluessel);
      expect(texteAus(e.aenderungen), contains('1 Zeile'));
    });

    test('ein Stand ohne Projekt bleibt ohne Verlauf', () async {
      final rezeptur = await rezepte.rezepturAnlegen(name: 'Grundbrät');
      final v = (await rezepte.neuesteVersion(rezeptur))!;
      await rezepte.versionAbschliessen(v.id);
      expect(await db.select(db.entwicklungProjektEintraege).get(), isEmpty);
    });

    test('eine gelöschte Datei verschwindet aus Verlauf und Bild', () async {
      final id = await repo.projektAnlegen(name: 'Bratwurst fein');
      await db.into(db.entwicklungDateien).insert(
            EntwicklungDateienCompanion.insert(
              id: 'd1',
              name: 'Foto.png',
              projektId: Value(id),
            ),
          );
      await repo.projektAendern(
        id,
        const EntwicklungProjekteCompanion(bildDateiId: Value('d1')),
      );
      final eintrag = await repo.eintragAnlegen(
        projektId: id,
        art: EintragArt.datei,
        titel: 'Foto',
        datum: DateTime(2026, 3, 1),
        dateiId: 'd1',
      );
      await repo.dateiVerweiseEntfernen('d1');
      expect((await repo.projekt(id))!.bildDateiId, isNull);
      expect((await repo.eintrag(eintrag))!.dateiId, isNull);
    });

    test('Fließdiagramme pflegen', () async {
      await repo.fliessdiagrammSpeichern(id: 'FD_002', bezeichnung: 'Zwei');
      await repo.fliessdiagrammSpeichern(id: 'FD_001', bezeichnung: 'Eins');
      // Neue hinten an, eine geänderte Bezeichnung behält ihren Platz.
      await repo.fliessdiagrammSpeichern(id: 'FD_002', bezeichnung: 'Zwei b');
      var liste = await repo.fliessdiagrammeBeobachten().first;
      expect([for (final f in liste) f.id], ['FD_002', 'FD_001']);
      expect(liste.first.bezeichnung, 'Zwei b');

      final id = await repo.projektAnlegen(name: 'Bratwurst fein');
      await repo.projektAendern(
        id,
        const EntwicklungProjekteCompanion(fliessdiagramm: Value('FD_001')),
      );
      expect(await repo.fliessdiagrammVerwendungen('FD_001'), 1);
      expect(await repo.fliessdiagrammVerwendungen('FD_002'), 0);

      await repo.fliessdiagrammLoeschen('FD_002');
      liste = await repo.fliessdiagrammeBeobachten().first;
      expect([for (final f in liste) f.id], ['FD_001']);
    });
  });

  group('Dateien', () {
    test('Größe, Medientyp und sichere Namen', () {
      expect(groesseText(512), '512 B');
      expect(groesseText(2048), '2 KB');
      expect(groesseText(3 * 1024 * 1024 + 400 * 1024), '3,4 MB');
      expect(mimeTypAus('Datenblatt.PDF'), 'application/pdf');
      expect(mimeTypAus('Foto.jpeg'), 'image/jpeg');
      expect(mimeTypAus('ohne'), isNull);
      expect(sichererDateiname('a/b:c*?.txt'), 'a_b_c__.txt');
      expect(sichererDateiname('   '), 'Datei');
    });
  });

  group('Seiten', () {
    final zeit = DateTime(2026, 10, 16);

    EntwicklungsProjekt projekt(
      String id,
      String name,
      ProjektStatus status, {
      String? kunde,
    }) =>
        EntwicklungsProjekt(
          id: id,
          name: name,
          kunde: kunde,
          artikelnummer: '4711',
          status: status.schluessel,
          produktidee: 'Paniertes Schnitzel aus der Oberschale',
          fliessdiagramm: 'FD_011',
          neuerProzess: true,
          neueZutaten: false,
          zielFett: 12,
          checkliste: checklisteZuJson({'artikelAngelegt'}),
          sensorik: const Sensorik(aussehen: 'goldbraun').alsJson(),
          createdAt: zeit,
          updatedAt: zeit,
        );

    final p1 = projekt(
      'p1',
      'Schnitzel Wiener Art',
      ProjektStatus.validierung,
      kunde: 'Muster GmbH',
    );
    final p2 = projekt('p2', 'Bratwurst fein', ProjektStatus.entwicklung);
    final p3 = projekt('p3', 'Altprojekt', ProjektStatus.archiviert);

    final rezeptur = Rezeptur(
      id: 'r1',
      name: 'Schnitzel Wiener Art',
      projektId: 'p1',
      createdAt: zeit,
      updatedAt: zeit,
    );
    final v1 = RezepturVersion(
      id: 'v1',
      rezepturId: 'r1',
      nummer: 1,
      status: VersionStatus.abgeschlossen,
      verlustProzent: 10,
      fettVerlustProzent: 0,
      verlustArt: 'garen',
      createdAt: zeit,
      updatedAt: zeit,
    );
    final datei = EntwicklungsDatei(
      id: 'd1',
      projektId: 'p1',
      name: 'Datenblatt.pdf',
      mimeTyp: 'application/pdf',
      groesse: 2048,
      createdAt: zeit,
    );
    ProjektEintrag eintrag(
      String id,
      EintragArt art,
      String titel, {
      String? dateiId,
      String? versionId,
      String? kommentare,
    }) =>
        ProjektEintrag(
          id: id,
          projektId: 'p1',
          art: art.schluessel,
          titel: titel,
          datum: zeit,
          status: EintragStatus.erledigt.schluessel,
          dateiId: dateiId,
          versionId: versionId,
          kommentare: kommentare,
          createdAt: zeit,
          updatedAt: zeit,
        );
    final eintraege = [
      eintrag(
        'e3',
        EintragArt.datei,
        'Datenblatt erhalten',
        dateiId: 'd1',
        kommentare: Kommentar.listeZuJson([
          Kommentar(name: 'QS', text: 'passt so', datum: zeit),
        ]),
      ),
      eintrag(
        'e2',
        EintragArt.rezeptur,
        'Rezepturstand 1 abgeschlossen',
        versionId: 'v1',
      ),
      eintrag('e1', EintragArt.meilenstein, 'Projekt angelegt'),
    ];

    const zutat = RechenZutat(
      id: 'z1',
      name: 'Schweineschulter S3',
      istFleisch: true,
      tierart: Tierart.schwein,
      naehrwerte: Naehrwerte(fett: 22, eiweiss: 18),
    );

    final overrides = [
      projekteProvider.overrideWith((ref) => Stream.value([p1, p2, p3])),
      projektProvider.overrideWith((ref, id) => Stream.value(p1)),
      projektEintraegeProvider.overrideWith(
        (ref, id) => Stream.value(eintraege),
      ),
      projektDateienProvider.overrideWith((ref, id) => Stream.value([datei])),
      projektRezepturenProvider.overrideWith(
        (ref, id) => Stream.value([rezeptur]),
      ),
      fliessdiagrammeProvider.overrideWith(
        (ref) => Stream.value([
          Fliessdiagramm(
            id: 'FD_011',
            bezeichnung: 'Bratstraße paniert',
            sortierung: 0,
            createdAt: zeit,
            updatedAt: zeit,
          ),
        ]),
      ),
      alleVersionenProvider.overrideWith((ref) => Stream.value([v1])),
      freigabeUebersichtProvider.overrideWith(
        (ref, id) async => const FreigabeUebersicht(),
      ),
      rechenRezepturProvider.overrideWith(
        (ref, id) async => const RechenRezeptur(
          id: 'r1',
          name: 'Schnitzel Wiener Art',
          verlustProzent: 10,
          verlustart: Verlustart.garen,
          positionen: [RechenPosition.zutat(zutat, mengeKg: 10)],
        ),
      ),
    ];

    Finder bereich(String titel, [String? untertitel]) =>
        find.byWidgetPredicate(
          (w) =>
              w is BereichKopf &&
              w.titel == titel &&
              (untertitel == null || w.untertitel == untertitel),
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

    Future<void> reiter(WidgetTester tester, String name) async {
      await tester.tap(find.widgetWithText(Tab, name));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Der Reiter baut sich erst im letzten Bild auf; seine Daten kommen
      // danach — ein Bild mehr, damit sie dastehen.
      await tester.pump();
    }

    testWidgets('Projekte: aktive Liste, Archiv und Suche', (tester) async {
      await zeige(tester, const ProjekteAnsicht());

      expect(find.text('Schnitzel Wiener Art'), findsOneWidget);
      expect(find.text('Bratwurst fein'), findsOneWidget);
      expect(find.text('Altprojekt'), findsNothing);
      expect(find.text('Muster GmbH'), findsOneWidget);
      expect(find.text('1 / 8'), findsNWidgets(2));

      await tester.tap(find.text('Archiv (1)'));
      await tester.pump();
      expect(find.text('Altprojekt'), findsOneWidget);
      expect(find.text('Bratwurst fein'), findsNothing);

      await tester.tap(find.text('Aktiv (2)'));
      await tester.enterText(find.byType(TextField), 'muster');
      await tester.pump();
      expect(find.text('Schnitzel Wiener Art'), findsOneWidget);
      expect(find.text('Bratwurst fein'), findsNothing);
    });

    testWidgets('Projekte schmal und dunkel: kein Überlauf', (tester) async {
      await zeige(
        tester,
        const ProjekteAnsicht(),
        groesse: const Size(600, 700),
        theme: AppTheme.dark(),
      );
      expect(find.text('Schnitzel Wiener Art'), findsOneWidget);
    });

    testWidgets('Projektseite breit: Übersicht mit Zielen und Checklisten',
        (tester) async {
      await zeige(tester, const ProjektScreen(projektId: 'p1'));
      await tester.pump();

      expect(find.text('Schnitzel Wiener Art · Muster GmbH'), findsOneWidget);
      expect(bereich('Stammdaten'), findsOneWidget);
      expect(bereich('Checkliste', '1 von 8'), findsOneWidget);
      expect(bereich('Etikett (LMIV)', '0 von 12'), findsOneWidget);
      expect(bereich('Rezepturen', '1'), findsOneWidget);
      expect(find.text('Stand 1 · abgeschlossen'), findsOneWidget);
      expect(find.text('FD_011 · Bratstraße paniert'), findsOneWidget);
      // Die Rezeptur hat mehr Fett als das Ziel erlaubt.
      expect(find.textContaining('über dem Ziel'), findsOneWidget);
    });

    testWidgets('Projektseite: Verlauf, Dateien und Sensorik',
        (tester) async {
      await zeige(tester, const ProjektScreen(projektId: 'p1'));

      await reiter(tester, 'Verlauf');
      // Zuerst der Zeitstrahl: Titel und Datum an der Achse.
      expect(find.byType(Zeitstrahl), findsOneWidget);
      expect(find.text('Datenblatt erhalten'), findsOneWidget);
      expect(find.text('3 Einträge'), findsOneWidget);
      expect(find.text('passt so'), findsNothing);

      // Antippen öffnet den Eintrag mit allem, was die Karte kann.
      await tester.tap(find.text('Datenblatt erhalten'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(EintragKarte), findsOneWidget);
      expect(find.text('passt so'), findsOneWidget);
      await tester.tap(find.text('Schließen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(EintragKarte), findsNothing);

      // Als Liste: die Karten mit Kommentar, Datei und Rezepturstand.
      await tester.tap(find.byTooltip('Liste'));
      await tester.pump();
      expect(find.byType(Zeitstrahl), findsNothing);
      expect(find.text('Datenblatt erhalten'), findsOneWidget);
      expect(find.text('passt so'), findsOneWidget);
      expect(find.text('Datenblatt.pdf'), findsOneWidget);
      expect(find.text('Rezepturstand 1 öffnen'), findsOneWidget);
      expect(find.text('3 Einträge'), findsOneWidget);

      await reiter(tester, 'Dateien');
      expect(find.text('Datenblatt.pdf'), findsOneWidget);
      expect(
        find.textContaining('Verlauf: Datenblatt erhalten'),
        findsOneWidget,
      );

      await reiter(tester, 'Sensorik');
      expect(bereich('Sensorik'), findsOneWidget);
      expect(find.text('goldbraun'), findsOneWidget);
    });

    testWidgets('Projektseite schmal und dunkel: kein Überlauf',
        (tester) async {
      await zeige(
        tester,
        const ProjektScreen(projektId: 'p1'),
        groesse: const Size(700, 800),
        theme: AppTheme.dark(),
      );
      await tester.pump();
      expect(bereich('Stammdaten'), findsOneWidget);
      await reiter(tester, 'Verlauf');
      expect(find.byType(Zeitstrahl), findsOneWidget);
      expect(find.text('Datenblatt erhalten'), findsOneWidget);
      await tester.tap(find.byTooltip('Liste'));
      await tester.pump();
      expect(find.text('passt so'), findsOneWidget);
    });
  });
}
