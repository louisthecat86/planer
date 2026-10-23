import 'dart:convert';

// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/auto_backup_trigger.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/freigabe/freigabe.dart';
import 'package:produktion_planer/features/entwicklung/projekte/datei_aktionen.dart';
import 'package:produktion_planer/features/entwicklung/projekte/fliessdiagramm_liste.dart';
import 'package:produktion_planer/features/entwicklung/projekte/fliessdiagramme_dialog.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_screen.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_verlauf.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekte_ansicht.dart';
import 'package:produktion_planer/features/entwicklung/projekte/zeitstrahl.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spezifikation_dienst.dart';

import 'helpers/test_db.dart';

/// Tests für die Projekte der Produktentwicklung: anlegen, Verlauf,
/// Kommentare, Checklisten mit zurückgestelltem Produktfoto, Dateien und
/// Fließdiagramme in der Datenbank — und die Seiten mit Daten aus den
/// Providern. Alles erfunden.
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
      // Die Pflichtangaben des Etiketts: abgehakt oder „trifft nicht zu"
      // (F28).
      await repo.lmivPunkt(
        id,
        schluessel: 'allergene',
        stand: LmivStand.erledigt,
      );
      await repo.lmivPunkt(
        id,
        schluessel: 'schutzgas',
        stand: LmivStand.trifftNichtZu,
      );
      var p = (await repo.projekt(id))!;
      expect(checklisteAus(p.checkliste), {'rezepturErstellt'});
      expect(lmivAus(p.etikettCheckliste), {
        'allergene': LmivStand.erledigt,
        'schutzgas': LmivStand.trifftNichtZu,
      });
      // Wer nur Haken liest (etwa eine frühere Version), sieht den einen.
      expect(checklisteAus(p.etikettCheckliste), {'allergene'});

      await repo.checklistePunkt(
        id,
        schluessel: 'rezepturErstellt',
        erledigt: false,
      );
      await repo.lmivPunkt(id, schluessel: 'allergene', stand: LmivStand.offen);
      await repo.lmivPunkt(id, schluessel: 'schutzgas', stand: LmivStand.offen);
      p = (await repo.projekt(id))!;
      expect(p.checkliste, isNull);
      expect(p.etikettCheckliste, isNull);
    });

    test('Produktfoto zurückstellen und hinterlegen (F37)', () async {
      final id = await repo.projektAnlegen(name: 'Bratwurst fein');
      await repo.checklistePunkt(
        id,
        schluessel: 'navisionAngelegt',
        erledigt: true,
      );
      await repo.checklisteZurueckstellen(
        id,
        schluessel: 'produktfotoHinterlegt',
        zurueck: true,
      );
      var p = (await repo.projekt(id))!;
      expect(checklisteAus(p.checkliste), {'navisionAngelegt'});
      expect(
        checklisteZurueckgestellt(p.checkliste),
        {'produktfotoHinterlegt'},
      );

      // Ein anderer Haken lässt das „Später" stehen.
      await repo.checklistePunkt(
        id,
        schluessel: 'navisionAngelegt',
        erledigt: false,
      );
      p = (await repo.projekt(id))!;
      expect(checklisteAus(p.checkliste), isEmpty);
      expect(
        checklisteZurueckgestellt(p.checkliste),
        {'produktfotoHinterlegt'},
      );

      // Mit einem Foto ist es nicht mehr zurückgestellt.
      await db.into(db.entwicklungDateien).insert(
            EntwicklungDateienCompanion.insert(
              id: 'f1',
              name: 'Foto.jpg',
              projektId: Value(id),
            ),
          );
      await repo.produktfotoSetzen(id, 'f1');
      p = (await repo.projekt(id))!;
      expect(p.bildDateiId, 'f1');
      expect(p.checkliste, isNull);

      // Zurückstellen lässt sich auch wieder aufheben.
      await repo.checklisteZurueckstellen(
        id,
        schluessel: 'produktfotoHinterlegt',
        zurueck: true,
      );
      await repo.checklisteZurueckstellen(
        id,
        schluessel: 'produktfotoHinterlegt',
        zurueck: false,
      );
      expect((await repo.projekt(id))!.checkliste, isNull);
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
        status: EintragStatus.erledigt,
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
      // Mit dem Namen der Rezeptur — ein Projekt kann mehrere haben.
      expect(e.titel, 'Bratwurst fein · Stand 1');
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

    test('eine gelöschte Datei verschwindet aus Verlauf und Foto', () async {
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
          fliessdiagramm: 'FD_101',
          neuerProzess: true,
          neueZutaten: false,
          zielFett: 12,
          checkliste: checklisteZuJson({'artikelAngelegt'}),
          // Zwei der zwölf Pflichtangaben geprüft (F28).
          etikettCheckliste: lmivZuJson(const {
            'bezeichnung': LmivStand.erledigt,
            'schutzgas': LmivStand.trifftNichtZu,
          }),
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
    const zutat = RechenZutat(
      id: 'z1',
      name: 'Schweineschulter S3',
      istFleisch: true,
      tierart: Tierart.schwein,
      naehrwerte: Naehrwerte(fett: 22, eiweiss: 18),
    );
    const eingabe = RechenRezeptur(
      id: 'r1',
      name: 'Schnitzel Wiener Art',
      verlustProzent: 10,
      verlustart: Verlustart.garen,
      positionen: [RechenPosition.zutat(zutat, mengeKg: 10)],
    );
    // Abgeschlossen — eingefroren mit allen Zutatendaten (daraus rechnet
    // die Checkliste die Nährwerte).
    final v1 = RezepturVersion(
      id: 'v1',
      rezepturId: 'r1',
      nummer: 1,
      status: VersionStatus.abgeschlossen,
      verlustProzent: 10,
      fettVerlustProzent: 0,
      verlustArt: 'garen',
      stand: jsonEncode(eingabe.toJson()),
      abgeschlossenAm: zeit,
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

    /// [seite]: das Projekt der Projektseite, sonst das Schnitzel;
    /// [verlauf]: seine Einträge, sonst die drei oben.
    List<Override> overrides({
      EntwicklungsProjekt? seite,
      List<ProjektEintrag>? verlauf,
    }) =>
        [
          projekteProvider.overrideWith((ref) => Stream.value([p1, p2, p3])),
          projektProvider.overrideWith((ref, id) => Stream.value(seite ?? p1)),
          projektEintraegeProvider.overrideWith(
            (ref, id) => Stream.value(verlauf ?? eintraege),
          ),
          projektDateienProvider.overrideWith((ref, id) => Stream.value([datei])),
          projektRezepturenProvider.overrideWith(
            (ref, id) => Stream.value([rezeptur]),
          ),
          // Alle Rezepturen — für die Checklisten der Projektliste.
          rezepturenProvider.overrideWith((ref) => Stream.value([rezeptur])),
          fliessdiagrammeProvider.overrideWith(
            (ref) => Stream.value([
              Fliessdiagramm(
                id: 'FD_101',
                bezeichnung: 'Testware paniert',
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
          rechenRezepturProvider.overrideWith((ref, id) async => eingabe),
          // Der Reiter „Produkt": noch kein Stand für die Spezifikation.
          spezStaendeProvider.overrideWith((ref, id) async => const []),
          spezVorschauProvider.overrideWith((ref, a) async => null),
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
      EntwicklungsProjekt? projekt,
      List<ProjektEintrag>? verlauf,
      List<Override> dazu = const [],
    }) async {
      tester.view.physicalSize = groesse;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides(seite: projekt, verlauf: verlauf),
            ...dazu,
          ],
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
      // danach — und was aus ihnen gerechnet wird (die Rezeptur, dann ihr
      // Ergebnis für den Vergleich mit dem Ziel), noch ein paar Bilder
      // später.
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
    }

    testWidgets('Projekte: aktive Liste, Archiv und Suche', (tester) async {
      await zeige(tester, const ProjekteAnsicht());

      expect(find.text('Schnitzel Wiener Art'), findsOneWidget);
      expect(find.text('Bratwurst fein'), findsOneWidget);
      expect(find.text('Altprojekt'), findsNothing);
      expect(find.text('Muster GmbH'), findsOneWidget);
      // Die Checkliste rechnet sich selbst (F25): beim Schnitzel Artikel
      // (früher abgehakt), Rezeptur und Nährwerte aus Stand 1, bei der
      // Bratwurst ohne Rezeptur nur der Artikel.
      expect(find.text('3 von 9'), findsOneWidget);
      expect(find.text('1 von 9'), findsOneWidget);

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
      // Fünf Reiter (F26).
      expect(
        [for (final t in tester.widgetList<Tab>(find.byType(Tab))) t.text],
        ['Verlauf', 'Übersicht', 'Produkt', 'Herstellung', 'Dateien'],
      );
      // Ein Projekt öffnet mit dem Verlauf (F21).
      expect(find.byType(Zeitstrahl), findsOneWidget);
      await reiter(tester, 'Übersicht');
      expect(bereich('Stammdaten'), findsOneWidget);
      expect(bereich('Checkliste', '3 von 9'), findsOneWidget);
      expect(
        find.text('Schnitzel Wiener Art · Stand 1 abgeschlossen'),
        findsOneWidget,
      );
      expect(find.text('Stand 1: alle Zutaten mit Nährwerten'), findsOneWidget);
      expect(find.text('Früher von Hand abgehakt'), findsOneWidget);
      expect(
        find.text('Fehlt: Geruch, Geschmack und Konsistenz'),
        findsOneWidget,
      );
      // Von Hand nur noch Navision.
      expect(find.text('von Hand'), findsOneWidget);
      // Das Etikett mit seinen Pflichtangaben — zugeklappt, es ist noch
      // nicht dran.
      expect(
        find.byKey(const ValueKey('check-etikettErstellt')),
        findsOneWidget,
      );
      expect(find.text('2 von 12 Pflichtangaben geprüft'), findsOneWidget);
      expect(find.byKey(const ValueKey('lmiv-zutaten')), findsNothing);
      await tester.ensureVisible(find.text('Etikett erstellt'));
      await tester.pump();
      await tester.tap(find.text('Etikett erstellt'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      bool haken(String schluessel) =>
          tester.widget<Checkbox>(find.byKey(ValueKey('lmiv-$schluessel')))
              .value!;
      bool trifftNichtZu(String schluessel) => tester
          .widget<FilterChip>(find.byKey(ValueKey('lmiv-nz-$schluessel')))
          .selected;
      expect(haken('bezeichnung'), isTrue);
      expect(haken('zutaten'), isFalse);
      expect(trifftNichtZu('schutzgas'), isTrue);
      expect(haken('schutzgas'), isFalse);
      expect(trifftNichtZu('zutaten'), isFalse);
      expect(find.text('trifft nicht zu'), findsNWidgets(12));
      // Kein früherer Haken — nichts zurückzunehmen.
      expect(find.byKey(const ValueKey('etikett-alter-haken')), findsNothing);
      expect(bereich('Etikett (LMIV)'), findsNothing);
      expect(bereich('Rezepturen', '1'), findsOneWidget);
      expect(find.text('Stand 1 · abgeschlossen'), findsOneWidget);
      // Die Artikelnummer steht nur hier — vor der Freigabe änderbar.
      final nummer = find.descendant(
        of: find.byKey(const ValueKey('stamm-artikelnummer')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(nummer).enabled, isTrue);
      expect(find.text('4711'), findsOneWidget);
      // Das Fließdiagramm: nur die Auswahl aus der Liste, kein PDF.
      expect(find.text('FD_101 · Testware paniert'), findsOneWidget);
      expect(
        find.byTooltip('Liste der Fließdiagramme bearbeiten'),
        findsOneWidget,
      );
      // Die Rezeptur hat mehr Fett als das Ziel erlaubt.
      expect(find.textContaining('über dem Ziel'), findsOneWidget);
      // Das Produktfoto pflegt man im Reiter „Produkt"; hier fehlt es noch.
      expect(bereich('Produktfoto'), findsOneWidget);
      expect(find.text('Fehlt noch'), findsOneWidget);
      expect(
        find.text('Im Reiter „Produkt" hinterlegen'),
        findsOneWidget,
      );
    });

    Future<void> bilder(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
    }

    testWidgets('Projektkopf: Phase, Fortschritt und was als Nächstes kommt',
        (tester) async {
      final offen = ProjektEintrag(
        id: 'e4',
        projektId: 'p1',
        art: EintragArt.notiz.schluessel,
        titel: 'Muster anfragen',
        datum: zeit,
        status: EintragStatus.offen.schluessel,
        createdAt: zeit,
        updatedAt: zeit,
      );
      await zeige(
        tester,
        const ProjektScreen(projektId: 'p1'),
        verlauf: [...eintraege, offen],
      );
      final kopf = find.byKey(const ValueKey('projekt-kopf'));
      expect(kopf, findsOneWidget);
      // Der Kopf steht über jedem Reiter — hier über dem Verlauf.
      expect(find.byType(Zeitstrahl), findsOneWidget);
      expect(
        find.descendant(of: kopf, matching: find.text('3 von 9')),
        findsOneWidget,
      );
      expect(find.text('Als Nächstes: Sensorik beschreiben'), findsOneWidget);
      expect(find.text('1 offener Eintrag im Verlauf'), findsOneWidget);
      // Was an Angaben fehlt — antippen startet den Assistenten (F39).
      expect(
        find.text('5 Angaben fehlen — ergänzen…'),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          'Fehlt: Sensorik, Produktfoto, Lagerung, Haltbarkeit und '
          'Verpackung',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('kopf-angaben')));
      await bilder(tester);
      expect(find.text('Angaben ergänzen'), findsOneWidget);
      expect(find.text('Wie ist das fertige Produkt?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assistent-schliessen')));
      await bilder(tester);
      // Das Fenster blendet noch aus.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Angaben ergänzen'), findsNothing);

      // „Als Nächstes" führt dorthin, wo es zu tun ist …
      await tester.tap(find.text('Als Nächstes: Sensorik beschreiben'));
      await bilder(tester);
      expect(bereich('Sensorik'), findsOneWidget);
      expect(find.byType(Zeitstrahl), findsNothing);
      // … die offenen Einträge in den Verlauf.
      await tester.tap(find.text('1 offener Eintrag im Verlauf'));
      await bilder(tester);
      expect(find.byType(Zeitstrahl), findsOneWidget);

      // Die aktuelle Phase lässt sich nicht antippen, eine andere fragt
      // erst nach.
      await tester.tap(find.byKey(const ValueKey('phase-validierung')));
      await bilder(tester);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('phase-entwicklung')));
      await bilder(tester);
      expect(find.text('Zurück in die Entwicklung?'), findsOneWidget);
      expect(find.textContaining('als Meilenstein im Verlauf'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await bilder(tester);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('phase-produktion')));
      await bilder(tester);
      expect(find.text('In Produktion setzen?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await bilder(tester);

      // Was sich aus dem Projekt erstellen lässt — in einem Menü.
      await tester.tap(find.byKey(const ValueKey('projekt-erstellen')));
      await bilder(tester);
      for (final t in const [
        'Spezifikation…',
        'Etikett…',
        'Projektbericht (PDF)…',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.tapAt(const Offset(5, 5));
      await bilder(tester);
      expect(find.text('Etikett…'), findsNothing);

      // Der Rest im Menü daneben; Archivieren fragt nach.
      await tester.tap(find.byKey(const ValueKey('projekt-mehr')));
      await bilder(tester);
      expect(find.text('Umbenennen…'), findsOneWidget);
      expect(find.text('Projekt löschen…'), findsOneWidget);
      await tester.tap(find.text('Archivieren…'));
      await bilder(tester);
      expect(find.text('Projekt archivieren?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await bilder(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Projektkopf archiviert: wieder aufnehmen', (tester) async {
      await zeige(
        tester,
        const ProjektScreen(projektId: 'p3'),
        projekt: p3,
        verlauf: [
          ProjektEintrag(
            id: 'w1',
            projektId: 'p3',
            art: EintragArt.meilenstein.schluessel,
            titel: 'Archiviert',
            datum: zeit,
            status: EintragStatus.erledigt.schluessel,
            wert: 'status:validierung>archiviert',
            createdAt: zeit,
            updatedAt: zeit,
          ),
        ],
      );
      expect(find.text('Phase · archiviert'), findsOneWidget);
      // Archiviert ruhen die Phasen, bis es weitergeht.
      await tester.tap(find.byKey(const ValueKey('phase-entwicklung')));
      await bilder(tester);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.byKey(const ValueKey('kopf-wieder-aufnehmen')));
      await bilder(tester);
      expect(find.text('Projekt wieder aufnehmen?'), findsOneWidget);
      // Weiter in der Phase vor dem Archiv.
      expect(
        find.textContaining('in der Phase „Validierung" weiter'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Wieder aufnehmen'),
        findsOneWidget,
      );
      await tester.tap(find.text('Abbrechen'));
      await bilder(tester);

      await tester.tap(find.byKey(const ValueKey('projekt-mehr')));
      await bilder(tester);
      expect(find.text('Wieder aufnehmen…'), findsOneWidget);
      expect(find.text('Archivieren…'), findsNothing);
      expect(tester.takeException(), isNull);
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

      // Nur noch offen oder erledigt — antippen schaltet um (F24).
      expect(find.byTooltip('Antippen: wieder offen'), findsWidgets);
      await tester.tap(find.byTooltip('Mehr').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Wieder auf offen setzen'), findsOneWidget);
      await tester.tap(find.text('Bearbeiten'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final wahl = find.byKey(const ValueKey('eintrag-status'));
      expect(wahl, findsOneWidget);
      expect(
        find.descendant(of: wahl, matching: find.text('erledigt')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: wahl, matching: find.text('offen')),
        findsOneWidget,
      );
      await tester.tap(find.text('Abbrechen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(wahl, findsNothing);

      await reiter(tester, 'Dateien');
      expect(find.text('Datenblatt.pdf'), findsOneWidget);
      expect(
        find.textContaining('Verlauf: Datenblatt erhalten'),
        findsOneWidget,
      );

      await reiter(tester, 'Produkt');
      expect(bereich('Sensorik'), findsOneWidget);
      expect(find.text('goldbraun'), findsOneWidget);
    });

    testWidgets('Projektseite: Filter und Entwicklungsweg im Verlauf',
        (tester) async {
      await zeige(tester, const ProjektScreen(projektId: 'p1'));
      await reiter(tester, 'Verlauf');
      final datei = find.widgetWithText(FilterChip, 'Datei (1)');
      expect(datei, findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Meilenstein (1)'), findsOneWidget);
      // Ohne Dateien: der Eintrag mit dem Datenblatt fehlt.
      await tester.tap(datei);
      await tester.pump();
      expect(find.text('Datenblatt erhalten'), findsNothing);
      expect(find.text('3 Einträge'), findsOneWidget);
      await tester.tap(datei);
      await tester.pump();
      expect(find.text('Datenblatt erhalten'), findsOneWidget);

      // Der Entwicklungsweg: die Idee, der Stand als Station.
      await tester.tap(find.byTooltip('Entwicklungsweg'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Idee und Anfrage'), findsOneWidget);
      expect(find.textContaining('Station 1 · '), findsOneWidget);
      expect(find.text('Datenblatt erhalten'), findsOneWidget);
      // Ohne Filter in dieser Ansicht.
      expect(datei, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Produktfoto: „Später" stellt zurück (F37)', (tester) async {
      final speicher = _Zurueckstellen();
      await zeige(
        tester,
        const ProjektScreen(projektId: 'p1'),
        dazu: [
          projektRepositoryProvider.overrideWithValue(speicher),
          autoBackupTriggerProvider.overrideWithValue(_OhneSicherung()),
        ],
      );
      await reiter(tester, 'Produkt');
      // Neben der Sensorik: noch kein Foto — wählen oder später.
      expect(find.byKey(const ValueKey('produktfoto')), findsOneWidget);
      expect(find.text('Noch kein Produktfoto'), findsOneWidget);
      expect(find.byKey(const ValueKey('foto-waehlen')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('foto-spaeter')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('foto-spaeter')));
      await tester.pump();
      expect(speicher.aufrufe, ['p1 produktfotoHinterlegt true']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Produktfoto zurückgestellt: der Kopf erinnert dezent (F37)',
        (tester) async {
      final spaeter = p1.copyWith(
        checkliste: Value(
          checklisteMit(p1.checkliste, 'produktfotoHinterlegt', kCheckSpaeter),
        ),
      );
      await zeige(
        tester,
        const ProjektScreen(projektId: 'p1'),
        projekt: spaeter,
      );
      final kopf = find.byKey(const ValueKey('projekt-kopf'));
      // Es zählt weiter als offen, „Als Nächstes" bleibt bei der Sensorik.
      expect(
        find.descendant(of: kopf, matching: find.text('3 von 9')),
        findsOneWidget,
      );
      expect(find.text('Als Nächstes: Sensorik beschreiben'), findsOneWidget);
      final fehlt =
          find.byKey(const ValueKey('kopf-fehlt-produktfotoHinterlegt'));
      expect(
        find.descendant(
          of: fehlt,
          matching: find.text('Produktfoto fehlt noch'),
        ),
        findsOneWidget,
      );

      // Antippen führt zum Foto im Reiter „Produkt".
      await tester.tap(fehlt);
      await bilder(tester);
      expect(
        find.text('Zurückgestellt, bis es ein Foto gibt'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('foto-wieder')), findsOneWidget);
      expect(find.byKey(const ValueKey('foto-spaeter')), findsNothing);

      // In der Übersicht: dezent, mit Uhr in der Checkliste.
      await reiter(tester, 'Übersicht');
      expect(find.text('Fehlt noch — zurückgestellt'), findsOneWidget);
      expect(
        find.byTooltip('Zurückgestellt — „Als Nächstes" geht weiter'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
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
      expect(find.byType(Zeitstrahl), findsOneWidget);
      await reiter(tester, 'Übersicht');
      expect(bereich('Stammdaten'), findsOneWidget);
      await reiter(tester, 'Verlauf');
      expect(find.byType(Zeitstrahl), findsOneWidget);
      expect(find.text('Datenblatt erhalten'), findsOneWidget);
      await tester.tap(find.byTooltip('Liste'));
      await tester.pump();
      expect(find.text('passt so'), findsOneWidget);
    });
  });

  group('Fließdiagramme', () {
    final zeit = DateTime(2026, 10, 16);
    Fliessdiagramm fd(int i) => Fliessdiagramm(
          id: 'FD_${i.toString().padLeft(3, '0')}',
          bezeichnung: 'Testware $i',
          sortierung: i,
          createdAt: zeit,
          updatedAt: zeit,
        );
    Future<void> zeige(
      WidgetTester tester, {
      List<Fliessdiagramm>? liste,
      ThemeData? theme,
      List<String> altePdfs = const [],
    }) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fliessdiagrammeProvider.overrideWith(
              (ref) => Stream.value(
                liste ?? [for (var i = 1; i <= 10; i++) fd(i)],
              ),
            ),
            fliessdiagrammAltePdfsProvider.overrideWith(
              (ref) => Stream.value(altePdfs),
            ),
          ],
          child: MaterialApp(
            theme: theme ?? AppTheme.light(),
            home: const Scaffold(body: FliessdiagrammeDialog()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('nur die Liste — ohne PDFs; Menü zum Ordnen', (tester) async {
      await zeige(tester);
      expect(find.text('FD_001'), findsOneWidget);
      expect(find.textContaining('pflegt die Qualitätssicherung'), findsOneWidget);
      expect(find.textContaining('PDF'), findsNothing);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);

      await tester.tap(find.byTooltip('Mehr zu FD_001'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Nach oben'), findsNothing);
      expect(find.text('Nach unten'), findsOneWidget);
      expect(find.text('Löschen'), findsOneWidget);
    });

    testWidgets('PDFs aus einer früheren Version lassen sich entfernen',
        (tester) async {
      await zeige(
        tester,
        altePdfs: const ['fliessdiagramm:FD_001:2026-07-31'],
      );
      expect(find.textContaining('ein PDF von Fließdiagrammen'), findsOneWidget);
      expect(find.text('Entfernen'), findsOneWidget);
    });

    testWidgets('ab neun Fließdiagrammen eine Suche', (tester) async {
      await zeige(tester, theme: AppTheme.dark());
      final suche = find.byKey(const ValueKey('fd-suche'));
      expect(suche, findsOneWidget);
      expect(find.text('Kennung oder Bezeichnung suchen'), findsOneWidget);
      await tester.enterText(suche, 'testware 10');
      await tester.pump();
      expect(find.text('FD_010'), findsOneWidget);
      expect(find.text('FD_001'), findsNothing);

      await tester.enterText(suche, 'gibt es nicht');
      await tester.pump();
      expect(find.text('Nichts gefunden.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leer: Liste einfügen', (tester) async {
      await zeige(tester, liste: const []);
      expect(find.textContaining('Noch keine Fließdiagramme'), findsOneWidget);
      expect(find.byKey(const ValueKey('fd-suche')), findsNothing);
      await tester.tap(find.text('Liste einfügen'));
      await tester.pump();
      expect(find.byKey(const ValueKey('fd-liste')), findsOneWidget);
      expect(find.text('Übernehmen'), findsOneWidget);
    });
  });
}

/// Hält fest, was zurückgestellt wird — ohne Datenbank.
class _Zurueckstellen implements ProjektRepository {
  final aufrufe = <String>[];

  @override
  Future<void> checklisteZurueckstellen(
    String id, {
    required String schluessel,
    required bool zurueck,
  }) async =>
      aufrufe.add('$id $schluessel $zurueck');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Keine Sicherung im Test.
class _OhneSicherung implements AutoBackupTrigger {
  @override
  void fireDebounced({String reason = 'Daten-Änderung'}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
