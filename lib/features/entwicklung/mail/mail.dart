import 'dart:typed_data';

import 'eml_lesen.dart';
import 'msg_lesen.dart';

// Eine E-Mail, wie sie in ein Projekt kommt: Betreff, Absender, Empfänger,
// Datum, Text und Anhänge — gelesen aus einer Outlook-Mail (.msg) oder
// einer Internet-Mail (.eml). Beides liest die App selbst, ohne Outlook.

/// Ein Anhang einer Mail.
class MailAnhang {
  const MailAnhang({
    required this.name,
    required this.inhalt,
    this.mimeTyp,
  });

  final String name;
  final Uint8List inhalt;

  /// Der Medientyp, wenn die Mail ihn nennt.
  final String? mimeTyp;
}

/// Eine gelesene Mail.
class Mail {
  const Mail({
    this.betreff = '',
    this.vonName = '',
    this.vonAdresse = '',
    this.an = '',
    this.cc = '',
    this.datum,
    this.text = '',
    this.anhaenge = const [],
  });

  final String betreff;
  final String vonName;
  final String vonAdresse;

  /// Die Empfänger, wie sie in der Mail stehen: „Max Muster; Erika
  /// Beispiel".
  final String an;
  final String cc;

  /// Gesendet am — null, wenn die Mail es nicht sagt.
  final DateTime? datum;

  /// Der Text — aus dem HTML gewonnen, wenn die Mail keinen reinen Text
  /// hat.
  final String text;

  final List<MailAnhang> anhaenge;

  /// „Max Muster <max@muster.de>" — oder was davon da ist.
  String get von {
    final name = vonName.trim();
    final adresse = vonAdresse.trim();
    if (name.isEmpty) return adresse;
    if (adresse.isEmpty || name == adresse) return name;
    return '$name <$adresse>';
  }
}

