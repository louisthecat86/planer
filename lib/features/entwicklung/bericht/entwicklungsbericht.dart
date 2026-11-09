part of 'bericht_pdf.dart';

// Der Bericht über die Produktentwicklung eines Zeitraums — etwa für die
// Managementbewertung am Jahresende. Vorn die Zahlen auf einen Blick mit
// dem Vorjahr und der Inhalt, dahinter die Kennzahlen (mit dem, wie
// gezählt wird), der Verlauf, was aus den Mustern wurde (auch je Kunde),
// warum Muster nicht weiter verfolgt wurden, die Muster im Einzelnen und
// der Stand heute. Gestalt, Kopf und Fuß wie im Projektbericht — oben
// rechts dessen Logo; die Angaben des Formblatts gehören zum
// Projektbericht und stehen hier nicht.
//
// Gerechnet wird in statistik/entwicklung_auswertung.dart — dieselben
// Zahlen wie im Bereich „Statistik".

/// Was der Bericht braucht: die Auswertung des Zeitraums und den Stand
/// heute.
class EntwicklungsberichtDaten {
  const EntwicklungsberichtDaten({required this.auswertung, this.stand});

  final EntwicklungsAuswertung auswertung;

  /// Die Projekte heute — null: ohne das Kapitel „Stand heute".
  final EntwicklungsStatistik? stand;
}

/// Die Kapitel des Berichts — Schlüssel für
/// [EntwicklungsberichtInhalt.kapitel].
abstract final class EntwicklungsberichtKapitel {
  static const kennzahlen = 'kennzahlen';
  static const verlauf = 'verlauf';
  static const ergebnis = 'ergebnis';
  static const gruende = 'gruende';
  static const muster = 'muster';
  static const stand = 'stand';
}

const Map<String, String> _eKapitelTitel = {
  EntwicklungsberichtKapitel.kennzahlen: 'Kennzahlen',
  EntwicklungsberichtKapitel.verlauf: 'Verlauf',
  EntwicklungsberichtKapitel.ergebnis: 'Was aus den Mustern wurde',
  EntwicklungsberichtKapitel.gruende: 'Nicht weiter verfolgt',
  EntwicklungsberichtKapitel.muster: 'Muster im Einzelnen',
  EntwicklungsberichtKapitel.stand: 'Stand heute',
};

/// Schlüssel der Wahl im Druckfenster.
abstract final class EntwicklungsberichtWahl {
  static const kapitel = 'kapitel';
  static const erklaerungen = 'erklaerungen';
  static const neueSeiten = 'neueSeiten';
}

/// Was in den Bericht kommt — die Wahl im Druckfenster.
class EntwicklungsberichtInhalt {
  const EntwicklungsberichtInhalt({
    this.kapitel,
    this.erklaerungen = true,
    this.neueSeiten = true,
  });

  /// Diese Kapitel ([EntwicklungsberichtKapitel]) — null: alle.
  final Set<String>? kapitel;

  /// Wie gezählt wird — im Kapitel Kennzahlen.
  final bool erklaerungen;

  /// Kapitel beginnen auf einer neuen Seite.
  final bool neueSeiten;
}

/// Ein Kapitel des Berichts.
class _EKapitel {
  _EKapitel(this.schluessel, this.bauen);

  final String schluessel;
  final List<pw.Widget> Function(_ESatz s, _EKapitel k) bauen;

  int nr = 0;

  String get titel => _eKapitelTitel[schluessel]!;
  String get anker => 'kapitel-$nr';
}

/// Was beim Setzen mitläuft.
class _ESatz {
  _ESatz(this.daten, this.jetzt, this.rahmen, this.inhalt);

  final EntwicklungsberichtDaten daten;
  final DateTime jetzt;
  final DruckRahmen rahmen;
  final EntwicklungsberichtInhalt inhalt;

  EntwicklungsAuswertung get a => daten.auswertung;

  bool get neueSeiten => inhalt.neueSeiten && rahmen.umbrueche;

  /// Höher als das darf ein Block nicht werden.
  double get blockHoehe => rahmen.hoehe - _kopfHoehe - _fussHoehe - 20;
}

/// Die Kapitel, die es für [d] gibt — mit Titel, in ihrer Reihenfolge.
List<(String, String)> entwicklungsberichtKapitelVon(
  EntwicklungsberichtDaten d,
) =>
    [for (final k in _eAlleKapitel(d)) (k.schluessel, k.titel)];

List<_EKapitel> _eAlleKapitel(EntwicklungsberichtDaten d) {
  final a = d.auswertung;
  return [
    _EKapitel(EntwicklungsberichtKapitel.kennzahlen, _eKennzahlen),
    // Ein Verlauf braucht mehr als einen Abschnitt — und etwas darin.
    if (a.verlauf.length > 1 &&
        a.verlauf.any(
          (x) =>
              x.neuGesamt > 0 ||
              x.gelistet.isNotEmpty ||
              x.nichtWeiter.isNotEmpty,
        ))
      _EKapitel(EntwicklungsberichtKapitel.verlauf, _eVerlauf),
    _EKapitel(EntwicklungsberichtKapitel.ergebnis, _eErgebnis),
    if (a.gruende.isNotEmpty)
      _EKapitel(EntwicklungsberichtKapitel.gruende, _eGruende),
    if (a.neu.isNotEmpty || a.gelistet.isNotEmpty)
      _EKapitel(EntwicklungsberichtKapitel.muster, _eMuster),
    if (d.stand != null) _EKapitel(EntwicklungsberichtKapitel.stand, _eStand),
  ];
}

