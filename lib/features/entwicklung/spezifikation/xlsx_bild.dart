import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'xlsx_blatt.dart';

// Ein Foto in eine Excel-Mappe setzen — das Produktfoto der Spezifikation:
// in den verbundenen Bereich der Zelle mit {{produktbild}}, eingepasst und
// mittig, das Seitenverhältnis bleibt.
//
// Vorher wird das Foto aufbereitet: so gedreht, wie die Kamera es in den
// EXIF-Daten vermerkt, auf höchstens [kBildKante] Pixel verkleinert, als
// JPEG — PNG nur, wenn es durchsichtige Stellen hat — und ohne EXIF-Daten:
// Aufnahmeort und Kamera gehören nicht in eine verschickte Spezifikation.
//
// In der Mappe entstehen die Bilddatei unter xl/media, ihre Beziehung in
// der Zeichnung des Blatts (eine neue Zeichnung, wenn das Blatt keine hat)
// und ein Anker mit fester Größe. Excel misst Spalten in Zeichen und
// Zeilen in Punkt; zum Einpassen rechnet die App mit der Standardschrift
// Calibri 11. Weicht die Schrift ab, sitzt das Bild etwas anders —
// verzerrt wird es nie.

/// Die längste Seite eines Fotos in der Mappe — genug für den Druck im
/// Feld neben der Sensorik.
const int kBildKante = 1200;

/// Ein aufbereitetes Bild für die Mappe.
class XlsxBild {
  const XlsxBild({
    required this.bytes,
    required this.endung,
    required this.breite,
    required this.hoehe,
  });

  final Uint8List bytes;

  /// „jpeg" oder „png".
  final String endung;

  /// Größe in Pixeln.
  final int breite;
  final int hoehe;

  String get mimeTyp => endung == 'png' ? 'image/png' : 'image/jpeg';
}

