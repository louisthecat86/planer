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
import '../../core/services/prozesskette_service.dart';
import '../../core/utils/krypto.dart';
import '../entwicklung/daten/dateien.dart';
import '../erfassung/geplante_produktion.dart';
import '../whiteboard/whiteboard_provider.dart' show leistungAusProduktionen;

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
///
/// Ist das Ergebnis verschlüsselt, liefert [schluesselFuer] den Schlüssel
/// zur Paket-ID ([HandyErfassungDienst.ergebnisSchluessel]).
Future<ErfassungsErgebnis> ergebnisLesen(
  Uint8List bytes, {
  Future<List<int>?> Function(String paketId)? schluesselFuer,
}) async {
  final gross = bytes.length >= kErgebnisImHintergrundAb;
  final (offen, geschuetzt) = await _oeffnen(bytes, gross);
  if (offen != null) return offen;
  final schluessel = await schluesselFuer?.call(geschuetzt!.paketId);
  if (schluessel == null) {
    throw const FormatFehler(
      'Das Ergebnis ist verschlüsselt, aber dieser Planer hat noch keinen '
      'Schlüssel — es gehört zu einem Paket eines anderen Planers.',
    );
  }
  return _entschluesseln(geschuetzt!, schluessel, gross);
}

// Eigene Funktionen für das, was aufs andere Isolate geht: So nimmt es
// nur seine Argumente mit, nicht den Rahmen von [ergebnisLesen] mit
// dessen Rückruf in die Datenbank.

Future<(ErfassungsErgebnis?, GeschuetztesErgebnis?)> _oeffnen(
  Uint8List bytes,
  bool gross,
) =>
    gross
        ? Isolate.run(() => _oeffnenSofort(bytes))
        : Future.sync(() => _oeffnenSofort(bytes));

(ErfassungsErgebnis?, GeschuetztesErgebnis?) _oeffnenSofort(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  final g = geschuetztesErgebnis(text);
  if (g != null) return (null, g);
  return (ErfassungsErgebnis.ausText(text), null);
}

Future<ErfassungsErgebnis> _entschluesseln(
  GeschuetztesErgebnis g,
  List<int> schluessel,
  bool gross,
) =>
    gross
        ? Isolate.run(() => ergebnisEntschluesseln(g, schluessel))
        : Future.sync(() => ergebnisEntschluesseln(g, schluessel));

/// Unter diesem Schlüssel steht in app_settings das Geheimnis, aus dem
/// der Planer für jedes Paket den Schlüssel des Ergebnisses ableitet. Es
/// verlässt den PC nie (nur mit dem Backup); nach außen geht je Paket nur
/// der abgeleitete Schlüssel.
const String kErgebnisGeheimnis = 'handy_ergebnis_geheimnis';

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
    String? schrittId,
    String? schluessel,
  })  : _schrittId = schrittId,
        _schluessel = schluessel;

  final GeaenderterWert wert;
  final WertStand stand;

  final String? _schrittId;
  final String? _schluessel;

  /// Der Schritt im Planer, an den der Wert geht. Meist der vom Handy —
  /// wurde die Kette am PC inzwischen neu angelegt (etwa beim
  /// Stammdaten-Import), der eine Schritt desselben Artikels, der das Feld
  /// hat.
  String get schrittId => _schrittId ?? wert.schrittId;

  /// Das Feld an [schrittId] — siehe dort.
  String get schluessel => _schluessel ?? wert.schluessel;

  /// Ob der Wert über das Feld einem neu angelegten Schritt zugeordnet
  /// wurde.
  bool get zugeordnet => _schrittId != null && _schrittId != wert.schrittId;
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
    this.schritte = const [],
  });

  final ErfassungsErgebnis ergebnis;
  final List<ProduktionVorschau> produktionen;
  final List<WertVorschau> werte;
  final List<FotoVorschau> fotos;

  /// Maschinen, die in eine Kette dazukommen oder wegfallen.
  final List<SchrittVorschau> schritte;
}

/// Was mit einer Änderung an einer Prozesskette beim Einlesen geschieht.
enum SchrittStand {
  /// Die Maschine kommt in die Kette.
  neu,

  /// Der Schritt kommt aus der Kette.
  entfernen,

  /// Der neue Schritt steht schon im Planer — die Datei wurde schon
  /// eingelesen.
  schonDa,

