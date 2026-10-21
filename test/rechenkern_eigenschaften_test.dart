import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/utils/format.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/fleisch_optimierung.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechenkern.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rueckrechnung.dart';

/// Eigenschaften des Rechenkerns an vielen zufälligen Rezepturen: Masse
/// bleibt erhalten, die Liste ist absteigend, Fleisch, Fett und
/// Bindegewebe ergeben zusammen die Fleischzutaten, eine Unterrezeptur
/// rechnet wie eine Zutat mit ihren Nährwerten, Reihenfolge und Maßstab
/// der Zeilen ändern nichts. Der Zufall hat einen festen Startwert — jeder
/// Lauf prüft dieselben Rezepturen. Alle Zutaten sind erfunden.
void main() {
  group('Rechenkern', () {
    test('Endgewicht, Masse und Reihenfolge', () {
      _jedeRezeptur((r, e, grund) {
        final eingesetzt = _eingesetzt(r);
        expect(e.eingesetztKg, closeTo(eingesetzt, 1e-9), reason: grund);
        expect(
          e.endgewichtKg,
          closeTo(_endgewicht(r), 1e-9 * math.max(1, eingesetzt)),
          reason: grund,
        );
        for (var i = 1; i < e.zeilen.length; i++) {
          expect(
            e.zeilen[i - 1].masseKg >= e.zeilen[i].masseKg,
            isTrue,
            reason: '$grund\nabsteigend bei Zeile $i',
          );
        }
        // Rohmasse: jede Zutat mit der Menge, die in der Charge steckt.
        final roh = _rohJeZutat(r);
        final rohSumme = roh.values.fold<double>(0, (s, v) => s + v);
        expect(e.rohmasseKg, closeTo(rohSumme, 1e-6), reason: grund);
        // Alles außer zugesetztem Wasser steht mit der Rohmasse da —
        // Fleisch samt Fett und Bindegewebe über dem Grenzwert.
        final ohneWasser = e.zeilen
            .where((z) => !z.istWasser)
            .fold<double>(0, (s, z) => s + z.masseKg);
        final wasserRoh = roh.entries
            .where((m) => _istWasser(m.key))
            .fold<double>(0, (s, m) => s + m.value);
        expect(ohneWasser, closeTo(rohSumme - wasserRoh, 1e-6), reason: grund);
        // Zugesetztes Wasser mit dem, was nach allen Verlusten bleibt.
        final wasser = e.zeilen
            .where((z) => z.istWasser)
            .fold<double>(0, (s, z) => s + z.masseKg);
        expect(wasser, closeTo(_wasserRest(r), 1e-6), reason: grund);
      });
    });

    test('jede Zeile einmal, Mengenangaben wie verlangt', () {
      _jedeRezeptur((r, e, grund) {
        final namen = [for (final z in e.zeilen) z.name];
        expect(namen.toSet().length, namen.length, reason: grund);
        for (final z in e.zeilen) {
          final anteil = e.endgewichtKg > 0
              ? z.masseKg / e.endgewichtKg * 100
              : 0.0;
          expect(z.anteilProzent, closeTo(anteil, 1e-9), reason: grund);
          if (!z.quid) {
            expect(z.text.contains('%'), isFalse, reason: grund);
          } else if (z.anteilProzent <= 100) {
            expect(
              z.text,
              endsWith('(${Format.zahl(z.anteilProzent, nachkomma: 1)} %)'),
              reason: grund,
            );
          } else {
            expect(z.text, startsWith('hergestellt aus '), reason: grund);
            expect(
              z.text,
              contains(' je 100 g des Enderzeugnisses'),
              reason: grund,
            );
          }
          expect(
            e.zutatenliste.contains(z.text),
            !z.ausgelassen,
            reason: '$grund\n${z.text}',
          );
        }
        // Zugesetztes Wasser bis 5 % fehlt in der Liste — ganz oder gar
        // nicht.
        final wasser = e.zeilen.where((z) => z.istWasser).toList();
        if (wasser.isNotEmpty) {
          final prozent =
              wasser.fold<double>(0, (s, z) => s + z.anteilProzent);
          for (final w in wasser) {
            expect(
              w.ausgelassen,
              prozent <= kWasserGrenzeProzent,
              reason: grund,
            );
          }
        }
        expect(
          e.zeilen.where((z) => z.ausgelassen && !z.istWasser),
          isEmpty,
          reason: grund,
        );
      });
    });

    test('Fleisch, Fett und Bindegewebe je Tierart', () {
      var mitFett = 0;
      var mitBindegewebe = 0;
      _jedeRezeptur((r, e, grund) {
        var fleisch = 0.0;
        for (final p in e.tierarten) {
          fleisch += p.fleischKg;
          expect(
            p.fleischKg + p.ueberschussFettKg + p.ueberschussBindegewebeKg,
            closeTo(p.masseKg, 1e-9 * math.max(1, p.masseKg)),
            reason: grund,
          );
          expect(p.ueberschussFettKg >= 0, isTrue, reason: grund);
          expect(p.ueberschussBindegewebeKg >= 0, isTrue, reason: grund);
          // Was als Fleisch bleibt, hält die Grenzwerte ein — genau auf
          // dem Grenzwert, wenn etwas abgezogen wurde.
          final kollagenKg = p.masseKg *
              p.eiweissProzent /
              100 *
              (p.kollagenVerhaeltnis ?? 0) /
              100;
          final kollagenWeg = p.ueberschussBindegewebeKg / 4.625;
          final eiweissKg = p.masseKg * p.eiweissProzent / 100;
          if (p.kollagenVerhaeltnis != null &&
              eiweissKg - kollagenWeg > 1e-9 &&
              p.fleischKg > 1e-9) {
            final verhaeltnis =
                (kollagenKg - kollagenWeg) / (eiweissKg - kollagenWeg) * 100;
            if (p.bindegewebeUeberGrenze) {
              mitBindegewebe++;
              expect(
                verhaeltnis,
                closeTo(p.tierart.bindegewebeGrenze, 1e-6),
                reason: grund,
              );
            } else {
              expect(
                verhaeltnis <= p.tierart.bindegewebeGrenze + 1e-6,
                isTrue,
                reason: grund,
              );
            }
          }
          final fettKg = p.masseKg * p.fettProzent / 100;
          final rest = p.masseKg - p.ueberschussBindegewebeKg -
              p.ueberschussFettKg;
          if (rest > 1e-9) {
            final fett = (fettKg - p.ueberschussFettKg) / rest * 100;
            if (p.fettUeberGrenze) {
              mitFett++;
              expect(
                fett,
                closeTo(p.tierart.fettGrenze, 1e-6),
                reason: grund,
              );
            } else {
              expect(
                fett <= p.tierart.fettGrenze + 1e-6,
                isTrue,
                reason: grund,
              );
            }
          }
          // Die Zeilen der Liste.
          final zeile =
              e.zeilen.singleWhere((z) => z.name == p.tierart.fleischName);
          expect(zeile.masseKg, closeTo(p.fleischKg, 1e-9), reason: grund);
          expect(zeile.quid, isTrue, reason: grund);
          expect(
            e.zeilen.any((z) => z.name == p.tierart.fettName),
            p.fettUeberGrenze,
            reason: grund,
          );
          expect(
            e.zeilen.any((z) => z.name == p.tierart.bindegewebeName),
            p.bindegewebeUeberGrenze,
            reason: grund,
          );
        }
        expect(
          e.fleischanteilProzent,
          closeTo(
            e.endgewichtKg > 0 ? fleisch / e.endgewichtKg * 100 : 0,
            1e-9,
          ),
          reason: grund,
        );
      });
      // Der Zufall soll beides auch wirklich treffen.
      expect(mitFett, greaterThan(20));
      expect(mitBindegewebe, greaterThan(20));
    });

    test('Nährwerte: was hineingeht, kommt heraus — abzüglich Verlust', () {
      var geprueft = 0;
      _jedeRezeptur((r, e, grund) {
        if (e.endgewichtKg <= 0) return;
        final n = e.je100g;
        final summe = n.fett! +
            n.eiweiss! +
            n.kohlenhydrate! +
            n.salz! +
            n.wasser! +
            n.asche!;
        // Reicht das Wasser für den Verlust, bleiben genau 100 g.
        if (e.warnungen.any((w) => w.contains('größer als'))) return;
        geprueft++;
        expect(summe, closeTo(100, 1e-6), reason: grund);
        expect(n.gesaettigteFettsaeuren! <= n.fett! + 1e-9, isTrue);
        expect(n.zucker! <= n.kohlenhydrate! + 1e-9, isTrue);
        if (n.beffe != null) {
          expect(n.beffe! <= n.eiweiss! + 1e-9, isTrue, reason: grund);
        }
        for (final w in [
          n.fett!,
          n.eiweiss!,
          n.kohlenhydrate!,
          n.salz!,
          n.wasser!,
          n.asche!,
        ]) {
          expect(w >= 0, isTrue, reason: grund);
        }
        expect(
          n.energieKj,
          closeTo(n.fett! * 37 + n.eiweiss! * 17 + n.kohlenhydrate! * 17, 1e-9),
        );
      });
      expect(geprueft, greaterThan(200));
    });

    test('eine Unterrezeptur rechnet wie eine Zutat mit ihren Nährwerten',
        () {
      var geprueft = 0;
      _jedeRezeptur((r, e, grund) {
        if (!r.positionen.any((p) => p.unterrezeptur != null)) return;
        // Eine Unterrezeptur ohne Endgewicht zählt zur Masse, aber ohne
        // Nährwerte.
        final flach = r.kopie(
          positionen: [
            for (final p in r.positionen)
              if (p.unterrezeptur case final u?)
                RechenPosition.zutat(
                  RechenZutat(
                    id: 'als-zutat-${u.id}',
                    name: u.name,
                    naehrwerte: berechne(u).endgewichtKg > 0
                        ? berechne(u).je100g
                        : Naehrwerte.leer,
                  ),
                  mengeKg: p.mengeKg,
                )
              else
                p,
          ],
        );
        final f = berechne(flach);
        if (f.endgewichtKg <= 0) return;
        geprueft++;
        for (final (a, b) in [
          (e.je100g.fett, f.je100g.fett),
          (e.je100g.gesaettigteFettsaeuren, f.je100g.gesaettigteFettsaeuren),
          (e.je100g.kohlenhydrate, f.je100g.kohlenhydrate),
          (e.je100g.zucker, f.je100g.zucker),
          (e.je100g.eiweiss, f.je100g.eiweiss),
          (e.je100g.salz, f.je100g.salz),
          (e.je100g.wasser, f.je100g.wasser),
          (e.je100g.asche, f.je100g.asche),
          (e.je100g.beffe, f.je100g.beffe),
        ]) {
          if (a == null || b == null) {
            expect(a, b, reason: grund);
          } else {
            expect(a, closeTo(b, 1e-9), reason: grund);
          }
        }
      });
      expect(geprueft, greaterThan(50));
    });

    test('Reihenfolge, Maßstab und geteilte Zeilen ändern nichts', () {
      final zufall = math.Random(7);
      _jedeRezeptur((r, e, grund) {
        if (e.endgewichtKg <= 0) return;
        void gleich(RezepturErgebnis b, String wie) {
          expect(b.zutatenliste, e.zutatenliste, reason: '$wie\n$grund');
          expect(
            b.fleischanteilProzent,
            closeTo(e.fleischanteilProzent, 1e-6),
            reason: '$wie\n$grund',
          );
          expect(
            b.je100g.fett!,
            closeTo(e.je100g.fett!, 1e-9),
            reason: '$wie\n$grund',
          );
          expect(
            b.je100g.eiweiss!,
            closeTo(e.je100g.eiweiss!, 1e-9),
            reason: '$wie\n$grund',
          );
          expect(
            b.je100g.salz!,
            closeTo(e.je100g.salz!, 1e-9),
            reason: '$wie\n$grund',
          );
          expect(b.allergene, e.allergene, reason: '$wie\n$grund');
        }

        // Andere Reihenfolge der Zeilen.
        final gemischt = [...r.positionen]..shuffle(zufall);
        gleich(berechne(r.kopie(positionen: gemischt)), 'gemischt');

        // Doppelte Charge.
        gleich(
          berechne(
            r.kopie(
              positionen: [
                for (final p in r.positionen) p.mitMenge(p.mengeKg * 2),
              ],
            ),
          ),
          'doppelt',
        );

        // Eine Zutat auf zwei Zeilen.
        final i = r.positionen.indexWhere((p) => p.zutat != null);
        if (i >= 0) {
          final p = r.positionen[i];
          gleich(
            berechne(
              r.kopie(
                positionen: [
                  ...r.positionen,
                  p.mitMenge(p.mengeKg * 0.3),
                ]..[i] = p.mitMenge(p.mengeKg * 0.7),
              ),
            ),
            'geteilt',
          );
        }

        // Als JSON gespeichert und wieder gelesen.
        gleich(
          berechne(
            RechenRezeptur.ausJson(
              jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>,
            ),
          ),
          'JSON',
        );
      });
    });

    test('Allergene aus allen Zutaten', () {
      _jedeRezeptur((r, e, grund) {
        final erwartet = <String>{};
        void sammeln(RechenRezeptur rr, double faktor) {
          for (final p in rr.positionen) {
            if (p.mengeKg <= 0 || faktor <= 0) continue;
            if (p.zutat case final z?) erwartet.addAll(z.allergene);
            if (p.unterrezeptur case final u?) {
              final end = _endgewicht(u);
              if (end > 0) sammeln(u, faktor * p.mengeKg / end);
            }
          }
        }

        sammeln(r, 1);
        expect(e.allergene.keys.toSet(), erwartet, reason: grund);
        // Jedes Allergen steht hervorgehoben in der Liste, oder es gibt
        // eine Warnung.
        for (final a in erwartet) {
          final wort = _allergenWort[a]!;
          expect(
            e.zutatenliste.contains(wort) ||
                e.warnungen.any((w) => w.startsWith('Allergen')),
            isTrue,
            reason: '$a\n$grund',
          );
        }
      });
    });
  });

  group('Fleischanteil einstellen', () {
    test('trifft jedes erreichbare Ziel, die Rohmasse bleibt', () {
      final zufall = math.Random(11);
      var getroffen = 0;
      for (var nr = 0; nr < 150; nr++) {
        final r = _flacheRezeptur(zufall, nr);
        final rollen = [for (final p in r.positionen) standardRolle(p)];
        if (!rollen.contains(OptimierRolle.ziel) ||
            !rollen.contains(OptimierRolle.ausgleich)) {
          continue;
        }
        for (final mass in FleischMass.values) {
          final ziel = 20 + zufall.nextDouble() * 80;
          final e = fleischanteilEinstellen(r, rollen, ziel, mass: mass);
          final grund = 'Nr. $nr, $mass, Ziel $ziel\n${_json(r)}';
          expect(
            _eingesetzt(e.rezeptur),
            closeTo(_eingesetzt(r), 1e-6),
            reason: grund,
          );
          for (var i = 0; i < rollen.length; i++) {
            final kg = e.rezeptur.positionen[i].mengeKg;
            expect(kg >= -1e-9, isTrue, reason: grund);
            if (rollen[i] == OptimierRolle.fest) {
              expect(kg, r.positionen[i].mengeKg, reason: grund);
            }
          }
          expect(
            fleischWert(e.rezeptur, mass),
            closeTo(e.erreichtProzent, 1e-6),
            reason: grund,
          );
          if (e.hinweis == null) {
            getroffen++;
            expect(e.erreicht, isTrue, reason: grund);
          } else {
            expect(e.erreicht, isFalse, reason: grund);
          }
        }
      }
      expect(getroffen, greaterThan(50));
    });
  });

  group('Rückrechnung', () {
    test('findet zu jedem Etikett eine Rezeptur in der Toleranz', () {
      // Auch mit Fett und Bindegewebe über dem Grenzwert und mit
      // Mengenangaben für das Fleisch, die dann weniger als die Rohmasse
      // meinen.
      final zufall = math.Random(13);
      var geprueft = 0;
      var mitAngabe = 0;
      for (var nr = 0; nr < 300; nr++) {
        final r = _flacheRezeptur(zufall, nr, ohneUeberschuss: nr.isEven);
        final e = berechne(r);
        // Fehlt das Wasser auf dem Etikett, weiß niemand, wie viel es war.
        if (e.endgewichtKg <= 0 || e.zeilen.any((z) => z.ausgelassen)) {
          continue;
        }
        if (e.warnungen.any((w) => w.contains('größer als'))) continue;
        // Die Zutaten in der Reihenfolge des Etiketts: Fleisch einer
        // Tierart hintereinander, die Mengenangabe beim ersten Stück.
        final quid = zufall.nextBool();
        final zutaten = <RueckZutat>[];
        final schon = <String>{};
        for (final zeile in e.zeilen) {
          var erstes = true;
          for (final p in r.positionen) {
            final z = p.zutat!;
            if (p.mengeKg <= 0 || schon.contains(z.id)) continue;
            final passt = zeile.istFleisch
                ? z.istFleisch && z.tierart?.fleischName == zeile.name
                : z.anzeigeName == zeile.name;
            if (!passt) continue;
            schon.add(z.id);
            zutaten.add(
              RueckZutat(
                z,
                quidProzent: quid && zeile.istFleisch && erstes
                    ? zeile.anteilProzent
                    : null,
              ),
            );
            erstes = false;
          }
        }
        final rueck = rueckrechnen(
          zutaten: zutaten,
          ziel: e.je100g,
          verlustart: r.verlustart,
          verlustProzent: r.verlustProzent,
          fettVerlustProzent: r.fettVerlustProzent,
        );
        final grund = 'Nr. $nr\n${_json(r)}\n${rueck.hinweise.join('\n')}';
        geprueft++;
        expect(
          rueck.mengenKg.fold<double>(0, (s, kg) => s + kg),
          closeTo(kRueckRohmasseKg, 1e-6),
          reason: grund,
        );
        expect(rueck.passt, isTrue, reason: grund);
        if (!quid) continue;
        for (final zeile in e.zeilen.where((z) => z.istFleisch)) {
          mitAngabe++;
          final nach = rueck.ergebnis.zeilen
              .singleWhere((z) => z.name == zeile.name);
          expect(
            nach.anteilProzent,
            closeTo(zeile.anteilProzent, 0.05),
            reason: grund,
          );
        }
      }
      expect(geprueft, greaterThan(120));
      expect(mitAngabe, greaterThan(80));
    });
  });
}

