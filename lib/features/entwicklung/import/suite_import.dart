import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/database/database.dart';
import '../../../core/utils/krypto.dart';
import '../daten/dateien.dart';
import '../daten/entwicklung_repository.dart' show VersionStatus;
import '../haccp/haccp_modell.dart';
import '../haccp/prozess_modell.dart';
import '../projekte/projekt_modell.dart';
import '../rechenkern/allergen_hervorhebung.dart';
import '../rechenkern/rechen_modell.dart';

// Übernahme aus der alten Development-Suite.
//
// Gelesen wird das Backup-ZIP der Suite (quid_full_backup_*.zip):
//
//   projects.json      Projekte mit Verlauf, Rezeptur, Prozess, FMEA …
//   ingredients.json   der Zutaten-Katalog
//   recipes.json       die Rezepturen der Bibliothek
//   Kunden/<Kunde>/<Projekt>/Dateien/…   die Anhänge
//
// Alle IDs leiten sich aus denen der Suite ab („suite-…"). Ein zweiter
// Import desselben Backups legt deshalb nichts doppelt an, sondern
// überschreibt die übernommenen Einträge mit dem Stand der Suite.
//
// Rezepturen: Die Rezepturen der Bibliothek werden Entwürfe. In einem
// Projekt wird jeder gespeicherte Rezepturstand des Verlaufs ein
// abgeschlossener Stand — eingefroren mit den Zutatendaten von damals —,
// der aktuelle Stand der Suite ein Entwurf dahinter. Die Zeilen verweisen
// auf den Katalog; was dort fehlt, wird als Zutat angelegt.

/// Vorsilbe aller übernommenen IDs.
const String kSuitePraefix = 'suite-';

/// Ein gelesenes Suite-Backup.
class SuiteDaten {
  SuiteDaten({
    this.zutaten = const [],
    this.rezepturen = const [],
    this.projekte = const [],
    Map<String, Uint8List> dateien = const {},
  }) : _dateien = dateien;

  final List<Map<String, dynamic>> zutaten;
  final List<Map<String, dynamic>> rezepturen;
  final List<Map<String, dynamic>> projekte;

  /// Die Anhänge im ZIP: Pfad → Inhalt.
  final Map<String, Uint8List> _dateien;

  /// Dieselben Pfade nur aus Buchstaben und Ziffern — für Namen, deren
  /// Umlaute im ZIP anders kodiert sind.
  late final Map<String, String> _vereinfacht = {
    for (final pfad in _dateien.keys) _nurZeichen(pfad): pfad,
  };

  /// Eine Datei im ZIP — genau oder über den vereinfachten Pfad.
  Uint8List? datei(String pfad) {
    final genau = _dateien[pfad];
    if (genau != null) return genau;
    final gefunden = _vereinfacht[_nurZeichen(pfad)];
    return gefunden == null ? null : _dateien[gefunden];
  }
}

String _nurZeichen(String text) =>
    text.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Liest ein Suite-Backup: das ZIP oder eine einzelne JSON-Datei
/// (projects.json, ingredients.json oder recipes.json). Wirft
/// [FormatException], wenn nichts davon passt.
SuiteDaten suiteDatenLesen(Uint8List bytes) {
  final istZip = bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4b;
  if (!istZip) {
    final liste = _jsonListe(bytes, 'Die Datei');
    if (liste.isEmpty) return SuiteDaten();
    final erstes = liste.first;
    if (erstes.containsKey('timeline')) return SuiteDaten(projekte: liste);
    if (erstes.containsKey('cookingLoss') ||
        erstes.containsKey('ingredients')) {
      return SuiteDaten(rezepturen: liste);
    }
    if (erstes.containsKey('nutrition') ||
        erstes.containsKey('quidRequiredDefault')) {
      return SuiteDaten(zutaten: liste);
    }
    throw const FormatException(
      'Die JSON-Datei enthält weder Projekte noch Zutaten noch Rezepturen '
      'der Suite.',
    );
  }

  final Archive archiv;
  try {
    archiv = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw FormatException('Das ZIP ließ sich nicht öffnen: $e');
  }
  var zutaten = <Map<String, dynamic>>[];
  var rezepturen = <Map<String, dynamic>>[];
  var projekte = <Map<String, dynamic>>[];
  var gefunden = false;
  final dateien = <String, Uint8List>{};
  for (final datei in archiv.files) {
    if (!datei.isFile) continue;
    final name = datei.name.replaceAll('\\', '/');
    final wichtig = name == 'projects.json' ||
        name == 'ingredients.json' ||
        name == 'recipes.json' ||
        name.startsWith('Kunden/');
    if (!wichtig) continue;
    final roh = datei.content;
    if (roh is! List<int>) continue;
    final inhalt = Uint8List.fromList(roh);
    switch (name) {
      case 'projects.json':
        projekte = _jsonListe(inhalt, 'projects.json');
        gefunden = true;
      case 'ingredients.json':
        zutaten = _jsonListe(inhalt, 'ingredients.json');
        gefunden = true;
      case 'recipes.json':
        rezepturen = _jsonListe(inhalt, 'recipes.json');
        gefunden = true;
      default:
        dateien[name] = inhalt;
    }
  }
  if (!gefunden) {
    throw const FormatException(
      'Im ZIP fehlen projects.json, ingredients.json und recipes.json — '
      'ist es ein Backup der Suite?',
    );
  }
  return SuiteDaten(
    zutaten: zutaten,
    rezepturen: rezepturen,
    projekte: projekte,
    dateien: dateien,
  );
}

