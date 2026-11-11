import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_dateien.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';

/// Die Dateien eines Projekts: Ein Bild lässt sich als Produktfoto nehmen
/// — nicht das, das es schon ist, keine PDF, und nichts bei einem
/// Gesamtprojekt. Ohne Datenbank, mit erfundenen Dateien.
void main() {
  EntwicklungsDatei datei(String id, String name, String mime) =>
      EntwicklungsDatei(
        id: id,
        projektId: 'p1',
        name: name,
        mimeTyp: mime,
        groesse: 2048,
        createdAt: DateTime(2026, 11, 10),
      );

  final dateien = [
    datei(
      'muster',
      'Musterfoto Pfeffer grob 2026-11-10_1105.jpg',
      'image/jpeg',
    ),
    datei('aktuell', 'Schnitzel.png', 'image/png'),
    datei('blatt', 'Datenblatt.pdf', 'application/pdf'),
  ];

  Future<void> zeige(
    WidgetTester tester, {
    required bool produktfotoMoeglich,
    Size groesse = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Von vorn — der Schlüssel sorgt für einen frischen Stand.
    await tester.pumpWidget(
      ProviderScope(
        key: ValueKey('scope-$produktfotoMoeglich-$groesse'),
        overrides: [
          projektDateienProvider
              .overrideWith((ref, id) => Stream.value(dateien)),
          projektEintraegeProvider.overrideWith(
            (ref, id) => Stream.value(const <ProjektEintrag>[]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DateienListe(
              zielId: 'p1',
              produktfotoMoeglich: produktfotoMoeglich,
              bildDateiId: 'aktuell',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder knopf(String id) => find.byKey(ValueKey('datei-produktfoto-$id'));

  testWidgets('beim Projekt: nur das Bild, das noch nicht Produktfoto ist',
      (tester) async {
    await zeige(tester, produktfotoMoeglich: true);
    expect(find.text('Datenblatt.pdf'), findsOneWidget);
    expect(knopf('muster'), findsOneWidget);
    expect(knopf('aktuell'), findsNothing);
    expect(knopf('blatt'), findsNothing);
    expect(find.byTooltip('Als Produktfoto'), findsOneWidget);
    expect(find.textContaining('· Produktfoto'), findsOneWidget);
  });

  testWidgets('beim Gesamtprojekt gibt es den Knopf nicht', (tester) async {
    await zeige(tester, produktfotoMoeglich: false);
    expect(find.text('Datenblatt.pdf'), findsOneWidget);
    expect(find.byTooltip('Als Produktfoto'), findsNothing);
  });

  testWidgets('schmal läuft die Zeile mit dem Knopf nicht über',
      (tester) async {
    await zeige(
      tester,
      produktfotoMoeglich: true,
      groesse: const Size(420, 800),
    );
    expect(knopf('muster'), findsOneWidget);
  });
}