List<_EKapitel> _eKapitelFuer(
  EntwicklungsberichtDaten d,
  EntwicklungsberichtInhalt inhalt,
) {
  final kapitel = [
    for (final k in _eAlleKapitel(d))
      if (inhalt.kapitel?.contains(k.schluessel) ?? true) k,
  ];
  for (final (i, k) in kapitel.indexed) {
    k.nr = i + 1;
  }
  return kapitel;
}

/// Der Kundenfilter in Worten: „alle Kunden", „ohne Kunden" oder
/// „Kunde Beispiel Feinkost".
String _kundeText(String? kunde) => kunde == null
    ? 'alle Kunden'
    : kunde == kOhneKunde
        ? 'Muster ohne Kunden'
        : 'Kunde $kunde';

/// Der Bericht für das Druckfenster.
DruckAuftrag entwicklungsberichtDruckAuftrag(
  EntwicklungsberichtDaten daten, {
  BerichtFormblatt formblatt = const BerichtFormblatt(),
  DateTime? gedrucktAm,
}) {
  final a = daten.auswertung;
  final kapitel = entwicklungsberichtKapitelVon(daten);
  const gruppe = 'Im Bericht';
  return DruckAuftrag(
    art: 'entwicklungsbericht',
    titel: 'Bericht Produktentwicklung',
    untertitel: '${a.zeitraum.name} · ${_kundeText(a.kunde)}',
    optionen: [
      DruckWahlMehrere(
        schluessel: EntwicklungsberichtWahl.kapitel,
        titel: 'Kapitel',
        werte: [
          for (final (i, (schluessel, titel)) in kapitel.indexed)
            DruckWert(schluessel, '${i + 1}  $titel'),
        ],
        standard: {for (final (schluessel, _) in kapitel) schluessel},
        // Welche es gibt, hängt vom Zeitraum ab.
        merken: false,
      ),
      const DruckSchalter(
        schluessel: EntwicklungsberichtWahl.erklaerungen,
        titel: 'Wie gezählt wird',
        hinweis: 'Im Kapitel Kennzahlen',
        gruppe: gruppe,
      ),
      const DruckSchalter(
        schluessel: EntwicklungsberichtWahl.neueSeiten,
        titel: 'Kapitel auf neuen Seiten',
        hinweis: 'Ohne: alles fortlaufend — spart Papier',
        gruppe: gruppe,
      ),
    ],
    bauen: (wahl) => entwicklungsberichtDruck(
      daten,
      gedrucktAm: gedrucktAm,
      formblatt: formblatt,
      inhalt: EntwicklungsberichtInhalt(
        kapitel: wahl.mehrere(EntwicklungsberichtWahl.kapitel),
        erklaerungen: wahl.an(EntwicklungsberichtWahl.erklaerungen),
        neueSeiten: wahl.an(EntwicklungsberichtWahl.neueSeiten),
      ),
    ),
  );
}

/// Baut den Bericht als PDF in Originalgröße — [komprimiert] nur für
/// Tests abgeschaltet, die den Text lesen.
Future<Uint8List> baueEntwicklungsberichtPdf(
  EntwicklungsberichtDaten daten, {
  EntwicklungsberichtInhalt inhalt = const EntwicklungsberichtInhalt(),
  BerichtFormblatt formblatt = const BerichtFormblatt(),
  DateTime? gedrucktAm,
  bool komprimiert = true,
}) async {
  final ergebnis = await druckSetzen(
    entwicklungsberichtDruck(
      daten,
      inhalt: inhalt,
      formblatt: formblatt,
      gedrucktAm: gedrucktAm,
    ),
    const DruckLayout(),
    komprimiert: komprimiert,
  );
  return ergebnis.bytes;
}

/// Der Bericht zum Drucken: ein Blatt über viele Seiten, mit Lesezeichen
/// je Kapitel. Von [formblatt] nur das Logo.
DruckDokument entwicklungsberichtDruck(
  EntwicklungsberichtDaten daten, {
  EntwicklungsberichtInhalt inhalt = const EntwicklungsberichtInhalt(),
  BerichtFormblatt formblatt = const BerichtFormblatt(),
  DateTime? gedrucktAm,
}) {
  final a = daten.auswertung;
  final jetzt = gedrucktAm ?? DateTime.now();
  final logo = formblatt.logoZeigen ? formblatt.logo : null;
  final logoBild = _bildAus(logo?.bytes);
  final titel = 'Bericht Produktentwicklung ${a.zeitraum.kurz}';
  return DruckDokument(
    titel: pdfText(titel),
    dateiname: druckDateiname(
      [
        titel,
        if (a.kunde case final k? when k != kOhneKunde) k,
      ].join(' '),
    ),
    lesezeichen: true,
    theme: pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    ),
    blaetter: [
      DruckBlatt(
        rand: const pw.EdgeInsets.fromLTRB(42, 24, 42, 22),
        bauen: (r) {
          final s = _ESatz(daten, jetzt, r, inhalt);
          final kapitel = _eKapitelFuer(daten, inhalt);
          return DruckSeiten(
            maxSeiten: 300,
            kopf: (_) => _kopfzeile(
              nummer: '',
              titel: 'Bericht Produktentwicklung',
              projekt: '${a.zeitraum.name} · ${_kundeText(a.kunde)}',
              logo: logoBild,
              logoBreite: logo?.breite ?? 0,
              logoHoehe: logo?.hoehe ?? 0,
            ),
            fuss: (ctx) => _fusszeile(
              ['Gedruckt am ${_datum(jetzt)} · Produktions Planer'],
              [r.seitenText(ctx)],
            ),
            inhalt: (ctx) => [
              ..._eDeckblatt(s, kapitel),
              for (final k in kapitel) ...k.bauen(s, k),
            ],
          );
        },
      ),
    ],
  );
}

