import 'package:drift/drift.dart';

import '../../../core/database/database.dart';
import '../daten/dateien.dart';
import '../daten/entwicklung_repository.dart';
import '../freigabe/freigabe.dart' show FreigabeDienst, VerlustAbgleich;
import '../projekte/entwicklungsstrang.dart';
import '../projekte/fliessdiagramm_liste.dart';
import '../projekte/projekt_checkliste.dart';
import '../rechenkern/rechen_modell.dart';
import '../rechenkern/rechenkern.dart';

export 'bericht_pdf.dart' show baueProjektPdf;

// Der Projektbericht: alles, was zu einem Projekt gehört, zum Nachschlagen
// und Ablegen — ob es noch läuft oder längst freigegeben ist. Hier steht,
// was er braucht, und wie es aus der Datenbank kommt; gesetzt wird er in
// bericht_pdf.dart.

/// Ein Stand, der gerade in Arbeit ist.
typedef InArbeit = ({String rezeptur, RezepturVersion version});

/// Ein Schritt aus dem freigegebenen Artikel mit den tatsächlich
/// gespeicherten Einstellungen.
typedef BerichtArtikelSchritt = ({
  ProductStep schritt,
  Machine? maschine,
  List<ProductStepParameter> parameter,
});

/// Was im Bericht steht.
class ProjektBericht {
  const ProjektBericht({
    required this.projekt,
    this.rezepturName,
    this.version,
    this.eingabe,
    this.ergebnis,
    this.verlauf = const [],
    this.bild,
    this.artikel,
    this.artikelSchritte = const [],
    this.abgleich,
    this.fliessdiagramm,
    this.checkliste,
    this.rezepturen = const [],
    this.versionen = const {},
    this.eingaben = const {},
    this.ergebnisse = const {},
    this.kennzahlen = const {},
    this.inArbeit = const [],
    this.dateien = const [],
    this.gesamtprojekt,
    this.muster = const [],
    this.gesamtVerlauf = const [],
  });

  final EntwicklungsProjekt projekt;
  final String? rezepturName;

  /// Der Stand, um den es geht: der freigegebene, sonst der neueste
  /// abgeschlossene, sonst der neueste.
  final RezepturVersion? version;

  /// Seine Zusammensetzung und was der Rechenkern daraus macht.
  final RechenRezeptur? eingabe;
  final RezepturErgebnis? ergebnis;

  /// Der neueste Eintrag zuerst.
  final List<ProjektEintrag> verlauf;

  /// Das Produktbild (PNG oder JPEG), entschlüsselt.
  final Uint8List? bild;

  /// Der freigegebene Artikel — auch, wenn er im Planer gelöscht ist.
  final Product? artikel;

  /// Die Prozessschritte des freigegebenen Artikels samt Maschinenwerten.
  final List<BerichtArtikelSchritt> artikelSchritte;

  /// Der Verlust der erfassten Produktionen gegen den der Rezeptur — null
  /// ohne Freigabe oder ohne Produktion.
  final VerlustAbgleich? abgleich;

  /// Das Fließdiagramm mit Bezeichnung, etwa „FD_011 · Schnitzel paniert"
  /// — null: nur die Kennung aus dem Projekt.
  final String? fliessdiagramm;

  /// Die Projekt-Checkliste, wie sie gerade steht — null: aus dem Projekt
  /// allein gerechnet (ohne Rezepturen).
  final ProjektCheckStand? checkliste;

  /// Die Rezepturen des Projekts, nach Namen.
  final List<Rezeptur> rezepturen;

  /// Die Rezepturstände — die des Projekts und die, um die es im Verlauf
  /// geht —, nach ID.
  final Map<String, RezepturVersion> versionen;

  /// Zusammensetzung und Ergebnis je Stand (ID).
  final Map<String, RechenRezeptur> eingaben;
  final Map<String, RezepturErgebnis> ergebnisse;

