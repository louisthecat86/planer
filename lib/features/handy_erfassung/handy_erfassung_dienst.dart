import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:erfassung_format/erfassung_format.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/constants/entwicklung.dart';
import '../../core/constants/parameter_namen.dart';
import '../../core/database/database.dart';
import '../../core/services/artikel_fotos.dart';
import '../../core/services/produktion_erfassen_service.dart';
import '../entwicklung/daten/dateien.dart';
import '../erfassung/geplante_produktion.dart';

// Die Handy-Erfassung im Planer: das Paket fürs Handy schreiben und das
// Ergebnis vom Handy einlesen. Ohne Oberfläche — die steht in
// handy_erfassung_screen.dart.
//
// Geschrieben wird mit denselben Regeln wie in der Artikelansicht:
// Steckbrief-Werte landen in der Gruppe, die der Schritt für Maschinenwerte
// benutzt, Plattentemperaturen in der Gruppe ihres Rasters, die Notiz in
// MASCHINENEINSTELLUNGEN — und harte Grenzen blockieren.
//
// Fotos kommen mit dem Ergebnis: Ein Foto aus der Produktion gehört zum
// Artikel (ArtikelFotoDienst), ein Musterfoto in den Foto-Eingang der
// Produktentwicklung — verschlüsselt wie ihre übrigen Dateien.

/// Schlüssel der Felder eines Schritts im Paket.
/// Ab dieser Größe wird das Ergebnis auf einem eigenen Isolate gelesen —
/// mit Fotos ist die Datei schnell einige Megabyte groß.
const int kErgebnisImHintergrundAb = 512 * 1024;

/// Liest die Ergebnis-Datei vom Handy aus [bytes] — große im Hintergrund,
/// damit das Fenster nicht stehen bleibt.
///
/// Eine Funktion für sich und keine Methode der Seite: Was aufs andere
/// Isolate geht, nimmt alles mit, was im selben Rahmen steht. In der Seite
/// war das die Seite selbst — und die lässt sich nicht verschicken; das
/// Einlesen jeder Datei über [kErgebnisImHintergrundAb] schlug so fehl.
Future<ErfassungsErgebnis> ergebnisLesen(Uint8List bytes) async =>
    bytes.length < kErgebnisImHintergrundAb
        ? _ergebnisAus(bytes)
        : Isolate.run(() => _ergebnisAus(bytes));

ErfassungsErgebnis _ergebnisAus(Uint8List bytes) =>
    ErfassungsErgebnis.ausText(utf8.decode(bytes, allowMalformed: true));

String steckbriefSchluessel(String parameterName) =>
    's:${parameterName.trim().toLowerCase()}';
String parameterSchluessel(String parameterId) => 'p:$parameterId';
String plattenSchluessel(String zeile) => 't:$zeile';
const String kNotizSchluessel = 'n';

String? _leerZuNull(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}

DateTime _tag(DateTime d) => DateTime(d.year, d.month, d.day);

/// Was mit einer erfassten Produktion beim Einlesen geschieht.
enum ProduktionStand {
  /// Wird als Produktion eingetragen.
  neu,

  /// Für Artikel und Tag steht schon eine Produktion — wohl schon
  /// eingelesen oder am PC erfasst.
  schonErfasst,

  /// Den Artikel gibt es nicht mehr.
  artikelFehlt,

  /// Die Zahlen passen nicht zusammen.
  fehlerhaft,
}

/// Eine erfasste Produktion in der Vorschau.
class ProduktionVorschau {
  const ProduktionVorschau({
    required this.erfasst,
    required this.stand,
    required this.artikel,
    this.hinweis,
  });

  final ErfassteProduktion erfasst;
  final ProduktionStand stand;

  /// „4711 · Grillwurst" — wie der Artikel heute heißt.
  final String artikel;
  final String? hinweis;

  /// Ob sie sich übernehmen lässt.
  bool get moeglich =>
      stand == ProduktionStand.neu || stand == ProduktionStand.schonErfasst;

  /// Ob sie ohne Zutun angehakt ist.
  bool get vorgewaehlt => stand == ProduktionStand.neu;
}

