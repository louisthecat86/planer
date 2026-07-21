import 'package:drift/drift.dart';

/// Steckbrief einer Maschine: WELCHE Parameter sie hat.
///
/// Jede Zeile definiert ein Eingabefeld, das in der Artikelmaske erscheint,
/// sobald diese Maschine einem Prozessschritt zugeordnet ist. Die WERTE
/// werden weiterhin pro Artikel/Schritt in `product_step_parameters`
/// gepflegt — hier steht nur, welche Felder es gibt.
///
/// Beispiel: Füllmaschine → "Takte" (Takte/min), "Portionsgröße" (g).
/// Der Parameter bleibt in der Maske stehen, bis er hier entfernt wird.
@DataClassName('MachineParameterDef')
class MachineParameterDefs extends Table {
  /// UUID.
  TextColumn get id => text()();

  /// Verweis auf machines.id.
  TextColumn get maschineId => text()();

  /// Name des Parameters — exakt so erscheint er in der Artikelmaske
  /// und in `product_step_parameters.parameterName`.
  TextColumn get parameterName => text()();

  /// Optionale Einheit, rein zur Anzeige (z.B. "°C", "Takte/min", "mm").
  TextColumn get einheit => text().nullable()();

  /// Reihenfolge in der Maske (kleiner = weiter oben).
  IntColumn get sortierung => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {maschineId, parameterName},
      ];
}
