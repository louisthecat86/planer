import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:xml/xml.dart';

import '../database/database.dart';
import 'excel_import_service_v3.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Ergebnis-Klasse
// ═══════════════════════════════════════════════════════════════════════════

class ExportResultV3 {
  const ExportResultV3({
    required this.bytes,
    required this.vorschlagDateiname,
    this.artikelAktualisiert = 0,
    this.schritteGeschrieben = 0,
    this.parameterGeschrieben = 0,
    this.artikelNichtInVorlage = const [],
    this.warnungen = const [],
    this.fehler = const [],
  });

  /// Die neuen Excel-Bytes — vom UI ins Dateisystem geschrieben.
  final Uint8List bytes;

  /// Vorschlag für den Dateinamen im Speichern-Dialog.
  final String vorschlagDateiname;

  final int artikelAktualisiert;
  final int schritteGeschrieben;
  final int parameterGeschrieben;

  /// Artikel, die in der DB sind, aber kein entsprechendes Sheet
  /// in der Vorlage haben (z.B. in der App neu angelegt).
  /// Die werden aktuell nicht exportiert — das kommt in einem zweiten
  /// Schritt.
  final List<String> artikelNichtInVorlage;

  final List<String> warnungen;
  final List<String> fehler;

  bool get hatFehler => fehler.isNotEmpty;
}

// ═══════════════════════════════════════════════════════════════════════════
// ExcelExportServiceV3
// ═══════════════════════════════════════════════════════════════════════════

/// Exportiert den aktuellen DB-Stand in die zuletzt importierte
/// Excel-Datei, unter Erhalt aller Formatierung.
///
/// Funktionsweise:
/// 1. Lädt die importierten Excel-Bytes aus `app_settings`.
/// 2. Öffnet das ZIP, liest `xl/workbook.xml` + `xl/sharedStrings.xml`
///    + `xl/_rels/workbook.xml.rels` um zu wissen welcher Sheet
///    welcher XML-Datei entspricht.
/// 3. Für jeden Artikel-DB-Eintrag: öffnet das passende Sheet-XML,
///    setzt die relevanten Zellen auf DB-Werte, schreibt es zurück.
/// 4. Packt das ZIP neu zusammen und liefert die Bytes.
///
/// **Bewusst unangetastete Teile:**
/// - Styles, Fonts, Fills, Borders (xl/styles.xml)
/// - Drawings, Charts, Images
/// - Data Validations (Dropdowns)
/// - Defined Names (Named Ranges wie "Anlagen_Liste")
/// - Tab-Farben, Merge-Definitionen
/// - Anlagen-Katalog, Übersicht, Anleitung, Blaupausen-Sheets
class ExcelExportServiceV3 {
  ExcelExportServiceV3(this._db);

  final AppDatabase _db;

