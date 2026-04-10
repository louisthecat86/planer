import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

/// Erzeugt die Stammdaten-Excel-Vorlage und bietet einen
/// „Speichern unter"-Dialog an.
class TemplateExportService {
  TemplateExportService._();

  /// Generiert die Vorlage und lässt den Nutzer einen Speicherort wählen.
  ///
  /// Gibt den gewählten Pfad zurück oder `null`, wenn abgebrochen wurde.
  static Future<String?> generateAndSave() async {
    final excel = Excel.createExcel();

    _buildArtikelSheet(excel);
    _buildSchritteSheet(excel);
    _buildRohwarenSheet(excel);
    _buildRezepturSheet(excel);

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
  // Sheet-Builder (entspricht tool/generate_template.dart)
  // -----------------------------------------------------------------------

  static void _buildArtikelSheet(Excel excel) {
    final sheet = excel['Artikel'];
    final headers = [
      'Artikelnr', 'Bezeichnung', 'Beschreibung', 'Verpackungsart',
      'Gebinde_kg', 'MHD_Tage', 'Gesamtausbeute', 'Vorlaufzeit',
      'Planungsgruppe',
    ];
    _writeHeaders(sheet, headers);
  }

  static void _buildSchritteSheet(Excel excel) {
    final sheet = excel['Schritte'];
    final headers = [
      'Artikelnr', 'Schritt', 'Abteilung', 'Basis_Menge', 'Dauer',
      'Fixzeit', 'Mitarbeiter', 'Ausbeute', 'Wartezeit', 'Min_Charge',
      'Max_Charge', 'Kerntemperatur', 'Raumtemperatur', 'Maschine', 'Notizen',
    ];
    _writeHeaders(sheet, headers);
  }

  static void _buildRohwarenSheet(Excel excel) {
    final sheet = excel['Rohwaren'];
    final headers = [
      'Name', 'Einheit', 'Lieferant', 'Lieferzeit', 'Chargen_Pflicht',
    ];
    _writeHeaders(sheet, headers);
  }

  static void _buildRezepturSheet(Excel excel) {
    final sheet = excel['Rezeptur'];
    final headers = [
      'Artikelnr', 'Rohware', 'Menge_pro_kg', 'Toleranz',
    ];
    _writeHeaders(sheet, headers);
  }

  static void _writeHeaders(Sheet sheet, List<String> headers) {
    for (var i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
  }
}
