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

/// Zellstil-Indizes (Positionen in `styles.xml`), die der Generator
/// verwendet. Sie werden aus einem bestehenden Sheet derselben
/// Arbeitsmappe geerntet, damit generierte Sheets exakt wie die
/// vorhandenen aussehen — inklusive Datums- und Zeitformaten in der
/// Historie. Die Standardwerte dienen nur als Notnagel, falls in der
/// Mappe kein Referenz-Sheet gefunden wird.
class GenStile {
  const GenStile({
    this.kategorie = 54,
    this.kopfLabel = 35,
    this.kopf = 39,
    this.prozessHeader = 35,
    this.blockHeader = 35,
    this.hinweis = 17,
    this.labelGelb = 13,
    this.labelGrau = 16,
    this.wert = 14,
    this.histHeader = 34,
    this.histDaten = const [12, 12, 12, 12, 12, 12, 12, 12, 12, 12],
  });

  /// Farbige Kategoriezeile (Z2).
  final int kategorie;

  /// Label „Artikelbezeichnung" (Z5).
  final int kopfLabel;

  /// Artikelkopf „Nr — Bezeichnung" (Z6).
  final int kopf;

  /// Abschnittskopf „PROZESSSCHRITTE".
  final int prozessHeader;

  /// Dunkler Blockkopf (MASCHINENEINSTELLUNGEN, Maschinenblöcke).
  final int blockHeader;

  /// Helle Hinweis-/Parameterzeile.
  final int hinweis;

  /// Gelbe Label-Zelle (Abteilung, Menge …).
  final int labelGelb;

  /// Graue Label-Zelle (Anlagen).
  final int labelGrau;

  /// Normale Wertzelle mit Rahmen.
  final int wert;

  /// Historie-Spaltenüberschriften.
  final int histHeader;

  /// Historie-Datenzeile, ein Stil je Spalte A…J. Entscheidend für
  /// Datums- und Zeitformate: ohne die richtigen Stile erscheint das
  /// Datum als Zahl (46225) und Uhrzeiten als Tagesbruchteile (0,27).
  final List<int> histDaten;
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

  // Stil-Indizes: werden zur Laufzeit aus einem vorhandenen Sheet der
  // Arbeitsmappe geerntet (siehe [GenStile]). Hart kodierte Indizes waren
  // nicht tragfähig — sie verschieben sich zwischen Vorlagen-Generationen,
  // wodurch generierte Sheets anders aussahen als bestehende und die
  // Historie ihr Datums-/Zeitformat verlor.

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
  String generiere(
    GenArtikel a, {
    String? reiterFarbe,
    GenStile stile = const GenStile(),
  }) {
    final st = stile;
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
      rows.add(vollzeile(r, text, st.blockHeader));
      merges.add('${_colLetter(1)}$r:${_colLetter(gesamtSpalten)}$r');
      r++;
    }

    // ── Kategoriezeile (2 Zeilen, gemerged, farbig) ─────────────────────
    r = 2;
    rows.add(vollzeile(2, a.kategorieName, st.kategorie));
    merges.add('A2:${_colLetter(gesamtSpalten)}2');
    rows.add(vollzeile(3, '', st.kategorie));
    merges.add('A3:${_colLetter(gesamtSpalten)}3');

    // ── Artikelkopf (Z5 Label, Z6 Nr — Bezeichnung) ─────────────────────
    rows.add(vollzeile(5, 'Artikelbezeichnung', st.kopfLabel));
    merges.add('A5:${_colLetter(gesamtSpalten)}5');
    rows.add(vollzeile(6, '${a.artikelnummer} — ${a.bezeichnung}', st.kopf));
    merges.add('A6:${_colLetter(gesamtSpalten)}6');

