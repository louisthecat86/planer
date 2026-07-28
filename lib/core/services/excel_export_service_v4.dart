import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

import '../constants/abteilungen.dart';
import '../database/database.dart';

/// Ergebnis eines Exports.
class ExportResultV4 {
  const ExportResultV4({
    required this.bytes,
    required this.vorschlagDateiname,
    required this.anzahlArtikel,
    required this.anzahlSchritte,
    required this.anzahlParameter,
    required this.warnungen,
  });

  final Uint8List bytes;
  final String vorschlagDateiname;
  final int anzahlArtikel;
  final int anzahlSchritte;
  final int anzahlParameter;
  final List<String> warnungen;
}

/// Baut die Stammdaten-Arbeitsmappe **vollständig neu** aus dem aktuellen
/// Datenbankstand.
///
/// Unterschied zur Vorgängerversion: Es gibt keine Kategorie-Blaupausen mehr.
/// Früher war jedes Artikelblatt die Kopie einer Vorlage („Hackprodukte roh",
/// „Brühwurst" …), und nur die dort vorgestanzten Maschinenblöcke konnten
/// Werte aufnehmen. Fügte man einem Artikel eine Anlage hinzu, die seine
/// Kategorie-Blaupause nicht kannte — etwa eine Bratstraße bei einem
/// Hackprodukt —, hatten deren Parameter im Blatt keinen Platz und fielen
/// beim Export lautlos weg.
///
/// Jetzt hat jeder Artikel denselben Aufbau, und die Maschinenblöcke
/// entstehen aus seinen tatsächlichen Prozessschritten. Was in der App
/// steht, steht damit auch in der Excel — unabhängig von der Kategorie.
///
/// Das Format bleibt exakt das, was `ExcelImportServiceV3` liest:
/// Artikelkopf in Zeile 6, die Label-Zeilen der Schritte, Blocküberschriften
/// in Spalte A und die Marker „ZUSÄTZLICHE PARAMETER", „Sonstige
/// Informationen" und „HISTORISCHE DATEN". Der Rundlauf App ⇄ Excel bleibt
/// dadurch verlustfrei.
class ExcelExportServiceV4 {
  ExcelExportServiceV4(this._db);

  final AppDatabase _db;

  /// Gruppe der Steckbrief-/Freitextwerte ohne eigene Anlagen-Gruppe.
  static const String kSteckbriefGruppe = 'MASCHINENEINSTELLUNGEN';

  static const String _markerCustom = 'ZUSÄTZLICHE PARAMETER';
  static const String _markerSonstige = 'Sonstige Informationen';
  static const String _markerHistorie = 'HISTORISCHE DATEN';

  /// Maximale Anzahl Schritt-Spalten (B..K) — wie vom Import erwartet.
  static const int _maxSchritte = 10;

  static const Map<String, String> _produktgruppeLabels = {
    'bruehwurst': 'Brühwurst',
    'rohwurst': 'Rohwurst',
    'kochpoekelware': 'Kochpökelware',
    'rohpoekelware': 'Rohpökelware',
    'aufschnitt': 'Aufschnitt',
    'bratstrasse_natur': 'Bratstraßenartikel Natur',
    'bratstrasse_paniert': 'Bratstraßenartikel paniert',
    'hackprodukt_gegart': 'Hackprodukte gegart',
    'hackprodukt_roh': 'Hackprodukte roh',
    'braten': 'Braten',
    'sous_vide': 'Sous Vide gegarte Produkte',
    'angebratene_bruehwurst': 'Angebratene Brühwürste',
  };

  // ══════════════════════════════════════════════════════════════════
  // Stile
  // ══════════════════════════════════════════════════════════════════

  static CellStyle get _titel => CellStyle(
        bold: true,
        fontSize: 14,
        backgroundColorHex: ExcelColor.fromHexString('FF4A9CA6'),
        fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
      );

