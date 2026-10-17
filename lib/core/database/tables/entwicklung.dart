import 'package:drift/drift.dart';

// Die Tabellen der Produktentwicklung.
//
// Alle SQL-Namen beginnen mit „entwicklung_" — daran erkennen Backup und
// „App zurücksetzen" sie (core/constants/entwicklung.dart). Im Backup
// stehen sie verschlüsselt in einem eigenen Teil.
//
// Bewusst ohne Fremdschlüssel: Ein Backup oder der Import aus der alten
// Suite spielt die Tabellen in beliebiger Reihenfolge ein, und eine
// gelöschte Zutat soll eine Rezeptur nicht blockieren, sondern dort als
// „fehlt" erscheinen. Abhängige Zeilen räumt der Code selbst ab.
//
// Strukturierte Teile, die nur als Ganzes gelesen und geschrieben werden
// (Sensorik, Checklisten, Prozessparameter, HACCP), liegen als JSON-Text
// in einer Spalte. Das hält das Schema schlank und erlaubt neue Felder ohne
// Migration.

/// Eine Zutat des Katalogs: Rohstoff mit Nährwerten, Allergenen und den
/// Angaben für Etikett und Fleischanteil. Nährwerte je 100 g.
@DataClassName('Zutat')
class EntwicklungZutaten extends Table {
  @override
  String get tableName => 'entwicklung_zutaten';

  TextColumn get id => text()();

  /// Interner Name, etwa „Schweinebauch S3".
  TextColumn get name => text()();

  TextColumn get artikelnummer => text().nullable()();

  /// Name auf dem Etikett, wenn er vom internen Namen abweicht.
  TextColumn get etikettName => text().nullable()();

  BoolColumn get istFleisch => boolean().withDefault(const Constant(false))();

  /// Zugesetztes Wasser oder Eis — zählt im Endprodukt nur mit dem, was
  /// nach dem Verlust übrig bleibt.
  BoolColumn get istWasser => boolean().withDefault(const Constant(false))();

  /// Tierart für den Fleischanteil, etwa „schwein" (siehe Rechenkern).
  TextColumn get tierart => text().nullable()();

  /// Bindegewebe als Verhältnis Kollagen zu Fleischeiweiß in Prozent.
  RealColumn get bindegewebe => real().nullable()();

  /// Fleischeiweißgrenze in Prozent — aus der alten Suite übernommen.
  RealColumn get fleischeiweissGrenze => real().nullable()();

  /// Ob die Zutat in der Zutatenliste mit Menge (QUID) erscheint.
  BoolColumn get quidPflicht => boolean().withDefault(const Constant(false))();

  /// Zusammengesetzte Zutat: was in Klammern dahinter steht.
  TextColumn get unterzutaten => text().nullable()();

  TextColumn get verarbeitungshilfsstoffe => text().nullable()();

  /// Allergene als Kommaliste der Planer-Werte (kAllergene).
  TextColumn get allergene => text().nullable()();

  RealColumn get energieKj => real().nullable()();
  RealColumn get energieKcal => real().nullable()();
  RealColumn get fett => real().nullable()();
  RealColumn get gesaettigteFettsaeuren => real().nullable()();
  RealColumn get kohlenhydrate => real().nullable()();
  RealColumn get zucker => real().nullable()();
  RealColumn get eiweiss => real().nullable()();
  RealColumn get salz => real().nullable()();
  RealColumn get wasser => real().nullable()();
  RealColumn get asche => real().nullable()();

  /// Bindegewebseiweißfreies Fleischeiweiß (BEFFE) in Prozent.
  RealColumn get beffe => real().nullable()();

  TextColumn get notiz => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Eine Rezeptur — der Kopf. Die Zusammensetzung steht in ihren
/// Versionen.
@DataClassName('Rezeptur')
class EntwicklungRezepturen extends Table {
  @override
  String get tableName => 'entwicklung_rezepturen';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get artikelnummer => text().nullable()();
  TextColumn get beschreibung => text().nullable()();