List<Map<String, dynamic>> _jsonListe(List<int> bytes, String name) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw FormatException('$name ist kein lesbares JSON.');
  }
  if (json is! List) throw FormatException('$name ist keine Liste.');
  return [
    for (final e in json)
      if (e is Map<String, dynamic>) e,
  ];
}

/// Eine Datei, die übernommen wird.
class SuiteDatei {
  const SuiteDatei({
    required this.id,
    required this.name,
    required this.inhalt,
    this.projektId,
    this.mimeTyp,
  });

  final String id;
  final String? projektId;
  final String name;
  final String? mimeTyp;
  final Uint8List inhalt;
}

/// Was übernommen wird — fertig zum Schreiben.
class SuiteImportPlan {
  final List<EntwicklungZutatenCompanion> zutaten = [];
  final List<EntwicklungRezepturenCompanion> rezepturen = [];
  final List<EntwicklungRezepturVersionenCompanion> versionen = [];
  final List<EntwicklungRezepturPositionenCompanion> positionen = [];
  final List<EntwicklungProjekteCompanion> projekte = [];
  final List<EntwicklungProjektEintraegeCompanion> eintraege = [];
  final List<EntwicklungFliessdiagrammeCompanion> fliessdiagramme = [];
  final List<SuiteDatei> dateien = [];

  /// Zutaten, die nur in Rezepturen standen und angelegt werden.
  int zutatenAusRezepturen = 0;

  /// Rezepturen der Bibliothek (auch aus Unterrezepturen angelegte).
  int bibliothek = 0;

  /// Projekte im Archiv.
  int archiviert = 0;

  /// Anhänge, deren Inhalt im Backup fehlt.
  final List<String> fehlendeDateien = [];

  /// Was beim Übernehmen auffiel — zum Nachsehen.
  final List<String> hinweise = [];

  bool get leer => zutaten.isEmpty && rezepturen.isEmpty && projekte.isEmpty;

  /// Die Kennzahlen für Vorschau und Bericht.
  List<({String label, int anzahl, String? davon})> get zahlen => [
        (
          label: 'Zutaten',
          anzahl: zutaten.length,
          davon: zutatenAusRezepturen == 0
              ? null
              : '$zutatenAusRezepturen nur aus Rezepturen',
        ),
        (
          label: 'Rezepturen',
          anzahl: rezepturen.length,
          davon: rezepturen.isEmpty
              ? null
              : '$bibliothek Bibliothek, ${rezepturen.length - bibliothek} '
                  'aus Projekten',
        ),
        (label: 'Rezepturstände', anzahl: versionen.length, davon: null),
        (
          label: 'Projekte',
          anzahl: projekte.length,
          davon: archiviert == 0 ? null : '$archiviert im Archiv',
        ),
        (label: 'Verlaufseinträge', anzahl: eintraege.length, davon: null),
        (
          label: 'Dateien',
          anzahl: dateien.length,
          davon: fehlendeDateien.isEmpty
              ? null
              : '${fehlendeDateien.length} ohne Inhalt',
        ),
        (label: 'Fließdiagramme', anzahl: fliessdiagramme.length, davon: null),
      ];
}

/// Plant die Übernahme von [daten]. [vorhandeneZutaten]: Namen (klein)
/// der Zutaten, die hier schon von Hand angelegt sind — für einen
/// Hinweis auf Doppelte. [jetzt] für Einträge ohne Datum.
SuiteImportPlan suiteImportPlanen(
  SuiteDaten daten, {
  Set<String> vorhandeneZutaten = const {},
  DateTime? jetzt,
}) =>
    _Planer(daten, jetzt ?? DateTime.now(), vorhandeneZutaten).planen();

/// Liest und plant auf einem eigenen Isolate — ein Backup mit vielen
/// Anhängen hielte die Oberfläche sonst an. Wirft [FormatException].
///
/// Ohne `async`: Die Funktion für das Isolate nimmt nur ihre Argumente
/// mit.
Future<SuiteImportPlan> suiteImportVorbereiten(
  Uint8List bytes, {
  Set<String> vorhandeneZutaten = const {},
}) =>
    Isolate.run(
      () => suiteImportPlanen(
        suiteDatenLesen(bytes),
        vorhandeneZutaten: vorhandeneZutaten,
      ),
    );

