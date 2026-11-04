import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'fehler_text.dart';

// Liest Excel-Mappen (.xlsx) so weit, wie Importe der App es brauchen:
// alle Blätter mit Namen, Texte (geteilt, direkt in der Zelle oder
// formatiert), Zahlen — bei Formeln das gespeicherte Ergebnis —,
// Wahrheits- und Fehlerwerte und ob eine Zahl als Datum formatiert ist.
//
// Ohne das excel-Paket: Es liefert bei Formeln nur die Formel, nicht ihr
// Ergebnis — wer in Excel etwa die Energie ausrechnen lässt, bekäme sonst
// „=B2*37" statt der Zahl.

/// Was in einer Zelle steht.
enum XlsxArt {
  text,
  zahl,

  /// Eine Zahl mit Datums- oder Zeitformat. So legt eine deutsche Excel
  /// „1.5" ab: als 1. Mai.
  datum,

  /// WAHR oder FALSCH.
  wahrheitswert,

  /// Ein Fehlerwert wie „#NV" — oder eine Formel ohne gespeichertes
  /// Ergebnis.
  fehler,
}

/// Eine gelesene Zelle.
class XlsxZelle {
  const XlsxZelle(this.art, this.wert);

  final XlsxArt art;

  /// Der Inhalt als Text: bei Zahlen die Zahl, wie die Mappe sie speichert
  /// („12.5"), bei Wahrheitswerten „1" oder „0", bei Fehlern der Fehler.
  final String wert;

  /// Die Zahl — null bei Text, Wahrheits- und Fehlerwerten.
  double? get zahl => art == XlsxArt.zahl || art == XlsxArt.datum
      ? double.tryParse(wert)
      : null;

  @override
  String toString() => '${art.name}($wert)';
}

/// Ein Blatt der Mappe: Zeile → Spalte → Zelle, beide ab 1 wie in Excel.
/// Leere Zellen fehlen.
class XlsxTabelle {
  const XlsxTabelle(this.name, this.zellen);

  final String name;
  final Map<int, Map<int, XlsxZelle>> zellen;

  XlsxZelle? zelle(int zeile, int spalte) => zellen[zeile]?[spalte];

  /// Die Nummer der letzten Zeile mit Inhalt — 0 bei einem leeren Blatt.
  int get letzteZeile =>
      zellen.keys.fold(0, (letzte, z) => z > letzte ? z : letzte);
}

