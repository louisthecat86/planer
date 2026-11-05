import '../../core/database/database.dart';

/// Eine geplante Produktion (Ketten-Wurzel) für die Erfassung — in der
/// Übersicht der Woche und auf der Erfassungsliste zum Drucken.
///
/// Bewusst ohne Flutter-Abhängigkeit: Die Liste zum Drucken entsteht
/// daraus ohne Oberfläche.
class GeplanteProduktion {
  const GeplanteProduktion({
    required this.task,
    required this.artikelName,
    required this.artikelNummer,
    this.rohwareKg,
  });

  final ProductionTask task;
  final String artikelName;
  final String artikelNummer;

  /// Die Rohware der Produktion mit allen Teilen, wenn ihr erster Schritt
  /// auf Tage verteilt ist — null: die Menge der Wurzel.
  final double? rohwareKg;

  /// Die geplante Rohware.
  double get rohKg => rohwareKg ?? task.mengeKg;

  /// Die geplante Fertigware — null, wenn die Produktion ohne sie geplant
  /// wurde (dann steht dort 0).
  double? get fertigKg {
    final f = task.fertigMengeKg;
    return f != null && f > 0 ? f : null;
  }

  /// Die geplante Fleischeinwaage — null, wenn keine geplant ist.
  double? get fleischKg {
    final f = task.fleischMengeKg;
    return f != null && f > 0 ? f : null;
  }

  /// Die Menge, die die Übersicht zeigt: die geplante Fertigware, ohne sie
  /// die Rohware.
  double get mengeKg => fertigKg ?? rohKg;
}
