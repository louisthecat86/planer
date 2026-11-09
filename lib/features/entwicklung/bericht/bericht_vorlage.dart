part of 'bericht_pdf.dart';

// Die leere Vorlage des Projektberichts — zum Ablegen bei den
// Formblättern. Derselbe Aufbau mit Kopf und Fuß des Formblatts: jedes
// Kapitel mit jedem Abschnitt, den ein Bericht haben kann. Statt der
// Angaben eines Projekts steht in «», was dort erscheint; was nur unter
// Umständen erscheint (das Gesamtprojekt nur bei einem Muster), sagt die
// graue Zeile neben der Überschrift.
//
// Bekommt der Bericht einen Abschnitt dazu, gehört er auch hierher — ein
// Test vergleicht die Überschriften beider
// (test/projektbericht_formblatt_test.dart).

/// Ein Platzhalter: was an dieser Stelle im Bericht steht.
String _v(String was) => '«$was»';

/// Die leere Vorlage zum Drucken oder Speichern — Kopf und Fuß aus
/// [formblatt].
DruckDokument berichtVorlageDruck({
  BerichtFormblatt formblatt = const BerichtFormblatt(),
  DateTime? gedrucktAm,
}) {
  final jetzt = gedrucktAm ?? DateTime.now();
  final b = ProjektBericht(
    projekt: EntwicklungsProjekt(
      id: 'vorlage',
      name: _v('Projektname'),
      status: ProjektStatus.entwicklung.schluessel,
      neuerProzess: false,
      neueZutaten: false,
      createdAt: jetzt,
      updatedAt: jetzt,
    ),
  );
  return _dokument(
    b: b,
    inhalt: const BerichtInhalt(),
    jetzt: jetzt,
    formblatt: formblatt,
    titel: 'Projektbericht Vorlage',
    dateiname: druckDateiname(
      [
        'Projektbericht Vorlage',
        formblatt.nummer,
        if (formblatt.stand.trim().isNotEmpty) 'Stand ${formblatt.stand}',
      ].join(' '),
    ),
    projektZeile: [
      _v('Projektname'),
      _v('Kunde'),
      'Art.-Nr. ${_v('Artikelnummer')}',
    ].join(' · '),
    kapitel: _vorlageKapitel,
    deckblatt: _vorlageDeckblatt,
    vorlage: true,
  );
}

/// Die leere Vorlage im Druckfenster — zum Speichern bei den
/// Formblättern. [formblatt] liefert Kopf und Fuß bei jedem Setzen.
DruckAuftrag berichtVorlageDruckAuftrag({
  BerichtFormblatt Function()? formblatt,
  DateTime? gedrucktAm,
}) =>
    DruckAuftrag(
      art: 'projektbericht-vorlage',
      titel: 'Projektbericht-Vorlage',
      untertitel: 'Leer — in «» steht, welche Angabe dort im Bericht erscheint',
      bauen: (_) => berichtVorlageDruck(
        formblatt: formblatt?.call() ?? const BerichtFormblatt(),
        gedrucktAm: gedrucktAm,
      ),
    );

/// Die leere Vorlage als PDF in Originalgröße — [komprimiert] nur für
/// Tests abgeschaltet, die den Text lesen.
Future<Uint8List> baueVorlagePdf({
  BerichtFormblatt formblatt = const BerichtFormblatt(),
  DateTime? gedrucktAm,
  bool komprimiert = true,
}) async {
  final ergebnis = await druckSetzen(
    berichtVorlageDruck(formblatt: formblatt, gedrucktAm: gedrucktAm),
    const DruckLayout(),
    komprimiert: komprimiert,
  );
  return ergebnis.bytes;
}

/// Alle Kapitel — in der Vorlage jedes, auch die, die ein junges Projekt
/// noch nicht hat.
List<_Kapitel> _vorlageKapitel() {
  final kapitel = [
    _kapitel(BerichtKapitel.projekt, _vorlageProjekt),
    _kapitel(BerichtKapitel.rezeptur, _vorlageRezeptur),
    _kapitel(BerichtKapitel.produkt, _vorlageProdukt),
    _kapitel(BerichtKapitel.herstellung, _vorlageHerstellung),
    _kapitel(BerichtKapitel.freigabe, _vorlageFreigabe),
    _kapitel(BerichtKapitel.weg, _vorlageWeg),
    _kapitel(BerichtKapitel.verlauf, _vorlageVerlauf),
    _kapitel(BerichtKapitel.dateien, _vorlageDateien),
  ];
  for (final (i, k) in kapitel.indexed) {
    k.nr = i + 1;
  }
  return kapitel;
}

// ── Bausteine der Vorlage ──────────────────────────────────────────────

/// Ein Hinweis in der Vorlage, klein und kursiv.
pw.Widget _vHinweis(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: _t(text, groesse: 7.5, kursiv: true, farbe: _grau),
    );

