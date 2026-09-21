import 'dart:async';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../constants/abteilungen.dart';
import '../constants/parameter_namen.dart';
import '../database/database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Ergebnis
// ═══════════════════════════════════════════════════════════════════════════

/// Was beim Import herausgekommen ist.
class StammdatenImportErgebnis {
  const StammdatenImportErgebnis({
    this.anlagen = 0,
    this.steckbriefZeilen = 0,
    this.artikelNeu = 0,
    this.artikelAktualisiert = 0,
    this.schritte = 0,
    this.parameter = 0,
    this.chargen = 0,
    this.warnungen = const [],
    this.fehler = const [],
  });

  final int anlagen;
  final int steckbriefZeilen;
  final int artikelNeu;
  final int artikelAktualisiert;
  final int schritte;
  final int parameter;
  final int chargen;
  final List<String> warnungen;
  final List<String> fehler;

  bool get hatFehler => fehler.isNotEmpty;
}

/// Abschnitt, in dem der Import gerade steckt — für den Ladebalken.
enum StammdatenPhase { datei, auswerten, speichern }

/// Zwischenstand eines laufenden Imports.
class StammdatenFortschritt {
  const StammdatenFortschritt({
    required this.phase,
    this.aktuell = 0,
    this.gesamt = 0,
  });

  final StammdatenPhase phase;
  final int aktuell;
  final int gesamt;

  /// Anteil 0..1, oder null wenn der Abschnitt keine Zwischenstände liefert.
  double? get anteil => gesamt <= 0 ? null : (aktuell / gesamt).clamp(0.0, 1.0);

