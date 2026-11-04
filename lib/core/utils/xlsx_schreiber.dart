import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

// Ein kleiner Baukasten für Excel-Mappen (xlsx), ohne Bibliothek: Er
// schreibt nur, was die Mappen der App brauchen — Texte, Zahlen, Formeln,
// Formate, verbundene Zellen, Auswahllisten, fixierte Zeilen, Verweise.

/// 1-basierte Spaltennummer → Buchstaben (1 → A, 27 → AA).
String xlsxSpalte(int n) {
  var c = n;
  final b = StringBuffer();
  while (c > 0) {
    final rest = (c - 1) % 26;
    b.write(String.fromCharCode(65 + rest));
    c = (c - 1) ~/ 26;
  }
  return b.toString().split('').reversed.join();
}

/// XML-Text entschärfen. Steuerzeichen fliegen raus: In XML 1.0 sind sie
/// grundsätzlich unzulässig, und Navision-Texte enthalten sie gelegentlich.
String _esc(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// ═══════════════════════════════════════════════════════════════════════════
// Zellformate — feste Nummern, passend zur styles.xml unten
// ═══════════════════════════════════════════════════════════════════════════

/// Die Zellformate der Mappe — feste Nummern, passend zur styles.xml.
abstract final class XlsxStil {
  static const int titel = 1;
  static const int block = 2;
  static const int label = 3;
  static const int parameter = 4;
  static const int wert = 5;
  static const int berechnet = 6;
  static const int hinweis = 7;
  static const int kopf = 8;
  static const int datum = 9;
  static const int zeit = 10;
  static const int prozent = 11;
  static const int zeitBerechnet = 12;
  static const int zahl1 = 13;
  static const int ganzBerechnet = 14;
  static const int summe = 15;
  static const int link = 16;
  static const int artikelKopf = 17;
  static const int umbruch = 18;

  /// Tabellenkopf, der lange Überschriften umbricht.
  static const int kopfUmbruch = 19;
}

const String _stylesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/'
    'spreadsheetml/2006/main">'
    '<numFmts count="4">'
    '<numFmt numFmtId="164" formatCode="DD.MM.YYYY"/>'
    '<numFmt numFmtId="165" formatCode="hh:mm"/>'
    '<numFmt numFmtId="166" formatCode="0.0"/>'
    '<numFmt numFmtId="167" formatCode="0.0%"/>'
    '</numFmts>'
    '<fonts count="7">'
    '<font><sz val="10"/><name val="Arial"/></font>'
    '<font><b/><sz val="14"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>'
    '<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>'
    '<font><b/><sz val="10"/><name val="Arial"/></font>'
    '<font><i/><sz val="9"/><color rgb="FF8A9099"/><name val="Arial"/></font>'
    '<font><u/><sz val="10"/><color rgb="FF1976D2"/><name val="Arial"/></font>'
    '<font><b/><sz val="12"/><name val="Arial"/></font>'
    '</fonts>'
    '<fills count="8">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF1F6F6F"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF3F4A54"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFFF7E0"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFEDEFF2"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF7F8FA"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFFFFFF"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="2"><border/>'
    '<border><left style="thin"><color rgb="FFC8CDD3"/></left>'
    '<right style="thin"><color rgb="FFC8CDD3"/></right>'
    '<top style="thin"><color rgb="FFC8CDD3"/></top>'
    '<bottom style="thin"><color rgb="FFC8CDD3"/></bottom>'
    '<diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
    'borderId="0"/></cellStyleXfs>'
    '<cellXfs count="20">'
    // 0 Standard
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    // 1 Titel
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" '
    'applyFont="1" applyFill="1" applyAlignment="1">'
    '<alignment vertical="center"/></xf>'
    // 2 Blockkopf
    '<xf numFmtId="0" fontId="2" fillId="3" borderId="0" xfId="0" '
    'applyFont="1" applyFill="1" applyAlignment="1">'
    '<alignment vertical="center"/></xf>'
    // 3 Beschriftung gelb
    '<xf numFmtId="0" fontId="3" fillId="4" borderId="1" xfId="0" '
    'applyFont="1" applyFill="1" applyBorder="1"/>'
    // 4 Parameterzeile grau
    '<xf numFmtId="0" fontId="0" fillId="5" borderId="1" xfId="0" '
    'applyFill="1" applyBorder="1"/>'
    // 5 Wert
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" '
    'applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>'
    // 6 Berechnet
    '<xf numFmtId="0" fontId="0" fillId="6" borderId="1" xfId="0" '
    'applyFill="1" applyBorder="1"/>'
    // 7 Hinweis
    '<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    // 8 Tabellenkopf
    '<xf numFmtId="0" fontId="3" fillId="5" borderId="1" xfId="0" '
    'applyFont="1" applyFill="1" applyBorder="1"/>'
    // 9 Datum
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyBorder="1"/>'
    // 10 Uhrzeit (Eingabe)
    '<xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyBorder="1"/>'
    // 11 Prozent (berechnet)
    '<xf numFmtId="167" fontId="0" fillId="6" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyFill="1" applyBorder="1"/>'
    // 12 Uhrzeit (berechnet)
    '<xf numFmtId="165" fontId="0" fillId="6" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyFill="1" applyBorder="1"/>'
    // 13 Zahl mit einer Nachkommastelle
    '<xf numFmtId="166" fontId="0" fillId="0" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyBorder="1"/>'
    // 14 Ganzzahl (berechnet)
    '<xf numFmtId="1" fontId="0" fillId="6" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyFill="1" applyBorder="1"/>'
    // 15 Summenzeile
    '<xf numFmtId="1" fontId="3" fillId="5" borderId="1" xfId="0" '
    'applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
    // 16 Verweis
    '<xf numFmtId="0" fontId="5" fillId="0" borderId="1" xfId="0" '
    'applyFont="1" applyBorder="1"/>'
    // 17 Artikelkopf
    '<xf numFmtId="0" fontId="6" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    // 18 Freitext mit Umbruch
    '<xf numFmtId="0" fontId="0" fillId="7" borderId="1" xfId="0" '
    'applyFill="1" applyBorder="1" applyAlignment="1">'
    '<alignment wrapText="1" vertical="center"/></xf>'
    // 19 Tabellenkopf mit Umbruch
    '<xf numFmtId="0" fontId="3" fillId="5" borderId="1" xfId="0" '
    'applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
    '<alignment wrapText="1" vertical="center"/></xf>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Standard" xfId="0" '
    'builtinId="0"/></cellStyles>'
    '</styleSheet>';

// ═══════════════════════════════════════════════════════════════════════════
// Minimaler xlsx-Baukasten
// ═══════════════════════════════════════════════════════════════════════════

/// Eine Excel-Mappe, Zelle für Zelle geschrieben: Texte als geteilte
/// Zeichenketten (die Lesebibliothek kennt keine Inline-Texte), mit
/// Auswahllisten, fixierten Zeilen und Verweisen.
class XlsxSchreiber {
  final List<XlsxSchreibBlatt> _blaetter = [];
  final Map<String, int> _textIndex = {};
  final List<String> _texte = [];

  /// Hängt ein Blatt an — [reiter] färbt seinen Reiter (ARGB, `FF…`).
  XlsxSchreibBlatt blatt(String name, {String? reiter}) {
    final b = XlsxSchreibBlatt._(this, name, reiter);
    _blaetter.add(b);
    return b;
  }

  /// Die Nummer von [s] unter den geteilten Zeichenketten.
  int textNr(String s) =>
      _textIndex.putIfAbsent(s, () => (_texte..add(s)).length - 1);

  /// Die fertige Datei.
  Uint8List packe() {
    final archiv = Archive();
    void datei(String pfad, String inhalt) {
      final bytes = utf8.encode(inhalt);
      archiv.addFile(ArchiveFile(pfad, bytes.length, bytes));
    }

    const kopf = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    final blattXml = [for (final b in _blaetter) b.xml()];

    datei(
      '[Content_Types].xml',
      '$kopf<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
          'content-types">'
          '<Default Extension="rels" ContentType="application/'
          'vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/'
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '${[
        for (var i = 0; i < _blaetter.length; i++)
          '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
              'ContentType="application/vnd.openxmlformats-officedocument.'
              'spreadsheetml.worksheet+xml"/>',
      ].join()}'
          '<Override PartName="/xl/styles.xml" ContentType="application/'
          'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '<Override PartName="/xl/sharedStrings.xml" ContentType='
          '"application/vnd.openxmlformats-officedocument.spreadsheetml.'
          'sharedStrings+xml"/>'
          '</Types>',
    );
    datei(
      '_rels/.rels',
      '$kopf<Relationships xmlns="http://schemas.openxmlformats.org/package/'
          '2006/relationships"><Relationship Id="rId1" Type="http://'
          'schemas.openxmlformats.org/officeDocument/2006/relationships/'
          'officeDocument" Target="xl/workbook.xml"/></Relationships>',
    );
    datei(
      'xl/workbook.xml',
      '$kopf<workbook xmlns="http://schemas.openxmlformats.org/'
          'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.'
          'org/officeDocument/2006/relationships">'
          // Die Blattansichten verweisen mit workbookViewId="0" hierauf.
          '<bookViews><workbookView/></bookViews><sheets>'
          '${[
        for (var i = 0; i < _blaetter.length; i++)
          '<sheet name="${_esc(_blaetter[i].name)}" sheetId="${i + 1}" '
              'r:id="rId${i + 1}"/>',
      ].join()}'
          '</sheets></workbook>',
    );
    // Beziehungsziele RELATIV — die Lesebibliothek setzt „xl/" davor.
    final n = _blaetter.length;
    datei(
      'xl/_rels/workbook.xml.rels',
      '$kopf<Relationships xmlns="http://schemas.openxmlformats.org/package/'
          '2006/relationships">'
          '${[
        for (var i = 0; i < n; i++)
          '<Relationship Id="rId${i + 1}" Type="http://schemas.'
              'openxmlformats.org/officeDocument/2006/relationships/'
              'worksheet" Target="worksheets/sheet${i + 1}.xml"/>',
      ].join()}'
          '<Relationship Id="rId${n + 1}" Type="http://schemas.'
          'openxmlformats.org/officeDocument/2006/relationships/styles" '
          'Target="styles.xml"/>'
          '<Relationship Id="rId${n + 2}" Type="http://schemas.'
          'openxmlformats.org/officeDocument/2006/relationships/'
          'sharedStrings" Target="sharedStrings.xml"/>'
          '</Relationships>',
    );
    for (var i = 0; i < blattXml.length; i++) {
      datei('xl/worksheets/sheet${i + 1}.xml', blattXml[i]);
    }
    datei('xl/styles.xml', _stylesXml);
    datei(
      'xl/sharedStrings.xml',
      '$kopf<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
          '2006/main" count="${_texte.length}" '
          'uniqueCount="${_texte.length}">'
          '${[
        for (final t in _texte)
          '<si><t xml:space="preserve">${_esc(t)}</t></si>',
      ].join()}'
          '</sst>',
    );

    final gepackt = ZipEncoder().encode(archiv);
    if (gepackt == null) {
      throw StateError('Die Mappe konnte nicht gepackt werden.');
    }
    return Uint8List.fromList(gepackt);
  }
}

