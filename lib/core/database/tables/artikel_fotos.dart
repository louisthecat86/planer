import 'package:drift/drift.dart';

/// Ein Foto zu einem Artikel — an der Anlage mit der App „Planer
/// Erfassung" aufgenommen oder am PC hinzugefügt. Hier stehen die Angaben;
/// das Bild selbst liegt in [ArtikelFotoInhalte].
///
/// Fotos sind klein gehalten (längere Kante 1600 px, JPEG): Sie sollen das
/// Produkt zeigen, nicht die Datenbank füllen.
@DataClassName('ArtikelFoto')
class ArtikelFotos extends Table {
  @override
  String get tableName => 'artikel_fotos';

  /// UUID — bei Fotos vom Handy die ID aus der Ergebnis-Datei: Wird
  /// dieselbe Datei zweimal eingelesen, kommt kein Foto doppelt.
  TextColumn get id => text()();

  /// Der Artikel (`products.id`).
  TextColumn get productId => text()();

  /// Wann das Foto aufgenommen wurde.
  DateTimeColumn get aufgenommenAm => dateTime()();

  /// Freiwillige Bemerkung zum Foto.
  TextColumn get bezeichnung => text().nullable()();

  /// Wer es aufgenommen hat.
  TextColumn get kuerzel => text().nullable()();

  /// Das Referenzbild des Artikels: So soll das Produkt aussehen. Je
  /// Artikel höchstens eins.
  BoolColumn get istReferenz => boolean().withDefault(const Constant(false))();

  /// Größe des Bilds in Bytes.
  IntColumn get groesse => integer().withDefault(const Constant(0))();

  /// SHA-256 des Bilds — unter diesem Namen liegt es in der Ablage neben
  /// den Backups, statt in jedem Auto-Backup ganz.
  TextColumn get pruefsumme => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Das Bild eines Fotos als JPEG. Eine eigene Tabelle, damit Listen die
/// Angaben laden, ohne die Bilder mitzuschleppen.
@DataClassName('ArtikelFotoInhalt')
class ArtikelFotoInhalte extends Table {
  @override
  String get tableName => 'artikel_foto_inhalte';

  TextColumn get fotoId => text()();
  BlobColumn get inhalt => blob()();

  @override
  Set<Column> get primaryKey => {fotoId};
}
