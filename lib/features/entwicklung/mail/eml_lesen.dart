import 'dart:convert';
import 'dart:typed_data';

import 'mail.dart';

// Internet-Mails lesen (.eml — RFC 5322 mit MIME): Kopfzeilen mit
// kodierten Wörtern („=?UTF-8?Q?Gr=C3=BC=C3=9Fe?="), verschachtelte Teile
// (Text, HTML, Anhänge), Quoted-Printable und Base64, die Zeichensätze, die
// in Mails vorkommen. Dazu Werkzeuge, die auch die Outlook-Mail braucht:
// HTML zu Text, Datum aus dem Kopf, Zeichensätze nach Codepage.

/// Liest eine Internet-Mail. Wirft [FormatException], wenn [bytes] keine
/// ist.
Mail emlLesen(Uint8List bytes) {
  final teil = _teil(bytes);
  const merkmale = {'from', 'subject', 'date', 'mime-version', 'received'};
  if (!teil.kopf.keys.any(merkmale.contains)) {
    throw const FormatException('Die Datei ist keine E-Mail.');
  }
  final sammlung = _Sammlung();
  _sammeln(teil, sammlung, 0);
  final von = adresseLesen(teil.kopf['from'] ?? teil.kopf['sender'] ?? '');
  return Mail(
    betreff: kopfDekodieren(teil.kopf['subject'] ?? '').trim(),
    vonName: von.name,
    vonAdresse: von.adresse,
    an: adressenText(teil.kopf['to'] ?? ''),
    cc: adressenText(teil.kopf['cc'] ?? ''),
    datum: internetDatum(teil.kopf['date']),
    text: _textAufraeumen(
      sammlung.text ?? (sammlung.html == null ? '' : htmlZuText(sammlung.html!)),
    ),
    anhaenge: sammlung.anhaenge,
  );
}

// ── Kopf und Teile ───────────────────────────────────────────────────

class _Teil {
  _Teil(this.kopf, this.rumpf);

  /// Die Kopfzeilen: Name klein geschrieben, Wert entfaltet — bei
  /// mehrfachen die erste.
  final Map<String, String> kopf;
  final Uint8List rumpf;
}

/// Text aus Bytes: UTF-8, wenn es gültiges UTF-8 ist, sonst Windows-1252.
String _rohText(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return _cp1252(bytes);
  }
}

/// Die Kopfzeilen eines Texts (bis zur ersten Leerzeile oder ganz):
/// Name klein geschrieben, Folgezeilen angehängt.
Map<String, String> kopfzeilenLesen(String text) {
  final kopf = <String, String>{};
  String? name;
  final wert = StringBuffer();
  void fertig() {
    final n = name;
    if (n != null) kopf.putIfAbsent(n, () => wert.toString().trim());
    name = null;
    wert.clear();
  }

  for (final roh in text.split('\n')) {
    final zeile = roh.endsWith('\r') ? roh.substring(0, roh.length - 1) : roh;
    if (zeile.isEmpty) break;
    if (zeile.startsWith(' ') || zeile.startsWith('\t')) {
      if (name != null) wert.write(' ${zeile.trim()}');
      continue;
    }
    fertig();
    final doppelpunkt = zeile.indexOf(':');
    if (doppelpunkt <= 0) continue;
    final n = zeile.substring(0, doppelpunkt).trim().toLowerCase();
    if (n.isEmpty || n.contains(' ')) continue;
    name = n;
    wert.write(zeile.substring(doppelpunkt + 1).trim());
  }
  fertig();
  return kopf;
}

/// Trennt Kopf und Rumpf an der ersten Leerzeile.
_Teil _teil(Uint8List bytes) {
  var kopfEnde = bytes.length;
  var rumpfAb = bytes.length;
  // Ein Teil ohne Kopf beginnt gleich mit der Leerzeile.
  if (bytes.isNotEmpty && bytes[0] == 0x0A) {
    kopfEnde = 0;
    rumpfAb = 1;
  } else if (bytes.length > 1 && bytes[0] == 0x0D && bytes[1] == 0x0A) {
    kopfEnde = 0;
    rumpfAb = 2;
  } else {
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 0x0A) continue;
      if (i + 1 < bytes.length && bytes[i + 1] == 0x0A) {
        kopfEnde = i;
        rumpfAb = i + 2;
        break;
      }
      if (i + 2 < bytes.length &&
          bytes[i + 1] == 0x0D &&
          bytes[i + 2] == 0x0A) {
        kopfEnde = i;
        rumpfAb = i + 3;
        break;
      }
    }
  }
  return _Teil(
    kopfzeilenLesen(_rohText(bytes.sublist(0, kopfEnde))),
    Uint8List.sublistView(bytes, rumpfAb),
  );
}

