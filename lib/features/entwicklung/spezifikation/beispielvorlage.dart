import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'spezifikation_werte.dart';

// Eine schlichte Beispielvorlage mit allen Platzhaltern — ohne Firmen-
// angaben. Sie zeigt, wie eine eigene Vorlage aufgebaut sein kann: Man
// öffnet die eigene Spezifikation in Excel und schreibt die Platzhalter in
// die Zellen, die gefüllt werden sollen.

const String _kopf = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _spalte(int c) {
  var n = c;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

class _VorlagenBlatt {
  _VorlagenBlatt(this.name);

  final String name;
  final Map<int, Map<int, (String, int)>> _zellen = {};
  final List<String> _verbunden = [];
  int _zeile = 0;

  int get zeile => _zeile;

  /// Schreibt [texte] in die nächste Zeile ab Spalte A. Stil 1 = fett.
  void schreibe(List<String> texte, {int stil = 0}) {
    _zeile++;
    for (var i = 0; i < texte.length; i++) {
      if (texte[i].isEmpty) continue;
      _zellen.putIfAbsent(_zeile, () => {})[i + 1] = (texte[i], stil);
    }
  }

  void leer() => _zeile++;

  void verbinde(String bereich) => _verbunden.add(bereich);

  String xml(Map<int, double> breiten) {
    final b = StringBuffer()
      ..write(_kopf)
      ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
        '2006/main">',
      );
    if (breiten.isNotEmpty) {
      b.write('<cols>');
      for (final MapEntry(:key, :value) in breiten.entries) {
        b.write('<col min="$key" max="$key" width="$value" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    final zeilen = _zellen.keys.toList()..sort();
    for (final r in zeilen) {
      b.write('<row r="$r">');
      final spalten = _zellen[r]!.keys.toList()..sort();
      for (final c in spalten) {
        final (text, stil) = _zellen[r]![c]!;
        b.write(
          '<c r="${_spalte(c)}$r" s="$stil" t="inlineStr"><is>'
          '<t xml:space="preserve">${_esc(text)}</t></is></c>',
        );
      }
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
    b.write('</worksheet>');
    return b.toString();
  }
}

const String _styles = '$_kopf<styleSheet '
    'xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
    '2006/main">'
    '<fonts count="3">'
    '<font><sz val="10"/><name val="Arial"/></font>'
    '<font><b/><sz val="10"/><name val="Arial"/></font>'
    '<font><b/><sz val="14"/><name val="Arial"/></font>'
    '</fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/>'
    '</border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
    'borderId="0"/></cellStyleXfs>'
    '<cellXfs count="4">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyAlignment="1"><alignment horizontal="center"/></xf>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Standard" xfId="0" '
    'builtinId="0"/></cellStyles>'
    '</styleSheet>';

/// Baut die Beispielvorlage als .xlsx.
Uint8List beispielvorlage() {
  String p(String name) => '{{$name}}';

  final spez = _VorlagenBlatt('Spezifikation')
    ..schreibe(['Produktspezifikation', '', '', p('gueltig_ab')], stil: 2)
    ..schreibe(['', '', 'Kürzel', p('kuerzel')])
    ..leer()
    ..schreibe(['Artikelnummer', p('artikelnummer')])
    ..schreibe(['Bezeichnung', p('bezeichnung')])
    ..schreibe(['Kunde', p('kunde')])
    ..schreibe(['Projekt', p('projekt')])
    ..schreibe(['Rezepturstand', p('stand')])
    ..schreibe(['Verlust', p('verlust')])
    ..schreibe(['Haltbarkeit', p('haltbarkeit')])
    ..schreibe(['Lagerung', p('lagerung')])
    ..schreibe(['Toleranz Stückgewicht', p('toleranz')])
    ..schreibe(['aw-Wert', p('aw')])
    ..leer()
    ..schreibe(['Zutaten', p('zutaten')]);
  spez
    ..verbinde('B${spez.zeile}:D${spez.zeile}')
    ..schreibe(['Fleischanteil', p('fleischanteil')])
    ..schreibe(['BEFFE', p('beffe')])
    ..schreibe(['Allergene', p('allergene')])
    ..leer()
    ..schreibe(['Verarbeitungshilfsstoffe', 'aus'], stil: 1);
  for (var i = 1; i <= kHilfsstoffPlaetze; i++) {
    spez.schreibe([p('hilfsstoff.$i.name'), p('hilfsstoff.$i.quelle')]);
  }
  spez
    ..leer()
    ..schreibe(['Sensorik'], stil: 1)
    ..schreibe(['Aussehen', p('sensorik.aussehen')])
    ..schreibe(['Geruch', p('sensorik.geruch')])
    ..schreibe(['Geschmack', p('sensorik.geschmack')])
    ..schreibe(['Konsistenz', p('sensorik.konsistenz')])
    ..schreibe(['Länge', p('sensorik.laenge')])
    ..schreibe(['Durchmesser', p('sensorik.durchmesser')])
    ..schreibe(['Stückgewicht', p('sensorik.gewicht')])
    ..schreibe(['Zubereitung', p('sensorik.zubereitung')])
    ..leer()
    ..schreibe(['Produkthinweise', p('hinweise')], stil: 1);
  for (var i = 1; i <= kHinweisPlaetze; i++) {
    spez.schreibe(['Hinweis $i', p('hinweis.$i')]);
  }
  spez
    ..leer()
    ..schreibe(['Nährwerte je 100 g'], stil: 1)
    ..schreibe(['Energie', p('naehrwert.energie')])
    ..schreibe(['Energie (kJ)', p('naehrwert.energie_kj')])
    ..schreibe(['Energie (kcal)', p('naehrwert.energie_kcal')])
    ..schreibe(['Fett (g)', p('naehrwert.fett')])
    ..schreibe([
      'davon gesättigte Fettsäuren (g)',
      p('naehrwert.gesaettigte_fettsaeuren'),
    ])
    ..schreibe(['Kohlenhydrate (g)', p('naehrwert.kohlenhydrate')])
    ..schreibe(['davon Zucker (g)', p('naehrwert.zucker')])
    ..schreibe(['Eiweiß (g)', p('naehrwert.eiweiss')])
    ..schreibe(['Salz (g)', p('naehrwert.salz')])
    ..leer()
    ..schreibe(['Allergen', 'ja', 'nein', 'Spuren', 'aus'], stil: 1);
  for (final a in kSpezAllergene) {
    spez.schreibe([
      allergenName(a, SpezSprache.de),
      p('allergen.$a.ja'),
      p('allergen.$a.nein'),
      p('allergen.$a.spuren'),
      p('allergen.$a.quelle'),
    ]);
  }
  spez
    ..leer()
    ..schreibe(['Verpackung'], stil: 1);
  for (final x in kSpezifikationPlatzhalter) {
    if (x.name.startsWith('verpackung.')) {
      spez.schreibe([x.erklaerung, p(x.name)]);
    }
  }

  // Die Liste aller Platzhalter — ohne Klammern, sonst würden sie beim
  // Füllen ersetzt.
  final liste = _VorlagenBlatt('Platzhalter')
    ..schreibe(
      ['Platzhalter (in der Vorlage in doppelten geschweiften Klammern)', 'Bedeutung'],
      stil: 1,
    );
  for (final x in kSpezifikationPlatzhalter) {
    liste.schreibe([x.name, x.erklaerung]);
  }

  final blaetter = [spez, liste];
  final archiv = Archive();
  void datei(String pfad, String inhalt) {
    final bytes = utf8.encode(inhalt);
    archiv.addFile(ArchiveFile(pfad, bytes.length, bytes));
  }

  datei(
    '[Content_Types].xml',
    '$_kopf<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
        'content-types">'
        '<Default Extension="rels" ContentType="application/'
        'vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '${[
      for (var i = 0; i < blaetter.length; i++)
        '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.'
            'spreadsheetml.worksheet+xml"/>',
    ].join()}'
        '<Override PartName="/xl/styles.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
  );
  datei(
    '_rels/.rels',
    '$_kopf<Relationships xmlns="http://schemas.openxmlformats.org/package/'
        '2006/relationships"><Relationship Id="rId1" Type="http://'
        'schemas.openxmlformats.org/officeDocument/2006/relationships/'
        'officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  datei(
    'xl/workbook.xml',
    '$_kopf<workbook xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.'
        'org/officeDocument/2006/relationships">'
        '<bookViews><workbookView/></bookViews><sheets>'
        '${[
      for (var i = 0; i < blaetter.length; i++)
        '<sheet name="${_esc(blaetter[i].name)}" sheetId="${i + 1}" '
            'r:id="rId${i + 1}"/>',
    ].join()}'
        '</sheets></workbook>',
  );
  final n = blaetter.length;
  datei(
    'xl/_rels/workbook.xml.rels',
    '$_kopf<Relationships xmlns="http://schemas.openxmlformats.org/package/'
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
        '</Relationships>',
  );
  datei(
    'xl/worksheets/sheet1.xml',
    spez.xml(const {1: 34, 2: 48, 3: 12, 4: 14, 5: 40}),
  );
  datei('xl/worksheets/sheet2.xml', liste.xml(const {1: 36, 2: 60}));
  datei('xl/styles.xml', _styles);

  final gepackt = ZipEncoder().encode(archiv);
  if (gepackt == null) {
    throw StateError('Die Beispielvorlage ließ sich nicht packen.');
  }
  return Uint8List.fromList(gepackt);
}