  /// Je Station (Stand-ID) die Kennzahlen mit der Änderung zum vorigen
  /// Stand derselben Rezeptur.
  final Map<String, List<WegKennzahl>> kennzahlen;

  /// Stände, die noch nicht abgeschlossen sind und keine Station — der
  /// älteste zuerst.
  final List<InArbeit> inArbeit;

  /// Die Dateien des Projekts, die älteste zuerst.
  final List<EntwicklungsDatei> dateien;

  /// Das Gesamtprojekt, zu dem das Projekt als Muster gehört — null für
  /// ein Projekt für sich.
  final Gesamtprojekt? gesamtprojekt;

  /// Alle Muster des Gesamtprojekts, in der Reihenfolge des Anlegens —
  /// dieses eingeschlossen.
  final List<EntwicklungsProjekt> muster;

  /// Der Verlauf des Gesamtprojekts, der neueste Eintrag zuerst: die
  /// Korrespondenz und Unterlagen, die alle Muster betreffen.
  final List<ProjektEintrag> gesamtVerlauf;

  /// So steht ein Eintrag aus dem Gesamtprojekt im Bericht eines Musters.
  static const String gesamtMarke = ' (Gesamtprojekt)';

  /// Der Bericht mit dem Verlauf des Gesamtprojekts im eigenen — dessen
  /// Einträge mit „(Gesamtprojekt)" hinter dem Titel.
  ProjektBericht mitGesamtVerlauf() {
    if (gesamtVerlauf.isEmpty) return this;
    final verlauf = [
      ...this.verlauf,
      for (final e in gesamtVerlauf)
        e.copyWith(titel: '${e.titel}$gesamtMarke'),
    ]..sort((a, b) {
        final d = b.datum.compareTo(a.datum);
        return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
      });
    return ProjektBericht(
      projekt: projekt,
      rezepturName: rezepturName,
      version: version,
      eingabe: eingabe,
      ergebnis: ergebnis,
      verlauf: verlauf,
      bild: bild,
      artikel: artikel,
      artikelSchritte: artikelSchritte,
      abgleich: abgleich,
      fliessdiagramm: fliessdiagramm,
      checkliste: checkliste,
      rezepturen: rezepturen,
      versionen: versionen,
      eingaben: eingaben,
      ergebnisse: ergebnisse,
      kennzahlen: kennzahlen,
      inArbeit: inArbeit,
      dateien: dateien,
      gesamtprojekt: gesamtprojekt,
      muster: muster,
      gesamtVerlauf: gesamtVerlauf,
    );
  }
}

