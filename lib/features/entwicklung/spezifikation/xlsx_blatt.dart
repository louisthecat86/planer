import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../core/utils/fehler_text.dart';

// Eine Excel-Mappe (.xlsx) ist ein ZIP mit XML. Hier wird sie gerade so
// weit gelesen, wie Vorlage und Einrichten es brauchen: Texte, Zellen,
// verbundene Bereiche, Kopf- und Fußzeilen und die Kontrollkästchen
// (Formularsteuerelemente). Geändert wird nur, was sich ändern soll — die
// übrigen Dateien der Mappe bleiben Byte für Byte, wie sie waren.

/// Zeile und Spalte, beide ab 0: „C5" ist (zeile: 4, spalte: 2).
typedef Zellort = ({int zeile, int spalte});

/// „C5" → (4, 2). null, wenn es kein Zellbezug ist.
Zellort? zellortAus(String ref) {
  final m = RegExp(r'^\$?([A-Za-z]{1,3})\$?(\d+)$').firstMatch(ref.trim());
  if (m == null) return null;
  var spalte = 0;
  for (final c in m[1]!.toUpperCase().codeUnits) {
    spalte = spalte * 26 + (c - 64);
  }
  return (zeile: int.parse(m[2]!) - 1, spalte: spalte - 1);
}

/// 0 → „A", 26 → „AA".
String spaltenName(int spalte) {
  var n = spalte + 1;
  final teile = <String>[];
  while (n > 0) {
    final rest = (n - 1) % 26;
    teile.insert(0, String.fromCharCode(65 + rest));
    n = (n - 1) ~/ 26;
  }
  return teile.join();
}

/// (4, 2) → „C5".
String zellName(int zeile, int spalte) => '${spaltenName(spalte)}${zeile + 1}';

/// Ein rechteckiger Bereich, etwa ein verbundener „C5:K5".
class Bereich {
  const Bereich(this.z1, this.s1, this.z2, this.s2);

  /// Eine einzelne Zelle.
  const Bereich.zelle(int zeile, int spalte) : this(zeile, spalte, zeile, spalte);

  final int z1;
  final int s1;
  final int z2;
  final int s2;

  static Bereich? aus(String ref) {
    final teile = ref.split(':');
    final a = zellortAus(teile.first);
    final b = teile.length > 1 ? zellortAus(teile[1]) : a;
    if (a == null || b == null) return null;
    return Bereich(a.zeile, a.spalte, b.zeile, b.spalte);
  }

  bool enthaelt(int zeile, int spalte) =>
      zeile >= z1 && zeile <= z2 && spalte >= s1 && spalte <= s2;

  @override
  String toString() => z1 == z2 && s1 == s2
      ? zellName(z1, s1)
      : '${zellName(z1, s1)}:${zellName(z2, s2)}';
}

/// Ein Kontrollkästchen der Mappe.
class Kaestchen {
  const Kaestchen({
    required this.nummer,
    required this.zeile,
    required this.spalte,
    required this.vmlPfad,
    required this.angehakt,
    this.ctrlPropPfad,
  });

  /// Die Nummer der Form — in der VML „_x0000_s<nummer>".
  final int nummer;

  /// Die Zelle der linken oberen Ecke.
  final int zeile;
  final int spalte;

  final String vmlPfad;

  /// Die Eigenschaften für neuere Excel-Versionen — null in alten Mappen.
  final String? ctrlPropPfad;

  final bool angehakt;
}

/// Eine Zelle mit ihrem Text.
class Zelle {
  const Zelle({
    required this.ref,
    required this.zeile,
    required this.spalte,
    required this.text,
  });

  final String ref;
  final int zeile;
  final int spalte;

  /// Der angezeigte Text — bei Zahlen die Zahl, leer bei leeren Zellen.
  final String text;
}

String xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(
      RegExp('&#(x?)([0-9A-Fa-f]+);'),
      (m) => String.fromCharCode(
        int.parse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16),
      ),
    )
    .replaceAll('&amp;', '&');