// ── Zufällige Rezepturen ──────────────────────────────────────────────

const _arten = [
  Tierart.schwein,
  Tierart.rind,
  Tierart.kalb,
  Tierart.lamm,
  Tierart.pute,
  Tierart.huhn,
];

/// Zutaten außer Fleisch — mit Nährwerten, die zusammen 100 g ergeben.
const _zutaten = [
  RechenZutat(
    id: 'salz',
    name: 'Speisesalz',
    etikettName: 'Salz',
    naehrwerte: Naehrwerte(salz: 100, wasser: 0),
  ),
  RechenZutat(
    id: 'zucker',
    name: 'Zucker',
    naehrwerte: Naehrwerte(kohlenhydrate: 100, zucker: 100, wasser: 0),
  ),
  RechenZutat(
    id: 'gewuerz',
    name: 'Gewürzmischung',
    etikettName: 'Gewürze',
    unterzutaten: 'Pfeffer, Paprika, SENFsaat',
    allergene: {'senf'},
    naehrwerte: Naehrwerte(
      fett: 5,
      gesaettigteFettsaeuren: 1,
      kohlenhydrate: 50,
      zucker: 5,
      eiweiss: 10,
      wasser: 10,
      asche: 25,
    ),
  ),
  RechenZutat(
    id: 'milch',
    name: 'Magermilchpulver',
    allergene: {'milch'},
    naehrwerte: Naehrwerte(
      fett: 1,
      kohlenhydrate: 52,
      zucker: 52,
      eiweiss: 35,
      salz: 1,
      wasser: 4,
      asche: 7,
    ),
  ),
  RechenZutat(
    id: 'mehl',
    name: 'Weizenmehl',
    allergene: {'gluten'},
    naehrwerte: Naehrwerte(
      fett: 1,
      kohlenhydrate: 72,
      zucker: 1,
      eiweiss: 11,
      wasser: 14,
      asche: 2,
    ),
  ),
  RechenZutat(
    id: 'zwiebeln',
    name: 'Zwiebeln',
    quidPflicht: true,
    naehrwerte: Naehrwerte(
      kohlenhydrate: 7,
      zucker: 5,
      eiweiss: 1,
      wasser: 91,
      asche: 1,
    ),
  ),
  RechenZutat(
    id: 'wasser',
    name: 'Trinkwasser',
    etikettName: 'Wasser',
    istWasser: true,
  ),
  RechenZutat(
    id: 'eis',
    name: 'Scherbeneis',
    etikettName: 'Wasser',
    istWasser: true,
  ),
];

