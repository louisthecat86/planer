import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../rechenkern/rechen_modell.dart';
import '../rechenkern/rechenkern.dart';

// Daten der Produktentwicklung: Zutaten und Rezepturen lesen und
// schreiben — und Rezepturen so laden, wie der Rechenkern sie braucht.

/// Status eines Rezepturstands.
abstract final class VersionStatus {
  static const String entwurf = 'entwurf';
  static const String abgeschlossen = 'abgeschlossen';
}

/// Sortiert nach Namen, ohne auf Groß- und Kleinschreibung zu achten.
int nachName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Eine Zutat aus dem Katalog, wie der Rechenkern sie braucht.
RechenZutat rechenZutatAus(Zutat z) => RechenZutat(
      id: z.id,
      name: z.name,
      etikettName: z.etikettName,
      istFleisch: z.istFleisch,
      istWasser: z.istWasser,
      tierart: Tierart.aus(z.tierart),
      bindegewebe: z.bindegewebe,
      quidPflicht: z.quidPflicht,
      unterzutaten: z.unterzutaten,
      verarbeitungshilfsstoffe: [
        for (final h in (z.verarbeitungshilfsstoffe ?? '').split(RegExp('[,;]')))
          if (h.trim().isNotEmpty) h.trim(),
      ],
      allergene: merkmaleAusText(z.allergene),
      naehrwerte: Naehrwerte(
        energieKj: z.energieKj,
        energieKcal: z.energieKcal,
        fett: z.fett,
        gesaettigteFettsaeuren: z.gesaettigteFettsaeuren,
        kohlenhydrate: z.kohlenhydrate,
        zucker: z.zucker,
        eiweiss: z.eiweiss,
        salz: z.salz,
        wasser: z.wasser,
        asche: z.asche,
        beffe: z.beffe,
      ),
    );

/// Lesen und Schreiben der Entwicklungstabellen.
class EntwicklungRepository {
  EntwicklungRepository(this._db);

  final AppDatabase _db;
  static const Uuid _uuid = Uuid();

  // ── Zutaten ─────────────────────────────────────────────────────────

  /// Alle Zutaten, die nicht gelöscht sind, nach Namen.
  Stream<List<Zutat>> zutatenBeobachten() =>
      (_db.select(_db.entwicklungZutaten)..where((z) => z.deletedAt.isNull()))
          .watch()
          .map((liste) => [...liste]..sort((a, b) => nachName(a.name, b.name)));

  /// Alle Zutaten, auch gelöschte — für Rezepturen, die sie noch nutzen.
  Stream<Map<String, Zutat>> alleZutatenBeobachten() =>
      _db.select(_db.entwicklungZutaten).watch().map(
            (liste) => {for (final z in liste) z.id: z},
          );

  /// Eine Zutat — auch eine gelöschte, damit alte Rezepturen sie zeigen.
  Future<Zutat?> zutat(String id) => (_db.select(_db.entwicklungZutaten)
        ..where((z) => z.id.equals(id)))
      .getSingleOrNull();

