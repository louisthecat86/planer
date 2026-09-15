import 'dart:async';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

import '../database/database.dart';

/// Abschnitt, in dem der Import gerade steckt.
enum NavisionPhase {
  /// Die Arbeitsmappe wird geöffnet. Dieser Abschnitt lässt sich nicht
  /// unterteilen — das Excel-Paket liest die Datei am Stück ein und meldet
  /// dabei nichts nach außen.
  datei,

  /// Die Datenzeilen werden ausgewertet. Hier gibt es echte Zwischenstände.
  zeilen,

  /// Der Katalog wird in die Datenbank geschrieben.
  speichern,
}

/// Zwischenstand eines laufenden Imports.
class NavisionFortschritt {
  const NavisionFortschritt({
    required this.phase,
    this.aktuell = 0,
    this.gesamt = 0,
  });

  final NavisionPhase phase;
  final int aktuell;
  final int gesamt;

  /// Anteil 0..1, oder null wenn der Abschnitt keine Zwischenstände liefert
  /// (dann gehört ein unbestimmter Balken hin, kein Prozentwert).
  double? get anteil {
    if (gesamt <= 0) return null;
    return (aktuell / gesamt).clamp(0.0, 1.0);
  }

  String get beschriftung => switch (phase) {
        NavisionPhase.datei => 'Datei wird geöffnet …',
        NavisionPhase.zeilen => gesamt > 0
            ? 'Artikel werden gelesen … $aktuell von $gesamt'
            : 'Artikel werden gelesen …',
        NavisionPhase.speichern => 'Wird gespeichert …',
      };
}

/// Ergebnis eines Navision-Imports.
class NavisionImportErgebnis {
  const NavisionImportErgebnis({
    required this.gelesen,
    required this.uebernommen,
    required this.mitAuftrag,
    required this.warnungen,
  });

  final int gelesen;
  final int uebernommen;
  final int mitAuftrag;
  final List<String> warnungen;
}

/// Liest die Navision-Artikelübersicht (Excel-Export aus NAV) ein.
///
/// Der Aufbau der Datei: Zeile 1 und 2 tragen Serverangabe und Titel,
/// Zeile 3 die Spaltenüberschriften, ab Zeile 4 die Artikel. Statt feste
/// Spaltenpositionen anzunehmen, wird die Kopfzeile ausgewertet — so
/// übersteht der Import auch eine geänderte Spaltenreihenfolge oder
/// zusätzliche Felder aus NAV.
class NavisionImportService {
  NavisionImportService(this._db);

  final AppDatabase _db;

  /// Feldname → mögliche Überschriften in der Navision-Ausgabe.
  ///
  /// Bewusst mit Aliasen: Jeder Mitarbeiter hat in Navision seine eigene
  /// Spaltenansicht — Spalten können fehlen, zusätzlich da sein, anders
  /// heißen oder in anderer Reihenfolge stehen. Verglichen wird
  /// normalisiert (klein, ohne Punkte/Leerzeichen, Umlaute aufgelöst),
  /// damit „Nr.", „Nr" und „Artikelnr." alle passen.
  static const Map<String, List<String>> _spaltenAliase = {
    'nummer': ['nr', 'nummer', 'artikelnr', 'artikelnummer', 'artikel'],
    'nummer2': ['nummer2', 'nr2'],
    'beschreibung': [
      'beschreibung',
      'beschreibung1',
      'bezeichnung',
      'artikelbeschreibung',
      'artikelbezeichnung',
      'name',
    ],
    'beschreibung2': ['beschreibung2', 'bezeichnung2'],
    'suchbegriff': ['suchbegriff'],
    'pluCode': ['plucode', 'plu'],
    'stuecklistenNr': [
      'fertstuecklistennr',
      'stuecklistennr',
      'fertigungsstuecklistennr',
      'stueckliste',
    ],
    'basiseinheit': [
      'basiseinheitencode',
      'basiseinheit',
      'einheitencode',
      'einheit',
      'masseinheit',
    ],
    'lagerbestand': ['lagerbestand', 'bestand', 'lagerbestandmenge'],
    'mengeInFa': [
      'mengeinfa',
      'mengeinfertigungsauftrag',
      'mengeinfertigungsauftragen',
    ],
    'mengeInAuftrag': [
      'mengeinauftrag',
      'mengeinauftragen',
      'mengeinverkaufsauftrag',
      'mengeinverkaufsauftragen',
    ],
    'produktbuchungsgruppe': ['produktbuchungsgruppe', 'produktbuchungsgr'],
    'artikelkategorie': ['artikelkategoriencode', 'artikelkategorie'],
    'produktgruppe': ['produktgruppencode', 'produktgruppe'],
  };

