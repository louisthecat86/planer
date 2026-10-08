/// Text für die Standardschrift im PDF.
///
/// Die eingebauten PDF-Schriften (Helvetica) kennen nur Latin-1. Zeichen
/// außerhalb davon druckte das PDF als leeres Kästchen — in Artikeltexten
/// aus Navision stecken aber gern Gedankenstriche und typografische
/// Anführungszeichen. Sie werden durch ihre einfachen Gegenstücke ersetzt,
/// alles andere Unbekannte durch ein Fragezeichen.
///
/// Bewusst ohne Flutter-Abhängigkeit, damit jeder Druck sie benutzen kann.
library;

const Map<String, String> _ersatz = {
  '–': '-',
  '—': '-',
  '‐': '-',
  '‑': '-',
  '‒': '-',
  '−': '-',
  '•': '-',
  '„': '"',
  '“': '"',
  '”': '"',
  '″': '"',
  '‚': "'",
  '‘': "'",
  '’': "'",
  '′': "'",
  '…': '...',
  '≈': 'ca.',
  '×': 'x',
  '€': 'EUR',
  '→': '->',
};

/// [s] so umgeschrieben, dass die PDF-Standardschrift jedes Zeichen
/// darstellen kann.
String pdfText(String s) {
  var ersetzt = s;
  for (final e in _ersatz.entries) {
    ersetzt = ersetzt.replaceAll(e.key, e.value);
  }
  final puffer = StringBuffer();
  for (final r in ersetzt.runes) {
    if (r == 0x0D) continue; // Windows-Zeilenende: der Umbruch bleibt
    if (r == 0x09) {
      puffer.writeCharCode(0x20);
      continue;
    }
    // Steuerzeichen und alles außerhalb von Latin-1 kann die Schrift
    // nicht darstellen. Zeilenumbrüche setzt das PDF selbst um.
    final darstellbar = r == 0x0A ||
        (r >= 0x20 && r < 0x7F) ||
        (r >= 0xA0 && r <= 0xFF);
    puffer.writeCharCode(darstellbar ? r : 0x3F);
  }
  return puffer.toString();
}
