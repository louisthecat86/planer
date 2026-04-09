// ignore_for_file: avoid_print
import 'dart:io';
import 'package:excel/excel.dart';

/// Generiert eine Excel-Vorlage für den App-Import.
///
/// Ausführen mit:
///   cd /workspaces/planer && flutter pub run tool/generate_template.dart
///
/// Oder:
///   dart run tool/generate_template.dart
void main() {
  final excel = Excel.createExcel();

  // =========================================================================
  // Sheet 1: Artikel (Stammdaten)
  // =========================================================================
  final artikel = excel['Artikel'];

  final artikelHeaders = [
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

  for (var i = 0; i < artikelHeaders.length; i++) {
    artikel.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value =
        TextCellValue(artikelHeaders[i]);
  }

  // Beispiel-Artikel
  final artikelDaten = [
    ['10001', 'Leberkäse fein', 'Feiner Leberkäse 500g', 'Vakuum', '0.5', '21', '0.85', '2', 'Aufschnitt'],
    ['10002', 'Wiener Würstchen', 'Wiener im Saitling 5er Pack', 'MAP', '0.4', '14', '0.92', '1', 'Würstchen'],
    ['10003', 'Schnitzel paniert', 'Schweineschnitzel paniert 200g', 'Skin-Pack', '0.2', '7', '0.78', '1', 'Bratstraße'],
    ['10004', 'Kotelett', 'Schweinekotelett natur 300g', 'Vakuum', '0.3', '7', '0.95', '1', 'Zerlegung'],
  ];

  for (var row = 0; row < artikelDaten.length; row++) {
    for (var col = 0; col < artikelDaten[row].length; col++) {
      artikel
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1))
          .value = TextCellValue(artikelDaten[row][col]);
    }
  }

  // =========================================================================
  // Sheet 2: Schritte (Produktionsschritte pro Artikel)
  // =========================================================================
  final schritte = excel['Schritte'];

  final schritteHeaders = [
    'Artikelnr',
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

  for (var i = 0; i < schritteHeaders.length; i++) {
    schritte
        .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        .value = TextCellValue(schritteHeaders[i]);
  }

  // Beispiel: Leberkäse — 4 Schritte
  final schritteDaten = [
    // Leberkäse
    ['10001', '1', 'zerlegung', '100', '45', '10', '2', '', '', '', '', '', '12', '', 'Schweinefleisch zerlegen'],
    ['10001', '2', 'kutterabteilung', '100', '30', '5', '1', '0.98', '', '50', '200', '', '8', 'Kutter', 'Brät herstellen'],
    ['10001', '3', 'wurstkueche', '100', '120', '15', '1', '0.88', '60', '', '', '72', '', 'Kochkammer', 'Kochen + Räuchern'],
    ['10001', '4', 'verpackung', '100', '20', '5', '2', '0.99', '', '', '', '', '', 'Multivac Neu', ''],

    // Wiener Würstchen
    ['10002', '1', 'kutterabteilung', '100', '25', '5', '1', '0.98', '', '30', '150', '', '8', 'Kutter', ''],
    ['10002', '2', 'wurstkueche', '100', '15', '5', '1', '1.0', '', '', '', '', '', 'Füllmaschine', 'In Saitling füllen'],
    ['10002', '3', 'wurstkueche', '100', '90', '10', '1', '0.90', '30', '', '', '72', '', 'Kochkammer', 'Brühen'],
    ['10002', '4', 'verpackung', '100', '15', '5', '2', '0.99', '', '', '', '', '', 'Multivac Alt', ''],

    // Schnitzel paniert
    ['10003', '1', 'zerlegung', '100', '30', '5', '2', '0.95', '', '', '', '', '12', '', 'Zuschneiden'],
    ['10003', '2', 'bratstrasse', '100', '25', '10', '2', '0.90', '', '', '', '72', '', 'Bratstraße', 'Panieren + Braten'],
    ['10003', '3', 'bratstrasse', '100', '15', '5', '1', '0.99', '', '', '', '-18', '', 'Schockfroster', 'Schockfrosten'],
    ['10003', '4', 'verpackung', '100', '20', '5', '2', '0.99', '', '', '', '', '', 'Multivac Neu', ''],

    // Kotelett
    ['10004', '1', 'zerlegung', '100', '20', '5', '2', '0.95', '', '', '', '', '7', '', 'Koteletts portionieren'],
    ['10004', '2', 'schneideabteilung', '100', '15', '5', '1', '0.98', '', '', '', '', '', 'Kotelethacker', 'Hacken'],
    ['10004', '3', 'verpackung', '100', '15', '5', '2', '0.99', '', '', '', '', '', 'Multivac Neu', ''],
  ];

  for (var row = 0; row < schritteDaten.length; row++) {
    for (var col = 0; col < schritteDaten[row].length; col++) {
      schritte
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1))
          .value = TextCellValue(schritteDaten[row][col]);
    }
  }

  // =========================================================================
  // Sheet 3: Rohwaren
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
  // Sheet 4: Rezeptur (Stückliste / BOM)
  // =========================================================================
  final rezeptur = excel['Rezeptur'];

  final rezeptHeaders = [
    'Artikelnr',
    'Rohware',
    'Menge_pro_kg',
    'Toleranz',
  ];

  for (var i = 0; i < rezeptHeaders.length; i++) {
    rezeptur
        .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        .value = TextCellValue(rezeptHeaders[i]);
  }

  final rezeptDaten = [
    // Leberkäse
    ['10001', 'Schweinefleisch S1', '0.45', '5'],
    ['10001', 'Schweinefleisch S8', '0.25', '5'],
    ['10001', 'Eis/Wasser', '0.20', ''],
    ['10001', 'Nitritpökelsalz', '0.018', ''],
    ['10001', 'Gewürzmischung LK', '0.012', ''],

    // Wiener
    ['10002', 'Schweinefleisch S8', '0.55', '5'],
    ['10002', 'Eis/Wasser', '0.25', ''],
    ['10002', 'Nitritpökelsalz', '0.018', ''],
    ['10002', 'Saitlinge', '1.0', ''],

    // Schnitzel paniert
    ['10003', 'Schweinefleisch S1', '0.70', '5'],
    ['10003', 'Paniermehl', '0.10', ''],
    ['10003', 'Vollei flüssig', '0.08', ''],
    ['10003', 'Mehl', '0.05', ''],

    // Kotelett
    ['10004', 'Schweinefleisch S1', '1.0', '5'],
  ];

  for (var row = 0; row < rezeptDaten.length; row++) {
    for (var col = 0; col < rezeptDaten[row].length; col++) {
      rezeptur
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1))
          .value = TextCellValue(rezeptDaten[row][col]);
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
  print('  📋 Artikel     — 4 Beispiel-Artikel (Artikelnr, Bezeichnung, ...)');
  print('  📋 Schritte    — 15 Produktionsschritte (Abteilung, Dauer, Ausbeute, ...)');
  print('  📋 Rohwaren    — 12 Rohstoffe (Name, Einheit, Lieferant, ...)');
  print('  📋 Rezeptur    — 14 Rezeptzeilen (Menge pro kg Fertigware)');
}