/// Was mit einem geänderten Wert beim Einlesen geschieht.
enum WertStand {
  /// Am PC steht noch der Stand aus dem Paket — übernehmen.
  neu,

  /// Am PC steht schon der neue Wert.
  gleich,

  /// Am PC wurde der Wert inzwischen anders geändert.
  konflikt,

  /// Den Schritt oder das Feld gibt es nicht mehr.
  fehlt,

  /// Der Wert liegt außerhalb der technischen Grenzen.
  blockiert,
}

/// Ein geänderter Wert in der Vorschau.
class WertVorschau {
  const WertVorschau({
    required this.wert,
    required this.stand,
    required this.artikel,
    required this.schritt,
    this.amPc,
    this.hinweis,
  });

  final GeaenderterWert wert;
  final WertStand stand;
  final String artikel;

  /// „2 · Bratstraße".
  final String schritt;

  /// Was am PC gerade steht.
  final String? amPc;

  /// Warnung der Grenzen oder der Grund, warum es nicht geht.
  final String? hinweis;

  bool get moeglich => stand == WertStand.neu || stand == WertStand.konflikt;

  bool get vorgewaehlt => stand == WertStand.neu;
}

/// Was mit einem Foto beim Einlesen geschieht.
enum FotoStand {
  /// Wird übernommen.
  neu,

  /// Das Foto ist schon im Planer — die Datei wurde schon eingelesen.
  schonDa,

  /// Den Artikel gibt es nicht mehr.
  artikelFehlt,

  /// In der Datei steht kein lesbares Bild.
  unlesbar,

  /// Ein Musterfoto — aber die Produktentwicklung ist auf diesem Rechner
  /// nicht eingerichtet.
  entwicklungFehlt,
}

/// Ein Foto in der Vorschau.
class FotoVorschau {
  const FotoVorschau({
    required this.foto,
    required this.stand,
    required this.ziel,
    this.hinweis,
  });

  final ErfasstesFoto foto;
  final FotoStand stand;

  /// Wohin es kommt: „4711 · Grillwurst" oder „Foto-Eingang der
  /// Produktentwicklung".
  final String ziel;
  final String? hinweis;

  bool get moeglich => stand == FotoStand.neu;

  bool get vorgewaehlt => moeglich;
}

/// Was ein Ergebnis vom Handy im Planer bewirken würde.
class ErgebnisVorschau {
  const ErgebnisVorschau({
    required this.ergebnis,
    required this.produktionen,
    required this.werte,
    this.fotos = const [],
  });

  final ErfassungsErgebnis ergebnis;
  final List<ProduktionVorschau> produktionen;
  final List<WertVorschau> werte;
  final List<FotoVorschau> fotos;
}

/// Was übernommen wurde.
typedef UebernahmeBericht = ({int produktionen, int werte, int fotos});

/// Was der Planer zu einem Feld gerade weiß.
class _FeldStand {
  const _FeldStand({
    required this.feld,
    this.parameter,
    this.gruppe,
    this.reihenfolge = 50,
  });

  final PaketFeld feld;

  /// Die Zeile, in der der Wert steht — null: es gibt noch keine.
  final ProductStepParameter? parameter;

  /// Gruppe und Reihenfolge einer neuen Zeile.
  final String? gruppe;
  final int reihenfolge;
}

class HandyErfassungDienst {
  const HandyErfassungDienst(this._db);

  final AppDatabase _db;

  // ── Paket ───────────────────────────────────────────────────────────

