import 'package:drift/drift.dart';

/// Rüst-, Reinigungs- und sonstige Nebenzeiten je Tag und Planungsspur.
///
/// Bisher zählte im Wochenplan nur die reine Produktionszeit der Aufträge.
/// Damit war die Tagesauslastung systematisch zu optimistisch: Umrüsten
/// zwischen zwei Artikeln und die Endreinigung brauchen ebenfalls Zeit an
/// derselben Anlage, blockieren sie also genauso.
///
/// Eine Zeile = ein Zeitblock an EINER Spur an EINEM Tag. Die Minuten
/// fließen in die Belegung der Spur ein und verkleinern damit die freie
/// Kapazität.
@DataClassName('Zusatzzeit')
class Zusatzzeiten extends Table {
  /// UUID.
  TextColumn get id => text()();

  /// Tag, auf den sich der Block bezieht (auf 00:00 normalisiert).
  DateTimeColumn get datum => dateTime()();

  /// Kennung der Planungsspur — identisch zu `BoardSpur.id`, also
  /// „<abteilung>|<maschineId>" bzw. „<abteilung>|" für die Sammelspur
  /// einer Abteilung ohne eigene Anlagen-Spuren.
  TextColumn get spurId => text()();

  /// Art des Blocks: `ruesten`, `reinigen` oder `sonstiges`.
  TextColumn get art => text()();

  /// Dauer in Minuten.
  RealColumn get minuten => real()();

  /// Freitext, z.B. „Wechsel hell → dunkel" oder „Grundreinigung".
  TextColumn get notiz => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