  /// Der Schritt ist im Planer schon entfernt.
  schonEntfernt,

  /// Den Artikel gibt es nicht mehr.
  artikelFehlt,

  /// Die Maschine steht nicht mehr im Katalog.
  maschineFehlt,

  /// Die Kette hätte mehr Schritte, als ein Artikel haben kann.
  zuViele,
}

/// Eine Änderung an einer Prozesskette in der Vorschau: eine Maschine,
/// die dazukommt ([neu]), oder ein Schritt, der wegfällt ([entfernt]).
class SchrittVorschau {
  const SchrittVorschau({
    required this.stand,
    required this.artikel,
    required this.text,
    this.neu,
    this.entfernt,
    this.hinweis,
  });

  final NeuerSchritt? neu;
  final EntfernterSchritt? entfernt;
  final SchrittStand stand;

  /// „4711 · Grillwurst".
  final String artikel;

  /// „Füllmaschine dazu — nach 2 · Kutter" oder „3 · Kutter entfernen".
  final String text;
  final String? hinweis;

  bool get istNeu => neu != null;

  bool get moeglich =>
      stand == SchrittStand.neu || stand == SchrittStand.entfernen;

  bool get vorgewaehlt => moeglich;
}

/// Was übernommen wurde.
typedef UebernahmeBericht = ({
  int produktionen,
  int werte,
  int fotos,
  int schritte,
});

/// Maschinen, Steckbriefe und Grenzen — siehe
/// [HandyErfassungDienst._kontext].
class _FeldKontext {
  const _FeldKontext({
    required this.maschinen,
    required this.defs,
    required this.grenzen,
  });

  final Map<String, Machine> maschinen;
  final Map<String, List<MachineParameterDef>> defs;
  final Map<(String, String), ParameterGrenzenData> grenzen;

