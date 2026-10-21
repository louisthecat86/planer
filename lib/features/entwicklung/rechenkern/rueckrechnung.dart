import 'dart:math' as math;

import '../../../core/utils/format.dart';
import 'naehrwert_rundung.dart';
import 'rechen_modell.dart';
import 'rechenkern.dart';

// Rezeptur rückrechnen: Aus der Zutatenliste eines Etiketts (Reihenfolge,
// vielleicht einzelne Mengenangaben) und seiner Nährwerttabelle eine
// Rezeptur schätzen, die zu beidem passt.
//
// Die alte Suite hat dafür gewürfelt — zweimal gerechnet, zwei Ergebnisse.
// Hier nicht: Bei fester Rohmasse hängen die Nährwerte je 100 g linear von
// den Mengen ab (der Verlust zieht feste Mengen ab), und die Reihenfolge
// der Liste ist eine Kette von Ungleichungen. Nimmt man die Abstände
// zwischen benachbarten Zeilen als Unbekannte, wird daraus ein lineares
// Ausgleichsproblem mit nichtnegativen Unbekannten — gelöst nach Lawson
// und Hanson. Gleiche Eingabe, gleiches Ergebnis.
//
// Was die Rechnung nicht sieht, entscheidet eine schwache Führung zu einer
// Verteilung, die mit der Reihenfolge abnimmt. Am Ende rechnet der
// Rechenkern die geschätzte Rezeptur ganz normal nach.
//
// Fleisch mit Fett oder Bindegewebe über dem Grenzwert wiegt auf dem
// Etikett weniger als roh — der Überschuss steht als eigene Zeile da. Die
// Reihenfolge und eine Mengenangabe wie „Schweinefleisch (60 %)" meinen
// das Fleisch auf dem Etikett. Wie viel davon ein kg jedes Stücks bringt,
// liest die Rechnung in ein paar Runden am Rechenkern ab; zuletzt trifft
// sie die Mengenangabe genau.

/// Rohmasse der geschätzten Rezeptur — die Mengen sind kg je 100 kg.
const double kRueckRohmasseKg = 100;

/// Gewicht der Nährstoffe beim Ausgleich. Salz wiegt schwer, weil schon
/// Zehntelgramm auffallen; gesättigte Fettsäuren fehlen, weil der
/// Fettverlust sie nicht linear mindert.
const Map<Naehrstoff, double> kRueckGewichte = {
  Naehrstoff.fett: 1,
  Naehrstoff.kohlenhydrate: 1,
  Naehrstoff.zucker: 1,
  Naehrstoff.eiweiss: 2,
  Naehrstoff.salz: 10,
};

/// Wie stark die Gleichungen (Summe, feste Mengen) gegenüber den
/// Nährwerten zählen.
const double _gleichungGewicht = 1e4;

/// Wie stark die Führung zur abnehmenden Verteilung zählt.
const double _fuehrungGewicht = 0.05;

/// Um wie viel jede Zeile der Führung kleiner wird als die vorige.
const double _fuehrungFaktor = 0.6;

/// Eine Zutat der Liste, in der Reihenfolge des Etiketts.
class RueckZutat {
  const RueckZutat(this.zutat, {this.quidProzent});

  final RechenZutat zutat;

  /// Die Mengenangabe des Etiketts in % des Enderzeugnisses — dann ist die
  /// Zeile fest. Bei mehreren Stücken derselben Tierart gilt sie für die
  /// ganze Fleischzeile.
  final double? quidProzent;
}

/// Ein Nährstoff: Ziel aus dem Etikett, Wert der geschätzten Rezeptur.
class NaehrstoffVergleich {
  const NaehrstoffVergleich({
    required this.stoff,
    required this.ziel,
    required this.wert,
  });

  final Naehrstoff stoff;
  final double ziel;
  final double wert;

  double get abweichung => wert - ziel;

  /// Die erlaubte Abweichung für das Ziel in g je 100 g.
  double get toleranz => naehrwertToleranz(stoff, ziel);

  bool get passt => abweichung.abs() <= toleranz + 1e-9;
}

