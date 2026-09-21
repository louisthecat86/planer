import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';

import '../constants/abteilungen.dart';
import '../constants/parameter_namen.dart';
import '../constants/product_groups.dart';
import '../database/database.dart';

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
              'fixZeitMinuten': s.fixZeitMinuten,
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

    final mappe = _Mappe();

    // ── Übersicht ─────────────────────────────────────────────────────
    final ue = mappe.blatt('Übersicht', reiter: _akzent);
    ue.text(1, 1, 'Produktions-Stammdaten', _S.titel);
    ue.verbinde('A1:E1');
    ue.hoehe(1, 28);
    ue.text(
      2,
      1,
      'Export ${_datumZeit(stand)} · ${artikel.length} Artikel · '
      '${anlagen.length} Anlagen',
      _S.hinweis,
    );
    ue.text(
      3,
      1,
      'Werte in dieser Datei ändern und sie wieder importieren — '
      'die App übernimmt sie.',
      _S.hinweis,
    );
    const ueKopf = ['Artikelnummer', 'Bezeichnung', 'Schritte', 'Chargen'];
    for (var i = 0; i < ueKopf.length; i++) {
      ue.text(5, 1 + i, ueKopf[i], _S.kopf);
    }
    ue.text(5, 5, 'Blatt', _S.kopf);
    var r = 6;
    for (final a in artikel) {
      final nr = a['nummer']! as String;
      ue.text(r, 1, nr, _S.wert);
      ue.text(r, 2, a['bezeichnung'] as String?, _S.wert);
      ue.zahl(r, 3, (a['schritte']! as List).length, _S.wert);
      ue.zahl(r, 4, (a['historie']! as List).length, _S.wert);
      ue.text(r, 5, 'öffnen', _S.link);
      ue.verweis('E$r', "'${_blattName(nr)}'!A1");
      r++;
    }
    ue.breiten({1: 16, 2: 55, 3: 10, 4: 10, 5: 10});
    ue.fixiere('A6');

    // ── Anlagen ───────────────────────────────────────────────────────
    final an = mappe.blatt('Anlagen', reiter: _dunkel);
    an.text(1, 1, 'Anlagen', _S.titel);
    an.verbinde('A1:D1');
    an.hoehe(1, 28);
    an.text(
      2,
      1,
      'Quelle der Auswahlmenüs. Neue Anlage hier eintragen — beim Import '
      'legt die App sie an.',
      _S.hinweis,
    );
    const anKopf = ['Anlage', 'Abteilung', 'Maschinentyp', 'Parameter'];
    for (var i = 0; i < anKopf.length; i++) {
      an.text(4, 1 + i, anKopf[i], _S.kopf);
    }
    final sortiert = [...anlagen]..sort(
        (a, b) => (a['name']! as String).compareTo(b['name']! as String),
      );
    r = 5;
    for (final a in sortiert) {
      final name = a['name']! as String;
      an.text(r, 1, name, _S.wert);
      an.text(r, 2, a['abteilung'] as String?, _S.wert);
      an.text(r, 3, typVon[name], _S.wert);
      an.zahl(r, 4, steckbriefJeTyp[typVon[name]]?.length ?? 0, _S.wert);
      r++;
    }
    final anlagenLetzte = r - 1;
    an.text(4, 6, 'Abteilungen', _S.kopf);
    for (var i = 0; i < abteilungen.length; i++) {
      an.text(5 + i, 6, abteilungen[i], _S.wert);
    }
    final abtLetzte = 4 + abteilungen.length;
    an.breiten({1: 30, 2: 22, 3: 26, 4: 12, 6: 22});
    an.fixiere('A5');

    // ── Steckbriefe ───────────────────────────────────────────────────
    final sb = mappe.blatt('Steckbriefe', reiter: _dunkel);
    sb.text(1, 1, 'Steckbriefe der Maschinentypen', _S.titel);
    sb.verbinde('A1:C1');
    sb.hoehe(1, 28);
    sb.text(
      2,
      1,
      'Neue Zeile hier ergänzen — sie erscheint beim nächsten Export in '
      'jedem Blatt, das diesen Maschinentyp benutzt.',
      _S.hinweis,
    );
    const sbKopf = ['Maschinentyp', 'Parameter', 'Einheit'];
    for (var i = 0; i < sbKopf.length; i++) {
      sb.text(4, 1 + i, sbKopf[i], _S.kopf);
    }
    r = 5;
    for (final typ in steckbriefJeTyp.keys.toList()..sort()) {
      for (final e in steckbriefJeTyp[typ]!.entries) {
        sb.text(r, 1, typ, _S.wert);
        sb.text(r, 2, e.key, _S.wert);
        sb.text(r, 3, e.value.isEmpty ? null : e.value, _S.wert);
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
        warnungen.add('Artikel ${a['nummer']}: Blatt übersprungen ($e).');
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
  static const int _spalten = 10;
  static const List<String> _schrittZeilen = [
    'Abteilung',
    'Prozessschritt',
    'Anlage',
    'Personen',
    'Menge (kg)',
    'Zeit (hh:mm)',
    'Fixe Zeit (min)',
  ];

  static void _artikelBlatt(
    _Mappe mappe,
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
    final ende = _spalte(1 + _spalten);

    final titel = produktgruppeLabel(gruppe);
    w.text(2, 1, titel.isEmpty ? 'Artikel' : titel, _S.titel);
    w.verbinde('A2:${ende}2');
    w.hoehe(2, 26);
    w.text(3, 1, '$nr — ${a['bezeichnung'] ?? ''}', _S.artikelKopf);
    w.text(
      4,
      1,
      'Von der App erzeugt. Werte hier ändern und die Datei wieder '
      'importieren.',
      _S.hinweis,
    );

    // ── Prozessschritte ───────────────────────────────────────────────
    w.text(6, 1, 'PROZESSSCHRITTE', _S.block);
    w.verbinde('A6:${ende}6');
    w.text(
      7,
      1,
      'Eine Spalte je Schritt, von links nach rechts in '
      'Produktionsreihenfolge. Freie Spalten können hier befüllt werden.',
      _S.hinweis,
    );
    for (var i = 0; i < _spalten; i++) {
      w.text(8, 2 + i, 'Schritt ${i + 1}', _S.kopf);
    }
    for (var z = 0; z < _schrittZeilen.length; z++) {
      w.text(9 + z, 1, _schrittZeilen[z], _S.label);
      for (var c = 2; c < 2 + _spalten; c++) {
        w.leer(9 + z, c, _S.wert);
      }
    }

    final schritte = (a['schritte']! as List).cast<Map<String, Object?>>();
    // Spalte je Anlage merken — eine Anlage kann in mehreren Schritten
    // vorkommen (zwei Verbufas im selben Artikel).
    final spaltenJeAnlage = <String, List<int>>{};
    for (var i = 0; i < schritte.length && i < _spalten; i++) {
      final s = schritte[i];
      final c = 2 + i;
      w.text(9, c, s['abteilung'] as String?, _S.wert);
      w.text(10, c, s['prozessschritt'] as String?, _S.wert);
      w.text(11, c, s['anlage'] as String?, _S.wert);
      final personen = s['personen']! as int;
      if (personen > 0) w.zahl(12, c, personen, _S.wert);
      final menge = s['mengeKg']! as double;
      if (menge > 0) w.zahl(13, c, menge, _S.zahl1);
      final dauer = s['dauerMinuten']! as double;
      if (dauer > 0) w.text(14, c, _hhmm(dauer.round()), _S.wert);
      final fix = s['fixZeitMinuten'] as double?;
      if (fix != null && fix > 0) w.zahl(15, c, fix, _S.wert);

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
        _S.hinweis,
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
      w.text(r, 1, anlage.toUpperCase(), _S.block);
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
            w.text(r, c, wert, _S.wert);
          } else {
            w.leer(r, c, _S.wert);
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
        zeile(platte, '', _S.parameter);
        bekannt.add(_schluessel(platte));
      }
      // 2. Steckbrief des Maschinentyps.
      final steck = steckbriefJeTyp[typVon[anlage] ?? anlage] ??
          <String, String>{};
      for (final e in steck.entries) {
        if (e.key == 'Sonstige Informationen') continue;
        zeile(e.key, e.value, _S.parameter);
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
        zeile(original, '', _S.parameter);
      }
      // 4. Freitext — immer zuletzt.
      sonstigeZeile[anlage] = r;
      zeile('Sonstige Informationen', '', _S.parameter);
      r++;
    }

    // ── Zusätzliche Informationen ─────────────────────────────────────
    w.text(r, 1, 'ZUSÄTZLICHE INFORMATIONEN', _S.block);
    w.verbinde('A$r:$ende$r');
    r++;
    final hinweise = _hinweiseAus(a['notizen'] as String?);
    const feste = ['Personal', 'Besonderheit', 'Merkmale', 'Verpackung'];
    final reihe = [
      ...feste,
      for (final k in hinweise.keys)
        if (!feste.contains(k)) k,
    ];
    for (final k in reihe) {
      w.text(r, 1, k, _S.label);
      final wert = hinweise[k];
      if (wert != null) {
        w.text(r, 2, wert, _S.umbruch);
      } else {
        w.leer(r, 2, _S.umbruch);
      }
      w.verbinde('B$r:$ende$r');
      w.hoehe(r, 24);
      r++;
    }
    if (sonstigeZeile.isNotEmpty) {
      w.text(r, 1, 'Aus den Anlagen gesammelt', _S.hinweis);
      r++;
      for (final e in sonstigeZeile.entries) {
        final z = e.value;
        // Ohne TEXTJOIN — das kennt Excel erst ab 2019. TRIM entfernt
        // auch doppelte Leerzeichen im Inneren.
        final kette = [
          for (var c = 2; c < 2 + _spalten; c++) '${_spalte(c)}$z',
        ].join(' & " " & ');
        w.text(r, 1, e.key, _S.parameter);
        w.formel(r, 2, 'TRIM($kette)', _S.berechnet);
        w.verbinde('B$r:$ende$r');
        r++;
      }
    }
    r += 2;

    // ── Historie ──────────────────────────────────────────────────────
    w.text(r, 1, 'HISTORISCHE DATEN', _S.block);
    w.verbinde('A$r:J$r');
    r++;
    w.text(
      r,
      1,
      'Nur Datum, Gewichte und Zeiten eintragen — Verlust, Dauer und kg/h '
      'rechnet die Tabelle.',
      _S.hinweis,
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
    ];
    for (var i = 0; i < histKopf.length; i++) {
      w.text(r, 1 + i, histKopf[i], _S.kopf);
    }
    final von = r + 1;
    r++;

    void histZeile(Map<String, Object?>? h) {
      if (h != null) {
        final tag = _excelTag(DateTime.parse(h['datum']! as String));
        w.zahl(r, 1, tag, _S.datum);
        w.zahlOderLeer(r, 2, h['kgRoh'] as double?, _S.zahl1);
        w.zahlOderLeer(r, 3, h['kgFertig'] as double?, _S.zahl1);
        w.zahlOderLeer(r, 5, _tagesbruch(h['start'] as String?), _S.zeit);
        w.zahlOderLeer(r, 6, _tagesbruch(h['ende'] as String?), _S.zeit);
        w.text(r, 10, h['notizen'] as String?, _S.wert);
      } else {
        w.leer(r, 1, _S.datum);
        w.leer(r, 2, _S.zahl1);
        w.leer(r, 3, _S.zahl1);
        w.leer(r, 5, _S.zeit);
        w.leer(r, 6, _S.zeit);
        w.leer(r, 10, _S.wert);
      }
      w.formel(r, 4, 'IF(OR(B$r="",C$r=""),"",1-C$r/B$r)', _S.prozent);
      w.formel(r, 7, 'IF(OR(E$r="",F$r=""),"",F$r-E$r)', _S.zeitBerechnet);
      w.formel(
        r,
        8,
        'IF(OR(B$r="",G$r=""),"",B$r/(G$r*24))',
        _S.ganzBerechnet,
      );
      w.formel(
        r,
        9,
        'IF(OR(C$r="",G$r=""),"",C$r/(G$r*24))',
        _S.ganzBerechnet,
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
    w.text(r, 1, 'Ø über alle Chargen', _S.summe);
    for (var c = 2; c <= 7; c++) {
      w.leer(r, c, _S.summe);
    }
    w.formel(
      r,
      8,
      'IF(SUM(G$von:G$bis)=0,"",SUM(B$von:B$bis)/(SUM(G$von:G$bis)*24))',
      _S.summe,
    );
    w.formel(
      r,
      9,
      'IF(SUM(G$von:G$bis)=0,"",SUM(C$von:C$bis)/(SUM(G$von:G$bis)*24))',
      _S.summe,
    );
    w.leer(r, 10, _S.summe);

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

/// 1-basierte Spaltennummer → Buchstaben (1 → A, 27 → AA).
String _spalte(int n) {
  var c = n;
  final b = StringBuffer();
  while (c > 0) {
    final rest = (c - 1) % 26;
    b.write(String.fromCharCode(65 + rest));
    c = (c - 1) ~/ 26;
  }
  return b.toString().split('').reversed.join();
}

/// XML-Text entschärfen. Steuerzeichen fliegen raus: In XML 1.0 sind sie
/// grundsätzlich unzulässig, und Navision-Texte enthalten sie gelegentlich.
String _esc(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// ═══════════════════════════════════════════════════════════════════════════
// Zellformate — feste Nummern, passend zur styles.xml unten
// ═══════════════════════════════════════════════════════════════════════════

abstract final class _S {
  static const int titel = 1;
  static const int block = 2;
  static const int label = 3;
  static const int parameter = 4;
  static const int wert = 5;
  static const int berechnet = 6;
  static const int hinweis = 7;
  static const int kopf = 8;
  static const int datum = 9;
  static const int zeit = 10;
  static const int prozent = 11;
  static const int zeitBerechnet = 12;
  static const int zahl1 = 13;
  static const int ganzBerechnet = 14;
  static const int summe = 15;
  static const int link = 16;
  static const int artikelKopf = 17;
  static const int umbruch = 18;
}

const String _stylesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/'
    'spreadsheetml/2006/main">'
    '<numFmts count="4">'
    '<numFmt numFmtId="164" formatCode="DD.MM.YYYY"/>'
    '<numFmt numFmtId="165" formatCode="hh:mm"/>'
    '<numFmt numFmtId="166" formatCode="0.0"/>'
    '<numFmt numFmtId="167" formatCode="0.0%"/>'
    '</numFmts>'
    '<fonts count="7">'
    '<font><sz val="10"/><name val="Arial"/></font>'
    '<font><b/><sz val="14"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>'
    '<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>'
    '<font><b/><sz val="10"/><name val="Arial"/></font>'
    '<font><i/><sz val="9"/><color rgb="FF8A9099"/><name val="Arial"/></font>'
    '<font><u/><sz val="10"/><color rgb="FF1976D2"/><name val="Arial"/></font>'
    '<font><b/><sz val="12"/><name val="Arial"/></font>'
    '</fonts>'
    '<fills count="8">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF1F6F6F"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF3F4A54"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFFF7E0"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFEDEFF2"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF7F8FA"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFFFFFF"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="2"><border/>'
    '<border><left style="thin"><color rgb="FFC8CDD3"/></left>'
    '<right style="thin"><color rgb="FFC8CDD3"/></right>'
    '<top style="thin"><color rgb="FFC8CDD3"/></top>'
    '<bottom style="thin"><color rgb="FFC8CDD3"/></bottom>'
    '<diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
    'borderId="0"/></cellStyleXfs>'
    '<cellXfs count="19">'
    // 0 Standard
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    // 1 Titel
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" '
    'applyFont="1" applyFill="1" applyAlignment="1">'
    '<alignment vertical="center"/></xf>'
    // 2 Blockkopf
    '<xf numFmtId="0" fontId="2" fillId="3" borderId="0" xfId="0" '
    'applyFont="1" applyFill="1" applyAlignment="1">'
    '<alignment vertical="center"/></xf>'
    // 3 Beschriftung gelb
    '<xf numFmtId="0" fontId="3" fillId="4" borderId="1" xfId="0" '
    'applyFont="1" applyFill="1" applyBorder="1"/>'
    // 4 Parameterzeile grau
    '<xf numFmtId="0" fontId="0" fillId="5" borderId="1" xfId="0" '
    'applyFill="1" applyBorder="1"/>'
    // 5 Wert
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" '
    'applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>'
    // 6 Berechnet
    '<xf numFmtId="0" fontId="0" fillId="6" borderId="1" xfId="0" '
    'applyFill="1" applyBorder="1"/>'
    // 7 Hinweis
    '<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    // 8 Tabellenkopf
    '<xf numFmtId="0" fontId="3" fillId="5" borderId="1" xfId="0" '
    'applyFont="1" applyFill="1" applyBorder="1"/>'
    // 9 Datum
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyBorder="1"/>'
    // 10 Uhrzeit (Eingabe)
    '<xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyBorder="1"/>'
    // 11 Prozent (berechnet)
    '<xf numFmtId="167" fontId="0" fillId="6" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyFill="1" applyBorder="1"/>'
    // 12 Uhrzeit (berechnet)
    '<xf numFmtId="165" fontId="0" fillId="6" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyFill="1" applyBorder="1"/>'
    // 13 Zahl mit einer Nachkommastelle
    '<xf numFmtId="166" fontId="0" fillId="0" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyBorder="1"/>'
    // 14 Ganzzahl (berechnet)
    '<xf numFmtId="1" fontId="0" fillId="6" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyFill="1" applyBorder="1"/>'
    // 15 Summenzeile
    '<xf numFmtId="1" fontId="3" fillId="5" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
    // 16 Verweis
    '<xf numFmtId="0" fontId="5" fillId="0" borderId="1" xfId="0" '
    'applyFont="1" applyBorder="1"/>'
    // 17 Artikelkopf
    '<xf numFmtId="0" fontId="6" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    // 18 Freitext mit Umbruch
    '<xf numFmtId="0" fontId="0" fillId="7" borderId="1" xfId="0" '
    'applyFill="1" applyBorder="1" applyAlignment="1">'
    '<alignment wrapText="1" vertical="center"/></xf>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Standard" xfId="0" '
    'builtinId="0"/></cellStyles>'
    '</styleSheet>';

// ═══════════════════════════════════════════════════════════════════════════
// Minimaler xlsx-Baukasten
// ═══════════════════════════════════════════════════════════════════════════

class _Mappe {
  final List<_Blatt> _blaetter = [];
  final Map<String, int> _textIndex = {};
  final List<String> _texte = [];

  _Blatt blatt(String name, {String? reiter}) {
    final b = _Blatt(this, name, reiter);
    _blaetter.add(b);
    return b;
  }

  int textNr(String s) =>
      _textIndex.putIfAbsent(s, () => (_texte..add(s)).length - 1);

  Uint8List packe() {
    final archiv = Archive();
    void datei(String pfad, String inhalt) {
      final bytes = utf8.encode(inhalt);
      archiv.addFile(ArchiveFile(pfad, bytes.length, bytes));
    }

    const kopf = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    final blattXml = [for (final b in _blaetter) b.xml()];

    datei(
      '[Content_Types].xml',
      '$kopf<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
          'content-types">'
          '<Default Extension="rels" ContentType="application/'
          'vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/'
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '${[
        for (var i = 0; i < _blaetter.length; i++)
          '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
              'ContentType="application/vnd.openxmlformats-officedocument.'
              'spreadsheetml.worksheet+xml"/>',
      ].join()}'
          '<Override PartName="/xl/styles.xml" ContentType="application/'
          'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '<Override PartName="/xl/sharedStrings.xml" ContentType='
          '"application/vnd.openxmlformats-officedocument.spreadsheetml.'
          'sharedStrings+xml"/>'
          '</Types>',
    );
    datei(
      '_rels/.rels',
      '$kopf<Relationships xmlns="http://schemas.openxmlformats.org/package/'
          '2006/relationships"><Relationship Id="rId1" Type="http://'
          'schemas.openxmlformats.org/officeDocument/2006/relationships/'
          'officeDocument" Target="xl/workbook.xml"/></Relationships>',
    );
    datei(
      'xl/workbook.xml',
      '$kopf<workbook xmlns="http://schemas.openxmlformats.org/'
          'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.'
          'org/officeDocument/2006/relationships">'
          // Die Blattansichten verweisen mit workbookViewId="0" hierauf.
          '<bookViews><workbookView/></bookViews><sheets>'
          '${[
        for (var i = 0; i < _blaetter.length; i++)
          '<sheet name="${_esc(_blaetter[i].name)}" sheetId="${i + 1}" '
              'r:id="rId${i + 1}"/>',
      ].join()}'
          '</sheets></workbook>',
    );
    // Beziehungsziele RELATIV — die Lesebibliothek setzt „xl/" davor.
    final n = _blaetter.length;
    datei(
      'xl/_rels/workbook.xml.rels',
      '$kopf<Relationships xmlns="http://schemas.openxmlformats.org/package/'
          '2006/relationships">'
          '${[
        for (var i = 0; i < n; i++)
          '<Relationship Id="rId${i + 1}" Type="http://schemas.'
              'openxmlformats.org/officeDocument/2006/relationships/'
              'worksheet" Target="worksheets/sheet${i + 1}.xml"/>',
      ].join()}'
          '<Relationship Id="rId${n + 1}" Type="http://schemas.'
          'openxmlformats.org/officeDocument/2006/relationships/styles" '
          'Target="styles.xml"/>'
          '<Relationship Id="rId${n + 2}" Type="http://schemas.'
          'openxmlformats.org/officeDocument/2006/relationships/'
          'sharedStrings" Target="sharedStrings.xml"/>'
          '</Relationships>',
    );
    for (var i = 0; i < blattXml.length; i++) {
      datei('xl/worksheets/sheet${i + 1}.xml', blattXml[i]);
    }
    datei('xl/styles.xml', _stylesXml);
    datei(
      'xl/sharedStrings.xml',
      '$kopf<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
          '2006/main" count="${_texte.length}" '
          'uniqueCount="${_texte.length}">'
          '${[
        for (final t in _texte)
          '<si><t xml:space="preserve">${_esc(t)}</t></si>',
      ].join()}'
          '</sst>',
    );

    final gepackt = ZipEncoder().encode(archiv);
    if (gepackt == null) {
      throw StateError('Die Mappe konnte nicht gepackt werden.');
    }
    return Uint8List.fromList(gepackt);
  }
}