  /// Das Projekt, zu dem die Rezeptur gehört — null für Rezepturen der
  /// Bibliothek, etwa eine Marinade, die viele Produkte nutzen.
  TextColumn get projektId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ein Stand einer Rezeptur. Entwürfe lassen sich ändern; ein
/// abgeschlossener Stand ist eingefroren — mit allen Zutatendaten in
/// [stand], damit spätere Änderungen am Katalog ihn nicht verschieben.
@DataClassName('RezepturVersion')
class EntwicklungRezepturVersionen extends Table {
  @override
  String get tableName => 'entwicklung_rezeptur_versionen';

  TextColumn get id => text()();
  TextColumn get rezepturId => text()();

  /// 1, 2, 3 … je Rezeptur.
  IntColumn get nummer => integer()();

  /// Kurzer Name des Stands, etwa „Muster 2 für den Kunden".
  TextColumn get bezeichnung => text().nullable()();

  /// 'entwurf' oder 'abgeschlossen'.
  TextColumn get status => text().withDefault(const Constant('entwurf'))();

  /// Gesamtverlust in Prozent der eingesetzten Masse.
  RealColumn get verlustProzent => real().withDefault(const Constant(0))();

  /// Davon Fett in Prozent der eingesetzten Masse.
  RealColumn get fettVerlustProzent =>
      real().withDefault(const Constant(0))();

  /// 'trocknung', 'garen' oder 'keiner'.
  TextColumn get verlustArt =>
      text().withDefault(const Constant('trocknung'))();

  TextColumn get notiz => text().nullable()();

  /// Beim Abschließen: die vollständige Eingabe des Rechenkerns als JSON.
  TextColumn get stand => text().nullable()();

  DateTimeColumn get abgeschlossenAm => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Eine Zeile einer Rezeptur-Version: eine Zutat oder eine Unterrezeptur.
@DataClassName('RezepturPosition')
class EntwicklungRezepturPositionen extends Table {
  @override
  String get tableName => 'entwicklung_rezeptur_positionen';

  TextColumn get id => text()();
  TextColumn get versionId => text()();
  IntColumn get reihenfolge => integer().withDefault(const Constant(0))();

  /// Die Zutat — oder null bei einer Unterrezeptur.
  TextColumn get zutatId => text().nullable()();

  /// Die Unterrezeptur — oder null bei einer Zutat.
  TextColumn get unterrezepturId => text().nullable()();

  /// Ein bestimmter Stand der Unterrezeptur. null: ihr neuester.
  TextColumn get unterVersionId => text().nullable()();

  /// Menge in kg. Bei einer Unterrezeptur die eingesetzte fertige Menge.
  RealColumn get mengeKg => real().withDefault(const Constant(0))();

  /// Mengenangabe in der Zutatenliste — null: wie bei der Zutat.
  BoolColumn get quidPflicht => boolean().nullable()();

  /// Name auf dem Etikett nur für diese Rezeptur — null: wie bei der
  /// Zutat.
  TextColumn get etikettName => text().nullable()();

  TextColumn get notiz => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ein Entwicklungsprojekt: ein Produkt für einen Kunden, von der Idee bis
/// zur Freigabe als Artikel im Planer.
@DataClassName('EntwicklungsProjekt')
class EntwicklungProjekte extends Table {
  @override
  String get tableName => 'entwicklung_projekte';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kunde => text().nullable()();
  TextColumn get artikelnummer => text().nullable()();

  /// 'entwicklung', 'validierung', 'produktion' oder 'archiviert'.
  TextColumn get status => text().withDefault(const Constant('entwicklung'))();

  TextColumn get produktidee => text().nullable()();
  TextColumn get kundenvereinbarungen => text().nullable()();

  /// Schlüssel des Fließdiagramms aus [EntwicklungFliessdiagramme].
  TextColumn get fliessdiagramm => text().nullable()();

  BoolColumn get neuerProzess => boolean().withDefault(const Constant(false))();
  BoolColumn get neueZutaten => boolean().withDefault(const Constant(false))();
  TextColumn get neueZutatenDetails => text().nullable()();

  /// Zielwerte: Fett und Eiweiß in Prozent, Obergrenze aw-Wert.
  RealColumn get zielFett => real().nullable()();
  RealColumn get zielEiweiss => real().nullable()();
  RealColumn get grenzeAw => real().nullable()();

  TextColumn get notizen => text().nullable()();

  /// Produktbild — eine Datei aus [EntwicklungDateien].
  TextColumn get bildDateiId => text().nullable()();

