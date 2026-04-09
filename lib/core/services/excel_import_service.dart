import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../constants/abteilungen.dart';
import '../database/database.dart';

// ---------------------------------------------------------------------------
// Import-Ergebnis
// ---------------------------------------------------------------------------

/// Zusammenfassung eines Excel-Imports.
class ImportResult {
  final int artikelNeu;
  final int artikelAktualisiert;
  final int schritteImportiert;
  final int rezepturenImportiert;
  final int rohwarenImportiert;
  final List<String> warnungen;
  final List<String> fehler;

  const ImportResult({
    this.artikelNeu = 0,
    this.artikelAktualisiert = 0,
    this.schritteImportiert = 0,
    this.rezepturenImportiert = 0,
    this.rohwarenImportiert = 0,
    this.warnungen = const [],
    this.fehler = const [],
  });

  bool get hatFehler => fehler.isNotEmpty;
  int get artikelGesamt => artikelNeu + artikelAktualisiert;
}

/// Vorschau vor dem Import (Dry-Run).
class ImportPreview {
  final int artikelNeu;
  final int artikelAktualisiert;
  final int schritte;
  final int rezepturen;
  final int rohwaren;
  final List<String> warnungen;
  final List<String> fehler;

  const ImportPreview({
    this.artikelNeu = 0,
    this.artikelAktualisiert = 0,
    this.schritte = 0,
    this.rezepturen = 0,
    this.rohwaren = 0,
    this.warnungen = const [],
    this.fehler = const [],
  });

