import 'package:drift/drift.dart';

/// Generische Key-Value-Tabelle für App-interne Einstellungen und
/// Zustandsinformationen, die nicht in eine eigene Domäne gehören.
///
/// Aktuelle Nutzung:
/// - `last_import_excel_bytes`: Die zuletzt importierte Excel-Datei
///   als Base64-kodierter Blob. Wird beim Export als Basis verwendet,
///   damit Formatierung, Farben, Dropdowns und Anlagen-Katalog
///   erhalten bleiben.
/// - `last_import_excel_filename`: Der ursprüngliche Dateiname
///   (z.B. "stammdaten_vorlage_v3_cleaned1.xlsx"), wird beim Export
///   als Vorschlag im Speichern-Dialog verwendet.
/// - `last_import_datum`: Zeitstempel des letzten Imports.
///
/// Die Tabelle ist bewusst schlicht gehalten: Ein String-Schlüssel,
/// ein String-Wert. Blobs werden als Base64-String abgelegt, damit
/// wir nicht zwei verschiedene Speicherformen pflegen müssen.
@DataClassName('AppSetting')
class AppSettings extends Table {
  /// Eindeutiger Schlüssel, z.B. "last_import_excel_bytes".
  TextColumn get key => text()();

  /// Wert als String. Binäre Daten werden Base64-kodiert abgelegt.
  TextColumn get value => text()();

  /// Zeitstempel der letzten Änderung.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}