/// Das Ergebnis der Rückrechnung.
class RueckrechnungsErgebnis {
  const RueckrechnungsErgebnis({
    required this.mengenKg,
    required this.rezeptur,
    required this.ergebnis,
    required this.vergleich,
    required this.hinweise,
  });

  /// kg je 100 kg Rohmasse, in der Reihenfolge der Eingabe.
  final List<double> mengenKg;

  /// Die geschätzte Rezeptur — wie eine gespeicherte nachgerechnet.
  final RechenRezeptur rezeptur;
  final RezepturErgebnis ergebnis;
  final List<NaehrstoffVergleich> vergleich;
  final List<String> hinweise;

  /// Alle Ziele innerhalb der Toleranz.
  bool get passt => vergleich.every((v) => v.passt);
}

/// Die Toleranz für eine Nährwertangabe [wert] in g je 100 g — nach dem
/// Leitfaden der EU-Kommission (Dezember 2012) für Lebensmittel.
double naehrwertToleranz(Naehrstoff stoff, double wert) {
  final w = wert.abs();
  switch (stoff) {
    case Naehrstoff.energieKj:
    case Naehrstoff.energieKcal:
      // Für die Energie nennt der Leitfaden keine eigene Toleranz.
      return w * 0.2;
    case Naehrstoff.fett:
      if (w < 10) return 1.5;
      return w <= 40 ? w * 0.2 : 8;
    case Naehrstoff.gesaettigteFettsaeuren:
      return w < 4 ? 0.8 : w * 0.2;
    case Naehrstoff.kohlenhydrate:
    case Naehrstoff.zucker:
    case Naehrstoff.eiweiss:
      if (w < 10) return 2;
      return w <= 40 ? w * 0.2 : 8;
    case Naehrstoff.salz:
      return w < 1.25 ? 0.375 : w * 0.2;
  }
}

Tierart? _tierart(RechenZutat z) =>
    z.istFleisch ? (z.tierart ?? Tierart.aus(z.name)) : null;

/// Der Wert eines Nährstoffs je 100 g einer Zutat, wie der Rechenkern ihn
/// zählt: Zugesetztes Wasser bringt nur Wasser mit.
double _gehalt(RechenZutat z, Naehrstoff s) =>
    z.istWasser ? 0 : naehrstoffWert(z.naehrwerte, s) ?? 0;