/// Ein Blatt des [XlsxSchreiber]s. Zeilen und Spalten zählen ab 1.
class XlsxSchreibBlatt {
  XlsxSchreibBlatt._(this._mappe, this.name, this._reiter);

  final XlsxSchreiber _mappe;
  final String name;
  final String? _reiter;

  /// Zeile → Spalte → Zell-XML. Sortiert, weil Excel Zeilen und Zellen in
  /// aufsteigender Reihenfolge verlangt.
  final SplayTreeMap<int, SplayTreeMap<int, String>> _zellen = SplayTreeMap();
  final Map<int, double> _hoehen = {};
  final Map<int, double> _breiten = {};
  final List<String> _verbunden = [];
  final List<String> _auswahl = [];
  final List<String> _verweise = [];
  String? _fixiert;

  void _setze(int r, int c, String xml) =>
      _zellen.putIfAbsent(r, SplayTreeMap.new)[c] = xml;

  String _ref(int r, int c) => '${xlsxSpalte(c)}$r';

  void text(int r, int c, String? wert, int stil) {
    if (wert == null || wert.isEmpty) return leer(r, c, stil);
    _setze(
      r,
      c,
      '<c r="${_ref(r, c)}" s="$stil" t="s"><v>${_mappe.textNr(wert)}</v></c>',
    );
  }