// ── Bausteine ──────────────────────────────────────────────────────────

/// Die Farbe eines Ergebnisses — wie die Phasen im Projektbericht.
PdfColor _ergebnisFarbe(MusterErgebnis e) => switch (e) {
      MusterErgebnis.gelistet => _ok,
      MusterErgebnis.nichtWeiter => _eingestellt,
      MusterErgebnis.offen => _phasenFarbe(ProjektStatus.entwicklung),
      MusterErgebnis.archiviert => _hellgrau,
    };

/// Hält [kinder] auf einer Seite zusammen.
pw.Widget _eZusammen(_ESatz s, List<pw.Widget> kinder) => _Block(
      maxHoehe: s.blockHoehe,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: kinder,
      ),
    );

/// Eine Überschrift mit ihrem Inhalt: bis 22 Zeilen als Block, länger
/// über die Seiten — nicht ganz unten auf einer beginnend.
List<pw.Widget> _eMitTitel(
  _ESatz s,
  pw.Widget titel,
  List<pw.Widget> inhalt, {
  required int zeilen,
}) =>
    zeilen <= 22
        ? [
            _eZusammen(s, [titel, ...inhalt]),
          ]
        : [
            if (s.rahmen.umbrueche) pw.NewPage(freeSpace: 180),
            titel,
            ...inhalt,
          ];

List<pw.Widget> _eKapitelKopf(_ESatz s, _EKapitel k, {String? untertitel}) =>
    _kapitelKopfFuer(
      neueSeiten: s.neueSeiten,
      rahmen: s.rahmen,
      anker: k.anker,
      nr: k.nr,
      titel: k.titel,
      untertitel: untertitel,
    );

/// „2025: 12 (+3)" — der Wert im Vorjahr und die Veränderung.
String _vergleich(EntwicklungsAuswertung a, num jetzt, num vorher) =>
    '${a.zeitraum.vorjahr.kurz}: ${Format.zahl(vorher)} '
    '(${veraenderungText(jetzt, vorher)})';

/// Eine Veränderung in Prozentpunkten: „+5 Pkt." — „—" ohne Wert.
String _punkteText(double? jetzt, double? vorher) =>
    jetzt == null || vorher == null
        ? '—'
        : '${veraenderungText((jetzt * 100).round(), (vorher * 100).round())} '
            'Pkt.';

/// Eine Veränderung von Tagen: „+12" — „—" ohne Wert.
String _tageVeraenderung(double? jetzt, double? vorher) =>
    jetzt == null || vorher == null
        ? '—'
        : veraenderungText(jetzt.round(), vorher.round());

/// „Ø 1,5" — eine Zahl mit einer Stelle, „—" ohne.
String _zahlText(double? wert, {int nachkomma = 1}) =>
    wert == null ? '—' : Format.zahl(wert, nachkomma: nachkomma);

/// Was aus den Mustern wurde, als Balken aus Teilen.
pw.Widget _ergebnisBalken(Map<MusterErgebnis, int> ergebnis) {
  final summe = ergebnis.values.fold<int>(0, (s, n) => s + n);
  return pw.Container(
    height: 12,
    decoration: const pw.BoxDecoration(color: _linie),
    child: summe == 0
        ? null
        : pw.Row(
            children: [
              for (final e in MusterErgebnis.values)
                if ((ergebnis[e] ?? 0) > 0)
                  pw.Expanded(
                    flex: ergebnis[e]!,
                    child: pw.Container(color: _ergebnisFarbe(e)),
                  ),
            ],
          ),
  );
}

/// Eine Legende: kleine Quadrate in Farbe, daneben was sie bedeuten.
pw.Widget _eLegende(List<(PdfColor, String)> eintraege) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Wrap(
        spacing: 14,
        runSpacing: 3,
        children: [
          for (final (farbe, text) in eintraege)
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(width: 7, height: 7, color: farbe),
                pw.SizedBox(width: 4),
                _t(text, groesse: 7.5, farbe: _grau),
              ],
            ),
        ],
      ),
    );

/// Säulen über die Zeit, gestapelt — je Abschnitt die Teile von unten
/// nach oben, darüber die Summe.
pw.Widget _eSaeulen(
  _ESatz s,
  List<({String label, List<(int, PdfColor)> teile})> saeulen, {
  double hoehe = 120,
}) {
  int summe(List<(int, PdfColor)> teile) =>
      teile.fold<int>(0, (n, t) => n + t.$1);
  final hoechste = saeulen.fold<int>(0, (m, x) => math.max(m, summe(x.teile)));
  // Platz für die Zahl über der Säule.
  final flaeche = hoehe - 12;
  final breite = math.min(22.0, s.rahmen.breite / saeulen.length * .55);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.SizedBox(
        height: hoehe,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            for (final x in saeulen)
              pw.Expanded(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    if (summe(x.teile) > 0)
                      _t('${summe(x.teile)}', groesse: 7, farbe: _grau),
                    pw.SizedBox(height: 2),
                    for (final (wert, farbe) in x.teile.reversed)
                      if (wert > 0 && hoechste > 0)
                        pw.Container(
                          width: breite,
                          height: flaeche * wert / hoechste,
                          color: farbe,
                        ),
                  ],
                ),
              ),
          ],
        ),
      ),
      pw.Container(height: .6, color: _grau),
      pw.SizedBox(height: 2),
      pw.Row(
        children: [
          for (final x in saeulen)
            pw.Expanded(
              child: _t(
                x.label,
                groesse: 7,
                farbe: _grau,
                ausrichtung: pw.TextAlign.center,
                maxLines: 1,
              ),
            ),
        ],
      ),
    ],
  );
}

