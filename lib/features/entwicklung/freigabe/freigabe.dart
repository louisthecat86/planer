import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/constants/product_groups.dart';
import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/prozesskette_service.dart';
import '../../whiteboard/whiteboard_provider.dart' show ausbeuteAusProduktionen;
import '../daten/entwicklung_repository.dart';
import '../entwicklung_format.dart';
import '../haccp/anlagen_katalog.dart' show anlagenLaden, ketteAusArtikel;
import '../haccp/prozess_kette.dart' show prozessKurztext;
import '../haccp/prozess_modell.dart';
import '../projekte/entwicklungsstrang.dart' show statusWert;
import '../projekte/projekt_modell.dart';
import '../projekte/projekt_repository.dart';
import '../rechenkern/rechen_modell.dart';
import '../rechenkern/rechenkern.dart';
import '../spezifikation/spez_angaben.dart'
    show SpezAngaben, haltbarkeitInTagen;
import 'kette_uebernahme.dart';

// Freigabe: Ein Projekt wird zum Artikel des Planers. Aus dem
// abgeschlossenen Rezepturstand kommen die Allergene, aus dem Projekt
// Nummer, Bezeichnung, Haltbarkeit (aus den Angaben im Reiter „Produkt")
// und aw-Wert; nur die Produktgruppe trägt man dabei ein. Den Verlust des
// Stands nimmt die Planung als Vorgabe, solange keine Produktion erfasst
// ist (core/services/entwicklung_vorgabe.dart).
//
// Die Prozesskette des Projekts wird die des Artikels (F35): Schritte, die
// einander entsprechen, bleiben derselbe Schritt — mit Personen und
// Leistungsdaten —, neue kommen dazu, was das Projekt nicht mehr hat,
// entfällt auf Wunsch (kette_uebernahme.dart). Es zählt der jetzige Stand;
// weicht er von der zuletzt festgehaltenen Version ab, wird er vorher als
// neue Version festgehalten (F36).
//
// Danach vergleicht der Abgleich den Verlust der erfassten Produktionen
// mit dem der Rezeptur — weicht er ab, stimmt auch der Fleischanteil auf
// dem Etikett nicht mehr.

/// Ab dieser Abweichung des gemessenen Verlusts (Prozentpunkte) gibt es
/// einen Hinweis.
const double kVerlustToleranz = 2;

/// Ab dieser Abweichung des Fleischanteils (Prozentpunkte) gibt es einen
/// Hinweis.
const double kFleischToleranz = 0.5;

/// Felder, die eine Freigabe in den Artikel schreiben kann.
enum FreigabeFeld {
  bezeichnung('Bezeichnung'),
  produktgruppe('Produktgruppe'),
  haltbarkeit('Haltbarkeit'),
  allergene('Allergene'),
  aw('aw-Wert');

  const FreigabeFeld(this.label);

  final String label;
}

/// Was die Freigabe in den Artikel schreibt.
class FreigabeWerte {
  const FreigabeWerte({
    required this.artikelnummer,
    required this.bezeichnung,
    this.produktgruppe,
    this.haltbarkeitTage,
    this.allergene,
    this.verlustProzent,
    this.aw,
  });

  final String artikelnummer;
  final String bezeichnung;

  /// [ProductGroup.dbValue].
  final String? produktgruppe;
  final int? haltbarkeitTage;

  /// Kommaliste der Planer-Werte; null: nicht bei allen Zutaten gepflegt.
  final String? allergene;

  /// Verlust des Stands in Prozent — nur zur Anzeige: Die Planung liest
  /// ihn aus der Freigabe, er wird nicht in den Artikel geschrieben.
  final double? verlustProzent;
  final double? aw;

  FreigabeWerte kopie({
    String? artikelnummer,
    String? bezeichnung,
    String? produktgruppe,
    int? haltbarkeitTage,
  }) =>
      FreigabeWerte(
        artikelnummer: artikelnummer ?? this.artikelnummer,
        bezeichnung: bezeichnung ?? this.bezeichnung,
        produktgruppe: produktgruppe ?? this.produktgruppe,
        haltbarkeitTage: haltbarkeitTage ?? this.haltbarkeitTage,
        allergene: allergene,
        verlustProzent: verlustProzent,
        aw: aw,
      );

