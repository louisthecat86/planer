import '../../../core/utils/format.dart';
import 'rechen_modell.dart';

// Gerundete Nährwerte für das Etikett — nach dem Leitfaden der
// EU-Kommission zu Toleranzen und Rundung (Dezember 2012):
//
//   Energie                         auf ganze kJ bzw. kcal
//   Fett, Kohlenhydrate, Zucker,    ab 10 g auf 1 g, darunter auf 0,1 g,
//   Eiweiß                          bis 0,5 g „< 0,5 g"
//   gesättigte Fettsäuren           ab 10 g auf 1 g, darunter auf 0,1 g,
//                                   bis 0,1 g „< 0,1 g"
//   Salz                            ab 1 g auf 0,1 g, darunter auf 0,01 g,
//                                   bis 0,0125 g „< 0,01 g"

/// Die Nährstoffe der Nährwerttabelle, in ihrer Reihenfolge.
enum Naehrstoff {
  energieKj('Energie', 'kJ'),
  energieKcal('Energie', 'kcal'),
  fett('Fett', 'g'),
  gesaettigteFettsaeuren('davon gesättigte Fettsäuren', 'g'),
  kohlenhydrate('Kohlenhydrate', 'g'),
  zucker('davon Zucker', 'g'),
  eiweiss('Eiweiß', 'g'),
  salz('Salz', 'g');

  const Naehrstoff(this.label, this.einheit);

  final String label;
  final String einheit;
}

/// Der ungerundete Wert eines Nährstoffs je 100 g.
double? naehrstoffWert(Naehrwerte n, Naehrstoff stoff) => switch (stoff) {
      Naehrstoff.energieKj => n.energieKj,
      Naehrstoff.energieKcal => n.energieKcal,
      Naehrstoff.fett => n.fett,
      Naehrstoff.gesaettigteFettsaeuren => n.gesaettigteFettsaeuren,
      Naehrstoff.kohlenhydrate => n.kohlenhydrate,
      Naehrstoff.zucker => n.zucker,
      Naehrstoff.eiweiss => n.eiweiss,
      Naehrstoff.salz => n.salz,
    };

/// Der gerundete Wert ohne Einheit, etwa „12", „3,4" oder „< 0,5".
/// „—" für einen unbekannten Wert.
String naehrwertGerundet(Naehrstoff stoff, double? wert) {
  if (wert == null || !wert.isFinite) return '—';
  final w = wert < 0 ? 0.0 : wert;
  switch (stoff) {
    case Naehrstoff.energieKj:
    case Naehrstoff.energieKcal:
      return '${w.round()}';
    case Naehrstoff.fett:
    case Naehrstoff.kohlenhydrate:
    case Naehrstoff.zucker:
    case Naehrstoff.eiweiss:
      return _gestuft(w, unter: 0.5, unterText: '< 0,5');
    case Naehrstoff.gesaettigteFettsaeuren:
      return _gestuft(w, unter: 0.1, unterText: '< 0,1');
    case Naehrstoff.salz:
      if (w <= 0.0125) return '< 0,01';
      // Unter 1 g auf Hundertstel — erst wenn das 1,00 ergibt, gilt die
      // Stufe darüber (0,96 bleibt „0,96", 0,996 wird „1,0").
      final hundertstel = (w * 100).round() / 100;
      if (w >= 1 || hundertstel >= 1) {
        return Format.zahl((w * 10).round() / 10, nachkomma: 1);
      }
      return Format.zahl(hundertstel, nachkomma: 2);
  }
}

/// Ab 10 ganze Gramm, darunter Zehntel, bis [unter] der [unterText].
String _gestuft(double w, {required double unter, required String unterText}) {
  if (w <= unter) return unterText;
  final zehntel = (w * 10).round() / 10;
  if (w >= 10 || zehntel >= 10) return '${w.round()}';
  return Format.zahl(zehntel, nachkomma: 1);
}