/// Schätzt eine Rezeptur für [zutaten] (in der Reihenfolge des Etiketts),
/// deren Nährwerte je 100 g möglichst nah an [ziel] liegen. Nur die
/// gesetzten Werte von [ziel] zählen. Mit [reihenfolge] bleiben die
/// Zeilen absteigend, wie die Liste es verlangt.
///
/// Wirft [ArgumentError], wenn keine Zutaten da sind oder die festen
/// Mengenangaben mehr als die ganze Rohmasse verlangen.
RueckrechnungsErgebnis rueckrechnen({
  required List<RueckZutat> zutaten,
  required Naehrwerte ziel,
  Verlustart verlustart = Verlustart.keiner,
  double verlustProzent = 0,
  double fettVerlustProzent = 0,
  bool reihenfolge = true,
}) {
  if (zutaten.isEmpty) {
    throw ArgumentError('Für die Rückrechnung fehlen die Zutaten.');
  }
  const roh = kRueckRohmasseKg;
  final verlust = verlustart == Verlustart.keiner
      ? 0.0
      : verlustProzent.clamp(0, 95).toDouble();
  final endKg = roh * (1 - verlust / 100);
  final verlustKg = roh - endKg;
  final fettKg = verlustKg <= 0
      ? 0.0
      : math.min(roh * fettVerlustProzent.clamp(0, 100) / 100, verlustKg);
  final saftKg = verlustKg - fettKg;

  // ── Die Zeilen der Liste ────────────────────────────────────────────
  // Fleisch derselben Tierart hintereinander steht als eine Zeile da.
  final zeilen = <List<int>>[];
  for (var i = 0; i < zutaten.length; i++) {
    final art = _tierart(zutaten[i].zutat);
    if (art != null && zeilen.isNotEmpty) {
      final vorige = _tierart(zutaten[zeilen.last.last].zutat);
      if (vorige == art) {
        zeilen.last.add(i);
        continue;
      }
    }
    zeilen.add([i]);
  }
  final zeileVon = <int, int>{
    for (var j = 0; j < zeilen.length; j++)
      for (final i in zeilen[j]) i: j,
  };
  // Zugesetztes Wasser steht mit dem, was nach dem Verlust bleibt — der
  // Verlust geht zuerst zulasten des Wassers.
  final wasserZeile = verlustKg <= 0
      ? -1
      : zeilen.indexWhere(
          (z) => z.length == 1 && zutaten[z.single].zutat.istWasser,
        );
  double versatz(int j) => j == wasserZeile ? verlustKg : 0;

  // Feste Zeilen: Etikettmasse aus der Mengenangabe.
  final fest = <int, double>{};
  for (var j = 0; j < zeilen.length; j++) {
    for (final i in zeilen[j]) {
      final q = zutaten[i].quidProzent;
      if (q != null && q > 0) {
        fest[j] = q * endKg / 100;
        break;
      }
    }
  }
  // Auf dem Etikett wiegt nichts mehr als roh — mehr als die Rohmasse
  // können die festen Zeilen also nie verlangen.
  final festEtikett = fest.entries
      .fold<double>(0, (s, e) => s + e.value + versatz(e.key));
  if (festEtikett > roh + 1e-6) {
    throw ArgumentError(
      'Die festen Mengenangaben verlangen zusammen mehr als die ganze '
      'Rohmasse.',
    );
  }
  final nZeilen = zeilen.length;

  /// Der Name der Fleischzeile im Ergebnis, wenn Zeile [j] Fleisch einer
  /// Tierart ist, die in keiner anderen Zeile steht.
  String? fleischName(int j) {
    final art = _tierart(zutaten[zeilen[j].first].zutat);
    if (art == null) return null;
    for (var k = 0; k < nZeilen; k++) {
      if (k != j && _tierart(zutaten[zeilen[k].first].zutat) == art) {
        return null;
      }
    }
    return art.fleischName;
  }

  double? fleischKgIn(RezepturErgebnis e, String name) {
    for (final z in e.zeilen) {
      if (z.istFleisch && z.name == name) return z.masseKg;
    }
    return null;
  }

  // Fett und Bindegewebe über dem Grenzwert stehen als eigene Zeilen da —
  // Fleisch wiegt auf dem Etikett weniger als roh. Je Stück ein Faktor:
  // so viel Fleisch auf dem Etikett bringt ein kg mehr davon. Ein mageres
  // Stück kann mehr als 1 bringen, weil es den Überschuss der anderen
  // senkt. Der Rechenkern liefert die Faktoren an der jeweiligen Mischung.
  final faktor = List<double>.filled(zutaten.length, 1);

  /// Fleisch auf dem Etikett aus den Stücken von Zeile [j] mit [kg].
  double fleischAus(int j, List<double> kg) {
    final r = RechenRezeptur(
      id: 'stuecke',
      name: 'Stücke',
      positionen: [
        for (var k = 0; k < zeilen[j].length; k++)
          RechenPosition.zutat(zutaten[zeilen[j][k]].zutat, mengeKg: kg[k]),
      ],
      verlustart: Verlustart.keiner,
    );
    return fleischKgIn(berechne(r), fleischName(j)!) ?? 0;
  }

  /// Die Faktoren an der Mischung [mengen] — bei leeren Zeilen an gleichen
  /// Teilen. Gibt zurück, ob sich einer geändert hat.
  bool faktorenAn(List<double>? mengen) {
    var anders = false;
    for (var j = 0; j < nZeilen; j++) {
      if (fleischName(j) == null) continue;
      final stuecke = zeilen[j];
      var kg = [for (final i in stuecke) mengen?[i] ?? 0.0];
      var summe = kg.fold<double>(0, (s, x) => s + x);
      if (summe <= 1e-9) {
        kg = List<double>.filled(stuecke.length, 1);
        summe = stuecke.length.toDouble();
      }
      final f0 = fleischAus(j, kg);
      final neu = <double>[];
      if (stuecke.length == 1) {
        // Ein Stück: Fleisch je kg roh — mindestens ein wenig, sonst
        // wüchse die Rohmasse ins Unendliche.
        neu.add(math.max(0.01, f0 / kg.single));
      } else {
        final d = 1e-6 * summe;
        for (var k = 0; k < stuecke.length; k++) {
          final mehr = [...kg]..[k] += d;
          neu.add((fleischAus(j, mehr) - f0) / d);
        }
      }
      for (var k = 0; k < stuecke.length; k++) {
        if ((neu[k] - faktor[stuecke[k]]).abs() > 1e-9) {
          faktor[stuecke[k]] = neu[k];
          anders = true;
        }
      }
    }
    return anders;
  }

  // ── Unbekannte ──────────────────────────────────────────────────────
  // Je Zeile eine: mit [reihenfolge] der Abstand zur nächsten Zeile (die
  // Masse einer Zeile auf dem Etikett ist dann die Summe ab ihr), sonst
  // die Masse selbst. Dazu je Stück einer Fleischzeile mit mehreren
  // Stücken eins — seine Rohmasse.
  var nVar = nZeilen;
  final stueck = <int, int>{};
  for (final z in zeilen) {
    if (z.length < 2) continue;
    for (final i in z) {
      stueck[i] = nVar++;
    }
  }

  /// Die Masse einer Zeile auf dem Etikett.
  List<double> masseZeile(int j) {
    final c = List<double>.filled(nVar, 0);
    if (reihenfolge) {
      for (var l = j; l < nZeilen; l++) {
        c[l] = 1;
      }
    } else {
      c[j] = 1;
    }
    return c;
  }

  /// Die Rohmasse einer Zutat: Koeffizienten und fester Teil.
  (List<double>, double) rohmasse(int i) {
    final v = stueck[i];
    if (v != null) {
      final c = List<double>.filled(nVar, 0)..[v] = 1;
      return (c, 0.0);
    }
    final j = zeileVon[i]!;
    return (
      [for (final c in masseZeile(j)) c / faktor[i]],
      versatz(j),
    );
  }

  final mitZiel =
      kRueckGewichte.keys.any((s) => naehrstoffWert(ziel, s) != null);

  /// Schätzt die Mengen je Zutat mit den aktuellen Faktoren.
  List<double> loese() {
    final matrix = <List<double>>[];
    final rechts = <double>[];
    void gleichung(List<double> c, double wert, double gewicht) {
      matrix.add([for (final v in c) v * gewicht]);
      rechts.add(wert * gewicht);
    }

    // 1. Die Nährwerte je 100 g.
    for (final MapEntry(key: stoff, value: gewicht)
        in kRueckGewichte.entries) {
      final t = naehrstoffWert(ziel, stoff);
      if (t == null) continue;
      final c = List<double>.filled(nVar, 0);
      var fix = 0.0;
      for (var i = 0; i < zutaten.length; i++) {
        final n = _gehalt(zutaten[i].zutat, stoff);
        if (n == 0) continue;
        final (ci, ki) = rohmasse(i);
        for (var v = 0; v < nVar; v++) {
          c[v] += ci[v] * n / endKg;
        }
        fix += ki * n / endKg;
      }
      final verlorenKg = switch (stoff) {
        Naehrstoff.fett => fettKg,
        Naehrstoff.eiweiss when verlustart == Verlustart.garen =>
          saftKg * kSaftEiweiss,
        Naehrstoff.salz when verlustart == Verlustart.garen =>
          saftKg * kSaftSalz,
        Naehrstoff.zucker || Naehrstoff.kohlenhydrate
            when verlustart == Verlustart.garen =>
          saftKg * kSaftZucker,
        _ => 0.0,
      };
      gleichung(c, t - fix + 100 * verlorenKg / endKg, gewicht);
    }

    // 2. Die Gleichungen: Summe der Rohmassen, feste Zeilen, Stücke einer
    //    Fleischzeile (ihr Fleisch ergibt die Masse der Zeile).
    {
      final c = List<double>.filled(nVar, 0);
      var fix = 0.0;
      for (var i = 0; i < zutaten.length; i++) {
        final (ci, ki) = rohmasse(i);
        for (var v = 0; v < nVar; v++) {
          c[v] += ci[v];
        }
        fix += ki;
      }
      gleichung(c, roh - fix, _gleichungGewicht);
    }
    for (final MapEntry(key: j, value: kg) in fest.entries) {
      gleichung(masseZeile(j), kg, _gleichungGewicht);
    }
    for (var j = 0; j < nZeilen; j++) {
      if (zeilen[j].length < 2) continue;
      final c = [for (final v in masseZeile(j)) -v];
      for (final i in zeilen[j]) {
        c[stueck[i]!] += faktor[i];
      }
      gleichung(c, 0, _gleichungGewicht);
    }

    // 3. Die schwache Führung: abnehmend mit der Reihenfolge.
    final frei = [
      for (var j = 0; j < nZeilen; j++)
        if (!fest.containsKey(j)) j,
    ];
    final gewichte = {
      for (final j in frei) j: math.pow(_fuehrungFaktor, j).toDouble(),
    };
    final gewichtSumme = gewichte.values.fold<double>(0, (s, g) => s + g);
    final freiKg = math.max(
      0.0,
      roh -
          festEtikett -
          (wasserZeile >= 0 && !fest.containsKey(wasserZeile)
              ? verlustKg
              : 0),
    );
    for (var i = 0; i < zutaten.length; i++) {
      final j = zeileVon[i]!;
      final zeileKg = fest[j] ??
          (gewichtSumme > 0 ? gewichte[j]! / gewichtSumme * freiKg : 0.0);
      final vorschlag = zeileKg / zeilen[j].length + versatz(j);
      final (ci, ki) = rohmasse(i);
      gleichung(ci, vorschlag - ki, _fuehrungGewicht);
    }

    // ── Lösen ─────────────────────────────────────────────────────────
    final x = nnls(matrix, rechts);
    final mengen = <double>[];
    for (var i = 0; i < zutaten.length; i++) {
      final (ci, ki) = rohmasse(i);
      var w = ki;
      for (var v = 0; v < nVar; v++) {
        w += ci[v] * x[v];
      }
      mengen.add(w > 0 ? w : 0.0);
    }
    // Die festen Zeilen genau auf ihre Angabe, die übrigen auf den Rest.
    final festRohKg = <int, double>{};
    for (final MapEntry(key: j, value: sollKg) in fest.entries) {
      final rohKg = zeilen[j].fold<double>(0, (s, i) => s + mengen[i]);
      final etikettKg = zeilen[j]
              .fold<double>(0, (s, i) => s + mengen[i] * faktor[i]) -
          versatz(j);
      festRohKg[j] = etikettKg > 1e-9
          ? (rohKg - versatz(j)) * sollKg / etikettKg + versatz(j)
          : sollKg + versatz(j);
    }
    _aufRohmasse(mengen, zeilen, festRohKg);
    return mengen;
  }

  RechenRezeptur rezepturAus(List<double> mengen) => RechenRezeptur(
        id: 'rueckrechnung',
        name: 'Rückrechnung',
        positionen: [
          for (var i = 0; i < zutaten.length; i++)
            RechenPosition.zutat(
              zutaten[i].zutat,
              mengeKg: mengen[i],
              quidPflicht: zutaten[i].quidProzent != null ? true : null,
            ),
        ],
        verlustProzent: verlust,
        fettVerlustProzent: verlustKg <= 0 ? 0 : fettVerlustProzent,
        verlustart: verlustart,
      );

  /// Eine feste Fleischzeile behält ihre Mischung und wird so groß, dass
  /// ihr Fleisch die Mengenangabe trifft. null, wenn das mehr Rohmasse
  /// verlangt, als da ist.
  List<double>? quidGenau(List<double> mengen, RezepturErgebnis e) {
    final festRohKg = <int, double>{};
    var korrigiert = false;
    for (final MapEntry(key: j, value: sollKg) in fest.entries) {
      final rohKg = zeilen[j].fold<double>(0, (s, i) => s + mengen[i]);
      festRohKg[j] = rohKg;
      final name = fleischName(j);
      final istKg = name == null ? null : fleischKgIn(e, name);
      if (istKg == null || istKg <= 1e-9) continue;
      if ((istKg - sollKg).abs() <= 1e-9 * roh) continue;
      festRohKg[j] = rohKg * sollKg / istKg;
      korrigiert = true;
    }
    if (!korrigiert) return mengen;
    if (festRohKg.values.fold<double>(0, (s, kg) => s + kg) > roh + 1e-6) {
      return null;
    }
    final neu = [...mengen];
    _aufRohmasse(neu, zeilen, festRohKg);
    return neu;
  }

  /// Wie weit die Nährwerte von [e] vom Ziel liegen — gewichtet wie beim
  /// Ausgleich.
  double abstand(RezepturErgebnis e) {
    var summe = 0.0;
    for (final MapEntry(key: stoff, value: gewicht)
        in kRueckGewichte.entries) {
      final t = naehrstoffWert(ziel, stoff);
      if (t == null) continue;
      final d = (naehrstoffWert(e.je100g, stoff) ?? 0) - t;
      summe += gewicht * gewicht * d * d;
    }
    return summe;
  }

  // Ein paar Runden: lösen, die Faktoren an der neuen Mischung ablesen,
  // wieder lösen. Es gilt die Runde, die nach dem genauen Treffen der
  // Mengenangaben am besten zum Etikett passt.
  faktorenAn(null);
  var mengen = loese();
  var ergebnis = berechne(rezepturAus(mengen));
  ({List<double> mengen, RezepturErgebnis ergebnis})? bestes;
  var bestesAbstand = double.infinity;
  for (var runde = 0; runde < 6; runde++) {
    final genau = quidGenau(mengen, ergebnis);
    if (genau != null) {
      final e = identical(genau, mengen)
          ? ergebnis
          : berechne(rezepturAus(genau));
      final a = abstand(e);
      if (a < bestesAbstand - 1e-12) {
        bestesAbstand = a;
        bestes = (mengen: genau, ergebnis: e);
      }
    }
    if (!faktorenAn(mengen)) break;
    mengen = loese();
    ergebnis = berechne(rezepturAus(mengen));
  }
  if (bestes != null) {
    mengen = bestes.mengen;
    ergebnis = bestes.ergebnis;
  }
  final rezeptur = rezepturAus(mengen);

  final vergleich = [
    for (final s in Naehrstoff.values)
      if (s != Naehrstoff.energieKj && s != Naehrstoff.energieKcal)
        if (naehrstoffWert(ziel, s) case final t?)
          NaehrstoffVergleich(
            stoff: s,
            ziel: t,
            wert: naehrstoffWert(ergebnis.je100g, s) ?? 0,
          ),
  ];

  // Mengenangaben für Fleisch, die der Rechenkern nicht bestätigt.
  final abweichend = <String>[];
  for (final MapEntry(key: j, value: sollKg) in fest.entries) {
    final name = fleischName(j);
    if (name == null) continue;
    final istKg = fleischKgIn(ergebnis, name) ?? 0;
    if ((istKg - sollKg).abs() / endKg * 100 < 0.05) continue;
    abweichend.add(
      '$name: auf dem Etikett ${_p(sollKg / endKg * 100)}, nachgerechnet '
      '${_p(istKg / endKg * 100)} — Fett oder Bindegewebe über dem '
      'Grenzwert zählen nicht als Fleisch; mehr passt nicht in die '
      'Rohmasse.',
    );
  }

  final hinweise = <String>[
    if (!mitZiel)
      'Ohne Nährwerte ist die Rezeptur nur aus der Reihenfolge geschätzt.',
    if (ergebnis.ohneNaehrwerte.isNotEmpty)
      'Ohne Nährwerte im Katalog — zählen als 0: '
          '${ergebnis.ohneNaehrwerte.join(', ')}.',
    for (final v in vergleich)
      if (!v.passt)
        '${v.stoff.label}: ${_g(v.abweichung.abs())} '
            '${v.abweichung > 0 ? 'zu viel' : 'zu wenig'} — mit diesen '
            'Zutaten nicht genauer zu treffen. Fehlt eine Zutat, oder passt '
            'eine Zutat aus dem Katalog nicht zum Original?',
    ...abweichend,
    if (reihenfolge && !_absteigend(fest))
      'Die festen Mengenangaben widersprechen der Reihenfolge der Liste.',
    for (final w in ergebnis.warnungen)
      if (!w.startsWith('Allergen')) w,
  ];

  return RueckrechnungsErgebnis(
    mengenKg: mengen,
    rezeptur: rezeptur,
    ergebnis: ergebnis,
    vergleich: vergleich,
    hinweise: hinweise,
  );
}