/// Schreibt [plan] in die Datenbank — Dateien verschlüsselt mit dem
/// Datenschlüssel ([dateien]).
Future<void> suiteImportAusfuehren(
  AppDatabase db,
  SuiteImportPlan plan,
  EntwicklungDateienDienst dateien,
) async {
  // Erst verschlüsseln, dann in einem Zug schreiben.
  final pakete = <String, Uint8List>{
    for (final d in plan.dateien) d.id: await dateien.verschluesselt(d.inhalt),
  };
  final versionen = [
    for (final v in plan.versionen) v.id.value,
  ];
  await db.transaction(() async {
    // Zeilen eines früher übernommenen Stands ersetzen, nicht ergänzen.
    if (versionen.isNotEmpty) {
      await (db.delete(db.entwicklungRezepturPositionen)
            ..where((p) => p.versionId.isIn(versionen)))
          .go();
    }
    await db.batch((b) {
      const ersetzen = InsertMode.insertOrReplace;
      b.insertAll(db.entwicklungZutaten, plan.zutaten, mode: ersetzen);
      b.insertAll(db.entwicklungRezepturen, plan.rezepturen, mode: ersetzen);
      b.insertAll(
        db.entwicklungRezepturVersionen,
        plan.versionen,
        mode: ersetzen,
      );
      b.insertAll(
        db.entwicklungRezepturPositionen,
        plan.positionen,
        mode: ersetzen,
      );
      b.insertAll(db.entwicklungProjekte, plan.projekte, mode: ersetzen);
      b.insertAll(
        db.entwicklungProjektEintraege,
        plan.eintraege,
        mode: ersetzen,
      );
      b.insertAll(
        db.entwicklungDateien,
        [
          for (final d in plan.dateien)
            EntwicklungDateienCompanion.insert(
              id: d.id,
              name: d.name,
              projektId: Value(d.projektId),
              mimeTyp: Value(d.mimeTyp),
              groesse: Value(d.inhalt.length),
            ),
        ],
        mode: ersetzen,
      );
      b.insertAll(
        db.entwicklungDateiInhalte,
        [
          for (final MapEntry(:key, :value) in pakete.entries)
            EntwicklungDateiInhalteCompanion.insert(
              dateiId: key,
              inhalt: value,
            ),
        ],
        mode: ersetzen,
      );
      // Bezeichnungen, die schon gepflegt sind, bleiben.
      b.insertAll(
        db.entwicklungFliessdiagramme,
        plan.fliessdiagramme,
        mode: InsertMode.insertOrIgnore,
      );
    });
  });
}

/// Allergen der Suite → Wert des Planers. null, wenn unbekannt.
String? planerAllergen(String suite) {
  switch (suite.trim().toLowerCase()) {
    case 'gluten':
      return 'gluten';
    case 'ei':
    case 'eier':
    case 'eggs':
      return 'eier';
    case 'soja':
    case 'soy':
      return 'soja';
    case 'milch':
    case 'milk':
      return 'milch';
    case 'schalenfrüchte':
    case 'schalenfruechte':
    case 'nuts':
      return 'schalenfruechte';
    case 'sellerie':
    case 'celery':
      return 'sellerie';
    case 'senf':
    case 'mustard':
      return 'senf';
    case 'sesam':
    case 'sesame':
      return 'sesam';
    case 'sulfit':
    case 'sulfite':
    case 'sulphites':
      return 'sulfit';
    case 'lupine':
    case 'lupinen':
    case 'lupin':
      return 'lupinen';
    case 'weichtiere':
    case 'molluscs':
      return 'weichtiere';
    case 'erdnuesse':
    case 'erdnüsse':
    case 'peanuts':
      return 'erdnuesse';
    case 'fisch':
    case 'fish':
      return 'fisch';
    case 'krebstiere':
    case 'crustaceans':
      return 'krebstiere';
    case 'keine':
      return kAllergenKeine;
  }
  return null;
}

// ── Die Planung ───────────────────────────────────────────────────────

/// Ein Objekt der Suite mit nachsichtigem Lesen: Zahlen dürfen auch als
/// Text kommen, Texte auch als Zahl.
class _Roh {
  _Roh(this.j);

  final Map<String, dynamic> j;

  String t(String k) {
    final v = j[k];
    if (v is String) return v.trim();
    if (v is int) return '$v';
    if (v is double) return v == v.roundToDouble() ? '${v.round()}' : '$v';
    return '';
  }

  String? n(String k) {
    final v = t(k);
    return v.isEmpty ? null : v;
  }

  bool b(String k) => j[k] == true;

  double? z(String k) => _zahl(j[k]);

  String get name => t('name').isEmpty ? '(ohne Namen)' : t('name');
  String? get nummer => n('articleNumber');
  bool get istRezeptur => b('isRecipe');
  double get menge => z('rawWeight') ?? 0;

  double? nw(String k) {
    final w = j['nutrition'];
    return w is Map<String, dynamic> ? _zahl(w[k]) : null;
  }

  List<String> get allergeneRoh => [
        for (final a in (j['allergens'] as List?) ?? const [])
          if (a is String) a,
      ];

  List<Map<String, dynamic>> get unterzutatenListe => [
        for (final u in (j['originalSubIngredients'] as List?) ?? const [])
          if (u is Map<String, dynamic>) u,
      ];

  List<Map<String, dynamic>> get zeilen => [
        for (final i in (j['ingredients'] as List?) ?? const [])
          if (i is Map<String, dynamic>) i,
      ];
}

double? _zahl(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
  return null;
}

class _Planer {
  _Planer(this.d, this.jetzt, this.vorhandeneZutaten);

  final SuiteDaten d;
  final DateTime jetzt;
  final Set<String> vorhandeneZutaten;
  final SuiteImportPlan plan = SuiteImportPlan();