/// Liest alle Blätter der Mappe [bytes], in ihrer Reihenfolge.
///
/// Wirft eine [FormatException] mit lesbarer Meldung, wenn [bytes] keine
/// Excel-Mappe ist.
List<XlsxTabelle> xlsxLesen(Uint8List bytes) {
  // Echte .xlsx-Dateien sind ZIP-Pakete und beginnen mit „PK".
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
    throw const FormatException(
      'Das ist keine Excel-Datei (.xlsx). Ältere .xls-Dateien bitte in '
      'Excel als .xlsx speichern.',
    );
  }
  final Archive archiv;
  try {
    archiv = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw FormatException(
      'Die Datei ließ sich nicht öffnen: ${fehlerText(e)}',
    );
  }
  final dateien = <String, ArchiveFile>{
    for (final d in archiv.files)
      if (d.isFile) _pfad(d.name).toLowerCase(): d,
  };
  String? inhalt(String pfad) {
    final roh = dateien[_pfad(pfad).toLowerCase()]?.content;
    if (roh is! List<int>) return null;
    final text = utf8.decode(roh, allowMalformed: true);
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  }

  final mappe = inhalt('xl/workbook.xml');
  if (mappe == null) {
    throw const FormatException(
      'Die Datei ist keine Excel-Mappe: Ihr fehlt das Inhaltsverzeichnis.',
    );
  }
  final ziele = <String, String>{};
  String? geteiltPfad;
  String? formatePfad;
  for (final m in _reBeziehung.allMatches(
    inhalt('xl/_rels/workbook.xml.rels') ?? '',
  )) {
    final id = _attribut(m[1]!, 'Id');
    final ziel = _attribut(m[1]!, 'Target');
    final typ = _attribut(m[1]!, 'Type') ?? '';
    if (id == null || ziel == null) continue;
    final pfad = ziel.startsWith('/') ? ziel.substring(1) : 'xl/$ziel';
    ziele[id] = pfad;
    if (typ.endsWith('/sharedStrings')) geteiltPfad = pfad;
    if (typ.endsWith('/styles')) formatePfad = pfad;
  }

  final geteilt = [
    for (final m in _reGeteilt.allMatches(
      inhalt(geteiltPfad ?? 'xl/sharedStrings.xml') ?? '',
    ))
      _texteAus(m[1]!.replaceAll(_reLautschrift, '')),
  ];
  final datumsStile = _datumsStile(
    inhalt(formatePfad ?? 'xl/styles.xml') ?? '',
  );

  final tabellen = <XlsxTabelle>[];
  var nummer = 0;
  for (final m in _reBlatt.allMatches(mappe)) {
    nummer++;
    final name = _attribut(m[1]!, 'name') ?? 'Blatt $nummer';
    final id = _reBlattVerweis.firstMatch(m[1]!)?[2];
    final pfad = ziele[id] ?? 'xl/worksheets/sheet$nummer.xml';
    final xml = inhalt(pfad);
    if (xml == null) continue;
    tabellen.add(
      XlsxTabelle(
        _entschluesseln(name),
        _zellenAus(xml, geteilt, datumsStile),
      ),
    );
  }
  return tabellen;
}

// ── Blätter ─────────────────────────────────────────────────────────────

// Elemente dürfen ein Namensraum-Präfix tragen („x:row") — manche
// Programme schreiben so.
const String _ns = r'(?:[A-Za-z_][\w.-]*:)?';

final _reBlatt = RegExp('<${_ns}sheet\\b([^>]*?)/?>');
final _reBlattVerweis = RegExp(r'''\b[\w.-]+:id=(["'])(.*?)\1''');
final _reBeziehung = RegExp('<${_ns}Relationship\\b([^>]*?)/?>');
final _reZeile =
    RegExp('<${_ns}row\\b([^>]*?)(?:/>|>(.*?)</${_ns}row>)', dotAll: true);
final _reZelle =
    RegExp('<${_ns}c\\b([^>]*?)(?:/>|>(.*?)</${_ns}c>)', dotAll: true);
final _reWert = RegExp('<${_ns}v(?:\\s[^>]*)?>(.*?)</${_ns}v>', dotAll: true);
final _reFormel = RegExp('<${_ns}f\\b');
final _reText = RegExp('<${_ns}t(?:\\s[^>]*)?>(.*?)</${_ns}t>', dotAll: true);
final _reGeteilt =
    RegExp('<${_ns}si\\b[^>]*?(?:/>|>(.*?)</${_ns}si>)', dotAll: true);
final _reLautschrift = RegExp('<${_ns}rPh\\b.*?</${_ns}rPh>', dotAll: true);
final _reZellbezug = RegExp(r'^([A-Za-z]{1,3})(\d+)$');

/// Der Wert des Attributs [name] in [attribute] — null, wenn es fehlt.
String? _attribut(String attribute, String name) => RegExp(
      '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*(["\'])(.*?)\\1',
      dotAll: true,
    ).firstMatch(attribute)?[2];

String _pfad(String pfad) {
  var p = pfad.replaceAll('\\', '/');
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  // „xl/worksheets/../sharedStrings.xml" → „xl/sharedStrings.xml"
  final teile = <String>[];
  for (final t in p.split('/')) {
    if (t == '..') {
      if (teile.isNotEmpty) teile.removeLast();
    } else if (t.isNotEmpty && t != '.') {
      teile.add(t);
    }
  }
  return teile.join('/');
}