/// Ein Kopfwert mit Parametern: „text/plain; charset=utf-8".
typedef _Wert = ({String wert, Map<String, String> parameter});

/// Zerlegt [text] an [trenner] — nicht in Anführungszeichen.
List<String> _teilen(String text, String trenner) {
  final teile = <String>[];
  final aktuell = StringBuffer();
  var inAnfuehrung = false;
  var inKlammer = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"' && (i == 0 || text[i - 1] != r'\')) {
      inAnfuehrung = !inAnfuehrung;
    } else if (!inAnfuehrung && c == '<') {
      inKlammer++;
    } else if (!inAnfuehrung && c == '>' && inKlammer > 0) {
      inKlammer--;
    }
    if (!inAnfuehrung && inKlammer == 0 && trenner.contains(c)) {
      teile.add(aktuell.toString());
      aktuell.clear();
    } else {
      aktuell.write(c);
    }
  }
  teile.add(aktuell.toString());
  return teile;
}

String _ohneAnfuehrung(String s) {
  final t = s.trim();
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
    return t.substring(1, t.length - 1).replaceAll(r'\"', '"');
  }
  return t;
}

/// Liest einen Kopfwert mit Parametern — auch nach RFC 2231 kodierte
/// und fortgesetzte („filename*0*=UTF-8''Gr%C3%BC…; filename*1*=…").
_Wert _wertLesen(String? kopfwert) {
  if (kopfwert == null || kopfwert.trim().isEmpty) {
    return (wert: '', parameter: const {});
  }
  final teile = _teilen(kopfwert, ';');
  final roh = <String, String>{};
  for (final t in teile.skip(1)) {
    final gleich = t.indexOf('=');
    if (gleich <= 0) continue;
    roh[t.substring(0, gleich).trim().toLowerCase()] =
        _ohneAnfuehrung(t.substring(gleich + 1));
  }
  // Fortsetzungen und Kodierung zusammensetzen.
  final abschnitte = <String, Map<int, ({String text, bool kodiert})>>{};
  final parameter = <String, String>{};
  final fortsetzung = RegExp(r'^(.+?)\*(\d+)(\*?)$');
  for (final MapEntry(:key, :value) in roh.entries) {
    final m = fortsetzung.firstMatch(key);
    if (m != null) {
      abschnitte.putIfAbsent(m[1]!, () => {})[int.parse(m[2]!)] =
          (text: value, kodiert: m[3] == '*');
    } else if (key.endsWith('*')) {
      abschnitte.putIfAbsent(key.substring(0, key.length - 1), () => {})[0] =
          (text: value, kodiert: true);
    } else {
      parameter[key] = kopfDekodieren(value);
    }
  }
  for (final MapEntry(key: name, value: teileNachNummer)
      in abschnitte.entries) {
    final nummern = teileNachNummer.keys.toList()..sort();
    String? zeichensatz;
    final bytes = <int>[];
    for (final n in nummern) {
      final a = teileNachNummer[n]!;
      var text = a.text;
      if (a.kodiert) {
        if (n == nummern.first) {
          // charset'sprache'wert
          final teil = text.split("'");
          if (teil.length >= 3) {
            zeichensatz = teil[0];
            text = teil.sublist(2).join("'");
          }
        }
        bytes.addAll(_prozentDekodiert(text));
      } else {
        bytes.addAll(latin1.encode(_nurLatin1(text)));
      }
    }
    parameter[name] = zeichensatzDekodieren(bytes, zeichensatz);
  }
  return (wert: teile.first.trim().toLowerCase(), parameter: parameter);
}

String _nurLatin1(String s) =>
    String.fromCharCodes(s.codeUnits.map((c) => c > 0xFF ? 0x3F : c));

List<int> _prozentDekodiert(String s) {
  final bytes = <int>[];
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x25 && i + 2 < s.length) {
      final h = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
      if (h != null) {
        bytes.add(h);
        i += 2;
        continue;
      }
    }
    bytes.add(c > 0xFF ? 0x3F : c);
  }
  return bytes;
}