  /// Zutaten: „artikelnummer|name" bzw. Name → ID. Ein Name, der im
  /// Katalog zweimal vorkommt, steht mit null da — er taugt nicht zum
  /// Zuordnen.
  final Map<String, String> _zutatNachSchluessel = {};
  final Map<String, String?> _zutatNachName = {};
  final Map<String, RechenZutat> _zutatDaten = {};
  final Set<String> _abweichend = {};
  final Set<String> _unbekannteAllergene = {};
  final Set<String> _eiOhneEi = {};
  final Set<String> _doppelt = {};

  /// Rezepturen der Bibliothek: Name bzw. Nummer → ID.
  final Map<String, String> _rezepturNachName = {};
  final Map<String, String> _rezepturNachNummer = {};
  final Set<String> _angelegteRezepturen = {};
  final Set<String> _fliessdiagramme = {};

  SuiteImportPlan planen() {
    for (final z in d.zutaten) {
      _katalogZutat(_Roh(z));
    }
    for (final r in d.rezepturen) {
      final roh = _Roh(r);
      final id = '${kSuitePraefix}r-${_suiteId(r, roh.name)}';
      _rezepturNachName.putIfAbsent(roh.name.toLowerCase(), () => id);
      final nummer = roh.nummer;
      if (nummer != null) _rezepturNachNummer.putIfAbsent(nummer, () => id);
    }
    for (final r in d.rezepturen) {
      final roh = _Roh(r);
      _bibliotheksRezeptur(r, '${kSuitePraefix}r-${_suiteId(r, roh.name)}');
    }
    for (final p in d.projekte) {
      _projekt(p);
    }
    for (final fd in _fliessdiagramme.toList()..sort()) {
      plan.fliessdiagramme.add(
        EntwicklungFliessdiagrammeCompanion.insert(id: fd, bezeichnung: fd),
      );
    }

    String liste(Set<String> namen) => (namen.toList()..sort()).join(', ');
    if (_eiOhneEi.isNotEmpty) {
      plan.hinweise.add(
        'Als Ei markiert, ohne ein Ei zu nennen — die Suite setzte beim '
        'Excel-Import „Ei" für jedes „ei" im Allergentext. Bitte prüfen: '
        '${liste(_eiOhneEi)}.',
      );
    }
    if (_abweichend.isNotEmpty) {
      plan.hinweise.add(
        'In Rezepturen standen andere Werte als im Katalog. Die Entwürfe '
        'rechnen jetzt mit dem Katalog, abgeschlossene Stände mit den '
        'Werten von damals: ${liste(_abweichend)}.',
      );
    }
    if (_doppelt.isNotEmpty) {
      plan.hinweise.add(
        'Gibt es hier schon (von Hand angelegt) und kommt jetzt ein zweites '
        'Mal: ${liste(_doppelt)}.',
      );
    }
    if (_unbekannteAllergene.isNotEmpty) {
      plan.hinweise.add(
        'Unbekannte Allergene übergangen: ${liste(_unbekannteAllergene)}.',
      );
    }
    if (plan.fehlendeDateien.isNotEmpty) {
      plan.hinweise.add(
        'Ohne Inhalt im Backup, nur der Eintrag kommt mit: '
        '${plan.fehlendeDateien.join(', ')}.',
      );
    }
    return plan;
  }

  // ── Zutaten ─────────────────────────────────────────────────────────

  static String _schluessel(String name, String? nummer) =>
      '${(nummer ?? '').toLowerCase()}|${name.toLowerCase()}';

  Set<String> _allergene(_Roh z) {
    final ergebnis = <String>{};
    for (final a in z.allergeneRoh) {
      final p = planerAllergen(a);
      if (p == null) {
        if (a.trim().isNotEmpty) _unbekannteAllergene.add(a.trim());
      } else {
        ergebnis.add(p);
      }
    }
    if (ergebnis.length > 1) ergebnis.remove(kAllergenKeine);
    return ergebnis;
  }

  RechenZutat _rechenZutat(_Roh z, String id, {required bool katalog}) =>
      RechenZutat(
        id: id,
        name: z.name,
        etikettName: z.n('labelName'),
        istFleisch: z.b('isMeat'),
        istWasser: z.b('isWater'),
        tierart: Tierart.aus(z.n('meatSpecies')),
        bindegewebe: z.z('connectiveTissuePercent'),
        quidPflicht: z.b(katalog ? 'quidRequiredDefault' : 'quidRequired'),
        unterzutaten: z.n('subIngredients'),
        verarbeitungshilfsstoffe: [
          for (final h in (z.n('processingAids') ?? '').split(RegExp('[,;]')))
            if (h.trim().isNotEmpty) h.trim(),
        ],
        allergene: _allergene(z),
        naehrwerte: Naehrwerte(
          energieKj: z.nw('energyKj'),
          energieKcal: z.nw('energyKcal'),
          fett: z.nw('fat'),
          gesaettigteFettsaeuren: z.nw('saturatedFat'),
          kohlenhydrate: z.nw('carbohydrates'),
          zucker: z.nw('sugar'),
          eiweiss: z.nw('protein'),
          salz: z.nw('salt'),
          wasser: z.nw('water'),
          asche: z.nw('ash'),
          beffe: z.nw('beffe'),
        ),
      );

