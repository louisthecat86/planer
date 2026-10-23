import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../daten/entwicklung_repository.dart' show nachName;
import 'entwicklungsstrang.dart';
import 'projekt_modell.dart';

// Projekte der Produktentwicklung: Stammdaten, Verlauf, Dateien und die
// Fließdiagramme, die ein Projekt nennen kann.

/// Lesen und Schreiben der Projekte.
class ProjektRepository {
  ProjektRepository(this._db);

  final AppDatabase _db;
  static const Uuid _uuid = Uuid();

  // ── Projekte ────────────────────────────────────────────────────────

  /// Alle Projekte, die nicht gelöscht sind — das zuletzt geänderte
  /// zuerst.
  Stream<List<EntwicklungsProjekt>> projekteBeobachten() =>
      (_db.select(_db.entwicklungProjekte)
            ..where((p) => p.deletedAt.isNull())
            ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]))
          .watch();

  Stream<EntwicklungsProjekt?> projektBeobachten(String id) =>
      (_db.select(_db.entwicklungProjekte)..where((p) => p.id.equals(id)))
          .watchSingleOrNull();

  Future<EntwicklungsProjekt?> projekt(String id) =>
      (_db.select(_db.entwicklungProjekte)..where((p) => p.id.equals(id)))
          .getSingleOrNull();

  /// Legt ein Projekt an — mit einem ersten Meilenstein im Verlauf. Gibt
  /// die ID zurück.
  Future<String> projektAnlegen({
    required String name,
    String? kunde,
    String? artikelnummer,
    String? produktidee,
    DateTime? jetzt,
  }) async {
    final id = _uuid.v4();
    final zeit = jetzt ?? DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.entwicklungProjekte).insert(
            EntwicklungProjekteCompanion.insert(
              id: id,
              name: name,
              kunde: Value(kunde),
              artikelnummer: Value(artikelnummer),
              produktidee: Value(produktidee),
              createdAt: Value(zeit),
              updatedAt: Value(zeit),
            ),
          );
      await _db.into(_db.entwicklungProjektEintraege).insert(
            EntwicklungProjektEintraegeCompanion.insert(
              id: _uuid.v4(),
              projektId: id,
              art: EintragArt.meilenstein.schluessel,
              titel: 'Projekt angelegt',
              datum: DateTime(zeit.year, zeit.month, zeit.day),
              status: Value(EintragStatus.erledigt.schluessel),
              createdAt: Value(zeit),
              updatedAt: Value(zeit),
            ),
          );
    });
    return id;
  }

  Future<void> projektAendern(
    String id,
    EntwicklungProjekteCompanion daten,
  ) =>
      (_db.update(_db.entwicklungProjekte)..where((p) => p.id.equals(id)))
          .write(daten.copyWith(updatedAt: Value(DateTime.now())));

  /// Ändert den Status eines Projekts und hält den Wechsel als Meilenstein
  /// im Verlauf fest — daraus entstehen die Phasen auf dem Zeitstrahl.
  Future<void> statusAendern(
    String id,
    ProjektStatus neu, {
    DateTime? jetzt,
  }) async {
    final p = await projekt(id);
    if (p == null) return;
    final alt = ProjektStatus.aus(p.status);
    if (alt == neu) return;
    final zeit = jetzt ?? DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.entwicklungProjekte)
            ..where((x) => x.id.equals(id)))
          .write(
        EntwicklungProjekteCompanion(
          status: Value(neu.schluessel),
          updatedAt: Value(zeit),
        ),
      );
      await _db.into(_db.entwicklungProjektEintraege).insert(
            EntwicklungProjektEintraegeCompanion.insert(
              id: _uuid.v4(),
              projektId: id,
              art: EintragArt.meilenstein.schluessel,
              titel: statusMeilensteinTitel(neu),
              datum: DateTime(zeit.year, zeit.month, zeit.day),
              status: Value(EintragStatus.erledigt.schluessel),
              beschreibung: Value('Status vorher: ${alt.label}'),
              wert: Value(statusWert(alt, neu)),
              createdAt: Value(zeit),
              updatedAt: Value(zeit),
            ),
          );
    });
  }

  /// Markiert ein Projekt als gelöscht. Seine Rezepturen bleiben — sie
  /// stehen danach ohne Projekt in der Liste.
  Future<void> projektLoeschen(String id) => _db.transaction(() async {
        await projektAendern(
          id,
          EntwicklungProjekteCompanion(deletedAt: Value(DateTime.now())),
        );
        await (_db.update(_db.entwicklungRezepturen)
              ..where((r) => r.projektId.equals(id)))
            .write(const EntwicklungRezepturenCompanion(projektId: Value(null)));
      });

  /// Hakt einen Punkt der Projekt-Checkliste ab oder nimmt den Haken weg.
  /// Die übrigen Punkte bleiben, wie sie sind — auch zurückgestellte.
  Future<void> checklistePunkt(
    String id, {
    required String schluessel,
    required bool erledigt,
  }) async {
    final p = await projekt(id);
    if (p == null) return;
    await projektAendern(
      id,
      EntwicklungProjekteCompanion(
        checkliste: Value(
          checklisteMit(p.checkliste, schluessel, erledigt ? true : null),
        ),
      ),
    );
  }

  /// Stellt einen Punkt der Checkliste mit „Später" zurück (F37) — „Als
  /// Nächstes" geht dann an ihm vorbei — oder nimmt das zurück.
  Future<void> checklisteZurueckstellen(
    String id, {
    required String schluessel,
    required bool zurueck,
  }) async {
    final p = await projekt(id);
    if (p == null) return;
    await projektAendern(
      id,
      EntwicklungProjekteCompanion(
        checkliste: Value(
          checklisteMit(
            p.checkliste,
            schluessel,
            zurueck ? kCheckSpaeter : null,
          ),
        ),
      ),
    );
  }

  /// Nimmt die Datei [dateiId] als Produktfoto — war das Foto
  /// zurückgestellt, ist es das damit nicht mehr.
  Future<void> produktfotoSetzen(String id, String dateiId) =>
      _db.transaction(() async {
        final p = await projekt(id);
        if (p == null) return;
        await projektAendern(
          id,
          EntwicklungProjekteCompanion(
            bildDateiId: Value(dateiId),
            checkliste: Value(
              checklisteMit(p.checkliste, 'produktfotoHinterlegt', null),
            ),
          ),
        );
      });

  /// Setzt eine Pflichtangabe des Etiketts auf [stand] (F28).
  Future<void> lmivPunkt(
    String id, {
    required String schluessel,
    required LmivStand stand,
  }) async {
    final p = await projekt(id);
    if (p == null) return;
    final staende = lmivAus(p.etikettCheckliste)..[schluessel] = stand;
    await projektAendern(
      id,
      EntwicklungProjekteCompanion(
        etikettCheckliste: Value(lmivZuJson(staende)),
      ),
    );
  }

  // ── Verlauf ─────────────────────────────────────────────────────────

  /// Die Einträge eines Projekts, der neueste zuerst.
  /// Die Einträge aller Projekte — für die Zahlen der Entwicklung.
  Stream<List<ProjektEintrag>> alleEintraegeBeobachten() =>
      _db.select(_db.entwicklungProjektEintraege).watch();

  Stream<List<ProjektEintrag>> eintraegeBeobachten(String projektId) =>
      (_db.select(_db.entwicklungProjektEintraege)
            ..where((e) => e.projektId.equals(projektId))
            ..orderBy([
              (e) => OrderingTerm.desc(e.datum),
              (e) => OrderingTerm.desc(e.createdAt),
            ]))
          .watch();

  Future<ProjektEintrag?> eintrag(String id) =>
      (_db.select(_db.entwicklungProjektEintraege)
            ..where((e) => e.id.equals(id)))
          .getSingleOrNull();

  /// Legt einen Eintrag an und gibt seine ID zurück. Das Projekt gilt
  /// damit als geändert.
  Future<String> eintragAnlegen({
    required String projektId,
    required EintragArt art,
    required String titel,
    required DateTime datum,
    String? benutzer,
    String? beschreibung,
    EintragStatus status = EintragStatus.offen,
    String? wert,
    String? ziel,
    String? dateiId,
    String? versionId,
    List<String> aenderungen = const [],
  }) async {
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db.into(_db.entwicklungProjektEintraege).insert(
            EntwicklungProjektEintraegeCompanion.insert(
              id: id,
              projektId: projektId,
              art: art.schluessel,
              titel: titel,
              datum: datum,
              benutzer: Value(benutzer),
              beschreibung: Value(beschreibung),
              status: Value(status.schluessel),
              wert: Value(wert),
              ziel: Value(ziel),
              dateiId: Value(dateiId),
              versionId: Value(versionId),
              aenderungen: Value(texteZuJson(aenderungen)),
            ),
          );
      await _beruehren(projektId);
    });
    return id;
  }

  Future<void> eintragAendern(
    String id,
    EntwicklungProjektEintraegeCompanion daten,
  ) =>
      (_db.update(_db.entwicklungProjektEintraege)
            ..where((e) => e.id.equals(id)))
          .write(daten.copyWith(updatedAt: Value(DateTime.now())));

  /// Setzt einen Eintrag auf offen oder erledigt.
  Future<void> eintragStatusSetzen(String id, EintragStatus status) =>
      eintragAendern(
        id,
        EntwicklungProjektEintraegeCompanion(status: Value(status.schluessel)),
      );

  Future<void> eintragLoeschen(String id) =>
      (_db.delete(_db.entwicklungProjektEintraege)
            ..where((e) => e.id.equals(id)))
          .go();

  /// Hängt einen Kommentar an einen Eintrag.
  Future<void> kommentieren(String eintragId, Kommentar kommentar) async {
    final e = await eintrag(eintragId);
    if (e == null) return;
    final liste = [...Kommentar.listeAus(e.kommentare), kommentar];
    await eintragAendern(
      eintragId,
      EntwicklungProjektEintraegeCompanion(
        kommentare: Value(Kommentar.listeZuJson(liste)),
      ),
    );
  }

  /// Nimmt den Kommentar an Stelle [index] wieder weg.
  Future<void> kommentarLoeschen(String eintragId, int index) async {
    final e = await eintrag(eintragId);
    if (e == null) return;
    final liste = [...Kommentar.listeAus(e.kommentare)];
    if (index < 0 || index >= liste.length) return;
    liste.removeAt(index);
    await eintragAendern(
      eintragId,
      EntwicklungProjektEintraegeCompanion(
        kommentare: Value(Kommentar.listeZuJson(liste)),
      ),
    );
  }

  Future<void> _beruehren(String projektId) =>
      (_db.update(_db.entwicklungProjekte)
            ..where((p) => p.id.equals(projektId)))
          .write(EntwicklungProjekteCompanion(updatedAt: Value(DateTime.now())));

  // ── Dateien und Rezepturen ──────────────────────────────────────────

  /// Die Dateien eines Projekts, die neueste zuerst.
  Stream<List<EntwicklungsDatei>> dateienBeobachten(String projektId) =>
      (_db.select(_db.entwicklungDateien)
            ..where((d) => d.projektId.equals(projektId))
            ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
          .watch();

  /// Nimmt eine gelöschte Datei aus Einträgen und Produktbild.
  Future<void> dateiVerweiseEntfernen(String dateiId) =>
      _db.transaction(() async {
        await (_db.update(_db.entwicklungProjektEintraege)
              ..where((e) => e.dateiId.equals(dateiId)))
            .write(
          const EntwicklungProjektEintraegeCompanion(dateiId: Value(null)),
        );
        await (_db.update(_db.entwicklungProjekte)
              ..where((p) => p.bildDateiId.equals(dateiId)))
            .write(const EntwicklungProjekteCompanion(bildDateiId: Value(null)));
      });

  /// Die Rezepturen eines Projekts, nach Namen.
  Stream<List<Rezeptur>> rezepturenBeobachten(String projektId) =>
      (_db.select(_db.entwicklungRezepturen)
            ..where((r) => r.projektId.equals(projektId) & r.deletedAt.isNull()))
          .watch()
          .map((liste) => [...liste]..sort((a, b) => nachName(a.name, b.name)));

  // ── Fließdiagramme ──────────────────────────────────────────────────

  /// Die gepflegten Fließdiagramme in ihrer Reihenfolge.
  Stream<List<Fliessdiagramm>> fliessdiagrammeBeobachten() =>
      (_db.select(_db.entwicklungFliessdiagramme)
            ..orderBy([
              (f) => OrderingTerm.asc(f.sortierung),
              (f) => OrderingTerm.asc(f.id),
            ]))
          .watch();

  /// Legt ein Fließdiagramm an oder ändert seine Bezeichnung.
  Future<void> fliessdiagrammSpeichern({
    required String id,
    required String bezeichnung,
    int? sortierung,
  }) async {
    final alle = await _db.select(_db.entwicklungFliessdiagramme).get();
    final vorhanden = alle.where((f) => f.id == id).firstOrNull;
    final ende = alle.isEmpty
        ? 0
        : alle.map((f) => f.sortierung).reduce((a, b) => a > b ? a : b) + 1;
    await _db.into(_db.entwicklungFliessdiagramme).insertOnConflictUpdate(
          EntwicklungFliessdiagrammeCompanion.insert(
            id: id,
            bezeichnung: bezeichnung,
            sortierung: Value(sortierung ?? vorhanden?.sortierung ?? ende),
            createdAt: Value(vorhanden?.createdAt ?? DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// Stellt die Fließdiagramme in die Reihenfolge von [ids].
  Future<void> fliessdiagrammeOrdnen(List<String> ids) => _db.batch((b) {
        for (var i = 0; i < ids.length; i++) {
          b.update(
            _db.entwicklungFliessdiagramme,
            EntwicklungFliessdiagrammeCompanion(sortierung: Value(i)),
            where: (f) => f.id.equals(ids[i]),
          );
        }
      });

  Future<void> fliessdiagrammLoeschen(String id) =>
      (_db.delete(_db.entwicklungFliessdiagramme)
            ..where((f) => f.id.equals(id)))
          .go();

  /// In wie vielen Projekten das Fließdiagramm steht.
  Future<int> fliessdiagrammVerwendungen(String id) async {
    final liste = await (_db.select(_db.entwicklungProjekte)
          ..where((p) => p.fliessdiagramm.equals(id) & p.deletedAt.isNull()))
        .get();
    return liste.length;
  }
}

// ── Provider ──────────────────────────────────────────────────────────

final projektRepositoryProvider = Provider<ProjektRepository>(
  (ref) => ProjektRepository(ref.watch(databaseProvider)),
);

final projekteProvider = StreamProvider<List<EntwicklungsProjekt>>(
  (ref) => ref.watch(projektRepositoryProvider).projekteBeobachten(),
);

final projektProvider =
    StreamProvider.autoDispose.family<EntwicklungsProjekt?, String>(
  (ref, id) => ref.watch(projektRepositoryProvider).projektBeobachten(id),
);

final projektEintraegeProvider =
    StreamProvider.autoDispose.family<List<ProjektEintrag>, String>(
  (ref, projektId) =>
      ref.watch(projektRepositoryProvider).eintraegeBeobachten(projektId),
);

final alleEintraegeProvider = StreamProvider<List<ProjektEintrag>>(
  (ref) => ref.watch(projektRepositoryProvider).alleEintraegeBeobachten(),
);

final projektDateienProvider =
    StreamProvider.autoDispose.family<List<EntwicklungsDatei>, String>(
  (ref, projektId) =>
      ref.watch(projektRepositoryProvider).dateienBeobachten(projektId),
);

final projektRezepturenProvider =
    StreamProvider.autoDispose.family<List<Rezeptur>, String>(
  (ref, projektId) =>
      ref.watch(projektRepositoryProvider).rezepturenBeobachten(projektId),
);

final fliessdiagrammeProvider = StreamProvider<List<Fliessdiagramm>>(
  (ref) => ref.watch(projektRepositoryProvider).fliessdiagrammeBeobachten(),
);
