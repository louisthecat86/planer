import 'dart:typed_data';

import 'xlsx_bild.dart';
import 'xlsx_blatt.dart';

// Platzhalter in einer Excel-Mappe ersetzen, ohne die Mappe neu zu bauen.
//
// Eine .xlsx ist ein ZIP mit XML. Texte stehen meist in
// xl/sharedStrings.xml, manchmal direkt in der Zelle („inlineStr"), dazu
// in Kopf- und Fußzeilen. Nur diese Texte werden geändert — Formatierung,
// verbundene Zellen, Bilder und Formeln der Vorlage bleiben unberührt.
//
// Steht ein Platzhalter allein in einer Zelle unter einem Kontroll-
// kästchen, setzt sein Wert das Häkchen: „X" hakt an, leer nimmt den Haken
// weg; die Zelle selbst bleibt dann leer.
//
// Ein Bild-Platzhalter ({{produktbild}}) allein in einer Zelle bekommt
// sein Bild über den verbundenen Bereich der Zelle (xlsx_bild.dart); ohne
// Bild bleibt die Zelle leer.
//
// Ein Platzhalter in einem formatierten Textstück behält dessen Format.
// Hat Excel einen Platzhalter beim Bearbeiten in mehrere Formatierungs-
// stücke zerlegt („{{zu" fett, „taten}}" normal), wird der ganze Text der
// Zelle zusammengesetzt und ohne diese Stücke neu geschrieben.

/// {{name}} — Buchstaben, Ziffern, Punkt und Unterstrich, Leerzeichen
/// innen erlaubt.
final RegExp kPlatzhalterMuster = RegExp(r'\{\{\s*([A-Za-z0-9_.]+)\s*\}\}');

/// Ein Platzhalter allein in einer Zelle.
final RegExp _allein = RegExp(r'^\s*\{\{\s*([A-Za-z0-9_.]+)\s*\}\}\s*$');

/// Platzhalter für Bilder — ohne Bild bleiben sie leer.
const Set<String> kBildPlatzhalter = {'produktbild'};

/// Das Ergebnis: die neue Mappe und was dabei auffiel.
class VorlageErgebnis {
  const VorlageErgebnis({
    required this.bytes,
    required this.ersetzt,
    required this.unbekannt,
    this.kaestchen = 0,
    this.bilder = const {},
  });

  final Uint8List bytes;

  /// Platzhalter, die ersetzt wurden.
  final Set<String> ersetzt;

  /// Platzhalter in der Vorlage, die die App nicht kennt — wohl Tippfehler.
  final Set<String> unbekannt;

  /// Wie viele Kontrollkästchen angehakt wurden.
  final int kaestchen;

  /// Die Bild-Platzhalter, die ihr Bild bekommen haben.
  final Set<String> bilder;
}

final RegExp _si = RegExp(r'<si>(.*?)</si>', dotAll: true);
final RegExp _is = RegExp(r'<is>(.*?)</is>', dotAll: true);

/// Die Platzhalter in einer Vorlage — in Zellen, Kopf- und Fußzeilen.
/// Wirft [FormatException], wenn [xlsx] keine Excel-Mappe ist.
Set<String> platzhalterIn(Uint8List xlsx) {
  final mappe = XlsxMappe.lesen(xlsx);
  final gefunden = <String>{};
  void sammle(String text) {
    for (final p in kPlatzhalterMuster.allMatches(text)) {
      gefunden.add(p[1]!);
    }
  }

  for (final roh in mappe.geteilteRoh) {
    sammle(textAusBlock(roh));
  }
  for (final pfad in mappe.blattPfade) {
    final xml = mappe.text(pfad) ?? '';
    for (final m in _is.allMatches(xml)) {
      sammle(textAusBlock(m[1]!));
    }
    for (final m in kKopfFuss.allMatches(xml)) {
      sammle(xmlUnescape(m[2]!));
    }
  }
  return gefunden;
}

