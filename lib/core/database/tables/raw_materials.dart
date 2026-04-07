import 'package:drift/drift.dart';

/// Rohwaren-Katalog (Schweinebauch, Salz, Gewürze, Därme, ...).
///
/// **Wichtig:** Rohwaren sind *produkt-unabhängig*. Eine Rohware wie
/// "Schweinebauch" existiert einmal und wird von mehreren Produkten über
/// [ProductRawMaterials] referenziert. Das erlaubt später Aggregation
/// für die Wochenbestellung ("Summe Schweinebauch über alle Produkte").
///
/// Konkrete Chargen mit MHD und Lieferdatum liegen in [RawMaterialBatches].
@DataClassName('RawMaterial')
class RawMaterials extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get artikelnummer => text().nullable()();

  /// Basis-Einheit für Mengenangaben ("kg", "g", "l", "Stk").
  /// Wird nicht automatisch umgerechnet — alle Angaben müssen pro Rohware
  /// konsistent in dieser Einheit sein.
  TextColumn get einheit => text()();

  TextColumn get lieferant => text().nullable()();

  /// Typische Lieferzeit in Tagen — für MRP-Bestelllogik (Phase 4).
  IntColumn get leadTimeTage => integer().nullable()();

  /// Wenn true: Chargen-Tracking ist für diese Rohware verpflichtend (HACCP).
  /// Jeder Verbrauch muss dann auf eine konkrete Charge gebucht werden.
  BoolColumn get chargenPflicht =>
      boolean().withDefault(const Constant(true))();

  TextColumn get notizen => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