// ── Seite 1 ────────────────────────────────────────────────────────────

List<pw.Widget> _eDeckblatt(_ESatz s, List<_EKapitel> kapitel) {
  final a = s.a;
  final z = a.zahlen;
  final v = a.vorjahr;
  final vj = a.zeitraum.vorjahr.kurz;
  final unterzeile = [
    if (a.zeitraum.art != ZeitraumArt.frei)
      '${_datum(a.zeitraum.von)} – ${_datum(a.zeitraum.bis)}',
    _kundeText(a.kunde),
    'verglichen mit ${a.zeitraum.vorjahr.name}',
  ].join('   ·   ');
  final haeufigsterGrund = a.gruende.isEmpty ? null : a.gruende.first;
  return [
    pw.Row(
      children: [
        _t(
          'BERICHT PRODUKTENTWICKLUNG',
          groesse: 8,
          fett: true,
          farbe: _akzent,
          sperrung: 1,
        ),
        pw.Spacer(),
        _t('Gedruckt am ${_datum(s.jetzt)}', groesse: 8, farbe: _grau),
      ],
    ),
    pw.SizedBox(height: 14),
    _t('Produktentwicklung ${a.zeitraum.name}', groesse: 22, fett: true),
    pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: _t(unterzeile, groesse: 10, farbe: _grau),
    ),
    if (a.laeuftNoch)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: _t(
          'Der Zeitraum läuft noch — Stand ${_datum(a.heute)}.',
          groesse: 8.5,
          kursiv: true,
          farbe: _grau,
        ),
      ),
    _abschnitt('Auf einen Blick'),
    _reihe([
      _kachel(
        'NEUE MUSTER',
        '${z.neueMuster}',
        [
          'davon ${z.neueMusterImGesamtprojekt} in Gesamtprojekten',
          '${z.neueAnfragen} neue '
              '${z.neueAnfragen == 1 ? 'Anfrage' : 'Anfragen'}',
          _vergleich(a, z.neueMuster, v.neueMuster),
        ],
      ),
      _kachel(
        'GELISTET',
        '${z.gelistet}',
        [
          'davon ${z.freigegeben} als Artikel freigegeben',
          if (z.neueArtikel > 0) '${z.neueArtikel} als neuer Artikel',
          _vergleich(a, z.gelistet, v.gelistet),
        ],
        farbe: _ok,
      ),
      _kachel(
        'NICHT WEITER VERFOLGT',
        '${z.nichtWeiter}',
        [
          if (haeufigsterGrund?.grund case final g?) 'meist: $g',
          _vergleich(a, z.nichtWeiter, v.nichtWeiter),
        ],
        farbe: _eingestellt,
      ),
    ]),
    pw.SizedBox(height: 8),
    _reihe([
      _kachel(
        'LISTUNGSQUOTE',
        quoteText(z.listungsquote),
        [
          '${z.kohorte[MusterErgebnis.gelistet] ?? 0} von ${z.neueMuster} '
              'neuen Mustern gelistet',
          'unter den entschiedenen ${quoteText(z.trefferquote)}',
          '$vj: ${quoteText(v.listungsquote)}',
        ],
        farbe: _ok,
      ),
      _kachel(
        'BIS ZUR LISTUNG',
        z.tageBisListung == null ? '—' : 'Ø ${tageText(z.tageBisListung)}',
        [
          if (z.tageBisListungMedian != null)
            'Median ${tageText(z.tageBisListungMedian)}',
          if (z.staendeBisListung != null)
            'Ø ${_zahlText(z.staendeBisListung)} Rezepturstände',
          '$vj: ${v.tageBisListung == null ? '—' : 'Ø ${tageText(v.tageBisListung)}'}',
        ],
      ),
      _kachel(
        'IN ARBEIT',
        '${z.inArbeitAmEnde}',
        [
          a.laeuftNoch ? 'heute' : 'am ${_datum(a.stichtag)}',
          '${z.neueProzesse} mit neuem Prozess, '
              '${z.neueZutaten} mit neuen Zutaten',
          '${z.staendeAngelegt} Rezepturstände angelegt',
        ],
        farbe: _phasenFarbe(ProjektStatus.entwicklung),
      ),
    ]),
    if (kapitel.isNotEmpty) ...[
      _abschnitt('Inhalt'),
      for (final k in kapitel)
        _inhaltSprung(k.anker, k.nr, k.titel, s.rahmen.bekannt[k.anker]),
    ],
  ];
}

// ── 1 Kennzahlen ───────────────────────────────────────────────────────

