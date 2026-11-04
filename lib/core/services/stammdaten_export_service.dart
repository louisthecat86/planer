import 'dart:collection';
import 'dart:isolate';

import 'package:drift/drift.dart';

import '../constants/abteilungen.dart';
import '../constants/artikel_merkmale.dart';
import '../constants/parameter_namen.dart';
import '../constants/product_groups.dart';
import '../database/database.dart';
import '../utils/fehler_text.dart';
import '../utils/xlsx_schreiber.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Ergebnis
// ═══════════════════════════════════════════════════════════════════════════

class StammdatenExportErgebnis {
  const StammdatenExportErgebnis({
    required this.bytes,
    required this.dateiname,
    this.artikel = 0,
    this.anlagen = 0,
    this.warnungen = const [],
  });

  final Uint8List bytes;
  final String dateiname;
  final int artikel;
  final int anlagen;
  final List<String> warnungen;
}

// ═══════════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════════

/// Erzeugt die Stammdaten-Arbeitsmappe vollständig aus dem App-Stand.
///
/// Das Gegenstück zu `StammdatenImportService`: Was dieser Generator
/// schreibt, liest der Importer wieder ein. Beide teilen sich die festen
/// Zeilenlagen des Artikelblatts und die Namensregeln für Plattenwerte.
///
/// **Keine Vorlage.** Die Mappe entsteht jedes Mal neu aus der Datenbank.
/// Es gibt keinen Zustand außerhalb der App, der verlorengehen oder
/// veralten könnte — der Grund, warum der alte Exporter nach einem Reset
/// nicht mehr lief.
///
/// **Alles kommt aus der Datenbank.** Anlagen, Steckbriefe, Abteilungen
/// werden gelesen, nicht fest einprogrammiert. Eine in der App neu
/// angelegte Anlage erscheint deshalb ohne Codeänderung im Blatt
/// „Anlagen", im Steckbrief und — sobald ein Schritt sie benutzt — als
/// eigener Block im Artikelblatt.
///
/// **Aufgebaut wird das XML von Hand**, nicht über das `excel`-Paket. Das
/// Paket kann weder Auswahlmenüs noch fixierte Bereiche, und die Mappe muss
/// zwei Eigenheiten der Lesebibliothek erfüllen: Texte als geteilte
/// Zeichenketten (`sharedStrings.xml`) und Blattpfade relativ. Fehlt eines
/// davon, scheitert der Import mit „Null check operator used on a null
/// value", noch bevor eine Zelle gelesen wurde.
class StammdatenExportService {
  StammdatenExportService(this._db);

  final AppDatabase _db;

  Future<StammdatenExportErgebnis> exportiere() async {
    final daten = await _ladeDaten();
    return _bauenImIsolate(daten);
  }

  /// MUSS statisch bleiben — siehe Navision-Import. Eine Closure in einer
  /// Instanzmethode nähme `this` mit und damit die Datenbankverbindung.
  static Future<StammdatenExportErgebnis> _bauenImIsolate(
    Map<String, Object?> daten,
  ) {
    return Isolate.run(() => _baue(daten));
  }

  // ═════════════════════════════════════════════════════════════════════
  // Daten laden — Hauptisolate, liefert nur einfache Typen
  // ═════════════════════════════════════════════════════════════════════

