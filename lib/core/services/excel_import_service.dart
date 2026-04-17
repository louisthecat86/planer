import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../constants/abteilungen.dart';
import '../constants/product_group_fields.dart';
import '../constants/product_groups.dart';
import '../database/database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Ergebnis-Klassen
// ═══════════════════════════════════════════════════════════════════════════

/// Zusammenfassung eines Excel-Imports.
class ImportResult {
  const ImportResult({
    this.artikelNeu = 0,
    this.artikelAktualisiert = 0,
    this.schritteImportiert = 0,
    this.rezepturenImportiert = 0,
    this.rohwarenImportiert = 0,
    this.historienVerarbeitet = 0,
    this.warnungen = const [],
    this.fehler = const [],
  });

  final int artikelNeu;
  final int artikelAktualisiert;
  final int schritteImportiert;
  final int rezepturenImportiert;
  final int rohwarenImportiert;
  final int historienVerarbeitet;
  final List<String> warnungen;
  final List<String> fehler;

  bool get hatFehler => fehler.isNotEmpty;
  int get artikelGesamt => artikelNeu + artikelAktualisiert;
}

/// Vorschau vor dem Import (Dry-Run).
class ImportPreview {
  const ImportPreview({
    this.artikelNeu = 0,
    this.artikelAktualisiert = 0,
    this.schritte = 0,
    this.rezepturen = 0,
    this.rohwaren = 0,
    this.historien = 0,
    this.warnungen = const [],
    this.fehler = const [],
  });

  final int artikelNeu;
  final int artikelAktualisiert;
  final int schritte;
  final int rezepturen;
  final int rohwaren;
  final int historien;
  final List<String> warnungen;
  final List<String> fehler;

  bool get hatFehler => fehler.isNotEmpty;
  bool get istLeer =>
      artikelNeu == 0 &&
      artikelAktualisiert == 0 &&
      schritte == 0 &&
      rezepturen == 0 &&
      rohwaren == 0 &&
      historien == 0;
}

/// Ein einzelner Validierungsfehler mit präziser Verortung.
class _ValidationError {
  const _ValidationError({
    required this.sheet,
    required this.artikelnr,
    required this.feld,
    required this.grund,
  });

  final String sheet;
  final String artikelnr;
  final String feld;
  final String grund;

  @override
  String toString() =>
      'Sheet "$sheet" ($artikelnr): Feld "$feld" — $grund';
}

// ═══════════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════════

class ExcelImportService {
  ExcelImportService(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // ─── Öffentliche API ──────────────────────────────────────────────────

  /// Liest die Excel-Datei und liefert eine Vorschau (ohne DB-Schreibung).
  Future<ImportPreview> preview(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return _previewFromBytes(bytes);
  }

  Future<ImportPreview> previewFromBytes(Uint8List bytes) async {
    return _previewFromBytes(bytes);
  }

  /// Importiert alle Sheets der Excel-Datei in die Datenbank.
  ///
  /// Die Validierung ist **zweistufig**:
  ///   1. Alle Sheets werden geparst und validiert — Fehler gesammelt
  ///   2. Nur wenn ZERO Fehler auftreten, wird geschrieben (transaktional)
  ///
  /// Bei Validierungsfehlern wird nichts geschrieben, das [ImportResult]
  /// enthält die vollständige Fehlerliste zum Beheben.
  Future<ImportResult> importFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return _importFromBytes(bytes);
  }

  Future<ImportResult> importFromBytes(Uint8List bytes) async {
    return _importFromBytes(bytes);
  }

  // ─── Preview ──────────────────────────────────────────────────────────

  ImportPreview _previewFromBytes(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final warnungen = <String>[];
    final fehler = <String>[];

    final uebersichtSheet =
        _findSheet(excel, ['übersicht', 'uebersicht', 'overview']);
    if (uebersichtSheet == null) {
      fehler.add(
        'Kein Sheet "Übersicht" gefunden. Bitte neue Vorlage aus der App '
        'erzeugen (Template-Export).',
      );
      return ImportPreview(fehler: fehler);
    }

    // Rohwaren
    final rohwarenSheet =
        _findSheet(excel, ['rohwaren', 'raw_materials', 'rohstoffe']);
    final rohwarenCount = rohwarenSheet != null
        ? (rohwarenSheet.rows.length - 1).clamp(0, 999999)
        : 0;

    // Artikel aus Übersicht
    int artikelCount = 0;
    int schritteCount = 0;
    int rezeptCount = 0;
    int historienCount = 0;

    for (var row = 1; row < uebersichtSheet.rows.length; row++) {
      final cells = uebersichtSheet.rows[row];
      final artNr = _cellStr(cells, 0);
      final bez = _cellStr(cells, 1);
      if (artNr == null || artNr.isEmpty) continue;
      artikelCount++;

      final produktSheet = _findProduktSheet(excel, artNr, bez);
      if (produktSheet == null) {
        warnungen.add('Kein Produkt-Sheet für "$artNr" gefunden.');
        continue;
      }

      final sections = _parseSheetSections(produktSheet);
      schritteCount += sections.schritteDataRows;
      rezeptCount += sections.rezepturDataRows;
      historienCount += sections.historieDataRows;
    }

    return ImportPreview(
      artikelNeu: artikelCount,
      schritte: schritteCount,
      rezepturen: rezeptCount,
      rohwaren: rohwarenCount,
      historien: historienCount,
      warnungen: warnungen,
      fehler: fehler,
    );
  }

