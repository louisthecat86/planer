import 'package:drift/drift.dart';

import '../database/database.dart';

/// Die Tabellen der Produktentwicklung als Ganzes: lesen, leeren,
/// schreiben — für das verschlüsselte Backup und den Import.
///
/// Die Dateiinhalte laufen getrennt: Sie liegen schon verschlüsselt in der
/// Datenbank und wandern unverändert ins Backup, statt ein zweites Mal
/// verschlüsselt zu werden.
class EntwicklungDaten {
  EntwicklungDaten._();

  /// Version des Formats von [lesen]. Steigt, wenn sich die Bedeutung
  /// eines Felds ändert; neue Felder brauchen keine neue Version.
  static const int format = 1;

  /// Alle Zeilen als JSON-fähige Liste je Tabelle.
  static Future<Map<String, Object?>> lesen(AppDatabase db) async => {
        'format': format,
        'zutaten': [
          for (final z in await db.select(db.entwicklungZutaten).get())
            z.toJson(),
        ],
        'rezepturen': [
          for (final r in await db.select(db.entwicklungRezepturen).get())
            r.toJson(),
        ],
        'versionen': [
          for (final v
              in await db.select(db.entwicklungRezepturVersionen).get())
            v.toJson(),
        ],
        'positionen': [
          for (final p
              in await db.select(db.entwicklungRezepturPositionen).get())
            p.toJson(),
        ],
        'projekte': [
          for (final p in await db.select(db.entwicklungProjekte).get())
            p.toJson(),
        ],
        'eintraege': [
          for (final e
              in await db.select(db.entwicklungProjektEintraege).get())
            e.toJson(),
        ],
        'dateien': [
          for (final d in await db.select(db.entwicklungDateien).get())
            d.toJson(),
        ],
        'fliessdiagramme': [
          for (final f
              in await db.select(db.entwicklungFliessdiagramme).get())
            f.toJson(),
        ],
      };

  /// Die verschlüsselten Dateiinhalte je Datei.
  static Future<Map<String, Uint8List>> dateiInhalte(AppDatabase db) async =>
      {
        for (final i in await db.select(db.entwicklungDateiInhalte).get())
          i.dateiId: i.inhalt,
      };

  /// Ob es auf diesem Rechner Entwicklungsdaten gibt.
  static Future<bool> vorhanden(AppDatabase db) async {
    for (final tabelle in _tabellen(db)) {
      final zeile = await (db.select(tabelle)..limit(1)).getSingleOrNull();
      if (zeile != null) return true;
    }
    return false;
  }

  /// Löscht alle Zeilen aller Tabellen der Produktentwicklung.
  static Future<void> leeren(AppDatabase db) async {
    for (final tabelle in _tabellen(db)) {
      await db.delete(tabelle).go();
    }
  }

  /// Schreibt [daten] (Aufbau wie bei [lesen]) und [inhalte] in die
  /// Tabellen. Vorhandene Zeilen mit derselben ID werden ersetzt; zum
  /// vollständigen Ersetzen vorher [leeren].
  static Future<void> schreiben(
    AppDatabase db,
    Map<String, dynamic> daten,
    Map<String, Uint8List> inhalte,
  ) async {
    List<Map<String, dynamic>> zeilen(String schluessel) {
      final liste = daten[schluessel];
      if (liste is! List) return const [];
      return [
        for (final z in liste)
          if (z is Map<String, dynamic>) z,
      ];
    }

    await db.batch((b) {
      b.insertAll(
        db.entwicklungZutaten,
        [
          for (final z in zeilen('zutaten'))
            Zutat.fromJson(z).toCompanion(true),
        ],
        mode: InsertMode.insertOrReplace,
      );
      b.insertAll(
        db.entwicklungRezepturen,
        [
          for (final z in zeilen('rezepturen'))
            Rezeptur.fromJson(z).toCompanion(true),
        ],
        mode: InsertMode.insertOrReplace,
      );
      b.insertAll(
        db.entwicklungRezepturVersionen,
        [
          for (final z in zeilen('versionen'))
            RezepturVersion.fromJson(z).toCompanion(true),
        ],
        mode: InsertMode.insertOrReplace,
      );
      b.insertAll(
        db.entwicklungRezepturPositionen,
        [
          for (final z in zeilen('positionen'))
            RezepturPosition.fromJson(z).toCompanion(true),
        ],
        mode: InsertMode.insertOrReplace,
      );
      b.insertAll(
        db.entwicklungProjekte,
        [
          for (final z in zeilen('projekte'))
            EntwicklungsProjekt.fromJson(z).toCompanion(true),
        ],
        mode: InsertMode.insertOrReplace,
      );
      b.insertAll(
        db.entwicklungProjektEintraege,
        [
          for (final z in zeilen('eintraege'))
            ProjektEintrag.fromJson(z).toCompanion(true),
        ],
        mode: InsertMode.insertOrReplace,
      );
      b.insertAll(
        db.entwicklungDateien,
        [
          for (final z in zeilen('dateien'))
            EntwicklungsDatei.fromJson(z).toCompanion(true),
        ],
        mode: InsertMode.insertOrReplace,
      );
      b.insertAll(
        db.entwicklungFliessdiagramme,
        [
          for (final z in zeilen('fliessdiagramme'))
            Fliessdiagramm.fromJson(z).toCompanion(true),
        ],
        mode: InsertMode.insertOrReplace,
      );
      b.insertAll(
        db.entwicklungDateiInhalte,
        [
          for (final MapEntry(:key, :value) in inhalte.entries)
            EntwicklungDateiInhalteCompanion.insert(
              dateiId: key,
              inhalt: value,
            ),
        ],
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  static List<TableInfo<Table, Object?>> _tabellen(AppDatabase db) => [
        db.entwicklungZutaten,
        db.entwicklungRezepturen,
        db.entwicklungRezepturVersionen,
        db.entwicklungRezepturPositionen,
        db.entwicklungProjekte,
        db.entwicklungProjektEintraege,
        db.entwicklungDateien,
        db.entwicklungDateiInhalte,
        db.entwicklungFliessdiagramme,
      ];
}
