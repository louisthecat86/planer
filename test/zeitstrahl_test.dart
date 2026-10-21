import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/zeitstrahl.dart';

/// Tests für den Zeitstrahl im Projektverlauf: Reihenfolge, Platz der
/// Pins, Scrollen zum Neuesten und Antippen. Alle Einträge sind erfunden.
void main() {
  ProjektEintrag eintrag(
    int nr, {
    DateTime? datum,
    DateTime? angelegt,
    EintragArt art = EintragArt.notiz,
    EintragStatus status = EintragStatus.erledigt,
  }) =>
      ProjektEintrag(
        id: 'e$nr',
        projektId: 'p1',
        art: art.schluessel,
        titel: 'Eintrag $nr',
        datum: datum ?? DateTime(2026, 1, 1).add(Duration(days: nr)),
        status: status.schluessel,
        createdAt: angelegt ?? DateTime(2026),
        updatedAt: DateTime(2026),
      );

  group('Ordnung', () {
    test('ältester zuerst, bei gleichem Datum der früher angelegte', () {
      final tag = DateTime(2026, 5, 4);
      final sortiert = zeitlichSortiert([
        eintrag(3),
        eintrag(1, datum: tag, angelegt: DateTime(2026, 5, 4, 12)),
        eintrag(2, datum: tag, angelegt: DateTime(2026, 5, 4, 8)),
      ]);
      expect([for (final e in sortiert) e.id], ['e3', 'e2', 'e1']);
    });

    test('Pins im Takt von vier: oben kurz, unten kurz, oben lang, unten lang',
        () {
      expect(zeitstrahlPlatz(0), (oben: true, lang: false));
      expect(zeitstrahlPlatz(1), (oben: false, lang: false));
      expect(zeitstrahlPlatz(2), (oben: true, lang: true));
      expect(zeitstrahlPlatz(3), (oben: false, lang: true));
      expect(zeitstrahlPlatz(4), zeitstrahlPlatz(0));
    });
  });

  group('Anzeige', () {
    Future<void> zeige(
      WidgetTester tester,
      List<ProjektEintrag> eintraege, {
      double breite = 800,
      void Function(ProjektEintrag)? onTippen,
      ThemeData? theme,
    }) async {
      tester.view.physicalSize = Size(breite, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: Scaffold(
            body: ListView(
              children: [
                Zeitstrahl(eintraege: eintraege, onTippen: onTippen ?? (_) {}),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('jede Art mit Titel und Datum, Meilensteine hervorgehoben',
        (tester) async {
      await zeige(tester, [
        for (final (i, art) in EintragArt.values.indexed)
          eintrag(i + 1, art: art),
      ]);
      for (var i = 1; i <= EintragArt.values.length; i++) {
        expect(find.text('Eintrag $i'), findsOneWidget);
      }
      expect(find.text('02.01.2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('viele Einträge: scrollbar, das Neueste ist zu sehen',
        (tester) async {
      await zeige(tester, [for (var i = 1; i <= 30; i++) eintrag(i)]);
      await tester.pump();
      final neuestes = tester.getCenter(find.text('Eintrag 30'));
      final aeltestes = tester.getCenter(find.text('Eintrag 1'));
      expect(neuestes.dx, inInclusiveRange(0, 800));
      expect(aeltestes.dx, lessThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('offene Einträge sind markiert, Antippen meldet den Eintrag',
        (tester) async {
      ProjektEintrag? getippt;
      await zeige(
        tester,
        [eintrag(1), eintrag(2, status: EintragStatus.offen)],
        onTippen: (e) => getippt = e,
      );
      expect(find.text('offen'), findsOneWidget);
      await tester.tap(find.text('Eintrag 2'));
      await tester.pump();
      expect(getippt?.id, 'e2');
    });

    testWidgets('schmal und dunkel: kein Überlauf', (tester) async {
      await zeige(
        tester,
        [
          for (var i = 1; i <= 6; i++)
            eintrag(i, art: EintragArt.values[i % EintragArt.values.length]),
        ],
        breite: 360,
        theme: AppTheme.dark(),
      );
      expect(find.text('Eintrag 6'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
