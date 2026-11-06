import 'dart:typed_data';

import 'xlsx_blatt.dart';

// Das Logo aus der Kopfzeile einer Excel-Vorlage — für den Projektbericht,
// der dasselbe Logo trägt wie die Spezifikation.
//
// Excel setzt ein Bild mit „&G" in die Kopfzeile. Das Bild selbst steht in
// einer VML-Zeichnung des Blatts (<legacyDrawingHF>), je Stelle eine Form:
// „LH", „CH" und „RH" für links, Mitte und rechts oben, „LF", „CF", „RF"
// unten. In ihrem Stil stehen Breite und Höhe, wie Excel das Bild druckt.

/// Ein Bild aus der Kopfzeile: der Inhalt und die Größe, mit der Excel es
/// druckt.
class KopfLogo {
  const KopfLogo({
    required this.bytes,
    required this.breite,
    required this.hoehe,
  });

  /// JPEG oder PNG.
  final Uint8List bytes;

  /// Breite und Höhe in Punkt (1/72 Zoll) — 0, wenn die Vorlage sie nicht
  /// nennt.
  final double breite;
  final double hoehe;
}

/// Die Stellen oben, rechts zuerst — dort steht ein Logo meist.
const List<String> _stellen = ['RH', 'LH', 'CH'];

final RegExp _form = RegExp(
  r'<v:shape\b([^>]*)>(.*?)</v:shape>',
  dotAll: true,
);

/// Das Logo aus der Kopfzeile von [xlsx]: im ersten Blatt mit einem Bild
/// oben — rechts vor links vor der Mitte. null ohne ein solches Bild oder
/// wenn es weder JPEG noch PNG ist (EMF und WMF kann das PDF nicht
/// zeigen). Wirft [FormatException], wenn [xlsx] keine Excel-Mappe ist.
KopfLogo? kopfzeilenLogo(Uint8List xlsx) {
  final mappe = XlsxMappe.lesen(xlsx);
  for (final blatt in mappe.blattPfade) {
    final xml = mappe.text(blatt) ?? '';
    final rid = RegExp(
      r'<legacyDrawingHF\b[^>]*\br:id="([^"]+)"',
    ).firstMatch(xml)?[1];
    final vmlPfad = rid == null ? null : mappe.beziehungen(blatt)[rid];
    final vml = vmlPfad == null ? null : mappe.text(vmlPfad);
    if (vmlPfad == null || vml == null) continue;
    final formen = <String, (String, String)>{
      for (final m in _form.allMatches(vml))
        if (_attribut(m[1]!, 'id') case final id?)
          id.trim().toUpperCase(): (m[1]!, m[2]!),
    };
    final bilder = mappe.beziehungen(vmlPfad);
    for (final stelle in _stellen) {
      final form = formen[stelle];
      if (form == null) continue;
      final (kopf, inhalt) = form;
      final daten = RegExp(r'<v:imagedata\b([^>]*)/?>').firstMatch(inhalt)?[1];
      final relid = daten == null ? null : _attribut(daten, 'o:relid');
      final pfad = relid == null ? null : bilder[relid];
      final bytes = pfad == null ? null : mappe.bytes(pfad);
      if (bytes == null || !_jpegOderPng(bytes)) continue;
      final stil = _attribut(kopf, 'style') ?? '';
      return KopfLogo(
        bytes: bytes,
        breite: _mass(stil, 'width'),
        hoehe: _mass(stil, 'height'),
      );
    }
  }
  return null;
}

/// Der Wert des Attributs [name] — in doppelten oder einfachen
/// Anführungszeichen, wie VML beides kennt.
String? _attribut(String attribute, String name) {
  final m = RegExp(
    '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')',
  ).firstMatch(attribute);
  return m == null ? null : (m[1] ?? m[2]);
}

/// Eine Länge aus einem VML-Stil in Punkt — 0, wenn sie fehlt oder die
/// Einheit unbekannt ist.
double _mass(String stil, String name) {
  final m = RegExp(
    '(?:^|;)\\s*${RegExp.escape(name)}\\s*:\\s*([0-9]+(?:\\.[0-9]+)?)\\s*'
    '([a-zA-Z]*)',
  ).firstMatch(stil);
  if (m == null) return 0;
  final zahl = double.parse(m[1]!);
  return switch (m[2]!.toLowerCase()) {
    'pt' => zahl,
    'in' => zahl * 72,
    'cm' => zahl * 72 / 2.54,
    'mm' => zahl * 72 / 25.4,
    // Ohne Einheit zählt VML wie CSS in Pixeln (96 je Zoll).
    'px' || '' => zahl * .75,
    _ => 0,
  };
}

/// JPEG (FF D8 FF) oder PNG (89 „PNG").
bool _jpegOderPng(Uint8List b) =>
    (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) ||
    (b.length > 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47);
