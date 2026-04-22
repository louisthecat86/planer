import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../constants/abteilungen.dart';
import '../database/database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Ergebnis-Klassen (V3-spezifisch, damit Legacy-API unangetastet bleibt)
// ═══════════════════════════════════════════════════════════════════════════

class ImportResultV3 {
  const ImportResultV3({
    this.artikelNeu = 0,
    this.artikelAktualisiert = 0,
    this.schritteImportiert = 0,
    this.parameterImportiert = 0,
    this.maschinenImportiert = 0,
    this.historienVerarbeitet = 0,
    this.warnungen = const [],
    this.fehler = const [],
  });

  final int artikelNeu;
  final int artikelAktualisiert;
  final int schritteImportiert;
  final int parameterImportiert;
  final int maschinenImportiert;
  final int historienVerarbeitet;
  final List<String> warnungen;
  final List<String> fehler;

  bool get hatFehler => fehler.isNotEmpty;
  int get artikelGesamt => artikelNeu + artikelAktualisiert;
}

class ImportPreviewV3 {
  const ImportPreviewV3({
    this.artikelNeu = 0,
    this.artikelAktualisiert = 0,
    this.schritte = 0,
    this.parameter = 0,
    this.maschinen = 0,
    this.historien = 0,
    this.warnungen = const [],
    this.fehler = const [],
  });

  final int artikelNeu;
  final int artikelAktualisiert;
  final int schritte;
  final int parameter;
  final int maschinen;
  final int historien;
  final List<String> warnungen;
  final List<String> fehler;

  bool get hatFehler => fehler.isNotEmpty;
  bool get istLeer =>
      artikelNeu == 0 &&
      artikelAktualisiert == 0 &&
      schritte == 0 &&
      parameter == 0 &&
      maschinen == 0 &&
      historien == 0;
}

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
  String toString() => 'Sheet "$sheet" ($artikelnr): Feld "$feld" — $grund';
}

// ═══════════════════════════════════════════════════════════════════════════
// Parsed-Data-Klassen
// ═══════════════════════════════════════════════════════════════════════════

class _ParsedMachine {
  _ParsedMachine({
    required this.name,
    required this.abteilungDb,
    this.typischeParameter,
  });

  final String name;
  final String abteilungDb;
  final String? typischeParameter;
}

class _ParsedStep {
  _ParsedStep({
    required this.reihenfolge,
    required this.abteilungDb,
    this.prozessschritt,
    this.maschineName,
    this.personen,
    this.mengeKg,
    this.zeitMinuten,
  });

  final int reihenfolge;
  final String abteilungDb;
  String? prozessschritt;
  String? maschineName;
  int? personen;
  double? mengeKg;
  double? zeitMinuten;

  final Map<String, List<_ParsedParam>> parameterByGruppe = {};
}

class _ParsedParam {
  _ParsedParam({
    required this.name,
    required this.wert,
    required this.istCustom,
  });

  final String name;
  final String wert;
  final bool istCustom;
}

class _ParsedHistorie {
  _ParsedHistorie({
    this.datum,
    this.kgRohware,
    this.kgFertigware,
    this.verlustProzent,
    this.startzeit,
    this.endzeit,
    this.produktionszeitMinuten,
    this.kgProStundeRoh,
    this.kgProStundeGegart,
    this.notizen,
  });

  DateTime? datum;
  double? kgRohware;
  double? kgFertigware;
  double? verlustProzent;
  String? startzeit;
  String? endzeit;
  double? produktionszeitMinuten;
  double? kgProStundeRoh;
  double? kgProStundeGegart;
  String? notizen;
}

class _ParsedProduct {
  _ParsedProduct({
    required this.sheetName,
    required this.artikelnummer,
    required this.bezeichnung,
    required this.kategorie,
    this.produktgruppeDb,
    this.schritte = const [],
    this.historie = const [],
  });

