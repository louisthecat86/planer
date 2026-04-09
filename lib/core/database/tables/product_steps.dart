import 'package:drift/drift.dart';
import 'products.dart';

/// Abteilungs-Schritte, die ein Produkt durchläuft — Herzkammer der Lernlogik.
///
/// Jede Zeile = ein Schritt im Durchlauf eines Produkts.
/// Beispiel "Leberkäse": (1) Zerlegung, (2) Wurstküche, (3) Bratstraße, (4) Verpackung.
///
/// Die `basis_*`-Felder sind **Mittelwerte über alle bisherigen Runs**
/// (siehe [ProductionRuns]). Sie werden nach jedem abgeschlossenen Auftrag
/// neu berechnet. Beim Anlegen eines neuen Auftrags werden daraus die
/// geplanten Werte linear auf die Auftragsmenge hochgerechnet:
///
///     geplante_dauer = fix_zeit_minuten + basis_dauer_minuten * (auftrags_menge / basis_menge_kg)
///
/// [fixZeitMinuten] erlaubt fixe Rüstzeiten (Maschine einrichten, Temperatur
/// erreichen), die unabhängig von der Menge anfallen.
class ProductSteps extends Table {
  TextColumn get id => text()();

  TextColumn get productId => text().references(Products, #id)();

  /// Position in der Abfolge (1, 2, 3, ...). Erlaubt Umsortieren per Drag&Drop.
  IntColumn get reihenfolge => integer()();

  /// Abteilung, die diesen Schritt ausführt — gespeichert als [Abteilung.dbValue].
  TextColumn get abteilung => text()();

  // --- Zeitkorridor (lernend, Mittelwerte über historische Runs) ---

  /// Referenzmenge in kg, auf die sich [basisDauerMinuten] bezieht.
  RealColumn get basisMengeKg => real()();

  /// Basis-Dauer in Minuten für [basisMengeKg].
  RealColumn get basisDauerMinuten => real()();

  /// Fixe Rüstzeit, unabhängig von der Menge. NULL/0 = rein lineare Skalierung.
  RealColumn get fixZeitMinuten => real().nullable()();

  /// Standardabweichung der gemessenen Dauern (aus [ProductionRuns] berechnet).
  /// UI kann damit "90 min ± 12 min" ehrlich anzeigen.
  RealColumn get dauerStdAbweichung => real().nullable()();

  IntColumn get basisMitarbeiter => integer()();

  /// Anzahl der Runs, aus denen die Basis-Werte berechnet wurden.
  /// 0 = noch nie gemessen (Schätzwerte). Ab ~5 zunehmend verlässlich.
  IntColumn get basisAnzahlMessungen =>
      integer().withDefault(const Constant(0))();

  // --- Ausbeute / Verluste ---

  /// Ausbeute-Faktor dieses Schritts: 0.88 = 12% Verlust (Gar, Schnitt, etc.).
  /// NULL = kein Verlust in diesem Schritt (Faktor 1.0).
  /// Gesamtausbeute = Produkt aller Schritt-Faktoren.
  RealColumn get ausbeuteFaktor => real().nullable()();

  // --- Wartezeit ---

  /// Pflicht-Wartezeit NACH diesem Schritt, bevor der nächste starten darf
  /// (z.B. Abkühlung 360 min, Brät ruhen 30 min). NULL/0 = sofort weiter.
  RealColumn get wartezeitMinuten => real().nullable()();

  // --- Chargengrößen / Maschinenkapazität ---

  /// Min. Chargengröße in kg für diesen Schritt (z.B. Kutter min 50 kg).
  RealColumn get minChargenKg => real().nullable()();

  /// Max. Chargengröße in kg (z.B. Kutter max 200 kg).
  /// Bei Überschreitung → mehrere Durchgänge nötig → Dauer multipliziert.
  RealColumn get maxChargenKg => real().nullable()();

  // --- HACCP / Temperatur ---

  /// Ziel-Kerntemperatur in °C (z.B. 72°C beim Garen). NULL = nicht relevant.
  RealColumn get kerntemperaturZiel => real().nullable()();

  /// Maximale Raumtemperatur in °C (z.B. 12°C beim Kuttern). NULL = nicht relevant.
  RealColumn get raumtemperaturMax => real().nullable()();

  // --- Maschine ---

  /// Freitext-Referenz auf die Maschine (z.B. "Kutter K200", "Bratstraße 2").
  /// Späterer Ausbau: FK auf Maschinen-Tabelle.
  TextColumn get maschine => text().nullable()();

  /// JSON-Objekt mit Maschineneinstellungen (z.B. {"temperatur": 72, "zeit_min": 45}).
  /// Bewusst frei, weil jede Abteilung andere Parameter hat. Strukturierte
  /// Validierung passiert in der Domain-Schicht.
  TextColumn get maschinenEinstellungenJson => text().nullable()();

  TextColumn get notizen => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