// ── Inhalte ──────────────────────────────────────────────────────────

class _Sammlung {
  String? text;
  String? html;
  final List<MailAnhang> anhaenge = [];
}

/// Teilt den Rumpf eines mehrteiligen Teils an der [grenze].
List<Uint8List> _mehrteilig(Uint8List rumpf, String grenze) {
  final s = latin1.decode(rumpf);
  final muster = RegExp(
    '(^|\\r?\\n)--${RegExp.escape(grenze)}(--)?[ \\t]*(\\r?\\n|\$)',
  );
  final teile = <Uint8List>[];
  int? anfang;
  for (final m in muster.allMatches(s)) {
    final a = anfang;
    if (a != null && m.start >= a) {
      teile.add(Uint8List.sublistView(rumpf, a, m.start));
    }
    if (m[2] == '--') return teile;
    anfang = m.end;
  }
  // Ohne Abschluss: der Rest gehört zum letzten Teil.
  final a = anfang;
  if (a != null && a < rumpf.length) {
    teile.add(Uint8List.sublistView(rumpf, a));
  }
  return teile;
}

/// Der Rumpf nach der Transportkodierung dekodiert.
Uint8List _dekodiert(_Teil t) {
  switch ((t.kopf['content-transfer-encoding'] ?? '').trim().toLowerCase()) {
    case 'base64':
      return base64Dekodiert(latin1.decode(t.rumpf));
    case 'quoted-printable':
      return quotedPrintableDekodiert(t.rumpf);
    default:
      return t.rumpf;
  }
}

/// Endungen nach Medientyp — für Anhänge ohne Namen.
const Map<String, String> _endungen = {
  'application/pdf': '.pdf',
  'image/png': '.png',
  'image/jpeg': '.jpg',
  'image/gif': '.gif',
  'text/plain': '.txt',
  'text/html': '.html',
  'text/csv': '.csv',
  'message/rfc822': '.eml',
  'application/vnd.ms-excel': '.xls',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
  'application/msword': '.doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      '.docx',
};

void _sammeln(_Teil t, _Sammlung s, int tiefe) {
  if (tiefe > 20) return;
  final typ = _wertLesen(t.kopf['content-type']);
  final art = typ.wert.isEmpty ? 'text/plain' : typ.wert;
  if (art.startsWith('multipart/')) {
    final grenze = typ.parameter['boundary'];
    if (grenze == null || grenze.isEmpty) return;
    for (final u in _mehrteilig(t.rumpf, grenze)) {
      _sammeln(_teil(u), s, tiefe + 1);
    }
    return;
  }
  final verwendung = _wertLesen(t.kopf['content-disposition']);
  final name = (verwendung.parameter['filename'] ?? typ.parameter['name'])
      ?.trim();
  final inhalt = _dekodiert(t);
  final anhang = verwendung.wert == 'attachment';
  final eingebettet = t.kopf.containsKey('content-id') &&
      art.startsWith('image/') &&
      !anhang;
  if (eingebettet) return;

  if (art == 'message/rfc822') {
    var n = name ?? '';
    if (n.isEmpty) {
      String betreff;
      try {
        betreff = emlLesen(inhalt).betreff;
      } on FormatException {
        betreff = '';
      }
      n = '${betreff.isEmpty ? 'Nachricht' : betreff}.eml';
    }
    s.anhaenge.add(MailAnhang(name: n, inhalt: inhalt, mimeTyp: art));
    return;
  }
  final istText = art == 'text/plain' || art == 'text/html';
  if (!anhang && istText && (name == null || name.isEmpty)) {
    final text = zeichensatzDekodieren(inhalt, typ.parameter['charset']);
    if (art == 'text/plain') {
      s.text ??= text;
    } else {
      s.html ??= text;
    }
    return;
  }
  var n = name ?? '';
  if (n.isEmpty) {
    n = 'Anhang ${s.anhaenge.length + 1}${_endungen[art] ?? ''}';
  }
  s.anhaenge.add(MailAnhang(name: n, inhalt: inhalt, mimeTyp: art));
}

// ── Kodierungen ──────────────────────────────────────────────────────

