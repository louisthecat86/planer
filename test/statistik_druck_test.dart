import 'dart:convert' show latin1;

import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_optionen.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';
import 'package:produktion_planer/core/utils/format.dart';
import 'package:produktion_planer/features/statistik/statistik_daten.dart';
import 'package:produktion_planer/features/statistik/statistik_druck.dart';

import 'helpers/statistik_beispiele.dart';

/// Tests für den Ausdruck der Statistik: welche Teile, welche Abteilung,
/// Verläufe und Erklärungen, jeder Teil auf einer eigenen Seite — und was
/// auf dem Blatt steht, wenn Daten fehlen.
///
/// Die PDFs entstehen unkomprimiert — so steht jedes gedruckte Wort als
/// „(Wort)" im Dokument und lässt sich suchen. Alle Daten sind erfunden.
void main() {
  final gedruckt = DateTime(2026, 10, 30, 16, 12);

  Future<(DruckErgebnis, String)> setze(DruckDokument d) async {
    final e = await druckSetzen(d, const DruckLayout(), komprimiert: false);
    return (e, latin1.decode(e.bytes));
  }

  Future<String> text(
    StatistikDaten daten, [
    StatistikDruckInhalt inhalt = const StatistikDruckInhalt(),
  ]) async =>
      (await setze(statistikDruck(daten, inhalt: inhalt, gedrucktAm: gedruckt)))
          .$2;

  /// Die Seitenangaben aller Fußzeilen: („Seite 2 von 3" → (2, 3)).
  List<(int, int)> seitenAngaben(String t) => [
        for (final m in RegExp(
          r'\(Seite\)\]TJ.*?\((\d+)\)\]TJ.*?\(von\)\]TJ.*?\((\d+)\)\]TJ',
          dotAll: true,
        ).allMatches(t))
          (int.parse(m.group(1)!), int.parse(m.group(2)!)),
      ];

  /// Ein Wort aus der Überschrift jedes Teils — nur dort gedruckt.
  const kennwort = {
    StatistikTeil.auslastung: '(Engpässe)',
    StatistikTeil.zeit: '(Wohin)',
    StatistikTeil.erfuellung: '(Planerfüllung)',
    StatistikTeil.ausbeute: '(Ausbeute)',
    StatistikTeil.leistung: '(Leistung)',
    StatistikTeil.produktmix: '(Produktmix)',
    StatistikTeil.pflege: '(Stammdaten-Pflege)',
  };

  /// Nur die Daten ab Montag der laufenden Woche — zu wenig für Verläufe.
  StatistikDaten nurDieseWoche() {
    final d = bspStatistikDaten(zeitraum: StatistikZeitraum.vierWochen);
    final ab = DateTime(2026, 10, 26);
    return StatistikDaten(
      spanne: d.spanne,
      stand: d.stand,
      belegung: [
        for (final b in d.belegung)
          if (!b.tag.isBefore(ab)) b,
      ],
      karten: [
        for (final k in d.karten)
          if (!k.datum.isBefore(ab)) k,
      ],
      produktionen: [
        for (final p in d.produktionen)
          if (!p.datum.isBefore(ab)) p,
      ],
      artikel: d.artikel,
    );
  }

  group('Statistik drucken', () {
    test('alle Teile, Kopf, Fuß und Seitenzahlen', () async {
      final daten = bspStatistikDaten();
      final dokument = statistikDruck(daten, gedrucktAm: gedruckt);
      expect(dokument.titel, 'Statistik Quartal 2026-10-30');
      final (e, t) = await setze(dokument);
      for (final wort in kennwort.values) {
        expect(t, contains(wort), reason: wort);
      }
      // Kopf: der Zeitraum; Fuß: wann die Daten geladen wurden.
      expect(t, contains('(03.08.2026)'));
      expect(t, contains('(15:20)'));
      expect(e.seiten, greaterThan(1));
      expect(seitenAngaben(t), [
        for (var i = 1; i <= e.seiten; i++) (i, e.seiten),
      ]);
      // Die Verläufe Woche für Woche, die Artikel mit Nummer.
      expect(t, contains('(KW)'));
      expect(t, contains('(7201)'));
      expect(t, contains('(Gartenwurst)'));
    });

    test('nur gewählte Teile', () async {
      final t = await text(
        bspStatistikDaten(),
        const StatistikDruckInhalt(teile: {StatistikTeil.zeit}),
      );
      for (final MapEntry(key: teil, value: wort) in kennwort.entries) {
        expect(
          t,
          teil == StatistikTeil.zeit ? contains(wort) : isNot(contains(wort)),
          reason: wort,
        );
      }
      expect(t, contains('(Rüsten)'));
      expect(t, contains('(Packanlage)'));
    });

    test('eine Abteilung: ihre Anlagen und Artikel', () async {
      final t = await text(
        bspStatistikDaten(),
        const StatistikDruckInhalt(abteilung: Abteilung.bratstrasse),
      );
      expect(t, contains('(Nord)'), reason: 'Bratlinie Nord');
      expect(t, contains('(Hackbällchen)'));
      expect(t, isNot(contains('(Packanlage)')));
      expect(t, isNot(contains('(Schweineschulter)')));
      expect(t, isNot(contains('(Rinderkeule)')));
      // Die Stammdaten-Pflege zählt trotzdem alle Artikel.
      expect(t, contains('(Stammdaten-Pflege)'));
      expect(t, contains('(eingepflegt)'));
    });

    test('ohne Verläufe und ohne Erklärungen', () async {
      final mit = await text(bspStatistikDaten());
      expect(mit, contains('(Gezählt)'));
      expect(mit, contains('(daraus)'));

      final t = await text(
        bspStatistikDaten(),
        const StatistikDruckInhalt(verlaeufe: false, erklaerungen: false),
      );
      expect(t, isNot(contains('(KW)')));
      expect(t, isNot(contains('(Gezählt)')));
      expect(t, isNot(contains('(daraus)')), reason: 'Was fehlt …');
      // Tabellen und Kennzahlen bleiben.
      expect(t, contains('(Bratlinie)'));
      expect(t, contains('(Schwankung)'));
    });

    test('jeder Teil auf einer neuen Seite', () async {
      final daten = bspStatistikDaten(zeitraum: StatistikZeitraum.vierWochen);
      final (zusammen, _) = await setze(
        statistikDruck(daten, gedrucktAm: gedruckt),
      );
      final (einzeln, t) = await setze(
        statistikDruck(
          daten,
          gedrucktAm: gedruckt,
          inhalt: const StatistikDruckInhalt(einzeln: true),
        ),
      );
      expect(einzeln.seiten, greaterThanOrEqualTo(StatistikTeil.values.length));
      expect(einzeln.seiten, greaterThan(zusammen.seiten));
      expect(seitenAngaben(t).last, (einzeln.seiten, einzeln.seiten));
    });

    test('12 Monate: Verläufe je Monat', () async {
      final t = await text(
        bspStatistikDaten(zeitraum: StatistikZeitraum.zwoelfMonate),
      );
      expect(t, contains('(September)'));
      expect(t, contains('(Monat)'));
      expect(t, isNot(contains('(KW)')));
    });

    test('Abweichungen von den Leistungsdaten mit Vorzeichen', () async {
      final daten = bspStatistikDaten();
      final l =
          werteLeistungAus(daten.produktionen, daten.artikel, daten.spanne);
      expect(l.abweichungen.length, 2, reason: 'schneller und langsamer');
      final t = await text(daten);
      for (final a in l.abweichungen) {
        final wert = a.abweichung!;
        final zahl = Format.prozent(wert.abs(), nachkomma: 0).split(' ').first;
        expect(t, contains('(${wert < 0 ? '-' : '+'}$zahl)'));
      }
    });

    test('ohne Daten sagt jeder Teil, was fehlt', () async {
      final (e, t) = await setze(
        statistikDruck(bspStatistikLeer(), gedrucktAm: gedruckt),
      );
      expect(e.seiten, 1);
      for (final wort in kennwort.values) {
        expect(t, contains(wort), reason: wort);
      }
      expect(t, contains('(geplant.)'), reason: 'nichts geplant');
      expect(t, contains('(Produktionserfassung.)'));
      // Die Artikel gibt es trotzdem — ihre Lücken stehen da.
      expect(t, contains('(Lücken)'));
    });

    test('zu wenig für Verläufe: ein Hinweis statt der Tabelle', () async {
      final t = await text(nurDieseWoche());
      expect(t, contains('(Verlauf)'));
      expect(t, contains('(braucht)'));
      expect(t, isNot(contains('(KW)')));
    });
  });

  group('Druckfenster', () {
    test('Teile, Abteilung der Seite, Schalter', () {
      final a = statistikDruckAuftrag(
        bspStatistikDaten(),
        abteilung: Abteilung.verpackung,
        gedrucktAm: gedruckt,
      );
      expect(a.art, 'statistik');
      expect(a.untertitel, startsWith('Quartal · '));
      expect(
        [for (final o in a.optionen) o.schluessel],
        [
          StatistikDruckWahl.teile,
          StatistikDruckWahl.abteilung,
          StatistikDruckWahl.verlaeufe,
          StatistikDruckWahl.erklaerungen,
          StatistikDruckWahl.einzeln,
        ],
      );
      final abteilung = a.optionen[1] as DruckWahlEins;
      expect(abteilung.merken, isFalse, reason: 'folgt der Seite');
      expect(
        [for (final w in abteilung.werte) w.wert],
        [StatistikDruckWahl.alle, for (final x in Abteilung.values) x.dbValue],
      );

      final wahl = DruckWahl.standard(a.optionen);
      expect(wahl.mehrere(StatistikDruckWahl.teile), {
        for (final t in StatistikTeil.values) t.name,
      });
      expect(wahl.eins(StatistikDruckWahl.abteilung), 'verpackung');
      expect(wahl.an(StatistikDruckWahl.einzeln), isFalse);

      final ohne = statistikDruckAuftrag(bspStatistikDaten());
      expect(
        DruckWahl.standard(ohne.optionen).eins(StatistikDruckWahl.abteilung),
        StatistikDruckWahl.alle,
      );
    });

    test('gebaut wie gewählt', () async {
      final a = statistikDruckAuftrag(
        bspStatistikDaten(),
        gedrucktAm: gedruckt,
      );
      final nurAuslastung = DruckWahl.standard(a.optionen)
          .mit(StatistikDruckWahl.teile, {StatistikTeil.auslastung.name});
      final dokument = await a.bauen(
        nurAuslastung.mit(StatistikDruckWahl.abteilung, 'bratstrasse'),
      );
      expect(dokument.titel, 'Statistik Quartal Bratstraße 2026-10-30');
      final (_, t) = await setze(dokument);
      expect(t, contains('(Engpässe)'));
      expect(t, isNot(contains('(Produktmix)')));
      expect(t, contains('(Nord)'));
      expect(t, isNot(contains('(Packanlage)')));
    });

    test('kein Teil gewählt: ein Hinweis statt eines leeren Blatts', () {
      final a = statistikDruckAuftrag(bspStatistikDaten());
      expect(
        () => a.bauen(
          DruckWahl.standard(a.optionen)
              .mit(StatistikDruckWahl.teile, <String>{}),
        ),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
    });
  });
}