class _Blatt {
  _Blatt(this._mappe, this.name, this._reiter);

  final _Mappe _mappe;
  final String name;
  final String? _reiter;

  /// Zeile → Spalte → Zell-XML. Sortiert, weil Excel Zeilen und Zellen in
  /// aufsteigender Reihenfolge verlangt.
  final SplayTreeMap<int, SplayTreeMap<int, String>> _zellen = SplayTreeMap();
  final Map<int, double> _hoehen = {};
  final Map<int, double> _breiten = {};
  final List<String> _verbunden = [];
  final List<String> _auswahl = [];
  final List<String> _verweise = [];
  String? _fixiert;

  void _setze(int r, int c, String xml) =>
      _zellen.putIfAbsent(r, SplayTreeMap.new)[c] = xml;

  String _ref(int r, int c) => '${_spalte(c)}$r';

  void text(int r, int c, String? wert, int stil) {
    if (wert == null || wert.isEmpty) return leer(r, c, stil);
    _setze(
      r,
      c,
      '<c r="${_ref(r, c)}" s="$stil" t="s"><v>${_mappe.textNr(wert)}</v></c>',
    );
  }

  void zahl(int r, int c, num wert, int stil) =>
      _setze(r, c, '<c r="${_ref(r, c)}" s="$stil"><v>$wert</v></c>');