const _allergenWort = {'senf': 'SENF', 'milch': 'MILCH', 'gluten': 'WEIZEN'};

bool _istWasser(String id) => id == 'wasser' || id == 'eis';

RechenZutat _fleisch(math.Random z, int nr, {bool ohneUeberschuss = false}) {
  final art = _arten[z.nextInt(_arten.length)];
  final eiweiss = 12 + z.nextDouble() * 10;
  final fett = ohneUeberschuss
      ? 2 + z.nextDouble() * (art.fettGrenze - 4)
      : 2 + z.nextDouble() * 50;
  const asche = 1.0;
  final mitBindegewebe = !ohneUeberschuss && z.nextBool();
  return RechenZutat(
    id: 'fleisch$nr',
    name: 'Fleisch $nr',
    istFleisch: true,
    tierart: art,
    bindegewebe: mitBindegewebe ? 3 + z.nextDouble() * 42 : null,
    quidPflicht: true,
    naehrwerte: Naehrwerte(
      fett: fett,
      gesaettigteFettsaeuren: fett * 0.4,
      kohlenhydrate: 0,
      zucker: 0,
      eiweiss: eiweiss,
      salz: 0.1,
      wasser: 100 - fett - eiweiss - asche - 0.1,
      asche: asche,
      beffe: z.nextBool() ? eiweiss * 0.85 : null,
    ),
  );
}