  /// Das Paket fürs Handy: die noch nicht erfassten Produktionen von
  /// [von] bis einschließlich [bis] und die Maschineneinstellungen aller
  /// Artikel mit Prozesskette.
  Future<ErfassungsPaket> paketErstellen({
    required DateTime von,
    required DateTime bis,
    DateTime? jetzt,
  }) async {
    final erster = _tag(von);
    final letzter = _tag(bis);
    final geplant = await geplanteProduktionenLaden(
      _db,
      erster,
      DateTime(letzter.year, letzter.month, letzter.day + 1),
    );
    final tage = geplant.keys.toList()..sort();
    return ErfassungsPaket(
      id: const Uuid().v4(),
      erstellt: jetzt ?? DateTime.now(),
      von: erster,
      bis: letzter,
      produktionen: [
        for (final tag in tage)
          for (final g in geplant[tag]!)
            PaketProduktion(
              id: g.task.id,
              artikelId: g.task.productId,
              artikelnummer: g.artikelNummer,
              artikel: g.artikelName,
              datum: tag,
              abteilung: g.task.abteilung,
              abteilungName:
                  _abteilung(g.task.abteilung)?.anzeigeName ?? g.task.abteilung,
              abteilungFarbe: _abteilung(g.task.abteilung)?.farbwert,
              start: zeitAus(g.task.startZeit),
              rohKg: g.rohKg,
              fleischKg: g.fleischKg,
              fertigKg: g.fertigKg,
            ),
      ],
      artikel: await _artikel(),
    );
  }

  static Abteilung? _abteilung(String dbValue) {
    for (final a in Abteilung.values) {
      if (a.dbValue == dbValue) return a;
    }
    return null;
  }