  /// Umgekehrte Zuordnung Überschrift → Feldname (einmal aufgebaut).
  static final Map<String, String> _feldVonUeberschrift = {
    for (final e in _spaltenAliase.entries)
      for (final alias in e.value) alias: e.key,
  };

  /// Klartextnamen für Meldungen.
  static const Map<String, String> _feldNamen = {
    'nummer': 'Nr.',
    'beschreibung': 'Beschreibung',
    'basiseinheit': 'Basiseinheitencode',
    'lagerbestand': 'Lagerbestand',
    'mengeInAuftrag': 'Menge in Auftrag',
  };

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('.', '')
      .replaceAll('-', '')
      .replaceAll('/', '')
      .replaceAll(' ', '')
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u')
      .replaceAll('ß', 'ss');

  static String? _text(Data? zelle) {
    final v = zelle?.value;
    if (v == null) return null;
    if (v is TextCellValue) return v.value.text?.trim();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    return v.toString().trim();
  }

  static double _zahl(Data? zelle) {
    final t = _text(zelle);
    if (t == null || t.isEmpty) return 0;
    // NAV exportiert je nach Einstellung mit Komma oder Punkt und
    // Tausenderpunkten — beides abfangen.
    var bereinigt = t.replaceAll(' ', '');
    if (bereinigt.contains(',') && bereinigt.contains('.')) {
      bereinigt = bereinigt.replaceAll('.', '').replaceAll(',', '.');
    } else {
      bereinigt = bereinigt.replaceAll(',', '.');
    }
    return double.tryParse(bereinigt) ?? 0;
  }

  /// Liest die Navision-Artikelübersicht aus den Roh-Bytes einer .xlsx-Datei.
  ///
  /// Bewusst Bytes statt Dateipfad: Auf dem Desktop liefert der FilePicker
  /// mit Custom-Filter teils gar keinen Pfad (nur Bytes), und Bytes
  /// funktionieren auf jeder Plattform gleich.
  ///
  /// Ablauf in zwei sauber getrennten Hälften:
  ///   1. Parsen auf einem eigenen Isolate ([_parseKatalog]) — das ist
  ///      reine Rechenarbeit und blockierte bisher das Fenster, während
  ///      gut 4.000 Zeilen durch den XML-Parser liefen.
  ///   2. Schreiben im Hauptisolate, weil die Datenbankverbindung dort
  ///      lebt — jetzt als EIN Batch statt 4.000 Einzel-Inserts.
  Future<NavisionImportErgebnis> importiere(
    Uint8List bytes, {
    void Function(NavisionFortschritt)? onFortschritt,
  }) async {
    debugPrint('[NAV] Import gestartet — ${bytes.length} Bytes');

    // Grober Format-Check: echte .xlsx sind ZIP-Container und beginnen mit
    // der Signatur „PK" (0x50 0x4B). Ein umbenanntes altes .xls oder eine
    // als Excel getarnte HTML-Tabelle hat das nicht — dann sofort raus mit
    // klarer Ansage statt kryptischem Parser-Crash. Der Check ist billig
    // und bleibt deshalb hier, noch vor dem Isolate-Wechsel.
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw Exception(
        'Das ist keine echte Excel-Datei (.xlsx). In Navision bitte über '
        '„Öffnen in Excel" bzw. „Nach Microsoft Excel" exportieren und die '
        'so erzeugte .xlsx wählen — ein umbenanntes .xls oder eine '
        'HTML-Tabelle kann die App nicht lesen.',
      );
    }

    // Über die Isolate-Grenze gehen ausschließlich einfache Typen (Listen,
    // Maps, Strings, Zahlen). Fehler aus dem Parser kommen als Exception
    // hier an und behalten ihren Wortlaut.
    final uhrGesamt = Stopwatch()..start();

    // Fortschritt aus dem Isolate: Ein SendPort ist übertragbar, deshalb
    // kann das Parse-Isolate Zwischenstände zurückmelden, ohne dass wir
    // Isolate.run gegen eine eigene Isolate.spawn-Verdrahtung tauschen
    // müssten.
    onFortschritt?.call(
      const NavisionFortschritt(phase: NavisionPhase.datei),
    );