  /// Eine Zahl — „NaN" oder „Infinity" kennt Excel nicht, die Zelle
  /// bleibt dann leer.
  void zahl(int r, int c, num wert, int stil) {
    if (!wert.isFinite) return leer(r, c, stil);
    _setze(r, c, '<c r="${_ref(r, c)}" s="$stil"><v>$wert</v></c>');
  }

  void formel(int r, int c, String f, int stil) =>
      _setze(r, c, '<c r="${_ref(r, c)}" s="$stil"><f>${_esc(f)}</f></c>');

  void leer(int r, int c, int stil) =>
      _setze(r, c, '<c r="${_ref(r, c)}" s="$stil"/>');

  void zahlOderLeer(int r, int c, num? wert, int stil) {
    if (wert == null) {
      leer(r, c, stil);
    } else {
      zahl(r, c, wert, stil);
    }
  }

  void verbinde(String bereich) => _verbunden.add(bereich);
  void hoehe(int r, double h) => _hoehen[r] = h;
  void breiten(Map<int, double> b) => _breiten.addAll(b);
  void fixiere(String zelle) => _fixiert = zelle;

  void auswahl(String bereich, String quelle) => _auswahl.add(
        '<dataValidation type="list" allowBlank="1" showInputMessage="1" '
        'showErrorMessage="0" sqref="$bereich">'
        '<formula1>${_esc(quelle)}</formula1></dataValidation>',
      );

