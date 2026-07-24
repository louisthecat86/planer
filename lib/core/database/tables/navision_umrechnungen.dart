import 'package:drift/drift.dart';

/// Umrechnung von Navision-Einheiten in Kilogramm.
///
/// Navision führt viele Artikel nicht in kg, sondern in Beutel, Pack,
/// Stück oder Karton — „9.857 BTL Frikadellen" sagt nichts darüber, wie
/// viel Fleisch dafür durch die Anlagen muss. Die Planung rechnet aber
/// durchgehend in Kilogramm.
///
/// Deshalb wird der Faktor einmal je Artikel hinterlegt und dann
/// wiederverwendet. Bewusst eine EIGENE Tabelle: Der Artikelkatalog wird
/// bei jedem Navision-Import komplett ersetzt — ein dort gespeicherter
/// Faktor wäre danach weg.
@DataClassName('NavisionUmrechnung')
class NavisionUmrechnungen extends Table {
  /// Artikelnummer aus Navision.
  TextColumn get nummer => text()();

  /// Einheit, für die der Faktor gilt (BTL, PACK, STCK …). Dient als
  /// Kontrolle: Ändert Navision die Basiseinheit, passt der alte Faktor
  /// nicht mehr und muss neu erfasst werden.
  TextColumn get einheit => text()();

  /// Wie viel Kilogramm eine Einheit entspricht (z.B. 3 kg je Beutel).
  RealColumn get kgJeEinheit => real()();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {nummer};
}