    ReceivePort? port;
    StreamSubscription<dynamic>? lauscher;
    if (onFortschritt != null) {
      port = ReceivePort();
      lauscher = port.listen((dynamic nachricht) {
        if (nachricht is! List || nachricht.length != 3) return;
        final index = nachricht[0];
        if (index is! int ||
            index < 0 ||
            index >= NavisionPhase.values.length) {
          return;
        }
        onFortschritt(
          NavisionFortschritt(
            phase: NavisionPhase.values[index],
            aktuell: nachricht[1] as int,
            gesamt: nachricht[2] as int,
          ),
        );
      });
    }

    final Map<String, Object?> roh;
    try {
      roh = await _parseImIsolate(bytes, port?.sendPort);
    } finally {
      await lauscher?.cancel();
      port?.close();
    }
    final msParsen = uhrGesamt.elapsedMilliseconds;

    final zeilen = (roh['zeilen'] as List).cast<Map<String, Object?>>();
    final warnungen = (roh['warnungen'] as List).cast<String>();
    final protokoll = (roh['protokoll'] as List).cast<String>();
    final gelesen = roh['gelesen'] as int;
    final mitAuftrag = roh['mitAuftrag'] as int;

    // Das Parser-Protokoll erst hier ausgeben: Aus einem Hintergrund-
    // Isolate landet debugPrint in unvorhersehbarer Reihenfolge im Log.
    for (final zeile in protokoll) {
      debugPrint(zeile);
    }

    final jetzt = DateTime.now();
    final eintraege = [
      for (final z in zeilen)
        NavisionArtikelKatalogCompanion.insert(
          nummer: z['nummer']! as String,
          nummer2: Value(z['nummer2'] as String?),
          beschreibung: Value((z['beschreibung'] as String?) ?? ''),
          beschreibung2: Value(z['beschreibung2'] as String?),
          suchbegriff: Value(z['suchbegriff'] as String?),
          pluCode: Value(z['pluCode'] as String?),
          stuecklistenNr: Value(z['stuecklistenNr'] as String?),
          basiseinheit: Value(z['basiseinheit'] as String?),
          lagerbestand: Value(z['lagerbestand']! as double),
          mengeInFa: Value(z['mengeInFa']! as double),
          mengeInAuftrag: Value(z['mengeInAuftrag']! as double),
          produktbuchungsgruppe: Value(z['produktbuchungsgruppe'] as String?),
          artikelkategorie: Value(z['artikelkategorie'] as String?),
          produktgruppe: Value(z['produktgruppe'] as String?),
          importiertAm: Value(jetzt),
        ),
    ];

    final msAufbereiten = uhrGesamt.elapsedMilliseconds - msParsen;

    onFortschritt?.call(
      const NavisionFortschritt(phase: NavisionPhase.speichern),
    );

    await _db.transaction(() async {
      // Kompletter Ersatz: Der Import bildet den aktuellen NAV-Stand ab,
      // alte Zeilen wären sonst Karteileichen mit falschen Beständen.
      await _db.delete(_db.navisionArtikelKatalog).go();
      if (eintraege.isNotEmpty) {
        // Ein Batch statt eines Inserts je Zeile. Bei rund 4.000 Artikeln
        // waren das vorher 4.000 einzelne Statements durch die
        // Drift-Schicht — der spürbarste Teil der Wartezeit.
        await _db.batch(
          (b) => b.insertAllOnConflictUpdate(
            _db.navisionArtikelKatalog,
            eintraege,
          ),
        );
      }
    });

    debugPrint(
      '[NAV] fertig — gelesen=$gelesen · uebernommen=${eintraege.length} · '
      'mitAuftrag=$mitAuftrag · Warnungen=${warnungen.length}',
    );
    // Vorübergehende Messung: zeigt, wo die Wartezeit wirklich entsteht.
    debugPrint(
      '[NAV] Zeiten — Parsen (Isolate): $msParsen ms · '
      'Companions bauen: $msAufbereiten ms · '
      'Datenbank schreiben: '
      '${uhrGesamt.elapsedMilliseconds - msParsen - msAufbereiten} ms · '
      'GESAMT: ${uhrGesamt.elapsedMilliseconds} ms',
    );

