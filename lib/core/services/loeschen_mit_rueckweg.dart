import 'package:drift/drift.dart';

import '../database/database.dart';

// Löschen mit Rückweg.
//
// Ein Bedarf, ein Auftrag im Board und eine erfasste Produktion werden beim
// Löschen nur als gelöscht markiert — die Zeile bleibt in der Datenbank.
// Deshalb fragt die App davor nicht mehr nach, sondern bietet danach
// „Rückgängig" an.
//
// Jede Funktion hier sagt, was sie wirklich gelöscht hat, und das
// Gegenstück holt genau das zurück. Was schon vorher gelöscht war, fasst
// keine von beiden an: Sonst käme mit dem Rückgängig etwas wieder, das
// jemand früher mit Absicht entfernt hat.

/// Löscht und holt zurück — siehe oben.
class LoeschenMitRueckweg {
  const LoeschenMitRueckweg._();

  /// Löscht den Bedarf [id]. `false`, wenn es ihn nicht gibt oder er schon
  /// gelöscht war.
  ///
  /// Aufträge, die für ihn schon im Board stehen, bleiben dort. Ein
  /// Planungsauftrag aus dem Auftragsbestand gibt seine Zeilen damit frei.
  static Future<bool> bedarf(
    AppDatabase db,
    String id, {
    DateTime? jetzt,
  }) async {
    final n = await (db.update(db.demands)
          ..where((b) => b.id.equals(id))
          ..where((b) => b.deletedAt.isNull()))
        .write(DemandsCompanion(deletedAt: Value(jetzt ?? DateTime.now())));
    return n > 0;
  }

  /// Holt den Bedarf [id] zurück.
  static Future<void> bedarfZurueck(AppDatabase db, String id) async {
    await (db.update(db.demands)..where((b) => b.id.equals(id)))
        .write(const DemandsCompanion(deletedAt: Value(null)));
  }

  /// Alle Aufträge der Kette, zu der [start] gehört — über
  /// [ProductionTask.parentTaskId] zur Wurzel hoch und von dort über alle
  /// Nachfahren. Getrennte Planungen desselben Artikels bleiben außen vor,
  /// weil sie eigene Ketten bilden. Gelöschte Aufträge zählen nicht.
  static Future<List<String>> kette(
    AppDatabase db,
    ProductionTask start,
  ) async {
    final alle = await (db.select(db.productionTasks)
          ..where((t) => t.productId.equals(start.productId))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final byId = {for (final t in alle) t.id: t};

    // Zur Wurzel hochlaufen.
    var root = start;
    final besucht = <String>{root.id};
    while (root.parentTaskId != null && byId.containsKey(root.parentTaskId)) {
      final parent = byId[root.parentTaskId]!;
      if (!besucht.add(parent.id)) break; // Zyklus-Schutz
      root = parent;
    }

    // Von der Wurzel alle Nachfahren einsammeln.
    final kette = <String>{root.id};
    var geaendert = true;
    while (geaendert) {
      geaendert = false;
      for (final t in alle) {
        final p = t.parentTaskId;
        if (p != null && kette.contains(p) && kette.add(t.id)) {
          geaendert = true;
        }
      }
    }
    return kette.toList();
  }

  /// Löscht die Aufträge [ids] aus der Planung. Zurück kommen die, die
  /// dabei wirklich gelöscht wurden — für [auftraegeZurueck].
  static Future<List<String>> auftraege(
    AppDatabase db,
    Iterable<String> ids, {
    DateTime? jetzt,
  }) {
    final wann = jetzt ?? DateTime.now();
    return db.transaction(() async {
      final da = await (db.select(db.productionTasks)
            ..where((t) => t.id.isIn(ids))
            ..where((t) => t.deletedAt.isNull()))
          .map((t) => t.id)
          .get();
      if (da.isEmpty) return const <String>[];
      await (db.update(db.productionTasks)..where((t) => t.id.isIn(da))).write(
        ProductionTasksCompanion(
          deletedAt: Value(wann),
          updatedAt: Value(wann),
        ),
      );
      return da;
    });
  }

  /// Holt die Aufträge [ids] in die Planung zurück — an ihren Tag, auf
  /// ihre Maschine, mit allem, was an ihnen eingetragen war.
  static Future<void> auftraegeZurueck(
    AppDatabase db,
    Iterable<String> ids, {
    DateTime? jetzt,
  }) async {
    final liste = ids.toList();
    if (liste.isEmpty) return;
    await (db.update(db.productionTasks)..where((t) => t.id.isIn(liste))).write(
      ProductionTasksCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(jetzt ?? DateTime.now()),
      ),
    );
  }

  /// Löscht die erfasste Produktion [id]. `false`, wenn es sie nicht gibt
  /// oder sie schon gelöscht war.
  static Future<bool> produktion(
    AppDatabase db,
    String id, {
    DateTime? jetzt,
  }) async {
    final wann = jetzt ?? DateTime.now();
    final n = await (db.update(db.productionHistory)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .write(
      ProductionHistoryCompanion(
        deletedAt: Value(wann),
        updatedAt: Value(wann),
      ),
    );
    return n > 0;
  }

  /// Holt die erfasste Produktion [id] zurück.
  static Future<void> produktionZurueck(
    AppDatabase db,
    String id, {
    DateTime? jetzt,
  }) async {
    await (db.update(db.productionHistory)..where((t) => t.id.equals(id)))
        .write(
      ProductionHistoryCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(jetzt ?? DateTime.now()),
      ),
    );
  }
}