  void _zutatSpeichern(_Roh z, RechenZutat r, {required String notiz}) {
    final n = r.naehrwerte;
    plan.zutaten.add(
      EntwicklungZutatenCompanion.insert(
        id: r.id,
        name: r.name,
        artikelnummer: Value(z.nummer),
        etikettName: Value(r.etikettName),
        istFleisch: Value(r.istFleisch),
        istWasser: Value(r.istWasser),
        tierart: Value(r.tierart?.schluessel),
        bindegewebe: Value(r.bindegewebe),
        fleischeiweissGrenze: Value(z.z('meatProteinLimit')),
        quidPflicht: Value(r.quidPflicht),
        unterzutaten: Value(r.unterzutaten),
        verarbeitungshilfsstoffe: Value(
          r.verarbeitungshilfsstoffe.isEmpty
              ? null
              : r.verarbeitungshilfsstoffe.join(', '),
        ),
        allergene: Value(merkmaleZuText(r.allergene, kAllergene)),
        energieKj: Value(n.energieKj),
        energieKcal: Value(n.energieKcal),
        fett: Value(n.fett),
        gesaettigteFettsaeuren: Value(n.gesaettigteFettsaeuren),
        kohlenhydrate: Value(n.kohlenhydrate),
        zucker: Value(n.zucker),
        eiweiss: Value(n.eiweiss),
        salz: Value(n.salz),
        wasser: Value(n.wasser),
        asche: Value(n.asche),
        beffe: Value(n.beffe),
        notiz: Value(notiz),
        createdAt: Value(jetzt),
        updatedAt: Value(jetzt),
      ),
    );
    _zutatNachSchluessel[_schluessel(r.name, z.nummer)] = r.id;
    final name = r.name.toLowerCase();
    _zutatNachName[name] = _zutatNachName.containsKey(name) ? null : r.id;
    _zutatDaten[r.id] = r;

    if (vorhandeneZutaten.contains(name.trim())) _doppelt.add(r.name);
    if (r.allergene.contains('eier')) {
      final texte = [r.name, r.etikettName ?? '', r.unterzutaten ?? ''];
      final nenntEi = texte.any(
        (t) => hebeAllergeneHervor(t, const {'eier'}).gefunden.isNotEmpty,
      );
      if (!nenntEi) _eiOhneEi.add(r.name);
    }
  }

  void _katalogZutat(_Roh z) {
    final id = '${kSuitePraefix}z-${_suiteId(z.j, z.name)}';
    _zutatSpeichern(
      z,
      _rechenZutat(z, id, katalog: true),
      notiz: 'Aus dem Katalog der Suite übernommen',
    );
  }

  /// Die Katalog-Zutat zu einer Rezepturzeile — gefunden über Nummer und
  /// Name oder neu angelegt.
  String _zutatFuer(_Roh z) {
    final schluessel = _schluessel(z.name, z.nummer);
    final gefunden = _zutatNachSchluessel[schluessel] ??
        _zutatNachName[z.name.toLowerCase()];
    if (gefunden != null) {
      final katalog = _zutatDaten[gefunden];
      final hier = _rechenZutat(z, gefunden, katalog: false);
      if (katalog != null && _weichtAb(katalog, hier)) _abweichend.add(z.name);
      return gefunden;
    }
    final id = '${kSuitePraefix}zr-${_kurz(schluessel)}';
    plan.zutatenAusRezepturen++;
    _zutatSpeichern(
      z,
      _rechenZutat(z, id, katalog: false),
      notiz: 'Aus einer Rezeptur der Suite übernommen — stand nicht im '
          'Katalog',
    );
    return id;
  }

  static bool _weichtAb(RechenZutat a, RechenZutat b) {
    bool anders(double? x, double? y) =>
        (x == null) != (y == null) ||
        (x != null && y != null && (x - y).abs() > 1e-6);
    final na = a.naehrwerte;
    final nb = b.naehrwerte;
    return a.istFleisch != b.istFleisch ||
        a.tierart != b.tierart ||
        anders(na.fett, nb.fett) ||
        anders(na.eiweiss, nb.eiweiss) ||
        anders(na.salz, nb.salz) ||
        anders(a.bindegewebe, b.bindegewebe) ||
        a.allergene.length != b.allergene.length ||
        !a.allergene.containsAll(b.allergene);
  }

  // ── Rezepturen ──────────────────────────────────────────────────────

  void _bibliotheksRezeptur(Map<String, dynamic> r, String id) {
    if (!_angelegteRezepturen.add(id)) return;
    final roh = _Roh(r);
    final datum = _datum(r['updatedAt']);
    plan.bibliothek++;
    plan.rezepturen.add(
      EntwicklungRezepturenCompanion.insert(
        id: id,
        name: roh.name,
        artikelnummer: Value(roh.nummer),
        beschreibung: Value(roh.n('description')),
        createdAt: Value(datum ?? jetzt),
        updatedAt: Value(datum ?? jetzt),
      ),
    );
    _version(
      r,
      rezepturId: id,
      versionId: '$id-v1',
      nummer: 1,
      abgeschlossen: false,
      bezeichnung: 'aus der Suite',
      datum: datum,
    );
  }