  Future<List<PaketArtikel>> _artikel() async {
    final produkte = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.artikelbezeichnung)]))
        .get();
    final schritte = await (_db.select(_db.productSteps)
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
        .get();
    final jeArtikel = <String, List<ProductStep>>{};
    for (final s in schritte) {
      (jeArtikel[s.productId] ??= []).add(s);
    }
    final staende = await _feldStaende(schritte);
    return [
      for (final p in produkte)
        if (jeArtikel[p.id] case final liste?)
          PaketArtikel(
            id: p.id,
            nummer: p.artikelnummer,
            name: p.artikelbezeichnung,
            schritte: [
              for (final (i, s) in liste.indexed)
                PaketSchritt(
                  id: s.id,
                  nummer: i + 1,
                  abteilung: s.abteilung,
                  abteilungName:
                      _abteilung(s.abteilung)?.anzeigeName ?? s.abteilung,
                  abteilungFarbe: _abteilung(s.abteilung)?.farbwert,
                  anlage: staende[s.id]!.anlage,
                  prozessschritt: _leerZuNull(s.prozessschritt),
                  felder: [for (final f in staende[s.id]!.felder) f.feld],
                ),
            ],
          ),
    ];
  }

  /// Je Schritt: der Name der Anlage und seine Felder mit dem Stand am PC
  /// — in der Reihenfolge der Artikelansicht: Steckbrief, Platten, weitere
  /// Parameter, Notiz.
  Future<Map<String, ({String anlage, List<_FeldStand> felder})>> _feldStaende(
    List<ProductStep> schritte,
  ) async {
    final maschinen = {
      for (final m in await _db.select(_db.machines).get()) m.id: m,
    };
    final defs = <String, List<MachineParameterDef>>{};
    for (final d in await (_db.select(_db.machineParameterDefs)
          ..where((d) => d.deletedAt.isNull())
          ..orderBy([
            (d) => OrderingTerm.asc(d.sortierung),
            (d) => OrderingTerm.asc(d.parameterName),
          ]))
        .get()) {
      if (istVerstecktesPlattenParam(d.parameterName)) continue;
      (defs[d.maschineId] ??= []).add(d);
    }
    final ids = {for (final s in schritte) s.id};
    final params = <String, List<ProductStepParameter>>{};
    for (final p in await (_db.select(_db.productStepParameters)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.reihenfolge)]))
        .get()) {
      if (ids.contains(p.stepId)) (params[p.stepId] ??= []).add(p);
    }
    final grenzen = <(String, String), ParameterGrenzenData>{
      for (final g in await (_db.select(_db.parameterGrenzen)
            ..where((g) => g.deletedAt.isNull()))
          .get())
        (g.kontext, g.parameterName): g,
    };
    // Erst die Grenze der Anlage, dann die der Parametergruppe — wie in
    // der Artikelansicht.
    Grenze? grenze(String? anlage, String gruppe, String name) {
      final g = (anlage != null && anlage.trim().isNotEmpty
              ? grenzen[(anlage.trim(), name)]
              : null) ??
          grenzen[(gruppe, name)];
      if (g == null) return null;
      final r = Grenze(
        hartMin: g.hartMin,
        hartMax: g.hartMax,
        weichMin: g.weichMin,
        weichMax: g.weichMax,
      );
      return r.leer ? null : r;
    }

    final ergebnis = <String, ({String anlage, List<_FeldStand> felder})>{};
    for (final s in schritte) {
      final maschine = maschinen[s.maschineId];
      final anlage = maschine?.name;
      final alle = params[s.id] ?? const <ProductStepParameter>[];
      final felder = <_FeldStand>[];

      // Die Gruppe, die der Schritt für Maschinenwerte benutzt.
      var steckbriefGruppe = kMaschinenNotizGruppe;
      for (final p in alle) {
        if (p.istCustom || p.parameterGruppe == kMaschinenNotizGruppe) continue;
        steckbriefGruppe = p.parameterGruppe;
        break;
      }
      final defNamen = <String>{};
      for (final d in defs[s.maschineId] ?? const <MachineParameterDef>[]) {
        final gesucht = d.parameterName.trim().toLowerCase();
        defNamen.add(gesucht);
        ProductStepParameter? zeile;
        for (final p in alle) {
          if (p.parameterName.trim().toLowerCase() == gesucht) {
            zeile = p;
            break;
          }
        }
        felder.add(
          _FeldStand(
            feld: PaketFeld(
              schluessel: steckbriefSchluessel(d.parameterName),
              art: FeldArt.steckbrief,
              name: d.parameterName,
              einheit: _leerZuNull(d.einheit),
              gruppe: 'Steckbrief',
              wert: _leerZuNull(zeile?.wert),
              grenze: grenze(anlage, kMaschinenNotizGruppe, d.parameterName),
            ),
            parameter: zeile,
            gruppe: steckbriefGruppe,
            reihenfolge: 50 + d.sortierung,
          ),
        );
      }

      if (anlage != null && istPlattenMaschine(anlage)) {
        final gruppe = istDampftunnelMaschine(anlage)
            ? kPlattenGruppeKombi
            : kPlattenGruppeBrat;
        for (final zeile in plattenZeilenFuer(anlage)) {
          ProductStepParameter? p;
          for (final x in alle) {
            if (x.parameterName == zeile && x.parameterGruppe == gruppe) {
              p = x;
              break;
            }
          }
          felder.add(
            _FeldStand(
              feld: PaketFeld(
                schluessel: plattenSchluessel(zeile),
                art: FeldArt.platte,
                name: zeile,
                einheit: '°C',
                gruppe: 'Plattentemperaturen',
                wert: _leerZuNull(p?.wert),
                grenze: grenze(anlage, gruppe, zeile),
              ),
              parameter: p,
              gruppe: gruppe,
              reihenfolge: 100,
            ),
          );
        }
      }

      // Erst die Parameter aus der Excel, dann die selbst angelegten.
      for (final custom in const [false, true]) {
        for (final p in alle) {
          if (p.istCustom != custom) continue;
          if (istVerstecktesPlattenParam(p.parameterName)) continue;
          if (defNamen.contains(p.parameterName.trim().toLowerCase())) continue;
          felder.add(
            _FeldStand(
              feld: PaketFeld(
                schluessel: parameterSchluessel(p.id),
                art: FeldArt.parameter,
                name: p.parameterName,
                gruppe: p.parameterGruppe,
                wert: _leerZuNull(p.wert),
                grenze: grenze(anlage, p.parameterGruppe, p.parameterName),
              ),
              parameter: p,
            ),
          );
        }
      }

      ProductStepParameter? notiz;
      for (final p in alle) {
        if (p.parameterName == kMaschinenNotizParam) {
          notiz = p;
          break;
        }
      }
      felder.add(
        _FeldStand(
          feld: PaketFeld(
            schluessel: kNotizSchluessel,
            art: FeldArt.notiz,
            name: 'Maschineneinstellungen (Notiz)',
            wert: _leerZuNull(notiz?.wert),
          ),
          parameter: notiz,
          gruppe: kMaschinenNotizGruppe,
        ),
      );

      ergebnis[s.id] = (
        anlage: anlage ?? _leerZuNull(s.prozessschritt) ?? 'Ohne Anlage',
        felder: felder,
      );
    }
    return ergebnis;
  }

  // ── Ergebnis ────────────────────────────────────────────────────────

  /// Was [ergebnis] im Planer bewirken würde — geändert wird noch nichts.
  Future<ErgebnisVorschau> vorschau(ErfassungsErgebnis ergebnis) async {
    final produkte = {
      for (final p in await (_db.select(_db.products)
            ..where((p) => p.deletedAt.isNull()))
          .get())
        p.id: p,
    };
    String artikelText(String id, String ersatz) {
      final p = produkte[id];
      return p == null
          ? ersatz
          : '${p.artikelnummer} · ${p.artikelbezeichnung}';
    }

    final produktionen = <ProduktionVorschau>[];
    for (final e in ergebnis.produktionen) {
      final artikel = artikelText(e.artikelId, e.artikel);
      if (!produkte.containsKey(e.artikelId)) {
        produktionen.add(
          ProduktionVorschau(
            erfasst: e,
            stand: ProduktionStand.artikelFehlt,
            artikel: artikel,
            hinweis: 'Den Artikel gibt es im Planer nicht mehr.',
          ),
        );
        continue;
      }
      final fehler = produktionFehler(
        rohKg: e.rohKg,
        fleischKg: e.fleischKg,
        fertigKg: e.fertigKg,
      );
      if (fehler != null) {
        produktionen.add(
          ProduktionVorschau(
            erfasst: e,
            stand: ProduktionStand.fehlerhaft,
            artikel: artikel,
            hinweis: fehler,
          ),
        );
        continue;
      }
      final tag = _tag(e.datum);
      final schon = await (_db.select(_db.productionHistory)
            ..where((h) => h.deletedAt.isNull())
            ..where((h) => h.productId.equals(e.artikelId))
            ..where((h) => h.datum.isBiggerOrEqualValue(tag))
            ..where(
              (h) => h.datum.isSmallerThanValue(
                DateTime(tag.year, tag.month, tag.day + 1),
              ),
            )
            ..limit(1))
          .get();
      produktionen.add(
        ProduktionVorschau(
          erfasst: e,
          stand: schon.isEmpty
              ? ProduktionStand.neu
              : ProduktionStand.schonErfasst,
          artikel: artikel,
          hinweis: schon.isEmpty
              ? null
              : 'Für diesen Tag ist schon eine Produktion erfasst — '
                  'anhaken trägt eine weitere ein.',
        ),
      );
    }

    final schrittIds = {for (final w in ergebnis.werte) w.schrittId};
    final schritte = schrittIds.isEmpty
        ? const <ProductStep>[]
        : await (_db.select(_db.productSteps)
              ..where((s) => s.deletedAt.isNull())
              ..where((s) => s.id.isIn(schrittIds))
              ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
            .get();
    final staende = await _feldStaende(schritte);
    final schrittVon = {for (final s in schritte) s.id: s};

    final werte = <WertVorschau>[];
    for (final w in ergebnis.werte) {
      final s = schrittVon[w.schrittId];
      final artikel = artikelText(w.artikelId, '');
      final stand = staende[w.schrittId];
      _FeldStand? feld;
      for (final f in stand?.felder ?? const <_FeldStand>[]) {
        if (f.feld.schluessel == w.schluessel) {
          feld = f;
          break;
        }
      }
      if (s == null || stand == null || feld == null) {
        werte.add(
          WertVorschau(
            wert: w,
            stand: WertStand.fehlt,
            artikel: artikel,
            schritt: stand?.anlage ?? '',
            hinweis: s == null
                ? 'Den Schritt gibt es im Planer nicht mehr.'
                : 'Das Feld gibt es an diesem Schritt nicht mehr.',
          ),
        );
        continue;
      }
      final amPc = feld.feld.wert;
      final neu = _leerZuNull(w.neu);
      final pruefung = feld.feld.grenze?.pruefe(neu) ?? GrenzPruefung.inOrdnung;
      final WertStand art;
      String? hinweis = pruefung.meldung;
      if (amPc == neu) {
        art = WertStand.gleich;
        hinweis = null;
      } else if (pruefung.status == GrenzStatus.blockiert) {
        art = WertStand.blockiert;
      } else if (amPc == _leerZuNull(w.alt)) {
        art = WertStand.neu;
      } else {
        art = WertStand.konflikt;
        hinweis = [
          'Am PC inzwischen geändert.',
          if (pruefung.meldung != null) pruefung.meldung!,
        ].join(' ');
      }
      werte.add(
        WertVorschau(
          wert: w,
          stand: art,
          artikel: artikel,
          schritt: stand.anlage,
          amPc: amPc,
          hinweis: hinweis,
        ),
      );
    }
    return ErgebnisVorschau(
      ergebnis: ergebnis,
      produktionen: produktionen,
      werte: werte,
      fotos: await _fotoVorschau(ergebnis.fotos, artikelText, produkte.keys),
    );
  }

  /// Ob die Produktentwicklung auf diesem Rechner Dateien ablegen kann —
  /// das kann sie, sobald sie einmal entsperrt war.
  Future<bool> _entwicklungBereit() async {
    final zeile = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(kEntwicklungDatenschluessel)))
        .getSingleOrNull();
    return zeile?.value != null;
  }

  Future<List<FotoVorschau>> _fotoVorschau(
    List<ErfasstesFoto> fotos,
    String Function(String id, String ersatz) artikelText,
    Iterable<String> artikelIds,
  ) async {
    if (fotos.isEmpty) return const [];
    final artikel = artikelIds.toSet();
    final ids = [for (final f in fotos) f.id];
    final schonArtikel = await ArtikelFotoDienst(_db).vorhandene(ids);
    final t = _db.entwicklungDateien;
    final schonMuster = (await (_db.selectOnly(t)
              ..addColumns([t.id])
              ..where(t.id.isIn(ids)))
            .map((z) => z.read(t.id)!)
            .get())
        .toSet();
    final bereit = await _entwicklungBereit();
    const eingang = 'Foto-Eingang der Produktentwicklung';
    return [
      for (final f in fotos)
        switch (f.art) {
          FotoArt.produktion => FotoVorschau(
              foto: f,
              ziel: artikelText(f.artikelId ?? '', f.artikel ?? ''),
              stand: !artikel.contains(f.artikelId)
                  ? FotoStand.artikelFehlt
                  : !istJpeg(f.daten)
                      ? FotoStand.unlesbar
                      : schonArtikel.contains(f.id)
                          ? FotoStand.schonDa
                          : FotoStand.neu,
              hinweis: !artikel.contains(f.artikelId)
                  ? 'Den Artikel gibt es im Planer nicht mehr.'
                  : !istJpeg(f.daten)
                      ? 'In der Datei steht dazu kein lesbares Bild.'
                      : schonArtikel.contains(f.id)
                          ? 'Ist schon beim Artikel.'
                          : null,
            ),
          FotoArt.muster => FotoVorschau(
              foto: f,
              ziel: eingang,
              stand: !istJpeg(f.daten)
                  ? FotoStand.unlesbar
                  : !bereit
                      ? FotoStand.entwicklungFehlt
                      : schonMuster.contains(f.id)
                          ? FotoStand.schonDa
                          : FotoStand.neu,
              hinweis: !istJpeg(f.daten)
                  ? 'In der Datei steht dazu kein lesbares Bild.'
                  : !bereit
                      ? 'Die Produktentwicklung ist auf diesem Rechner noch '
                          'nicht eingerichtet — das Musterfoto bleibt in '
                          'der Datei.'
                      : schonMuster.contains(f.id)
                          ? 'Ist schon in der Produktentwicklung.'
                          : null,
            ),
        },
    ];
  }

  /// Trägt ein, was in [produktionen], [werte] und [fotos] angehakt ist —
  /// alles oder nichts. Was sich nicht übernehmen lässt, wird übergangen.
  Future<UebernahmeBericht> uebernehmen({
    required Iterable<ProduktionVorschau> produktionen,
    required Iterable<WertVorschau> werte,
    Iterable<FotoVorschau> fotos = const [],
  }) async {
    // Die Bilder vorab: ohne Aufnahmeort und Kamera, notfalls verkleinert.
    // Das rechnet — also nicht erst in der Transaktion.
    final bilder = <FotoVorschau, Uint8List>{};
    for (final x in fotos) {
      final daten = x.foto.daten;
      if (!x.moeglich || daten == null) continue;
      final bild = await fotoAufbereiten(daten, vomHandy: true);
      if (bild != null) bilder[x] = bild;
    }
    return _db.transaction(() async {
      var f = 0;
      for (final MapEntry(key: x, value: bild) in bilder.entries) {
        final foto = x.foto;
        switch (foto.art) {
          case FotoArt.produktion:
            await ArtikelFotoDienst(_db).speichern(
              id: foto.id,
              productId: foto.artikelId!,
              bild: bild,
              aufgenommenAm: foto.aufgenommenAm,
              bezeichnung: foto.bezeichnung,
              kuerzel: foto.kuerzel,
            );
          case FotoArt.muster:
            await EntwicklungDateienDienst(_db).speichern(
              id: foto.id,
              name: foto.dateiname,
              inhalt: bild,
              projektId: kEntwicklungFotoEingang,
              mimeTyp: 'image/jpeg',
            );
        }
        f++;
      }

      var p = 0;
      for (final x in produktionen) {
        if (!x.moeglich) continue;
        final e = x.erfasst;
        await ProduktionErfassenService.speichere(
          db: _db,
          productId: e.artikelId,
          datum: e.datum,
          kgRohware: e.rohKg,
          kgFleischeinwaage: e.fleischKg,
          kgFertigware: e.fertigKg,
          startzeit: e.start,
          endzeit: e.ende,
          notizen: e.notiz,
        );
        p++;
      }

      var w = 0;
      final liste = [
        for (final x in werte)
          if (x.moeglich) x,
      ];
      if (liste.isNotEmpty) {
        final schritte = await (_db.select(_db.productSteps)
              ..where((s) => s.deletedAt.isNull())
              ..where(
                (s) => s.id.isIn({for (final x in liste) x.wert.schrittId}),
              ))
            .get();
        final staende = await _feldStaende(schritte);
        for (final x in liste) {
          _FeldStand? feld;
          for (final f
              in staende[x.wert.schrittId]?.felder ?? const <_FeldStand>[]) {
            if (f.feld.schluessel == x.wert.schluessel) {
              feld = f;
              break;
            }
          }
          if (feld == null) continue;
          final neu = _leerZuNull(x.wert.neu);
          if (feld.feld.grenze?.pruefe(neu).status == GrenzStatus.blockiert) {
            continue;
          }
          final zeile = feld.parameter;
          if (zeile != null) {
            await (_db.update(_db.productStepParameters)
                  ..where((t) => t.id.equals(zeile.id)))
                .write(
              ProductStepParametersCompanion(
                wert: Value(neu),
                updatedAt: Value(DateTime.now()),
              ),
            );
          } else {
            if (neu == null) continue;
            await _db.into(_db.productStepParameters).insert(
                  ProductStepParametersCompanion(
                    id: Value(const Uuid().v4()),
                    stepId: Value(x.wert.schrittId),
                    parameterGruppe: Value(feld.gruppe!),
                    parameterName: Value(
                      feld.feld.art == FeldArt.notiz
                          ? kMaschinenNotizParam
                          : feld.feld.name,
                    ),
                    wert: Value(neu),
                    reihenfolge: Value(feld.reihenfolge),
                    istCustom: const Value(false),
                  ),
                );
          }
          w++;
        }
      }
      return (produktionen: p, werte: w, fotos: f);
    });
  }
}