String xmlEscape(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Ein <t>-Element: Inhalt in Gruppe 1 (leer bei <t/>).
final RegExp kTextElement =
    RegExp(r'<t(?:\s[^>]*)?>(.*?)</t>|<t(?:\s[^>]*)?/>', dotAll: true);

/// Der Text eines <si>- oder <is>-Inhalts: alle <t> hintereinander.
String textAusBlock(String inhalt) =>
    [for (final m in kTextElement.allMatches(inhalt)) xmlUnescape(m[1] ?? '')]
        .join();

final RegExp _si = RegExp(r'<si>(.*?)</si>|<si/>', dotAll: true);
final RegExp _zelleXml =
    RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true);
final RegExp _attrR = RegExp(r'\br="([^"]+)"');
final RegExp _attrT = RegExp(r'\bt="([^"]+)"');
final RegExp _wert = RegExp(r'<v>(.*?)</v>', dotAll: true);
final RegExp _is = RegExp(r'<is>(.*?)</is>', dotAll: true);

/// Die Mappe: alle Dateien des ZIP; Texte werden bei Bedarf gelesen und
/// geändert, beim Packen bleibt die Reihenfolge.
class XlsxMappe {
  XlsxMappe._(this._dateien, this._reihenfolge);

  /// Öffnet [bytes]. Wirft [FormatException], wenn es keine Excel-Mappe
  /// ist.
  factory XlsxMappe.lesen(Uint8List bytes) {
    final istZip = bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4b;
    if (!istZip) {
      throw const FormatException(
        'Die Vorlage ist keine Excel-Mappe (.xlsx).',
      );
    }
    final Archive archiv;
    try {
      archiv = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException(
        'Die Vorlage ließ sich nicht öffnen: ${fehlerText(e)}',
      );
    }
    if (archiv.findFile('xl/workbook.xml') == null) {
      throw const FormatException(
        'Die Vorlage ist keine Excel-Mappe (.xlsx).',
      );
    }
    final dateien = <String, Uint8List>{};
    final reihenfolge = <String>[];
    for (final d in archiv.files) {
      if (!d.isFile) continue;
      final inhalt = d.content;
      if (inhalt is! List<int>) continue;
      dateien[d.name] = Uint8List.fromList(inhalt);
      reihenfolge.add(d.name);
    }
    return XlsxMappe._(dateien, reihenfolge);
  }

  final Map<String, Uint8List> _dateien;
  final List<String> _reihenfolge;
  final Map<String, String> _texte = {};
  List<String>? _geteilt;

  bool hat(String pfad) => _dateien.containsKey(pfad);

  /// Der Inhalt von [pfad] als Text — null, wenn es die Datei nicht gibt.
  String? text(String pfad) {
    final schon = _texte[pfad];
    if (schon != null) return schon;
    final bytes = _dateien[pfad];
    if (bytes == null) return null;
    return _texte[pfad] = utf8.decode(bytes, allowMalformed: true);
  }

  /// Ersetzt den Inhalt von [pfad].
  void schreibe(String pfad, String text) {
    if (!_dateien.containsKey(pfad)) _reihenfolge.add(pfad);
    _texte[pfad] = text;
    _dateien[pfad] = Uint8List.fromList(utf8.encode(text));
  }

  /// Die Mappe wieder als .xlsx.
  Uint8List packen() {
    final neu = Archive();
    for (final name in _reihenfolge) {
      final inhalt = _dateien[name];
      if (inhalt == null) continue;
      neu.addFile(ArchiveFile(name, inhalt.length, inhalt));
    }
    final gepackt = ZipEncoder().encode(neu);
    if (gepackt == null) {
      throw const FormatException('Die Mappe ließ sich nicht packen.');
    }
    return Uint8List.fromList(gepackt);
  }

  /// Die Beziehungen eines Teils: ID → Pfad in der Mappe.
  Map<String, String> beziehungen(String pfad) {
    final ordner = pfad.contains('/')
        ? pfad.substring(0, pfad.lastIndexOf('/'))
        : '';
    final datei = pfad.substring(pfad.lastIndexOf('/') + 1);
    final rels = text('${ordner.isEmpty ? '' : '$ordner/'}_rels/$datei.rels');
    if (rels == null) return const {};
    final ergebnis = <String, String>{};
    for (final m
        in RegExp(r'<Relationship\b([^>]*)/?>').allMatches(rels)) {
      final attr = m[1]!;
      final id = RegExp(r'\bId="([^"]+)"').firstMatch(attr)?[1];
      final ziel = RegExp(r'\bTarget="([^"]+)"').firstMatch(attr)?[1];
      if (id == null || ziel == null) continue;
      ergebnis[id] = _aufloesen(ordner, xmlUnescape(ziel));
    }
    return ergebnis;
  }