  /// JSON: Aussehen, Geruch, Geschmack, Konsistenz, Maße, Zubereitung.
  TextColumn get sensorik => text().nullable()();

  /// JSON: erledigte Punkte der Projekt-Checkliste.
  TextColumn get checkliste => text().nullable()();

  /// JSON: erledigte Punkte der Etiketten-Checkliste.
  TextColumn get etikettCheckliste => text().nullable()();

  /// JSON: Prozessparameter nach Abschnitten.
  TextColumn get prozess => text().nullable()();

  /// JSON: frühere Stände der Prozessparameter.
  TextColumn get prozessHistorie => text().nullable()();

  /// JSON: Gefahrenanalyse (FMEA) und Lenkungspunkte (CCP).
  TextColumn get haccp => text().nullable()();

  /// Der Artikel im Planer (products.id), sobald freigegeben.
  TextColumn get artikelId => text().nullable()();

  /// Die freigegebene Rezeptur-Version.
  TextColumn get freigabeVersionId => text().nullable()();
  DateTimeColumn get freigegebenAm => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ein Eintrag im Verlauf eines Projekts: Meilenstein, Rezepturstand,
/// E-Mail, Parameter, Datei oder Notiz.
@DataClassName('ProjektEintrag')
class EntwicklungProjektEintraege extends Table {
  @override
  String get tableName => 'entwicklung_projekt_eintraege';

  TextColumn get id => text()();
  TextColumn get projektId => text()();

  /// 'meilenstein', 'rezeptur', 'email', 'parameter', 'datei' oder 'notiz'.
  TextColumn get art => text()();

  TextColumn get titel => text()();
  DateTimeColumn get datum => dateTime()();
  TextColumn get benutzer => text().nullable()();
  TextColumn get beschreibung => text().nullable()();

  /// 'erledigt', 'erhalten', 'ok' oder 'offen'.
  TextColumn get status => text().withDefault(const Constant('offen'))();

  /// Bei Parametern: gemessener Wert und Ziel.
  TextColumn get wert => text().nullable()();
  TextColumn get ziel => text().nullable()();

  /// JSON-Liste der Änderungen, etwa bei einem neuen Rezepturstand.
  TextColumn get aenderungen => text().nullable()();

  /// Angehängte Datei aus [EntwicklungDateien].
  TextColumn get dateiId => text().nullable()();

  /// Der Rezepturstand, um den es geht.
  TextColumn get versionId => text().nullable()();

  /// JSON-Liste der Kommentare: Name, Text, Datum.
  TextColumn get kommentare => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Eine angehängte Datei — die Angaben. Der Inhalt liegt verschlüsselt in
/// [EntwicklungDateiInhalte].
@DataClassName('EntwicklungsDatei')
class EntwicklungDateien extends Table {
  @override
  String get tableName => 'entwicklung_dateien';

  TextColumn get id => text()();
  TextColumn get projektId => text().nullable()();

  /// Dateiname mit Endung, etwa „Spezifikation Kunde.pdf".
  TextColumn get name => text()();

  TextColumn get mimeTyp => text().nullable()();

  /// Größe des Klartexts in Bytes.
  IntColumn get groesse => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Der Inhalt einer Datei, mit dem Datenschlüssel verschlüsselt. Eine
/// eigene Tabelle, damit Listen die Angaben laden, ohne die Inhalte
/// mitzuschleppen.
@DataClassName('DateiInhalt')
class EntwicklungDateiInhalte extends Table {
  @override
  String get tableName => 'entwicklung_datei_inhalte';

  TextColumn get dateiId => text()();
  BlobColumn get inhalt => blob()();

  @override
  Set<Column> get primaryKey => {dateiId};
}

/// Ein Fließdiagramm des Betriebs, etwa „FD_009 Bratstraßenartikel".
/// Die Liste pflegt jeder selbst — sie gehört nicht ins öffentliche Repo.
@DataClassName('Fliessdiagramm')
class EntwicklungFliessdiagramme extends Table {
  @override
  String get tableName => 'entwicklung_fliessdiagramme';

  /// Kürzel, etwa „FD_009".
  TextColumn get id => text()();

  TextColumn get bezeichnung => text()();
  IntColumn get sortierung => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
