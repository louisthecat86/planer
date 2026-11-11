import 'package:erfassung/artikel_seite.dart';
import 'package:erfassung/erfassen_seite.dart';
import 'package:erfassung/modell.dart';
import 'package:erfassung/produktionen_seite.dart';
import 'package:erfassung/stand.dart';
import 'package:erfassung/start_seite.dart';
import 'package:erfassung/stil.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'beispiel.dart';

/// Die Seiten der App auf einem kleinen Handy, hell und dunkel: Nichts
/// läuft über, und eine Produktion lässt sich erfassen.
///
/// Ein Überlauf (gelb-schwarzer Streifen) meldet Flutter als Fehler; der
/// Test schlägt dann von selbst fehl.
void main() {
  ErfassungsModell modell({bool mitPaket = true}) => ErfassungsModell(
        stand: Erfassungsstand(kuerzel: 'AB')
          ..paket = mitPaket ? beispielPaket() : null,
      );

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
      // Wie an der Anlage: Platte 1 rechts, oben über unten, und die
      // zweite Zeile (ab Platte 6) unter der ersten.
      Offset platte(String name) =>
          tester.getCenter(find.byKey(ValueKey('platte-$name')));
      final oben1 = platte('Platte Oben 1');
      final oben6 = platte('Platte Oben 6');
      expect(oben1.dx, greaterThan(platte('Platte Oben 2').dx));
      expect(oben1.dy, platte('Platte Oben 5').dy);
      expect(oben6.dy, greaterThan(oben1.dy));
      expect(oben6.dx, oben1.dx);
      expect(platte('Platte Unten 1').dy, greaterThan(oben6.dy));
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
}
