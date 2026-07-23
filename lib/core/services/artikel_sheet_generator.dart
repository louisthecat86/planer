/// Ein Prozessschritt, aufbereitet für den Sheet-Generator.
class GenSchritt {
  const GenSchritt({
    required this.nr,
    required this.abteilung,
    required this.prozessschritt,
    required this.anlage,
    this.personen,
    this.mengeKg,
    this.zeitText,
    this.fixZeitMin,
  });

  final int nr;
  final String abteilung;
  final String? prozessschritt;
  final String? anlage;
  final int? personen;
  final double? mengeKg;
  final String? zeitText; // "h:mm"
  final double? fixZeitMin;
}

/// Ein Parameter-Wert eines Schritts (Steckbrief- oder fester Rasterwert).
class GenWert {
  const GenWert(this.parameterName, this.wert);
  final String parameterName;
  final String? wert;
}

/// Vollständige Eingabe für ein Artikel-Sheet.
class GenArtikel {
  const GenArtikel({
    required this.artikelnummer,
    required this.bezeichnung,
    required this.kategorieName,
    required this.schritte,
    required this.werteJeSchritt,
    required this.steckbriefJeAnlage,
    this.freitextNotiz,
  });

  final String artikelnummer;
  final String bezeichnung;
  final String kategorieName;
  final List<GenSchritt> schritte;

  /// Werte je Schritt-Nr → Liste (Parametername, Wert).
  final Map<int, List<GenWert>> werteJeSchritt;

  /// Steckbrief-Parameterdefinitionen je Anlagenname (Reihenfolge zählt).
  /// Liste von (Parametername, Einheit?).
  final Map<String, List<(String, String?)>> steckbriefJeAnlage;

  final String? freitextNotiz;
}

/// Erzeugt ein vollständiges Artikel-Sheet (Sheet-XML) aus den App-Daten —
/// ohne Blaupause. Prozessblock, dynamische Maschinenblöcke in
/// Prozess-Reihenfolge (Werte in der Schritt-Spalte), feste Raster für
/// Bratstraße/Dampftunnel, „Sonstige Informationen" und Historie mit 20
/// Formelzeilen. Die Spaltenbreite richtet sich nach der Schrittzahl.
///
/// Die Zellstile werden NICHT neu erzeugt, sondern über die Stil-Indizes
/// der bestehenden styles.xml referenziert (siehe [_Stil]). Diese Indizes
/// stammen aus den vom Import mitgelieferten v3-Vorlagen und sind dort
/// stabil vorhanden.
class ArtikelSheetGenerator {
  const ArtikelSheetGenerator();

  // ── Stil-Indizes aus der vorhandenen styles.xml der v3-Vorlage ────────
  // (geerntet aus einem realen Export — diese Stile existieren dort)
  static const _sKategorie = 54; // farbige Kategoriezeile
  static const _sKopf = 39; // gelber Artikelkopf
  static const _sBlockHeader = 35; // dunkelgrauer Blockkopf (PROZESS, MASCH…)
  static const _sHinweis = 17; // hellgraue Zeile / Parameterzeile
  static const _sLabelGelb = 13; // gelbe Label-Zelle (Abteilung, Menge…)
  static const _sLabelGrau = 16; // graue Label-Zelle (Anlagen)
  static const _sWert = 14; // normale Wertzelle mit Rahmen
  static const _sHistSpalten = 34; // Historie-Spaltenüberschriften
  static const _sFormel = 12; // Historie-Formelzelle

  /// XML-Escape für Textinhalte.
  static String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Spaltenbuchstabe zu 1-basiertem Index (1→A, 2→B … 27→AA).
  static String _colLetter(int col) {
    var c = col;
    final sb = StringBuffer();
    while (c > 0) {
      final rem = (c - 1) % 26;
      sb.write(String.fromCharCode(65 + rem));
      c = (c - 1) ~/ 26;
    }
    return sb.toString().split('').reversed.join();
  }

  // ── Zell-Bausteine ────────────────────────────────────────────────────

  /// Inline-String-Zelle mit optionalem Stil.
  static String _cellStr(int col, int row, String text, {int? stil}) {
    final ref = '${_colLetter(col)}$row';
    final s = stil != null ? ' s="$stil"' : '';
    return '<c r="$ref"$s t="inlineStr"><is><t xml:space="preserve">'
        '${_esc(text)}</t></is></c>';
  }

