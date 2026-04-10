// ignore_for_file: avoid_print
import 'dart:io';
import 'package:excel/excel.dart';

/// Generiert eine Excel-Vorlage für den App-Import.
///
/// Neues Format:
///   - Sheet "Übersicht": Artikelliste mit Hyperlinks zu den Produkt-Sheets
///   - Sheet "Rohwaren": Globale Rohstoff-Stammdaten
///   - Je Artikel ein eigenes Sheet mit Stammdaten, Schritten, Rezeptur, Historie
///
/// Ausführen mit:
///   cd /workspaces/planer && dart run tool/generate_template.dart
void main() {
  final excel = Excel.createExcel();

  // ---- Beispieldaten ----

  final produkte = [
    _Produkt(
      nr: '10001',
      bezeichnung: 'Leberkäse fein',
      beschreibung: 'Feiner Leberkäse 500g',
      verpackungsart: 'Vakuum',
      gebindeKg: '0.5',
      mhdTage: '21',
      ausbeute: '0.85',
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
        ['1', '2026-01-15', '100', '42', '2', ''],
        ['1', '2026-02-03', '100', '47', '2', ''],
        ['1', '2026-03-10', '100', '44', '2', ''],
        ['2', '2026-01-15', '100', '28', '1', ''],
        ['2', '2026-02-03', '100', '32', '1', ''],
        ['2', '2026-03-10', '100', '30', '1', ''],
        ['3', '2026-01-15', '100', '115', '1', ''],
        ['3', '2026-02-03', '100', '125', '1', ''],
        ['3', '2026-03-10', '100', '120', '1', ''],
      ],
    ),
    _Produkt(
      nr: '10002',
      bezeichnung: 'Wiener Würstchen',
      beschreibung: 'Wiener im Saitling 5er Pack',
      verpackungsart: 'MAP',
      gebindeKg: '0.4',
      mhdTage: '14',
      ausbeute: '0.92',
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
    _Produkt(
      nr: '10003',
      bezeichnung: 'Schnitzel paniert',
      beschreibung: 'Schweineschnitzel paniert 200g',
      verpackungsart: 'Skin-Pack',
      gebindeKg: '0.2',
      mhdTage: '7',
      ausbeute: '0.78',
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
    _Produkt(
      nr: '10004',
      bezeichnung: 'Kotelett',
      beschreibung: 'Schweinekotelett natur 300g',
      verpackungsart: 'Vakuum',
      gebindeKg: '0.3',
      mhdTage: '7',
      ausbeute: '0.95',
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

  // =========================================================================
  // Sheet 1: Übersicht (Artikelliste mit Hyperlinks)
  // =========================================================================
  final uebersicht = excel['Übersicht'];

  final uebersichtHeaders = [
    'Artikelnr',
    'Bezeichnung',
    'Beschreibung',
    'Verpackungsart',
    'Gebinde_kg',
    'MHD_Tage',
    'Gesamtausbeute',
    'Vorlaufzeit',
    'Planungsgruppe',
  ];

  for (var i = 0; i < uebersichtHeaders.length; i++) {
    uebersicht
        .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        .value = TextCellValue(uebersichtHeaders[i]);
  }

  for (var p = 0; p < produkte.length; p++) {
    final prod = produkte[p];
    final sheetName = _sheetName(prod.nr, prod.bezeichnung);
    final rowIdx = p + 1;

    // Artikelnr als Hyperlink zum Produkt-Sheet
    uebersicht
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx))
        .value = FormulaCellValue("HYPERLINK(\"#'$sheetName'!A1\", \"${prod.nr}\")");

    final stammdaten = [
      prod.bezeichnung,
      prod.beschreibung,
      prod.verpackungsart,
      prod.gebindeKg,
      prod.mhdTage,
      prod.ausbeute,
      prod.vorlaufzeit,
      prod.planungsgruppe,
    ];
    for (var c = 0; c < stammdaten.length; c++) {
      uebersicht
          .cell(CellIndex.indexByColumnRow(columnIndex: c + 1, rowIndex: rowIdx))
          .value = TextCellValue(stammdaten[c]);
    }
  }

  // =========================================================================
  // Sheet 2: Rohwaren (global)
  // =========================================================================
  final rohwaren = excel['Rohwaren'];

  final rohwarenHeaders = [
    'Name',
    'Einheit',
    'Lieferant',
    'Lieferzeit',
    'Chargen_Pflicht',
  ];

  for (var i = 0; i < rohwarenHeaders.length; i++) {
    rohwaren
        .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        .value = TextCellValue(rohwarenHeaders[i]);
  }

  final rohwarenDaten = [
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

  for (var row = 0; row < rohwarenDaten.length; row++) {
    for (var col = 0; col < rohwarenDaten[row].length; col++) {
      rohwaren
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1))
          .value = TextCellValue(rohwarenDaten[row][col]);
    }
  }

  // =========================================================================
  // Pro Produkt: eigenes Sheet
  // =========================================================================
  final schritteHeaders = [
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
  ];

  final rezeptHeaders = [
    'Rohware',
    'Menge_pro_kg',
    'Toleranz',
  ];

  final historieHeaders = [
    'Schritt',
    'Datum',
    'Menge_kg',
    'Dauer_min',
    'Mitarbeiter',
    'Notizen',
  ];

  for (final prod in produkte) {
    final sheetName = _sheetName(prod.nr, prod.bezeichnung);
    final sheet = excel[sheetName];
    var row = 0;

    // Zurück-Link
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = const FormulaCellValue("HYPERLINK(\"#'Übersicht'!A1\", \"← Zurück zur Übersicht\")");
    row += 2;

    // == STAMMDATEN ==
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue('== STAMMDATEN ==');
    row++;

    final stammdatenLabels = uebersichtHeaders;
    for (var i = 0; i < stammdatenLabels.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
          .value = TextCellValue(stammdatenLabels[i]);
    }
    row++;
    final stammdatenValues = [
      prod.nr,
      prod.bezeichnung,
      prod.beschreibung,
      prod.verpackungsart,
      prod.gebindeKg,
      prod.mhdTage,
      prod.ausbeute,
      prod.vorlaufzeit,
      prod.planungsgruppe,
    ];
    for (var i = 0; i < stammdatenValues.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
          .value = TextCellValue(stammdatenValues[i]);
    }
    row += 2;

    // == PRODUKTIONSSCHRITTE ==
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue('== PRODUKTIONSSCHRITTE ==');
    row++;

    for (var i = 0; i < schritteHeaders.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
          .value = TextCellValue(schritteHeaders[i]);
    }
    row++;

    for (final s in prod.schritte) {
      for (var c = 0; c < s.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
            .value = TextCellValue(s[c]);
      }
      row++;
    }
    row++;

    // == REZEPTUR ==
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue('== REZEPTUR ==');
    row++;

    for (var i = 0; i < rezeptHeaders.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
          .value = TextCellValue(rezeptHeaders[i]);
    }
    row++;

    for (final r in prod.rezeptur) {
      for (var c = 0; c < r.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
            .value = TextCellValue(r[c]);
      }
      row++;
    }
    row++;

    // == PRODUKTIONSHISTORIE ==
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue('== PRODUKTIONSHISTORIE ==');
    row++;

    for (var i = 0; i < historieHeaders.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
          .value = TextCellValue(historieHeaders[i]);
    }
    row++;

    for (final h in prod.historie) {
      for (var c = 0; c < h.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
            .value = TextCellValue(h[c]);
      }
      row++;
    }
  }

  // Standard-Sheet "Sheet1" entfernen
  excel.delete('Sheet1');

  // Speichern
  final bytes = excel.encode();
  if (bytes == null) {
    print('Fehler beim Erzeugen der Excel-Datei.');
    return;
  }

  const outPath = 'stammdaten_vorlage.xlsx';
  File(outPath).writeAsBytesSync(bytes);
  print('✅ Excel-Vorlage erstellt: $outPath');
  print('');
  print('Sheets:');
  print('  📋 Übersicht  — Artikelliste mit Hyperlinks zu den Produkt-Sheets');
  print('  📋 Rohwaren   — 12 Rohstoffe (Name, Einheit, Lieferant, ...)');
  for (final prod in produkte) {
    final name = _sheetName(prod.nr, prod.bezeichnung);
    print('  📋 $name — Stammdaten, Schritte, Rezeptur, Historie');
  }
}

/// Erzeugt einen Sheet-Namen: "ArtNr_Bez" max 31 Zeichen.
String _sheetName(String artNr, String bezeichnung) {
  final bez = bezeichnung
      .replaceAll(RegExp(r'[\\/*?\[\]:]'), '')
      .replaceAll(' ', '_');
  final name = '${artNr}_$bez';
  return name.length > 31 ? name.substring(0, 31) : name;
}

class _Produkt {
  _Produkt({
    required this.nr,
    required this.bezeichnung,
    required this.beschreibung,
    required this.verpackungsart,
    required this.gebindeKg,
    required this.mhdTage,
    required this.ausbeute,
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
  final String ausbeute;
  final String vorlaufzeit;
  final String planungsgruppe;
  final List<List<String>> schritte;
  final List<List<String>> rezeptur;
  final List<List<String>> historie;
}
