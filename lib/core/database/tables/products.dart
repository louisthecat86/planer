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

  // --- Verpackung ---

  /// Art der Verpackung (z.B. 'vakuum', 'map', 'frischetheke', 'thermoform').
  TextColumn get verpackungsart => text().nullable()();

  /// Gebindegröße in kg (z.B. 0.5, 1.0, 2.5).
  RealColumn get gebindeGroesseKg => real().nullable()();

  // --- Haltbarkeit ---

  /// Haltbarkeit ab Produktion in Tagen (z.B. vakuum Leberkäse = 21 Tage).
  IntColumn get haltbarkeitTage => integer().nullable()();

  // --- Planungsrelevant ---

  /// Gesamtausbeute-Faktor (Rohware → Fertigware).
  /// z.B. 0.75 = aus 1 kg Rohware werden 0.75 kg Fertigprodukt.
  /// Wird aus den einzelnen Schritt-Ausbeutefaktoren berechnet oder manuell gesetzt.
  RealColumn get gesamtAusbeuteFaktor => real().nullable()();

  /// Mindest-Vorlaufzeit in Tagen (z.B. 2 = muss 2 Tage vorher geplant werden).
  IntColumn get mindestVorlaufzeitTage => integer().nullable()();

  /// Planungsgruppe für Reihenfolge-Optimierung
  /// (z.B. 'hell', 'dunkel', 'allergen_senf', 'allergen_soja').
  /// Helle Produkte vor dunklen → weniger Reinigung.
  TextColumn get planungsgruppe => text().nullable()();

  // --- Sync-Felder (in allen Tabellen identisch) ---
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
