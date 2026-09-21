import 'package:drift/drift.dart';

/// Generische Key-Value-Tabelle für App-interne Einstellungen und
/// Zustandsinformationen, die nicht in eine eigene Domäne gehören.
///
/// Aktuelle Nutzung: Darstellung (Hell/Dunkel, Anzeigegröße).
///
/// Früher lag hier auch die zuletzt importierte Excel-Vorlage als
/// Base64-Text (`last_import_excel_bytes` und zwei Begleitschlüssel). Der
/// alte Exporter schrieb in diese Datei hinein. Seit der Generator die
/// Mappe selbst baut, wird sie nicht mehr gebraucht; Migration 21 entfernt
/// die Einträge.
///
/// Die Tabelle ist bewusst schlicht gehalten: Ein String-Schlüssel,
/// ein String-Wert. Blobs werden als Base64-String abgelegt, damit
/// wir nicht zwei verschiedene Speicherformen pflegen müssen.
@DataClassName('AppSetting')
class AppSettings extends Table {
  /// Eindeutiger Schlüssel, z.B. "theme_mode".
  TextColumn get key => text()();

  /// Wert als String. Binäre Daten werden Base64-kodiert abgelegt.
  TextColumn get value => text()();

  /// Zeitstempel der letzten Änderung.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}