(Verlustart, double, double) _verlust(math.Random z) {
  final art = switch (z.nextInt(20)) {
    < 9 => Verlustart.trocknung,
    < 17 => Verlustart.garen,
    _ => Verlustart.keiner,
  };
  final verlust = z.nextInt(6) == 0 ? 0.0 : z.nextDouble() * 45;
  final fett = z.nextBool() ? 0.0 : z.nextDouble() * math.min(5, verlust);
  return (art, verlust, fett);
}

RechenRezeptur _rezeptur(math.Random z, String id, int tiefe) {
  final fleisch = <RechenZutat>[];
  final positionen = <RechenPosition>[];
  final anzahl = 1 + z.nextInt(tiefe == 0 ? 7 : 4);
  for (var i = 0; i < anzahl; i++) {
    final wurf = z.nextDouble();
    final menge = z.nextInt(30) == 0 ? 0.0 : 0.1 + z.nextDouble() * 60;
    final quid = z.nextInt(8) == 0 ? true : null;
    if (wurf < 0.45) {
      // Neues Fleisch oder eines, das schon da ist.
      final f = fleisch.isNotEmpty && z.nextInt(4) == 0
          ? fleisch[z.nextInt(fleisch.length)]
          : _fleisch(z, z.nextInt(1 << 20));
      fleisch.add(f);
      positionen.add(RechenPosition.zutat(f, mengeKg: menge));
    } else if (wurf < 0.88 || tiefe >= 2) {
      final zutat = _zutaten[z.nextInt(_zutaten.length)];
      positionen.add(
        RechenPosition.zutat(zutat, mengeKg: menge, quidPflicht: quid),
      );
    } else {
      final unter = _rezeptur(z, '$id.$i', tiefe + 1);
      positionen.add(
        RechenPosition.unterrezeptur(unter, mengeKg: menge / 4),
      );
    }
  }
  final (art, verlust, fett) = _verlust(z);
  return RechenRezeptur(
    id: id,
    name: 'Rezeptur $id',
    positionen: positionen,
    verlustProzent: verlust,
    fettVerlustProzent: fett,
    verlustart: art,
  );
}

