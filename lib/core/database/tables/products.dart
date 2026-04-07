import 'package:drift/drift.dart';

/// Produkt-Stammdaten (das "lernende" Zentrum der App).
///
/// Jedes Produkt, das jemals produziert wurde, steht hier einmal drin.
/// Details (Abteilungsfolge, Rohwaren) hängen über [ProductSteps] und
/// [ProductRawMaterials] dran. Beim erneuten Planen desselben Produkts
/// werden diese Daten automatisch übernommen.
@DataClassName('Product')
class Products extends Table {
  /// UUID — wird in der App per `uuid`-Package erzeugt, nicht von SQLite.
  /// Grund: Supabase-Sync-Kompatibilität (keine Auto-Increment-Kollisionen).
  TextColumn get id => text()();

  /// Artikelnummer wie im Betrieb verwendet (z.B. "LK-001"). Unique.
  TextColumn get artikelnummer => text().unique()();

  /// Menschenlesbare Bezeichnung ("Leberkäse grob").
  TextColumn get artikelbezeichnung => text()();

  TextColumn get beschreibung => text().nullable()();
  TextColumn get notizen => text().nullable()();

  // --- Sync-Felder (in allen Tabellen identisch) ---
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