  String get beschriftung => switch (phase) {
        StammdatenPhase.datei => 'Datei wird geöffnet …',
        StammdatenPhase.auswerten => gesamt > 0
            ? 'Artikel werden gelesen … $aktuell von $gesamt'
            : 'Artikel werden gelesen …',
        StammdatenPhase.speichern => 'Wird gespeichert …',
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════════

/// Liest eine Stammdaten-Arbeitsmappe im aktuellen Format.
///
/// Aufbau der Mappe (siehe auch den Generator, der sie erzeugt):
///
///   „Anlagen"      Gerät | Abteilung | Maschinentyp | Parameteranzahl
///   „Steckbriefe"  Maschinentyp | Parameter | Einheit
///   je Artikel     ein Blatt, benannt nach der Artikelnummer
///
/// Das Artikelblatt hat feste Zeilenlagen im Kopf und danach variable
/// Abschnitte, die über ihre Überschrift in Spalte A erkannt werden. Die
/// Zeilenlagen stehen als Konstanten weiter unten — sie beschreiben den
/// Aufbau, nicht ein Rechenergebnis.
class StammdatenImportService {
  StammdatenImportService(this._db);

  final AppDatabase _db;

  // ── Feste Zeilenlagen im Artikelblatt (1-basiert) ──────────────────
  static const int _zeileKopf = 3; // „10390 — Geflügelbratwurst"
  static const int _zeileAbteilung = 9;
  static const int _zeileProzessschritt = 10;
  static const int _zeileAnlage = 11;
  static const int _zeilePersonen = 12;
  static const int _zeileMenge = 13;
  static const int _zeileZeit = 14;
  static const int _zeileFixZeit = 15;

  /// Höchstzahl an Schrittspalten (B bis K).
  static const int _maxSchritte = 10;

  /// Parametergruppe, unter der die Werte einer Anlage abgelegt werden.
  static const String _gruppeAnlage = 'MASCHINENEINSTELLUNGEN';

  /// Überschriften, die einen Abschnitt beenden.
  static const Set<String> _abschnitte = {
    'PROZESSSCHRITTE',
    'ZUSÄTZLICHE INFORMATIONEN',
    'HISTORISCHE DATEN',
  };

  /// Liest die Mappe und schreibt sie in die Datenbank.
  ///
  /// Zwei sauber getrennte Hälften: Das Auswerten läuft auf einem eigenen
  /// Isolate (reine Rechenarbeit, sonst steht das Fenster), das Schreiben
  /// im Hauptisolate, weil die Datenbankverbindung dort lebt.
  Future<StammdatenImportErgebnis> importiere(
    Uint8List bytes, {
    void Function(StammdatenFortschritt)? onFortschritt,
  }) async {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      return const StammdatenImportErgebnis(
        fehler: [
          'Das ist keine Excel-Datei (.xlsx). Bitte die vom Export '
              'erzeugte Mappe wählen.',
        ],
      );
    }

    onFortschritt?.call(
      const StammdatenFortschritt(phase: StammdatenPhase.datei),
    );

    ReceivePort? port;
    StreamSubscription<dynamic>? lauscher;
    if (onFortschritt != null) {
      port = ReceivePort();
      lauscher = port.listen((dynamic n) {
        if (n is! List || n.length != 3) return;
        final i = n[0];
        if (i is! int || i < 0 || i >= StammdatenPhase.values.length) return;
        onFortschritt(
          StammdatenFortschritt(
            phase: StammdatenPhase.values[i],
            aktuell: n[1] as int,
            gesamt: n[2] as int,
          ),
        );
      });
    }

    final Map<String, Object?> roh;
    try {
      roh = await _lesenImIsolate(bytes, port?.sendPort);
    } catch (e) {
      return StammdatenImportErgebnis(
        fehler: ['Die Datei ließ sich nicht auswerten: $e'],
      );
    } finally {
      await lauscher?.cancel();
      port?.close();
    }

    final fehler = (roh['fehler'] as List).cast<String>();
    if (fehler.isNotEmpty) return StammdatenImportErgebnis(fehler: fehler);

    onFortschritt?.call(
      const StammdatenFortschritt(phase: StammdatenPhase.speichern),
    );
    return _speichere(roh);
  }

  /// Startet [_lesen] auf einem eigenen Isolate.
  ///
  /// MUSS statisch bleiben: Eine Closure in einer Instanzmethode nimmt
  /// `this` mit, daran hinge die Datenbankverbindung — und die ist nicht
  /// zwischen Isolaten übertragbar.
  static Future<Map<String, Object?>> _lesenImIsolate(
    Uint8List bytes,
    SendPort? fortschritt,
  ) {
    return Isolate.run(() => _lesen(bytes, fortschritt));
  }

  // ═════════════════════════════════════════════════════════════════════
  // Auswerten — ohne Datenbankzugriff, isolate-tauglich
  // ═════════════════════════════════════════════════════════════════════

  static Map<String, Object?> _lesen(Uint8List bytes, SendPort? fortschritt) {
    final warnungen = <String>[];
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      return {'fehler': <String>['Die Datei ließ sich nicht öffnen: $e']};
    }

    final blattNamen = excel.tables.keys.toList();
    if (!blattNamen.contains('Anlagen') ||
        !blattNamen.contains('Steckbriefe')) {
      return {
        'fehler': <String>[
          'Die Mappe hat keine Blätter „Anlagen" und „Steckbriefe". '
              'Erwartet wird die vom Export erzeugte Datei. '
              'Gefundene Blätter: ${blattNamen.take(8).join(', ')}',
        ],
      };
    }

    // ── Anlagen ────────────────────────────────────────────────────────
    final anlagen = <Map<String, Object?>>[];
    final zeilenAnlagen = excel.tables['Anlagen']!.rows;
    for (var r = 0; r < zeilenAnlagen.length; r++) {
      final name = _text(zeilenAnlagen[r], 0);
      final abteilung = _text(zeilenAnlagen[r], 1);
      final typ = _text(zeilenAnlagen[r], 2);
      if (name == null || abteilung == null || typ == null) continue;
      if (name == 'Anlage') continue; // Kopfzeile
      anlagen.add({'name': name, 'abteilung': abteilung, 'typ': typ});
    }

    // ── Steckbriefe je Maschinentyp ────────────────────────────────────
    final steckbriefe = <String, List<Map<String, Object?>>>{};
    final zeilenSteck = excel.tables['Steckbriefe']!.rows;
    for (var r = 0; r < zeilenSteck.length; r++) {
      final typ = _text(zeilenSteck[r], 0);
      final param = _text(zeilenSteck[r], 1);
      if (typ == null || param == null) continue;
      if (typ == 'Maschinentyp') continue;
      steckbriefe
          .putIfAbsent(typ, () => [])
          .add({'param': param, 'einheit': _text(zeilenSteck[r], 2) ?? ''});
    }

    // ── Artikelblätter ─────────────────────────────────────────────────
    final geraetNamen = {for (final a in anlagen) a['name']! as String};
    final artikelBlaetter = blattNamen
        .where((n) => RegExp(r'^\d{3,8}$').hasMatch(n.trim()))
        .toList();

    final artikel = <Map<String, Object?>>[];
    for (var i = 0; i < artikelBlaetter.length; i++) {
      if (i % 5 == 0) {
        fortschritt?.send(<Object?>[
          StammdatenPhase.auswerten.index,
          i,
          artikelBlaetter.length,
        ]);
      }
      final name = artikelBlaetter[i];
      try {
        artikel.add(
          _lesArtikel(name, excel.tables[name]!.rows, geraetNamen, warnungen),
        );
      } catch (e) {
        warnungen.add('Blatt „$name" übersprungen: $e');
      }
    }
    fortschritt?.send(<Object?>[
      StammdatenPhase.auswerten.index,
      artikelBlaetter.length,
      artikelBlaetter.length,
    ]);

    return {
      'fehler': <String>[],
      'warnungen': warnungen,
      'anlagen': anlagen,
      'steckbriefe': steckbriefe,
      'artikel': artikel,
    };
  }