  /// Zahl-Zelle mit optionalem Stil.
  static String _cellNum(int col, int row, num wert, {int? stil}) {
    final ref = '${_colLetter(col)}$row';
    final s = stil != null ? ' s="$stil"' : '';
    return '<c r="$ref"$s><v>$wert</v></c>';
  }

  /// Formel-Zelle (String-Formel ohne führendes „=").
  static String _cellFormel(int col, int row, String formel, {int? stil}) {
    final ref = '${_colLetter(col)}$row';
    final s = stil != null ? ' s="$stil"' : '';
    return '<c r="$ref"$s><f>${_esc(formel)}</f></c>';
  }

  /// Leere, aber gestylte Zelle (für Rahmen/Hintergrund).
  static String _cellLeer(int col, int row, {int? stil}) {
    final ref = '${_colLetter(col)}$row';
    final s = stil != null ? ' s="$stil"' : '';
    return '<c r="$ref"$s/>';
  }

  /// Überschrift eines Maschinenblocks. Wichtig: `toUpperCase()` lässt das
  /// „ß" in Dart unverändert — aus „Bratstraße" würde „BRATSTRAßE", was
  /// nicht zur Parametergruppe „BRATSTRASSE" der App passt. Deshalb wird
  /// ß hier zu SS aufgelöst.
  static String blockKopfName(String anlage) =>
      anlage.replaceAll('ß', 'ss').replaceAll('ẞ', 'SS').toUpperCase();