  void verweis(String zelle, String ziel) => _verweise.add(
        '<hyperlink ref="$zelle" location="${_esc(ziel)}" display="öffnen"/>',
      );

  String xml() {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
          'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.'
          'org/officeDocument/2006/relationships">');
    // Reihenfolge der Elemente ist im OOXML-Schema festgelegt.
    if (_reiter != null) {
      b.write('<sheetPr><tabColor rgb="$_reiter"/></sheetPr>');
    }
    b.write('<sheetViews><sheetView workbookViewId="0">');
    final f = _fixiert;
    if (f != null) {
      final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(f)!;
      final spalteNr = m.group(1)!.codeUnits.fold<int>(
            0,
            (s, u) => s * 26 + (u - 64),
          );
      final xSplit = spalteNr - 1;
      final ySplit = int.parse(m.group(2)!) - 1;
      final pane = xSplit > 0 && ySplit > 0
          ? 'bottomRight'
          : (ySplit > 0 ? 'bottomLeft' : 'topRight');
      b.write('<pane${xSplit > 0 ? ' xSplit="$xSplit"' : ''}'
          '${ySplit > 0 ? ' ySplit="$ySplit"' : ''} topLeftCell="$f" '
          'activePane="$pane" state="frozen"/>');
    }
    b.write('</sheetView></sheetViews>');
    b.write('<sheetFormatPr defaultRowHeight="15"/>');
    if (_breiten.isNotEmpty) {
      b.write('<cols>');
      for (final e in (SplayTreeMap<int, double>.from(_breiten)).entries) {
        b.write('<col min="${e.key}" max="${e.key}" width="${e.value}" '
            'customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (final z in _zellen.entries) {
      final h = _hoehen[z.key];
      b.write('<row r="${z.key}"'
          '${h == null ? '' : ' ht="$h" customHeight="1"'}>');
      z.value.values.forEach(b.write);
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (_verbunden.isNotEmpty) {
      b.write('<mergeCells count="${_verbunden.length}">');
      for (final v in _verbunden) {
        b.write('<mergeCell ref="$v"/>');
      }
      b.write('</mergeCells>');
    }
    if (_auswahl.isNotEmpty) {
      b
        ..write('<dataValidations count="${_auswahl.length}">')
        ..writeAll(_auswahl)
        ..write('</dataValidations>');
    }
    if (_verweise.isNotEmpty) {
      b
        ..write('<hyperlinks>')
        ..writeAll(_verweise)
        ..write('</hyperlinks>');
    }
    b.write('<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/>');
    b.write('</worksheet>');
    return b.toString();
  }
}


