import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/services/erledigt_service.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/articles/artikel_luecken.dart';
import 'package:produktion_planer/features/board/board_providers.dart';
import 'package:produktion_planer/features/statistik/statistik_daten.dart';
import 'package:produktion_planer/features/statistik/statistik_diagramme.dart';
import 'package:produktion_planer/features/statistik/statistik_screen.dart';

/// Tests für die Statistik-Seite mit erfundenen Daten: Alle Bereiche
/// erscheinen, nichts läuft über — breit und schmal, hell und dunkel —,
/// ein Tipp auf eine Abteilung zeigt ihre Anlagen, Lücken und Artikel
/// führen dorthin, wo man sie pflegt, und ohne Daten stehen Hinweise statt
/// Diagrammen da.
///
/// Ein Überlauf (gelb-schwarzer Streifen) meldet Flutter als Fehler; der
/// Test schlägt dann von selbst fehl.
void main() {
  final heute = DateTime(2026, 10, 16);
  final spanne = StatistikSpanne.fuer(StatistikZeitraum.quartal, heute);

  ErfassteProduktion produktion(
    String id,
    DateTime datum, {
    required double roh,
    double? fertig,
    double? minuten,
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
      minuten: minuten,
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
    final karten = <PlanKarte>[];
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

        if (!frei) {
          // Meist erfasst, ab und zu nur abgehakt oder offen.
          final rest = (woche + t) % 5;
          final stand = rest == 0
              ? null
              : (rest == 1 ? Erledigt.abgehakt : Erledigt.erfasst);
          karten.addAll([
            PlanKarte(
              productId: 'p1',
              abteilung: Abteilung.zerlegung,
              datum: tag,
              erledigt: stand,
            ),
            PlanKarte(
              productId: 'p1',
              abteilung: Abteilung.bratstrasse,
              datum: tag,
              erledigt: stand,
            ),
            PlanKarte(
              productId: 'p2',
              abteilung: Abteilung.verpackung,
              datum: tag,
              erledigt: t.isEven ? Erledigt.erfasst : null,
            ),
          ]);
        }
      }

      final roh = 300.0 + woche * 10;
      produktionen.add(
        produktion(
          'p1',
          montag,
          roh: roh,
          fertig: roh * (0.70 + (woche % 4) * 0.03),
          minuten: 75.0 + (woche % 3) * 10,
        ),
      );
      if (woche.isEven) {
        produktionen.add(
          produktion(
            'p2',
            DateTime(montag.year, montag.month, montag.day + 1),
            roh: 200,
            fertig: 170.0 - woche,
            minuten: 40,
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
      stand: heute,
      belegung: belegung,
      karten: karten,
      produktionen: produktionen,
      artikel: const {
        'p1': StatistikArtikel(
          id: 'p1',
          artikelnummer: '5001',
          bezeichnung: 'Testfrikadelle',
          produktgruppe: 'bratstrasse_natur',
          abteilungen: {'zerlegung', 'bratstrasse', 'verpackung'},
          // Gemessen werden gut 250 kg/h — ein Viertel weniger.
          leistungKgH: 340,
        ),
        'p2': StatistikArtikel(
          id: 'p2',
          artikelnummer: '5002',
          bezeichnung: 'Testartikel mit einem sehr langen Namen, der in '
              'keine Zeile passt und gekürzt werden muss',
          produktgruppe: 'bruehwurst',
          abteilungen: {'wurstkueche', 'verpackung'},
          luecken: {ArtikelLuecke.zeitPlatzhalter},
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
          luecken: {
            ArtikelLuecke.ohneProduktgruppe,
            ArtikelLuecke.ohneAusbeute,
          },
        ),
        'p5': StatistikArtikel(
          id: 'p5',
          artikelnummer: '5005',
          bezeichnung: 'Testartikel aus Navision',
          luecken: {
            ArtikelLuecke.nichtEingepflegt,
            ArtikelLuecke.ohneProduktgruppe,
            ArtikelLuecke.ohneSchritte,
            ArtikelLuecke.ohneAusbeute,
          },
        ),
      },
    );
  }

  StatistikDaten leer() => StatistikDaten(
        spanne: spanne,
        stand: heute,
        belegung: const [],
        karten: const [],
        produktionen: const [],
        artikel: const {},
      );

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

  /// Der Kopf des Bereichs mit genau diesem Titel. Nicht über den Text:
  /// Wörter wie „Produktmix" stehen auch in Erklärungen anderer Bereiche.
  Finder bereich(String titel) => find.byWidgetPredicate(
        (w) => w is BereichKopf && w.titel == titel,
      );

  // So hoch, dass die ganze Seite gebaut wird — sonst prüfte der Test die
  // unteren Bereiche nicht.
  const breit = Size(1400, 5000);
  const schmal = Size(900, 8000);

  testWidgets('breit und hell: alle sieben Bereiche mit Diagrammen',
      (tester) async {
    await zeige(tester, beispiel(), groesse: breit);

    for (final titel in const [
      'Auslastung und Engpässe',
      'Wohin die Zeit geht',
      'Planerfüllung',
      'Ausbeute und Verlust',
      'Leistung',
      'Produktmix',
      'Stammdaten-Pflege',
    ]) {
      expect(bereich(titel), findsOneWidget, reason: titel);
    }
    expect(find.text('Die meiste Produktionszeit'), findsOneWidget);

    expect(zeile('Bratstraße'), findsWidgets);
    // Einmal in der Auslastung, einmal in der Planerfüllung.
    expect(zeile('Verpackung'), findsNWidgets(2));
    expect(find.text('Je Abteilung · Ø pro Woche'), findsOneWidget);
    expect(find.text('Größte Schwankung je Artikel'), findsOneWidget);
    expect(find.text('Nach Produktgruppe'), findsOneWidget);
    expect(find.byType(StatistikKreis), findsNWidgets(2));
    // Auslastung, Planerfüllung und Verlust.
    expect(find.byType(StatistikSaeulen), findsNWidgets(3));

    // Die Frikadelle weicht von ihren Leistungsdaten ab.
    expect(
      find.text('Abweichung von den Leistungsdaten · 1 von 1 Artikeln'),
      findsOneWidget,
    );
    expect(find.byType(AbweichungsBalken), findsOneWidget);

    // Jede Lücke eine Zeile.
    for (final l in ArtikelLuecke.values) {
      expect(zeile(l.titel), findsOneWidget, reason: l.titel);
    }
  });

  testWidgets('ein Tipp auf eine Abteilung zeigt ihre Anlagen',
      (tester) async {
    await zeige(tester, beispiel(), groesse: breit);

    // Die erste Zeile „Verpackung" steht in der Auslastung.
    await tester.tap(zeile('Verpackung').first);
    await tester.pumpAndSettle();

    expect(find.text('Verpackung je Anlage · Ø pro Woche'), findsOneWidget);
    expect(zeile('Anlage A'), findsWidgets);
    expect(zeile('Ohne Anlage'), findsWidgets);
    expect(zeile('Zerlegung'), findsNothing);
    // Die Planerfüllung zeigt nur noch die Verpackung.
    expect(zeile('Verpackung'), findsOneWidget);
  });

  testWidgets('schmal und dunkel: kein Überlauf, Zeitraum umschaltbar',
      (tester) async {
    await zeige(
      tester,
      beispiel(),
      groesse: schmal,
      theme: AppTheme.dark(),
    );
    expect(bereich('Produktmix'), findsOneWidget);
    expect(bereich('Stammdaten-Pflege'), findsOneWidget);

    await tester.tap(find.text('4 Wochen'));
    await tester.pumpAndSettle();
    expect(bereich('Auslastung und Engpässe'), findsOneWidget);
  });

  testWidgets('Lücken und Artikel führen dorthin, wo man sie pflegt',
      (tester) async {
    tester.view.physicalSize = breit;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Statt der echten Seiten ein Text mit dem, was ankommt.
    final router = GoRouter(
      initialLocation: '/statistik',
      routes: [
        GoRoute(
          path: '/statistik',
          builder: (context, state) => const StatistikScreen(),
        ),
        GoRoute(
          path: '/articles',
          name: 'articles',
          builder: (context, state) => Text(
            'Artikelliste: ${state.uri.queryParameters['luecke']}',
          ),
        ),
        GoRoute(
          path: '/article/:productId',
          name: 'articleDetail',
          builder: (context, state) => Text(
            'Artikel ${state.pathParameters['productId']}',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    final daten = beispiel();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statistikProvider.overrideWith((ref, zeitraum) => daten),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(zeile('Ohne Ausbeute'));
    await tester.pumpAndSettle();
    expect(find.text('Artikelliste: ohneAusbeute'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(zeile('5004 · Testbraten').first);
    await tester.pumpAndSettle();
    expect(find.text('Artikel p4'), findsOneWidget);
  });

  testWidgets('ohne Daten: Hinweise statt Diagrammen', (tester) async {
    await zeige(tester, leer(), groesse: const Size(1200, 2400));

    expect(find.text('Im Zeitraum ist nichts geplant.'), findsNWidgets(2));
    expect(
      find.text('Im Zeitraum war bis gestern nichts geplant.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Im Zeitraum sind keine Produktionen erfasst.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Im Zeitraum ist keine Produktion mit Rohware'),
      findsOneWidget,
    );
    expect(
      find.text('Im Zeitraum sind keine Produktionen mit Rohware erfasst.'),
      findsOneWidget,
    );
    expect(find.text('Es sind noch keine Artikel angelegt.'), findsOneWidget);
    expect(find.byType(StatistikKreis), findsNothing);
    expect(find.byType(StatistikSaeulen), findsNothing);
  });
}
