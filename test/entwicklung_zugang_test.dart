import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/entwicklung.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/entwicklung_sicherung.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/utils/krypto.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_auto_sperre.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_screen.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';

import 'helpers/test_db.dart';

/// Tests für den Zugang zur Produktentwicklung: Passwort festlegen,
/// prüfen, ändern und zurücksetzen, den Datenschlüssel dahinter — und die
/// Sperre auf der Seite.
///
/// Die Tests rechnen mit 1000 statt 200.000 Iterationen; das Verfahren ist
/// dasselbe, nur schneller.
void main() {
  group('Passwort-Regeln', () {
    test('leer und zu kurz taugen nicht', () {
      expect(passwortFehler(''), isNotNull);
      expect(passwortFehler('   '), isNotNull);
      expect(passwortFehler('1234567'), 'Mindestens 8 Zeichen.');
      expect(passwortFehler('12345678'), isNull);
    });

    test('ein unlesbarer Datensatz gilt als nicht gesetzt', () {
      expect(PasswortDatensatz.ausJson('kaputt'), isNull);
      expect(PasswortDatensatz.ausJson('[]'), isNull);
      expect(
        PasswortDatensatz.ausJson(
          '{"iterationen":1000,"salz":"%%%","pruefwert":"AA=="}',
        ),
        isNull,
      );
      expect(
        PasswortDatensatz.ausJson('{"iterationen":0,"salz":"","pruefwert":""}'),
        isNull,
      );
    });
  });

  group('Zugang mit der Datenbank', () {
    late AppDatabase db;
    late DbEntwicklungsSpeicher speicher;
    late EntwicklungZugang zugang;

    setUp(() {
      db = testDatenbank();
      speicher = DbEntwicklungsSpeicher(db);
      zugang = EntwicklungZugang(
        speicher,
        iterationen: 1000,
        imHintergrund: false,
      );
    });

    tearDown(() => db.close());

    Future<String?> datensatzText() =>
        speicher.lesen(kEntwicklungPasswortSchluessel);

    Future<PasswortDatensatz> datensatz() async =>
        PasswortDatensatz.ausJson((await datensatzText())!)!;

    Future<Uint8List?> lokalerSchluessel() async {
      final text = await speicher.lesen(kEntwicklungDatenschluessel);
      return text == null ? null : base64Decode(text);
    }

    /// Packt den Datenschlüssel aus dem Datensatz mit [passwort] aus.
    Future<Uint8List> ausgepackt(String passwort) async {
      final d = await datensatz();
      final grund = grundwertFuer(passwort, d.salz, d.iterationen);
      return entschluesseln(
        verpackungAus(grund),
        d.verpackterSchluessel!,
        zweck: kZweckSchluessel,
      );
    }

    test('ohne Passwort ist nichts gesetzt und nichts stimmt', () async {
      expect(await zugang.passwortGesetzt(), isFalse);
      expect(await zugang.pruefen('geheim123'), isFalse);
      expect(await zugang.oeffnen('geheim123'), isFalse);
    });

    test('festlegen, prüfen und öffnen', () async {
      await zugang.festlegen('geheim123');

      expect(await zugang.passwortGesetzt(), isTrue);
      expect(await zugang.pruefen('geheim123'), isTrue);
      expect(await zugang.pruefen('geheim124'), isFalse);
      expect(await zugang.pruefen(''), isFalse);
      expect(await zugang.oeffnen('geheim124'), isFalse);
      expect(await zugang.oeffnen('geheim123'), isTrue);
    });

    test('gespeichert wird nie das Passwort selbst', () async {
      await zugang.festlegen('geheim123');

      final text = await datensatzText();
      expect(text, isNot(contains('geheim123')));
      final json = jsonDecode(text!) as Map<String, dynamic>;
      expect(json['verfahren'], 'PBKDF2-HMAC-SHA256');
      expect(json['iterationen'], 1000);
      expect(base64Decode(json['salz'] as String).length, 16);
      expect(base64Decode(json['pruefwert'] as String).length, 32);
      expect(json['schluessel'], isA<String>());
    });

    test('festlegen richtet den Datenschlüssel ein, verpackt im Datensatz',
        () async {
      await zugang.festlegen('geheim123');

      final lokal = await lokalerSchluessel();
      expect(lokal, isNotNull);
      expect(lokal!.length, kSchluesselLaenge);
      expect(await ausgepackt('geheim123'), lokal);
    });

    test('jedes Festlegen bekommt ein neues Salz', () async {
      await zugang.festlegen('geheim123');
      final erster = await datensatz();
      await zugang.zuruecksetzen();
      await zugang.festlegen('geheim123');
      final zweiter = await datensatz();

      expect(zweiter.salz, isNot(equals(erster.salz)));
      expect(zweiter.pruefwert, isNot(equals(erster.pruefwert)));
    });

    test('ein zweites Festlegen geht nicht, ein zu kurzes auch nicht',
        () async {
      await expectLater(zugang.festlegen('kurz'), throwsArgumentError);
      expect(await zugang.passwortGesetzt(), isFalse);

      await zugang.festlegen('geheim123');
      await expectLater(zugang.festlegen('anderes123'), throwsStateError);
      expect(await zugang.pruefen('geheim123'), isTrue);
    });

    test('ändern nur mit dem richtigen alten Passwort — der Schlüssel bleibt',
        () async {
      await zugang.festlegen('geheim123');
      final schluessel = await lokalerSchluessel();

      expect(await zugang.aendern('falsch123', 'neuesPasswort'), isFalse);
      expect(await zugang.pruefen('geheim123'), isTrue);

      expect(await zugang.aendern('geheim123', 'neuesPasswort'), isTrue);
      expect(await zugang.pruefen('geheim123'), isFalse);
      expect(await zugang.pruefen('neuesPasswort'), isTrue);
      expect(await lokalerSchluessel(), schluessel);
      expect(await ausgepackt('neuesPasswort'), schluessel);

      await expectLater(
        zugang.aendern('neuesPasswort', 'kurz'),
        throwsArgumentError,
      );
      expect(await zugang.pruefen('neuesPasswort'), isTrue);
    });

    test('zurücksetzen entfernt Passwort, Schlüssel und alle Daten',
        () async {
      await zugang.festlegen('geheim123');
      await db.into(db.entwicklungZutaten).insert(
            EntwicklungZutatenCompanion.insert(id: 'z1', name: 'Salz'),
          );
      await speicher.schreiben(kEntwicklungAusstehend, '{}');

      await zugang.zuruecksetzen();

      expect(await zugang.passwortGesetzt(), isFalse);
      expect(await zugang.pruefen('geheim123'), isFalse);
      expect(await datensatzText(), isNull);
      expect(await lokalerSchluessel(), isNull);
      expect(await speicher.lesen(kEntwicklungAusstehend), isNull);
      expect(await db.select(db.entwicklungZutaten).get(), isEmpty);
    });

    test('ein Passwort aus dem ersten App-Stand bekommt beim Öffnen seinen '
        'Schlüssel', () async {
      // Damals stand nur der Prüfwert im Datensatz.
      await speicher.schreiben(
        kEntwicklungPasswortSchluessel,
        _datensatz('geheim123'),
      );
      expect((await datensatz()).verpackterSchluessel, isNull);

      expect(await zugang.oeffnen('geheim123'), isTrue);

      final lokal = await lokalerSchluessel();
      expect(lokal, isNotNull);
      expect(await ausgepackt('geheim123'), lokal);
    });

    test('die Iterationen stehen im Datensatz und gelten beim Prüfen',
        () async {
      await zugang.festlegen('geheim123');
      // Ein späterer App-Stand rechnet für neue Passwörter öfter — das
      // alte bleibt prüfbar.
      final spaeter = EntwicklungZugang(
        speicher,
        iterationen: 2000,
        imHintergrund: false,
      );
      expect(await spaeter.pruefen('geheim123'), isTrue);
    });

    test('alle Einstellungen liegen unter dem Präfix der Produktentwicklung',
        () async {
      await zugang.festlegen('geheim123');
      final zeilen = await db.select(db.appSettings).get();
      expect(
        zeilen.map((z) => z.key).toSet(),
        {kEntwicklungPasswortSchluessel, kEntwicklungDatenschluessel},
      );
      expect(zeilen.every((z) => istEntwicklungsSchluessel(z.key)), isTrue);
    });
  });

  test('auf einem eigenen Isolate gerechnet stimmt es genauso', () async {
    final speicher = _Speicher();
    final zugang = EntwicklungZugang(speicher, iterationen: 1000);

    await zugang.festlegen('geheim123');

    expect(await zugang.pruefen('geheim123'), isTrue);
    expect(await zugang.pruefen('geheim124'), isFalse);
    expect(await zugang.oeffnen('geheim123'), isTrue);
  });

  group('Seite', () {
    Future<void> zeige(
      WidgetTester tester,
      _Speicher speicher, {
      bool autoGesperrt = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            if (autoGesperrt)
              entwicklungAutoGesperrtProvider.overrideWith((ref) => true),
            entwicklungZugangProvider.overrideWithValue(
              EntwicklungZugang(
                speicher,
                iterationen: 1000,
                imHintergrund: false,
              ),
            ),
            // Der offene Bereich zeigt Listen aus der Datenbank — hier leer.
            projekteProvider.overrideWith((ref) => Stream.value(const [])),
            zutatenProvider.overrideWith((ref) => Stream.value(const [])),
            rezepturenProvider.overrideWith((ref) => Stream.value(const [])),
            alleVersionenProvider
                .overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const EntwicklungScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    /// Lässt die Prüfung durchlaufen: ein paar Bilder, bis Kreisel und
    /// Abfrage verschwunden sind.
    Future<void> warte(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Finder feld(String label) => find.widgetWithText(TextField, label);

    /// Offen: die Reiter der Produktentwicklung.
    Finder offen() => find.byType(TabBar);

    testWidgets('beim ersten Mal: Passwort festlegen, Fehler, dann offen',
        (tester) async {
      final speicher = _Speicher();
      await zeige(tester, speicher);

      expect(find.text('Passwort festlegen'), findsOneWidget);

      await tester.enterText(feld('Neues Passwort'), 'kurz');
      await tester.enterText(feld('Passwort wiederholen'), 'kurz');
      await tester.tap(find.text('Festlegen und öffnen'));
      await warte(tester);
      expect(find.text('Mindestens 8 Zeichen.'), findsOneWidget);

      await tester.enterText(feld('Neues Passwort'), 'geheim123');
      await tester.enterText(feld('Passwort wiederholen'), 'geheim124');
      await tester.tap(find.text('Festlegen und öffnen'));
      await warte(tester);
      expect(
        find.text('Die beiden Eingaben unterscheiden sich.'),
        findsOneWidget,
      );
      expect(speicher.werte[kEntwicklungPasswortSchluessel], isNull);

      await tester.enterText(feld('Passwort wiederholen'), 'geheim123');
      await tester.tap(find.text('Festlegen und öffnen'));
      await warte(tester);

      expect(offen(), findsOneWidget);
      expect(speicher.werte[kEntwicklungPasswortSchluessel], isNotNull);
      expect(speicher.werte[kEntwicklungDatenschluessel], isNotNull);
    });

    testWidgets('gesperrt: falsches Passwort, richtiges, wieder sperren',
        (tester) async {
      final speicher = _Speicher()
        ..werte[kEntwicklungPasswortSchluessel] = _datensatz('geheim123');
      await zeige(tester, speicher);

      expect(find.text('Gesperrt'), findsOneWidget);
      expect(offen(), findsNothing);

      await tester.enterText(feld('Passwort'), 'falsch123');
      await tester.tap(find.text('Öffnen'));
      await warte(tester);
      expect(find.text('Das Passwort stimmt nicht.'), findsOneWidget);
      expect(offen(), findsNothing);

      await tester.enterText(feld('Passwort'), 'geheim123');
      await tester.tap(find.text('Öffnen'));
      await warte(tester);
      expect(offen(), findsOneWidget);

      await tester.tap(find.byTooltip('Sperren'));
      await warte(tester);
      expect(find.text('Gesperrt'), findsOneWidget);
      expect(offen(), findsNothing);
    });

    testWidgets('nach der automatischen Sperre steht es dabei', (tester) async {
      final speicher = _Speicher()
        ..werte[kEntwicklungPasswortSchluessel] = _datensatz('geheim123');
      await zeige(tester, speicher, autoGesperrt: true);
      await warte(tester);

      expect(find.text('Gesperrt'), findsOneWidget);
      expect(find.text('Automatisch gesperrt'), findsOneWidget);

      await tester.enterText(feld('Passwort'), 'geheim123');
      await tester.tap(find.text('Öffnen'));
      await warte(tester);
      expect(offen(), findsOneWidget);

      // Von Hand gesperrt: ohne den Hinweis.
      await tester.tap(find.byTooltip('Sperren'));
      await warte(tester);
      expect(find.text('Gesperrt'), findsOneWidget);
      expect(find.text('Automatisch gesperrt'), findsNothing);
    });

    testWidgets('ein wartendes Backup wird angekündigt', (tester) async {
      final speicher = _Speicher()
        ..werte[kEntwicklungPasswortSchluessel] = _datensatz('geheim123')
        ..werte[kEntwicklungAusstehend] = '{}';
      await zeige(tester, speicher);
      await warte(tester);

      expect(find.text('Gesperrt'), findsOneWidget);
      expect(find.text('Backup wartet'), findsOneWidget);
    });

    testWidgets('Passwort vergessen: zurücksetzen nur mit Bestätigung',
        (tester) async {
      final speicher = _Speicher()
        ..werte[kEntwicklungPasswortSchluessel] = _datensatz('geheim123');
      await zeige(tester, speicher);

      await tester.tap(find.text('Passwort vergessen?'));
      await warte(tester);
      expect(find.text('Produktentwicklung zurücksetzen?'), findsOneWidget);

      // Ohne das Wort bleibt der Knopf gesperrt.
      final knopf = find.widgetWithText(FilledButton, 'Zurücksetzen');
      expect(tester.widget<FilledButton>(knopf).onPressed, isNull);

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'zurücksetzen',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(knopf).onPressed, isNotNull);

      await tester.tap(knopf);
      await warte(tester);

      expect(speicher.werte, isEmpty);
      expect(speicher.geloescht, isTrue);
      expect(find.text('Passwort festlegen'), findsOneWidget);
    });
  });

  group('Automatische Sperre (F20)', () {
    testWidgets('nach 15 Minuten ohne Eingabe zu — Klick und Taste zählen',
        (tester) async {
      var zeit = DateTime(2026, 10, 21, 8);
      var fensterZu = 0;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: EntwicklungAutoSperre(
              takt: const Duration(seconds: 10),
              jetzt: () => zeit,
              fensterSchliessen: () => fensterZu++,
              child: const Scaffold(body: Center(child: Text('Planung'))),
            ),
          ),
        ),
      );
      bool offen() => container.read(entwicklungEntsperrtProvider);
      Future<void> warten(Duration ruhe) async {
        zeit = zeit.add(ruhe);
        await tester.pump(const Duration(seconds: 11));
      }

      // Gesperrt bleibt gesperrt — dann gibt es nichts zu tun.
      await warten(const Duration(hours: 1));
      expect(fensterZu, 0);

      container.read(entwicklungEntsperrtProvider.notifier).state = true;
      await tester.pump();
      await warten(const Duration(minutes: 10));
      expect(offen(), isTrue);

      // Ein Klick setzt die Zeit zurück …
      await tester.tap(find.text('Planung'));
      await warten(const Duration(minutes: 14));
      expect(offen(), isTrue);

      // … eine Taste auch.
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      await warten(const Duration(minutes: 14));
      expect(offen(), isTrue);

      // Eine Viertelstunde ohne Eingabe: gesperrt, Fenster zu.
      await warten(const Duration(minutes: 2));
      expect(offen(), isFalse);
      expect(container.read(entwicklungAutoGesperrtProvider), isTrue);
      expect(fensterZu, 1);

      // Wieder offen: Der Hinweis geht weg, die Zeit läuft von vorn.
      container.read(entwicklungEntsperrtProvider.notifier).state = true;
      await tester.pump();
      expect(container.read(entwicklungAutoGesperrtProvider), isFalse);
      await warten(const Duration(minutes: 14));
      expect(offen(), isTrue);
    });
  });
}

/// Ein Speicher im Arbeitsspeicher.
class _Speicher implements EntwicklungsSpeicher {
  final Map<String, String> werte = {};
  bool geloescht = false;
  EntwicklungsInhalt? ersetztDurch;

  @override
  Future<String?> lesen(String schluessel) async => werte[schluessel];

  @override
  Future<void> schreiben(String schluessel, String? wert) async {
    if (wert == null) {
      werte.remove(schluessel);
    } else {
      werte[schluessel] = wert;
    }
  }

  @override
  Future<void> datenErsetzen(EntwicklungsInhalt inhalt) async {
    ersetztDurch = inhalt;
  }

  @override
  Future<void> datenLoeschen() async {
    geloescht = true;
  }
}

/// Ein Datensatz wie aus dem ersten App-Stand — nur Salz und Prüfwert,
/// ohne Umweg über async.
String _datensatz(String passwort) {
  final salz = Uint8List.fromList(List<int>.generate(16, (i) => i * 7));
  return jsonEncode(
    PasswortDatensatz(
      salz: salz,
      iterationen: 1000,
      pruefwert: pruefwertFuer(passwort, salz, 1000),
    ).toJson(),
  );
}
