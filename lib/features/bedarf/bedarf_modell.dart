import '../../core/database/database.dart';
import '../../core/services/auftragsbestand_deckung.dart'
    show kQuelleAuftragsbestand;

// Ein Bedarf, wie die Bedarfsliste und ihr Ausdruck ihn zeigen.
//
// Bewusst ohne Flutter-Abhängigkeit: Der Ausdruck entsteht daraus ohne
// Oberfläche.

/// Ein Bedarf samt berechnetem Fortschritt.
///
/// Die geplante Menge wird NICHT als Zähler geführt, sondern aus den
/// verknüpften Aufträgen summiert. Dadurch kann sie nicht aus dem Tritt
/// geraten: Löscht man eine geplante Produktion, ist der Bedarf sofort
/// wieder offen.
class BedarfInfo {
  const BedarfInfo({
    required this.bedarf,
    required this.artikelName,
    required this.artikelNummer,
    required this.geplantKg,
    required this.produziertKg,
    required this.heute,
  });

  final Demand bedarf;
  final String artikelName;
  final String artikelNummer;

  /// Insgesamt eingeplante Fertigware-Menge (alle verknüpften Aufträge).
  final double geplantKg;

  /// Davon bereits PRODUZIERT: Aufträge, deren Tag in der Vergangenheit
  /// liegt. Eine Produktion, die auf einen vergangenen Tag geplant war und
  /// nicht mehr verschoben wurde, gilt als gelaufen — der Bedarf ist dann
  /// automatisch gedeckt, ohne dass man ihn von Hand abhaken muss.
  final double produziertKg;

  /// Der Kalendertag, gegen den gerechnet wurde — auf 00:00 normiert.
  ///
  /// Wird hereingereicht statt hier aus `DateTime.now()` gezogen: So
  /// rechnen alle Einträge einer Liste gegen denselben Tag, und die Liste
  /// kann sich um Mitternacht gezielt erneuern (siehe heuteProvider in
  /// bedarf_screen.dart).
  final DateTime heute;

  /// Noch nicht eingeplante Menge (für die Planung relevant).
  double get offenKg =>
      (bedarf.mengeKgFertig - geplantKg).clamp(0, double.infinity);

  /// Eingeplant, aber der Produktionstag steht noch aus.
  double get inPlanungKg =>
      (geplantKg - produziertKg).clamp(0, double.infinity);

  /// Erledigt, wenn manuell abgehakt ODER die produzierte Menge den Bedarf
  /// deckt (Produktionstag liegt in der Vergangenheit).
  bool get erledigt =>
      bedarf.manuellErledigt ||
      produziertKg >= bedarf.mengeKgFertig - 0.5;

  /// Fortschritt am eingeplanten Anteil (zeigt auch die noch offene Planung).
  double get fortschritt => bedarf.mengeKgFertig > 0
      ? (geplantKg / bedarf.mengeKgFertig).clamp(0.0, 1.0)
      : 0.0;

  /// Anteil, der bereits produziert ist (für die zweifarbige Leiste).
  double get produziertAnteil => bedarf.mengeKgFertig > 0
      ? (produziertKg / bedarf.mengeKgFertig).clamp(0.0, 1.0)
      : 0.0;

  /// Termin überschritten und noch nicht gedeckt?
  bool get ueberfaellig {
    final t = bedarf.termin;
    if (t == null || erledigt) return false;
    return t.isBefore(heute);
  }
}

/// Woher ein Bedarf kommt, in Worten: „Bestellung", „Bestand",
/// „Sonstiges", „Auftragsbestand" — Unbekanntes, wie es gespeichert ist.
String bedarfQuelleText(String quelle) => switch (quelle) {
      'bestellung' => 'Bestellung',
      'bestand' => 'Bestand',
      'sonstiges' => 'Sonstiges',
      kQuelleAuftragsbestand => 'Auftragsbestand',
      _ => quelle,
    };