  /// Liest ein einzelnes Artikelblatt.
  static Map<String, Object?> _lesArtikel(
    String blattName,
    List<List<Data?>> zeilen,
    Set<String> geraetNamen,
    List<String> warnungen,
  ) {
    String? zelle(int zeile, int spalte) =>
        zeile - 1 < zeilen.length ? _text(zeilen[zeile - 1], spalte) : null;

    // Kopf: „10390 — Geflügelbratwurst, fränkische Art"
    final kopf = zelle(_zeileKopf, 0) ?? blattName;
    final teile = kopf.split('—');
    final nummer = teile.first.trim().isEmpty ? blattName : teile.first.trim();
    final bezeichnung =
        teile.length > 1 ? teile.sublist(1).join('—').trim() : '';

    // ── Schritte aus den Kopfzeilen ────────────────────────────────────
    final schritte = <Map<String, Object?>>[];
    for (var s = 0; s < _maxSchritte; s++) {
      final spalte = 1 + s; // B = 1
      final abteilung = zelle(_zeileAbteilung, spalte);
      final anlage = zelle(_zeileAnlage, spalte);
      final prozess = zelle(_zeileProzessschritt, spalte);
      if (abteilung == null && anlage == null && prozess == null) continue;
      schritte.add({
        'spalte': spalte,
        'abteilung': abteilung,
        'prozessschritt': prozess,
        'anlage': anlage,
        'personen': _zahl(zelle(_zeilePersonen, spalte)),
        'mengeKg': _zahl(zelle(_zeileMenge, spalte)),
        'dauerMinuten': _minuten(zelle(_zeileZeit, spalte)),
        'fixZeitMinuten': _zahl(zelle(_zeileFixZeit, spalte)),
        'werte': <Map<String, Object?>>[],
      });
    }

    // ── Abschnitte ab Zeile 16 durchlaufen ─────────────────────────────
    String? aktuellesGeraet;
    var inHistorie = false;
    var historieKopfGesehen = false;
    final historie = <Map<String, Object?>>[];
    final hinweise = <String, String>{};

    for (var r = _zeileFixZeit; r < zeilen.length; r++) {
      final a = _text(zeilen[r], 0);
      if (a == null) continue;
      final oben = a.toUpperCase();

      if (_abschnitte.contains(oben)) {
        aktuellesGeraet = null;
        inHistorie = oben == 'HISTORISCHE DATEN';
        historieKopfGesehen = false;
        continue;
      }
      // Blockkopf einer Anlage? Steht in Großbuchstaben.
      final treffer = geraetNamen.firstWhere(
        (g) => g.toUpperCase() == oben,
        orElse: () => '',
      );
      if (treffer.isNotEmpty) {
        aktuellesGeraet = treffer;
        inHistorie = false;
        continue;
      }

      if (inHistorie) {
        if (!historieKopfGesehen) {
          if (a == 'Datum') historieKopfGesehen = true;
          continue;
        }
        if (a.startsWith('Ø')) continue; // Auswertungszeile
        final datum = _datum(zelle(r + 1, 0));
        if (datum == null) continue;
        historie.add({
          'datum': datum.toIso8601String(),
          'kgRoh': _zahl(zelle(r + 1, 1)),
          'kgFertig': _zahl(zelle(r + 1, 2)),
          'start': _hhmm(zelle(r + 1, 4)),
          'ende': _hhmm(zelle(r + 1, 5)),
          'notizen': zelle(r + 1, 9),
        });
        continue;
      }

      // Zusätzliche Informationen: Personal, Besonderheit, Merkmale …
      if (aktuellesGeraet == null) {
        final wert = _text(zeilen[r], 1);
        if (wert != null && wert.isNotEmpty) hinweise[a] = wert;
        continue;
      }

      // Parameterzeile eines Anlagenblocks: Werte je Schrittspalte.
      for (final schritt in schritte) {
        if (schritt['anlage'] != aktuellesGeraet) continue;
        final wert = _text(zeilen[r], schritt['spalte']! as int);
        if (wert == null || wert.isEmpty) continue;
        (schritt['werte']! as List<Map<String, Object?>>)
            .add({'name': a, 'wert': wert});
      }
    }

    return {
      'nummer': nummer,
      'bezeichnung': bezeichnung,
      'schritte': schritte,
      'historie': historie,
      'hinweise': hinweise,
    };
  }