/// Eine leere Fläche mit Rahmen — wo im Bericht ein Bild steht.
pw.Widget _vFlaeche(
  String was, {
  double? breite,
  required double hoehe,
  pw.EdgeInsets? rand,
}) =>
    pw.Container(
      width: breite,
      height: hoehe,
      margin: rand,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _linie, width: .6),
      ),
      child: _t(
        _v(was),
        groesse: 8.5,
        farbe: _grau,
        ausrichtung: pw.TextAlign.center,
      ),
    );

/// Eine Station mit ihrem ersten Schritt, wie in der Kette.
List<pw.Widget> _vStation(List<(String, String)> werte) => [
      _band('STATION 1', _v('Abteilung'), _grau),
      _schrittKopf(
        '1',
        '${_v('Anlage')} - ${_v('Prozessschritt')}',
        zusatz: _v('Personen · Leistung'),
      ),
      _schrittFelder(werte),
    ];

// ── Seite 1 ────────────────────────────────────────────────────────────

List<pw.Widget> _vorlageDeckblatt(_Satz s, List<_Kapitel> kapitel) => [
      pw.Row(
        children: [
          _t(
            'PROJEKTBERICHT',
            groesse: 8,
            fett: true,
            farbe: _akzent,
            sperrung: 1,
          ),
          pw.Spacer(),
          _t('Gedruckt am ${_v('Datum')}', groesse: 8, farbe: _grau),
        ],
      ),
      _vHinweis(
        'Leere Vorlage: In «» steht, welche Angabe dort im Bericht erscheint. '
        'Was nur unter Umständen erscheint, sagt die graue Zeile neben der '
        'Überschrift.',
      ),
      pw.SizedBox(height: 10),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _t(
                  'Muster im Gesamtprojekt „${_v('Gesamtprojekt')}" - nur bei '
                  'einem Muster',
                  groesse: 9,
                  farbe: _akzent,
                ),
                pw.SizedBox(height: 2),
                _t(_v('Projektname'), groesse: 22, fett: true),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: _t(
                    [
                      _v('Kunde'),
                      'Art.-Nr. ${_v('Artikelnummer')}',
                      _v('Fließdiagramm'),
                    ].join('   ·   '),
                    groesse: 10,
                    farbe: _grau,
                  ),
                ),
                pw.SizedBox(height: 14),
                pw.Row(
                  children: [
                    for (final (i, ph) in const [
                      ProjektStatus.entwicklung,
                      ProjektStatus.validierung,
                      ProjektStatus.produktion,
                    ].indexed) ...[
                      if (i > 0)
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 5),
                          child: _t('»', farbe: _hellgrau),
                        ),
                      _t(_phasenName(ph), groesse: 8, farbe: _grau),
                    ],
                    pw.SizedBox(width: 10),
                    _t(
                      'die jetzige Phase hervorgehoben',
                      groesse: 7.5,
                      kursiv: true,
                      farbe: _hellgrau,
                    ),
                  ],
                ),
                pw.SizedBox(height: 5),
                _t(
                  '${_v('Phase')} seit ${_v('Datum')} · angelegt am '
                  '${_v('Datum')}',
                  groesse: 8,
                  farbe: _grau,
                ),
                pw.SizedBox(height: 10),
                _t(_v('Produktidee, bis zu vier Zeilen'), groesse: 9),
              ],
            ),
          ),
          _fotoUndFreigabe(_vFlaeche('Produktfoto', hoehe: 126)),
        ],
      ),
      _abschnitt('Auf einen Blick'),
      _reihe([
        _kachel('FREIGABE', 'Artikel ${_v('Nr.')}', [
          _v('Artikelbezeichnung'),
          'Stand ${_v('Nr.')} · am ${_v('Datum')}',
        ]),
        _kachel('REZEPTUR', 'Stand ${_v('Nr.')} · ${_v('Status')}', [
          _v('Rezeptur'),
          'Fleisch ${_v('Anteil')} · Verlust ${_v('Anteil')}',
          '${_v('Anzahl')} Stände, davon ${_v('Anzahl')} in Arbeit',
        ]),
        _kachel(
          'CHECKLISTE',
          '${_v('x von y')} erledigt',
          ['Als Nächstes: ${_v('Punkt')}'],
          zusatz: _balken(0),
        ),
      ]),
      pw.SizedBox(height: 8),
      _reihe([
        _kachel('PROZESS', 'Version ${_v('Nr.')}', [
          _v('Kette in Kürze'),
          'vom ${_v('Datum')}',
        ]),
        _kachel('HACCP', '${_v('Anzahl')} Gefahren', [
          '${_v('Anzahl')} Lenkungspunkte, davon ${_v('Anzahl')} CCP',
          'höchstes Risiko ${_v('Wert')}',
        ]),
        _kachel('OFFENE PUNKTE', '${_v('Anzahl')} Einträge offen', [
          '${_v('fällig bis')}: ${_v('Titel')}',
        ]),
      ]),
      pw.SizedBox(height: 8),
      pw.Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: pw.WrapCrossAlignment.center,
        children: [
          _t(
            'ZIELE JE 100 G',
            groesse: 6.5,
            fett: true,
            farbe: _grau,
            sperrung: .4,
          ),
          _t(
            'Fett max. ${_v('Wert')} % · Rezeptur ${_v('Wert')} g',
            groesse: 8.5,
          ),
          _t(
            'Eiweiß min. ${_v('Wert')} % · Rezeptur ${_v('Wert')} g',
            groesse: 8.5,
          ),
          _t('aw-Wert max. ${_v('Wert')}', groesse: 8.5),
        ],
      ),
      _abschnitt('Inhalt'),
      for (final k in kapitel) _inhaltZeile(s, k),
    ];