List<pw.Widget> _eKennzahlen(_ESatz s, _EKapitel k) {
  final a = s.a;
  final z = a.zahlen;
  final v = a.vorjahr;
  final stichtag = a.laeuftNoch ? 'heute' : 'am Ende';
  // Kennzahl, jetzt, im Vorjahr, Veränderung — „davon" eingerückt.
  final zeilen = <(String, String, String, String, bool)>[
    (
      'Neue Muster',
      '${z.neueMuster}',
      '${v.neueMuster}',
      veraenderungText(z.neueMuster, v.neueMuster),
      false,
    ),
    (
      'davon in Gesamtprojekten',
      '${z.neueMusterImGesamtprojekt}',
      '${v.neueMusterImGesamtprojekt}',
      veraenderungText(
        z.neueMusterImGesamtprojekt,
        v.neueMusterImGesamtprojekt,
      ),
      true,
    ),
    (
      'Neue Anfragen (Gesamtprojekte)',
      '${z.neueAnfragen}',
      '${v.neueAnfragen}',
      veraenderungText(z.neueAnfragen, v.neueAnfragen),
      false,
    ),
    (
      'Gelistet (in Produktion gegangen)',
      '${z.gelistet}',
      '${v.gelistet}',
      veraenderungText(z.gelistet, v.gelistet),
      false,
    ),
    (
      'davon als Artikel freigegeben',
      '${z.freigegeben}',
      '${v.freigegeben}',
      veraenderungText(z.freigegeben, v.freigegeben),
      true,
    ),
    (
      'davon als neuer Artikel',
      '${z.neueArtikel}',
      '${v.neueArtikel}',
      veraenderungText(z.neueArtikel, v.neueArtikel),
      true,
    ),
    (
      'Nicht weiter verfolgt',
      '${z.nichtWeiter}',
      '${v.nichtWeiter}',
      veraenderungText(z.nichtWeiter, v.nichtWeiter),
      false,
    ),
    (
      'Listungsquote der neuen Muster',
      quoteText(z.listungsquote),
      quoteText(v.listungsquote),
      _punkteText(z.listungsquote, v.listungsquote),
      false,
    ),
    (
      'unter den entschiedenen',
      quoteText(z.trefferquote),
      quoteText(v.trefferquote),
      _punkteText(z.trefferquote, v.trefferquote),
      true,
    ),
    (
      'Tage bis zur Listung, Mittel',
      _zahlText(z.tageBisListung, nachkomma: 0),
      _zahlText(v.tageBisListung, nachkomma: 0),
      _tageVeraenderung(z.tageBisListung, v.tageBisListung),
      false,
    ),
    (
      'Tage bis zur Listung, Median',
      _zahlText(z.tageBisListungMedian, nachkomma: 0),
      _zahlText(v.tageBisListungMedian, nachkomma: 0),
      _tageVeraenderung(z.tageBisListungMedian, v.tageBisListungMedian),
      true,
    ),
    (
      'Rezepturstände bis zur Listung, Mittel',
      _zahlText(z.staendeBisListung),
      _zahlText(v.staendeBisListung),
      z.staendeBisListung == null || v.staendeBisListung == null
          ? '—'
          : veraenderungText(
              z.staendeBisListung!,
              v.staendeBisListung!,
              nachkomma: 1,
            ),
      false,
    ),
    (
      'In Arbeit $stichtag',
      '${z.inArbeitAmEnde}',
      '${v.inArbeitAmEnde}',
      veraenderungText(z.inArbeitAmEnde, v.inArbeitAmEnde),
      false,
    ),
    (
      'Neue Muster mit neuem Prozess',
      '${z.neueProzesse}',
      '${v.neueProzesse}',
      veraenderungText(z.neueProzesse, v.neueProzesse),
      false,
    ),
    (
      'Neue Muster mit neuen Zutaten',
      '${z.neueZutaten}',
      '${v.neueZutaten}',
      veraenderungText(z.neueZutaten, v.neueZutaten),
      false,
    ),
    (
      'Rezepturstände angelegt',
      '${z.staendeAngelegt}',
      '${v.staendeAngelegt}',
      veraenderungText(z.staendeAngelegt, v.staendeAngelegt),
      false,
    ),
    (
      'Rezepturstände abgeschlossen',
      '${z.staendeAbgeschlossen}',
      '${v.staendeAbgeschlossen}',
      veraenderungText(z.staendeAbgeschlossen, v.staendeAbgeschlossen),
      false,
    ),
  ];
  final tabelle = _tabelle(
    kopf: ['Kennzahl', a.zeitraum.kurz, a.zeitraum.vorjahr.kurz, 'Veränderung'],
    breiten: const {
      0: pw.FlexColumnWidth(),
      1: pw.FixedColumnWidth(84),
      2: pw.FixedColumnWidth(84),
      3: pw.FixedColumnWidth(74),
    },
    rechts: const {1, 2, 3},
    zeilen: [
      for (final (name, jetzt, vorher, veraenderung, davon) in zeilen)
        [
          pw.Padding(
            padding: pw.EdgeInsets.only(left: davon ? 12 : 0),
            child: _zelle(name, farbe: davon ? _grau : _schwarz),
          ),
          _zelle(jetzt, fett: !davon),
          _zelle(vorher, farbe: _grau),
          _zelle(veraenderung, farbe: _grau),
        ],
    ],
  );
  return [
    ..._eKapitelKopf(
      s,
      k,
      untertitel: '${a.zeitraum.name} verglichen mit '
          '${a.zeitraum.vorjahr.name} · ${_kundeText(a.kunde)}',
    ),
    _eZusammen(s, [_abschnitt('Im Vergleich mit dem Vorjahr'), tabelle]),
    if (s.inhalt.erklaerungen)
      _eZusammen(s, [
        _abschnitt('Wie gezählt wird'),
        _punkt(
          'Muster: jedes Projekt — ein Muster in einem Gesamtprojekt wie ein '
          'Projekt für sich —, gezählt am Tag, an dem es angelegt wurde. '
          'Eine Anfrage ist ein Gesamtprojekt.',
        ),
        _punkt(
          'Gelistet: in Produktion gegangen — mit der Freigabe als Artikel '
          'oder von Hand. Es zählt der Tag dieses Wechsels im Verlauf, gleich '
          'wann das Muster angelegt wurde.',
        ),
        _punkt(
          'Nicht weiter verfolgt: im Zeitraum dazu gekommen und an seinem '
          'Ende noch so (heute, wenn er noch läuft). Wieder aufgenommene '
          'zählen nicht; ins Archiv von dort zählt mit.',
        ),
        _punkt(
          'Listungsquote: Anteil der im Zeitraum angelegten Muster, die heute '
          'gelistet sind — unter den entschiedenen: unter denen, die gelistet '
          'oder nicht weiter verfolgt sind.',
        ),
        _punkt(
          'Tage bis zur Listung: vom Anlegen bis zur Listung, über die '
          'Listungen im Zeitraum. Rezepturstände bis zur Listung: die bis '
          'zu diesem Tag angelegten.',
        ),
        _punkt(
          'In Arbeit: in Entwicklung oder Validierung am Ende des Zeitraums '
          '(heute, wenn er noch läuft).',
        ),
        if (a.ohneDatumGelistet > 0)
          _punkt(
            '${a.ohneDatumGelistet} gelistete '
            '${a.ohneDatumGelistet == 1 ? 'Muster ist' : 'Muster sind'} '
            'ohne Tag der Listung (etwa aus der Suite übernommen) — '
            '${a.ohneDatumGelistet == 1 ? 'es zählt' : 'sie zählen'} bei der '
            'Listungsquote, nicht bei den Listungen.',
            farbe: _grau,
          ),
      ]),
  ];
}