/// Ob [bytes] eine Verbunddatei ist — so speichert Outlook eine Mail
/// (.msg).
bool istVerbunddatei(Uint8List bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0xD0 &&
    bytes[1] == 0xCF &&
    bytes[2] == 0x11 &&
    bytes[3] == 0xE0 &&
    bytes[4] == 0xA1 &&
    bytes[5] == 0xB1 &&
    bytes[6] == 0x1A &&
    bytes[7] == 0xE1;

/// Ob die Datei [name] nach ihrer Endung eine Mail ist.
bool istMailName(String name) {
  final n = name.toLowerCase().trim();
  return n.endsWith('.msg') || n.endsWith('.eml');
}

/// Liest eine Mail — Outlook (.msg) oder Internet-Mail (.eml), erkannt am
/// Inhalt. Wirft [FormatException], wenn sie sich nicht lesen lässt.
Mail mailLesen(Uint8List bytes) =>
    istVerbunddatei(bytes) ? msgLesen(bytes) : emlLesen(bytes);

/// Liest [bytes] als Mail, wenn [name] eine ist — sonst null; auch null,
/// wenn sie sich nicht lesen lässt.
Mail? alsMail(String name, Uint8List bytes) {
  if (!istMailName(name)) return null;
  try {
    return mailLesen(bytes);
  } on FormatException {
    return null;
  }
}

final RegExp _vorsatz = RegExp(
  r'^\s*((re|aw|wg|fw|fwd|wtr|antw|weiterl|tr|sv|vs|rv)\s*(\[\d+\])?\s*:\s*)+',
  caseSensitive: false,
);

/// Der Betreff ohne „AW:", „WG:", „Re:", „Fwd:" am Anfang.
String betreffOhneVorsatz(String betreff) =>
    betreff.replaceFirst(_vorsatz, '').trim();

/// Adressen bei Anbietern für jedermann — dort sagt die Adresse nichts
/// über die Firma.
const Set<String> _freemailer = {
  'gmail.com',
  'googlemail.com',
  'web.de',
  'gmx.de',
  'gmx.net',
  'gmx.at',
  'gmx.ch',
  't-online.de',
  'outlook.com',
  'outlook.de',
  'hotmail.com',
  'hotmail.de',
  'live.com',
  'live.de',
  'msn.com',
  'yahoo.com',
  'yahoo.de',
  'icloud.com',
  'me.com',
  'mac.com',
  'aol.com',
  'freenet.de',
  'arcor.de',
  'posteo.de',
  'mailbox.org',
  'protonmail.com',
  'proton.me',
};

/// Der Kunde nach dem Absender: die Firma aus der Adresse
/// („einkauf@muster-fleisch.de" → „Muster-Fleisch"), bei Anbietern für
/// jedermann der Name des Absenders.
String kundeAusAbsender(Mail m) {
  final adresse = m.vonAdresse.trim().toLowerCase();
  final at = adresse.lastIndexOf('@');
  final domain = at < 0 ? '' : adresse.substring(at + 1);
  if (domain.isEmpty || _freemailer.contains(domain)) return m.vonName.trim();
  final teile = domain.split('.');
  // „mail.muster.co.uk" → „muster": der Teil vor der Endung, ohne „mail."
  // oder „de." davor.
  var kern = teile.length >= 2 ? teile[teile.length - 2] : teile.first;
  if (teile.length >= 3 &&
      const {'co', 'com', 'or', 'ac', 'gv', 'ne'}.contains(kern)) {
    kern = teile[teile.length - 3];
  }
  return kern
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join('-');
}

/// Die Beschreibung eines Verlaufseintrags zur Mail: Empfänger und Text,
/// höchstens [maxZeichen] lang.
String mailBeschreibung(Mail m, {int maxZeichen = 8000}) {
  final kopf = [
    if (m.an.trim().isNotEmpty) 'An: ${m.an.trim()}',
    if (m.cc.trim().isNotEmpty) 'Cc: ${m.cc.trim()}',
  ].join('\n');
  var text = m.text.trim();
  if (text.length > maxZeichen) {
    text = '${text.substring(0, maxZeichen).trimRight()} …';
  }
  return [if (kopf.isNotEmpty) kopf, if (text.isNotEmpty) text].join('\n\n');
}

final RegExp _zitatBeginn = RegExp(
  r'^(-{2,}\s*(ursprüngliche nachricht|original message|weitergeleitete '
  r'nachricht|forwarded message)\s*-{2,}.*'
  r'|(von|from):\s.+'
  r'|am .+ schrieb .+:'
  r'|on .+ wrote:'
  r'|_{20,})$',
  caseSensitive: false,
);

/// Der Text einer Mail ohne das, was sie zitiert: ab „-----Ursprüngliche
/// Nachricht-----", „Von: …" oder „Am … schrieb …:"; Zeilen mit „>" am
/// Anfang fallen weg.
String ohneZitat(String text) {
  final zeilen = <String>[];
  for (final z in text.split('\n')) {
    final t = z.trim();
    if (_zitatBeginn.hasMatch(t)) break;
    if (t.startsWith('>')) continue;
    zeilen.add(z);
  }
  return zeilen.join('\n').trim();
}

/// Was ein neues Projekt aus einer Mail mitbringt: den Namen aus dem
/// Betreff, den Kunden aus dem Absender, die Anfrage als Produktidee.
({String name, String kunde, String idee}) projektVorschlag(Mail m) {
  final betreff = betreffOhneVorsatz(m.betreff);
  final von =
      m.vonName.trim().isNotEmpty ? m.vonName.trim() : m.vonAdresse.trim();
  var idee = ohneZitat(m.text);
  if (idee.length > 1500) idee = '${idee.substring(0, 1500).trimRight()} …';
  return (
    name: betreff.isNotEmpty
        ? betreff
        : (von.isEmpty ? 'Anfrage' : 'Anfrage von $von'),
    kunde: kundeAusAbsender(m),
    idee: idee,
  );
}