Map<int, Map<int, XlsxZelle>> _zellenAus(
  String xml,
  List<String> geteilt,
  Set<int> datumsStile,
) {
  final zeilen = <int, Map<int, XlsxZelle>>{};
  var zeileNr = 0;
  for (final zm in _reZeile.allMatches(xml)) {
    zeileNr = int.tryParse(_attribut(zm[1]!, 'r') ?? '') ?? zeileNr + 1;
    final koerper = zm[2];
    if (koerper == null) continue;
    var spalteNr = 0;
    final zellen = <int, XlsxZelle>{};
    for (final cm in _reZelle.allMatches(koerper)) {
      final attribute = cm[1]!;
      final bezug = _reZellbezug.firstMatch(_attribut(attribute, 'r') ?? '');
      spalteNr = bezug == null ? spalteNr + 1 : _spaltenNummer(bezug[1]!);
      final zelle = _zelleAus(
        attribute,
        cm[2] ?? '',
        geteilt,
        datumsStile,
      );
      if (zelle != null) zellen[spalteNr] = zelle;
    }
    if (zellen.isNotEmpty) zeilen[zeileNr] = zellen;
  }
  return zeilen;
}

XlsxZelle? _zelleAus(
  String attribute,
  String innen,
  List<String> geteilt,
  Set<int> datumsStile,
) {
  final typ = _attribut(attribute, 't') ?? 'n';
  final roh = _reWert.firstMatch(innen)?[1];
  switch (typ) {
    case 's':
      final i = int.tryParse(roh?.trim() ?? '');
      if (i == null || i < 0 || i >= geteilt.length) return null;
      return _text(geteilt[i]);
    case 'inlineStr':
      return _text(_texteAus(innen));
    case 'str':
      return roh == null ? null : _text(_entschluesseln(roh));
    case 'b':
      return roh == null
          ? null
          : XlsxZelle(XlsxArt.wahrheitswert, roh.trim() == '1' ? '1' : '0');
    case 'e':
      return XlsxZelle(XlsxArt.fehler, _entschluesseln(roh ?? '#FEHLER'));
    case 'd':
      // Ein Datum als ISO-Text — Excel schreibt so nur in „Strict".
      return roh == null ? null : XlsxZelle(XlsxArt.datum, roh.trim());
  }
  if (roh == null || roh.trim().isEmpty) {
    // Eine Formel ohne gespeichertes Ergebnis — etwa aus einem Programm,
    // das nicht rechnet. Leer ist sie trotzdem nicht.
    return _reFormel.hasMatch(innen)
        ? const XlsxZelle(XlsxArt.fehler, '#FORMEL')
        : null;
  }
  final stil = int.tryParse(_attribut(attribute, 's') ?? '') ?? 0;
  return XlsxZelle(
    datumsStile.contains(stil) ? XlsxArt.datum : XlsxArt.zahl,
    roh.trim(),
  );
}

XlsxZelle? _text(String text) =>
    text.isEmpty ? null : XlsxZelle(XlsxArt.text, text);

int _spaltenNummer(String buchstaben) {
  var n = 0;
  for (final c in buchstaben.toUpperCase().codeUnits) {
    n = n * 26 + (c - 64);
  }
  return n;
}

// ── Texte ───────────────────────────────────────────────────────────────

/// Alle Texte eines Elements, aneinandergehängt — formatierte Zellen
/// bestehen aus mehreren Stücken mit je eigenem `<t>`.
String _texteAus(String xml) =>
    _reText.allMatches(xml).map((m) => _entschluesseln(m[1]!)).join();

final _reEntity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);');

/// Excel schreibt Steuerzeichen wie den Zeilenvorschub als `_x000D_`.
final _reExcelZeichen = RegExp(r'_x([0-9A-Fa-f]{4})_');

