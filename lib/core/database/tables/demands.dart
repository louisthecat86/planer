import 'package:drift/drift.dart';

/// Bedarfsliste — der Auslöser der Produktion.
///
/// Bisher entstand der Wochenplan aus dem Kopf des Planers: Man sah im
/// Warenwirtschaftssystem nach, was bestellt ist und was auf Lager liegt,
/// und legte sich das Puzzle zurecht. Diese Liste macht genau diesen
/// Schritt sichtbar — sie beantwortet die Frage „WAS muss produziert
/// werden?", während das Board die Frage „WANN und WOMIT?" beantwortet.
///
/// Bewusst schlank gehalten: kein ERP, keine Bestandsführung. Nur die
/// offenen Mengen, die anstehen — der Rest bleibt eure Entscheidung.
class Demands extends Table {
  TextColumn get id => text()();

  /// Artikel, für den der Bedarf besteht.
  TextColumn get productId => text()();

  /// Benötigte Menge in kg FERTIGWARE (das, was rausgehen muss).
  /// Die Rohwarenmenge rechnet die Planung daraus über die Ausbeute
  /// zurück — so, wie ihr auch denkt.
  RealColumn get mengeKgFertig => real()();

  /// Wunschtermin: bis wann soll es fertig sein.
  DateTimeColumn get termin => dateTime().nullable()();

  /// Woher kommt der Bedarf: 'bestellung', 'bestand' oder 'sonstiges'.
  /// Rein informativ — hilft beim Priorisieren.
  TextColumn get quelle => text().withDefault(const Constant('bestellung'))();

  /// Priorität: 0 = normal, 1 = hoch (wird oben einsortiert).
  IntColumn get prioritaet => integer().withDefault(const Constant(0))();

  /// Freitext: Kunde, Auftragsnummer, Besonderheiten.
  TextColumn get notizen => text().nullable()();

  /// Manuell auf „erledigt" gesetzt (unabhängig von der geplanten Menge) —
  /// z.B. wenn ein Auftrag storniert wurde oder aus Lagerbestand gedeckt
  /// werden konnte.
  BoolColumn get manuellErledigt =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
