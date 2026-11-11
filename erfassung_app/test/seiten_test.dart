import 'package:erfassung/artikel_seite.dart';
import 'package:erfassung/erfassen_seite.dart';
import 'package:erfassung/fotos.dart';
import 'package:erfassung/modell.dart';
import 'package:erfassung/produktionen_seite.dart';
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
      expect(find.text('Paket öffnen'), findsOneWidget);

      final m = modell();
      await zeige(tester, StartSeite(modell: m), dunkel: dunkel);
      expect(find.text('Produktionen'), findsOneWidget);
      expect(find.text('Maschineneinstellungen'), findsOneWidget);
      expect(find.text('2 geplante sind noch offen'), findsOneWidget);
      expect(find.text('Fotos'), findsOneWidget);
      expect(find.text('Musterfoto aufnehmen'), findsOneWidget);
    });

    testWidgets('Fotos: Kachel, Liste und großes Bild ($art)', (tester) async {
      final m = mitFotos();
      await zeige(
        tester,
        StartSeite(modell: m),
        dunkel: dunkel,
        groesse: const Size(360, 1400),
      );
      expect(find.text('2 Fotos · 512 KB'), findsOneWidget);
      // Fotos zählen als Erfasstes — das Ergebnis lässt sich speichern.
      expect(
        find.textContaining('noch in keiner Ergebnis-Datei'),
        findsOneWidget,
      );

      await zeige(tester, FotosSeite(modell: m), dunkel: dunkel);
      expect(find.text('Musterfoto aufnehmen'), findsOneWidget);
      expect(
        find.text('Musterfoto · Pfeffer grob, zweiter Versuch mit langem '
            'Namen'),
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

    testWidgets('Produktionen, Artikel und Schritte ($art)', (tester) async {
      final m = modell();
      await zeige(tester, ProduktionenSeite(modell: m), dunkel: dunkel);
      expect(find.text('Kochschinken'), findsOneWidget);
      expect(find.text('Ohne Plan erfassen'), findsOneWidget);

      await zeige(tester, ArtikelSeite(modell: m), dunkel: dunkel);
      expect(find.text('Kochschinken'), findsOneWidget);

      await zeige(
        tester,
        SchritteSeite(modell: m, artikel: m.stand.paket!.artikelMit('a1')!),
        dunkel: dunkel,
        groesse: const Size(320, 2400),
      );
      expect(find.text('Füller Test'), findsOneWidget);
      expect(find.text('Bratstraße Test'), findsOneWidget);
      expect(find.text('120 g'), findsOneWidget);
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
  }

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
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(find.text('Bitte die Rohware (kg) eintragen.'), findsOneWidget);
    expect(m.stand.produktionen, isEmpty);

    final felder = find.byType(TextField);
    await tester.enterText(felder.at(0), '1260,5');
    await tester.enterText(felder.at(2), '1008,4');
    await tester.enterText(felder.at(3), '600');
    await tester.enterText(felder.at(4), '13:30');
    await tester.pump();
    expect(find.textContaining('Verlust 20'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    // Die Meldung am unteren Rand ablaufen lassen.
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    final e = m.stand.produktionen['t1']!;
    expect(
      (e.rohKg, e.fertigKg, e.start, e.ende),
      (1260.5, 1008.4, '06:00', '13:30'),
    );
    expect(e.kuerzel, 'AB');
    expect(m.stand.offen.single.id, 't2');
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
}