/// Base64 — großzügig: Zeilenumbrüche, fehlendes Auffüllen, Fremdzeichen.
Uint8List base64Dekodiert(String text) {
  final sauber = text.replaceAll(RegExp(r'[^A-Za-z0-9+/]'), '');
  final rest = sauber.length % 4;
  // Ein einzelnes überzähliges Zeichen trägt keine ganzen Bytes.
  final passend = rest == 1 ? sauber.substring(0, sauber.length - 1) : sauber;
  final aufgefuellt = passend.length % 4 == 0
      ? passend
      : passend.padRight(passend.length + 4 - passend.length % 4, '=');
  try {
    return base64.decode(aufgefuellt);
  } on FormatException {
    return Uint8List(0);
  }
}

int? _hex(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return null;
}

/// Quoted-Printable: „=C3=BC" sind Bytes, „=" am Zeilenende ein weicher
/// Umbruch.
Uint8List quotedPrintableDekodiert(List<int> bytes) {
  final aus = BytesBuilder(copy: false);
  for (var i = 0; i < bytes.length; i++) {
    final c = bytes[i];
    if (c != 0x3D) {
      aus.addByte(c);
      continue;
    }
    // Weicher Umbruch: „=" vor dem Zeilenende (auch mit Leerraum davor).
    var j = i + 1;
    while (j < bytes.length && (bytes[j] == 0x20 || bytes[j] == 0x09)) {
      j++;
    }
    if (j < bytes.length && bytes[j] == 0x0A) {
      i = j;
      continue;
    }
    if (j + 1 < bytes.length && bytes[j] == 0x0D && bytes[j + 1] == 0x0A) {
      i = j + 1;
      continue;
    }
    if (i + 2 < bytes.length) {
      final h = _hex(bytes[i + 1]);
      final l = _hex(bytes[i + 2]);
      if (h != null && l != null) {
        aus.addByte(h * 16 + l);
        i += 2;
        continue;
      }
    }
    aus.addByte(c);
  }
  return aus.takeBytes();
}

/// Das „Q" der kodierten Wörter: wie Quoted-Printable, „_" ist ein
/// Leerzeichen.
List<int> _qWort(String text) => quotedPrintableDekodiert(
      [for (final c in text.codeUnits) c == 0x5F ? 0x20 : (c > 0xFF ? 0x3F : c)],
    );

final RegExp _kodiertesWort = RegExp(r'=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?=');

/// Dekodiert die kodierten Wörter eines Kopfwerts (RFC 2047) —
/// aufeinanderfolgende im selben Zeichensatz zusammen, damit ein geteiltes
/// Zeichen ganz bleibt.
String kopfDekodieren(String text) {
  final aus = StringBuffer();
  var pos = 0;
  List<int>? puffer;
  String? pufferZeichensatz;
  void leeren() {
    final p = puffer;
    if (p != null) aus.write(zeichensatzDekodieren(p, pufferZeichensatz));
    puffer = null;
    pufferZeichensatz = null;
  }

  for (final m in _kodiertesWort.allMatches(text)) {
    final zwischen = text.substring(pos, m.start);
    // Leerraum zwischen zwei kodierten Wörtern fällt weg.
    if (puffer == null || zwischen.trim().isNotEmpty) {
      leeren();
      aus.write(zwischen);
    }
    final zeichensatz = m[1]!.split('*').first.toLowerCase();
    final bytes = m[2]!.toLowerCase() == 'b'
        ? base64Dekodiert(m[3]!)
        : _qWort(m[3]!);
    final p = puffer;
    if (p != null && pufferZeichensatz == zeichensatz) {
      p.addAll(bytes);
    } else {
      leeren();
      puffer = [...bytes];
      pufferZeichensatz = zeichensatz;
    }
    pos = m.end;
  }
  leeren();
  aus.write(text.substring(pos));
  return aus.toString();
}

// ── Zeichensätze ─────────────────────────────────────────────────────

/// Windows-1252 von 0x80 bis 0x9F — der Rest ist Latin-1.
const List<int> _cp1252Mitte = [
  0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
  0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
];

String _cp1252(List<int> bytes) => String.fromCharCodes([
      for (final b in bytes)
        b >= 0x80 && b <= 0x9F ? _cp1252Mitte[b - 0x80] : b,
    ]);

/// ISO-8859-15: Latin-1 mit Euro und acht anderen Zeichen.
const Map<int, int> _latin9 = {
  0xA4: 0x20AC,
  0xA6: 0x0160,
  0xA8: 0x0161,
  0xB4: 0x017D,
  0xB8: 0x017E,
  0xBC: 0x0152,
  0xBD: 0x0153,
  0xBE: 0x0178,
};

