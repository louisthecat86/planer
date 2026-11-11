import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/artikel_fotos.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/articles/artikel_fotoleiste.dart';

/// Die Fotoleiste eines Artikels mit erfundenen Fotos: leer mit Hinweis,
/// die Kacheln in der Reihenfolge des Dienstes, das Referenzbild markiert,
/// und was sich mit einem Foto tun lässt. Ohne Datenbank — die Fotos
/// kommen über die Provider.
void main() {
  // Ein kleines, echtes JPEG.
  final bild = img.encodeJpg(img.Image(width: 8, height: 6));

  ArtikelFoto foto(
    String id,
    DateTime am, {
    bool referenz = false,
    String? bezeichnung,
    String? kuerzel,
  }) =>
      ArtikelFoto(
        id: id,
        productId: 'a1',
        aufgenommenAm: am,
        bezeichnung: bezeichnung,
        kuerzel: kuerzel,
        istReferenz: referenz,
        groesse: bild.length,
        createdAt: am,
      );

  Future<void> zeige(
    WidgetTester tester,
    List<ArtikelFoto> fotos, {
    Size groesse = const Size(1000, 700),
    ThemeData? theme,
    Uint8List? inhalt,
  }) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artikelFotosProvider.overrideWith((ref, id) => Stream.value(fotos)),
          artikelFotoBildProvider.overrideWith((ref, id) => inhalt),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: ArtikelFotoleiste(productId: 'a1'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder schluessel(String s) => find.byKey(ValueKey(s));

  /// Der Kopf der Leiste mit diesem Zusatz hinter dem Titel.
  Finder kopf(String? untertitel) => find.byWidgetPredicate(
        (w) =>
            w is BereichKopf &&
            w.titel == 'Fotos' &&
            w.untertitel == untertitel,
      );

  testWidgets('ohne Fotos: der Hinweis und der Knopf zum Hinzufügen',
      (tester) async {
    await zeige(tester, const []);
    expect(kopf(null), findsOneWidget);
    expect(find.textContaining('Noch keine Fotos'), findsOneWidget);
    expect(schluessel('fotoleiste-hinzufuegen'), findsOneWidget);
  });

  testWidgets('die Leiste: Referenzbild markiert, Datum und Kürzel darunter',
      (tester) async {
    await zeige(tester, [
      foto(
        'ref',
        DateTime(2026, 11, 2),
        referenz: true,
        bezeichnung: 'Anschnitt',
        kuerzel: 'AB',
      ),
      foto('neu', DateTime(2026, 11, 9)),
    ]);
    expect(kopf('2 Fotos'), findsOneWidget);
    expect(find.text('Referenzbild'), findsOneWidget);
    expect(find.text('02.11.2026 · AB'), findsOneWidget);
    expect(find.text('Anschnitt'), findsOneWidget);
    expect(find.text('09.11.2026'), findsOneWidget);
    // In der Reihenfolge, in der der Dienst sie liefert.
    expect(
      tester.getTopLeft(schluessel('artikel-foto-ref')).dx,
      lessThan(tester.getTopLeft(schluessel('artikel-foto-neu')).dx),
    );
  });

  testWidgets('antippen zeigt das Foto groß — mit dem, was sich tun lässt',
      (tester) async {
    await zeige(
      tester,
      [foto('f1', DateTime(2026, 11, 9), kuerzel: 'AB')],
      inhalt: bild,
    );
    await tester.tap(schluessel('artikel-foto-f1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Foto aus der Produktion'), findsOneWidget);
    expect(find.text('Als Referenzbild'), findsOneWidget);
    expect(schluessel('foto-bemerkung'), findsOneWidget);
    expect(schluessel('foto-loeschen'), findsOneWidget);

    await tester.tap(find.text('Schließen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Als Referenzbild'), findsNothing);
  });

  testWidgets('schmal und dunkel: viele Fotos laufen nicht über',
      (tester) async {
    await zeige(
      tester,
      [
        for (var i = 1; i <= 12; i++)
          foto(
            'f$i',
            DateTime(2026, 11, i),
            referenz: i == 1,
            bezeichnung: 'Eine recht lange Bemerkung zum Foto Nummer $i',
            kuerzel: 'ABCD',
          ),
      ],
      groesse: const Size(420, 700),
      theme: AppTheme.dark(),
    );
    expect(kopf('12 Fotos'), findsOneWidget);
    expect(schluessel('artikel-foto-f1'), findsOneWidget);
  });
}
