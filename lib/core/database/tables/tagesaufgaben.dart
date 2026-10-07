import 'package:drift/drift.dart';

/// Sonstige Aufgaben einer Abteilung an einem Tag — von Hand eingetragen.
///
/// Alles, was nicht aus der Planung eines Artikels entsteht: „Kessel
/// entkalken", „Messer schleifen lassen", „Neue Folie testen". Im
/// Wochenboard hat jede Abteilung dafür unter ihren Anlagen eine eigene
/// Zeile. Die Aufgaben lassen sich abhaken wie die Aufträge und auf einen
/// anderen Tag ziehen, wenn sie liegen geblieben sind.
///
/// Bewusst ohne Dauer oder Anlage: Sie belegen keine Kapazität. Wer Zeit an
/// einer Anlage blockieren will, nimmt die Rüst- und Reinigungszeiten.
@DataClassName('Tagesaufgabe')
class Tagesaufgaben extends Table {
  /// UUID.
  TextColumn get id => text()();

  /// Tag, für den die Aufgabe gilt (auf 00:00 normalisiert).
  DateTimeColumn get datum => dateTime()();

  /// Abteilung, gespeichert als [Abteilung.dbValue].
  TextColumn get abteilung => text()();

  /// Was zu tun oder zu wissen ist.
  TextColumn get inhalt => text()();

  /// Abgehakt — im Board grün.
  BoolColumn get erledigt => boolean().withDefault(const Constant(false))();

  /// Reihenfolge innerhalb von Tag und Abteilung, kleinere zuerst. Neue
  /// Einträge kommen ans Ende.
  IntColumn get sortierung => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
