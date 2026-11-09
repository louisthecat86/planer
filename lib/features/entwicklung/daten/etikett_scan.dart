import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../core/database/database.dart';
import 'datei_typen.dart';

// Das Originaletikett eines Projekts: der Scan des gedruckten Etiketts,
// wie es aus der Warenwirtschaft kam — ein Bild oder ein PDF. Hier steht,
// was die App und der Projektbericht gleich brauchen; Einfügen und Zeigen
// in projekte/originaletikett.dart.
//
// Ist das Etikett im Scan zu klein — etwa ein kleines Etikett auf einem
// A4-Scan —, lässt es sich vergrößern: Man zoomt in einem Rahmen von der
// Form seines Platzes im Bericht darauf ([EtikettAusschnitt]), und der
// Bericht zeigt nur diesen Ausschnitt, so groß, wie Platz ist.

/// Die Endungen, die das Feld nimmt.
const List<String> kEtikettEndungen = ['pdf', 'jpg', 'jpeg', 'png'];

/// Von einem PDF zeigen App und Bericht höchstens so viele Seiten.
const int kEtikettMaxSeiten = 4;

/// Was beim Punkt „Etikett erstellt" zum Originaletikett steht — es zählt
/// nicht für den Punkt, es steht nur dabei.
String originaletikettStand(EntwicklungsProjekt p) => p.etikettDateiId == null
    ? 'Originaletikett fehlt noch'
    : 'Originaletikett hinterlegt';

/// Rastert die ersten Seiten eines PDFs zu PNG-Bildern — in der App mit
/// PDFium (projekte/originaletikett.dart), im Test ersetzbar.
typedef PdfSeiten = Future<List<Uint8List>> Function(Uint8List pdf);

/// Ist die Datei ein PDF? Nach ihrem Inhalt, wenn es ihn gibt — „%PDF"
/// steht in den ersten 1024 Bytes —, sonst nach Medientyp und Endung.
bool istPdfDatei(EntwicklungsDatei datei, [Uint8List? inhalt]) {
  if (inhalt != null) {
    final ende = inhalt.length < 1024 ? inhalt.length : 1024;
    // „%PDF" in Bytes: 0x25 0x50 0x44 0x46.
    for (var i = 0; i + 3 < ende; i++) {
      if (inhalt[i] == 0x25 &&
          inhalt[i + 1] == 0x50 &&
          inhalt[i + 2] == 0x44 &&
          inhalt[i + 3] == 0x46) {
        return true;
      }
    }
    return false;
  }
  return (datei.mimeTyp ?? mimeTypAus(datei.name)) == 'application/pdf';
}

/// Das Originaletikett als Bilder: ein Bild, wie es ist; ein PDF als
/// seine ersten [kEtikettMaxSeiten] Seiten über [pdfSeiten]. Ohne sie —
/// oder wenn das Rastern scheitert — leer: Dann bleibt das PDF unter den
/// Dateien zum Öffnen.
Future<List<Uint8List>> etikettAlsBilder(
  EntwicklungsDatei datei,
  Uint8List inhalt, {
  PdfSeiten? pdfSeiten,
}) async {
  if (!istPdfDatei(datei, inhalt)) return [inhalt];
  if (pdfSeiten == null) return const [];
  try {
    final seiten = await pdfSeiten(inhalt);
    return [
      for (final s in seiten.take(kEtikettMaxSeiten))
        if (s.isNotEmpty) s,
    ];
  } catch (_) {
    return const [];
  }
}

// ── Vergrößern ─────────────────────────────────────────────────────────

/// Die Form des Platzes, den das Originaletikett im Bericht hat (A4 hoch:
/// die Seitenbreite, 360 Punkt hoch) — breit durch hoch. Der Rahmen beim
/// Vergrößern hat dieselbe Form: Was darin steht, füllt den Platz.
const double kEtikettRahmenForm = 511.28 / 360;