  // ── Zellen-Helfer ────────────────────────────────────────────────────

  static String? _text(List<Data?> zeile, int spalte) {
    if (spalte >= zeile.length) return null;
    final v = zeile[spalte]?.value;
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double? _zahl(String? s) {
    if (s == null) return null;
    final bereinigt =
        s.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
    if (bereinigt.isEmpty) return null;
    return double.tryParse(bereinigt);
  }

  /// „01:15" oder „1:15:00" → Minuten.
  static double? _minuten(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{1,3}):(\d{2})(?::(\d{2}))?$').firstMatch(s.trim());
    if (m == null) return _zahl(s);
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    return h * 60 + min.toDouble();
  }

  /// Datum aus einer Zelle — tolerant gegenüber allen Schreibweisen.
  ///
  /// Die excel-Bibliothek liefert Datumszellen nicht als Text, sondern als
  /// eigene Typen. Deren `toString()` ist je nach Version unterschiedlich:
  /// `2026-07-14`, `2026-07-14 00:00:00.000` oder
  /// `DateCellValue(year: 2026, month: 7, day: 14)`. Deshalb wird nicht auf
  /// ein Format geprüft, sondern nach Jahr, Monat und Tag gesucht.
  static DateTime? _datum(String? s) {
    if (s == null) return null;
    final t = s.trim();

    // 2026-07-14 (auch mit Uhrzeit dahinter)
    final iso = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (iso != null) {
      return _bau(iso.group(1)!, iso.group(2)!, iso.group(3)!);
    }
    // DateCellValue(year: 2026, month: 7, day: 14)
    final benannt = RegExp(
      r'year:\s*(\d{4}).*?month:\s*(\d{1,2}).*?day:\s*(\d{1,2})',
      dotAll: true,
    ).firstMatch(t);
    if (benannt != null) {
      return _bau(benannt.group(1)!, benannt.group(2)!, benannt.group(3)!);
    }
    // 14.07.2026
    final de = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(t);
    if (de != null) {
      return _bau(de.group(3)!, de.group(2)!, de.group(1)!);
    }
    // Reine Zahl: Excel-Tageswert seit dem 30.12.1899.
    final zahl = double.tryParse(t.replaceAll(',', '.'));
    if (zahl != null && zahl > 20000 && zahl < 80000) {
      return DateTime(1899, 12, 30).add(Duration(days: zahl.floor()));
    }
    return null;
  }