String _p(double prozent) => '${Format.zahl(prozent, nachkomma: 1)} %';

String _g(double wert) =>
    '${Format.zahl(wert, nachkomma: wert < 1 ? 2 : 1)} g';

/// Sind die festen Zeilen untereinander absteigend?
bool _absteigend(Map<int, double> fest) {
  final schluessel = fest.keys.toList()..sort();
  for (var k = 1; k < schluessel.length; k++) {
    if (fest[schluessel[k]]! > fest[schluessel[k - 1]]! + 1e-6) return false;
  }
  return true;
}

/// Bringt die Mengen genau auf [kRueckRohmasseKg]: Feste Zeilen stehen
/// genau auf ihrer Rohmasse [festRohKg], die übrigen werden gemeinsam
/// skaliert.
void _aufRohmasse(
  List<double> mengen,
  List<List<int>> zeilen,
  Map<int, double> festRohKg,
) {
  var festKg = 0.0;
  var freiKg = 0.0;
  for (var j = 0; j < zeilen.length; j++) {
    final soll = festRohKg[j];
    if (soll == null) {
      for (final i in zeilen[j]) {
        freiKg += mengen[i];
      }
      continue;
    }
    final ist = zeilen[j].fold<double>(0, (s, i) => s + mengen[i]);
    for (final i in zeilen[j]) {
      mengen[i] = ist > 0 ? mengen[i] * soll / ist : soll / zeilen[j].length;
    }
    festKg += soll;
  }
  final rest = kRueckRohmasseKg - festKg;
  if (freiKg <= 0 || rest <= 0) return;
  final faktor = rest / freiKg;
  for (var j = 0; j < zeilen.length; j++) {
    if (festRohKg.containsKey(j)) continue;
    for (final i in zeilen[j]) {
      mengen[i] *= faktor;
    }
  }
}

