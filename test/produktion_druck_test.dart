import 'dart:convert' show latin1;

import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_optionen.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';
import 'package:produktion_planer/core/services/auftragsbestand_deckung.dart';
import 'package:produktion_planer/features/auftragsbestand/auftragsbestand_ansicht.dart';
import 'package:produktion_planer/features/auftragsbestand/auftragsbestand_druck.dart';
import 'package:produktion_planer/features/auftragsbestand/planung_pruefen.dart';
import 'package:produktion_planer/features/bedarf/bedarf_druck.dart';
import 'package:produktion_planer/features/bedarf/bedarf_modell.dart';
import 'package:produktion_planer/features/erfassung/erfassung_druck.dart';
import 'package:produktion_planer/features/erfassung/geplante_produktion.dart';
import 'package:produktion_planer/features/planung/planungsvorschlag_druck.dart';
import 'package:produktion_planer/features/planung/planungsvorschlag_service.dart';

/// Tests für die Listen der Produktion zum Drucken: Erfassungsliste,
/// Auftragsbestand mit Deckung, Bedarfsliste und Planungsvorschlag — dazu
/// die Wahl im Druckfenster.
///
/// Die PDFs entstehen unkomprimiert — so steht jedes gedruckte Wort als
/// „(Wort)" im Dokument und lässt sich suchen. Alle Daten sind erfunden.
void main() {
  final gedruckt = DateTime(2026, 10, 29, 7, 41);
  final heute = DateTime(2026, 10, 29);

  Future<(DruckErgebnis, String)> setze(DruckDokument d) async {
    final e = await druckSetzen(d, const DruckLayout(), komprimiert: false);
    return (e, latin1.decode(e.bytes));
  }

  Future<String> text(DruckDokument d) async => (await setze(d)).$2;

  /// Die Seitenangaben aller Fußzeilen: („Seite 2 von 3" → (2, 3)).
  List<(int, int)> seitenAngaben(String t) => [
        for (final m in RegExp(
          r'\(Seite\)\]TJ.*?\((\d+)\)\]TJ.*?\(von\)\]TJ.*?\((\d+)\)\]TJ',
          dotAll: true,
        ).allMatches(t))
          (int.parse(m.group(1)!), int.parse(m.group(2)!)),
      ];

  // ── Erfassungsliste ─────────────────────────────────────────────────────

  group('Erfassungsliste', () {
    final mo = DateTime(2026, 11, 2);
    final di = DateTime(2026, 11, 3);
    final mi = DateTime(2026, 11, 4);

    GeplanteProduktion p(
      String id,
      String nummer,
      String name,
      DateTime tag, {
      String abteilung = 'bratstrasse',
      double roh = 1200,
      double? fertig = 950,
      String? start,
      String? notiz,
      int sortierung = 0,
    }) =>
        GeplanteProduktion(
          task: ProductionTask(
            id: id,
            productId: 'p$id',
            mengeKg: roh,
            datum: tag,
            abteilung: abteilung,
            fertigMengeKg: fertig,
            startZeit: start,
            geplanteDauerMinuten: 120,
            geplanteMitarbeiter: 2,
            sortierung: sortierung,
            status: 'geplant',
            notizen: notiz,
            createdAt: gedruckt,
            updatedAt: gedruckt,
          ),
          artikelName: name,
          artikelNummer: nummer,
        );

    Map<DateTime, List<GeplanteProduktion>> woche() => {
          mo: [
            p('1', '10815', 'Rinderpatties', mo, start: '06:00'),
            p('2', '10820', 'Nuggets', mo, notiz: 'Panade frisch'),
          ],
          mi: [p('3', '20417', 'Leberkäse', mi, fertig: null)],
        };

    test('Standard: die Tage mit Produktionen, Spalten zum Eintragen',
        () async {
      final auftrag = erfassungDruckAuftrag(
        montag: mo,
        gruppen: woche(),
        gedrucktAm: gedruckt,
      );
      final wahl = DruckWahl.standard(auftrag.optionen);
      expect(wahl.mehrere(ErfassungDruckWahl.tage), {'1', '3'});
      // Nur eine Abteilung — nichts zu wählen.
      expect(
        auftrag.optionen.map((o) => o.schluessel),
        isNot(contains(ErfassungDruckWahl.abteilungen)),
      );

      final dokument = await auftrag.bauen(wahl);
      final (e, t) = await setze(dokument);
      expect(e.format.width, greaterThan(e.format.height), reason: 'quer');
      expect(dokument.dateiname, 'Produktionserfassung_KW_45');
      for (final wort in [
        'Produktionserfassung',
        'Montag,',
        'Mittwoch,',
        '10815',
        'Rinderpatties',
        'Plan:',
        '1.200',
        'Rohware',
        'Fertigware',
        'Start',
        '06:00',
        'Panade',
        'Ende',
        'Charge',
        'Kürzel',
        'Bemerkung',
        'Ist-Werte',
      ]) {
        expect(t, contains('($wort)'), reason: wort);
      }
      expect(t, isNot(contains('(Dienstag,)')));
      // Ohne Abteilungsspalte bei nur einer Abteilung.
      expect(t, isNot(contains('(Abt.)')));
    });

    test('der Plan in einer Zeile — ohne Fertigmenge nur die Rohware', () {
      final x = p('9', '1', 'X', mo, roh: 80, fertig: null, start: ' ');
      expect(
        erfassungPlanText(x),
        'Plan: 80 kg Rohware',
      );
      final y = p('8', '1', 'Y', mo, notiz: 'erste Zeile\nzweite Zeile');
      expect(
        erfassungPlanText(y),
        'Plan: 1.200 kg Rohware · 950 kg Fertigware · erste Zeile',
      );
    });

    test('in der Reihenfolge des Plans: Abteilung, Board, Startzeit',
        () async {
      final t = await text(
        erfassungDruck(
          montag: mo,
          gruppen: {
            mo: [
              p('1', '30003', 'C', mo, abteilung: 'verpackung'),
              p('2', '30002', 'B', mo, start: '09:00'),
              p('3', '30001', 'A', mo, start: '07:00'),
              p('4', '30004', 'D', mo, sortierung: -1),
            ],
          },
          gedrucktAm: gedruckt,
        ),
      );
      final reihe = [
        for (final n in ['30004', '30001', '30002', '30003'])
          t.indexOf('($n)'),
      ];
      expect(reihe.every((i) => i >= 0), isTrue);
      expect([...reihe]..sort(), reihe);
      // Zwei Abteilungen: die Spalte nennt sie.
      expect(t, contains('(Abt.)'));
      expect(t, contains('(VP)'));
    });

    test('je Tag ein Blatt mit eigener Seitenzählung', () async {
      final auftrag = erfassungDruckAuftrag(
        montag: mo,
        gruppen: woche(),
        gedrucktAm: gedruckt,
      );
      final dokument = await auftrag.bauen(
        DruckWahl.standard(auftrag.optionen)
            .mit(ErfassungDruckWahl.aufteilung, 'tage'),
      );
      final (e, t) = await setze(dokument);
      expect(e.blattSeiten, [1, 1]);
      expect(seitenAngaben(t), [(1, 1), (1, 1)]);
      // Der Kopf nennt den Tag.
      expect(t, contains('(November)'));
      expect(t, contains('(02.11.2026)'));
    });

    test('Spalten abwählen, ohne Plan und ohne leere Zeilen', () async {
      final auftrag = erfassungDruckAuftrag(
        montag: mo,
        gruppen: woche(),
        gedrucktAm: gedruckt,
      );
      final wahl = DruckWahl.standard(auftrag.optionen)
          .mit(ErfassungDruckWahl.charge, false)
          .mit(ErfassungDruckWahl.kuerzel, false)
          .mit(ErfassungDruckWahl.bemerkung, false)
          .mit(ErfassungDruckWahl.plan, false);
      final t = await text(await auftrag.bauen(wahl));
      expect(t, contains('(Rohware)'));
      expect(t, contains('(Ende)'));
      expect(t, isNot(contains('(Charge)')));
      expect(t, isNot(contains('(Kürzel)')));
      expect(t, isNot(contains('(Bemerkung)')));
      expect(t, isNot(contains('(Plan:)')));

      // Ohne leere Zeilen weniger zu zeichnen.
      final mit = await text(await auftrag.bauen(wahl));
      final ohne = await text(
        await auftrag.bauen(wahl.mit(ErfassungDruckWahl.leer, false)),
      );
      expect(ohne.length, lessThan(mit.length));
    });

    test('Abteilungen wählbar, wenn es mehrere gibt', () async {
      final gruppen = {
        mo: [
          p('1', '10815', 'Rinderpatties', mo),
          p('2', '40001', 'Aufschnitt', mo, abteilung: 'schneideabteilung'),
        ],
      };
      final auftrag = erfassungDruckAuftrag(
        montag: mo,
        gruppen: gruppen,
        gedrucktAm: gedruckt,
      );
      final wahl = DruckWahl.standard(auftrag.optionen);
      expect(
        wahl.mehrere(ErfassungDruckWahl.abteilungen),
        {'bratstrasse', 'schneideabteilung'},
      );
      final t = await text(
        await auftrag.bauen(
          wahl.mit(ErfassungDruckWahl.abteilungen, {'schneideabteilung'}),
        ),
      );
      expect(t, contains('(40001)'));
      expect(t, isNot(contains('(10815)')));
      // Auf dem Blatt steht nur noch eine Abteilung.
      expect(t, isNot(contains('(Abt.)')));

      expect(
        () => auftrag.bauen(
          wahl.mit(ErfassungDruckWahl.abteilungen, <String>{}),
        ),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
    });

    test('eine leere Woche: alle Tage, leere Zeilen zum Eintragen', () async {
      final auftrag = erfassungDruckAuftrag(
        montag: mo,
        gruppen: const {},
        gedrucktAm: gedruckt,
      );
      final wahl = DruckWahl.standard(auftrag.optionen);
      expect(wahl.mehrere(ErfassungDruckWahl.tage), {'1', '2', '3', '4', '5'});
      final t = await text(await auftrag.bauen(wahl));
      expect(t, contains('(Freitag,)'));
      expect(t, contains('(Charge)'));

      final ohne = await text(
        await auftrag.bauen(wahl.mit(ErfassungDruckWahl.leer, false)),
      );
      expect(ohne, contains('(Nichts)'));
      expect(ohne, isNot(contains('(Charge)')));

      expect(
        () => auftrag.bauen(wahl.mit(ErfassungDruckWahl.tage, <String>{})),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
    });

    test('ein langer Tag läuft über die Seite — mit dem Tag im Kopf',
        () async {
      final (e, t) = await setze(
        erfassungDruck(
          montag: mo,
          gruppen: {
            mo: [p('0', '1', 'Erster', mo)],
            di: [
              for (var i = 0; i < 30; i++)
                p('d$i', '${50000 + i}', 'Artikel $i', di),
            ],
          },
          gedrucktAm: gedruckt,
        ),
      );
      expect(e.seiten, greaterThan(1));
      // Die Kopfzeile der Tabelle nennt den Tag — auch auf der nächsten
      // Seite. Dazu einmal die Leiste über dem Tag.
      expect(
        RegExp(r'\(03\.11\.\)').allMatches(t).length,
        greaterThanOrEqualTo(3),
      );
    });
  });

  // ── Auftragsbestand ─────────────────────────────────────────────────────

  group('Auftragsbestand', () {
    final mo = DateTime(2026, 11, 2);
    final di = DateTime(2026, 11, 3);
    final mi = DateTime(2026, 11, 4);
    final fr = DateTime(2026, 11, 6);
    final spaeter = DateTime(2026, 11, 16);
    var id = 0;

    AuftragsPosition pos(
      String beleg,
      String kunde,
      DateTime tag,
      double kg, {
      String einheit = 'KG',
    }) =>
        AuftragsPosition(
          id: ++id,
          artikelnummer: '',
          beleg: beleg,
          debitor: kunde,
          warenausgang: tag,
          menge: kg,
          einheit: einheit,
          kg: kg,
        );

    AuftragsbestandZeile artikel(
      String nummer,
      String name,
      double lager,
      List<AuftragsPosition> positionen, {
      List<ProduktionsZugang> zugaenge = const [],
      List<Vormerkung> vormerkungen = const [],
      Map<String, PlanungsKonflikt> verschoben = const {},
    }) {
      final p = [
        for (final x in positionen) x.copyWith(artikelnummer: nummer),
      ];
      return AuftragsbestandZeile(
        artikel: AuftragsArtikel(
          artikelnummer: nummer,
          bezeichnung: name,
          lagerKg: lager,
          auftragKg: p.fold<double>(0, (s, x) => s + x.kg),
          importiertAm: gedruckt,
        ),
        positionen: p,
        zugaenge: zugaenge,
        vormerkungen: vormerkungen,
        verschoben: verschoben,
        deckung: berechneDeckung(
          lagerKg: lager,
          positionen: p,
          zugaenge: zugaenge,
          vormerkungen: vormerkungen,
          gesperrt: verschoben.keys.toSet(),
        ),
      );
    }

    // 10001 fehlt am Montag, 10002 ist aus dem Lager gedeckt, 10003 ist
    // beim Planungsvorschlag vorgemerkt, 10004 kommt zu spät, 10005 ist
    // verschoben, 10006 hat nur einen späten Versandtag.
    AuftragsbestandAnsicht bestand({DateTime? berichtTag}) =>
        AuftragsbestandAnsicht(
          stand: DateTime(2026, 10, 29, 6, 12),
          importiertAm: gedruckt,
          berichtTag: berichtTag ?? heute,
          zeilen: [
            artikel('10001', 'Fehlt am Montag', 100, [
              pos('A1', 'Kunde Nord', mo, 300),
              pos('A2', 'Kunde Süd', fr, 50),
            ]),
            artikel('10002', 'Aus dem Lager', 1000, [
              pos('B1', 'Kunde Nord', di, 400),
            ]),
            artikel(
              '10003',
              'Vorgemerkt',
              0,
              [pos('C1', 'Kunde Ost', mi, 200)],
              vormerkungen: [
                Vormerkung(
                  bedarfId: 'v1',
                  offenKg: 200,
                  termin: di,
                  bezuege: [
                    AuftragsBezug(
                      beleg: 'C1',
                      warenausgang: mi,
                      kg: 200,
                      debitor: 'Kunde Ost',
                    ),
                  ],
                ),
              ],
            ),
            artikel(
              '10004',
              'Zu spät eingeplant',
              0,
              [pos('D1', 'Kunde West', di, 120)],
              zugaenge: [
                ProduktionsZugang(
                  kettenId: 'k1',
                  productId: 'p4',
                  fertigAm: mi,
                  art: ZugangsArt.eingeplant,
                  kg: 120,
                ),
              ],
            ),
            artikel(
              '10005',
              'Verschoben',
              0,
              [pos('E1', '', mi, 75)],
              verschoben: {
                auftragsZeilenSchluessel('E1', mi): PlanungsKonflikt(
                  art: PruefArt.verschoben,
                  artikelnummer: '10005',
                  beleg: 'E1',
                  warenausgang: di,
                  neuerWarenausgang: mi,
                  verplant: const [],
                ),
              },
            ),
            artikel('10006', 'Erst später', 0, [
              pos('F1', 'Kunde Nord', spaeter, 90),
            ]),
          ],
        );

    test('Lage eines Artikels in Worten', () {
      final z = {for (final x in bestand().zeilen) x.artikel.artikelnummer: x};
      expect(artikelLage(z['10001']!.deckung).lage, DeckungsLage.fehlt);
      expect(
        artikelLage(z['10001']!.deckung).text,
        'fehlt 250 kg ab Mo 02.11.',
      );
      expect(artikelLage(z['10002']!.deckung).text, 'Lager reicht');
      expect(
        artikelLage(z['10003']!.deckung).text,
        'vorgemerkt · spätestens Di 03.11.',
      );
      expect(
        artikelLage(z['10004']!.deckung).text,
        'zu spät eingeplant · Di 03.11.',
      );
      expect(
        lagerSatz(z['10001']!.deckung),
        'Der Lagerbestand von 100 kg deckt am Mo 02.11. 100 von 300 kg.',
      );
      expect(
        lagerSatz(z['10002']!.deckung),
        'Der Lagerbestand von 1.000 kg deckt alle Aufträge — 600 kg '
        'bleiben übrig.',
      );
    });

    test('Reihenfolge: frühester Engpass, nach Nummer, nach Fehlmenge', () {
      final zeilen = bestand().zeilen;
      List<String> nummern(BestandSortierung s) => [
            for (final z in sortiereBestand(zeilen, s))
              z.artikel.artikelnummer,
          ];
      expect(nummern(BestandSortierung.nummer).first, '10001');
      final engpass = nummern(BestandSortierung.engpass);
      // Erst, was Arbeit macht — 10001 fehlt am Montag.
      expect(engpass.first, '10001');
      // Lager und Vormerkung zuletzt.
      expect(engpass.indexOf('10002'), greaterThan(engpass.indexOf('10006')));
      expect(nummern(BestandSortierung.fehlmenge).first, '10001');
    });

    test('was auf den Ausdruck kommt: Handlungsbedarf, ungedeckt, alles',
        () {
      final z = {for (final x in bestand().zeilen) x.artikel.artikelnummer: x};
      TagesDeckung tag(String nr) => z[nr]!.deckung.tage.first;
      bool zeigt(String nr, BestandUmfang u) =>
          bestandTagZeigen(tag(nr), u, verschoben: z[nr]!.verschoben);

      expect(zeigt('10001', BestandUmfang.handlung), isTrue);
      expect(zeigt('10002', BestandUmfang.handlung), isFalse);
      expect(zeigt('10002', BestandUmfang.alle), isTrue);
      // Vorgemerkt: keine Arbeit mehr hier, aber noch nicht gedeckt.
      expect(zeigt('10003', BestandUmfang.handlung), isFalse);
      expect(zeigt('10003', BestandUmfang.ungedeckt), isTrue);
      expect(zeigt('10004', BestandUmfang.handlung), isTrue);
      expect(zeigt('10005', BestandUmfang.handlung), isTrue);

      final zeile = tag('10005').zeilen.single;
      expect(
        bestandZeileZeigen(
          zeile,
          BestandUmfang.handlung,
          verschoben: z['10005']!.verschoben,
        ),
        isTrue,
      );
      expect(
        bestandZeileZeigen(tag('10002').zeilen.single, BestandUmfang.ungedeckt),
        isFalse,
      );
    });

    test('Zeitraum: spätere Versandtage fallen weg, die Rechnung bleibt', () {
      final d = bestand().zeilen.first.deckung;
      final bis = bestandImZeitraum(d, mo);
      expect(bis.tage, hasLength(1));
      expect(bis.offenKg, 200);
      expect(bestandImZeitraum(d, null), same(d));
    });

    test('nach Artikel: nur mit Handlungsbedarf, Tage und Hinweis', () async {
      final dokument = bestandDruck(
        bestand(),
        heute: heute,
        gedrucktAm: gedruckt,
      );
      final (e, t) = await setze(dokument);
      expect(e.format.width, greaterThan(e.format.height), reason: 'quer');
      expect(dokument.dateiname, 'Auftragsbestand_2026-10-29');
      for (final wort in [
        'Auftragsbestand',
        '10001',
        '10004',
        '10005',
        '10006',
        'fehlt',
        'noch',
        'einzuplanen',
        'Stand',
        'Mo',
        '02.11.',
        'verschoben',
        'Handlungsbedarf',
      ]) {
        expect(t, contains('($wort)'), reason: wort);
      }
      // Gedeckt oder vorgemerkt: nicht auf diesem Ausdruck.
      expect(t, isNot(contains('(10002)')));
      expect(t, isNot(contains('(10003)')));
      // Der Bericht ist von heute — keine Warnung.
      expect(t, isNot(contains('(frisch)')));
    });

    test('nach Artikel: alles, mit Aufträgen, Vormerkungen, Produktionen',
        () async {
      final t = await text(
        bestandDruck(
          bestand(),
          heute: heute,
          gedrucktAm: gedruckt,
          inhalt: const BestandDruckInhalt(
            umfang: BestandUmfang.alle,
            tiefe: BestandTiefe.auftraege,
            sortierung: BestandSortierung.nummer,
          ),
        ),
      );
      for (final wort in [
        '10002',
        '10003',
        'A1',
        'Kunde',
        'Nord',
        'Vorgemerkt,',
        'Produktion',
        'reicht',
        'Lager',
      ]) {
        expect(t, contains('($wort)'), reason: wort);
      }
      expect(t.indexOf('(10001)'), lessThan(t.indexOf('(10002)')));
      expect(t.indexOf('(10005)'), lessThan(t.indexOf('(10006)')));
    });

    test('eine Zeile je Artikel — ohne Versandtage', () async {
      final t = await text(
        bestandDruck(
          bestand(),
          heute: heute,
          gedrucktAm: gedruckt,
          inhalt: const BestandDruckInhalt(tiefe: BestandTiefe.artikel),
        ),
      );
      expect(t, contains('(10001)'));
      // Der Freitag von 10001 stünde nur in seiner Zeile.
      expect(t, isNot(contains('(Fr)')));
    });

    test('hinter den gezeigten Tagen: wie viele es noch gibt', () async {
      final ansicht = AuftragsbestandAnsicht(
        stand: DateTime(2026, 10, 29, 6),
        berichtTag: heute,
        zeilen: [
          artikel('20001', 'Zum Teil', 500, [
            pos('G1', 'Kunde Nord', mo, 500),
            pos('G2', 'Kunde Nord', fr, 80),
          ]),
        ],
      );
      final t = await text(
        bestandDruck(ansicht, heute: heute, gedrucktAm: gedruckt),
      );
      expect(t, contains('(Fr)'));
      expect(t, contains('(Versandtag)'));
      expect(t, contains('(ohne)'));
    });

    test('nach Versandtag: Tage als Abschnitte, Aufträge einzeln', () async {
      final t = await text(
        bestandDruck(
          bestand(),
          heute: heute,
          gedrucktAm: gedruckt,
          inhalt: const BestandDruckInhalt(
            gliederung: BestandGliederung.versandtag,
            umfang: BestandUmfang.ungedeckt,
            auftraegeEinzeln: true,
          ),
        ),
      );
      expect(t, contains('(Montag,)'));
      expect(t, contains('(Mittwoch,)'));
      expect(t, contains('(A1)'));
      // Ungedeckt: der vorgemerkte Artikel ist dabei, der gedeckte nicht.
      expect(t, contains('(10003)'));
      expect(t, isNot(contains('(10002)')));
      expect(t.indexOf('(Montag,)'), lessThan(t.indexOf('(Mittwoch,)')));
    });

    test('nach Kunde: alphabetisch, ohne Kunde zuletzt', () async {
      final t = await text(
        bestandDruck(
          bestand(),
          heute: heute,
          gedrucktAm: gedruckt,
          inhalt: const BestandDruckInhalt(
            gliederung: BestandGliederung.kunde,
            umfang: BestandUmfang.alle,
          ),
        ),
      );
      final nord = t.indexOf('(Nord)');
      final ost = t.indexOf('(Ost)');
      final west = t.indexOf('(West)');
      final ohne = t.indexOf('(Ohne)');
      expect([nord, ost, west, ohne].every((i) => i >= 0), isTrue);
      expect(nord, lessThan(ost));
      expect(ost, lessThan(west));
      expect(west, lessThan(ohne));
      expect(t, contains('(B1)'));
    });

    test('gefiltert und bis Ende der Woche', () async {
      final t = await text(
        bestandDruck(
          bestand(),
          heute: heute,
          gedrucktAm: gedruckt,
          inhalt: BestandDruckInhalt(
            umfang: BestandUmfang.alle,
            nurArtikel: const {'10001', '10006'},
            filterText: 'Suche „Probe“',
            versandBis: DateTime(2026, 11, 8),
          ),
        ),
      );
      expect(t, contains('(10001)'));
      // Nur ein Versandtag nach dem Zeitraum.
      expect(t, isNot(contains('(10006)')));
      expect(t, isNot(contains('(10002)')));
      expect(t, contains('(gefiltert:)'));
      expect(t, contains('("Probe")'));
    });

    test('ein Bericht von gestern wird angemerkt', () async {
      final t = await text(
        bestandDruck(
          bestand(berichtTag: DateTime(2026, 10, 28)),
          heute: heute,
          gedrucktAm: gedruckt,
        ),
      );
      expect(t, contains('(frisch)'));
    });

    test('nichts zu tun: ein Hinweis statt einer leeren Tabelle', () async {
      final ansicht = AuftragsbestandAnsicht(
        stand: DateTime(2026, 10, 29, 6),
        berichtTag: heute,
        zeilen: [
          artikel('30001', 'Gedeckt', 1000, [pos('H1', 'Kunde', mo, 10)]),
        ],
      );
      final t = await text(
        bestandDruck(ansicht, heute: heute, gedrucktAm: gedruckt),
      );
      expect(t, contains('(Nichts)'));
      expect(t, isNot(contains('(30001)')));
    });

    test('Druckfenster: Vorwahl wie die Liste, Filter nur wenn gesetzt',
        () async {
      final ansicht = bestand();
      final ohneFilter = bestandDruckAuftrag(
        ansicht,
        heute: heute,
        nurHandlung: false,
        sortierung: BestandSortierung.nummer,
        gedrucktAm: gedruckt,
      );
      final wahl = DruckWahl.standard(ohneFilter.optionen);
      expect(wahl.eins(BestandDruckWahl.umfang), BestandUmfang.alle.name);
      expect(
        wahl.eins(BestandDruckWahl.sortierung),
        BestandSortierung.nummer.name,
      );
      expect(
        ohneFilter.optionen.map((o) => o.schluessel),
        isNot(contains(BestandDruckWahl.gefiltert)),
      );
      // Reihenfolge und Tiefe nur in der Gliederung nach Artikel.
      final sortierung = ohneFilter.optionen
          .firstWhere((o) => o.schluessel == BestandDruckWahl.sortierung);
      expect(sortierung.istSichtbar(wahl), isTrue);
      expect(
        sortierung.istSichtbar(
          wahl.mit(
            BestandDruckWahl.gliederung,
            BestandGliederung.kunde.name,
          ),
        ),
        isFalse,
      );

      final mitFilter = bestandDruckAuftrag(
        ansicht,
        heute: heute,
        gefiltert: const {'10004'},
        filterText: 'Abteilung Bratstraße',
        gedrucktAm: gedruckt,
      );
      final w = DruckWahl.standard(mitFilter.optionen);
      expect(w.an(BestandDruckWahl.gefiltert), isTrue);
      final t = await text(await mitFilter.bauen(w));
      expect(t, contains('(10004)'));
      expect(t, isNot(contains('(10001)')));

      // Bis Ende dieser Woche: Der Do 29.10. gehört zur Woche bis So 01.11.
      final woche = await mitFilter.bauen(
        w
            .mit(BestandDruckWahl.gefiltert, false)
            .mit(BestandDruckWahl.zeitraum, 'woche'),
      );
      final tw = await text(woche);
      expect(tw, contains('(Keine)'));
    });
  });

  // ── Bedarfsliste ────────────────────────────────────────────────────────

  group('Bedarfsliste', () {
    BedarfInfo bedarf(
      String id,
      String nummer,
      String name,
      double kg, {
      DateTime? termin,
      String quelle = 'bestellung',
      String? notiz,
      int prio = 0,
      double geplant = 0,
      double produziert = 0,
      bool vonHand = false,
    }) =>
        BedarfInfo(
          bedarf: Demand(
            id: id,
            productId: 'p$id',
            mengeKgFertig: kg,
            termin: termin,
            quelle: quelle,
            prioritaet: prio,
            notizen: notiz,
            manuellErledigt: vonHand,
            createdAt: gedruckt,
            updatedAt: gedruckt,
          ),
          artikelName: name,
          artikelNummer: nummer,
          geplantKg: geplant,
          produziertKg: produziert,
          heute: heute,
        );

    List<BedarfInfo> liste() => [
          bedarf(
            '1',
            '10815',
            'Rinderpatties',
            500,
            termin: DateTime(2026, 10, 27),
            notiz: 'Telefonisch',
            prio: 1,
            geplant: 200,
          ),
          bedarf(
            '2',
            '20417',
            'Leberkäse',
            800,
            termin: DateTime(2026, 11, 3),
            quelle: kQuelleAuftragsbestand,
          ),
          bedarf(
            '3',
            '10833',
            'Frikadellen',
            1200,
            termin: DateTime(2026, 11, 10),
          ),
          bedarf('4', '10834', 'Cevapcici', 150, quelle: 'sonstiges'),
          bedarf(
            '5',
            '10820',
            'Nuggets',
            400,
            termin: DateTime(2026, 10, 20),
            geplant: 400,
            produziert: 400,
          ),
        ];

    test('nach Termin: überfällig, je Woche, ohne Termin', () async {
      final dokument = bedarfDruck(liste(), heute: heute, gedrucktAm: gedruckt);
      final (e, t) = await setze(dokument);
      expect(e.format.height, greaterThan(e.format.width), reason: 'hoch');
      expect(dokument.dateiname, 'Bedarfsliste_2026-10-29');
      for (final wort in [
        'Bedarfsliste',
        'Überfällig',
        'KW',
        '45',
        '46',
        'Ohne',
        'Termin',
        'Telefonisch',
        'Auftragsbestand',
        '300',
        '!',
      ]) {
        expect(t, contains('($wort)'), reason: wort);
      }
      final reihe = [
        for (final n in ['10815', '20417', '10833', '10834']) t.indexOf('($n)'),
      ];
      expect(reihe.every((i) => i >= 0), isTrue);
      expect([...reihe]..sort(), reihe);
      // Gedeckt: nicht auf der Liste der offenen.
      expect(t, isNot(contains('(10820)')));
    });

    test('auch erledigte — am Ende, als gedeckt', () async {
      final t = await text(
        bedarfDruck(
          liste(),
          heute: heute,
          gedrucktAm: gedruckt,
          inhalt: const BedarfDruckInhalt(mitErledigten: true),
        ),
      );
      expect(t, contains('(Erledigt)'));
      expect(t, contains('(gedeckt)'));
      expect(t.indexOf('(10834)'), lessThan(t.indexOf('(10820)')));
    });

    test('nach Artikelnummer, ohne Notizen', () async {
      final t = await text(
        bedarfDruck(
          liste(),
          heute: heute,
          gedrucktAm: gedruckt,
          inhalt: const BedarfDruckInhalt(nachArtikel: true, notizen: false),
        ),
      );
      expect(t.indexOf('(10815)'), lessThan(t.indexOf('(10833)')));
      expect(t.indexOf('(10834)'), lessThan(t.indexOf('(20417)')));
      expect(t, isNot(contains('(Überfällig)')));
      expect(t, isNot(contains('(Telefonisch)')));
    });

    test('Druckfenster: Herkunft wählbar, nur was vorkommt', () async {
      final auftrag = bedarfDruckAuftrag(
        liste(),
        heute: heute,
        gedrucktAm: gedruckt,
      );
      final wahl = DruckWahl.standard(auftrag.optionen);
      expect(
        wahl.mehrere(BedarfDruckWahl.herkunft),
        {'bestellung', 'sonstiges', kQuelleAuftragsbestand},
      );
      final t = await text(
        await auftrag.bauen(
          wahl.mit(BedarfDruckWahl.herkunft, {kQuelleAuftragsbestand}),
        ),
      );
      expect(t, contains('(20417)'));
      expect(t, isNot(contains('(10815)')));
      expect(
        () => auftrag.bauen(wahl.mit(BedarfDruckWahl.herkunft, <String>{})),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );

      final einerlei = bedarfDruckAuftrag(
        [liste().first],
        heute: heute,
      );
      expect(
        einerlei.optionen.map((o) => o.schluessel),
        isNot(contains(BedarfDruckWahl.herkunft)),
      );
    });

    test('Herkunft in Worten', () {
      expect(bedarfQuelleText('bestand'), 'Bestand');
      expect(bedarfQuelleText(kQuelleAuftragsbestand), 'Auftragsbestand');
      expect(bedarfQuelleText('neu'), 'neu');
    });
  });

  // ── Planungsvorschlag ───────────────────────────────────────────────────

  group('Planungsvorschlag', () {
    final di = DateTime(2026, 11, 3);
    final mi = DateTime(2026, 11, 4);
    final do_ = DateTime(2026, 11, 5);

    VorschlagPosten posten(
      String nummer,
      double kg, {
      WechselGrund grund = WechselGrund.ohneUmstellung,
      double neben = 0,
      DateTime? termin,
      List<AuftragsBezug> bezuege = const [],
      int allergen = 0,
    }) =>
        VorschlagPosten(
          bedarfId: 'b$nummer',
          productId: 'p$nummer',
          artikelnummer: nummer,
          bezeichnung: 'Artikel $nummer',
          mengeKg: kg,
          rohwareKg: kg * 1.25,
          dauerMinuten: kg / 4,
          ausHistorie: false,
          nebenzeitMinuten: neben,
          wechselGrund: grund,
          begruendung: 'gegart',
          allergenRang: allergen,
          bioRang: 0,
          rohRang: 0,
          plattenTemp: 180,
          hoehe: 20,
          ausgangsMengeKg: kg,
          termin: termin,
          auftragsBezuege: bezuege,
        );

    VorschlagTag tag(
      DateTime t,
      List<VorschlagPosten> p, {
      List<String> warnungen = const [],
    }) =>
        VorschlagTag(
          tag: t,
          posten: p,
          kapazitaetMinuten: 450,
          belegtVorherMinuten: 0,
          endreinigungMinuten: 45,
          warnungen: warnungen,
        );

    List<VorschlagTag> tage() => [
          tag(
            di,
            [
              posten('10820', 300, grund: WechselGrund.tagesstart),
              posten(
                '10815',
                300,
                grund: WechselGrund.umstellen,
                neben: 20,
                termin: DateTime(2026, 10, 27),
              ),
              // Von Hand nach vorn: weniger Allergene nach mehr.
              posten(
                '20417',
                800,
                grund: WechselGrund.reinigen,
                neben: 45,
                allergen: -1,
                bezuege: [
                  AuftragsBezug(
                    beleg: '700120',
                    warenausgang: mi,
                    kg: 800,
                    debitor: 'Kunde Nord',
                  ),
                ],
              ),
            ],
            warnungen: ['Verpackung läuft über.'],
          ),
          tag(mi, const []),
          tag(do_, [posten('10833', 1200, grund: WechselGrund.tagesstart)]),
        ];

    const nichtPlanbar = [
      NichtPlanbar(
        artikelnummer: '10834',
        bezeichnung: 'Cevapcici',
        mengeKg: 150,
        grund: 'Keine Leistungsdaten',
      ),
    ];

    test('die Tage mit Aufträgen, Wechsel, Termin, nicht Eingeplantes',
        () async {
      final dokument = vorschlagDruck(
        tage: tage(),
        einstellungen: const VorschlagEinstellungen(),
        nichtPlanbar: nichtPlanbar,
        gedrucktAm: gedruckt,
      );
      final (e, t) = await setze(dokument);
      expect(e.blaetter, 1);
      expect(dokument.dateiname, 'Planungsvorschlag_2026-11-03');
      for (final wort in [
        'Planungsvorschlag',
        'Entwurf',
        'Dienstag,',
        'Donnerstag,',
        'umrüsten',
        'reinigen',
        '0:45',
        'Termin',
        'Auftragsbestand,',
        'Verpackung',
        'Nicht',
        'eingeplant',
        'Leistungsdaten',
        'Rüsten',
        'Endreinigung',
      ]) {
        expect(t, contains('($wort)'), reason: wort);
      }
      // Der Tag ohne Aufträge steht nicht da.
      expect(t, isNot(contains('(Mittwoch,)')));
      // Der Regelbruch steht unter dem Tag.
      expect(t, contains('(Allergene)'));
    });

    test('übernommen und angepasst, Aufträge je Artikel', () async {
      final t = await text(
        vorschlagDruck(
          tage: tage(),
          einstellungen: const VorschlagEinstellungen(),
          uebernommen: {do_},
          angepasst: true,
          inhalt: const VorschlagDruckInhalt(auftraege: true),
          gedrucktAm: gedruckt,
        ),
      );
      expect(t, contains('(Board)'));
      expect(t, contains('(angepasst.)'));
      expect(t, contains('(für)'));
      expect(t, contains('(Nord)'));
      expect(t, isNot(contains('(Auftragsbestand,)')));
    });

    test('je Tag ein Blatt, die Liste des nicht Eingeplanten extra',
        () async {
      final (e, t) = await setze(
        vorschlagDruck(
          tage: tage(),
          einstellungen: const VorschlagEinstellungen(),
          nichtPlanbar: nichtPlanbar,
          inhalt: const VorschlagDruckInhalt(jeTag: true, hinweise: false),
          gedrucktAm: gedruckt,
        ),
      );
      expect(e.blaetter, 3);
      expect(seitenAngaben(t), [(1, 1), (1, 1), (1, 1)]);
      expect(t, isNot(contains('(Allergene)')));
      expect(t, isNot(contains('(läuft)')));
    });

    test('Druckfenster: nur Tage mit Aufträgen, mindestens einer', () async {
      final auftrag = vorschlagDruckAuftrag(
        tage: tage(),
        einstellungen: const VorschlagEinstellungen(),
        uebernommen: {do_},
        gedrucktAm: gedruckt,
      );
      final wahl = DruckWahl.standard(auftrag.optionen);
      expect(wahl.mehrere(VorschlagDruckWahl.tage), {
        '2026-11-03',
        '2026-11-05',
      });
      // Ohne nicht Eingeplantes kein Schalter dafür.
      expect(
        auftrag.optionen.map((o) => o.schluessel),
        isNot(contains(VorschlagDruckWahl.nichtPlanbar)),
      );
      final t = await text(
        await auftrag.bauen(
          wahl.mit(VorschlagDruckWahl.tage, {'2026-11-05'}),
        ),
      );
      expect(t, contains('(10833)'));
      expect(t, isNot(contains('(10820)')));
      // Ein einziger Tag — und der ist übernommen.
      expect(t, contains('(übernommen.)'));

      expect(
        () => auftrag.bauen(wahl.mit(VorschlagDruckWahl.tage, <String>{})),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
    });
  });
}