/// So weit lässt sich ein Scan höchstens vergrößern.
const double kEtikettMaxVergroesserung = 10;

/// Der Ausschnitt eines Originaletiketts, den der Bericht vergrößert zeigt
/// — in Bruchteilen des Scans (0 bis 1, von links oben). Er gehört zum
/// Scan [datei]: Ein neuer Scan zeigt wieder das ganze Etikett. Bei einem
/// PDF gilt er für jede Seite.
class EtikettAusschnitt {
  const EtikettAusschnitt({
    required this.datei,
    required this.x,
    required this.y,
    required this.breite,
    required this.hoehe,
  });

  /// Der gespeicherte Ausschnitt — null, wenn es keinen gibt oder er
  /// nicht taugt.
  static EtikettAusschnitt? ausJson(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final m = jsonDecode(json);
      if (m is! Map<String, dynamic>) return null;
      final datei = m['datei'];
      double? zahl(String k) => (m[k] as num?)?.toDouble();
      final (x, y, b, h) = (zahl('x'), zahl('y'), zahl('b'), zahl('h'));
      if (datei is! String || x == null || y == null || b == null) {
        return null;
      }
      if (h == null || b <= 0 || h <= 0) return null;
      // Ein wenig Rundung darf sein; mehr ist kein Ausschnitt des Scans.
      const spiel = 1e-6;
      if (x < -spiel || y < -spiel || x + b > 1 + spiel) return null;
      if (y + h > 1 + spiel) return null;
      return EtikettAusschnitt(
        datei: datei,
        x: x.clamp(0.0, 1.0),
        y: y.clamp(0.0, 1.0),
        breite: b.clamp(0.0, 1.0),
        hoehe: h.clamp(0.0, 1.0),
      );
    } catch (_) {
      return null;
    }
  }

  /// Die ID des Scans, zu dem der Ausschnitt gehört.
  final String datei;

  final double x;
  final double y;
  final double breite;
  final double hoehe;

  String alsJson() => jsonEncode({
        'datei': datei,
        'x': x,
        'y': y,
        'b': breite,
        'h': hoehe,
      });
}

/// Der Ausschnitt des Projekts — nur, wenn er zu seinem Originaletikett
/// gehört.
EtikettAusschnitt? etikettAusschnitt(EntwicklungsProjekt p) {
  final a = EtikettAusschnitt.ausJson(p.etikettAusschnitt);
  return a != null && a.datei == p.etikettDateiId ? a : null;
}

/// Wo ein Bild ([bildBreite] × [bildHoehe]) in einem Rahmen steht, wenn es
/// ganz hineinpasst und mittig sitzt — wie ein Bild mit BoxFit.contain.
({double x, double y, double breite, double hoehe}) bildImRahmen({
  required double bildBreite,
  required double bildHoehe,
  required double rahmenBreite,
  required double rahmenHoehe,
}) {
  final massstab = math.min(rahmenBreite / bildBreite, rahmenHoehe / bildHoehe);
  final b = bildBreite * massstab;
  final h = bildHoehe * massstab;
  return (
    x: (rahmenBreite - b) / 2,
    y: (rahmenHoehe - h) / 2,
    breite: b,
    hoehe: h,
  );
}