  // ─── Import (zweistufig: Validate → Write) ────────────────────────────

  Future<ImportResult> _importFromBytes(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    final warnungen = <String>[];
    final fehler = <String>[];
    final validationErrors = <_ValidationError>[];

    // ── Phase 1: Übersicht-Sheet finden ───────────────────────────────
    final uebersichtSheet =
        _findSheet(excel, ['übersicht', 'uebersicht', 'overview']);
    if (uebersichtSheet == null) {
      fehler.add(
        'Kein Sheet "Übersicht" gefunden. Bitte neue Vorlage aus der App '
        'erzeugen (Template-Export).',
      );
      return ImportResult(fehler: fehler);
    }

    // ── Phase 2: Alle Produkt-Sheets parsen und validieren ────────────
    final geparseProdukte = <_ParsedProduct>[];

    for (var row = 1; row < uebersichtSheet.rows.length; row++) {
      final cells = uebersichtSheet.rows[row];
      final artNr = _cellStr(cells, 0);
      final bez = _cellStr(cells, 1);
      if (artNr == null || artNr.isEmpty) continue;

      final produktSheet = _findProduktSheet(excel, artNr, bez);
      if (produktSheet == null) {
        warnungen.add(
          'Übersichtszeile ${row + 1}: Kein Produkt-Sheet für "$artNr" — '
          'übersprungen.',
        );
        continue;
      }

      final parsed = _parseAndValidateProduct(
        produktSheet,
        artNr,
        validationErrors,
      );
      if (parsed != null) geparseProdukte.add(parsed);
    }

    // ── Phase 3: Bei Validierungsfehlern → Abbruch ohne Schreibung ────
    if (validationErrors.isNotEmpty) {
      for (final err in validationErrors) {
        fehler.add(err.toString());
      }
      fehler.insert(
        0,
        '${validationErrors.length} Validierungsfehler — Import abgebrochen, '
        'nichts geschrieben. Bitte Pflichtfelder ergänzen und erneut importieren.',
      );
      return ImportResult(fehler: fehler, warnungen: warnungen);
    }

    // ── Phase 4: Transaktionales Schreiben ────────────────────────────
    int artikelNeu = 0;
    int artikelAktualisiert = 0;
    int schritteImportiert = 0;
    int rezepturenImportiert = 0;
    int rohwarenImportiert = 0;
    int historienVerarbeitet = 0;

    try {
      await _db.transaction(() async {
        // Rohwaren zuerst (FK-Reihenfolge)
        final rohwarenSheet =
            _findSheet(excel, ['rohwaren', 'raw_materials', 'rohstoffe']);
        if (rohwarenSheet != null) {
          rohwarenImportiert = await _importRohwaren(rohwarenSheet, warnungen);
        }

        // Alle Produkte schreiben
        for (final p in geparseProdukte) {
          final isNew = await _writeProduct(p, warnungen);
          if (isNew) {
            artikelNeu++;
          } else {
            artikelAktualisiert++;
          }

          schritteImportiert += await _writeSchritte(p, warnungen);
          rezepturenImportiert += await _writeRezeptur(p, warnungen);
          historienVerarbeitet += await _writeHistorie(p, warnungen);
        }
      });
    } catch (e) {
      fehler.add('Datenbank-Fehler während Import: $e');
      return ImportResult(fehler: fehler, warnungen: warnungen);
    }

    return ImportResult(
      artikelNeu: artikelNeu,
      artikelAktualisiert: artikelAktualisiert,
      schritteImportiert: schritteImportiert,
      rezepturenImportiert: rezepturenImportiert,
      rohwarenImportiert: rohwarenImportiert,
      historienVerarbeitet: historienVerarbeitet,
      warnungen: warnungen,
      fehler: fehler,
    );
  }

  // ─── Produkt-Sheet parsen + validieren ────────────────────────────────