  static String _aufloesen(String ordner, String ziel) {
    if (ziel.startsWith('/')) return ziel.substring(1);
    final teile = [
      if (ordner.isNotEmpty) ...ordner.split('/'),
      ...ziel.split('/'),
    ];
    final weg = <String>[];
    for (final t in teile) {
      if (t == '..') {
        if (weg.isNotEmpty) weg.removeLast();
      } else if (t != '.' && t.isNotEmpty) {
        weg.add(t);
      }
    }
    return weg.join('/');
  }

  /// Die Blätter in der Reihenfolge der Mappe.
  List<String> get blattPfade {
    final mappe = text('xl/workbook.xml') ?? '';
    final rels = beziehungen('xl/workbook.xml');
    final pfade = <String>[];
    for (final m in RegExp(r'<sheet\b([^>]*)/?>').allMatches(mappe)) {
      final id = RegExp(r'\br:id="([^"]+)"').firstMatch(m[1]!)?[1];
      final pfad = id == null ? null : rels[id];
      if (pfad != null && hat(pfad)) pfade.add(pfad);
    }
    if (pfade.isNotEmpty) return pfade;
    return [
      for (final name in _reihenfolge)
        if (name.startsWith('xl/worksheets/') &&
            name.endsWith('.xml') &&
            !name.contains('/_rels/'))
          name,
    ];
  }

  /// Die geteilten Texte, roh: der Inhalt jedes <si>.
  List<String> get geteilteRoh => _geteilt ??= [
        for (final m in _si.allMatches(text('xl/sharedStrings.xml') ?? ''))
          m[1] ?? '',
      ];

  /// Der Text des geteilten Texts [index] — leer, wenn es ihn nicht gibt.
  String geteilterText(int index) {
    final roh = geteilteRoh;
    return index >= 0 && index < roh.length ? textAusBlock(roh[index]) : '';
  }
}

/// Ein Blatt der Mappe, gelesen: Zellen, verbundene Bereiche und
/// Kontrollkästchen.
class XlsxBlatt {
  XlsxBlatt(this.mappe, this.pfad) {
    final xml = mappe.text(pfad) ?? '';
    _zellenLesen(xml);
    for (final m in RegExp(r'<mergeCell\b[^>]*\bref="([^"]+)"').allMatches(xml)) {
      final b = Bereich.aus(m[1]!);
      if (b != null) bereiche.add(b);
    }
    _kaestchenLesen(xml);
  }

  final XlsxMappe mappe;
  final String pfad;
  final List<Zelle> zellen = [];
  final List<Bereich> bereiche = [];
  final List<Kaestchen> kaestchen = [];
  final Map<String, Zelle> _nachOrt = {};

  void _zellenLesen(String xml) {
    for (final m in _zelleXml.allMatches(xml)) {
      final attr = m[1]!;
      final ref = _attrR.firstMatch(attr)?[1];
      final ort = ref == null ? null : zellortAus(ref);
      if (ref == null || ort == null) continue;
      final typ = _attrT.firstMatch(attr)?[1];
      final innen = m[2] ?? '';
      final v = _wert.firstMatch(innen)?[1];
      String text;
      if (typ == 's') {
        text = mappe.geteilterText(int.tryParse(v?.trim() ?? '') ?? -1);
      } else if (typ == 'inlineStr') {
        text = textAusBlock(_is.firstMatch(innen)?[1] ?? '');
      } else {
        text = v == null ? '' : xmlUnescape(v);
      }
      final z = Zelle(
        ref: ref,
        zeile: ort.zeile,
        spalte: ort.spalte,
        text: text,
      );
      zellen.add(z);
      _nachOrt['${ort.zeile}:${ort.spalte}'] = z;
    }
  }

