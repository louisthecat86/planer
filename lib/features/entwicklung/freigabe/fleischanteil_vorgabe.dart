import 'package:drift/drift.dart';

import '../../../core/database/database.dart';
import '../daten/entwicklung_repository.dart';
import '../rechenkern/rechenkern.dart';

/// Der Fleischanteil der Rohware nach der freigegebenen Rezeptur eines
/// Artikels, als Bruchteil (0…1): das roh eingewogene Fleisch unter allen
/// Rohstoffen, auch denen in Unterrezepturen. null, wenn der Artikel nicht
/// aus einer Freigabe stammt oder seine Rezeptur kein Fleisch hat.
///
/// Die Planung nimmt ihn, solange für den Artikel keine Produktion mit
/// Fleischeinwaage erfasst ist — wie den Verlust der Rezeptur
/// (core/services/entwicklung_vorgabe.dart).
Future<double?> fleischanteilAusEntwicklung(
  AppDatabase db,
  String productId,
) async {
  final projekte = await (db.select(db.entwicklungProjekte)
        ..where((p) => p.artikelId.equals(productId))
        ..where((p) => p.deletedAt.isNull())
        ..where((p) => p.freigabeVersionId.isNotNull())
        ..orderBy([(p) => OrderingTerm.desc(p.freigegebenAm)]))
      .get();
  final repo = EntwicklungRepository(db);
  for (final p in projekte) {
    final rezeptur = await repo.rechenRezeptur(p.freigabeVersionId!);
    if (rezeptur == null) continue;
    final ergebnis = berechne(rezeptur);
    if (ergebnis.rohmasseKg <= 0 || ergebnis.fleischRohKg <= 0) continue;
    return ergebnis.fleischRohKg / ergebnis.rohmasseKg;
  }
  return null;
}
