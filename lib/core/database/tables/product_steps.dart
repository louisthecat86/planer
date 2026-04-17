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
  RealColumn get dauerStdAbweichung => real().nullable()();

  IntColumn get basisMitarbeiter => integer()();

  /// Anzahl der Runs, aus denen die Basis-Werte berechnet wurden.
  IntColumn get basisAnzahlMessungen =>
      integer().withDefault(const Constant(0))();

  // --- Ausbeute / Verluste ---

  /// Ausbeute-Faktor dieses Schritts: 0.88 = 12% Verlust.
  RealColumn get ausbeuteFaktor => real().nullable()();

  // --- Wartezeit ---

  /// Pflicht-Wartezeit NACH diesem Schritt (z.B. Abkühlung, Reifung).
  RealColumn get wartezeitMinuten => real().nullable()();

  // --- Chargengrößen / Maschinenkapazität ---

  RealColumn get minChargenKg => real().nullable()();
  RealColumn get maxChargenKg => real().nullable()();

  // --- HACCP / Temperatur ---

  RealColumn get kerntemperaturZiel => real().nullable()();
  RealColumn get raumtemperaturMax => real().nullable()();

  // --- Maschine ---

  /// Freitext-Referenz auf die Maschine.
  TextColumn get maschine => text().nullable()();

  /// JSON mit Maschineneinstellungen.
  TextColumn get maschinenEinstellungenJson => text().nullable()();

  // --- Programm-spezifisch (Phase A-Erweiterung) ---

  /// Kochkammer-Programm-Nr oder -Name (wenn Abteilung = Wurstküche).
  TextColumn get kochkammerProgramm => text().nullable()();

  /// Klimaprogramm-Nr oder -Name (wenn Rohwurst/Rohpökel-Reifung).
  TextColumn get klimaprogramm => text().nullable()();

  /// Bratparameter als Freitext (z.B. "220°C oben / 180°C unten, 4 min").
  TextColumn get bratparameter => text().nullable()();

  TextColumn get notizen => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}