import 'package:erfassung/artikel_seite.dart';
import 'package:erfassung/erfassen_seite.dart';
import 'package:erfassung/modell.dart';
import 'package:erfassung/heute_seite.dart';
import 'package:erfassung/stand.dart';
import 'package:erfassung/start_seite.dart';
import 'package:erfassung/stil.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'beispiel.dart';

/// Die Seiten der App auf einem kleinen Handy, hell und dunkel: Nichts
/// läuft über, eine Produktion lässt sich erfassen, und die Fotos stehen,
/// wo man sie sucht. (Die Kamera selbst und die Bilddateien prüft
/// modell_test.dart — hier hat das Modell weder Kamera noch Ordner.)
///
/// Ein Überlauf (gelb-schwarzer Streifen) meldet Flutter als Fehler; der
/// Test schlägt dann von selbst fehl.
void main() {
  ErfassungsModell modell({bool mitPaket = true}) => ErfassungsModell(
        stand: Erfassungsstand(kuerzel: 'AB')
          ..paket = mitPaket ? beispielPaket() : null,
      );

  /// Ein Modell mit einem Foto aus der Produktion und einem Musterfoto.
  ErfassungsModell mitFotos() {
    final m = modell();
    final s = m.stand;
    s
      ..fotoHinzu(
        s.fotoAnlegen(
          id: 'f-1',
          jetzt: DateTime(2026, 11, 10, 9, 30),
          artikelId: 'a1',
          artikel: 'Grillwurst fein mit einem recht langen Namen 5 x 100 g',
          produktionId: 't1',
        ),
        groesse: 300 * 1024,
      )
      ..fotoHinzu(
        s.fotoAnlegen(
          id: 'f-2',
          jetzt: DateTime(2026, 11, 10, 11, 5),
          bezeichnung: 'Pfeffer grob, zweiter Versuch mit langem Namen',
        ),
        groesse: 212 * 1024,
      );
    return m;
  }

  Future<void> zeige(
    WidgetTester tester,
    Widget seite, {
    bool dunkel = false,
    Size groesse = const Size(360, 720),
  }) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: dunkel ? AppStil.dunkel() : AppStil.hell(),
        home: seite,
      ),
    );
    await tester.pump();
  }

  for (final dunkel in const [false, true]) {
    final art = dunkel ? 'dunkel' : 'hell';

    testWidgets('Start ohne und mit Paket ($art)', (tester) async {
      await zeige(
        tester,
        StartSeite(modell: modell(mitPaket: false)),
        dunkel: dunkel,
      );
      expect(find.text('Per QR-Code empfangen'), findsOneWidget);
      expect(find.text('Datei öffnen'), findsOneWidget);

      final m = modell();
      await zeige(tester, StartSeite(modell: m), dunkel: dunkel);
      // Titel oben und Bereich unten.
      expect(find.text('Heute'), findsNWidgets(2));
      expect(find.text('Anlagen'), findsOneWidget);
      expect(find.text('Fotos'), findsOneWidget);
      expect(find.byKey(const ValueKey('an-pc')), findsOneWidget);
      // Beide geplanten Produktionen liegen in der Vergangenheit: offen.
      expect(find.byKey(const ValueKey('start-t1')), findsOneWidget);
      expect(find.byKey(const ValueKey('start-t2')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('bereich-anlagen')));
      await tester.pumpAndSettle();
      expect(find.text('2 Artikel'), findsOneWidget);
      expect(find.text('ALLE ARTIKEL'), findsOneWidget);
      expect(find.text('Kochschinken'), findsWidgets);
    });

    testWidgets('Fotos: Bereich, Raster und großes Bild ($art)',
        (tester) async {
      final m = mitFotos();
      await zeige(tester, StartSeite(modell: m), dunkel: dunkel);
      // Fotos zählen als Erfasstes — „An PC" zählt sie.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('an-pc')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('bereich-fotos')));
      await tester.pumpAndSettle();
      expect(find.text('2 Fotos · 512 KB'), findsOneWidget);
      expect(find.text('Musterfoto aufnehmen'), findsOneWidget);
      expect(
        find.text('Pfeffer grob, zweiter Versuch mit langem Namen'),
        findsOneWidget,
      );
      expect(find.text('MUSTERFOTOS'), findsOneWidget);
      expect(find.text('AUS DER PRODUKTION'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('fotozeile-f-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('foto-loeschen')), findsOneWidget);
      expect(find.textContaining('10.11.2026, 09:30 Uhr'), findsOneWidget);

      // Löschen fragt nach — und nimmt das Foto dann aus dem Stand.
      await tester.tap(find.byKey(const ValueKey('foto-loeschen')));
      await tester.pumpAndSettle();
      expect(find.text('Foto löschen?'), findsOneWidget);
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      expect(m.stand.fotos.keys, ['f-2']);
      expect(find.byKey(const ValueKey('fotozeile-f-1')), findsNothing);
      expect(find.byKey(const ValueKey('fotozeile-f-2')), findsOneWidget);
    });

    testWidgets('Heute: läuft, offen, morgen eingeklappt ($art)',
        (tester) async {
      final m = modell();
      m.stand.produktionStarten(
        produktionId: 't1',
        artikelId: 'a1',
        artikel: 'Grillwurst',
        jetzt: DateTime(2026, 11, 10, 6, 10),
      );
      await zeige(
        tester,
        Scaffold(
          body: HeuteAnsicht(
            modell: m,
            onOhnePlan: () {},
            jetzt: () => DateTime(2026, 11, 10, 9, 16),
          ),
        ),
        dunkel: dunkel,
      );
      expect(find.text('LÄUFT'), findsOneWidget);
      expect(find.byKey(const ValueKey('fertig-t1')), findsOneWidget);
      expect(find.text('seit 06:10 · 3:06 h'), findsOneWidget);
      // 1.250 kg bei Ø 250 kg/h: 5 Stunden.
      expect(find.text('fertig gegen 11:10 · 5:00 h'), findsOneWidget);
      expect(find.text('1.250'), findsOneWidget);
      // t2 ist morgen — eingeklappt.
      expect(find.byKey(const ValueKey('karte-t2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('klappe-morgen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('start-t2')), findsOneWidget);
      expect(find.text('Wurstküche'), findsOneWidget);
    });

    testWidgets('Anlagen und die Kette eines Artikels ($art)', (tester) async {
      final m = modell();
      await zeige(
        tester,
        Scaffold(body: AnlagenAnsicht(modell: m)),
        dunkel: dunkel,
      );
      expect(find.text('Kochschinken'), findsWidgets);

      await zeige(
        tester,
        SchritteSeite(modell: m, artikel: m.stand.paket!.artikelMit('a1')!),
        dunkel: dunkel,
        groesse: const Size(320, 2400),
      );
      expect(find.text('Füller Test'), findsOneWidget);
      expect(find.text('Bratstraße Test'), findsOneWidget);
      expect(find.text('120 g'), findsOneWidget);
      // Der Artikel steht jetzt unter „Zuletzt geöffnet".
      await tester.pump();
      expect(m.stand.zuletzt, ['a1']);
      // Wie an der Anlage: alle Platten einer Reihe in einer Zeile,
      // Platte 1 rechts, oben über unten.
      Offset platte(String name) =>
          tester.getCenter(find.byKey(ValueKey('platte-$name')));
      final oben1 = platte('Platte Oben 1');
      final oben10 = platte('Platte Oben 10');
      expect(oben1.dx, greaterThan(platte('Platte Oben 2').dx));
      expect(platte('Platte Oben 2').dx, greaterThan(oben10.dx));
      expect(oben10.dy, oben1.dy);
      expect(platte('Platte Unten 1').dy, greaterThan(oben1.dy));
      expect(platte('Platte Unten 1').dx, oben1.dx);
    });

    testWidgets('Schritte mit neuer und herausgenommener Maschine ($art)',
        (tester) async {
      final m = modell();
      final artikel = m.stand.paket!.artikelMit('a1')!;
      m.stand
        ..maschineHinzu(
          id: 'n1',
          artikel: artikel,
          maschine: m.stand.paket!.maschineMit('m-kutter')!,
          nachSchrittId: 's1',
          jetzt: DateTime(2026, 11, 10, 9),
        )
        ..schrittEntfernen(
          artikel: artikel,
          schritt: artikel.schrittMit('s1')!,
          jetzt: DateTime(2026, 11, 10, 9),
        );
      await zeige(
        tester,
        SchritteSeite(modell: m, artikel: artikel),
        dunkel: dunkel,
        groesse: const Size(320, 2400),
      );
      expect(find.text('neu'), findsOneWidget);
      expect(find.text('wird entfernt'), findsOneWidget);
      expect(find.text('Behalten'), findsOneWidget);
      // Die Felder des herausgenommenen Füllers stehen nicht mehr da.
      expect(find.text('120 g'), findsNothing);
      expect(find.text('Messerdrehzahl'), findsOneWidget);

      await zeige(
        tester,
        MaschineWaehlenSeite(maschinen: m.stand.paket!.maschinen),
        dunkel: dunkel,
      );
      expect(find.text('KUTTERABTEILUNG'), findsOneWidget);
      expect(find.text('Kutter Test'), findsOneWidget);
    });
  }

  testWidgets('eine Maschine dazu und eine heraus', (tester) async {
    final m = modell();
    final artikel = m.stand.paket!.artikelMit('a1')!;
    await zeige(
      tester,
      SchritteSeite(modell: m, artikel: artikel),
      groesse: const Size(360, 2400),
    );

    await tester.tap(find.byKey(const ValueKey('maschine-hinzu')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'kutter');
    await tester.pump();
    expect(find.byKey(const ValueKey('maschine-m-fueller')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('maschine-m-kutter')));
    await tester.pumpAndSettle();

    // Vorgeschlagen: ans Ende, denn die Kutterabteilung hat noch keinen
    // Schritt. Gewählt wird hinter den Füller.
    await tester.tap(find.byKey(const ValueKey('platz-s1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('platz-hinzu')));
    await tester.pumpAndSettle();

    final neu = m.stand.neueSchritte.values.single;
    expect((neu.maschineId, neu.nachSchrittId), ('m-kutter', 's1'));
    expect(find.text('Kutter Test'), findsOneWidget);
    expect(find.text('neu'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('schritt-entfernen-s2')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Entfernen'));
    await tester.pumpAndSettle();
    expect(m.stand.entfernteSchritte.keys, ['s2']);
    expect(find.text('wird entfernt'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('schritt-behalten-s2')));
    await tester.pumpAndSettle();
    expect(m.stand.entfernteSchritte, isEmpty);
    expect(find.text('wird entfernt'), findsNothing);
  });

  testWidgets('eine Produktion erfassen', (tester) async {
    final m = modell();
    final plan = m.stand.paket!.produktionen.first;
    await zeige(
      tester,
      const Scaffold(body: SizedBox()),
      groesse: const Size(360, 2000),
    );
    // Wie in der App: die Seite liegt über einer anderen.
    tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute<void>(
            builder: (_) => ErfassenSeite(modell: m, geplant: plan),
          ),
        );
    await tester.pumpAndSettle();

    // Ohne Rohware geht es nicht.
    await tester.tap(find.text('Produktion erfassen'));
    await tester.pump();
    expect(find.text('Bitte die Rohware (kg) eintragen.'), findsOneWidget);
    expect(m.stand.produktionen, isEmpty);

    final felder = find.byType(TextField);
    await tester.enterText(felder.at(0), '1260,5');
    await tester.enterText(felder.at(2), '1008,4');
    await tester.enterText(felder.at(3), '600');
    await tester.enterText(felder.at(4), '13:30');
    // Ende an der Verpackung — zählt nicht für die Leistung.
    await tester.enterText(felder.at(5), '14:15');
    await tester.pump();
    expect(find.text('Verlust'), findsOneWidget);
    expect(find.text('20,0 %'), findsOneWidget);
    expect(find.text('Bis VPK'), findsOneWidget);
    expect(find.text('8:15 h'), findsOneWidget);
    expect(find.text('7:30 h'), findsOneWidget);
    await tester.tap(find.text('Produktion erfassen'));
    // Die Meldung am unteren Rand ablaufen lassen.
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    final e = m.stand.produktionen['t1']!;
    expect(
      (e.rohKg, e.fertigKg, e.start, e.ende, e.endeVpk),
      (1260.5, 1008.4, '06:00', '13:30', '14:15'),
    );
    expect(e.kuerzel, 'AB');
    expect(m.stand.offen.single.id, 't2');
  });

  testWidgets('zwischenspeichern, später weitermachen und erfassen',
      (tester) async {
    final m = modell();
    final plan = m.stand.paket!.produktionen.first;
    await zeige(
      tester,
      const Scaffold(body: SizedBox()),
      groesse: const Size(360, 2000),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    void oeffnen() => navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => ErfassenSeite(modell: m, geplant: plan),
          ),
        );

    // Vor der Produktion: Rohware und Start.
    oeffnen();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '1260,5');
    await tester.enterText(find.byType(TextField).at(3), '0610');
    await tester.pump();
    await tester.tap(find.text('Zwischenspeichern'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    // Nichts erfasst — aber alles festgehalten, so wie getippt.
    expect(m.stand.produktionen, isEmpty);
    expect(m.stand.offen, hasLength(2));
    final entwurf = m.stand.entwuerfe['t1']!;
    expect(
      (entwurf.roh, entwurf.start, entwurf.fertig),
      ('1260,5', '0610', ''),
    );

    // Nach der Produktion: Die Eingaben stehen wieder da.
    oeffnen();
    await tester.pumpAndSettle();
    expect(find.text('1260,5'), findsOneWidget);
    expect(find.text('0610'), findsOneWidget);
    expect(find.textContaining('Begonnen'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(2), '1008,4');
    await tester.enterText(find.byType(TextField).at(4), '13:30');
    await tester.pump();
    await tester.tap(find.text('Produktion erfassen'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    final e = m.stand.produktionen['t1']!;
    expect(
      (e.rohKg, e.fertigKg, e.start, e.ende),
      (1260.5, 1008.4, '06:10', '13:30'),
    );
    expect(m.stand.entwuerfe, isEmpty);
  });

  testWidgets('zurück hält fest, was eingetragen ist', (tester) async {
    final m = modell();
    final plan = m.stand.paket!.produktionen.first;
    await zeige(
      tester,
      const Scaffold(body: SizedBox()),
      groesse: const Size(360, 2000),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator))
      ..push(
        MaterialPageRoute<void>(
          builder: (_) => ErfassenSeite(modell: m, geplant: plan),
        ),
      );
    await tester.pumpAndSettle();

    // Ohne Eingaben bleibt nichts zurück.
    navigator.pop();
    await tester.pumpAndSettle();
    expect(m.stand.entwuerfe, isEmpty);

    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ErfassenSeite(modell: m, geplant: plan),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(3), '6:05');
    await tester.pump();
    navigator.pop();
    await tester.pumpAndSettle();

    expect(m.stand.entwuerfe['t1']!.start, '6:05');
    expect(m.stand.produktionen, isEmpty);
  });

  testWidgets('beim Erfassen: die Fotos des Artikels und der Knopf dafür',
      (tester) async {
    final m = mitFotos();
    final plan = m.stand.paket!.produktionen.first;
    await zeige(
      tester,
      ErfassenSeite(modell: m, geplant: plan),
      groesse: const Size(360, 2000),
    );
    expect(find.text('FOTOS AUS DER PRODUKTION'), findsOneWidget);
    // Nur das Foto dieses Artikels — nicht das Musterfoto.
    expect(find.byKey(const ValueKey('foto-f-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('foto-f-2')), findsNothing);
    expect(find.text('Weiteres Foto aufnehmen'), findsOneWidget);

    // Bei einem Artikel ohne Fotos heißt der Knopf anders. (Mit eigenem
    // Schlüssel — sonst behielte die Seite den Artikel von eben.)
    await zeige(
      tester,
      ErfassenSeite(
        key: const ValueKey('zweite'),
        modell: m,
        geplant: m.stand.paket!.produktionen.last,
      ),
      groesse: const Size(360, 2000),
    );
    expect(find.text('Foto aufnehmen'), findsOneWidget);

    // Ohne Kamera sagt die App, woran es liegt, statt zu schweigen.
    await tester.tap(find.byKey(const ValueKey('foto-produktion')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('nicht erreichbar'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(m.stand.fotos, hasLength(2));
  });

  testWidgets('Foto schon im Programm: Knopf ausgegraut, „Trotzdem" geht',
      (tester) async {
    final m = ErfassungsModell(
      stand: Erfassungsstand(kuerzel: 'AB')
        ..paket = beispielPaket(fotosImPlaner: {'a2': 2}),
    );
    await zeige(
      tester,
      ErfassenSeite(modell: m, geplant: m.stand.paket!.produktionen.last),
      groesse: const Size(360, 2000),
    );
    expect(find.byKey(const ValueKey('foto-im-planer')), findsOneWidget);
    expect(find.textContaining('schon 2 Fotos'), findsOneWidget);
    expect(find.text('Foto schon im Programm'), findsOneWidget);
    final knopf = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('foto-produktion')),
    );
    expect(knopf.onPressed, isNull);
    expect(find.byKey(const ValueKey('foto-trotzdem')), findsOneWidget);

    // Der andere Artikel hat im Programm noch keins.
    await zeige(
      tester,
      ErfassenSeite(
        key: const ValueKey('zweite'),
        modell: m,
        geplant: m.stand.paket!.produktionen.first,
      ),
      groesse: const Size(360, 2000),
    );
    expect(find.byKey(const ValueKey('foto-im-planer')), findsNothing);
    expect(find.text('Foto aufnehmen'), findsOneWidget);
  });

  testWidgets('unter der Rohware: wie lange die Produktion dauert',
      (tester) async {
    final m = modell();
    // Grillwurst: 1.000 kg in 4 Stunden — 250 kg/h.
    await zeige(
      tester,
      ErfassenSeite(modell: m, geplant: m.stand.paket!.produktionen.first),
      groesse: const Size(360, 2200),
    );
    expect(find.byKey(const ValueKey('roh-dauer')), findsOneWidget);
    expect(
      find.textContaining('≈ 5:00 h'),
      findsOneWidget,
      reason: 'geplant sind 1.250 kg',
    );
    expect(find.textContaining('für die geplante Menge'), findsOneWidget);

    final roh = find.byType(TextField).first;
    await tester.enterText(roh, '500');
    await tester.pump();
    expect(find.textContaining('≈ 2:00 h'), findsOneWidget);
    expect(find.textContaining('für die geplante Menge'), findsNothing);

    // Auch während gerechnet wird.
    await tester.enterText(roh, '250×4');
    await tester.pump();
    expect(find.textContaining('≈ 4:00 h'), findsOneWidget);

    // Kochschinken wurde noch nie erfasst.
    await zeige(
      tester,
      ErfassenSeite(
        key: const ValueKey('zweite'),
        modell: m,
        geplant: m.stand.paket!.produktionen.last,
      ),
      groesse: const Size(360, 2200),
    );
    expect(
      find.textContaining('noch keine Erfahrungswerte'),
      findsOneWidget,
    );
  });

  testWidgets('Musterfoto: erst die Bezeichnung, dann die Kamera',
      (tester) async {
    final m = modell();
    await zeige(tester, StartSeite(modell: m), groesse: const Size(360, 1200));
    await tester.tap(find.byKey(const ValueKey('start-musterfoto')));
    await tester.pumpAndSettle();
    expect(find.text('Musterfoto'), findsOneWidget);
    expect(find.byKey(const ValueKey('muster-bezeichnung')), findsOneWidget);

    // Abbrechen: nichts geschieht.
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('muster-bezeichnung')), findsNothing);
    expect(m.stand.fotos, isEmpty);
    expect(m.stand.fotoWartend, isNull);
  });

  testWidgets('Start und Fertig: die Uhrzeit vom Handy, dann erfassen',
      (tester) async {
    final m = modell();
    await zeige(
      tester,
      Scaffold(body: HeuteAnsicht(modell: m, onOhnePlan: () {})),
      groesse: const Size(360, 2000),
    );
    await tester.tap(find.byKey(const ValueKey('start-t1')));
    await tester.pumpAndSettle();
    // Beim Start: wie lange es nach der Erfahrung dauert.
    expect(find.byKey(const ValueKey('prognose')), findsOneWidget);
    expect(find.textContaining('Voraussichtlich 5:00 h'), findsOneWidget);
    expect(find.text('fertig gegen'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final start = m.stand.entwuerfe['t1']!.start;
    expect(start, matches(RegExp(r'^\d\d:\d\d$')));
    expect(m.stand.produktionen, isEmpty);

    await tester.tap(find.byKey(const ValueKey('fertig-t1')));
    await tester.pumpAndSettle();
    // Start steht da, das Ende ist die Uhrzeit des Handys, „Jetzt" gibt
    // es weiter.
    // (Das Ende kann in derselben Minute liegen wie der Start.)
    expect(find.text(start), findsWidgets);
    expect(find.byKey(const ValueKey('jetzt-Start')), findsOneWidget);
    expect(find.byKey(const ValueKey('jetzt-Ende')), findsOneWidget);
    expect(find.byKey(const ValueKey('jetzt-EndeVpk')), findsOneWidget);
    final felder = find.byType(TextField);
    await tester.enterText(felder.at(0), '1250');
    await tester.enterText(felder.at(2), '1000');
    await tester.pump();
    expect(find.text('Ausbeute'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('produktion-erfassen')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    final e = m.stand.produktionen['t1']!;
    expect((e.rohKg, e.fertigKg, e.start), (1250.0, 1000.0, start));
    expect(e.ende, isNotNull);
    expect(e.endeVpk, isNull);
    expect(m.stand.entwuerfe, isEmpty);
    expect(find.byKey(const ValueKey('erfasst-t1')), findsOneWidget);
  });

  testWidgets('An PC: was mitgeht, und der Knopf zum Speichern',
      (tester) async {
    final m = mitFotos();
    await zeige(tester, StartSeite(modell: m), groesse: const Size(360, 900));
    await tester.tap(find.byKey(const ValueKey('an-pc')));
    await tester.pumpAndSettle();
    expect(find.text('An den PC senden'), findsOneWidget);
    expect(find.text('Produktionen'), findsOneWidget);
    expect(find.text('Maschinenwerte'), findsOneWidget);
    final knopf = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('ergebnis-speichern')),
    );
    expect(knopf.onPressed, isNotNull);
    final mail = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('ergebnis-mailen')),
    );
    expect(mail.onPressed, isNotNull);
    expect(find.text('E-Mail-Adresse eintragen'), findsOneWidget);
  });

  testWidgets('„Jetzt" am Start: ohne Erfahrung sagt die App, warum',
      (tester) async {
    final m = modell();
    // Kochschinken wurde noch nie erfasst.
    final plan = m.stand.paket!.produktionen.singleWhere((p) => p.id == 't2');
    await zeige(
      tester,
      ErfassenSeite(modell: m, geplant: plan),
      groesse: const Size(360, 2000),
    );
    expect(find.byKey(const ValueKey('prognose-text')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('jetzt-Start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prognose')), findsOneWidget);
    expect(find.text('fertig gegen'), findsNothing);
    expect(
      find.textContaining('Keine Dauer ermittelbar'),
      findsNWidgets(2),
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // Unter der Zeit bleibt der Satz stehen, bis das Ende eingetragen ist.
    expect(find.byKey(const ValueKey('prognose-text')), findsOneWidget);
  });

  testWidgets('Aufgelegt, dann „Fertig": die Uhrzeit kommt ins Ende VPK',
      (tester) async {
    final m = modell();
    m.stand.entwurfMerken(
      ProduktionsEntwurf(
        produktionId: 't1',
        artikelId: 'a1',
        artikel: 'Grillwurst',
        datum: DateTime(2026, 11, 10),
        geaendertAm: DateTime(2026, 11, 10, 9),
        start: '06:00',
        ende: '09:00',
      ),
    );
    await zeige(
      tester,
      Scaffold(
        body: HeuteAnsicht(
          modell: m,
          onOhnePlan: () {},
          jetzt: () => DateTime(2026, 11, 10, 9, 20),
        ),
      ),
      groesse: const Size(360, 2000),
    );
    expect(find.text('aufgelegt bis 09:00 · VPK läuft'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fertig-t1')));
    await tester.pumpAndSettle();
    final felder = find.byType(TextField);
    String text(int i) =>
        tester.widget<TextField>(felder.at(i)).controller!.text;
    expect(text(3), '06:00');
    expect(text(4), '09:00');
    expect(text(5), matches(RegExp(r'^\d\d:\d\d$')));
  });

  testWidgets('Rechnen in den Mengenfeldern: nur das Ergebnis zählt',
      (tester) async {
    final m = modell();
    final plan = m.stand.paket!.produktionen.first;
    await zeige(
      tester,
      ErfassenSeite(modell: m, geplant: plan),
      groesse: const Size(360, 2200),
    );
    final felder = find.byType(TextField);
    TextEditingController feld(int i) =>
        tester.widget<TextField>(felder.at(i)).controller!;

    // Die Tasten erscheinen, sobald das Feld den Cursor hat.
    expect(find.byKey(const ValueKey('rechnen-roh-mal')), findsNothing);
    await tester.enterText(felder.at(0), '270');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rechnen-roh-mal')));
    await tester.pump();
    expect(feld(0).text, '270×');
    expect(find.text('Rechnung noch nicht vollständig'), findsOneWidget);

    await tester.enterText(felder.at(0), '270×10');
    await tester.pump();
    expect(find.text('= 2.700 kg'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rechnen-roh-gleich')));
    await tester.pump();
    expect(feld(0).text, '2700');

    // Wechselt der Cursor ins nächste Feld, wird ausgerechnet.
    await tester.enterText(felder.at(2), '2700/3*2');
    await tester.pump();
    await tester.enterText(felder.at(1), '1500+700');
    await tester.pump();
    expect(feld(2).text, '1800');
    expect(find.text('= 2.200 kg'), findsOneWidget);

    // Gespeichert wird das Ergebnis — auch aus einem Feld, das noch die
    // Rechnung zeigt.
    await tester.tap(find.byKey(const ValueKey('produktion-erfassen')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    final e = m.stand.produktionen[plan.id]!;
    expect((e.rohKg, e.fleischKg, e.fertigKg), (2700.0, 2200.0, 1800.0));
  });
}
