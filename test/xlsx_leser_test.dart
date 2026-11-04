import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/utils/xlsx_leser.dart';
import 'package:produktion_planer/core/utils/xlsx_schreiber.dart';

/// Der Leser für Excel-Mappen: Texte in allen Formen, Zahlen und
/// Formelergebnisse, Wahrheits- und Fehlerwerte, Datumsformate — und was
/// andere Programme anders schreiben als Excel.
void main() {
  const ns =
      'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships"';

  /// Die Beziehungen der Mappe: je ID die Art („worksheet",
  /// „sharedStrings", „styles") und das Ziel.
  String rels(Map<String, (String, String)> ziele) =>
      '<?xml version="1.0"?><Relationships xmlns="http://schemas.'
      'openxmlformats.org/package/2006/relationships">'
      '${[
        for (final MapEntry(key: id, value: (art, ziel)) in ziele.entries)
          '<Relationship Id="$id" Type="http://schemas.openxmlformats.org/'
              'officeDocument/2006/relationships/$art" Target="$ziel"/>',
      ].join()}'
      '</Relationships>';

  /// Eine Mappe mit einem Blatt „Blatt" aus [zeilen] (dem Inhalt von
  /// sheetData), dazu geteilten Texten und Formaten.
  Uint8List mappe(
    String zeilen, {
    List<String> geteilt = const [],
    String formate = '',
    Map<String, String> weitere = const {},
  }) =>
      zip({
        'xl/workbook.xml': '<workbook $ns><sheets>'
            '<sheet name="Blatt" sheetId="1" r:id="rId1"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels': rels({
          'rId1': ('worksheet', 'worksheets/sheet1.xml'),
          'rId2': ('sharedStrings', 'sharedStrings.xml'),
          'rId3': ('styles', 'styles.xml'),
        }),
        'xl/worksheets/sheet1.xml':
            '<worksheet $ns><sheetData>$zeilen</sheetData></worksheet>',
        'xl/sharedStrings.xml': '<sst $ns>'
            '${geteilt.map((s) => '<si>$s</si>').join()}</sst>',
        'xl/styles.xml': '<styleSheet $ns>$formate</styleSheet>',
        ...weitere,
      });

  XlsxTabelle blatt(Uint8List bytes) => xlsxLesen(bytes).single;

  test('Texte: geteilt, formatiert, direkt in der Zelle, als Formel', () {
    final t = blatt(
      mappe(
        '<row r="1">'
        '<c r="A1" t="s"><v>0</v></c>'
        '<c r="B1" t="s"><v>1</v></c>'
        '<c r="C1" t="inlineStr"><is><t>Sal</t><r><t>z</t></r></is></c>'
        '<c r="D1" t="str"><f>A1&amp;"!"</f><v>Fett!</v></c>'
        '<c r="E1" t="s"><v>2</v></c>'
        '<c r="F1" t="s"><v>3</v></c>'
        '</row>',
        geteilt: [
          '<t>Fett</t>',
          '<r><rPr><b/></rPr><t>Eiw</t></r><r><t>eiß</t></r>'
              '<rPh sb="0" eb="1"><t>ignorieren</t></rPh>',
          '<t xml:space="preserve">a &amp;lt; b &amp; c</t>',
          '<t>Zeile_x000D__x000A_zwei</t>',
        ],
      ),
    );
    expect(t.zelle(1, 1)?.wert, 'Fett');
    expect(t.zelle(1, 2)?.wert, 'Eiweiß');
    expect(t.zelle(1, 3)?.wert, 'Salz');
    expect(t.zelle(1, 3)?.art, XlsxArt.text);
    expect(t.zelle(1, 4)?.wert, 'Fett!');
    expect(t.zelle(1, 5)?.wert, 'a &lt; b & c');
    expect(t.zelle(1, 6)?.wert, 'Zeile\nzwei');
  });

  test('Zahlen, Formelergebnisse, Wahrheits- und Fehlerwerte', () {
    final t = blatt(
      mappe(
        '<row r="2">'
        '<c r="A2"><v>12.5</v></c>'
        '<c r="B2"><f>A2*2</f><v>25</v></c>'
        '<c r="C2"><f>A2*2</f></c>'
        '<c r="D2" t="b"><v>1</v></c>'
        '<c r="E2" t="e"><v>#N/A</v></c>'
        '<c r="F2" s="0"/>'
        '</row>',
      ),
    );
    expect(t.zelle(2, 1)?.art, XlsxArt.zahl);
    expect(t.zelle(2, 1)?.zahl, 12.5);
    expect(t.zelle(2, 2)?.zahl, 25, reason: 'das Ergebnis, nicht die Formel');
    expect(t.zelle(2, 3)?.art, XlsxArt.fehler);
    expect(t.zelle(2, 4)?.art, XlsxArt.wahrheitswert);
    expect(t.zelle(2, 4)?.wert, '1');
    expect(t.zelle(2, 4)?.zahl, isNull);
    expect(t.zelle(2, 5)?.wert, '#N/A');
    expect(t.zelle(2, 6), isNull, reason: 'leere Zellen fehlen');
    expect(t.zellen.keys, [2]);
    expect(t.letzteZeile, 2);
  });

  test('Datumsformate: eigene und eingebaute, Prozent ist keins', () {
    const formate = '<numFmts count="3">'
        '<numFmt numFmtId="164" formatCode="DD.MM.YYYY"/>'
        '<numFmt numFmtId="165" formatCode="0.0%"/>'
        '<numFmt numFmtId="166" formatCode="[Red]0.00;&quot;minus&quot;0"/>'
        '</numFmts>'
        '<cellXfs count="6">'
        '<xf numFmtId="0"/>'
        '<xf numFmtId="164"/>'
        '<xf numFmtId="14"/>'
        '<xf numFmtId="165"/>'
        '<xf numFmtId="166"/>'
        '<xf numFmtId="46"/>'
        '</cellXfs>';
    final t = blatt(
      mappe(
        '<row r="1">'
        '<c r="A1" s="0"><v>45000</v></c>'
        '<c r="B1" s="1"><v>45000</v></c>'
        '<c r="C1" s="2"><v>45000</v></c>'
        '<c r="D1" s="3"><v>0.5</v></c>'
        '<c r="E1" s="4"><v>3</v></c>'
        '<c r="F1" s="5"><v>1.5</v></c>'
        '</row>',
        formate: formate,
      ),
    );
    expect(
      [for (var c = 1; c <= 6; c++) t.zelle(1, c)!.art],
      [
        XlsxArt.zahl,
        XlsxArt.datum,
        XlsxArt.datum,
        XlsxArt.zahl,
        XlsxArt.zahl,
        XlsxArt.datum,
      ],
    );
    expect(istDatumsformat('[h]:mm'), isTrue);
    expect(istDatumsformat('[\$-407]DD. MMMM YYYY'), isTrue);
    expect(istDatumsformat('General'), isFalse);
    expect(istDatumsformat('#,##0.00 "kg"'), isFalse);
  });

  test('Namensraum-Präfixe, Zellen ohne Bezug, BOM und absolute Ziele', () {
    final bytes = zip({
      'xl/workbook.xml': '﻿<x:workbook xmlns:x="urn:x" '
          'xmlns:r="urn:r"><x:sheets>'
          '<x:sheet name="Ä &amp; B" sheetId="1" r:id="rId7"/>'
          '<x:sheet name="Zweites" sheetId="2" r:id="rId8"/>'
          '</x:sheets></x:workbook>',
      'xl/_rels/workbook.xml.rels': rels({
        'rId7': ('worksheet', '/xl/worksheets/eins.xml'),
        'rId8': ('worksheet', 'worksheets/../worksheets/zwei.xml'),
        'rId9': ('sharedStrings', '/xl/sharedStrings.xml'),
      }),
      'xl/worksheets/eins.xml': '<x:worksheet xmlns:x="urn:x"><x:sheetData>'
          '<x:row><x:c t="s"><x:v>0</x:v></x:c><x:c><x:v>7</x:v></x:c>'
          '</x:row>'
          '<x:row><x:c t="inlineStr"><x:is><x:t>unten</x:t></x:is></x:c>'
          '</x:row>'
          '</x:sheetData></x:worksheet>',
      'xl/worksheets/zwei.xml': '<worksheet><sheetData/></worksheet>',
      'XL/SharedStrings.xml': '<x:sst xmlns:x="urn:x"><x:si><x:t>oben'
          '</x:t></x:si></x:sst>',
    });
    final blaetter = xlsxLesen(bytes);
    expect(blaetter.map((b) => b.name), ['Ä & B', 'Zweites']);
    final t = blaetter.first;
    expect(t.zelle(1, 1)?.wert, 'oben');
    expect(t.zelle(1, 2)?.zahl, 7);
    expect(t.zelle(2, 1)?.wert, 'unten');
    expect(blaetter.last.zellen, isEmpty);
  });

  test('keine Excel-Datei', () {
    expect(
      () => xlsxLesen(Uint8List.fromList(utf8.encode('Name;Fett\nSalz;0'))),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('keine Excel-Datei'),
        ),
      ),
    );
    expect(
      () => xlsxLesen(zip({'word/document.xml': '<w/>'})),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Inhaltsverzeichnis'),
        ),
      ),
    );
  });

  test('liest, was der Schreiber schreibt', () {
    final m = XlsxSchreiber();
    m.blatt('Probe')
      ..text(1, 1, 'a < b & "c" \'d\'', 0)
      ..text(1, 2, 'zwei\nZeilen\tmit Tab', 0)
      ..text(1, 3, 'Grüße 🍖', 0)
      ..zahl(2, 1, 42, 0)
      ..zahl(2, 2, -0.125, 0)
      ..zahl(2, 3, double.nan, 0)
      ..text(2, 4, '', 0)
      ..zahl(3, 1, 7, XlsxStil.datum);
    final t = xlsxLesen(m.packe()).single;
    expect(t.name, 'Probe');
    expect(t.zelle(1, 1)?.wert, 'a < b & "c" \'d\'');
    expect(t.zelle(1, 2)?.wert, 'zwei\nZeilen\tmit Tab');
    expect(t.zelle(1, 3)?.wert, 'Grüße 🍖');
    expect(t.zelle(2, 1)?.zahl, 42);
    expect(t.zelle(2, 2)?.zahl, -0.125);
    expect(t.zelle(2, 3), isNull, reason: 'NaN bleibt leer');
    expect(t.zelle(2, 4), isNull);
    expect(t.zelle(3, 1)?.art, XlsxArt.datum);
  });
}

Uint8List zip(Map<String, String> dateien) {
  final archiv = Archive();
  for (final MapEntry(:key, :value) in dateien.entries) {
    final bytes = utf8.encode(value);
    archiv.addFile(ArchiveFile(key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archiv)!);
}
