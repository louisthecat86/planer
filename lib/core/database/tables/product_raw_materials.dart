import 'package:drift/drift.dart';
import 'products.dart';
import 'raw_materials.dart';

/// Rezept-Bestandteile: welches Produkt braucht welche Rohware in welcher Menge.
///
/// Einheit: Menge pro 1 kg **Fertigprodukt** (nach Verarbeitung/Gar-Verlust).
/// Das ist konsistent mit der EU-QUID-Logik. Falls ihr lieber auf Rohmasse
/// rechnen wollt, ist das eine andere Kalkulation und muss umgebaut werden.
@DataClassName('ProductRawMaterial')
class ProductRawMaterials extends Table {
  TextColumn get id => text()();

  TextColumn get productId => text().references(Products, #id)();
  TextColumn get rawMaterialId => text().references(RawMaterials, #id)();

  /// Menge der Rohware pro 1 kg Fertigprodukt.
  /// Einheit ergibt sich aus [RawMaterials.einheit].
  RealColumn get mengeProKgProdukt => real()();

  /// Optional: prozentuale Toleranz (z.B. 5.0 = ±5%). Reserviert für Phase 4+.
  RealColumn get toleranzProzent => real().nullable()();

  TextColumn get notizen => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