  /// Namespace für relationships (wird zum Auflösen der Sheet-IDs gebraucht).
  static const _nsRel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  /// Prüft ob eine Excel-Datei als Basis vorliegt. Das UI ruft das vor
  /// dem Export-Button-Click auf, um einen Hinweis zu zeigen falls
  /// noch nichts importiert wurde.
  Future<bool> hasImportedFile() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(kAppSettingLastImportExcelBytes))
          ..limit(1))
        .getSingleOrNull();
    return row != null && row.value.isNotEmpty;
  }

  /// Liest den gespeicherten Dateinamen (für den Speichern-Dialog-Vorschlag).
  Future<String> letzterDateiname() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(kAppSettingLastImportExcelFilename))
          ..limit(1))
        .getSingleOrNull();
    return row?.value ?? 'stammdaten_export.xlsx';
  }

  /// Haupt-Export-Methode. Liefert die Bytes der aktualisierten Excel.
  Future<ExportResultV3> export() async {
    // ─── 1. Basis-Excel aus app_settings laden ──────────────────────────
    final bytesRow = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(kAppSettingLastImportExcelBytes))
          ..limit(1))
        .getSingleOrNull();
    if (bytesRow == null || bytesRow.value.isEmpty) {
      return ExportResultV3(
        bytes: Uint8List(0),
        vorschlagDateiname: 'stammdaten_export.xlsx',
        fehler: const [
          'Keine Basis-Excel gefunden. Bitte importiere zuerst eine '
              'v3-Vorlage, bevor du exportieren kannst.',
        ],
      );
    }

    final vorlageBytes = base64Decode(bytesRow.value);
    final dateiname = await letzterDateiname();

    // ─── 2. ZIP entpacken ───────────────────────────────────────────────
    final archive = ZipDecoder().decodeBytes(vorlageBytes);

    // ─── 3. Sheet-Namen → XML-Pfad auflösen ─────────────────────────────
    final sheetInfo = _ermittleSheetXmlPfade(archive);
    if (sheetInfo.isEmpty) {
      return ExportResultV3(
        bytes: Uint8List(0),
        vorschlagDateiname: dateiname,
        fehler: const [
          'Konnte die Sheet-Struktur der Basis-Excel nicht auflösen.',
        ],
      );
    }

    // ─── 4. Shared-Strings-Tabelle lesen ────────────────────────────────
    final sharedStrings = _SharedStrings.fromArchive(archive);

    // ─── 5. DB-Artikel laden ────────────────────────────────────────────
    final alleArtikel = await _db.select(_db.products).get();
    final alleSchritte = await _db.select(_db.productSteps).get();
    final alleParameter =
        await _db.select(_db.productStepParameters).get();
    final alleMaschinen = await _db.select(_db.machines).get();
    final maschinenById = {for (final m in alleMaschinen) m.id: m};

    // Artikel nach Artikelnummer gruppieren (= Sheetname der Vorlage)
    int artikelAktualisiert = 0;
    int schritteGeschrieben = 0;
    int parameterGeschrieben = 0;
    final artikelNichtInVorlage = <String>[];
    final warnungen = <String>[];

    // ─── 6. Pro Artikel: Sheet-XML aktualisieren ────────────────────────
    for (final artikel in alleArtikel) {
      if (artikel.deletedAt != null) continue;

      final sheetXmlPfad = sheetInfo[artikel.artikelnummer];
      if (sheetXmlPfad == null) {
        // Artikel in DB, aber nicht in Vorlage → neu angelegter Artikel.
        // Wird in einem späteren Build als neues Sheet behandelt.
        artikelNichtInVorlage.add(artikel.artikelnummer);
        continue;
      }

      final schritte = alleSchritte
          .where(
            (s) => s.productId == artikel.id && s.deletedAt == null,
          )
          .toList()
        ..sort((a, b) => a.reihenfolge.compareTo(b.reihenfolge));

      final paramsByStep = <String, List<ProductStepParameter>>{};
      for (final p in alleParameter) {
        if (p.deletedAt != null) continue;
        paramsByStep.putIfAbsent(p.stepId, () => []).add(p);
      }
      for (final list in paramsByStep.values) {
        list.sort((a, b) => a.reihenfolge.compareTo(b.reihenfolge));
      }

      final archiveFile = archive.findFile(sheetXmlPfad);
      if (archiveFile == null) {
        warnungen.add(
          'Artikel ${artikel.artikelnummer}: Sheet-XML "$sheetXmlPfad" '
          'nicht im ZIP gefunden — übersprungen.',
        );
        continue;
      }

      try {
        final xmlBytes = archiveFile.content as List<int>;
        final doc = XmlDocument.parse(utf8.decode(xmlBytes));

        final aktualisiert = _aktualisiereSheetXml(
          doc: doc,
          artikel: artikel,
          schritte: schritte,
          paramsByStep: paramsByStep,
          maschinenById: maschinenById,
          sharedStrings: sharedStrings,
          warnungen: warnungen,
          artikelLabel: artikel.artikelnummer,
        );

        if (aktualisiert.schritte > 0 || aktualisiert.parameter > 0) {
          artikelAktualisiert++;
        }
        schritteGeschrieben += aktualisiert.schritte;
        parameterGeschrieben += aktualisiert.parameter;

        final neuesXml = utf8.encode(doc.toXmlString(pretty: false));
        archive.addFile(
          ArchiveFile(
            archiveFile.name,
            neuesXml.length,
            neuesXml,
          ),
        );
      } catch (e) {
        warnungen.add(
          'Artikel ${artikel.artikelnummer}: Fehler beim Aktualisieren '
          'des Sheets ($e) — Original bleibt erhalten.',
        );
      }
    }

    // ─── 7. Shared-Strings neu schreiben (falls wir welche hinzugefügt
    //       haben, passiert aktuell nicht weil wir inline strings nutzen,
    //       aber robust für später) ──────────────────────────────────────
    sharedStrings.writeBackIfDirty(archive);

    // ─── 8. ZIP neu packen ──────────────────────────────────────────────
    final encoder = ZipEncoder();
    final neuesBytes = Uint8List.fromList(encoder.encode(archive)!);

    return ExportResultV3(
      bytes: neuesBytes,
      vorschlagDateiname: _generiereExportDateiname(dateiname),
      artikelAktualisiert: artikelAktualisiert,
      schritteGeschrieben: schritteGeschrieben,
      parameterGeschrieben: parameterGeschrieben,
      artikelNichtInVorlage: artikelNichtInVorlage,
      warnungen: warnungen,
    );
  }

  /// Generiert einen Dateinamen mit Zeitstempel als Vorschlag
  /// für den Speichern-Dialog.
  String _generiereExportDateiname(String originalname) {
    final jetzt = DateTime.now();
    final ts = '${jetzt.year}${_pad(jetzt.month)}${_pad(jetzt.day)}_'
        '${_pad(jetzt.hour)}${_pad(jetzt.minute)}';
    final basis = originalname.replaceAll(RegExp(r'\.xlsx$'), '');
    return '${basis}_export_$ts.xlsx';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  // ═════════════════════════════════════════════════════════════════════════
  // ZIP/XML-Hilfsmethoden
  // ═════════════════════════════════════════════════════════════════════════

  /// Liest `xl/workbook.xml` + `xl/_rels/workbook.xml.rels` und liefert
  /// ein Mapping Sheet-Name → XML-Pfad im ZIP.
  Map<String, String> _ermittleSheetXmlPfade(Archive archive) {
    final result = <String, String>{};

    final workbookFile = archive.findFile('xl/workbook.xml');
    final relsFile = archive.findFile('xl/_rels/workbook.xml.rels');
    if (workbookFile == null || relsFile == null) return result;

    final workbookDoc = XmlDocument.parse(
      utf8.decode(workbookFile.content as List<int>),
    );
    final relsDoc = XmlDocument.parse(
      utf8.decode(relsFile.content as List<int>),
    );

    // rId → Target (z.B. "rId3" → "worksheets/sheet3.xml")
    final rIdToTarget = <String, String>{};
    for (final rel in relsDoc.findAllElements('Relationship')) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id != null && target != null) {
        rIdToTarget[id] = target;
      }
    }

    // Sheet-Name → rId
    for (final sheet in workbookDoc.findAllElements('sheet')) {
      final name = sheet.getAttribute('name');
      final rid = sheet.getAttribute('id', namespace: _nsRel) ??
          sheet.getAttribute('r:id');
      if (name != null && rid != null) {
        final target = rIdToTarget[rid];
        if (target != null) {
          final fullPath = 'xl/$target';
          result[name] = fullPath;
        }
      }
    }
    return result;
  }

  /// Aktualisiert ein einzelnes Sheet-XML mit den DB-Daten.
  _AktualisierungsStats _aktualisiereSheetXml({
    required XmlDocument doc,
    required Product artikel,
    required List<ProductStep> schritte,
    required Map<String, List<ProductStepParameter>> paramsByStep,
    required Map<String, Machine> maschinenById,
    required _SharedStrings sharedStrings,
    required List<String> warnungen,
    required String artikelLabel,
  }) {
    final sheetData = doc.findAllElements('sheetData').firstOrNull;
    if (sheetData == null) return _AktualisierungsStats(0, 0);

    final labelRows = _findeSchrittLabelZeilen(doc, sharedStrings);

    int schritteAktualisiert = 0;
    int parameterAktualisiert = 0;

    for (final step in schritte) {
      final col = step.reihenfolge; // 1..10 → Spalte B..K
      if (col < 1 || col > 10) continue;
      final colLetter = _spaltenBuchstabe(col + 1);

      if (labelRows.abteilungRow != null) {
        _setzeZelleInlineStr(
          sheetData,
          row: labelRows.abteilungRow!,
          colLetter: colLetter,
          wert: _abteilungLabel(step.abteilung),
        );
      }
      if (labelRows.prozessschrittRow != null && step.prozessschritt != null) {
        _setzeZelleInlineStr(
          sheetData,
          row: labelRows.prozessschrittRow!,
          colLetter: colLetter,
          wert: step.prozessschritt!,
        );
      }
      if (labelRows.anlagenRow != null) {
        String? anlage = step.maschine;
        if (anlage == null && step.maschineId != null) {
          anlage = maschinenById[step.maschineId]?.name;
        }
        if (anlage != null) {
          _setzeZelleInlineStr(
            sheetData,
            row: labelRows.anlagenRow!,
            colLetter: colLetter,
            wert: anlage,
          );
        }
      }
      if (labelRows.personenRow != null && step.basisMitarbeiter > 0) {
        _setzeZelleZahl(
          sheetData,
          row: labelRows.personenRow!,
          colLetter: colLetter,
          wert: step.basisMitarbeiter.toDouble(),
        );
      }
      if (labelRows.mengeRow != null && step.basisMengeKg > 0) {
        _setzeZelleZahl(
          sheetData,
          row: labelRows.mengeRow!,
          colLetter: colLetter,
          wert: step.basisMengeKg,
        );
      }
      if (labelRows.zeitRow != null && step.basisDauerMinuten > 0) {
        // hh:mm als Bruchteil eines Tages (Excel-Konvention für Zeiten)
        final bruchteilTag = step.basisDauerMinuten / (24 * 60);
        _setzeZelleZahl(
          sheetData,
          row: labelRows.zeitRow!,
          colLetter: colLetter,
          wert: bruchteilTag,
        );
      }
      schritteAktualisiert++;

      // Parameter-Zeilen aktualisieren
      final stepParams = paramsByStep[step.id] ?? [];
      for (final param in stepParams) {
        final paramRow = _findeZeileMitLabelInA(
          doc,
          sharedStrings,
          param.parameterName,
        );
        if (paramRow == null) continue;
        final wert = param.wert ?? '';
        if (wert.isEmpty) continue;

        final zahl = double.tryParse(wert.replaceAll(',', '.'));
        if (zahl != null) {
          _setzeZelleZahl(
            sheetData,
            row: paramRow,
            colLetter: colLetter,
            wert: zahl,
          );
        } else {
          _setzeZelleInlineStr(
            sheetData,
            row: paramRow,
            colLetter: colLetter,
            wert: wert,
          );
        }
        parameterAktualisiert++;
      }
    }

    return _AktualisierungsStats(schritteAktualisiert, parameterAktualisiert);
  }

  // ─── Zeilen-Lokalisierung ─────────────────────────────────────────────

  String? _leseZelleA(XmlElement rowElement, _SharedStrings sharedStrings) {
    for (final cell in rowElement.findElements('c')) {
      final ref = cell.getAttribute('r') ?? '';
      if (!ref.startsWith('A')) continue;
      return _leseZellwertAlsString(cell, sharedStrings);
    }
    return null;
  }

  String? _leseZellwertAlsString(
    XmlElement cell,
    _SharedStrings sharedStrings,
  ) {
    final type = cell.getAttribute('t');
    if (type == 's') {
      final vElement = cell.findElements('v').firstOrNull;
      final idx = int.tryParse(vElement?.innerText ?? '');
      if (idx != null) return sharedStrings.getString(idx);
    } else if (type == 'inlineStr') {
      final is_ = cell.findElements('is').firstOrNull;
      final t = is_?.findElements('t').firstOrNull;
      return t?.innerText;
    } else if (type == 'str') {
      return cell.findElements('v').firstOrNull?.innerText;
    } else {
      return cell.findElements('v').firstOrNull?.innerText;
    }
    return null;
  }

  _SchrittLabelZeilen _findeSchrittLabelZeilen(
    XmlDocument doc,
    _SharedStrings sharedStrings,
  ) {
    int? abteilung, prozess, anlagen, personen, menge, zeit;
    final sheetData = doc.findAllElements('sheetData').firstOrNull;
    if (sheetData == null) return _SchrittLabelZeilen();

    for (final row in sheetData.findElements('row')) {
      final rNum = int.tryParse(row.getAttribute('r') ?? '');
      if (rNum == null) continue;
      final label = _leseZelleA(row, sharedStrings)?.trim();
      if (label == null) continue;
      switch (label) {
        case 'Abteilung':
          abteilung = rNum;
        case 'Prozessschritt':
          prozess = rNum;
        case 'Anlagen':
          anlagen = rNum;
        case 'Personen':
          personen = rNum;
        case 'Menge (kg)':
          menge = rNum;
        case 'Zeit (hh:mm)':
          zeit = rNum;
      }
    }
    return _SchrittLabelZeilen(
      abteilungRow: abteilung,
      prozessschrittRow: prozess,
      anlagenRow: anlagen,
      personenRow: personen,
      mengeRow: menge,
      zeitRow: zeit,
    );
  }

  int? _findeZeileMitLabelInA(
    XmlDocument doc,
    _SharedStrings sharedStrings,
    String gesuchtesLabel,
  ) {
    final sheetData = doc.findAllElements('sheetData').firstOrNull;
    if (sheetData == null) return null;
    final ziel = gesuchtesLabel.trim();
    for (final row in sheetData.findElements('row')) {
      final rNum = int.tryParse(row.getAttribute('r') ?? '');
      if (rNum == null) continue;
      final label = _leseZelleA(row, sharedStrings)?.trim();
      if (label == ziel) return rNum;
    }
    return null;
  }

  // ─── Zellen-Manipulation ──────────────────────────────────────────────

  void _setzeZelleInlineStr(
    XmlElement sheetData, {
    required int row,
    required String colLetter,
    required String wert,
  }) {
    final cellRef = '$colLetter$row';
    final rowElement = _findeOderLegeRowAn(sheetData, row);
    final cell = _findeOderLegeCellAn(rowElement, cellRef);

    final styleAttr = cell.getAttribute('s');

    cell.attributes.clear();
    cell.children.clear();
    cell.setAttribute('r', cellRef);
    if (styleAttr != null) cell.setAttribute('s', styleAttr);
    cell.setAttribute('t', 'inlineStr');

    final is_ = XmlElement(XmlName('is'));
    final t = XmlElement(XmlName('t'));
    t.setAttribute('xml:space', 'preserve');
    t.children.add(XmlText(wert));
    is_.children.add(t);
    cell.children.add(is_);
  }

  void _setzeZelleZahl(
    XmlElement sheetData, {
    required int row,
    required String colLetter,
    required double wert,
  }) {
    final cellRef = '$colLetter$row';
    final rowElement = _findeOderLegeRowAn(sheetData, row);
    final cell = _findeOderLegeCellAn(rowElement, cellRef);

    final styleAttr = cell.getAttribute('s');

    cell.attributes.clear();
    cell.children.clear();
    cell.setAttribute('r', cellRef);
    if (styleAttr != null) cell.setAttribute('s', styleAttr);

    final v = XmlElement(XmlName('v'));
    final zahlStr = wert == wert.roundToDouble()
        ? wert.toInt().toString()
        : wert.toString();
    v.children.add(XmlText(zahlStr));
    cell.children.add(v);
  }

  XmlElement _findeOderLegeRowAn(XmlElement sheetData, int rowNum) {
    for (final row in sheetData.findElements('row')) {
      final r = int.tryParse(row.getAttribute('r') ?? '');
      if (r == rowNum) return row;
    }
    final neu = XmlElement(XmlName('row'));
    neu.setAttribute('r', rowNum.toString());

    int? insertBefore;
    final rows = sheetData.findElements('row').toList();
    for (var i = 0; i < rows.length; i++) {
      final r = int.tryParse(rows[i].getAttribute('r') ?? '');
      if (r != null && r > rowNum) {
        insertBefore = i;
        break;
      }
    }
    if (insertBefore != null) {
      final index = sheetData.children.indexOf(rows[insertBefore]);
      sheetData.children.insert(index, neu);
    } else {
      sheetData.children.add(neu);
    }
    return neu;
  }

  XmlElement _findeOderLegeCellAn(XmlElement rowElement, String cellRef) {
    for (final cell in rowElement.findElements('c')) {
      if (cell.getAttribute('r') == cellRef) return cell;
    }
    final neu = XmlElement(XmlName('c'));
    neu.setAttribute('r', cellRef);

    final targetCol = _spaltenIndex(cellRef);
    final cells = rowElement.findElements('c').toList();
    int? insertBefore;
    for (var i = 0; i < cells.length; i++) {
      final existingRef = cells[i].getAttribute('r') ?? '';
      if (_spaltenIndex(existingRef) > targetCol) {
        insertBefore = i;
        break;
      }
    }
    if (insertBefore != null) {
      final index = rowElement.children.indexOf(cells[insertBefore]);
      rowElement.children.insert(index, neu);
    } else {
      rowElement.children.add(neu);
    }
    return neu;
  }

  // ─── Koordinaten-Utilities ────────────────────────────────────────────

  String _spaltenBuchstabe(int index) {
    if (index < 1) return 'A';
    var n = index;
    final result = StringBuffer();
    while (n > 0) {
      final mod = (n - 1) % 26;
      result.write(String.fromCharCode(65 + mod));
      n = (n - 1) ~/ 26;
    }
    return result.toString().split('').reversed.join();
  }

  int _spaltenIndex(String cellRef) {
    final match = RegExp(r'^([A-Z]+)').firstMatch(cellRef);
    if (match == null) return 0;
    final letters = match.group(1)!;
    var result = 0;
    for (final c in letters.codeUnits) {
      result = result * 26 + (c - 64);
    }
    return result;
  }

  String _abteilungLabel(String dbValue) {
    switch (dbValue) {
      case 'zerlegung':
        return 'Zerlegung';
      case 'wurstkueche':
        return 'Wurstküche';
      case 'kutterabteilung':
        return 'Kutterabteilung';
      case 'bratstrasse':
        return 'Bratstraße';
      case 'schneideabteilung':
        return 'Schneideabteilung';
      case 'verpackung':
        return 'Verpackung';
      case 'verpackung_tef1':
        return 'Verpackung Tef1';
      default:
        return dbValue;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Hilfsklassen
// ═══════════════════════════════════════════════════════════════════════════

class _AktualisierungsStats {
  _AktualisierungsStats(this.schritte, this.parameter);
  final int schritte;
  final int parameter;
}

class _SchrittLabelZeilen {
  _SchrittLabelZeilen({
    this.abteilungRow,
    this.prozessschrittRow,
    this.anlagenRow,
    this.personenRow,
    this.mengeRow,
    this.zeitRow,
  });

  final int? abteilungRow;
  final int? prozessschrittRow;
  final int? anlagenRow;
  final int? personenRow;
  final int? mengeRow;
  final int? zeitRow;
}

/// Wrapper um die Shared-Strings-Tabelle des Workbooks.
class _SharedStrings {
  _SharedStrings._(this._strings, this._originalFile);

  final List<String> _strings;
  final ArchiveFile? _originalFile;
  final bool _dirty = false;

  factory _SharedStrings.fromArchive(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return _SharedStrings._(<String>[], null);
    final doc = XmlDocument.parse(
      utf8.decode(file.content as List<int>),
    );
    final strings = <String>[];
    for (final si in doc.findAllElements('si')) {
      final tDirekt = si.findElements('t').firstOrNull;
      if (tDirekt != null) {
        strings.add(tDirekt.innerText);
        continue;
      }
      final buffer = StringBuffer();
      for (final r in si.findElements('r')) {
        for (final t in r.findElements('t')) {
          buffer.write(t.innerText);
        }
      }
      strings.add(buffer.toString());
    }
    return _SharedStrings._(strings, file);
  }

  String getString(int index) {
    if (index < 0 || index >= _strings.length) return '';
    return _strings[index];
  }

  void writeBackIfDirty(Archive archive) {
    if (!_dirty || _originalFile == null) return;
    // Aktuell nicht genutzt — wir schreiben nur mit inlineStr.
    // Methode bleibt als Platzhalter für spätere Erweiterung.
  }
}

// Extension für firstOrNull auf Iterable (falls nicht verfügbar)
extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}