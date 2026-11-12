import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../providers/daten_waechter.dart';
import '../providers/database_provider.dart';
import 'navision_import_service.dart';

// Der Stand der Navision-Artikelübersicht in der App.
//
// Beim Einlesen der Übersicht merkt sich die App je Artikelnummer, was
// Navision dazu sagt (Tabelle `navision_artikel`). Daraus liest sie, was
// sie selbst nicht pflegt — zuerst: ob ein Artikel noch ein Muster ist.

/// Ob [nummer2] — die Spalte „Nummer 2" der Artikelübersicht — den Artikel
/// als Muster kennzeichnet: Das Wort „Muster" steht darin, egal wie
/// geschrieben und was sonst noch dabeisteht.
bool istMusterKennung(String? nummer2) =>
    nummer2 != null && nummer2.toLowerCase().contains('muster');

/// Schreibt und liest den Stand der Artikelübersicht.
class NavisionKatalogSpeicher {
  const NavisionKatalogSpeicher._();

  /// Merkt sich den [katalog]. Zurück kommt die Zahl der Zeilen.
  ///
  /// Ergänzend: Artikel, die in dieser Übersicht nicht stehen, bleiben
  /// wie sie sind — eine gefilterte Übersicht löscht nichts. Fehlt der
  /// Übersicht die Spalte „Nummer 2", bleibt bei schon bekannten Artikeln
  /// auch die Muster-Kennzeichnung stehen.
  static Future<int> merken(
    AppDatabase db,
    NavisionKatalog katalog, {
    DateTime? jetzt,
  }) async {
    final wann = jetzt ?? DateTime.now();
    await db.batch((b) {
      b.insertAllOnConflictUpdate(db.navisionArtikel, [
        for (final z in katalog.zeilen)
          NavisionArtikelCompanion(
            artikelnummer: Value(z.nummer),
            // Ohne die Spalte: nicht anfassen, statt zu leeren.
            nummer2:
                katalog.mitNummer2 ? Value(z.nummer2) : const Value.absent(),
            beschreibung: Value(z.beschreibung),
            beschreibung2: Value(z.beschreibung2),
            suchbegriff: Value(z.suchbegriff),
            basiseinheit: Value(z.basiseinheit),
            produktbuchungsgruppe: Value(z.produktbuchungsgruppe),
            artikelkategorie: Value(z.artikelkategorie),
            produktgruppe: Value(z.produktgruppe),
            eingelesenAm: Value(wann),
          ),
      ]);
    });
    return katalog.zeilen.length;
  }

  /// Die Artikelnummern, die Navision als Muster führt.
  static Future<Set<String>> musterNummern(AppDatabase db) async {
    final zeilen = await (db.select(db.navisionArtikel)
          ..where((a) => a.nummer2.isNotNull()))
        .get();
    return {
      for (final z in zeilen)
        if (istMusterKennung(z.nummer2)) z.artikelnummer,
    };
  }

  // ── Backup ───────────────────────────────────────────────────────────

  /// Schlüssel im Datenteil des Backups (ab Backup-Version 1.9).
  static const String kSchluessel = 'navision_artikel';

  /// Der Stand fürs Backup — auch leer: Daran erkennt das Einspielen,
  /// dass dieses Backup ihn kennt.
  static Future<Map<String, Object?>> exportieren(AppDatabase db) async => {
        kSchluessel: [
          for (final z in await db.select(db.navisionArtikel).get()) z.toJson(),
        ],
      };

  /// Ob der Datenteil [data] eines Backups den Stand enthält.
  static bool enthalten(Map<String, dynamic> data) => data[kSchluessel] is List;

  /// Spielt den Stand aus [data] ein. Mit [ersetzen] steht danach genau
  /// der aus dem Backup da. Kennt das Backup ihn nicht (vor 1.9),
  /// geschieht nichts — der Stand des Rechners bleibt.
  static Future<void> einspielen(
    AppDatabase db,
    Map<String, dynamic> data, {
    bool ersetzen = true,
  }) async {
    if (!enthalten(data)) return;
    if (ersetzen) await db.delete(db.navisionArtikel).go();
    await db.batch((b) {
      b.insertAllOnConflictUpdate(db.navisionArtikel, [
        for (final z in data[kSchluessel] as List)
          if (z is Map<String, dynamic>)
            NavisionArtikelZeile.fromJson(z).toCompanion(true),
      ]);
    });
  }
}

/// Die Artikelnummern, die Navision als Muster führt — hält sich selbst
/// aktuell, wenn eine Übersicht eingelesen wird.
final musterNummernProvider = FutureProvider<Set<String>>((ref) async {
  final db = ref.watch(databaseProvider);
  neuLadenBeiAenderung(ref, db, tabellen: [db.navisionArtikel]);
  return NavisionKatalogSpeicher.musterNummern(db);
});