  bool get hatFehler => fehler.isNotEmpty;
  bool get istLeer =>
      artikelNeu == 0 &&
      artikelAktualisiert == 0 &&
      schritte == 0 &&
      rezepturen == 0 &&
      rohwaren == 0;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class ExcelImportService {
  ExcelImportService(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // ---- Öffentliche API ----

  /// Liest die Excel-Datei ein und gibt eine Vorschau zurück (ohne DB-Schreibung).
  Future<ImportPreview> preview(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return _previewFromBytes(bytes);
  }

  Future<ImportPreview> previewFromBytes(Uint8List bytes) async {
    return _previewFromBytes(bytes);
  }

  /// Importiert alle Sheets der Excel-Datei in die Datenbank.
  Future<ImportResult> importFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return _importFromBytes(bytes);
  }

  Future<ImportResult> importFromBytes(Uint8List bytes) async {
    return _importFromBytes(bytes);
  }

  // ---- Preview ----

  ImportPreview _previewFromBytes(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final warnungen = <String>[];
    final fehler = <String>[];

    int artikelNeu = 0;
    const int artikelAktualisiert = 0;

    // Sheet "Artikel" prüfen
    final artikelSheet = _findSheet(excel, ['artikel', 'products', 'stammdaten']);
    if (artikelSheet == null) {
      fehler.add('Kein Sheet "Artikel" gefunden.');
    }

    // Sheet "Schritte" prüfen
    final schritteSheet =
        _findSheet(excel, ['schritte', 'steps', 'produktionsschritte']);
    final schritteCount = schritteSheet != null
        ? (schritteSheet.rows.length - 1).clamp(0, 999999)
        : 0;
    if (schritteSheet == null) {
      warnungen.add('Kein Sheet "Schritte" gefunden — keine Schritte importiert.');
    }

    // Sheet "Rezeptur" prüfen
    final rezeptSheet = _findSheet(excel, ['rezeptur', 'rezepturen', 'bom']);
    final rezeptCount = rezeptSheet != null
        ? (rezeptSheet.rows.length - 1).clamp(0, 999999)
        : 0;
    if (rezeptSheet == null) {
      warnungen.add('Kein Sheet "Rezeptur" gefunden — keine Rezepturen importiert.');
    }

    // Sheet "Rohwaren" prüfen
    final rohwarenSheet =
        _findSheet(excel, ['rohwaren', 'raw_materials', 'rohstoffe']);
    final rohwarenCount = rohwarenSheet != null
        ? (rohwarenSheet.rows.length - 1).clamp(0, 999999)
        : 0;

    // Artikel zählen (würde existierende prüfen, aber für Preview reicht Zeilencount)
    if (artikelSheet != null) {
      artikelNeu = (artikelSheet.rows.length - 1).clamp(0, 999999);
    }

    return ImportPreview(
      artikelNeu: artikelNeu,
      artikelAktualisiert: artikelAktualisiert,
      schritte: schritteCount,
      rezepturen: rezeptCount,
      rohwaren: rohwarenCount,
      warnungen: warnungen,
      fehler: fehler,
    );
  }

  // ---- Import ----

  Future<ImportResult> _importFromBytes(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    final warnungen = <String>[];
    final fehler = <String>[];

    int artikelNeu = 0;
    int artikelAktualisiert = 0;
    int schritteImportiert = 0;
    int rezepturenImportiert = 0;
    int rohwarenImportiert = 0;

    // 1. Rohwaren zuerst (weil Rezeptur darauf referenziert)
    final rohwarenSheet =
        _findSheet(excel, ['rohwaren', 'raw_materials', 'rohstoffe']);
    if (rohwarenSheet != null) {
      rohwarenImportiert =
          await _importRohwaren(rohwarenSheet, warnungen, fehler);
    }

    // 2. Artikel
    final artikelSheet =
        _findSheet(excel, ['artikel', 'products', 'stammdaten']);
    if (artikelSheet != null) {
      final result =
          await _importArtikel(artikelSheet, warnungen, fehler);
      artikelNeu = result.$1;
      artikelAktualisiert = result.$2;
    } else {
      fehler.add('Kein Sheet "Artikel" gefunden — Abbruch.');
      return ImportResult(fehler: fehler);
    }

    // 3. Schritte
    final schritteSheet =
        _findSheet(excel, ['schritte', 'steps', 'produktionsschritte']);
    if (schritteSheet != null) {
      schritteImportiert =
          await _importSchritte(schritteSheet, warnungen, fehler);
    }

    // 4. Rezeptur
    final rezeptSheet = _findSheet(excel, ['rezeptur', 'rezepturen', 'bom']);
    if (rezeptSheet != null) {
      rezepturenImportiert =
          await _importRezeptur(rezeptSheet, warnungen, fehler);
    }

    return ImportResult(
      artikelNeu: artikelNeu,
      artikelAktualisiert: artikelAktualisiert,
      schritteImportiert: schritteImportiert,
      rezepturenImportiert: rezepturenImportiert,
      rohwarenImportiert: rohwarenImportiert,
      warnungen: warnungen,
      fehler: fehler,
    );
  }

  // ---- Sheet-Importer: Rohwaren ----

  Future<int> _importRohwaren(
    Sheet sheet,
    List<String> warn,
    List<String> err,
  ) async {
    final headers = _readHeaders(sheet);
    final nameCol = _findCol(headers, ['name', 'rohware', 'bezeichnung']);
    final einheitCol = _findCol(headers, ['einheit', 'unit']);
    final lieferantCol = _findCol(headers, ['lieferant', 'supplier']);
    final leadTimeCol = _findCol(headers, ['lieferzeit', 'lead_time', 'lieferzeit_tage']);
    final chargenCol =
        _findCol(headers, ['chargen_pflicht', 'chargenpflicht', 'haccp']);

    if (nameCol == null || einheitCol == null) {
      err.add('Rohwaren-Sheet: Spalte "Name" oder "Einheit" nicht gefunden.');
      return 0;
    }

    int count = 0;
    for (var row = 1; row < sheet.rows.length; row++) {
      final cells = sheet.rows[row];
      final name = _cellStr(cells, nameCol);
      if (name == null || name.isEmpty) continue;

      final einheit = _cellStr(cells, einheitCol) ?? 'kg';

      // Prüfen ob schon vorhanden
      final existing = await (_db.select(_db.rawMaterials)
            ..where((r) => r.name.equals(name))
            ..where((r) => r.deletedAt.isNull()))
          .getSingleOrNull();

      if (existing != null) {
        // Update
        await (_db.update(_db.rawMaterials)
              ..where((r) => r.id.equals(existing.id)))
            .write(RawMaterialsCompanion(
          einheit: Value(einheit),
          lieferant: Value(_cellStr(cells, lieferantCol)),
          leadTimeTage: Value(_cellInt(cells, leadTimeCol)),
          chargenPflicht:
              Value(_cellStr(cells, chargenCol)?.toLowerCase() == 'ja'),
          updatedAt: Value(DateTime.now()),
        ),);
      } else {
        // Insert
        await _db.into(_db.rawMaterials).insert(
              RawMaterialsCompanion.insert(
                id: _uuid.v4(),
                name: name,
                einheit: einheit,
                lieferant: Value(_cellStr(cells, lieferantCol)),
                leadTimeTage: Value(_cellInt(cells, leadTimeCol)),
                chargenPflicht:
                    Value(_cellStr(cells, chargenCol)?.toLowerCase() == 'ja'),
              ),
            );
      }
      count++;
    }
    return count;
  }

  // ---- Sheet-Importer: Artikel ----

  Future<(int, int)> _importArtikel(
    Sheet sheet,
    List<String> warn,
    List<String> err,
  ) async {
    final headers = _readHeaders(sheet);
    final nrCol = _findCol(headers, ['artikelnr', 'artikelnummer', 'nr', 'art_nr']);
    final bezCol = _findCol(headers, ['bezeichnung', 'artikelbezeichnung', 'name']);
    final beschCol = _findCol(headers, ['beschreibung', 'description']);
    final vpArtCol = _findCol(headers, ['verpackungsart', 'verpackung']);
    final gebindeCol = _findCol(headers, ['gebinde_kg', 'gebinde', 'gebindegroesse']);
    final mhdCol = _findCol(headers, ['mhd_tage', 'haltbarkeit', 'haltbarkeit_tage']);
    final ausbeuteCol =
        _findCol(headers, ['gesamtausbeute', 'ausbeute', 'ausbeute_faktor']);
    final vorlaufCol =
        _findCol(headers, ['vorlaufzeit', 'mindest_vorlaufzeit', 'vorlaufzeit_tage']);
    final gruppeCol = _findCol(headers, ['planungsgruppe', 'gruppe']);

    if (nrCol == null || bezCol == null) {
      err.add(
        'Artikel-Sheet: Spalte "Artikelnr" oder "Bezeichnung" nicht gefunden.',
      );
      return (0, 0);
    }

    int neu = 0;
    int aktualisiert = 0;
    for (var row = 1; row < sheet.rows.length; row++) {
      final cells = sheet.rows[row];
      final nr = _cellStr(cells, nrCol);
      final bez = _cellStr(cells, bezCol);
      if (nr == null || nr.isEmpty || bez == null || bez.isEmpty) continue;

      final existing = await (_db.select(_db.products)
            ..where((p) => p.artikelnummer.equals(nr))
            ..where((p) => p.deletedAt.isNull()))
          .getSingleOrNull();

      if (existing != null) {
        await (_db.update(_db.products)
              ..where((p) => p.id.equals(existing.id)))
            .write(ProductsCompanion(
          artikelbezeichnung: Value(bez),
          beschreibung: Value(_cellStr(cells, beschCol)),
          verpackungsart: Value(_cellStr(cells, vpArtCol)),
          gebindeGroesseKg: Value(_cellDouble(cells, gebindeCol)),
          haltbarkeitTage: Value(_cellInt(cells, mhdCol)),
          gesamtAusbeuteFaktor: Value(_cellDouble(cells, ausbeuteCol)),
          mindestVorlaufzeitTage: Value(_cellInt(cells, vorlaufCol)),
          planungsgruppe: Value(_cellStr(cells, gruppeCol)),
          updatedAt: Value(DateTime.now()),
        ),);
        aktualisiert++;
      } else {
        await _db.into(_db.products).insert(
              ProductsCompanion.insert(
                id: _uuid.v4(),
                artikelnummer: nr,
                artikelbezeichnung: bez,
                beschreibung: Value(_cellStr(cells, beschCol)),
                verpackungsart: Value(_cellStr(cells, vpArtCol)),
                gebindeGroesseKg: Value(_cellDouble(cells, gebindeCol)),
                haltbarkeitTage: Value(_cellInt(cells, mhdCol)),
                gesamtAusbeuteFaktor: Value(_cellDouble(cells, ausbeuteCol)),
                mindestVorlaufzeitTage: Value(_cellInt(cells, vorlaufCol)),
                planungsgruppe: Value(_cellStr(cells, gruppeCol)),
              ),
            );
        neu++;
      }
    }
    return (neu, aktualisiert);
  }

  // ---- Sheet-Importer: Schritte ----

  Future<int> _importSchritte(
    Sheet sheet,
    List<String> warn,
    List<String> err,
  ) async {
    final headers = _readHeaders(sheet);
    final nrCol = _findCol(headers, ['artikelnr', 'artikelnummer', 'art_nr']);
    final reihenfolgeCol = _findCol(headers, ['schritt', 'reihenfolge', 'step', 'nr']);
    final abtCol = _findCol(headers, ['abteilung', 'department']);
    final dauerCol = _findCol(headers, ['dauer', 'dauer_min', 'basis_dauer']);
    final fixzeitCol = _findCol(headers, ['fixzeit', 'fix_zeit', 'ruestzeit']);
    final mengCol = _findCol(headers, ['basis_menge', 'basismenge', 'basis_menge_kg']);
    final maCol = _findCol(headers, ['mitarbeiter', 'basis_mitarbeiter', 'ma']);
    final ausbeuteCol = _findCol(headers, ['ausbeute', 'ausbeute_faktor']);
    final wartezeitCol = _findCol(headers, ['wartezeit', 'wartezeit_min']);
    final minChargeCol = _findCol(headers, ['min_charge', 'min_chargen_kg']);
    final maxChargeCol = _findCol(headers, ['max_charge', 'max_chargen_kg']);
    final kerntempCol = _findCol(headers, ['kerntemperatur', 'kerntemp']);
    final raumtempCol = _findCol(headers, ['raumtemperatur', 'raumtemp']);
    final maschineCol = _findCol(headers, ['maschine', 'machine']);
    final einstellungenCol =
        _findCol(headers, ['einstellungen', 'maschineneinstellungen']);
    final notizenCol = _findCol(headers, ['notizen', 'notes']);

    if (nrCol == null || abtCol == null || dauerCol == null) {
      err.add(
        'Schritte-Sheet: Spalte "Artikelnr", "Abteilung" oder "Dauer" fehlt.',
      );
      return 0;
    }

    int count = 0;
    for (var row = 1; row < sheet.rows.length; row++) {
      final cells = sheet.rows[row];
      final artNr = _cellStr(cells, nrCol);
      if (artNr == null || artNr.isEmpty) continue;

      final abtStr = _cellStr(cells, abtCol);
      if (abtStr == null) continue;

      // Abteilung validieren
      Abteilung abt;
      try {
        abt = Abteilung.fromDbValue(abtStr.toLowerCase().replaceAll(' ', '_'));
      } catch (_) {
        // Fuzzy-Match: anzeigeName
        final match = Abteilung.values.where(
          (a) => a.anzeigeName.toLowerCase() == abtStr.toLowerCase(),
        );
        if (match.isEmpty) {
          warn.add('Zeile $row: Unbekannte Abteilung "$abtStr" — übersprungen.');
          continue;
        }
        abt = match.first;
      }

      // Produkt-ID auflösen
      final product = await (_db.select(_db.products)
            ..where((p) => p.artikelnummer.equals(artNr))
            ..where((p) => p.deletedAt.isNull()))
          .getSingleOrNull();
      if (product == null) {
        warn.add('Zeile $row: Artikel "$artNr" nicht gefunden — übersprungen.');
        continue;
      }

      final reihenfolge = _cellInt(cells, reihenfolgeCol) ?? (row);
      final basisMenge = _cellDouble(cells, mengCol) ?? 100.0;
      final dauer = _cellDouble(cells, dauerCol) ?? 0.0;
      final fixzeit = _cellDouble(cells, fixzeitCol);
      final ma = _cellInt(cells, maCol) ?? 1;

      // Existierenden Schritt suchen (gleiches Produkt + gleiche Reihenfolge)
      final existing = await (_db.select(_db.productSteps)
            ..where((s) => s.productId.equals(product.id))
            ..where((s) => s.reihenfolge.equals(reihenfolge))
            ..where((s) => s.deletedAt.isNull()))
          .getSingleOrNull();

      if (existing != null) {
        await (_db.update(_db.productSteps)
              ..where((s) => s.id.equals(existing.id)))
            .write(ProductStepsCompanion(
          abteilung: Value(abt.dbValue),
          basisMengeKg: Value(basisMenge),
          basisDauerMinuten: Value(dauer),
          fixZeitMinuten: Value(fixzeit),
          basisMitarbeiter: Value(ma),
          ausbeuteFaktor: Value(_cellDouble(cells, ausbeuteCol)),
          wartezeitMinuten: Value(_cellDouble(cells, wartezeitCol)),
          minChargenKg: Value(_cellDouble(cells, minChargeCol)),
          maxChargenKg: Value(_cellDouble(cells, maxChargeCol)),
          kerntemperaturZiel: Value(_cellDouble(cells, kerntempCol)),
          raumtemperaturMax: Value(_cellDouble(cells, raumtempCol)),
          maschine: Value(_cellStr(cells, maschineCol)),
          maschinenEinstellungenJson:
              Value(_cellStr(cells, einstellungenCol)),
          notizen: Value(_cellStr(cells, notizenCol)),
          updatedAt: Value(DateTime.now()),
        ),);
      } else {
        await _db.into(_db.productSteps).insert(
              ProductStepsCompanion.insert(
                id: _uuid.v4(),
                productId: product.id,
                reihenfolge: reihenfolge,
                abteilung: abt.dbValue,
                basisMengeKg: basisMenge,
                basisDauerMinuten: dauer,
                fixZeitMinuten: Value(fixzeit),
                basisMitarbeiter: ma,
                ausbeuteFaktor: Value(_cellDouble(cells, ausbeuteCol)),
                wartezeitMinuten: Value(_cellDouble(cells, wartezeitCol)),
                minChargenKg: Value(_cellDouble(cells, minChargeCol)),
                maxChargenKg: Value(_cellDouble(cells, maxChargeCol)),
                kerntemperaturZiel: Value(_cellDouble(cells, kerntempCol)),
                raumtemperaturMax: Value(_cellDouble(cells, raumtempCol)),
                maschine: Value(_cellStr(cells, maschineCol)),
                maschinenEinstellungenJson:
                    Value(_cellStr(cells, einstellungenCol)),
                notizen: Value(_cellStr(cells, notizenCol)),
              ),
            );
      }
      count++;
    }
    return count;
  }

  // ---- Sheet-Importer: Rezeptur ----

  Future<int> _importRezeptur(
    Sheet sheet,
    List<String> warn,
    List<String> err,
  ) async {
    final headers = _readHeaders(sheet);
    final artNrCol = _findCol(headers, ['artikelnr', 'artikelnummer', 'art_nr']);
    final rohwareCol = _findCol(headers, ['rohware', 'rohstoff', 'name']);
    final mengeCol = _findCol(headers, ['menge_pro_kg', 'menge', 'mengeprokg']);
    final toleranzCol = _findCol(headers, ['toleranz', 'toleranz_prozent']);

    if (artNrCol == null || rohwareCol == null || mengeCol == null) {
      err.add(
        'Rezeptur-Sheet: Spalte "Artikelnr", "Rohware" oder "Menge" fehlt.',
      );
      return 0;
    }

    int count = 0;
    for (var row = 1; row < sheet.rows.length; row++) {
      final cells = sheet.rows[row];
      final artNr = _cellStr(cells, artNrCol);
      final rohwareName = _cellStr(cells, rohwareCol);
      if (artNr == null || rohwareName == null) continue;

      final menge = _cellDouble(cells, mengeCol);
      if (menge == null || menge <= 0) {
        warn.add('Zeile $row: Ungültige Menge — übersprungen.');
        continue;
      }

      // Produkt auflösen
      final product = await (_db.select(_db.products)
            ..where((p) => p.artikelnummer.equals(artNr))
            ..where((p) => p.deletedAt.isNull()))
          .getSingleOrNull();
      if (product == null) {
        warn.add(
          'Zeile $row: Artikel "$artNr" nicht gefunden — übersprungen.',
        );
        continue;
      }

      // Rohware auflösen
      final rohware = await (_db.select(_db.rawMaterials)
            ..where((r) => r.name.equals(rohwareName))
            ..where((r) => r.deletedAt.isNull()))
          .getSingleOrNull();
      if (rohware == null) {
        warn.add(
          'Zeile $row: Rohware "$rohwareName" nicht gefunden — übersprungen.',
        );
        continue;
      }

      // Existierenden Eintrag prüfen
      final existing = await (_db.select(_db.productRawMaterials)
            ..where((r) => r.productId.equals(product.id))
            ..where((r) => r.rawMaterialId.equals(rohware.id))
            ..where((r) => r.deletedAt.isNull()))
          .getSingleOrNull();

      if (existing != null) {
        await (_db.update(_db.productRawMaterials)
              ..where((r) => r.id.equals(existing.id)))
            .write(ProductRawMaterialsCompanion(
          mengeProKgProdukt: Value(menge),
          toleranzProzent: Value(_cellDouble(cells, toleranzCol)),
          updatedAt: Value(DateTime.now()),
        ),);
      } else {
        await _db.into(_db.productRawMaterials).insert(
              ProductRawMaterialsCompanion.insert(
                id: _uuid.v4(),
                productId: product.id,
                rawMaterialId: rohware.id,
                mengeProKgProdukt: menge,
                toleranzProzent: Value(_cellDouble(cells, toleranzCol)),
              ),
            );
      }
      count++;
    }
    return count;
  }

  // ---- Hilfsfunktionen ----

  /// Sucht ein Sheet per Name (case-insensitive, mehrere Aliase).
  Sheet? _findSheet(Excel excel, List<String> names) {
    for (final table in excel.tables.keys) {
      final lower = table.toLowerCase().trim();
      for (final name in names) {
        if (lower == name) return excel.tables[table];
      }
    }
    return null;
  }

  /// Liest die Kopfzeile und gibt eine Map { lower_name: col_index } zurück.
  Map<String, int> _readHeaders(Sheet sheet) {
    final headers = <String, int>{};
    if (sheet.rows.isEmpty) return headers;
    final row = sheet.rows[0];
    for (var i = 0; i < row.length; i++) {
      final val = row[i]?.value?.toString().trim().toLowerCase();
      if (val != null && val.isNotEmpty) {
        // Leerzeichen und Sonderzeichen normalisieren
        headers[val.replaceAll(' ', '_').replaceAll('-', '_')] = i;
      }
    }
    return headers;
  }

  /// Findet eine Spalte anhand einer Liste von möglichen Headern.
  int? _findCol(Map<String, int> headers, List<String> aliases) {
    for (final alias in aliases) {
      if (headers.containsKey(alias)) return headers[alias];
    }
    return null;
  }

  String? _cellStr(List<Data?> cells, int? col) {
    if (col == null || col >= cells.length) return null;
    final val = cells[col]?.value;
    if (val == null) return null;
    final s = val.toString().trim();
    return s.isEmpty ? null : s;
  }

  double? _cellDouble(List<Data?> cells, int? col) {
    if (col == null || col >= cells.length) return null;
    final val = cells[col]?.value;
    if (val == null) return null;
    if (val is DoubleCellValue) return val.value;
    if (val is IntCellValue) return val.value.toDouble();
    final s = val.toString().trim().replaceAll(',', '.');
    return double.tryParse(s);
  }

  int? _cellInt(List<Data?> cells, int? col) {
    if (col == null || col >= cells.length) return null;
    final val = cells[col]?.value;
    if (val == null) return null;
    if (val is IntCellValue) return val.value;
    if (val is DoubleCellValue) return val.value.toInt();
    final s = val.toString().trim();
    return int.tryParse(s);
  }
}
