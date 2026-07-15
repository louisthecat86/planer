import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:xml/xml.dart';

import '../database/database.dart';
import 'excel_import_service_v3.dart';

/// Name der Notiz-Parameterzeile (identisch zur App-Konstante in
/// article_detail_screen.dart) — hier lokal, um keine Flutter-Abhängigkeit
/// in den Export zu ziehen.
const String kMaschinenNotizParam = 'Maschineneinstellungen';

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
    this.customParameterGeschrieben = 0,
    this.customParameterUebersprungen = 0,
    this.historienGeschrieben = 0,
    this.artikelSheetsAngelegt = 0,
    this.maschinenInKatalog = 0,
    this.artikelNichtInVorlage = const [],
    this.warnungen = const [],
    this.fehler = const [],
  });

  final Uint8List bytes;
  final String vorschlagDateiname;

  final int artikelAktualisiert;
  final int schritteGeschrieben;
  final int parameterGeschrieben;
  final int customParameterGeschrieben;
  final int customParameterUebersprungen;
  final int historienGeschrieben;

  /// Neu in der Vorlage angelegte Artikel-Sheets (Artikel, die es nur
  /// in der App gab).
  final int artikelSheetsAngelegt;

  /// Neu in den Anlagen-Katalog der Vorlage eingetragene Maschinen.
  final int maschinenInKatalog;

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
/// Geschrieben werden: Schritt-Matrix, Standard- und Custom-Parameter sowie
/// der Block „HISTORISCHE DATEN" (aus production_history — sowohl importierte
/// als auch in der App erfasste Zeilen).
class ExcelExportServiceV3 {
  ExcelExportServiceV3(this._db);

  final AppDatabase _db;

  static const _nsRel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  /// Marker-Text in Spalte A der Vorlage, der den Beginn des
  /// „ZUSÄTZLICHE PARAMETER"-Blocks markiert.
  static const _zusaetzlicheParameterMarker = 'ZUSÄTZLICHE PARAMETER';

  /// Marker-Text in Spalte A, der das Ende des Parameter-Bereichs
  /// markiert (alles danach gehört zur Historie).
  static const _historieMarker = 'HISTORISCHE DATEN';