// ── 2 Verlauf ──────────────────────────────────────────────────────────

List<pw.Widget> _eVerlauf(_ESatz s, _EKapitel k) {
  final a = s.a;
  final v = a.verlauf;
  final raster = a.zeitraum.raster.label;
  final summe = (
    neu: a.zahlen.neueMuster,
    gelistet: a.zahlen.gelistet,
    nichtWeiter: a.zahlen.nichtWeiter,
    staende: a.zahlen.staendeAngelegt,
  );
  return [
    ..._eKapitelKopf(s, k, untertitel: '${a.zeitraum.name} je $raster'),
    _eZusammen(s, [
      _abschnitt('Neue Muster — und was aus ihnen wurde'),
      _eSaeulen(s, [
        for (final x in v)
          (
            label: x.abschnitt.label,
            teile: [
              for (final e in MusterErgebnis.values)
                (x.neu[e] ?? 0, _ergebnisFarbe(e)),
            ],
          ),
      ]),
      _eLegende([
        for (final e in MusterErgebnis.values) (_ergebnisFarbe(e), e.label),
      ]),
    ]),
    _eZusammen(s, [
      _abschnitt('Gelistet und nicht weiter verfolgt'),
      _eSaeulen(s, hoehe: 90, [
        for (final x in v)
          (
            label: x.abschnitt.label,
            teile: [
              (x.gelistet.length, _ergebnisFarbe(MusterErgebnis.gelistet)),
              (
                x.nichtWeiter.length,
                _ergebnisFarbe(MusterErgebnis.nichtWeiter),
              ),
            ],
          ),
      ]),
      _eLegende([
        (_ergebnisFarbe(MusterErgebnis.gelistet), 'Gelistet'),
        (_ergebnisFarbe(MusterErgebnis.nichtWeiter), 'Nicht weiter verfolgt'),
      ]),
    ]),
    ..._eMitTitel(
      s,
      _abschnitt('Je $raster'),
      zeilen: v.length + 2,
      [
        _tabelle(
          kopf: const [
            'Zeitraum',
            'Neue Muster',
            'Gelistet',
            'Nicht weiter verfolgt',
            'Rezepturstände',
          ],
          breiten: const {
            0: pw.FlexColumnWidth(),
            1: pw.FixedColumnWidth(70),
            2: pw.FixedColumnWidth(60),
            3: pw.FixedColumnWidth(100),
            4: pw.FixedColumnWidth(80),
          },
          rechts: const {1, 2, 3, 4},
          zeilen: [
            for (final x in v)
              [
                _zelle(x.abschnitt.name),
                _zelle('${x.neuGesamt}'),
                _zelle('${x.gelistet.length}'),
                _zelle('${x.nichtWeiter.length}'),
                _zelle('${x.staende}', farbe: _grau),
              ],
            [
              _zelle('Zusammen', fett: true),
              _zelle('${summe.neu}', fett: true),
              _zelle('${summe.gelistet}', fett: true),
              _zelle('${summe.nichtWeiter}', fett: true),
              _zelle('${summe.staende}', fett: true),
            ],
          ],
        ),
      ],
    ),
  ];
}

// ── 3 Was aus den Mustern wurde ────────────────────────────────────────