/// XML-Entities und Excels `_xHHHH_` auflösen — je in einem Durchgang,
/// sonst würde aus „&amp;lt;" fälschlich „<". Zeilenumbrüche werden zu
/// `\n`.
String _entschluesseln(String s) {
  var t = s;
  if (t.contains('&')) {
    t = t.replaceAllMapped(_reEntity, (m) {
      final k = m[1]!;
      switch (k) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final code = k.startsWith('#x')
          ? int.tryParse(k.substring(2), radix: 16)
          : int.tryParse(k.substring(1));
      return code == null ? m[0]! : String.fromCharCode(code);
    });
  }
  if (t.contains('_x')) {
    t = t.replaceAllMapped(
      _reExcelZeichen,
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    );
  }
  return t.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

// ── Formate ─────────────────────────────────────────────────────────────

/// Die eingebauten Zahlenformate für Datum und Uhrzeit.
const Set<int> _eingebauteDaten = {
  14, 15, 16, 17, 18, 19, 20, 21, 22, //
  27, 28, 29, 30, 31, 32, 33, 34, 35, 36, //
  45, 46, 47, 50, 51, 52, 53, 54, 55, 56, 57, 58,
};

final _reFormatBlock = RegExp(
  '<${_ns}numFmts\\b[^>]*>(.*?)</${_ns}numFmts>',
  dotAll: true,
);
final _reFormat = RegExp('<${_ns}numFmt\\b([^>]*?)/?>');
final _reZellformate = RegExp(
  '<${_ns}cellXfs\\b[^>]*>(.*?)</${_ns}cellXfs>',
  dotAll: true,
);
final _reZellformat = RegExp('<${_ns}xf\\b([^>]*?)(?:/>|>)');

/// Die Nummern der Zellformate, die eine Zahl als Datum oder Uhrzeit
/// zeigen.
Set<int> _datumsStile(String xml) {
  final eigene = <int, String>{};
  final block = _reFormatBlock.firstMatch(xml)?[1] ?? '';
  for (final m in _reFormat.allMatches(block)) {
    final id = int.tryParse(_attribut(m[1]!, 'numFmtId') ?? '');
    final code = _attribut(m[1]!, 'formatCode');
    if (id != null && code != null) eigene[id] = _entschluesseln(code);
  }
  final stile = <int>{};
  final formate = _reZellformate.firstMatch(xml)?[1] ?? '';
  var i = 0;
  for (final m in _reZellformat.allMatches(formate)) {
    final id = int.tryParse(_attribut(m[1]!, 'numFmtId') ?? '') ?? 0;
    final code = eigene[id];
    if (_eingebauteDaten.contains(id) ||
        (code != null && istDatumsformat(code))) {
      stile.add(i);
    }
    i++;
  }
  return stile;
}

final _reInAnfuehrung = RegExp(r'"[^"]*"');
final _reMaskiert = RegExp(r'\\.');
final _reEckig = RegExp(r'\[([^\]]*)\]');
final _reDatumsTeil = RegExp('[dmyhs]');

/// Ob der Formatcode [code] eine Zahl als Datum oder Uhrzeit zeigt —
/// „DD.MM.YYYY" ja, „0.0 %" nicht.
bool istDatumsformat(String code) {
  final ohne = code
      .replaceAll(_reInAnfuehrung, '')
      .replaceAll(_reMaskiert, '')
      // [h] und [mm] zählen Stunden und Minuten; [Red] oder [$-407]
      // färben oder nennen die Sprache.
      .replaceAllMapped(
        _reEckig,
        (m) => RegExp(r'^[hms]+$', caseSensitive: false).hasMatch(m[1]!)
            ? m[1]!
            : '',
      )
      .toLowerCase();
  // Der erste Abschnitt entscheidet; „General" hat keinen Datumsteil.
  final erster = ohne.split(';').first;
  return erster != 'general' && _reDatumsTeil.hasMatch(erster);
}