  /// Parst ein Produkt-Sheet. Fehler werden in [errors] gesammelt.
  /// Returns null wenn das Sheet gar nicht geparst werden konnte (z.B.
  /// Stammdaten-Sektion fehlt).
  _ParsedProduct? _parseAndValidateProduct(
    Sheet sheet,
    String artNrExpected,
    List<_ValidationError> errors,
  ) {
    final sections = _parseSheetSections(sheet);
    final sheetName = sheet.sheetName;

    if (sections.stammdatenHeaderRow == null) {
      errors.add(_ValidationError(
        sheet: sheetName,
        artikelnr: artNrExpected,
        feld: 'Stammdaten-Block',
        grund: 'Marker "== STAMMDATEN ==" nicht gefunden',
      ));
      return null;
    }

    // Label-Zeile (Header) → Spaltenindex
    final labelCols = <String, int>{};
    final headerCells = sheet.rows[sections.stammdatenHeaderRow!];
    for (var i = 0; i < headerCells.length; i++) {
      final label = _cellStr(headerCells, i);
      if (label != null && label.isNotEmpty) {
        labelCols[label] = i;
      }
    }

    // Datenzeile: Header + 2 (Header + Einheiten + Daten)
    // Falls Nutzer alte Vorlage hat (keine Einheiten-Zeile): fallback auf +1
    final datenRow = sections.stammdatenHeaderRow! + 2;
    final datenRowAlt = sections.stammdatenHeaderRow! + 1;

    if (datenRow >= sheet.rows.length) {
      errors.add(_ValidationError(
        sheet: sheetName,
        artikelnr: artNrExpected,
        feld: 'Datenzeile',
        grund: 'Keine Datenzeile unter Stammdaten-Header',
      ));
      return null;
    }

    final datenCells = sheet.rows[datenRow];

    // Heuristik für altes Format (ohne Einheiten-Zeile):
    // Wenn die Zeile direkt unter dem Header eine Artikelnummer enthält,
    // ist es das alte Format.
    List<Data?> effektiveDaten = datenCells;
    final artNrColFromLabels = labelCols['Artikelnr'];
    if (artNrColFromLabels != null) {
      final altDatenCells = datenRowAlt < sheet.rows.length
          ? sheet.rows[datenRowAlt]
          : <Data?>[];
      final artNrNeuFormat = _cellStr(datenCells, artNrColFromLabels);
      final artNrAltFormat = _cellStr(altDatenCells, artNrColFromLabels);
      if ((artNrNeuFormat == null || artNrNeuFormat.isEmpty) &&
          artNrAltFormat != null &&
          artNrAltFormat.isNotEmpty) {
        // Altes Format erkannt — Daten stehen eine Zeile höher
        effektiveDaten = altDatenCells;
      }
    }

    // Produktgruppe lesen — Pflicht
    final gruppeCol = labelCols['Produktgruppe'];
    if (gruppeCol == null) {
      errors.add(_ValidationError(
        sheet: sheetName,
        artikelnr: artNrExpected,
        feld: 'Produktgruppe',
        grund: 'Spalte "Produktgruppe" fehlt im Stammdaten-Header',
      ));
      return null;
    }
    final gruppeStr = _cellStr(effektiveDaten, gruppeCol);
    if (gruppeStr == null || gruppeStr.isEmpty) {
      errors.add(_ValidationError(
        sheet: sheetName,
        artikelnr: artNrExpected,
        feld: 'Produktgruppe',
        grund: 'Pflichtfeld leer',
      ));
      return null;
    }
    final gruppe = ProductGroup.tryFromAnyString(gruppeStr);
    if (gruppe == null) {
      errors.add(_ValidationError(
        sheet: sheetName,
        artikelnr: artNrExpected,
        feld: 'Produktgruppe',
        grund: 'Unbekannter Wert "$gruppeStr" — erlaubt sind: '
            '${ProductGroup.values.map((g) => g.label).join(", ")}',
      ));
      return null;
    }

    // Alle Felder für diese Gruppe extrahieren und validieren
    final felder = ProductGroupFields.alleFelderFuer(gruppe);
    final werte = <String, Object?>{}; // FieldSpec.key → typisierter Wert

    for (final field in felder) {
      final col = labelCols[field.label];
      if (col == null) {
        if (field.required) {
          errors.add(_ValidationError(
            sheet: sheetName,
            artikelnr: artNrExpected,
            feld: field.label,
            grund: 'Pflicht-Spalte fehlt im Stammdaten-Header',
          ));
        }
        continue;
      }

      final rawValue = _cellStr(effektiveDaten, col);
      if (rawValue == null || rawValue.isEmpty) {
        if (field.required) {
          errors.add(_ValidationError(
            sheet: sheetName,
            artikelnr: artNrExpected,
            feld: field.label,
            grund: 'Pflichtfeld leer',
          ));
        }
        continue;
      }

      // Typ-Validierung + Konvertierung
      final converted = _convertValue(field, rawValue);
      if (converted.error != null) {
        errors.add(_ValidationError(
          sheet: sheetName,
          artikelnr: artNrExpected,
          feld: field.label,
          grund: converted.error!,
        ));
        continue;
      }
      werte[field.key] = converted.value;
    }

    // Artikelnr konsistent mit Übersicht?
    final artNrImSheet = werte['artikelnummer'] as String?;
    if (artNrImSheet != null && artNrImSheet != artNrExpected) {
      errors.add(_ValidationError(
        sheet: sheetName,
        artikelnr: artNrExpected,
        feld: 'Artikelnr',
        grund: 'Artikelnr im Sheet ("$artNrImSheet") stimmt nicht mit '
            'Übersichtseintrag ("$artNrExpected") überein',
      ));
    }

    return _ParsedProduct(
      sheet: sheet,
      sheetName: sheetName,
      artikelnr: artNrExpected,
      gruppe: gruppe,
      werte: werte,
      sections: sections,
    );
  }

