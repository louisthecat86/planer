import 'dart:convert' show latin1;

import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart'
    show WeekSnapshot;
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_optionen.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';
import 'package:produktion_planer/core/services/week_snapshot_service.dart';
import 'package:produktion_planer/features/board/board_druck_dialog.dart';
import 'package:produktion_planer/features/board/board_print_service.dart';
import 'package:produktion_planer/features/board/board_providers.dart';
import 'package:produktion_planer/features/history/wochenauswertung_druck.dart';
import 'package:produktion_planer/features/history/wochenuebersicht_druck.dart';

import 'helpers/archiv_beispiele.dart';

/// Tests für die Ausdrucke aus dem Archiv: der Wochenplan, wie er beim
/// Archivieren stand, die Auswertung einer Woche und die Wochen im
/// Überblick — dazu die Wahl im Druckfenster.
///
/// Die PDFs entstehen unkomprimiert — so steht jedes gedruckte Wort als
/// „(Wort)" im Dokument und lässt sich suchen. Alle Daten sind erfunden.
void main() {
  final gedruckt = DateTime(2026, 10, 30, 16, 12);
  final dienstag = DateTime(2026, 10, 27);
  final donnerstag = DateTime(2026, 10, 29);

  Future<(DruckErgebnis, String)> setze(DruckDokument d) async {
    final e = await druckSetzen(d, const DruckLayout(), komprimiert: false);
    return (e, latin1.decode(e.bytes));
  }

  Future<String> text(DruckDokument d) async => (await setze(d)).$2;

  Future<String> gebaut(DruckAuftrag a, [DruckWahl? wahl]) async =>
      text(await a.bauen(wahl ?? DruckWahl.standard(a.optionen)));

  /// Die Seitenangaben aller Fußzeilen: („Seite 2 von 3" → (2, 3)).
  List<(int, int)> seitenAngaben(String t) => [
        for (final m in RegExp(
          r'\(Seite\)\]TJ.*?\((\d+)\)\]TJ.*?\(von\)\]TJ.*?\((\d+)\)\]TJ',
          dotAll: true,
        ).allMatches(t))
          (int.parse(m.group(1)!), int.parse(m.group(2)!)),
      ];

  DruckOption option(DruckAuftrag a, String schluessel) =>
      a.optionen.firstWhere((o) => o.schluessel == schluessel);

  List<String> werteVon(DruckAuftrag a, String schluessel) =>
      switch (option(a, schluessel)) {
        final DruckWahlEins o => [for (final w in o.werte) w.wert],
        final DruckWahlMehrere o => [for (final w in o.werte) w.wert],
        _ => const [],
      };

  // ── Archivierter Wochenplan ─────────────────────────────────────────────

  group('Archivierter Wochenplan', () {
    test('die Aufgaben kommen je Abteilung und Tag aus dem Archiv', () {
      final aufgaben = aufgabenAusArchiv(
        bspArchivPlan(),
        stand: bspArchiviert,
      );
      expect(
        aufgaben.keys,
        unorderedEquals([('verpackung', dienstag), ('zerlegung', donnerstag)]),
      );
      final etiketten = aufgaben[('verpackung', dienstag)]!.single;
      expect(etiketten.inhalt, 'Etiketten nachbestellen');
      expect(etiketten.erledigt, isTrue);
      expect(etiketten.createdAt, bspArchiviert);
      final messer = aufgaben[('zerlegung', donnerstag)]!.single;
      expect(messer.inhalt, 'Messer schleifen lassen');
      expect(messer.erledigt, isFalse);
      expect(messer.id, isNot(etiketten.id));
    });

    WeekBoard woche() {
      final daten = dekodiereSnapshot(bspSnapshot());
      return wochenboardAusArchiv(
        daten.plan!,
        stand: bspArchiviert,
        zusatzzeiten: daten.zusatzzeiten,
      );
    }

    DruckAuftrag auftrag() => archivPlanDruckAuftrag(
          woche: woche(),
          aufgaben: aufgabenAusArchiv(bspArchivPlan(), stand: bspArchiviert),
          stand: bspArchiviert,
          gedrucktAm: gedruckt,
        );

    test('Kopf und Fuß sagen, dass der Plan aus dem Archiv stammt', () async {
      final a = auftrag();
      expect(a.art, 'archivplan');
      expect(a.untertitel, 'KW 44 · Stand beim Archivieren 30.10.2026, 14:03');

      final dokument = await a.bauen(DruckWahl.standard(a.optionen));
      expect(dokument.titel, 'Wochenplan KW 44 Archiv');
      final (e, t) = await setze(dokument);
      expect(e.seiten, 1);
      for (final wort in [
        '(Archiv:)',
        '(Stand)',
        '(30.10.2026,)',
        '(14:03)',
        '(Archiv)',
        '(Schweineschulter)',
        '(Bratwurst)',
        '(Etiketten)',
        '(Messer)',
      ]) {
        expect(t, contains(wort), reason: wort);
      }
      expect(seitenAngaben(t), [(1, 1)]);
    });

    test('der aktuelle Plan sagt nichts vom Archiv', () async {
      final t = await text(
        BoardPrintService.wochenDruck(
          woche(),
          aufgaben: aufgabenAusArchiv(bspArchivPlan(), stand: bspArchiviert),
          gedrucktAm: gedruckt,
        ),
      );
      expect(t, contains('(Schweineschulter)'));
      expect(t, isNot(contains('(Archiv)')));
      expect(t, isNot(contains('(Archiv:)')));
    });

    test('Wahl: Abteilungen, Tage, Aufgaben, Erledigtes', () async {
      final a = auftrag();
      final standard = DruckWahl.standard(a.optionen);
      expect(
        standard.mehrere(PlanDruckWahl.abteilungenWoche),
        {'zerlegung', 'bratstrasse', 'verpackung'},
      );
      expect(standard.mehrere(PlanDruckWahl.tage), {'1', '2', '3', '4', '5'});
      expect(standard.an(PlanDruckWahl.kaestchen), isFalse);
      expect(
        option(a, PlanDruckWahl.abteilungenWoche).merken,
        isFalse,
        reason: 'eine archivierte Woche hat ihre eigenen Abteilungen',
      );

      // Nur die Verpackung, ohne sonstige Aufgaben.
      final nurVerpackung =
          standard.mit(PlanDruckWahl.abteilungenWoche, {'verpackung'});
      final verpackung = await gebaut(
        a,
        nurVerpackung.mit(PlanDruckWahl.aufgaben, false),
      );
      expect(verpackung, contains('(Schale)'));
      expect(verpackung, isNot(contains('(Schweineschulter)')));
      expect(verpackung, isNot(contains('(Etiketten)')));

      // Ohne Erledigtes: nur, was beim Archivieren offen war.
      final offen = await gebaut(
        a,
        standard.mit(PlanDruckWahl.erledigte, false),
      );
      expect(offen, isNot(contains('(Rinderkeule)')), reason: 'erledigt');
      expect(offen, contains('(Schweineschulter)'), reason: 'Donnerstag');
      expect(offen, isNot(contains('(Etiketten)')), reason: 'abgehakt');
      expect(offen, contains('(Messer)'));
    });

    test('nichts gewählt: ein Hinweis statt eines leeren Blatts', () {
      final a = auftrag();
      final standard = DruckWahl.standard(a.optionen);
      expect(
        () => a.bauen(
          standard.mit(PlanDruckWahl.abteilungenWoche, <String>{}),
        ),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
      expect(
        () => a.bauen(standard.mit(PlanDruckWahl.tage, <String>{})),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
    });
  });

  // ── Auswertung einer Woche ──────────────────────────────────────────────

  group('Wochenauswertung', () {
    test('je Abteilung: belegt mit Nebenzeiten, Kapazität Mo–Fr', () {
      final wochen = abteilungsWochen(bspWochenDaten());
      expect(
        [for (final w in wochen) w.abteilung],
        [Abteilung.zerlegung, Abteilung.bratstrasse, Abteilung.verpackung],
      );
      final zerlegung = wochen[0];
      expect(zerlegung.belegtMinuten, 1260);
      expect(zerlegung.nebenMinuten, 0);
      expect(zerlegung.kapazitaetMinuten, 3000);
      expect(zerlegung.kg, 4850);
      expect(zerlegung.auftraege, 3);
      final brat = wochen[1];
      expect(brat.belegtMinuten, 1695, reason: '1650 Aufträge + 45 Reinigen');
      expect(brat.nebenMinuten, 45);
      expect(brat.kapazitaetMinuten, 2400);
      expect(wochen[2].belegtMinuten, 930);
      expect(wochen[2].kapazitaetMinuten, 4800);
    });

    test('alles drauf: Kennzahlen, Auslastung, Tage, Nebenzeiten, Notiz',
        () async {
      final snap = bspSnapshot(notiz: 'Bratlinie länger gereinigt.');
      final (e, t) = await setze(
        wochenauswertungDruck(
          snap,
          gedrucktAm: gedruckt,
          inhalt: const WochenauswertungInhalt(auftragsnotizen: true),
        ),
      );
      expect(e.seiten, 1);
      for (final wort in [
        '(Auswertung)',
        '(Aufträge)',
        '(Auslastung)',
        '(Zerlegung)',
        '(Bratstraße)',
        '(Verpackung)',
        '(Frikadellen)',
        // Notiz eines Auftrags.
        '(Lieferung)',
        // Nebenzeiten mit der Anlage aus dem Plan.
        '(Nebenzeiten)',
        '(Reinigen)',
        '(Allergenwechsel)',
        '(Nord)',
        // Erkenntnisse.
        '(gereinigt.)',
        '(Wochenauswertung)',
      ]) {
        expect(t, contains(wort), reason: wort);
      }
      expect(seitenAngaben(t), [(1, 1)]);
    });

    test('ohne Tage, Nebenzeiten und Erkenntnisse nur das Gerüst', () async {
      final t = await text(
        wochenauswertungDruck(
          bspSnapshot(notiz: 'Bratlinie länger gereinigt.'),
          gedrucktAm: gedruckt,
          inhalt: const WochenauswertungInhalt(
            tage: false,
            nebenzeiten: false,
            erkenntnisse: false,
          ),
        ),
      );
      expect(t, contains('(Auslastung)'));
      expect(t, isNot(contains('(Frikadellen)')));
      expect(t, isNot(contains('(Allergenwechsel)')));
      expect(t, isNot(contains('(gereinigt.)')));
      expect(t, isNot(contains('(Lieferung)')), reason: 'Notizen aus');
    });

    test('nur gewählte Abteilungen — die Kennzahlen zählen nur sie', () async {
      final t = await text(
        wochenauswertungDruck(
          bspSnapshot(),
          gedrucktAm: gedruckt,
          inhalt: const WochenauswertungInhalt(abteilungen: {'verpackung'}),
        ),
      );
      expect(t, contains('(Schale)'));
      expect(t, isNot(contains('(Schweineschulter)')));
      expect(t, isNot(contains('(Allergenwechsel)')));
      // Drei Aufträge der Verpackung, 2.900 kg.
      expect(t, contains('(2.900)'));
    });

    test('ohne Plan im Archiv: Nebenzeiten unter der Abteilung', () async {
      final t = await text(
        wochenauswertungDruck(
          bspSnapshot(mitPlan: false),
          gedrucktAm: gedruckt,
        ),
      );
      expect(t, contains('(Allergenwechsel)'));
      expect(t, isNot(contains('(Nord)')));
    });

    test('Druckfenster: nur Wahlen, für die es Daten gibt', () async {
      final mit = wochenauswertungDruckAuftrag(
        bspSnapshot(),
        notiz: 'Gerade getippt, noch nicht gespeichert.',
        gedrucktAm: gedruckt,
      );
      expect(mit.art, 'wochenauswertung');
      expect(
        [for (final o in mit.optionen) o.schluessel],
        [
          WochenauswertungWahl.abteilungen,
          WochenauswertungWahl.tage,
          WochenauswertungWahl.auftragsnotizen,
          WochenauswertungWahl.nebenzeiten,
          WochenauswertungWahl.erkenntnisse,
        ],
      );
      expect(
        werteVon(mit, WochenauswertungWahl.abteilungen),
        ['zerlegung', 'bratstrasse', 'verpackung'],
      );
      final standard = DruckWahl.standard(mit.optionen);
      expect(standard.an(WochenauswertungWahl.auftragsnotizen), isFalse);
      // Die Notiz aus dem Feld, nicht die gespeicherte.
      expect(await gebaut(mit), contains('(getippt,)'));
      expect(
        () => mit.bauen(
          standard.mit(WochenauswertungWahl.abteilungen, <String>{}),
        ),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );

      // Ohne Notiz kein Schalter für Erkenntnisse.
      final ohne = wochenauswertungDruckAuftrag(bspSnapshot());
      expect(
        [for (final o in ohne.optionen) o.schluessel],
        isNot(contains(WochenauswertungWahl.erkenntnisse)),
      );
    });

    test('Nebenzeit-Arten heißen wie auf dem Schirm', () {
      expect(nebenzeitArt('ruesten'), 'Rüsten');
      expect(nebenzeitArt('reinigen'), 'Reinigen');
      expect(nebenzeitArt('sonstiges'), 'Sonstiges');
      expect(nebenzeitArt('unbekannt'), 'Sonstiges');
    });
  });

  // ── Wochen im Überblick ─────────────────────────────────────────────────

  group('Wochen im Überblick', () {
    List<WeekSnapshot> wochen(int n) => [
          for (var i = 0; i < n; i++)
            bspSnapshot(
              wochen: i,
              notiz: i == 1 ? 'Kurze Woche wegen Feiertag.' : null,
            ),
        ];

    test('je Woche eine Zeile, älteste zuerst, mit Erkenntnissen', () async {
      final (e, t) = await setze(
        wochenuebersichtDruck(
          wochen(3),
          titelZusatz: 'Die letzten 3 Wochen',
          gedrucktAm: gedruckt,
        ),
      );
      expect(e.seiten, 1);
      final kw42 = t.indexOf('(42/26)');
      final kw43 = t.indexOf('(43/26)');
      final kw44 = t.indexOf('(44/26)');
      expect(kw42, greaterThan(-1));
      expect(kw42, lessThan(kw43));
      expect(kw43, lessThan(kw44));
      expect(t, contains('(Feiertag.)'));
      expect(t, contains('(VP)'), reason: 'Spalte je Abteilung');
    });

    test('ohne Abteilungen und Erkenntnisse', () async {
      final t = await text(
        wochenuebersichtDruck(
          wochen(3),
          titelZusatz: 'Alle Wochen',
          gedrucktAm: gedruckt,
          inhalt: const WochenuebersichtInhalt(
            abteilungen: false,
            erkenntnisse: false,
          ),
        ),
      );
      expect(t, isNot(contains('(VP)')));
      expect(t, isNot(contains('(Feiertag.)')));
    });

    test('Auswahl: Monat im Kalender, die letzten Wochen, alle', () async {
      // Sechs Wochen: KW 39 bis 44. Im Oktober liegen KW 40 bis 44.
      final a = wochenuebersichtDruckAuftrag(
        wochen(6),
        monat: DateTime(2026, 10),
        gedrucktAm: gedruckt,
      );
      expect(a.art, 'wochenuebersicht');
      expect(a.untertitel, '6 Wochen archiviert');
      expect(werteVon(a, WochenuebersichtWahl.wochen), ['monat', '4', 'alle']);
      final standard = DruckWahl.standard(a.optionen);
      expect(standard.eins(WochenuebersichtWahl.wochen), 'monat');

      final oktober = await a.bauen(standard);
      expect(oktober.titel, 'Wochen im Überblick Oktober 2026');
      final t = await text(oktober);
      expect(t, contains('(40/26)'));
      expect(t, isNot(contains('(39/26)')));

      final vier =
          await gebaut(a, standard.mit(WochenuebersichtWahl.wochen, '4'));
      expect(vier, contains('(41/26)'));
      expect(vier, isNot(contains('(40/26)')));
    });

    test('ohne Monat: ein Quartal, wenn es mehr Wochen gibt, sonst alle', () {
      final viele = wochenuebersichtDruckAuftrag(wochen(14));
      expect(werteVon(viele, WochenuebersichtWahl.wochen), ['4', '13', 'alle']);
      expect(
        DruckWahl.standard(viele.optionen).eins(WochenuebersichtWahl.wochen),
        '13',
      );

      final wenige = wochenuebersichtDruckAuftrag(
        wochen(3),
        monat: DateTime(2026, 6),
      );
      expect(werteVon(wenige, WochenuebersichtWahl.wochen), ['alle']);
      expect(
        DruckWahl.standard(wenige.optionen).eins(WochenuebersichtWahl.wochen),
        'alle',
      );
      // Ohne Erkenntnisse kein Schalter dafür.
      expect(
        [
          for (final o
              in wochenuebersichtDruckAuftrag([bspSnapshot()]).optionen)
            o.schluessel,
        ],
        isNot(contains(WochenuebersichtWahl.erkenntnisse)),
      );
    });
  });
}