    // ── PROZESSSCHRITTE ─────────────────────────────────────────────────
    r = 8;
    // Eigener Stil, damit der Prozess-Abschnitt genauso aussieht wie in
    // den bestehenden Sheets.
    rows.add(vollzeile(r, 'PROZESSSCHRITTE', st.prozessHeader));
    merges.add('${_colLetter(1)}$r:${_colLetter(gesamtSpalten)}$r');
    r++;
    // r ist jetzt 9 → Hinweiszeile
    rows.add(vollzeile(9, 'Eine Spalte pro Prozessschritt', st.hinweis));
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
      ('Abteilung', st.labelGelb, (s) => s.abteilung),
      ('Prozessschritt', st.labelGelb, (s) => s.prozessschritt),
      ('Anlagen', st.labelGrau, (s) => s.anlage),
      ('Personen', st.labelGelb, (s) => s.personen?.toString()),
      ('Menge (kg)', st.labelGelb,
          (s) => s.mengeKg == null ? null : _zahl(s.mengeKg!)),
      ('Zeit (hh:mm)', st.labelGelb, zeit),
      ('Fixe Zeit (min)', st.labelGelb,
          (s) => s.fixZeitMin == null ? null : _zahl(s.fixZeitMin!)),
    ];
    for (final (label, stil, getter) in felder) {
      final cells = StringBuffer(_cellStr(1, r, label, stil: stil));
      for (var i = 0; i < n; i++) {
        final v = getter(schritte[i]);
        if (v == null || v.isEmpty) {
          cells.write(_cellLeer(2 + i, r, stil: st.wert));
        } else {
          final num_ = double.tryParse(v.replaceAll(',', '.'));
          // Menge/Fixzeit als Zahl, Rest als Text.
          if (num_ != null &&
              (label.startsWith('Menge') || label.startsWith('Fixe'))) {
            cells.write(_cellNum(2 + i, r, num_, stil: st.wert));
          } else {
            cells.write(_cellStr(2 + i, r, v, stil: st.wert));
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
      _cellStr(1, r, 'Maschineneinstellungen', stil: st.hinweis),
    );
    for (var c = 2; c <= gesamtSpalten; c++) {
      if (c == 2 && notiz.isNotEmpty) {
        freitextCells.write(_cellStr(c, r, notiz, stil: st.hinweis));
      } else {
        freitextCells.write(_cellLeer(c, r, stil: st.hinweis));
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
        rows.add(vollzeile(r, '(keine Parameter hinterlegt)', st.hinweis));
        r++;
        continue;
      }

      for (final zeile in zeilenNamen) {
        final cells = StringBuffer(_cellStr(1, r, zeile, stil: st.hinweis));
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
            cells.write(_cellLeer(c, r, stil: st.wert));
          } else {
            final num_ = double.tryParse(wert.replaceAll(',', '.'));
            cells.write(
              num_ != null
                  ? _cellNum(c, r, num_, stil: st.wert)
                  : _cellStr(c, r, wert, stil: st.wert),
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
    rows.add(vollzeile(r, histHinweis, st.hinweis));
    r++;
    // Spaltenüberschriften
    const histSpalten = [
      'Datum', 'Kg Rohware', 'Kg Fertigware', 'Verlust %', 'Startzeit',
      'Endzeit', 'Produktionszeit', 'kg/h roh', 'kg/h gegart', 'Notizen',
    ];
    final histKopf = StringBuffer();
    for (var i = 0; i < histSpalten.length; i++) {
      histKopf.write(_cellStr(1 + i, r, histSpalten[i], stil: st.histHeader));
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
      // Stil je Spalte — trägt das Zahlenformat: A Datum, E/F Uhrzeit,
      // G Dauer, D Prozent. Ohne diese Stile zeigt Excel das Datum als
      // fortlaufende Zahl und Uhrzeiten als Tagesbruchteile.
      int hs(int spalte) => spalte - 1 < st.histDaten.length
          ? st.histDaten[spalte - 1]
          : st.histDaten.last;
      final cells = StringBuffer()
        ..write(_cellLeer(1, rr, stil: hs(1))) // Datum
        ..write(_cellLeer(2, rr, stil: hs(2))) // Kg Rohware
        ..write(_cellLeer(3, rr, stil: hs(3))) // Kg Fertigware
        ..write(_cellFormel(4, rr, fVerlust, stil: hs(4))) // Verlust
        ..write(_cellLeer(5, rr, stil: hs(5))) // Startzeit
        ..write(_cellLeer(6, rr, stil: hs(6))) // Endzeit
        ..write(_cellFormel(7, rr, fZeit, stil: hs(7))) // Produktionszeit
        ..write(_cellFormel(8, rr, fRoh, stil: hs(8))) // kg/h roh
        ..write(_cellFormel(9, rr, fGegart, stil: hs(9))) // kg/h gegart
        ..write(_cellLeer(10, rr, stil: hs(10))); // Notizen
      rows.add('<row r="$rr">$cells</row>');
    }
    final letzteZeile = headerRow + 20;

    // ── Spaltenbreiten ──────────────────────────────────────────────────
    final cols = StringBuffer('<cols>')
      ..write('<col min="1" max="1" width="28" customWidth="1"/>')
      ..write('<col min="2" max="$gesamtSpalten" width="20" customWidth="1"/>')
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