  void _kaestchenLesen(String xml) {
    final rels = mappe.beziehungen(pfad);
    final vmlId =
        RegExp(r'<legacyDrawing\b[^>]*\br:id="([^"]+)"').firstMatch(xml)?[1];
    final vmlPfad = vmlId == null ? null : rels[vmlId];
    if (vmlPfad == null) return;
    final vml = mappe.text(vmlPfad);
    if (vml == null) return;

    // Neuere Mappen: je Kästchen eine Datei mit seinen Eigenschaften.
    final props = <int, String>{};
    for (final m in RegExp(r'<control\b([^>]*)>').allMatches(xml)) {
      final nr = RegExp(r'\bshapeId="(\d+)"').firstMatch(m[1]!)?[1];
      final id = RegExp(r'\br:id="([^"]+)"').firstMatch(m[1]!)?[1];
      final ziel = id == null ? null : rels[id];
      if (nr != null && ziel != null) props[int.parse(nr)] = ziel;
    }

    for (final m in kVmlForm.allMatches(vml)) {
      final kopf = m[1]!;
      final inhalt = m[2]!;
      if (!RegExp(r'ObjectType="Checkbox"', caseSensitive: false)
          .hasMatch(inhalt)) {
        continue;
      }
      final nr = vmlFormNummer(kopf);
      final anker = RegExp(r'<x:Anchor>\s*([^<]*)</x:Anchor>').firstMatch(inhalt);
      if (nr == null || anker == null) continue;
      final zahlen = [
        for (final t in anker[1]!.split(',')) int.tryParse(t.trim()) ?? 0,
      ];
      if (zahlen.length < 4) continue;
      final haken = RegExp(r'<x:Checked>\s*(\d+)\s*</x:Checked>')
          .firstMatch(inhalt);
      kaestchen.add(
        Kaestchen(
          nummer: nr,
          spalte: zahlen[0],
          zeile: zahlen[2],
          vmlPfad: vmlPfad,
          ctrlPropPfad: props[nr],
          angehakt: haken != null && haken[1] != '0',
        ),
      );
    }
  }

  /// Die Zelle an (zeile, spalte) — null, wenn das Blatt sie nicht nennt.
  Zelle? zelle(int zeile, int spalte) => _nachOrt['$zeile:$spalte'];

  /// Der verbundene Bereich um (zeile, spalte) — sonst die Zelle allein.
  Bereich bereichVon(int zeile, int spalte) {
    for (final b in bereiche) {
      if (b.enthaelt(zeile, spalte)) return b;
    }
    return Bereich.zelle(zeile, spalte);
  }

  /// Die Kontrollkästchen, deren linke obere Ecke in [b] liegt.
  List<Kaestchen> kaestchenIn(Bereich b) => [
        for (final k in kaestchen)
          if (b.enthaelt(k.zeile, k.spalte)) k,
      ];
}

/// Eine Form der VML: Kopf (Attribute) in Gruppe 1, Inhalt in Gruppe 2.
final RegExp kVmlForm =
    RegExp(r'<v:shape\b([^>]*)>(.*?)</v:shape>', dotAll: true);

/// Die Nummer einer VML-Form aus ihrem Kopf: „_x0000_s1231" → 1231.
int? vmlFormNummer(String kopf) {
  final m = RegExp(r'(?:\bid|o:spid)="_x0000_s(\d+)"').firstMatch(kopf);
  return m == null ? null : int.parse(m[1]!);
}

/// Setzt oder nimmt den Haken des Kästchens [nummer] in der VML — an
/// derselben Stelle wie Excel: vor `<x:NoThreeD/>`, sonst am Ende.
String vmlKaestchenSetzen(String vml, int nummer, {required bool an}) =>
    vml.replaceAllMapped(kVmlForm, (m) {
      if (vmlFormNummer(m[1]!) != nummer) return m[0]!;
      var inhalt = m[2]!.replaceAll(
        RegExp(r'\s*<x:Checked>[^<]*</x:Checked>'),
        '',
      );
      if (an) {
        inhalt = inhalt.contains('<x:NoThreeD/>')
            ? inhalt.replaceFirst(
                '<x:NoThreeD/>',
                '<x:Checked>1</x:Checked><x:NoThreeD/>',
              )
            : inhalt.replaceFirst(
                '</x:ClientData>',
                '<x:Checked>1</x:Checked></x:ClientData>',
              );
      }
      return '<v:shape${m[1]}>$inhalt</v:shape>';
    });