// ── 1 Projekt ──────────────────────────────────────────────────────────

List<pw.Widget> _vorlageProjekt(_Satz s, _Kapitel k) => [
      ..._kapitelKopf(s, k),
      _zusammen(s, [
        _felderZweispaltig([
          ('Gesamtprojekt', '${_v('Name')} - bei einem Muster'),
          ('Kunde', _v('Kunde')),
          ('Artikelnummer', _v('Artikelnummer')),
          ('Fließdiagramm', _v('Nummer · Bezeichnung')),
          ('Phase', '${_v('Phase')} seit ${_v('Datum')}'),
          ('Angelegt', _v('Datum')),
          ('Zuletzt geändert', _v('Datum')),
          ('Freigegeben', '${_v('Datum')} oder nein'),
          ('Neuer Prozess', 'ja oder nein'),
          ('Neue Zutaten', 'ja: ${_v('welche')} - oder nein'),
          ('Rezepturen', _v('Namen der Rezepturen')),
        ]),
      ]),
      _zusammen(s, [
        _abschnitt('Gesamtprojekt', zusatz: 'nur bei einem Muster'),
        _fliess(_v('Anfrage aus dem Gesamtprojekt')),
        pw.SizedBox(height: 5),
        _tabelle(
          kopf: const ['Muster', 'Phase', 'Art.-Nr.'],
          breiten: const {
            0: pw.FlexColumnWidth(),
            1: pw.FixedColumnWidth(110),
            2: pw.FixedColumnWidth(80),
          },
          zeilen: [
            [
              _zelle('${_v('Muster')}  (dieser Bericht)', fett: true),
              _zelle(_v('Phase')),
              _zelle(_v('Art.-Nr.')),
            ],
            [_zelle(_v('Muster')), _zelle(_v('Phase')), _zelle(_v('Art.-Nr.'))],
          ],
        ),
      ]),
      _zusammen(s, [
        _abschnitt('Phasen', zusatz: 'sobald die Phase einmal gewechselt hat'),
        _tabelle(
          kopf: const ['Seit', 'Phase', 'Anlass'],
          breiten: const {
            0: pw.FixedColumnWidth(62),
            1: pw.FixedColumnWidth(80),
            2: pw.FlexColumnWidth(),
          },
          zeilen: [
            [_zelle(_v('Datum')), _zelle(_v('Phase')), _zelle(_v('Anlass'))],
          ],
        ),
      ]),
      _zusammen(s, [
        _abschnitt(
          'Ziele',
          zusatz: 'je 100 g, verglichen mit Stand ${_v('Nr.')} · wenn gesetzt',
        ),
        _tabelle(
          kopf: const ['Ziel', 'Vorgabe', 'Rezeptur', 'Ergebnis'],
          breiten: const {
            0: pw.FixedColumnWidth(80),
            1: pw.FixedColumnWidth(80),
            2: pw.FixedColumnWidth(80),
            3: pw.FlexColumnWidth(),
          },
          zeilen: [
            [
              _zelle('Fett'),
              _zelle('max. ${_v('Wert')} %'),
              _zelle('${_v('Wert')} g'),
              _zelle('erreicht oder nicht erreicht'),
            ],
            [
              _zelle('Eiweiß'),
              _zelle('min. ${_v('Wert')} %'),
              _zelle('${_v('Wert')} g'),
              _zelle('erreicht oder nicht erreicht'),
            ],
            [
              _zelle('aw-Wert'),
              _zelle('max. ${_v('Wert')}'),
              _zelle('-'),
              _zelle('nicht berechnet', farbe: _grau),
            ],
          ],
        ),
      ]),
      ..._textAbschnitt(s, 'Produktidee', _v('Text aus dem Projekt')),
      ..._textAbschnitt(
        s,
        'Anfrage und Vereinbarungen',
        _v('Text aus dem Projekt'),
      ),
      ..._textAbschnitt(s, 'Notizen', _v('Text aus dem Projekt')),
    ];

// ── 2 Rezeptur ─────────────────────────────────────────────────────────

