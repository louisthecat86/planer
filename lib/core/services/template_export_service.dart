import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

/// Erzeugt die Stammdaten-Excel-Vorlage und bietet einen
/// „Speichern unter"-Dialog an.
///
/// Aufbau der Vorlage:
///   1. **Übersicht** — Gesamtliste aller Artikel mit Hyperlinks zu den
///      jeweiligen Produkt-Sheets
///   2. **Rohwaren** — Globale Rohstoff-Definitionen (Lieferant, Einheit, ...)
///   3. **Pro Artikel ein Sheet** (z.B. „10001_Leberkaese_fein") mit:
///      - Stammdaten-Block
///      - Produktionsschritte
///      - Rezeptur / Stückliste
///      - Produktionshistorie (historische Ist-Daten)
class TemplateExportService {
  TemplateExportService._();

  /// Generiert die Vorlage und lässt den Nutzer einen Speicherort wählen.
  static Future<String?> generateAndSave() async {
    final excel = Excel.createExcel();

    // Beispiel-Artikeldaten
    final artikel = [
      _ArtikelDaten(
        nr: '10001',
        bezeichnung: 'Leberkäse fein',
        beschreibung: 'Feiner Leberkäse 500g',
        verpackungsart: 'Vakuum',
        gebindeKg: '0.5',
        mhdTage: '21',
        gesamtausbeute: '0.85',
        vorlaufzeit: '2',
        planungsgruppe: 'Aufschnitt',
        schritte: [
          ['1', 'zerlegung', '100', '45', '10', '2', '', '', '', '', '', '12', '', 'Schweinefleisch zerlegen'],
          ['2', 'kutterabteilung', '100', '30', '5', '1', '0.98', '', '50', '200', '', '8', 'Kutter', 'Brät herstellen'],
          ['3', 'wurstkueche', '100', '120', '15', '1', '0.88', '60', '', '', '72', '', 'Kochkammer', 'Kochen + Räuchern'],
          ['4', 'verpackung', '100', '20', '5', '2', '0.99', '', '', '', '', '', 'Multivac Neu', ''],
        ],
        rezeptur: [
          ['Schweinefleisch S1', '0.45', '5'],
          ['Schweinefleisch S8', '0.25', '5'],
          ['Eis/Wasser', '0.20', ''],
          ['Nitritpökelsalz', '0.018', ''],
          ['Gewürzmischung LK', '0.012', ''],
        ],
        historie: [
          ['2026-01-15', '1', '100', '42', '2', ''],
          ['2026-02-03', '1', '100', '47', '2', ''],
          ['2026-03-10', '1', '100', '44', '2', ''],
          ['2026-01-15', '2', '100', '28', '1', ''],
          ['2026-02-03', '2', '100', '32', '1', ''],
          ['2026-03-10', '2', '100', '30', '1', ''],
          ['2026-01-15', '3', '100', '115', '1', ''],
          ['2026-02-03', '3', '100', '125', '1', ''],
          ['2026-03-10', '3', '100', '120', '1', ''],
        ],
      ),
      _ArtikelDaten(
        nr: '10002',
        bezeichnung: 'Wiener Würstchen',
        beschreibung: 'Wiener im Saitling 5er Pack',
        verpackungsart: 'MAP',
        gebindeKg: '0.4',
        mhdTage: '14',
        gesamtausbeute: '0.92',
        vorlaufzeit: '1',
        planungsgruppe: 'Würstchen',
        schritte: [
          ['1', 'kutterabteilung', '100', '25', '5', '1', '0.98', '', '30', '150', '', '8', 'Kutter', ''],
          ['2', 'wurstkueche', '100', '15', '5', '1', '1.0', '', '', '', '', '', 'Füllmaschine', 'In Saitling füllen'],
          ['3', 'wurstkueche', '100', '90', '10', '1', '0.90', '30', '', '', '72', '', 'Kochkammer', 'Brühen'],
          ['4', 'verpackung', '100', '15', '5', '2', '0.99', '', '', '', '', '', 'Multivac Alt', ''],
        ],
        rezeptur: [
          ['Schweinefleisch S8', '0.55', '5'],
          ['Eis/Wasser', '0.25', ''],
          ['Nitritpökelsalz', '0.018', ''],
          ['Saitlinge', '1.0', ''],
        ],
        historie: [],
      ),
      _ArtikelDaten(
        nr: '10003',
        bezeichnung: 'Schnitzel paniert',
        beschreibung: 'Schweineschnitzel paniert 200g',
        verpackungsart: 'Skin-Pack',
        gebindeKg: '0.2',
        mhdTage: '7',
        gesamtausbeute: '0.78',
        vorlaufzeit: '1',
        planungsgruppe: 'Bratstraße',
        schritte: [
          ['1', 'zerlegung', '100', '30', '5', '2', '0.95', '', '', '', '', '12', '', 'Zuschneiden'],
          ['2', 'bratstrasse', '100', '25', '10', '2', '0.90', '', '', '', '72', '', 'Bratstraße', 'Panieren + Braten'],
          ['3', 'bratstrasse', '100', '15', '5', '1', '0.99', '', '', '', '-18', '', 'Schockfroster', 'Schockfrosten'],
          ['4', 'verpackung', '100', '20', '5', '2', '0.99', '', '', '', '', '', 'Multivac Neu', ''],
        ],
        rezeptur: [
          ['Schweinefleisch S1', '0.70', '5'],
          ['Paniermehl', '0.10', ''],
          ['Vollei flüssig', '0.08', ''],
          ['Mehl', '0.05', ''],
        ],
        historie: [],
      ),
      _ArtikelDaten(
        nr: '10004',
        bezeichnung: 'Kotelett',
        beschreibung: 'Schweinekotelett natur 300g',
        verpackungsart: 'Vakuum',
        gebindeKg: '0.3',
        mhdTage: '7',
        gesamtausbeute: '0.95',
        vorlaufzeit: '1',
        planungsgruppe: 'Zerlegung',
        schritte: [
          ['1', 'zerlegung', '100', '20', '5', '2', '0.95', '', '', '', '', '7', '', 'Koteletts portionieren'],
          ['2', 'schneideabteilung', '100', '15', '5', '1', '0.98', '', '', '', '', '', 'Kotelethacker', 'Hacken'],
          ['3', 'verpackung', '100', '15', '5', '2', '0.99', '', '', '', '', '', 'Multivac Neu', ''],
        ],
        rezeptur: [
          ['Schweinefleisch S1', '1.0', '5'],
        ],
        historie: [],
      ),
    ];

    // 1. Übersicht-Sheet mit Hyperlinks
    _buildUebersichtSheet(excel, artikel);

    // 2. Rohwaren-Sheet (global)
    _buildRohwarenSheet(excel);

    // 3. Pro Artikel ein Sheet
    for (final art in artikel) {
      _buildProduktSheet(excel, art);
    }

    // Standard-Sheet entfernen
    excel.delete('Sheet1');

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

  // -----------------------------------------------------------------------
  // Sheet: Übersicht — Gesamtliste aller Artikel
  // -----------------------------------------------------------------------

  static void _buildUebersichtSheet(Excel excel, List<_ArtikelDaten> artikel) {
    final sheet = excel['Übersicht'];
    final headers = [
      'Artikelnr',
      'Bezeichnung',
      'Beschreibung',
      'Verpackungsart',
      'Gebinde_kg',
      'MHD_Tage',
      'Gesamtausbeute',
      'Vorlaufzeit',
      'Planungsgruppe',
      '→ Zum Produkt-Sheet',
    ];
    _writeHeaders(sheet, headers);

    for (var i = 0; i < artikel.length; i++) {
      final art = artikel[i];
      final row = i + 1;
      final sheetName = _sheetName(art.nr, art.bezeichnung);

      _setCellText(sheet, row, 0, art.nr);
      _setCellText(sheet, row, 1, art.bezeichnung);
      _setCellText(sheet, row, 2, art.beschreibung);
      _setCellText(sheet, row, 3, art.verpackungsart);
      _setCellText(sheet, row, 4, art.gebindeKg);
      _setCellText(sheet, row, 5, art.mhdTage);
      _setCellText(sheet, row, 6, art.gesamtausbeute);
      _setCellText(sheet, row, 7, art.vorlaufzeit);
      _setCellText(sheet, row, 8, art.planungsgruppe);

      // Hyperlink zur Produkt-Sheet
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: row))
          .value = FormulaCellValue(
        "HYPERLINK(\"#'$sheetName'!A1\",\"→ $sheetName\")",
      );
    }
  }

  // -----------------------------------------------------------------------
  // Sheet: Rohwaren (global)
  // -----------------------------------------------------------------------

  static void _buildRohwarenSheet(Excel excel) {
    final sheet = excel['Rohwaren'];
    _writeHeaders(sheet, ['Name', 'Einheit', 'Lieferant', 'Lieferzeit', 'Chargen_Pflicht']);

    final beispiele = [
      ['Schweinefleisch S1', 'kg', 'Fleisch Müller GmbH', '2', 'Ja'],
      ['Schweinefleisch S8', 'kg', 'Fleisch Müller GmbH', '2', 'Ja'],
      ['Eis/Wasser', 'kg', '', '0', 'Nein'],
      ['Nitritpökelsalz', 'kg', 'Gewürz Schmidt', '5', 'Ja'],
      ['Gewürzmischung LK', 'kg', 'Gewürz Schmidt', '5', 'Ja'],
      ['Saitlinge', 'Stk', 'Darm Weber', '7', 'Ja'],
      ['Paniermehl', 'kg', 'Bäcker Huber', '3', 'Ja'],
      ['Vollei flüssig', 'kg', 'Ei-Center', '2', 'Ja'],
      ['Mehl', 'kg', 'Mühle Berger', '3', 'Nein'],
      ['Vakuumbeutel 500g', 'Stk', 'Verpackung AG', '10', 'Nein'],
      ['MAP-Schale 5er', 'Stk', 'Verpackung AG', '10', 'Nein'],
      ['Skin-Pack Folie', 'Stk', 'Verpackung AG', '10', 'Nein'],
    ];
    _writeRows(sheet, beispiele);
  }

  // -----------------------------------------------------------------------
  // Pro-Produkt-Sheet — Stammdaten + Schritte + Rezeptur + Historie
  // -----------------------------------------------------------------------

  static void _buildProduktSheet(Excel excel, _ArtikelDaten art) {
    final name = _sheetName(art.nr, art.bezeichnung);
    final sheet = excel[name];
    var row = 0;

    // --- Link zurück zur Übersicht ---
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = FormulaCellValue(
      "HYPERLINK(\"#'Übersicht'!A1\",\"← Zurück zur Übersicht\")",
    );
    row += 2;

    // --- Block 1: Stammdaten ---
    _setCellText(sheet, row, 0, '== STAMMDATEN ==');
    row++;
    _writeHeaders(sheet, [
      'Artikelnr',
      'Bezeichnung',
      'Beschreibung',
      'Verpackungsart',
      'Gebinde_kg',
      'MHD_Tage',
      'Gesamtausbeute',
      'Vorlaufzeit',
      'Planungsgruppe',
    ], startRow: row);
    row++;
    _writeRowAt(sheet, row, [
      art.nr,
      art.bezeichnung,
      art.beschreibung,
      art.verpackungsart,
      art.gebindeKg,
      art.mhdTage,
      art.gesamtausbeute,
      art.vorlaufzeit,
      art.planungsgruppe,
    ]);
    row += 3;

    // --- Block 2: Produktionsschritte ---
    _setCellText(sheet, row, 0, '== PRODUKTIONSSCHRITTE ==');
    row++;
    _writeHeaders(sheet, [
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
      'Notizen',
    ], startRow: row);
    row++;
    for (final s in art.schritte) {
      _writeRowAt(sheet, row, s);
      row++;
    }
    // Platz für neue Schritte
    row += 3;

    // --- Block 3: Rezeptur ---
    _setCellText(sheet, row, 0, '== REZEPTUR ==');
    row++;
    _writeHeaders(sheet, [
      'Rohware',
      'Menge_pro_kg',
      'Toleranz',
    ], startRow: row);
    row++;
    for (final r in art.rezeptur) {
      _writeRowAt(sheet, row, r);
      row++;
    }
    // Platz für neue Rohwaren
    row += 3;

    // --- Block 4: Produktionshistorie ---
    _setCellText(sheet, row, 0, '== PRODUKTIONSHISTORIE ==');
    row++;
    _writeHeaders(sheet, [
      'Datum',
      'Schritt',
      'Menge_kg',
      'Dauer_min',
      'Mitarbeiter',
      'Notizen',
    ], startRow: row);
    row++;
    for (final h in art.historie) {
      _writeRowAt(sheet, row, h);
      row++;
    }
  }

  // -----------------------------------------------------------------------
  // Hilfsmethoden
  // -----------------------------------------------------------------------

  /// Erzeugt einen gültigen Sheet-Namen (max. 31 Zeichen, keine [ ] : * ? / \).
  static String _sheetName(String nr, String bezeichnung) {
    final clean = bezeichnung
        .replaceAll(RegExp(r'[\\/:*?\[\]]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final raw = '${nr}_$clean';
    return raw.length > 31 ? raw.substring(0, 31) : raw;
  }

  static void _writeHeaders(
    Sheet sheet,
    List<String> headers, {
    int startRow = 0,
  }) {
    for (var i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: startRow))
          .value = TextCellValue(headers[i]);
    }
  }

  static void _writeRows(Sheet sheet, List<List<String>> rows) {
    for (var row = 0; row < rows.length; row++) {
      _writeRowAt(sheet, row + 1, rows[row]);
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

  static void _setCellText(Sheet sheet, int row, int col, String text) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
        .value = TextCellValue(text);
  }
}