// ── Nichtnegative kleinste Quadrate ───────────────────────────────────

/// Das x ≥ 0 mit dem kleinsten |A·x − b| — nach Lawson und Hanson
/// („Solving Least Squares Problems", 1974, Kapitel 23). [a] hat eine
/// Zeile je Gleichung, alle gleich lang.
List<double> nnls(List<List<double>> a, List<double> b) {
  final m = a.length;
  if (m == 0) return const [];
  final n = a.first.length;
  final x = List<double>.filled(n, 0);
  if (n == 0) return x;

  // Was als „größer null" gilt, hängt von der Größe der Zahlen ab.
  var norm1 = 0.0;
  for (var j = 0; j < n; j++) {
    var s = 0.0;
    for (var i = 0; i < m; i++) {
      s += a[i][j].abs();
    }
    norm1 = math.max(norm1, s);
  }
  final tol = 10 * 2.220446049250313e-16 * norm1 * math.max(m, n);

  List<double> gradient() {
    final r = [
      for (var i = 0; i < m; i++) b[i] - _skalar(a[i], x),
    ];
    return [
      for (var j = 0; j < n; j++) _spalteMal(a, j, r),
    ];
  }

  final passiv = <int>[];
  final gesperrt = <int>{};
  for (var runde = 0; runde < 3 * n + 10; runde++) {
    final w = gradient();
    var neu = -1;
    var groesster = tol;
    for (var j = 0; j < n; j++) {
      if (passiv.contains(j) || gesperrt.contains(j)) continue;
      if (w[j] > groesster) {
        groesster = w[j];
        neu = j;
      }
    }
    if (neu < 0) break;
    passiv.add(neu);
    var erster = true;
    for (var innen = 0; innen < n + 5; innen++) {
      final z = _kleinsteQuadrate(a, b, passiv);
      // Wird die neue Unbekannte selbst nicht positiv, bringt sie nichts —
      // sie bleibt draußen, bis sich x wieder ändert.
      if (erster && z.last <= 0) {
        passiv.removeLast();
        gesperrt.add(neu);
        break;
      }
      erster = false;
      if (z.every((v) => v > 0)) {
        for (var k = 0; k < passiv.length; k++) {
          x[passiv[k]] = z[k];
        }
        gesperrt.clear();
        break;
      }
      var alpha = 1.0;
      for (var k = 0; k < passiv.length; k++) {
        if (z[k] > 0) continue;
        final j = passiv[k];
        final schritt = x[j] / (x[j] - z[k]);
        if (schritt < alpha) alpha = schritt;
      }
      for (var k = 0; k < passiv.length; k++) {
        final j = passiv[k];
        x[j] += alpha * (z[k] - x[j]);
      }
      passiv.removeWhere((j) {
        if (x[j] > 1e-12) return false;
        x[j] = 0;
        return true;
      });
      if (passiv.isEmpty) break;
    }
  }
  return x;
}