/// Eine Rezeptur ohne Unterrezepturen, mit Fleisch und Wasser.
RechenRezeptur _flacheRezeptur(
  math.Random z,
  int nr, {
  bool ohneUeberschuss = false,
}) {
  final positionen = <RechenPosition>[
    for (var i = 0; i < 1 + z.nextInt(3); i++)
      RechenPosition.zutat(
        _fleisch(z, nr * 10 + i, ohneUeberschuss: ohneUeberschuss),
        mengeKg: 10 + z.nextDouble() * 50,
      ),
    RechenPosition.zutat(_zutaten[6], mengeKg: 2 + z.nextDouble() * 20),
    for (final i in [0, 1, 2, 3, 4, 5])
      if (z.nextInt(3) == 0)
        RechenPosition.zutat(_zutaten[i], mengeKg: 0.2 + z.nextDouble() * 4),
  ]..shuffle(z);
  final (art, verlust, fett) = _verlust(z);
  return RechenRezeptur(
    id: 'flach$nr',
    name: 'Flach $nr',
    positionen: positionen,
    verlustProzent: verlust,
    fettVerlustProzent: fett,
    verlustart: art,
  );
}

void _jedeRezeptur(
  void Function(RechenRezeptur r, RezepturErgebnis e, String grund) pruefe,
) {
  final zufall = math.Random(20261021);
  for (var nr = 0; nr < 400; nr++) {
    final r = _rezeptur(zufall, 'r$nr', 0);
    pruefe(r, berechne(r), 'Rezeptur Nr. $nr: ${_json(r)}');
  }
}