  /// Erst die Grenze der Anlage, dann die der Parametergruppe — wie in
  /// der Artikelansicht.
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
}

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

  /// Der Schlüssel, mit dem die App das Ergebnis zum Paket [paketId]
  /// verschlüsselt: HMAC-SHA256 aus dem Geheimnis dieses Planers und der
  /// Paket-ID. Ohne Geheimnis null — mit [anlegen] wird es dann erzeugt.
  Future<Uint8List?> ergebnisSchluessel(
    String paketId, {
    bool anlegen = false,
  }) async {
    final zeile = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(kErgebnisGeheimnis)))
        .getSingleOrNull();
    Uint8List? geheimnis;
    if (zeile != null) {
      try {
        geheimnis = base64Decode(zeile.value);
      } on FormatException {
        geheimnis = null;
      }
    }
    if (geheimnis == null || geheimnis.length != kSchluesselLaenge) {
      if (!anlegen) return null;
      geheimnis = zufallsBytes(kSchluesselLaenge);
      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: kErgebnisGeheimnis,
              value: base64Encode(geheimnis),
            ),
          );
    }
    return hmacSha256(geheimnis, utf8.encode('ergebnis:$paketId'));
  }

  /// Das Paket fürs Handy: die noch nicht erfassten Produktionen von
  /// [von] bis einschließlich [bis] und die Maschineneinstellungen aller
  /// Artikel mit Prozesskette — mit [nurGeplante] nur die der geplanten
  /// Produktionen: viel kleiner, etwa für den Weg per QR-Code.
  Future<ErfassungsPaket> paketErstellen({
    required DateTime von,
    required DateTime bis,
    DateTime? jetzt,
    bool nurGeplante = false,
  }) async {
    final erster = _tag(von);
    final letzter = _tag(bis);
    final geplant = await geplanteProduktionenLaden(
      _db,
      erster,
      DateTime(letzter.year, letzter.month, letzter.day + 1),
    );
    final tage = geplant.keys.toList()..sort();
    final ids = {
      for (final liste in geplant.values)
        for (final g in liste) g.task.productId,
    };
    bool mit(String artikelId) => !nurGeplante || ids.contains(artikelId);
    final id = const Uuid().v4();
    return ErfassungsPaket(
      id: id,
      ergebnisSchluessel: base64Encode(
        (await ergebnisSchluessel(id, anlegen: true))!,
      ),
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
      artikel: [
        for (final a in await _artikel())
          if (mit(a.id)) a,
      ],
      maschinen: await _katalog(),
      erfahrungen: [
        for (final e in await _erfahrungen())
          if (mit(e.artikelId)) e,
      ],
      fotosImPlaner: {
        for (final MapEntry(:key, :value) in (await _fotoAnzahlen()).entries)
          if (mit(key)) key: value,
      },
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

  /// Je Artikel, wie viele Fotos der Planer von ihm hat.
  Future<Map<String, int>> _fotoAnzahlen() async {
    final anzahl = _db.artikelFotos.id.count();
    final zeilen = await (_db.selectOnly(_db.artikelFotos)
          ..addColumns([_db.artikelFotos.productId, anzahl])
          ..groupBy([_db.artikelFotos.productId]))
        .get();
    return {
      for (final z in zeilen)
        if ((z.read(anzahl) ?? 0) > 0)
          z.read(_db.artikelFotos.productId)!: z.read(anzahl)!,
    };
  }

  /// Je Artikel der Schnitt seiner letzten erfassten Produktionen mit
  /// Menge und Zeit — genau der, mit dem die Planung die Dauer rechnet
  /// ([leistungAusProduktionen]). Artikel ohne solche fehlen.
  Future<List<PaketErfahrung>> _erfahrungen() async {
    final jeArtikel = <String, List<ProductionHistoryData>>{};
    for (final h in await (_db.select(_db.productionHistory)
          ..where((h) => h.deletedAt.isNull())
          ..orderBy([
            (h) => OrderingTerm.desc(h.datum),
            (h) => OrderingTerm.desc(h.createdAt),
          ]))
        .get()) {
      (jeArtikel[h.productId] ??= []).add(h);
    }
    return [
      for (final MapEntry(key: id, value: liste) in jeArtikel.entries)
        if (leistungAusProduktionen(liste) case final l?)
          if (l.mengeKg > 0 && l.minuten > 0)
            PaketErfahrung(
              artikelId: id,
              mengeKg: l.mengeKg,
              minuten: l.minuten,
              anzahl: l.anzahl,
            ),
    ];
  }

  /// Was zum Zusammenstellen der Felder gebraucht wird: Maschinen,
  /// Steckbriefe und Grenzen — einmal geladen für viele Schritte.
  Future<_FeldKontext> _kontext() async {
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
    final grenzen = <(String, String), ParameterGrenzenData>{
      for (final g in await (_db.select(_db.parameterGrenzen)
            ..where((g) => g.deletedAt.isNull()))
          .get())
        (g.kontext, g.parameterName): g,
    };
    return _FeldKontext(maschinen: maschinen, defs: defs, grenzen: grenzen);
  }

  /// Je Schritt: der Name der Anlage und seine Felder mit dem Stand am PC
  /// — in der Reihenfolge der Artikelansicht: Steckbrief, Platten, weitere
  /// Parameter, Notiz.
  Future<Map<String, ({String anlage, List<_FeldStand> felder})>> _feldStaende(
    List<ProductStep> schritte,
  ) async {
    final k = await _kontext();
    final ids = {for (final s in schritte) s.id};
    final params = <String, List<ProductStepParameter>>{};
    for (final p in await (_db.select(_db.productStepParameters)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.reihenfolge)]))
        .get()) {
      if (ids.contains(p.stepId)) (params[p.stepId] ??= []).add(p);
    }
    return {
      for (final s in schritte)
        s.id: _felderVon(
          k,
          maschineId: s.maschineId,
          prozessschritt: s.prozessschritt,
          alle: params[s.id] ?? const [],
        ),
    };
  }

  /// Die Felder eines Schritts an der Maschine [maschineId] mit den
  /// Parametern [alle] — ohne Parameter die eines neuen Schritts.
  static ({String anlage, List<_FeldStand> felder}) _felderVon(
    _FeldKontext k, {
    required String? maschineId,
    required String? prozessschritt,
    required List<ProductStepParameter> alle,
  }) {
    final anlage = k.maschinen[maschineId]?.name;
    final felder = <_FeldStand>[];

    // Die Gruppe, die der Schritt für Maschinenwerte benutzt.
    var steckbriefGruppe = kMaschinenNotizGruppe;
    for (final p in alle) {
      if (p.istCustom || p.parameterGruppe == kMaschinenNotizGruppe) continue;
      steckbriefGruppe = p.parameterGruppe;
      break;
    }
    final defNamen = <String>{};
    for (final d in k.defs[maschineId] ?? const <MachineParameterDef>[]) {
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
            grenze: k.grenze(anlage, kMaschinenNotizGruppe, d.parameterName),
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
              grenze: k.grenze(anlage, gruppe, zeile),
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
              grenze: k.grenze(anlage, p.parameterGruppe, p.parameterName),
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

    return (
      anlage: anlage ?? _leerZuNull(prozessschritt) ?? 'Ohne Anlage',
      felder: felder,
    );
  }

  /// Der Maschinenkatalog fürs Handy: alle Maschinen, die nicht gelöscht
  /// sind, nach Abteilung und Name — je mit den Feldern eines neuen
  /// Schritts.
  Future<List<PaketMaschine>> _katalog() async {
    final k = await _kontext();
    final reihe = {
      for (final (i, a) in Abteilung.values.indexed) a.dbValue: i,
    };
    final liste = [
      for (final m in k.maschinen.values)
        if (m.deletedAt == null) m,
    ]..sort((a, b) {
        final r = (reihe[a.abteilung] ?? 999).compareTo(
          reihe[b.abteilung] ?? 999,
        );
        return r != 0
            ? r
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return [
      for (final m in liste)
        PaketMaschine(
          id: m.id,
          name: m.name,
          abteilung: m.abteilung,
          abteilungName: _abteilung(m.abteilung)?.anzeigeName ?? m.abteilung,
          abteilungFarbe: _abteilung(m.abteilung)?.farbwert,
          felder: [
            for (final f in _felderVon(
              k,
              maschineId: m.id,
              prozessschritt: null,
              alle: const [],
            ).felder)
              f.feld,
          ],
        ),
    ];
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

    final ketten = await _kettenVorschau(ergebnis, artikelText);

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
    final ersatz = await _ersatzSuche(ergebnis, schrittVon, ketten.felder);

    final werte = <WertVorschau>[];
    for (final w in ergebnis.werte) {
      var s = schrittVon[w.schrittId];
      final artikel = artikelText(w.artikelId, '');
      // Ein Wert an einer Maschine, die erst mit diesem Ergebnis in die
      // Kette kommt: Er zählt wie ein neuer Wert an einem leeren Schritt.
      final neuerSchritt = s == null ? ketten.felder[w.schrittId] : null;
      var stand = staende[w.schrittId] ?? neuerSchritt;
      _FeldStand? feld;
      for (final f in stand?.felder ?? const <_FeldStand>[]) {
        if (f.feld.schluessel == w.schluessel) {
          feld = f;
          break;
        }
      }
      String? schrittId;
      String? schluessel;
      if (feld == null && neuerSchritt == null) {
        // Den Schritt oder das Feld gibt es so nicht mehr — die Kette oder
        // der Parameter wurde am PC neu angelegt. Dann der eine Schritt
        // desselben Artikels, der das Feld hat.
        final t = ersatz(w);
        if (t != null) {
          s = t.schritt;
          stand = t.stand;
          feld = t.feld;
          schrittId = t.schritt.id;
          schluessel = t.feld.feld.schluessel;
        }
      }
      if ((s == null && neuerSchritt == null) ||
          stand == null ||
          feld == null) {
        werte.add(
          WertVorschau(
            wert: w,
            stand: WertStand.fehlt,
            artikel: artikel,
            schritt: stand?.anlage ?? '',
            hinweis: s == null
                ? 'Den Schritt gibt es im Planer nicht mehr, und im Artikel '
                    'steht kein eindeutiger Schritt mit diesem Feld.'
                : 'Das Feld gibt es an diesem Schritt nicht mehr.',
          ),
        );
        continue;
      }
      final zugeordnetHinweis = schrittId != null && schrittId != w.schrittId
          ? 'Die Kette wurde am PC neu angelegt — zugeordnet über das Feld.'
          : null;
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
          hinweis: _leerZuNull(
            [
              if (zugeordnetHinweis != null) zugeordnetHinweis,
              if (hinweis != null) hinweis,
            ].join(' '),
          ),
          schrittId: schrittId,
          schluessel: schluessel,
        ),
      );
    }
    return ErgebnisVorschau(
      ergebnis: ergebnis,
      produktionen: produktionen,
      werte: werte,
      fotos: await _fotoVorschau(ergebnis.fotos, artikelText, produkte.keys),
      schritte: ketten.vorschau,
    );
  }

  /// Sucht für einen Wert, dessen Schritt oder Feld es nicht mehr gibt,
  /// den Ersatz im selben Artikel — die Kette wurde am PC inzwischen neu
  /// angelegt (etwa beim Stammdaten-Import), die IDs stimmen nicht mehr.
  ///
  /// Die Werte eines alten Schritts bleiben zusammen: Gesucht wird der
  /// Schritt, der alle ihre Felder hat — Steckbrief, Platte und Notiz über
  /// den Schlüssel, weitere Parameter über den Namen —, bei bekannter
  /// Anlage nur an dieser Anlage, bei mehreren der mit der nächsten
  /// Nummer. Klappt das nicht, der eine Schritt, der das einzelne Feld
  /// hat. Sonst ist es nicht eindeutig: null. Fehlt nur das Feld, wird nur
  /// am Schritt selbst gesucht. Neue Schritte aus demselben Ergebnis
  /// zählen nicht.
  Future<
      ({
        ProductStep schritt,
        ({String anlage, List<_FeldStand> felder}) stand,
        _FeldStand feld,
      })?
          Function(GeaenderterWert)> _ersatzSuche(
    ErfassungsErgebnis ergebnis,
    Map<String, ProductStep> gefunden,
    Map<String, ({String anlage, List<_FeldStand> felder})> neue,
  ) async {
    final artikelIds = {
      for (final w in ergebnis.werte)
        if (!gefunden.containsKey(w.schrittId) || w.art == FeldArt.parameter)
          if (!neue.containsKey(w.schrittId)) w.artikelId,
    };
    if (artikelIds.isEmpty) return (_) => null;
    final ketten = await (_db.select(_db.productSteps)
          ..where((s) => s.deletedAt.isNull())
          ..where((s) => s.productId.isIn(artikelIds))
          ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
        .get();
    final staende = await _feldStaende(ketten);

    _FeldStand? feldAn(ProductStep s, GeaenderterWert w) {
      final name = w.name.trim().toLowerCase();
      for (final f in staende[s.id]?.felder ?? const <_FeldStand>[]) {
        final passt = w.art == FeldArt.parameter
            ? f.feld.art == FeldArt.parameter &&
                f.feld.name.trim().toLowerCase() == name
            : f.feld.schluessel == w.schluessel;
        if (passt) return f;
      }
      return null;
    }

    /// Unter [kandidaten] der eine: erst nach Anlage, dann nach Nummer.
    ProductStep? eindeutig(
      List<ProductStep> kandidaten,
      String? anlage,
      int? nummer,
    ) {
      var liste = kandidaten;
      final a = anlage?.trim().toLowerCase();
      if (a != null && a.isNotEmpty) {
        final gleich = [
          for (final s in liste)
            if (staende[s.id]?.anlage.trim().toLowerCase() == a) s,
        ];
        if (gleich.isNotEmpty) liste = gleich;
      }
      if (liste.length == 1) return liste.single;
      if (liste.isEmpty || nummer == null) return null;
      int abstand(ProductStep s) => (s.reihenfolge - nummer).abs();
      final naechster = liste.map(abstand).reduce((x, y) => x < y ? x : y);
      final beste = [
        for (final s in liste)
          if (abstand(s) == naechster) s,
      ];
      return beste.length == 1 ? beste.single : null;
    }

    // Je altem Schritt, den es nicht mehr gibt: der neue.
    final jeAltemSchritt = <String, List<GeaenderterWert>>{};
    for (final w in ergebnis.werte) {
      if (gefunden.containsKey(w.schrittId) || neue.containsKey(w.schrittId)) {
        continue;
      }
      (jeAltemSchritt[w.schrittId] ??= []).add(w);
    }
    final zuordnung = <String, ProductStep>{};
    for (final MapEntry(key: alt, value: werte) in jeAltemSchritt.entries) {
      final w0 = werte.first;
      final kandidaten = [
        for (final s in ketten)
          if (s.productId == w0.artikelId &&
              werte.every((w) => feldAn(s, w) != null))
            s,
      ];
      final s = eindeutig(kandidaten, w0.anlage, w0.nummer);
      if (s != null) zuordnung[alt] = s;
    }

    return (GeaenderterWert w) {
      final ProductStep? schritt;
      if (gefunden[w.schrittId] case final da?) {
        // Der Schritt ist noch da, nur das Feld nicht: nur an ihm.
        schritt = da;
      } else if (zuordnung[w.schrittId] case final z?) {
        schritt = z;
      } else {
        schritt = eindeutig(
          [
            for (final s in ketten)
              if (s.productId == w.artikelId && feldAn(s, w) != null) s,
          ],
          w.anlage,
          w.nummer,
        );
      }
      if (schritt == null) return null;
      final feld = feldAn(schritt, w);
      final stand = staende[schritt.id];
      if (feld == null || stand == null) return null;
      return (schritt: schritt, stand: stand, feld: feld);
    };
  }

  /// Die Änderungen an den Prozessketten — und die Felder der neuen
  /// Schritte, damit ihre Werte in der Vorschau geprüft werden können.
  Future<
      ({
        List<SchrittVorschau> vorschau,
        Map<String, ({String anlage, List<_FeldStand> felder})> felder,
      })> _kettenVorschau(
    ErfassungsErgebnis ergebnis,
    String Function(String id, String ersatz) artikelText,
  ) async {
    final vorschau = <SchrittVorschau>[];
    final felder = <String, ({String anlage, List<_FeldStand> felder})>{};
    if (!ergebnis.hatKettenAenderungen) {
      return (vorschau: vorschau, felder: felder);
    }
    final k = await _kontext();
    final produkte = {
      for (final p in await (_db.select(_db.products)
            ..where((p) => p.deletedAt.isNull()))
          .get())
        p.id,
    };
    final artikelIds = {
      for (final n in ergebnis.neueSchritte) n.artikelId,
      for (final e in ergebnis.entfernteSchritte) e.artikelId,
    };
    // Alle Schritte dieser Artikel, auch entfernte: Ein schon angelegter
    // neuer Schritt soll nicht ein zweites Mal entstehen, und ein schon
    // entfernter nicht als „fehlt" erscheinen.
    final alle = await (_db.select(_db.productSteps)
          ..where((s) => s.productId.isIn(artikelIds))
          ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
        .get();
    final jeId = {for (final s in alle) s.id: s};
    final aktivJeArtikel = <String, int>{};
    for (final s in alle) {
      if (s.deletedAt == null) {
        aktivJeArtikel[s.productId] = (aktivJeArtikel[s.productId] ?? 0) + 1;
      }
    }
    final neuJeId = {for (final n in ergebnis.neueSchritte) n.id: n};

    String anlageVon(String id) {
      if (neuJeId[id] case final n?) return n.maschine;
      final s = jeId[id];
      if (s == null) return 'einem Schritt, den es nicht mehr gibt';
      return k.maschinen[s.maschineId]?.name ??
          _leerZuNull(s.prozessschritt) ??
          'Ohne Anlage';
    }

    for (final e in ergebnis.entfernteSchritte) {
      final s = jeId[e.schrittId];
      final SchrittStand stand;
      String? hinweis;
      if (!produkte.contains(e.artikelId)) {
        stand = SchrittStand.artikelFehlt;
        hinweis = 'Den Artikel gibt es im Planer nicht mehr.';
      } else if (s == null || s.deletedAt != null) {
        stand = SchrittStand.schonEntfernt;
        hinweis = 'Ist im Planer schon nicht mehr in der Kette.';
      } else {
        stand = SchrittStand.entfernen;
        aktivJeArtikel[e.artikelId] = (aktivJeArtikel[e.artikelId] ?? 1) - 1;
      }
      vorschau.add(
        SchrittVorschau(
          entfernt: e,
          stand: stand,
          artikel: artikelText(e.artikelId, ''),
          text: '${s == null ? e.anlage : anlageVon(s.id)} entfernen',
          hinweis: hinweis,
        ),
      );
    }

    for (final n in ergebnis.neueSchritte) {
      final maschine = k.maschinen[n.maschineId];
      final SchrittStand stand;
      String? hinweis;
      if (!produkte.contains(n.artikelId)) {
        stand = SchrittStand.artikelFehlt;
        hinweis = 'Den Artikel gibt es im Planer nicht mehr.';
      } else if (jeId.containsKey(n.id)) {
        stand = SchrittStand.schonDa;
        hinweis = 'Steht schon in der Kette.';
      } else if (maschine == null || maschine.deletedAt != null) {
        stand = SchrittStand.maschineFehlt;
        hinweis = 'Die Maschine steht nicht mehr im Katalog.';
      } else if ((aktivJeArtikel[n.artikelId] ?? 0) >=
          ProzesskettenService.maxSchritte) {
        stand = SchrittStand.zuViele;
        hinweis = 'Die Kette hat schon ${ProzesskettenService.maxSchritte} '
            'Schritte — mehr kann ein Artikel nicht haben.';
      } else {
        stand = SchrittStand.neu;
        aktivJeArtikel[n.artikelId] = (aktivJeArtikel[n.artikelId] ?? 0) + 1;
        felder[n.id] = _felderVon(
          k,
          maschineId: n.maschineId,
          prozessschritt: null,
          alle: const [],
        );
      }
      final nach = n.nachSchrittId;
      vorschau.add(
        SchrittVorschau(
          neu: n,
          stand: stand,
          artikel: artikelText(n.artikelId, ''),
          text: '${maschine?.name ?? n.maschine} dazu — '
              '${nach == null ? 'ganz vorn' : 'nach ${anlageVon(nach)}'}',
          hinweis: hinweis,
        ),
      );
    }
    return (vorschau: vorschau, felder: felder);
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
    Iterable<SchrittVorschau> schritte = const [],
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
          endeVpk: e.endeVpk,
          notizen: e.notiz,
        );
        p++;
      }

      // Erst die Ketten: Was wegfällt, zuerst — dann ist Platz für das, was
      // dazukommt. Die Werte danach, damit sie auch an den neuen Schritten
      // landen.
      var k = 0;
      for (final x in schritte) {
        if (x.stand != SchrittStand.entfernen) continue;
        final e = x.entfernt!;
        final da = await (_db.select(_db.productSteps)
              ..where((s) => s.id.equals(e.schrittId))
              ..where((s) => s.deletedAt.isNull()))
            .getSingleOrNull();
        if (da == null) continue;
        await ProzesskettenService.entferneSchritt(_db, e.schrittId);
        k++;
      }
      for (final x in schritte) {
        if (x.stand != SchrittStand.neu) continue;
        if (await _schrittEinfuegen(x.neu!)) k++;
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
                (s) => s.id.isIn({for (final x in liste) x.schrittId}),
              ))
            .get();
        final staende = await _feldStaende(schritte);
        for (final x in liste) {
          _FeldStand? feld;
          for (final f
              in staende[x.schrittId]?.felder ?? const <_FeldStand>[]) {
            if (f.feld.schluessel == x.schluessel) {
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
                    stepId: Value(x.schrittId),
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
      return (produktionen: p, werte: w, fotos: f, schritte: k);
    });
  }

  /// Legt den neuen Schritt [n] an — hinter seinem Vorgänger, sonst am
  /// Ende seiner Abteilung. false, wenn es nicht geht: Er steht schon da,
  /// die Maschine fehlt, oder die Kette ist voll.
  Future<bool> _schrittEinfuegen(NeuerSchritt n) async {
    final schon = await (_db.select(_db.productSteps)
          ..where((s) => s.id.equals(n.id)))
        .getSingleOrNull();
    if (schon != null) return false;
    final maschine = await (_db.select(_db.machines)
          ..where((m) => m.id.equals(n.maschineId))
          ..where((m) => m.deletedAt.isNull()))
        .getSingleOrNull();
    if (maschine == null) return false;
    final kette = await ProzesskettenService.schritte(_db, n.artikelId);
    if (kette.length >= ProzesskettenService.maxSchritte) return false;
    final nach = n.nachSchrittId;
    int? index;
    if (nach == null) {
      index = 0;
    } else {
      final i = kette.indexWhere((s) => s.id == nach);
      // Gibt es den Vorgänger nicht mehr, kommt der Schritt ans Ende
      // seiner Abteilung — wie beim Einfügen am PC ohne Angabe.
      if (i >= 0) index = i + 1;
    }
    await ProzesskettenService.fuegeEin(
      _db,
      id: n.id,
      productId: n.artikelId,
      abteilung: _leerZuNull(n.abteilung) ?? maschine.abteilung,
      index: index,
      maschineId: maschine.id,
      maschine: maschine.name,
    );
    return true;
  }
}
