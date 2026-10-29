import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show LayoutCallback;
import 'package:produktion_planer/core/druck/druck_fenster.dart';
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_optionen.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';

/// Tests für das Druckfenster: Es setzt das Dokument nach jeder Änderung
/// neu, merkt sich beim Drucken die Einstellungen und liest sie beim
/// nächsten Mal. Vorschau, Druckdialog und Speichern sind ersetzt — die
/// gibt es im Test nicht.
void main() {
  /// Ein Auftrag mit zwei Teilen zum Auswählen und einem Schalter. Jede
  /// Wahl, aus der gebaut wird, landet in [gebaut].
  DruckAuftrag auftrag(List<DruckWahl> gebaut) => DruckAuftrag(
        art: 'probe',
        titel: 'Probe drucken',
        untertitel: 'Erfundene Daten',
        optionen: const [
          DruckWahlMehrere(
            schluessel: 'teile',
            titel: 'Teile',
            werte: [DruckWert('a', 'Teil A'), DruckWert('b', 'Teil B')],
            standard: {'a', 'b'},
          ),
          DruckSchalter(
            schluessel: 'lang',
            titel: 'Lange Fassung',
            hinweis: 'Mit vielen Zeilen',
            standard: false,
          ),
        ],
        bauen: (wahl) {
          gebaut.add(wahl);
          final teile = wahl.mehrere('teile');
          if (teile.isEmpty) {
            throw const DruckNichtsGewaehlt('Wähle mindestens einen Teil.');
          }
          final zeilen = wahl.an('lang') ? 150 : 5;
          return DruckDokument(
            dateiname: 'Probe',
            blaetter: [
              for (final t in teile)
                DruckBlatt(
                  bauen: (_) => DruckSeiten(
                    inhalt: (_) => [
                      for (var i = 0; i < zeilen; i++) pw.Text('$t $i'),
                    ],
                  ),
                ),
            ],
          );
        },
      );

  Future<_System> oeffne(
    WidgetTester tester,
    DruckAuftrag auftrag, {
    Object? gemerkt,
    List<bool>? ergebnis,
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final system = _System(gemerkt);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [druckSystemProvider.overrideWithValue(system)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final gedruckt = await druckFensterOeffnen(
                      context,
                      auftrag,
                    );
                    ergebnis?.add(gedruckt);
                  },
                  child: const Text('öffnen'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    await warte(tester);
    return system;
  }

  bool aktiv(WidgetTester tester, String label) => tester
      .widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      )
      .enabled;

  testWidgets('setzt beim Öffnen und zeigt, was herauskommt', (tester) async {
    final gebaut = <DruckWahl>[];
    await oeffne(tester, auftrag(gebaut));

    expect(find.text('Probe drucken'), findsOneWidget);
    expect(find.text('Erfundene Daten'), findsOneWidget);
    expect(gebaut, hasLength(1));
    expect(
      find.text('Vorschau: 2 Blätter · 2 Seiten · A4 hoch · 100 %'),
      findsOneWidget,
    );
    expect(aktiv(tester, 'Drucken …'), isTrue);
    expect(aktiv(tester, 'Als PDF speichern …'), isTrue);
  });

  testWidgets('jede Änderung setzt neu', (tester) async {
    final gebaut = <DruckWahl>[];
    await oeffne(tester, auftrag(gebaut));

    await tester.tap(find.text('Teil B'));
    await warte(tester);
    expect(gebaut.last.mehrere('teile'), {'a'});
    expect(find.textContaining('Vorschau: 1 Seite'), findsOneWidget);

    await tester.tap(find.text('Lange Fassung'));
    await warte(tester);
    expect(gebaut.last.an('lang'), isTrue);
    expect(find.textContaining('Vorschau: 3 Seiten'), findsOneWidget);

    await tippe(tester, 'Alles auf eine Seite');
    await warte(tester);
    expect(gebaut.last.layout.anpassung, DruckAnpassung.eineSeite);
    expect(find.textContaining('Vorschau: 1 Seite · A4 hoch · '), findsOne);
    expect(find.text('Vorschau: 1 Seite · A4 hoch · 100 %'), findsNothing);

    await tippe(tester, 'A3');
    await warte(tester);
    expect(gebaut.last.layout.papier, DruckPapier.a3);
  });

  testWidgets('ohne Auswahl sagt es, was fehlt, und druckt nicht',
      (tester) async {
    final gebaut = <DruckWahl>[];
    await oeffne(tester, auftrag(gebaut));

    await tester.tap(find.text('Keine'));
    await warte(tester);
    expect(find.text('Wähle mindestens einen Teil.'), findsOneWidget);
    expect(aktiv(tester, 'Drucken …'), isFalse);

    await tester.tap(find.text('Alle'));
    await warte(tester);
    expect(aktiv(tester, 'Drucken …'), isTrue);
  });

  testWidgets('Drucken merkt sich die Einstellungen und schließt',
      (tester) async {
    final gebaut = <DruckWahl>[];
    final ergebnis = <bool>[];
    final system = await oeffne(tester, auftrag(gebaut), ergebnis: ergebnis);

    await tippe(tester, 'In Graustufen');
    await warte(tester);
    await tester.tap(find.text('Drucken …'));
    await warte(tester);

    expect(system.gedruckt, hasLength(1));
    expect(system.gedruckt.single.layout.graustufen, isTrue);
    expect(ergebnis, [true]);
    expect(find.text('Probe drucken'), findsNothing);
    final gemerkt = DruckWahl.fromJson(
      system.gemerkt,
      auftrag(gebaut).optionen,
    );
    expect(gemerkt.layout.graustufen, isTrue);
  });

  testWidgets('beim nächsten Mal gilt das Gemerkte, Zurücksetzen holt den '
      'Standard', (tester) async {
    final gebaut = <DruckWahl>[];
    final probe = auftrag(gebaut);
    await oeffne(
      tester,
      probe,
      gemerkt: DruckWahl.standard(probe.optionen)
          .mit('lang', true)
          .mitLayout(const DruckLayout(ausrichtung: DruckAusrichtung.quer))
          .toJson(probe.optionen),
    );
    expect(gebaut.single.an('lang'), isTrue);
    // Die Vorschau und die Zeile unten sagen beide, was herauskommt.
    expect(
      find.text('Vorschau: 2 Blätter · 8 Seiten · A4 quer · 100 %'),
      findsOneWidget,
    );
    expect(find.text('2 Blätter · 8 Seiten · A4 quer · 100 %'), findsOneWidget);

    await tester.tap(find.text('Zurücksetzen'));
    await warte(tester);
    expect(gebaut.last.an('lang'), isFalse);
    expect(gebaut.last.layout, const DruckLayout());
  });

  testWidgets('Abbrechen druckt nichts und merkt nichts', (tester) async {
    final gebaut = <DruckWahl>[];
    final ergebnis = <bool>[];
    final system = await oeffne(tester, auftrag(gebaut), ergebnis: ergebnis);

    await tippe(tester, 'In Graustufen');
    await warte(tester);
    await tester.tap(find.text('Abbrechen'));
    await warte(tester);

    expect(ergebnis, [false]);
    expect(system.gedruckt, isEmpty);
    expect(system.gemerkt, isNull);
  });
}

/// Tippt auf [text] — die Liste links scrollt dafür, wenn nötig.
Future<void> tippe(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump();
  await tester.tap(find.text(text));
}

/// Wartet, bis das Fenster neu gesetzt hat — die Änderung wartet kurz,
/// ob noch eine folgt.
Future<void> warte(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Ersatz für Vorschau, Druckdialog, Speichern und das Gedächtnis.
class _System extends DruckSystem {
  _System(this.gemerkt) : super(null);

  Object? gemerkt;
  final List<DruckErgebnis> gedruckt = [];

  @override
  Future<Object?> laden(String art) async => gemerkt;

  @override
  Future<void> merken(String art, Map<String, Object> json) async {
    gemerkt = jsonDecode(jsonEncode(json));
  }

  @override
  Widget vorschau(
    BuildContext context,
    DruckErgebnis ergebnis,
    LayoutCallback bauen,
    String dateiname,
  ) =>
      Center(child: Text('Vorschau: ${ergebnis.beschreibung}'));

  @override
  Future<bool> drucken(DruckErgebnis ergebnis, String dateiname) async {
    gedruckt.add(ergebnis);
    return true;
  }

  @override
  Future<String?> speichern(DruckErgebnis ergebnis, String dateiname) async =>
      '/ablage/$dateiname.pdf';
}