  static DateTime? _bau(String j, String m, String t) {
    final jahr = int.tryParse(j);
    final monat = int.tryParse(m);
    final tag = int.tryParse(t);
    if (jahr == null || monat == null || tag == null) return null;
    if (monat < 1 || monat > 12 || tag < 1 || tag > 31) return null;
    return DateTime(jahr, monat, tag);
  }

  // ═════════════════════════════════════════════════════════════════════
  // Speichern
  // ═════════════════════════════════════════════════════════════════════

  Future<StammdatenImportErgebnis> _speichere(Map<String, Object?> roh) async {
    const uuid = Uuid();
    // Eigene Liste: Die aus dem Isolate ist nur eine Sicht darauf, und
    // hier kommen beim Abbilden der Abteilungen noch Hinweise dazu.
    final warnungen = <String>[...(roh['warnungen'] as List).cast<String>()];
    final anlagen = (roh['anlagen'] as List).cast<Map<String, Object?>>();
    final steckbriefe = (roh['steckbriefe'] as Map).map(
      (k, v) => MapEntry(k as String, (v as List).cast<Map<String, Object?>>()),
    );
    final artikel = (roh['artikel'] as List).cast<Map<String, Object?>>();

    final jetzt = DateTime.now();
    var anzAnlagen = 0, anzSteck = 0, anzNeu = 0, anzAkt = 0;
    var anzSchritte = 0, anzParam = 0, anzChargen = 0;

    await _db.transaction(() async {
      // ── Anlagen ──────────────────────────────────────────────────────
      final vorhandeneMaschinen = await _db.select(_db.machines).get();
      final idVonName = {
        for (final m in vorhandeneMaschinen) m.name.toLowerCase(): m.id,
      };
      final typVonGeraet = <String, String>{};
      final neueMaschinen = <MachinesCompanion>[];

      for (final a in anlagen) {
        final name = a['name']! as String;
        typVonGeraet[name] = a['typ']! as String;
        if (idVonName.containsKey(name.toLowerCase())) continue;
        final id = uuid.v4();
        idVonName[name.toLowerCase()] = id;
        neueMaschinen.add(
          MachinesCompanion.insert(
            id: id,
            name: name,
            // Auch hier der Datenbankwert, nicht der Anzeigename: Der
            // Produktionsmittel-Katalog gruppiert danach.
            abteilung: _abteilungDbWert(a['abteilung'] as String?, warnungen),
          ),
        );
        anzAnlagen++;
      }
      if (neueMaschinen.isNotEmpty) {
        await _db.batch((b) => b.insertAll(_db.machines, neueMaschinen));
      }

      // ── Steckbriefe: je Gerät die Zeilen seines Typs ─────────────────
      //
      // Die App hängt Parameterzeilen an das einzelne Gerät, die Mappe an
      // den Typ. Zwei Verbufas teilen sich also denselben Steckbrief —
      // gespeichert wird er für jede einzeln.
      final vorhandeneDefs = await _db.select(_db.machineParameterDefs).get();
      final bekannt = <String>{
        for (final d in vorhandeneDefs)
          '${d.maschineId}|${d.parameterName.toLowerCase()}',
      };
      final neueDefs = <MachineParameterDefsCompanion>[];
      for (final eintrag in typVonGeraet.entries) {
        final maschineId = idVonName[eintrag.key.toLowerCase()];
        if (maschineId == null) continue;
        final zeilen = steckbriefe[eintrag.value] ?? const [];
        for (var i = 0; i < zeilen.length; i++) {
          final param = zeilen[i]['param']! as String;
          // Plattentemperaturen gehören nicht in den Steckbrief — die
          // verwaltet die Plattenleiste. Sonst tauchen sie in der
          // Parameterliste doppelt auf.
          if (kPlattenParamMuster.hasMatch(param)) continue;
          if (bekannt.contains('$maschineId|${param.toLowerCase()}')) continue;
          neueDefs.add(
            MachineParameterDefsCompanion.insert(
              id: uuid.v4(),
              maschineId: maschineId,
              parameterName: param,
              einheit: Value(zeilen[i]['einheit'] as String?),
              sortierung: Value(i),
            ),
          );
          anzSteck++;
        }
      }
      if (neueDefs.isNotEmpty) {
        await _db.batch(
          (b) => b.insertAll(_db.machineParameterDefs, neueDefs),
        );
      }

      // ── Artikel ──────────────────────────────────────────────────────
      final vorhandeneArtikel = await _db.select(_db.products).get();
      final artikelId = {
        for (final p in vorhandeneArtikel) p.artikelnummer: p.id,
      };

      for (final a in artikel) {
        final nummer = a['nummer']! as String;
        final bezeichnung = a['bezeichnung']! as String;
        final hinweise = (a['hinweise'] as Map).cast<String, String>();
        final notiz = hinweise.entries
            .map((e) => '${e.key}: ${e.value}')
            .join(' | ');

        var pid = artikelId[nummer];
        if (pid == null) {
          pid = uuid.v4();
          artikelId[nummer] = pid;
          await _db.into(_db.products).insert(
                ProductsCompanion.insert(
                  id: pid,
                  artikelnummer: nummer,
                  artikelbezeichnung:
                      bezeichnung.isEmpty ? nummer : bezeichnung,
                  notizen: Value(notiz.isEmpty ? null : notiz),
                  istEingepflegt: const Value(false),
                ),
              );
          anzNeu++;
        } else {
          await (_db.update(_db.products)..where((p) => p.id.equals(pid!)))
              .write(
            ProductsCompanion(
              artikelbezeichnung: bezeichnung.isEmpty
                  ? const Value.absent()
                  : Value(bezeichnung),
              notizen: notiz.isEmpty ? const Value.absent() : Value(notiz),
              updatedAt: Value(jetzt),
            ),
          );
          anzAkt++;
        }

        // Schritte ersetzen: Die Mappe ist für sie die Wahrheit.
        final alteSchritte = await (_db.select(_db.productSteps)
              ..where((s) => s.productId.equals(pid!)))
            .get();
        if (alteSchritte.isNotEmpty) {
          final ids = alteSchritte.map((s) => s.id).toList();
          await (_db.delete(_db.productStepParameters)
                ..where((p) => p.stepId.isIn(ids)))
              .go();
          await (_db.delete(_db.productSteps)
                ..where((s) => s.productId.equals(pid!)))
              .go();
        }

        final schritte = (a['schritte'] as List).cast<Map<String, Object?>>();
        final neueSchritte = <ProductStepsCompanion>[];
        final neueWerte = <ProductStepParametersCompanion>[];
        for (var i = 0; i < schritte.length; i++) {
          final s = schritte[i];
          final stepId = uuid.v4();
          final anlage = s['anlage'] as String?;
          neueSchritte.add(
            ProductStepsCompanion.insert(
              id: stepId,
              productId: pid,
              reihenfolge: i + 1,
              abteilung: _abteilungDbWert(
                s['abteilung'] as String?,
                warnungen,
              ),
              prozessschritt: Value(s['prozessschritt'] as String?),
              maschine: Value(anlage),
              maschineId: Value(
                anlage == null ? null : idVonName[anlage.toLowerCase()],
              ),
              basisMengeKg: (s['mengeKg'] as double?) ?? 0,
              basisDauerMinuten: (s['dauerMinuten'] as double?) ?? 0,
              basisMitarbeiter: ((s['personen'] as double?) ?? 0).round(),
              fixZeitMinuten: Value(s['fixZeitMinuten'] as double?),
            ),
          );
          anzSchritte++;

          // Plattenwerte gehören in ihre eigene Gruppe: Die Leiste im
          // Artikeldetail sucht über Name UND Gruppe. Läge ein
          // `Platte Oben 3` unter MASCHINENEINSTELLUNGEN, wäre der Wert
          // zwar gespeichert, in der Leiste aber unsichtbar — und der
          // Export fände ihn dort auch nicht wieder.
          final istKombi = anlage != null && _istKombiofen(anlage);
          final plattenGruppe =
              istKombi ? kPlattenGruppeKombi : kPlattenGruppeBrat;
          var hatPlatten = false;

          final werte = (s['werte'] as List).cast<Map<String, Object?>>();
          for (var w = 0; w < werte.length; w++) {
            final name = werte[w]['name']! as String;
            final istPlatte = kPlattenParamMuster.hasMatch(name);
            if (istPlatte) hatPlatten = true;
            neueWerte.add(
              ProductStepParametersCompanion.insert(
                id: uuid.v4(),
                stepId: stepId,
                parameterGruppe: istPlatte ? plattenGruppe : _gruppeAnlage,
                parameterName: name,
                wert: Value(werte[w]['wert'] as String?),
                reihenfolge: Value(w),
              ),
            );
            anzParam++;
          }

          // Markerparameter, damit die Leiste weiß, welches Raster gilt.
          if (hatPlatten) {
            neueWerte.add(
              ProductStepParametersCompanion.insert(
                id: uuid.v4(),
                stepId: stepId,
                parameterGruppe: plattenGruppe,
                parameterName: kPlattenSchemaParam,
                wert: Value(istKombi ? 'kombiofen' : 'bratstrasse'),
                reihenfolge: const Value(0),
              ),
            );
          }
        }
        if (neueSchritte.isNotEmpty) {
          await _db.batch((b) => b.insertAll(_db.productSteps, neueSchritte));
        }
        if (neueWerte.isNotEmpty) {
          await _db.batch(
            (b) => b.insertAll(_db.productStepParameters, neueWerte),
          );
        }

        // Historie ergänzen — vorhandene Chargen bleiben unangetastet.
        final vorhandeneChargen = await (_db.select(_db.productionHistory)
              ..where((h) => h.productId.equals(pid!)))
            .get();
        final schluessel = <String>{
          for (final h in vorhandeneChargen)
            '${h.datum.toIso8601String()}|${h.kgRohware}',
        };
        final neueChargen = <ProductionHistoryCompanion>[];
        for (final h in (a['historie'] as List).cast<Map<String, Object?>>()) {
          final datum = DateTime.parse(h['datum']! as String);
          final roh = h['kgRoh'] as double?;
          if (roh == null || roh <= 0) continue;
          if (schluessel.contains('${datum.toIso8601String()}|$roh')) continue;
          final fertig = h['kgFertig'] as double?;
          final start = h['start'] as String?;
          final ende = h['ende'] as String?;
          final dauer = _dauerMinuten(start, ende);
          neueChargen.add(
            ProductionHistoryCompanion.insert(
              id: uuid.v4(),
              productId: pid,
              datum: datum,
              kgRohware: Value(roh),
              kgFertigware: Value(fertig),
              verlustAnteil: Value(
                (fertig != null && roh > 0) ? 1 - (fertig / roh) : null,
              ),
              startzeit: Value(start),
              endzeit: Value(ende),
              produktionszeitMinuten: Value(dauer),
              kgProStundeRoh: Value(
                (dauer != null && dauer > 0) ? roh / (dauer / 60) : null,
              ),
              kgProStundeGegart: Value(
                (dauer != null && dauer > 0 && fertig != null)
                    ? fertig / (dauer / 60)
                    : null,
              ),
              notizen: Value(h['notizen'] as String?),
              quelle: const Value('excel'),
            ),
          );
          anzChargen++;
        }
        if (neueChargen.isNotEmpty) {
          await _db.batch(
            (b) => b.insertAll(_db.productionHistory, neueChargen),
          );
        }
      }
    });

    return StammdatenImportErgebnis(
      anlagen: anzAnlagen,
      steckbriefZeilen: anzSteck,
      artikelNeu: anzNeu,
      artikelAktualisiert: anzAkt,
      schritte: anzSchritte,
      parameter: anzParam,
      chargen: anzChargen,
      warnungen: warnungen,
    );
  }

