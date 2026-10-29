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
  });

  final ProductionTask task;
  final String artikelName;
  final String artikelNummer;

  /// Die Menge, die die Übersicht zeigt: die geplante Fertigware, ohne sie
  /// die Rohware.
  double get mengeKg => task.fertigMengeKg ?? task.mengeKg;
}
