import '../../../core/utils/format.dart';
import 'rechen_modell.dart';
import 'rechenkern.dart';

// Den Fleischanteil einer Rezeptur auf einen Zielwert bringen: Die Zeilen
// mit der Rolle „Fleisch" werden gemeinsam größer oder kleiner, die mit
// „Ausgleich" (Wasser, Eis) gleichen aus, alles andere bleibt. Die
// Rohmasse der Charge bleibt dabei gleich.
//
// Wie in der alten Suite, aber gezielt: Statt eines Schätzwerts sucht die
// Rechnung den Faktor, bei dem der Rechenkern genau den Zielwert ausgibt —
// beim Fleischanteil laut Etikett mit den Grenzwerten für Fett und
// Bindegewebe.

/// Was eine Zeile beim Einstellen tut.
enum OptimierRolle {
  ziel('Fleisch'),
  ausgleich('Ausgleich'),
  fest('fest');

  const OptimierRolle(this.label);

  final String label;
}

/// Welcher Anteil eingestellt wird.
enum FleischMass {
  /// Der Fleischanteil laut Etikett: nach LMIV, bezogen auf das
  /// Endgewicht.
  etikett('Fleischanteil laut Etikett'),

  /// Fleisch im Rohgemisch: Fleischzutaten durch die Rohmasse.
  roh('Fleisch im Rohgemisch');

  const FleischMass(this.label);

  final String label;
}

/// Die Rolle, die eine Zeile von sich aus bekommt: Fleisch wird
/// eingestellt, Wasser und Eis gleichen aus, alles andere bleibt.
OptimierRolle standardRolle(RechenPosition p) {
  final z = p.zutat;
  if (z == null) return OptimierRolle.fest;
  if (z.istFleisch) return OptimierRolle.ziel;
  if (z.istWasser) return OptimierRolle.ausgleich;
  final name = z.name.toLowerCase();
  if (RegExp(r'(^|[\s(,-])(eis|scherbeneis|wasser|schüttung)($|[\s),-])')
      .hasMatch(name)) {
    return OptimierRolle.ausgleich;
  }
  return OptimierRolle.fest;
}

/// Der Anteil nach [mass] in Prozent.
double fleischWert(RechenRezeptur r, FleischMass mass) {
  switch (mass) {
    case FleischMass.etikett:
      return berechne(r).fleischanteilProzent;
    case FleischMass.roh:
      var summe = 0.0;
      var fleisch = 0.0;
      for (final p in r.positionen) {
        final kg = p.mengeKg > 0 ? p.mengeKg : 0.0;
        summe += kg;
        if (p.zutat?.istFleisch ?? false) fleisch += kg;
      }
      return summe > 0 ? fleisch / summe * 100 : 0;
  }
}

/// Das Ergebnis des Einstellens.
class FleischEinstellung {
  const FleischEinstellung({
    required this.rezeptur,
    required this.vorherProzent,
    required this.erreichtProzent,
    required this.zielProzent,
    this.hinweis,
  });

  /// Die Rezeptur mit den neuen Mengen — Reihenfolge wie vorher.
  final RechenRezeptur rezeptur;
  final double vorherProzent;
  final double erreichtProzent;
  final double zielProzent;

  /// Warum das Ziel nicht (genau) erreicht wurde — null, wenn es passt.
  final String? hinweis;

  /// Ziel auf eine Hundertstel Prozentpunkt getroffen.
  bool get erreicht => (erreichtProzent - zielProzent).abs() < 0.01;

  List<double> get mengenKg => [for (final p in rezeptur.positionen) p.mengeKg];
}