  static CellStyle get _sektion => CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FF455A64'),
        fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
      );

  static CellStyle get _blockKopf => CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FF607D8B'),
        fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
      );

  static CellStyle get _labelStil => CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FFFFF9C4'),
      );

  static CellStyle get _kopfStil => CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FFE8EAF6'),
      );

  static CellStyle get _hinweisStil => CellStyle(
        italic: true,
        fontColorHex: ExcelColor.fromHexString('FF757575'),
      );

  static CellStyle get _artikelStil => CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FFFFFDE7'),
      );

  // ══════════════════════════════════════════════════════════════════
  // Export
  // ══════════════════════════════════════════════════════════════════

  Future<ExportResultV4> export() async {
    final warnungen = <String>[];

    final artikel = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.artikelnummer)]))
        .get();

    final alleSchritte = await (_db.select(_db.productSteps)
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
        .get();
    final schritteVonArtikel = <String, List<ProductStep>>{};
    for (final s in alleSchritte) {
      schritteVonArtikel.putIfAbsent(s.productId, () => []).add(s);
    }

    final alleParams = await (_db.select(_db.productStepParameters)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.reihenfolge)]))
        .get();
    final paramsVonSchritt = <String, List<ProductStepParameter>>{};
    for (final p in alleParams) {
      paramsVonSchritt.putIfAbsent(p.stepId, () => []).add(p);
    }

    final maschinen = await (_db.select(_db.machines)
          ..where((m) => m.deletedAt.isNull())
          ..orderBy([(m) => OrderingTerm.asc(m.name)]))
        .get();
    final maschineVonId = {for (final m in maschinen) m.id: m};

    final defs = await (_db.select(_db.machineParameterDefs)
          ..where((d) => d.deletedAt.isNull())
          ..orderBy([(d) => OrderingTerm.asc(d.sortierung)]))
        .get();

    final historie = await (_db.select(_db.productionHistory)
          ..where((h) => h.deletedAt.isNull())
          ..orderBy([(h) => OrderingTerm.asc(h.datum)]))
        .get();
    final historieVonArtikel = <String, List<ProductionHistoryData>>{};
    for (final h in historie) {
      historieVonArtikel.putIfAbsent(h.productId, () => []).add(h);
    }

    final excel = Excel.createExcel();

    var schritteGesamt = 0;
    var parameterGesamt = 0;

    _baueUebersicht(
      excel,
      artikel: artikel,
      schritteVonArtikel: schritteVonArtikel,
      historieVonArtikel: historieVonArtikel,
    );
    _baueAnlagenKatalog(excel, maschinen);
    _baueSteckbriefe(excel, maschinen, defs);

    final belegteNamen = <String>{
      'Übersicht',
      'Anlagen-Katalog',
      'Maschinen-Steckbriefe',
    };

    for (final a in artikel) {
      final schritte = schritteVonArtikel[a.id] ?? const <ProductStep>[];
      if (schritte.length > _maxSchritte) {
        warnungen.add(
          '${a.artikelnummer}: ${schritte.length} Schritte — nur die ersten '
          '$_maxSchritte passen in das Blatt.',
        );
      }
      final blattName = _eindeutigerBlattName(a.artikelnummer, belegteNamen);

      final ergebnis = _baueArtikelblatt(
        excel,
        blattName: blattName,
        artikel: a,
        schritte: schritte.take(_maxSchritte).toList(),
        paramsVonSchritt: paramsVonSchritt,
        maschineVonId: maschineVonId,
        historie: historieVonArtikel[a.id] ?? const <ProductionHistoryData>[],
      );
      schritteGesamt += ergebnis.schritte;
      parameterGesamt += ergebnis.parameter;
    }

    // Das von der Bibliothek angelegte Standardblatt entfernen.
    try {
      excel.delete('Sheet1');
    } catch (_) {
      // Nicht kritisch.
    }

    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('Die Arbeitsmappe konnte nicht erzeugt werden.');
    }

    debugPrint(
      '[EXPORT] ${artikel.length} Artikel · $schritteGesamt Schritte · '
      '$parameterGesamt Parameter',
    );

    return ExportResultV4(
      bytes: Uint8List.fromList(bytes),
      vorschlagDateiname: _dateiname(),
      anzahlArtikel: artikel.length,
      anzahlSchritte: schritteGesamt,
      anzahlParameter: parameterGesamt,
      warnungen: warnungen,
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // Übersicht / Kataloge
  // ══════════════════════════════════════════════════════════════════

  void _baueUebersicht(
    Excel excel, {
    required List<Product> artikel,
    required Map<String, List<ProductStep>> schritteVonArtikel,
    required Map<String, List<ProductionHistoryData>> historieVonArtikel,
  }) {
    final s = excel['Übersicht'];
    _setz(s, 0, 0, 'Produkt-Katalog', _titel);
    _setz(
      s,
      0,
      1,
      'Von der App erzeugt. Je Artikel ein eigenes Blatt — Änderungen dort '
      'werden beim Import wieder übernommen.',
      _hinweisStil,
    );

    const kopf = [
      'Artikelnummer',
      'Bezeichnung',
      'Produktgruppe',
      'Schritte',
      'Produktionen',
      'Blatt',
    ];
    for (var c = 0; c < kopf.length; c++) {
      _setz(s, c, 3, kopf[c], _kopfStil);
    }

    var row = 4;
    for (final a in artikel) {
      _setz(s, 0, row, a.artikelnummer);
      _setz(s, 1, row, a.artikelbezeichnung);
      _setz(
        s,
        2,
        row,
        _produktgruppeLabels[a.produktgruppe] ?? (a.produktgruppe ?? ''),
      );
      _setzZahl(
        s,
        3,
        row,
        (schritteVonArtikel[a.id] ?? const <ProductStep>[]).length,
      );
      _setzZahl(
        s,
        4,
        row,
        (historieVonArtikel[a.id] ?? const <ProductionHistoryData>[]).length,
      );
      _setz(s, 5, row, a.artikelnummer);
      row++;
    }
    s.setColumnWidth(1, 42);
    s.setColumnWidth(2, 24);
  }

  void _baueAnlagenKatalog(Excel excel, List<Machine> maschinen) {
    final s = excel['Anlagen-Katalog'];
    _setz(s, 0, 0, 'Anlagen-Katalog', _titel);
    const kopf = ['Anlage', 'Abteilung', 'Kapazität (Min/Tag)', 'Hinweis'];
    for (var c = 0; c < kopf.length; c++) {
      _setz(s, c, 2, kopf[c], _kopfStil);
    }
    var row = 3;
    for (final m in maschinen) {
      _setz(s, 0, row, m.name);
      _setz(s, 1, row, _abteilungsName(m.abteilung));
      _setzZahl(s, 2, row, m.kapazitaetMinutenProTag);
      _setz(s, 3, row, m.eignungHinweis ?? '');
      row++;
    }
    s.setColumnWidth(0, 26);
    s.setColumnWidth(1, 20);
    s.setColumnWidth(3, 34);
  }

  void _baueSteckbriefe(
    Excel excel,
    List<Machine> maschinen,
    List<MachineParameterDef> defs,
  ) {
    final s = excel['Maschinen-Steckbriefe'];
    _setz(s, 0, 0, 'Maschinen-Steckbriefe', _titel);
    _setz(
      s,
      0,
      1,
      'Welche Werte an welcher Anlage gepflegt werden. Nur zur Ansicht — '
      'gepflegt wird der Katalog in der App.',
      _hinweisStil,
    );
    const kopf = ['Anlage', 'Parameter', 'Einheit'];
    for (var c = 0; c < kopf.length; c++) {
      _setz(s, c, 3, kopf[c], _kopfStil);
    }
    final nameVonId = {for (final m in maschinen) m.id: m.name};
    var row = 4;
    for (final d in defs) {
      final anlage = nameVonId[d.maschineId];
      if (anlage == null) continue;
      _setz(s, 0, row, anlage);
      _setz(s, 1, row, d.parameterName);
      _setz(s, 2, row, d.einheit ?? '');
      row++;
    }
    s.setColumnWidth(0, 26);
    s.setColumnWidth(1, 28);
  }

  // ══════════════════════════════════════════════════════════════════
  // Artikelblatt — einheitlicher Aufbau, dynamische Maschinenblöcke
  // ══════════════════════════════════════════════════════════════════

  ({int schritte, int parameter}) _baueArtikelblatt(
    Excel excel, {
    required String blattName,
    required Product artikel,
    required List<ProductStep> schritte,
    required Map<String, List<ProductStepParameter>> paramsVonSchritt,
    required Map<String, Machine> maschineVonId,
    required List<ProductionHistoryData> historie,
  }) {
    final s = excel[blattName];

    // Spalte je Schritt: 1 = B, 2 = C … Der Import liest die Werte über
    // genau diese Spaltennummer zurück (sie wird dort zur `reihenfolge`).
    final spalteVonSchritt = <String, int>{};
    for (var i = 0; i < schritte.length; i++) {
      spalteVonSchritt[schritte[i].id] = i + 1;
    }

    // ── Kopf ──────────────────────────────────────────────────────────
    _setz(
      s,
      0,
      1,
      _produktgruppeLabels[artikel.produktgruppe] ??
          (artikel.produktgruppe ?? 'Artikel'),
      _titel,
    );
    _setz(
      s,
      0,
      2,
      'Von der App erzeugt. Werte hier ändern und die Datei wieder '
      'importieren — die App übernimmt sie.',
      _hinweisStil,
    );
    _setz(s, 0, 4, 'Artikelbezeichnung', _sektion);
    // Zeile 6 (Index 5): „NR — Bezeichnung" — genau dort sucht der Import
    // den Artikelkopf.
    _setz(
      s,
      0,
      5,
      '${artikel.artikelnummer} — ${artikel.artikelbezeichnung}',
      _artikelStil,
    );

    // ── Prozessschritte ───────────────────────────────────────────────
    _setz(s, 0, 7, 'PROZESSSCHRITTE', _sektion);
    _setz(
      s,
      0,
      8,
      'Eine Spalte pro Prozessschritt — von links nach rechts in der '
      'Reihenfolge der Produktion.',
      _hinweisStil,
    );
    for (var i = 0; i < schritte.length; i++) {
      _setz(s, i + 1, 9, 'Schritt ${i + 1}', _kopfStil);
    }

    const labels = [
      'Abteilung',
      'Prozessschritt',
      'Anlagen',
      'Personen',
      'Menge (kg)',
      'Zeit (hh:mm)',
      'Fixe Zeit (min)',
    ];
    for (var i = 0; i < labels.length; i++) {
      _setz(s, 0, 10 + i, labels[i], _labelStil);
    }

    for (var i = 0; i < schritte.length; i++) {
      final st = schritte[i];
      final col = i + 1;
      final maschine =
          st.maschineId != null ? maschineVonId[st.maschineId] : null;
      final anlagenName = maschine?.name ?? st.maschine ?? '';

      _setz(s, col, 10, _abteilungsName(st.abteilung));
      _setz(s, col, 11, st.prozessschritt ?? '');
      _setz(s, col, 12, anlagenName);
      if (st.basisMitarbeiter > 0) _setzZahl(s, col, 13, st.basisMitarbeiter);
      if (st.basisMengeKg > 0) _setzZahl(s, col, 14, st.basisMengeKg);
      if (st.basisDauerMinuten > 0) {
        _setz(s, col, 15, _hhmm(st.basisDauerMinuten));
      }
      if ((st.fixZeitMinuten ?? 0) > 0) {
        _setzZahl(s, col, 16, st.fixZeitMinuten!);
      }
    }

    var row = 18;
    var parameterGesamt = 0;

    // ── Maschinenblöcke — dynamisch aus den Schritten ─────────────────
    //
    // Je Parametergruppe ein Block. Die Blocküberschrift ist der
    // Gruppenname in Großbuchstaben; genau daran erkennt der Import den
    // Block wieder und ordnet ihn der Anlage zu. Ein Parametername
    // ergibt eine Zeile, die Werte der Schritte stehen nebeneinander in
    // ihren Spalten.
    final gruppen = <String, List<String>>{}; // Gruppe → Parameternamen
    final werte = <String, Map<int, String>>{}; // "Gruppe|Name" → col→Wert

    for (final st in schritte) {
      final col = spalteVonSchritt[st.id]!;
      for (final p
          in paramsVonSchritt[st.id] ?? const <ProductStepParameter>[]) {
        if (p.istCustom) continue;
        final wert = (p.wert ?? '').trim();
        if (wert.isEmpty) continue;
        final gruppe = p.parameterGruppe.trim().isEmpty
            ? kSteckbriefGruppe
            : p.parameterGruppe.trim();
        final namen = gruppen.putIfAbsent(gruppe, () => []);
        if (!namen.contains(p.parameterName)) namen.add(p.parameterName);
        werte
            .putIfAbsent('$gruppe|${p.parameterName}', () => {})[col] = wert;
        parameterGesamt++;
      }
    }

    for (final eintrag in gruppen.entries) {
      _setz(s, 0, row, _blockUeberschrift(eintrag.key), _blockKopf);
      row++;
      for (final name in eintrag.value) {
        _setz(s, 0, row, name);
        final zellen = werte['${eintrag.key}|$name'] ?? const {};
        for (final z in zellen.entries) {
          _setz(s, z.key, row, z.value);
        }
        row++;
      }
      row++; // Leerzeile zwischen den Blöcken
    }

    // ── Zusätzliche (selbst angelegte) Parameter ──────────────────────
    final customNamen = <String>[];
    final customWerte = <String, Map<int, String>>{};
    for (final st in schritte) {
      final col = spalteVonSchritt[st.id]!;
      for (final p
          in paramsVonSchritt[st.id] ?? const <ProductStepParameter>[]) {
        if (!p.istCustom) continue;
        final wert = (p.wert ?? '').trim();
        if (wert.isEmpty) continue;
        if (!customNamen.contains(p.parameterName)) {
          customNamen.add(p.parameterName);
        }
        customWerte.putIfAbsent(p.parameterName, () => {})[col] = wert;
        parameterGesamt++;
      }
    }

    _setz(s, 0, row, _markerCustom, _sektion);
    row++;
    for (final name in customNamen) {
      _setz(s, 0, row, name);
      for (final z in (customWerte[name] ?? const {}).entries) {
        _setz(s, z.key, row, z.value);
      }
      row++;
    }
    // Ein paar freie Zeilen, damit man von Hand ergänzen kann.
    row += 3;

    // ── Sonstige Informationen ────────────────────────────────────────
    //
    // Achtung: Der Import sammelt in diesem Block JEDE nicht-leere Zelle
    // ein — auch Text in Spalte A. Zwischen diesem Marker und
    // „HISTORISCHE DATEN" darf deshalb nichts anderes stehen.
    _setz(s, 0, row, _markerSonstige, _sektion);
    row++;
    final besonderheit = (artikel.beschreibung ?? '').trim();
    if (besonderheit.isNotEmpty) {
      _setz(s, 1, row, besonderheit);
    }
    row += 2;

    // ── Historische Daten ─────────────────────────────────────────────
    _setz(s, 0, row, _markerHistorie, _sektion);
    row++;
    _setz(
      s,
      0,
      row,
      'Jede produzierte Charge als eine Zeile — die App mittelt daraus die '
      'tatsächlichen Produktionszeiten.',
      _hinweisStil,
    );
    row++;
    const histKopf = [
      'Datum',
      'Kg Rohware',
      'Kg Fertigware',
      'Verlust %',
      'Startzeit',
      'Endzeit',
      'Produktionszeit',
      'kg/h roh',
      'kg/h gegart',
      'Notizen',
    ];
    for (var c = 0; c < histKopf.length; c++) {
      _setz(s, c, row, histKopf[c], _kopfStil);
    }
    row++;
    for (final h in historie) {
      _setz(s, 0, row, _isoDatum(h.datum));
      if (h.kgRohware != null) _setzZahl(s, 1, row, h.kgRohware!);
      if (h.kgFertigware != null) _setzZahl(s, 2, row, h.kgFertigware!);
      if (h.verlustAnteil != null) {
        _setzZahl(s, 3, row, (h.verlustAnteil! * 100).roundToDouble() / 100);
      }
      _setz(s, 4, row, h.startzeit ?? '');
      _setz(s, 5, row, h.endzeit ?? '');
      if (h.produktionszeitMinuten != null) {
        _setz(s, 6, row, _hhmm(h.produktionszeitMinuten!));
      }
      if (h.kgProStundeRoh != null) _setzZahl(s, 7, row, h.kgProStundeRoh!);
      if (h.kgProStundeGegart != null) {
        _setzZahl(s, 8, row, h.kgProStundeGegart!);
      }
      _setz(s, 9, row, h.notizen ?? '');
      row++;
    }

    s.setColumnWidth(0, 30);
    for (var c = 1; c <= _maxSchritte; c++) {
      s.setColumnWidth(c, 20);
    }

    return (schritte: schritte.length, parameter: parameterGesamt);
  }

  // ══════════════════════════════════════════════════════════════════
  // Helfer
  // ══════════════════════════════════════════════════════════════════

  /// Blocküberschrift: durchgehend groß, damit der Import sie als
  /// Gruppenkopf erkennt (er verlangt mindestens zwei Großbuchstaben und
  /// nicht mehr Klein- als Großbuchstaben).
  static String _blockUeberschrift(String gruppe) =>
      gruppe.replaceAll('ß', 'ss').toUpperCase();

  static String _abteilungsName(String dbValue) {
    try {
      return Abteilung.fromDbValue(dbValue).anzeigeName;
    } catch (_) {
      return dbValue;
    }
  }

  static String _hhmm(double minuten) {
    final gesamt = minuten.round();
    final h = gesamt ~/ 60;
    final m = gesamt % 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  static String _isoDatum(DateTime d) =>
      '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

  static String _pad(int n) => n.toString().padLeft(2, '0');

  String _dateiname() {
    final n = DateTime.now();
    return 'stammdaten_${n.year}${_pad(n.month)}${_pad(n.day)}_'
        '${_pad(n.hour)}${_pad(n.minute)}.xlsx';
  }

  /// Blattnamen dürfen in Excel höchstens 31 Zeichen lang und nicht doppelt
  /// sein; einige Sonderzeichen sind verboten.
  static String _eindeutigerBlattName(String nummer, Set<String> belegt) {
    var basis = nummer.trim().replaceAll(RegExp(r'[\[\]:*?/\\]'), '-');
    if (basis.isEmpty) basis = 'Artikel';
    if (basis.length > 31) basis = basis.substring(0, 31);
    var name = basis;
    var i = 2;
    while (belegt.contains(name)) {
      final suffix = '_$i';
      final maxBasis = 31 - suffix.length;
      name =
          '${basis.length > maxBasis ? basis.substring(0, maxBasis) : basis}'
          '$suffix';
      i++;
    }
    belegt.add(name);
    return name;
  }

  static void _setz(
    Sheet s,
    int col,
    int row,
    String wert, [
    CellStyle? stil,
  ]) {
    if (wert.isEmpty && stil == null) return;
    final zelle = s.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    zelle.value = TextCellValue(wert);
    if (stil != null) zelle.cellStyle = stil;
  }

  static void _setzZahl(Sheet s, int col, int row, num wert) {
    final zelle = s.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    if (wert is int || wert == wert.roundToDouble()) {
      zelle.value = IntCellValue(wert.round());
    } else {
      zelle.value = DoubleCellValue(wert.toDouble());
    }
  }
}