  /// Ist die Anlage der Kombiofen? Er trug früher auch die Namen
  /// „Dampftunnel" und „Heißluftofen" — sein Raster hat 12 untere Platten,
  /// die Bratstraße dagegen 10 oben und 10 unten.
  static bool _istKombiofen(String anlage) {
    final n = anlage.toLowerCase();
    return n.contains('kombiofen') ||
        n.contains('dampftunnel') ||
        n.contains('heißluft') ||
        n.contains('heissluft');
  }

  /// Abteilungsname aus der Mappe → Datenbankwert des Enums.
  ///
  /// In der Mappe stehen Anzeigenamen („Bratstraße"), in der Datenbank
  /// Schlüssel („bratstrasse"). `Abteilung.fromDbValue` wirft bei
  /// unbekannten Werten eine Ausnahme — landet also ein Anzeigename in der
  /// Spalte, stürzt später jede Ansicht ab, die den Schritt darstellt.
  ///
  /// Erkannt wird in dieser Reihenfolge: Datenbankwert, Anzeigename,
  /// entschärfte Schreibweise (Umlaute aufgelöst, Leerzeichen entfernt),
  /// bekannte Sonderfälle. Bleibt alles ohne Treffer, greift die Zerlegung
  /// als Anfang der Produktionskette — mit Hinweis.
  static String _abteilungDbWert(String? name, List<String> warnungen) {
    if (name == null || name.trim().isEmpty) return Abteilung.zerlegung.dbValue;
    final roh = name.trim();

    String entschaerft(String v) => v
        .toLowerCase()
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    final gesucht = entschaerft(roh);
    for (final a in Abteilung.values) {
      if (a.dbValue == roh) return a.dbValue;
      if (entschaerft(a.anzeigeName) == gesucht) return a.dbValue;
      if (entschaerft(a.dbValue) == gesucht) return a.dbValue;
    }

    const sonderfaelle = <String, String>{
      'verpackungsabteilung': 'verpackung',
      'tef1': 'verpackung_tef1',
      'tef2': 'verpackung_tef2',
      'poekelraum': 'wurstkueche',
      'mobil': 'verpackung',
    };
    final treffer = sonderfaelle[gesucht];
    if (treffer != null) return treffer;

    final hinweis = 'Abteilung „$roh" ist unbekannt — als Zerlegung '
        'übernommen. Bitte in der App richtigstellen.';
    if (!warnungen.contains(hinweis)) warnungen.add(hinweis);
    return Abteilung.zerlegung.dbValue;
  }