double _skalar(List<double> zeile, List<double> x) {
  var s = 0.0;
  for (var j = 0; j < x.length; j++) {
    s += zeile[j] * x[j];
  }
  return s;
}

double _spalteMal(List<List<double>> a, int j, List<double> r) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i][j] * r[i];
  }
  return s;
}

/// Kleinste Quadrate nur mit den [spalten] von [a] — über eine
/// QR-Zerlegung mit Householder-Spiegelungen. Spalten ohne eigenen Beitrag
/// bekommen 0.
List<double> _kleinsteQuadrate(
  List<List<double>> a,
  List<double> b,
  List<int> spalten,
) {
  final m = a.length;
  final k = spalten.length;
  if (k == 0) return const [];
  final q = [
    for (var i = 0; i < m; i++) [for (final j in spalten) a[i][j]],
  ];
  final y = [...b];
  final stufen = math.min(k, m);
  for (var c = 0; c < stufen; c++) {
    var norm = 0.0;
    for (var i = c; i < m; i++) {
      norm += q[i][c] * q[i][c];
    }
    norm = math.sqrt(norm);
    if (norm == 0) continue;
    final alpha = q[c][c] > 0 ? -norm : norm;
    final v = List<double>.filled(m, 0);
    for (var i = c; i < m; i++) {
      v[i] = q[i][c];
    }
    v[c] -= alpha;
    var vv = 0.0;
    for (var i = c; i < m; i++) {
      vv += v[i] * v[i];
    }
    if (vv == 0) continue;
    for (var j = c; j < k; j++) {
      var s = 0.0;
      for (var i = c; i < m; i++) {
        s += v[i] * q[i][j];
      }
      final f = 2 * s / vv;
      for (var i = c; i < m; i++) {
        q[i][j] -= f * v[i];
      }
    }
    var s = 0.0;
    for (var i = c; i < m; i++) {
      s += v[i] * y[i];
    }
    final f = 2 * s / vv;
    for (var i = c; i < m; i++) {
      y[i] -= f * v[i];
    }
  }
  var groesste = 0.0;
  for (var c = 0; c < stufen; c++) {
    groesste = math.max(groesste, q[c][c].abs());
  }
  final z = List<double>.filled(k, 0);
  for (var c = stufen - 1; c >= 0; c--) {
    var s = y[c];
    for (var j = c + 1; j < k; j++) {
      s -= q[c][j] * z[j];
    }
    final d = q[c][c];
    z[c] = d.abs() <= 1e-13 * groesste ? 0 : s / d;
  }
  return z;
}
