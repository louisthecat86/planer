import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../daten/entwicklung_repository.dart' show nachName;
import 'entwicklungsstrang.dart';
import 'gesamtprojekt_modell.dart';
import 'projekt_modell.dart';

// Projekte der Produktentwicklung: Stammdaten, Verlauf, Dateien und die
// Fließdiagramme, die ein Projekt nennen kann — dazu die Gesamtprojekte,
// die mehrere Muster zu einer Anfrage zusammenhalten.

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
  ///
  /// Mit [gesamtprojektId] entsteht ein Muster dieses Gesamtprojekts: Es
  /// bekommt dessen Kunden, und der erste Meilenstein heißt „Muster
  /// angelegt".
  Future<String> projektAnlegen({
    required String name,
    String? kunde,
    String? artikelnummer,
    String? produktidee,
    String? gesamtprojektId,
    DateTime? jetzt,
  }) async {
    final id = _uuid.v4();
    final zeit = jetzt ?? DateTime.now();
    await _db.transaction(() async {
      final g = gesamtprojektId == null
          ? null
          : await gesamtprojekt(gesamtprojektId);
      if (gesamtprojektId != null && (g == null || g.deletedAt != null)) {
        throw StateError('Das Gesamtprojekt gibt es nicht mehr.');
      }
      await _db.into(_db.entwicklungProjekte).insert(
            EntwicklungProjekteCompanion.insert(
              id: id,
              name: name,
              kunde: Value(g == null ? kunde : _oderNull(g.kunde) ?? kunde),
              artikelnummer: Value(artikelnummer),
              produktidee: Value(produktidee),
              gesamtprojektId: Value(g?.id),
              createdAt: Value(zeit),
              updatedAt: Value(zeit),
            ),
          );
      await _meilenstein(
        id,
        g == null ? 'Projekt angelegt' : 'Muster angelegt',
        beschreibung: g == null ? null : 'Im Gesamtprojekt „${g.name}"',
        zeit: zeit,
      );
      if (g != null) await _beruehren(g.id, zeit: zeit);
    });
    return id;
  }

  /// Ein erledigter Meilenstein im Verlauf von [projektId] (Projekt oder
  /// Gesamtprojekt).
  Future<void> _meilenstein(
    String projektId,
    String titel, {
    String? beschreibung,
    String? wert,
    required DateTime zeit,
  }) =>
      _db.into(_db.entwicklungProjektEintraege).insert(
            EntwicklungProjektEintraegeCompanion.insert(
              id: _uuid.v4(),
              projektId: projektId,
              art: EintragArt.meilenstein.schluessel,
              titel: titel,
              datum: DateTime(zeit.year, zeit.month, zeit.day),
              status: Value(EintragStatus.erledigt.schluessel),
              beschreibung: Value(beschreibung),
              wert: Value(wert),
              createdAt: Value(zeit),
              updatedAt: Value(zeit),
            ),
          );

  Future<void> projektAendern(
    String id,
    EntwicklungProjekteCompanion daten,
  ) =>
      (_db.update(_db.entwicklungProjekte)..where((p) => p.id.equals(id)))
          .write(daten.copyWith(updatedAt: Value(DateTime.now())));

  /// Ändert den Status eines Projekts und hält den Wechsel als Meilenstein
  /// im Verlauf fest — daraus entstehen die Phasen auf dem Zeitstrahl.
  /// [grund] steht mit im Meilenstein, etwa warum ein Muster nicht weiter
  /// verfolgt wird.
  Future<void> statusAendern(
    String id,
    ProjektStatus neu, {
    String? grund,
    DateTime? jetzt,
  }) async {
    final p = await projekt(id);
    if (p == null) return;
    final alt = ProjektStatus.aus(p.status);
    if (alt == neu) return;
    final zeit = jetzt ?? DateTime.now();
    final g = _oderNull(grund);
    await _db.transaction(() async {
      await (_db.update(_db.entwicklungProjekte)
            ..where((x) => x.id.equals(id)))
          .write(
        EntwicklungProjekteCompanion(
          status: Value(neu.schluessel),
          updatedAt: Value(zeit),
        ),
      );
      await _meilenstein(
        id,
        statusMeilensteinTitel(neu),
        beschreibung: [
          if (g != null) 'Grund: $g',
          'Status vorher: ${alt.label}',
        ].join('\n'),
        wert: statusWert(alt, neu),
        zeit: zeit,
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

  // ── Gesamtprojekte ──────────────────────────────────────────────────

  /// Alle Gesamtprojekte, die nicht gelöscht sind — das zuletzt geänderte
  /// zuerst.
  Stream<List<Gesamtprojekt>> gesamtprojekteBeobachten() =>
      (_db.select(_db.entwicklungGesamtprojekte)
            ..where((g) => g.deletedAt.isNull())
            ..orderBy([(g) => OrderingTerm.desc(g.updatedAt)]))
          .watch();

  Stream<Gesamtprojekt?> gesamtprojektBeobachten(String id) =>
      (_db.select(_db.entwicklungGesamtprojekte)
            ..where((g) => g.id.equals(id)))
          .watchSingleOrNull();

  Future<Gesamtprojekt?> gesamtprojekt(String id) =>
      (_db.select(_db.entwicklungGesamtprojekte)
            ..where((g) => g.id.equals(id)))
          .getSingleOrNull();

  /// Die Muster eines Gesamtprojekts, die nicht gelöscht sind — in der
  /// Reihenfolge, in der sie angelegt wurden.
  Stream<List<EntwicklungsProjekt>> musterBeobachten(String gesamtprojektId) =>
      (_db.select(_db.entwicklungProjekte)
            ..where(
              (p) =>
                  p.gesamtprojektId.equals(gesamtprojektId) &
                  p.deletedAt.isNull(),
            )
            ..orderBy([
              (p) => OrderingTerm.asc(p.createdAt),
              (p) => OrderingTerm.asc(p.name),
            ]))
          .watch();

  Future<List<EntwicklungsProjekt>> muster(String gesamtprojektId) =>
      (_db.select(_db.entwicklungProjekte)
            ..where(
              (p) =>
                  p.gesamtprojektId.equals(gesamtprojektId) &
                  p.deletedAt.isNull(),
            ))
          .get();

  /// Legt ein Gesamtprojekt an — mit einem ersten Meilenstein in seinem
  /// Verlauf und je Name in [muster] einem Muster. Ein leerer Name wird
  /// „Muster 1", „Muster 2" … Gibt die ID zurück.
  Future<String> gesamtprojektAnlegen({
    required String name,
    String? kunde,
    String? anfrage,
    List<String> muster = const [],
    DateTime? jetzt,
  }) async {
    final id = _uuid.v4();
    final zeit = jetzt ?? DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.entwicklungGesamtprojekte).insert(
            EntwicklungGesamtprojekteCompanion.insert(
              id: id,
              name: name,
              kunde: Value(_oderNull(kunde)),
              anfrage: Value(_oderNull(anfrage)),
              createdAt: Value(zeit),
              updatedAt: Value(zeit),
            ),
          );
      await _meilenstein(id, 'Gesamtprojekt angelegt', zeit: zeit);
      for (final (i, m) in musterNamen(muster).indexed) {
        await projektAnlegen(
          name: m,
          gesamtprojektId: id,
          // Je Muster eine Sekunde später — so bleibt ihre Reihenfolge.
          jetzt: zeit.add(Duration(seconds: i)),
        );
      }
    });
    return id;
  }

  /// Ändert ein Gesamtprojekt. Ein neuer Kunde gilt gleich für alle Muster.
  Future<void> gesamtprojektAendern(
    String id,
    EntwicklungGesamtprojekteCompanion daten,
  ) =>
      _db.transaction(() async {
        final zeit = DateTime.now();
        await (_db.update(_db.entwicklungGesamtprojekte)
              ..where((g) => g.id.equals(id)))
            .write(daten.copyWith(updatedAt: Value(zeit)));
        if (daten.kunde.present) {
          await (_db.update(_db.entwicklungProjekte)
                ..where((p) => p.gesamtprojektId.equals(id)))
              .write(
            EntwicklungProjekteCompanion(
              kunde: Value(_oderNull(daten.kunde.value)),
              updatedAt: Value(zeit),
            ),
          );
        }
      });

  /// Markiert ein Gesamtprojekt als gelöscht — mit allen seinen Mustern.
  /// Deren Rezepturen bleiben und stehen danach ohne Projekt in der Liste.
  Future<void> gesamtprojektLoeschen(String id) => _db.transaction(() async {
        final zeit = DateTime.now();
        await (_db.update(_db.entwicklungGesamtprojekte)
              ..where((g) => g.id.equals(id)))
            .write(
          EntwicklungGesamtprojekteCompanion(
            deletedAt: Value(zeit),
            updatedAt: Value(zeit),
          ),
        );
        for (final m in await muster(id)) {
          await projektLoeschen(m.id);
        }
      });

  /// Nimmt ein Projekt als Muster in das Gesamtprojekt [gesamtprojektId]
  /// auf — oder löst es mit null wieder heraus. Der Wechsel steht im
  /// Verlauf des Projekts. Der Kunde des Gesamtprojekts gilt danach auch
  /// für das Muster; hat das Gesamtprojekt noch keinen, übernimmt es den
  /// des Projekts.
  Future<void> inGesamtprojektVerschieben(
    String projektId,
    String? gesamtprojektId, {
    DateTime? jetzt,
  }) =>
      _db.transaction(() async {
        final p = await projekt(projektId);
        if (p == null || p.gesamtprojektId == gesamtprojektId) return;
        final zeit = jetzt ?? DateTime.now();
        final bisher = p.gesamtprojektId == null
            ? null
            : await gesamtprojekt(p.gesamtprojektId!);
        if (gesamtprojektId == null) {
          await (_db.update(_db.entwicklungProjekte)
                ..where((x) => x.id.equals(projektId)))
              .write(
            EntwicklungProjekteCompanion(
              gesamtprojektId: const Value(null),
              updatedAt: Value(zeit),
            ),
          );
          await _meilenstein(
            projektId,
            'Aus dem Gesamtprojekt gelöst',
            beschreibung: bisher == null ? null : 'Bisher in „${bisher.name}"',
            zeit: zeit,
          );
          if (bisher != null) await _beruehren(bisher.id, zeit: zeit);
          return;
        }
        final g = await gesamtprojekt(gesamtprojektId);
        if (g == null || g.deletedAt != null) {
          throw StateError('Das Gesamtprojekt gibt es nicht mehr.');
        }
        final kunde = _oderNull(g.kunde);
        if (kunde == null && _oderNull(p.kunde) != null) {
          await gesamtprojektAendern(
            g.id,
            EntwicklungGesamtprojekteCompanion(kunde: Value(p.kunde!.trim())),
          );
        }
        await (_db.update(_db.entwicklungProjekte)
              ..where((x) => x.id.equals(projektId)))
            .write(
          EntwicklungProjekteCompanion(
            gesamtprojektId: Value(g.id),
            kunde: kunde == null ? const Value.absent() : Value(kunde),
            updatedAt: Value(zeit),
          ),
        );
        await _meilenstein(
          projektId,
          'Ins Gesamtprojekt aufgenommen',
          beschreibung: [
            'Muster im Gesamtprojekt „${g.name}"',
            if (bisher != null) 'Bisher in „${bisher.name}"',
          ].join('\n'),
          zeit: zeit,
        );
        await _beruehren(g.id, zeit: zeit);
      });

  /// Bildet um ein Projekt ein neues Gesamtprojekt [name]: Das Projekt
  /// wird sein erstes Muster. Mit [mailsMitnehmen] wandern seine Mails
  /// (samt Anhängen) in den Verlauf des Gesamtprojekts — sie betreffen
  /// dann alle Muster. Gibt die ID des Gesamtprojekts zurück.
  Future<String> gesamtprojektUmProjekt(
    String projektId, {
    required String name,
    bool mailsMitnehmen = true,
    DateTime? jetzt,
  }) async {
    final p = await projekt(projektId);
    if (p == null) throw StateError('Das Projekt gibt es nicht mehr.');
    final zeit = jetzt ?? DateTime.now();
    return _db.transaction(() async {
      final id = await gesamtprojektAnlegen(
        name: name,
        kunde: p.kunde,
        anfrage: p.produktidee,
        jetzt: zeit,
      );
      await inGesamtprojektVerschieben(projektId, id, jetzt: zeit);
      if (mailsMitnehmen) {
        final mails = await (_db.select(_db.entwicklungProjektEintraege)
              ..where(
                (e) =>
                    e.projektId.equals(projektId) &
                    e.art.equals(EintragArt.email.schluessel),
              ))
            .get();
        for (final m in mails) {
          await eintragVerschieben(m.id, id);
        }
      }
      return id;
    });
  }

  // ── Verschieben ─────────────────────────────────────────────────────

  /// Verschiebt einen Eintrag in den Verlauf eines anderen Projekts oder
  /// Gesamtprojekts [zielId] — mit seiner Datei, bei einer Mail auch mit
  /// ihren Anhängen. Der Bezug auf einen Rezepturstand fällt weg: Der
  /// Stand gehört zum bisherigen Projekt.
  Future<void> eintragVerschieben(String eintragId, String zielId) =>
      _db.transaction(() async {
        final e = await eintrag(eintragId);
        if (e == null || e.projektId == zielId) return;
        final quelle = e.projektId;
        final dateien = <String>{
          if (e.dateiId case final d?) d,
          if (EintragArt.aus(e.art) == EintragArt.email)
            ...await _anhaenge(e),
        };
        await (_db.update(_db.entwicklungProjektEintraege)
              ..where((x) => x.id.equals(eintragId)))
            .write(
          EntwicklungProjektEintraegeCompanion(
            projektId: Value(zielId),
            versionId: const Value(null),
            updatedAt: Value(DateTime.now()),
          ),
        );
        for (final d in dateien) {
          await _dateiUmziehen(d, von: quelle, nach: zielId);
        }
        await _beruehren(quelle);
        await _beruehren(zielId);
      });

  /// Verschiebt eine Datei in ein anderes Projekt oder Gesamtprojekt
  /// [zielId]. Hängt sie an Einträgen im Verlauf, wandern die mit.
  Future<void> dateiVerschieben(String dateiId, String zielId) =>
      _db.transaction(() async {
        final d = await (_db.select(_db.entwicklungDateien)
              ..where((x) => x.id.equals(dateiId)))
            .getSingleOrNull();
        final quelle = d?.projektId;
        if (d == null || quelle == null || quelle == zielId) return;
        final eintraege = await (_db.select(_db.entwicklungProjektEintraege)
              ..where(
                (e) => e.projektId.equals(quelle) & e.dateiId.equals(dateiId),
              ))
            .get();
        for (final e in eintraege) {
          await eintragVerschieben(e.id, zielId);
        }
        await _dateiUmziehen(dateiId, von: quelle, nach: zielId);
        await _beruehren(quelle);
        await _beruehren(zielId);
      });

  /// Setzt die Datei [dateiId] von [von] nach [nach] — ist sie das
  /// Produktfoto des bisherigen Projekts, ist sie es danach nicht mehr.
  Future<void> _dateiUmziehen(
    String dateiId, {
    required String von,
    required String nach,
  }) async {
    await (_db.update(_db.entwicklungDateien)
          ..where((d) => d.id.equals(dateiId) & d.projektId.equals(von)))
        .write(EntwicklungDateienCompanion(projektId: Value(nach)));
    await (_db.update(_db.entwicklungProjekte)
          ..where((p) => p.id.equals(von) & p.bildDateiId.equals(dateiId)))
        .write(const EntwicklungProjekteCompanion(bildDateiId: Value(null)));
  }

  /// Die Anhänge einer Mail im Verlauf: Beim Ablegen kamen sie als eigene
  /// Dateien zum Projekt, der Eintrag nennt sie („Anhang: Name (Größe)").
  /// Gefunden wird je Name die Datei des Projekts, die kurz vor dem
  /// Eintrag gespeichert wurde.
  Future<List<String>> _anhaenge(ProjektEintrag e) async {
    final namen = mailAnhangNamen(texteAus(e.aenderungen));
    if (namen.isEmpty) return const [];
    final kandidaten = await (_db.select(_db.entwicklungDateien)
          ..where(
            (d) =>
                d.projektId.equals(e.projektId) &
                d.name.isIn(namen.toSet()) &
                d.createdAt.isBiggerOrEqualValue(
                  e.createdAt.subtract(const Duration(minutes: 10)),
                ) &
                d.createdAt.isSmallerOrEqualValue(
                  e.createdAt.add(const Duration(minutes: 1)),
                ),
          ))
        .get();
    final frei = [...kandidaten.where((d) => d.id != e.dateiId)];
    final gefunden = <String>[];
    for (final name in namen) {
      final passend = frei.where((d) => d.name == name).toList()
        ..sort(
          (a, b) => e.createdAt
              .difference(a.createdAt)
              .abs()
              .compareTo(e.createdAt.difference(b.createdAt).abs()),
        );
      final d = passend.firstOrNull;
      if (d == null) continue;
      gefunden.add(d.id);
      frei.remove(d);
    }
    return gefunden;
  }

  // ── Verlauf ─────────────────────────────────────────────────────────

  /// Die Einträge aller Projekte und Gesamtprojekte — für die Zahlen der
  /// Entwicklung.
  Stream<List<ProjektEintrag>> alleEintraegeBeobachten() =>
      _db.select(_db.entwicklungProjektEintraege).watch();

  /// Die Einträge eines Projekts oder Gesamtprojekts, der neueste zuerst.
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

  /// Das Projekt oder Gesamtprojekt [projektId] gilt als geändert.
  Future<void> _beruehren(String projektId, {DateTime? zeit}) async {
    final jetzt = zeit ?? DateTime.now();
    await (_db.update(_db.entwicklungProjekte)
          ..where((p) => p.id.equals(projektId)))
        .write(EntwicklungProjekteCompanion(updatedAt: Value(jetzt)));
    await (_db.update(_db.entwicklungGesamtprojekte)
          ..where((g) => g.id.equals(projektId)))
        .write(EntwicklungGesamtprojekteCompanion(updatedAt: Value(jetzt)));
  }

  // ── Dateien und Rezepturen ──────────────────────────────────────────

  /// Die Dateien eines Projekts oder Gesamtprojekts, die neueste zuerst.
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

String? _oderNull(String? t) {
  final x = t?.trim() ?? '';
  return x.isEmpty ? null : x;
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

final gesamtprojekteProvider = StreamProvider<List<Gesamtprojekt>>(
  (ref) => ref.watch(projektRepositoryProvider).gesamtprojekteBeobachten(),
);

final gesamtprojektProvider =
    StreamProvider.autoDispose.family<Gesamtprojekt?, String>(
  (ref, id) => ref.watch(projektRepositoryProvider).gesamtprojektBeobachten(id),
);

/// Die Muster eines Gesamtprojekts, in der Reihenfolge des Anlegens.
final musterProvider =
    StreamProvider.autoDispose.family<List<EntwicklungsProjekt>, String>(
  (ref, id) => ref.watch(projektRepositoryProvider).musterBeobachten(id),
);

/// Wohin sich im Gesamtprojekt Einträge und Dateien verschieben lassen:
/// es selbst und seine Muster.
final verschiebeZieleProvider =
    Provider.autoDispose.family<List<VerschiebeZiel>, String>((ref, id) {
  final g = ref.watch(gesamtprojektProvider(id)).valueOrNull;
  final muster = ref.watch(musterProvider(id)).valueOrNull ??
      const <EntwicklungsProjekt>[];
  return verschiebeZiele(g, muster);
});

final projektRezepturenProvider =
    StreamProvider.autoDispose.family<List<Rezeptur>, String>(
  (ref, projektId) =>
      ref.watch(projektRepositoryProvider).rezepturenBeobachten(projektId),
);

final fliessdiagrammeProvider = StreamProvider<List<Fliessdiagramm>>(
  (ref) => ref.watch(projektRepositoryProvider).fliessdiagrammeBeobachten(),
);
