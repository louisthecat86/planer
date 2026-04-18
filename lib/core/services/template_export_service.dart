import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../constants/product_groups.dart';
import '../constants/product_group_fields.dart';

/// Erzeugt die Stammdaten-Excel-Vorlage mit gruppenspezifischen Feldern.
///
/// Aufbau:
///   1. **Übersicht** — filterbare Gesamtliste aller Artikel mit
///      Hyperlinks zu den jeweiligen Produkt-Sheets
///   2. **Rohwaren** — globale Rohstoff-Definitionen
///   3. **Ein Beispiel-Sheet pro Produktgruppe** mit:
///      - Zurück-Link zur Übersicht
///      - Stammdaten-Block (allgemein + gruppenspezifisch)
///        · Zeile 1: Label (Pflichtfelder gelb hinterlegt)
///        · Zeile 2: Einheit (grau, kursiv)
///        · Zeile 3: Beispiel-Datenzeile
///      - Produktionsschritte (nur Header, vom Nutzer auszufüllen)
///      - Rezeptur (nur Header)
///      - Produktionshistorie (nur Header)
///      - Tab-Farbe je nach Gruppe
///
/// Der Nutzer kann die Beispiel-Sheets kopieren (Excel-Rechtsklick auf Tab →
/// "Verschieben/Kopieren → Kopie erstellen") und als Blaupause für neue
/// Artikel verwenden. Jeder Artikel, der importiert werden soll, muss in
/// der Übersicht eingetragen sein.
class TemplateExportService {
  TemplateExportService._();

  /// Generiert die Vorlage und lässt den Nutzer einen Speicherort wählen.
  static Future<String?> generateAndSave() async {
    final excel = Excel.createExcel();

    // 1. Übersicht-Sheet
    _buildUebersichtSheet(excel);

    // 2. Rohwaren-Sheet
    _buildRohwarenSheet(excel);

    // 3. Pro Produktgruppe ein Beispiel-Sheet
    for (final group in ProductGroup.values) {
      final beispiel = _beispielFuer(group);
      _buildProduktSheet(excel, beispiel);
    }

    // Standard-Sheet entfernen
    excel.delete('Sheet1');

    // Übersicht als aktives Sheet beim Öffnen (falls API unterstützt)
    try {
      // ignore: avoid_dynamic_calls
      (excel as dynamic).setDefaultSheet('Übersicht');
    } catch (_) {
      // Nicht kritisch — Nutzer sieht beim Öffnen das erste Sheet
    }

    final bytes = excel.encode();
    if (bytes == null) return null;

    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Stammdaten-Vorlage speichern…',
      fileName: 'stammdaten_vorlage.xlsx',
      type: FileType.any,
    );

    if (outputPath == null) return null;

    final path = outputPath.endsWith('.xlsx') ? outputPath : '$outputPath.xlsx';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Übersicht
  // ══════════════════════════════════════════════════════════════════════

  static void _buildUebersichtSheet(Excel excel) {
    final sheet = excel['Übersicht'];

    final headers = [
      'Artikelnr',
      'Bezeichnung',
      'Produktgruppe',
      'Verpackungsart',
      'Gebinde (kg)',
      'MHD (Tage)',
      'Vorlaufzeit (Tage)',
      'Planungsgruppe',
      '→ Zum Produkt-Sheet',
    ];

    // Header-Zeile mit Style
    for (var col = 0; col < headers.length; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[col]);
      _applyStyle(cell, _headerStyle);
    }