// ---------------------------------------------------------------------------
// Internes Datenmodell für die Vorlage
// ---------------------------------------------------------------------------

class _ArtikelDaten {
  const _ArtikelDaten({
    required this.nr,
    required this.bezeichnung,
    required this.beschreibung,
    required this.verpackungsart,
    required this.gebindeKg,
    required this.mhdTage,
    required this.gesamtausbeute,
    required this.vorlaufzeit,
    required this.planungsgruppe,
    required this.schritte,
    required this.rezeptur,
    required this.historie,
  });

  final String nr;
  final String bezeichnung;
  final String beschreibung;
  final String verpackungsart;
  final String gebindeKg;
  final String mhdTage;
  final String gesamtausbeute;
  final String vorlaufzeit;
  final String planungsgruppe;

  /// [Schritt, Abteilung, Basis_Menge, Dauer, Fixzeit, Mitarbeiter,
  ///  Ausbeute, Wartezeit, Min_Charge, Max_Charge, Kerntemp, Raumtemp,
  ///  Maschine, Notizen]
  final List<List<String>> schritte;

  /// [Rohware, Menge_pro_kg, Toleranz]
  final List<List<String>> rezeptur;

  /// [Datum, Schritt, Menge_kg, Dauer_min, Mitarbeiter, Notizen]
  final List<List<String>> historie;
}