  Future<bool> hasImportedFile() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(kAppSettingLastImportExcelBytes))
          ..limit(1))
        .getSingleOrNull();
    return row != null && row.value.isNotEmpty;
  }

  Future<String> letzterDateiname() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(kAppSettingLastImportExcelFilename))
          ..limit(1))
        .getSingleOrNull();
    return row?.value ?? 'stammdaten_export.xlsx';
  }

  Future<ExportResultV3> export() async {
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
    final archive = ZipDecoder().decodeBytes(vorlageBytes);

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

    final sharedStrings = _SharedStrings.fromArchive(archive);

    final alleArtikel = await _db.select(_db.products).get();
    final alleSchritte = await _db.select(_db.productSteps).get();
    final alleParameter = await _db.select(_db.productStepParameters).get();
    final alleMaschinen = await _db.select(_db.machines).get();
    final maschinenById = {for (final m in alleMaschinen) m.id: m};

    // Historie je Artikel (importierte + in der App erfasste Zeilen).
    final alleHistorie = await _db.select(_db.productionHistory).get();
    final historieByProduct = <String, List<ProductionHistoryData>>{};
    for (final h in alleHistorie) {
      if (h.deletedAt != null) continue;
      historieByProduct.putIfAbsent(h.productId, () => []).add(h);
    }

    int artikelAktualisiert = 0;
    int schritteGeschrieben = 0;
    int parameterGeschrieben = 0;
    int customParameterGeschrieben = 0;
    int customParameterUebersprungen = 0;
    int historienGeschrieben = 0;
    final artikelNichtInVorlage = <String>[];
    final warnungen = <String>[];

    // App-Artikel ohne Sheet in der Vorlage: neues Sheet anlegen
    // (Blueprint der passenden Kategorie klonen) — damit App und Excel
    // immer denselben Artikelbestand haben. Vorher per A6 mappen, damit
    // abweichend benannte Sheets erkannt und keine Duplikate angelegt
    // werden.
    _ergaenzeArtikelnummernAusA6(archive, sheetInfo, sharedStrings);
    final artikelSheetsAngelegt = _legeFehlendeArtikelSheetsAn(
      archive: archive,
      sheetInfo: sheetInfo,
      artikel: alleArtikel,
      warnungen: warnungen,
    );

    // In der App angelegte Maschinen in den Anlagen-Katalog übernehmen.
    final maschinenInKatalog = _ergaenzeAnlagenKatalog(
      archive: archive,
      sheetInfo: sheetInfo,
      sharedStrings: sharedStrings,
      maschinen: alleMaschinen,
      warnungen: warnungen,
    );

    for (final artikel in alleArtikel) {
      if (artikel.deletedAt != null) continue;

      final sheetXmlPfad = sheetInfo[artikel.artikelnummer];
      if (sheetXmlPfad == null) {
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
          historie: historieByProduct[artikel.id] ?? const [],
          sharedStrings: sharedStrings,
          warnungen: warnungen,
          artikelLabel: artikel.artikelnummer,
        );

        if (aktualisiert.schritte > 0 ||
            aktualisiert.parameter > 0 ||
            aktualisiert.customParameter > 0 ||
            aktualisiert.historie > 0) {
          artikelAktualisiert++;
        }
        schritteGeschrieben += aktualisiert.schritte;
        parameterGeschrieben += aktualisiert.parameter;
        customParameterGeschrieben += aktualisiert.customParameter;
        customParameterUebersprungen += aktualisiert.customUebersprungen;
        historienGeschrieben += aktualisiert.historie;

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

    sharedStrings.writeBackIfDirty(archive);

    final encoder = ZipEncoder();
    final neuesBytes = Uint8List.fromList(encoder.encode(archive)!);

    return ExportResultV3(
      bytes: neuesBytes,
      vorschlagDateiname: _generiereExportDateiname(dateiname),
      artikelAktualisiert: artikelAktualisiert,
      schritteGeschrieben: schritteGeschrieben,
      parameterGeschrieben: parameterGeschrieben,
      customParameterGeschrieben: customParameterGeschrieben,
      customParameterUebersprungen: customParameterUebersprungen,
      historienGeschrieben: historienGeschrieben,
      artikelSheetsAngelegt: artikelSheetsAngelegt,
      maschinenInKatalog: maschinenInKatalog,
      artikelNichtInVorlage: artikelNichtInVorlage,
      warnungen: warnungen,
    );
  }

  String _generiereExportDateiname(String originalname) {
    final jetzt = DateTime.now();
    final ts = '${jetzt.year}${_pad(jetzt.month)}${_pad(jetzt.day)}_'
        '${_pad(jetzt.hour)}${_pad(jetzt.minute)}';
    final basis = originalname.replaceAll(RegExp(r'\.xlsx$'), '');
    return '${basis}_export_$ts.xlsx';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// Kategorie-Titel der Blueprint-Sheets je Produktgruppe (Umkehrung des
  /// Import-Mappings) — bestimmt, welches Blueprint geklont wird.
  static const Map<String, String> _produktgruppeZuKategorie = {
    'bruehwurst': 'Brühwurst',
    'rohwurst': 'Rohwurst',
    'kochpoekelware': 'Kochpökelwaren',
    'rohpoekelware': 'Rohpökelwaren',
    'aufschnitt': 'Aufschnitt',
    'bratstrasse_natur': 'Bratstraßenartikel Natur',
    'bratstrasse_paniert': 'Bratstraßenartikel paniert',
    'hackprodukt_gegart': 'Hackprodukte gegart',
    'hackprodukt_roh': 'Hackprodukte roh',
    'braten': 'Braten',
    'sous_vide': 'Sous Vide gegarte Produkte',
    'angebratene_bruehwurst': 'Angebratene Brühwürste',
  };

  /// Legt für App-Artikel ohne Vorlage-Sheet ein neues Sheet an, indem das
  /// Blueprint-Sheet der passenden Kategorie geklont wird. Der Artikelkopf
  /// (A6 = "Nr — Bezeichnung") wird gesetzt; Schritte/Parameter/Historie
  /// schreibt anschließend die normale Export-Schleife.
  ///
  /// `sheetInfo` wird um die neuen Sheets ergänzt. Liefert die Anzahl
  /// angelegter Sheets.
  int _legeFehlendeArtikelSheetsAn({
    required Archive archive,
    required Map<String, String> sheetInfo,
    required List<Product> artikel,
    required List<String> warnungen,
  }) {
    final fehlende = artikel
        .where(
          (a) =>
              a.deletedAt == null &&
              !sheetInfo.containsKey(a.artikelnummer),
        )
        .toList();
    if (fehlende.isEmpty) return 0;

    final workbookFile = archive.findFile('xl/workbook.xml');
    final relsFile = archive.findFile('xl/_rels/workbook.xml.rels');
    final ctFile = archive.findFile('[Content_Types].xml');
    if (workbookFile == null || relsFile == null || ctFile == null) {
      warnungen.add(
        'Neue Artikel-Sheets: Workbook-Struktur unvollständig — '
        '${fehlende.length} Artikel nicht angelegt.',
      );
      return 0;
    }

    final workbookDoc = XmlDocument.parse(
      utf8.decode(workbookFile.content as List<int>),
    );
    final relsDoc = XmlDocument.parse(
      utf8.decode(relsFile.content as List<int>),
    );
    final ctDoc = XmlDocument.parse(
      utf8.decode(ctFile.content as List<int>),
    );

    final sheetsElement =
        workbookDoc.findAllElements('sheets').firstOrNull;
    final relsRoot =
        relsDoc.findAllElements('Relationships').firstOrNull;
    final ctRoot = ctDoc.findAllElements('Types').firstOrNull;
    if (sheetsElement == null || relsRoot == null || ctRoot == null) {
      warnungen.add(
        'Neue Artikel-Sheets: Workbook-XML unerwartet — nicht angelegt.',
      );
      return 0;
    }

    // Höchste vorhandene Indizes ermitteln (Datei-Nr., sheetId, rId).
    var maxDateiNr = 0;
    for (final f in archive.files) {
      final m = RegExp(r'^xl/worksheets/sheet(\d+)\.xml$').firstMatch(f.name);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        if (n > maxDateiNr) maxDateiNr = n;
      }
    }
    var maxSheetId = 0;
    for (final s in workbookDoc.findAllElements('sheet')) {
      final n = int.tryParse(s.getAttribute('sheetId') ?? '') ?? 0;
      if (n > maxSheetId) maxSheetId = n;
    }
    var maxRid = 0;
    for (final r in relsDoc.findAllElements('Relationship')) {
      final m = RegExp(r'^rId(\d+)$').firstMatch(r.getAttribute('Id') ?? '');
      if (m != null) {
        final n = int.parse(m.group(1)!);
        if (n > maxRid) maxRid = n;
      }
    }

    var angelegt = 0;
    for (final art in fehlende) {
      // Blueprint der Kategorie finden (Fallback: irgendein Blueprint).
      String? blueprintName = art.produktgruppe == null
          ? null
          : _produktgruppeZuKategorie[art.produktgruppe];
      if (blueprintName == null || !sheetInfo.containsKey(blueprintName)) {
        blueprintName = _produktgruppeZuKategorie.values
            .where(sheetInfo.containsKey)
            .firstOrNull;
      }
      final quellPfad =
          blueprintName == null ? null : sheetInfo[blueprintName];
      final quellFile =
          quellPfad == null ? null : archive.findFile(quellPfad);
      if (quellFile == null) {
        warnungen.add(
          'Artikel ${art.artikelnummer}: Kein Blueprint-Sheet gefunden — '
          'Sheet nicht angelegt.',
        );
        continue;
      }

      try {
        // Blueprint klonen + Artikelkopf setzen (A6 = "Nr — Bezeichnung",
        // exakt das Format, das der Import wieder einliest).
        final doc = XmlDocument.parse(
          utf8.decode(quellFile.content as List<int>),
        );
        final sheetData = doc.findAllElements('sheetData').firstOrNull;
        if (sheetData == null) {
          warnungen.add(
            'Artikel ${art.artikelnummer}: Blueprint ohne sheetData — '
            'Sheet nicht angelegt.',
          );
          continue;
        }
        _setzeZelleInlineStr(
          sheetData,
          row: 6,
          colLetter: 'A',
          wert: '${art.artikelnummer} — ${art.artikelbezeichnung}',
        );
        // Blaupausen-Hinweis ("für jeden neuen Artikel kopieren …")
        // im geklonten Sheet entfernen — A2 (Kategorie) bleibt, sie
        // bestimmt beim Re-Import die Produktgruppe.
        _setzeZelleInlineStr(sheetData, row: 3, colLetter: 'A', wert: '');

        maxDateiNr++;
        maxSheetId++;
        maxRid++;
        final neuerPfad = 'xl/worksheets/sheet$maxDateiNr.xml';
        final xmlBytes = utf8.encode(doc.toXmlString(pretty: false));
        archive.addFile(ArchiveFile(neuerPfad, xmlBytes.length, xmlBytes));

        // Relationship (Target RELATIV — absolute Pfade crashen den
        // Dart-Excel-Parser beim Re-Import).
        final rel = XmlElement(XmlName('Relationship'));
        rel.setAttribute('Id', 'rId$maxRid');
        rel.setAttribute(
          'Type',
          'http://schemas.openxmlformats.org/officeDocument/2006/'
              'relationships/worksheet',
        );
        rel.setAttribute('Target', 'worksheets/sheet$maxDateiNr.xml');
        relsRoot.children.add(rel);

        // Workbook-Eintrag (Sheet-Name = Artikelnummer).
        // WICHTIG: xmlns:r muss am Element selbst deklariert sein — die
        // Vorlage deklariert es pro <sheet> (nicht am Root). Ohne diese
        // Zeile hätte r:id ein undeklariertes Präfix → Excel meldet die
        // gesamte Arbeitsmappe als beschädigt.
        final sheetEl = XmlElement(XmlName('sheet'));
        sheetEl.setAttribute(
          'xmlns:r',
          'http://schemas.openxmlformats.org/officeDocument/2006/'
              'relationships',
        );
        sheetEl.setAttribute('name', art.artikelnummer);
        sheetEl.setAttribute('sheetId', '$maxSheetId');
        sheetEl.setAttribute('state', 'visible');
        sheetEl.setAttribute('r:id', 'rId$maxRid');
        sheetsElement.children.add(sheetEl);

        // Content-Types-Override.
        final ov = XmlElement(XmlName('Override'));
        ov.setAttribute('PartName', '/$neuerPfad');
        ov.setAttribute(
          'ContentType',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.'
              'worksheet+xml',
        );
        ctRoot.children.add(ov);

        sheetInfo[art.artikelnummer] = neuerPfad;
        angelegt++;
      } catch (e) {
        warnungen.add(
          'Artikel ${art.artikelnummer}: Sheet-Anlage fehlgeschlagen ($e).',
        );
      }
    }

    if (angelegt > 0) {
      final wb = utf8.encode(workbookDoc.toXmlString(pretty: false));
      archive.addFile(ArchiveFile('xl/workbook.xml', wb.length, wb));
      final rl = utf8.encode(relsDoc.toXmlString(pretty: false));
      archive.addFile(
        ArchiveFile('xl/_rels/workbook.xml.rels', rl.length, rl),
      );
      final ct = utf8.encode(ctDoc.toXmlString(pretty: false));
      archive.addFile(ArchiveFile('[Content_Types].xml', ct.length, ct));
    }
    return angelegt;
  }

  /// Trägt in der App angelegte Maschinen in den Anlagen-Katalog der
  /// Vorlage ein (Spalte A = Name, Spalte B = Abteilung; Zeilen 13–88,
  /// passend zum benannten Bereich "Anlagen_Liste").
  int _ergaenzeAnlagenKatalog({
    required Archive archive,
    required Map<String, String> sheetInfo,
    required _SharedStrings sharedStrings,
    required List<Machine> maschinen,
    required List<String> warnungen,
  }) {
    final pfad = sheetInfo['Anlagen-Katalog'];
    final file = pfad == null ? null : archive.findFile(pfad);
    if (file == null) {
      warnungen.add(
        'Anlagen-Katalog-Sheet nicht gefunden — neue Maschinen wurden '
        'nicht in die Excel übernommen.',
      );
      return 0;
    }

    try {
      final doc = XmlDocument.parse(
        utf8.decode(file.content as List<int>),
      );
      final sheetData = doc.findAllElements('sheetData').firstOrNull;
      if (sheetData == null) return 0;

      // Belegte Zeilen (13..88) und vorhandene Namen einsammeln.
      final belegt = <int>{};
      final vorhanden = <String>{};
      for (final row in sheetData.findElements('row')) {
        final r = int.tryParse(row.getAttribute('r') ?? '');
        if (r == null || r < 13 || r > 88) continue;
        final t = _leseZelleA(row, sharedStrings)?.trim();
        if (t != null && t.isNotEmpty) {
          belegt.add(r);
          vorhanden.add(t.toLowerCase());
        }
      }

      final fehlend = maschinen
          .where(
            (m) =>
                m.deletedAt == null &&
                m.name.trim().isNotEmpty &&
                !vorhanden.contains(m.name.trim().toLowerCase()),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (fehlend.isEmpty) return 0;

      var geschrieben = 0;
      var zeile = 13;
      for (final m in fehlend) {
        while (zeile <= 88 && belegt.contains(zeile)) {
          zeile++;
        }
        if (zeile > 88) {
          warnungen.add(
            'Anlagen-Katalog voll (Zeile 88 erreicht) — '
            '"${m.name}" und weitere nicht eingetragen.',
          );
          break;
        }
        _setzeZelleInlineStr(
          sheetData,
          row: zeile,
          colLetter: 'A',
          wert: m.name.trim(),
        );
        _setzeZelleInlineStr(
          sheetData,
          row: zeile,
          colLetter: 'B',
          wert: _abteilungLabel(m.abteilung),
        );
        belegt.add(zeile);
        geschrieben++;
      }

      if (geschrieben > 0) {
        final xml = utf8.encode(doc.toXmlString(pretty: false));
        archive.addFile(ArchiveFile(file.name, xml.length, xml));
      }
      return geschrieben;
    } catch (e) {
      warnungen.add('Anlagen-Katalog konnte nicht ergänzt werden ($e).');
      return 0;
    }
  }

  /// Schreibt die Besonderheiten des Artikels (Product.beschreibung) in die
  /// Zeile direkt unter dem Marker „Sonstige Informationen", Spalte B.
  ///
  /// Genau dort liest der Import sie wieder ein — der Roundtrip
  /// App ⇄ Excel bleibt damit verlustfrei. Ein leerer Text löscht den
  /// Eintrag (das Feld wurde in der App geleert).
  void _schreibeSonstigeInfos(
    XmlDocument doc,
    XmlElement sheetData,
    _SharedStrings sharedStrings,
    String? text,
  ) {
    int? markerZeile;
    for (final row in sheetData.findElements('row')) {
      final r = int.tryParse(row.getAttribute('r') ?? '');
      if (r == null) continue;
      final label = _leseZelleA(row, sharedStrings)?.trim();
      if (label == 'Sonstige Informationen') {
        markerZeile = r;
        break;
      }
    }
    if (markerZeile == null) return; // Vorlage ohne den Block

    final wert = (text ?? '').trim();
    _setzeZelleInlineStr(
      sheetData,
      row: markerZeile + 1,
      colLetter: 'B',
      wert: wert,
    );
  }

  /// Leert die Schritt-Spalten B..K im gesamten Schritt-/Parameter-Bereich
  /// (von der ersten Schritt-Label-Zeile bis vor den HISTORISCHE-DATEN-
  /// Block). Spalte A (Labels) und die Historie bleiben unangetastet;
  /// Zell-Styles bleiben erhalten, nur Werte werden entfernt.
  void _leereSchrittSpalten(
    XmlElement sheetData,
    _SharedStrings sharedStrings,
    _SchrittLabelZeilen labelRows,
    List<int> customSlots,
  ) {
    final kandidaten = <int>[
      if (labelRows.abteilungRow != null) labelRows.abteilungRow!,
      if (labelRows.prozessschrittRow != null) labelRows.prozessschrittRow!,
      if (labelRows.anlagenRow != null) labelRows.anlagenRow!,
      if (labelRows.personenRow != null) labelRows.personenRow!,
      if (labelRows.mengeRow != null) labelRows.mengeRow!,
      if (labelRows.zeitRow != null) labelRows.zeitRow!,
      if (labelRows.fixZeitRow != null) labelRows.fixZeitRow!,
    ];
    if (kandidaten.isEmpty) return;
    final von = kandidaten.reduce((a, b) => a < b ? a : b);

    // Endzeile: direkt vor dem HISTORISCHE-DATEN-Marker. Ohne Marker
    // konservativ nur bis zur größten bekannten Zeile (Labels/Slots),
    // damit keinesfalls Historie-Daten gelöscht werden.
    int? historieZeile;
    for (final row in sheetData.findElements('row')) {
      final r = int.tryParse(row.getAttribute('r') ?? '');
      if (r == null) continue;
      final label = _leseZelleA(row, sharedStrings)?.trim() ?? '';
      if (label.contains(_historieMarker)) {
        historieZeile = r;
        break;
      }
    }
    var bis = kandidaten.reduce((a, b) => a > b ? a : b);
    for (final s in customSlots) {
      if (s > bis) bis = s;
    }
    if (historieZeile != null) bis = historieZeile - 1;

    const spalten = {'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K'};
    for (final row in sheetData.findElements('row')) {
      final r = int.tryParse(row.getAttribute('r') ?? '');
      if (r == null || r < von || r > bis) continue;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r') ?? '';
        final col = RegExp(r'^([A-Z]+)').firstMatch(ref)?.group(1);
        if (col == null || !spalten.contains(col)) continue;
        c.children.clear();
        c.attributes.removeWhere((a) => a.name.local == 't');
      }
    }
  }

  /// Ergänzt `sheetInfo` um Artikelnummern aus Zeile A6 der Sheets
  /// ("NR — Bezeichnung"). Damit findet der Export einen Artikel auch
  /// dann, wenn das Sheet nicht exakt nach der Artikelnummer benannt
  /// ist — und legt kein Duplikat-Sheet an.
  void _ergaenzeArtikelnummernAusA6(
    Archive archive,
    Map<String, String> sheetInfo,
    _SharedStrings sharedStrings,
  ) {
    const meta = {'Übersicht', 'Anleitung', 'Anlagen-Katalog'};
    final zusatz = <String, String>{};

    for (final eintrag in sheetInfo.entries) {
      if (meta.contains(eintrag.key)) continue;
      final file = archive.findFile(eintrag.value);
      if (file == null) continue;
      try {
        final doc = XmlDocument.parse(
          utf8.decode(file.content as List<int>),
        );
        final sheetData = doc.findAllElements('sheetData').firstOrNull;
        if (sheetData == null) continue;
        String? a6;
        for (final row in sheetData.findElements('row')) {
          if (row.getAttribute('r') == '6') {
            a6 = _leseZelleA(row, sharedStrings)?.trim();
            break;
          }
        }
        if (a6 == null || a6.isEmpty) continue;

        String? nummer;
        for (final sep in [' — ', ' – ', ' - ', ': ']) {
          if (a6.contains(sep)) {
            nummer = a6.split(sep).first.trim();
            break;
          }
        }
        nummer ??= int.tryParse(a6) != null ? a6 : null;
        if (nummer != null &&
            nummer.isNotEmpty &&
            !sheetInfo.containsKey(nummer)) {
          zusatz[nummer] = eintrag.value;
        }
      } catch (_) {
        // Defektes Einzelsheet ignorieren — betrifft nur das Mapping.
      }
    }
    sheetInfo.addAll(zusatz);
  }

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

    final rIdToTarget = <String, String>{};
    for (final rel in relsDoc.findAllElements('Relationship')) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id != null && target != null) {
        rIdToTarget[id] = target;
      }
    }

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

  _AktualisierungsStats _aktualisiereSheetXml({
    required XmlDocument doc,
    required Product artikel,
    required List<ProductStep> schritte,
    required Map<String, List<ProductStepParameter>> paramsByStep,
    required Map<String, Machine> maschinenById,
    required List<ProductionHistoryData> historie,
    required _SharedStrings sharedStrings,
    required List<String> warnungen,
    required String artikelLabel,
  }) {
    final sheetData = doc.findAllElements('sheetData').firstOrNull;
    if (sheetData == null) return _AktualisierungsStats(0, 0, 0, 0, 0);

    final labelRows = _findeSchrittLabelZeilen(doc, sharedStrings);

    int schritteAktualisiert = 0;
    int parameterAktualisiert = 0;
    int customGeschrieben = 0;
    int customUebersprungen = 0;

    // ── Custom-Parameter pro Schritt: Pool aus dem ZUSÄTZLICHE-Block
    //    in der Vorlage-Excel ermitteln ────────────────────────────────
    final customSlots = _findeCustomParameterSlots(doc, sharedStrings);

    // ── Schritt-Bereich komplett leeren (Spalten B..K) ────────────────
    // Der Export war bisher rein additiv: Felder ohne Wert wurden
    // übersprungen, wodurch nach Umsortierungen alte „Geister-Werte"
    // in den Spalten stehen blieben (z.B. Bratstraßen-Parameter unter
    // einem Verpackungs-Schritt). Deshalb: erst leeren, dann schreiben.
    _leereSchrittSpalten(sheetData, sharedStrings, labelRows, customSlots);

    // ── Besonderheiten in den Block „Sonstige Informationen" ──────────
    // Muss NACH dem Leeren passieren (der Bereich liegt in den Spalten
    // B..K und würde sonst gleich wieder geleert).
    _schreibeSonstigeInfos(doc, sheetData, sharedStrings, artikel.beschreibung);

    for (final step in schritte) {
      final col = step.reihenfolge; // 1..10 → Spalte B..K
      if (col < 1 || col > 10) continue;
      final colLetter = _spaltenBuchstabe(col + 1);

      // ── Standard-Schritt-Werte ─────────────────────────────────────
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
        // Als lesbaren „h:mm"-Text schreiben (z.B. 2:05) — nicht als
        // Tagesbruchteil-Zahl (0.086…), die ohne Zeitformat als nackte
        // Dezimalzahl erschiene. Die App liest diesen Text beim Import
        // korrekt zurück.
        final gesamt = step.basisDauerMinuten.round();
        final std = gesamt ~/ 60;
        final min = gesamt % 60;
        _setzeZelleInlineStr(
          sheetData,
          row: labelRows.zeitRow!,
          colLetter: colLetter,
          wert: '$std:${min.toString().padLeft(2, '0')}',
        );
      }
      // Fixe Zeit / Durchlauf — als Minuten-Zahl (nur wenn Zeile vorhanden).
      if (labelRows.fixZeitRow != null &&
          step.fixZeitMinuten != null &&
          step.fixZeitMinuten! > 0) {
        _setzeZelleZahl(
          sheetData,
          row: labelRows.fixZeitRow!,
          colLetter: colLetter,
          wert: step.fixZeitMinuten!,
        );
      }
      schritteAktualisiert++;

      // ── Standard-Parameter aktualisieren (nur wenn das Label in
      //    der Vorlage existiert — sonst überspringen) ────────────────
      final stepParams = paramsByStep[step.id] ?? [];
      final standardParams = stepParams.where((p) => !p.istCustom);
      for (final param in standardParams) {
        final paramRow = _findeZeileMitLabelInA(
          doc,
          sharedStrings,
          param.parameterName,
          gruppe: param.parameterGruppe,
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
          // Lange Freitexte (v.a. „Maschineneinstellungen") brauchen eine
          // höhere Zeile, sonst schneidet Excel den umbrochenen Text ab.
          if (param.parameterName == kMaschinenNotizParam ||
              wert.length > 40 ||
              wert.contains('\n')) {
            _setzeZeilenHoehe(sheetData, row: paramRow, mindestHoehe: 60);
          }
        }
        parameterAktualisiert++;
      }

      // ── Custom-Parameter in die ZUSÄTZLICHE-PARAMETER-Slots ───────
      final customParams = stepParams.where((p) => p.istCustom).toList();
      for (var i = 0; i < customParams.length; i++) {
        if (i >= customSlots.length) {
          customUebersprungen++;
          continue;
        }
        final slot = customSlots[i];
        final p = customParams[i];

        // Label in Spalte A schreiben (Name des Custom-Parameters)
        _setzeZelleInlineStr(
          sheetData,
          row: slot,
          colLetter: 'A',
          wert: p.parameterName,
        );

        // Wert in der Schritt-Spalte
        final wert = p.wert ?? '';
        if (wert.isNotEmpty) {
          final zahl = double.tryParse(wert.replaceAll(',', '.'));
          if (zahl != null) {
            _setzeZelleZahl(
              sheetData,
              row: slot,
              colLetter: colLetter,
              wert: zahl,
            );
          } else {
            _setzeZelleInlineStr(
              sheetData,
              row: slot,
              colLetter: colLetter,
              wert: wert,
            );
          }
        }
        customGeschrieben++;
      }

      if (customParams.length > customSlots.length) {
        warnungen.add(
          'Artikel $artikelLabel, Schritt ${step.reihenfolge}: '
          'Mehr Custom-Parameter (${customParams.length}) als '
          'freie Slots in der Vorlage (${customSlots.length}). '
          'Überschüssige Parameter wurden nicht exportiert.',
        );
      }
    }

    // ── Historische Produktionsdaten in den HISTORISCHE-DATEN-Block ───
    final historieGeschrieben = _schreibeHistorie(
      sheetData: sheetData,
      doc: doc,
      sharedStrings: sharedStrings,
      historie: historie,
    );

    return _AktualisierungsStats(
      schritteAktualisiert,
      parameterAktualisiert,
      customGeschrieben,
      customUebersprungen,
      historieGeschrieben,
    );
  }

  /// Findet alle freien Zeilen unterhalb von „ZUSÄTZLICHE PARAMETER"
  /// die als Custom-Parameter-Slots dienen können.
  ///
  /// Ein Slot ist eine Zeile in der die Spalte A entweder leer ist
  /// oder schon einen Custom-Parameter-Namen enthält. Der Block endet
  /// bei „HISTORISCHE DATEN" oder am Ende des Sheets.
  List<int> _findeCustomParameterSlots(
    XmlDocument doc,
    _SharedStrings sharedStrings,
  ) {
    final sheetData = doc.findAllElements('sheetData').firstOrNull;
    if (sheetData == null) return [];

    int? markerZeile;
    int? endZeile;

    for (final row in sheetData.findElements('row')) {
      final rNum = int.tryParse(row.getAttribute('r') ?? '');
      if (rNum == null) continue;
      final label = _leseZelleA(row, sharedStrings)?.trim() ?? '';
      if (label.contains(_zusaetzlicheParameterMarker)) {
        markerZeile = rNum;
      } else if (markerZeile != null && label.contains(_historieMarker)) {
        endZeile = rNum;
        break;
      }
    }

    if (markerZeile == null) return [];

    // Slots sind alle Zeilen zwischen Marker+1 und endZeile-1.
    // Das sind in der typischen Vorlage etwa 10 Zeilen.
    final slots = <int>[];
    final ende = endZeile ?? (markerZeile + 11);
    for (var r = markerZeile + 1; r < ende; r++) {
      slots.add(r);
    }
    return slots;
  }

  // ─── Historie zurückschreiben ─────────────────────────────────────────

  /// Schreibt alle [historie]-Zeilen in den HISTORISCHE-DATEN-Block.
  /// Bestehende Datenzeilen unterhalb der „Datum"-Kopfzeile werden ersetzt.
  ///
  /// Datum wird als Excel-Seriennummer, Zeiten als Tagesbruchteil und Verlust
  /// als Bruch geschrieben — jeweils mit dem Zellformat (Style) der ersten
  /// vorhandenen Datenzeile, damit Format und Datentyp exakt der Vorlage
  /// entsprechen (und ein Re-Import sie wieder als Datum/Zeit erkennt).
  /// Ohne erfassbaren Style wird auf Text zurückgefallen (re-import-sicher).
  /// Spalten: A Datum, B Roh, C Fertig, D Verlust, E Start, F Ende,
  /// G Produktionszeit, H kg/h roh, I kg/h gegart, J Notizen.
  int _schreibeHistorie({
    required XmlElement sheetData,
    required XmlDocument doc,
    required _SharedStrings sharedStrings,
    required List<ProductionHistoryData> historie,
  }) {
    final headerRow = _findeHistorieHeaderZeile(doc, sharedStrings);
    if (headerRow == null) return 0;

    // Zell-Styles der ersten Datenzeile je Spalte erfassen (VOR dem Löschen),
    // damit neue Zeilen identisch formatiert werden.
    final stilByCol = _erfasseHistorieStile(sheetData, headerRow);

    // Alte Datenzeilen (alles unterhalb der „Datum"-Kopfzeile) entfernen.
    final alteZeilen = sheetData
        .findElements('row')
        .where((r) {
          final n = int.tryParse(r.getAttribute('r') ?? '');
          return n != null && n > headerRow;
        })
        .toList();
    for (final z in alteZeilen) {
      sheetData.children.remove(z);
    }

    final sortiert = [...historie]
      ..sort((a, b) => a.datum.compareTo(b.datum));

    var r = headerRow;
    var count = 0;
    for (final h in sortiert) {
      r++;

      // A — Datum: Seriennummer + Datums-Style, sonst ISO-Text.
      _schreibeZelle(
        sheetData,
        row: r,
        colLetter: 'A',
        stil: stilByCol['A'],
        zahl: _excelDatumSerial(h.datum).toDouble(),
        textFallback: _isoDatum(h.datum),
      );

      if (h.kgRohware != null) {
        _schreibeZelle(
          sheetData,
          row: r,
          colLetter: 'B',
          stil: stilByCol['B'],
          zahl: h.kgRohware,
        );
      }
      if (h.kgFertigware != null) {
        _schreibeZelle(
          sheetData,
          row: r,
          colLetter: 'C',
          stil: stilByCol['C'],
          zahl: h.kgFertigware,
        );
      }
      if (h.verlustAnteil != null) {
        _schreibeZelle(
          sheetData,
          row: r,
          colLetter: 'D',
          stil: stilByCol['D'],
          zahl: h.verlustAnteil,
        );
      }

      // E/F — Start/Ende: Tagesbruchteil + Zeit-Style, sonst "HH:MM"-Text.
      final bsStart = _zeitBruchteil(h.startzeit);
      if (bsStart != null) {
        _schreibeZelle(
          sheetData,
          row: r,
          colLetter: 'E',
          stil: stilByCol['E'],
          zahl: bsStart,
          textFallback: h.startzeit,
        );
      }
      final bsEnde = _zeitBruchteil(h.endzeit);
      if (bsEnde != null) {
        _schreibeZelle(
          sheetData,
          row: r,
          colLetter: 'F',
          stil: stilByCol['F'],
          zahl: bsEnde,
          textFallback: h.endzeit,
        );
      }

      // G — Produktionszeit: Minuten → Tagesbruchteil.
      if (h.produktionszeitMinuten != null) {
        _schreibeZelle(
          sheetData,
          row: r,
          colLetter: 'G',
          stil: stilByCol['G'],
          zahl: h.produktionszeitMinuten! / 1440,
          textFallback: _hhmmVonMinuten(h.produktionszeitMinuten!),
        );
      }

      if (h.kgProStundeRoh != null) {
        _schreibeZelle(
          sheetData,
          row: r,
          colLetter: 'H',
          stil: stilByCol['H'],
          zahl: h.kgProStundeRoh,
        );
      }
      if (h.kgProStundeGegart != null) {
        _schreibeZelle(
          sheetData,
          row: r,
          colLetter: 'I',
          stil: stilByCol['I'],
          zahl: h.kgProStundeGegart,
        );
      }
      final notiz = h.notizen;
      if (notiz != null && notiz.isNotEmpty) {
        _schreibeZelle(
          sheetData,
          row: r,
          colLetter: 'J',
          stil: stilByCol['J'],
          text: notiz,
        );
      }
      count++;
    }
    return count;
  }

  /// Erfasst die Style-IDs (`s`-Attribut) je Spalte aus der ersten Datenzeile
  /// (headerRow + 1) des Historie-Blocks.
  Map<String, String> _erfasseHistorieStile(
    XmlElement sheetData,
    int headerRow,
  ) {
    final result = <String, String>{};
    for (final row in sheetData.findElements('row')) {
      final n = int.tryParse(row.getAttribute('r') ?? '');
      if (n != headerRow + 1) continue;
      for (final cell in row.findElements('c')) {
        final ref = cell.getAttribute('r') ?? '';
        final m = RegExp(r'^([A-Z]+)').firstMatch(ref);
        final s = cell.getAttribute('s');
        if (m != null && s != null) result[m.group(1)!] = s;
      }
      break;
    }
    return result;
  }

  /// Schreibt eine Zelle wahlweise als Zahl oder Text, optional mit
  /// vorgegebenem Style. Bei [zahl] ohne Style wird – falls vorhanden –
  /// auf [textFallback] zurückgegriffen, damit das Format (Datum/Zeit)
  /// nicht verloren geht.
  void _schreibeZelle(
    XmlElement sheetData, {
    required int row,
    required String colLetter,
    String? stil,
    double? zahl,
    String? text,
    String? textFallback,
  }) {
    if (text != null) {
      _setzeMitStil(sheetData, row, colLetter, stil);
      _setzeZelleInlineStr(
        sheetData,
        row: row,
        colLetter: colLetter,
        wert: text,
      );
      return;
    }
    if (zahl == null) return;
    if (stil != null) {
      _setzeMitStil(sheetData, row, colLetter, stil);
      _setzeZelleZahl(sheetData, row: row, colLetter: colLetter, wert: zahl);
    } else if (textFallback != null) {
      _setzeZelleInlineStr(
        sheetData,
        row: row,
        colLetter: colLetter,
        wert: textFallback,
      );
    } else {
      _setzeZelleZahl(sheetData, row: row, colLetter: colLetter, wert: zahl);
    }
  }

  /// Legt die Zelle an (falls nötig) und setzt das `s`-Attribut, sofern noch
  /// keines vorhanden ist. Die anschließenden Schreib-Helfer erhalten den
  /// Style.
  void _setzeMitStil(
    XmlElement sheetData,
    int row,
    String colLetter,
    String? stil,
  ) {
    if (stil == null) return;
    final rowEl = _findeOderLegeRowAn(sheetData, row);
    final cell = _findeOderLegeCellAn(rowEl, '$colLetter$row');
    if (cell.getAttribute('s') == null) cell.setAttribute('s', stil);
  }

  /// Excel-Datums-Seriennummer (Tage seit 1899-12-30, UTC-sicher).
  int _excelDatumSerial(DateTime d) {
    final tag = DateTime.utc(d.year, d.month, d.day);
    final epoch = DateTime.utc(1899, 12, 30);
    return tag.difference(epoch).inDays;
  }

  /// "HH:MM" → Tagesbruchteil (z. B. "06:35" → 0.27430…).
  double? _zeitBruchteil(String? hhmm) {
    if (hhmm == null || hhmm.isEmpty) return null;
    final p = hhmm.trim().split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return (h * 60 + m) / 1440;
  }

  /// Findet die „Datum"-Kopfzeile innerhalb/unterhalb des
  /// HISTORISCHE-DATEN-Markers.
  int? _findeHistorieHeaderZeile(
    XmlDocument doc,
    _SharedStrings sharedStrings,
  ) {
    final sheetData = doc.findAllElements('sheetData').firstOrNull;
    if (sheetData == null) return null;

    var imBlock = false;
    for (final row in sheetData.findElements('row')) {
      final rNum = int.tryParse(row.getAttribute('r') ?? '');
      if (rNum == null) continue;
      final label = _leseZelleA(row, sharedStrings)?.trim() ?? '';
      if (label.contains(_historieMarker)) {
        imBlock = true;
        continue;
      }
      if (imBlock && label == 'Datum') return rNum;
    }
    return null;
  }

  String _isoDatum(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_pad(d.month)}-${_pad(d.day)}';

  String _hhmmVonMinuten(double minuten) {
    final t = minuten.round();
    final h = t ~/ 60;
    final m = t % 60;
    return '${_pad(h)}:${_pad(m)}';
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
    int? abteilung, prozess, anlagen, personen, menge, zeit, fixZeit;
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
        case 'Fixe Zeit (min)':
          fixZeit = rNum;
      }
    }
    return _SchrittLabelZeilen(
      abteilungRow: abteilung,
      prozessschrittRow: prozess,
      anlagenRow: anlagen,
      personenRow: personen,
      mengeRow: menge,
      zeitRow: zeit,
      fixZeitRow: fixZeit,
    );
  }

  /// Findet die Zeilennummer, deren Spalte A exakt [gesuchtesLabel] enthält.
  ///
  /// Ist [gruppe] gesetzt (z.B. "BRATSTRASSE" oder "DAMPFTUNNEL"), wird nur
  /// INNERHALB dieses Blocks gesucht — vom Block-Header bis zum nächsten
  /// Block-Header. Das ist nötig, weil identische Label wie
  /// "Platte Unten 1" in mehreren Blöcken vorkommen (Bratstraße 10 Platten
  /// vs. Dampftunnel 12 Platten); ohne Gruppen-Eingrenzung landete der
  /// Wert immer im ersten (Bratstraße-)Block.
  ///
  /// Block-Header sind in Spalte A durchgängig GROSS geschrieben
  /// (BRATSTRASSE, DAMPFTUNNEL, SCHOCKFROSTER …), Parameter-Label dagegen
  /// gemischt ("Platte Unten 1", "Eingang (°C)"). Wird der Block oder das
  /// Label darin nicht gefunden, greift der globale Erst-Treffer (altes
  /// Verhalten — für Parameter ohne Mehrdeutigkeit unverändert korrekt).
  int? _findeZeileMitLabelInA(
    XmlDocument doc,
    _SharedStrings sharedStrings,
    String gesuchtesLabel, {
    String? gruppe,
  }) {
    final sheetData = doc.findAllElements('sheetData').firstOrNull;
    if (sheetData == null) return null;
    final ziel = gesuchtesLabel.trim();

    // Zeilen in Dokumentreihenfolge mit ihrem A-Label sammeln.
    final eintraege = <({int rNum, String label})>[];
    for (final row in sheetData.findElements('row')) {
      final rNum = int.tryParse(row.getAttribute('r') ?? '');
      if (rNum == null) continue;
      eintraege.add(
        (rNum: rNum, label: _leseZelleA(row, sharedStrings)?.trim() ?? ''),
      );
    }

    // 1) Gruppen-Eingrenzung
    final g = gruppe?.trim() ?? '';
    if (g.isNotEmpty) {
      var startIdx = -1;
      for (var i = 0; i < eintraege.length; i++) {
        if (eintraege[i].label.toLowerCase() == g.toLowerCase()) {
          startIdx = i;
          break;
        }
      }
      if (startIdx >= 0) {
        for (var i = startIdx + 1; i < eintraege.length; i++) {
          final e = eintraege[i];
          if (_istBlockHeader(e.label)) break; // nächster Block → Ende
          if (e.label == ziel) return e.rNum;
        }
        // Im Block nicht gefunden → unten globaler Fallback.
      }
    }

    // 2) Globaler Erst-Treffer (altes Verhalten)
    for (final e in eintraege) {
      if (e.label == ziel) return e.rNum;
    }
    return null;
  }

  /// Block-Header-Erkennung: Label enthält Buchstaben und diese sind
  /// vollständig groß geschrieben (BRATSTRASSE, DAMPFTUNNEL …). Parameter-
  /// Label ("Platte Unten 1") sind gemischt und damit kein Header.
  bool _istBlockHeader(String label) {
    final l = label.trim();
    if (l.isEmpty) return false;
    final buchstaben = l.replaceAll(RegExp(r'[^A-Za-zÄÖÜäöüß]'), '');
    if (buchstaben.isEmpty) return false;
    return buchstaben == buchstaben.toUpperCase();
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

    var styleAttr = cell.getAttribute('s');
    // Neu angelegte Zellen erben das Format der B-Zelle derselben Zeile
    // (Vorlagen formatieren Spalte B durchgängig) — sonst gehen z.B.
    // Zeit-Formate verloren und es erscheint 0,0833 statt 2:00.
    if (styleAttr == null && colLetter != 'B') {
      for (final c in rowElement.findElements('c')) {
        if (c.getAttribute('r') == 'B$row') {
          styleAttr = c.getAttribute('s');
          break;
        }
      }
    }

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

    var styleAttr = cell.getAttribute('s');
    // Format-Erbe wie bei _setzeZelleInlineStr (siehe dort).
    if (styleAttr == null && colLetter != 'B') {
      for (final c in rowElement.findElements('c')) {
        if (c.getAttribute('r') == 'B$row') {
          styleAttr = c.getAttribute('s');
          break;
        }
      }
    }

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

  /// Setzt die Höhe einer Zeile auf mindestens [mindestHoehe] Punkte, damit
  /// umbrochener Text (z.B. lange Maschineneinstellungen) vollständig sichtbar
  /// ist. Bestehende größere Höhen bleiben erhalten.
  void _setzeZeilenHoehe(
    XmlElement sheetData, {
    required int row,
    required double mindestHoehe,
  }) {
    final rowEl = _findeOderLegeRowAn(sheetData, row);
    final alt = double.tryParse(rowEl.getAttribute('ht') ?? '');
    if (alt != null && alt >= mindestHoehe) return;
    rowEl.setAttribute('ht', mindestHoehe.toString());
    rowEl.setAttribute('customHeight', '1');
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
      case 'verpackung_tef2':
        return 'Verpackung Tef2';
      default:
        return dbValue;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Hilfsklassen
// ═══════════════════════════════════════════════════════════════════════════

class _AktualisierungsStats {
  _AktualisierungsStats(
    this.schritte,
    this.parameter,
    this.customParameter,
    this.customUebersprungen,
    this.historie,
  );

  final int schritte;
  final int parameter;
  final int customParameter;
  final int customUebersprungen;
  final int historie;
}

class _SchrittLabelZeilen {
  _SchrittLabelZeilen({
    this.abteilungRow,
    this.prozessschrittRow,
    this.anlagenRow,
    this.personenRow,
    this.mengeRow,
    this.zeitRow,
    this.fixZeitRow,
  });

  final int? abteilungRow;
  final int? prozessschrittRow;
  final int? anlagenRow;
  final int? personenRow;
  final int? mengeRow;
  final int? zeitRow;
  final int? fixZeitRow;
}

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
  }
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