List<pw.Widget> _vorlageRezeptur(_Satz s, _Kapitel k) {
  List<pw.Widget> vergleich(String titel, String wert) => [
        _zelle(titel),
        for (var i = 0; i < 3; i++) _zelle(_v(wert)),
      ];
  return [
    ..._kapitelKopf(
      s,
      k,
      untertitel: '${_v('Rezeptur')} · Stand ${_v('Nr.')} · ${_v('Status')} · '
          'abgeschlossen am ${_v('Datum')} · freigegeben ist Stand '
          '${_v('Nr.')}',
    ),
    ..._absatz(s, 'Grund für diesen Stand', _v('Notiz zum Stand')),
    ..._absatz(s, 'Bezeichnung des Stands', _v('Bezeichnung')),
    pw.SizedBox(height: 8),
    _kennzahlen([
      _kennzahl('EINSATZ', '${_v('Menge')} kg'),
      _kennzahl('VERLUST', '${_v('Wert')} %', unten: _v('Verlustart')),
      _kennzahl('ENDGEWICHT', '${_v('Menge')} kg'),
      _kennzahl('FLEISCHANTEIL', '${_v('Wert')} %'),
      _kennzahl('BEFFE', '${_v('Wert')} %'),
    ]),
    _zusammen(s, [
      _abschnitt('Zusammensetzung', zusatz: 'je Ansatz'),
      _tabelle(
        kopf: const ['Nr.', 'Zutat', 'Menge', 'Anteil', 'Merkmale'],
        rechts: const {2, 3},
        breiten: const {
          0: pw.FixedColumnWidth(24),
          1: pw.FlexColumnWidth(3),
          2: pw.FixedColumnWidth(62),
          3: pw.FixedColumnWidth(50),
          4: pw.FlexColumnWidth(2.2),
        },
        zeilen: [
          [
            _zelle('1', farbe: _grau),
            _zelle(_v('Zutat oder Unterrezeptur')),
            _zelle('${_v('Menge')} kg'),
            _zelle('${_v('Wert')} %'),
            _zelle(
              _v('Fleisch (Tierart) · Wasser · Allergene'),
              farbe: _grau,
              groesse: 7.5,
            ),
          ],
          [
            _zelle(''),
            _zelle('Summe', fett: true),
            _zelle('${_v('Menge')} kg', fett: true),
            _zelle('100 %', fett: true),
            _zelle(''),
          ],
        ],
        hintergruende: const [null, _flaeche],
      ),
    ]),
    _zusammen(s, [
      _abschnitt('Zutatenverzeichnis', zusatz: 'wie auf dem Etikett'),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _linie, width: .6),
        ),
        child: _t(_v('Zutatenverzeichnis aus der Rezeptur'), groesse: 9),
      ),
      pw.SizedBox(height: 6),
      _felder([
        ('Allergene', '${_v('Allergen')} (${_v('Zutaten')}) - oder keine'),
        ('Spuren möglich', _v('Allergene aus der Spezifikation')),
        ('Verarbeitungshilfsstoffe', '${_v('Stoff')} (${_v('Zutaten')})'),
      ]),
    ]),
    _zusammen(s, [
      _abschnitt(
        'Nährwerte',
        zusatz: 'je 100 g, gerundet wie auf dem Etikett · mit den Zutatendaten '
            '${_v('von heute oder vom Abschluss')}',
      ),
      pw.SizedBox(
        width: 380,
        child: _tabelle(
          kopf: const ['Nährwert', 'je 100 g', 'Ziel'],
          breiten: const {
            0: pw.FlexColumnWidth(),
            1: pw.FixedColumnWidth(96),
            2: pw.FixedColumnWidth(100),
          },
          zeilen: [
            [
              _zelle('Energie'),
              _zelle('${_v('kJ')} / ${_v('kcal')}'),
              _zelle(''),
            ],
            [
              _zelle('Fett'),
              _zelle('${_v('Wert')} g'),
              _zelle('max. ${_v('Wert')} g'),
            ],
            [
              _zelle('   davon gesättigte Fettsäuren'),
              _zelle('${_v('Wert')} g'),
              _zelle(''),
            ],
            [_zelle('Kohlenhydrate'), _zelle('${_v('Wert')} g'), _zelle('')],
            [_zelle('   davon Zucker'), _zelle('${_v('Wert')} g'), _zelle('')],
            [
              _zelle('Eiweiß'),
              _zelle('${_v('Wert')} g'),
              _zelle('min. ${_v('Wert')} g'),
            ],
            [_zelle('Salz'), _zelle('${_v('Wert')} g'), _zelle('')],
          ],
        ),
      ),
      _vHinweis('Die Spalte „Ziel" nur, wenn das Projekt Ziele hat.'),
    ]),
    _zusammen(s, [
      _abschnitt(
        'Fleisch nach LMIV',
        zusatz: 'Grenzwerte für Fett und Bindegewebe · mit Fleisch',
      ),
      _tabelle(
        kopf: const ['Tierart', 'Masse', 'Fett', 'Bindegewebe', 'als Fleisch'],
        rechts: const {1, 4},
        breiten: const {
          0: pw.FlexColumnWidth(1.4),
          1: pw.FixedColumnWidth(58),
          2: pw.FlexColumnWidth(1.3),
          3: pw.FlexColumnWidth(1.5),
          4: pw.FixedColumnWidth(70),
        },
        zeilen: [
          [
            _zelle(_v('Tierart')),
            _zelle('${_v('Menge')} kg'),
            _zelle('${_v('Wert')} % (Grenze ${_v('Wert')} %)'),
            _zelle('${_v('Wert')} % (Grenze ${_v('Wert')} %)'),
            _zelle('${_v('Menge')} kg'),
          ],
        ],
      ),
    ]),
    _zusammen(s, [
      _abschnitt('Hinweise der Berechnung', zusatz: 'wenn es welche gibt'),
      _punkt(_v('Warnung der Berechnung'), farbe: _warn),
      _punkt(
        'Ohne Nährwerte: ${_v('Zutaten')} — die Tabelle ist zu niedrig.',
        farbe: _warn,
      ),
      _punkt('Ohne BEFFE-Wert: ${_v('Zutaten')}', farbe: _warn),
    ]),
    _zusammen(s, [
      _abschnitt(
        'Stände im Vergleich',
        zusatz: 'ab zwei Ständen · die letzten fünf · geändert: fett',
      ),
      _tabelle(
        kopf: [
          'Zutat',
          'Stand ${_v('Nr.')}',
          'Stand ${_v('Nr.')} (E)',
          'Stand ${_v('Nr.')} *',
        ],
        rechts: const {1, 2, 3},
        breiten: const {
          0: pw.FlexColumnWidth(2.4),
          1: pw.FlexColumnWidth(),
          2: pw.FlexColumnWidth(),
          3: pw.FlexColumnWidth(),
        },
        zeilen: [
          vergleich(_v('Zutat'), 'Menge'),
          vergleich('Verlust', 'Wert'),
          vergleich('Fleischanteil', 'Wert'),
          vergleich('Fett je 100 g', 'Wert'),
          vergleich('Eiweiß je 100 g', 'Wert'),
          vergleich('Salz je 100 g', 'Wert'),
        ],
        hintergruende: [null, for (var i = 0; i < 5; i++) _flaeche],
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: _t(
          '* der Stand dieses Berichts · (E) Entwurf',
          groesse: 7,
          farbe: _grau,
        ),
      ),
    ]),
    _zusammen(s, [
      _abschnitt('Alle Rezepturen des Projekts', zusatz: 'ab zwei Rezepturen'),
      _tabelle(
        kopf: const ['Rezeptur', 'Neuester Stand', 'Status', 'Datum'],
        breiten: const {
          0: pw.FlexColumnWidth(),
          1: pw.FixedColumnWidth(80),
          2: pw.FixedColumnWidth(80),
          3: pw.FixedColumnWidth(62),
        },
        zeilen: [
          [
            _zelle(_v('Rezeptur')),
            _zelle('Stand ${_v('Nr.')}'),
            _zelle(_v('Status')),
            _zelle(_v('Datum')),
          ],
        ],
      ),
    ]),
  ];
}