  /// Baut das komplette Sheet-XML für einen Artikel. [reiterFarbe] ist die
  /// ARGB-Hex-Reiterfarbe (oder null). Rückgabe: fertige worksheet-XML.
  String generiere(GenArtikel a, {String? reiterFarbe}) {
    final schritte = a.schritte;
    final n = schritte.length;
    // Sheet-Breite: Spalte A (Label) + eine Spalte je Schritt, mindestens
    // 10 Spalten Gesamtbreite (Historie hat 10 Spalten).
    final wertSpalten = n; // B..(1+n)
    final gesamtSpalten = (1 + wertSpalten) < 10 ? 10 : (1 + wertSpalten);

    // Schritt-Nr → Spaltenindex (B=2 …). Zwei aufeinanderfolgende gleiche
    // Anlagen teilen sich einen Block mit mehreren Spalten.
    final spalteVonSchritt = <int, int>{};
    for (var i = 0; i < n; i++) {
      spalteVonSchritt[schritte[i].nr] = 2 + i;
    }

    final rows = <String>[];
    var r = 1;

    // Helfer: baut eine Zeile mit einer Label-Zelle in A und gestylten
    // Leerzellen bis zum rechten Rand — für gemergte Vollbreite-Zeilen.
    String vollzeile(int row, String label, int stil) {
      final b = StringBuffer(_cellStr(1, row, label, stil: stil));
      for (var c = 2; c <= gesamtSpalten; c++) {
        b.write(_cellLeer(c, row, stil: stil));
      }
      return '<row r="$row">$b</row>';
    }

    // Helfer: Blockkopf über die gesamte Sheet-Breite (gemerged).
    final merges = <String>[];
    void blockKopf(String text) {
      rows.add(vollzeile(r, text, _sBlockHeader));
      merges.add('${_colLetter(1)}$r:${_colLetter(gesamtSpalten)}$r');
      r++;
    }

    // ── Kategoriezeile (2 Zeilen, gemerged, farbig) ─────────────────────
    r = 2;
    rows.add(vollzeile(2, a.kategorieName, _sKategorie));
    merges.add('A2:${_colLetter(gesamtSpalten)}2');
    rows.add(vollzeile(3, '', _sKategorie));
    merges.add('A3:${_colLetter(gesamtSpalten)}3');

    // ── Artikelkopf (Z5 Label, Z6 Nr — Bezeichnung) ─────────────────────
    rows.add(vollzeile(5, 'Artikelbezeichnung', _sBlockHeader));
    merges.add('A5:${_colLetter(gesamtSpalten)}5');
    rows.add(vollzeile(6, '${a.artikelnummer} — ${a.bezeichnung}', _sKopf));
    merges.add('A6:${_colLetter(gesamtSpalten)}6');

    // ── PROZESSSCHRITTE ─────────────────────────────────────────────────
    r = 8;
    blockKopf('PROZESSSCHRITTE');
    // r ist jetzt 9 → Hinweiszeile
    rows.add(vollzeile(9, 'Eine Spalte pro Prozessschritt', _sHinweis));
    merges.add('A9:${_colLetter(gesamtSpalten)}9');
    r = 10;
    // Schritt-Nummern-Zeile
    final nummernZeile = StringBuffer();
    for (var i = 0; i < n; i++) {
      nummernZeile.write(_cellStr(2 + i, 10, 'Schritt ${schritte[i].nr}'));
    }
    rows.add('<row r="10">$nummernZeile</row>');
    r = 11;

    // Prozess-Felder
    String? zeit(GenSchritt s) => s.zeitText;
    final felder = <(String, int, String? Function(GenSchritt))>[
      ('Abteilung', _sLabelGelb, (s) => s.abteilung),
      ('Prozessschritt', _sLabelGelb, (s) => s.prozessschritt),
      ('Anlagen', _sLabelGrau, (s) => s.anlage),
      ('Personen', _sLabelGelb, (s) => s.personen?.toString()),
      ('Menge (kg)', _sLabelGelb,
          (s) => s.mengeKg == null ? null : _zahl(s.mengeKg!)),
      ('Zeit (hh:mm)', _sLabelGelb, zeit),
      ('Fixe Zeit (min)', _sLabelGelb,
          (s) => s.fixZeitMin == null ? null : _zahl(s.fixZeitMin!)),
    ];
    for (final (label, stil, getter) in felder) {
      final cells = StringBuffer(_cellStr(1, r, label, stil: stil));
      for (var i = 0; i < n; i++) {
        final v = getter(schritte[i]);
        if (v == null || v.isEmpty) {
          cells.write(_cellLeer(2 + i, r, stil: _sWert));
        } else {
          final num_ = double.tryParse(v.replaceAll(',', '.'));
          // Menge/Fixzeit als Zahl, Rest als Text.
          if (num_ != null &&
              (label.startsWith('Menge') || label.startsWith('Fixe'))) {
            cells.write(_cellNum(2 + i, r, num_, stil: _sWert));
          } else {
            cells.write(_cellStr(2 + i, r, v, stil: _sWert));
          }
        }
      }
      rows.add('<row r="$r">$cells</row>');
      r++;
    }

    // ── MASCHINENEINSTELLUNGEN ──────────────────────────────────────────
    blockKopf('MASCHINENEINSTELLUNGEN');
    // Freitext-Zeile (bleibt für Sonderfälle) — Notiz, falls vorhanden,
    // in die erste Wert-Spalte.
    final notiz = a.freitextNotiz ?? '';
    final freitextCells = StringBuffer(
      _cellStr(1, r, 'Maschineneinstellungen', stil: _sHinweis),
    );
    for (var c = 2; c <= gesamtSpalten; c++) {
      if (c == 2 && notiz.isNotEmpty) {
        freitextCells.write(_cellStr(c, r, notiz, stil: _sHinweis));
      } else {
        freitextCells.write(_cellLeer(c, r, stil: _sHinweis));
      }
    }
    rows.add('<row r="$r">$freitextCells</row>');
    r++;

    // Maschinenblöcke in PROZESS-Reihenfolge; gleiche Anlage in Folge
    // teilt sich einen Block (mehrere Wert-Spalten).
    final bloecke = <({String anlage, List<int> schrittNrs})>[];
    for (final s in schritte) {
      final anlage = s.anlage;
      if (anlage == null || anlage.isEmpty) continue;
      if (bloecke.isNotEmpty && bloecke.last.anlage == anlage) {
        bloecke.last.schrittNrs.add(s.nr);
      } else {
        bloecke.add((anlage: anlage, schrittNrs: [s.nr]));
      }
    }

    for (final block in bloecke) {
      blockKopf(blockKopfName(block.anlage));

      // Die Zeilen (Parameternamen) und Werte eines Blocks kommen
      // AUSSCHLIESSLICH aus den Parametern der Schritte dieses Blocks —
      // so überlagern sich gleichnamige Parameter verschiedener Anlagen
      // (z.B. „Platte Unten 1" bei Bratstraße UND Heißluftofen) nie.
      // Zusätzlich werden leere Steckbrief-Defs der Anlage als Pflege-
      // zeilen ergänzt.
      final zeilenNamen = <String>[];
      final gesehen = <String>{};

      // Katalog-Parameternamen dieser Anlage (klein) — sie dürfen auch
      // leer als Pflegezeile erscheinen. Alles andere muss einen Wert
      // haben, sonst ist es Altlast und wird weggelassen (Selbstheilung:
      // leerer Müll verschwindet beim nächsten Export dauerhaft).
      final defs = a.steckbriefJeAnlage[block.anlage] ??
          const <(String, String?)>[];
      final katalogNamen = <String>{for (final d in defs) d.$1.toLowerCase()};

      // (1) Steckbrief-Defs der Anlage (auch leere → Pflegezeilen).
      for (final def in defs) {
        final einheit = def.$2;
        final label = (einheit == null || einheit.isEmpty)
            ? def.$1
            : '${def.$1} ($einheit)';
        if (gesehen.add(def.$1.toLowerCase())) zeilenNamen.add(label);
      }
      // (2) Tatsächliche Parameter der Schritte dieses Blocks. Ein leerer
      //     Parameter wird nur übernommen, wenn er im Katalog steht;
      //     befüllte immer (auch wenn Katalog ihn (noch) nicht kennt).
      for (final nr in block.schrittNrs) {
        for (final w in a.werteJeSchritt[nr] ?? const <GenWert>[]) {
          final key = w.parameterName.toLowerCase();
          final hatWert = (w.wert ?? '').isNotEmpty;
          if (!hatWert && !katalogNamen.contains(key)) continue;
          if (gesehen.add(key)) zeilenNamen.add(w.parameterName);
        }
      }

      if (zeilenNamen.isEmpty) {
        rows.add(vollzeile(r, '(keine Parameter hinterlegt)', _sHinweis));
        r++;
        continue;
      }

      for (final zeile in zeilenNamen) {
        final cells = StringBuffer(_cellStr(1, r, zeile, stil: _sHinweis));
        for (var c = 2; c <= gesamtSpalten; c++) {
          // Wert nur aus dem Schritt, dessen Spalte c ist UND der zu
          // diesem Block gehört. Damit bleibt jeder Wert in seiner Anlage.
          String? wert;
          for (final nr in block.schrittNrs) {
            if (spalteVonSchritt[nr] == c) {
              wert = _wertFuerSchritt(a, nr, zeile);
              break;
            }
          }
          if (wert == null || wert.isEmpty) {
            cells.write(_cellLeer(c, r, stil: _sWert));
          } else {
            final num_ = double.tryParse(wert.replaceAll(',', '.'));
            cells.write(
              num_ != null
                  ? _cellNum(c, r, num_, stil: _sWert)
                  : _cellStr(c, r, wert, stil: _sWert),
            );
          }
        }
        rows.add('<row r="$r">$cells</row>');
        r++;
      }
    }

    // ── Sonstige Informationen ──────────────────────────────────────────
    blockKopf('Sonstige Informationen');
    r++; // eine Leerzeile

    // ── HISTORISCHE DATEN ───────────────────────────────────────────────
    blockKopf('HISTORISCHE DATEN');
    const histHinweis =
        'Jede produzierte Charge als eine Zeile — die App mittelt daraus.';
    rows.add(vollzeile(r, histHinweis, _sHinweis));
    r++;
    // Spaltenüberschriften
    const histSpalten = [
      'Datum', 'Kg Rohware', 'Kg Fertigware', 'Verlust %', 'Startzeit',
      'Endzeit', 'Produktionszeit', 'kg/h roh', 'kg/h gegart', 'Notizen',
    ];
    final histKopf = StringBuffer();
    for (var i = 0; i < histSpalten.length; i++) {
      histKopf.write(_cellStr(1 + i, r, histSpalten[i], stil: _sHistSpalten));
    }
    rows.add('<row r="$r">$histKopf</row>');
    final headerRow = r;
    r++;
    // 20 Formel-Datenzeilen (Verlust, Produktionszeit, kg/h automatisch).
    for (var k = 0; k < 20; k++) {
      final rr = headerRow + 1 + k;
      final fVerlust = 'IF(OR(B$rr="",C$rr=""),"",1-C$rr/B$rr)';
      final fZeit = 'IF(OR(E$rr="",F$rr=""),"",F$rr-E$rr)';
      final fRoh = 'IF(OR(B$rr="",G$rr=""),"",B$rr/(G$rr*24))';
      final fGegart = 'IF(OR(C$rr="",G$rr=""),"",C$rr/(G$rr*24))';
      final cells = StringBuffer()
        ..write(_cellLeer(1, rr, stil: _sFormel)) // Datum
        ..write(_cellLeer(2, rr, stil: _sFormel)) // Kg Rohware
        ..write(_cellLeer(3, rr, stil: _sFormel)) // Kg Fertigware
        ..write(_cellFormel(4, rr, fVerlust, stil: _sFormel)) // Verlust
        ..write(_cellLeer(5, rr, stil: _sFormel)) // Startzeit
        ..write(_cellLeer(6, rr, stil: _sFormel)) // Endzeit
        ..write(_cellFormel(7, rr, fZeit, stil: _sFormel)) // Produktionszeit
        ..write(_cellFormel(8, rr, fRoh, stil: _sFormel)) // kg/h roh
        ..write(_cellFormel(9, rr, fGegart, stil: _sFormel)) // kg/h gegart
        ..write(_cellLeer(10, rr, stil: _sFormel)); // Notizen
      rows.add('<row r="$rr">$cells</row>');
    }
    final letzteZeile = headerRow + 20;

    // ── Spaltenbreiten ──────────────────────────────────────────────────
    final cols = StringBuffer('<cols>')
      ..write('<col min="1" max="1" width="30" customWidth="1"/>')
      ..write('<col min="2" max="$gesamtSpalten" width="18" customWidth="1"/>')
      ..write('</cols>');

    // ── Reiterfarbe ─────────────────────────────────────────────────────
    final sheetPr = reiterFarbe != null
        ? '<sheetPr><tabColor rgb="$reiterFarbe"/></sheetPr>'
        : '';

    // ── mergeCells ──────────────────────────────────────────────────────
    final mergeXml = merges.isEmpty
        ? ''
        : '<mergeCells count="${merges.length}">'
            '${merges.map((m) => '<mergeCell ref="$m"/>').join()}'
            '</mergeCells>';

    final dim = 'A1:${_colLetter(gesamtSpalten)}$letzteZeile';

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main">'
        '$sheetPr'
        '<dimension ref="$dim"/>'
        '$cols'
        '<sheetData>${rows.join()}</sheetData>'
        '$mergeXml'
        '</worksheet>';
  }