/// Bringt den Anteil nach [mass] von [r] auf [zielProzent]. [rollen] hat
/// je Zeile von [r] eine Rolle. Wirft [ArgumentError], wenn die Zahl der
/// Rollen nicht passt.
FleischEinstellung fleischanteilEinstellen(
  RechenRezeptur r,
  List<OptimierRolle> rollen,
  double zielProzent, {
  FleischMass mass = FleischMass.etikett,
}) {
  if (rollen.length != r.positionen.length) {
    throw ArgumentError('Je Zeile der Rezeptur eine Rolle.');
  }
  final vorher = fleischWert(r, mass);
  double menge(int i) {
    final kg = r.positionen[i].mengeKg;
    return kg > 0 ? kg : 0;
  }

  var zielKg = 0.0;
  var ausgleichKg = 0.0;
  for (var i = 0; i < rollen.length; i++) {
    if (rollen[i] == OptimierRolle.ziel) zielKg += menge(i);
    if (rollen[i] == OptimierRolle.ausgleich) ausgleichKg += menge(i);
  }

  FleischEinstellung ergebnis(RechenRezeptur neu, double erreicht, [
    String? hinweis,
  ]) =>
      FleischEinstellung(
        rezeptur: neu,
        vorherProzent: vorher,
        erreichtProzent: erreicht,
        zielProzent: zielProzent,
        hinweis: hinweis,
      );

  if (zielKg <= 0) {
    return ergebnis(
      r,
      vorher,
      'Keine Zeile mit der Rolle „Fleisch" und Menge — es gibt nichts '
      'einzustellen.',
    );
  }
  if (ausgleichKg <= 0) {
    return ergebnis(
      r,
      vorher,
      'Keine Zeile zum Ausgleichen (etwa Wasser oder Eis) — die Rohmasse '
      'bliebe nicht gleich.',
    );
  }

  /// Die Rezeptur, wenn das Fleisch mit [faktor] wächst und der Ausgleich
  /// die Differenz trägt.
  RechenRezeptur mitFaktor(double faktor) {
    final mehr = zielKg * (faktor - 1);
    final ausgleichFaktor = (ausgleichKg - mehr) / ausgleichKg;
    return r.kopie(
      positionen: [
        for (var i = 0; i < rollen.length; i++)
          switch (rollen[i]) {
            OptimierRolle.ziel => r.positionen[i].mitMenge(menge(i) * faktor),
            OptimierRolle.ausgleich =>
              r.positionen[i].mitMenge(menge(i) * ausgleichFaktor),
            OptimierRolle.fest => r.positionen[i],
          },
      ],
    );
  }

  // Mehr Fleisch als Fleisch plus Ausgleich geht nicht.
  final maxFaktor = (zielKg + ausgleichKg) / zielKg;
  final unten = fleischWert(mitFaktor(0), mass);
  final oben = fleischWert(mitFaktor(maxFaktor), mass);
  if (zielProzent >= oben) {
    final neu = mitFaktor(maxFaktor);
    return ergebnis(
      neu,
      oben,
      zielProzent - oben < 0.01
          ? null
          : 'Mehr als ${_p(oben)} geht nur, wenn noch etwas anderes '
              'weniger wird — der ganze Ausgleich ist schon Fleisch.',
    );
  }
  if (zielProzent <= unten) {
    final neu = mitFaktor(0);
    return ergebnis(
      neu,
      unten,
      unten - zielProzent < 0.01
          ? null
          : 'Weniger als ${_p(unten)} geht nur ohne die Zeilen mit der '
              'Rolle „Fleisch".',
    );
  }

  // Der Anteil wächst mit dem Faktor — halbieren, bis er sitzt.
  var a = 0.0;
  var b = maxFaktor;
  for (var schritt = 0; schritt < 60; schritt++) {
    final mitte = (a + b) / 2;
    if (fleischWert(mitFaktor(mitte), mass) < zielProzent) {
      a = mitte;
    } else {
      b = mitte;
    }
    if (b - a < 1e-9) break;
  }
  final faktor = (a + b) / 2;
  final neu = mitFaktor(faktor);
  return ergebnis(neu, fleischWert(neu, mass));
}

String _p(double prozent) => '${Format.zahl(prozent, nachkomma: 1)} %';