  Future<Map<String, Object?>> _ladeDaten() async {
    final produkte = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final schritte = await (_db.select(_db.productSteps)
          ..where((s) => s.deletedAt.isNull()))
        .get();
    final parameter = await (_db.select(_db.productStepParameters)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final maschinen = await (_db.select(_db.machines)
          ..where((m) => m.deletedAt.isNull()))
        .get();
    final defs = await (_db.select(_db.machineParameterDefs)
          ..where((d) => d.deletedAt.isNull())
          ..orderBy([(d) => OrderingTerm.asc(d.sortierung)]))
        .get();
    final historie = await (_db.select(_db.productionHistory)
          ..where((h) => h.deletedAt.isNull()))
        .get();

    String abteilungAnzeige(String db) {
      for (final a in Abteilung.values) {
        if (a.dbValue == db) return a.anzeigeName;
      }
      return db;
    }

    final schritteJeProdukt = <String, List<ProductStep>>{};
    for (final s in schritte) {
      schritteJeProdukt.putIfAbsent(s.productId, () => []).add(s);
    }
    final paramJeSchritt = <String, List<ProductStepParameter>>{};
    for (final p in parameter) {
      paramJeSchritt.putIfAbsent(p.stepId, () => []).add(p);
    }
    final histJeProdukt = <String, List<ProductionHistoryData>>{};
    for (final h in historie) {
      histJeProdukt.putIfAbsent(h.productId, () => []).add(h);
    }
    final maschineVonId = {for (final m in maschinen) m.id: m};

    // Nur Artikel mit Prozessdaten oder Historie. Die leeren Hüllen aus dem
    // Navision-Abgleich — über zweitausend — würden die Mappe unbrauchbar
    // machen, ohne etwas zu enthalten.
    final artikel = <Map<String, Object?>>[];
    for (final p in produkte) {
      final ps = (schritteJeProdukt[p.id] ?? [])
        ..sort((a, b) => a.reihenfolge.compareTo(b.reihenfolge));
      final hs = (histJeProdukt[p.id] ?? [])
        ..sort((a, b) => a.datum.compareTo(b.datum));
      if (ps.isEmpty && hs.isEmpty) continue;

      artikel.add({
        'nummer': p.artikelnummer,
        'bezeichnung': p.artikelbezeichnung,
        'produktgruppe': p.produktgruppe,
        'notizen': p.notizen,
        // Merkmale als Klartext — die Mappe soll ohne Schlüsseltabelle
        // lesbar sein, und der Import erkennt beides.
        'merkmale': <String, String?>{
          'Allergene': merkmaleLabel(p.allergene, kAllergene),
          'Qualitätsstufe': merkmalLabel(p.qualitaetsstufe, kQualitaetsstufen),
          'Verarbeitungsstufe':
              merkmaleLabel(p.verarbeitungsstufe, kVerarbeitungsstufen),
          'Verpackungsformen':
              merkmaleLabel(p.verpackungsformen, kVerpackungsformen),
          'Kartongröße': merkmalLabel(p.kartonGroesse, kKartonGroessen),
          'Kartonbedruckung':
              merkmalLabel(p.kartonBedruckung, kKartonBedruckungen),
          'Packungen pro Karton': p.packungenProKarton?.toString(),
          'Füllmenge netto (g)': p.fuellmengeNettoG == null
              ? null
              : (p.fuellmengeNettoG! == p.fuellmengeNettoG!.roundToDouble()
                  ? p.fuellmengeNettoG!.round().toString()
                  : p.fuellmengeNettoG!.toString()),
          'Abgabeart': merkmalLabel(p.abgabeart, kAbgabearten),
        },
        'schritte': [
          for (final s in ps)
            {
              'abteilung': abteilungAnzeige(s.abteilung),
              'prozessschritt': s.prozessschritt,
              'anlage': s.maschineId == null
                  ? s.maschine
                  : (maschineVonId[s.maschineId]?.name ?? s.maschine),
              'personen': s.basisMitarbeiter,
              'mengeKg': s.basisMengeKg,
              'dauerMinuten': s.basisDauerMinuten,
              'werte': <String, String>{
                for (final w
                    in paramJeSchritt[s.id] ?? <ProductStepParameter>[])
                  if (w.wert != null && w.wert!.trim().isNotEmpty)
                    w.parameterName: w.wert!,
              },
            },
        ],
        'historie': [
          for (final h in hs)
            {
              'datum': h.datum.toIso8601String(),
              'kgRoh': h.kgRohware,
              'kgFertig': h.kgFertigware,
              'kgFleisch': h.kgFleischeinwaage,
              'start': h.startzeit,
              'ende': h.endzeit,
              'notizen': h.notizen,
            },
        ],
      });
    }
    artikel.sort(
      (a, b) => (a['nummer']! as String).compareTo(b['nummer']! as String),
    );

    return {
      'artikel': artikel,
      'anlagen': [
        for (final m in maschinen)
          {
            'id': m.id,
            'name': m.name,
            'abteilung': abteilungAnzeige(m.abteilung),
          },
      ],
      'defs': [
        for (final d in defs)
          {
            'maschineId': d.maschineId,
            'name': d.parameterName,
            'einheit': d.einheit ?? '',
          },
      ],
      'abteilungen': [for (final a in Abteilung.values) a.anzeigeName],
      'stand': DateTime.now().toIso8601String(),
    };
  }

  // ═════════════════════════════════════════════════════════════════════
  // Mappe bauen — isolate-tauglich, ohne Datenbank
  // ═════════════════════════════════════════════════════════════════════

  static StammdatenExportErgebnis _baue(Map<String, Object?> d) {
    final warnungen = <String>[];
    final artikel = (d['artikel']! as List).cast<Map<String, Object?>>();
    final anlagen = (d['anlagen']! as List).cast<Map<String, Object?>>();
    final defs = (d['defs']! as List).cast<Map<String, Object?>>();
    final abteilungen = (d['abteilungen']! as List).cast<String>();
    final stand = DateTime.parse(d['stand']! as String);

    // ── Maschinentypen ────────────────────────────────────────────────
    //
    // Die App führt jede Anlage einzeln, die Mappe gruppiert nach Typ, damit
    // Verbufa 1 und 2 nur einmal gepflegt werden müssen. Typ = Name ohne
    // abschließende Nummer.
    final typVon = <String, String>{
      for (final a in anlagen)
        a['name']! as String: typAusName(a['name']! as String),
    };

    // Steckbrief je Typ = Vereinigung der Zeilen aller Geräte dieses Typs,
    // in der Reihenfolge des ersten Auftretens. Plattenzeilen gehören nicht
    // hinein — die verwaltet die Leiste.
    final steckbriefJeTyp = <String, LinkedHashMap<String, String>>{};
    final typVonId = {
      for (final a in anlagen) a['id']! as String: typVon[a['name']]!,
    };
    for (final def in defs) {
      final typ = typVonId[def['maschineId']];
      if (typ == null) continue;
      final name = def['name']! as String;
      if (kPlattenParamMuster.hasMatch(name)) continue;
      steckbriefJeTyp
          .putIfAbsent(typ, LinkedHashMap.new)
          .putIfAbsent(name, () => def['einheit']! as String);
    }

    final mappe = XlsxSchreiber();

    // ── Übersicht ─────────────────────────────────────────────────────
    final ue = mappe.blatt('Übersicht', reiter: _akzent);
    ue.text(1, 1, 'Produktions-Stammdaten', XlsxStil.titel);
    ue.verbinde('A1:E1');
    ue.hoehe(1, 28);
    ue.text(
      2,
      1,
      'Export ${_datumZeit(stand)} · ${artikel.length} Artikel · '
      '${anlagen.length} Anlagen',
      XlsxStil.hinweis,
    );
    ue.text(
      3,
      1,
      'Werte in dieser Datei ändern und sie wieder importieren — '
      'die App übernimmt sie.',
      XlsxStil.hinweis,
    );
    const ueKopf = ['Artikelnummer', 'Bezeichnung', 'Schritte', 'Chargen'];
    for (var i = 0; i < ueKopf.length; i++) {
      ue.text(5, 1 + i, ueKopf[i], XlsxStil.kopf);
    }
    ue.text(5, 5, 'Blatt', XlsxStil.kopf);
    var r = 6;
    for (final a in artikel) {
      final nr = a['nummer']! as String;
      ue.text(r, 1, nr, XlsxStil.wert);
      ue.text(r, 2, a['bezeichnung'] as String?, XlsxStil.wert);
      ue.zahl(r, 3, (a['schritte']! as List).length, XlsxStil.wert);
      ue.zahl(r, 4, (a['historie']! as List).length, XlsxStil.wert);
      ue.text(r, 5, 'öffnen', XlsxStil.link);
      ue.verweis('E$r', "'${_blattName(nr)}'!A1");
      r++;
    }
    ue.breiten({1: 16, 2: 55, 3: 10, 4: 10, 5: 10});
    ue.fixiere('A6');

    // ── Anlagen ───────────────────────────────────────────────────────
    final an = mappe.blatt('Anlagen', reiter: _dunkel);
    an.text(1, 1, 'Anlagen', XlsxStil.titel);
    an.verbinde('A1:D1');
    an.hoehe(1, 28);
    an.text(
      2,
      1,
      'Quelle der Auswahlmenüs. Neue Anlage hier eintragen — beim Import '
      'legt die App sie an.',
      XlsxStil.hinweis,
    );
    const anKopf = ['Anlage', 'Abteilung', 'Maschinentyp', 'Parameter'];
    for (var i = 0; i < anKopf.length; i++) {
      an.text(4, 1 + i, anKopf[i], XlsxStil.kopf);
    }
    final sortiert = [...anlagen]..sort(
        (a, b) => (a['name']! as String).compareTo(b['name']! as String),
      );
    r = 5;
    for (final a in sortiert) {
      final name = a['name']! as String;
      an.text(r, 1, name, XlsxStil.wert);
      an.text(r, 2, a['abteilung'] as String?, XlsxStil.wert);
      an.text(r, 3, typVon[name], XlsxStil.wert);
      an.zahl(r, 4, steckbriefJeTyp[typVon[name]]?.length ?? 0, XlsxStil.wert);
      r++;
    }
    final anlagenLetzte = r - 1;
    an.text(4, 6, 'Abteilungen', XlsxStil.kopf);
    for (var i = 0; i < abteilungen.length; i++) {
      an.text(5 + i, 6, abteilungen[i], XlsxStil.wert);
    }
    final abtLetzte = 4 + abteilungen.length;
    an.breiten({1: 30, 2: 22, 3: 26, 4: 12, 6: 22});
    an.fixiere('A5');

    // ── Steckbriefe ───────────────────────────────────────────────────
    final sb = mappe.blatt('Steckbriefe', reiter: _dunkel);
    sb.text(1, 1, 'Steckbriefe der Maschinentypen', XlsxStil.titel);
    sb.verbinde('A1:C1');
    sb.hoehe(1, 28);
    sb.text(
      2,
      1,
      'Neue Zeile hier ergänzen — sie erscheint beim nächsten Export in '
      'jedem Blatt, das diesen Maschinentyp benutzt.',
      XlsxStil.hinweis,
    );
    const sbKopf = ['Maschinentyp', 'Parameter', 'Einheit'];
    for (var i = 0; i < sbKopf.length; i++) {
      sb.text(4, 1 + i, sbKopf[i], XlsxStil.kopf);
    }
    r = 5;
    for (final typ in steckbriefJeTyp.keys.toList()..sort()) {
      for (final e in steckbriefJeTyp[typ]!.entries) {
        sb.text(r, 1, typ, XlsxStil.wert);
        sb.text(r, 2, e.key, XlsxStil.wert);
        sb.text(r, 3, e.value.isEmpty ? null : e.value, XlsxStil.wert);
        r++;
      }
    }
    sb.breiten({1: 28, 2: 44, 3: 16});
    sb.fixiere('A5');

    // ── Artikelblätter ────────────────────────────────────────────────
    for (final a in artikel) {
      try {
        _artikelBlatt(
          mappe,
          a,
          typVon: typVon,
          steckbriefJeTyp: steckbriefJeTyp,
          anlagenLetzte: anlagenLetzte,
          abtLetzte: abtLetzte,
        );
      } catch (e) {
        warnungen.add(
          'Artikel ${a['nummer']}: Blatt übersprungen (${fehlerText(e)}).',
        );
      }
    }

    return StammdatenExportErgebnis(
      bytes: mappe.packe(),
      dateiname: 'stammdaten_${_datumDatei(stand)}.xlsx',
      artikel: artikel.length,
      anlagen: anlagen.length,
      warnungen: warnungen,
    );
  }

  // ── Feste Zeilenlagen — identisch zum Importer ──────────────────────
  /// Schrittspalten B bis U — so viele Schritte erlaubt die App.
  static const int _spalten = 20;

  /// Zeile 15 hieß früher „Fixe Zeit (min)". Fixe Zeiten gibt es nicht
  /// mehr; die Zeile bleibt frei, damit ältere Mappen dieselbe Lage haben.
  static const List<String> _schrittZeilen = [
    'Abteilung',
    'Prozessschritt',
    'Anlage',
    'Personen',
    'Menge (kg)',
    'Zeit (hh:mm)',
  ];

  static void _artikelBlatt(
    XlsxSchreiber mappe,
    Map<String, Object?> a, {
    required Map<String, String> typVon,
    required Map<String, LinkedHashMap<String, String>> steckbriefJeTyp,
    required int anlagenLetzte,
    required int abtLetzte,
  }) {
    final nr = a['nummer']! as String;
    final gruppe = a['produktgruppe'] as String?;
    final w = mappe.blatt(
      _blattName(nr),
      reiter: gruppe == null ? null : _farbeVon[gruppe],
    );
    final ende = xlsxSpalte(1 + _spalten);

    final titel = produktgruppeLabel(gruppe);
    w.text(2, 1, titel.isEmpty ? 'Artikel' : titel, XlsxStil.titel);
    w.verbinde('A2:${ende}2');
    w.hoehe(2, 26);
    w.text(3, 1, '$nr — ${a['bezeichnung'] ?? ''}', XlsxStil.artikelKopf);
    w.text(
      4,
      1,
      'Von der App erzeugt. Werte hier ändern und die Datei wieder '
      'importieren.',
      XlsxStil.hinweis,
    );

    // ── Prozessschritte ───────────────────────────────────────────────
    w.text(6, 1, 'PROZESSSCHRITTE', XlsxStil.block);
    w.verbinde('A6:${ende}6');
    w.text(
      7,
      1,
      'Eine Spalte je Schritt, von links nach rechts in '
      'Produktionsreihenfolge. Freie Spalten können hier befüllt werden.',
      XlsxStil.hinweis,
    );
    for (var i = 0; i < _spalten; i++) {
      w.text(8, 2 + i, 'Schritt ${i + 1}', XlsxStil.kopf);
    }
    for (var z = 0; z < _schrittZeilen.length; z++) {
      w.text(9 + z, 1, _schrittZeilen[z], XlsxStil.label);
      for (var c = 2; c < 2 + _spalten; c++) {
        w.leer(9 + z, c, XlsxStil.wert);
      }
    }

    final schritte = (a['schritte']! as List).cast<Map<String, Object?>>();
    // Spalte je Anlage merken — eine Anlage kann in mehreren Schritten
    // vorkommen (zwei Verbufas im selben Artikel).
    final spaltenJeAnlage = <String, List<int>>{};
    for (var i = 0; i < schritte.length && i < _spalten; i++) {
      final s = schritte[i];
      final c = 2 + i;
      w.text(9, c, s['abteilung'] as String?, XlsxStil.wert);
      w.text(10, c, s['prozessschritt'] as String?, XlsxStil.wert);
      w.text(11, c, s['anlage'] as String?, XlsxStil.wert);
      final personen = s['personen']! as int;
      if (personen > 0) w.zahl(12, c, personen, XlsxStil.wert);
      final menge = s['mengeKg']! as double;
      if (menge > 0) w.zahl(13, c, menge, XlsxStil.zahl1);
      final dauer = s['dauerMinuten']! as double;
      if (dauer > 0) w.text(14, c, _hhmm(dauer.round()), XlsxStil.wert);

      final anlage = s['anlage'] as String?;
      if (anlage != null && anlage.isNotEmpty) {
        spaltenJeAnlage.putIfAbsent(anlage, () => []).add(c);
      }
    }
    if (schritte.length > _spalten) {
      w.text(
        16,
        1,
        'Achtung: ${schritte.length} Schritte — nur die ersten $_spalten '
        'passen in die Mappe.',
        XlsxStil.hinweis,
      );
    }
    w.auswahl('B9:${ende}9', 'Anlagen!\$F\$5:\$F\$$abtLetzte');
    w.auswahl('B11:${ende}11', 'Anlagen!\$A\$5:\$A\$$anlagenLetzte');

    // ── Anlagenblöcke ─────────────────────────────────────────────────
    var r = 17;
    final sonstigeZeile = <String, int>{};
    for (final eintrag in spaltenJeAnlage.entries) {
      final anlage = eintrag.key;
      final spalten = eintrag.value;
      w.text(r, 1, anlage.toUpperCase(), XlsxStil.block);
      w.verbinde('A$r:$ende$r');
      r++;

      // Werte aller Schritte dieser Anlage, über den Namen ohne Einheit
      // angesprochen — so stehen sie in der Datenbank.
      final werteJeSpalte = <int, Map<String, String>>{};
      for (final c in spalten) {
        final roh = (schritte[c - 2]['werte']! as Map).cast<String, String>();
        werteJeSpalte[c] = {
          for (final e in roh.entries) _schluessel(e.key): e.value,
        };
      }
      void zeile(String name, String einheit, int stil) {
        w.text(r, 1, einheit.isEmpty ? name : '$name ($einheit)', stil);
        for (var c = 2; c < 2 + _spalten; c++) {
          final wert = werteJeSpalte[c]?[_schluessel(name)];
          if (wert != null) {
            w.text(r, c, wert, XlsxStil.wert);
          } else {
            w.leer(r, c, XlsxStil.wert);
          }
        }
        r++;
      }

      // Was hier schon als Zeile steht — damit Schritt 3 es nicht ein
      // zweites Mal als Zusatzzeile anhängt. Verglichen wird über den
      // Schlüssel (klein, ohne Einheit), also auch die Platten darüber und
      // nicht über das Namensmuster: das unterscheidet Groß- und
      // Kleinschreibung und hat die Platten deshalb nie erkannt.
      final bekannt = <String>{};

      // 1. Plattenzeilen — Namen exakt wie in der Leiste der App.
      for (final platte in plattenZeilenFuer(anlage)) {
        zeile(platte, '', XlsxStil.parameter);
        bekannt.add(_schluessel(platte));
      }
      // 2. Steckbrief des Maschinentyps.
      final steck = steckbriefJeTyp[typVon[anlage] ?? anlage] ??
          <String, String>{};
      for (final e in steck.entries) {
        if (e.key == 'Sonstige Informationen') continue;
        zeile(e.key, e.value, XlsxStil.parameter);
        bekannt.add(_schluessel(e.key));
      }
      // 3. Werte, die in keinem Steckbrief stehen — damit nichts verloren
      //    geht. Beim Import landen sie wieder bei derselben Anlage.
      final zusatz = <String>{};
      for (final m in werteJeSpalte.values) {
        for (final k in m.keys) {
          if (bekannt.contains(k)) continue;
          if (k == _schluessel('Sonstige Informationen')) continue;
          if (k == _schluessel(kPlattenSchemaParam)) continue;
          zusatz.add(k);
        }
      }
      for (final k in zusatz) {
        // Ursprüngliche Schreibweise aus den Werten holen.
        final original = [
          for (final c in spalten)
            ...(schritte[c - 2]['werte']! as Map).keys.cast<String>(),
        ].firstWhere((n) => _schluessel(n) == k, orElse: () => k);
        zeile(original, '', XlsxStil.parameter);
      }
      // 4. Freitext — immer zuletzt.
      sonstigeZeile[anlage] = r;
      zeile('Sonstige Informationen', '', XlsxStil.parameter);
      r++;
    }

    // ── Zusätzliche Informationen ─────────────────────────────────────
    w.text(r, 1, 'ZUSÄTZLICHE INFORMATIONEN', XlsxStil.block);
    w.verbinde('A$r:$ende$r');
    r++;
    final hinweise = _hinweiseAus(a['notizen'] as String?);
    // Die gepflegten Merkmale stehen zwischen den festen Zeilen und den
    // freien Hinweisen: Sie kommen aus eigenen Spalten, nicht aus der
    // Notiz, und werden beim Import wieder dorthin zurückgeschrieben.
    final merkmale = (a['merkmale'] as Map<String, String?>?) ?? const {};
    const feste = ['Personal', 'Besonderheit', 'Merkmale', 'Verpackung'];
    final reihe = [
      ...feste,
      ...merkmale.keys,
      for (final k in hinweise.keys)
        if (!feste.contains(k) && !merkmale.containsKey(k)) k,
    ];
    for (final k in reihe) {
      w.text(r, 1, k, XlsxStil.label);
      final wert = merkmale.containsKey(k) ? merkmale[k] : hinweise[k];
      if (wert != null) {
        w.text(r, 2, wert, XlsxStil.umbruch);
      } else {
        w.leer(r, 2, XlsxStil.umbruch);
      }
      w.verbinde('B$r:$ende$r');
      w.hoehe(r, 24);
      r++;
    }
    if (sonstigeZeile.isNotEmpty) {
      w.text(r, 1, 'Aus den Anlagen gesammelt', XlsxStil.hinweis);
      r++;
      for (final e in sonstigeZeile.entries) {
        final z = e.value;
        // Ohne TEXTJOIN — das kennt Excel erst ab 2019. TRIM entfernt
        // auch doppelte Leerzeichen im Inneren.
        final kette = [
          for (var c = 2; c < 2 + _spalten; c++) '${xlsxSpalte(c)}$z',
        ].join(' & " " & ');
        w.text(r, 1, e.key, XlsxStil.parameter);
        w.formel(r, 2, 'TRIM($kette)', XlsxStil.berechnet);
        w.verbinde('B$r:$ende$r');
        r++;
      }
    }
    r += 2;

    // ── Historie ──────────────────────────────────────────────────────
    w.text(r, 1, 'HISTORISCHE DATEN', XlsxStil.block);
    w.verbinde('A$r:K$r');
    r++;
    w.text(
      r,
      1,
      'Nur Datum, Gewichte und Zeiten eintragen — Verlust, Dauer und kg/h '
      'rechnet die Tabelle.',
      XlsxStil.hinweis,
    );
    r++;
    const histKopf = [
      'Datum',
      'Kg Rohware',
      'Kg Fertigware',
      'Verlust %',
      'Startzeit',
      'Endzeit',
      'Produktionszeit',
      'kg/h roh',
      'kg/h gegart',
      'Notizen',
      // Hinten angehängt: Ältere Mappen enden mit „Notizen" und lassen
      // sich so weiter einlesen.
      'Kg Fleischeinwaage',
    ];
    for (var i = 0; i < histKopf.length; i++) {
      w.text(r, 1 + i, histKopf[i], XlsxStil.kopf);
    }
    final von = r + 1;
    r++;

    void histZeile(Map<String, Object?>? h) {
      if (h != null) {
        final tag = _excelTag(DateTime.parse(h['datum']! as String));
        w.zahl(r, 1, tag, XlsxStil.datum);
        w.zahlOderLeer(r, 2, h['kgRoh'] as double?, XlsxStil.zahl1);
        w.zahlOderLeer(r, 3, h['kgFertig'] as double?, XlsxStil.zahl1);
        w.zahlOderLeer(r, 5, _tagesbruch(h['start'] as String?), XlsxStil.zeit);
        w.zahlOderLeer(r, 6, _tagesbruch(h['ende'] as String?), XlsxStil.zeit);
        w.text(r, 10, h['notizen'] as String?, XlsxStil.wert);
        w.zahlOderLeer(r, 11, h['kgFleisch'] as double?, XlsxStil.zahl1);
      } else {
        w.leer(r, 1, XlsxStil.datum);
        w.leer(r, 2, XlsxStil.zahl1);
        w.leer(r, 3, XlsxStil.zahl1);
        w.leer(r, 5, XlsxStil.zeit);
        w.leer(r, 6, XlsxStil.zeit);
        w.leer(r, 10, XlsxStil.wert);
        w.leer(r, 11, XlsxStil.zahl1);
      }
      w.formel(r, 4, 'IF(OR(B$r="",C$r=""),"",1-C$r/B$r)', XlsxStil.prozent);
      w.formel(r, 7, 'IF(OR(E$r="",F$r=""),"",F$r-E$r)', XlsxStil.zeitBerechnet);
      w.formel(
        r,
        8,
        'IF(OR(B$r="",G$r=""),"",B$r/(G$r*24))',
        XlsxStil.ganzBerechnet,
      );
      w.formel(
        r,
        9,
        'IF(OR(C$r="",G$r=""),"",C$r/(G$r*24))',
        XlsxStil.ganzBerechnet,
      );
      r++;
    }

    for (final h in (a['historie']! as List).cast<Map<String, Object?>>()) {
      histZeile(h);
    }
    for (var i = 0; i < 25; i++) {
      histZeile(null);
    }
    final bis = r - 1;

    // Durchschnitt über alle Chargen — gewichtet: Summe kg / Summe Stunden.
    r++;
    w.text(r, 1, 'Ø über alle Chargen', XlsxStil.summe);
    for (var c = 2; c <= 7; c++) {
      w.leer(r, c, XlsxStil.summe);
    }
    w.formel(
      r,
      8,
      'IF(SUM(G$von:G$bis)=0,"",SUM(B$von:B$bis)/(SUM(G$von:G$bis)*24))',
      XlsxStil.summe,
    );
    w.formel(
      r,
      9,
      'IF(SUM(G$von:G$bis)=0,"",SUM(C$von:C$bis)/(SUM(G$von:G$bis)*24))',
      XlsxStil.summe,
    );
    w.leer(r, 10, XlsxStil.summe);
    w.leer(r, 11, XlsxStil.summe);

    w.breiten({1: 38, for (var i = 0; i < _spalten; i++) 2 + i: 16});
    w.fixiere('B9');
  }

  // ═════════════════════════════════════════════════════════════════════
  // Helfer
  // ═════════════════════════════════════════════════════════════════════

  /// Maschinentyp aus dem Anlagennamen: abschließende Nummer weg.
  /// „Verbufa 2" → „Verbufa", „Kochkammer 1-4" bleibt, „Wolf" bleibt.
  static String typAusName(String name) =>
      name.replaceFirst(RegExp(r'\s+\d+$'), '').trim();

  /// Vergleichsschlüssel: ohne Einheit in Klammern, klein geschrieben.
  static String _schluessel(String n) =>
      n.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim().toLowerCase();

  /// Notiz „Personal: 3 | Besonderheit: …" → geordnete Einträge.
  static Map<String, String> _hinweiseAus(String? notiz) {
    // Map-Literale behalten die Einfügereihenfolge — die Zeilen erscheinen
    // in der Reihenfolge, in der sie in der Notiz stehen.
    final aus = <String, String>{};
    if (notiz == null || notiz.trim().isEmpty) return aus;
    for (final teil in notiz.split(' | ')) {
      final i = teil.indexOf(':');
      if (i <= 0) {
        aus['Hinweis'] = teil.trim();
      } else {
        aus[teil.substring(0, i).trim()] = teil.substring(i + 1).trim();
      }
    }
    return aus;
  }

  static String _blattName(String nr) {
    final bereinigt = nr.replaceAll(RegExp(r'[\[\]:*?/\\]'), '_');
    return bereinigt.length > 31 ? bereinigt.substring(0, 31) : bereinigt;
  }

  static String _hhmm(int minuten) =>
      '${(minuten ~/ 60).toString().padLeft(2, '0')}:'
      '${(minuten % 60).toString().padLeft(2, '0')}';

  static double? _tagesbruch(String? hhmm) {
    if (hhmm == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm.trim());
    if (m == null) return null;
    return (int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) / 1440;
  }

  static int _excelTag(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day)
          .difference(DateTime.utc(1899, 12, 30))
          .inDays;

  static String _datumZeit(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${_hhmm(d.hour * 60 + d.minute)}';

  static String _datumDatei(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}_'
      '${d.hour.toString().padLeft(2, '0')}'
      '${d.minute.toString().padLeft(2, '0')}';

  static const String _akzent = 'FF1F6F6F';
  static const String _dunkel = 'FF3F4A54';

  static const Map<String, String> _farbeVon = {
    'bruehwurst': 'FFD32F2F',
    'rohwurst': 'FF7B1FA2',
    'kochpoekelware': 'FFC2185B',
    'rohpoekelware': 'FFE64A19',
    'aufschnitt': 'FF1976D2',
    'bratstrasse_natur': 'FF5D4037',
    'bratstrasse_paniert': 'FFF57C00',
    'hackprodukt_gegart': 'FF388E3C',
    'hackprodukt_roh': 'FF0097A7',
    'braten': 'FF455A64',
    'sous_vide': 'FF303F9F',
    'angebratene_bruehwurst': 'FFFFA000',
  };
}