// ── 3 Produkt und Spezifikation ────────────────────────────────────────

List<pw.Widget> _vorlageProdukt(_Satz s, _Kapitel k) => [
      ..._kapitelKopf(s, k),
      _zusammen(s, [
        _abschnitt('Sensorik'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _felder(
                [
                  for (final l in const [
                    'Aussehen',
                    'Geruch',
                    'Geschmack',
                    'Konsistenz',
                    'Länge',
                    'Durchmesser',
                  ])
                    (l, _v(l)),
                  ('Stückgewicht', '${_v('Gewicht')} ${_v('Toleranz')}'),
                  ('Zubereitung', _v('Zubereitung')),
                ],
                labelBreite: 92,
              ),
            ),
            _vFlaeche(
              'Produktfoto',
              breite: 190,
              hoehe: 142,
              rand: const pw.EdgeInsets.only(left: 14),
            ),
          ],
        ),
      ]),
      _zusammen(s, [
        _abschnitt('Spezifikation'),
        _felder([
          ('Bezeichnung', _v('Bezeichnung')),
          ('Lagerung', _v('Lagerung')),
          ('Haltbarkeit', _v('Haltbarkeit')),
          ('Gewichtstoleranz', _v('Toleranz')),
          ('Spuren möglich', _v('Allergene')),
        ]),
        _etikett('Produkthinweise'),
        _punkt(_v('Hinweis, je Zeile einer')),
      ]),
      _zusammen(s, [
        _abschnitt('Verpackung'),
        _tabelle(
          kopf: const ['', 'Einzelverpackung', 'Umverpackung'],
          breiten: const {
            0: pw.FixedColumnWidth(96),
            1: pw.FlexColumnWidth(),
            2: pw.FlexColumnWidth(),
          },
          zeilen: [
            for (final (l, einzel, um) in [
              ('Verpackung', _v('Art'), _v('Art')),
              ('Füllart', _v('Füllart'), _v('Füllart')),
              (
                'Inhalt',
                '${_v('Anzahl')} Stück',
                '${_v('Anzahl')} Einzelverpackungen',
              ),
              ('Nettogewicht', _v('Gewicht'), _v('Gewicht')),
              ('Tara', _v('Gewicht'), _v('Gewicht')),
              ('Material', _v('Material'), _v('Material')),
              ('Atmosphäre', _v('Atmosphäre'), '-'),
              ('Karton', '-', _v('Aufmachung')),
            ])
              [_zelle(l, farbe: _grau), _zelle(einzel), _zelle(um)],
          ],
        ),
      ]),
      _zusammen(s, [
        _abschnitt(
          'Etikett nach LMIV',
          zusatz:
              '${_v('Anzahl')} von ${kEtikettCheckliste.length} Pflichtangaben '
              'geprüft',
        ),
        _lmivPunkte((_) => LmivStand.offen),
        _vHinweis('Je Angabe: geprüft, offen oder trifft nicht zu.'),
        _etikett('Originaletikett'),
        _t(
          '${_v('Dateiname')} · abgelegt am ${_v('Datum')} · '
          'vergrößerter Ausschnitt, wenn gewählt',
          groesse: 8,
          farbe: _grau,
        ),
        _vFlaeche(
          'Scan des gedruckten Etiketts',
          hoehe: 150,
          rand: const pw.EdgeInsets.only(top: 4),
        ),
      ]),
    ];