  final String sheetName;
  final String artikelnummer;
  final String bezeichnung;
  final String kategorie;
  final String? produktgruppeDb;
  List<_ParsedStep> schritte;
  List<_ParsedHistorie> historie;
}

// ═══════════════════════════════════════════════════════════════════════════
// ExcelImportServiceV3
// ═══════════════════════════════════════════════════════════════════════════

class ExcelImportServiceV3 {
  ExcelImportServiceV3(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();

  static const _metaSheets = <String>{
    'Übersicht',
    'Anleitung',
    'Anlagen-Katalog',
    'Brühwurst',
    'Rohwurst',
    'Kochpökelwaren',
    'Rohpökelwaren',
    'Aufschnitt',
    'Bratstraßenartikel Natur',
    'Bratstraßenartikel paniert',
    'Hackprodukte gegart',
    'Hackprodukte roh',
    'Braten',
    'Sous Vide gegarte Produkte',
    'Angebratene Brühwürste',
  };

  static const _schrittZeilen = <String>{
    'Abteilung',
    'Prozessschritt',
    'Anlagen',
    'Personen',
    'Menge (kg)',
    'Zeit (hh:mm)',
  };

  static const _customBlockMarker = 'ZUSÄTZLICHE PARAMETER';
  static const _sonstigeBlockMarker = 'Sonstige Informationen';
  static const _historieBlockMarker = 'HISTORISCHE DATEN';

  static const Map<String, String> _kategorieZuProduktgruppe = {
    'Brühwurst': 'bruehwurst',
    'Rohwurst': 'rohwurst',
    'Kochpökelwaren': 'kochpoekelware',
    'Rohpökelwaren': 'rohpoekelware',
    'Aufschnitt': 'aufschnitt',
    'Bratstraßenartikel Natur': 'bratstrasse_natur',
    'Bratstraßenartikel paniert': 'bratstrasse_paniert',
    'Hackprodukte gegart': 'hackprodukt_gegart',
    'Hackprodukte roh': 'hackprodukt_roh',
    'Braten': 'braten',
    'Sous Vide gegarte Produkte': 'sous_vide',
    'Angebratene Brühwürste': 'angebratene_bruehwurst',
  };

  static const Map<String, String> _abteilungMapping = {
    'Zerlegung': 'zerlegung',
    'Wurstküche': 'wurstkueche',
    'Kutterabteilung': 'kutterabteilung',
    'Bratstraße': 'bratstrasse',
    'Schockfroster': 'bratstrasse',
    'Räucherei': 'wurstkueche',
    'Klimakammer': 'wurstkueche',
    'Reifekammer': 'wurstkueche',
    'Pökelei': 'wurstkueche',
    'Aufschnitt': 'schneideabteilung',
    'Schneideabteilung': 'schneideabteilung',
    'Sous-Vide': 'wurstkueche',
    'Verpackung': 'verpackung',
    'Verpackung Tef1': 'verpackung_tef1',
    'Verpackung TEF1': 'verpackung_tef1',
  };

  static Set<String> _collectSheetNames(Excel excel) {
    final names = <String>{};
    try {
      names.addAll(excel.tables.keys);
    } catch (_) {}
    try {
      // ignore: avoid_dynamic_calls
      final dyn = (excel as dynamic).sheets;
      if (dyn is Map) {
        names.addAll(dyn.keys.map((k) => k.toString()));
      }
    } catch (_) {}
    return names;
  }

  static bool istV3Format(Excel excel) {
    final sheetNames = _collectSheetNames(excel);
    if (!sheetNames.contains('Anlagen-Katalog')) return false;
    final blaupausen = _metaSheets.where(
      (s) =>
          s != 'Übersicht' && s != 'Anleitung' && s != 'Anlagen-Katalog',
    );
    return blaupausen.any(sheetNames.contains);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Preview
  // ═════════════════════════════════════════════════════════════════════════

  Future<ImportPreviewV3> preview(File file) async {
    final excel = Excel.decodeBytes(await file.readAsBytes());

    if (!istV3Format(excel)) {
      return const ImportPreviewV3(
        fehler: [
          'Datei ist nicht im v3-Format (Sheet "Anlagen-Katalog" oder Blaupausen fehlen).',
        ],
      );
    }

    final errors = <_ValidationError>[];
    final warnings = <String>[];

    final katalog = excel.tables['Anlagen-Katalog']!;
    final maschinen = _parseMaschinenKatalog(katalog, errors, warnings);

    final existing = await _db.select(_db.products).get();
    final existingArtNrs = existing.map((p) => p.artikelnummer).toSet();

    int neu = 0;
    int updates = 0;
    int schritte = 0;
    int parameter = 0;
    int historien = 0;

    final sheetNames = _collectSheetNames(excel);
    for (final sheetName in sheetNames) {
      if (_metaSheets.contains(sheetName)) continue;
      final sheet = excel.tables[sheetName];
      if (sheet == null) continue;
      final parsed = _parseArtikelSheet(
        sheet,
        sheetName,
        maschinen.map((m) => m.name).toSet(),
        errors,
        warnings,
      );
      if (parsed == null) continue;
      if (existingArtNrs.contains(parsed.artikelnummer)) {
        updates++;
      } else {
        neu++;
      }
      schritte += parsed.schritte.length;
      for (final s in parsed.schritte) {
        for (final list in s.parameterByGruppe.values) {
          parameter += list.length;
        }
      }
      historien += parsed.historie.length;
    }

    return ImportPreviewV3(
      artikelNeu: neu,
      artikelAktualisiert: updates,
      schritte: schritte,
      parameter: parameter,
      maschinen: maschinen.length,
      historien: historien,
      warnungen: warnings,
      fehler: errors.map((e) => e.toString()).toList(),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Import
  // ═════════════════════════════════════════════════════════════════════════

  Future<ImportResultV3> import(File file) async {
    final excel = Excel.decodeBytes(await file.readAsBytes());

    if (!istV3Format(excel)) {
      return const ImportResultV3(
        fehler: ['Datei ist nicht im v3-Format.'],
      );
    }

    final errors = <_ValidationError>[];
    final warnings = <String>[];

    final katalog = excel.tables['Anlagen-Katalog']!;
    final parsedMaschinen = _parseMaschinenKatalog(katalog, errors, warnings);

    final maschinenNamenSet = parsedMaschinen.map((m) => m.name).toSet();
    final parsedArtikel = <_ParsedProduct>[];

    final sheetNames = _collectSheetNames(excel);
    for (final sheetName in sheetNames) {
      if (_metaSheets.contains(sheetName)) continue;
      final sheet = excel.tables[sheetName];
      if (sheet == null) continue;
      final parsed = _parseArtikelSheet(
        sheet,
        sheetName,
        maschinenNamenSet,
        errors,
        warnings,
      );
      if (parsed != null) parsedArtikel.add(parsed);
    }

    if (errors.isNotEmpty) {
      return ImportResultV3(
        fehler: errors.map((e) => e.toString()).toList(),
        warnungen: warnings,
      );
    }

    int artikelNeu = 0;
    int artikelAktualisiert = 0;
    int schritteImportiert = 0;
    int parameterImportiert = 0;
    int maschinenImportiert = 0;
    int historienVerarbeitet = 0;

    await _db.transaction(() async {
      final maschinenIdByName = <String, String>{};
      for (final m in parsedMaschinen) {
        final existing = await (_db.select(_db.machines)
              ..where((t) => t.name.equals(m.name))
              ..limit(1))
            .getSingleOrNull();
        if (existing == null) {
          final id = _uuid.v4();
          await _db.into(_db.machines).insert(
                MachinesCompanion(
                  id: Value(id),
                  name: Value(m.name),
                  abteilung: Value(m.abteilungDb),
                  typischeParameter: Value(m.typischeParameter),
                ),
              );
          maschinenIdByName[m.name] = id;
          maschinenImportiert++;
        } else {
          await (_db.update(_db.machines)
                ..where((t) => t.id.equals(existing.id)))
              .write(
            MachinesCompanion(
              abteilung: Value(m.abteilungDb),
              typischeParameter: Value(m.typischeParameter),
              updatedAt: Value(DateTime.now()),
            ),
          );
          maschinenIdByName[m.name] = existing.id;
        }
      }

      for (final art in parsedArtikel) {
        final existing = await (_db.select(_db.products)
              ..where((t) => t.artikelnummer.equals(art.artikelnummer))
              ..limit(1))
            .getSingleOrNull();

        String productId;
        if (existing == null) {
          productId = _uuid.v4();
          await _db.into(_db.products).insert(
                ProductsCompanion(
                  id: Value(productId),
                  artikelnummer: Value(art.artikelnummer),
                  artikelbezeichnung: Value(art.bezeichnung),
                  produktgruppe: Value(art.produktgruppeDb),
                ),
              );
          artikelNeu++;
        } else {
          productId = existing.id;
          await (_db.update(_db.products)
                ..where((t) => t.id.equals(productId)))
              .write(
            ProductsCompanion(
              artikelbezeichnung: Value(art.bezeichnung),
              produktgruppe: Value(art.produktgruppeDb),
              updatedAt: Value(DateTime.now()),
            ),
          );
          artikelAktualisiert++;

          final oldStepIds = await (_db.select(_db.productSteps)
                ..where((t) => t.productId.equals(productId)))
              .map((s) => s.id)
              .get();
          for (final sid in oldStepIds) {
            await (_db.delete(_db.productStepParameters)
                  ..where((t) => t.stepId.equals(sid)))
                .go();
          }
          await (_db.delete(_db.productSteps)
                ..where((t) => t.productId.equals(productId)))
              .go();
        }

        for (final s in art.schritte) {
          final stepId = _uuid.v4();
          final maschineId = s.maschineName != null
              ? maschinenIdByName[s.maschineName]
              : null;

          await _db.into(_db.productSteps).insert(
                ProductStepsCompanion(
                  id: Value(stepId),
                  productId: Value(productId),
                  reihenfolge: Value(s.reihenfolge),
                  abteilung: Value(s.abteilungDb),
                  maschineId: Value(maschineId),
                  prozessschritt: Value(s.prozessschritt),
                  mengeKg: Value(s.mengeKg),
                  basisMengeKg: Value(s.mengeKg ?? 0.0),
                  basisDauerMinuten: Value(s.zeitMinuten ?? 0.0),
                  basisMitarbeiter: Value(s.personen ?? 1),
                  maschine: Value(s.maschineName),
                ),
              );
          schritteImportiert++;

          int paramIdx = 0;
          for (final entry in s.parameterByGruppe.entries) {
            for (final p in entry.value) {
              await _db.into(_db.productStepParameters).insert(
                    ProductStepParametersCompanion(
                      id: Value(_uuid.v4()),
                      stepId: Value(stepId),
                      parameterGruppe: Value(entry.key),
                      parameterName: Value(p.name),
                      wert: Value(p.wert),
                      reihenfolge: Value(paramIdx++),
                      istCustom: Value(p.istCustom),
                    ),
                  );
              parameterImportiert++;
            }
          }
        }

        historienVerarbeitet += art.historie.length;
        if (art.historie.isNotEmpty) {
          warnings.add(
            'Sheet "${art.sheetName}" (${art.artikelnummer}): '
            '${art.historie.length} Historie-Einträge gefunden — '
            'diese werden in Phase 1c in die Lernlogik übernommen.',
          );
        }
      }
    });

    return ImportResultV3(
      artikelNeu: artikelNeu,
      artikelAktualisiert: artikelAktualisiert,
      schritteImportiert: schritteImportiert,
      parameterImportiert: parameterImportiert,
      maschinenImportiert: maschinenImportiert,
      historienVerarbeitet: historienVerarbeitet,
      warnungen: warnings,
      fehler: errors.map((e) => e.toString()).toList(),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Parsing-Helpers
  // ═════════════════════════════════════════════════════════════════════════

  List<_ParsedMachine> _parseMaschinenKatalog(
    Sheet sheet,
    List<_ValidationError> errors,
    List<String> warnings,
  ) {
    final result = <_ParsedMachine>[];
    int? headerRow;
    for (var r = 0; r < sheet.rows.length; r++) {
      final a = _cellStr(sheet.rows[r], 0);
      if (a == 'Anlage') {
        headerRow = r;
        break;
      }
    }
    if (headerRow == null) {
      errors.add(
        const _ValidationError(
          sheet: 'Anlagen-Katalog',
          artikelnr: '—',
          feld: 'Header',
          grund: 'Header-Zeile mit "Anlage" nicht gefunden',
        ),
      );
      return result;
    }

    for (var r = headerRow + 1; r < sheet.rows.length; r++) {
      final name = _cellStr(sheet.rows[r], 0);
      final abtText = _cellStr(sheet.rows[r], 1);
      final params = _cellStr(sheet.rows[r], 2);

      if (name == null || name.isEmpty) continue;
      if (abtText == null || abtText.isEmpty) {
        warnings.add(
          'Anlagen-Katalog Zeile ${r + 1}: '
          'Anlage "$name" ohne Abteilung — übersprungen.',
        );
        continue;
      }
      final abtDb = _mapAbteilung(abtText);
      if (abtDb == null) {
        warnings.add(
          'Anlagen-Katalog Zeile ${r + 1}: '
          'Unbekannte Abteilung "$abtText" für "$name" — übersprungen.',
        );
        continue;
      }
      result.add(
        _ParsedMachine(
          name: name,
          abteilungDb: abtDb,
          typischeParameter: params,
        ),
      );
    }
    return result;
  }

  /// Sucht eine Zelle in einer Zeile tolerant:
  /// Wenn der erwartete Spaltenindex leer ist, werden die nachfolgenden
  /// Spalten durchsucht. Das fängt gemergte Zellen ab, bei denen der
  /// Wert in einer anderen Spalte als erwartet landet.
  static String? _cellStrToleranteSuche(
    List<Data?> row,
    int startCol, {
    int maxLookahead = 12,
  }) {
    final direkt = _cellStr(row, startCol);
    if (direkt != null && direkt.isNotEmpty) return direkt;
    for (var c = startCol + 1; c < startCol + maxLookahead && c < row.length; c++) {
      final v = _cellStr(row, c);
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  _ParsedProduct? _parseArtikelSheet(
    Sheet sheet,
    String sheetName,
    Set<String> bekannteMaschinen,
    List<_ValidationError> errors,
    List<String> warnings,
  ) {
    final rows = sheet.rows;
    if (rows.length < 6) {
      errors.add(
        _ValidationError(
          sheet: sheetName,
          artikelnr: sheetName,
          feld: 'Sheet-Struktur',
          grund: 'Zu wenige Zeilen für ein Artikel-Sheet',
        ),
      );
      return null;
    }

    final kategorie = _cellStr(rows[1], 0);
    if (kategorie == null || kategorie.isEmpty) {
      errors.add(
        _ValidationError(
          sheet: sheetName,
          artikelnr: sheetName,
          feld: 'Kategorie',
          grund: 'Zelle A2 (Kategorie-Titel) leer',
        ),
      );
      return null;
    }
    final produktgruppeDb = _kategorieZuProduktgruppe[kategorie];
    if (produktgruppeDb == null) {
      warnings.add(
        'Sheet "$sheetName": Unbekannte Kategorie "$kategorie" '
        '— Produktgruppe bleibt leer.',
      );
    }

    // Artikelnummer aus A5 (Zeile 5, Spalte A)
    final artNrCell = rows[4].isNotEmpty ? rows[4][0] : null;
    String? artikelnummer = _cellStr([artNrCell], 0);

    if (artNrCell?.value is IntCellValue) {
      artikelnummer = (artNrCell!.value as IntCellValue).value.toString();
    } else if (artNrCell?.value is DoubleCellValue) {
      final d = (artNrCell!.value as DoubleCellValue).value;
      artikelnummer =
          d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }

    if (artikelnummer == null || artikelnummer.isEmpty) {
      errors.add(
        _ValidationError(
          sheet: sheetName,
          artikelnr: sheetName,
          feld: 'Artikelnummer',
          grund: 'Zelle A5 leer oder ungültig',
        ),
      );
      return null;
    }

    // Bezeichnung tolerant suchen: B5 zuerst, sonst C5/D5/... durchsuchen.
    // Grund: Bei gemergten Zellen (B5:K5) landet der Wert manchmal in einer
    // anderen Spalte als B, je nach Excel-Version / Re-Save-Verhalten.
    final bezeichnung = _cellStrToleranteSuche(rows[4], 1);

    if (bezeichnung == null || bezeichnung.isEmpty) {
      errors.add(
        _ValidationError(
          sheet: sheetName,
          artikelnr: artikelnummer,
          feld: 'Artikelbezeichnung',
          grund: 'Zelle B5 (und Nachbarzellen) leer',
        ),
      );
      return null;
    }

    final schritte = _parseSchritte(
      rows,
      sheetName,
      artikelnummer,
      bekannteMaschinen,
      errors,
      warnings,
    );
    final historie = _parseHistorie(rows);

    return _ParsedProduct(
      sheetName: sheetName,
      artikelnummer: artikelnummer,
      bezeichnung: bezeichnung,
      kategorie: kategorie,
      produktgruppeDb: produktgruppeDb,
      schritte: schritte,
      historie: historie,
    );
  }

  List<_ParsedStep> _parseSchritte(
    List<List<Data?>> rows,
    String sheetName,
    String artikelnummer,
    Set<String> bekannteMaschinen,
    List<_ValidationError> errors,
    List<String> warnings,
  ) {
    final labelRow = <String, int>{};
    for (var r = 0; r < rows.length; r++) {
      final label = _cellStr(rows[r], 0);
      if (label == null) continue;
      if (_schrittZeilen.contains(label)) {
        labelRow[label] = r;
      }
    }
    if (!labelRow.containsKey('Abteilung')) {
      errors.add(
        _ValidationError(
          sheet: sheetName,
          artikelnr: artikelnummer,
          feld: 'Schritt-Struktur',
          grund: 'Zeile "Abteilung" nicht gefunden',
        ),
      );
      return [];
    }

    final abtRow = labelRow['Abteilung']!;
    final schritte = <_ParsedStep>[];

    int maxSchritt = 0;
    for (var c = 1; c <= 20; c++) {
      final v = _cellStr(rows[abtRow], c);
      if (v == null || v.isEmpty) break;
      maxSchritt = c;
    }

    for (var col = 1; col <= maxSchritt; col++) {
      final abtText = _cellStr(rows[abtRow], col);
      if (abtText == null || abtText.isEmpty) continue;

      final abtDb = _mapAbteilung(abtText);
      if (abtDb == null) {
        warnings.add(
          'Sheet "$sheetName" ($artikelnummer): '
          'Schritt $col: Unbekannte Abteilung "$abtText" — übersprungen.',
        );
        continue;
      }

      final step = _ParsedStep(
        reihenfolge: col,
        abteilungDb: abtDb,
        prozessschritt: _cellStr(rows[labelRow['Prozessschritt'] ?? -1], col),
        maschineName: _cellStr(rows[labelRow['Anlagen'] ?? -1], col),
        personen: _parseInt(rows[labelRow['Personen'] ?? -1], col),
        mengeKg: _parseDouble(rows[labelRow['Menge (kg)'] ?? -1], col),
        zeitMinuten: _parseZeit(rows[labelRow['Zeit (hh:mm)'] ?? -1], col),
      );

      if (step.maschineName != null && step.maschineName!.isNotEmpty) {
        if (!bekannteMaschinen.contains(step.maschineName)) {
          warnings.add(
            'Sheet "$sheetName" ($artikelnummer): '
            'Schritt $col: Anlage "${step.maschineName}" nicht im '
            'Anlagen-Katalog — Schritt wird trotzdem importiert, '
            'aber ohne Maschinen-Referenz.',
          );
          step.maschineName = null;
        }
      }

      schritte.add(step);
    }

    final startParamRow = (labelRow['Zeit (hh:mm)'] ?? abtRow + 5) + 1;
    _parseParameter(rows, startParamRow, schritte, maxSchritt);

    return schritte;
  }

  void _parseParameter(
    List<List<Data?>> rows,
    int startRow,
    List<_ParsedStep> schritte,
    int maxSchritt,
  ) {
    String? aktuelleGruppe;
    bool inCustomBlock = false;

    for (var r = startRow; r < rows.length; r++) {
      final label = _cellStr(rows[r], 0);
      if (label == null || label.isEmpty) continue;

      if (label.contains(_historieBlockMarker)) break;
      if (label == _sonstigeBlockMarker) continue;

      if (label.startsWith(_customBlockMarker)) {
        aktuelleGruppe = 'CUSTOM';
        inCustomBlock = true;
        continue;
      }

      if (_istGruppenHeader(label, rows[r], maxSchritt)) {
        aktuelleGruppe = label.trim();
        inCustomBlock = false;
        continue;
      }

      if (aktuelleGruppe == null) continue;

      for (final step in schritte) {
        final wert = _cellStr(rows[r], step.reihenfolge);
        if (wert == null || wert.isEmpty) continue;
        step.parameterByGruppe
            .putIfAbsent(aktuelleGruppe, () => [])
            .add(
              _ParsedParam(
                name: label.trim(),
                wert: wert,
                istCustom: inCustomBlock,
              ),
            );
      }
    }
  }

  bool _istGruppenHeader(String label, List<Data?> row, int maxSchritt) {
    final hasLetters = label.runes.any((r) {
      final c = String.fromCharCode(r);
      return RegExp(r'[A-Za-zÄÖÜäöüß]').hasMatch(c);
    });
    if (!hasLetters) return false;
    final uppers = label.runes.where((r) {
      final c = String.fromCharCode(r);
      return RegExp(r'[A-ZÄÖÜ]').hasMatch(c);
    }).length;
    final lowers = label.runes.where((r) {
      final c = String.fromCharCode(r);
      return RegExp(r'[a-zäöüß]').hasMatch(c);
    }).length;
    if (uppers < 2) return false;
    if (lowers > uppers) return false;

    for (var c = 1; c <= maxSchritt; c++) {
      if (_cellStr(row, c)?.isNotEmpty ?? false) return false;
    }
    return true;
  }

  List<_ParsedHistorie> _parseHistorie(List<List<Data?>> rows) {
    int? headerRow;
    for (var r = 0; r < rows.length; r++) {
      final a = _cellStr(rows[r], 0);
      if (a == 'Datum') {
        headerRow = r;
        if (r >= 2) {
          final zweiHoeher = _cellStr(rows[r - 2], 0) ?? '';
          final eineHoeher = _cellStr(rows[r - 1], 0) ?? '';
          if (zweiHoeher.contains(_historieBlockMarker) ||
              eineHoeher.contains(_historieBlockMarker)) {
            break;
          }
        }
      }
    }
    if (headerRow == null) return [];

    final result = <_ParsedHistorie>[];
    for (var r = headerRow + 1; r < rows.length; r++) {
      if (rows[r].isEmpty) continue;
      final datumCell = rows[r].isNotEmpty ? rows[r][0] : null;
      if (datumCell == null || datumCell.value == null) continue;
      final dt = _parseDatum(datumCell);
      if (dt == null) continue;
      result.add(
        _ParsedHistorie(
          datum: dt,
          kgRohware: _parseDouble(rows[r], 1),
          kgFertigware: _parseDouble(rows[r], 2),
          verlustProzent: _parseDouble(rows[r], 3),
          startzeit: _cellStr(rows[r], 4),
          endzeit: _cellStr(rows[r], 5),
          produktionszeitMinuten: _parseZeit(rows[r], 6),
          kgProStundeRoh: _parseDouble(rows[r], 7),
          kgProStundeGegart: _parseDouble(rows[r], 8),
          notizen: _cellStr(rows[r], 9),
        ),
      );
    }
    return result;
  }

  static String? _cellStr(List<Data?> row, int col) {
    if (col < 0 || col >= row.length) return null;
    final cell = row[col];
    final v = cell?.value;
    if (v == null) return null;
    if (v is TextCellValue) return v.value.text?.trim();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    if (v is BoolCellValue) return v.value.toString();
    if (v is DateCellValue) {
      return '${v.year}-${_pad(v.month)}-${_pad(v.day)}';
    }
    if (v is TimeCellValue) {
      return '${_pad(v.hour)}:${_pad(v.minute)}';
    }
    if (v is DateTimeCellValue) {
      return '${v.year}-${_pad(v.month)}-${_pad(v.day)}';
    }
    return v.toString().trim();
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static int? _parseInt(List<Data?> row, int col) {
    if (col < 0 || col >= row.length) return null;
    final v = row[col]?.value;
    if (v is IntCellValue) return v.value;
    if (v is DoubleCellValue) return v.value.round();
    if (v is TextCellValue) {
      final s = v.value.text?.trim() ?? '';
      final m = RegExp(r'(\d+)').firstMatch(s);
      if (m != null) return int.parse(m.group(1)!);
    }
    return null;
  }

  static double? _parseDouble(List<Data?> row, int col) {
    if (col < 0 || col >= row.length) return null;
    final v = row[col]?.value;
    if (v is DoubleCellValue) return v.value;
    if (v is IntCellValue) return v.value.toDouble();
    if (v is TextCellValue) {
      final s = v.value.text?.trim().replaceAll(',', '.') ?? '';
      return double.tryParse(s);
    }
    return null;
  }

  static double? _parseZeit(List<Data?> row, int col) {
    if (col < 0 || col >= row.length) return null;
    final v = row[col]?.value;
    if (v is TimeCellValue) {
      return v.hour * 60.0 + v.minute + v.second / 60.0;
    }
    if (v is TextCellValue) {
      final s = v.value.text?.trim() ?? '';
      final parts = s.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) return h * 60.0 + m;
      }
    }
    if (v is DoubleCellValue) {
      return v.value * 24 * 60;
    }
    return null;
  }

  static DateTime? _parseDatum(Data? cell) {
    final v = cell?.value;
    if (v is DateCellValue) {
      return DateTime(v.year, v.month, v.day);
    }
    if (v is DateTimeCellValue) {
      return DateTime(v.year, v.month, v.day);
    }
    if (v is TextCellValue) {
      return DateTime.tryParse(v.value.text ?? '');
    }
    return null;
  }

  String? _mapAbteilung(String text) {
    final trimmed = text.trim();
    if (_abteilungMapping.containsKey(trimmed)) {
      return _abteilungMapping[trimmed];
    }
    try {
      return Abteilung.fromDbValue(trimmed.toLowerCase()).dbValue;
    } catch (_) {
      return null;
    }
  }
}