/// Ersetzt in [xlsx] jeden bekannten Platzhalter durch seinen Wert aus
/// [werte] und setzt die [bilder] ein. Unbekannte Platzhalter bleiben
/// stehen und werden gemeldet. Wirft [FormatException], wenn [xlsx] keine
/// Excel-Mappe ist.
VorlageErgebnis vorlageFuellen(
  Uint8List xlsx,
  Map<String, String> werte, {
  Map<String, XlsxBild> bilder = const {},
}) {
  final mappe = XlsxMappe.lesen(xlsx);
  final ersetzt = <String>{};
  final unbekannt = <String>{};
  final eingesetzt = <String>{};

  String? wertVon(String name) {
    final wert =
        werte[name] ?? (kBildPlatzhalter.contains(name) ? '' : null);
    if (wert == null) {
      unbekannt.add(name);
    } else {
      ersetzt.add(name);
    }
    return wert;
  }

  String ersetze(String text) =>
      text.replaceAllMapped(kPlatzhalterMuster, (m) => wertVon(m[1]!) ?? m[0]!);

  String block(String tag, String inhalt, String ganz) {
    final text = textAusBlock(inhalt);
    if (!kPlatzhalterMuster.hasMatch(text)) return ganz;
    // Jeder Platzhalter liegt ganz in einem Textstück: dort ersetzen, das
    // Format der Stücke bleibt.
    final stuecke = kTextElement.allMatches(inhalt).toList();
    final inStuecken = stuecke.fold<int>(
      0,
      (n, s) =>
          n + kPlatzhalterMuster.allMatches(xmlUnescape(s[1] ?? '')).length,
    );
    if (inStuecken == kPlatzhalterMuster.allMatches(text).length) {
      final neu = inhalt.replaceAllMapped(kTextElement, (s) {
        final alt = xmlUnescape(s[1] ?? '');
        if (!kPlatzhalterMuster.hasMatch(alt)) return s[0]!;
        return '<t xml:space="preserve">${xmlEscape(ersetze(alt))}</t>';
      });
      return '<$tag>$neu</$tag>';
    }
    return '<$tag><t xml:space="preserve">${xmlEscape(ersetze(text))}</t>'
        '</$tag>';
  }

  var kaestchen = 0;
  for (final pfad in mappe.blattPfade) {
    final blatt = XlsxBlatt(mappe, pfad);
    var xml = mappe.text(pfad) ?? '';

    // Bilder: über den verbundenen Bereich ihrer Zelle, die leer wird.
    for (final z in blatt.zellen) {
      final m = _allein.firstMatch(z.text);
      final bild = m == null ? null : bilder[m[1]!];
      if (m == null || bild == null) continue;
      final neu = bildEinsetzen(
        mappe,
        blattPfad: pfad,
        blattXml: xml,
        bereich: blatt.bereichVon(z.zeile, z.spalte),
        bild: bild,
      );
      if (neu == null) continue;
      xml = zelleLeeren(neu, z.ref);
      wertVon(m[1]!);
      eingesetzt.add(m[1]!);
    }

    // Platzhalter unter Kontrollkästchen setzen den Haken.
    for (final z in blatt.zellen) {
      final m = _allein.firstMatch(z.text);
      if (m == null) continue;
      final unter = blatt.kaestchenIn(blatt.bereichVon(z.zeile, z.spalte));
      if (unter.isEmpty) continue;
      final wert = wertVon(m[1]!);
      if (wert == null) continue;
      final an = wert.trim().isNotEmpty;
      for (final k in unter) {
        final vml = mappe.text(k.vmlPfad);
        if (vml != null) {
          mappe.schreibe(k.vmlPfad, vmlKaestchenSetzen(vml, k.nummer, an: an));
        }
        final propPfad = k.ctrlPropPfad;
        final prop = propPfad == null ? null : mappe.text(propPfad);
        if (propPfad != null && prop != null) {
          mappe.schreibe(propPfad, ctrlPropSetzen(prop, an: an));
        }
        if (an) kaestchen++;
      }
      xml = zelleLeeren(xml, z.ref);
    }

    xml = xml.replaceAllMapped(_is, (m) => block('is', m[1]!, m[0]!));
    xml = xml.replaceAllMapped(kKopfFuss, (m) {
      final alt = xmlUnescape(m[2]!);
      if (!kPlatzhalterMuster.hasMatch(alt)) return m[0]!;
      return '<${m[1]}>${xmlEscape(kopfFussErsetzen(alt, wertVon))}'
          '</${m[1]}>';
    });
    mappe.schreibe(pfad, xml);
  }

  final geteilt = mappe.text('xl/sharedStrings.xml');
  if (geteilt != null) {
    mappe.schreibe(
      'xl/sharedStrings.xml',
      geteilt.replaceAllMapped(_si, (m) => block('si', m[1]!, m[0]!)),
    );
  }

  return VorlageErgebnis(
    bytes: mappe.packen(),
    ersetzt: ersetzt,
    unbekannt: unbekannt,
    kaestchen: kaestchen,
    bilder: eingesetzt,
  );
}

/// Ersetzt die Platzhalter in einer Kopf- oder Fußzeile. Dort leitet „&"
/// einen Steuercode ein („&P" Seite, „&8" Schriftgröße): Ein „&" im Wert
/// wird verdoppelt, und beginnt ein Wert mit einer Ziffer direkt hinter
/// einer Schriftgröße, kommt ein Leerzeichen dazwischen.
String kopfFussErsetzen(String text, String? Function(String name) wert) {
  final aus = StringBuffer();
  var bis = 0;
  for (final m in kPlatzhalterMuster.allMatches(text)) {
    aus.write(text.substring(bis, m.start));
    bis = m.end;
    final w = wert(m[1]!);
    if (w == null) {
      aus.write(m[0]);
      continue;
    }
    var neu = w.replaceAll('&', '&&');
    final davor = text.substring(0, m.start);
    if (RegExp(r'(^|[^&])&\d+$').hasMatch(davor) &&
        RegExp(r'^\d').hasMatch(neu)) {
      neu = ' $neu';
    }
    aus.write(neu);
  }
  aus.write(text.substring(bis));
  return aus.toString();
}
