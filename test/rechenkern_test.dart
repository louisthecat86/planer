import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/allergen_hervorhebung.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/naehrwert_rundung.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechenkern.dart';

/// Tests für den Rechenkern der Produktentwicklung: Zutatenliste mit
/// QUID, Fleischanteil nach LMIV, Unterrezepturen, Wasser, Nährwerte,
/// Allergene. Alle Rezepturen sind erfunden; die Zahlen sind von Hand
/// nachgerechnet und stehen jeweils dabei.
void main() {
  // ── Zutaten ─────────────────────────────────────────────────────────
  RechenZutat schwein({
    String id = 'schwein',
    String name = 'Schweinefleisch S2',
    double fett = 20,
    double eiweiss = 18,
    double? bindegewebe,
    Set<String> allergene = const {},
  }) =>
      RechenZutat(
        id: id,
        name: name,
        istFleisch: true,
        tierart: Tierart.schwein,
        bindegewebe: bindegewebe,
        quidPflicht: true,
        allergene: allergene,
        naehrwerte: Naehrwerte(fett: fett, eiweiss: eiweiss),
      );

  const salz = RechenZutat(
    id: 'salz',
    name: 'Salz',
    naehrwerte: Naehrwerte(salz: 100, wasser: 0),
  );
  const pfeffer = RechenZutat(
    id: 'pfeffer',
    name: 'Pfeffer',
    naehrwerte: Naehrwerte(kohlenhydrate: 50, wasser: 10),
  );
  const wasser = RechenZutat(id: 'wasser', name: 'Wasser', istWasser: true);

  RechenPosition z(RechenZutat zutat, double kg, {bool? quid}) =>
      RechenPosition.zutat(zutat, mengeKg: kg, quidPflicht: quid);

  RechenRezeptur rezeptur(
    List<RechenPosition> positionen, {
    String id = 'r',
    String name = 'Testrezeptur',
    double verlust = 0,
    double fettVerlust = 0,
    Verlustart art = Verlustart.trocknung,
  }) =>
      RechenRezeptur(
        id: id,
        name: name,
        positionen: positionen,
        verlustProzent: verlust,
        fettVerlustProzent: fettVerlust,
        verlustart: art,
      );

  group('Zutatenliste und QUID', () {
    test('einfach: absteigend nach Masse, Mengen nur wo verlangt', () {
      final e = berechne(
        rezeptur([z(schwein(), 80), z(salz, 2), z(wasser, 18)]),
      );
      expect(e.eingesetztKg, 100);
      expect(e.endgewichtKg, 100);
      expect(e.zutatenliste, 'Schweinefleisch (80,0 %), Wasser, Salz');
      expect(e.fleischanteilProzent, closeTo(80, 1e-9));
    });

    test('über 100 %: Gramm je 100 g Enderzeugnis, nicht die Charge', () {
      // 150 kg Fleisch + 10 kg Gewürz = 160 kg, 37,5 % Verlust → 100 kg.
      // Die Suite schrieb hier „150.000,0 g".
      final e = berechne(
        rezeptur(
          [
            z(schwein(fett: 25, eiweiss: 17), 150),
            z(const RechenZutat(id: 'g', name: 'Gewürz'), 10),
          ],
          verlust: 37.5,
        ),
      );
      expect(e.endgewichtKg, closeTo(100, 1e-9));
      expect(
        e.zutatenliste,
        'hergestellt aus 150 g Schweinefleisch je 100 g des '
        'Enderzeugnisses, Gewürz',
      );
      expect(e.fleischanteilProzent, closeTo(150, 1e-9));
      expect(e.ohneNaehrwerte, ['Gewürz']);
    });

    test('Wasser zählt mit dem, was nach dem Verlust bleibt', () {
      // 100 kg, 10 % Verlust → 90 kg. Der Verlust geht zuerst vom Wasser:
      // 20 − 10 = 10 kg bleiben, 11,1 %.
      final e = berechne(
        rezeptur(
          [z(schwein(), 80), z(wasser, 20, quid: true)],
          verlust: 10,
        ),
      );
      expect(e.endgewichtKg, closeTo(90, 1e-9));
      expect(e.zutatenliste, 'Schweinefleisch (88,9 %), Wasser (11,1 %)');
    });

    test('Wasser bis 5 % steht nicht in der Liste', () {
      // 103 kg, 5 % Verlust → 97,85 kg; vom Wasser bleiben 8 − 5,15 =
      // 2,85 kg, also 2,9 %.
      final e = berechne(
        rezeptur([z(schwein(), 95), z(wasser, 8)], verlust: 5),
      );
      expect(e.zutatenliste, 'Schweinefleisch (97,1 %)');
      final w = e.zeilen.singleWhere((zeile) => zeile.istWasser);
      expect(w.ausgelassen, isTrue);
      expect(w.anteilProzent, closeTo(2.9126, 1e-3));
      expect(e.warnungen.any((t) => t.contains('Wasser')), isTrue);
    });

    test('Wasser, das der Verlust ganz nimmt, steht nicht in der Liste', () {
      // 5 kg Wasser, 10 % Verlust von 100 kg: Es bleibt nichts.
      final e = berechne(
        rezeptur([z(schwein(), 95), z(wasser, 5)], verlust: 10),
      );
      expect(
        e.zutatenliste,
        'hergestellt aus 106 g Schweinefleisch je 100 g des Enderzeugnisses',
      );
      expect(e.zeilen.singleWhere((zz) => zz.istWasser).ausgelassen, isTrue);
      expect(
        e.warnungen.any((w) => w.contains('geht ganz mit dem Verlust')),
        isTrue,
      );
    });

    test('Zeilen gleichen Namens stehen einmal da', () {
      // Trinkwasser und Eis heißen beide „Wasser".
      const eis = RechenZutat(
        id: 'eis',
        name: 'Scherbeneis',
        etikettName: 'Wasser',
        istWasser: true,
      );
      // „Speck" als Zutat und als Fett über dem Grenzwert.
      const speck = RechenZutat(
        id: 'speck',
        name: 'Speck',
        naehrwerte: Naehrwerte(fett: 80, eiweiss: 5, wasser: 15),
      );
      final e = berechne(
        rezeptur([
          z(schwein(fett: 40, eiweiss: 14), 70),
          z(speck, 5),
          z(wasser, 10),
          z(eis, 15),
        ]),
      );
      // Speck: 5 kg + 70 × (40 − 30) / 70 = 15 kg.
      expect(
        e.zutatenliste,
        'Schweinefleisch (60,0 %), Wasser, Speck',
      );
      expect(
        e.zeilen.singleWhere((zz) => zz.name == 'Wasser').masseKg,
        closeTo(25, 1e-9),
      );
      expect(
        e.zeilen.singleWhere((zz) => zz.name == 'Speck').masseKg,
        closeTo(15, 1e-9),
      );
    });

    test('gleiche Zutaten aus Unterrezeptur und Rezeptur stehen einmal da', () {
      final wuerze = rezeptur(
        [z(salz, 1), z(pfeffer, 1)],
        id: 'w',
        name: 'Würzmischung',
      );
      final e = berechne(
        rezeptur([
          z(schwein(), 96),
          z(salz, 2),
          RechenPosition.unterrezeptur(wuerze, mengeKg: 2),
        ]),
      );
      expect(e.zutatenliste, 'Schweinefleisch (96,0 %), Salz, Pfeffer');
      final s = e.zeilen.singleWhere((zeile) => zeile.name == 'Salz');
      expect(s.masseKg, closeTo(3, 1e-9));
    });

    test('Etikettname und Unterzutaten', () {
      const mischung = RechenZutat(
        id: 'm',
        name: 'Gewürzmischung 4711',
        etikettName: 'Gewürze',
        unterzutaten: 'Pfeffer, Paprika',
        quidPflicht: true,
      );
      final e = berechne(rezeptur([z(schwein(), 98), z(mischung, 2)]));
      expect(
        e.zutatenliste,
        'Schweinefleisch (98,0 %), Gewürze (Pfeffer, Paprika) (2,0 %)',
      );
    });
  });

  group('Fleischanteil nach LMIV', () {
    test('Fett über dem Grenzwert: der Überschuss steht als Speck da', () {
      // 100 kg mit 40 % Fett, Grenze Schwein 30 %:
      // 100 × (40 − 30) / 70 = 14,29 kg Speck, 85,71 kg Fleisch.
      final e = berechne(rezeptur([z(schwein(fett: 40, eiweiss: 14), 100)]));
      // Der Überschuss ohne Mengenangabe — QUID gilt dem Fleisch (F19).
      expect(e.zutatenliste, 'Schweinefleisch (85,7 %), Speck');
      final p = e.tierarten.single;
      expect(p.ueberschussFettKg, closeTo(14.2857, 1e-3));
      expect(p.bindegewebeUeberGrenze, isFalse);
      expect(e.fleischanteilProzent, closeTo(85.714, 1e-3));
      expect(e.warnungen.any((t) => t.contains('Speck')), isTrue);
    });

    test('Bindegewebe über dem Grenzwert steht als eigene Zutat da', () {
      // Eiweiß 16 %, Kollagen 40 % davon = 6,4 %.
      // MAXCOL = 25 × (16 − 6,4) / 75 = 3,2 → EXCOL 3,2 → EXCT 14,8 %.
      // Fett 20 % bleibt unter MAXFAT = 30 × (100 − 14,8 − 20) / 70.
      final e = berechne(
        rezeptur([z(schwein(fett: 20, eiweiss: 16, bindegewebe: 40), 100)]),
      );
      final p = e.tierarten.single;
      expect(p.kollagenVerhaeltnis, closeTo(40, 1e-9));
      expect(p.ueberschussBindegewebeKg, closeTo(14.8, 1e-9));
      expect(p.fettUeberGrenze, isFalse);
      // LMIV Anhang VII Teil B Nr. 17: Der Überschuss wird genannt (F16).
      expect(e.zutatenliste, 'Schweinefleisch (85,2 %), Schweinebindegewebe');
      expect(e.fleischanteilProzent, closeTo(85.2, 1e-9));
      expect(
        e.warnungen.any((t) => t.contains('„Schweinebindegewebe"')),
        isTrue,
      );
    });

    test('Fett und Bindegewebe zugleich: beide zählen', () {
      // Eiweiß 14 %, Kollagen 5,6 %: MAXCOL 2,8 → EXCT 12,95 %.
      // MAXFAT = 30 × (100 − 12,95 − 40) / 70 = 20,164 → EXFAT 19,836 %.
      // Fleisch = 100 − 19,836 − 12,95 = 67,214 %.
      // Die Suite korrigierte hier nur das Fett.
      final e = berechne(
        rezeptur([z(schwein(fett: 40, eiweiss: 14, bindegewebe: 40), 100)]),
      );
      final p = e.tierarten.single;
      expect(p.ueberschussBindegewebeKg, closeTo(12.95, 1e-9));
      expect(p.ueberschussFettKg, closeTo(19.8357, 1e-3));
      expect(p.fleischKg, closeTo(67.2143, 1e-3));
      // Absteigend nach Gewicht: 19,8 kg Speck vor 12,95 kg Bindegewebe.
      expect(
        e.zutatenliste,
        'Schweinefleisch (67,2 %), Speck, Schweinebindegewebe',
      );
    });

    test('Bindegewebe gemittelt nach Fleischeiweiß, nur wo ein Wert steht',
        () {
      // A: 10 kg Eiweiß, Verhältnis 10 → 1 kg Kollagen.
      // B: 5 kg Eiweiß, Verhältnis 40 → 2 kg Kollagen.
      // C ohne Wert zählt nicht in den Mittelwert: 3 / 15 = 20 %.
      // (Nach Masse gemittelt wären es 25 %.)
      final e = berechne(
        rezeptur([
          z(schwein(id: 'a', eiweiss: 20, bindegewebe: 10), 50),
          z(schwein(id: 'b', eiweiss: 10, bindegewebe: 40), 50),
          z(schwein(id: 'c', eiweiss: 15), 50),
        ]),
      );
      expect(e.tierarten.single.kollagenVerhaeltnis, closeTo(20, 1e-9));
    });

    test('reine Schwarte: nie mehr Bindegewebe, als da ist', () {
      // Eiweiß 30 %, davon 90 % Kollagen: Der Faktor 4,625 ergäbe über
      // 100 % Bindegewebe. Höchstens alles außer dem Fett (10 %) zählt —
      // Fleisch bleibt keines, und die Masse stimmt.
      final e = berechne(
        rezeptur(
          [z(schwein(fett: 10, eiweiss: 30, bindegewebe: 90), 20)],
        ),
      );
      final p = e.tierarten.single;
      expect(p.ueberschussBindegewebeKg, closeTo(18, 1e-9));
      expect(p.ueberschussFettKg, closeTo(2, 1e-9));
      expect(p.fleischKg, closeTo(0, 1e-9));
      expect(e.fleischanteilProzent, closeTo(0, 1e-9));
      expect(e.zutatenliste, startsWith('Schweinebindegewebe, Speck'));
    });

    test('ohne Bindegewebswerte wird das Bindegewebe nicht geprüft', () {
      final e = berechne(rezeptur([z(schwein(), 100)]));
      expect(e.tierarten.single.kollagenVerhaeltnis, isNull);
      expect(e.tierarten.single.ueberschussBindegewebeKg, 0);
    });

    test('Tierarten getrennt, Geflügel mit eigenen Grenzen', () {
      const pute = RechenZutat(
        id: 'pute',
        name: 'Putenoberkeule',
        istFleisch: true,
        tierart: Tierart.pute,
        naehrwerte: Naehrwerte(fett: 20, eiweiss: 18),
      );
      // Pute 20 % Fett, Grenze 15 %: 50 × 5 / 85 = 2,94 kg Putenfett.
      final e = berechne(rezeptur([z(schwein(), 50), z(pute, 50)]));
      expect(
        e.tierarten.map((p) => p.tierart),
        [Tierart.schwein, Tierart.pute],
      );
      expect(
        e.zutatenliste,
        'Schweinefleisch (50,0 %), Putenfleisch (47,1 %), Putenfett',
      );
    });

    test('Fleisch ohne Tierart steht einzeln da, mit Warnung', () {
      const fleisch = RechenZutat(
        id: 'x',
        name: 'Fleischabschnitte',
        istFleisch: true,
        quidPflicht: true,
      );
      final e = berechne(rezeptur([z(fleisch, 100)]));
      expect(e.tierarten, isEmpty);
      expect(e.fleischanteilProzent, 0);
      expect(e.zutatenliste, 'Fleischabschnitte (100,0 %)');
      expect(e.warnungen.any((t) => t.contains('ohne Tierart')), isTrue);
    });
  });

  group('Unterrezepturen (F13)', () {
    // Röstzwiebeln: 10 kg Zwiebeln, 50 % Trocknungsverlust → 5 kg.
    const zwiebeln = RechenZutat(
      id: 'zwiebeln',
      name: 'Zwiebeln',
      quidPflicht: true,
      naehrwerte: Naehrwerte(kohlenhydrate: 7, wasser: 90),
    );

    RechenRezeptur roestzwiebeln() => RechenRezeptur(
          id: 'roest',
          name: 'Röstzwiebeln',
          positionen: [z(zwiebeln, 10)],
          verlustProzent: 50,
        );

    test('die fertige Menge zählt — ihr Verlust nicht ein zweites Mal', () {
      // 95 kg Fleisch + 5 kg fertige Röstzwiebeln = 100 kg Endgewicht.
      // Für 5 kg Röstzwiebeln braucht es 10 kg Zwiebeln: 10 %.
      // (Die Suite zog den Verlust nochmal ab und kam auf 97,5 kg.)
      final e = berechne(
        rezeptur([
          z(schwein(), 95),
          RechenPosition.unterrezeptur(roestzwiebeln(), mengeKg: 5),
        ]),
      );
      expect(e.eingesetztKg, 100);
      expect(e.endgewichtKg, 100);
      expect(e.rohmasseKg, 105);
      expect(e.zutatenliste, 'Schweinefleisch (95,0 %), Zwiebeln (10,0 %)');
    });

    test('nur ein Teil der Unterrezeptur: die Zutaten anteilig', () {
      // 2,5 kg von 5 kg Röstzwiebeln → 5 kg Zwiebeln.
      final e = berechne(
        rezeptur([
          z(schwein(), 97.5),
          RechenPosition.unterrezeptur(roestzwiebeln(), mengeKg: 2.5),
        ]),
      );
      final zeile = e.zeilen.singleWhere((zz) => zz.name == 'Zwiebeln');
      expect(zeile.masseKg, closeTo(5, 1e-9));
    });

    test('Nährwerte der Unterrezeptur nach ihrem Verlust', () {
      // Röstzwiebeln: 0,7 kg Kohlenhydrate in 5 kg → in 100 kg Wurst
      // 0,7 g je 100 g.
      final e = berechne(
        rezeptur([
          z(schwein(), 95),
          RechenPosition.unterrezeptur(roestzwiebeln(), mengeKg: 5),
        ]),
      );
      expect(e.je100g.kohlenhydrate, closeTo(0.7, 1e-9));
    });

    test('eine Rezeptur, die sich selbst enthält, hängt nicht', () {
      final positionenA = <RechenPosition>[];
      final a = RechenRezeptur(id: 'a', name: 'A', positionen: positionenA);
      final b = RechenRezeptur(
        id: 'b',
        name: 'B',
        positionen: [RechenPosition.unterrezeptur(a, mengeKg: 1)],
      );
      positionenA
        ..add(z(schwein(), 10))
        ..add(RechenPosition.unterrezeptur(b, mengeKg: 5));

      final e = berechne(a);
      expect(e.warnungen.any((t) => t.contains('sich selbst')), isTrue);
    });
  });

  group('Nährwerte', () {
    const fleisch = RechenZutat(
      id: 'f',
      name: 'Schweinefleisch',
      istFleisch: true,
      tierart: Tierart.schwein,
      naehrwerte: Naehrwerte(
        fett: 20,
        gesaettigteFettsaeuren: 8,
        eiweiss: 18,
        salz: 0.1,
        wasser: 60,
      ),
    );

    test('ohne Verlust: wie die Zutat, Energie aus den Nährstoffen', () {
      final e = berechne(rezeptur([z(fleisch, 100)]));
      expect(e.je100g.fett, closeTo(20, 1e-9));
      expect(e.je100g.eiweiss, closeTo(18, 1e-9));
      // 20 × 37 + 18 × 17 = 1046 kJ, 20 × 9 + 18 × 4 = 252 kcal.
      expect(e.je100g.energieKj, closeTo(1046, 1e-9));
      expect(e.je100g.energieKcal, closeTo(252, 1e-9));
    });

    test('Trocknung: nur Wasser geht, der Rest wird dichter', () {
      final e = berechne(rezeptur([z(fleisch, 100)], verlust: 20));
      expect(e.je100g.fett, closeTo(25, 1e-9));
      expect(e.je100g.eiweiss, closeTo(22.5, 1e-9));
      expect(e.je100g.wasser, closeTo(50, 1e-9));
    });

    test('Garen mit Fettverlust: Fett nach Angabe, der Rest als Saft', () {
      // 20 kg Verlust, davon 5 kg Fett. Saft 15 kg: 0,75 kg Eiweiß,
      // 0,15 kg Salz (nur 0,1 kg da), 0,15 kg Zucker (keiner da), der Rest
      // Wasser: 15 − 0,75 − 0,1 = 14,15 kg.
      final e = berechne(
        rezeptur(
          [z(fleisch, 100)],
          verlust: 20,
          fettVerlust: 5,
          art: Verlustart.garen,
        ),
      );
      expect(e.je100g.fett, closeTo(18.75, 1e-9));
      expect(e.je100g.gesaettigteFettsaeuren, closeTo(7.5, 1e-9));
      expect(e.je100g.eiweiss, closeTo(21.5625, 1e-9));
      expect(e.je100g.salz, closeTo(0, 1e-9));
      expect(e.je100g.wasser, closeTo(57.3125, 1e-9));
      // Was hineinging, abzüglich Verlust: 98,1 − 20 = 78,1 kg in 80 kg.
      final n = e.je100g;
      expect(
        n.fett! + n.eiweiss! + n.salz! + n.wasser! + n.kohlenhydrate!,
        closeTo(97.625, 1e-9),
      );
    });

    test('Garen: das BEFFE geht anteilig mit dem Eiweiß', () {
      // 18 kg Eiweiß, davon 15 kg BEFFE. 20 kg Saft nehmen 1 kg Eiweiß:
      // BEFFE 15 × 17 / 18 = 14,1667 kg in 80 kg.
      const mitBeffe = RechenZutat(
        id: 'fb',
        name: 'Schweinefleisch',
        istFleisch: true,
        tierart: Tierart.schwein,
        naehrwerte: Naehrwerte(fett: 20, eiweiss: 18, beffe: 15, wasser: 61),
      );
      final e = berechne(
        rezeptur([z(mitBeffe, 100)], verlust: 20, art: Verlustart.garen),
      );
      expect(e.je100g.eiweiss, closeTo(17 / 80 * 100, 1e-9));
      expect(e.je100g.beffe, closeTo(15 * 17 / 18 / 80 * 100, 1e-9));
    });

    test('BEFFE: Fleisch ohne Wert wird genannt', () {
      const mit = RechenZutat(
        id: 'mit',
        name: 'Schweineschulter',
        istFleisch: true,
        tierart: Tierart.schwein,
        naehrwerte: Naehrwerte(fett: 20, eiweiss: 18, beffe: 15),
      );
      const ohne = RechenZutat(
        id: 'ohne',
        name: 'Schweinebacke',
        istFleisch: true,
        tierart: Tierart.schwein,
        naehrwerte: Naehrwerte(fett: 30, eiweiss: 15),
      );
      final beide = berechne(rezeptur([z(mit, 50), z(ohne, 30), z(salz, 2)]));
      // Nur die Schulter zählt: 50 × 15 % = 7,5 kg in 82 kg.
      expect(beide.je100g.beffe, closeTo(7.5 / 82 * 100, 1e-9));
      // Salz ist kein Fleisch und braucht keinen Wert.
      expect(beide.ohneBeffe, ['Schweinebacke']);
      // Hat keine Zutat einen Wert, gibt es kein BEFFE und keinen Hinweis.
      final keine = berechne(rezeptur([z(ohne, 30), z(salz, 2)]));
      expect(keine.je100g.beffe, isNull);
      expect(keine.ohneBeffe, isEmpty);
    });

    test('mehr Fettverlust als Fett: der Rest geht als Wasser', () {
      const mager = RechenZutat(
        id: 'm',
        name: 'Putenbrust',
        istFleisch: true,
        tierart: Tierart.pute,
        naehrwerte: Naehrwerte(fett: 2, eiweiss: 23, wasser: 74, asche: 1),
      );
      // 100 kg mit 2 kg Fett, 10 % Verlust, davon 5 % Fett: Es gehen die
      // 2 kg Fett und 8 kg Wasser.
      final e = berechne(
        rezeptur([z(mager, 100)], verlust: 10, fettVerlust: 5),
      );
      expect(e.je100g.fett, closeTo(0, 1e-9));
      expect(e.je100g.wasser, closeTo(66 / 90 * 100, 1e-9));
      expect(
        e.warnungen.any((w) => w.contains('Fettverlust')),
        isTrue,
      );
    });

    test('„kein Verlust" übergeht einen eingetragenen Verlust', () {
      final e = berechne(
        rezeptur([z(fleisch, 100)], verlust: 20, art: Verlustart.keiner),
      );
      expect(e.endgewichtKg, 100);
    });
  });

  group('Allergene', () {
    Hervorhebung h(String text, Set<String> allergene) =>
        hebeAllergeneHervor(text, allergene);

    test('ganze Wortteile in Großbuchstaben', () {
      expect(h('Weizenmehl', {'gluten'}).text, 'WEIZENmehl');
      expect(h('Gerstenmalzextrakt', {'gluten'}).text, 'GERSTENmalzextrakt');
      expect(h('Vollmilchpulver', {'milch'}).text, 'VollMILCHpulver');
      expect(h('Erdnussöl', {'erdnuesse'}).text, 'ERDNUSSöl');
      expect(h('Senfsaat', {'senf'}).text, 'SENFsaat');
      expect(h('Krebstiere', {'krebstiere'}).text, 'KREBSTIERE');
      expect(
        h('Natriummetabisulfit', {'sulfit'}).text,
        'NatriummetabiSULFIT',
      );
    });

    test('Eier: nicht jedes „ei" (die Suite schrieb „SpEIsesalz")', () {
      expect(h('Speisesalz', {'eier'}).text, 'Speisesalz');
      expect(h('Speisesalz', {'eier'}).gefunden, isEmpty);
      expect(h('Weizen', {'eier'}).text, 'Weizen');
      expect(h('Hühnerei', {'eier'}).text, 'HühnerEI');
      expect(h('Vollei, Eigelb', {'eier'}).text, 'VollEI, EIGELB');
      expect(h('Volleipulver', {'eier'}).text, 'VollEIpulver');
      expect(h('Eier', {'eier'}).text, 'EIER');
    });

    test('nur was die Zutat enthält, und keine falschen Freunde', () {
      expect(h('Kakaobutter', {'milch'}).text, 'Kakaobutter');
      expect(h('Weizenmehl', {'milch'}).text, 'Weizenmehl');
      expect(h('Butter', <String>{}).text, 'Butter');
    });

    test('E-Nummern der Sulfite zählen als genannt', () {
      expect(h('Konservierungsstoff E 223', {'sulfit'}).gefunden, {'sulfit'});
    });

    test('ein Allergen, das die Liste nicht nennt, gibt eine Warnung', () {
      const mischung = RechenZutat(
        id: 'm',
        name: 'Gewürzmischung',
        unterzutaten: 'Salz, Pfeffer',
        allergene: {'senf'},
      );
      final ohne = berechne(rezeptur([z(schwein(), 98), z(mischung, 2)]));
      expect(ohne.warnungen.any((t) => t.contains('Senf')), isTrue);

      const richtig = RechenZutat(
        id: 'm2',
        name: 'Gewürzmischung',
        unterzutaten: 'Salz, Senfsaat',
        allergene: {'senf'},
      );
      final mit = berechne(rezeptur([z(schwein(), 98), z(richtig, 2)]));
      expect(mit.warnungen.any((t) => t.contains('Senf')), isFalse);
      expect(
        mit.zutatenliste,
        'Schweinefleisch (98,0 %), Gewürzmischung (Salz, SENFsaat)',
      );
    });

    test('Allergene und Hilfsstoffe mit Herkunft, in der Rangfolge', () {
      const sahne = RechenZutat(
        id: 's',
        name: 'Sahne',
        allergene: {'milch'},
      );
      const mehl = RechenZutat(
        id: 'w',
        name: 'Weizenmehl',
        allergene: {'gluten'},
        verarbeitungshilfsstoffe: ['Trennmittel'],
      );
      const kaese = RechenZutat(
        id: 'k',
        name: 'Käse',
        allergene: {'milch'},
      );
      final e = berechne(
        rezeptur([z(sahne, 5), z(mehl, 5), z(kaese, 5)]),
      );
      expect(e.allergene.keys, ['gluten', 'milch']);
      expect(e.allergene['milch'], ['Käse', 'Sahne']);
      expect(e.verarbeitungshilfsstoffe, {
        'Trennmittel': ['Weizenmehl'],
      });
    });
  });

  group('Rundung für das Etikett', () {
    test('nach dem Leitfaden der EU-Kommission', () {
      expect(naehrwertGerundet(Naehrstoff.energieKj, 1046.4), '1046');
      expect(naehrwertGerundet(Naehrstoff.fett, 12.4), '12');
      expect(naehrwertGerundet(Naehrstoff.fett, 3.44), '3,4');
      expect(naehrwertGerundet(Naehrstoff.fett, 9.96), '10');
      expect(naehrwertGerundet(Naehrstoff.fett, 0.5), '< 0,5');
      expect(
        naehrwertGerundet(Naehrstoff.gesaettigteFettsaeuren, 0.08),
        '< 0,1',
      );
      expect(
        naehrwertGerundet(Naehrstoff.gesaettigteFettsaeuren, 0.14),
        '0,1',
      );
      expect(naehrwertGerundet(Naehrstoff.salz, 1.234), '1,2');
      // Unter 1 g auf Hundertstel; erst was dabei 1,00 ergibt, auf Zehntel.
      expect(naehrwertGerundet(Naehrstoff.salz, 0.96), '0,96');
      expect(naehrwertGerundet(Naehrstoff.salz, 0.996), '1,0');
      expect(naehrwertGerundet(Naehrstoff.salz, 0.456), '0,46');
      expect(naehrwertGerundet(Naehrstoff.salz, 0.01), '< 0,01');
      expect(naehrwertGerundet(Naehrstoff.eiweiss, null), '—');
    });
  });

  group('Modell', () {
    test('ein Stand als JSON rechnet genauso', () {
      final wuerze = rezeptur(
        [z(salz, 1), z(pfeffer, 1)],
        id: 'w',
        name: 'Würzmischung',
      );
      final original = rezeptur(
        [
          z(schwein(bindegewebe: 15, allergene: {'sellerie'}), 90),
          z(wasser, 8),
          RechenPosition.unterrezeptur(wuerze, mengeKg: 2),
        ],
        verlust: 12,
        fettVerlust: 1,
        art: Verlustart.garen,
      );
      final kopie = RechenRezeptur.ausJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      final a = berechne(original);
      final b = berechne(kopie);
      expect(b.zutatenliste, a.zutatenliste);
      expect(b.endgewichtKg, a.endgewichtKg);
      expect(b.je100g.fett, a.je100g.fett);
      expect(b.allergene, a.allergene);
    });

    test('Tierart aus gespeicherten Werten und Wörtern', () {
      expect(Tierart.aus('schwein'), Tierart.schwein);
      expect(Tierart.aus('pork'), Tierart.schwein);
      expect(Tierart.aus('Schweinebauch'), Tierart.schwein);
      expect(Tierart.aus('Kalbsleberwurst'), Tierart.kalb);
      expect(Tierart.aus('Rinderhack'), Tierart.rind);
      expect(Tierart.aus('Hähnchenbrust'), Tierart.huhn);
      expect(Tierart.aus(''), isNull);
      expect(Tierart.aus(null), isNull);
    });

    test('wirksamer Verlust: „kein Verlust" zählt als 0', () {
      expect(rezeptur(const [], verlust: 12).wirksamerVerlust, 12);
      expect(
        rezeptur(const [], verlust: 12, art: Verlustart.keiner)
            .wirksamerVerlust,
        0,
      );
      expect(rezeptur(const [], verlust: 120).wirksamerVerlust, 100);
      expect(rezeptur(const [], verlust: -5).wirksamerVerlust, 0);
    });

    test('Verlustart aus gespeicherten Werten', () {
      expect(Verlustart.aus('cooking'), Verlustart.garen);
      expect(Verlustart.aus('none'), Verlustart.keiner);
      expect(Verlustart.aus(null), Verlustart.trocknung);
    });
  });
}