  /// Legt eine Zutat an und gibt ihre ID zurück.
  Future<String> zutatAnlegen(EntwicklungZutatenCompanion daten) async {
    final id = _uuid.v4();
    await _db.into(_db.entwicklungZutaten).insert(
          daten.copyWith(
            id: Value(id),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
    return id;
  }

  Future<void> zutatAendern(String id, EntwicklungZutatenCompanion daten) =>
      (_db.update(_db.entwicklungZutaten)..where((z) => z.id.equals(id)))
          .write(daten.copyWith(updatedAt: Value(DateTime.now())));

  /// Markiert eine Zutat als gelöscht. Rezepturen, die sie nutzen, rechnen
  /// weiter mit ihr und zeigen sie als gelöscht.
  Future<void> zutatLoeschen(String id) =>
      (_db.update(_db.entwicklungZutaten)..where((z) => z.id.equals(id)))
          .write(
        EntwicklungZutatenCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// In wie vielen Rezepturständen die Zutat steht.
  Future<int> zutatVerwendungen(String id) async {
    final zeilen = await (_db.select(_db.entwicklungRezepturPositionen)
          ..where((p) => p.zutatId.equals(id)))
        .get();
    return zeilen.map((p) => p.versionId).toSet().length;
  }

  // ── Rezepturen ──────────────────────────────────────────────────────

  Stream<List<Rezeptur>> rezepturenBeobachten() =>
      (_db.select(_db.entwicklungRezepturen)
            ..where((r) => r.deletedAt.isNull()))
          .watch()
          .map((liste) => [...liste]..sort((a, b) => nachName(a.name, b.name)));

  /// Alle Rezepturen, auch gelöschte — für Unterrezepturen.
  Stream<Map<String, Rezeptur>> alleRezepturenBeobachten() =>
      _db.select(_db.entwicklungRezepturen).watch().map(
            (liste) => {for (final r in liste) r.id: r},
          );

  Stream<Rezeptur?> rezepturBeobachten(String id) =>
      (_db.select(_db.entwicklungRezepturen)..where((r) => r.id.equals(id)))
          .watchSingleOrNull();

  Future<Rezeptur?> rezeptur(String id) => (_db.select(_db.entwicklungRezepturen)
        ..where((r) => r.id.equals(id)))
      .getSingleOrNull();

  /// Alle Stände aller Rezepturen — für Listen, die den neuesten zeigen.
  Stream<List<RezepturVersion>> alleVersionenBeobachten() =>
      _db.select(_db.entwicklungRezepturVersionen).watch();

  /// Die Stände einer Rezeptur, der neueste zuerst.
  Stream<List<RezepturVersion>> versionenBeobachten(String rezepturId) =>
      (_db.select(_db.entwicklungRezepturVersionen)
            ..where((v) => v.rezepturId.equals(rezepturId))
            ..orderBy([(v) => OrderingTerm.desc(v.nummer)]))
          .watch();

  Future<RezepturVersion?> version(String id) =>
      (_db.select(_db.entwicklungRezepturVersionen)
            ..where((v) => v.id.equals(id)))
          .getSingleOrNull();

  /// Der neueste Stand einer Rezeptur — null, wenn sie keinen hat.
  Future<RezepturVersion?> neuesteVersion(String rezepturId) =>
      (_db.select(_db.entwicklungRezepturVersionen)
            ..where((v) => v.rezepturId.equals(rezepturId))
            ..orderBy([(v) => OrderingTerm.desc(v.nummer)])
            ..limit(1))
          .getSingleOrNull();

  Stream<List<RezepturPosition>> positionenBeobachten(String versionId) =>
      (_db.select(_db.entwicklungRezepturPositionen)
            ..where((p) => p.versionId.equals(versionId))
            ..orderBy([(p) => OrderingTerm.asc(p.reihenfolge)]))
          .watch();

  Future<List<RezepturPosition>> positionen(String versionId) =>
      (_db.select(_db.entwicklungRezepturPositionen)
            ..where((p) => p.versionId.equals(versionId))
            ..orderBy([(p) => OrderingTerm.asc(p.reihenfolge)]))
          .get();

  /// Legt eine Rezeptur mit einem ersten, leeren Stand an. Gibt die ID der
  /// Rezeptur zurück.
  Future<String> rezepturAnlegen({
    required String name,
    String? artikelnummer,
    String? beschreibung,
    String? projektId,
  }) async {
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db.into(_db.entwicklungRezepturen).insert(
            EntwicklungRezepturenCompanion.insert(
              id: id,
              name: name,
              artikelnummer: Value(artikelnummer),
              beschreibung: Value(beschreibung),
              projektId: Value(projektId),
            ),
          );
      await _db.into(_db.entwicklungRezepturVersionen).insert(
            EntwicklungRezepturVersionenCompanion.insert(
              id: _uuid.v4(),
              rezepturId: id,
              nummer: 1,
            ),
          );
    });
    return id;
  }

  Future<void> rezepturAendern(
    String id,
    EntwicklungRezepturenCompanion daten,
  ) =>
      (_db.update(_db.entwicklungRezepturen)..where((r) => r.id.equals(id)))
          .write(daten.copyWith(updatedAt: Value(DateTime.now())));

  /// Markiert eine Rezeptur als gelöscht. Wer sie als Unterrezeptur nutzt,
  /// rechnet weiter mit ihr.
  Future<void> rezepturLoeschen(String id) => rezepturAendern(
        id,
        EntwicklungRezepturenCompanion(deletedAt: Value(DateTime.now())),
      );

  /// In wie vielen anderen Rezepturständen die Rezeptur als Unterrezeptur
  /// steht.
  Future<int> rezepturVerwendungen(String id) async {
    final zeilen = await (_db.select(_db.entwicklungRezepturPositionen)
          ..where((p) => p.unterrezepturId.equals(id)))
        .get();
    return zeilen.map((p) => p.versionId).toSet().length;
  }

  /// Legt einen neuen Entwurf an — als Kopie von [vorlageId], sonst leer.
  /// Gibt seine ID zurück.
  Future<String> versionAnlegen(
    String rezepturId, {
    String? vorlageId,
    String? bezeichnung,
  }) async {
    final id = _uuid.v4();
    await _db.transaction(() async {
      final neueste = await neuesteVersion(rezepturId);
      final vorlage = vorlageId == null ? null : await version(vorlageId);
      await _db.into(_db.entwicklungRezepturVersionen).insert(
            EntwicklungRezepturVersionenCompanion.insert(
              id: id,
              rezepturId: rezepturId,
              nummer: (neueste?.nummer ?? 0) + 1,
              bezeichnung: Value(bezeichnung),
              verlustProzent: Value(vorlage?.verlustProzent ?? 0),
              fettVerlustProzent: Value(vorlage?.fettVerlustProzent ?? 0),
              verlustArt: Value(vorlage?.verlustArt ?? 'trocknung'),
            ),
          );
      if (vorlage == null) return;
      final alte = await positionen(vorlage.id);
      await _db.batch((b) {
        b.insertAll(_db.entwicklungRezepturPositionen, [
          for (final p in alte)
            EntwicklungRezepturPositionenCompanion.insert(
              id: _uuid.v4(),
              versionId: id,
              reihenfolge: Value(p.reihenfolge),
              zutatId: Value(p.zutatId),
              unterrezepturId: Value(p.unterrezepturId),
              unterVersionId: Value(p.unterVersionId),
              mengeKg: Value(p.mengeKg),
              quidPflicht: Value(p.quidPflicht),
              etikettName: Value(p.etikettName),
              notiz: Value(p.notiz),
            ),
        ]);
      });
    });
    return id;
  }

  /// Ändert einen Stand — nur einen Entwurf.
  Future<void> versionAendern(
    String id,
    EntwicklungRezepturVersionenCompanion daten,
  ) async {
    await _nurEntwurf(id);
    await (_db.update(_db.entwicklungRezepturVersionen)
          ..where((v) => v.id.equals(id)))
        .write(daten.copyWith(updatedAt: Value(DateTime.now())));
  }

  /// Schließt einen Entwurf ab: Er wird mit allen Zutatendaten
  /// eingefroren.
  Future<void> versionAbschliessen(String id) async {
    await _nurEntwurf(id);
    final eingabe = await rechenRezeptur(id);
    if (eingabe == null) throw StateError('Den Stand gibt es nicht.');
    await (_db.update(_db.entwicklungRezepturVersionen)
          ..where((v) => v.id.equals(id)))
        .write(
      EntwicklungRezepturVersionenCompanion(
        status: const Value(VersionStatus.abgeschlossen),
        stand: Value(jsonEncode(eingabe.toJson())),
        abgeschlossenAm: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Löscht einen Entwurf mit seinen Zeilen.
  Future<void> versionLoeschen(String id) async {
    await _nurEntwurf(id);
    await _db.transaction(() async {
      await (_db.delete(_db.entwicklungRezepturPositionen)
            ..where((p) => p.versionId.equals(id)))
          .go();
      await (_db.delete(_db.entwicklungRezepturVersionen)
            ..where((v) => v.id.equals(id)))
          .go();
    });
  }

  Future<void> _nurEntwurf(String versionId) async {
    final v = await version(versionId);
    if (v == null) throw StateError('Den Stand gibt es nicht.');
    if (v.status == VersionStatus.abgeschlossen) {
      throw StateError(
        'Stand ${v.nummer} ist abgeschlossen — für Änderungen einen neuen '
        'Stand anlegen.',
      );
    }
  }

  // ── Zeilen ──────────────────────────────────────────────────────────

  /// Fügt eine Zutat oder eine Unterrezeptur am Ende an.
  Future<void> positionHinzufuegen(
    String versionId, {
    String? zutatId,
    String? unterrezepturId,
    double mengeKg = 0,
  }) async {
    await _nurEntwurf(versionId);
    final vorhanden = await positionen(versionId);
    final reihenfolge = vorhanden.isEmpty
        ? 0
        : vorhanden.map((p) => p.reihenfolge).reduce((a, b) => a > b ? a : b) +
            1;
    await _db.into(_db.entwicklungRezepturPositionen).insert(
          EntwicklungRezepturPositionenCompanion.insert(
            id: _uuid.v4(),
            versionId: versionId,
            reihenfolge: Value(reihenfolge),
            zutatId: Value(zutatId),
            unterrezepturId: Value(unterrezepturId),
            mengeKg: Value(mengeKg),
          ),
        );
  }

  Future<void> positionAendern(
    RezepturPosition position,
    EntwicklungRezepturPositionenCompanion daten,
  ) async {
    await _nurEntwurf(position.versionId);
    await (_db.update(_db.entwicklungRezepturPositionen)
          ..where((p) => p.id.equals(position.id)))
        .write(daten.copyWith(updatedAt: Value(DateTime.now())));
  }

  Future<void> positionLoeschen(RezepturPosition position) async {
    await _nurEntwurf(position.versionId);
    await (_db.delete(_db.entwicklungRezepturPositionen)
          ..where((p) => p.id.equals(position.id)))
        .go();
  }

  /// Rückt eine Zeile um eins nach oben ([nachOben]) oder unten.
  Future<void> positionVerschieben(
    RezepturPosition position, {
    required bool nachOben,
  }) async {
    await _nurEntwurf(position.versionId);
    final liste = await positionen(position.versionId);
    final i = liste.indexWhere((p) => p.id == position.id);
    final j = nachOben ? i - 1 : i + 1;
    if (i < 0 || j < 0 || j >= liste.length) return;
    // Neu durchnummerieren — so stören doppelte Nummern nicht.
    final neu = [...liste];
    final tausch = neu[i];
    neu[i] = neu[j];
    neu[j] = tausch;
    await _db.batch((b) {
      for (var k = 0; k < neu.length; k++) {
        b.update(
          _db.entwicklungRezepturPositionen,
          EntwicklungRezepturPositionenCompanion(reihenfolge: Value(k)),
          where: (p) => p.id.equals(neu[k].id),
        );
      }
    });
  }

  // ── Für den Rechenkern ──────────────────────────────────────────────

  /// Lädt einen Stand so, wie der Rechenkern ihn braucht. Ein
  /// abgeschlossener Stand kommt aus seinem eingefrorenen JSON, ein
  /// Entwurf aus Katalog und Unterrezepturen von heute. null, wenn es den
  /// Stand nicht gibt.
  Future<RechenRezeptur?> rechenRezeptur(
    String versionId, {
    Set<String> unterwegs = const <String>{},
  }) async {
    final v = await version(versionId);
    if (v == null) return null;
    final stand = v.stand;
    if (v.status == VersionStatus.abgeschlossen && stand != null) {
      try {
        final json = jsonDecode(stand);
        if (json is Map<String, dynamic>) return RechenRezeptur.ausJson(json);
      } on FormatException {
        // Beschädigt — dann wie ein Entwurf aus den Zeilen.
      }
    }
    final kopf = await rezeptur(v.rezepturId);
    final weiter = {...unterwegs, v.rezepturId};
    final liste = <RechenPosition>[];
    for (final p in await positionen(versionId)) {
      final zutatId = p.zutatId;
      final unterId = p.unterrezepturId;
      if (zutatId != null) {
        final z = await zutat(zutatId);
        if (z == null) continue;
        liste.add(
          RechenPosition.zutat(
            rechenZutatAus(z),
            mengeKg: p.mengeKg,
            quidPflicht: p.quidPflicht,
            etikettName: p.etikettName,
          ),
        );
      } else if (unterId != null) {
        final RechenRezeptur? unter;
        if (weiter.contains(unterId)) {
          // Enthält sich selbst — der Rechenkern meldet das.
          unter = RechenRezeptur(
            id: unterId,
            name: (await rezeptur(unterId))?.name ?? '',
            positionen: const [],
          );
        } else {
          final vid = p.unterVersionId ?? (await neuesteVersion(unterId))?.id;
          unter = vid == null
              ? null
              : await rechenRezeptur(vid, unterwegs: weiter);
        }
        if (unter == null) continue;
        liste.add(
          RechenPosition.unterrezeptur(
            unter,
            mengeKg: p.mengeKg,
            quidPflicht: p.quidPflicht,
            etikettName: p.etikettName,
          ),
        );
      }
    }
    return RechenRezeptur(
      id: v.rezepturId,
      name: kopf?.name ?? '',
      positionen: liste,
      verlustProzent: v.verlustProzent,
      fettVerlustProzent: v.fettVerlustProzent,
      verlustart: Verlustart.aus(v.verlustArt),
    );
  }

  /// Ein Zeichen bei jeder Änderung an Zutaten oder Rezepturen — Ergebnisse
  /// rechnen dann neu, auch wenn sich nur eine Unterrezeptur geändert hat.
  Stream<void> aenderungen() => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _db.entwicklungZutaten,
          _db.entwicklungRezepturen,
          _db.entwicklungRezepturVersionen,
          _db.entwicklungRezepturPositionen,
        ]),
      )
      .map((_) {});
}

// ── Provider ──────────────────────────────────────────────────────────

final entwicklungRepositoryProvider = Provider<EntwicklungRepository>(
  (ref) => EntwicklungRepository(ref.watch(databaseProvider)),
);

final zutatenProvider = StreamProvider<List<Zutat>>(
  (ref) => ref.watch(entwicklungRepositoryProvider).zutatenBeobachten(),
);

final rezepturenProvider = StreamProvider<List<Rezeptur>>(
  (ref) => ref.watch(entwicklungRepositoryProvider).rezepturenBeobachten(),
);

/// Alle Zutaten nach ID, auch gelöschte.
final alleZutatenProvider = StreamProvider<Map<String, Zutat>>(
  (ref) => ref.watch(entwicklungRepositoryProvider).alleZutatenBeobachten(),
);

/// Alle Rezepturen nach ID, auch gelöschte.
final alleRezepturenProvider = StreamProvider<Map<String, Rezeptur>>(
  (ref) => ref.watch(entwicklungRepositoryProvider).alleRezepturenBeobachten(),
);

final alleVersionenProvider = StreamProvider<List<RezepturVersion>>(
  (ref) => ref.watch(entwicklungRepositoryProvider).alleVersionenBeobachten(),
);

final rezepturProvider = StreamProvider.autoDispose.family<Rezeptur?, String>(
  (ref, id) => ref.watch(entwicklungRepositoryProvider).rezepturBeobachten(id),
);

final versionenProvider =
    StreamProvider.autoDispose.family<List<RezepturVersion>, String>(
  (ref, rezepturId) =>
      ref.watch(entwicklungRepositoryProvider).versionenBeobachten(rezepturId),
);

final positionenProvider =
    StreamProvider.autoDispose.family<List<RezepturPosition>, String>(
  (ref, versionId) =>
      ref.watch(entwicklungRepositoryProvider).positionenBeobachten(versionId),
);

/// Meldet jede Änderung an Zutaten und Rezepturen.
final entwicklungAenderungProvider = StreamProvider.autoDispose<void>(
  (ref) => ref.watch(entwicklungRepositoryProvider).aenderungen(),
);

/// Die Eingabe des Rechenkerns für einen Stand.
final rechenRezepturProvider =
    FutureProvider.autoDispose.family<RechenRezeptur?, String>(
  (ref, versionId) {
    ref.watch(entwicklungAenderungProvider);
    return ref.watch(entwicklungRepositoryProvider).rechenRezeptur(versionId);
  },
);

/// Das Ergebnis des Rechenkerns für einen Stand.
final rezepturErgebnisProvider =
    FutureProvider.autoDispose.family<RezepturErgebnis?, String>(
  (ref, versionId) async {
    final eingabe = await ref.watch(rechenRezepturProvider(versionId).future);
    return eingabe == null ? null : berechne(eingabe);
  },
);
