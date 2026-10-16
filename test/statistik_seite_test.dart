import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/features/board/board_providers.dart';
import 'package:produktion_planer/features/statistik/statistik_daten.dart';
import 'package:produktion_planer/features/statistik/statistik_diagramme.dart';
import 'package:produktion_planer/features/statistik/statistik_screen.dart';

/// Tests für die Statistik-Seite mit erfundenen Daten: Alle Bereiche
/// erscheinen, nichts läuft über — breit und schmal, hell und dunkel —,
/// ein Tipp auf eine Abteilung zeigt ihre Anlagen, und ohne Daten stehen
/// Hinweise statt Diagrammen da.
///
/// Ein Überlauf (gelb-schwarzer Streifen) meldet Flutter als Fehler; der
/// Test schlägt dann von selbst fehl.
void main() {
  final spanne = StatistikSpanne.fuer(
    StatistikZeitraum.quartal,
    DateTime(2026, 10, 16),
  );

  ErfassteProduktion produktion(
    String id,
    DateTime datum, {
    required double roh,
    double? fertig,
  }) {
    final verlust = roh > 0 && fertig != null ? 1 - fertig / roh : null;
    return ErfassteProduktion(
      productId: id,
      datum: datum,
      kgRohware: roh,
      kgFertigware: fertig,
      verlust:
          verlust != null && verlust > 0 && verlust < 1 ? verlust : null,
      ausbeuteAngegeben: verlust != null,
    );
  }

  StatistikDaten beispiel() {
    const zerlegung = BoardSpur(
      abteilung: Abteilung.zerlegung,
      kapazitaetMinuten: 600,
    );
    const wurstkueche = BoardSpur(
      abteilung: Abteilung.wurstkueche,
      kapazitaetMinuten: 600,
    );
    const brat = BoardSpur(
      abteilung: Abteilung.bratstrasse,
      kapazitaetMinuten: 480,
    );
    const anlageA = BoardSpur(
      abteilung: Abteilung.verpackung,
      maschineId: 'm1',
      maschineName: 'Anlage A',
      kapazitaetMinuten: 480,
    );
    const anlageB = BoardSpur(
      abteilung: Abteilung.verpackung,
      maschineId: 'm2',
      maschineName: 'Anlage B mit einem sehr langen Namen für die Zeile',
      kapazitaetMinuten: 480,
    );
    const sammel = BoardSpur(
      abteilung: Abteilung.verpackung,
      kapazitaetMinuten: 600,
    );

    final belegung = <SpurTagBelegung>[];
    final produktionen = <ErfassteProduktion>[];
    for (var woche = 0; woche < spanne.abschnitte.length; woche++) {
      final montag = spanne.abschnitte[woche];
      for (var t = 0; t < 5; t++) {
        final tag = DateTime(montag.year, montag.month, montag.day + t);
        // Ein Feiertag: nirgends etwas geplant.
        final frei = woche == 3 && t == 0;
        double minuten(double basis) =>
            frei ? 0 : basis + (woche * 7 + t * 13) % 90;
        belegung.addAll([
          SpurTagBelegung(
            spur: zerlegung,
            tag: tag,
            produktionsMinuten: minuten(380),
            zusatzMinuten: frei ? const {} : const {'reinigen': 30},
          ),
          SpurTagBelegung(
            spur: wurstkueche,
            tag: tag,
            produktionsMinuten: minuten(250),
          ),
          SpurTagBelegung(
            spur: brat,
            tag: tag,
            produktionsMinuten: minuten(420),
            zusatzMinuten: frei ? const {} : {'ruesten': 20.0 + t * 5},
          ),
          SpurTagBelegung(
            spur: anlageA,
            tag: tag,
            produktionsMinuten: minuten(200),
          ),
          SpurTagBelegung(
            spur: anlageB,
            tag: tag,
            produktionsMinuten: minuten(100),
            zusatzMinuten: t == 4 ? const {'sonstiges': 15} : const {},
          ),
          SpurTagBelegung(
            spur: sammel,
            tag: tag,
            produktionsMinuten: t == 2 ? minuten(60) : 0,
          ),
        ]);
      }

      final roh = 300.0 + woche * 10;
      produktionen.add(
        produktion(
          'p1',
          montag,
          roh: roh,
          fertig: roh * (0.70 + (woche % 4) * 0.03),
        ),
      );
      if (woche.isEven) {
        produktionen.add(
          produktion(
            'p2',
            DateTime(montag.year, montag.month, montag.day + 1),
            roh: 200,
            fertig: 170.0 - woche,
          ),
        );
      }
      if (woche % 3 == 2) {
        produktionen.add(
          produktion(
            'p3',
            DateTime(montag.year, montag.month, montag.day + 2),
            roh: 150,
            fertig: 140,
          ),
        );
      }
    }
    produktionen.addAll([
      produktion('p4', spanne.abschnitte[4], roh: 80),
      // Mehr heraus als hinein: zählt nicht.
      produktion('p1', spanne.abschnitte[6], roh: 100, fertig: 104),
    ]);

    return StatistikDaten(
      spanne: spanne,
      belegung: belegung,
      produktionen: produktionen,
      artikel: const {
        'p1': StatistikArtikel(
          id: 'p1',
          artikelnummer: '5001',
          bezeichnung: 'Testfrikadelle',
          produktgruppe: 'bratstrasse_natur',
          abteilungen: {'zerlegung', 'bratstrasse', 'verpackung'},
        ),
        'p2': StatistikArtikel(
          id: 'p2',
          artikelnummer: '5002',
          bezeichnung: 'Testartikel mit einem sehr langen Namen, der in '
              'keine Zeile passt und gekürzt werden muss',
          produktgruppe: 'bruehwurst',
          abteilungen: {'wurstkueche', 'verpackung'},
        ),
        'p3': StatistikArtikel(
          id: 'p3',
          artikelnummer: '5003',
          bezeichnung: 'Testschinken',
          produktgruppe: 'kochpoekelware',
          abteilungen: {'zerlegung', 'wurstkueche'},
        ),
        'p4': StatistikArtikel(
          id: 'p4',
          artikelnummer: '5004',
          bezeichnung: 'Testbraten',
          abteilungen: {'zerlegung'},
        ),
      },
    );
  }

  Future<void> zeige(
    WidgetTester tester,
    StatistikDaten daten, {
    required Size groesse,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statistikProvider.overrideWith((ref, zeitraum) => daten),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: const StatistikScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Ein Name in einer Tabellenzeile der Seite.
  Finder zeile(String name) => find.descendant(
        of: find.byType(BalkenZeile),
        matching: find.text(name),
      );

  testWidgets('breit und hell: alle vier Bereiche mit Diagrammen',
      (tester) async {
    await zeige(tester, beispiel(), groesse: const Size(1400, 2800));

    expect(find.textContaining('Auslastung und Engpässe'), findsOneWidget);
    expect(find.textContaining('Wohin die Zeit geht'), findsOneWidget);
    expect(find.textContaining('Ausbeute und Verlust'), findsOneWidget);
    expect(find.textContaining('Produktmix'), findsOneWidget);

    expect(zeile('Bratstraße'), findsWidgets);
    expect(zeile('Verpackung'), findsOneWidget);
    expect(find.text('Je Abteilung · Ø pro Woche'), findsOneWidget);
    expect(find.text('Größte Schwankung je Artikel'), findsOneWidget);
    expect(find.text('Nach Produktgruppe'), findsOneWidget);
    expect(find.byType(StatistikKreis), findsNWidgets(2));
    expect(find.byType(StatistikSaeulen), findsNWidgets(2));
  });

  testWidgets('ein Tipp auf eine Abteilung zeigt ihre Anlagen',
      (tester) async {
    await zeige(tester, beispiel(), groesse: const Size(1400, 2800));

    await tester.tap(zeile('Verpackung'));
    await tester.pumpAndSettle();

    expect(find.text('Verpackung je Anlage · Ø pro Woche'), findsOneWidget);
    expect(zeile('Anlage A'), findsWidgets);
    expect(zeile('Ohne Anlage'), findsWidgets);
    expect(zeile('Zerlegung'), findsNothing);
  });

  testWidgets('schmal und dunkel: kein Überlauf, Zeitraum umschaltbar',
      (tester) async {
    await zeige(
      tester,
      beispiel(),
      groesse: const Size(900, 3200),
      theme: AppTheme.dark(),
    );
    expect(find.textContaining('Produktmix'), findsOneWidget);

    await tester.tap(find.text('4 Wochen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Auslastung und Engpässe'), findsOneWidget);
  });

  testWidgets('ohne Daten: Hinweise statt Diagrammen', (tester) async {
    await zeige(
      tester,
      StatistikDaten(
        spanne: spanne,
        belegung: const [],
        produktionen: const [],
        artikel: const {},
      ),
      groesse: const Size(1200, 1400),
    );

    expect(find.text('Im Zeitraum ist nichts geplant.'), findsNWidgets(2));
    expect(
      find.textContaining('Im Zeitraum sind keine Produktionen erfasst.'),
      findsOneWidget,
    );
    expect(
      find.text('Im Zeitraum sind keine Produktionen mit Rohware erfasst.'),
      findsOneWidget,
    );
    expect(find.byType(StatistikKreis), findsNothing);
    expect(find.byType(StatistikSaeulen), findsNothing);
  });
}
