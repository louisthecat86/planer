import 'package:drift/drift.dart';

/// Produkt-Stammdaten (das "lernende" Zentrum der App).
///
/// Jedes Produkt, das jemals produziert wurde, steht hier einmal drin.
/// Details (Abteilungsfolge, Rohwaren) hängen über [ProductSteps] und
/// [ProductRawMaterials] dran. Beim erneuten Planen desselben Produkts
/// werden diese Daten automatisch übernommen.
///
/// **Gruppenspezifische Felder:** Je nach [produktgruppe] werden beim
/// Import einer Vorlage unterschiedliche Spalten gefüllt. Welche Gruppe
/// welche Felder erwartet, ist in `product_group_fields.dart` definiert.
/// Alle gruppenspezifischen Spalten sind nullable — ein Leberkäse hat
/// keinen aw-Wert, eine Salami keinen Anbratgrad.
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

  // ── Produktgruppe (steuert welche Zusatzfelder relevant sind) ─────────

  /// Produktgruppe als [ProductGroup.dbValue]. NULL = noch nicht klassifiziert
  /// (nur für Altdaten, neue Artikel sollten eine Gruppe haben).
  TextColumn get produktgruppe => text().nullable()();

  // ── Verpackung ────────────────────────────────────────────────────────

  TextColumn get verpackungsart => text().nullable()();
  RealColumn get gebindeGroesseKg => real().nullable()();

  // ── Haltbarkeit ───────────────────────────────────────────────────────

  IntColumn get haltbarkeitTage => integer().nullable()();

  // ── Planungsrelevant (allgemein) ──────────────────────────────────────

  RealColumn get gesamtAusbeuteFaktor => real().nullable()();
  IntColumn get mindestVorlaufzeitTage => integer().nullable()();

  /// Alte Freitext-Planungsgruppe. Wird nicht mehr aktiv gepflegt, bleibt
  /// aber als Spalte erhalten für Abwärtskompatibilität mit alten Backups.
  TextColumn get planungsgruppe => text().nullable()();

  // ═══════════════════════════════════════════════════════════════════════
  // Gruppenspezifische Felder
  //
  // Jede Spalte ist nullable. Welche für welche Gruppe Pflicht sind,
  // steht in product_group_fields.dart und wird beim Import validiert.
  // ═══════════════════════════════════════════════════════════════════════

  // ── Temperaturen (gruppenübergreifend verwendet) ──────────────────────

  /// Ziel-Kerntemperatur in °C (Brühwurst, Kochpökel, Bratstraße, SV, Braten).
  RealColumn get zielKerntempC => real().nullable()();

  /// Kutter-Endtemperatur in °C (Brühwurst, angebratene Brühwurst).
  RealColumn get kutterEndtempC => real().nullable()();

  // ── Brät-/Wurst-spezifisch ────────────────────────────────────────────

  /// 'grob' | 'mittel' | 'fein' (Brühwurst, angebratene Brühwurst).
  TextColumn get braetFeinheit => text().nullable()();

  /// Kochkammer-Programm als Freitext (Brühwurst, angebratene Brühwurst).
  TextColumn get kochkammerProgramm => text().nullable()();

  /// 'keine' | 'kalt' | 'warm' | 'heiß' (diverse Gruppen).
  TextColumn get raeucherart => text().nullable()();

  // ── Rohwurst / Reifung ────────────────────────────────────────────────

  /// Produktname der Starterkultur (Rohwurst).
  TextColumn get startkultur => text().nullable()();

  /// Reifezeit in Tagen (Rohwurst, Rohpökelware).
  IntColumn get reifezeitTage => integer().nullable()();

  /// Klimaprogramm-Bezeichnung (Rohwurst).
  TextColumn get klimaprogramm => text().nullable()();

  /// Ziel-pH-Wert (Rohwurst).
  RealColumn get zielPh => real().nullable()();

  /// Ziel-aw-Wert (Rohwurst, Rohpökelware).
  RealColumn get zielAw => real().nullable()();

  /// Gewichtsverlust bzw. Trocknungsverlust in % (Rohwurst, Rohpökelware).
  RealColumn get gewichtsverlustProzent => real().nullable()();

  // ── Pökelware ─────────────────────────────────────────────────────────

  /// 'trocken' | 'nass' | 'injektion' (Kochpökel, Rohpökel).
  TextColumn get poekelart => text().nullable()();

  /// Lake-Konzentration in % (Kochpökel).
  RealColumn get lakeKonzentrationProzent => real().nullable()();

  /// Pökelzeit in Tagen (Kochpökel, Rohpökel).
  IntColumn get poekelzeitTage => integer().nullable()();

  /// Tumbelzeit in Minuten (Kochpökel).
  RealColumn get tumbelzeitMin => real().nullable()();

  // ── Aufschnitt ────────────────────────────────────────────────────────

  /// Artikelnummer des Basis-Produkts (Aufschnitt verweist auf Rohprodukt).
  /// Bewusst KEIN DB-FK, damit der Import auch bei fehlender Basis nicht bricht.
  TextColumn get basisProduktArtikelnummer => text().nullable()();

  /// Scheibendicke in mm (Aufschnitt).
  RealColumn get scheibendickeMm => real().nullable()();

  /// Anzahl Scheiben pro Packung (Aufschnitt).
  IntColumn get scheibenProPackung => integer().nullable()();

  /// Packungsgewicht in g (Aufschnitt).
  RealColumn get packungsgewichtG => real().nullable()();

  /// MAP-Gasgemisch als Freitext (Aufschnitt).
  TextColumn get mapGas => text().nullable()();

  // ── Bratstraße ────────────────────────────────────────────────────────

  /// Formgewicht in g (Bratstraße natur, Bratstraße paniert).
  RealColumn get formgewichtG => real().nullable()();

  /// 'rund' | 'oval' | 'patty' | 'länglich' (Bratstraße natur).
  TextColumn get form => text().nullable()();

  /// 'leicht' | 'mittel' | 'durch' (Bratstraße natur).
  TextColumn get bratgrad => text().nullable()();

  /// 'Mehl' | 'Paniermehl' | 'Panko' | 'Cornflakes' | 'Sonstige'.
  TextColumn get panierart => text().nullable()();

  /// Panier-Aufnahme in % (Bratstraße paniert).
  RealColumn get panierAufnahmeProzent => real().nullable()();

  // ── Hackprodukte ──────────────────────────────────────────────────────

  /// 'S1' | 'S8' | 'gemischt' | 'R1' | 'R8' (Hackprodukte gegart/roh).
  TextColumn get fleischanteilTyp => text().nullable()();

  /// Gesamtdurchlaufzeit max in Stunden (Hackprodukte roh, Frische-Fenster).
  RealColumn get gesamtdurchlaufzeitMaxStd => real().nullable()();

  /// Wolf-Lochscheibe in mm (Hackprodukte roh).
  RealColumn get wolfLochscheibeMm => real().nullable()();

  /// Abkühlgradient als Freitext (Hackprodukte gegart, Sous Vide).
  TextColumn get abkuehlgradient => text().nullable()();

  // ── Braten ────────────────────────────────────────────────────────────

  /// 'roh' | 'vorgegart'.
  TextColumn get bratenVariante => text().nullable()();

  /// Füllungs-Beschreibung (Braten).
  TextColumn get fuellung => text().nullable()();

  /// Netzbindung ja/nein (Braten).
  BoolColumn get netzbindung => boolean().nullable()();

  // ── Sous Vide ─────────────────────────────────────────────────────────

  /// SV-Badtemperatur in °C (Sous Vide).
  RealColumn get svBadtempC => real().nullable()();

  /// SV-Garzeit in Stunden (Sous Vide).
  RealColumn get svGarzeitStd => real().nullable()();

  // ── Angebratene Brühwurst ─────────────────────────────────────────────

  /// 'hell' | 'mittel' | 'dunkel' (angebratene Brühwurst).
  TextColumn get anbratgrad => text().nullable()();

  // ── Sync-Felder (in allen Tabellen identisch) ─────────────────────────

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}