List<pw.Widget> _eErgebnis(_ESatz s, _EKapitel k) {
  final a = s.a;
  final z = a.zahlen;
  final n = z.neueMuster;
  int anzahl(MusterErgebnis e) => z.kohorte[e] ?? 0;
  String anteil(MusterErgebnis e) =>
      n == 0 ? '' : ' (${quoteText(anzahl(e) / n)})';
  return [
    ..._eKapitelKopf(
      s,
      k,
      untertitel: 'Die ${a.zeitraum.name} angelegten Muster — Stand '
          '${_datum(a.heute)}',
    ),
    if (n == 0)
      _leer('Im Zeitraum wurde kein Muster angelegt.')
    else
      _eZusammen(s, [
        _abschnitt('Von $n ${n == 1 ? 'Muster' : 'Mustern'}'),
        _ergebnisBalken(z.kohorte),
        _eLegende([
          for (final e in MusterErgebnis.values)
            if (anzahl(e) > 0)
              (_ergebnisFarbe(e), '${e.label}: ${anzahl(e)}${anteil(e)}'),
        ]),
        pw.SizedBox(height: 8),
        _kennzahlen([
          _kennzahl(
            'LISTUNGSQUOTE',
            quoteText(z.listungsquote),
            unten: '${anzahl(MusterErgebnis.gelistet)} von $n gelistet',
          ),
          _kennzahl(
            'UNTER DEN ENTSCHIEDENEN',
            quoteText(z.trefferquote),
            unten: 'gelistet oder nicht weiter verfolgt',
          ),
          _kennzahl(
            'NOCH IN ARBEIT',
            '${anzahl(MusterErgebnis.offen)}',
            unten: 'kann sich noch entscheiden',
          ),
        ]),
      ]),
    if (a.kunden.isNotEmpty)
      ..._eMitTitel(
        s,
        _abschnitt('Nach Kunde'),
        zeilen: a.kunden.length + 1,
        [
          _tabelle(
            kopf: const [
              'Kunde',
              'Muster',
              'Gelistet',
              'Nicht weiter verfolgt',
              'In Arbeit',
              'Archiviert',
              'Quote',
            ],
            breiten: const {
              0: pw.FlexColumnWidth(),
              1: pw.FixedColumnWidth(46),
              2: pw.FixedColumnWidth(50),
              3: pw.FixedColumnWidth(92),
              4: pw.FixedColumnWidth(52),
              5: pw.FixedColumnWidth(56),
              6: pw.FixedColumnWidth(44),
            },
            rechts: const {1, 2, 3, 4, 5, 6},
            zeilen: [
              for (final x in a.kunden)
                [
                  _zelle(x.kunde ?? 'Ohne Kunden', farbe: _schwarz),
                  _zelle('${x.muster}', fett: true),
                  _zelle('${x.anzahl(MusterErgebnis.gelistet)}'),
                  _zelle('${x.anzahl(MusterErgebnis.nichtWeiter)}'),
                  _zelle('${x.anzahl(MusterErgebnis.offen)}'),
                  _zelle('${x.anzahl(MusterErgebnis.archiviert)}'),
                  _zelle(quoteText(x.quote), farbe: _grau),
                ],
            ],
          ),
        ],
      ),
  ];
}

// ── 4 Nicht weiter verfolgt ────────────────────────────────────────────

List<pw.Widget> _eGruende(_ESatz s, _EKapitel k) {
  final a = s.a;
  return [
    ..._eKapitelKopf(
      s,
      k,
      untertitel: '${a.nichtWeiter.length} Muster im Zeitraum',
    ),
    ..._eMitTitel(
      s,
      _abschnitt('Gründe'),
      zeilen: a.gruende.length + 1,
      [
        _tabelle(
          kopf: const ['Grund', 'Anzahl', 'Muster'],
          breiten: const {
            0: pw.FlexColumnWidth(1.4),
            1: pw.FixedColumnWidth(46),
            2: pw.FlexColumnWidth(2),
          },
          rechts: const {1},
          zeilen: [
            for (final g in a.gruende)
              [
                _zelle(
                  g.grund ?? 'Ohne Angabe',
                  farbe: g.grund == null ? _grau : _schwarz,
                ),
                _zelle('${g.anzahl}', fett: true),
                _zelle(
                  [for (final l in g.muster) l.name].join(', '),
                  farbe: _grau,
                ),
              ],
          ],
        ),
      ],
    ),
    ..._eMitTitel(
      s,
      _abschnitt('Im Einzelnen'),
      zeilen: a.nichtWeiter.length + 1,
      [
        _tabelle(
          kopf: const ['Muster', 'Kunde', 'Angelegt', 'Nicht weiter', 'Grund'],
          breiten: const {
            0: pw.FlexColumnWidth(1.4),
            1: pw.FlexColumnWidth(),
            2: pw.FixedColumnWidth(56),
            3: pw.FixedColumnWidth(60),
            4: pw.FlexColumnWidth(1.4),
          },
          zeilen: [
            for (final l in a.nichtWeiter)
              [
                _musterZelle(l),
                _zelle(l.kunde ?? '-', farbe: _grau),
                _zelle(_datum(l.angelegt)),
                _zelle(_datum(a.eingestelltAm(l))),
                _zelle(a.grund(l) ?? '-', farbe: _grau),
              ],
          ],
        ),
      ],
    ),
  ];
}

/// Name des Musters, darunter klein sein Gesamtprojekt.
pw.Widget _musterZelle(MusterLauf l) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _zelle(l.name),
        if (l.gesamtprojekt case final g?) _zelle(g, farbe: _grau, groesse: 7),
      ],
    );

// ── 5 Muster im Einzelnen ──────────────────────────────────────────────

