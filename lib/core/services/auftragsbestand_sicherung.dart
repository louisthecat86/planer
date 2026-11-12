import '../database/database.dart';

// Der Auftragsbestand im Backup (ab Backup-Version 1.8): der zuletzt
// eingelesene Navision-Bericht — Artikel und Positionen — und der Stand
// davor, aus dem „Änderungen" den Vergleich zieht.
//
// Vorher stand er nicht im Backup: Nach einem Wiederherstellen passte er
// nicht mehr zum gesicherten Board und Bedarf, und auf einem neuen Rechner
// fehlte er, bis der Bericht neu eingelesen war.
//
// Ein älteres Backup kennt ihn nicht. Es lässt den Auftragsbestand des
// Rechners deshalb, wie er ist — statt ihn zu leeren.

/// Ausfuhr und Einfuhr des Auftragsbestands im Backup.
class AuftragsbestandSicherung {
  AuftragsbestandSicherung._();

  static const String kArtikel = 'auftragsbestand_artikel';
  static const String kPositionen = 'auftragsbestand_positionen';
  static const String kArtikelVorher = 'auftragsbestand_artikel_vorher';
  static const String kPositionenVorher = 'auftragsbestand_positionen_vorher';

  /// Die vier Tabellen fürs Backup — auch leer: Daran erkennt das
  /// Einspielen, dass dieses Backup den Auftragsbestand kennt.
  static Future<Map<String, Object?>> exportieren(AppDatabase db) async => {
        kArtikel: [
          for (final z in await db.select(db.auftragsbestandArtikel).get())
            z.toJson(),
        ],
        kPositionen: [
          for (final z in await db.select(db.auftragsbestandPositionen).get())
            z.toJson(),
        ],
        kArtikelVorher: [
          for (final z
              in await db.select(db.auftragsbestandArtikelVorher).get())
            z.toJson(),
        ],
        kPositionenVorher: [
          for (final z
              in await db.select(db.auftragsbestandPositionenVorher).get())
            z.toJson(),
        ],
      };

  /// Ob der Datenteil [data] eines Backups den Auftragsbestand enthält.
  static bool enthalten(Map<String, dynamic> data) =>
      data[kArtikel] is List && data[kPositionen] is List;

  /// Spielt den Auftragsbestand aus [data] ein. Mit [ersetzen] steht danach
  /// genau der aus dem Backup da. Kennt das Backup ihn nicht, geschieht
  /// nichts — der Auftragsbestand des Rechners bleibt.
  static Future<void> einspielen(
    AppDatabase db,
    Map<String, dynamic> data, {
    bool ersetzen = true,
  }) async {
    if (!enthalten(data)) return;
    if (ersetzen) {
      await db.delete(db.auftragsbestandPositionen).go();
      await db.delete(db.auftragsbestandArtikel).go();
      await db.delete(db.auftragsbestandPositionenVorher).go();
      await db.delete(db.auftragsbestandArtikelVorher).go();
    }
    List<Map<String, dynamic>> zeilen(String schluessel) => [
          for (final z in data[schluessel] as List? ?? const <Object?>[])
            if (z is Map<String, dynamic>) z,
        ];
    await db.batch((b) {
      b
        ..insertAllOnConflictUpdate(db.auftragsbestandArtikel, [
          for (final z in zeilen(kArtikel))
            AuftragsArtikel.fromJson(z).toCompanion(true),
        ])
        ..insertAllOnConflictUpdate(db.auftragsbestandPositionen, [
          for (final z in zeilen(kPositionen))
            AuftragsPosition.fromJson(z).toCompanion(true),
        ])
        ..insertAllOnConflictUpdate(db.auftragsbestandArtikelVorher, [
          for (final z in zeilen(kArtikelVorher))
            AuftragsArtikelVorher.fromJson(z).toCompanion(true),
        ])
        ..insertAllOnConflictUpdate(db.auftragsbestandPositionenVorher, [
          for (final z in zeilen(kPositionenVorher))
            AuftragsPositionVorher.fromJson(z).toCompanion(true),
        ]);
    });
  }
}