  /// Die Rezeptur zu einer Unterrezeptur-Zeile — aus der Bibliothek oder
  /// aus den Zutaten, die die Zeile mitbringt.
  String _unterrezepturFuer(_Roh z) {
    final nummer = z.nummer;
    final gefunden = (nummer == null ? null : _rezepturNachNummer[nummer]) ??
        _rezepturNachName[z.name.toLowerCase()];
    if (gefunden != null) return gefunden;
    final id = '${kSuitePraefix}u-${_kurz(_schluessel(z.name, nummer))}';
    _rezepturNachName[z.name.toLowerCase()] = id;
    if (nummer != null) _rezepturNachNummer[nummer] = id;
    final rezept = <String, dynamic>{
      'name': z.name,
      'articleNumber': nummer,
      'description': 'Aus einer Unterrezeptur der Suite übernommen',
      'cookingLoss': z.z('processLoss') ?? 0,
      'ingredients': z.unterzutatenListe,
    };
    _bibliotheksRezeptur(rezept, id);
    return id;
  }

  /// Ein Stand aus einer Rezeptur der Suite (SavedRecipe).
  void _version(
    Map<String, dynamic> rezept, {
    required String rezepturId,
    required String versionId,
    required int nummer,
    required bool abgeschlossen,
    String? bezeichnung,
    DateTime? datum,
  }) {
    final r = _Roh(rezept);
    final stand = abgeschlossen
        ? jsonEncode(_rechenRezeptur(rezept, rezepturId).toJson())
        : null;
    plan.versionen.add(
      EntwicklungRezepturVersionenCompanion.insert(
        id: versionId,
        rezepturId: rezepturId,
        nummer: nummer,
        bezeichnung: Value(bezeichnung),
        status: Value(
          abgeschlossen ? VersionStatus.abgeschlossen : VersionStatus.entwurf,
        ),
        verlustProzent: Value(r.z('cookingLoss') ?? 0),
        fettVerlustProzent: Value(r.z('fatLoss') ?? 0),
        verlustArt: Value(_verlustart(r.n('lossType')).schluessel),
        stand: Value(stand),
        abgeschlossenAm: Value(abgeschlossen ? (datum ?? jetzt) : null),
        createdAt: Value(datum ?? jetzt),
        updatedAt: Value(datum ?? jetzt),
      ),
    );
    final zeilen = r.zeilen;
    for (var i = 0; i < zeilen.length; i++) {
      final z = _Roh(zeilen[i]);
      final unter = z.istRezeptur;
      final quid = z.j['quidRequired'];
      plan.positionen.add(
        EntwicklungRezepturPositionenCompanion.insert(
          id: '$versionId-p$i',
          versionId: versionId,
          reihenfolge: Value(i),
          zutatId: Value(unter ? null : _zutatFuer(z)),
          unterrezepturId: Value(unter ? _unterrezepturFuer(z) : null),
          mengeKg: Value(z.menge),
          quidPflicht: Value(!unter && quid is bool ? quid : null),
          createdAt: Value(datum ?? jetzt),
          updatedAt: Value(datum ?? jetzt),
        ),
      );
    }
  }

  /// Die Eingabe des Rechenkerns aus einer Rezeptur der Suite — mit den
  /// Zutatendaten, die sie damals mitgespeichert hat.
  RechenRezeptur _rechenRezeptur(Map<String, dynamic> rezept, String id) {
    final r = _Roh(rezept);
    return RechenRezeptur(
      id: id,
      name: r.name,
      verlustProzent: r.z('cookingLoss') ?? 0,
      fettVerlustProzent: r.z('fatLoss') ?? 0,
      verlustart: _verlustart(r.n('lossType')),
      positionen: [for (final i in r.zeilen) _rechenPosition(_Roh(i))],
    );
  }

  RechenPosition _rechenPosition(_Roh z) {
    if (!z.istRezeptur) {
      final quid = z.j['quidRequired'];
      return RechenPosition.zutat(
        _rechenZutat(z, _zutatFuer(z), katalog: false),
        mengeKg: z.menge,
        quidPflicht: quid is bool ? quid : null,
      );
    }
    final unterId = _unterrezepturFuer(z);
    return RechenPosition.unterrezeptur(
      RechenRezeptur(
        id: unterId,
        name: z.name,
        verlustProzent: z.z('processLoss') ?? 0,
        positionen: [
          for (final u in z.unterzutatenListe) _rechenPosition(_Roh(u)),
        ],
      ),
      mengeKg: z.menge,
    );
  }

  static Verlustart _verlustart(String? suite) {
    switch (suite) {
      case 'cooking':
        return Verlustart.garen;
      case 'none':
        return Verlustart.keiner;
      default:
        return Verlustart.trocknung;
    }
  }

  // ── Projekte ────────────────────────────────────────────────────────