  // ─── Value Conversion (mit Typprüfung) ────────────────────────────────

  _ConversionResult _convertValue(FieldSpec field, String raw) {
    final trimmed = raw.trim();

    switch (field.type) {
      case FieldType.text:
        return _ConversionResult.ok(trimmed);

      case FieldType.number:
        final normalized = trimmed.replaceAll(',', '.');
        final num = double.tryParse(normalized);
        if (num == null) {
          return _ConversionResult.err('Ungültige Zahl: "$raw"');
        }
        if (field.minValue != null && num < field.minValue!) {
          return _ConversionResult.err(
            'Wert $num unter Minimum ${field.minValue}',
          );
        }
        if (field.maxValue != null && num > field.maxValue!) {
          return _ConversionResult.err(
            'Wert $num über Maximum ${field.maxValue}',
          );
        }
        return _ConversionResult.ok(num);

      case FieldType.boolean:
        final lower = trimmed.toLowerCase();
        if (['ja', 'yes', 'true', '1', 'x'].contains(lower)) {
          return _ConversionResult.ok(true);
        }
        if (['nein', 'no', 'false', '0', ''].contains(lower)) {
          return _ConversionResult.ok(false);
        }
        return _ConversionResult.err('Ungültiger Ja/Nein-Wert: "$raw"');

      case FieldType.enumValue:
        final allowed = field.enumValues ?? const [];
        // Exakter Match oder case-insensitive
        final match = allowed.firstWhere(
          (v) => v.toLowerCase() == trimmed.toLowerCase(),
          orElse: () => '',
        );
        if (match.isEmpty) {
          return _ConversionResult.err(
            'Ungültiger Wert "$raw" — erlaubt: ${allowed.join(", ")}',
          );
        }
        return _ConversionResult.ok(match);
    }
  }

  // ─── DB-Write: Produkt ────────────────────────────────────────────────

  /// Returns true wenn neu angelegt, false wenn aktualisiert.
  Future<bool> _writeProduct(
    _ParsedProduct p,
    List<String> warnungen,
  ) async {
    final werte = p.werte;
    final artikelnummer = werte['artikelnummer'] as String;
    final bezeichnung = werte['artikelbezeichnung'] as String;

    final existing = await (_db.select(_db.products)
          ..where((t) => t.artikelnummer.equals(artikelnummer))
          ..where((t) => t.deletedAt.isNull()))
        .getSingleOrNull();

    final bool isNew = existing == null;
    final String productId = existing?.id ?? _uuid.v4();

    // Grunddaten via Companion (typsicher)
    if (isNew) {
      await _db.into(_db.products).insert(ProductsCompanion.insert(
            id: productId,
            artikelnummer: artikelnummer,
            artikelbezeichnung: bezeichnung,
            beschreibung: Value(werte['beschreibung'] as String?),
            produktgruppe: Value(p.gruppe.dbValue),
          ));
    } else {
      await (_db.update(_db.products)
            ..where((t) => t.id.equals(productId)))
          .write(ProductsCompanion(
        artikelbezeichnung: Value(bezeichnung),
        beschreibung: Value(werte['beschreibung'] as String?),
        produktgruppe: Value(p.gruppe.dbValue),
        updatedAt: Value(DateTime.now()),
      ));
    }

    // Alle weiteren Felder via einzelne UPDATEs auf die dbColumn-Namen.
    // Das erspart einen riesigen typsicheren Companion-Switch und bleibt
    // wartbar, wenn neue Felder dazukommen.
    final felder = ProductGroupFields.alleFelderFuer(p.gruppe);
    for (final field in felder) {
      if (field.key == 'artikelnummer' ||
          field.key == 'artikelbezeichnung' ||
          field.key == 'beschreibung' ||
          field.key == 'produktgruppe') {
        continue; // bereits geschrieben
      }
      if (!werte.containsKey(field.key)) continue;

      final rawValue = werte[field.key];
      final dbValue = _mapToDbValue(field, rawValue);

      await _db.customStatement(
        'UPDATE products SET ${field.dbColumn} = ?, updated_at = ? WHERE id = ?',
        [dbValue, DateTime.now().toIso8601String(), productId],
      );
    }

    // Aufschnitt-Spezialfall: Basis-Artikelnr-Check
    if (p.gruppe == ProductGroup.aufschnitt) {
      final basisNr = werte['basis_produkt_artikelnr'] as String?;
      if (basisNr != null && basisNr.isNotEmpty) {
        final basis = await (_db.select(_db.products)
              ..where((t) => t.artikelnummer.equals(basisNr))
              ..where((t) => t.deletedAt.isNull()))
            .getSingleOrNull();
        if (basis == null) {
          warnungen.add(
            'Aufschnitt "$artikelnummer" verweist auf Basis-Artikelnr '
            '"$basisNr" — diese existiert nicht in der DB. Verweis bleibt '
            'bestehen, kann später aufgelöst werden.',
          );
        }
      }
    }

    // productId zurücklegen für Schritte/Rezeptur/Historie
    p.productId = productId;
    return isNew;
  }

