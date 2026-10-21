import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/ui/fehler_anzeige.dart';
import 'package:produktion_planer/core/utils/fehler_text.dart';

/// Tests für Fehler in der Oberfläche: ein Fehler als Satz statt roh,
/// Meldungen ohne BuildContext und die Kachel für einen Bereich, der
/// sich nicht aufbauen ließ.
void main() {
  group('fehlerText', () {
    test('ohne Inhalt', () {
      expect(fehlerText(null), 'Unbekannter Fehler.');
      expect(fehlerText('   '), 'Unbekannter Fehler.');
    });

    test('Texte und Dart-Fehler ohne Vorsilbe', () {
      expect(fehlerText('Datei fehlt'), 'Datei fehlt');
      expect(
        fehlerText(const FormatException('Zeile 3 hat zu wenige Spalten.')),
        'Zeile 3 hat zu wenige Spalten.',
      );
      expect(
        fehlerText(const FormatException('')),
        'Das Format passt nicht.',
      );
      expect(
        fehlerText(StateError('Kein Artikel gewählt.')),
        'Kein Artikel gewählt.',
      );
      expect(fehlerText(ArgumentError('Menge fehlt')), 'Menge fehlt');
      expect(fehlerText(ArgumentError()), 'Ungültige Angabe.');
      expect(fehlerText(UnsupportedError('Nur am Rechner')), 'Nur am Rechner');
      expect(
        fehlerText(Exception('Backup-Import fehlgeschlagen: kaputt')),
        'Backup-Import fehlgeschlagen: kaputt',
      );
    });

    test('Zeitüberschreitung, Dateien und Verbindungen', () {
      expect(
        fehlerText(TimeoutException('nach 30 s')),
        'Zeitüberschreitung — bitte noch einmal versuchen.',
      );
      expect(
        fehlerText(
          const FileSystemException(
            'Cannot open file',
            '/daten/vorlage.xlsx',
            OSError('No such file or directory', 2),
          ),
        ),
        'Dateizugriff fehlgeschlagen: No such file or directory '
        '(/daten/vorlage.xlsx)',
      );
      expect(
        fehlerText(const FileSystemException('Cannot delete file')),
        'Dateizugriff fehlgeschlagen: Cannot delete file',
      );
      expect(
        fehlerText(
          const SocketException(
            'Failed host lookup',
            osError: OSError('Name or service not known', -2),
          ),
        ),
        'Keine Verbindung: Name or service not known',
      );
    });

    test('Meldungen der Datenbank in Worten', () {
      expect(
        fehlerText(
          const _SqlFehler(
            'SqliteException(2067): while executing statement, UNIQUE '
            'constraint failed: products.artikelnummer, constraint failed '
            '(code 2067)\n  Causing statement: INSERT INTO products …',
          ),
        ),
        'Datenbankfehler: Diesen Eintrag gibt es schon '
        '(products.artikelnummer).',
      );
      expect(
        fehlerText(
          const _SqlFehler(
            'SqliteException(787): while executing statement, FOREIGN KEY '
            'constraint failed, constraint failed (code 787)',
          ),
        ),
        'Datenbankfehler: Der Eintrag hängt noch an anderen Daten.',
      );
      expect(
        fehlerText(
          const _SqlFehler(
            'SqliteException(5): while executing statement, database is '
            'locked, database is locked (code 5)',
          ),
        ),
        'Die Datenbank ist gerade belegt — bitte gleich noch einmal '
        'versuchen.',
      );
      final sonst = fehlerText(
        const _SqlFehler(
          'SqliteException(1): while preparing statement, no such table: '
          'beispiel, SQL logic error (code 1)\n  Causing statement: SELECT 1',
        ),
      );
      expect(sonst, startsWith('Datenbankfehler: '));
      expect(sonst, contains('no such table: beispiel'));
      expect(sonst, isNot(contains('Causing statement')));
    });

    test('lange Meldungen werden gekürzt', () {
      expect(
        fehlerText(Exception('erste\nzweite\ndritte\nvierte\nfünfte')),
        'erste\nzweite\ndritte',
      );
      final lang = fehlerText('x' * 1000);
      expect(lang.length, 400);
      expect(lang, endsWith('…'));
    });
  });

  group('Anzeige', () {
    testWidgets('eine Kachel sagt in Worten, dass ein Bereich fehlt',
        (tester) async {
      await tester.pumpWidget(FehlerKachel(fehler: StateError('Liste leer')));
      expect(
        find.textContaining('Dieser Bereich ließ sich nicht anzeigen.'),
        findsOneWidget,
      );
      expect(find.textContaining('Liste leer'), findsOneWidget);
    });

    testWidgets('Meldungen erscheinen ohne BuildContext, nicht im '
        'Sekundentakt', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: appMessengerKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      final start = DateTime(2026, 10, 21, 8);
      Future<void> zeigen() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
      }

      Future<void> wegnehmen() async {
        appMessengerKey.currentState!.removeCurrentSnackBar();
        await tester.pump();
      }

      fehlerMelden(StateError('Etikett fehlt'), wobei: 'Drucken', jetzt: start);
      await zeigen();
      expect(find.text('Drucken: Etikett fehlt'), findsOneWidget);
      await wegnehmen();
      expect(find.text('Drucken: Etikett fehlt'), findsNothing);

      // Dieselbe Meldung zwei Sekunden später: nicht noch einmal.
      fehlerMelden(
        StateError('Etikett fehlt'),
        wobei: 'Drucken',
        jetzt: start.add(const Duration(seconds: 2)),
      );
      await zeigen();
      expect(find.text('Drucken: Etikett fehlt'), findsNothing);

      // Nach fünf Sekunden darf sie wieder kommen.
      fehlerMelden(
        StateError('Etikett fehlt'),
        wobei: 'Drucken',
        jetzt: start.add(const Duration(seconds: 8)),
      );
      await zeigen();
      expect(find.text('Drucken: Etikett fehlt'), findsOneWidget);
      await wegnehmen();

      // Ohne Angabe, wobei: ein unerwarteter Fehler.
      fehlerMelden(
        Exception('Datei weg'),
        jetzt: start.add(const Duration(seconds: 9)),
      );
      await zeigen();
      expect(find.text('Unerwarteter Fehler: Datei weg'), findsOneWidget);
      await wegnehmen();
    });
  });
}

/// Steht für eine Meldung von SQLite — ohne das Paket direkt zu brauchen.
class _SqlFehler implements Exception {
  const _SqlFehler(this.text);

  final String text;

  @override
  String toString() => text;
}