  /// Sucht den Wert eines Parameters innerhalb der Parameter GENAU dieses
  /// einen Schritts. Weil nur die Werte des jeweiligen Schritts durchsucht
  /// werden, können gleichnamige Parameter verschiedener Anlagen (z.B.
  /// „Platte Unten 1" bei Bratstraße und Heißluftofen) nicht kollidieren.
  /// Kommt derselbe Name im Schritt mehrfach vor (Altlast aus früheren
  /// Zyklen), wird der erste BEFÜLLTE Wert bevorzugt — so geht kein Wert
  /// verloren, falls eine leere Dublette vor der befüllten steht.
  static String? _wertFuerSchritt(
    GenArtikel a,
    int schrittNr,
    String zeileLabel,
  ) {
    final werte = a.werteJeSchritt[schrittNr];
    if (werte == null) return null;
    // zeileLabel kann "Name (Einheit)" sein → auf den reinen Namen matchen.
    final reinerName = zeileLabel.contains(' (')
        ? zeileLabel.substring(0, zeileLabel.lastIndexOf(' ('))
        : zeileLabel;
    final ziel = reinerName.toLowerCase();
    final zielVoll = zeileLabel.toLowerCase();
    String? ersterTreffer;
    for (final w in werte) {
      final name = w.parameterName.toLowerCase();
      if (name == ziel || name == zielVoll) {
        // Befüllten Wert sofort nehmen; leeren nur als Fallback merken.
        if ((w.wert ?? '').isNotEmpty) return w.wert;
        ersterTreffer ??= w.wert;
      }
    }
    return ersterTreffer;
  }

  static String _zahl(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}


