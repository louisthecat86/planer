import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/services/erledigt_service.dart';
import 'package:produktion_planer/features/articles/artikel_luecken.dart';
import 'package:produktion_planer/features/board/board_providers.dart';
import 'package:produktion_planer/features/statistik/statistik_daten.dart';
import 'package:produktion_planer/features/statistik/statistik_ueberblick_daten.dart';

/// Tests für den Überblick der Statistik mit erfundenen Daten: der
/// Zeitraum davor, Plan gegen Ist, die Vorschau der nächsten Werktage und
/// die Hinweise.
void main() {
  // Ein Freitag.
  final heute = DateTime(2026, 10, 16);
  final spanne = StatistikSpanne.fuer(StatistikZeitraum.vierWochen, heute);

  const wurst = StatistikArtikel(
    id: 'a1',
    artikelnummer: '9001',
    bezeichnung: 'Testwurst',
    abteilungen: {'zerlegung', 'bratstrasse'},
  );
  const schinken = StatistikArtikel(
    id: 'a2',
    artikelnummer: '9002',
    bezeichnung: 'Testschinken',
    abteilungen: {'wurstkueche'},
  );
  const artikel = {'a1': wurst, 'a2': schinken};

  ErfassteProduktion produktion(
    String id,
    DateTime datum, {
    double? roh,
    double? fertig,
    double? minuten,
  }) {
    final v = roh != null && fertig != null ? 1 - fertig / roh : null;
    return ErfassteProduktion(
      productId: id,
      datum: datum,
      kgRohware: roh,
      kgFertigware: fertig,
      verlust: v,
      ausbeuteAngegeben: v != null,
      minuten: minuten,
    );
  }

  group('Zeitraum davor', () {
    test('gleich lang, direkt davor', () {
      final v = spanne.vorher!;
      expect(v.bisExkl, spanne.von);
      expect(v.wochen, spanne.wochen);
      expect(v.von, DateTime(2026, 8, 24));
    });

    test('bei „Alles" keiner', () {
      expect(
        StatistikSpanne.fuer(StatistikZeitraum.alles, heute).vorher,
        isNull,
      );
    });
  });

  group('Plan gegen Ist', () {
    final tag = DateTime(2026, 10, 12);

    test('Menge an der Wurzel, Zeit an der Bratstraße', () {
      final a = wertePlanIstAus(
        [
          PlanKarte(
            productId: 'a1',
            abteilung: Abteilung.zerlegung,
            datum: tag,
            mengeKg: 1000,
            dauerMinuten: 90,
          ),
          // Ein späterer Schritt der Kette: seine Menge zählt nicht.
          PlanKarte(
            productId: 'a1',
            abteilung: Abteilung.bratstrasse,
            datum: tag,
            mengeKg: 950,
            dauerMinuten: 240,
            wurzel: false,
          ),
        ],
        [
          // Zwei Erfassungen am selben Tag zählen zusammen.
          produktion('a1', tag, roh: 600, minuten: 180),
          produktion('a1', tag, roh: 450, minuten: 120),
        ],
        artikel,
        spanne,
      );
      expect(a.produktionen, 1);
      expect(a.ungeplant, 0);
      final p = a.paare.single;
      expect(p.planKg, 1000);
      expect(p.istKg, 1050);
      expect(p.planMinuten, 240);
      expect(p.istMinuten, 300);
      expect(p.mengeAbweichung, closeTo(0.05, 1e-9));
      expect(p.mengeImBand, isTrue);
      expect(p.zeitAbweichung, closeTo(0.25, 1e-9));
      expect(p.zeitImBand, isFalse);
      expect(a.mengentreue, 1);
      expect(a.zeittreue, 0);
      expect(a.zuLang, 1);
      expect(a.abweichungen.single, same(p));
    });

    test('ohne Karte am Tag: ungeplant', () {
      final a = wertePlanIstAus(
        [
          PlanKarte(
            productId: 'a1',
            abteilung: Abteilung.zerlegung,
            datum: tag,
            mengeKg: 500,
          ),
        ],
        [
          produktion('a1', tag, roh: 500),
          produktion('a2', tag, roh: 300),
          produktion('a1', DateTime(2026, 10, 13), roh: 500),
        ],
        artikel,
        spanne,
      );
      expect(a.produktionen, 3);
      expect(a.ungeplant, 2);
      expect(a.mengentreue, 1);
      expect(a.zeittreue, isNull);
      expect(a.abweichungen, isEmpty);
    });

    test('Abteilungsfilter und Zeitraum', () {
      final a = wertePlanIstAus(
        [
          PlanKarte(
            productId: 'a2',
            abteilung: Abteilung.wurstkueche,
            datum: tag,
            mengeKg: 300,
          ),
        ],
        [
          produktion('a1', tag, roh: 500),
          produktion('a2', tag, roh: 200),
          // Vor dem Zeitraum.
          produktion('a2', DateTime(2026, 8, 3), roh: 200),
        ],
        artikel,
        spanne,
        abteilung: Abteilung.wurstkueche,
      );
      expect(a.produktionen, 1);
      expect(a.paare.single.artikel.id, 'a2');
      expect(a.paare.single.mengeAbweichung, closeTo(-1 / 3, 1e-9));
      expect(a.mengentreue, 0);
    });

    test('die größte Abweichung zuerst, im Verlauf je Woche', () {
      final a = wertePlanIstAus(
        [
          for (final d in [12, 13])
            PlanKarte(
              productId: 'a1',
              abteilung: Abteilung.zerlegung,
              datum: DateTime(2026, 10, d),
              mengeKg: 1000,
            ),
          PlanKarte(
            productId: 'a1',
            abteilung: Abteilung.zerlegung,
            datum: DateTime(2026, 10, 5),
            mengeKg: 1000,
          ),
        ],
        [
          produktion('a1', DateTime(2026, 10, 12), roh: 1150),
          produktion('a1', DateTime(2026, 10, 13), roh: 700),
          produktion('a1', DateTime(2026, 10, 5), roh: 1000),
        ],
        artikel,
        spanne,
      );
      expect(
        [for (final p in a.abweichungen) p.datum.day],
        [13, 12],
      );
      final wochen = {
        for (final p in a.verlauf) p.abschnitt: p.mengentreue,
      };
      expect(wochen[DateTime(2026, 10, 5)], 1);
      expect(wochen[DateTime(2026, 10, 12)], 0);
      expect(wochen[DateTime(2026, 9, 28)], isNull);
    });
  });

  group('Vorschau', () {
    const brat = BoardSpur(
      abteilung: Abteilung.bratstrasse,
      kapazitaetMinuten: 480,
    );
    const anlageA = BoardSpur(
      abteilung: Abteilung.verpackung,
      maschineId: 'm1',
      maschineName: 'Anlage A',
      kapazitaetMinuten: 400,
    );
    const anlageB = BoardSpur(
      abteilung: Abteilung.verpackung,
      maschineId: 'm2',
      maschineName: 'Anlage B',
      kapazitaetMinuten: 400,
    );

    SpurTagBelegung b(BoardSpur spur, DateTime tag, double minuten) =>
        SpurTagBelegung(spur: spur, tag: tag, produktionsMinuten: minuten);

    test('zehn Werktage ab heute, ohne Wochenende', () {
      final v = werteVorschauAus(const [], heute: heute);
      expect(v.tage, hasLength(kVorschauWerktage));
      expect(v.tage.first, heute);
      expect(v.tage[1], DateTime(2026, 10, 19));
      expect(v.tage.every((t) => t.weekday <= DateTime.friday), isTrue);
      expect(v.leer, isTrue);
    });

    test('je Abteilung zählt die vollste Spur', () {
      final montag = DateTime(2026, 10, 19);
      final v = werteVorschauAus(
        [
          b(brat, heute, 300),
          b(brat, montag, 560),
          b(anlageA, montag, 440),
          b(anlageB, montag, 100),
          // Am Wochenende: zählt nicht.
          b(brat, DateTime(2026, 10, 17), 900),
        ],
        heute: heute,
      );
      expect([for (final z in v.zeilen) z.name], ['Bratstraße', 'Verpackung']);
      final brZellen = v.zeilen.first.zellen;
      expect(brZellen[0].auslastung, closeTo(300 / 480, 1e-9));
      expect(brZellen[0].status, CapacityStatus.frei);
      expect(brZellen[1].status, CapacityStatus.ueberbucht);
      expect(v.zeilen.last.zellen[1].auslastung, closeTo(1.1, 1e-9));
      expect(
        [for (final (z, c) in v.ueberbucht) '${z.name} ${c.tag.day}'],
        ['Bratstraße 19', 'Verpackung 19'],
      );
    });

    test('mit Abteilung je Anlage', () {
      final montag = DateTime(2026, 10, 19);
      final v = werteVorschauAus(
        [
          b(brat, montag, 300),
          b(anlageA, montag, 200),
          b(anlageB, montag, 100),
        ],
        heute: heute,
        abteilung: Abteilung.verpackung,
      );
      expect([for (final z in v.zeilen) z.name], ['Anlage A', 'Anlage B']);
    });
  });

  group('Überblick', () {
    StatistikDaten daten({
      List<PlanKarte> karten = const [],
      List<ErfassteProduktion> produktionen = const [],
      List<ErfassteProduktion> vorher = const [],
      List<SpurTagBelegung> vorschau = const [],
      Map<String, StatistikArtikel> artikelListe = artikel,
    }) =>
        StatistikDaten(
          spanne: spanne,
          stand: heute,
          belegung: const [],
          karten: karten,
          produktionen: produktionen,
          artikel: artikelListe,
          vorher: StatistikVorher(
            spanne: spanne.vorher!,
            produktionen: vorher,
          ),
          vorschau: vorschau,
        );

    test('fünf Kennzahlen, Ausbeute mit dem Zeitraum davor', () {
      final u = werteUeberblickAus(
        daten(
          produktionen: [
            produktion('a1', DateTime(2026, 10, 5), roh: 100, fertig: 78),
            produktion('a1', DateTime(2026, 10, 12), roh: 100, fertig: 78),
          ],
          vorher: [
            produktion('a1', DateTime(2026, 9, 7), roh: 100, fertig: 82),
            produktion('a1', DateTime(2026, 9, 14), roh: 100, fertig: 82),
          ],
        ),
      );
      expect(
        [for (final k in u.kennzahlen) k.name],
        [
          'Ø Auslastung',
          'Mengentreue',
          'Zeittreue',
          'Ø Ausbeute',
          'Planerfüllung',
        ],
      );
      final ausbeute = u.kennzahlen[3];
      expect(ausbeute.wert, closeTo(0.78, 1e-9));
      expect(ausbeute.vorher, closeTo(0.82, 1e-9));
      expect(ausbeute.differenz, closeTo(-0.04, 1e-9));
      expect(ausbeute.ampel, Ampel.kritisch);
      expect(ausbeute.thema, StatistikThema.ausbeute);
      // Ohne Planung keine Auslastung — und keine Ampel.
      expect(u.kennzahlen.first.wert, isNull);
      expect(u.kennzahlen.first.ampel, Ampel.neutral);

      // Der Artikel selbst wird gemeldet.
      final h = u.hinweise.single;
      expect(h.ziel, HinweisZiel.artikel);
      expect(h.artikelId, 'a1');
      expect(h.text, 'Testwurst: Ausbeute 4,0 Punkte unter dem Zeitraum davor');
    });

    test('Hinweise: kritisch zuerst, höchstens fünf', () {
      final montag = DateTime(2026, 10, 19);
      const brat = BoardSpur(
        abteilung: Abteilung.bratstrasse,
        kapazitaetMinuten: 480,
      );
      const zer = BoardSpur(
        abteilung: Abteilung.zerlegung,
        kapazitaetMinuten: 480,
      );
      const wk = BoardSpur(
        abteilung: Abteilung.wurstkueche,
        kapazitaetMinuten: 480,
      );
      final u = werteUeberblickAus(
        daten(
          artikelListe: const {
            'a1': wurst,
            'a2': StatistikArtikel(
              id: 'a2',
              artikelnummer: '9002',
              bezeichnung: 'Testschinken',
              abteilungen: {'wurstkueche'},
              luecken: {},
            ),
          },
          karten: [
            // Offen, vor drei Tagen.
            PlanKarte(
              productId: 'a2',
              abteilung: Abteilung.wurstkueche,
              datum: DateTime(2026, 10, 13),
            ),
            // Offen, aber älter als zwei Wochen: zählt nicht.
            PlanKarte(
              productId: 'a2',
              abteilung: Abteilung.wurstkueche,
              datum: DateTime(2026, 9, 21),
            ),
            // Erledigt.
            PlanKarte(
              productId: 'a1',
              abteilung: Abteilung.zerlegung,
              datum: DateTime(2026, 10, 14),
              erledigt: Erledigt.erfasst,
            ),
          ],
          vorschau: [
            SpurTagBelegung(spur: brat, tag: montag, produktionsMinuten: 600),
            SpurTagBelegung(spur: zer, tag: montag, produktionsMinuten: 500),
            SpurTagBelegung(spur: wk, tag: montag, produktionsMinuten: 490),
          ],
        ),
      );
      expect(
        [for (final h in u.hinweise) h.schwere],
        [
          HinweisSchwere.kritisch,
          HinweisSchwere.kritisch,
          HinweisSchwere.warnung,
        ],
      );
      // Die zwei vollsten Tage, nicht alle drei.
      expect(u.hinweise[0].text, 'Mo 19.10.: Bratstraße 125 % belegt');
      expect(u.hinweise[0].ziel, HinweisZiel.board);
      expect(u.hinweise[0].tag, montag);
      expect(u.hinweise[1].text, 'Mo 19.10.: Zerlegung 104 % belegt');
      expect(
        u.hinweise[2].text,
        '1 Karte der letzten 14 Tage weder erfasst noch abgehakt',
      );
      expect(u.hinweise[2].ziel, HinweisZiel.erfassung);
      expect(u.hinweise.length, lessThanOrEqualTo(kHinweiseHoechstens));
    });

    test('Lücken der aktiven Artikel als Hinweis', () {
      final u = werteUeberblickAus(
        daten(
          artikelListe: const {
            'a1': StatistikArtikel(
              id: 'a1',
              artikelnummer: '9001',
              bezeichnung: 'Testwurst',
              luecken: {ArtikelLuecke.ohneAusbeute},
            ),
            // Mit Lücke, aber nicht aktiv: zählt nicht.
            'a2': StatistikArtikel(
              id: 'a2',
              artikelnummer: '9002',
              bezeichnung: 'Testschinken',
              luecken: {ArtikelLuecke.ohneAusbeute},
            ),
          },
          produktionen: [produktion('a1', DateTime(2026, 10, 12), roh: 100)],
        ),
      );
      final h = u.hinweise.single;
      expect(h.text, '1 aktiver Artikel mit Lücken in den Stammdaten');
      expect(h.schwere, HinweisSchwere.info);
      expect(h.thema, StatistikThema.artikel);
    });
  });
}