/// Lädt alles für den Bericht.
Future<ProjektBericht> berichtLaden(
  AppDatabase db,
  EntwicklungDateienDienst dateien,
  EntwicklungsProjekt projekt,
) async {
  final repo = EntwicklungRepository(db);
  final rezepturen =
      await (db.select(db.entwicklungRezepturen)
            ..where((r) => r.projektId.equals(projekt.id))
            ..where((r) => r.deletedAt.isNull())
            ..orderBy([(r) => OrderingTerm.asc(r.name)]))
          .get();
  final versionen = <RezepturVersion>[];
  for (final r in rezepturen) {
    versionen.addAll(
      await (db.select(db.entwicklungRezepturVersionen)
            ..where((v) => v.rezepturId.equals(r.id))
            ..orderBy([(v) => OrderingTerm.asc(v.nummer)]))
          .get(),
    );
  }
  RezepturVersion? version;
  for (final v in versionen) {
    if (v.id == projekt.freigabeVersionId) version = v;
  }
  if (version == null) {
    // Der neueste zuerst — bei gleicher Zeit der mit der höheren Nummer.
    int neuer(
      RezepturVersion a,
      RezepturVersion b,
      DateTime Function(RezepturVersion v) zeit,
    ) {
      final z = zeit(b).compareTo(zeit(a));
      return z != 0 ? z : b.nummer.compareTo(a.nummer);
    }

    final abgeschlossen =
        versionen.where((v) => v.status == VersionStatus.abgeschlossen).toList()
          ..sort(
            (a, b) => neuer(a, b, (v) => v.abgeschlossenAm ?? v.updatedAt),
          );
    final alle = [...versionen]
      ..sort((a, b) => neuer(a, b, (v) => v.updatedAt));
    version = abgeschlossen.firstOrNull ?? alle.firstOrNull;
  }
  final rezeptur = rezepturen
      .where((r) => r.id == version?.rezepturId)
      .firstOrNull;

  final verlauf =
      await (db.select(db.entwicklungProjektEintraege)
            ..where((e) => e.projektId.equals(projekt.id))
            ..orderBy([
              (e) => OrderingTerm.desc(e.datum),
              (e) => OrderingTerm.desc(e.createdAt),
            ]))
          .get();

  Uint8List? bild;
  final bildId = projekt.bildDateiId;
  if (bildId != null) {
    try {
      bild = await dateien.lesen(bildId);
    } catch (_) {
      bild = null;
    }
  }

  final artikelId = projekt.artikelId;
  final artikel = artikelId == null
      ? null
      : await (db.select(
          db.products,
        )..where((p) => p.id.equals(artikelId))).getSingleOrNull();
  final artikelSchritte = <BerichtArtikelSchritt>[];
  VerlustAbgleich? abgleich;
  if (artikel != null) {
    final schritte =
        await (db.select(db.productSteps)
              ..where((s) => s.productId.equals(artikel.id))
              ..where((s) => s.deletedAt.isNull())
              ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
            .get();
    for (final schritt in schritte) {
      final parameter =
          await (db.select(db.productStepParameters)
                ..where((p) => p.stepId.equals(schritt.id))
                ..where((p) => p.deletedAt.isNull())
                ..orderBy([
                  (p) => OrderingTerm.asc(p.reihenfolge),
                  (p) => OrderingTerm.asc(p.parameterGruppe),
                ]))
              .get();
      final maschineId = schritt.maschineId;
      final maschine = maschineId == null
          ? null
          : await (db.select(
              db.machines,
            )..where((m) => m.id.equals(maschineId))).getSingleOrNull();
      artikelSchritte.add(
        (schritt: schritt, maschine: maschine, parameter: parameter),
      );
    }
    final versionId = projekt.freigabeVersionId;
    if (artikel.deletedAt == null && versionId != null) {
      try {
        abgleich = await FreigabeDienst(db)
            .verlustAbgleich(artikel.id, versionId);
      } catch (_) {
        abgleich = null;
      }
    }
  }

  // Die Stände des Entwicklungswegs — auch solche, deren Rezeptur nicht
  // mehr zum Projekt gehört.
  final versionenNachId = {for (final v in versionen) v.id: v};
  final weg = entwicklungsweg(verlauf);
  final stationen = weg.whereType<WegStation>().toList();
  for (final id in {
    for (final s in stationen) s.versionId,
    for (final w in weg.whereType<WegPhase>())
      if (w.eintrag.versionId case final id?) id,
  }) {
    if (versionenNachId.containsKey(id)) continue;
    final v = await repo.version(id);
    if (v != null) versionenNachId[id] = v;
  }

  // Zusammensetzung und Ergebnis jedes Stands — für den Vergleich der
  // Stände und die Kennzahlen der Stationen.
  final eingaben = <String, RechenRezeptur>{};
  final ergebnisse = <String, RezepturErgebnis>{};
  for (final id in versionenNachId.keys) {
    final e = await repo.rechenRezeptur(id);
    if (e == null) continue;
    eingaben[id] = e;
    ergebnisse[id] = berechne(e);
  }

  // Die Kennzahlen jeder Station mit der Änderung zur vorigen Station
  // derselben Rezeptur — wie in der Ansicht „Entwicklungsweg".
  final kennzahlen = <String, List<WegKennzahl>>{};
  final letzte = <String, String>{};
  for (final s in stationen) {
    final rezepturId = versionenNachId[s.versionId]?.rezepturId;
    final davor = rezepturId == null ? null : letzte[rezepturId];
    final neu = ergebnisse[s.versionId];
    if (neu != null) {
      kennzahlen[s.versionId] = wegKennzahlen(
        neu,
        vorher: davor == null ? null : ergebnisse[davor],
      );
    }
    if (rezepturId != null) letzte[rezepturId] = s.versionId;
  }
  final stationIds = {for (final s in stationen) s.versionId};
  final namen = {for (final r in rezepturen) r.id: r.name};
  final inArbeit = <InArbeit>[
    for (final v in versionen)
      if (v.status == VersionStatus.entwurf && !stationIds.contains(v.id))
        (rezeptur: namen[v.rezepturId] ?? '', version: v),
  ]..sort((a, b) => a.version.updatedAt.compareTo(b.version.updatedAt));

  final projektDateien =
      await (db.select(db.entwicklungDateien)
            ..where((d) => d.projektId.equals(projekt.id))
            ..orderBy([(d) => OrderingTerm.asc(d.createdAt)]))
          .get();

  // Ein Muster: sein Gesamtprojekt, die Muster und dessen Verlauf.
  final gid = projekt.gesamtprojektId;
  final gesamtprojekt = gid == null
      ? null
      : await (db.select(
          db.entwicklungGesamtprojekte,
        )..where((g) => g.id.equals(gid))).getSingleOrNull();
  final muster = gesamtprojekt == null
      ? const <EntwicklungsProjekt>[]
      : await (db.select(db.entwicklungProjekte)
              ..where((p) => p.gesamtprojektId.equals(gesamtprojekt.id))
              ..where((p) => p.deletedAt.isNull())
              ..orderBy([
                (p) => OrderingTerm.asc(p.createdAt),
                (p) => OrderingTerm.asc(p.name),
              ]))
            .get();
  final gesamtVerlauf = gesamtprojekt == null
      ? const <ProjektEintrag>[]
      : await (db.select(db.entwicklungProjektEintraege)
              ..where((e) => e.projektId.equals(gesamtprojekt.id))
              ..orderBy([
                (e) => OrderingTerm.desc(e.datum),
                (e) => OrderingTerm.desc(e.createdAt),
              ]))
            .get();

  return ProjektBericht(
    projekt: projekt,
    rezepturName: rezeptur?.name,
    version: version,
    eingabe: version == null ? null : eingaben[version.id],
    ergebnis: version == null ? null : ergebnisse[version.id],
    verlauf: verlauf,
    bild: bild,
    artikel: artikel,
    artikelSchritte: artikelSchritte,
    abgleich: abgleich,
    fliessdiagramm: await _fliessdiagrammText(db, projekt.fliessdiagramm),
    checkliste: projektCheckStand(
      projekt: projekt,
      rezepturen: rezepturen,
      versionen: versionen,
    ),
    rezepturen: rezepturen,
    versionen: versionenNachId,
    eingaben: eingaben,
    ergebnisse: ergebnisse,
    kennzahlen: kennzahlen,
    inArbeit: inArbeit,
    dateien: projektDateien,
    gesamtprojekt: gesamtprojekt,
    muster: muster,
    gesamtVerlauf: gesamtVerlauf,
  );
}

/// Kennung und Bezeichnung des Fließdiagramms.
Future<String?> _fliessdiagrammText(AppDatabase db, String? fdId) async {
  if (fdId == null || fdId.isEmpty) return null;
  final fd = await (db.select(
    db.entwicklungFliessdiagramme,
  )..where((f) => f.id.equals(fdId))).getSingleOrNull();
  return fdText(fdId, bezeichnung: fd?.bezeichnung);
}
