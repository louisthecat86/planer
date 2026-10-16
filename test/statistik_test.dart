// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/erledigt_service.dart';
import 'package:produktion_planer/features/articles/artikel_luecken.dart';
import 'package:produktion_planer/features/board/board_providers.dart';
import 'package:produktion_planer/features/statistik/statistik_daten.dart';

import 'helpers/test_db.dart';

/// Tests für die Statistik: Zeitraum und Abschnitte, Auslastung und
/// Engpässe, Zeitverteilung, Planerfüllung, Ausbeute, Leistung,
/// Produktmix und Stammdaten-Pflege — und dass Belegung und Karten aus der
/// Datenbank genau die des Boards sind. Alle Daten sind erfunden.
void main() {
  // Freitag in KW 42/2026.
  final heute = DateTime(2026, 10, 16);
  final montag = DateTime(2026, 10, 12);
  final dienstag = DateTime(2026, 10, 13);
  final mittwoch = DateTime(2026, 10, 14);

  group('Zeitraum', () {
    test('Quartal: 13 ganze Wochen bis einschließlich der laufenden', () {
      final s = StatistikSpanne.fuer(StatistikZeitraum.quartal, heute);
      expect(s.von, DateTime(2026, 7, 20));
      expect(s.bisExkl, DateTime(2026, 10, 19));
      expect(s.wochen, 13);
      expect(s.raster, StatistikRaster.woche);
      expect(s.abschnitte.length, 13);
      expect(s.abschnitte.first, DateTime(2026, 7, 20));
      expect(s.abschnitte.last, montag);
      expect(s.kurzname(montag), 'KW 42');
      expect(s.langname(montag), 'KW 42/2026 · 12.10.–16.10.');
      expect(s.enthaelt(DateTime(2026, 10, 18)), isTrue);
      expect(s.enthaelt(DateTime(2026, 10, 19)), isFalse);
    });

    test('12 Monate: Abschnitte sind Monate', () {
      final s = StatistikSpanne.fuer(StatistikZeitraum.zwoelfMonate, heute);
      expect(s.von, DateTime(2025, 10, 20));
      expect(s.wochen, 52);
      expect(s.raster, StatistikRaster.monat);
      expect(s.abschnitte.first, DateTime(2025, 10));
      expect(s.abschnitte.last, DateTime(2026, 10));
      expect(s.abschnitte.length, 13);
      expect(s.kurzname(DateTime(2026, 3)), 'Mär 26');
      expect(s.langname(DateTime(2026, 3)), 'März 2026');
      expect(s.abschnittVon(DateTime(2026, 3, 31)), DateTime(2026, 3));
    });

    test('Alles beginnt in der Woche der ältesten Daten', () {
      final s = StatistikSpanne.fuer(
        StatistikZeitraum.alles,
        heute,
        fruehestes: DateTime(2026, 9, 2),
      );
      expect(s.von, DateTime(2026, 8, 31));
      expect(s.wochen, 7);

      final leer = StatistikSpanne.fuer(StatistikZeitraum.alles, heute);
      expect(leer.von, montag);
      expect(leer.wochen, 1);
    });

    test('Wochen über die Zeitumstellung bleiben auf Mitternacht', () {
      final s = StatistikSpanne.fuer(
        StatistikZeitraum.vierWochen,
        DateTime(2026, 10, 28),
      );
      expect(s.abschnitte, [
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 26),
      ]);
      expect(s.wochen, 4);
    });

    test('„Alles": der Verlauf beginnt mit den ersten Daten — mit eigenem '
        'Raster', () {
      final alles = StatistikSpanne.fuer(
        StatistikZeitraum.alles,
        heute,
        fruehestes: DateTime(2025, 7, 28),
      );
      expect(alles.raster, StatistikRaster.monat);

      final ab = alles.abDatenbeginn(DateTime(2026, 9, 30));
      expect(ab.von, DateTime(2026, 9, 28));
      expect(ab.bisExkl, alles.bisExkl);
      expect(ab.raster, StatistikRaster.woche);
      expect(ab.abschnitte.length, 3);

      // Feste Zeiträume und „Alles" ohne Daten bleiben, wie sie sind.
      final quartal = StatistikSpanne.fuer(StatistikZeitraum.quartal, heute);
      expect(identical(quartal.abDatenbeginn(DateTime(2026, 9, 30)), quartal),
          isTrue,);
      expect(identical(alles.abDatenbeginn(null), alles), isTrue);
    });
  });

  // Spuren wie im Board: drei Abteilungen, die Verpackung mit zwei Anlagen
  // und einer Sammelspur.
  const zerlegung = BoardSpur(
    abteilung: Abteilung.zerlegung,
    kapazitaetMinuten: 600,
  );
  const brat = BoardSpur(
    abteilung: Abteilung.bratstrasse,
    kapazitaetMinuten: 480,
  );
  const anlageB = BoardSpur(
    abteilung: Abteilung.verpackung,
    maschineId: 'm1',
    maschineName: 'Anlage B',
    kapazitaetMinuten: 480,
  );
  const anlageA = BoardSpur(
    abteilung: Abteilung.verpackung,
    maschineId: 'm2',
    maschineName: 'Anlage A',
    kapazitaetMinuten: 480,
  );
  const sammel = BoardSpur(
    abteilung: Abteilung.verpackung,
    kapazitaetMinuten: 600,
  );

  SpurTagBelegung b(
    BoardSpur spur,
    DateTime tag,
    double produktion, {
    Map<String, double> zusatz = const {},
  }) =>
      SpurTagBelegung(
        spur: spur,
        tag: tag,
        produktionsMinuten: produktion,
        zusatzMinuten: zusatz,
      );

  // Montag: Bratstraße überbucht. Dienstag: Zerlegung mit Rüsten
  // überbucht, Anlage A genau voll (nicht überbucht). Mittwoch: Feiertag,
  // nirgends etwas geplant.
  final belegung = [
    b(zerlegung, montag, 300),
    b(brat, montag, 500),
    b(anlageB, montag, 240),
    b(anlageA, montag, 0),
    b(sammel, montag, 0),
    b(zerlegung, dienstag, 600, zusatz: const {'ruesten': 60}),
    b(brat, dienstag, 240),
    b(anlageB, dienstag, 0),
    b(anlageA, dienstag, 480),
    b(sammel, dienstag, 120),
    for (final spur in const [zerlegung, brat, anlageB, anlageA, sammel])
      b(spur, mittwoch, 0),
  ];

  group('Auslastung', () {
    final spanne = StatistikSpanne.fuer(StatistikZeitraum.vierWochen, heute);

    test('je Abteilung über die Planungstage, ohne den Feiertag', () {
      final a = werteAuslastungAus(belegung, spanne);
      expect(a.planungstage, 2, reason: 'Mittwoch zählt nicht');
      expect(a.geplanteWochen, 1);
      expect(a.ueberbuchteTage, 2);
      expect(
        [for (final z in a.zeilen) z.abteilung],
        [Abteilung.zerlegung, Abteilung.bratstrasse, Abteilung.verpackung],
      );

      final z = a.zeilen[0];
      expect(z.belegtMinuten, 960);
      expect(z.kapazitaetMinuten, 1200);
      expect(z.auslastung, closeTo(0.8, 1e-9));
      expect(z.ueberbuchteTage, 1);
      expect(z.status, CapacityStatus.gut);

      final v = a.zeilen[2];
      expect(v.belegtMinuten, 840);
      expect(v.kapazitaetMinuten, 3120);
      expect(v.ueberbuchteTage, 0, reason: 'genau voll ist nicht überbucht');
      expect(v.status, CapacityStatus.frei);

      expect(a.engpass?.abteilung, Abteilung.zerlegung);
      expect(a.auslastung, closeTo(2540 / 5280, 1e-9));
    });

    test('mit Abteilung: je Spur, Anlagen nach Namen, Sammelspur zuletzt',
        () {
      final a = werteAuslastungAus(
        belegung,
        spanne,
        abteilung: Abteilung.verpackung,
      );
      expect(
        [for (final z in a.zeilen) z.name],
        ['Anlage A', 'Anlage B', 'Ohne Anlage'],
      );
      expect(a.zeilen[0].auslastung, closeTo(0.5, 1e-9));
      expect(a.zeilen[2].spur?.istAnlage, isFalse);
      expect(a.ueberbuchteTage, 0);
      // Die Planungstage bleiben die des ganzen Betriebs.
      expect(a.planungstage, 2);
    });

    test('„Alles": Verlauf je Woche ab der ersten Planung', () {
      final alles = StatistikSpanne.fuer(
        StatistikZeitraum.alles,
        heute,
        fruehestes: DateTime(2025, 7, 28),
      );
      final a = werteAuslastungAus(belegung, alles);
      expect(a.verlaufSpanne.raster, StatistikRaster.woche);
      expect([for (final p in a.verlauf) p.abschnitt], [montag]);
      expect(a.verlaufPunkte, 1, reason: 'zu wenig für einen Verlauf');
    });

    test('Verlauf je Woche: nur die Woche mit Planung hat Daten', () {
      final a = werteAuslastungAus(belegung, spanne);
      expect(identical(a.verlaufSpanne, spanne), isTrue);
      expect(a.verlauf.length, 4);
      expect([for (final p in a.verlauf) p.hatDaten], [false, false, false, true]);
      final p = a.verlauf.last;
      expect(p.abschnitt, montag);
      expect(p.belegtMinuten, 2540);
      expect(p.kapazitaetMinuten, 5280);
      expect(p.tage, 2);
      expect(p.ueberbuchteTage, 2);
    });

    test('ohne Planung ist die Auswertung leer', () {
      final a = werteAuslastungAus(
        [for (final e in belegung) if (e.tag == mittwoch) e],
        spanne,
      );
      expect(a.leer, isTrue);
      expect(a.zeilen, isEmpty);
      expect(a.engpass, isNull);
    });
  });

  group('Wohin die Zeit geht', () {
    test('gesamt und je Spur in der Reihenfolge des Boards', () {
      final z = werteZeitAus(belegung);
      expect(z.gesamt.produktion, 2480);
      expect(z.gesamt.ruesten, 60);
      expect(z.gesamt.neben, 60);
      expect(z.gesamt.summe, 2540);
      expect(
        [for (final s in z.jeSpur) s.name],
        ['Zerlegung', 'Bratstraße', 'Anlage A', 'Anlage B', 'Ohne Anlage'],
      );
      expect(z.jeSpur.first.anteile.produktion, 900);
      expect(z.jeSpur.first.anteile.ruesten, 60);
    });

    test('mit Abteilung nur deren Spuren', () {
      final z = werteZeitAus(belegung, abteilung: Abteilung.bratstrasse);
      expect(z.gesamt.summe, 740);
      expect([for (final s in z.jeSpur) s.name], ['Bratstraße']);
    });
  });

  // Artikel und erfasste Produktionen.
  const a1 = StatistikArtikel(
    id: 'a1',
    artikelnummer: '1001',
    bezeichnung: 'Testwurst',
    produktgruppe: 'bruehwurst',
    abteilungen: {'bratstrasse', 'verpackung'},
  );
  const a2 = StatistikArtikel(
    id: 'a2',
    artikelnummer: '1002',
    bezeichnung: 'Testbraten',
    abteilungen: {'zerlegung'},
  );
  const artikel = {'a1': a1, 'a2': a2};

  ErfassteProduktion p(
    String id,
    DateTime datum, {
    double? roh,
    double? fertig,
  }) {
    final verlust = roh != null && roh > 0 && fertig != null
        ? 1 - fertig / roh
        : null;
    return ErfassteProduktion(
      productId: id,
      datum: datum,
      kgRohware: roh,
      kgFertigware: fertig,
      verlust:
          verlust != null && verlust > 0 && verlust < 1 ? verlust : null,
      ausbeuteAngegeben: verlust != null,
    );
  }

  final produktionen = [
    p('a1', DateTime(2026, 10, 5), roh: 100, fertig: 80),
    p('a1', DateTime(2026, 10, 6), roh: 100, fertig: 75),
    p('a1', DateTime(2026, 10, 13), roh: 200, fertig: 170),
    // Mehr heraus als hinein: ein Tippfehler.
    p('a1', DateTime(2026, 10, 14), roh: 100, fertig: 110),
    // Fertigware fehlt.
    p('a2', DateTime(2026, 10, 12), roh: 50),
    p('a2', DateTime(2026, 10, 13), roh: 80, fertig: 60),
    // Vor dem Zeitraum.
    p('a2', DateTime(2026, 6, 1), roh: 100, fertig: 90),
  ];

  group('Ausbeute und Verlust', () {
    final spanne = StatistikSpanne.fuer(StatistikZeitraum.quartal, heute);

    test('Ø je Produktion, kg Verlust, Ausreißer zählen nicht', () {
      final a = werteAusbeuteAus(produktionen, artikel, spanne);
      expect(a.produktionen, 6);
      expect(a.gueltig, 4);
      expect(a.unplausibel, 1);
      expect(a.ohneAusbeute, 1);
      expect(a.mittlererVerlust, closeTo(0.2125, 1e-9));
      expect(a.mittlereAusbeute, closeTo(0.7875, 1e-9));
      expect(a.verlustKg, closeTo(95, 1e-9));
    });

    test('Verlauf je Woche', () {
      final a = werteAusbeuteAus(produktionen, artikel, spanne);
      final jeWoche = {
        for (final v in a.verlauf)
          if (v.hatDaten) v.abschnitt: v,
      };
      final vorwoche = DateTime(2026, 10, 5);
      expect(jeWoche.keys, [vorwoche, montag]);
      expect(jeWoche[vorwoche]!.mittlererVerlust, closeTo(0.225, 1e-9));
      expect(jeWoche[montag]!.mittlererVerlust, closeTo(0.2, 1e-9));
      expect(jeWoche[montag]!.verlustKg, closeTo(50, 1e-9));
    });

    test('Spanne erst ab drei Produktionen', () {
      final a = werteAusbeuteAus(produktionen, artikel, spanne);
      expect(a.spannen.length, 1);
      final s = a.spannen.single;
      expect(s.artikel.id, 'a1');
      expect(s.anzahl, 3);
      expect(s.min, closeTo(0.75, 1e-9));
      expect(s.max, closeTo(0.85, 1e-9));
      expect(s.mittel, closeTo(0.8, 1e-9));
    });

    test('mit Abteilung nur Artikel mit einem Schritt dort', () {
      final z = werteAusbeuteAus(
        produktionen,
        artikel,
        spanne,
        abteilung: Abteilung.zerlegung,
      );
      expect(z.produktionen, 2);
      expect(z.gueltig, 1);
      expect(z.mittlererVerlust, closeTo(0.25, 1e-9));

      final w = werteAusbeuteAus(
        produktionen,
        artikel,
        spanne,
        abteilung: Abteilung.wurstkueche,
      );
      expect(w.produktionen, 0);
      expect(w.mittlereAusbeute, isNull);
    });
  });

  group('Produktmix', () {
    final spanne = StatistikSpanne.fuer(StatistikZeitraum.quartal, heute);

    test('höchstens sechs Stücke — der Rest als „Übrige"', () {
      const gruppen = [
        'bruehwurst',
        'rohwurst',
        'kochpoekelware',
        'aufschnitt',
        'braten',
        'sous_vide',
        'hackprodukt_roh',
      ];
      final viele = {
        for (var i = 0; i < gruppen.length; i++)
          'g$i': StatistikArtikel(
            id: 'g$i',
            artikelnummer: '20$i',
            bezeichnung: 'Artikel $i',
            produktgruppe: gruppen[i],
          ),
        'ohne': const StatistikArtikel(
          id: 'ohne',
          artikelnummer: '2099',
          bezeichnung: 'Ohne Gruppe',
        ),
      };
      final mengen = {
        'g0': 700.0,
        'g1': 600.0,
        'g2': 500.0,
        'g3': 400.0,
        'g4': 300.0,
        'g5': 200.0,
        'g6': 100.0,
        'ohne': 50.0,
      };
      final liste = [
        for (final MapEntry(key: id, value: kg) in mengen.entries)
          p(id, montag, roh: kg),
        // Ohne Rohware zählt nicht.
        p('g0', dienstag),
      ];

      final m = werteProduktmixAus(liste, viele, spanne);
      expect(m.kgGesamt, 2850);
      expect(m.produktionen, 8);
      expect(m.artikelAnzahl, 8);
      // Die Artikel ohne Gruppe bekommen immer ein eigenes Stück am Ende —
      // für die gepflegten Gruppen bleiben fünf, davon eins „Übrige".
      expect(
        [for (final g in m.gruppen) g.name],
        [
          'Brühwurst',
          'Rohwurst',
          'Kochpökelware',
          'Aufschnitt',
          'Übrige (3 Gruppen)',
          'Ohne Produktgruppe',
        ],
      );
      expect(m.gruppen[4].uebrige, isTrue);
      expect(m.gruppen[4].kg, 600);
      expect(m.gruppen.last.ohneGruppe, isTrue);
      expect(m.gruppen.last.kg, 50);
      expect(m.kgOhneGruppe, 50);
      expect([for (final a in m.topArtikel) a.kg].first, 700);
      expect(m.topArtikel.length, 8);
    });

    test('sechs gepflegte Gruppen passen ohne „Übrige"', () {
      const gruppen = [
        'bruehwurst',
        'rohwurst',
        'kochpoekelware',
        'aufschnitt',
        'braten',
        'sous_vide',
      ];
      final sechs = {
        for (var i = 0; i < gruppen.length; i++)
          'g$i': StatistikArtikel(
            id: 'g$i',
            artikelnummer: '30$i',
            bezeichnung: 'Artikel $i',
            produktgruppe: gruppen[i],
          ),
      };
      final m = werteProduktmixAus(
        [for (var i = 0; i < 6; i++) p('g$i', montag, roh: 100.0 + i)],
        sechs,
        spanne,
      );
      expect(m.gruppen.length, 6);
      expect(m.gruppen.any((g) => g.uebrige || g.ohneGruppe), isFalse);
      expect(m.gruppen.first.name, 'Sous Vide gegarte Produkte');
    });

    test('Artikel ohne Produktgruppe stehen am Ende', () {
      final m = werteProduktmixAus(produktionen, artikel, spanne);
      expect(
        [for (final g in m.gruppen) (g.name, g.kg)],
        [('Brühwurst', 500.0), ('Ohne Produktgruppe', 130.0)],
      );
      expect(m.gruppen.last.ohneGruppe, isTrue);
      expect(m.kgOhneGruppe, 130);
      expect(m.topArtikel.first.artikel.id, 'a1');
    });
  });

  group('Leistung', () {
    final spanne = StatistikSpanne.fuer(StatistikZeitraum.quartal, heute);

    // l1 mit hinterlegten 300 kg/h, l2 mit 200 kg/h, l3 ohne.
    const leistungsArtikel = {
      'l1': StatistikArtikel(
        id: 'l1',
        artikelnummer: '3001',
        bezeichnung: 'Testbällchen',
        abteilungen: {'bratstrasse'},
        leistungKgH: 300,
      ),
      'l2': StatistikArtikel(
        id: 'l2',
        artikelnummer: '3002',
        bezeichnung: 'Testsalami',
        abteilungen: {'wurstkueche'},
        leistungKgH: 200,
      ),
      'l3': StatistikArtikel(
        id: 'l3',
        artikelnummer: '3003',
        bezeichnung: 'Testpastete',
        abteilungen: {'bratstrasse'},
      ),
    };

    ErfassteProduktion z(
      String id,
      DateTime datum, {
      double? roh,
      double? minuten,
    }) =>
        ErfassteProduktion(
          productId: id,
          datum: datum,
          kgRohware: roh,
          minuten: minuten,
        );

    final liste = [
      // l1: 900 kg in 240 min = 225 kg/h — ein Viertel langsamer als
      // hinterlegt.
      z('l1', montag, roh: 300, minuten: 60),
      z('l1', dienstag, roh: 300, minuten: 90),
      z('l1', mittwoch, roh: 300, minuten: 90),
      // l2: 600 kg in 165 min ≈ 218 kg/h — nur 9 % daneben.
      z('l2', montag, roh: 200, minuten: 60),
      z('l2', dienstag, roh: 200, minuten: 55),
      z('l2', mittwoch, roh: 200, minuten: 50),
      // l3: viel Zeit, keine Leistungsdaten — und eine Produktion ohne
      // Zeit.
      z('l3', montag, roh: 1000, minuten: 400),
      z('l3', dienstag, roh: 500),
      // Ohne Rohware zählt gar nicht, vor dem Zeitraum auch nicht.
      z('l1', dienstag, minuten: 30),
      z('l1', DateTime(2026, 6, 1), roh: 300, minuten: 10),
    ];

    test('Ø kg/h aus Rohware und Zeit, wie die Planung mittelt', () {
      final l = werteLeistungAus(liste, leistungsArtikel, spanne);
      expect(l.produktionen, 8);
      expect(l.mitZeit, 7);
      expect(l.ohneZeit, 1);
      expect(l.kg, 2500);
      expect(l.minuten, 805);
      expect(l.kgProStunde, closeTo(2500 / 805 * 60, 1e-9));

      expect(
        [for (final a in l.zeitverbraucher) a.artikel.id],
        ['l3', 'l1', 'l2'],
        reason: 'meiste Produktionszeit zuerst',
      );
      final l1 = l.zeitverbraucher[1];
      expect(l1.anzahl, 3);
      expect(l1.kgProStunde, closeTo(225, 1e-9));
      expect(l1.langsamste, closeTo(200, 1e-9));
      expect(l1.schnellste, closeTo(300, 1e-9));
      expect(l1.abweichung, closeTo(-0.25, 1e-9));
      expect(l.zeitverbraucher.first.abweichung, isNull);
    });

    test('abweichend erst ab drei Produktionen und 20 %', () {
      final l = werteLeistungAus(liste, leistungsArtikel, spanne);
      expect(l.verglichen, 2, reason: 'l3 hat keine Leistungsdaten');
      expect(l.abweichend, 1);
      expect([for (final a in l.abweichungen) a.artikel.id], ['l1']);

      // Mit nur zwei Produktionen vergleicht die Statistik nicht.
      final zwei = werteLeistungAus(
        [for (final p in liste) if (p.datum != mittwoch) p],
        leistungsArtikel,
        spanne,
      );
      expect(zwei.verglichen, 0);
      expect(zwei.abweichungen, isEmpty);
    });

    test('mit Abteilung nur Artikel mit einem Schritt dort', () {
      final l = werteLeistungAus(
        liste,
        leistungsArtikel,
        spanne,
        abteilung: Abteilung.wurstkueche,
      );
      expect(l.produktionen, 3);
      expect([for (final a in l.zeitverbraucher) a.artikel.id], ['l2']);
      expect(l.abweichungen, isEmpty);
      expect(l.verglichen, 1);
    });
  });

  group('Planerfüllung', () {
    final spanne = StatistikSpanne.fuer(StatistikZeitraum.vierWochen, heute);
    final vorwoche = DateTime(2026, 10, 5);

    final karten = [
      PlanKarte(
        productId: 'a1',
        abteilung: Abteilung.zerlegung,
        datum: vorwoche,
        erledigt: Erledigt.erfasst,
      ),
      PlanKarte(
        productId: 'a1',
        abteilung: Abteilung.bratstrasse,
        datum: vorwoche,
        erledigt: Erledigt.erfasst,
      ),
      PlanKarte(
        productId: 'a2',
        abteilung: Abteilung.zerlegung,
        datum: DateTime(2026, 10, 6),
        erledigt: Erledigt.abgehakt,
      ),
      PlanKarte(
        productId: 'a2',
        abteilung: Abteilung.zerlegung,
        datum: montag,
      ),
      PlanKarte(
        productId: 'a1',
        abteilung: Abteilung.verpackung,
        datum: mittwoch,
        erledigt: Erledigt.abgehakt,
      ),
      // Heute läuft noch.
      PlanKarte(
        productId: 'a1',
        abteilung: Abteilung.zerlegung,
        datum: heute,
      ),
      // Vor dem Zeitraum.
      PlanKarte(
        productId: 'a1',
        abteilung: Abteilung.zerlegung,
        datum: DateTime(2026, 9, 1),
        erledigt: Erledigt.erfasst,
      ),
    ];

    test('die Karten bis gestern: erfasst, nur abgehakt, offen', () {
      final e = werteErfuellungAus(karten, spanne, heute: heute);
      expect(e.gesamt.karten, 5);
      expect(e.gesamt.erfasst, 2);
      expect(e.gesamt.abgehakt, 2);
      expect(e.gesamt.offen, 1);
      expect(e.gesamt.anteilErledigt, closeTo(0.8, 1e-9));
      expect(e.gesamt.anteilErfasst, closeTo(0.4, 1e-9));

      expect(
        [for (final z in e.jeAbteilung) z.abteilung],
        [Abteilung.zerlegung, Abteilung.bratstrasse, Abteilung.verpackung],
      );
      final zahlen = e.jeAbteilung.first.zahlen;
      expect((zahlen.erfasst, zahlen.abgehakt, zahlen.offen), (1, 1, 1));
    });

    test('Verlauf je Woche — nur Wochen, die vor heute beginnen', () {
      final e = werteErfuellungAus(karten, spanne, heute: heute);
      expect(
        [for (final p in e.verlauf) p.abschnitt],
        spanne.abschnitte,
      );
      expect(
        [for (final p in e.verlauf) p.zahlen.karten],
        [0, 0, 3, 2],
      );
      expect(e.verlaufPunkte, 2);

      // Am Montag hat die laufende Woche noch nichts erledigt.
      final amMontag = werteErfuellungAus(karten, spanne, heute: montag);
      expect(amMontag.verlauf.length, 3);
      expect(amMontag.gesamt.karten, 3);
    });

    test('mit Abteilung nur deren Karten', () {
      final e = werteErfuellungAus(
        karten,
        spanne,
        heute: heute,
        abteilung: Abteilung.verpackung,
      );
      expect(e.gesamt.karten, 1);
      expect(e.gesamt.abgehakt, 1);
      expect(
        [for (final z in e.jeAbteilung) z.abteilung],
        [Abteilung.verpackung],
      );

      final leer = werteErfuellungAus(const [], spanne, heute: heute);
      expect(leer.leer, isTrue);
      expect(leer.verlaufPunkte, 0);
    });
  });

  group('Stammdaten-Pflege', () {
    test('je Lücke: Anzahl und davon aktiv', () {
      const pflegeArtikel = {
        'x1': StatistikArtikel(
          id: 'x1',
          artikelnummer: '4001',
          bezeichnung: 'Testwürstchen',
          luecken: {ArtikelLuecke.ohneAusbeute, ArtikelLuecke.zeitPlatzhalter},
        ),
        'x2': StatistikArtikel(
          id: 'x2',
          artikelnummer: '4002',
          bezeichnung: 'Testleberkäse',
          luecken: {ArtikelLuecke.ohneAusbeute},
        ),
        'x3': StatistikArtikel(
          id: 'x3',
          artikelnummer: '4003',
          bezeichnung: 'Testsülze',
        ),
      };
      final p = wertePflegeAus(pflegeArtikel, {'x1', 'x3', 'unbekannt'});
      expect(p.artikel, 3);
      expect(p.vollstaendig, 1);
      expect(p.anteilVollstaendig, closeTo(1 / 3, 1e-9));
      expect(p.aktiv, 2, reason: 'unbekannte IDs zählen nicht');
      expect(
        [for (final z in p.zeilen) z.luecke],
        ArtikelLuecke.values,
        reason: 'jede Lücke eine Zeile, in fester Folge',
      );
      expect(
        {for (final z in p.zeilen) z.luecke: (z.anzahl, z.aktiv)},
        {
          ArtikelLuecke.nichtEingepflegt: (0, 0),
          ArtikelLuecke.ohneProduktgruppe: (0, 0),
          ArtikelLuecke.ohneSchritte: (0, 0),
          ArtikelLuecke.ohneAusbeute: (2, 1),
          ArtikelLuecke.zeitPlatzhalter: (1, 1),
        },
      );
    });
  });

  group('mit Datenbank', () {
    late AppDatabase db;

    setUp(() async {
      db = testDatenbank();
      await seedArtikel(db, id: 'p1', nummer: '9001');
      await seedArtikel(db, id: 'p2', nummer: '9002');
      await seedAnlage(
        db,
        id: 'm1',
        name: 'Testanlage',
        abteilung: 'verpackung',
        kapazitaetMinutenProTag: 480,
      );
    });
    tearDown(() => db.close());

    Future<void> auftrag(
      String id, {
      required String productId,
      required DateTime tag,
      required String abteilung,
      required double minuten,
      String? maschineId,
      String? vorgaenger,
      String status = 'geplant',
    }) =>
        db.into(db.productionTasks).insert(
              ProductionTasksCompanion.insert(
                id: id,
                productId: productId,
                mengeKg: 100,
                datum: tag,
                abteilung: abteilung,
                geplanteDauerMinuten: minuten,
                geplanteMitarbeiter: 2,
                maschineId: Value(maschineId),
                parentTaskId: Value(vorgaenger),
                status: Value(status),
              ),
            );

    Future<void> nebenzeit(
      String id,
      DateTime tag,
      String spurId,
      String art,
      double minuten,
    ) =>
        db.into(db.zusatzzeiten).insert(
              ZusatzzeitenCompanion.insert(
                id: id,
                datum: tag,
                spurId: spurId,
                art: art,
                minuten: minuten,
              ),
            );

    test('die Belegung ist Zelle für Zelle die des Boards', () async {
      final vorwoche = DateTime(2026, 10, 5);
      await auftrag(
        'z',
        productId: 'p1',
        tag: montag,
        abteilung: 'zerlegung',
        minuten: 120,
      );
      await auftrag(
        'b',
        productId: 'p1',
        tag: montag,
        abteilung: 'bratstrasse',
        minuten: 300,
      );
      await auftrag(
        'v1',
        productId: 'p1',
        tag: montag,
        abteilung: 'verpackung',
        minuten: 240,
        maschineId: 'm1',
      );
      // Ohne Anlage: In dieser Woche braucht die Verpackung eine
      // Sammelspur.
      await auftrag(
        'v2',
        productId: 'p2',
        tag: dienstag,
        abteilung: 'verpackung',
        minuten: 60,
      );
      await auftrag(
        'v0',
        productId: 'p1',
        tag: vorwoche,
        abteilung: 'verpackung',
        minuten: 90,
        maschineId: 'm1',
      );
      await nebenzeit('n1', montag, 'bratstrasse|', 'ruesten', 30);
      await nebenzeit('n2', montag, 'bratstrasse|', 'unbekannt', 10);
      // Eine Sammelspur, die es in der Vorwoche nicht gibt — das Board
      // zeigt die Zeit dort nicht, die Statistik auch nicht.
      await nebenzeit('n3', vorwoche, 'verpackung|', 'reinigen', 20);

      final belegung = await belegungImZeitraum(
        db,
        von: vorwoche,
        bisExkl: DateTime(2026, 10, 19),
      );

      SpurTagBelegung? zelle(String spurId, DateTime tag) {
        for (final e in belegung) {
          if (e.spur.id == spurId && e.tag == tag) return e;
        }
        return null;
      }

      final bratMontag = zelle('bratstrasse|', montag)!;
      expect(bratMontag.produktionsMinuten, 300);
      expect(bratMontag.zusatzMinuten, {'ruesten': 30.0, 'sonstiges': 10.0});
      expect(zelle('verpackung|m1', montag)!.produktionsMinuten, 240);
      expect(zelle('verpackung|', dienstag)!.produktionsMinuten, 60);
      expect(
        zelle('verpackung|', vorwoche),
        isNull,
        reason: 'in der Vorwoche gibt es keine Sammelspur',
      );
      expect(zelle('verpackung|m1', vorwoche)!.produktionsMinuten, 90);
      expect(
        belegung.every((e) => e.tag.weekday <= DateTime.friday),
        isTrue,
        reason: 'nur Werktage wie im Board',
      );

      for (final woche in [vorwoche, montag]) {
        final board = await ladeWochenboard(db, woche);
        for (final spur in board.spuren) {
          for (final tag in board.tage) {
            final e = zelle(spur.id, tag);
            if (e == null) fail('${spur.id} am $tag fehlt');
            expect(
              e.belegtMinuten,
              board.cellFor(spur, tag).belegtMinuten,
              reason: '${spur.id} am $tag',
            );
            expect(e.kapazitaetMinuten, spur.kapazitaetMinuten);
          }
        }
      }
    });

    test('ladeStatistik: Produktionen im Zeitraum, mit Artikeln und '
        'Abteilungen', () async {
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'weg',
              artikelnummer: '9099',
              artikelbezeichnung: 'Gelöschter Artikel',
              deletedAt: Value(DateTime(2026, 9, 1)),
            ),
          );
      await (db.update(db.products)..where((t) => t.id.equals('p1'))).write(
        const ProductsCompanion(produktgruppe: Value('bruehwurst')),
      );
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p1',
        reihenfolge: 1,
        abteilung: 'zerlegung',
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p1',
        reihenfolge: 2,
        abteilung: 'bratstrasse',
      );

      Future<void> produktion(
        String id,
        String productId,
        DateTime datum, {
        required double roh,
        double? fertig,
        DateTime? geloescht,
      }) =>
          db.into(db.productionHistory).insert(
                ProductionHistoryCompanion.insert(
                  id: id,
                  productId: productId,
                  datum: datum,
                  kgRohware: Value(roh),
                  kgFertigware: Value(fertig),
                  deletedAt: Value(geloescht),
                ),
              );

      await produktion('h1', 'p1', dienstag, roh: 100, fertig: 80);
      await produktion('h2', 'p1', mittwoch, roh: 100, fertig: 120);
      await produktion('h3', 'p2', mittwoch, roh: 40);
      await produktion(
        'h4',
        'p1',
        mittwoch,
        roh: 100,
        fertig: 90,
        geloescht: DateTime(2026, 10, 15),
      );
      await produktion('h5', 'weg', mittwoch, roh: 100, fertig: 90);
      await produktion('h6', 'p1', DateTime(2026, 8, 3), roh: 100, fertig: 90);

      final daten = await ladeStatistik(
        db,
        StatistikZeitraum.vierWochen,
        heute: heute,
      );
      expect(daten.spanne.von, DateTime(2026, 9, 21));
      expect(daten.produktionen.length, 3);
      expect(daten.artikel.keys.toSet(), {'p1', 'p2'});
      expect(daten.artikel['p1']!.abteilungen, {'zerlegung', 'bratstrasse'});
      expect(daten.artikel['p1']!.produktgruppe, 'bruehwurst');

      final h1 = daten.produktionen.firstWhere((e) => e.datum == dienstag);
      expect(h1.verlust, closeTo(0.2, 1e-9));
      final h2 = daten.produktionen.firstWhere(
        (e) => e.productId == 'p1' && e.datum == mittwoch,
      );
      expect(h2.verlust, isNull, reason: 'mehr heraus als hinein');
      expect(h2.ausbeuteAngegeben, isTrue);

      final a = werteAusbeuteAus(
        daten.produktionen,
        daten.artikel,
        daten.spanne,
      );
      expect(a.gueltig, 1);
      expect(a.unplausibel, 1);
      expect(a.ohneAusbeute, 1);

      // „Alles" reicht bis zur ältesten Produktion zurück.
      final alles = await ladeStatistik(
        db,
        StatistikZeitraum.alles,
        heute: heute,
      );
      expect(alles.spanne.von, DateTime(2026, 8, 3));
      expect(alles.produktionen.length, 4);
    });

    test('kartenImZeitraum: gebündelt wie im Board, mit Erledigt-Stand',
        () async {
      // Zwei Aufträge derselben Abteilung am selben Tag: eine Karte.
      await auftrag(
        'z1',
        productId: 'p1',
        tag: montag,
        abteilung: 'zerlegung',
        minuten: 60,
      );
      await auftrag(
        'z2',
        productId: 'p1',
        tag: montag,
        abteilung: 'zerlegung',
        minuten: 30,
      );
      // Die Bratstraße am Dienstag hängt an der Zerlegung vom Montag.
      await auftrag(
        'b1',
        productId: 'p1',
        tag: dienstag,
        abteilung: 'bratstrasse',
        minuten: 120,
        vorgaenger: 'z1',
      );
      await auftrag(
        'v1',
        productId: 'p2',
        tag: mittwoch,
        abteilung: 'verpackung',
        minuten: 45,
        status: 'fertig',
      );
      await auftrag(
        'v2',
        productId: 'p2',
        tag: dienstag,
        abteilung: 'verpackung',
        minuten: 45,
      );
      await auftrag(
        'x',
        productId: 'p2',
        tag: montag,
        abteilung: 'zerlegung',
        minuten: 45,
        status: 'storniert',
      );
      // Erfasst am Tag der Wurzel: Das macht die ganze Kette erledigt.
      await db.into(db.productionHistory).insert(
            ProductionHistoryCompanion.insert(
              id: 'h1',
              productId: 'p1',
              datum: montag,
              kgRohware: const Value(200),
            ),
          );

      final karten = await kartenImZeitraum(
        db,
        von: montag,
        bisExkl: DateTime(2026, 10, 19),
      );
      BoardTask karte(Abteilung abteilung, DateTime tag) => karten.singleWhere(
            (k) => k.abteilung == abteilung && k.datum == tag,
          );

      expect(karten.length, 4, reason: 'storniert fehlt, z1 und z2 gebündelt');
      expect(
        karte(Abteilung.zerlegung, montag).mitgliederIds.toSet(),
        {'z1', 'z2'},
      );
      expect(karte(Abteilung.zerlegung, montag).erledigt, Erledigt.erfasst);
      expect(karte(Abteilung.bratstrasse, dienstag).erledigt, Erledigt.erfasst);
      expect(karte(Abteilung.verpackung, mittwoch).erledigt, Erledigt.abgehakt);
      expect(karte(Abteilung.verpackung, dienstag).erledigt, isNull);

      // Genau die Karten des Boards.
      final board = await ladeWochenboard(db, montag);
      expect(
        {for (final k in karten) (k.id, k.erledigt)},
        {
          for (final zelle in board.cells.values)
            for (final k in zelle.tasks) (k.id, k.erledigt),
        },
      );
    });

    test('ladeStatistik: Karten, alle Artikel mit Lücken und Leistung',
        () async {
      // p1 gepflegt: Gruppe, Zerlegung und Bratstraße mit Leistungsdaten
      // (120 kg in 30 min = 240 kg/h), Produktionen mit Zeit und Ausbeute.
      await (db.update(db.products)..where((t) => t.id.equals('p1'))).write(
        const ProductsCompanion(produktgruppe: Value('bruehwurst')),
      );
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p1',
        reihenfolge: 1,
        abteilung: 'zerlegung',
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p1',
        reihenfolge: 2,
        abteilung: 'bratstrasse',
        basisMengeKg: 120,
        basisDauerMinuten: 30,
      );
      // p2: ohne Gruppe und Schritte, die Produktion ohne Fertigware.
      // p3: noch nicht eingepflegt und nie produziert.
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p3',
              artikelnummer: '9003',
              artikelbezeichnung: 'Testartikel aus Navision',
              istEingepflegt: const Value(false),
            ),
          );

      await db.into(db.productionHistory).insert(
            ProductionHistoryCompanion.insert(
              id: 'h1',
              productId: 'p1',
              datum: dienstag,
              kgRohware: const Value(200),
              kgFertigware: const Value(160),
              produktionszeitMinuten: const Value(50),
            ),
          );
      // Lange vor dem Zeitraum — zählt trotzdem für die Lücken.
      await db.into(db.productionHistory).insert(
            ProductionHistoryCompanion.insert(
              id: 'h2',
              productId: 'p2',
              datum: DateTime(2025, 3, 3),
              kgRohware: const Value(80),
              startzeit: const Value('06:00'),
              endzeit: const Value('07:00'),
            ),
          );
      await auftrag(
        'z1',
        productId: 'p1',
        tag: dienstag,
        abteilung: 'zerlegung',
        minuten: 60,
      );
      await auftrag(
        'v1',
        productId: 'p2',
        tag: mittwoch,
        abteilung: 'verpackung',
        minuten: 30,
        status: 'fertig',
      );

      final daten = await ladeStatistik(
        db,
        StatistikZeitraum.vierWochen,
        heute: heute,
      );
      expect(daten.stand, heute);
      expect(daten.artikel.keys.toSet(), {'p1', 'p2', 'p3'});
      expect(daten.artikel['p1']!.luecken, isEmpty);
      expect(daten.artikel['p2']!.luecken, {
        ArtikelLuecke.ohneProduktgruppe,
        ArtikelLuecke.ohneSchritte,
        ArtikelLuecke.ohneAusbeute,
      });
      expect(daten.artikel['p3']!.luecken, {
        ArtikelLuecke.nichtEingepflegt,
        ArtikelLuecke.ohneProduktgruppe,
        ArtikelLuecke.ohneSchritte,
        ArtikelLuecke.ohneAusbeute,
      });
      expect(daten.artikel['p1']!.leistungKgH, closeTo(240, 1e-9));
      expect(daten.artikel['p2']!.leistungKgH, isNull);

      expect(daten.produktionen.length, 1, reason: 'h2 liegt vor dem Zeitraum');
      final h1 = daten.produktionen.single;
      expect(h1.minuten, 50);
      expect(h1.kgProStunde, closeTo(240, 1e-9));

      expect(
        {for (final k in daten.karten) (k.productId, k.abteilung, k.erledigt)},
        {
          ('p1', Abteilung.zerlegung, Erledigt.erfasst),
          ('p2', Abteilung.verpackung, Erledigt.abgehakt),
        },
      );
      expect(daten.aktiveArtikel, {'p1', 'p2'});

      final pflege = wertePflegeAus(daten.artikel, daten.aktiveArtikel);
      expect(pflege.vollstaendig, 1);
      expect(pflege.aktiv, 2);
      final ohneAusbeute = pflege.zeilen.firstWhere(
        (z) => z.luecke == ArtikelLuecke.ohneAusbeute,
      );
      expect((ohneAusbeute.anzahl, ohneAusbeute.aktiv), (2, 1));
    });
  });
}