    return NavisionImportErgebnis(
      gelesen: gelesen,
      uebernommen: eintraege.length,
      mitAuftrag: mitAuftrag,
      warnungen: warnungen,
    );
  }

  /// Startet [_parseKatalog] auf einem eigenen Isolate.
  ///
  /// Diese Methode MUSS statisch bleiben. Eine Closure übernimmt beim
  /// Erzeugen ihren umgebenden Kontext — in einer Instanzmethode gehört
  /// `this` dazu, und damit hinge die ganze Kette `NavisionImportService`
  /// → `AppDatabase` → `DatabaseConnection` mit dran. Eine offene
  /// Datenbankverbindung ist nicht zwischen Isolaten übertragbar, der
  /// Import scheiterte dann mit „object is unsendable". Dass
  /// [_parseKatalog] statisch ist und `this` nie benutzt, genügt nicht:
  /// Der Kontext wird als Block erfasst, nicht je Variable.
  ///
  /// In einer statischen Methode gibt es kein `this` — übertragen wird
  /// nur [bytes].
  static Future<Map<String, Object?>> _parseImIsolate(
    Uint8List bytes,
    SendPort? fortschritt,
  ) {
    return Isolate.run(() => _parseKatalog(bytes, fortschritt));
  }

  /// Parst die Arbeitsmappe zu reinen Daten — ohne jeden Datenbankzugriff.
  ///
  /// Läuft auf einem eigenen Isolate und darf deshalb nichts zurückgeben,
  /// was an Instanzzustand hängt. Das Ergebnis ist bewusst eine schlichte
  /// Map aus Listen, Maps, Strings und Zahlen.
  static Map<String, Object?> _parseKatalog(
    Uint8List bytes,
    SendPort? fortschritt,
  ) {
    final warnungen = <String>[];
    final protokoll = <String>[];

    final uhr = Stopwatch()..start();

    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      throw Exception('Die Datei ließ sich nicht als Excel öffnen: $e');
    }
    final msDecode = uhr.elapsedMilliseconds;

    if (excel.tables.isEmpty) {
      throw Exception('Die Datei enthält kein Tabellenblatt.');
    }
    final sheetName = excel.tables.keys.first;
    final tabelle = excel.tables[sheetName];
    if (tabelle == null || tabelle.rows.isEmpty) {
      throw Exception('Die Datei enthält keine Daten.');
    }
    protokoll.add('[NAV] Blatt „$sheetName" · ${tabelle.rows.length} Zeilen');

    // Kopfzeile suchen — nicht über feste Namen, sondern über die Zeile mit
    // den MEISTEN erkannten Spalten. Dadurch ist es egal, welche Spalten der
    // jeweilige Navision-Nutzer ein- oder ausgeblendet hat, solange die
    // Artikelnummer dabei ist. Es werden mehr Zeilen geprüft als früher,
    // weil manche Ansichten zusätzliche Titelzeilen voranstellen.
    int? kopfZeile;
    Map<String, int> spalteVon = {};
    var besteTreffer = 0;
    final maxPruefen = tabelle.rows.length < 40 ? tabelle.rows.length : 40;
    for (var r = 0; r < maxPruefen; r++) {
      final zeile = tabelle.rows[r];
      final treffer = <String, int>{};
      for (var c = 0; c < zeile.length; c++) {
        final feld = _feldVonUeberschrift[_norm(_text(zeile[c]) ?? '')];
        // Erste Fundstelle gewinnt — doppelte Überschriften kippen die
        // Zuordnung damit nicht.
        if (feld != null && !treffer.containsKey(feld)) treffer[feld] = c;
      }
      // Ohne Artikelnummer ist eine Zeile als Kopfzeile wertlos.
      if (!treffer.containsKey('nummer')) continue;
      if (treffer.length > besteTreffer) {
        besteTreffer = treffer.length;
        kopfZeile = r;
        spalteVon = treffer;
      }
    }

    if (kopfZeile == null) {
      // Zur Fehlersuche: zeigen, was in den ersten Zeilen überhaupt stand.
      final gefunden = <String>[];
      for (var r = 0; r < maxPruefen && gefunden.length < 15; r++) {
        for (final c in tabelle.rows[r]) {
          final t = _text(c);
          if (t != null && t.isNotEmpty) gefunden.add(t);
          if (gefunden.length >= 15) break;
        }
      }
      throw Exception(
        'Keine Kopfzeile mit einer Artikelnummer-Spalte gefunden. Erwartet '
        'wird eine Spalte „Nr." (auch „Artikelnr." o.ä.). '
        'Gefundene Überschriften: ${gefunden.join(' | ')}',
      );
    }

    protokoll.add(
      '[NAV] Kopfzeile in Zeile ${kopfZeile + 1} · '
      '${spalteVon.length} Spalten erkannt: ${spalteVon.keys.join(', ')}',
    );

    // Ab hier bricht NICHTS mehr ab: Fehlende Spalten werden gemeldet, der
    // Import läuft mit dem durch, was die Datei hergibt. Die betroffenen
    // Felder bleiben leer bzw. 0.
    for (final feld in ['beschreibung', 'basiseinheit']) {
      if (!spalteVon.containsKey(feld)) {
        warnungen.add(
          'Spalte „${_feldNamen[feld] ?? feld}" fehlt in dieser Ansicht — '
          'das Feld bleibt leer.',
        );
      }
    }
    for (final feld in ['mengeInAuftrag', 'lagerbestand']) {
      if (!spalteVon.containsKey(feld)) {
        warnungen.add(
          'Spalte „${_feldNamen[feld] ?? feld}" fehlt — ohne sie lässt sich '
          'der Bedarf nicht berechnen. In Navision bitte einblenden.',
        );
      }
    }

    String? feld(List<Data?> zeile, String name) {
      final c = spalteVon[name];
      if (c == null || c >= zeile.length) return null;
      final t = _text(zeile[c]);
      return (t == null || t.isEmpty) ? null : t;
    }

    double zahlFeld(List<Data?> zeile, String name) {
      final c = spalteVon[name];
      if (c == null || c >= zeile.length) return 0;
      return _zahl(zeile[c]);
    }

    final zeilen = <Map<String, Object?>>[];
    var gelesen = 0;
    var mitAuftrag = 0;

    final ersteDatenZeile = kopfZeile + 1;
    final gesamtZeilen = tabelle.rows.length - ersteDatenZeile;
    void melde(int fertig) {
      fortschritt?.send(<Object?>[
        NavisionPhase.zeilen.index,
        fertig,
        gesamtZeilen,
      ]);
    }

    melde(0);

    for (var r = ersteDatenZeile; r < tabelle.rows.length; r++) {
      // Alle 200 Zeilen melden — oft genug für einen flüssigen Balken,
      // selten genug, dass das Verschicken nicht selbst ins Gewicht fällt.
      if ((r - ersteDatenZeile) % 200 == 0) melde(r - ersteDatenZeile);
      final zeile = tabelle.rows[r];
      final nummer = feld(zeile, 'nummer');
      if (nummer == null) continue;
      gelesen++;

      final auftrag = zahlFeld(zeile, 'mengeInAuftrag');
      if (auftrag > 0) mitAuftrag++;

      zeilen.add(<String, Object?>{
        'nummer': nummer,
        'nummer2': feld(zeile, 'nummer2'),
        'beschreibung': feld(zeile, 'beschreibung') ?? '',
        'beschreibung2': feld(zeile, 'beschreibung2'),
        'suchbegriff': feld(zeile, 'suchbegriff'),
        'pluCode': feld(zeile, 'pluCode'),
        'stuecklistenNr': feld(zeile, 'stuecklistenNr'),
        'basiseinheit': feld(zeile, 'basiseinheit'),
        'lagerbestand': zahlFeld(zeile, 'lagerbestand'),
        'mengeInFa': zahlFeld(zeile, 'mengeInFa'),
        'mengeInAuftrag': auftrag,
        'produktbuchungsgruppe': feld(zeile, 'produktbuchungsgruppe'),
        'artikelkategorie': feld(zeile, 'artikelkategorie'),
        'produktgruppe': feld(zeile, 'produktgruppe'),
      });
    }

    melde(gesamtZeilen);

    protokoll.add(
      '[NAV] Zeiten — Excel.decodeBytes: $msDecode ms · '
      'Zeilen auswerten: ${uhr.elapsedMilliseconds - msDecode} ms',
    );

    return <String, Object?>{
      'zeilen': zeilen,
      'warnungen': warnungen,
      'protokoll': protokoll,
      'gelesen': gelesen,
      'mitAuftrag': mitAuftrag,
    };
  }
}