  /// Konvertiert einen typisierten Wert in den DB-tauglichen Typ.
  Object? _mapToDbValue(FieldSpec field, Object? value) {
    if (value == null) return null;
    switch (field.type) {
      case FieldType.number:
        // Für INTEGER-Spalten ggf. runden. Wir wissen nicht aus dem FieldSpec
        // ob die DB-Spalte INT oder REAL ist — SQLite akzeptiert beides
        // kulant (dynamic typing). Dennoch: für Tage/Stk-Felder integer casten.
        if (field.fractionDigits == 0 && value is double) {
          return value.round();
        }
        return value;
      case FieldType.boolean:
        return (value as bool) ? 1 : 0;
      case FieldType.text:
      case FieldType.enumValue:
        return value as String;
    }
  }

  // ─── DB-Write: Schritte ───────────────────────────────────────────────

  Future<int> _writeSchritte(
    _ParsedProduct p,
    List<String> warnungen,
  ) async {
    final sections = p.sections;
    if (sections.schritteHeaderRow == null) return 0;
    final productId = p.productId!;
    final sheet = p.sheet;

    final headerRow = sections.schritteHeaderRow!;
    final startRow = headerRow + 2; // Header + Einheiten
    final endRow = sections.schritteEndRow;

    final labelCols = _readHeaderCols(sheet, headerRow);
    final reihenfolgeCol = _findCol(labelCols, ['schritt', 'reihenfolge', 'step', 'nr']);
    final abtCol = _findCol(labelCols, ['abteilung', 'department']);
    final dauerCol = _findCol(labelCols, ['dauer', 'dauer_min', 'basis_dauer']);
    final fixzeitCol = _findCol(labelCols, ['fixzeit', 'fix_zeit', 'ruestzeit']);
    final mengCol = _findCol(labelCols, ['basis_menge', 'basismenge', 'basis_menge_kg']);
    final maCol = _findCol(labelCols, ['mitarbeiter', 'basis_mitarbeiter', 'ma']);
    final ausbeuteCol = _findCol(labelCols, ['ausbeute', 'ausbeute_faktor']);
    final wartezeitCol = _findCol(labelCols, ['wartezeit', 'wartezeit_min']);
    final minChargeCol = _findCol(labelCols, ['min_charge', 'min_chargen_kg']);
    final maxChargeCol = _findCol(labelCols, ['max_charge', 'max_chargen_kg']);
    final kerntempCol = _findCol(labelCols, ['kerntemperatur', 'kerntemp']);
    final raumtempCol = _findCol(labelCols, ['raumtemperatur', 'raumtemp']);
    final maschineCol = _findCol(labelCols, ['maschine', 'machine']);
    final kochkammerCol = _findCol(labelCols, ['kochkammer_programm', 'kochkammer']);
    final klimaCol = _findCol(labelCols, ['klimaprogramm', 'klima']);
    final bratparamCol = _findCol(labelCols, ['bratparameter', 'brat_parameter']);
    final notizenCol = _findCol(labelCols, ['notizen', 'notes']);

    if (abtCol == null || dauerCol == null) return 0;

    int count = 0;
    int autoReihenfolge = 1;
    for (var row = startRow; row < endRow && row < sheet.rows.length; row++) {
      final cells = sheet.rows[row];
      final abtStr = _cellStr(cells, abtCol);
      if (abtStr == null || abtStr.isEmpty) continue;

      Abteilung? abt;
      try {
        abt = Abteilung.fromDbValue(abtStr.toLowerCase().replaceAll(' ', '_'));
      } catch (_) {
        final match = Abteilung.values.where(
          (a) => a.anzeigeName.toLowerCase() == abtStr.toLowerCase(),
        );
        if (match.isNotEmpty) abt = match.first;
      }
      if (abt == null) {
        warnungen.add(
          'Produkt ${p.artikelnr}: Unbekannte Abteilung "$abtStr" in Schritt-'
          'Zeile ${row + 1} — übersprungen.',
        );
        continue;
      }

      final reihenfolge = _cellInt(cells, reihenfolgeCol) ?? autoReihenfolge;
      autoReihenfolge = reihenfolge + 1;
      final basisMenge = _cellDouble(cells, mengCol) ?? 100.0;
      final dauer = _cellDouble(cells, dauerCol) ?? 0.0;
      final fixzeit = _cellDouble(cells, fixzeitCol);
      final ma = _cellInt(cells, maCol) ?? 1;

      final existing = await (_db.select(_db.productSteps)
            ..where((s) => s.productId.equals(productId))
            ..where((s) => s.reihenfolge.equals(reihenfolge))
            ..where((s) => s.deletedAt.isNull()))
          .getSingleOrNull();

      final companion = ProductStepsCompanion(
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
        kochkammerProgramm: Value(_cellStr(cells, kochkammerCol)),
        klimaprogramm: Value(_cellStr(cells, klimaCol)),
        bratparameter: Value(_cellStr(cells, bratparamCol)),
        notizen: Value(_cellStr(cells, notizenCol)),
        updatedAt: Value(DateTime.now()),
      );

      if (existing != null) {
        await (_db.update(_db.productSteps)
              ..where((s) => s.id.equals(existing.id)))
            .write(companion);
      } else {
        await _db.into(_db.productSteps).insert(ProductStepsCompanion.insert(
              id: _uuid.v4(),
              productId: productId,
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
              kochkammerProgramm: Value(_cellStr(cells, kochkammerCol)),
              klimaprogramm: Value(_cellStr(cells, klimaCol)),
              bratparameter: Value(_cellStr(cells, bratparamCol)),
              notizen: Value(_cellStr(cells, notizenCol)),
            ));
      }
      count++;
    }
    return count;
  }

