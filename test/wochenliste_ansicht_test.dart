import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/features/planung/wochenliste.dart';
import 'package:produktion_planer/features/planung/wochenliste_ansicht.dart';
import 'package:produktion_planer/features/whiteboard/produktions_mengen.dart'
    show Verhaeltnis, VerhaeltnisQuelle;

/// Eine Datenquelle ohne Datenbank: merkt sich, was gespeichert und
/// gelöscht wird. Alle Artikel erfunden.
class _Quelle implements WochenlisteQuelle {
  final zeilen = <WochenZeile>[];
  final gespeichert = <({
    String? id,
    String productId,
    DateTime? tag,
    MengenFeld feld,
    double kg,
    double fertig,
  })>[];
  final geloescht = <String>[];

  @override
  Future<List<WochenArtikel>> artikel() async => const [
        WochenArtikel(id: 'p1', nummer: '9101', bezeichnung: 'Testbraten'),
        WochenArtikel(id: 'p2', nummer: '9102', bezeichnung: 'Testwurst'),
      ];

  @override
  Future<List<WochenZeile>> lade() async => [...zeilen];

  @override
  Future<String> speichere({
    String? bedarfId,
    required String productId,
    required DateTime? wunschtag,
    required MengenFeld feld,
    required double kg,
    required double fertigKg,
  }) async {
    gespeichert.add(
      (
        id: bedarfId,
        productId: productId,
        tag: wunschtag,
        feld: feld,
        kg: kg,
        fertig: fertigKg,
      ),
    );
    return bedarfId ?? 'neu-${gespeichert.length}';
  }

  @override
  Future<void> loesche(String bedarfId) async => geloescht.add(bedarfId);

  @override
  Future<ArtikelVerhaeltnisse> verhaeltnisse(String productId) async =>
      productId == 'p1'
          ? const ArtikelVerhaeltnisse(
              ausbeute: Verhaeltnis(
                0.8,
                VerhaeltnisQuelle.produktionen,
                anzahl: 3,
              ),
              fleischanteil: Verhaeltnis(
                0.7,
                VerhaeltnisQuelle.produktionen,
                anzahl: 3,
              ),
            )
          : const ArtikelVerhaeltnisse();

  @override
  Future<ZeilenDauer> dauer(String productId, double fertigKg) async =>
      ZeilenDauer({
        Abteilung.bratstrasse: fertigKg * 0.75,
        Abteilung.verpackung: 30,
      });

  @override
  Future<double> tageskapazitaet() async => 600;
}

void main() {
  final mittwoch = DateTime(2026, 10, 7);
  final tage = [
    for (var d = 5; d <= 9; d++) DateTime(2026, 10, d),
  ];

  late _Quelle quelle;
  late int vorschlaege;

  setUp(() {
    quelle = _Quelle();
    vorschlaege = 0;
  });

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [wochenlisteQuelleProvider.overrideWithValue(quelle)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              body: WochenlisteAnsicht(
                tage: tage,
                onVorschlag: () async => vorschlaege++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String feld(WidgetTester tester, String name, int zeile) => tester
      .widget<TextField>(find.byKey(ValueKey('wochenliste-$name-$zeile')))
      .controller!
      .text;

  Finder artikelFeld(int zeile) => find.descendant(
        of: find.byKey(ValueKey('wochenliste-artikel-$zeile')),
        matching: find.byType(TextField),
      );

  WochenZeile braten() => WochenZeile(
        bedarfId: 'b1',
        productId: 'p1',
        artikelnummer: '9101',
        bezeichnung: 'Testbraten',
        wunschtag: mittwoch,
        feld: MengenFeld.roh,
        kg: 270,
        fertigKg: 216,
      );

  testWidgets('gespeicherte Zeile: eingetragen, gerechnet, Dauer, Summe',
      (tester) async {
    quelle.zeilen.add(braten());
    await zeige(tester);

    expect(feld(tester, 'roh', 0), '270');
    expect(feld(tester, 'fertig', 0), '216');
    expect(feld(tester, 'fleisch', 0), '189');
    expect(find.text('Mi 07.10.'), findsOneWidget);
    // 216 kg Fertigware × 0,75 = 162 min in der Bratstraße.
    expect(find.text('B 2:42 · VP 0:30'), findsOneWidget);
    expect(find.text('Bratstraße 2:42 h · ≈ 0,3 Tage'), findsOneWidget);
    // Darunter wartet eine leere Zeile.
    expect(find.byKey(const ValueKey('wochenliste-artikel-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('wochenliste-weg-1')), findsNothing);
  });

  testWidgets('ein anderes Feld eintragen rechnet um und speichert',
      (tester) async {
    quelle.zeilen.add(braten());
    await zeige(tester);

    await tester.enterText(
      find.byKey(const ValueKey('wochenliste-fleisch-0')),
      '140',
    );
    await tester.pump();
    expect(feld(tester, 'roh', 0), '200');
    expect(feld(tester, 'fertig', 0), '160');
    expect(quelle.gespeichert, isEmpty);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    final s = quelle.gespeichert.single;
    expect(s.id, 'b1');
    expect(s.feld, MengenFeld.fleisch);
    expect((s.kg, s.fertig), (140.0, 160.0));
    expect(s.tag, mittwoch);
  });

  testWidgets('neue Zeile: Artikel suchen, Menge rechnen lassen',
      (tester) async {
    await zeige(tester);

    await tester.enterText(artikelFeld(0), 'wurst');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Testwurst'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wochenliste-artikel-1')), findsOneWidget);

    // Ohne Ausbeute lässt sich Rohware nicht umrechnen — die Zeile sagt es.
    await tester.enterText(
      find.byKey(const ValueKey('wochenliste-roh-0')),
      '100',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ausbeute unbekannt'), findsOneWidget);
    expect(quelle.gespeichert, isEmpty);

    // Fertigware geht immer, auch als kleine Rechnung.
    await tester.enterText(
      find.byKey(const ValueKey('wochenliste-fertig-0')),
      '2*25',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    final s = quelle.gespeichert.single;
    expect((s.id, s.productId, s.fertig), (null, 'p2', 50.0));
    expect(s.tag, isNull);
  });

  testWidgets('Wunschtag wählen, Zeile löschen, Vorschlag rechnen',
      (tester) async {
    quelle.zeilen.add(braten());
    await zeige(tester);

    await tester.tap(find.byKey(const ValueKey('wochenliste-wunsch-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fr 09.10.').last);
    await tester.pumpAndSettle();
    expect(quelle.gespeichert.single.tag, DateTime(2026, 10, 9));

    await tester.tap(find.byKey(const ValueKey('wochenliste-vorschlag')));
    await tester.pumpAndSettle();
    expect(vorschlaege, 1);

    await tester.tap(find.byKey(const ValueKey('wochenliste-weg-0')));
    await tester.pumpAndSettle();
    expect(quelle.geloescht, ['b1']);
    // Übrig ist nur die leere Zeile zum Weiterschreiben.
    expect(find.byKey(const ValueKey('wochenliste-weg-0')), findsNothing);
    expect(find.byKey(const ValueKey('wochenliste-artikel-1')), findsNothing);
  });
}