List<pw.Widget> _eMuster(_ESatz s, _EKapitel k) {
  final a = s.a;
  pw.Widget marke(MusterErgebnis e) => _markeZelle(
        e.label.toUpperCase(),
        _ergebnisFarbe(e),
      );
  return [
    ..._eKapitelKopf(s, k, untertitel: a.zeitraum.name),
    if (a.neu.isNotEmpty)
      ..._eMitTitel(
        s,
        _abschnitt(
          'Im Zeitraum angelegt',
          zusatz: '${a.neu.length} Muster · Ergebnis Stand '
              '${_datum(a.heute)}',
        ),
        zeilen: a.neu.length + 1,
        [
          _tabelle(
            kopf: const [
              'Muster',
              'Kunde',
              'Angelegt',
              'Ergebnis',
              'Gelistet am',
              'Tage',
              'Stände',
            ],
            breiten: const {
              0: pw.FlexColumnWidth(1.5),
              1: pw.FlexColumnWidth(),
              2: pw.FixedColumnWidth(56),
              3: pw.FixedColumnWidth(112),
              4: pw.FixedColumnWidth(58),
              5: pw.FixedColumnWidth(34),
              6: pw.FixedColumnWidth(38),
            },
            rechts: const {5, 6},
            zeilen: [
              for (final l in a.neu)
                [
                  _musterZelle(l),
                  _zelle(l.kunde ?? '-', farbe: _grau),
                  _zelle(_datum(l.angelegt)),
                  marke(a.ergebnis(l)),
                  _zelle(l.gelistetAm == null ? '-' : _datum(l.gelistetAm)),
                  _zelle(
                    l.tageBisListung == null ? '-' : '${l.tageBisListung}',
                  ),
                  _zelle('${l.staende.length}', farbe: _grau),
                ],
            ],
          ),
        ],
      ),
    if (a.gelistet.isNotEmpty)
      ..._eMitTitel(
        s,
        _abschnitt(
          'Im Zeitraum gelistet',
          zusatz: '${a.gelistet.length} Muster — gleich, wann angelegt',
        ),
        zeilen: a.gelistet.length + 1,
        [
          _tabelle(
            kopf: const [
              'Muster',
              'Kunde',
              'Angelegt',
              'Gelistet am',
              'Tage',
              'Stände',
              'Artikel',
            ],
            breiten: const {
              0: pw.FlexColumnWidth(1.5),
              1: pw.FlexColumnWidth(),
              2: pw.FixedColumnWidth(56),
              3: pw.FixedColumnWidth(58),
              4: pw.FixedColumnWidth(34),
              5: pw.FixedColumnWidth(38),
              6: pw.FixedColumnWidth(64),
            },
            rechts: const {4, 5},
            zeilen: [
              for (final l in a.gelistet)
                [
                  _musterZelle(l),
                  _zelle(l.kunde ?? '-', farbe: _grau),
                  _zelle(_datum(l.angelegt)),
                  _zelle(_datum(l.gelistetAm)),
                  _zelle('${l.tageBisListung}'),
                  _zelle('${l.staendeBisListung}', farbe: _grau),
                  _zelle(
                    [
                      if (_oderNull(l.projekt.artikelnummer) case final n?) n,
                      if (l.neuerArtikel) 'neu',
                    ].join(' · '),
                    farbe: _grau,
                  ),
                ],
            ],
          ),
        ],
      ),
  ];
}

// ── 6 Stand heute ──────────────────────────────────────────────────────

List<pw.Widget> _eStand(_ESatz s, _EKapitel k) {
  final st = s.daten.stand!;
  final ruhend = st.ruhend(s.jetzt);
  return [
    ..._eKapitelKopf(
      s,
      k,
      untertitel: 'Alle Projekte am ${_datum(s.jetzt)} · '
          '${_kundeText(s.a.kunde)}',
    ),
    _eZusammen(s, [
      _abschnitt('Projekte je Phase', zusatz: '${st.projekte} zusammen'),
      _tabelle(
        kopf: [for (final p in ProjektStatus.values) _phasenName(p)],
        rechts: {for (var i = 0; i < ProjektStatus.values.length; i++) i},
        zeilen: [
          [
            for (final p in ProjektStatus.values)
              _zelle('${st.projekteJeStatus[p] ?? 0}', fett: true),
          ],
        ],
      ),
    ]),
    if (st.aktive.isEmpty)
      _leer('Kein Projekt in Entwicklung oder Validierung.')
    else
      ..._eMitTitel(
        s,
        _abschnitt(
          'In Arbeit',
          zusatz: ruhend.isEmpty
              ? 'das zuletzt bewegte zuerst'
              : '${ruhend.length} seit mindestens $kRuhendNachTagen Tagen '
                  'ohne Änderung',
        ),
        zeilen: st.aktive.length + 1,
        [
          _tabelle(
            kopf: const [
              'Projekt',
              'Phase',
              'Checkliste',
              'Stände',
              'Zuletzt bewegt',
            ],
            breiten: const {
              0: pw.FlexColumnWidth(),
              1: pw.FixedColumnWidth(78),
              2: pw.FixedColumnWidth(64),
              3: pw.FixedColumnWidth(44),
              4: pw.FixedColumnWidth(80),
            },
            rechts: const {3},
            zeilen: [
              for (final p in st.aktive)
                [
                  _zelle(p.projekt.name),
                  _zelle(ProjektStatus.aus(p.projekt.status).label),
                  _zelle(p.checkliste.text, farbe: _grau),
                  _zelle('${p.staende}', farbe: _grau),
                  _zelle(
                    _datum(p.letzteAktivitaet),
                    farbe: ruhend.contains(p) ? _warn : _schwarz,
                    fett: ruhend.contains(p),
                  ),
                ],
            ],
          ),
          if (ruhend.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: _t(
                'Fett: seit mindestens $kRuhendNachTagen Tagen ohne Änderung '
                'am Projekt, im Verlauf oder an seinen Rezepturen.',
                groesse: 7,
                farbe: _grau,
              ),
            ),
        ],
      ),
  ];
}
