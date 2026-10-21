/// Ein Fehler als Satz für die Oberfläche.
///
/// Vorher stand der Fehler roh in den Meldungen: „Bad state: …",
/// „FileSystemException: Cannot open file, path = … (OS Error: …)" oder
/// eine SQL-Meldung samt Anweisung. Hier wird daraus, was für die Arbeit
/// zählt — der Grund und, wo es hilft, die Datei. Ohne
/// Flutter-Abhängigkeit, damit auch Dienste ihn benutzen können.
library;

import 'dart:async';
import 'dart:io';

/// So lang darf eine Meldung höchstens werden.
const int _hoechstens = 400;

/// Der Fehler [fehler] in lesbarer Form.
String fehlerText(Object? fehler) {
  final text = _text(fehler).trim();
  if (text.isEmpty) return 'Unbekannter Fehler.';
  return text.length <= _hoechstens
      ? text
      : '${text.substring(0, _hoechstens - 1)}…';
}

String _text(Object? fehler) {
  if (fehler == null) return '';
  if (fehler is String) return fehler;
  if (fehler is FormatException) {
    return fehler.message.trim().isEmpty
        ? 'Das Format passt nicht.'
        : fehler.message;
  }
  if (fehler is StateError) return fehler.message;
  if (fehler is ArgumentError) {
    final m = fehler.message;
    return m == null ? 'Ungültige Angabe.' : '$m';
  }
  if (fehler is UnsupportedError) return fehler.message ?? 'Nicht möglich.';
  if (fehler is TimeoutException) {
    return 'Zeitüberschreitung — bitte noch einmal versuchen.';
  }
  if (fehler is FileSystemException) {
    final grund = fehler.osError?.message.trim();
    final pfad = fehler.path;
    return [
      'Dateizugriff fehlgeschlagen',
      if (grund != null && grund.isNotEmpty)
        ': $grund'
      else
        ': ${fehler.message}',
      if (pfad != null && pfad.isNotEmpty) ' ($pfad)',
    ].join();
  }
  if (fehler is SocketException) {
    return 'Keine Verbindung: ${fehler.osError?.message ?? fehler.message}';
  }
  return _ohneVorsilbe(fehler.toString());
}

/// Vorsilben von Dart, die nur sagen, welche Art Fehler es war.
const List<String> _vorsilben = [
  'Exception: ',
  'Bad state: ',
  'Invalid argument(s): ',
  'Invalid argument: ',
  'FormatException: ',
  'Unsupported operation: ',
  'Instance of ',
];

String _ohneVorsilbe(String roh) {
  var text = roh.trim();
  if (text.startsWith('SqliteException')) return _datenbank(text);
  for (final v in _vorsilben) {
    if (text.startsWith(v)) {
      text = text.substring(v.length);
      break;
    }
  }
  // Mehrzeilige Meldungen (etwa mit Stapel) nur mit den ersten Zeilen.
  final zeilen = text.split('\n');
  return zeilen.length <= 3 ? text : zeilen.take(3).join('\n');
}

/// Eine Meldung von SQLite: „SqliteException(2067): while executing
/// statement, UNIQUE constraint failed: products.artikelnummer, …".
String _datenbank(String roh) {
  final erste = roh.split('\n').first;
  final doppelpunkt = erste.indexOf('): ');
  var grund = doppelpunkt < 0 ? erste : erste.substring(doppelpunkt + 3);
  grund = grund.replaceFirst('while executing statement, ', '');
  final klein = grund.toLowerCase();
  if (klein.contains('unique constraint failed')) {
    final feld = RegExp(r'unique constraint failed: ([\w.]+)')
        .firstMatch(klein)
        ?.group(1);
    return 'Datenbankfehler: Diesen Eintrag gibt es schon'
        '${feld == null ? '' : ' ($feld)'}.';
  }
  if (klein.contains('foreign key constraint failed')) {
    return 'Datenbankfehler: Der Eintrag hängt noch an anderen Daten.';
  }
  if (klein.contains('database is locked')) {
    return 'Die Datenbank ist gerade belegt — bitte gleich noch einmal '
        'versuchen.';
  }
  return 'Datenbankfehler: $grund';
}