// ── 4 Herstellung und HACCP ────────────────────────────────────────────

List<pw.Widget> _vorlageHerstellung(_Satz s, _Kapitel k) => [
      ..._kapitelKopf(s, k),
      _zusammen(s, [
        _abschnitt(
          'Prozess',
          zusatz: '${_v('Version')} · ${_v('Kette in Kürze')}',
        ),
        ..._vStation([
          ('Maschineneinstellungen', _v('Einstellungen, je Zeile eine')),
          (_v('Wert'), _v('eingetragen')),
        ]),
        _vHinweis(
          'Je Station ein Band, darunter ihre Schritte mit Einstellungen — an '
          'Anlagen mit Platten die Platten als Raster.',
        ),
      ]),
      _zusammen(s, [
        _abschnitt(
          'Prozess im Artikel ${_v('Artikelnummer')}',
          zusatz: 'nur, wenn er vom Projekt abweicht',
        ),
        ..._vStation([(_v('Parameter'), _v('Wert'))]),
      ]),
      _zusammen(s, [
        _abschnitt('Festgehaltene Versionen'),
        _tabelle(
          kopf: const ['Version', 'Datum', 'Was sich geändert hat', 'Kette'],
          breiten: const {
            0: pw.FixedColumnWidth(46),
            1: pw.FixedColumnWidth(62),
            2: pw.FlexColumnWidth(),
            3: pw.FixedColumnWidth(110),
          },
          zeilen: [
            [
              _zelle(_v('Nr.'), fett: true),
              _zelle(_v('Datum')),
              _zelle(_v('Notiz zur Version')),
              _zelle(_v('Kette in Kürze'), farbe: _grau),
            ],
          ],
        ),
      ]),
      _zusammen(s, [
        _abschnitt('HACCP-Gefahrenanalyse'),
        _tabelle(
          kopf: const ['Gefahr', 'Art', 'S x W', 'Risiko', 'Maßnahmen'],
          breiten: const {
            0: pw.FlexColumnWidth(2),
            1: pw.FixedColumnWidth(72),
            2: pw.FixedColumnWidth(34),
            3: pw.FixedColumnWidth(54),
            4: pw.FlexColumnWidth(2.4),
          },
          zeilen: [
            [
              _zelle(_v('Gefahr')),
              _zelle(_v('Art'), farbe: _grau),
              _zelle('${_v('S')} x ${_v('W')}'),
              _zelle(_v('Risiko')),
              _zelle(_v('Maßnahmen')),
            ],
          ],
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: _t(
            'S Schwere, W Wahrscheinlichkeit (je 1 bis 3) · Risiko = S x W: '
            '1-2 gering, 3-4 mittel, 6-9 hoch',
            groesse: 7,
            farbe: _grau,
          ),
        ),
      ]),
      _zusammen(s, [
        _abschnitt('Lenkungspunkte'),
        _tabelle(
          kopf: const [
            'Einstufung',
            'Prozessschritt',
            'Lenkung',
            'Entscheidungsbaum',
          ],
          breiten: const {
            0: pw.FixedColumnWidth(58),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FlexColumnWidth(2.4),
            3: pw.FlexColumnWidth(1.4),
          },
          zeilen: [
            [
              _zelle('CCP, CP oder KP'),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _zelle(_v('Schritt')),
                  _zelle(_v('Beschreibung'), farbe: _grau, groesse: 7.5),
                ],
              ),
              _zelle(_v('Lenkung')),
              _zelle(_v('Antworten'), farbe: _grau, groesse: 7.5),
            ],
          ],
        ),
      ]),
    ];