    // Beispiel-Artikel pro Gruppe (Blaupause-Zeilen)
    var row = 1;
    for (final group in ProductGroup.values) {
      final beispiel = _beispielFuer(group);
      final sheetName = _sheetName(beispiel.artikelnr, beispiel.bezeichnung);

      _writeRowAt(sheet, row, [
        beispiel.artikelnr,
        beispiel.bezeichnung,
        group.label,
        beispiel.feldwerte['Verpackungsart'] ?? '',
        beispiel.feldwerte['Gebinde'] ?? '',
        beispiel.feldwerte['MHD'] ?? '',
        beispiel.feldwerte['Vorlaufzeit'] ?? '',
        '', // Planungsgruppe — leer
      ]);

      // Hyperlink in Spalte 8 (→ Zum Produkt-Sheet)
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row))
          .value = FormulaCellValue(
        "HYPERLINK(\"#'$sheetName'!A1\",\"→ $sheetName\")",
      );
      row++;
    }

    // AutoFilter auf den Datenbereich legen
    _trySetAutoFilter(sheet, row - 1, headers.length);

    // Erste Zeile fixieren
    _tryFreezeFirstRow(sheet);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Rohwaren
  // ══════════════════════════════════════════════════════════════════════

  static void _buildRohwarenSheet(Excel excel) {
    final sheet = excel['Rohwaren'];
    final headers = [
      'Name',
      'Einheit',
      'Lieferant',
      'Lieferzeit',
      'Chargen_Pflicht',
    ];

    // Header
    for (var col = 0; col < headers.length; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[col]);
      _applyStyle(cell, _headerStyle);
    }

    // Beispiele
    final beispiele = [
      ['Schweinefleisch S1', 'kg', 'Fleisch Müller GmbH', '2', 'Ja'],
      ['Schweinefleisch S8', 'kg', 'Fleisch Müller GmbH', '2', 'Ja'],
      ['Rindfleisch R1', 'kg', 'Fleisch Müller GmbH', '2', 'Ja'],
      ['Eis/Wasser', 'kg', '', '0', 'Nein'],
      ['Nitritpökelsalz', 'kg', 'Gewürz Schmidt', '5', 'Ja'],
      ['Gewürzmischung Brühwurst', 'kg', 'Gewürz Schmidt', '5', 'Ja'],
      ['Gewürzmischung Rohwurst', 'kg', 'Gewürz Schmidt', '5', 'Ja'],
      ['Starterkultur Rohwurst', 'kg', 'Kultur-Lab', '7', 'Ja'],
      ['Saitlinge 24mm', 'Stk', 'Darm Weber', '7', 'Ja'],
      ['Kunstdarm 60mm', 'Stk', 'Darm Weber', '7', 'Ja'],
      ['Paniermehl', 'kg', 'Bäcker Huber', '3', 'Ja'],
      ['Panko', 'kg', 'Bäcker Huber', '3', 'Ja'],
      ['Vollei flüssig', 'kg', 'Ei-Center', '2', 'Ja'],
      ['Mehl', 'kg', 'Mühle Berger', '3', 'Nein'],
      ['Vakuumbeutel 500g', 'Stk', 'Verpackung AG', '10', 'Nein'],
      ['MAP-Schale 5er', 'Stk', 'Verpackung AG', '10', 'Nein'],
      ['Skin-Pack Folie', 'Stk', 'Verpackung AG', '10', 'Nein'],
    ];

    for (var i = 0; i < beispiele.length; i++) {
      _writeRowAt(sheet, i + 1, beispiele[i]);
    }

    _tryFreezeFirstRow(sheet);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Pro-Produkt-Sheet
  // ══════════════════════════════════════════════════════════════════════

  static void _buildProduktSheet(Excel excel, _BeispielArtikel beispiel) {
    final name = _sheetName(beispiel.artikelnr, beispiel.bezeichnung);
    final sheet = excel[name];

    // Tab-Farbe je Gruppe
    _trySetTabColor(sheet, _tabColorFor(beispiel.group));

    var row = 0;

    // ── Link zurück zur Übersicht ─────────────────────────────────────
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = const FormulaCellValue(
      "HYPERLINK(\"#'Übersicht'!A1\",\"← Zurück zur Übersicht\")",
    );
    row += 2;

    // ── Block 1: Stammdaten ───────────────────────────────────────────
    _setSectionHeader(sheet, row, 0, '== STAMMDATEN ==');
    row++;

    // Felder für diese Gruppe zusammenstellen
    final felder = ProductGroupFields.alleFelderFuer(beispiel.group);

    // Zeile 1: Label (Pflichtfelder gelb)
    for (var col = 0; col < felder.length; col++) {
      final field = felder[col];
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = TextCellValue(field.label);
      _applyStyle(cell, field.required ? _pflichtStyle : _headerStyle);
    }
    final einheitenRow = row + 1;
    final datenRow = row + 2;

    // Zeile 2: Einheit (grau, kursiv)
    for (var col = 0; col < felder.length; col++) {
      final field = felder[col];
      final einheitText = field.unit ?? '';
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: einheitenRow),
      );
      cell.value = TextCellValue(einheitText);
      _applyStyle(cell, _einheitStyle);
    }

    // Zeile 3: Beispiel-Datenzeile
    for (var col = 0; col < felder.length; col++) {
      final field = felder[col];
      final wert = _valueFor(field, beispiel);
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: datenRow),
      );
      cell.value = TextCellValue(wert);
    }

    row = datenRow + 3;

    // ── Block 2: Produktionsschritte (leer, nur Header) ───────────────
    _setSectionHeader(sheet, row, 0, '== PRODUKTIONSSCHRITTE ==');
    row++;

    const schritteHeaders = [
      'Schritt',
      'Abteilung',
      'Basis_Menge',
      'Dauer',
      'Fixzeit',
      'Mitarbeiter',
      'Ausbeute',
      'Wartezeit',
      'Min_Charge',
      'Max_Charge',
      'Kerntemperatur',
      'Raumtemperatur',
      'Maschine',
      'Kochkammer_Programm',
      'Klimaprogramm',
      'Bratparameter',
      'Notizen',
    ];
    const schritteEinheiten = [
      '(Nr)',
      '',
      '(kg)',
      '(min)',
      '(min)',
      '(Anz)',
      '(0-1)',
      '(min)',
      '(kg)',
      '(kg)',
      '(°C)',
      '(°C)',
      '',
      '',
      '',
      '',
      '',
    ];
    _writeHeadersWithUnits(sheet, row, schritteHeaders, schritteEinheiten);
    row += 2;
    // Platz für ca. 10 Schritte — Nutzer füllt manuell
    row += 10;

    // ── Block 3: Rezeptur (leer, nur Header) ──────────────────────────
    _setSectionHeader(sheet, row, 0, '== REZEPTUR ==');
    row++;
    const rezepturHeaders = ['Rohware', 'Menge_pro_kg', 'Toleranz'];
    const rezepturEinheiten = ['', '(kg/kg)', '(%)'];
    _writeHeadersWithUnits(sheet, row, rezepturHeaders, rezepturEinheiten);
    row += 2;
    // Platz für ca. 15 Zeilen
    row += 15;

    // ── Block 4: Produktionshistorie (leer, nur Header) ───────────────
    _setSectionHeader(sheet, row, 0, '== PRODUKTIONSHISTORIE ==');
    row++;
    const historieHeaders = [
      'Datum',
      'Schritt',
      'Menge_kg',
      'Dauer_min',
      'Mitarbeiter',
      'Notizen',
    ];
    const historieEinheiten = ['(YYYY-MM-DD)', '(Nr)', '(kg)', '(min)', '(Anz)', ''];
    _writeHeadersWithUnits(sheet, row, historieHeaders, historieEinheiten);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Hilfsfunktionen: Styling
  // ══════════════════════════════════════════════════════════════════════

  /// Standard-Header-Style (fetter dunkelblauer Text, hellgrauer Hintergrund).
  static CellStyle get _headerStyle => CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('E0E0E0'),
        fontColorHex: ExcelColor.fromHexString('212121'),
        horizontalAlign: HorizontalAlign.Left,
      );

  /// Pflichtfeld-Style (fetter Text, gelber Hintergrund).
  static CellStyle get _pflichtStyle => CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FFF9C4'),
        fontColorHex: ExcelColor.fromHexString('BF360C'),
        horizontalAlign: HorizontalAlign.Left,
      );

  /// Einheiten-Style (kursiv, grau).
  static CellStyle get _einheitStyle => CellStyle(
        italic: true,
        fontColorHex: ExcelColor.fromHexString('757575'),
        horizontalAlign: HorizontalAlign.Left,
      );

  /// Section-Header-Style (== BLOCK ==, fett und groß).
  static CellStyle get _sectionStyle => CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('455A64'),
        fontColorHex: ExcelColor.fromHexString('FFFFFF'),
      );

  static void _applyStyle(Data cell, CellStyle style) {
    cell.cellStyle = style;
  }

  static void _setSectionHeader(Sheet sheet, int row, int col, String text) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = TextCellValue(text);
    _applyStyle(cell, _sectionStyle);
  }

  static void _writeHeadersWithUnits(
    Sheet sheet,
    int startRow,
    List<String> headers,
    List<String> einheiten,
  ) {
    for (var col = 0; col < headers.length; col++) {
      final headerCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: startRow),
      );
      headerCell.value = TextCellValue(headers[col]);
      _applyStyle(headerCell, _headerStyle);

      final einheitCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: startRow + 1),
      );
      einheitCell.value = TextCellValue(
        col < einheiten.length ? einheiten[col] : '',
      );
      _applyStyle(einheitCell, _einheitStyle);
    }
  }

  static void _writeRowAt(Sheet sheet, int rowIndex, List<String> values) {
    for (var col = 0; col < values.length; col++) {
      sheet
          .cell(CellIndex.indexByColumnRow(
            columnIndex: col,
            rowIndex: rowIndex,
          ),)
          .value = TextCellValue(values[col]);
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Defensive Feature-Calls (falls API-Version es nicht unterstützt)
  // ══════════════════════════════════════════════════════════════════════

  /// Setzt die Tab-Farbe, falls das excel-Paket das unterstützt.
  /// Fail-silent bei API-Inkompatibilität.
  static void _trySetTabColor(Sheet sheet, String hexColor) {
    try {
      // Hex ohne führendes '#' übergeben (excel-Paket-Konvention)
      final clean = hexColor.startsWith('#') ? hexColor.substring(1) : hexColor;
      // ignore: avoid_dynamic_calls
      (sheet as dynamic).sheetProperties?.tabColor =
          ExcelColor.fromHexString(clean);
    } catch (_) {
      // Fallback: keine Tab-Farbe
    }
  }

  /// Versucht AutoFilter auf den Datenbereich zu setzen.
  static void _trySetAutoFilter(Sheet sheet, int lastRow, int colCount) {
    try {
      // ignore: avoid_dynamic_calls
      (sheet as dynamic).setAutoFilter(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(
          columnIndex: colCount - 1,
          rowIndex: lastRow,
        ),
      );
    } catch (_) {
      // Nutzer muss Filter bei Bedarf manuell setzen (Strg+Umschalt+L)
    }
  }

  /// Versucht die erste Zeile einzufrieren.
  static void _tryFreezeFirstRow(Sheet sheet) {
    try {
      // ignore: avoid_dynamic_calls
      (sheet as dynamic).freezePane(rowIndex: 1);
    } catch (_) {
      // Fallback: kein Freeze, Nutzer kann in Excel manuell setzen
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Farben pro Produktgruppe (Tab-Farbe)
  // ══════════════════════════════════════════════════════════════════════

  static String _tabColorFor(ProductGroup group) {
    switch (group) {
      case ProductGroup.bruehwurst:
        return '#E57373'; // hellrot
      case ProductGroup.rohwurst:
        return '#B71C1C'; // dunkelrot
      case ProductGroup.kochpoekelware:
        return '#F48FB1'; // rosa
      case ProductGroup.rohpoekelware:
        return '#8D6E63'; // braun
      case ProductGroup.aufschnitt:
        return '#64B5F6'; // hellblau
      case ProductGroup.bratstrasseNatur:
        return '#FFB74D'; // orange
      case ProductGroup.bratstrassePaniert:
        return '#FFA000'; // dunkelorange/gold
      case ProductGroup.hackproduktGegart:
        return '#9575CD'; // violett
      case ProductGroup.hackproduktRoh:
        return '#CE93D8'; // hellviolett
      case ProductGroup.braten:
        return '#5D4037'; // dunkelbraun
      case ProductGroup.sousVide:
        return '#4DB6AC'; // türkis
      case ProductGroup.angebrateneBruehwurst:
        return '#FF7043'; // rot-orange
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Sheet-Namen
  // ══════════════════════════════════════════════════════════════════════

  /// Erzeugt einen gültigen Sheet-Namen (max. 31 Zeichen, keine [ ] : * ? / \).
  static String _sheetName(String nr, String bezeichnung) {
    final clean = bezeichnung
        .replaceAll(RegExp(r'[\\/:*?\[\]]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final raw = '${nr}_$clean';
    return raw.length > 31 ? raw.substring(0, 31) : raw;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Wert-Mapping für Beispiel-Datenzeile
  // ══════════════════════════════════════════════════════════════════════

  static String _valueFor(FieldSpec field, _BeispielArtikel b) {
    // Erst im feldwerte-Map nachschauen (gruppenspezifisch)
    if (b.feldwerte.containsKey(field.label)) {
      return b.feldwerte[field.label] ?? '';
    }
    // Allgemeine Felder über label-Match
    switch (field.key) {
      case 'artikelnummer':
        return b.artikelnr;
      case 'artikelbezeichnung':
        return b.bezeichnung;
      case 'beschreibung':
        return b.beschreibung;
      case 'produktgruppe':
        return b.group.label;
      default:
        return '';
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Beispiel-Artikel pro Gruppe
  // ══════════════════════════════════════════════════════════════════════

  static _BeispielArtikel _beispielFuer(ProductGroup group) {
    switch (group) {
      case ProductGroup.bruehwurst:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'BW-001',
          bezeichnung: 'Leberkäse fein',
          beschreibung: 'Feiner Leberkäse 500g',
          feldwerte: {
            'Verpackungsart': 'Vakuum',
            'Gebinde': '0.5',
            'MHD': '21',
            'Gesamtausbeute': '0.85',
            'Vorlaufzeit': '2',
            'Brät-Feinheit': 'fein',
            'Kutter-Endtemp': '12.0',
            'Kochkammer-Programm': 'Programm 12',
            'Räucherart': 'warm',
            'Ziel-Kerntemp': '72.0',
          },
        );
      case ProductGroup.rohwurst:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'RW-001',
          bezeichnung: 'Salami Milano',
          beschreibung: 'Luftgetrocknete Salami 200g',
          feldwerte: {
            'Verpackungsart': 'Vakuum',
            'Gebinde': '0.2',
            'MHD': '60',
            'Gesamtausbeute': '0.65',
            'Vorlaufzeit': '28',
            'Startkultur': 'Bactoferm T-SPX',
            'Reifezeit': '21',
            'Klimaprogramm': 'Reife-Prog-A',
            'Ziel-pH': '5.30',
            'Ziel-aw-Wert': '0.900',
            'Gewichtsverlust': '35.0',
            'Räucherart': 'kalt',
          },
        );
      case ProductGroup.kochpoekelware:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'KP-001',
          bezeichnung: 'Kochschinken',
          beschreibung: 'Kochschinken am Stück',
          feldwerte: {
            'Verpackungsart': 'Vakuum',
            'Gebinde': '2.5',
            'MHD': '30',
            'Gesamtausbeute': '1.05',
            'Vorlaufzeit': '4',
            'Pökelart': 'injektion',
            'Lake-Konzentration': '15.0',
            'Pökelzeit': '3',
            'Tumbelzeit': '180',
            'Ziel-Kerntemp': '68.0',
            'Räucherart': 'warm',
          },
        );
      case ProductGroup.rohpoekelware:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'RP-001',
          bezeichnung: 'Schinkenspeck',
          beschreibung: 'Luftgetrockneter Schinkenspeck',
          feldwerte: {
            'Verpackungsart': 'Vakuum',
            'Gebinde': '1.0',
            'MHD': '120',
            'Gesamtausbeute': '0.70',
            'Vorlaufzeit': '90',
            'Pökelart': 'trocken',
            'Pökelzeit': '14',
            'Reifezeit': '70',
            'Trocknungsverlust': '30.0',
            'Ziel-aw-Wert': '0.920',
            'Räucherart': 'kalt',
          },
        );
      case ProductGroup.aufschnitt:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'AS-001',
          bezeichnung: 'Kochschinken Aufschnitt 100g',
          beschreibung: 'Kochschinken in Scheiben, MAP',
          feldwerte: {
            'Verpackungsart': 'MAP',
            'Gebinde': '0.1',
            'MHD': '14',
            'Vorlaufzeit': '1',
            'Basis-Artikelnr': 'KP-001',
            'Scheibendicke': '1.5',
            'Scheiben pro Packung': '8',
            'Packungsgewicht': '100',
            'MAP-Gasgemisch': '70% N₂ / 30% CO₂',
          },
        );
      case ProductGroup.bratstrasseNatur:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'BN-001',
          bezeichnung: 'Frikadelle 80g',
          beschreibung: 'Hausmacher Frikadelle, gebraten',
          feldwerte: {
            'Verpackungsart': 'MAP',
            'Gebinde': '0.4',
            'MHD': '10',
            'Gesamtausbeute': '0.82',
            'Vorlaufzeit': '1',
            'Formgewicht': '80',
            'Form': 'rund',
            'Ziel-Kerntemp': '75.0',
            'Bratgrad': 'durch',
          },
        );
      case ProductGroup.bratstrassePaniert:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'BP-001',
          bezeichnung: 'Schnitzel paniert 200g',
          beschreibung: 'Schweineschnitzel paniert, gebraten',
          feldwerte: {
            'Verpackungsart': 'Skin-Pack',
            'Gebinde': '0.2',
            'MHD': '7',
            'Gesamtausbeute': '0.78',
            'Vorlaufzeit': '1',
            'Panierart': 'Paniermehl',
            'Panier-Aufnahme': '22.0',
            'Formgewicht': '200',
            'Ziel-Kerntemp': '72.0',
          },
        );
      case ProductGroup.hackproduktGegart:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'HG-001',
          bezeichnung: 'Chili con Carne',
          beschreibung: 'Fertiggericht mit Hackfleisch',
          feldwerte: {
            'Verpackungsart': 'Vakuum',
            'Gebinde': '0.5',
            'MHD': '14',
            'Vorlaufzeit': '1',
            'Fleischanteil-Typ': 'S8',
            'Ziel-Kerntemp': '75.0',
            'Abkühlgradient': 'auf 7°C in 90 min',
          },
        );
      case ProductGroup.hackproduktRoh:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'HR-001',
          bezeichnung: 'Hackfleisch gemischt',
          beschreibung: 'Rind/Schwein 50/50, tagesfrisch',
          feldwerte: {
            'Verpackungsart': 'MAP',
            'Gebinde': '0.5',
            'MHD': '3',
            'Vorlaufzeit': '0',
            'Fleischanteil-Typ': 'gemischt',
            'Gesamtdurchlaufzeit max': '4',
            'Wolf-Lochscheibe': '3.0',
          },
        );
      case ProductGroup.braten:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'BR-001',
          bezeichnung: 'Rollbraten mit Füllung',
          beschreibung: 'Schweinerollbraten, vorgegart',
          feldwerte: {
            'Verpackungsart': 'Vakuum',
            'Gebinde': '1.5',
            'MHD': '14',
            'Vorlaufzeit': '2',
            'Variante': 'vorgegart',
            'Füllung': 'Semmelfüllung',
            'Netzbindung': 'Ja',
            'Ziel-Kerntemp': '68.0',
          },
        );
      case ProductGroup.sousVide:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'SV-001',
          bezeichnung: 'Pulled Pork',
          beschreibung: 'Schweinenacken Sous Vide gegart',
          feldwerte: {
            'Verpackungsart': 'Vakuum',
            'Gebinde': '1.0',
            'MHD': '30',
            'Vorlaufzeit': '2',
            'SV-Badtemp': '74.0',
            'SV-Garzeit': '24.0',
            'Ziel-Kerntemp': '72.0',
            'Abkühlgradient': 'auf 3°C in 120 min',
          },
        );
      case ProductGroup.angebrateneBruehwurst:
        return _BeispielArtikel(
          group: group,
          artikelnr: 'AB-001',
          bezeichnung: 'Weiße Bratwurst angebraten',
          beschreibung: 'Weiße Bratwurst, oberflächlich angebraten',
          feldwerte: {
            'Verpackungsart': 'MAP',
            'Gebinde': '0.5',
            'MHD': '14',
            'Gesamtausbeute': '0.88',
            'Vorlaufzeit': '1',
            'Brät-Feinheit': 'fein',
            'Kutter-Endtemp': '10.0',
            'Kochkammer-Programm': 'Programm 8',
            'Anbratgrad': 'hell',
            'Ziel-Kerntemp': '72.0',
          },
        );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Interne Datenklasse für Beispiel-Artikel
// ══════════════════════════════════════════════════════════════════════════

class _BeispielArtikel {
  const _BeispielArtikel({
    required this.group,
    required this.artikelnr,
    required this.bezeichnung,
    required this.beschreibung,
    required this.feldwerte,
  });

  final ProductGroup group;
  final String artikelnr;
  final String bezeichnung;
  final String beschreibung;

  /// Mapping: Feld-Label → Wert als String.
  /// Label muss EXAKT mit dem FieldSpec.label in product_group_fields.dart
  /// übereinstimmen.
  final Map<String, String> feldwerte;
}