  /// Minuten zwischen zwei Uhrzeiten, über Mitternacht hinweg.
  static double? _dauerMinuten(String? start, String? ende) {
    final a = _uhrzeit(start);
    final b = _uhrzeit(ende);
    if (a == null || b == null) return null;
    var diff = b - a;
    if (diff < 0) diff += 24 * 60; // Nachtschicht
    return diff.toDouble();
  }

  /// Uhrzeit in der Form „HH:MM", oder null.
  static String? _hhmm(String? s) {
    final min = _uhrzeit(s);
    if (min == null) return null;
    final h = (min ~/ 60).toString().padLeft(2, '0');
    final m = (min % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Uhrzeit als Minuten seit Mitternacht — ebenfalls tolerant.
  ///
  /// Mögliche Schreibweisen: `07:25`, `7:25:00.000`,
  /// `TimeCellValue(hour: 7, minute: 25, second: 0)` oder der
  /// Excel-Tagesbruchteil `0.309`.
  static int? _uhrzeit(String? s) {
    if (s == null) return null;
    final t = s.trim();

    final uhr = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(t);
    if (uhr != null) {
      final h = int.parse(uhr.group(1)!);
      final m = int.parse(uhr.group(2)!);
      if (h < 24 && m < 60) return h * 60 + m;
    }
    final benannt = RegExp(
      r'hour:\s*(\d{1,2}).*?minute:\s*(\d{1,2})',
      dotAll: true,
    ).firstMatch(t);
    if (benannt != null) {
      return int.parse(benannt.group(1)!) * 60 +
          int.parse(benannt.group(2)!);
    }
    // Tagesbruchteil: 0.309 -> 07:25
    final bruch = double.tryParse(t.replaceAll(',', '.'));
    if (bruch != null && bruch >= 0 && bruch < 1) {
      return (bruch * 24 * 60).round();
    }
    return null;
  }
}