// ── 5 Freigabe und Checkliste ──────────────────────────────────────────

List<pw.Widget> _vorlageFreigabe(_Satz s, _Kapitel k) => [
      ..._kapitelKopf(s, k),
      _zusammen(s, [
        _abschnitt('Freigabe als Artikel'),
        _felder([
          ('Artikel', '${_v('Artikelnummer')} · ${_v('Bezeichnung')}'),
          ('Freigegeben am', _v('Datum')),
          ('Rezepturstand', 'Stand ${_v('Nr.')} · ${_v('Rezeptur')}'),
          ('Produktgruppe', _v('Produktgruppe')),
          ('Haltbarkeit', '${_v('Anzahl')} Tage'),
          ('Allergene', _v('Allergene')),
          ('aw-Wert (Ziel)', _v('Wert')),
        ]),
        _etikett('Verlust in der Produktion'),
        _fliess(
          'Verlust im Mittel der letzten ${_v('Anzahl')} Produktionen: '
          '${_v('Wert')} % — die Rezeptur rechnet mit ${_v('Wert')} %.',
        ),
        _punkt(_v('ob Rezeptur und Produktion zusammenpassen')),
      ]),
      _zusammen(s, [
        _abschnitt('Projekt-Checkliste', zusatz: '${_v('x von y')} erledigt'),
        for (final c in kProjektCheckliste)
          _mitZeichen(
            _Zeichen.offen,
            c.label,
            zusatz: c.schluessel == 'etikettErstellt'
                ? 'Originaletikett hinterlegt oder fehlt noch'
                : null,
          ),
        _vHinweis(
          'Je Punkt: erledigt, offen oder zurückgestellt — mit Vermerk.',
        ),
      ]),
    ];

// ── 6 Entwicklungsweg ──────────────────────────────────────────────────

List<pw.Widget> _vorlageWeg(_Satz s, _Kapitel k) {
  pw.Widget eintrag() => _wegZeile(
        datum: _v('Datum'),
        art: _v('Art'),
        titel: _v('Titel'),
        beschreibung: _v('Beschreibung'),
      );
  pw.Widget klein(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, top: 4),
        child: _t(text, groesse: 8, farbe: _grau),
      );
  return [
    ..._kapitelKopf(
      s,
      k,
      untertitel: 'Von der Idee über die Rezepturstände bis zur Freigabe — '
          'der älteste Schritt zuerst.',
    ),
    _zusammen(s, [
      _abschnitt('Die Stände im Überblick'),
      _tabelle(
        kopf: const [
          'Stand',
          'Status',
          'Datum',
          'Grund',
          'Fleisch',
          'Fett',
          'Salz',
        ],
        rechts: const {4, 5, 6},
        breiten: const {
          0: pw.FixedColumnWidth(34),
          1: pw.FixedColumnWidth(72),
          2: pw.FixedColumnWidth(54),
          3: pw.FlexColumnWidth(2.6),
          4: pw.FixedColumnWidth(42),
          5: pw.FixedColumnWidth(36),
          6: pw.FixedColumnWidth(38),
        },
        zeilen: [
          [
            _zelle(_v('Nr.'), fett: true),
            _zelle(_v('Status')),
            _zelle(_v('Datum')),
            _zelle(_v('Grund für den Stand'), groesse: 7.8),
            _zelle(_v('%')),
            _zelle(_v('g')),
            _zelle(_v('g')),
          ],
        ],
      ),
      _vHinweis('Mit mehreren Rezepturen vorn ihr Name.'),
    ]),
    _zusammen(s, [
      _abschnitt('Der Weg'),
      _wegKopf('START', 'Idee und Anfrage · ${_v('Datum')}', _akzent),
      eintrag(),
    ]),
    _zusammen(s, [
      _wegKopf(
        'STAND ${_v('Nr.')}',
        'abgeschlossen ${_v('Datum')} · freigegeben',
        _station,
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, top: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 60,
              child: _t('Warum', groesse: 8, farbe: _grau),
            ),
            pw.Expanded(
              child: _t(_v('Grund für den Stand'), groesse: 8.5),
            ),
          ],
        ),
      ),
      _kennzahlMarken([
        for (final l in const [
          'Fleischanteil',
          'Energie',
          'Fett',
          'Eiweiß',
          'Salz',
        ])
          (label: l, wert: _v('Wert'), aenderung: _v('Änderung')),
      ]),
      klein('Was sich geändert hat'),
      _punkt(_v('Änderung'), einzug: 12),
      klein('Rückmeldungen dazu'),
      eintrag(),
    ]),
    _zusammen(s, [
      _wegKopf(
        'PHASE',
        '${_v('Phase')} » ${_v('Phase')} · ${_v('Datum')} · ${_v('Anlass')}',
        _phasenFarbe(ProjektStatus.validierung),
      ),
      _punkt(_v('Änderung'), einzug: 12, farbe: _grau),
    ]),
    _zusammen(s, [
      _wegKopf(
        'IN ARBEIT',
        '${_v('Rezeptur')} · Stand ${_v('Nr.')} · Entwurf · zuletzt '
            'geändert ${_v('Datum')}',
        _warn,
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, top: 2),
        child: _t(
          'Fleisch ${_v('Wert')} % · Fett ${_v('Wert')} g · Salz '
          '${_v('Wert')} g je 100 g',
          groesse: 8,
          farbe: _grau,
        ),
      ),
    ]),
  ];
}

