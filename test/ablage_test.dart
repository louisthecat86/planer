import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/ablage.dart';
import 'package:produktion_planer/features/entwicklung/mail/eml_lesen.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekte_ansicht.dart';

/// Tests für das Ablegen per Ziehen: Was das Fenster über den Kanal
/// „planer/ablage" meldet, landet in der Zone unter dem Punkt — der
/// innersten, nur auf der obersten Seite. Dazu das Fenster „Neues Projekt
/// aus Mail". Alles erfunden.
void main() {
  const codec = StandardMethodCodec();

  /// Schickt eine Meldung des Fensters und gibt die Antwort der App zurück
  /// — danach ein Bild, außer in echter Zeit ([pumpen] aus).
  Future<Object?> melden(
    WidgetTester tester,
    String methode, [
    Map<String, Object?> argumente = const {},
    bool pumpen = true,
  ]) async {
    Object? antwort;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'planer/ablage',
      codec.encodeMethodCall(MethodCall(methode, argumente)),
      (daten) {
        if (daten != null) antwort = codec.decodeEnvelope(daten);
      },
    );
    if (pumpen) await tester.pump();
    return antwort;
  }

  Future<void> zeige(WidgetTester tester, Widget kind) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: kind),
      ),
    );
  }

  final hinweis = find.byKey(const ValueKey('ablage-zone-hinweis'));

  testWidgets('darüber ziehen: die Zone zeigt, was geschieht', (tester) async {
    await zeige(
      tester,
      AblageZone(
        hinweis: 'Mail loslassen',
        onAbgelegt: (_) async {},
        child: const SizedBox.expand(),
      ),
    );
    expect(hinweis, findsNothing);
    expect(await melden(tester, 'ueber', {'x': 100.0, 'y': 100.0}), isTrue);
    expect(hinweis, findsOneWidget);
    expect(find.text('Mail loslassen'), findsOneWidget);
    expect(await melden(tester, 'weg'), isNull);
    expect(hinweis, findsNothing);
    // Außerhalb des Fensters: keine Zone.
    expect(await melden(tester, 'ueber', {'x': 5000.0, 'y': 10.0}), isFalse);
    expect(hinweis, findsNothing);
  });

  testWidgets('ineinander: die innerste gewinnt; ausgeschaltet nimmt keine',
      (tester) async {
    var aktiv = true;
    late StateSetter neu;
    await zeige(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          neu = setState;
          return AblageZone(
            hinweis: 'außen',
            onAbgelegt: (_) async {},
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                height: 200,
                child: AblageZone(
                  hinweis: 'innen',
                  aktiv: aktiv,
                  onAbgelegt: (_) async {},
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          );
        },
      ),
    );
    await melden(tester, 'ueber', {'x': 50.0, 'y': 50.0});
    expect(find.text('innen'), findsOneWidget);
    expect(find.text('außen'), findsNothing);
    await melden(tester, 'ueber', {'x': 500.0, 'y': 400.0});
    expect(find.text('innen'), findsNothing);
    expect(find.text('außen'), findsOneWidget);
    neu(() => aktiv = false);
    await tester.pump();
    await melden(tester, 'ueber', {'x': 50.0, 'y': 50.0});
    expect(find.text('innen'), findsNothing);
    expect(find.text('außen'), findsOneWidget);
    await melden(tester, 'weg');
  });

  testWidgets('eine verdeckte Seite nimmt nichts an', (tester) async {
    await zeige(
      tester,
      Builder(
        builder: (context) => AblageZone(
          hinweis: 'unten',
          onAbgelegt: (_) async {},
          child: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('oben')),
                ),
              ),
              child: const Text('weiter'),
            ),
          ),
        ),
      ),
    );
    expect(await melden(tester, 'ueber', {'x': 10.0, 'y': 10.0}), isTrue);
    await melden(tester, 'weg');
    await tester.tap(find.text('weiter'));
    await tester.pumpAndSettle();
    expect(await melden(tester, 'ueber', {'x': 10.0, 'y': 10.0}), isFalse);
  });

  testWidgets('loslassen: die Zone bekommt die Dateien', (tester) async {
    final abgelegt = <AbgelegteDatei>[];
    await zeige(
      tester,
      AblageZone(
        hinweis: 'Datei loslassen',
        onAbgelegt: (dateien) async => abgelegt.addAll(dateien),
        child: const SizedBox.expand(),
      ),
    );
    final ordner = await tester.runAsync(
      () => Directory.systemTemp.createTemp('ablage_zone'),
    );
    addTearDown(() => ordner!.delete(recursive: true));
    final datei = File(p.join(ordner!.path, 'Notiz.txt'));
    await tester.runAsync(() => datei.writeAsString('Muster'));

    final antwort = await tester.runAsync(() async {
      final a = await melden(
        tester,
        'abgelegt',
        {
          'x': 10.0,
          'y': 10.0,
          'pfade': [datei.path],
          'virtuell': false,
        },
        false,
      );
      // Lesen braucht echte Zeit.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return a;
    });
    await tester.pump();
    expect(antwort, isTrue);
    expect([for (final d in abgelegt) d.name], ['Notiz.txt']);
    expect(utf8.decode(abgelegt.single.inhalt), 'Muster');
    // Keine Kopie des Fensters: Die Datei bleibt, wo sie ist.
    expect(await tester.runAsync(datei.exists), isTrue);
    expect(hinweis, findsNothing);
  });

  testWidgets('Neues Projekt aus Mail: vorbelegt, mit der Mail',
      (tester) async {
    final roh = Uint8List.fromList(
      utf8.encode(
        'From: Hans Muster <hans@muster-fleisch.de>\r\n'
        'Subject: AW: Anfrage Grillwurst\r\n'
        'Date: Tue, 6 Oct 2026 14:05:00 +0200\r\n'
        '\r\n'
        'Wir suchen eine grobe Grillwurst.\r\n',
      ),
    );
    final mail = emlLesen(roh);
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projekteProvider.overrideWith(
            (ref) => Stream.value(const <EntwicklungsProjekt>[]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: NeuesProjektDialog(
              ausMail: (mail: mail, datei: (name: 'Anfrage.eml', inhalt: roh)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Neues Projekt aus Mail'), findsOneWidget);
    expect(find.text('AW: Anfrage Grillwurst'), findsOneWidget);
    expect(
      find.text('Hans Muster <hans@muster-fleisch.de> · 06.10.2026'),
      findsOneWidget,
    );
    expect(
      find.text('Die Mail kommt als Anfrage in den Verlauf.'),
      findsOneWidget,
    );
    // Vorbelegt: Name ohne „AW:", Kunde aus der Adresse, die Anfrage.
    expect(find.widgetWithText(TextField, 'Anfrage Grillwurst'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Muster-Fleisch'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Wir suchen eine grobe Grillwurst.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