/// Bereitet ein Foto für die Mappe auf — null, wenn es sich nicht lesen
/// lässt. Das dauert bei großen Fotos einen Moment; die App ruft es im
/// Hintergrund auf.
XlsxBild? bildFuerMappe(Uint8List bytes, {int kante = kBildKante}) {
  img.Image? roh;
  try {
    roh = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (roh == null || roh.width == 0 || roh.height == 0) return null;
  var bild = roh;
  final ifd = bild.exif.imageIfd;
  if (ifd.hasOrientation && ifd.orientation != 1) {
    bild = img.bakeOrientation(bild);
  }
  // Farbpaletten (GIF, PNG mit 256 Farben) einmal in echte Farben.
  if (bild.hasPalette) bild = bild.convert(numChannels: bild.numChannels);
  if (math.max(bild.width, bild.height) > kante) {
    bild = bild.width >= bild.height
        ? img.copyResize(
            bild,
            width: kante,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            bild,
            height: kante,
            interpolation: img.Interpolation.average,
          );
  }
  // Ohne EXIF: kein Aufnahmeort, keine Kamera — und gedreht ist es schon.
  bild.exif = img.ExifData();
  final png = _durchsichtig(bild);
  return XlsxBild(
    bytes: png ? img.encodePng(bild) : img.encodeJpg(bild, quality: 85),
    endung: png ? 'png' : 'jpeg',
    breite: bild.width,
    hoehe: bild.height,
  );
}

/// Hat das Bild durchsichtige Stellen?
bool _durchsichtig(img.Image b) {
  if (!b.hasAlpha) return false;
  final voll = b.maxChannelValue;
  for (final p in b) {
    if (p.a < voll) return true;
  }
  return false;
}

/// Wo ein Bild im Bereich sitzt: Spalte und Zeile (ab 0) der linken oberen
/// Ecke mit Versatz darin und die Größe — Versatz und Größe in EMU (9525
/// je Pixel).
typedef BildAnker = ({
  int spalte,
  int spaltenVersatz,
  int zeile,
  int zeilenVersatz,
  int cx,
  int cy,
});

/// Abstand des Bilds zum Rand des Bereichs, in Pixeln.
const double _rand = 4;

/// Die Maße eines Blatts in Pixeln (96 dpi), soweit es sie nennt.
class _Masse {
  _Masse(String xml) {
    final format =
        RegExp(r'<sheetFormatPr\b([^>]*?)/?>').firstMatch(xml)?[1] ?? '';
    final breite = _zahl(format, 'defaultColWidth');
    final basis = _zahl(format, 'baseColWidth') ?? 8;
    _standardSpalte = breite != null ? _px(breite) : basis * _mdw + 5;
    _standardZeile = (_zahl(format, 'defaultRowHeight') ?? 15) * 96 / 72;
    for (final m in RegExp(r'<col\b([^>]*?)/?>').allMatches(xml)) {
      final a = m[1]!;
      final von = _zahl(a, 'min')?.toInt();
      final bis = _zahl(a, 'max')?.toInt();
      if (von == null || bis == null) continue;
      final w = _zahl(a, 'width');
      _spalten.add(
        (
          von: von - 1,
          bis: bis - 1,
          px: _versteckt(a) ? 0 : (w == null ? _standardSpalte : _px(w)),
        ),
      );
    }
    for (final m in RegExp(r'<row\b([^>]*?)/?>').allMatches(xml)) {
      final a = m[1]!;
      final r = _zahl(a, 'r')?.toInt();
      if (r == null) continue;
      final ht = _zahl(a, 'ht');
      if (_versteckt(a)) {
        _zeilen[r - 1] = 0;
      } else if (ht != null) {
        _zeilen[r - 1] = ht * 96 / 72;
      }
    }
  }

  /// Die breiteste Ziffer der Standardschrift (Calibri 11) in Pixeln.
  static const int _mdw = 7;

  late final double _standardSpalte;
  late final double _standardZeile;
  final List<({int von, int bis, double px})> _spalten = [];
  final Map<int, double> _zeilen = {};

  static double? _zahl(String attr, String name) {
    final m = RegExp('\\b$name="([^"]+)"').firstMatch(attr);
    return m == null ? null : double.tryParse(m[1]!);
  }

  static bool _versteckt(String attr) =>
      RegExp(r'\bhidden="(1|true)"').hasMatch(attr);

  /// Eine Spaltenbreite in Zeichen als Pixel — wie Excel rechnet.
  static double _px(double breite) =>
      ((256 * breite + (128 / _mdw).truncate()) / 256 * _mdw)
          .truncateToDouble();

  double spalte(int s) {
    for (final c in _spalten) {
      if (s >= c.von && s <= c.bis) return c.px;
    }
    return _standardSpalte;
  }

  double zeile(int z) => _zeilen[z] ?? _standardZeile;
}

/// Wo ein Bild von [breite] × [hoehe] Pixeln im Bereich [b] des Blatts mit
/// dem XML [blattXml] sitzt: so groß wie möglich, mit etwas Rand, mittig.
BildAnker bildAnker(String blattXml, Bereich b, int breite, int hoehe) {
  final masse = _Masse(blattXml);
  final spalten = [for (var s = b.s1; s <= b.s2; s++) masse.spalte(s)];
  final zeilen = [for (var z = b.z1; z <= b.z2; z++) masse.zeile(z)];
  final w = spalten.fold<double>(0, (a, x) => a + x);
  final h = zeilen.fold<double>(0, (a, x) => a + x);
  final faktor = math.min(
    math.max(1.0, w - 2 * _rand) / math.max(1, breite),
    math.max(1.0, h - 2 * _rand) / math.max(1, hoehe),
  );
  final bw = breite * faktor;
  final bh = hoehe * faktor;
  var x = (w - bw) / 2;
  var y = (h - bh) / 2;
  var s = 0;
  while (s < spalten.length - 1 && x >= spalten[s]) {
    x -= spalten[s];
    s++;
  }
  var z = 0;
  while (z < zeilen.length - 1 && y >= zeilen[z]) {
    y -= zeilen[z];
    z++;
  }
  int emu(double px) => (px * 9525).round();
  return (
    spalte: b.s1 + s,
    spaltenVersatz: emu(x),
    zeile: b.z1 + z,
    zeilenVersatz: emu(y),
    cx: emu(bw),
    cy: emu(bh),
  );
}

const String _nsR =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _nsXdr =
    'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing';
const String _nsA = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _nsRels =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String _ctZeichnung =
    'application/vnd.openxmlformats-officedocument.drawing+xml';
const String _ctPfad = '[Content_Types].xml';
const String _xmlKopf =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

/// Setzt [bild] eingepasst und mittig in den Bereich [bereich] des Blatts
/// [blattPfad], dessen XML gerade [blattXml] ist. Gibt das XML des Blatts
/// zurück — mit Verweis auf eine neue Zeichnung, wenn es noch keine hatte;
/// null, wenn sich seine Zeichnung nicht ergänzen ließ (dann bleibt die
/// Mappe, wie sie war).
String? bildEinsetzen(
  XlsxMappe mappe, {
  required String blattPfad,
  required String blattXml,
  required Bereich bereich,
  required XlsxBild bild,
  String name = 'Produktfoto',
}) {
  var xml = blattXml;
  final rid = RegExp(r'<drawing\b[^>]*\br:id="([^"]+)"').firstMatch(xml)?[1];
  var zeichnung = rid == null ? null : mappe.beziehungen(blattPfad)[rid];
  if (rid != null && (zeichnung == null || !mappe.hat(zeichnung))) {
    // Der Verweis führt ins Leere — lieber nichts anfassen.
    return null;
  }
  if (zeichnung != null && !(mappe.text(zeichnung) ?? '').contains(
        '</xdr:wsDr>',
      )) {
    return null;
  }
  if (zeichnung == null) {
    zeichnung = _freierPfad(mappe, 'xl/drawings/drawing', '.xml');
    mappe.schreibe(
      zeichnung,
      '$_xmlKopf<xdr:wsDr xmlns:xdr="$_nsXdr" xmlns:a="$_nsA"></xdr:wsDr>',
    );
    _inhaltstypTeil(mappe, zeichnung, _ctZeichnung);
    final neu = _beziehung(mappe, blattPfad, '$_nsR/drawing', zeichnung);
    xml = _zeichnungImBlatt(xml, neu);
  }

  final medium = _freierPfad(mappe, 'xl/media/image', '.${bild.endung}');
  mappe.schreibeBytes(medium, bild.bytes);
  _inhaltstypEndung(mappe, bild.endung, bild.mimeTyp);
  final bildId = _beziehung(mappe, zeichnung, '$_nsR/image', medium);

  final zxml = mappe.text(zeichnung)!;
  final a = bildAnker(xml, bereich, bild.breite, bild.hoehe);
  final nr = [
        for (final m
            in RegExp(r'<xdr:cNvPr\b[^>]*?\bid="(\d+)"').allMatches(zxml))
          int.parse(m[1]!),
      ].fold<int>(1, math.max) +
      1;
  final anker = '<xdr:oneCellAnchor>'
      '<xdr:from><xdr:col>${a.spalte}</xdr:col>'
      '<xdr:colOff>${a.spaltenVersatz}</xdr:colOff>'
      '<xdr:row>${a.zeile}</xdr:row>'
      '<xdr:rowOff>${a.zeilenVersatz}</xdr:rowOff></xdr:from>'
      '<xdr:ext cx="${a.cx}" cy="${a.cy}"/>'
      '<xdr:pic xmlns:a="$_nsA">'
      '<xdr:nvPicPr><xdr:cNvPr id="$nr" name="${xmlEscape(name)}"/>'
      '<xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr>'
      '</xdr:nvPicPr>'
      '<xdr:blipFill><a:blip xmlns:r="$_nsR" r:embed="$bildId"/>'
      '<a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
      '<xdr:spPr><a:xfrm><a:off x="0" y="0"/>'
      '<a:ext cx="${a.cx}" cy="${a.cy}"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>'
      '</xdr:pic><xdr:clientData/></xdr:oneCellAnchor>';
  mappe.schreibe(
    zeichnung,
    zxml.replaceFirst('</xdr:wsDr>', '$anker</xdr:wsDr>'),
  );
  return xml;
}

/// Der erste freie Pfad „[anfang]1[ende]", „[anfang]2[ende]" …
String _freierPfad(XlsxMappe mappe, String anfang, String ende) {
  var n = 1;
  while (mappe.hat('$anfang$n$ende')) {
    n++;
  }
  return '$anfang$n$ende';
}

/// Wo die Beziehungen eines Teils stehen: „xl/drawings/drawing1.xml" →
/// „xl/drawings/_rels/drawing1.xml.rels".
String _relsPfad(String teil) {
  final i = teil.lastIndexOf('/');
  return i < 0
      ? '_rels/$teil.rels'
      : '${teil.substring(0, i)}/_rels/${teil.substring(i + 1)}.rels';
}

/// [nach] relativ zum Ordner von [von]: „../media/image1.jpeg".
String relativerPfad(String von, String nach) {
  final ordner = von.contains('/')
      ? von.substring(0, von.lastIndexOf('/')).split('/')
      : <String>[];
  final ziel = nach.split('/');
  var gleich = 0;
  while (gleich < ordner.length &&
      gleich < ziel.length - 1 &&
      ordner[gleich] == ziel[gleich]) {
    gleich++;
  }
  return [
    for (var i = gleich; i < ordner.length; i++) '..',
    ...ziel.sublist(gleich),
  ].join('/');
}

/// Trägt eine Beziehung von [teil] zu [ziel] ein und gibt ihre ID zurück.
String _beziehung(XlsxMappe mappe, String teil, String typ, String ziel) {
  final pfad = _relsPfad(teil);
  var rels = mappe.text(pfad) ??
      '$_xmlKopf<Relationships xmlns="$_nsRels"></Relationships>';
  if (!rels.contains('</Relationships>')) {
    rels = rels.replaceFirstMapped(
      RegExp(r'<Relationships\b([^>]*?)/>'),
      (m) => '<Relationships${m[1]}></Relationships>',
    );
  }
  final vergeben = {
    for (final m in RegExp(r'\bId="([^"]+)"').allMatches(rels)) m[1]!,
  };
  var n = 1;
  while (vergeben.contains('rId$n')) {
    n++;
  }
  final id = 'rId$n';
  mappe.schreibe(
    pfad,
    rels.replaceFirst(
      '</Relationships>',
      '<Relationship Id="$id" Type="$typ" '
          'Target="${relativerPfad(teil, ziel)}"/></Relationships>',
    ),
  );
  return id;
}

/// Meldet die Endung eines Bilds bei den Inhaltstypen an, wenn sie fehlt.
void _inhaltstypEndung(XlsxMappe mappe, String endung, String typ) {
  final ct = mappe.text(_ctPfad);
  if (ct == null) return;
  final schon = RegExp(
    '<Default\\b[^>]*\\bExtension="$endung"',
    caseSensitive: false,
  ).hasMatch(ct);
  if (schon) return;
  mappe.schreibe(
    _ctPfad,
    ct.replaceFirstMapped(
      RegExp(r'<Types\b[^>]*>'),
      (m) => '${m[0]}<Default Extension="$endung" ContentType="$typ"/>',
    ),
  );
}

/// Meldet einen neuen Teil der Mappe bei den Inhaltstypen an.
void _inhaltstypTeil(XlsxMappe mappe, String teil, String typ) {
  final ct = mappe.text(_ctPfad);
  if (ct == null || ct.contains('PartName="/$teil"')) return;
  mappe.schreibe(
    _ctPfad,
    ct.replaceFirst(
      '</Types>',
      '<Override PartName="/$teil" ContentType="$typ"/></Types>',
    ),
  );
}

/// Elemente, vor denen <drawing> im Blatt stehen muss — keins davon kommt
/// verschachtelt vor.
const List<String> _nachZeichnung = [
  '<legacyDrawing',
  '<drawingHF',
  '<picture',
  '<oleObjects',
  '<controls',
  '<webPublishItems',
  '<tableParts',
];

/// Hängt die Zeichnung [rid] an der richtigen Stelle ins Blatt.
String _zeichnungImBlatt(String xml, String rid) {
  var neu = xml;
  if (!RegExp(r'<worksheet\b[^>]*\bxmlns:r=').hasMatch(neu)) {
    neu = neu.replaceFirst(
      RegExp(r'<worksheet\b'),
      '<worksheet xmlns:r="$_nsR"',
    );
  }
  final daten = neu.indexOf('</sheetData>');
  final ab = daten < 0 ? 0 : daten;
  int? stelle;
  for (final tag in _nachZeichnung) {
    final i = neu.indexOf(tag, ab);
    if (i >= 0 && (stelle == null || i < stelle)) stelle = i;
  }
  final ext = _oberstesExtLst(neu);
  if (ext != null && ext >= ab && (stelle == null || ext < stelle)) {
    stelle = ext;
  }
  stelle ??= neu.lastIndexOf('</worksheet>');
  if (stelle < 0) return neu;
  return neu.replaceRange(stelle, stelle, '<drawing r:id="$rid"/>');
}

/// Wo die Erweiterungen des Blatts selbst beginnen — das letzte Element
/// vor </worksheet>. Null, wenn es keine gibt. Verschachtelte extLst (etwa
/// in einer bedingten Formatierung) zählen nicht.
int? _oberstesExtLst(String xml) {
  if (!RegExp(r'</extLst>\s*</worksheet>\s*$').hasMatch(xml)) return null;
  int? start;
  var tiefe = 0;
  for (final m in RegExp(r'<extLst\b[^>]*?(/?)>|</extLst>').allMatches(xml)) {
    if (m[0]!.startsWith('</')) {
      tiefe--;
      continue;
    }
    if (m[1] == '/') continue;
    if (tiefe == 0) start = m.start;
    tiefe++;
  }
  return start;
}