String _utf16(List<int> bytes, {bool bigEndian = false}) {
  final einheiten = <int>[
    for (var i = 0; i + 1 < bytes.length; i += 2)
      bigEndian
          ? (bytes[i] << 8) | bytes[i + 1]
          : bytes[i] | (bytes[i + 1] << 8),
  ];
  return String.fromCharCodes(einheiten);
}

/// Text aus [bytes] im [zeichensatz] der Mail — unbekannt oder ohne: UTF-8,
/// wenn es gültiges ist, sonst Windows-1252. ISO-8859-1 liest die App wie
/// Windows-1252 (so machen es auch die Browser).
String zeichensatzDekodieren(List<int> bytes, String? zeichensatz) {
  final cs = (zeichensatz ?? '').trim().toLowerCase().replaceAll('"', '');
  switch (cs) {
    case 'utf-8':
    case 'utf8':
      return utf8.decode(bytes, allowMalformed: true);
    case 'iso-8859-1':
    case 'iso8859-1':
    case 'iso_8859-1':
    case 'latin1':
    case 'latin-1':
    case 'l1':
    case 'windows-1252':
    case 'cp1252':
    case 'x-cp1252':
      return _cp1252(bytes);
    case 'iso-8859-15':
    case 'iso8859-15':
    case 'latin-9':
    case 'latin9':
      return String.fromCharCodes([for (final b in bytes) _latin9[b] ?? b]);
    case 'utf-16le':
    case 'utf-16':
    case 'unicode':
      return _utf16(bytes);
    case 'utf-16be':
      return _utf16(bytes, bigEndian: true);
  }
  return _rohText(bytes);
}

/// Text aus [bytes] nach einer Windows-Codepage (in Outlook-Mails).
String codepageDekodieren(List<int> bytes, int? codepage) => switch (codepage) {
      65001 => utf8.decode(bytes, allowMalformed: true),
      28591 => _cp1252(bytes),
      28605 => zeichensatzDekodieren(bytes, 'iso-8859-15'),
      1200 => _utf16(bytes),
      1201 => _utf16(bytes, bigEndian: true),
      20127 || 1252 => _cp1252(bytes),
      _ => _rohText(bytes),
    };

// ── HTML zu Text ─────────────────────────────────────────────────────

const Map<String, String> _entitaeten = {
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'auml': 'ä',
  'ouml': 'ö',
  'uuml': 'ü',
  'Auml': 'Ä',
  'Ouml': 'Ö',
  'Uuml': 'Ü',
  'szlig': 'ß',
  'euro': '€',
  'ndash': '–',
  'mdash': '—',
  'bdquo': '„',
  'ldquo': '“',
  'rdquo': '”',
  'sbquo': '‚',
  'lsquo': '‘',
  'rsquo': '’',
  'laquo': '«',
  'raquo': '»',
  'hellip': '…',
  'bull': '•',
  'middot': '·',
  'deg': '°',
  'plusmn': '±',
  'times': '×',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'sect': '§',
  'para': '¶',
  'micro': 'µ',
  'frac12': '½',
  'eacute': 'é',
  'egrave': 'è',
  'aacute': 'á',
  'agrave': 'à',
  'ccedil': 'ç',
  'shy': '',
  'zwnj': '',
  'zwj': '',
};

/// Ersetzt HTML-Entitäten: „&uuml;", „&#252;", „&#xFC;".
String htmlEntitaeten(String text) => text.replaceAllMapped(
      RegExp(r'&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z][a-zA-Z0-9]*);'),
      (m) {
        final e = m[1]!;
        if (e.startsWith('#')) {
          final hex = e.length > 1 && (e[1] == 'x' || e[1] == 'X');
          final code = int.tryParse(
            hex ? e.substring(2) : e.substring(1),
            radix: hex ? 16 : 10,
          );
          if (code == null || code <= 0 || code > 0x10FFFF) return m[0]!;
          return code == 0xA0 ? ' ' : String.fromCharCode(code);
        }
        return _entitaeten[e] ?? m[0]!;
      },
    );

