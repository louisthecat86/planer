import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../core/utils/fehler_text.dart';

// Platzhalter in einer Excel-Mappe ersetzen, ohne die Mappe neu zu bauen.
//
// Eine .xlsx ist ein ZIP mit XML. Texte stehen meist in
// xl/sharedStrings.xml, manchmal direkt in der Zelle („inlineStr"). Nur
// diese Texte werden geändert — Formatierung, verbundene Zellen, Bilder
// und Formeln der Vorlage bleiben unberührt.
//
// Hat Excel einen Platzhalter beim Bearbeiten in mehrere Formatierungs-
// stücke zerlegt („{{zu" fett, „taten}}" normal), wird der ganze Text der
// Zelle zusammengesetzt und ohne diese Stücke neu geschrieben.

/// {{name}} — Buchstaben, Ziffern, Punkt und Unterstrich, Leerzeichen
/// innen erlaubt.
final RegExp kPlatzhalterMuster = RegExp(r'\{\{\s*([A-Za-z0-9_.]+)\s*\}\}');

/// Das Ergebnis: die neue Mappe und was dabei auffiel.
class VorlageErgebnis {
  const VorlageErgebnis({
    required this.bytes,
    required this.ersetzt,
    required this.unbekannt,
  });

  final Uint8List bytes;

  /// Platzhalter, die ersetzt wurden.
  final Set<String> ersetzt;

  /// Platzhalter in der Vorlage, die die App nicht kennt — wohl Tippfehler.
  final Set<String> unbekannt;
}

final RegExp _si = RegExp(r'<si>(.*?)</si>', dotAll: true);
final RegExp _is = RegExp(r'<is>(.*?)</is>', dotAll: true);
final RegExp _t = RegExp(r'<t(?:\s[^>]*)?>(.*?)</t>|<t(?:\s[^>]*)?/>', dotAll: true);

String _unescape(String s) => s
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

String _escape(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Der Text eines <si>- oder <is>-Inhalts: alle <t> hintereinander.
String _textAus(String inhalt) =>
    [for (final m in _t.allMatches(inhalt)) _unescape(m[1] ?? '')].join();

/// Die Platzhalter in einer Vorlage.
Set<String> platzhalterIn(Uint8List xlsx) {
  final gefunden = <String>{};
  for (final datei in _textDateien(_oeffne(xlsx))) {
    final xml = utf8.decode(datei.inhalt, allowMalformed: true);
    for (final muster in [_si, _is]) {
      for (final m in muster.allMatches(xml)) {
        for (final p in kPlatzhalterMuster.allMatches(_textAus(m[1]!))) {
          gefunden.add(p[1]!);
        }
      }
    }
  }
  return gefunden;
}

/// Ersetzt in [xlsx] jeden bekannten Platzhalter durch seinen Wert aus
/// [werte]. Unbekannte bleiben stehen und werden gemeldet. Wirft
/// [FormatException], wenn [xlsx] keine Excel-Mappe ist.
VorlageErgebnis vorlageFuellen(Uint8List xlsx, Map<String, String> werte) {
  final archiv = _oeffne(xlsx);
  final ersetzt = <String>{};
  final unbekannt = <String>{};

  String ersetze(String text) => text.replaceAllMapped(kPlatzhalterMuster, (m) {
        final name = m[1]!;
        final wert = werte[name];
        if (wert == null) {
          unbekannt.add(name);
          return m[0]!;
        }
        ersetzt.add(name);
        return wert;
      });

  String block(String tag, Match m) {
    final inhalt = m[1]!;
    final text = _textAus(inhalt);
    if (!kPlatzhalterMuster.hasMatch(text)) return m[0]!;
    return '<$tag><t xml:space="preserve">${_escape(ersetze(text))}</t></$tag>';
  }

  final neu = Archive();
  final aendern = {for (final d in _textDateien(archiv)) d.name};
  for (final datei in archiv.files) {
    if (!datei.isFile) continue;
    final roh = datei.content;
    if (roh is! List<int>) continue;
    var inhalt = Uint8List.fromList(roh);
    if (aendern.contains(datei.name)) {
      var xml = utf8.decode(inhalt, allowMalformed: true);
      xml = xml.replaceAllMapped(_si, (m) => block('si', m));
      xml = xml.replaceAllMapped(_is, (m) => block('is', m));
      inhalt = Uint8List.fromList(utf8.encode(xml));
    }
    neu.addFile(ArchiveFile(datei.name, inhalt.length, inhalt));
  }
  final gepackt = ZipEncoder().encode(neu);
  if (gepackt == null) {
    throw const FormatException('Die Mappe ließ sich nicht packen.');
  }
  return VorlageErgebnis(
    bytes: Uint8List.fromList(gepackt),
    ersetzt: ersetzt,
    unbekannt: unbekannt,
  );
}

Archive _oeffne(Uint8List xlsx) {
  final istZip = xlsx.length > 3 && xlsx[0] == 0x50 && xlsx[1] == 0x4b;
  if (!istZip) {
    throw const FormatException('Die Vorlage ist keine Excel-Mappe (.xlsx).');
  }
  final Archive archiv;
  try {
    archiv = ZipDecoder().decodeBytes(xlsx);
  } catch (e) {
    throw FormatException(
      'Die Vorlage ließ sich nicht öffnen: ${fehlerText(e)}',
    );
  }
  if (archiv.findFile('xl/workbook.xml') == null) {
    throw const FormatException('Die Vorlage ist keine Excel-Mappe (.xlsx).');
  }
  return archiv;
}

/// Die XML-Dateien, in denen Texte stehen können.
List<({String name, List<int> inhalt})> _textDateien(Archive archiv) => [
      for (final d in archiv.files)
        if (d.isFile &&
            (d.name == 'xl/sharedStrings.xml' ||
                (d.name.startsWith('xl/worksheets/') &&
                    d.name.endsWith('.xml'))))
          if (d.content case final List<int> inhalt)
            (name: d.name, inhalt: inhalt),
    ];