String _json(RechenRezeptur r) => jsonEncode(r.toJson());

// ── Nachgerechnet, unabhängig vom Rechenkern ──────────────────────────

double _eingesetzt(RechenRezeptur r) => r.positionen
    .fold<double>(0, (s, p) => s + (p.mengeKg > 0 ? p.mengeKg : 0));

double _verlustProzent(RechenRezeptur r) => r.verlustart == Verlustart.keiner
    ? 0
    : r.verlustProzent.clamp(0, 100).toDouble();

double _endgewicht(RechenRezeptur r) =>
    _eingesetzt(r) * (1 - _verlustProzent(r) / 100);

/// Rohmasse je Zutat: eine Unterrezeptur mit dem Anteil ihrer fertigen
/// Menge an ihrem Endgewicht (F13).
Map<String, double> _rohJeZutat(RechenRezeptur r) {
  final aus = <String, double>{};
  void dazu(String id, double kg) =>
      aus.update(id, (v) => v + kg, ifAbsent: () => kg);
  for (final p in r.positionen) {
    final kg = p.mengeKg > 0 ? p.mengeKg : 0.0;
    if (p.zutat case final z?) dazu(z.id, kg);
    if (p.unterrezeptur case final u?) {
      final end = _endgewicht(u);
      if (end <= 0) continue;
      for (final MapEntry(:key, :value) in _rohJeZutat(u).entries) {
        dazu(key, value * kg / end);
      }
    }
  }
  return aus;
}

/// Zugesetztes Wasser nach allen Verlusten: Jede Ebene verliert zuerst
/// Wasser.
double _wasserRest(RechenRezeptur r) {
  var wasser = 0.0;
  for (final p in r.positionen) {
    final kg = p.mengeKg > 0 ? p.mengeKg : 0.0;
    if (p.zutat case final z?) {
      if (z.istWasser) wasser += kg;
    }
    if (p.unterrezeptur case final u?) {
      final end = _endgewicht(u);
      if (end > 0) wasser += _wasserRest(u) * kg / end;
    }
  }
  final verlustKg = _eingesetzt(r) - _endgewicht(r);
  return wasser > verlustKg ? wasser - verlustKg : 0;
}