/// Macht aus HTML lesbaren Text: Absätze und Umbrüche als Zeilen,
/// Aufzählungen mit „•", ohne Stile, Skripte und Kommentare.
String htmlZuText(String html) {
  var s = html
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .replaceAll(
        RegExp(
          r'<(head|style|script|title|xml)\b[^>]*>.*?</\1\s*>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      );
  // Zeilenumbrüche im Quelltext sind im HTML nur Leerraum.
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  s = s
      .replaceAll(RegExp(r'<br\b[^>]*>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(
          r'</(p|div|tr|h[1-6]|li|table|blockquote|ul|ol|pre)\s*>',
          caseSensitive: false,
        ),
        '\n',
      )
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'</t[dh]\s*>', caseSensitive: false), '  ')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  return _textAufraeumen(htmlEntitaeten(s).replaceAll('\u00A0', ' '));
}

/// Zeilen ohne Leerraum am Rand, höchstens eine Leerzeile am Stück.
String _textAufraeumen(String text) {
  final zeilen = [
    for (final z in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
        .split('\n'))
      z.replaceAll(RegExp(r'[ \t]+$'), '').replaceAll(RegExp(r'^ +'), ''),
  ];
  return zeilen
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

// ── Adressen und Datum ───────────────────────────────────────────────

/// Name und Adresse aus „Max Muster <max@muster.de>", „max@muster.de
/// (Max Muster)" oder „max@muster.de".
({String name, String adresse}) adresseLesen(String text) {
  final t = kopfDekodieren(text).trim();
  final spitz = RegExp(r'^(.*?)<([^>]*)>').firstMatch(t);
  if (spitz != null) {
    return (
      name: _ohneAnfuehrung(spitz[1]!),
      adresse: spitz[2]!.trim(),
    );
  }
  final klammer = RegExp(r'^([^\s(]+@[^\s(]+)\s*\((.*)\)\s*$').firstMatch(t);
  if (klammer != null) {
    return (name: klammer[2]!.trim(), adresse: klammer[1]!.trim());
  }
  if (t.contains('@')) return (name: '', adresse: _ohneAnfuehrung(t));
  return (name: _ohneAnfuehrung(t), adresse: '');
}

/// Eine Liste von Adressen zum Lesen: „Max Muster; erika@beispiel.de".
String adressenText(String text) => [
      for (final teil in _teilen(text, ',;'))
        if (teil.trim().isNotEmpty) _anzeige(adresseLesen(teil)),
    ].where((t) => t.isNotEmpty).join('; ');

String _anzeige(({String name, String adresse}) a) =>
    a.name.isNotEmpty ? a.name : a.adresse;

const Map<String, int> _monate = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'mär': 3,
  'mrz': 3,
  'apr': 4,
  'may': 5,
  'mai': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'okt': 10,
  'nov': 11,
  'dec': 12,
  'dez': 12,
};

/// Zeitzonen mit Namen in Minuten zu UTC.
const Map<String, int> _zonen = {
  'ut': 0,
  'utc': 0,
  'gmt': 0,
  'z': 0,
  'est': -300,
  'edt': -240,
  'cst': -360,
  'cdt': -300,
  'mst': -420,
  'mdt': -360,
  'pst': -480,
  'pdt': -420,
  'cet': 60,
  'cest': 120,
  'mez': 60,
  'mesz': 120,
};

/// Das Datum einer Mail („Tue, 21 Oct 2026 14:05:00 +0200") in
/// Ortszeit — null, wenn es sich nicht lesen lässt.
DateTime? internetDatum(String? text) {
  if (text == null) return null;
  final m = RegExp(
    r'(\d{1,2})\s+([A-Za-zä]{3})[A-Za-zä]*\.?\s+(\d{2,4})\s+'
    r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]{1,5})?',
  ).firstMatch(text);
  if (m == null) return null;
  final monat = _monate[m[2]!.toLowerCase()];
  if (monat == null) return null;
  var jahr = int.parse(m[3]!);
  if (jahr < 100) jahr += jahr < 50 ? 2000 : 1900;
  final zone = m[7];
  var minuten = 0;
  if (zone != null) {
    if (zone.startsWith('+') || zone.startsWith('-')) {
      final z = int.parse(zone.substring(1));
      minuten = (z ~/ 100) * 60 + z % 100;
      if (zone.startsWith('-')) minuten = -minuten;
    } else {
      minuten = _zonen[zone.toLowerCase()] ?? 0;
    }
  }
  final utc = DateTime.utc(
    jahr,
    monat,
    int.parse(m[1]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.tryParse(m[6] ?? '') ?? 0,
  ).subtract(Duration(minutes: minuten));
  return utc.toLocal();
}