/// Setzt oder nimmt den Haken in den Eigenschaften eines Kästchens — wie
/// Excel direkt hinter `objectType`.
String ctrlPropSetzen(String xml, {required bool an}) =>
    xml.replaceFirstMapped(RegExp(r'<formControlPr\b([^>]*?)(/?)>'), (m) {
      var attr = m[1]!.replaceAll(RegExp(r'\s+checked="[^"]*"'), '');
      if (an) {
        final typ = RegExp(r'\sobjectType="[^"]*"').firstMatch(attr);
        attr = typ == null
            ? '$attr checked="Checked"'
            : '${attr.substring(0, typ.end)} checked="Checked"'
                '${attr.substring(typ.end)}';
      }
      return '<formControlPr$attr${m[2]}>';
    });

/// Die Zelle [ref] ohne Wert — ihr Format bleibt.
String zelleLeeren(String blattXml, String ref) =>
    blattXml.replaceFirstMapped(_zelleMit(ref), (m) {
      final attr = m[1]!.replaceAll(RegExp(r'\s+t="[^"]*"'), '');
      return '<c$attr/>';
    });

RegExp _zelleMit(String ref) => RegExp(
      '<c\\b([^>]*?\\br="${RegExp.escape(ref)}"[^>]*?)(?:/>|>(.*?)</c>)',
      dotAll: true,
    );

/// Schreibt [text] als Text direkt in die Zelle [ref] — ihr Format
/// bleibt. Fehlt die Zelle oder ihre Zeile, entsteht sie.
String zelleSetzen(String blattXml, String ref, String text) {
  final inhalt = '<is><t xml:space="preserve">${xmlEscape(text)}</t></is>';
  final muster = _zelleMit(ref);
  if (muster.hasMatch(blattXml)) {
    return blattXml.replaceFirstMapped(muster, (m) {
      final attr = m[1]!.replaceAll(RegExp(r'\s+t="[^"]*"'), '');
      return '<c$attr t="inlineStr">$inhalt</c>';
    });
  }
  final ort = zellortAus(ref)!;
  final neueZelle = '<c r="$ref" t="inlineStr">$inhalt</c>';
  final zeile = RegExp(
    '<row\\b([^>]*?\\br="${ort.zeile + 1}"[^>]*?)(?:/>|>(.*?)</row>)',
    dotAll: true,
  );
  if (zeile.hasMatch(blattXml)) {
    return blattXml.replaceFirstMapped(zeile, (m) {
      final attr = m[1]!.replaceAll(RegExp(r'\s+spans="[^"]*"'), '');
      final zellen = m[2] ?? '';
      // An die richtige Stelle: vor die erste Zelle weiter rechts.
      final teile = _zelleXml.allMatches(zellen).toList();
      for (final t in teile) {
        final r = _attrR.firstMatch(t[1]!)?[1];
        final o = r == null ? null : zellortAus(r);
        if (o != null && o.spalte > ort.spalte) {
          return '<row$attr>${zellen.substring(0, t.start)}$neueZelle'
              '${zellen.substring(t.start)}</row>';
        }
      }
      return '<row$attr>$zellen$neueZelle</row>';
    });
  }
  // Die Zeile fehlt: vor die erste Zeile weiter unten.
  final neueZeile = '<row r="${ort.zeile + 1}">$neueZelle</row>';
  for (final m in RegExp(r'<row\b[^>]*?\br="(\d+)"').allMatches(blattXml)) {
    if (int.parse(m[1]!) > ort.zeile + 1) {
      return blattXml.replaceRange(m.start, m.start, neueZeile);
    }
  }
  if (blattXml.contains('<sheetData/>')) {
    return blattXml.replaceFirst(
      '<sheetData/>',
      '<sheetData>$neueZeile</sheetData>',
    );
  }
  return blattXml.replaceFirst('</sheetData>', '$neueZeile</sheetData>');
}

/// Die Elemente der Kopf- und Fußzeilen.
final RegExp kKopfFuss = RegExp(
  r'<(oddHeader|oddFooter|evenHeader|evenFooter|firstHeader|firstFooter)>'
  r'(.*?)</\1>',
  dotAll: true,
);