  /// Der Wert eines Felds als Text für die Anzeige.
  String text(FreigabeFeld f) => switch (f) {
        FreigabeFeld.bezeichnung => bezeichnung,
        FreigabeFeld.produktgruppe => _gruppe(produktgruppe),
        FreigabeFeld.haltbarkeit =>
          haltbarkeitTage == null ? '—' : '$haltbarkeitTage Tage',
        FreigabeFeld.allergene => _allergene(allergene),
        FreigabeFeld.aw => aw == null ? '—' : feldText(aw),
      };
}

String _gruppe(String? dbValue) {
  for (final g in ProductGroup.values) {
    if (g.dbValue == dbValue) return g.label;
  }
  return dbValue ?? '—';
}

String _allergene(String? text) {
  if (text == null || text.trim().isEmpty) return 'nicht gepflegt';
  final label = merkmaleLabel(text, kAllergene);
  return label.isEmpty ? text : label;
}

/// Der Stand des Artikels zu einem Feld — als Text, wie [FreigabeWerte.text].
String artikelText(Product p, FreigabeFeld f) => switch (f) {
      FreigabeFeld.bezeichnung => p.artikelbezeichnung,
      FreigabeFeld.produktgruppe => _gruppe(p.produktgruppe),
      FreigabeFeld.haltbarkeit =>
        p.haltbarkeitTage == null ? '—' : '${p.haltbarkeitTage} Tage',
      FreigabeFeld.allergene => _allergene(p.allergene),
      FreigabeFeld.aw => p.zielAw == null ? '—' : feldText(p.zielAw),
    };

/// Ob die Freigabe [f] am Artikel ändern würde. Leere Werte der Freigabe
/// ändern nichts.
bool aendertFeld(Product p, FreigabeWerte w, FreigabeFeld f) {
  bool anders(double? a, double? b) =>
      b != null && (a == null || (a - b).abs() > 1e-9);
  return switch (f) {
    FreigabeFeld.bezeichnung =>
      w.bezeichnung.trim().isNotEmpty &&
          w.bezeichnung.trim() != p.artikelbezeichnung,
    FreigabeFeld.produktgruppe =>
      w.produktgruppe != null && w.produktgruppe != p.produktgruppe,
    FreigabeFeld.haltbarkeit =>
      w.haltbarkeitTage != null && w.haltbarkeitTage != p.haltbarkeitTage,
    FreigabeFeld.allergene => w.allergene != null &&
        !_gleicheMenge(
          merkmaleAusText(w.allergene),
          merkmaleAusText(p.allergene),
        ),
    FreigabeFeld.aw => anders(p.zielAw, w.aw),
  };
}

