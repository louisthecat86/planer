import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

import '../database/database.dart';

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
  Future<NavisionImportErgebnis> importiere(Uint8List bytes) async {
    debugPrint('[NAV] Import gestartet — ${bytes.length} Bytes');

    // Grober Format-Check: echte .xlsx sind ZIP-Container und beginnen mit
    // der Signatur „PK" (0x50 0x4B). Ein umbenanntes altes .xls oder eine
    // als Excel getarnte HTML-Tabelle hat das nicht — dann sofort raus mit
    // klarer Ansage statt kryptischem Parser-Crash.
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw Exception(
        'Das ist keine echte Excel-Datei (.xlsx). In Navision bitte über '
        '„Öffnen in Excel" bzw. „Nach Microsoft Excel" exportieren und die '
        'so erzeugte .xlsx wählen — ein umbenanntes .xls oder eine '
        'HTML-Tabelle kann die App nicht lesen.',
      );
    }

    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      debugPrint('[NAV] decodeBytes fehlgeschlagen: $e');
      throw Exception('Die Datei ließ sich nicht als Excel öffnen: $e');
    }

    final warnungen = <String>[];

    if (excel.tables.isEmpty) {
      throw Exception('Die Datei enthält kein Tabellenblatt.');
    }
    final sheetName = excel.tables.keys.first;
    final tabelle = excel.tables[sheetName];
    if (tabelle == null || tabelle.rows.isEmpty) {
      throw Exception('Die Datei enthält keine Daten.');
    }
    debugPrint(
      '[NAV] Blatt „$sheetName" · ${tabelle.rows.length} Zeilen',
    );

    // Kopfzeile suchen — nicht über feste Namen, sondern über die Zeile mit
    // den MEISTEN erkannten Spalten. Dadurch ist es egal, welche Spalten der
    // jeweilige Navision-Nutzer ein- oder ausgeblendet hat, solange die
    // Artikelnummer dabei ist. Es werden mehr Zeilen geprüft als früher,
    // weil manche Ansichten zusätzliche Titelzeilen voranstellen.
    int? kopfZeile;
    Map<String, int> spalteVon = {};
    var besteTreffer = 0;
    final maxPruefen =
        tabelle.rows.length < 40 ? tabelle.rows.length : 40;
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

    debugPrint(
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

    final jetzt = DateTime.now();
    var gelesen = 0;
    var uebernommen = 0;
    var mitAuftrag = 0;

    await _db.transaction(() async {
      // Kompletter Ersatz: Der Import bildet den aktuellen NAV-Stand ab,
      // alte Zeilen wären sonst Karteileichen mit falschen Beständen.
      await _db.delete(_db.navisionArtikelKatalog).go();

      for (var r = kopfZeile! + 1; r < tabelle.rows.length; r++) {
        final zeile = tabelle.rows[r];
        final nummer = feld(zeile, 'nummer');
        if (nummer == null) continue;
        gelesen++;

        final auftrag = zahlFeld(zeile, 'mengeInAuftrag');
        if (auftrag > 0) mitAuftrag++;

        await _db.into(_db.navisionArtikelKatalog).insertOnConflictUpdate(
              NavisionArtikelKatalogCompanion.insert(
                nummer: nummer,
                nummer2: Value(feld(zeile, 'nummer2')),
                beschreibung: Value(feld(zeile, 'beschreibung') ?? ''),
                beschreibung2: Value(feld(zeile, 'beschreibung2')),
                suchbegriff: Value(feld(zeile, 'suchbegriff')),
                pluCode: Value(feld(zeile, 'pluCode')),
                stuecklistenNr: Value(feld(zeile, 'stuecklistenNr')),
                basiseinheit: Value(feld(zeile, 'basiseinheit')),
                lagerbestand: Value(zahlFeld(zeile, 'lagerbestand')),
                mengeInFa: Value(zahlFeld(zeile, 'mengeInFa')),
                mengeInAuftrag: Value(auftrag),
                produktbuchungsgruppe:
                    Value(feld(zeile, 'produktbuchungsgruppe')),
                artikelkategorie: Value(feld(zeile, 'artikelkategorie')),
                produktgruppe: Value(feld(zeile, 'produktgruppe')),
                importiertAm: Value(jetzt),
              ),
            );
        uebernommen++;
      }
    });

    debugPrint(
      '[NAV] fertig — gelesen=$gelesen · uebernommen=$uebernommen · '
      'mitAuftrag=$mitAuftrag · Warnungen=${warnungen.length}',
    );

    return NavisionImportErgebnis(
      gelesen: gelesen,
      uebernommen: uebernommen,
      mitAuftrag: mitAuftrag,
      warnungen: warnungen,
    );
  }
}