  void formel(int r, int c, String f, int stil) =>
      _setze(r, c, '<c r="${_ref(r, c)}" s="$stil"><f>${_esc(f)}</f></c>');

  void leer(int r, int c, int stil) =>
      _setze(r, c, '<c r="${_ref(r, c)}" s="$stil"/>');

  void zahlOderLeer(int r, int c, num? wert, int stil) {
    if (wert == null) {
      leer(r, c, stil);
    } else {
      zahl(r, c, wert, stil);
    }
  }

  void verbinde(String bereich) => _verbunden.add(bereich);
  void hoehe(int r, double h) => _hoehen[r] = h;
  void breiten(Map<int, double> b) => _breiten.addAll(b);
  void fixiere(String zelle) => _fixiert = zelle;

  void auswahl(String bereich, String quelle) => _auswahl.add(
        '<dataValidation type="list" allowBlank="1" showInputMessage="1" '
        'showErrorMessage="0" sqref="$bereich">'
        '<formula1>${_esc(quelle)}</formula1></dataValidation>',
      );

  void verweis(String zelle, String ziel) => _verweise.add(
        '<hyperlink ref="$zelle" location="${_esc(ziel)}" display="öffnen"/>',
      );

  String xml() {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
          'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.'
          'org/officeDocument/2006/relationships">');
    // Reihenfolge der Elemente ist im OOXML-Schema festgelegt.
    if (_reiter != null) {
      b.write('<sheetPr><tabColor rgb="$_reiter"/></sheetPr>');
    }
    b.write('<sheetViews><sheetView workbookViewId="0">');
    final f = _fixiert;
    if (f != null) {
      final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(f)!;
      final spalteNr = m.group(1)!.codeUnits.fold<int>(
            0,
            (s, u) => s * 26 + (u - 64),
          );
      final xSplit = spalteNr - 1;
      final ySplit = int.parse(m.group(2)!) - 1;
      final pane = xSplit > 0 && ySplit > 0
          ? 'bottomRight'
          : (ySplit > 0 ? 'bottomLeft' : 'topRight');
      b.write('<pane${xSplit > 0 ? ' xSplit="$xSplit"' : ''}'
          '${ySplit > 0 ? ' ySplit="$ySplit"' : ''} topLeftCell="$f" '
          'activePane="$pane" state="frozen"/>');
    }
    b.write('</sheetView></sheetViews>');
    b.write('<sheetFormatPr defaultRowHeight="15"/>');
    if (_breiten.isNotEmpty) {
      b.write('<cols>');
      for (final e in (SplayTreeMap<int, double>.from(_breiten)).entries) {
        b.write('<col min="${e.key}" max="${e.key}" width="${e.value}" '
            'customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (final z in _zellen.entries) {
      final h = _hoehen[z.key];
      b.write('<row r="${z.key}"'
          '${h == null ? '' : ' ht="$h" customHeight="1"'}>');
      z.value.values.forEach(b.write);
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (_verbunden.isNotEmpty) {
      b.write('<mergeCells count="${_verbunden.length}">');
      for (final v in _verbunden) {
        b.write('<mergeCell ref="$v"/>');
      }
      b.write('</mergeCells>');
    }
    if (_auswahl.isNotEmpty) {
      b
        ..write('<dataValidations count="${_auswahl.length}">')
        ..writeAll(_auswahl)
        ..write('</dataValidations>');
    }
    if (_verweise.isNotEmpty) {
      b
        ..write('<hyperlinks>')
        ..writeAll(_verweise)
        ..write('</hyperlinks>');
    }
    b.write('<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/>');
    b.write('</worksheet>');
    return b.toString();
  }
}
