// Losgröße: die Rezeptur auf eine gewünschte Gesamtmenge umrechnen.
//
// Die Losgröße ist die Summe aller Zeilen — das, was eingewogen wird.
// Umrechnen heißt: jede Zeile im selben Verhältnis größer oder kleiner,
// sodass die Anteile bleiben und die Summe die gewünschte Menge trifft.

/// Auf so viele Stellen hinter dem Komma stehen die Mengen (Gramm).
const int kMengenStellen = 3;

double _aufGramm(double kg) => (kg * 1000).roundToDouble() / 1000;

/// Rechnet die [mengen] (kg) so um, dass ihre Summe [zielKg] ergibt —
/// jede im selben Verhältnis, aufs Gramm gerundet.
///
/// Was beim Runden an Gramm übrig bleibt, bekommt die größte Zeile: So
/// stimmt die Summe genau, und der Fehler fällt dort am wenigsten ins
/// Gewicht. Zeilen mit 0 kg bleiben bei 0.
///
/// Wirft [ArgumentError], wenn es nichts umzurechnen gibt (Summe 0) oder
/// [zielKg] keine Menge über 0 ist.
List<double> aufLosgroesse(List<double> mengen, double zielKg) {
  if (!zielKg.isFinite || zielKg <= 0) {
    throw ArgumentError('Die Losgröße muss größer als 0 sein.');
  }
  final summe = mengen.fold<double>(0, (s, m) => s + m);
  if (!summe.isFinite || summe <= 0) {
    throw ArgumentError(
      'Die Rezeptur hat noch keine Mengen — erst wenn Zeilen Mengen '
      'tragen, lässt sie sich umrechnen.',
    );
  }
  final ziel = _aufGramm(zielKg);
  final faktor = ziel / summe;
  final neu = [for (final m in mengen) _aufGramm(m * faktor)];

  // In ganzen Gramm rechnen, damit beim Rest nichts verrutscht.
  final rest = (ziel * 1000).round() -
      neu.fold<int>(0, (s, m) => s + (m * 1000).round());
  if (rest != 0) {
    var groesste = 0;
    for (var i = 1; i < neu.length; i++) {
      if (neu[i] > neu[groesste]) groesste = i;
    }
    neu[groesste] = ((neu[groesste] * 1000).round() + rest) / 1000;
  }
  return neu;
}
