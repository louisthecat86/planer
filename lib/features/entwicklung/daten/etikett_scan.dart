import 'dart:typed_data';

import '../../../core/database/database.dart';
import 'datei_typen.dart';

// Das Originaletikett eines Projekts: der Scan des gedruckten Etiketts,
// wie es aus der Warenwirtschaft kam — ein Bild oder ein PDF. Hier steht,
// was die App und der Projektbericht gleich brauchen; Einfügen und Zeigen
// in projekte/originaletikett.dart.

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