// ── 7 Verlauf ──────────────────────────────────────────────────────────

/// Je ein Eintrag jeder Art für den Zeitstrahl der Vorlage — die Daten
/// zeigt die Vorlage nicht.
List<ProjektEintrag> _vorlageEintraege(DateTime jetzt) {
  ProjektEintrag eintrag(
    int i,
    EintragArt art, {
    String status = 'erledigt',
    String? versionId,
  }) =>
      ProjektEintrag(
        id: 'vorlage-$i',
        projektId: 'vorlage',
        art: art.schluessel,
        titel: _v(art.label),
        datum: jetzt.add(Duration(days: i)),
        status: status,
        versionId: versionId,
        createdAt: jetzt,
        updatedAt: jetzt,
      );
  return [
    eintrag(0, EintragArt.meilenstein),
    eintrag(1, EintragArt.email),
    eintrag(2, EintragArt.rezeptur, versionId: 'vorlage'),
    eintrag(3, EintragArt.notiz, status: 'offen'),
    eintrag(4, EintragArt.datei),
    eintrag(5, EintragArt.parameter),
  ];
}

List<pw.Widget> _vorlageVerlauf(_Satz s, _Kapitel k) {
  final eintraege = _vorlageEintraege(s.jetzt);
  final phasen = {
    for (final (i, e) in eintraege.indexed)
      e.id: i < 3
          ? ProjektStatus.entwicklung
          : (i < 5 ? ProjektStatus.validierung : ProjektStatus.produktion),
  };
  return [
    ..._kapitelKopf(
      s,
      k,
      untertitel:
          '${_v('Anzahl')} Einträge vom ${_v('Datum')} bis ${_v('Datum')} · '
          '${_v('Anzahl')} offen, ${_v('Anzahl')} überfällig.',
    ),
    _zusammen(s, [
      _zeitstrahlLegende(eintraege, phasen),
      ..._zeitstrahl(s, eintraege, phasen),
    ]),
    _zusammen(s, [
      _abschnitt('Im Einzelnen', zusatz: 'der älteste Eintrag zuerst'),
      _monat(_v('Monat Jahr')),
      _eintragKopf(
        art: EintragArt.email,
        datum: _v('Datum'),
        titel: _v('Titel'),
        meta: [
          _v('Art'),
          'von ${_v('Name')}',
          'zu Stand ${_v('Nr.')}',
          'Datei: ${_v('Dateiname')}',
          'fällig bis ${_v('Datum')}',
        ].join(' · '),
        marke: _marke('OFFEN', _warn),
      ),
      _eintragText(_v('Text des Eintrags')),
      _eintragNachtrag('Änderungen: ${_v('Änderung')} · ${_v('Änderung')}'),
      _eintragNachtrag('${_v('Name')} (${_v('Datum')}): ${_v('Kommentar')}'),
    ]),
  ];
}

// ── 8 Dateien ──────────────────────────────────────────────────────────

List<pw.Widget> _vorlageDateien(_Satz s, _Kapitel k) => [
      ..._kapitelKopf(
        s,
        k,
        untertitel: 'Die Dateien liegen verschlüsselt in der App — hier, was '
            'es gibt.',
      ),
      _tabelle(
        kopf: const ['Datei', 'Art', 'Größe', 'Abgelegt'],
        rechts: const {2},
        breiten: const {
          0: pw.FlexColumnWidth(),
          1: pw.FixedColumnWidth(54),
          2: pw.FixedColumnWidth(50),
          3: pw.FixedColumnWidth(62),
        },
        zeilen: [
          for (final (name, art) in [
            ('${_v('Dateiname')} (Produktfoto)', 'Bild'),
            ('${_v('Dateiname')} (Originaletikett)', _v('Art')),
            (_v('Dateiname'), _v('Art')),
          ])
            [
              _zelle(name),
              _zelle(art, farbe: _grau),
              _zelle(_v('Größe')),
              _zelle(_v('Datum')),
            ],
        ],
      ),
    ];
