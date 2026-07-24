import 'dart:io';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart';

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

  /// Erwartete Überschriften → Feldname. Kleingeschrieben und ohne
  /// Sonderzeichen verglichen, damit „Nr." und „Nr" beide passen.
  static const Map<String, String> _spalten = {
    'lagerbestand': 'lagerbestand',
    'nummer2': 'nummer2',
    'nr': 'nummer',
    'beschreibung': 'beschreibung',
    'beschreibung2': 'beschreibung2',
    'suchbegriff': 'suchbegriff',
    'plucode': 'pluCode',
    'fertstuecklistennr': 'stuecklistenNr',
    'basiseinheitencode': 'basiseinheit',
    'mengeinfa': 'mengeInFa',
    'mengeinauftrag': 'mengeInAuftrag',
    'produktbuchungsgruppe': 'produktbuchungsgruppe',
    'artikelkategoriencode': 'artikelkategorie',
    'produktgruppencode': 'produktgruppe',
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

  Future<NavisionImportErgebnis> importiere(String dateipfad) async {
    final bytes = await File(dateipfad).readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final warnungen = <String>[];

    final sheetName = excel.tables.keys.first;
    final tabelle = excel.tables[sheetName];
    if (tabelle == null || tabelle.rows.isEmpty) {
      throw Exception('Die Datei enthält keine Daten.');
    }

    // Kopfzeile suchen: die Zeile, in der „Nr." und „Beschreibung" stehen.
    int? kopfZeile;
    for (var r = 0; r < tabelle.rows.length && r < 20; r++) {
      final werte = tabelle.rows[r].map((c) => _norm(_text(c) ?? '')).toList();
      if (werte.contains('nr') && werte.contains('beschreibung')) {
        kopfZeile = r;
        break;
      }
    }
    if (kopfZeile == null) {
      throw Exception(
        'Kopfzeile nicht gefunden — erwartet werden die Spalten '
        '„Nr." und „Beschreibung".',
      );
    }

    // Spaltenzuordnung aufbauen.
    final spalteVon = <String, int>{};
    final kopf = tabelle.rows[kopfZeile];
    for (var c = 0; c < kopf.length; c++) {
      final feld = _spalten[_norm(_text(kopf[c]) ?? '')];
      if (feld != null) spalteVon[feld] = c;
    }
    if (!spalteVon.containsKey('nummer')) {
      throw Exception('Spalte „Nr." fehlt.');
    }
    for (final pflicht in ['mengeInAuftrag', 'lagerbestand']) {
      if (!spalteVon.containsKey(pflicht)) {
        warnungen.add(
          'Spalte für „$pflicht" nicht gefunden — Bedarfsrechnung '
          'ist dadurch unvollständig.',
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

    return NavisionImportErgebnis(
      gelesen: gelesen,
      uebernommen: uebernommen,
      mitAuftrag: mitAuftrag,
      warnungen: warnungen,
    );
  }
}