/// Der Teil des Bilds, den der Rahmen zeigt: Das Bild steht darin ganz
/// eingepasst ([bildImRahmen]), die Ansicht ist um [vergroesserung]
/// gezoomt und um [dx], [dy] verschoben — ein Punkt p erscheint bei
/// p · vergroesserung + d, wie im InteractiveViewer. null, wenn das ganze
/// Bild zu sehen ist (oder nichts davon).
EtikettAusschnitt? ausschnittDerAnsicht({
  required String datei,
  required double bildBreite,
  required double bildHoehe,
  required double rahmenBreite,
  required double rahmenHoehe,
  required double vergroesserung,
  required double dx,
  required double dy,
}) {
  final bild = bildImRahmen(
    bildBreite: bildBreite,
    bildHoehe: bildHoehe,
    rahmenBreite: rahmenBreite,
    rahmenHoehe: rahmenHoehe,
  );
  // Was der Rahmen zeigt, in Punkten des ungezoomten Rahmens.
  final links = math.max(-dx / vergroesserung, bild.x);
  final oben = math.max(-dy / vergroesserung, bild.y);
  final rechts =
      math.min((rahmenBreite - dx) / vergroesserung, bild.x + bild.breite);
  final unten =
      math.min((rahmenHoehe - dy) / vergroesserung, bild.y + bild.hoehe);
  if (rechts <= links || unten <= oben) return null;
  final a = EtikettAusschnitt(
    datei: datei,
    x: (links - bild.x) / bild.breite,
    y: (oben - bild.y) / bild.hoehe,
    breite: (rechts - links) / bild.breite,
    hoehe: (unten - oben) / bild.hoehe,
  );
  // Fast alles zu sehen: kein Ausschnitt.
  return a.breite > .98 && a.hoehe > .98 ? null : a;
}

/// Umgekehrt: Vergrößerung und Verschiebung, die [a] im Rahmen zeigen —
/// so groß, wie er hineinpasst, mittig, ohne über den Rand des Rahmens
/// hinaus zu schieben.
({double vergroesserung, double dx, double dy}) ansichtFuer(
  EtikettAusschnitt a, {
  required double bildBreite,
  required double bildHoehe,
  required double rahmenBreite,
  required double rahmenHoehe,
}) {
  final bild = bildImRahmen(
    bildBreite: bildBreite,
    bildHoehe: bildHoehe,
    rahmenBreite: rahmenBreite,
    rahmenHoehe: rahmenHoehe,
  );
  final b = a.breite * bild.breite;
  final h = a.hoehe * bild.hoehe;
  final v = math
      .min(rahmenBreite / b, rahmenHoehe / h)
      .clamp(1.0, kEtikettMaxVergroesserung);
  final mitteX = bild.x + (a.x + a.breite / 2) * bild.breite;
  final mitteY = bild.y + (a.y + a.hoehe / 2) * bild.hoehe;
  return (
    vergroesserung: v,
    dx: (rahmenBreite / 2 - mitteX * v)
        .clamp(rahmenBreite - rahmenBreite * v, 0.0),
    dy: (rahmenHoehe / 2 - mitteY * v)
        .clamp(rahmenHoehe - rahmenHoehe * v, 0.0),
  );
}

/// Schneidet [a] aus dem Bild [bytes] — gedreht, wie es angezeigt wird
/// (EXIF). Ein JPEG bleibt JPEG, alles andere wird PNG. Lässt es sich
/// nicht lesen, bleibt es, wie es ist.
Uint8List etikettZuschneiden(Uint8List bytes, EtikettAusschnitt a) {
  try {
    // Wirft bei manchem, das kein Bild ist, statt null zu liefern.
    final gelesen = img.decodeImage(bytes);
    if (gelesen == null) return bytes;
    final bild = img.bakeOrientation(gelesen);
    final x = (a.x * bild.width).floor().clamp(0, bild.width - 1);
    final y = (a.y * bild.height).floor().clamp(0, bild.height - 1);
    final b = (a.breite * bild.width).ceil().clamp(1, bild.width - x);
    final h = (a.hoehe * bild.height).ceil().clamp(1, bild.height - y);
    final teil = img.copyCrop(bild, x: x, y: y, width: b, height: h);
    final jpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    return jpeg ? img.encodeJpg(teil, quality: 92) : img.encodePng(teil);
  } catch (_) {
    return bytes;
  }
}

/// [etikettZuschneiden] neben der Oberfläche — ein großer Scan braucht
/// einen Moment.
Future<Uint8List> etikettZuschneidenImHintergrund(
  Uint8List bytes,
  EtikettAusschnitt a,
) =>
    Isolate.run(() => etikettZuschneiden(bytes, a));