  void _projekt(Map<String, dynamic> p) {
    final roh = _Roh(p);
    final id = '${kSuitePraefix}p-${_suiteId(p, roh.name)}';
    final status = ProjektStatus.aus(roh.n('status'));
    if (status == ProjektStatus.archiviert) plan.archiviert++;
    final kunde = roh.n('customer');
    final verlauf = [
      for (final e in (p['timeline'] as List?) ?? const [])
        if (e is Map<String, dynamic>) e,
    ];

    final versionZuEintrag = _projektRezeptur(p, id, verlauf);
    final bildId = _produktbild(roh, id);

    for (final e in verlauf) {
      _eintrag(e, id, kunde ?? 'Allgemein', roh.name, versionZuEintrag);
    }

    // Checklisten mit den Schlüsseln von hier.
    Set<String> haken(Object? json, Map<String, String> schluessel) => {
          if (json is Map<String, dynamic>)
            for (final MapEntry(:key, :value) in json.entries)
              if (value == true && schluessel[key] != null) schluessel[key]!,
        };

    final fd = roh.n('processFlow');
    if (fd != null) _fliessdiagramme.add(fd);
    final parameter = p['parameters'];
    final ziele = _Roh(
      parameter is Map<String, dynamic> ? parameter : <String, dynamic>{},
    );
    final notizen = [
      if (roh.n('notes') != null) roh.n('notes')!,
      if (roh.n('riskAnalysis') != null)
        'Risikoanalyse (aus der Suite): ${roh.n('riskAnalysis')}',
    ].join('\n\n');

    plan.projekte.add(
      EntwicklungProjekteCompanion.insert(
        id: id,
        name: roh.name,
        kunde: Value(kunde),
        artikelnummer: Value(roh.nummer),
        status: Value(status.schluessel),
        produktidee: Value(roh.n('productIdea')),
        kundenvereinbarungen: Value(roh.n('customerAgreements')),
        fliessdiagramm: Value(fd),
        neuerProzess: Value(roh.b('isNewProcess')),
        neueZutaten: Value(roh.b('hasNewIngredients')),
        neueZutatenDetails: Value(roh.n('newIngredientDetails')),
        zielFett: Value(ziele.z('fatTarget')),
        zielEiweiss: Value(ziele.z('proteinTarget')),
        grenzeAw: Value(ziele.z('awLimit')),
        notizen: Value(notizen.isEmpty ? null : notizen),
        bildDateiId: Value(bildId),
        sensorik: Value(Sensorik.ausSuite(p['sensory']).alsJson()),
        checkliste: Value(
          checklisteZuJson(haken(p['checklist'], kSuiteProjektCheckliste)),
        ),
        etikettCheckliste: Value(
          checklisteZuJson(
            haken(p['labelChecklist'], kSuiteEtikettCheckliste),
          ),
        ),
        prozess: Value(
          Prozessparameter.ausJson(p['processSettings'], suite: true).alsJson(),
        ),
        prozessHistorie: Value(
          ProzessStand.listeZuJson(ProzessStand.ausSuite(p['processHistory'])),
        ),
        haccp: Value(Haccp.ausSuite(p['fmeaData']).alsJson()),
        createdAt: Value(_datum(p['createdAt']) ?? jetzt),
        updatedAt: Value(_datum(p['updatedAt']) ?? jetzt),
      ),
    );
  }

  /// Die Rezeptur eines Projekts: die gespeicherten Stände des Verlaufs
  /// als abgeschlossene Stände, der aktuelle Stand als Entwurf dahinter.
  /// Gibt zurück, welcher Eintrag zu welchem Stand gehört.
  Map<String, String> _projektRezeptur(
    Map<String, dynamic> p,
    String projektId,
    List<Map<String, dynamic>> verlauf,
  ) {
    final staende = [
      for (final e in verlauf)
        if (e['type'] == 'recipe' && e['value'] is String) e,
    ]..sort((a, b) {
        final c =
            (_datum(a['date']) ?? jetzt).compareTo(_datum(b['date']) ?? jetzt);
        return c != 0 ? c : '${a['id']}'.compareTo('${b['id']}');
      });
    final aktuell = p['currentRecipe'];
    final zuordnung = <String, String>{};
    if (staende.isEmpty && aktuell is! Map<String, dynamic>) return zuordnung;

    final roh = _Roh(p);
    final rezepturId = '$projektId-r';
    final name = aktuell is Map<String, dynamic> ? _Roh(aktuell).t('name') : '';
    plan.rezepturen.add(
      EntwicklungRezepturenCompanion.insert(
        id: rezepturId,
        name: name.isEmpty ? roh.name : name,
        artikelnummer: Value(roh.nummer),
        projektId: Value(projektId),
        createdAt: Value(_datum(p['createdAt']) ?? jetzt),
        updatedAt: Value(_datum(p['updatedAt']) ?? jetzt),
      ),
    );
    var nummer = 0;
    Map<String, dynamic>? letzter;
    for (final e in staende) {
      final Object? stand;
      try {
        stand = jsonDecode(e['value'] as String);
      } on FormatException {
        continue;
      }
      if (stand is! Map<String, dynamic>) continue;
      nummer++;
      final versionId = '$rezepturId-v$nummer';
      _version(
        stand,
        rezepturId: rezepturId,
        versionId: versionId,
        nummer: nummer,
        abgeschlossen: true,
        bezeichnung: _Roh(e).n('title'),
        datum: _datum(e['date']),
      );
      zuordnung['${e['id']}'] = versionId;
      letzter = stand;
    }
    if (aktuell is Map<String, dynamic> &&
        (letzter == null || !_gleicheRezeptur(aktuell, letzter))) {
      nummer++;
      _version(
        aktuell,
        rezepturId: rezepturId,
        versionId: '$rezepturId-v$nummer',
        nummer: nummer,
        abgeschlossen: false,
        bezeichnung: 'aktueller Stand aus der Suite',
        datum: _datum(p['updatedAt']),
      );
    }
    return zuordnung;
  }