bool _gleicheMenge(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// Die Allergene einer Rezeptur als Kommaliste: die genannten — „keine",
/// wenn alle Zutaten gepflegt sind und keins enthalten, sonst null.
String? allergeneFuerArtikel(RechenRezeptur r, RezepturErgebnis e) {
  if (e.allergene.isNotEmpty) {
    return merkmaleZuText(e.allergene.keys, kAllergene);
  }
  bool allesGepflegt(RechenRezeptur x) => x.positionen.every((p) {
        final z = p.zutat;
        if (z != null) return z.allergene.isNotEmpty;
        final u = p.unterrezeptur;
        return u == null || allesGepflegt(u);
      });
  return allesGepflegt(r) ? kAllergenKeine : null;
}

/// Ein Rezepturstand, der sich freigeben lässt.
class FreigabeStand {
  const FreigabeStand({required this.rezeptur, required this.version});

  final Rezeptur rezeptur;
  final RezepturVersion version;

  String get label {
    final b = version.bezeichnung?.trim() ?? '';
    return '${rezeptur.name} · Stand ${version.nummer}'
        '${b.isEmpty ? '' : ' · $b'}';
  }
}

/// Der Vergleich von Rezeptur und erfassten Produktionen.
class VerlustAbgleich {
  const VerlustAbgleich({
    required this.produktionen,
    required this.gemessenProzent,
    required this.rezepturProzent,
    this.fleischRezeptur,
    this.fleischGemessen,
    this.zutatenlisteRezeptur,
    this.zutatenlisteGemessen,
  });

  /// Aus wie vielen Produktionen der Schnitt stammt.
  final int produktionen;
  final double gemessenProzent;
  final double rezepturProzent;

  /// Fleischanteil mit dem Verlust der Rezeptur bzw. dem gemessenen — null
  /// ohne Fleisch.
  final double? fleischRezeptur;
  final double? fleischGemessen;

  final String? zutatenlisteRezeptur;
  final String? zutatenlisteGemessen;

  double get differenz => gemessenProzent - rezepturProzent;

  bool get verlustWeichtAb => differenz.abs() >= kVerlustToleranz;

  /// Das Etikett nennt mehr Fleisch, als nach dem gemessenen Verlust drin
  /// ist.
  bool get fleischZuHoch {
    final r = fleischRezeptur;
    final g = fleischGemessen;
    return r != null && g != null && r - g >= kFleischToleranz;
  }

  /// Das Etikett nennt weniger Fleisch — unbedenklich, aber verschenkt.
  bool get fleischZuNiedrig {
    final r = fleischRezeptur;
    final g = fleischGemessen;
    return r != null && g != null && g - r >= kFleischToleranz;
  }
}

/// Was die Übersicht zur Freigabe zeigt.
class FreigabeUebersicht {
  const FreigabeUebersicht({
    this.artikel,
    this.stand,
    this.abgleich,
    this.staende = const [],
  });

  /// Der freigegebene Artikel — null, solange nicht freigegeben (oder er
  /// gelöscht ist).
  final Product? artikel;

  /// Der freigegebene Stand.
  final FreigabeStand? stand;

  final VerlustAbgleich? abgleich;

  /// Abgeschlossene Stände der Rezepturen des Projekts, neueste zuerst.
  final List<FreigabeStand> staende;
}

/// Lesen und Schreiben rund um die Freigabe.
class FreigabeDienst {
  FreigabeDienst(this._db)
      : _rezepte = EntwicklungRepository(_db),
        _projekte = ProjektRepository(_db);

  final AppDatabase _db;
  final EntwicklungRepository _rezepte;
  final ProjektRepository _projekte;
  static const Uuid _uuid = Uuid();

  /// Abgeschlossene Stände der Rezepturen eines Projekts, neueste zuerst.
  Future<List<FreigabeStand>> staende(String projektId) async {
    final rezepturen = await (_db.select(_db.entwicklungRezepturen)
          ..where((r) => r.projektId.equals(projektId))
          ..where((r) => r.deletedAt.isNull()))
        .get();
    final liste = <FreigabeStand>[];
    for (final r in rezepturen) {
      final versionen = await (_db.select(_db.entwicklungRezepturVersionen)
            ..where((v) => v.rezepturId.equals(r.id))
            ..where((v) => v.status.equals(VersionStatus.abgeschlossen)))
          .get();
      for (final v in versionen) {
        liste.add(FreigabeStand(rezeptur: r, version: v));
      }
    }
    liste.sort(
      (a, b) => (b.version.abgeschlossenAm ?? b.version.updatedAt)
          .compareTo(a.version.abgeschlossenAm ?? a.version.updatedAt),
    );
    return liste;
  }

  /// Die Prozesskette des Artikels [artikelId] — die Schritte unter ihrer
  /// ID im Artikel.
  Future<List<ProzessSchritt>> artikelKette(String artikelId) async =>
      ketteAusArtikel(
        _db,
        artikelId,
        katalog: await anlagenLaden(_db),
      );

  /// Ein Artikel mit dieser Nummer — auch ein gelöschter.
  Future<Product?> artikelZuNummer(String nummer) =>
      (_db.select(_db.products)
            ..where((p) => p.artikelnummer.equals(nummer.trim())))
          .getSingleOrNull();

  /// Was die Freigabe des Stands [versionId] schreiben würde.
  Future<FreigabeWerte> vorschlag(
    EntwicklungsProjekt projekt,
    String versionId,
  ) async {
    final eingabe = await _rezepte.rechenRezeptur(versionId);
    final version = await _rezepte.version(versionId);
    final rezeptur =
        version == null ? null : await _rezepte.rezeptur(version.rezepturId);
    String? allergene;
    double? verlust;
    if (eingabe != null) {
      allergene = allergeneFuerArtikel(eingabe, berechne(eingabe));
      final v = eingabe.wirksamerVerlust;
      if (v > 0 && v < 100) verlust = v;
    }
    final vorhanden = projekt.artikelId == null
        ? null
        : await (_db.select(_db.products)
              ..where((p) => p.id.equals(projekt.artikelId!)))
            .getSingleOrNull();
    final nummer = projekt.artikelnummer?.trim().isNotEmpty == true
        ? projekt.artikelnummer!.trim()
        : (rezeptur?.artikelnummer?.trim() ?? vorhanden?.artikelnummer ?? '');
    // Was im Projekt schon steht, wird nicht noch einmal gefragt.
    final angaben = SpezAngaben.aus(projekt.spezifikation);
    final bezeichnung = angaben.bezeichnung.trim();
    return FreigabeWerte(
      artikelnummer: nummer,
      bezeichnung: bezeichnung.isNotEmpty
          ? bezeichnung
          : (vorhanden?.artikelbezeichnung ?? projekt.name),
      produktgruppe: vorhanden?.produktgruppe,
      haltbarkeitTage: haltbarkeitInTagen(angaben.haltbarkeit) ??
          vorhanden?.haltbarkeitTage,
      allergene: allergene,
      verlustProzent: verlust,
      aw: projekt.grenzeAw,
    );
  }

  /// Gibt den Stand [versionId] als Artikel frei: legt ihn an oder schreibt
  /// [felder] in den vorhandenen. Mit [prozessUebernehmen] wird die Kette
  /// des Projekts die des Artikels — mit [prozessEntfernen] entfällt dabei,
  /// was das Projekt nicht mehr hat. Gibt die ID des Artikels zurück.
  Future<String> freigeben({
    required EntwicklungsProjekt projekt,
    required String versionId,
    required FreigabeWerte werte,
    Set<FreigabeFeld> felder = const {...FreigabeFeld.values},
    bool prozessUebernehmen = true,
    bool prozessEntfernen = true,
  }) async {
    final nummer = werte.artikelnummer.trim();
    if (nummer.isEmpty) {
      throw ArgumentError('Ohne Artikelnummer lässt sich nichts freigeben.');
    }
    final jetzt = DateTime.now();
    late final String artikelId;
    final geschrieben = <String>[];
    await _db.transaction(() async {
      final vorhanden = await artikelZuNummer(nummer);
      // Ein neuer Artikel bekommt alles, was da ist; ein vorhandener nur
      // die gewählten Felder, die sich ändern.
      Value<T> wert<T extends Object>(FreigabeFeld f, T? neu) {
        if (neu == null) return Value<T>.absent();
        if (vorhanden != null &&
            !(felder.contains(f) && aendertFeld(vorhanden, werte, f))) {
          return Value<T>.absent();
        }
        geschrieben.add(f.label);
        return Value(neu);
      }

      final gruppe = wert(FreigabeFeld.produktgruppe, werte.produktgruppe);
      final daten = ProductsCompanion(
        artikelbezeichnung: werte.bezeichnung.trim().isEmpty
            ? const Value.absent()
            : wert(FreigabeFeld.bezeichnung, werte.bezeichnung.trim()),
        produktgruppe: gruppe,
        haltbarkeitTage:
            wert(FreigabeFeld.haltbarkeit, werte.haltbarkeitTage),
        allergene: wert(FreigabeFeld.allergene, werte.allergene),
        zielAw: wert(FreigabeFeld.aw, werte.aw),
        updatedAt: Value(jetzt),
      );
      if (vorhanden == null) {
        artikelId = _uuid.v4();
        await _db.into(_db.products).insert(
              daten.copyWith(
                id: Value(artikelId),
                artikelnummer: Value(nummer),
                artikelbezeichnung: Value(
                  werte.bezeichnung.trim().isEmpty
                      ? nummer
                      : werte.bezeichnung.trim(),
                ),
                // Mit Produktgruppe ist die Maske gepflegt; Prozessschritte
                // fehlen noch — das meldet die Artikelliste.
                istEingepflegt: Value(werte.produktgruppe != null),
                createdAt: Value(jetzt),
              ),
            );
      } else {
        artikelId = vorhanden.id;
        await (_db.update(_db.products)..where((p) => p.id.equals(artikelId)))
            .write(
          daten.copyWith(
            deletedAt: const Value(null),
            istEingepflegt: vorhanden.deletedAt != null
                ? const Value(false)
                : (gruppe.present ? const Value(true) : const Value.absent()),
          ),
        );
      }

      // Geht das Projekt damit in Produktion, hält der Meilenstein den
      // Wechsel fest — wie ein Statuswechsel von Hand (Phasen im Verlauf).
      final aktuell = await _projekte.projekt(projekt.id);
      final vorher = ProjektStatus.aus(aktuell?.status ?? projekt.status);
      // Nur den Punkt setzen — zurückgestellte bleiben zurückgestellt.
      final checkliste = checklisteMit(
        aktuell?.checkliste ?? projekt.checkliste,
        'artikelAngelegt',
        true,
      );
      final kette = prozessUebernehmen
          ? await _ketteUebernehmen(
              artikelId: artikelId,
              nummer: nummer,
              prozess: Prozessparameter.aus(
                aktuell?.prozess ?? projekt.prozess,
              ),
              historie: ProzessStand.listeAus(
                aktuell?.prozessHistorie ?? projekt.prozessHistorie,
              ),
              entfernen: prozessEntfernen,
              jetzt: jetzt,
            )
          : null;
      final festgehalten = kette?.festgehalten;
      await _projekte.projektAendern(
        projekt.id,
        EntwicklungProjekteCompanion(
          artikelId: Value(artikelId),
          artikelnummer: Value(nummer),
          freigabeVersionId: Value(versionId),
          freigegebenAm: Value(jetzt),
          status: Value(ProjektStatus.produktion.schluessel),
          checkliste: Value(checkliste),
          prozess: festgehalten == null
              ? const Value.absent()
              : Value(festgehalten.prozess.alsJson()),
          prozessHistorie: festgehalten == null
              ? const Value.absent()
              : Value(ProzessStand.listeZuJson(festgehalten.historie)),
        ),
      );
      // Eine Version, die erst die Freigabe festhält, steht im Verlauf wie
      // eine von Hand festgehaltene.
      if (festgehalten != null) {
        final stand = festgehalten.historie.last;
        await _projekte.eintragAnlegen(
          projektId: projekt.id,
          art: EintragArt.parameter,
          titel: 'Prozessparameter ${stand.version}',
          datum: DateTime(jetzt.year, jetzt.month, jetzt.day),
          beschreibung: stand.notiz,
          status: EintragStatus.erledigt,
          wert: festgehalten.prozess.alsJson(),
        );
      }
      final version = await _rezepte.version(versionId);
      await _projekte.eintragAnlegen(
        projektId: projekt.id,
        art: EintragArt.meilenstein,
        titel: vorhanden == null
            ? 'Freigegeben als neuer Artikel $nummer'
            : 'Freigegeben für Artikel $nummer',
        datum: DateTime(jetzt.year, jetzt.month, jetzt.day),
        status: EintragStatus.erledigt,
        versionId: versionId,
        beschreibung:
            version == null ? null : 'Rezepturstand ${version.nummer}',
        aenderungen: [
          if (geschrieben.isNotEmpty) 'Geschrieben: ${geschrieben.join(', ')}',
          if (kette != null) kette.text,
          if (geschrieben.isEmpty && kette == null) 'Nichts geändert',
        ],
        wert: vorher == ProjektStatus.produktion
            ? null
            : statusWert(vorher, ProjektStatus.produktion),
      );
    });
    return artikelId;
  }

  /// Übernimmt die Kette [prozess] des Projekts in den Artikel — null,
  /// wenn es keine gibt, die sich übernehmen lässt (keine Schritte, noch
  /// frühere Abschnitte oder eine Station ohne Abteilung). Weicht der
  /// Stand von der zuletzt festgehaltenen Version ab, wird er als neue
  /// festgehalten (F36) — das Ergebnis nennt sie, damit sie ins Projekt
  /// kommt.
  Future<
      ({
        String text,
        ({Prozessparameter prozess, List<ProzessStand> historie})?
            festgehalten,
      })?> _ketteUebernehmen({
    required String artikelId,
    required String nummer,
    required Prozessparameter prozess,
    required List<ProzessStand> historie,
    required bool entfernen,
    required DateTime jetzt,
  }) async {
    if (!kannKetteUebernehmen(prozess)) return null;
    final fassung = prozessFassung(prozess, historie);
    ({Prozessparameter prozess, List<ProzessStand> historie})? festgehalten;
    var stand = prozess;
    var nummerDerVersion = fassung.version ?? prozess.version;
    if (fassung.geaendert) {
      nummerDerVersion = naechsteProzessVersion(prozess, historie);
      stand = prozess.kopie(version: nummerDerVersion, stand: jetzt);
      festgehalten = (
        prozess: stand,
        historie: [
          ...historie,
          ProzessStand(
            version: nummerDerVersion,
            datum: jetzt,
            notiz: 'Bei der Freigabe für Artikel $nummer festgehalten',
            parameter: stand,
          ),
        ],
      );
    }
    final ziel = zielKette(
      await artikelKette(artikelId),
      stand.schritte,
      entfernen: entfernen,
    );
    final ids = await ProzesskettenService.uebernehmen(_db, artikelId, [
      for (final z in ziel)
        (
          id: z.artikelId,
          abteilung: z.schritt.abteilung,
          maschineId: z.schritt.maschineId,
          maschine: _oderNull(z.schritt.maschine),
          prozessschritt: _oderNull(z.schritt.prozessschritt),
        ),
    ]);
    for (final (i, z) in ziel.indexed) {
      await _werteSchreiben(
        ids[i],
        z.schritt,
        // Ein neuer Schritt hat nichts, was entfallen könnte.
        entfernen: entfernen || z.artikelId == null,
      );
    }
    return (
      text: 'Prozess Version $nummerDerVersion übernommen: '
          '${prozessKurztext(Prozessparameter(schritte: stand.schritte))}',
      festgehalten: festgehalten,
    );
  }

  /// Schreibt die Werte von [soll] an den Schritt [stepId] im Artikel.
  Future<void> _werteSchreiben(
    String stepId,
    ProzessSchritt soll, {
    required bool entfernen,
  }) async {
    final zeilen = await (_db.select(_db.productStepParameters)
          ..where((p) => p.stepId.equals(stepId))
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final aktionen = werteAbgleichen(
      [
        for (final z in zeilen)
          (
            id: z.id,
            gruppe: z.parameterGruppe,
            name: z.parameterName,
            wert: z.wert,
            eigen: z.istCustom,
            reihenfolge: z.reihenfolge,
          ),
      ],
      soll,
      entfernen: entfernen,
    );
    final jetzt = DateTime.now();
    for (final a in aktionen) {
      switch (a) {
        case WertSetzen(:final id, :final wert):
          await (_db.update(_db.productStepParameters)
                ..where((p) => p.id.equals(id)))
              .write(
            ProductStepParametersCompanion(
              wert: Value(wert),
              updatedAt: Value(jetzt),
            ),
          );
        case WertAnlegen():
          await _db.into(_db.productStepParameters).insert(
                ProductStepParametersCompanion.insert(
                  id: _uuid.v4(),
                  stepId: stepId,
                  parameterGruppe: a.gruppe,
                  parameterName: a.name,
                  wert: Value(a.wert),
                  reihenfolge: Value(a.reihenfolge),
                  istCustom: Value(a.eigen),
                ),
              );
        case WertLoeschen(:final id):
          await (_db.update(_db.productStepParameters)
                ..where((p) => p.id.equals(id)))
              .write(
            ProductStepParametersCompanion(
              deletedAt: Value(jetzt),
              updatedAt: Value(jetzt),
            ),
          );
      }
    }
  }

  /// Der freigegebene Artikel, der Stand und der Abgleich mit den
  /// erfassten Produktionen.
  Future<FreigabeUebersicht> uebersicht(EntwicklungsProjekt projekt) async {
    final staende = await this.staende(projekt.id);
    final artikelId = projekt.artikelId;
    final versionId = projekt.freigabeVersionId;
    final artikel = artikelId == null
        ? null
        : await (_db.select(_db.products)
              ..where((p) => p.id.equals(artikelId))
              ..where((p) => p.deletedAt.isNull()))
            .getSingleOrNull();
    FreigabeStand? stand;
    for (final s in staende) {
      if (s.version.id == versionId) stand = s;
    }
    VerlustAbgleich? abgleich;
    if (artikel != null && versionId != null) {
      abgleich = await verlustAbgleich(artikel.id, versionId);
    }
    return FreigabeUebersicht(
      artikel: artikel,
      stand: stand,
      abgleich: abgleich,
      staende: staende,
    );
  }

  /// Vergleicht den Verlust der erfassten Produktionen des Artikels mit
  /// dem des Stands — null, solange keine Produktion einen Verlust liefert.
  Future<VerlustAbgleich?> verlustAbgleich(
    String artikelId,
    String versionId,
  ) async {
    final eingabe = await _rezepte.rechenRezeptur(versionId);
    if (eingabe == null) return null;
    final historie = await (_db.select(_db.productionHistory)
          ..where((h) => h.productId.equals(artikelId))
          ..where((h) => h.deletedAt.isNull())
          ..orderBy([(h) => OrderingTerm.desc(h.datum)]))
        .get();
    final erfasst = ausbeuteAusProduktionen(historie);
    if (erfasst == null) return null;
    final gemessen = (1 - erfasst.faktor) * 100;
    final mitVerlust = eingabe.verlustart != Verlustart.keiner;
    final mitRezeptur = berechne(eingabe);
    final mitMessung = berechne(
      eingabe.kopie(
        verlustProzent: gemessen,
        // Gerechnet mit „kein Verlust", gemessen aber einer: Für den
        // Fleischanteil zählt nur, wie viel verloren geht.
        verlustart: mitVerlust ? null : Verlustart.trocknung,
      ),
    );
    final mitFleisch = mitRezeptur.fleischanteilProzent > 0;
    return VerlustAbgleich(
      produktionen: erfasst.anzahl,
      gemessenProzent: gemessen,
      rezepturProzent: eingabe.wirksamerVerlust,
      fleischRezeptur: mitFleisch ? mitRezeptur.fleischanteilProzent : null,
      fleischGemessen: mitFleisch ? mitMessung.fleischanteilProzent : null,
      zutatenlisteRezeptur: mitRezeptur.zutatenliste,
      zutatenlisteGemessen: mitMessung.zutatenliste,
    );
  }
}

/// Lässt sich die Kette von [prozess] in einen Artikel übernehmen? Dafür
/// braucht sie Schritte, keine früheren Abschnitte mehr und an jeder
/// Station eine Abteilung.
bool kannKetteUebernehmen(Prozessparameter prozess) =>
    prozess.abschnitte.isEmpty &&
    prozess.schritte.isNotEmpty &&
    stationenOhneAbteilung(prozess.schritte).isEmpty;

String? _oderNull(String text) => text.trim().isEmpty ? null : text.trim();

final freigabeDienstProvider = Provider<FreigabeDienst>(
  (ref) => FreigabeDienst(ref.watch(databaseProvider)),
);

/// Die Freigabe eines Projekts für die Übersicht — neu, sobald sich das
/// Projekt ändert.
final freigabeUebersichtProvider =
    FutureProvider.autoDispose.family<FreigabeUebersicht, String>(
  (ref, projektId) async {
    final projekt = await ref.watch(projektProvider(projektId).future);
    ref.watch(alleVersionenProvider);
    if (projekt == null) return const FreigabeUebersicht();
    return ref.watch(freigabeDienstProvider).uebersicht(projekt);
  },
);
