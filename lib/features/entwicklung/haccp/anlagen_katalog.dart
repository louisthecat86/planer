import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import 'prozess_kette.dart';
import 'prozess_modell.dart';

// Was die Prozesskette eines Projekts aus der Planung liest: den Katalog
// der Anlagen mit ihren Steckbriefen, die Grenzen der Werte und die Ketten
// der Artikel — zum Übernehmen in ein Projekt. Geschrieben wird hier
// nichts.

/// Die Anlagen des Katalogs mit ihren Steckbriefen, nach Namen.
Future<List<KatalogAnlage>> anlagenLaden(AppDatabase db) async {
  final maschinen = await (db.select(db.machines)
        ..where((m) => m.deletedAt.isNull())
        ..orderBy([(m) => OrderingTerm.asc(m.name)]))
      .get();
  final felder = await (db.select(db.machineParameterDefs)
        ..where((d) => d.deletedAt.isNull())
        ..orderBy([
          (d) => OrderingTerm.asc(d.sortierung),
          (d) => OrderingTerm.asc(d.parameterName),
        ]))
      .get();
  final jeAnlage = <String, List<SteckbriefFeld>>{};
  for (final d in felder) {
    // Die Platten verwaltet das Schema, nicht der Steckbrief.
    if (istVersteckterParameter(d.parameterName)) continue;
    jeAnlage
        .putIfAbsent(d.maschineId, () => [])
        .add(SteckbriefFeld(d.parameterName, einheit: d.einheit ?? ''));
  }
  return [
    for (final m in maschinen)
      KatalogAnlage(
        id: m.id,
        name: m.name,
        abteilung: m.abteilung,
        steckbrief: jeAnlage[m.id] ?? const [],
      ),
  ];
}

/// Die Grenzen der Werte aus den Einstellungen der Planung.
Future<GrenzenKatalog> grenzenLaden(AppDatabase db) async {
  final zeilen = await (db.select(db.parameterGrenzen)
        ..where((g) => g.deletedAt.isNull()))
      .get();
  return GrenzenKatalog({
    for (final g in zeilen)
      GrenzenKatalog.schluessel(g.kontext, g.parameterName): ParameterGrenze(
        hartMin: g.hartMin,
        hartMax: g.hartMax,
        weichMin: g.weichMin,
        weichMax: g.weichMax,
      ),
  });
}

/// Ein Artikel mit Prozesskette — zur Wahl beim Übernehmen.
class ArtikelMitKette {
  const ArtikelMitKette({
    required this.id,
    required this.nummer,
    required this.bezeichnung,
    required this.schritte,
  });

  final String id;
  final String nummer;
  final String bezeichnung;

  /// Wie viele Schritte seine Kette hat.
  final int schritte;
}

/// Die Artikel, die eine Prozesskette haben — nach Artikelnummer.
Future<List<ArtikelMitKette>> artikelMitKetteLaden(AppDatabase db) async {
  final artikel = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.artikelnummer)]))
      .get();
  final schritte = await (db.select(db.productSteps)
        ..where((s) => s.deletedAt.isNull()))
      .get();
  final anzahl = <String, int>{};
  for (final s in schritte) {
    anzahl[s.productId] = (anzahl[s.productId] ?? 0) + 1;
  }
  return [
    for (final a in artikel)
      if ((anzahl[a.id] ?? 0) > 0)
        ArtikelMitKette(
          id: a.id,
          nummer: a.artikelnummer,
          bezeichnung: a.artikelbezeichnung,
          schritte: anzahl[a.id]!,
        ),
  ];
}

/// Die Kette des Artikels [productId] als Schritte eines Projekts — mit
/// neuen IDs aus [neueId], ohne Personen und Leistungsdaten (F33).
Future<List<ProzessSchritt>> ketteAusArtikel(
  AppDatabase db,
  String productId, {
  required List<KatalogAnlage> katalog,
  required String Function() neueId,
}) async {
  final schritte = await (db.select(db.productSteps)
        ..where((s) => s.productId.equals(productId))
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
      .get();
  if (schritte.isEmpty) return const [];
  final parameter = await (db.select(db.productStepParameters)
        ..where((p) => p.stepId.isIn([for (final s in schritte) s.id]))
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.reihenfolge)]))
      .get();
  final jeSchritt = <String, List<ArtikelParameter>>{};
  for (final p in parameter) {
    jeSchritt.putIfAbsent(p.stepId, () => []).add(
      (
        gruppe: p.parameterGruppe,
        name: p.parameterName,
        wert: p.wert,
        eigen: p.istCustom,
      ),
    );
  }
  final nachId = {for (final k in katalog) k.id: k};
  return [
    for (final s in schritte)
      schrittAusArtikel(
        id: neueId(),
        abteilung: s.abteilung,
        maschineId: s.maschineId,
        maschine: s.maschine,
        prozessschritt: s.prozessschritt,
        parameter: jeSchritt[s.id] ?? const [],
        anlage: s.maschineId == null ? null : nachId[s.maschineId],
      ),
  ];
}

/// Liest aus der Planung, was die Kette eines Projekts braucht — ein
/// Baustein, den Tests ersetzen.
class AnlagenQuelle {
  const AnlagenQuelle(this._db);

  final AppDatabase _db;

  Future<List<KatalogAnlage>> anlagen() => anlagenLaden(_db);

  Future<GrenzenKatalog> grenzen() => grenzenLaden(_db);

  Future<List<ArtikelMitKette>> artikel() => artikelMitKetteLaden(_db);

  Future<List<ProzessSchritt>> kette(
    String productId, {
    required List<KatalogAnlage> katalog,
    required String Function() neueId,
  }) =>
      ketteAusArtikel(_db, productId, katalog: katalog, neueId: neueId);
}

final anlagenQuelleProvider = Provider<AnlagenQuelle>(
  (ref) => AnlagenQuelle(ref.watch(databaseProvider)),
);

/// Der Katalog der Anlagen — für die Kette im Reiter „Herstellung".
final anlagenKatalogProvider = FutureProvider.autoDispose<List<KatalogAnlage>>(
  (ref) => ref.watch(anlagenQuelleProvider).anlagen(),
);

/// Die Grenzen der Werte — für die Eingabe eines Werts.
final parameterGrenzenProvider = FutureProvider.autoDispose<GrenzenKatalog>(
  (ref) => ref.watch(anlagenQuelleProvider).grenzen(),
);

/// Die Artikel mit Prozesskette — für „Aus einem Artikel übernehmen…".
final artikelMitKetteProvider =
    FutureProvider.autoDispose<List<ArtikelMitKette>>(
  (ref) => ref.watch(anlagenQuelleProvider).artikel(),
);
