import 'package:drift/drift.dart';

import '../database/database.dart';

/// Der Verlust, mit dem die Planung einen Artikel aus der
/// Produktentwicklung rechnen kann, solange noch keine Produktion mit
/// Fertigware erfasst ist: der Verlust des freigegebenen Rezepturstands,
/// in Prozent. null, wenn der Artikel nicht aus einer Freigabe stammt oder
/// der Stand keinen Verlust hat (auch bei „kein Verlust").
///
/// Bewusst nicht aus der alten Spalte `gesamtAusbeuteFaktor` des Artikels:
/// Was dort aus früheren Versionen noch steht, soll die Planung nicht
/// verändern (siehe schrittplan_test).
Future<double?> verlustVorgabeAusEntwicklung(
  AppDatabase db,
  String productId,
) async {
  final projekte = await (db.select(db.entwicklungProjekte)
        ..where((p) => p.artikelId.equals(productId))
        ..where((p) => p.deletedAt.isNull())
        ..where((p) => p.freigabeVersionId.isNotNull())
        ..orderBy([(p) => OrderingTerm.desc(p.freigegebenAm)]))
      .get();
  for (final p in projekte) {
    final v = await (db.select(db.entwicklungRezepturVersionen)
          ..where((v) => v.id.equals(p.freigabeVersionId!)))
        .getSingleOrNull();
    // „Kein Verlust" (Verlustart.keiner): Ein eingetragener Wert bleibt
    // stehen, zählt aber nicht — auch der Rechenkern rechnet ohne.
    if (v == null || v.verlustArt == 'keiner') continue;
    final prozent = v.verlustProzent;
    if (prozent > 0 && prozent < 100) return prozent;
  }
  return null;
}