  /// Das Produktbild als Datei. Gibt ihre ID zurück.
  String? _produktbild(_Roh p, String projektId) {
    final bild = p.n('productImage');
    if (bild == null) return null;
    final daten = ausDatenUrl(bild);
    if (daten == null) return null;
    final id = '$projektId-bild';
    plan.dateien.add(
      SuiteDatei(
        id: id,
        projektId: projektId,
        name: 'Produktbild${_endung(daten.mimeTyp)}',
        mimeTyp: daten.mimeTyp,
        inhalt: daten.inhalt,
      ),
    );
    return id;
  }

  void _eintrag(
    Map<String, dynamic> e,
    String projektId,
    String kunde,
    String projektName,
    Map<String, String> versionZuEintrag,
  ) {
    final ev = _Roh(e);
    final art = EintragArt.aus(ev.n('type'));

    String? dateiId;
    final anhang = ev.n('attachment');
    if (anhang != null) {
      final inhalt = _anhang(e, kunde, projektName);
      if (inhalt == null) {
        plan.fehlendeDateien.add(anhang);
      } else {
        dateiId = '$projektId-d${e['id']}';
        plan.dateien.add(
          SuiteDatei(
            id: dateiId,
            projektId: projektId,
            name: anhang,
            mimeTyp: ev.n('attachmentType'),
            inhalt: inhalt,
          ),
        );
      }
    }

    String? wert = ev.n('value');
    if (art == EintragArt.rezeptur) {
      // Der Stand steckt jetzt in der Rezeptur.
      wert = null;
    } else if (art == EintragArt.parameter && wert != null) {
      try {
        final p = Prozessparameter.ausJson(jsonDecode(wert), suite: true);
        if (!p.leer) wert = p.alsJson();
      } on FormatException {
        // Kein JSON — der Text bleibt.
      }
    }
    final aenderungen = [
      for (final a in (e['changes'] as List?) ?? const [])
        if (a is String) a,
    ];
    final kommentare = [
      for (final k in (e['comments'] as List?) ?? const [])
        if (k is Map<String, dynamic>)
          Kommentar(
            name: _Roh(k).t('user'),
            text: _Roh(k).t('text'),
            datum: _datum(k['date']) ?? jetzt,
          ),
    ];
    final datum = _datum(e['date']) ?? jetzt;
    plan.eintraege.add(
      EntwicklungProjektEintraegeCompanion.insert(
        id: '$projektId-e${e['id']}',
        projektId: projektId,
        art: art.schluessel,
        titel: ev.t('title').isEmpty ? art.label : ev.t('title'),
        datum: datum,
        benutzer: Value(ev.n('user')),
        beschreibung: Value(ev.n('description')),
        status: Value(EintragStatus.aus(ev.n('status')).schluessel),
        wert: Value(wert),
        ziel: Value(ev.n('target')),
        aenderungen: Value(
          aenderungen.isEmpty ? null : jsonEncode(aenderungen),
        ),
        dateiId: Value(dateiId),
        versionId: Value(versionZuEintrag['${e['id']}']),
        kommentare: Value(Kommentar.listeZuJson(kommentare)),
        createdAt: Value(datum),
        updatedAt: Value(datum),
      ),
    );
  }

  /// Der Inhalt eines Anhangs: im JSON selbst, im Ordner des Projekts oder
  /// über den Verweis auf eine gleiche Datei anderswo im ZIP.
  Uint8List? _anhang(Map<String, dynamic> e, String kunde, String projekt) {
    final inline = e['attachmentContent'];
    if (inline is String) {
      final daten = ausDatenUrl(inline);
      if (daten != null) return daten.inhalt;
    }
    final name = e['attachment'] is String ? e['attachment'] as String : '';
    final ordner =
        d.datei('Kunden/${_sicher(kunde)}/${_sicher(projekt)}/Dateien/$name');
    if (ordner != null) return ordner;
    final ref = e['attachmentRef'];
    return ref is String ? d.datei(ref) : null;
  }

  /// Wie die Suite Ordnernamen bildet.
  static String _sicher(String name) =>
      name.replaceAll(RegExp(r'[^a-zA-Z0-9äöüßÄÖÜ \-]'), '_');

  static bool _gleicheRezeptur(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    String kurz(Map<String, dynamic> r) => jsonEncode({
          'verlust': r['cookingLoss'],
          'fett': r['fatLoss'],
          'art': r['lossType'],
          'zeilen': [
            for (final i in (r['ingredients'] as List?) ?? const [])
              if (i is Map<String, dynamic>) [i['name'], i['rawWeight']],
          ],
        });
    return kurz(a) == kurz(b);
  }
}

String _suiteId(Map<String, dynamic> j, String name) {
  final id = '${j['id'] ?? ''}'.trim();
  return id.isEmpty ? _kurz(name) : id;
}

DateTime? _datum(Object? wert) =>
    wert is String && wert.isNotEmpty ? DateTime.tryParse(wert) : null;

String _endung(String? mime) => switch (mime) {
      'image/png' => '.png',
      'image/jpeg' || 'image/jpg' => '.jpg',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      _ => '',
    };

/// Ein kurzer, fester Schlüssel aus einem Text — gleiche Texte ergeben bei
/// jedem Import dieselbe ID.
String _kurz(String text) {
  final h = hmacSha256(utf8.encode('suite-import'), utf8.encode(text));
  return [
    for (final b in h.take(8)) b.toRadixString(16).padLeft(2, '0'),
  ].join();
}