  // ─── DB-Write: Rezeptur ───────────────────────────────────────────────

  Future<int> _writeRezeptur(
    _ParsedProduct p,
    List<String> warnungen,
  ) async {
    final sections = p.sections;
    if (sections.rezepturHeaderRow == null) return 0;
    final productId = p.productId!;
    final sheet = p.sheet;

    final headerRow = sections.rezepturHeaderRow!;
    final startRow = headerRow + 2;
    final endRow = sections.rezepturEndRow;

    final labelCols = _readHeaderCols(sheet, headerRow);
    final rohwareCol = _findCol(labelCols, ['rohware', 'rohstoff', 'name']);
    final mengeCol = _findCol(labelCols, ['menge_pro_kg', 'menge', 'mengeprokg']);
    final toleranzCol = _findCol(labelCols, ['toleranz', 'toleranz_prozent']);

    if (rohwareCol == null || mengeCol == null) return 0;

    int count = 0;
    for (var row = startRow; row < endRow && row < sheet.rows.length; row++) {
      final cells = sheet.rows[row];
      final rohwareName = _cellStr(cells, rohwareCol);
      if (rohwareName == null || rohwareName.isEmpty) continue;

      final menge = _cellDouble(cells, mengeCol);
      if (menge == null || menge <= 0) continue;

      final rohware = await (_db.select(_db.rawMaterials)
            ..where((r) => r.name.equals(rohwareName))
            ..where((r) => r.deletedAt.isNull()))
          .getSingleOrNull();
      if (rohware == null) {
        warnungen.add(
          'Produkt ${p.artikelnr}: Rohware "$rohwareName" nicht in Katalog — '
          'Rezepturzeile ${row + 1} übersprungen.',
        );
        continue;
      }

      final existing = await (_db.select(_db.productRawMaterials)
            ..where((r) => r.productId.equals(productId))
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
        ));
      } else {
        await _db.into(_db.productRawMaterials).insert(
              ProductRawMaterialsCompanion.insert(
                id: _uuid.v4(),
                productId: productId,
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

  // ─── DB-Write: Produktionshistorie → Mittelwerte ──────────────────────

  Future<int> _writeHistorie(
    _ParsedProduct p,
    List<String> warnungen,
  ) async {
    final sections = p.sections;
    if (sections.historieHeaderRow == null) return 0;
    final productId = p.productId!;
    final sheet = p.sheet;

    final headerRow = sections.historieHeaderRow!;
    final startRow = headerRow + 2;
    final endRow = sections.historieEndRow;

    final labelCols = _readHeaderCols(sheet, headerRow);
    final schrittCol = _findCol(labelCols, ['schritt', 'step', 'reihenfolge']);
    final mengeCol = _findCol(labelCols, ['menge_kg', 'menge', 'ist_menge']);
    final dauerCol = _findCol(labelCols, ['dauer_min', 'dauer', 'ist_dauer']);
    final maCol = _findCol(labelCols, ['mitarbeiter', 'ma', 'ist_mitarbeiter']);

    if (schrittCol == null || dauerCol == null) return 0;

    final measurements = <int, List<_HistoryEntry>>{};

    for (var row = startRow; row < endRow && row < sheet.rows.length; row++) {
      final cells = sheet.rows[row];
      final schritt = _cellInt(cells, schrittCol);
      final dauer = _cellDouble(cells, dauerCol);
      if (schritt == null || dauer == null) continue;

      final menge = _cellDouble(cells, mengeCol) ?? 100.0;
      final ma = _cellInt(cells, maCol) ?? 1;

      measurements
          .putIfAbsent(schritt, () => [])
          .add(_HistoryEntry(menge: menge, dauer: dauer, mitarbeiter: ma));
    }

    int count = 0;
    for (final entry in measurements.entries) {
      final schritt = entry.key;
      final values = entry.value;

      final step = await (_db.select(_db.productSteps)
            ..where((s) => s.productId.equals(productId))
            ..where((s) => s.reihenfolge.equals(schritt))
            ..where((s) => s.deletedAt.isNull()))
          .getSingleOrNull();
      if (step == null) {
        warnungen.add(
          'Produkt ${p.artikelnr}: Historie für Schritt $schritt verworfen — '
          'Schritt existiert nicht.',
        );
        continue;
      }

      final n = values.length;
      final avgDauer = values.map((v) => v.dauer).reduce((a, b) => a + b) / n;
      final avgMenge = values.map((v) => v.menge).reduce((a, b) => a + b) / n;
      final avgMa = (values.map((v) => v.mitarbeiter).reduce((a, b) => a + b) / n).round();

      double stdAbw = 0;
      if (n > 1) {
        final variance = values
                .map((v) => (v.dauer - avgDauer) * (v.dauer - avgDauer))
                .reduce((a, b) => a + b) /
            (n - 1);
        stdAbw = _sqrt(variance);
      }

      await (_db.update(_db.productSteps)
            ..where((s) => s.id.equals(step.id)))
          .write(ProductStepsCompanion(
        basisDauerMinuten: Value(avgDauer),
        basisMengeKg: Value(avgMenge),
        basisMitarbeiter: Value(avgMa),
        basisAnzahlMessungen: Value(n),
        dauerStdAbweichung: Value(n > 1 ? stdAbw : null),
        updatedAt: Value(DateTime.now()),
      ));

      count += n;
    }
    return count;
  }

  // ─── DB-Write: Rohwaren ───────────────────────────────────────────────

  Future<int> _importRohwaren(
    Sheet sheet,
    List<String> warnungen,
  ) async {
    final headers = _readHeaderCols(sheet, 0);
    final nameCol = _findCol(headers, ['name', 'rohware', 'bezeichnung']);
    final einheitCol = _findCol(headers, ['einheit', 'unit']);
    final lieferantCol = _findCol(headers, ['lieferant', 'supplier']);
    final leadTimeCol = _findCol(headers, ['lieferzeit', 'lead_time', 'lieferzeit_tage']);
    final chargenCol =
        _findCol(headers, ['chargen_pflicht', 'chargenpflicht', 'haccp']);

    if (nameCol == null || einheitCol == null) {
      warnungen.add('Rohwaren-Sheet: "Name" oder "Einheit" fehlt.');
      return 0;
    }

    int count = 0;
    for (var row = 1; row < sheet.rows.length; row++) {
      final cells = sheet.rows[row];
      final name = _cellStr(cells, nameCol);
      if (name == null || name.isEmpty) continue;

      final einheit = _cellStr(cells, einheitCol) ?? 'kg';

      final existing = await (_db.select(_db.rawMaterials)
            ..where((r) => r.name.equals(name))
            ..where((r) => r.deletedAt.isNull()))
          .getSingleOrNull();

      if (existing != null) {
        await (_db.update(_db.rawMaterials)
              ..where((r) => r.id.equals(existing.id)))
            .write(RawMaterialsCompanion(
          einheit: Value(einheit),
          lieferant: Value(_cellStr(cells, lieferantCol)),
          leadTimeTage: Value(_cellInt(cells, leadTimeCol)),
          chargenPflicht:
              Value(_cellStr(cells, chargenCol)?.toLowerCase() == 'ja'),
          updatedAt: Value(DateTime.now()),
        ));
      } else {
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

  // ─── Sheet-Struktur erkennen ──────────────────────────────────────────

  /// Parst die Block-Marker im Produkt-Sheet ("== STAMMDATEN ==" etc.).
  _SheetSections _parseSheetSections(Sheet sheet) {
    int? stammdatenStart;
    int? schritteStart;
    int? rezepturStart;
    int? historieStart;

    for (var row = 0; row < sheet.rows.length; row++) {
      final cells = sheet.rows[row];
      final firstCell = _cellStr(cells, 0)?.toUpperCase() ?? '';
      if (firstCell.contains('STAMMDATEN')) {
        stammdatenStart = row;
      } else if (firstCell.contains('PRODUKTIONSSCHRITTE')) {
        schritteStart = row;
      } else if (firstCell.contains('REZEPTUR')) {
        rezepturStart = row;
      } else if (firstCell.contains('PRODUKTIONSHISTORIE')) {
        historieStart = row;
      }
    }

    // Header-Zeile = Marker-Zeile + 1
    int? headerRow(int? markerRow) => markerRow != null ? markerRow + 1 : null;

    int sectionEnd(int? start, List<int?> nextStarts) {
      if (start == null) return sheet.rows.length;
      final candidates = nextStarts
          .whereType<int>()
          .where((s) => s > start)
          .toList()
        ..sort();
      return candidates.isNotEmpty ? candidates.first : sheet.rows.length;
    }

    final allStarts = [
      stammdatenStart,
      schritteStart,
      rezepturStart,
      historieStart,
    ];

    return _SheetSections(
      stammdatenHeaderRow: headerRow(stammdatenStart),
      schritteHeaderRow: headerRow(schritteStart),
      schritteEndRow: sectionEnd(schritteStart, allStarts),
      rezepturHeaderRow: headerRow(rezepturStart),
      rezepturEndRow: sectionEnd(rezepturStart, allStarts),
      historieHeaderRow: headerRow(historieStart),
      historieEndRow: sectionEnd(historieStart, allStarts),
    );
  }

  Map<String, int> _readHeaderCols(Sheet sheet, int headerRow) {
    final cols = <String, int>{};
    if (headerRow >= sheet.rows.length) return cols;
    final cells = sheet.rows[headerRow];
    for (var i = 0; i < cells.length; i++) {
      final val = cells[i]?.value?.toString().trim();
      if (val == null || val.isEmpty) continue;
      // Exakter Key + normalisierte Version (snake_case, lowercase)
      cols[val] = i;
      cols[val.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_')] = i;
    }
    return cols;
  }

  int? _findCol(Map<String, int> headers, List<String> aliases) {
    for (final alias in aliases) {
      if (headers.containsKey(alias)) return headers[alias];
    }
    return null;
  }

  // ─── Sheet suchen ─────────────────────────────────────────────────────

  Sheet? _findSheet(Excel excel, List<String> names) {
    for (final table in excel.tables.keys) {
      final lower = table.toLowerCase().trim();
      for (final name in names) {
        if (lower == name) return excel.tables[table];
      }
    }
    return null;
  }

  Sheet? _findProduktSheet(Excel excel, String artNr, String? bezeichnung) {
    final artNrLower = artNr.toLowerCase().trim();
    for (final name in excel.tables.keys) {
      if (name.toLowerCase().trim().startsWith(artNrLower)) {
        return excel.tables[name];
      }
    }
    return null;
  }

  // ─── Zell-Lese-Helfer ─────────────────────────────────────────────────

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

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (var i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Interne Datenklassen
// ═══════════════════════════════════════════════════════════════════════════

/// Ein geparster, validierter Artikel bereit zum Schreiben.
class _ParsedProduct {
  _ParsedProduct({
    required this.sheet,
    required this.sheetName,
    required this.artikelnr,
    required this.gruppe,
    required this.werte,
    required this.sections,
  });

  final Sheet sheet;
  final String sheetName;
  final String artikelnr;
  final ProductGroup gruppe;

  /// FieldSpec.key → typisierter Wert (String / double / int / bool).
  final Map<String, Object?> werte;

  final _SheetSections sections;

  /// Wird nach dem Write gesetzt — für Schritte/Rezeptur/Historie.
  String? productId;
}

/// Sheet-Struktur: welche Zeile ist Block-Header wofür.
class _SheetSections {
  const _SheetSections({
    this.stammdatenHeaderRow,
    this.schritteHeaderRow,
    this.schritteEndRow = 0,
    this.rezepturHeaderRow,
    this.rezepturEndRow = 0,
    this.historieHeaderRow,
    this.historieEndRow = 0,
  });

  final int? stammdatenHeaderRow;
  final int? schritteHeaderRow;
  final int schritteEndRow;
  final int? rezepturHeaderRow;
  final int rezepturEndRow;
  final int? historieHeaderRow;
  final int historieEndRow;

  int get schritteDataRows => schritteHeaderRow != null
      ? (schritteEndRow - schritteHeaderRow! - 2).clamp(0, 999999)
      : 0;
  int get rezepturDataRows => rezepturHeaderRow != null
      ? (rezepturEndRow - rezepturHeaderRow! - 2).clamp(0, 999999)
      : 0;
  int get historieDataRows => historieHeaderRow != null
      ? (historieEndRow - historieHeaderRow! - 2).clamp(0, 999999)
      : 0;
}

class _ConversionResult {
  _ConversionResult.ok(this.value) : error = null;
  _ConversionResult.err(this.error) : value = null;

  final Object? value;
  final String? error;
}

class _HistoryEntry {
  const _HistoryEntry({
    required this.menge,
    required this.dauer,
    required this.mitarbeiter,
  });

  final double menge;
  final double dauer;
  final int mitarbeiter;
}